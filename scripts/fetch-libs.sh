#!/usr/bin/env bash
# Downloads the Ace3 libraries Sprout embeds into libs/ for local development.
#
# libs/ is gitignored: at release time the BigWigs packager pulls the same
# libraries from the externals listed in .pkgmeta. This script exists so a
# fresh clone can be symlinked into the WoW AddOns folder and just work.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIBS_DIR="$REPO_ROOT/libs"
WORK_DIR="$(mktemp -d)"
ACE3_MIRROR="https://github.com/WoWUIDev/Ace3.git"

LIBRARIES=(
  LibStub
  CallbackHandler-1.0
  AceAddon-3.0
  AceEvent-3.0
  AceTimer-3.0
  AceDB-3.0
  AceComm-3.0
  AceConsole-3.0
  AceGUI-3.0
  AceConfig-3.0
)

trap 'rm -rf "$WORK_DIR"' EXIT

echo "Cloning Ace3 mirror..."
git clone --quiet --depth 1 "$ACE3_MIRROR" "$WORK_DIR/Ace3"

mkdir -p "$LIBS_DIR"

for library in "${LIBRARIES[@]}"; do
  rm -rf "${LIBS_DIR:?}/$library"
  cp -R "$WORK_DIR/Ace3/$library" "$LIBS_DIR/$library"
  echo "  vendored $library"
done

# Minimap button libraries (not part of Ace3).
echo "Fetching LibDataBroker-1.1..."
git clone --quiet --depth 1 https://github.com/tekkub/libdatabroker-1-1.git "$WORK_DIR/ldb"
rm -rf "$LIBS_DIR/LibDataBroker-1.1"
mkdir -p "$LIBS_DIR/LibDataBroker-1.1"
cp "$WORK_DIR/ldb/LibDataBroker-1.1.lua" "$LIBS_DIR/LibDataBroker-1.1/"
echo "  vendored LibDataBroker-1.1"

echo "Fetching LibDBIcon-1.0..."
LIBDBICON_URL="https://repos.wowace.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0"
rm -rf "$LIBS_DIR/LibDBIcon-1.0"
mkdir -p "$LIBS_DIR/LibDBIcon-1.0"
curl -sSf "$LIBDBICON_URL/LibDBIcon-1.0.lua" -o "$LIBS_DIR/LibDBIcon-1.0/LibDBIcon-1.0.lua"
curl -sSf "$LIBDBICON_URL/lib.xml" -o "$LIBS_DIR/LibDBIcon-1.0/lib.xml"
echo "  vendored LibDBIcon-1.0"

echo "Done. Libraries are in $LIBS_DIR"
