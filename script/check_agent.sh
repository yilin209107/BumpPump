#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK_PATH="${FITNESS_APP_SDK:-$(xcrun --show-sdk-path)}"
if [[ -z "${FITNESS_APP_SDK:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi
mkdir -p work/agent-checks
swiftc -I Sources/CSQLite -lsqlite3 -swift-version 5 -parse-as-library -sdk "$SDK_PATH" -target "$(uname -m)-apple-macos14.0" \
  Sources/BumpPump/Home/Models/*.swift \
  Sources/BumpPump/Models/SetupState.swift \
  Sources/BumpPump/Support/SetupTheme.swift \
  Sources/BumpPump/Support/AppGlass.swift \
  Sources/BumpPump/Services/APIConnectionTester.swift \
  Sources/BumpPump/Services/LocalAPIKeyStore.swift \
  Sources/BumpPump/Agent/AgentTypes.swift \
  Sources/BumpPump/Agent/AgentStreaming.swift \
  Sources/BumpPump/Agent/AppRecordDatabase.swift \
  Sources/BumpPump/Agent/AgentDataTools.swift \
  Sources/BumpPump/Agent/AgentAttachments.swift \
  Sources/BumpPump/Agent/FitnessAgentState.swift \
  Tests/BumpPumpChecks/AgentChecks.swift \
  -o work/agent-checks/checks
work/agent-checks/checks
