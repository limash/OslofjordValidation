# Shared paths and helpers of the report scripts. A run is scored against the NIVA casts (from ODM2), IMR's
# casts (from Vannmiljø) and Kartverket, with the operational NorKyst-v3 (its 160 m Oslofjord nest and the
# 800 m reference run) and IMR's NorFjords-160m hindcast as reference models.
include("report_config.jl")
using NCDatasets, Dates, Statistics, Printf

const OBS = joinpath(DATA, "observations", CONFIG["niva_casts"])
# Havforskningsinstituttet's casts (ØkoKyst and Tisler) from Vannmiljø, `imr_fetch.py`.
const IMR_OBS = joinpath(DATA, "observations", CONFIG["imr_casts"])

const COLORS = Dict("obs" => :black, "fjordsim" => :dodgerblue, "norkyst" => :darkorange, "norfjords" => :forestgreen)
const LABELS = Dict("obs" => "observed", "fjordsim" => "FjordSim", "norkyst" => "NorKyst v3 (160 m / 800 m)",
                    "norfjords" => "NorFjords 160 m")
# The models scored jointly. NorFjords' files end on 2026-06-30, so it is scored beside FjordSim on the samples
# both reach instead, and the FjordSim–NorKyst scores keep the whole window.
const MODELS = ("fjordsim", "norkyst")
const ALL_MODELS = ("fjordsim", "norkyst", "norfjords")

stem(code) = replace(code, "Ø" => "O", r"[^A-Za-z0-9]" => "_")
days_since_start(t) = Dates.value(DateTime(t) - START) / 86_400_000

writecsv(path, header, rows) = open(path, "w") do io
    println(io, header)
    foreach(r -> println(io, r), rows)
end
readcsv(path) = (l = readlines(path); h = split(l[1], ","); [Dict{String,String}(zip(h, split(x, ","))) for x in l[2:end]])
num(x::Real) = Float64(x)
num(x) = (v = tryparse(Float64, x); isnothing(v) ? NaN : v)

"Linear interpolation in a column; `depths` positive down, any order. The top value covers the top 1.5 m."
function interp(depths, values, target)
    order = sortperm(depths); d = depths[order]; v = values[order]
    ok = isfinite.(v); any(ok) || return NaN
    d = d[ok]; v = v[ok]
    target < d[1] && return d[1] <= 1.5 ? v[1] : NaN
    target > d[end] && return NaN
    i = searchsortedfirst(d, target)
    d[i] == target && return v[i]
    w = (target - d[i-1]) / (d[i] - d[i-1])
    return (1 - w) * v[i-1] + w * v[i]
end

# A reference model's level depths on day `k`: NorKyst's z-levels are fixed, NorFjords' s-levels move.
depths(col, k) = col.z isa AbstractMatrix ? col.z[:, k] : col.z

# The FerryBox stations are 4 m samples from a ferry's intake at a nominal position, not casts.
ferrybox(code) = endswith(code, "-FB")

# Project 6302 is the Inner Oslofjord programme; of project 12914, D-2 and D-3 are the Drammensfjord.
const INNER = Set(split(l, ",")[1] for l in readlines(joinpath(OBS, "stations.csv"))[2:end] if split(l, ",")[end] == "6302")
region(s) = s in ("D-2", "D-3") ? "Drammensfjord" : (s in INNER ? "Inner Oslofjord" : "Outer fjord")
const REGIONS = ("Outer fjord", "Drammensfjord", "Inner Oslofjord")

"Every sample in the model domain between `from` and `to` of the casts in `dir` (the NIVA ones by default), T and S joined on (time, depth)."
function niva_casts(from, to; with_ferrybox = false, dir = OBS)
    positions = Dict{String,Tuple{Float64,Float64,String}}()
    # Some names are quoted and hold a comma, so the position is read from the end of the line.
    for l in readlines(joinpath(dir, "stations.csv"))[2:end]
        f = split(l, ",")
        positions[f[1]] = (parse(Float64, f[end-2]), parse(Float64, f[end-1]), f[end])
    end
    casts = []
    for (code, (lon, lat, project)) in positions
        (with_ferrybox || !ferrybox(code)) || continue
        sfile = joinpath(dir, "$(obs_stem(code))_S.csv")
        tfile = joinpath(dir, "$(obs_stem(code))_T.csv")
        (isfile(sfile) && isfile(tfile)) || continue
        (10.0 <= lon <= 11.2 && 58.95 <= lat <= 59.93) || continue
        T = Dict((r["time"], num(r["depth"])) => num(r["value"]) for r in readcsv(tfile))
        for r in readcsv(sfile)
            t = DateTime(r["time"]); from <= t <= to || continue
            key = (r["time"], num(r["depth"]))
            push!(casts, (station = code, time = t, depth = key[2], S = num(r["value"]), T = get(T, key, NaN),
                          lon, lat, project))
        end
    end
    return casts
end
