#!/usr/bin/env bash
# Export the browser build into docs/ (served by GitHub Pages).
# Usage:  tools/export_web.sh [path-to-godot-4.3-console-exe]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${1:-${GODOT:-/c/Users/sessa/GameDev/Godot_v4.3-stable_win64.exe/Godot_v4.3-stable_win64_console.exe}}"
mkdir -p docs
find docs -mindepth 1 ! -name '.gdignore' ! -name '.nojekyll' -delete
touch docs/.gdignore docs/.nojekyll
"$GODOT" --headless --path . --export-release "Web" docs/index.html
echo "Exported to docs/:"; ls -la docs
