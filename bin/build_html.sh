#!/usr/bin/env bash
# The report's page: reports/<report>/build_html.py over the tables, figures and videos in output/<report>/,
# written to output/<report>/<report>.html. Open it in a browser from that folder: it links the figures and
# videos by relative paths.
#
#   bin/build_html.sh <report>
set -euo pipefail
source "$(dirname "$0")/config.sh"
report=$1
REPORT=$report PYTHONPATH="$PROJECT/src" uv run --project "$PROJECT" python "$PROJECT/reports/$report/build_html.py"
