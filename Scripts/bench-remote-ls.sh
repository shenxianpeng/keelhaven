#!/bin/bash
# Measures how long `restic ls` takes against remote backends at realistic
# round-trip times — the numbers that decide how snapshot browsing must be
# built.
#
# Why this exists: on loopback, S3 and SFTP look identical to a local disk
# (~0.8s either way), so a laptop benchmark says nothing about a user whose
# repository lives in a cloud bucket or on a NAS across a VPN. This script
# puts a real backend behind Scripts/netdelay.py, which holds every byte for
# half the round trip in each direction, and measures through it.
#
# Everything runs unprivileged and self-contained: MinIO is downloaded if
# absent, sshd is a throwaway instance on a high port with its own host key
# (your system Remote Login setting is never touched), and all state lives in
# a temp directory that is removed on exit.
#
# Re-run it when:
#   - bumping the pinned restic version (its backend behaviour can change)
#   - changing how snapshot browsing calls restic
#   - considering any design that calls restic more than once per user action
#
# Usage: bench-remote-ls.sh
# Env:
#   BENCH_FILES=15000        files in the synthetic dataset
#   BENCH_RTTS="0 20 60"     round trips to measure, in milliseconds
#   BENCH_BACKENDS="s3 sftp" which backends to run
#   BENCH_NO_CACHE=1         also measure with restic's cache disabled
#                            (slow — minutes — but shows what cache is worth)
set -euo pipefail

FILES="${BENCH_FILES:-15000}"
RTTS="${BENCH_RTTS:-0 20 60}"
BACKENDS="${BENCH_BACKENDS:-s3 sftp}"
NO_CACHE="${BENCH_NO_CACHE:-0}"

# High ports, away from anything a dev machine is likely to be running.
MINIO_PORT=9400
SSHD_PORT=2400
# Each RTT gets its own proxy: MinIO at 94xx, sshd at 24xx.
proxy_port() { # backend, index
    if [ "$1" = s3 ]; then echo $((9410 + $2)); else echo $((2410 + $2)); fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
PIDS=()

cleanup() {
    for pid in ${PIDS+"${PIDS[@]}"}; do kill "$pid" 2>/dev/null || true; done
    wait 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

say() { printf '\033[1m%s\033[0m\n' "$*"; }
now() { python3 -c 'import time; print(time.time())'; }
elapsed() { python3 -c "print(f'{($2-$1):6.2f}')"; }

command -v restic >/dev/null || { echo "restic not found — brew install restic" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found" >&2; exit 1; }

# ---------------------------------------------------------------- dataset

say "Building a ${FILES}-file dataset"
python3 - "$WORK/src" "$FILES" <<'PY'
import os, sys
root, count = sys.argv[1], int(sys.argv[2])
# Fan out over nested directories so the tree has real depth, the way a
# Documents or source folder does — a flat directory would understate the
# number of tree objects restic has to walk.
for i in range(count):
    d = os.path.join(root, f"dir{i // 100:03d}", f"sub{i // 10 % 10}")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, f"file{i:05d}.txt"), "w") as f:
        f.write(f"keelhaven benchmark payload {i}\n" * 8)
PY

# ---------------------------------------------------------------- backends

start_minio() {
    local minio_bin
    if command -v minio >/dev/null; then
        minio_bin="$(command -v minio)"
    else
        say "Downloading MinIO"
        local arch os
        arch="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')"
        os="$(uname -s | tr '[:upper:]' '[:lower:]')"
        curl --proto "=https" -fsSL -o "$WORK/minio" "https://dl.min.io/server/minio/release/${os}-${arch}/minio"
        chmod +x "$WORK/minio"
        minio_bin="$WORK/minio"
    fi
    MINIO_ROOT_USER=keelhaven-bench MINIO_ROOT_PASSWORD=keelhaven-bench-secret \
        "$minio_bin" server --address "127.0.0.1:$MINIO_PORT" "$WORK/minio-data" \
        >"$WORK/minio.log" 2>&1 &
    PIDS+=($!)
    for _ in $(seq 1 40); do
        curl -sf "http://127.0.0.1:$MINIO_PORT/minio/health/live" >/dev/null && return 0
        sleep 0.5
    done
    echo "MinIO did not become healthy; log:" >&2; cat "$WORK/minio.log" >&2; exit 1
}

start_sshd() {
    # A throwaway sshd owned by the current user. No sudo, and the system's
    # Remote Login setting is left exactly as it was — sshd only needs root
    # when it has to switch users, and here it never does.
    local d="$WORK/sshd" sftp_server=""
    # Path differs by distribution; macOS and the common Linux layouts.
    for candidate in /usr/libexec/sftp-server \
                     /usr/lib/openssh/sftp-server \
                     /usr/lib/ssh/sftp-server; do
        [ -x "$candidate" ] && { sftp_server="$candidate"; break; }
    done
    [ -n "$sftp_server" ] || { echo "no sftp-server binary found" >&2; exit 1; }
    mkdir -p "$d"; chmod 700 "$d"
    ssh-keygen -q -t ed25519 -f "$d/host_key" -N "" -C bench-host
    ssh-keygen -q -t ed25519 -f "$d/id_bench" -N "" -C bench-client
    cp "$d/id_bench.pub" "$d/authorized_keys"
    chmod 600 "$d/host_key" "$d/id_bench" "$d/authorized_keys"
    cat >"$d/sshd_config" <<EOF
Port $SSHD_PORT
ListenAddress 127.0.0.1
HostKey $d/host_key
AuthorizedKeysFile $d/authorized_keys
PidFile $d/sshd.pid
UsePAM no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
StrictModes no
Subsystem sftp $sftp_server
EOF
    /usr/sbin/sshd -f "$d/sshd_config" -D -e >"$d/sshd.log" 2>&1 &
    PIDS+=($!)
    for _ in $(seq 1 40); do
        ssh_bench "$SSHD_PORT" true 2>/dev/null && return 0
        sleep 0.5
    done
    echo "sshd did not come up; log:" >&2; cat "$d/sshd.log" >&2; exit 1
}

SSH_COMMON=(-o BatchMode=yes -o StrictHostKeyChecking=no
            -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
ssh_bench() { # port, then the remote command
    local port="$1"; shift
    ssh "${SSH_COMMON[@]}" -i "$WORK/sshd/id_bench" -p "$port" 127.0.0.1 "$@"
}
sftp_args() { echo "-p $1 -i $WORK/sshd/id_bench ${SSH_COMMON[*]}"; }

# restic invocation for a backend at a given port.
restic_at() { # backend, port, then restic args
    local backend="$1" port="$2"; shift 2
    if [ "$backend" = s3 ]; then
        AWS_ACCESS_KEY_ID=keelhaven-bench AWS_SECRET_ACCESS_KEY=keelhaven-bench-secret \
        RESTIC_PASSWORD=bench \
            restic -r "s3:http://127.0.0.1:$port/kh-bench/repo" "$@"
    else
        RESTIC_PASSWORD=bench \
            restic -o "sftp.args=$(sftp_args "$port")" \
                   -r "sftp:$(whoami)@127.0.0.1:$WORK/sftp-repo" "$@"
    fi
}

# ---------------------------------------------------------------- setup

for backend in $BACKENDS; do
    case "$backend" in
        s3)   start_minio ;;
        sftp) mkdir -p "$WORK/sftp-repo"; start_sshd ;;
        *)    echo "unknown backend: $backend" >&2; exit 1 ;;
    esac
done

for backend in $BACKENDS; do
    base_port=$([ "$backend" = s3 ] && echo "$MINIO_PORT" || echo "$SSHD_PORT")
    say "Seeding the $backend repository"
    restic_at "$backend" "$base_port" init >/dev/null 2>&1
    restic_at "$backend" "$base_port" backup "$WORK/src" --no-scan >/dev/null 2>&1
done

# One proxy per (backend, rtt). RTT 0 talks to the backend directly, so the
# proxy's own overhead never hides in the baseline.
index=0
for rtt in $RTTS; do
    [ "$rtt" = 0 ] && { index=$((index + 1)); continue; }
    for backend in $BACKENDS; do
        upstream=$([ "$backend" = s3 ] && echo "$MINIO_PORT" || echo "$SSHD_PORT")
        python3 "$SCRIPT_DIR/netdelay.py" "$(proxy_port "$backend" "$index")" "$upstream" "$rtt" \
            >/dev/null 2>&1 &
        PIDS+=($!)
    done
    index=$((index + 1))
done
sleep 1

# ---------------------------------------------------------------- measure

CACHE="$WORK/cache"
DEEP="$WORK/src/dir000/sub0"

printf '\n'
say "restic ls — ${FILES} files, times in seconds"
printf '%-16s %10s %10s %10s %10s\n' "backend · rtt" "full/cold" "full/warm" "one-level" "connect"
printf '%s\n' "--------------------------------------------------------------"

for backend in $BACKENDS; do
    index=0
    for rtt in $RTTS; do
        if [ "$rtt" = 0 ]; then
            port=$([ "$backend" = s3 ] && echo "$MINIO_PORT" || echo "$SSHD_PORT")
        else
            port="$(proxy_port "$backend" "$index")"
        fi
        index=$((index + 1))

        snap="$(restic_at "$backend" "$port" snapshots --json --no-lock --cache-dir "$CACHE" 2>/dev/null \
                | python3 -c 'import json,sys; print(json.load(sys.stdin)[-1]["id"])')"

        rm -rf "$CACHE"
        t0="$(now)"; restic_at "$backend" "$port" ls --json "$snap" --recursive --no-lock --cache-dir "$CACHE" >/dev/null 2>&1; t1="$(now)"
        cold="$(elapsed "$t0" "$t1")"

        t0="$(now)"; restic_at "$backend" "$port" ls --json "$snap" --recursive --no-lock --cache-dir "$CACHE" >/dev/null 2>&1; t1="$(now)"
        warm="$(elapsed "$t0" "$t1")"

        t0="$(now)"; restic_at "$backend" "$port" ls --json "$snap" "$DEEP" --no-lock --cache-dir "$CACHE" >/dev/null 2>&1; t1="$(now)"
        one="$(elapsed "$t0" "$t1")"

        # `snapshots` is the cheapest repository operation there is, so its
        # time is essentially the cost of connecting and opening the
        # repository — the price every extra restic invocation pays.
        t0="$(now)"; restic_at "$backend" "$port" snapshots --no-lock --cache-dir "$CACHE" >/dev/null 2>&1; t1="$(now)"
        connect="$(elapsed "$t0" "$t1")"

        printf '%-16s %10s %10s %10s %10s\n' "$backend · ${rtt}ms" "$cold" "$warm" "$one" "$connect"
    done
done

if [ "$NO_CACHE" = 1 ]; then
    printf '\n'
    say "With restic's cache disabled (--no-cache)"
    printf '%-16s %10s\n' "backend · rtt" "full"
    printf '%s\n' "---------------------------"
    for backend in $BACKENDS; do
        index=0
        for rtt in $RTTS; do
            if [ "$rtt" = 0 ]; then
                port=$([ "$backend" = s3 ] && echo "$MINIO_PORT" || echo "$SSHD_PORT")
            else
                port="$(proxy_port "$backend" "$index")"
            fi
            index=$((index + 1))
            snap="$(restic_at "$backend" "$port" snapshots --json --no-lock --cache-dir "$CACHE" 2>/dev/null \
                    | python3 -c 'import json,sys; print(json.load(sys.stdin)[-1]["id"])')"
            t0="$(now)"; restic_at "$backend" "$port" ls --json "$snap" --recursive --no-lock --no-cache >/dev/null 2>&1; t1="$(now)"
            printf '%-16s %10s\n' "$backend · ${rtt}ms" "$(elapsed "$t0" "$t1")"
        done
    done
fi

printf '\n'
say "Done. Servers stopped and temp data removed on exit."
