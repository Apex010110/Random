#!/usr/bin/env bash
# Build the Flutter web app and publish it to GitHub Pages at
#   https://apex010110.github.io/Random/cartcloser/
# Only the gh-pages "cartcloser/" folder is replaced; other site files are left untouched.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/cartcloser-ai/flutter_app"
BASE="${BASE_HREF:-/Random/cartcloser/}"
WT="$(mktemp -d)"
(cd "$APP" && flutter build web --release --no-web-resources-cdn --base-href "$BASE")
cd "$ROOT"
git fetch origin gh-pages
git worktree add "$WT" origin/gh-pages -B gh-pages
rm -rf "$WT/cartcloser" && cp -r "$APP/build/web" "$WT/cartcloser" && touch "$WT/.nojekyll"
(cd "$WT" && git add cartcloser .nojekyll && (git diff --cached --quiet || git commit -m "Update CartCloser AI web demo") && git push origin gh-pages)
git worktree remove --force "$WT"
echo "Deployed. Live in ~1-2 minutes: https://apex010110.github.io/Random/cartcloser/"
