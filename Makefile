# Thin task-runner over Scripts/ and the standard Swift/Xcode tooling.
# Logic lives in Scripts/*.sh (reusable by CI); this file is the command index.

.DEFAULT_GOAL := help

.PHONY: help bootstrap test bench-remote restic build dmg release install update dev-site deploy-site clean

help: ## List available targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  make %-12s %s\n", $$1, $$2}'

bootstrap: ## Install development dependencies via Homebrew
	brew install restic xcodegen gh

test: ## Run KeelhavenCore tests (incl. the real-restic integration suite)
	swift test --package-path KeelhavenCore

bench-remote: ## Measure restic ls latency against S3/SFTP at injected round trips
	./Scripts/bench-remote-ls.sh

restic: ## Vendor the universal restic binary that gets bundled into the app
	./Scripts/fetch-restic.sh

build: restic ## Build a Release Keelhaven.app from the working tree
	xcodegen generate
	xcodebuild -project Keelhaven.xcodeproj -scheme Keelhaven \
		-configuration Release -derivedDataPath build build

dmg: build ## Package the Release build into Keelhaven.dmg (ad-hoc signed locally)
	./Scripts/make-dmg.sh

release: ## Cut a public release from this Mac: tests, universal DMG, GitHub Release, site mirror (make release VERSION=0.2.0)
	./Scripts/release-local.sh $(VERSION)

install: build ## Build from source and install to /Applications
	./Scripts/install-local.sh

update: ## Install the latest build of main from CI (builds on demand, no local toolchain)
	./Scripts/install-latest.sh

dev-site: ## Preview the website locally with live reload (http://localhost:5173/)
	@[ -d site/node_modules ] || npm --prefix site install --ignore-scripts
	npm --prefix site run dev

deploy-site: ## Build site/ and push it to keelhaven-site's gh-pages (manual deploy)
	./Scripts/deploy-site.sh

clean: ## Remove generated project and build products
	rm -rf Keelhaven.xcodeproj build .build KeelhavenCore/.build
