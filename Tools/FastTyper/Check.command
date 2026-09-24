#!/bin/bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="$(mktemp -d /tmp/fast-typer-check.XXXXXX)"
FAST_TYPER_BUILD_DIR="$build_dir" "$source_dir/Launch.command" --build-only
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$build_dir/ModuleCache" \
    "$source_dir/ClipboardLease.swift" "$source_dir/ClipboardChecks.swift" -o "$build_dir/ClipboardChecks"
"$build_dir/ClipboardChecks"
bash -n "$source_dir/Launch.command"
plutil -lint "$source_dir/Info.plist"
codesign --verify --deep --strict "$build_dir/Fast Typer.app"
