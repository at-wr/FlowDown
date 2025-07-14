#!/bin/zsh

cd "$(dirname "$0")"

while [[ ! -d .git ]] && [[ "$(pwd)" != "/" ]]; do
    cd ..
done

if [[ -d .git ]] && [[ -d FlowDown.xcworkspace ]]; then
    echo "[*] found project root: $(pwd)"
else
    echo "[!] could not find project root"
    exit 1
fi

PROJECT_ROOT=$(pwd)

if [[ -n $(git status --porcelain) ]]; then
    echo "[!] git is not clean"
    exit 1
fi

./Resources/DevKit/scripts/bump.version.sh
git add -A
git commit -m "Archive Commit $(date)"

./Resources/DevKit/scripts/scan.license.sh

xcodebuild -workspace FlowDown.xcworkspace \
    -scheme FlowDown \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$PROJECT_ROOT/.build/FlowDown.xcarchive" \
    archive | xcbeautify

echo "[*] registering FlowDown.xcarchive in Xcode Organizer..."
open "$PROJECT_ROOT/.build/FlowDown.xcarchive" -g

xcodebuild -workspace FlowDown.xcworkspace \
    -scheme FlowDown-Catalyst \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$PROJECT_ROOT/.build/FlowDown-Catalyst.xcarchive" \
    archive | xcbeautify

echo "[*] registering FlowDown-Catalyst.xcarchive in Xcode Organizer..."
open "$PROJECT_ROOT/.build/FlowDown-Catalyst.xcarchive" -g

echo "[*] done"

osascript -e 'display notification "FlowDown has completed archive process." with title "Build Success"'
