#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
SDK_PATH="${FITNESS_APP_SDK:-$(xcrun --show-sdk-path)}"
if [[ -z "${FITNESS_APP_SDK:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi
mkdir -p work/home-checks
swiftc -I Sources/CSQLite -lsqlite3 -swift-version 5 -parse-as-library -sdk "$SDK_PATH" -target "$(uname -m)-apple-macos13.0" \
  Sources/BumpPump/Home/Models/HomeTraining.swift \
  Sources/BumpPump/Home/Models/StrengthSeries.swift \
  Sources/BumpPump/Home/Models/HomeDemoData.swift \
  Sources/BumpPump/Home/Models/HomeState.swift \
  Sources/BumpPump/Home/Models/HomePackagedFood.swift \
  Sources/BumpPump/Home/Models/HomeDemoEntries.swift \
  Sources/BumpPump/Home/Models/HomeLocalRecord.swift \
  Sources/BumpPump/Home/Models/HomeRecordBackup.swift \
  Sources/BumpPump/Home/Models/HomeEntryDraft.swift \
  Sources/BumpPump/Home/Support/HomeFluidPhysics.swift \
  Sources/BumpPump/Agent/AppRecordDatabase.swift \
  Tests/BumpPumpChecks/HomeDataChecks.swift \
  -o work/home-checks/checks
work/home-checks/checks "$ROOT_DIR/work/home-checks/report.json"
