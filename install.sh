#!/bin/bash
# Copy the app to ~/Applications (the share destination points there) and launch it: first launch registers everything.
set -euo pipefail
cd "$(dirname "$0")"
pkill -x PlugKitExport 2>/dev/null || true
rm -rf "$HOME/Applications/PlugKit Export.app" && mkdir -p "$HOME/Applications"
cp -R "build/PlugKit Export.app" "$HOME/Applications/"
open "$HOME/Applications/PlugKit Export.app"
echo "Installé. Relancez Final Cut Pro : Fenêtre > Extensions > PlugKit Export, et Fichier > Partager > PlugKit."
