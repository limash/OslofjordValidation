#!/usr/bin/env bash
# The report's FjordSim columns from the run's daily 3D snapshots. Each monthly part is pulled from the
# bucket into data/runs/<run>/snapshots/, reduced by src/extract.jl to output/<report>/data/extract_part<N>.jld2
# (T and S at the cells of cells_extract.csv, and domain statistics) and deleted: a part is ~7 GB, two years
# ~160 GB. The bucket keeps the originals. Parts already extracted are skipped. For an archived run the parts
# are then merged into extract.jld2 and deleted; with extract.jld2 there, nothing is done.
#
# cells_extract.csv is the NIVA cells (cells.csv) and IMR cells (imr_cells.csv) together; both are made by
# src/cells.jl if missing. In the live run (results/oslofjorden/) the last part is still being written and is
# left for a later call, and the parts are kept until the run is archived.
#
#   bin/extract_run.sh <report>
set -euo pipefail
source "$(dirname "$0")/config.sh"
report=$1
export REPORT=$report
run=$(toml_value "$report" run)
out=$PROJECT/output/$report/data
snapshots=$PROJECT/data/runs/$run/snapshots
mkdir -p "$out" "$snapshots"
julia() { command julia --project="$PROJECT" "$@"; }
if [ -f "$out/extract.jld2" ]; then
    echo "$out/extract.jld2 exists"
    exit 0
fi

if [ ! -f "$out/cells_extract.csv" ]; then
    [ -f "$out/cells.csv" ] || julia "$PROJECT/src/cells.jl"
    [ -f "$out/imr_cells.csv" ] || julia "$PROJECT/src/cells.jl" \
        "$PROJECT/data/inputs/observations/$(toml_value "$report" imr_casts)" "$out/imr_cells.csv"
    { cat "$out/cells.csv"; tail -n +2 "$out/imr_cells.csv"; } > "$out/cells_extract.csv"
fi

parts=$(gcloud storage ls "$BUCKET/results/$run/snapshots_ocean_*_part*.nc" | sed -E 's/.*_part([0-9]+)\.nc$/\1/' | sort -n)
last=$(echo "$parts" | tail -n 1)
for n in $parts; do
    target=$out/extract_part$n.jld2
    [ -f "$target" ] && continue
    if [ "$run" = "$FJORD" ] && [ "$n" = "$last" ]; then
        echo "part $n is still being written"
        continue
    fi
    source=$(gcloud storage ls "$BUCKET/results/$run/snapshots_ocean_*_part$n.nc")
    file=$snapshots/$(basename "$source")
    gcloud storage cp "$source" "$file"
    julia "$PROJECT/src/extract.jl" "$target" "$out/cells_extract.csv" "$file"
    rm "$file"
done

if [ "$run" != "$FJORD" ]; then
    julia "$PROJECT/src/merge_extract.jl"
    rm "$out"/extract_part*.jld2
fi
