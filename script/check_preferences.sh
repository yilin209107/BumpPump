#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK_PATH="${FITNESS_APP_SDK:-$(xcrun --show-sdk-path)}"
if [[ -z "${FITNESS_APP_SDK:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi
mkdir -p work/preference-checks
swiftc -swift-version 5 -parse-as-library -sdk "$SDK_PATH" -target "$(uname -m)-apple-macos13.0" \
  Sources/BumpPump/Support/AppPreference.swift \
  Tests/BumpPumpChecks/PreferenceChecks.swift -o work/preference-checks/checks
work/preference-checks/checks
