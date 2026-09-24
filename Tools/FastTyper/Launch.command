#!/bin/bash
set -euo pipefail

source_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${FAST_TYPER_BUILD_DIR:-$HOME/Library/Application Support/FastTyper}"
bundle="$build_dir/Fast Typer.app"
binary="$bundle/Contents/MacOS/FastTyper"

if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "Install Apple's Command Line Tools with: xcode-select --install"
    exit 1
fi

if [[ ! -x "$binary" || "$source_dir/FastTyper.swift" -nt "$binary" || "$source_dir/Info.plist" -nt "$binary" ]]; then
    mkdir -p "$bundle/Contents/MacOS"
    cp "$source_dir/Info.plist" "$bundle/Contents/Info.plist"
    xcrun swiftc -swift-version 5 -O -module-cache-path "$build_dir/ModuleCache" "$source_dir/FastTyper.swift" -o "$binary"
    codesign --force --sign - --identifier local.fast-typer "$bundle"
fi

if [[ "${1:-}" != "--build-only" ]]; then
    open "$bundle"
fi
