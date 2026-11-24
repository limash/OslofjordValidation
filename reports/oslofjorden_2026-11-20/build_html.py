"""The report page of run oslofjorden_2026-11-20: output/oslofjorden_2026-11-20/oslofjorden_2026-11-20.html.

    bin/build_html.sh oslofjorden_2026-11-20

For a new run, copy this file and rewrite the text. The setup table is copied by hand from the run's setup file
(data/runs/<run>/setup/*.jl), the reasons for its choices from the comments there; the time step and wall time
come from the run log. Every result number is read from output/<report>/tables/ and data/; the sentences around
them, and the summary, are this run's.
"""

import math
import re
import statistics
from datetime import datetime, timedelta

from html_report import CONFIG, HERE, PROJECT, Page, plain, read, signed, thousands

NAME = {
    "fjordsim": "FjordSim",
    "norkyst160": "NorKyst v3 160 m",
    "norkyst800": "NorKyst v3 800 m",
    "norfjords": "NorFjords 160 m",
}
REFERENCES = ("norkyst160", "norkyst800", "norfjords")
RUN_DIR = PROJECT / "data" / "runs" / CONFIG["run"]
START, SPINUP, STOP = (str(CONFIG[k])[:10] for k in ("run_start", "spinup", "stop"))
# The run's second year starts a year after it does.
YEAR2 = f"{int(START[:4]) + 1}{START[4:]}"
MONTHS = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
]
# The depth bands of the scores, named once and used so throughout.
LAYER = {
    "0-5 m": "surface layer (0–5 m)",
    "5-20 m": "upper layer (5–20 m)",
    "20-50 m": "intermediate layer (20–50 m)",
    ">50 m": "deep layer (below 50 m)",
}


def month_name(ym):
    """'2026-07' as 'July 2026'."""
    return f"{MONTHS[int(ym[5:7]) - 1]} {ym[:4]}"


# --- the run logs, one per launch: tags, wall time, mean time step, restart ------------------------------------
# The run was resumed from a checkpoint, so it has one log and one tag per launch.
LOGS = sorted((RUN_DIR / "results").glob("fjordsim_*.log"))
STAMPS = [p.stem.split("_")[1] for p in LOGS]
logs = [p.read_text() for p in LOGS]
UNIT_S = {"seconds": 1, "minutes": 60, "hours": 3600, "days": 86400}
# Each progress line gives the wall time since the last one; a resumed launch's first line counts from the
# checkpoint's own clock (over a day), so it is left out.
WALL_DAYS = (
    sum(
        x
        for log in logs
        for v, u in re.findall(r"wall time: ([\d.]+) (seconds|minutes|hours|days)", log)
        if (x := float(v) * UNIT_S[u]) < 86400
    )
    / 86400
)
iterations, model_days = re.findall(r"Iter: (\d+), time: ([\d.]+) days", logs[-1])[-1]
MEAN_DT = float(model_days) * 86400 / int(iterations)
# The second launch's first progress line: the model day it picked up from.
RESTART_DAY = float(re.search(r"Iter: \d+, time: ([\d.]+) days", logs[1])[1])
RUN_ID = (RUN_DIR / "setup" / "run_id").read_text().strip()
# The run logs name only the image `fjordsim:latest`, built from a working tree on 2026-11-16 and committed
# as this commit the next morning; its examples/oslofjorden/oslofjorden.jl is the run's setup file.
FJORDSIM_COMMIT = "ae8960012b012cb7b8d638e32ef44202dad2c755"
RESTART_DATE = str(datetime.fromisoformat(START) + timedelta(days=RESTART_DAY))[:10]
N_HYDROGRAPHY = len(
    list((RUN_DIR / "results").glob(f"stations_hydrography_{STAMPS[0]}_*.nc"))
)

# --- the CTD pairs ----------------------------------------------------------------------------------------------
PAIRS = [
    r
    for r in read("ctd_pairs.csv")
    if r["time"] >= SPINUP and not r["station"].endswith("-FB")
]


def error(r, k, v):
    return float(r[f"{k}_{v}"]) - float(r[f"obs_{v}"])


def stats(rows, k, v, joint=()):
    """Samples, bias and RMSE of model `k` on `rows`, where `k` and every model in `joint` have a value; NaN
    with fewer than three samples."""
    e = [
        error(r, k, v)
        for r in rows
        if all(math.isfinite(error(r, m, v)) for m in (k, *joint))
    ]
    if len(e) < 3:
        return len(e), math.nan, math.nan
    return len(e), sum(e) / len(e), math.sqrt(sum(x * x for x in e) / len(e))


def skill(k, var, band="all", group="ALL"):
    """FjordSim's row (k = "fjordsim", every sample) or FjordSim beside reference model `k`."""
    rows = read("ctd_skill_fjordsim.csv" if k == "fjordsim" else f"ctd_skill_{k}.csv")
    return next(
        r
        for r in rows
        if r["group"] == group and r["variable"] == var and r["band"] == band
    )


def br(r, k):
    return f"{signed(r[k + '_bias'])} / {plain(r[k + '_rmse'])}"


casts = {(r["station"], r["time"]) for r in PAIRS}
n_stations = len({r["station"] for r in PAIRS})
n_samples = int(skill("fjordsim", "S")["n"])
last_cast = max(r["time"] for r in PAIRS)[:10]
grid = {
    r["station"]: "norkyst" + r["grid"].rstrip("m") for r in read("norkyst_points.csv")
}
scored = sorted({r["station"] for r in PAIRS})
on_800 = [s for s in scored if grid[s] == "norkyst800"]
on_160 = [s for s in scored if grid[s] == "norkyst160"]
nf_points = {r["station"]: r for r in read("norfjords_points.csv")}
on_nf = {r["station"] for r in PAIRS if math.isfinite(float(r["norfjords_S"]))}
# Project 6302 is the Inner Oslofjord programme.
STATIONS_CSV = (
    PROJECT / "data" / "inputs" / "observations" / CONFIG["niva_casts"] / "stations.csv"
)
INNER = {
    l.split(",")[0]
    for l in STATIONS_CSV.read_text().splitlines()[1:]
    if l.split(",")[-1] == "6302"
}
nk_points = {r["station"]: r for r in read("norkyst_points.csv")}
cells = {r["station"]: r for r in read("cells.csv")}

# The overall scores, FjordSim beside each reference model.
s160, s800, snf = (skill(k, "S") for k in REFERENCES)
t160, t800, tnf = (skill(k, "T") for k in REFERENCES)

# The two years, FjordSim on every sample.
year = {
    y: [r for r in PAIRS if lo <= r["time"] < hi]
    for y, lo, hi in (("1", SPINUP, YEAR2), ("2", YEAR2, "9999"))
}
yr = {(y, v): stats(year[y], "fjordsim", v) for y in year for v in "ST"}
yr_deep_T = {
    y: stats([r for r in year[y] if float(r["depth"]) >= 50], "fjordsim", "T")
    for y in year
}

# Spring 2026 below 50 m, by month: FjordSim on every sample, NorKyst 160 m beside it.
spring = ["2026-03", "2026-04", "2026-05"]
deep = {
    m: [r for r in PAIRS if r["time"][:7] == m and float(r["depth"]) >= 50]
    for m in spring
}
spring_fs = [stats(deep[m], "fjordsim", "T")[1] for m in spring]
spring_nk = [stats(deep[m], "norkyst160", "T")[1] for m in spring]
# The March 2026 casts below 40 m at the profile stations: each station's mean, observed and modelled.
march = {
    s: [
        r
        for r in PAIRS
        if r["station"] == s and r["time"][:7] == "2026-03" and float(r["depth"]) >= 40
    ]
    for s in CONFIG["profile_stations"]
    if s != "D-2"
}
march_mean = lambda k: [
    mean([float(r[f"{k}_T"]) for r in v if math.isfinite(error(r, "fjordsim", "T"))])  # noqa: E731
    for v in march.values()
]


def station_band(k, s, v, lo, hi):
    return stats(
        [r for r in PAIRS if r["station"] == s and lo <= float(r["depth"]) < hi], k, v
    )[1]


# Deep and surface series on the cast days (basin_drift.csv, surface_drift.csv).
drift = read("basin_drift.csv")


def series(s, d, v, k, lo="0000", hi="9999"):
    return [
        float(r[k])
        for r in drift
        if r["station"] == s
        and r["depth"] == d
        and r["variable"] == v
        and lo <= r["date"] < hi
        and math.isfinite(float(r[k]))
    ]


def span(x, digits=1):
    lo, hi = plain(min(x), digits), plain(max(x), digits)
    return lo if lo == hi else f"{lo}–{hi}"


def mean(x):
    return sum(x) / len(x)


surface = read("surface_drift.csv")


def surface_bias(s, k):
    e = [
        float(r[k]) - float(r["obs"])
        for r in surface
        if r["station"] == s
        and r["variable"] == "S"
        and r["date"] >= SPINUP
        and math.isfinite(float(r[k]))
    ]
    return sum(e) / len(e)


# Inner-basin temperature after the missed February 2026 inflow: casts minus FjordSim, March to July.
missed = [
    float(r["obs"]) - float(r["fjordsim"])
    for r in drift
    if (r["station"], r["depth"]) in (("Dk1", "60"), ("Fl1", "100"))
    and r["variable"] == "T"
    and "2026-03" <= r["date"] < "2026-08"
]
dk1_feb = next(
    r
    for r in drift
    if r["station"] == "Dk1"
    and r["depth"] == "60"
    and r["variable"] == "S"
    and r["date"][:7] == "2026-02"
)
ep_s, ep_t = (
    series("Ep1", "120", "S", "fjordsim"),
    series("Ep1", "120", "T", "fjordsim"),
)
d2 = series("D-2", "100", "S", "fjordsim")
d2_T_err = max(
    abs(float(r["fjordsim"]) - float(r["obs"]))
    for r in drift
    if (r["station"], r["depth"], r["variable"]) == ("D-2", "100", "T")
    and math.isfinite(float(r["fjordsim"]) - float(r["obs"]))
)

strat = {
    k: {r["group"]: r for r in read(f"stratification_skill_{k}.csv")}
    for k in REFERENCES
}
# Taylor and target statistics per depth layer (taylor_target.csv): FjordSim (m = "fjordsim") or reference model
# m = k, on the samples both have.
pattern = {
    (r["reference"], r["model"], r["variable"], int(r["layer"])): r
    for r in read("taylor_target.csv")
}
PATTERN_REFS = sorted({k for k, *_ in pattern}, key=list(REFERENCES).index)
layers_of = lambda k, v: sorted({l for k_, _, v_, l in pattern if (k_, v_) == (k, v)})  # noqa: E731
pat = lambda k, m, v, l, c: float(pattern[(k, m, v, l)][c])  # noqa: E731
corr = lambda k, m, v, l: pat(k, m, v, l, "correlation")  # noqa: E731
sd_ratio = lambda k, m, v, l: pat(k, m, v, l, "model_std") / pat(k, m, v, l, "obs_std")  # noqa: E731
norm_bias = lambda k, m, v, l: pat(k, m, v, l, "bias") / pat(k, m, v, l, "obs_std")  # noqa: E731
norm_rmse = lambda k, m, v, l: (
    math.hypot(pat(k, m, v, l, "centred_rmse"), pat(k, m, v, l, "bias")) / pat(k, m, v, l, "obs_std")
)  # noqa: E731
edges = {int(r["layer"]): (float(r["top_m"]), float(r["bottom_m"])) for r in pattern.values()}
metres = lambda z: f"{z:g}"  # noqa: E731
layer_span = lambda l: f"{metres(edges[l][0])}–{metres(edges[l][1])} m"  # noqa: E731
# Temperature in the layers from 50 m down: every model's σ_model/σ_obs.
deep_layers = {k: [l for l in layers_of(k, "T") if edges[l][0] >= 50] for k in PATTERN_REFS}
deep_top = min(edges[l][0] for k in PATTERN_REFS for l in deep_layers[k])
deep_sd = [sd_ratio(k, m, "T", l) for k in PATTERN_REFS for l in deep_layers[k] for m in ("fjordsim", k)]
# Target per station (target_stations.csv): each model on every cast it has, one point per station.
per_station = read("target_stations.csv")
station_pts = lambda m, v: [r for r in per_station if r["model"] == m and r["variable"] == v]  # noqa: E731
inside = lambda m, v: sum(math.hypot(float(r["x"]), float(r["y"])) < 1 for r in station_pts(m, v))  # noqa: E731
too_high = lambda m, v: sum(float(r["y"]) > 0 for r in station_pts(m, v))  # noqa: E731
median_bias = lambda m, v: statistics.median(float(r["y"]) for r in station_pts(m, v))  # noqa: E731
too_variable = lambda m, v: [r["station"] for r in station_pts(m, v) if float(r["x"]) > 0]  # noqa: E731
outside = lambda m, v: [r["station"] for r in station_pts(m, v) if math.hypot(float(r["x"]), float(r["y"])) >= 1]  # noqa: E731
one_cast = {s for s in scored if len({t for st, t in casts if st == s}) == 1}


def diagram_stations(k):
    """The stations of reference model `k`'s diagram column: where it and FjordSim both have a cast value."""
    ok = lambda r, v: all(
        math.isfinite(float(r[f"{m}_{v}"])) for m in ("obs", "fjordsim", k)
    )  # noqa: E731
    return {r["station"] for r in PAIRS if ok(r, "S") or ok(r, "T")}


def by_region(stations):
    """`stations` split into the Inner Oslofjord, the Drammensfjord (D-2, D-3) and the outer fjord; "all <n>" where
    every scored station of a region is in."""
    drammen = {"D-2", "D-3"}
    regions = (INNER, drammen, set(scored) - INNER - drammen)
    return [
        f"all {len(region)}"
        if region <= stations
        else ", ".join(sorted(stations & region)) or "–"
        for region in regions
    ]


# Bias by month and depth band, each model on every sample it reaches (ctd_bias_monthly.csv).
monthly = {
    (r["model"], r["variable"], r["band"], r["month"]): float(r["bias"])
    for r in read("ctd_bias_monthly.csv")
}
fs_top_T = {
    m: b
    for (k, v, band, m), b in monthly.items()
    if (k, v, band) == ("fjordsim", "T", "0-5 m")
}
warmest, coldest = max(fs_top_T, key=fs_top_T.get), min(fs_top_T, key=fs_top_T.get)
summer25 = [fs_top_T[m] for m in ("2025-06", "2025-07", "2025-08")]
months_of = lambda k, v, b: {
    m: x for (k_, v_, b_, m), x in monthly.items() if (k_, v_, b_) == (k, v, b)
}  # noqa: E731
fs_deep_cold = sum(x < 0 for x in months_of("fjordsim", "T", ">50 m").values())
n_months = len(months_of("fjordsim", "T", ">50 m"))
# Months each model is too salty in both the surface and the upper layer, of the months it has both.
salty = {
    k: (
        sum(
            months_of(k, "S", "0-5 m")[m] > 0 and months_of(k, "S", "5-20 m")[m] > 0
            for m in both
        ),
        len(both),
    )
    for k in NAME
    for both in [set(months_of(k, "S", "0-5 m")) & set(months_of(k, "S", "5-20 m"))]
}

# Below 50 m where NorKyst v3 800 m, FjordSim's boundary source, has values (boundary_deep.csv).
boundary = read("boundary_deep.csv")
bnd = {(r["source"], r["variable"], r["month"]): r for r in boundary}
bnd_T = [r for r in boundary if r["variable"] == "T"]
bnd_close = [
    r
    for r in bnd_T
    if abs(float(r["fjordsim_bias"]) - float(r["norkyst800_bias"])) < 0.5
]

# IMR's casts (imr_pairs.csv, imr_skill_*.csv).
imr_pairs = [r for r in read("imr_pairs.csv") if r["time"] >= SPINUP]
imr_casts = {(r["station"], r["time"]) for r in imr_pairs}
imr_each = {
    (r["station"], r["variable"], r["band"]): r for r in read("imr_skill_each.csv")
}
imr_vs = {
    k: {(r["station"], r["variable"], r["band"]): r for r in read(f"imr_skill_{k}.csv")}
    for k in REFERENCES
}

# Svelvik strait currents (svelvik_currents.csv, svelvik_outflow.csv).
sv = read("svelvik_currents.csv")
sv_obs = [r for r in sv if r["source"] == "observed"]
sv_fs = [r for r in sv if r["source"] == "fjordsim"]
STRAIT = sv_fs[0]["station"]
f = lambda r, k: float(r[k])  # noqa: E731
sv_turn = next(
    (a, b) for a, b in zip(sv_fs, sv_fs[1:]) if f(a, "mean_ms") > 0 >= f(b, "mean_ms")
)
obs_turn = next(
    (a, b) for a, b in zip(sv_obs, sv_obs[1:]) if f(a, "mean_ms") > 0 >= f(b, "mean_ms")
)
sv_top = [r for r in sv_fs if f(r, "depth_m") <= 5]
obs_top = [r for r in sv_obs if f(r, "depth_m") <= 5]
uq_ratio = mean([f(r, "upper_quartile_ms") for r in sv_top]) / mean(
    [f(r, "upper_quartile_ms") for r in obs_top]
)
over_13 = max(f(r, "fraction_over_1.3ms") for r in sv_fs)
outflow = read("svelvik_outflow.csv")
outflow_r = statistics.correlation(
    [f(r, "outflow_0_3.7m_ms") for r in outflow],
    [f(r, "drammenselva_m3s") for r in outflow],
)

# Sea level and tide.
GAUGES = ("Viker", "Oscarsborg", "Oslo")
CONSTITUENTS = ("M2", "S2", "N2", "O1", "K1", "M4")
tides = {(r["station"], r["constituent"]): r for r in read("tides.csv")}
tides_nf = {
    (r["station"], r["constituent"]): r for r in read("tides_norfjords_2024.csv")
}
level = read("waterlevel.csv")
level_daily = read("waterlevel_daily.csv")
fs = [r for r in level if r["model"] == "FjordSim"]
nk = [r for r in level if r["model"].startswith("NorKyst")]
nfd = [r for r in level_daily if r["model"].startswith("NorFjords")]
fsd = [r for r in level_daily if r["model"] == "FjordSim"]
pct = lambda rows: span(
    [
        100
        * float(r["std_ratio_residual" if "std_ratio_residual" in r else "std_ratio"])
        for r in rows
    ],
    0,
)  # noqa: E731
rr = lambda rows, k: span([float(r[k]) for r in rows], 2)  # noqa: E731
m2 = [tides[(g, "M2")] for g in GAUGES]
m2_nf = [tides_nf[(g, "M2")] for g in GAUGES]
m2_off = max(abs(float(r["fjordsim_cm"]) - float(r["kartverket_obs_cm"])) for r in m2)
m2_phase = max(abs(float(r["fjordsim_minus_obs_phase_deg"])) for r in m2)
too_large = lambda rows, k: span(
    [100 * (float(r[k]) / float(r["kartverket_obs_cm"]) - 1) for r in rows], 0
)  # noqa: E731
viker = tides[("Viker", "M2")]
# λ in 5-day windows (waterlevel_lambda.csv): the share of windows each model scores good, and how many of
# FjordSim's misses NorKyst shares at the same gauge.
lam = read("waterlevel_lambda.csv")
good = lambda model: (
    100 * mean([r["class"] == "good" for r in lam if r["model"].startswith(model)])
)  # noqa: E731
fs_miss = {
    (r["station"], r["window_start"])
    for r in lam
    if r["model"] == "FjordSim" and r["class"] != "good"
}
nk_miss = {
    (r["station"], r["window_start"])
    for r in lam
    if r["model"].startswith("NorKyst") and r["class"] != "good"
}
calm = lambda good_: statistics.median(
    float(r["obs_std_m"])
    for r in lam
    if r["model"] == "FjordSim"  # noqa: E731
    and (r["class"] == "good") == good_
)

sill = {r["depth_m"]: r for r in read("sill_exchange.csv") if r["station"] == "DS-53"}
sills = read("sills.csv")
grid_cells = read("grid_cells.csv")[0]

# Surface videos: video/surface/<stem>_part<N>_<variable>.mp4, part N being the run's Nth month.
VARIABLES = (
    ("temperature", "Temperature"),
    ("salinity", "Salinity"),
    ("elevation", "Sea level"),
    ("currents", "Currents"),
)
videos = sorted((HERE / "video" / "surface").glob("*_part*_*.mp4"))
part_of = lambda p: int(re.search(r"_part(\d+)_", p.name)[1])  # noqa: E731
parts = sorted({part_of(p) for p in videos})


def month_of(part):
    m = int(START[5:7]) - 1 + part - 1
    return f"{MONTHS[m % 12]} {int(START[:4]) + m // 12}"


sources = {
    label: {
        month_of(part_of(p)): f"video/surface/{p.name}"
        for p in videos
        if p.stem.endswith("_" + v)
    }
    for v, label in VARIABLES
}

FIGURES = [
    "surface",
    "map",
    "scatter",
    "taylor",
    "target",
    "target_stations",
    "bias",
    "monthly",
    "stratification",
    "surface_drift",
    "basin_drift",
    "hovmoller",
    "boundary",
    "profiles",
    "imr",
    "section",
    "svelvik",
    "tide",
    "residual",
    "lambda",
]
page = Page(
    "Validation of FjordSim's Oslofjord simulation",
    f"Run {CONFIG['run']} (tags {' and '.join(STAMPS)}) · NIVA and IMR casts, Kartverket tide gauges, NorKyst v3 and NorFjords",
    FIGURES,
)
F = page.fig
dr = "Drammensfjord"
deep_cold = [
    s
    for s in ("Fl1", "Ej1", "Dk1", "Dm1", "Ep1", "Cq1", "Cp2")
    if station_band("fjordsim", s, "T", 50, 1e9) <= -1.2
]

# ================================================================================================================
page.h2("abstract", "Abstract", numbered=False)
page.p(
    f"FjordSim ran the Oslofjord on a 160 m grid from {START} to {STOP}. We score it against observations: "
    f"{len(casts)} NIVA casts, {len(imr_casts)} IMR casts and three tide gauges and other Oslofjord models: NorKyst v3 160 m, "
    f"NorKyst v3 800 m and NorFjords 160 m. FjordSim has the lowest salinity RMSE of all four models "
    f"({plain(s160['fjordsim_rmse'])} against {plain(s160['norkyst160_rmse'])} g/kg for NorKyst v3 160 m on the same "
    f"samples) and is the only one that keeps the Drammensfjord's brackish surface layer. NorKyst v3 160 m has the "
    f"lower temperature RMSE ({plain(t160['norkyst160_rmse'])} against {plain(t160['fjordsim_rmse'])} °C). FjordSim "
    f"misses the February 2026 inflow to the Inner Oslofjord, and its deep layer is too cold in spring 2026; that "
    f"cold water is in NorKyst v3 800 m, its boundary source, too. The sill basins start from the NIVA casts, but "
    f"their deep water freshens through the run. The tide is right to {m2_off:.1f} cm in M2."
)

page.h2("surface", "Modelled surface fields", numbered=False)
page.video_switch(
    "surface",
    sources,
    [month_of(p) for p in parts],
    f"Hourly surface temperature, salinity, sea level and currents, "
    f"{month_of(parts[0])}{'' if len(parts) == 1 else ' to ' + month_of(parts[-1])}.",
)

# ================================================================================================================
page.h2("simulation", "The simulation")
page.p(
    f'<a href="https://github.com/NIVANorge/FjordSim.jl">FjordSim</a> builds and runs fjord models with '
    f'<a href="https://github.com/CliMA/Oceananigans.jl">Oceananigans</a>, a flexible Julia package for finite volume simulations that runs on CPUs and GPUs (<a href="#references">Ramadhan et al., 2020</a>). '
    f"This run covers the Oslofjord from the Skagerrak to Oslo ({F('map')}) for two years. "
)
page.p("Table 1 provides an overview of each setting.")
page.table(
    ["", "Setting"],
    [
        [
            "Period",
            f"{START} to {STOP}. Scores start on {SPINUP}: the first month is the adjustment from the initial state.",
        ],
        [
            "Domain",
            "10.00–11.20 °E, 58.95–59.93 °N. One open boundary, along the southern edge.",
        ],
        ["Horizontal grid", "424 × 681 cells of 160 m, longitude–latitude."],
        [
            "Vertical grid",
            "39 z-levels, partial bottom cells. Layer interfaces (m): 0, 1, 2.2, 3.7, 5.5, 7.9, 10.8, 14.5, 19, "
            "25, 32, 41, 46.06, 51.11, 56.17, 61.22, 66.28, 71.33, 76.39, 81.44, 86.5, 91.56, 96.61, 101.67, "
            "106.72, 111.78, 116.83, 121.89, 126.94, 132, 165.5, 199, 232.5, 266, 299.5, 333, 366.5, 400, "
            "433.5, 467.",
        ],
        [
            "Cells",
            f"{int(grid_cells['nx']) * int(grid_cells['ny']) * int(grid_cells['nz']):,} in total, "
            f"{int(grid_cells['wet_cells']):,} of them water ({int(grid_cells['wet_columns']):,} water columns).",
        ],
        [
            "Bathymetry",
            f"Kartverket's soundings (Geonorge Dybdedata), gridded at 40 m. Minimum depth 2 m, slopes limited, "
            f"sills kept: Drøbak {sills[0]['model_m']} m (real {sills[0]['real_m'].split(' ')[0]} m), "
            f"Svelvik {sills[1]['model_m']} m (real 11 m).",
        ],
        [
            "Equations",
            "Hydrostatic, Boussinesq, TEOS-10 equation of state, split-explicit free surface, Coriolis on the sphere.",
        ],
        [
            "Time step",
            f"Adaptive, advective CFL 0.3, at most 3 min; {MEAN_DT:.0f} s on average.",
        ],
        ["Momentum advection", "5th-order WENO, vector-invariant form."],
        [
            "Tracer advection",
            "5th-order WENO; salinity bounded to 0–40 g/kg. First-order upwind within 3 cells of a river mouth. "
            "Where land or the seabed is closer than three cells to a face, temperature falls back to "
            "first-order upwind in the top four cells (to 5.5 m) and to second-order centred below.",
        ],
        [
            "Vertical mixing",
            "CATKE (prognostic turbulent kinetic energy), minimum TKE 7 × 10⁻⁷ m² s⁻².",
        ],
        [
            "Horizontal mixing",
            "Biharmonic viscosity 9.4 × 10³ m⁴ s⁻¹. ",
        ],
        ["Bottom drag", "Quadratic, coefficient 0.003."],
        [
            "Shortwave",
            "Absorbed over depth in two bands: 58 % over 0.35 m, the rest over 3 m. ",
        ],
        [
            "Open boundary",
            "Hourly T, S, u, v and sea level from NorKyst v3 800 m. Relaxation "
            "to the data is 3 h on inflow, 360 days on outflow; a 3.2 km sponge (viscosity 20, diffusivity "
            "10 m² s⁻¹) damps what the boundary radiates. Below 300 m the 300 m value: NorKyst's output stops "
            f"there. The tide is scaled per constituent to the Viker gauge: NorKyst v3 800 m's "
            f"M2 at the boundary is {viker['norkyst800_boundary_cm']} cm against {viker['kartverket_obs_cm']} cm "
            "observed at Viker (M2 × 0.70).",
        ],
        [
            "Atmosphere",
            "NORA3 hindcast, hourly, regridded to 0.02°.",
        ],
        [
            "Rivers",
            "NVE: 23 mouths, every river of at least 0.5 m³/s, 1212 m³/s in total on average. Glomma (two mouths), "
            "Drammenselva and six small rivers follow gauged discharge; the rest run at their catchment's normal "
            "discharge.",
        ],
        [
            "Sea ice",
            "None. Temperature is held at or above the freezing point.",
        ],
        [
            "Initial state",
            f"NorKyst v3 on {START}: the 160 m Oslofjord nest (m71), which covers the domain, the 800 m "
            "run (m00) elsewhere. Over the sill basins of the Inner Oslofjord and the Drammensfjord, the NIVA "
            "casts nearest the start (within 14 days) replace whole columns. In the Drøbak Sound (Im2), it is only the "
            "water below the sill that is replaced. Reason: NorKyst's columns end above the basins' deep water there, and the water "
            "was up to 1.9 g/kg too salty and 2.3 °C too cold.",
        ],
        [
            "Output",
            f"Daily 3D T, S, u, v and TKE; hourly surface fields; hourly profiles at {N_HYDROGRAPHY} stations and at 77 points "
            "along the Drammensfjord; hourly velocity at 7 current-meter sites; sea level every 10 min at 3 gauges.",
        ],
        [
            "Cost",
            f"{WALL_DAYS:.1f} days on one NVIDIA L4 GPU. Output writing took a quarter of the time.",
        ],
    ],
    caption="<b>Table 1.</b> Model setup.",
)
page.p(
    f"NORA3 overstates the solar radiation: it warmed NorKyst v3's summer surface by up to 0.7–0.8 °C in 2012–2020 "
    f'(<a href="#references">Christensen et al., 2026</a>). FjordSim\'s surface layer is not too warm in summer 2025 '
    f"(June to August: {', '.join(signed(x, 1) for x in summer25)} °C)."
)

# ================================================================================================================
page.h2("data", "Validation data")
page.h3("Observations")
page.figure(
    "map",
    "figures/map.png",
    "Model depth and the stations. Green circles: NIVA cast stations; orange diamonds: IMR stations; "
    "squares: tide gauges; blue triangles: river inflow columns, with the main rivers named; "
    "red line: open boundary.",
    fit=True,
)
page.table(
    ["Source", "What", "Period", "Size"],
    [
        [
            "NIVA CTD casts (ODM2)",
            "T and S every 1 m; Inner Oslofjord (Fagrådet) and Outer Oslofjord monitoring",
            f"{SPINUP} to {last_cast}",
            f"{n_stations} stations, {len(casts)} casts, {thousands(n_samples)} samples",
        ],
        [
            "IMR CTD casts (Vannmiljø)",
            "T and S at fixed depths from 0 to 440 m, dated by day; ØkoKyst and Tisler",
            f"{SPINUP} to {max(r['time'] for r in imr_pairs)[:10]}",
            f"{len({r['station'] for r in imr_pairs})} stations, {len(imr_casts)} casts, {thousands(len(imr_pairs))} samples",
        ],
        [
            "Kartverket tide gauges",
            "Sea level every 10 min",
            f"{SPINUP} to {STOP}",
            "Viker, Oscarsborg, Oslo",
        ],
        [
            "ADCP in the Svelvik strait",
            "Current at 1–11 m: one month's mean and upper quartile",
            "1999",
            '<a href="#references">Staalstrøm and Hjelmervik (2017)</a>, Table 1',
        ],
    ],
    caption="<b>Table 2.</b> Observations.",
)
page.p(
    "The ADCP month is from 1999, so it gives the strait's typical currents, not those of this run's period."
)

page.h3("Reference models")
page.p(
    "This report uses 3 reference models: NorKyst v3 160 m, NorKyst v3 800 m and NorFjords 160 m. "
    "NorKyst v3 160 m and NorKyst v3 800 m are separate simulations. The 160 m nest runs two-way nested in its "
    "own 800 m parent, which is not the 800 m run used here. Each station is read from the 160 m nest where it "
    "covers the station, else from the 800 m run. So every station has values from one NorKyst model only "
    f"(800 m: {', '.join(on_800)})."
)
# NorKyst v3: Christensen et al. (2026), GMD 19, 2785. Its 160 m nest's settings are not given apart from the
# 800 m system's (*). NorFjords: IMR's archive metadata, and IMR's reports for its boundary.
A = "As 800 m*"
NP = "Not published"
page.table(
    ["", "FjordSim", "NorKyst v3 160 m", "NorKyst v3 800 m", "NorFjords 160 m"],
    [
        ["Producer", "NIVA", "MET Norway", "MET Norway", "IMR"],
        ["Code", "Oceananigans", "ROMS", "ROMS", "ROMS 3.9"],
        [
            "Product",
            "This hindcast",
            "Operational forecast, member m71, first day of each forecast",
            "Operational forecast, member m00, first day of each forecast",
            "Hindcast A01 (v3)",
        ],
        [
            "Domain",
            "Oslofjord, 10.0–11.2 °E, 58.95–59.93 °N",
            "Oslofjord, 9.9–11.4 °E, 59.24–60.03 °N",
            "Norwegian coast",
            "Skagerrak coast, 8.2–12.0 °E, 57.7–60.1 °N",
        ],
        [
            "Horizontal grid",
            "160 m, 424 × 681",
            "160 m, 417 × 377",
            "800 m, 2747 × 1148",
            "160 m, 1501 × 721",
        ],
        [
            "Vertical grid",
            "39 z-levels; 1 m at the surface",
            A,
            "40 terrain-following levels; 0.1–1 m at the surface",
            "40 terrain-following levels; minimum depth 10 m",
        ],
        [
            "Vertical mixing",
            "CATKE",
            A,
            "GLS, k–ε, Canuto-A stability functions",
            "GLS",
        ],
        [
            "Tracer advection",
            "5th-order WENO",
            A,
            "3rd-order upwind (T), HSIMT (S)",
            "3rd-order upstream",
        ],
        [
            "Horizontal mixing",
            "Biharmonic viscosity; no tracer diffusion",
            A,
            "No interior viscosity; tracer diffusivity 10 m² s⁻¹",
            NP,
        ],
        [
            "Atmosphere",
            "NORA3 (3 km), hourly",
            A,
            "AROME-MetCoOp (2.5 km), hourly",
            "AROME",
        ],
        [
            "Open boundary",
            "NorKyst v3 800 m (m00), hourly; tide corrected to Viker",
            "Two-way nested (5:1) in its own 800 m parent, not in m00",
            "CMEMS Arctic and Baltic models, daily means; TPXO9 tides",
            "NorKyst-800, version not published",
        ],
        [
            "Rivers",
            "NVE: 23 mouths, 8 with gauged discharge",
            A,
            "NVE daily runoff spread over 247 rivers",
            NP,
        ],
        [
            "Data assimilation",
            "None",
            A,
            "None (4D-Var runs only in the separate 2.4 km NorKyst-DA)",
            "None",
        ],
        [
            "Output compared",
            "Daily 3D snapshot nearest the cast",
            "Hourly, 15 z-levels to 300 m; hour nearest the cast",
            "Hourly, 15 z-levels to 300 m; hour nearest the cast",
            "Daily means, on the cast's day; ends 2026-06-30",
        ],
        [
            "NIVA stations here",
            f"{len(scored)}",
            f"{len(on_160)}",
            f"{len(on_800)}",
            f"{len(on_nf)}",
        ],
    ],
    caption="<b>Table 3.</b> The four models: FjordSim and 3 reference models.",
)
page.p(
    'Sources: <a href="#references">Christensen et al. (2026)</a> for NorKyst v3; NorFjords\' archive metadata and '
    '<a href="#references">Albretsen et al. (2022)</a> for NorFjords.'
)

basins = (
    ("Bunnefjorden", "Ep1"),
    ("Vestfjorden", "Fl1"),
    ("Steilene", "Dk1"),
    ("Drøbak Sound", "Im2"),
    ("Drammensfjord", "D-2"),
)
page.table(
    [
        "Basin (station)",
        "Deepest cast",
        "FjordSim",
        "NorKyst v3 160 m",
        "NorFjords 160 m",
    ],
    [
        [
            f"{b} ({s})",
            cells[s]["deepest_cast_m"],
            f"{float(cells[s]['model_depth_m']):.0f}",
            f"{float(nk_points[s]['norkyst_depth_m']):.0f}",
            f"{float(nf_points[s]['norfjords_depth_m']):.0f}",
        ]
        for b, s in basins
    ],
    caption="<b>Table 4.</b> Water depth (m) of each model's column in the deep basins. NorKyst v3 160 m "
    "misses the deep water of most basins.",
    numeric=(1, 2, 3, 4),
)

page.h3("Scores")
page.items(
    [
        r"Error is model minus observed, \(e_i = m_i - o_i\), over the \(N\) model–observation pairs; bias is the "
        r"mean error and RMSE the root-mean-square error: "
        r"\[\text{bias} = \frac{1}{N}\sum_{i=1}^{N} e_i, \qquad \text{RMSE} = \sqrt{\frac{1}{N}\sum_{i=1}^{N} e_i^2}.\]",
        "Each reference model is scored beside FjordSim on the samples both have. The sample sets differ: NorKyst's "
        "columns end at its own bottom, NorKyst v3 800 m covers only the outer stations, and NorFjords ends on 2026-06-30.",
        "Depth layers: " + ", ".join(LAYER.values()) + ".",
        "Regions: <i>Outer fjord</i>, the Outer Oslofjord programme; <i>Inner Oslofjord</i>, north of the Drøbak sill; "
        "<i>Drammensfjord</i>, D-2 and D-3.",
        'Sea level is also scored in 5-day windows with the index λ of <a href="#references">Duveiller et al. (2016)</a>, as '
        '<a href="#references">Dalsøren et al. (2020)</a> and <a href="#references">Christensen et al. (2026)</a> score fjord currents. λ is the '
        r"correlation \(r\), lowered for any difference in mean or variance; 1 is perfect. Over a window, "
        r"\[\lambda = 1 - \frac{\frac{1}{N}\sum_{i=1}^{N} e_i^2}{\sigma_m^2 + \sigma_o^2 + (\bar m - \bar o)^2}"
        r"\quad (r \ge 0), \qquad \lambda = 0 \quad (r < 0),\]"
        r"where \(\bar m, \bar o\) are the means and \(\sigma_m, \sigma_o\) the standard deviations of model and "
        "observed sea level. A window is <i>good</i> at "
        "λ ≥ 0.05; below that, <i>poor</i> where the model's mean anomaly over the window has the wrong sign, else "
        "<i>medium</i>.",
    ]
)

# ================================================================================================================
page.h2("results", "Results")
page.h3("Overall scores")
rows = []
r = skill("fjordsim", "S")
t = skill("fjordsim", "T")
rows.append(
    ["All samples", "FjordSim", thousands(r["n"]), br(r, "fjordsim"), br(t, "fjordsim")]
)
for k in REFERENCES:
    r, t = skill(k, "S"), skill(k, "T")
    label = f"Where {NAME[k]} has values" + (
        " (to 2026-06-30)" if k == "norfjords" else ""
    )
    rows.append(
        [label, "FjordSim", thousands(r["n"]), br(r, "fjordsim"), br(t, "fjordsim")]
    )
    rows.append(["", NAME[k], "", br(r, k), br(t, k)])
page.table(
    ["Samples", "Model", "Count", "Salinity (g/kg)", "Temperature (°C)"],
    rows,
    caption="<b>Table 5.</b> Bias / RMSE over all depths, NIVA casts.",
    numeric=(2, 3, 4),
)
page.p(
    f"FjordSim has the lowest salinity RMSE against every reference model: {plain(s160['fjordsim_rmse'])} against "
    f"{plain(s160['norkyst160_rmse'])} g/kg (NorKyst v3 160 m), {plain(s800['fjordsim_rmse'])} against "
    f"{plain(s800['norkyst800_rmse'])} (800 m) and {plain(snf['fjordsim_rmse'])} against {plain(snf['norfjords_rmse'])} "
    f"(NorFjords). In temperature NorKyst v3 160 m is better ({plain(t160['norkyst160_rmse'])} against "
    f"{plain(t160['fjordsim_rmse'])} °C); the 800 m run ({plain(t800['norkyst800_rmse'])} against "
    f"{plain(t800['fjordsim_rmse'])}) and NorFjords ({plain(tnf['norfjords_rmse'])} against {plain(tnf['fjordsim_rmse'])}) "
    f"are about even with FjordSim. All models are too salty in the top 20 m ({F('scatter')}, {F('bias')})."
)
page.p(
    f"The second year is worse than the first. FjordSim's salinity RMSE grows from {plain(yr[('1', 'S')][2])} to "
    f"{plain(yr[('2', 'S')][2])} g/kg and its temperature RMSE from {plain(yr[('1', 'T')][2])} to "
    f"{plain(yr[('2', 'T')][2])} °C. Most of the temperature loss is in the deep layer ({plain(yr_deep_T['1'][2])} to "
    f"{plain(yr_deep_T['2'][2])} °C). Year 1 is {SPINUP} to {YEAR2}, year 2 {YEAR2} to {STOP}."
)
page.figure(
    "scatter",
    "figures/ctd_scatter.png",
    f"Observed against modelled salinity (top) and temperature (bottom), coloured by region. Each model "
    f"on every sample it has, from {SPINUP}.",
)
page.body.append(
    '<a class="explorer" href="scatter_explorer.html"><b>Interactive Scatter Explorer →</b>'
    "Observed against modelled salinity and temperature for any stretch of the Oslofjord and any depth layer: "
    "FjordSim, NorKyst v3 (160 m or 800 m) and NorFjords side by side.</a>"
)
page.p(
    f"Only FjordSim reproduces the brackish surface water of the Drammensfjord: samples observed below 10 g/kg "
    f"lie on the diagonal for FjordSim and at 10–30 g/kg in NorKyst v3 160 m and NorFjords ({F('scatter')}). In its "
    f"surface layer the salinity bias is {signed(skill('norkyst160', 'S', '0-5 m', dr)['fjordsim_bias'], 1)} g/kg in "
    f"FjordSim, NorKyst v3 160 m {signed(skill('norkyst160', 'S', '0-5 m', dr)['norkyst160_bias'], 1)} and NorFjords "
    f"{signed(skill('norfjords', 'S', '0-5 m', dr)['norfjords_bias'], 1)} g/kg."
)

page.h3("Taylor and target diagrams")
page.p(
    f'Both diagrams (<a href="#references">Taylor, 2001</a>; <a href="#references">Jolliff et al., 2009</a>) score '
    f"{len(edges)} depth layers, FjordSim beside one 160 m reference model on the samples both have, so within a panel "
    f"both share each layer's samples and σ_obs. The layers' edges lie on FjordSim's cell faces "
    f"({', '.join(metres(edges[l][0]) for l in sorted(edges))} and {metres(edges[max(edges)][1])} m). A layer with fewer "
    f"than five stations is left out, so the NorKyst v3 160 m panels end at "
    f"{metres(edges[max(layers_of('norkyst160', 'T'))][1])} m. Every statistic is divided by the observed standard deviation σ_obs of those samples. In the Taylor diagram "
    f"({F('taylor')}) the angle is the correlation r and the radius σ_model/σ_obs. The distance to the star "
    f"(the observations) is the centred RMSE, the RMSE with the bias removed. In the target diagram ({F('target')}) "
    f"the vertical axis is the bias, the horizontal one the centred RMSE, negative where the model varies less "
    f"than observed. The distance to the origin is the RMSE; inside the unit circle a model beats the observed mean."
)
page.p(
    "Each column scores different stations (Table 6). σ_obs changes with the stations, and the same error lies "
    "farther out where it is small."
)
page.table(
    ["Column", "Inner Oslofjord", "Drammensfjord", "Outer fjord"],
    [[NAME[k], *by_region(diagram_stations(k))] for k in PATTERN_REFS],
    caption="<b>Table 6.</b> The stations of each column of the Taylor and target diagrams.",
)
page.p("A few disclaimers before reading the diagrams:")
page.items(
    [
        "Within one panel, the comparison is fair: FjordSim and the reference model are scored on exactly the same samples.",
        f"Across panels, the comparison is not fair: the NorKyst v3 160 m panels cover fewer stations (Table 6) and "
        f"end at {metres(edges[max(layers_of('norkyst160', 'T'))][1])} m.",
        "The NorFjords column is the closest to FjordSim's overall score, since it covers all stations. It still stops "
        "at the end of June 2026.",
    ]
)
page.figure(
    "taylor",
    "figures/taylor.png",
    "Taylor diagrams: salinity (top), temperature (bottom); FjordSim beside NorKyst v3 160 m (left) and NorFjords "
    "160 m (right) on the samples both have. Numbers: depth layers from the surface, listed under the panels. "
    "Angle: correlation; radius: σ_model/σ_obs; dashed arcs: centred RMSE / σ_obs; star: observations.",
)
page.body.append(
    '<a class="explorer" href="taylor_explorer.html"><b>Interactive Taylor Explorer →</b>'
    "Correlation and variability of salinity and temperature for any stretch of the Oslofjord and any layering: "
    "FjordSim beside NorKyst v3 160 m and NorFjords.</a>"
)
page.figure(
    "target",
    "figures/target.png",
    "Target diagrams, same layout. Vertical: bias / σ_obs; horizontal: centred RMSE / σ_obs, negative where "
    "the model varies less than observed. Dashed circles: RMSE / σ_obs of 0.5 and 1.",
)
page.body.append(
    '<a class="explorer" href="target_explorer.html"><b>Interactive Target Explorer →</b>'
    "Bias and centred RMSE of salinity and temperature for any stretch of the Oslofjord and any layering: "
    "FjordSim beside NorKyst v3 160 m and NorFjords.</a>"
)
k160, knf = "norkyst160", "norfjords"
# Salinity: the reference models' bias and spread in every layer; FjordSim's sign change in the NorFjords panel.
ref_bias_S = [norm_bias(k, k, "S", l) for k in PATTERN_REFS for l in layers_of(k, "S")]
ref_sd_S = [sd_ratio(k, k, "S", l) for k in PATTERN_REFS for l in layers_of(k, "S")]
fs_bias_S = {l: norm_bias(knf, "fjordsim", "S", l) for l in layers_of(knf, "S")}
flip = min(l for l, b in fs_bias_S.items() if b < 0)
assert min(ref_bias_S) > 0 and max(ref_sd_S) < 1
assert all((b > 0) == (l < flip) for l, b in fs_bias_S.items())
deep_S = max(layers_of(knf, "S"))
page.p(
    f"In salinity both reference models are too salty in every layer, by {span(ref_bias_S, 2)} σ_obs, and too smooth "
    f"(σ_model/σ_obs {span(ref_sd_S, 2)}). FjordSim is too salty above {metres(edges[flip][0])} m "
    f"({span([b for l, b in fs_bias_S.items() if l < flip], 2)} σ_obs) and too fresh below "
    f"(by {span([-b for l, b in fs_bias_S.items() if l >= flip], 2)} σ_obs). Below {metres(edges[flip][0])} m it has the "
    f"observed variability (σ_model/σ_obs {span([sd_ratio(knf, 'fjordsim', 'S', l) for l in fs_bias_S if l >= flip], 2)}, "
    f"NorFjords' {span([sd_ratio(knf, knf, 'S', l) for l in fs_bias_S if l >= flip], 2)}), and at {layer_span(deep_S)} it "
    f"correlates best ({plain(corr(knf, 'fjordsim', 'S', deep_S))} against {plain(corr(knf, knf, 'S', deep_S))} for NorFjords)."
)
# Temperature: the layers from the surface where every model is inside the 0.5 circle, and the layer from which
# every model is too cold and too variable.
pairs_T = [(k, m, l) for k in PATTERN_REFS for l in layers_of(k, "T") for m in ("fjordsim", k)]
calm_T = 0
while calm_T + 1 in edges and all(norm_rmse(k, m, "T", l) < 0.5 for k, m, l in pairs_T if l == calm_T + 1):
    calm_T += 1
cold = min(l for l in edges if all(norm_bias(k, m, "T", x) < 0 and sd_ratio(k, m, "T", x) > 1
                                   for k, m, x in pairs_T if x >= l))
fs_bias_T = [norm_bias(knf, "fjordsim", "T", l) for l in layers_of(knf, "T") if l >= cold]
assert fs_bias_T == sorted(fs_bias_T, reverse=True)
deep_T, deep_nk = max(layers_of(knf, "T")), max(layers_of(k160, "T"))
page.p(
    f"In temperature every model is inside the 0.5 circle down to {metres(edges[calm_T][1])} m. Below "
    f"{metres(edges[cold][0])} m every model is too cold and too variable. FjordSim's cold bias grows with depth to "
    f"{plain(-norm_bias(knf, 'fjordsim', 'T', deep_T))} σ_obs at {layer_span(deep_T)}; NorFjords' stays at "
    f"{span([-norm_bias(knf, knf, 'T', l) for l in layers_of(knf, 'T') if l >= cold], 2)} σ_obs, but it varies more there "
    f"(σ_model/σ_obs {plain(sd_ratio(knf, knf, 'T', deep_T))} against FjordSim's {plain(sd_ratio(knf, 'fjordsim', 'T', deep_T))}). "
    f"At {layer_span(deep_nk)} NorKyst v3 160 m is colder than FjordSim ({plain(norm_bias(k160, k160, 'T', deep_nk))} against "
    f"{plain(norm_bias(k160, 'fjordsim', 'T', deep_nk))} σ_obs) and varies less ({plain(sd_ratio(k160, k160, 'T', deep_nk))} "
    f"against {plain(sd_ratio(k160, 'fjordsim', 'T', deep_nk))})."
)
of_n = lambda f, m, v: f"{f(m, v)} of {len(station_pts(m, v))}"  # noqa: E731
names = lambda xs: ", ".join(xs[:-1]) + " and " + xs[-1] if len(xs) > 1 else "".join(xs)  # noqa: E731
fs_T_out = outside("fjordsim", "T")
page.figure(
    "target_stations",
    "figures/target_stations.png",
    f"Target diagrams per station: salinity (top), temperature (bottom); FjordSim, NorKyst v3 160 m and NorFjords "
    f"160 m, each on all its casts after {SPINUP}, all depths. Each point is one station with at least 10 samples, "
    f"scaled by its own σ_obs. Dashed circles: RMSE / σ_obs of 0.5 and 1.",
)
page.p(
    f"{F('target_stations')} scores FjordSim, NorKyst v3 160 m and NorFjords on all the casts each has, one point "
    f"per station over all depths after {SPINUP}, scaled by that station's σ_obs. In salinity NorKyst v3 160 m and "
    f"NorFjords are too salty at {of_n(too_high, 'norkyst160', 'S')} and {of_n(too_high, 'norfjords', 'S')} "
    f"stations, FjordSim at {of_n(too_high, 'fjordsim', 'S')}. Their median bias is "
    f"{plain(median_bias('norkyst160', 'S'))} and {plain(median_bias('norfjords', 'S'))} σ_obs against FjordSim's "
    f"{plain(median_bias('fjordsim', 'S'))}. FjordSim's RMSE is below σ_obs at {of_n(inside, 'fjordsim', 'S')} "
    f"stations, NorKyst v3 160 m's at {of_n(inside, 'norkyst160', 'S')} and NorFjords' at "
    f"{of_n(inside, 'norfjords', 'S')}. Every model is too smooth at most stations; FjordSim varies too much at "
    f"{names(too_variable('fjordsim', 'S'))}, next to river and harbour outlets."
)
page.p(
    f"In temperature the RMSE is below σ_obs at {of_n(inside, 'fjordsim', 'T')} stations for FjordSim, "
    f"{of_n(inside, 'norkyst160', 'T')} for NorKyst v3 160 m and {of_n(inside, 'norfjords', 'T')} for NorFjords, "
    f"with a small cold bias (median {plain(median_bias('fjordsim', 'T'))} σ_obs for FjordSim)."
    + (f" FjordSim's exception is {names(fs_T_out)}"
       + (", which has a single cast." if set(fs_T_out) <= one_cast else ".") if fs_T_out else "")
)

page.h3("Bias by station and depth")
off_deep = [
    (s, b)
    for s in scored
    for b in (
        station_band("fjordsim", s, "S", 20, 50),
        station_band("fjordsim", s, "S", 50, 1e9),
    )
    if math.isfinite(b) and abs(b) > 0.5
]
off_deep = {s: max((b for t, b in off_deep if t == s), key=abs) for s, _ in off_deep}
nf_inner_S = [
    station_band("norfjords", s, "S", 20, 1e9)
    for s in scored
    if s in INNER and s in on_nf
]
nf_inner_S = [x for x in nf_inner_S if math.isfinite(x)]
nf_deep_T = [station_band("norfjords", s, "T", 50, 1e9) for s in on_nf]
nf_deep_T = [x for x in nf_deep_T if math.isfinite(x)]
page.p(
    f"The surface layer is too salty at nearly every station in every model ({F('bias')}). The largest errors are in "
    f"the Glomma plume at I-1: {signed(station_band('fjordsim', 'I-1', 'S', 0, 5), 1)} g/kg in FjordSim, "
    f"{signed(station_band('norkyst800', 'I-1', 'S', 0, 5), 1)} in NorKyst v3 800 m and "
    f"{signed(station_band('norfjords', 'I-1', 'S', 0, 5), 1)} in NorFjords. Below 20 m FjordSim's salinity is "
    f"within 0.5 g/kg at {len(scored) - len(off_deep)} of {len(scored)} stations; the exceptions are "
    + ", ".join(f"{s} ({signed(b, 1)})" for s, b in sorted(off_deep.items()))
    + f". NorFjords is {span(nf_inner_S)} g/kg too salty below 20 m in the Inner Oslofjord."
)
page.p(
    f"In the deep layer the inner basins are too cold in FjordSim: by 1.2 °C or more at {', '.join(deep_cold)}, most "
    f"at Ep1 ({signed(station_band('fjordsim', 'Ep1', 'T', 50, 1e9), 1)} °C). NorKyst v3 160 m is as cold where its "
    f"columns reach 50 m (Ep1 {signed(station_band('norkyst160', 'Ep1', 'T', 50, 1e9), 1)} °C). NorFjords is within "
    f"{max(map(abs, nf_deep_T)):.1f} °C."
)
page.figure(
    "bias",
    "figures/ctd_bias.png",
    "Mean error by station and depth layer: salinity (top), temperature (bottom). Each model on every sample "
    "it has; grey: no samples. Stations run from the outer fjord (top) to Oslo harbour (bottom).",
)

page.h3("Bias by month")
page.p(
    f"The overall scores hide a seasonal pattern ({F('monthly')}). FjordSim's surface layer is "
    f"{plain(fs_top_T[warmest], 1)} °C too warm in {month_name(warmest)} and {plain(-fs_top_T[coldest], 1)} °C too "
    f"cold in {month_name(coldest)}; NorKyst v3 160 m, on its own samples, is "
    f"{signed(monthly[('norkyst160', 'T', '0-5 m', warmest)], 1)} and {signed(monthly[('norkyst160', 'T', '0-5 m', coldest)], 1)} °C "
    f"in the same months. FjordSim's deep layer is too cold in {fs_deep_cold} of {n_months} months, most in spring "
    f"2026 ({', '.join(signed(x, 1) for x in spring_fs)} °C in March, April and May). The surface and upper layers "
    "are too salty in "
    + ", ".join(f"{salty[k][0]} of {salty[k][1]} months in {NAME[k]}" for k in NAME)
    + "."
)
page.figure(
    "monthly",
    "figures/ctd_bias_monthly.png",
    "Mean error by month and depth layer over every station: salinity (top), temperature (bottom). Each model "
    "on every sample it has; grey: no samples.",
)

page.h3("Stratification")
page.p(
    f"The halocline, S(25 m) − S(1 m), is too weak in every model ({F('stratification')}). On the casts both have, "
    f"FjordSim's is {plain(-float(strat['norkyst160']['ALL']['fjordsim_bias']), 1)} g/kg too weak and NorKyst v3 160 m's "
    f"{plain(-float(strat['norkyst160']['ALL']['norkyst160_bias']), 1)}. The bias (model − observed) is largest in the Drammensfjord: FjordSim "
    f"{signed(strat['norkyst160'][dr]['fjordsim_bias'], 1)}, NorKyst v3 160 m "
    f"{signed(strat['norkyst160'][dr]['norkyst160_bias'], 1)}, NorFjords {signed(strat['norfjords'][dr]['norfjords_bias'], 1)} "
    f"g/kg (FjordSim {signed(strat['norfjords'][dr]['fjordsim_bias'], 1)} on the same casts)."
)
page.figure(
    "stratification",
    "figures/stratification.png",
    "Observed against modelled halocline strength, S(25 m) − S(1 m), one point per cast.",
)

page.h3("Surface water through the run")
page.p(
    f"At D-2 FjordSim keeps the Drammenselva's fresh layer: its 1 m salinity is "
    f"{signed(surface_bias('D-2', 'fjordsim'), 1)} g/kg off on average, NorKyst v3 160 m "
    f"{signed(surface_bias('D-2', 'norkyst160'), 1)} and NorFjords {signed(surface_bias('D-2', 'norfjords'), 1)} "
    f"({F('surface_drift')}). Surface temperature follows the casts in all models."
)
page.figure(
    "surface_drift",
    "figures/surface_drift.png",
    "Salinity (left) and temperature (right) at 1 m, from the outer fjord (top) to Oslo harbour (bottom). "
    "Lines: models, daily; dots: casts.",
)

page.h3("Deep water through the run")
im_lo, im_hi = "2026-02", "2026-07"
page.items(
    [
        f"<b>Bunnefjorden is never renewed.</b> At Ep1, 120 m, FjordSim starts from the cast and its salinity falls "
        f"from {plain(ep_s[0], 1)} to {plain(ep_s[-1], 1)} g/kg; the casts stay at {span(series('Ep1', '120', 'S', 'obs'))}. "
        f"Its temperature falls from {plain(ep_t[0], 1)} to {plain(ep_t[-1], 1)} °C; the casts read "
        f"{span(series('Ep1', '120', 'T', 'obs'))} °C. NorFjords renews the basin and overshoots, up to "
        f"{plain(max(series('Ep1', '120', 'S', 'norfjords')), 1)} g/kg ({F('basin_drift')}).",
        f"<b>The February 2026 inflow is missed.</b> The casts show salty, warm water at Dk1 (60 m) and Fl1 (100 m) from "
        f"February 2026. FjordSim brings in fresher, colder water: at Dk1 on {dk1_feb['date']} it has {plain(dk1_feb['fjordsim'])} g/kg against "
        f"{plain(dk1_feb['obs'])} observed, and from March to July both stations are {span(missed)} °C too cold. "
        f"NorKyst v3 160 m ({plain(dk1_feb['norkyst160'])}) and NorFjords ({plain(dk1_feb['norfjords'])}) carry the inflow.",
        f"<b>The water outside the Drøbak sill is too fresh.</b> At Im2, 100 m, the casts average "
        f"{plain(mean(series('Im2', '100', 'S', 'obs', im_lo, im_hi)))} g/kg in February–June 2026; FjordSim "
        f"{plain(mean(series('Im2', '100', 'S', 'fjordsim', im_lo, im_hi)))}, NorKyst v3 160 m "
        f"{plain(mean(series('Im2', '100', 'S', 'norkyst160', im_lo, im_hi)))}.",
        f"<b>The Drammensfjord's deep water freshens.</b> At D-2, 100 m, FjordSim starts from the cast at "
        f"{plain(d2[0], 1)} g/kg and falls steadily to {plain(d2[-1], 1)}; the casts stay at "
        f"{span(series('D-2', '100', 'S', 'obs'))}. Its temperature is within {d2_T_err:.1f} °C. FjordOs mixed the fresh "
        f'surface water down into the basin too fast as well (<a href="#references">Hjelmervik et al., 2017</a>).',
    ]
)
page.figure(
    "basin_drift",
    "figures/basin_drift.png",
    "Salinity (left) and temperature (right) in the deep water. Lines: models, daily; dots: casts. A missing "
    "line means that model's column does not reach the depth.",
)
hov = ", ".join(
    f'<a href="figures/{p.name}">{p.stem.removeprefix("hovmoller_").replace("_", " ")}</a>'
    for p in sorted((HERE / "figures").glob("hovmoller_*.png"))
)
page.p(
    f"{F('hovmoller')} shows the inner basins at every depth, with the casts in the same colour scale. NorKyst v3 "
    f"160 m's columns end above the deep water at Fl1 and Ep1 (Table 4). Every station group: {hov}."
)
page.figure(
    "hovmoller",
    "figures/hovmoller_inner_T.png",
    "Temperature against time and depth at Fl1, Dk1 and Ep1: FjordSim (top), NorKyst v3 160 m (middle), "
    "NorFjords (bottom), daily; the casts are drawn over them in the same colours.",
)

page.h3("Cold water from the open boundary")
i_mar, n_mar = bnd[("IMR", "T", "2026-03")], bnd[("NIVA", "T", "2026-03")]
page.p(
    f"FjordSim takes its boundary water from NorKyst v3 800 m. Where NorKyst v3 800 m has values, at the outer "
    f"stations, both models carry the same deep-layer error month by month ({F('boundary')}). In March 2026 "
    f"FjordSim is {signed(i_mar['fjordsim_bias'], 1)} °C off and NorKyst v3 800 m {signed(i_mar['norkyst800_bias'], 1)} °C "
    f"at IMR's casts (Færder, Torbjørnskjær and the others in the outer fjord); at the NIVA casts, "
    f"{signed(n_mar['fjordsim_bias'], 1)} and {signed(n_mar['norkyst800_bias'], 1)} °C. In {len(bnd_close)} of "
    f"{len(bnd_T)} monthly means (NIVA and IMR casts apart) the two differ by less than 0.5 °C. So the cold spring 2026 water most likely came in "
    f'over the open boundary, as <a href="#references">Dalsøren et al. (2020)</a> found for NorFjords in the '
    "Hardangerfjord. FjordOs, forced by NorKyst-800, was also too cold and too salty at depth in the outer fjord "
    '(<a href="#references">Hjelmervik et al., 2017</a>).'
)
page.figure(
    "boundary",
    "figures/boundary_deep.png",
    "Mean temperature (top) and salinity (bottom) error below 50 m by month, FjordSim and NorKyst v3 800 m on "
    "the same samples, at the stations NorKyst v3 800 m serves. Solid: NIVA casts; dashed: IMR casts.",
)

page.h3("Profiles")
nk_spring = ", ".join(signed(x, 1) for x in spring_nk)
page.p(
    f"Spring 2026 is too cold in the deep layer. In March–May 2026 FjordSim's bias there is "
    f"{', '.join(signed(x, 1) for x in spring_fs)} °C by month; NorKyst v3 160 m's, on its own samples, {nk_spring} °C. "
    f"Below 40 m the March casts at {', '.join(march)} average {span(march_mean('obs'))} °C, FjordSim "
    f"{span(march_mean('fjordsim'))} °C ({F('profiles')}). At D-2 FjordSim follows the brackish layer and the "
    "thermocline; the reference models are far too salty at the surface."
)
page.figure(
    "profiles",
    "figures/profiles_selected.png",
    "Salinity and temperature profiles at five stations, from the outer fjord (top) to Bunnefjorden (bottom), "
    "in four seasons of the second year.",
)
links = ", ".join(
    f'<a href="figures/{p.name}">{p.stem.removeprefix("profiles_").replace("_", "-")}</a>'
    for p in sorted((HERE / "figures").glob("profiles_*.png"))
    if p.stem != "profiles_selected"
)
page.p(f"Every cast, by station: {links}.")

page.h3("IMR's outer-fjord stations")
ia = lambda v: imr_each[("ALL", v, "all")]  # noqa: E731
inf = lambda v: imr_vs["norfjords"][("ALL", v, "all")]  # noqa: E731
i_top = imr_each[("ALL", "S", "0-5 m")]
page.p(
    f"IMR's casts cover the outer fjord from Færder to Breiangen, to {max(r['time'] for r in imr_pairs)[:10]} "
    f"({F('imr')}). FjordSim's RMSE there is {plain(ia('S')['fjordsim_rmse'])} g/kg and {plain(ia('T')['fjordsim_rmse'])} °C; "
    f"on the samples both have, NorFjords' is {plain(inf('S')['norfjords_rmse'])} against "
    f"{plain(inf('S')['fjordsim_rmse'])} g/kg and {plain(inf('T')['norfjords_rmse'])} against "
    f"{plain(inf('T')['fjordsim_rmse'])} °C. As at the NIVA stations, every model is too salty in the surface layer "
    f"(FjordSim {signed(i_top['fjordsim_bias'], 1)}, NorKyst v3 800 m {signed(i_top['norkyst800_bias'], 1)}, NorFjords "
    f"{signed(i_top['norfjords_bias'], 1)} g/kg, each on its own samples)."
)
page.figure(
    "imr",
    "figures/imr_bias.png",
    "Mean error by depth at IMR's stations, from the outer fjord (left) to Breiangen (right): salinity (top), "
    "temperature (bottom). Orange: NorKyst v3 160 m.",
)
# The figure names transliterate the station names (imr.jl's `stem`); the links show the names.
imr_names = {
    re.sub(r"[^A-Za-z0-9]", "_", r["station"]): r["station"] for r in imr_pairs
}
imr_links = ", ".join(
    f'<a href="figures/{p.name}">{imr_names.get(p.stem.removeprefix("imr_series_"), p.stem)}</a>'
    for p in sorted((HERE / "figures").glob("imr_series_*.png"))
)
page.p(f"Time series at each IMR station: {imr_links}.")

page.h3("The Drammensfjord section")
s_top = [float(sill[d]["mean_along_ms"]) for d in sill if float(d) < 2]
s_in = [d for d in sill if float(sill[d]["fraction_days_inflow_gt_1cms"]) >= 0.9]
page.p(
    f"On the Svelvik sill (DS-53) the top 2 m flow out at {span(s_top, 2)} m/s on average. Water flows in at "
    f"{span([float(d) for d in s_in])} m on "
    f"{span([100 * float(sill[d]['fraction_days_inflow_gt_1cms']) for d in s_in], 0)} % of days ({F('section')})."
)
page.video(
    "section",
    "video/section_drammensfjord.mp4",
    "Daily-mean salinity, temperature and along-section velocity from the Drammenselva mouth (left) over the "
    "Svelvik sill (dashed) to Breiangen, with the D-2 and D-3 casts. Right: velocity on the sill.",
)

page.h3("Currents in the Svelvik strait")
page.p(
    f"The strait is the section point with the strongest depth-mean current, {STRAIT}, north of the sill. There "
    f"FjordSim's mean current in the top 5 m is {span([f(r, 'mean_ms') for r in sv_top], 2)} m/s out of the fjord; "
    f"the ADCP measured {span([f(r, 'mean_ms') for r in obs_top], 1)} m/s at 1–5 m "
    f'(<a href="#references">Staalstrøm and Hjelmervik, 2017</a>; {F("svelvik")}). The flow turns into the fjord '
    f"between {plain(sv_turn[0]['depth_m'], 1)} and {plain(sv_turn[1]['depth_m'], 1)} m in FjordSim and between "
    f"{plain(obs_turn[0]['depth_m'], 0)} and {plain(obs_turn[1]['depth_m'], 0)} m observed. The strongest currents "
    f"are too weak: FjordSim's upper-quartile speed in the top 5 m is {100 * (1 - uq_ratio):.0f} % below the "
    f"observed {span([f(r, 'upper_quartile_ms') for r in obs_top], 1)} m/s. "
    + (
        "Its current never exceeds 1.3 m/s; the observed one did a quarter of the time at 3 m. "
        if over_13 == 0
        else f"Its current exceeds 1.3 m/s in {100 * over_13:.0f} % of hours; the observed one did a quarter of the time at 3 m. "
    )
    + f"The 60 h running mean of the outflow in the top 3.7 m follows Drammenselva's "
    f"discharge (r = {outflow_r:.2f}), as the outflow Staalstrøm and Hjelmervik measured 2.5 km further south did."
)
page.figure(
    "svelvik",
    "figures/svelvik_currents.png",
    f"Left: along-strait current at {STRAIT}, from {SPINUP}; FjordSim's mean, its range of monthly means "
    "(band) and its upper-quartile speed, with the ADCP month of 1999. Right: the top 3.7 m, 60 h running mean, "
    "and Drammenselva's discharge.",
)

page.h3("Sea level and tide")
page.table(
    ["Gauge", "Observed", "FjordSim", "NorKyst v3", "NorFjords 160 m (2024)"],
    [
        [
            g,
            tides[(g, "M2")]["kartverket_obs_cm"],
            tides[(g, "M2")]["fjordsim_cm"],
            f"{tides[(g, 'M2')]['norkyst_cm']} ({NAME[tides[(g, 'M2')]['norkyst_model']].removeprefix('NorKyst v3 ')})",
            f"{tides_nf[(g, 'M2')]['norfjords_cm']} (obs. {tides_nf[(g, 'M2')]['kartverket_obs_cm']})",
        ]
        for g in GAUGES
    ],
    caption=f"<b>Table 7.</b> M2 amplitude (cm), {SPINUP} to {STOP}. NorFjords keeps hourly sea level for "
    f"2024 only.",
    numeric=(1, 2, 3, 4),
)
page.p(
    f"FjordSim's tide is right: M2 within {m2_off:.1f} cm and {m2_phase:.0f}° at all gauges, after the boundary "
    f"correction to Viker. NorKyst v3's M2 is {too_large(m2, 'norkyst_cm')} % too large, NorFjords' "
    f"{too_large(m2_nf, 'norfjords_cm')} % ({F('tide')}). Table 8 gives the other constituents."
)
page.table(
    ["Constituent", *GAUGES],
    [
        [
            c,
            *(
                f"{tides[(g, c)]['kartverket_obs_cm']} / {tides[(g, c)]['fjordsim_cm']} "
                f"({signed(tides[(g, c)]['fjordsim_minus_obs_phase_deg'], 0)}°)"
                for g in GAUGES
            ),
        ]
        for c in CONSTITUENTS
    ],
    caption=f"<b>Table 8.</b> Tidal amplitude (cm), observed / FjordSim, and FjordSim's phase error, "
    f"{SPINUP} to {STOP}.",
    numeric=(1, 2, 3),
)
page.p(
    f"Weather drives the rest of the sea level. FjordSim carries {pct(fs)} % of its observed variability "
    f"(r {rr(fs, 'r_residual')}), NorKyst v3 {pct(nk)} % (r {rr(nk, 'r_residual')}). In daily means NorFjords carries "
    f"{pct(nfd)} % (r {rr(nfd, 'r')}), FjordSim {pct(fsd)} % (r {rr(fsd, 'r')}) ({F('residual')})."
)
page.p(
    f"In 5-day windows FjordSim is good in {good('FjordSim'):.0f} % of them and NorKyst v3 in {good('NorKyst'):.0f} % "
    f"({F('lambda')}). The two fail together: NorKyst v3 also fails {len(fs_miss & nk_miss)} of FjordSim's "
    f"{len(fs_miss)} failed windows at the same gauge. The failed windows are calm: the observed weather-driven sea "
    f"level varies by {100 * calm(False):.1f} cm (median standard deviation) in them, against {100 * calm(True):.1f} cm "
    "in the good ones."
)
page.figure(
    "tide",
    "figures/tide_amplitudes.png",
    "Tidal amplitudes at the three gauges. NorKyst v3 is the 800 m run at Viker and the 160 m nest at "
    "Oscarsborg and Oslo. NorFjords is fitted over 2024 and compared with the gauges over 2024.",
)
page.figure(
    "residual",
    "figures/waterlevel_residual.png",
    "Weather-driven sea level at Oscarsborg (series minus its own fitted tide), daily means.",
)
page.figure(
    "lambda",
    "figures/waterlevel_lambda.png",
    "λ of the weather-driven sea level in 5-day windows at the three gauges. Dashed: λ = 0.05, the limit of "
    "a good window.",
)

# ================================================================================================================
page.h2("summary", "Summary")
page.items(
    [
        f"<b>Salinity:</b> FjordSim beats every reference model (RMSE {plain(s160['fjordsim_rmse'])} against "
        f"{plain(s160['norkyst160_rmse'])} g/kg for NorKyst v3 160 m, {plain(s800['fjordsim_rmse'])} against "
        f"{plain(s800['norkyst800_rmse'])} for 800 m, {plain(snf['fjordsim_rmse'])} against {plain(snf['norfjords_rmse'])} for "
        f"NorFjords).",
        f"<b>Temperature:</b> NorKyst v3 160 m is better ({plain(t160['norkyst160_rmse'])} against "
        f"{plain(t160['fjordsim_rmse'])} °C); NorKyst v3 800 m and NorFjords are about even with FjordSim.",
        f"<b>Variability:</b> FjordSim has the observed range of salinity in the surface layer; the reference models "
        f"smooth it. Below {metres(deep_top)} m every model's temperature varies {span([(x - 1) * 100 for x in deep_sd], 0)} % too much.",
        "<b>Drammensfjord:</b> only FjordSim keeps the brackish surface layer and a halocline close to the observed one.",
        f"<b>Svelvik:</b> the strait's mean outflow and the depth where it turns are close to the observed ones; the "
        f"strongest currents are {100 * (1 - uq_ratio):.0f} % too weak.",
        f"<b>Surface salinity:</b> the top 20 m are too salty in every model, in FjordSim in {salty['fjordsim'][0]} of "
        f"{salty['fjordsim'][1]} months, and no model has the Glomma plume.",
        f"<b>Surface temperature:</b> FjordSim's surface layer is {signed(fs_top_T[warmest], 1)} °C off in "
        f"{month_name(warmest)} and {signed(fs_top_T[coldest], 1)} °C in {month_name(coldest)}.",
        f"<b>Inner basins:</b> FjordSim misses the February 2026 inflow and never renews Bunnefjorden; in the deep layer they "
        f"are 1.2–{-min(station_band('fjordsim', s, 'T', 50, 1e9) for s in deep_cold):.1f} °C too cold.",
        f"<b>Spring 2026:</b> in the deep layer FjordSim is {span([-x for x in spring_fs])} °C too cold, NorKyst v3 160 m "
        f"{span([-x for x in spring_nk])} °C. NorKyst v3 800 m, FjordSim's boundary source, has the same error near the "
        "boundary, so the cold water most likely came in over it.",
        f"<b>Sill basins:</b> they start from the NIVA casts, but their deep water freshens: by "
        f"{plain(d2[0] - d2[-1], 1)} g/kg at D-2 (100 m) and {plain(ep_s[0] - ep_s[-1], 1)} g/kg at Ep1 (120 m) in two years.",
        f"<b>Second year:</b> worse than the first (RMSE {plain(yr[('1', 'S')][2])} to {plain(yr[('2', 'S')][2])} g/kg, "
        f"{plain(yr[('1', 'T')][2])} to {plain(yr[('2', 'T')][2])} °C).",
        f"<b>Sea level:</b> M2 within {m2_off:.1f} cm; {pct(fs)} % of the weather-driven variability, more than NorKyst v3 and less "
        f"than NorFjords; good in {good('FjordSim'):.0f} % of 5-day windows.",
    ],
    ordered=True,
    cls="summary",
)

# ================================================================================================================
page.h2("next", "Next steps")
page.items(
    [
        "<b>Currents.</b> The run writes hourly velocity at the six ADCP sites of 2014 (Km1, Kn2, Ri1, Rl1, Rm1, Rn1) and "
        'at the Slagen refinery, whose bottom ADCP measured at 2.5 and 10 m from 1997 (<a href="#references">Hjelmervik et al., 2017</a>). A record '
        "from 2024–2026 at "
        "any of them would let the currents be scored in 5-day windows, as NorKyst v3's are.",
        "<b>Boundary data.</b> The deep spring 2026 error most likely comes from NorKyst v3 800 m. A bias correction of the boundary "
        'data, which NorKyst\'s developers also plan (<a href="#references">Christensen et al., 2026</a>), or another boundary source would test that.',
        f"<b>Inner basins.</b> Find why FjordSim misses the February 2026 inflow, which NorKyst v3 160 m carries. Near "
        f"the boundary FjordSim's deep layer is within {max(abs(float(bnd[(s_, 'T', '2026-02')]['fjordsim_bias'])) for s_ in ('NIVA', 'IMR')):.1f} °C "
        f"in February 2026, so the suspects are inside the fjord: the Drøbak sill ({sills[0]['model_m']} m in the model, "
        f"{sills[0]['real_m'].split(' ')[0]} m real, no jetty openings) and the deep mixing.",
        f"<b>Drammensfjord.</b> Find what freshens its deep water by {plain(d2[0] - d2[-1], 1)} g/kg in two years: mixing "
        "below the halocline, or too little salt water over the Svelvik sill.",
        "<b>Svelvik.</b> Find why the strait's strongest currents are too weak: the strait's cross-section in the model, "
        "or the tidal exchange of the Drammensfjord.",
        "<b>Representativeness.</b> Score each station's 3×3 neighbouring columns as well as its own, to see how much of "
        'the error a 160 m shift explains (<a href="#references">Dalsøren et al., 2020</a>). This needs a new column extract on the GCP VM.',
        "<b>FerryBox.</b> NIVA's FerryBox tracks (4 m, every minute) are fetched but not scored: FjordSim has to be read "
        "along the tracks from the 3D snapshots.",
    ]
)

# ================================================================================================================
page.h2("availability", "Code and data availability")
page.items(
    [
        f'Model: <a href="https://github.com/NIVANorge/FjordSim.jl">FjordSim.jl</a> at commit '
        f'<a href="https://github.com/NIVANorge/FjordSim.jl/commit/{FJORDSIM_COMMIT}"><code>{FJORDSIM_COMMIT[:7]}</code></a>, '
        f"setup <code>examples/oslofjorden/oslofjorden.jl</code>, run <code>{RUN_ID}</code> (tags {' and '.join(STAMPS)}).",
        f"Scores and figures: this project's <code>src/</code> scripts and <code>reports/{HERE.name}/</code>, run as its "
        "README describes.",
        "NIVA CTD casts: NIVA's ODM2 database (odm2.p.niva.no), access on request. FerryBox: ferrybox-api.niva.no.",
        "IMR casts: Vannmiljø (vannmiljoapi.miljodirektoratet.no).",
        "Sea level: Kartverket (vannstand.kartverket.no).",
        'NorKyst v3: MET Norway\'s THREDDS server (<a href="https://thredds.met.no">thredds.met.no</a>). NorFjords 160 m: '
        "IMR, on request.",
        "Forcing: NORA3 (MET Norway), river discharge from NVE's HydAPI, bathymetry from Geonorge Dybdedata.",
    ]
)

# ================================================================================================================
page.h2("references", "References")
page.items(
    [
        "Albretsen, J., Sandvik, A. D., Asplin, L., Lien, V., Skardhamar, J. (2022). NorKyst800: versjoner og arkiver. "
        "<i>Rapport fra havforskningen</i> 2022-35, Havforskningsinstituttet (Institute of Marine Research). "
        '<a href="https://www.hi.no/en/hi/nettrapporter/rapport-fra-havforskningen-2022-35">hi.no</a>',
        "Christensen, K. H., Albretsen, J., Asplin, L., Frøysa, H. G., Gusdal, Y., Iversen, S. C., Jensen, M. F., Johnsen, I. A., "
        "Kristensen, N. M., Sævik, P. N., Sandvik, A. D., Simonsen, M., Skarðhamar, J., Sperrevik, A. K., Trodahl, M. (2026). "
        '"Norkyst" version 3: the coastal ocean forecasting system for Norway. <i>Geoscientific Model Development</i>, 19, '
        '2785–2798. <a href="https://doi.org/10.5194/gmd-19-2785-2026">doi:10.5194/gmd-19-2785-2026</a>',
        "Dalsøren, S. B., Albretsen, J., Asplin, L. (2020). New validation method for hydrodynamic fjord models applied in "
        "the Hardangerfjord, Norway. <i>Estuarine, Coastal and Shelf Science</i>, 246, 107028. "
        '<a href="https://doi.org/10.1016/j.ecss.2020.107028">doi:10.1016/j.ecss.2020.107028</a>',
        "Duveiller, G., Fasbender, D., Meroni, M. (2016). Revisiting the concept of a symmetric index of agreement for "
        "continuous datasets. <i>Scientific Reports</i>, 6, 19401. "
        '<a href="https://doi.org/10.1038/srep19401">doi:10.1038/srep19401</a>',
        "Hjelmervik, K., Kristensen, N. M., Røed, L. P., Staalstrøm, A. (2017). Evaluation of the FjordOs-model. FjordOs "
        "technical report no. 4, <i>METreport</i> 11/2017, Norwegian Meteorological Institute.",
        "Jolliff, J. K., Kindle, J. C., Shulman, I., Penta, B., Friedrichs, M. A. M., Helber, R., Arnone, R. A. (2009). "
        "Summary diagrams for coupled hydrodynamic-ecosystem model skill assessment. <i>Journal of Marine Systems</i>, 76(1–2), "
        '64–82. <a href="https://doi.org/10.1016/j.jmarsys.2008.05.014">doi:10.1016/j.jmarsys.2008.05.014</a>',
        "Ramadhan, A., Wagner, G. L., Hill, C., Campin, J.-M., Churavy, V., Besard, T., Souza, A., Edelman, A., Ferrari, R., "
        "Marshall, J. (2020). Oceananigans.jl: Fast and friendly geophysical fluid dynamics on GPUs. <i>Journal of Open Source "
        'Software</i>, 5(53), 2018. <a href="https://doi.org/10.21105/joss.02018">doi:10.21105/joss.02018</a>',
        "Røed, L. P., Kristensen, N. M., Hjelmervik, K. B., Staalstrøm, A. (2016). A high-resolution, curvilinear ROMS model "
        "for the Oslofjord. FjordOs technical report no. 2, <i>METreport</i> 4/2016, Norwegian Meteorological Institute.",
        "Staalstrøm, A., Hjelmervik, K. B. (2017). Strømforholdene i innløpet til Drammensfjorden. <i>Vann</i>, 52(1), "
        "110–121.",
        "Taylor, K. E. (2001). Summarizing multiple aspects of model performance in a single diagram. <i>Journal of Geophysical "
        'Research: Atmospheres</i>, 106(D7), 7183–7192. <a href="https://doi.org/10.1029/2000JD900719">'
        "doi:10.1029/2000JD900719</a>",
    ]
)

out = HERE / f"{HERE.name}.html"
page.write(out)
print(out)
