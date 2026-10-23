#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
SDK_PATH="${FITNESS_APP_SDK:-$(xcrun --show-sdk-path)}"
if [[ -z "${FITNESS_APP_SDK:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi
mkdir -p work/onboarding-connection
swiftc -swift-version 5 -parse-as-library -sdk "$SDK_PATH" -target "$(uname -m)-apple-macos14.0" \
  Sources/BumpPump/Models/SetupState.swift \
  Sources/BumpPump/Support/SetupTheme.swift \
  Sources/BumpPump/Support/AppGlass.swift \
  Sources/BumpPump/Services/LocalAPIKeyStore.swift \
  Sources/BumpPump/Services/APIConnectionTester.swift \
  Tests/BumpPumpChecks/ConnectionChecks.swift \
  -o work/onboarding-connection/checks
work/onboarding-connection/checks "$ROOT_DIR/work/onboarding-connection/report.json"
