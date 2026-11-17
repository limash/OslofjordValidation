# Oslofjord validation

Validation reports of FjordSim's Oslofjord runs (`examples/oslofjorden/oslofjorden.jl` in FjordSim.jl),
run on GCP and read from the bucket. Each report scores one run against:
- **NIVA's CTD casts** from ODM2.
- **IMR's casts** (ØkoKyst and Tisler) from Vannmiljø.
- **Kartverket's tide gauges.**

Two reference models are scored beside it:
- the operational **NorKyst v3** (its 160 m Oslofjord nest and the 800 m run);
- IMR's **NorFjords 160 m** hindcast.

The output is a set of CSV tables, figures and a PDF.

## Layout

| Folder | What it holds | In git |
|---|---|---|
| `bin/` | shell tools: list, fetch and extract runs from the bucket, surface videos, build a PDF | yes |
| `src/` | the report scripts (Julia) and the observation fetchers and PDF helpers (Python) | yes |
| `reports/<report>/` | one report's settings `report.toml` and its text `build_pdf.py` | yes |
| `data/inputs/` | shared inputs, all at the stations: `observations/`, `norkyst_v3_stations/`, `norfjords_stations/` | no |
| `data/runs/<run>/` | one run, only what the reports read (below) | no |
| `output/<report>/` | everything a report's scripts write (below) | no |

A report's output:

```
output/<report>/
├── <report>.pdf
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
bin/extract_run.sh <report>               # 6. FjordSim columns from the 3D snapshots
julia --project src/run_scripts.jl <report> stations.jl section.jl sill_exchange.jl \
    ctd.jl imr.jl hovmoller.jl analysis.jl map.jl              # 7. tables and figures
#                                           8. reports/<report>/build_pdf.py (copy the last one, rewrite the text)
bin/build_pdf.sh <report>                 # 9. output/<report>/<report>.pdf
```

Steps 1 to 4 can come in any order. Step 6 is the slow one: it downloads about 7 GB per month of run.

### Videos

Videos go in `output/<report>/video/` and are not part of the PDF.

```bash
REPORT=<report> julia --project src/section_video.jl [fps]   # the Drammensfjord section, one frame per day
bin/surface_videos.sh <report> [part numbers...]             # surface T, S, elevation and currents per monthly part
```

- **Section video:** made from the run's hourly section file (`stations_section_<tag>.nc`) and the D-2
  and D-3 casts. It shows the daily-mean S, T and velocity along the Drammensfjord path, plus the
  velocity profile on the Svelvik sill. Its default is 15 frames per second.
- **Surface videos:** made by `src/surface_videos.jl` from the surface snapshot parts
  (`snapshots_surface_<tag>_part<N>.jld2`). It is copied from FjordSim's `scripts/surface_videos.jl`, but
  takes the run's `bathymetry.nc` and `report.toml`'s `run_start` instead of the run's setup file. Each part
  is about 1 GB and is pulled, drawn and deleted in turn, taking about 27 min.

### `report.toml`

```toml
run = "oslofjorden_2026-11-10"          # data/runs/<run>
run_start = 2024-10-01T00:00:00         # the run's start_date: the time origin of its station files
start = 2024-10-01T00:00:00             # the window drawn
spinup = 2024-11-01T00:00:00            # scored from here
stop = 2026-10-01T00:00:00
niva_casts = "niva_ctd_odm2_2024-2026"  # folders in data/inputs/observations/
imr_casts = "imr_ctd_2024-2026"
# stamp = "20261107T210205"             # only if data/runs/<run>/results holds more than one run log
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

Both Python fetchers need their API keys in `~/.config/niva-data/`. Kartverket's monthly files are read by
`kartverket_series` in `src/tides.jl`.

## Origin

The scripts come from the full-period report of run `20261107T210205`, which was archived as
`oslofjorden_2026-11-10`. That report's output is `output/oslofjorden_2026-11-10/`. Its scripts were
rerun here and gave the same tables and the same PDF text.
