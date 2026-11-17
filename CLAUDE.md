# CLAUDE.md

This project validates FjordSim's Oslofjord runs, which run on GCP. `README.md` holds the layout,
the environments and the step-by-step workflow; read it before any step.

## Hard rules

- **The bucket is read-only from here.** `bin/` only reads `gs://fjordsim`. Never copy, move or delete
  anything there without asking first. Archiving runs and running simulations belong to FjordSim.jl's
  `gcp/fjordsim-gcp` (its `gcp/README.md`), not to this project.
- **Copying from the bucket costs money: ask first.** Before anything copies files from the bucket to
  this machine (`bin/fetch_run.sh`, `bin/fetch_inputs.sh`, `bin/extract_run.sh`, `bin/surface_videos.sh`,
  a `gcloud storage cp`/`rsync`), say what and how many GB, and wait for a yes. Listing the bucket is free.
- **The snapshots are read on a GCP VM, without asking.** The station extract and the surface videos run
  through `bin/vm_run.sh` (README, "On a GCP VM"): a preprocessing VM reads the bucket in its region for
  free and only the result comes down (~20 MB extract, ~50 MB of videos a part). Starting the VM, running
  the step and copying its result down need no permission. Never run `bin/extract_run.sh` or
  `bin/surface_videos.sh` here unless the user asks for it.
- **Code, data and output stay apart.** Code goes in `src/`, `bin/` and `reports/`. Downloads go in
  `data/` and nowhere else. Everything a script writes goes in `output/<report>/`: figures in
  `figures/`, results in `tables/`, intermediate files in `data/`, videos in `video/`, and the PDF at
  its top. Never edit a file in `output/` or `data/` by hand: change the script and rerun it. Keep
  only what a report or a later step reads; no logs, scratch files or part files once merged.
- **One report per `reports/<report>/` and `output/<report>/`.** Every script takes the report from
  `REPORT=<name>` (or from the first argument of `src/run_scripts.jl`). A new report gets a new name. Do
  not rerun another report's steps into its folder unless that is the task.
- **The report text is hand-written.** `reports/<report>/build_pdf.py` holds the findings with their
  numbers. Take every number from the CSVs in `output/<report>/`, and check them again after any
  rerun. Start a new report's text from the last one and rewrite it; never leave the old run's numbers
  in it.
- **Ask before:** adding a Julia or Python dependency (`Pkg.add`, `uv add`), deleting anything in
  `output/` or `data/runs/`, and running a test that takes over 5 minutes or uses GCP (a VM, the bucket),
  even through `bin/vm_run.sh`: say what, how long and what it costs.

## Gotchas

- **The snapshots are large.** One monthly 3D snapshot part is about 7 GB, and two years are about
  175 GB; a surface part is about 1.1 GB. Hence `bin/vm_run.sh`. The `/tmp` scratch space is a small
  tmpfs, so never download there.
- **Background jobs die with the session** (SIGTERM, even under `setsid nohup`) and on reboot. Run long
  steps from the active session. Every step skips what is already done (extract parts, NorKyst months),
  so it can simply be started again. A step `bin/vm_run.sh` started goes on on the VM: run the same
  command again to wait for it and copy its result down.
- **A VM bills while it is up.** `bin/vm_run.sh` powers its VM off when the step ends, and a VM it started
  powers itself off when idle. If it is stopped by hand, check `gcloud compute instances list
  --project=nivatest-1` and power an idle VM off with `gcp/fjordsim-gcp down --vm N` (FjordSim.jl).
- **Never wait with `pgrep -f <pattern>`** or stop jobs with `pkill -f <pattern>` from a command line
  that contains the pattern: it matches its own shell. Wait on the job's notification; stop it by PID.
- **gcloud login expires.** On an auth error, ask the user to run `! gcloud auth login`.
- **Bathymetry and rivers are the bucket's current ones.** `bin/fetch_run.sh` copies the setup's
  `bathymetry.nc` and `rivers_nve.nc` when the run is fetched. If the setup's grid or rivers were
  prepared again after the run, replace them with the run's own versions before `cells.jl`/`map.jl`.
  Compare the grid size against the run's log and its setup file in `setup/`.
- **Every report needs NorFjords.** `ctd.jl`, `hovmoller.jl`, `imr.jl` and `analysis.jl` load
  `norfjords_columns.jld2`, `imr_norfjords.jld2` and `norfjords_pairs.csv`. These are cut from
  `data/inputs/norfjords_stations/`, extracted once from IMR's daily files on an external drive (README).
  NorFjords ends on 2026-06-30. Its hourly sea level exists only for 2024, which is why `analysis.jl` fits
  its tide over 2024.
- **A station added to the casts** gets no NorKyst or NorFjords point until the station extracts are made
  again. `norfjords_stations/points.csv` and `norkyst_v3_stations/<grid>m/points.csv` are fixed once
  written. Delete them and the month files, then fetch again.
- **Choosing a model cell.** `cells.jl` picks each station's column from the casts in the window and the
  run's bathymetry. Extract columns again (`bin/vm_run.sh <report> extract`, after deleting
  `data/extract.jld2`) whenever `cells_extract.csv` changes. A report on the same run with an identical `cells_extract.csv`
  can copy another report's `data/extract.jld2` instead of downloading again.
- **Assumptions fixed in the code:** the model box (10.0–11.2 °E, 58.95–59.93 °N) in `niva_casts`
  (`src/common.jl`), `norfjords_fetch.jl`, `imr_fetch.py` and `ferrybox_fetch.py`. The cast folders the
  station extracts are chosen from are named in `norkyst_fetch.jl` and `norfjords_fetch.jl`. A run on
  another box or period needs these checked.
- **FjordSim is not a dependency.** `src/tides.jl` and `src/surface_videos.jl` are copies of FjordSim
  code. If FjordSim changes its station-file layout (JLD2 `timeseries/...`, NetCDF attributes), its
  Kartverket cache names or its surface writer, update the copies and every script that reads run files.
  Don't add FjordSim back to `Project.toml`.
- **Observation file names transliterate Norwegian letters** (`Bastoy_S.csv`, `Faerder_T.csv`). Read
  them through `obs_stem` in `src/paths.jl`; the fetchers write the same names.
