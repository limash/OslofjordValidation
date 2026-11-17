# Sourced by the other scripts in bin/. BUCKET may be overridden from the environment.
PROJECT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUCKET=${BUCKET:-gs://fjordsim}
FJORD=oslofjorden

# The run tag of a run log or results file name: fjordsim_20261107T210205.log -> 20261107T210205.
stamp_of() { grep -o '[0-9]\{8\}T[0-9]\{6\}' | head -n 1; }

# The run marker gs://.../runs/<run id>/ whose log names the tag $1, or nothing. A marker's log starts with
# the image pull and staging, so the first 2 MB are searched.
run_id_of() {
    local marker
    for marker in $(gcloud storage ls "$BUCKET/runs/" | grep "/runs/$FJORD"); do
        if gcloud storage cat -r 0-2000000 "${marker}run.log" 2>/dev/null | grep -q "fjordsim_$1\.log"; then
            basename "$marker"
            return
        fi
    done
}

# The run ids whose status is `running`. A run uploads its run.log only when it ends, so the live run
# (results/oslofjorden/) is found by its status instead of its tag.
running_ids() {
    local marker
    for marker in $(gcloud storage ls "$BUCKET/runs/" | grep "/runs/$FJORD"); do
        [ "$(gcloud storage cat "${marker}status" 2>/dev/null)" = running ] && basename "$marker"
    done
    return 0
}

# A value from reports/<report>/report.toml: `toml_value <report> run`.
toml_value() { sed -n "s/^$2 *= *\"\{0,1\}\([^\"#]*\)\"\{0,1\}.*/\1/p" "$PROJECT/reports/$1/report.toml" | sed 's/ *$//'; }
