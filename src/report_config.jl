# The report named by the environment variable REPORT: its settings `reports/<REPORT>/report.toml`, the run
# it validates in `data/runs/<run>/`, and its output folder `output/<REPORT>/`: `figures/`, `tables/` (the
# results), `data/` (what one script hands to the next: extracts, model columns, cells, pairs) and `video/`.
@isdefined(PROJECT) || include("paths.jl")
using Dates, TOML

const REPORT_NAME = get(ENV, "REPORT") do
    error("set REPORT to a folder name in reports/, e.g. REPORT=oslofjorden_2026-11-10")
end
const CONFIG = TOML.parsefile(joinpath(PROJECT, "reports", REPORT_NAME, "report.toml"))
const RES = joinpath(RUNS, CONFIG["run"], "results")      # what the run wrote: station files and its log
const RUN_SETUP = joinpath(RUNS, CONFIG["run"], "setup")  # its setup file, bathymetry and rivers
const REPORT = joinpath(PROJECT, "output", REPORT_NAME)
const FIG = joinpath(REPORT, "figures")
const TABLES = joinpath(REPORT, "tables")
const REPORT_DATA = joinpath(REPORT, "data")
foreach(mkpath, (FIG, TABLES, REPORT_DATA))

"The run's tag: `stamp` in report.toml, else the one `fjordsim_<stamp>.log` in the run folder."
function run_stamp()
    haskey(CONFIG, "stamp") && return CONFIG["stamp"]
    stamps = [m[1] for m in (match(r"^fjordsim_(\d{8}T\d{6})\.log$", f) for f in readdir(RES)) if !isnothing(m)]
    length(stamps) == 1 || error("$(RES) holds $(length(stamps)) run logs; set `stamp` in report.toml")
    return only(stamps)
end
const STAMP = run_stamp()

# The run starts at RUN_START, the time origin of its station files; the window validated is START to STOP,
# scored from SPINUP: the first weeks are the adjustment from the initial state.
const RUN_START = DateTime(CONFIG["run_start"])
const START = DateTime(CONFIG["start"])
const SPINUP = DateTime(CONFIG["spinup"])
const STOP = DateTime(CONFIG["stop"])
const DAYS_LABEL = "days since $(Date(START))"
