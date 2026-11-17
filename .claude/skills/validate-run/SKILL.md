---
name: validate-run
description: Make a validation report of a FjordSim Oslofjord run - pick the run, check and fetch the inputs, extract the model on a GCP preprocessing VM, run the scripts, write and build the HTML page. Use when asked to validate or score a run, or to make a new report in reports/.
---

# Validating a run

The commands are in README.md ("Making a report", "On a GCP VM", "`report.toml`", "Reference model data",
"Observations") and the rules in CLAUDE.md; read README.md first and follow both. This skill holds what they
don't: the order, the choices, and the checks between the steps.

## 1. Agree the scope

Ask the user, in one question, what you cannot settle yourself:
- **The run.** `bin/list_runs.sh` (a listing, free) shows tags, parts and status. An archived
  `oslofjorden_<date>` is complete; the live `oslofjorden` is still growing and its last part is skipped.
- **The report's name and window** (`start`, `spinup`, `stop`). `stop` must not pass the run's end: the
  run log's last `Simulation time ... days` after the setup file's `start_date`.
- **What the report should say this time.** What changed in the run (diff its setup file
  `data/runs/<run>/setup/*.jl` against the last report's run), and what to look at. The last report is a
  template for the layout, not a spec of the content.
- **Surface videos or not** (README, "Videos").

## 2. Check the inputs cover the window

Check the files themselves, not a remembered date:
- Casts: the first and last `time` in `data/inputs/observations/<niva_casts>/*_S.csv` and `<imr_casts>/`.
  Their fetchers (`src/odm2_fetch.py`, `src/imr_fetch.py`) have fixed periods and output folders. A
  window beyond them needs the dates and a new folder name edited in the fetcher, in `report.toml`, and in
  `norkyst_fetch.jl`/`norfjords_fetch.jl` (CLAUDE.md, "Assumptions fixed in the code").
- NorKyst: `ls data/inputs/norkyst_v3_stations/{160m,800m}/` must hold every month of the window; else
  `src/norkyst_fetch.jl` (README).
- The FerryBox tracks (`niva_ferrybox_2024-2026`) exist but no script scores them yet. Mention them; don't
  build that scoring unless asked.

## 3. Fetch the run and write report.toml

- `bin/fetch_inputs.sh` (if `data/inputs/` is missing or the bucket has new observations) and
  `bin/fetch_run.sh <run>` copy from the bucket (CLAUDE.md); `gcloud storage du -s` gives the size.
- Bathymetry and rivers: CLAUDE.md, "Bathymetry and rivers are the bucket's current ones".
- `reports/<report>/report.toml`: copy the last one and change the comment, `run`, the window and the cast
  folders. `run_start` is the setup file's `start_date`.

## 4. The model data: start the VM first, it is the slow part

- Unless another report's `extract.jld2` can be reused (CLAUDE.md, "Choosing a model cell"), start
  `bin/vm_run.sh <report> extract` as a background command. It makes `cells.csv` here first, then runs
  on the VM.
- While it runs, do README step 5 (NorKyst and NorFjords columns) here. It does not need the extract.
- Videos: one background `bin/vm_run.sh <report> videos --vm N <parts>` per VM (N = 1..3), started one
  after another, each with a third of the parts.
- Wait on the task notifications. If the session ended, run the same command again: it waits for the step
  on the VM and copies its result down.

## 5. Tables and figures

- README step 7, in one `src/run_scripts.jl` call. Each script prints `== <file>` and its time; any error
  stops the call, so fix it and rerun from that script.
- Check before writing:
  - `ctd_pairs.csv` spans the scored window (`spinup` to `stop`).
  - No skill table is empty or all `NaN`.
  - Look at `map.png`, a few `profiles_*.png`, the `hovmoller_*` and `waterlevel_*` figures for blank
    panels or a wrong window.

## 6. The text

- Set `profile_stations` and `profile_dates` in `report.toml` to casts that show this run's main
  errors, and rerun `ctd.jl` if they changed.
- Copy the last report's `build_html.py`. Rewrite the setup table from the run's setup file (diff it against
  the last run's), and every sentence that holds a judgement. Add or drop sections as agreed in step 1.
  Compute every result number from a `read(...)` table or `ctd_pairs.csv`; never type one.
- Then grep the new `build_html.py` for the old report's name, run tag and dates: none may be left.
- `bin/build_html.sh <report>`, then print the page's text (strip the tags) and read it against the
  figures: a claim must hold in the figure it links. Check every `figures/` and `video/` link exists.

## 7. Finish

- No VM left on: `gcloud compute instances list --project=nivatest-1 --filter="name~fjordsim-preprocessing"`
  should show none of them `RUNNING` unless something else uses it.
- Tell the user:
  - the page's path and the main findings;
  - what was copied from the bucket (GB) and how long the VMs ran;
  - what was skipped, and why.
