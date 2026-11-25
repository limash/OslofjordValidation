#!/usr/bin/env bash
# Copy a built report into the GitHub Pages repo, a clone of limash/OslofjordValidationReport next to this
# project. The site holds only the newest report: the previous one's pages, figures and videos are removed,
# the report's page becomes index.html, and only the figures and videos the pages link are copied. Earlier reports stay in the repo's releases and on Zenodo.
# Commit, push and release from the clone (README, "Publishing").
#
#   bin/publish_pages.sh <report>
set -euo pipefail
source "$(dirname "$0")/config.sh"
report=$1
src="$PROJECT/output/$report"
pages="$PROJECT/../OslofjordValidationReport"
[ -f "$src/$report.html" ] || { echo "no $src/$report.html: run bin/build_html.sh $report first" >&2; exit 1; }
[ -d "$pages/.git" ] || { echo "no Pages clone at $pages" >&2; exit 1; }

rm -rf "$pages"/*.html "$pages/figures" "$pages/video"
cp "$src/$report.html" "$pages/index.html"
cp "$src"/*_explorer.html "$pages/"
# Only the figures and videos the pages link: output/<report>/ also keeps ones the text no longer shows.
(cd "$src" && grep -ohE '(figures|video)/[A-Za-z0-9_./-]+\.(png|mp4|gif)' *.html | sort -u | xargs cp --parents -t "$pages")
git -C "$pages" add -A
git -C "$pages" status --short | sed -n '1,5p'
echo "$(git -C "$pages" status --short | wc -l) files changed in $(cd "$pages" && pwd); size $(du -sh --exclude=.git "$pages" | cut -f1)"
