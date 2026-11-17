#!/usr/bin/env bash
# The snapshot steps on one of FjordSim's preprocessing VMs, so that only their results come down from GCP.
# The VM reads the bucket in its own region at no transfer cost; this machine gets the result:
#   extract   bin/extract_run.sh there, and its extract.jld2 (or, for the live run, its extract_part<N>.jld2)
#             back: ~20 MB instead of ~175 GB of 3D snapshots
#   videos    bin/surface_videos.sh there, and its MP4s back: ~50 MB a part instead of ~1.1 GB
# The VM gets the code and the few small inputs these steps read, installs Julia on first use and runs the
# step detached, so it goes on if this session ends. Every minute the step's last log line is printed. When
# it ends, the results missing here are copied down and the VM is powered off. A VM nobody uses powers
# itself off: 10 minutes after this script starts it, or 30 minutes after a step ends. Calling the script
# again with the same arguments picks up where it stopped, since the steps skip what is done.
#
#   bin/vm_run.sh <report> extract [--vm N]
#   bin/vm_run.sh <report> videos [--vm N] [part numbers...]   (default: the parts without videos here)
#
# --vm N picks PREP_VM_PREFIX-N (default 1); one step per VM at a time, so several VMs can share the videos.
# The project, VMs and bucket are FjordSim's, from its gcp/config.env (FJORDSIM_GCP, default
# ~/src/FjordSim.jl/gcp). The VM and its service account only read the bucket.
set -euo pipefail
source "$(dirname "$0")/config.sh"
GCP=${FJORDSIM_GCP:-$HOME/src/FjordSim.jl/gcp}
source "$GCP/load_config.sh"
_fjordsim_load_config "$GCP/config.env"

report=$1 step=$2; shift 2
n=1
if [ "${1:-}" = --vm ]; then n=$2; shift 2; fi
run=$(toml_value "$report" run)
data=output/$report/data
id=${report}_$step

case $step in
extract)
    [ -f "$PROJECT/$data/extract.jld2" ] && { echo "$data/extract.jld2 exists"; exit 0; }
    # cells_extract.csv as bin/extract_run.sh makes it, here, where the run's station files are.
    if [ ! -f "$PROJECT/$data/cells_extract.csv" ]; then
        export REPORT=$report
        [ -f "$PROJECT/$data/cells.csv" ] || julia --project="$PROJECT" "$PROJECT/src/cells.jl"
        [ -f "$PROJECT/$data/imr_cells.csv" ] || julia --project="$PROJECT" "$PROJECT/src/cells.jl" \
            "$PROJECT/data/inputs/observations/$(toml_value "$report" imr_casts)" "$PROJECT/$data/imr_cells.csv"
        { cat "$PROJECT/$data/cells.csv"; tail -n +2 "$PROJECT/$data/imr_cells.csv"; } > "$PROJECT/$data/cells_extract.csv"
    fi
    command="bin/extract_run.sh $report"
    results="$data/extract*.jld2" ;;
videos)
    parts=$*
    if [ -z "$parts" ]; then
        for source in $(gcloud storage ls "$BUCKET/results/$run/snapshots_surface_*_part*.jld2"); do
            ls "$PROJECT/output/$report/video/surface/$(basename "$source" .jld2)_"*.mp4 > /dev/null 2>&1 ||
                parts="$parts $(echo "$source" | sed -E 's/.*_part([0-9]+)\.jld2$/\1/')"
        done
    fi
    [ -n "$parts" ] || { echo "every part has its videos here"; exit 0; }
    command="bin/surface_videos.sh $report $parts"
    results="output/$report/video/surface/*.mp4" ;;
*)
    echo "the step is extract or videos" >&2; exit 1 ;;
esac

vm=$PREP_VM_PREFIX-$n
status() { gcloud compute instances list --project="$PROJECT_ID" --filter="name ~ ^$PREP_VM_PREFIX-[0-9]+\$" \
    --format='value(name,status,zone.basename())'; }
# Power the VM off after $1 seconds, unless a step holds it then or a FjordSim container runs there.
idle_off() { echo "sleep ${1}; flock -n ~/vm_run.lock true && [ -z \"\$(sudo docker ps -q 2>/dev/null)\" ] && sudo poweroff"; }
before=$(status)
running() { awk -v vm="$1" '$1 == vm && $2 == "RUNNING" {f = 1} END {exit !f}' <<< "$2"; }
if ! running "$vm" "$before"; then
    "$GCP/fjordsim-gcp" up --prep "$n" || "$GCP/fjordsim-gcp" up --prep
    # In job mode the launch starts VMs 1..n (or the job's own count): every one started here is left to
    # power itself off if nothing takes it, once its SSH answers (a minute or two after it is RUNNING).
    while read -r name state zone; do
        [ "$state" = RUNNING ] && ! running "$name" "$before" || continue
        for try in $(seq 30); do
            gcloud compute ssh "$name" --project="$PROJECT_ID" --zone="$zone" --quiet --command \
                "setsid nohup bash -c '$(idle_off 600)' > /dev/null 2>&1 < /dev/null &" < /dev/null > /dev/null 2>&1 && break
            [ "$try" -lt 30 ] || { echo "no SSH to $name" >&2; exit 1; }
            sleep 10
        done
    done <<< "$(status)"
fi
zone=$(status | awk -v vm="$vm" '$1 == vm {print $3}')
on_vm() { gcloud compute ssh "$vm" --project="$PROJECT_ID" --zone="$zone" --quiet --command "$1"; }

# The step on the VM, if one holds the lock: a step stopped by a power-off leaves vm_run.current behind.
current=$(on_vm 'flock -n ~/vm_run.lock true || cat ~/vm_run.current 2>/dev/null || true')
if [ -z "$current" ]; then
    [ -z "$(on_vm 'sudo docker ps -q 2>/dev/null || true')" ] || { echo "$vm runs a FjordSim job: pick another --vm" >&2; exit 1; }
    # The code and what the steps read: the casts' station lists (common.jl), the run's log (its tag), its
    # bathymetry (the videos), the cells and the parts already extracted.
    cd "$PROJECT"
    files="Project.toml Manifest.toml bin src reports/$report data/runs/$run/setup/bathymetry.nc
           data/inputs/observations/$(toml_value "$report" niva_casts) data/inputs/observations/$(toml_value "$report" imr_casts)
           $(ls data/runs/"$run"/results/fjordsim_*.log $data/cells_extract.csv $data/extract_part*.jld2 2>/dev/null || true)"
    tar --exclude=__pycache__ -czf - $files | on_vm 'mkdir -p ~/oslofjord_validation && tar -xzf - -C ~/oslofjord_validation'
    on_vm "cat > ~/vm_run_$id.sh" <<EOF
exec 9> ~/vm_run.lock
flock -n 9 || { echo 'another step holds the VM'; exit 1; }
echo $id > ~/vm_run.current
cd ~/oslofjord_validation
[ -x ~/.juliaup/bin/julia ] || curl -fsSL https://install.julialang.org | sh -s -- --yes --default-channel $(sed -n 's/^julia_version = "\(.*\)"/\1/p' Manifest.toml)
export PATH=\$HOME/.juliaup/bin:\$PATH
code=0
{ julia --project -e 'using Pkg; Pkg.instantiate()' && $command; } || code=\$?
rm ~/vm_run.current
echo \$code > ~/vm_run_$id.done
exec 9>&-
setsid nohup bash -c '$(idle_off 1800)' > /dev/null 2>&1 < /dev/null &
EOF
    on_vm "rm -f ~/vm_run_$id.done; setsid nohup bash ~/vm_run_$id.sh > ~/vm_run_$id.log 2>&1 < /dev/null & echo started $id on $vm"
elif [ "$current" != "$id" ]; then
    echo "$vm is running $current: pick another --vm" >&2; exit 1
else
    echo "$id is already running on $vm"
fi

last=""
until code=$(on_vm "cat ~/vm_run_$id.done 2>/dev/null") && [ -n "$code" ]; do
    line=$(on_vm "tail -n 1 ~/vm_run_$id.log 2>/dev/null" || true)
    [ "$line" = "$last" ] || echo "$(date +%H:%M) $line"
    last=$line
    sleep 60
done

missing=""
for f in $(on_vm "cd ~/oslofjord_validation && ls $results 2>/dev/null || true"); do
    [ -f "$PROJECT/$f" ] || missing="$missing $f"
done
if [ -n "$missing" ]; then
    echo "copying down:$missing"
    on_vm "cd ~/oslofjord_validation && tar -cf - $missing" | tar -xf - -C "$PROJECT"
fi
[ "$code" = 0 ] || { echo "$id failed (exit $code); the end of its log:" >&2; on_vm "tail -n 30 ~/vm_run_$id.log" >&2; }
echo "powering off $vm"
on_vm "$(idle_off 0)" > /dev/null 2>&1 || true
exit "$code"
