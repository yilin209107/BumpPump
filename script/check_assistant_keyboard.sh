#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK_PATH="${FITNESS_APP_SDK:-$(xcrun --show-sdk-path)}"
if [[ -z "${FITNESS_APP_SDK:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi
mkdir -p work/assistant-keyboard-checks
swiftc -swift-version 5 -parse-as-library -sdk "$SDK_PATH" -target "$(uname -m)-apple-macos14.0" \
  Sources/BumpPump/Agent/AssistantMessageEditor.swift \
  Tests/BumpPumpChecks/AssistantKeyboardChecks.swift \
  -o work/assistant-keyboard-checks/checks
work/assistant-keyboard-checks/checks
