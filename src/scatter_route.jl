# What `scatter_video.jl` and `scatter_explorer.jl` share: the route through the Oslofjord, the depth layers,
# and observed against modelled S and T at every station on it (`taylor_explorer.jl` takes the route and the map). NIVA casts (`ctd_pairs.csv`) and IMR's
# (`imr_pairs.csv`), scored from SPINUP. NorKyst v3 is merged here: the 160 m nest where it covers a station,
# else the 800 m run; `grid_<var>` names which one each sample comes from.
include("common.jl")

const ROUTE = [
    "Inner Oslofjord" => ["Gp2", "Ep1", "Ep2", "Cq1", "Br1", "Aq3", "Aq2", "Ap2", "Ap3", "Cp2", "Bn1", "Bl4", "Cj1", "Dm1",
                          "Dk1", "Ej1", "Fl1", "Gl2", "Gk1", "En-1"],
    "Drøbak Sound" => ["Hm4", "Im3", "Im2"],
    "Bastøy" => ["MO-2", "Bastøy"],
    "Glomma" => ["KF-1", "Ø-1", "I-4"],
    "Hvaler" => ["I-1", "S-9", "Tisler-1", "Tisler-5"],
    "Skagerrak" => ["Torbjørnskjær", "Færder", "LA-1", "SF-3"],
    "Outer Oslofjord" => ["TØ-1", "BO-1", "Missingene", "VAL-1"],
    "Bastøy" => ["Bastøy"],
    "Breiangen" => ["Breiangen vest", "SAN-5"],
]
const FINAL = "Drammensfjord" => ["D-3", "D-2"]
const WINDOW = 5
const LAYERS = [(">50 m", 50, 1e4), ("20–50 m", 20, 50), ("5–20 m", 5, 20), ("0–5 m", 0, 5)]
const MODELS = ("fjordsim", "norkyst", "norfjords")
# Okabe–Ito colours; consecutive stations on the route never share one.
const PALETTE_HEX = ["#0072B2", "#D55E00", "#009E73", "#CC79A7", "#E69F00"]
const NORKYST_NOTE = "NorKyst v3: the 160 m nest (m71) where it covers a station, else the 800 m run (m00)."

pairs = []
for file in ("ctd_pairs.csv", "imr_pairs.csv"), r in readcsv(joinpath(REPORT_DATA, file))
    DateTime(r["time"]) >= SPINUP || continue
    p = Dict{String,Any}("station" => r["station"], "time" => DateTime(r["time"]), "depth" => num(r["depth"]))
    for v in ("T", "S")
        n160, n800 = num(r["norkyst160_$v"]), num(r["norkyst800_$v"])
        p["obs_$v"], p["fjordsim_$v"], p["norfjords_$v"] = num(r["obs_$v"]), num(r["fjordsim_$v"]), num(r["norfjords_$v"])
        p["norkyst_$v"] = isfinite(n160) ? n160 : n800
        p["grid_$v"] = isfinite(n160) ? "160 m" : isfinite(n800) ? "800 m" : ""
    end
    push!(pairs, p)
end
imr_names = Set(r["station"] for r in readcsv(joinpath(REPORT_DATA, "imr_cells.csv")))
station_position = Dict(r["station"] => (num(r["lon"]), num(r["lat"])) for f in ("cells.csv", "imr_cells.csv")
                for r in readcsv(joinpath(REPORT_DATA, f)))
in_layer(p, lo, hi) = lo <= p["depth"] < hi

"Square axis limits of one layer and variable: 0.2–99.8 % of every value in it, padded."
function layer_limits(lo, hi, v)
    xs = Float64[p["$(k)_$v"] for p in pairs if in_layer(p, lo, hi) for k in ("obs", MODELS...)]
    a, b = quantile(filter(isfinite, xs), (0.002, 0.998))
    pad = 0.05(b - a)
    return a - pad, b + pad
end

lon, lat, h = NCDataset(joinpath(RUN_SETUP, "bathymetry.nc")) do ds
    Float64.(ds["lon"][:]), Float64.(ds["lat"][:]), Float64.(coalesce.(ds["h"][:, :], NaN))
end
depth = map(x -> x < 0 ? -x : NaN, h)
