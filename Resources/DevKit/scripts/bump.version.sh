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

XC_BUILD_NUMBER=$(agvtool what-version -terse 2>&1)
if [[ -z "$XC_BUILD_NUMBER" ]]; then
    echo "[!] could not retrieve build number"
    exit 1
fi
echo "[*] current build number: $XC_BUILD_NUMBER"
NEW_BUILD_NUMBER=$((XC_BUILD_NUMBER + 1))

echo "[*] incrementing build number to: $NEW_BUILD_NUMBER"
agvtool new-version -all "$NEW_BUILD_NUMBER"

echo "[*] done"
