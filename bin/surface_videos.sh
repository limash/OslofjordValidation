#!/usr/bin/env bash
# Videos of the run's surface snapshots, one MP4 per variable and monthly part (T, S, surface elevation,
# current speed), by src/surface_videos.jl, given the run's bathymetry and report.toml's run_start. Each part
# (~1 GB) is pulled from the bucket into data/runs/<run>/snapshots/, drawn into output/<report>/video/surface/
# and deleted; about 27 min per part. Parts whose videos exist are skipped; in the live run
# (results/oslofjorden/) the last part is still being written and is left out.
#
#   bin/surface_videos.sh <report> [part numbers...]      (default: every part)
set -euo pipefail
source "$(dirname "$0")/config.sh"
report=$1; shift
run=$(toml_value "$report" run)
runs=$PROJECT/data/runs/$run
out=$PROJECT/output/$report/video/surface
mkdir -p "$out" "$runs/snapshots"
script=$PROJECT/src/surface_videos.jl

all=$(gcloud storage ls "$BUCKET/results/$run/snapshots_surface_*_part*.jld2" | sed -E 's/.*_part([0-9]+)\.jld2$/\1/' | sort -n)
last=$(echo "$all" | tail -n 1)
for n in ${*:-$all}; do
    if [ "$run" = "$FJORD" ] && [ "$n" = "$last" ]; then
        echo "part $n is still being written"
        continue
    fi
    source=$(gcloud storage ls "$BUCKET/results/$run/snapshots_surface_*_part$n.jld2")
    stem=$(basename "$source" .jld2)
    if ls "$out/${stem}_"*.mp4 > /dev/null 2>&1; then
        continue
    fi
    file=$runs/snapshots/$stem.jld2
    [ -f "$file" ] || gcloud storage cp "$source" "$file"
    julia --project="$PROJECT" "$script" --bathymetry "$runs/setup/bathymetry.nc" \
        --start-date "$(toml_value "$report" run_start)" --title "$run" --out "$out" "$file"
    rm "$file"
done
