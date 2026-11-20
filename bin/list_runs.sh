#!/usr/bin/env bash
# The Oslofjord runs in the bucket: each results folder with its run tag, its monthly ocean snapshot parts
# and hydrography station files, and the run id and status of the run that wrote it. `results/oslofjorden/`
# is the live run (or the last one not yet archived); every other folder is an archived run.
#
#   bin/list_runs.sh
set -euo pipefail
source "$(dirname "$0")/config.sh"

declare -A RUN_ID STATUS
running=()
for marker in $(gcloud storage ls "$BUCKET/runs/" | grep "/runs/$FJORD"); do
    status=$(gcloud storage cat "${marker}status" 2>/dev/null || echo "?")
    [ "$status" = running ] && running+=("$(basename "$marker")")
    stamp=$(gcloud storage cat -r 0-2000000 "${marker}run.log" 2>/dev/null | grep -o 'fjordsim_[0-9]\{8\}T[0-9]\{6\}\.log' | stamp_of || true)
    [ -n "$stamp" ] || continue
    RUN_ID[$stamp]=$(basename "$marker")
    STATUS[$stamp]=$status
done

printf "%-32s %-16s %5s %8s  %-48s %s\n" "results folder" "run tag" "parts" "stations" "run id" "status"
for dir in $(gcloud storage ls "$BUCKET/results/" | grep "/results/$FJORD"); do
    files=$(gcloud storage ls "$dir")
    # A resumed run has one tag per launch; its marker's run.log is the last launch's, so the newest tag names it.
    stamps=$(echo "$files" | grep -o 'fjordsim_[0-9]\{8\}T[0-9]\{6\}\.log' | grep -o '[0-9]\{8\}T[0-9]\{6\}' | sort || true)
    stamp=$(echo "$stamps" | tail -n 1)
    parts=$(echo "$files" | grep -c 'snapshots_ocean_.*_part[0-9]*\.nc$' || true)
    stations=$(echo "$files" | grep -c "stations_hydrography_${stamp}_" || true)
    # The live run has not uploaded its run.log yet: name the running run, if there is one.
    if [ -z "${RUN_ID[$stamp]:-}" ] && [ "$(basename "$dir")" = "$FJORD" ] && [ ${#running[@]} -eq 1 ]; then
        RUN_ID[$stamp]=${running[0]}
        STATUS[$stamp]=running
    fi
    printf "%-32s %-16s %5s %8s  %-48s %s\n" "$(basename "$dir")" "$(echo ${stamps:--} | tr ' ' ',')" "$parts" "$stations" \
        "${RUN_ID[$stamp]:--}" "${STATUS[$stamp]:--}"
done
