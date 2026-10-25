#!/bin/zsh
set -eu
cd "$(dirname "$0")"
mkdir -p Build
xcrun swiftc -swift-version 5 Source/Logic.swift Source/TestLogic.swift -o Build/test-logic
Build/test-logic
# Legacy numeric OCR is retained as a standalone regression utility.
xcrun swiftc -swift-version 5 -framework AppKit -framework Vision   Source/Logic.swift Source/NumericOCR.swift Source/TestNumeric.swift -o Build/test-numeric
Build/test-numeric
