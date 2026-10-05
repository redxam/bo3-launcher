#!/bin/bash
set -e
cd "$(dirname "$0")"

command -v xcodegen >/dev/null 2>&1 || { echo "Install xcodegen: brew install xcodegen"; exit 1; }

xcodegen generate --quiet
xcodebuild -project BO3Launcher.xcodeproj \
  -scheme BO3Launcher \
  -configuration Debug \
  -derivedDataPath build \
  build 2>&1 | tail -5

APP="build/Build/Products/Debug/BO3 Launcher.app"
if [ -d "$APP" ]; then
  echo "✅ Build succeeded"
  open "$APP"
else
  echo "❌ Build failed"
  exit 1
fi
