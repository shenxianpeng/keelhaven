import Foundation

/// Reads a child process's stdout and stderr without either one being able to
/// hold up the other.
///
/// `FileHandle.bytes` looks like the tool for this and is the wrong one for
/// two pipes. Every `FileHandle.AsyncBytes` in a process takes its turn on a
/// single shared actor, and a turn is a blocking `read`. restic says nothing
/// on stderr while it works, so the read waiting there keeps the actor — and
/// stdout, queued behind it, is never read again. Its pipe holds 64 KB; once
/// that is full restic blocks on its next write and never exits, which is the
/// one thing that would have ended the stderr read.
///
/// Measured with restic 0.19.1 through the old path: a backup throttled to
/// take 58 seconds printed 81 KB of progress, delivered one event, and was
/// still sitting there after 150. Anything that outgrew the pipe did the same
/// — a long backup, a snapshot list a few months deep — and so, the other way
/// round, did a run that complained at length on stderr.
///
/// So each pipe gets a thread of its own, parked in an ordinary blocking read
/// that nothing else waits behind.
enum PipeReader {
    /// The pipe's bytes, in the pieces they arrive in, until it closes.
    static func chunks(of handle: FileHandle) -> AsyncStream<Data> {
        AsyncStream { continuation in
            DispatchQueue(label: "app.keelhaven.pipe-reader").async {
                // `availableData` waits for something to read and comes back
                // empty only once the writing end has closed.
                var chunk = handle.availableData
                while !chunk.isEmpty {
                    continuation.yield(chunk)
                    chunk = handle.availableData
                }
                continuation.finish()
            }
        }
    }

    /// The pipe's output a line at a time, each as soon as it is complete.
    static func lines(of handle: FileHandle) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                var buffer = LineBuffer()
                for await chunk in chunks(of: handle) {
                    for line in buffer.append(chunk) { continuation.yield(line) }
                }
                for line in buffer.finish() { continuation.yield(line) }
                continuation.finish()
            }
        }
    }

    /// Everything the pipe ever says, once it has closed.
    static func collect(_ handle: FileHandle) async -> Data {
        var data = Data()
        for await chunk in chunks(of: handle) {
            data.append(chunk)
        }
        return data
    }
}

/// Cuts a byte stream into lines as it arrives in pieces.
///
/// A pipe hands over whatever has been written so far, and that ends wherever
/// it ends: halfway through a line, or halfway through a character. Bytes are
/// held back until their newline turns up, so a line is only ever decoded
/// whole — and because a newline byte cannot occur inside a multi-byte UTF-8
/// sequence, no character is ever cut in two either.
struct LineBuffer {
    private var pending = Data()

    /// Adds a piece and returns every line it completed, newlines removed.
    mutating func append(_ chunk: Data) -> [String] {
        var lines: [String] = []
        var start = chunk.startIndex
        while let newline = chunk[start...].firstIndex(of: 0x0A) {
            pending.append(chunk[start..<newline])
            lines.append(String(decoding: pending, as: UTF8.self))
            pending.removeAll(keepingCapacity: true)
            start = chunk.index(after: newline)
        }
        pending.append(chunk[start...])
        return lines
    }

    /// What is left when the stream ends: a last line nobody terminated, or
    /// nothing.
    mutating func finish() -> [String] {
        guard !pending.isEmpty else { return [] }
        defer { pending.removeAll() }
        return [String(decoding: pending, as: UTF8.self)]
    }
}
