#!/usr/bin/env bash
# The report's PDF: reports/<report>/build_pdf.py over the tables and figures in output/<report>/, written to
# output/<report>/<report>.pdf.
#
#   bin/build_pdf.sh <report>
set -euo pipefail
source "$(dirname "$0")/config.sh"
report=$1
REPORT=$report PYTHONPATH="$PROJECT/src" uv run --project "$PROJECT" \
    python "$PROJECT/reports/$report/build_pdf.py" "$PROJECT/output/$report/$report.pdf"
