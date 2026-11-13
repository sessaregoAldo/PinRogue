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
# Browsers (phones especially) keep serving an old index.pck from their cache
# after an update. Ask for it under a per-build address so a new build is
# always downloaded. The engine (index.wasm) is left cacheable: it only changes
# with the Godot version.
STAMP="$(date -u +"%Y%m%d%H%M%S")"
BUST="<script>(function(){var f=window.fetch;window.fetch=function(u,o){if(typeof u==='string'){if(u.slice(-4)==='.pck'){u+='?v=${STAMP}';}}return f.call(this,u,o);};})();</script>"
sed -i "s|<script src=\"index.js\"></script>|${BUST}<script src=\"index.js?v=${STAMP}\"></script>|" docs/index.html
grep -q "v=${STAMP}" docs/index.html || { echo "cache-busting line was not added to docs/index.html"; exit 1; }
echo "Exported to docs/ (build $(sed -n 's/^time="\(.*\)"$/\1/p' build_info.cfg)):"; ls -la docs
