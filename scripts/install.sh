#!/bin/zsh
# Builds the app and installs it into /Applications on this Mac.
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/build-app.sh

pkill -x FinderSucks 2>/dev/null || true
rm -rf "/Applications/Finder Sucks.app"
ditto "build/Finder Sucks.app" "/Applications/Finder Sucks.app"
echo "Installed /Applications/Finder Sucks.app"
