#!/usr/bin/env bash
# One day's hourly surface T and S, output/<report>/data/ferry_fields_<yyyy-mm-dd>.jld2 (~60 MB), for
# src/ferry_video.jl. The month's surface part (~1.1 GB; part N is month N from run_start) is pulled into
# data/runs/<run>/snapshots/, cut by src/ferry_fields.jl and deleted. Run it on a VM:
#
#   bin/vm_run.sh <report> ferry <yyyy-mm-dd>
set -euo pipefail
source "$(dirname "$0")/config.sh"
report=$1 day=$2
run=$(toml_value "$report" run)
start=$(toml_value "$report" run_start)
out=$PROJECT/output/$report/data/ferry_fields_$day.jld2
[ -f "$out" ] && { echo "$out exists"; exit 0; }
mkdir -p "$(dirname "$out")" "$PROJECT/data/runs/$run/snapshots"
n=$(( (10#${day:0:4} - 10#${start:0:4}) * 12 + 10#${day:5:2} - 10#${start:5:2} + 1 ))
files=""
for source in $(gcloud storage ls "$BUCKET/results/$run/snapshots_surface_*_part$n.jld2" | written_order); do
    file=$PROJECT/data/runs/$run/snapshots/$(basename "$source")
    [ -f "$file" ] || gcloud storage cp "$source" "$file"
    files="$files $file"
done
julia --project="$PROJECT" "$PROJECT/src/ferry_fields.jl" "$start" "$day" "$out" $files
rm $files
