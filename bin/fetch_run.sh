#!/usr/bin/env bash
# One run from the bucket into data/runs/<run>/, only what the reports read:
#   setup/     the setup file the run ran (named in its run log), the setup's bathymetry.nc and rivers_nve.nc,
#              and run_id, the run's id in gs://fjordsim/runs/
#   results/   from gs://fjordsim/results/<run>/: the run log and the hydrography, section and tide-gauge
#              station files
# Not the snapshots (bin/extract_run.sh, bin/surface_videos.sh), the checkpoints or the other station files.
# Rerun it while the run is going to bring the station files up to date.
#
#   bin/fetch_run.sh <results folder>      e.g. bin/fetch_run.sh oslofjorden_2026-11-10
set -euo pipefail
source "$(dirname "$0")/config.sh"
run=$1
setup=$PROJECT/data/runs/$run/setup
results=$PROJECT/data/runs/$run/results
mkdir -p "$setup" "$results"

gcloud storage rsync "$BUCKET/results/$run" "$results" \
    --exclude='^(?!(fjordsim_[0-9T]+\.log|stations_(hydrography|section|tidegauge)_.*)$)'
# The bucket holds the setup's current bathymetry and rivers, which may have been prepared again since the run.
for f in bathymetry.nc rivers_nve.nc; do
    [ -f "$setup/$f" ] || gcloud storage cp "$BUCKET/data/$FJORD/$f" "$setup/$f"
done

if [ ! -f "$setup/run_id" ]; then
    # The newest tag: a resumed run's marker keeps only its last launch's log.
    stamp=$(ls "$results" | grep -o 'fjordsim_[0-9]\{8\}T[0-9]\{6\}\.log' | grep -o '[0-9]\{8\}T[0-9]\{6\}' | tail -n 1 || true)
    id=$([ -n "$stamp" ] && run_id_of "$stamp" || true)
    if [ -z "$id" ] && [ "$run" = "$FJORD" ]; then
        running=$(running_ids)
        [ "$(echo "$running" | grep -c .)" = 1 ] && id=$running
    fi
    if [ -z "$id" ]; then
        echo "no run marker names tag ${stamp:-?}: setup file not fetched"
        exit 0
    fi
    echo "$id" > "$setup/run_id"
    # The run log names the setup file: "=== run_simulation --config /configs/<run id>/<file> ===". A live run
    # has not uploaded its log yet; its setup is then the fjord's own.
    file=$(gcloud storage cat "$BUCKET/runs/$id/run.log" 2>/dev/null | grep -o -m1 "\-\-config /configs/$id/[^ ]*\.jl" | sed 's|.*/||' || true)
    gcloud storage cp "$BUCKET/configs/$id/${file:-$FJORD.jl}" "$setup/"
fi
