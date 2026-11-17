#!/usr/bin/env bash
# The inputs every report shares, from the bucket's copy of the setup's data folder into data/inputs/, only
# what the reports read:
#   observations/niva_ctd_odm2_2024-2026   NIVA's CTD casts (src/odm2_fetch.py)
#   observations/imr_ctd_2024-2026         IMR's casts (src/imr_fetch.py)
#   observations/kartverket                tide-gauge sea level (FjordSim's download_observations), from 2020 on
#   norkyst_v3_stations                    NorKyst-v3 at the stations (src/norkyst_fetch.jl)
#   norfjords_stations                     NorFjords-160m at the stations (src/norfjords_fetch.jl)
# A rerun copies only what changed.
#
#   bin/fetch_inputs.sh
set -euo pipefail
source "$(dirname "$0")/config.sh"

for folder in observations/niva_ctd_odm2_2024-2026 observations/imr_ctd_2024-2026 observations/kartverket \
              norkyst_v3_stations norfjords_stations; do
    if ! gcloud storage ls "$BUCKET/data/$FJORD/$folder/" > /dev/null 2>&1; then
        echo "not in the bucket: $folder"
        continue
    fi
    mkdir -p "$PROJECT/data/inputs/$folder"
    gcloud storage rsync -r --exclude='_(19|200|201)[0-9]+\.xml$' "$BUCKET/data/$FJORD/$folder" "$PROJECT/data/inputs/$folder"
done
