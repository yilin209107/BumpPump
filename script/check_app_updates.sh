#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
SDK_PATH="${FITNESS_APP_SDK:-$(xcrun --show-sdk-path)}"
if [[ -z "${FITNESS_APP_SDK:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi
mkdir -p work/update-checks
swiftc -swift-version 5 -parse-as-library -sdk "$SDK_PATH" -target "$(uname -m)-apple-macos14.0" Sources/BumpPump/Services/AppReleaseChecker.swift Tests/BumpPumpChecks/UpdateChecks.swift -o work/update-checks/checks
work/update-checks/checks "$ROOT_DIR/work/update-checks/report.json"
