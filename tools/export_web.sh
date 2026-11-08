#!/usr/bin/env bash
# Export the browser build into docs/ (served by GitHub Pages).
# Usage:  tools/export_web.sh [path-to-godot-4.3-console-exe]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${1:-${GODOT:-/c/Users/sessa/GameDev/Godot_v4.3-stable_win64.exe/Godot_v4.3-stable_win64_console.exe}}"
mkdir -p docs
find docs -mindepth 1 ! -name '.gdignore' ! -name '.nojekyll' -delete
touch docs/.gdignore docs/.nojekyll
# Stamp the build time; the in-game version tag (scripts/version_tag.gd) shows it,
# so after a push you can confirm the live site is running this build.
{
	echo "[build]"
	echo "time=\"$(date -u +"%Y-%m-%d %H:%M UTC")\""
} > build_info.cfg
"$GODOT" --headless --path . --export-release "Web" docs/index.html
echo "Exported to docs/ (build $(sed -n 's/^time="\(.*\)"$/\1/p' build_info.cfg)):"; ls -la docs
