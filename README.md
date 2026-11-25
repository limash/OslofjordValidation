# Oslofjord validation

Validation reports of FjordSim's Oslofjord runs (`examples/oslofjorden/oslofjorden.jl` in FjordSim.jl),
run on GCP and read from the bucket. Each report scores one run against:
- **NIVA's CTD casts** from ODM2.
- **IMR's casts** (ØkoKyst and Tisler) from Vannmiljø.
- **Kartverket's tide gauges.**

Two reference models are scored beside it:
- the operational **NorKyst v3**: its 160 m Oslofjord nest (m71) and its 800 m run (m00), two separate
  simulations scored as two models. A station is read from the nest where it covers it, else from the 800 m run;
- IMR's **NorFjords 160 m** hindcast.

The output is a set of CSV tables, figures, videos and an HTML page.

## Layout

| Folder | What it holds | In git |
|---|---|---|
| `bin/` | shell tools: list, fetch and extract runs from the bucket (on a GCP VM), surface videos, build the page | yes |
| `src/` | the report scripts (Julia), the observation fetchers and the page helpers `html_report.py` (Python) | yes |
| `reports/<report>/` | one report's settings `report.toml` and its text `build_html.py` | yes |
| `data/inputs/` | shared inputs, all at the stations: `observations/`, `norkyst_v3_stations/`, `norfjords_stations/` | no |
| `data/runs/<run>/` | one run, only what the reports read (below) | no |
| `output/<report>/` | everything a report's scripts write (below) | no |

A report's output:

```
output/<report>/
├── <report>.html   the report; open it in a browser from this folder (it links figures/ and video/)
├── figures/   PNG figures
├── tables/    the results as CSV: skill scores, tides, water level, drift, domain statistics
├── data/      what one script hands to the next: extract.jld2 (FjordSim at the station cells),
│              NorKyst and NorFjords columns, cells*.csv (each station's model cell), *_pairs.csv
│              (model values beside each observed sample), *_points.csv (each reference model's cell)
└── video/     section and surface videos
```

A run's folder:

```
data/runs/<run>/
├── setup/      the setup file the run ran (named in its run log), bathymetry.nc, rivers_nve.nc, run_id
├── results/    from gs://fjordsim/results/<run>/: the run log and the hydrography, section and
│               tide-gauge station files
└── snapshots/  temporary: one snapshot part while it is extracted or drawn
```

A *run* is a results folder in the bucket. `oslofjorden` is the live run; `oslofjorden_<date>` is an
archived one. A *report* scores one run over a window. Its name is the run's name, or
`<run>_<window>` when one run gets several reports.

## Environments

- **Julia** (≥ 1.12): `Project.toml` here: NCDatasets, JLD2 and CairoMakie. Run everything from this folder
  with `julia --project`. FjordSim itself is not a dependency: the reports read its output files. The few
  functions they need from it are copied: the tidal analysis and the Kartverket and tide-gauge readers
  (`src/tides.jl`), and the surface videos (`src/surface_videos.jl`).
- **Python** (uv): `pyproject.toml`, `uv.lock`. Run with `uv run`; `uv sync` after a pull.
- **gcloud**, logged in with read access to the bucket (`gs://fjordsim`, or `BUCKET=...`).

## Making a report

```bash
bin/list_runs.sh                          # 1. the runs in the bucket: tag, parts, run id, status
bin/fetch_inputs.sh                       # 2. shared inputs (once, and after new observations)
bin/fetch_run.sh <run>                    # 3. station files, log, setup file, bathymetry, rivers
#                                           4. reports/<report>/report.toml (copy the last one)
REPORT=<report> julia --project src/norkyst_columns.jl          # 5. NorKyst at the stations
REPORT=<report> julia --project src/imr_norkyst.jl              #    NorKyst at the IMR stations
REPORT=<report> julia --project src/norfjords_columns.jl        #    NorFjords at the stations
REPORT=<report> julia --project src/imr_norfjords.jl            #    NorFjords at the IMR stations
bin/vm_run.sh <report> extract            # 6. FjordSim columns from the 3D snapshots, on a GCP VM
julia --project src/run_scripts.jl <report> stations.jl section.jl sill_exchange.jl svelvik.jl \
    ctd.jl imr.jl boundary.jl hovmoller.jl analysis.jl map.jl  # 7. tables and figures
#                                           8. reports/<report>/build_html.py (copy the last one, rewrite the text)
bin/build_html.sh <report>                # 9. output/<report>/<report>.html
```

Steps 1 to 4 can come in any order. Step 6 is the slow one: the VM reads about 7 GB per month of run
(below). Steps 2 and 3 copy from the bucket to this machine, about 0.25 GB and 0.7 GB.

### On a GCP VM

Copying out of the bucket costs about $0.12 per GB. A full run is ~175 GB of 3D snapshots and ~26 GB of
surface snapshots, while the reports need only what is cut from them. `bin/vm_run.sh` therefore runs the
snapshot steps on one of FjordSim's preprocessing VMs (`fjordsim-preprocessing-vm-eu-N`, in the bucket's
region `europe-west4`, where reading the bucket is free) and copies down only the result:

| Step | Reads on the VM | Copies down |
|---|---|---|
| `bin/vm_run.sh <report> extract` | `bin/extract_run.sh`: the 3D snapshots | `extract.jld2`, ~20 MB (live run: `extract_<tag>_part<N>.jld2`) |
| `bin/vm_run.sh <report> videos [--vm N] [parts...]` | `bin/surface_videos.sh`: the surface snapshots | the MP4s, ~50 MB a part |
| `bin/vm_run.sh <report> ferry [--vm N] <yyyy-mm-dd>` | `bin/ferry_fields.sh`: the day's surface part | `ferry_fields_<day>.jld2`, the day's hourly surface T and S, ~60 MB |

- **What it does:** it starts the VM with FjordSim's `gcp/fjordsim-gcp up --prep N` (job mode; the VM's
  disk keeps what earlier steps left there). Then it ships the code and the small inputs the step reads,
  installs Julia and the environment on first use (~15 min), and runs the step detached. It prints the
  log's last line each minute, copies down the results this machine lacks, and powers the VM off.
- **It survives this session.** The step runs on the VM. Running the same command again waits for it
  and copies its result down; a finished step is started again cheaply, since the steps skip what is
  done.
- **Billing stops by itself.** A VM it started powers itself off after 10 idle minutes, and 30 minutes
  after a step ends if nothing collected it. One step runs per VM. The videos take ~27 min a part, so
  share the parts out with `--vm 1`, `--vm 2`, `--vm 3`.
- **Needs** FjordSim.jl's `gcp/` (`FJORDSIM_GCP`, default `~/src/FjordSim.jl/gcp`) with its `config.env`, and
  the rights of its job mode: executing the launch job and SSH with sudo on the VMs.

`bin/extract_run.sh` and `bin/surface_videos.sh` also run here, where they copy every part to this
machine.

### Videos

Videos go in `output/<report>/video/`; the page plays them from there.

```bash
REPORT=<report> julia --project src/section_video.jl [fps]   # the Drammensfjord section, one frame per day
bin/vm_run.sh <report> videos [--vm N] [part numbers...]     # surface T, S, elevation and currents per monthly part
bin/vm_run.sh <report> ferry <yyyy-mm-dd>                    # then:
REPORT=<report> julia --project src/ferry_video.jl <yyyy-mm-dd> [fps]   # Color Fantasy's crossings that day
REPORT=<report> julia --project src/ferry_gap.jl            # tables/ferry_gap.csv, over every day with fields
```

- **Section video:** made from the run's hourly section file (`stations_section_<tag>.nc`) and the D-2
  and D-3 casts. It shows the daily-mean S, T and velocity along the Drammensfjord path, plus the
  velocity profile on the Svelvik sill. Its default is 15 frames per second.
- **Surface videos:** made by `src/surface_videos.jl` from the surface snapshot parts
  (`snapshots_surface_<tag>_part<N>.jld2`). It is copied from FjordSim's `scripts/surface_videos.jl`, but
  takes the run's `bathymetry.nc` and `report.toml`'s `run_start` instead of the run's setup file. Each part
  is about 1.1 GB and is pulled, drawn and deleted in turn on the VM, taking about 27 min.
- **Ferry videos:** made by `src/ferry_video.jl`, one MP4 per MS Color Fantasy crossing of the day
  (`ferry_<day>_northbound.mp4`, `..._southbound.mp4`). Each shows the surface T and S maps with the ship's
  track coloured by the FerryBox values. Below each map, the FerryBox and FjordSim's top cell along the track,
  each FjordSim value taken when the ship passes. The day's hourly fields are interpolated to each FerryBox
  minute, one frame per minute, 12 frames per second by default. `src/ferry_gap.jl` averages FjordSim minus
  the FerryBox south of 59.2° N, between 59.2 and 59.6° N, and north of 59.6° N, for each crossing. The report
  quotes it and links the northbound videos of the days its `FERRY_DAYS` names.

### `report.toml`

```toml
run = "oslofjorden_2026-11-10"          # data/runs/<run>
run_start = 2024-10-01T00:00:00         # the run's start_date: the time origin of its station files
start = 2024-10-01T00:00:00             # the window drawn
spinup = 2024-11-01T00:00:00            # scored from here
stop = 2026-10-01T00:00:00
niva_casts = "niva_ctd_odm2_2024-2026"  # folders in data/inputs/observations/
imr_casts = "imr_ctd_2024-2026"
profile_stations = ["VAL-1", "Im2", "D-2", "Dk1", "Ep1"]          # the page's profile figure: each station at
profile_dates = [2025-12-10, 2026-03-18, 2026-06-26, 2026-08-14]  # its cast nearest each date (within 20 days)
# stamp = "20261107T210205"             # one launch only; default: every run log in data/runs/<run>/results, joined
```

`run_start` is the `start_date` of the `RunConfig` in the run's setup file, `data/runs/<run>/setup/`.

### Reference model data

- **NorKyst v3 at the stations**: `data/inputs/norkyst_v3_stations/`, fetched from met.no's THREDDS server
  by `src/norkyst_fetch.jl`. Run at most two fetches at once, because THREDDS refuses more.
  - `{160m,800m}/<yyyymm>.jld2`: hourly columns at the NIVA stations and sea level at the gauges. If a window
    goes beyond those months, fetch more: `julia --project src/norkyst_fetch.jl 160 <first yyyymm> <last yyyymm>`,
    then the same with `800`.
  - `imr/<yyyymm>.jld2`: daily means at the IMR stations on their cast days. After new IMR casts, run
    `julia --project src/norkyst_fetch.jl imr`.
  - `boundary_zeta.jld2`: NorKyst's own hourly sea level near the open boundary south of Viker, which
    `analysis.jl` fits NorKyst's tide on. It is cut from FjordSim's boundary downloads
    (`gs://fjordsim/data/oslofjorden/norkyst_v3_hourly/`, 2.5 GB) by
    `julia --project src/norkyst_fetch.jl boundary <their folder>`.
- **NorFjords 160 m at the stations**: `data/inputs/norfjords_stations/`, with monthly `<yyyymm>.jld2`
  files, `points.csv` (each station's NorFjords cell) and `tides_2024.jld2` (hourly sea level at the gauges,
  the only year it exists). These are extracted once by
  `julia --project src/norfjords_fetch.jl <dir> <first yyyymm> <last yyyymm>` from IMR's daily-mean files
  `<dir>/<year>/norfjords_160m_avg.nc4_<yyyymmdd>12` and `<dir>/Tides/`. Those files are not in the bucket;
  they are a local copy on an external drive, and reading them takes about 1.7 s per day. NorFjords ends on
  2026-06-30.

### Observations

`data/inputs/observations/` holds the stations' data, pulled from `gs://fjordsim/data/oslofjorden/observations/`:

| Folder | What | Made by |
|---|---|---|
| `niva_ctd_odm2_2024-2026/` | NIVA's CTD casts | `uv run src/odm2_fetch.py`, from NIVA's ODM2 database |
| `imr_ctd_2024-2026/` | IMR's ØkoKyst and Tisler casts | `uv run src/imr_fetch.py`, from Vannmiljø |
| `kartverket/` | sea level at Viker, Oscarsborg and Oslo, from 2020 on | FjordSim's `download_observations` |
| `niva_ferrybox_2024-2026/` | FerryBox tracks of MS Color Fantasy and MS Color Hybrid, 4 m, one row a minute | `uv run src/ferrybox_fetch.py`, from NIVA's FerryBox API; not in the bucket |

The Python fetchers need their API keys in `~/.config/niva-data/`; `ferrybox_fetch.py` signs in with NIVA's
service account, `niva-service-account.json`. Kartverket's monthly files are read by
`kartverket_series` in `src/tides.jl`.

### Publishing

The newest report is published at https://limash.github.io/OslofjordValidationReport/ from the repo
[limash/OslofjordValidationReport](https://github.com/limash/OslofjordValidationReport), cloned next to this
project. Each GitHub release there is archived on Zenodo with its own DOI.

```bash
bin/publish_pages.sh <report>                     # the page as index.html, its explorers, the figures and videos it links
cd ../OslofjordValidationReport
git commit -m "Report <report>" && git push       # the site updates in a minute
gh release create vN.0 --notes "Report <report>"  # a new Zenodo version
```

The site keeps only the newest report; earlier ones stay in the releases and on Zenodo. The Zenodo metadata
(type, author, licence CC BY 4.0) is in the clone's `.zenodo.json`.

## Origin

The scripts come from the full-period report of run `20261107T210205`, which was archived as
`oslofjorden_2026-11-10`. That report's output is `output/oslofjorden_2026-11-10/`. Its scripts were
rerun here and gave the same tables. Its text is now the HTML page.
