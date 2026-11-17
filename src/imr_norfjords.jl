# NorFjords-160m at the IMR stations (`imr_fetch.py`) on the days of their casts in the validated window, from
# the monthly files `norfjords_fetch.jl` writes, points as chosen there. Writes `imr_norfjords.jld2`.
#
#   REPORT=<name> julia --project src/imr_norfjords.jl
include("common.jl")
using JLD2

const SOURCE = joinpath(DATA, "norfjords_stations")

casts = niva_casts(START, STOP; dir = IMR_OBS)
cast_days = Set(Date(c.time) for c in casts)
months = sort(unique(firstdayofmonth.(cast_days)))
X = [load(f) for f in (joinpath(SOURCE, Dates.format(m, "yyyymm") * ".jld2") for m in months) if isfile(f)]
keep = [findall(in(cast_days), x["days"]) for x in X]
days = reduce(vcat, x["days"][k] for (x, k) in zip(X, keep))
along_days(key) = cat((x[key][:, :, k] for (x, k) in zip(X, keep))...; dims = 3)
Z, T, S = along_days("Z"), along_days("T"), along_days("S")

selected = [(; name = q["station"], i = parse(Int, q["i"]), j = parse(Int, q["j"]), depth = num(q["norfjords_depth_m"]),
             offset = num(q["offset_m"]), deepest = num(q["deepest_cast_m"]))
            for q in readcsv(joinpath(SOURCE, "points.csv")) if q["source"] == CONFIG["imr_casts"]]
index = Dict(name => p for (p, name) in enumerate(X[1]["casts"]))
columns = Dict(q.name => (; grid = "160m", point = q, days, z = Float64.(Z[:, index[q.name], :]),
                          daily_T = Float64.(T[:, index[q.name], :]), daily_S = Float64.(S[:, index[q.name], :]))
               for q in selected)
jldsave(joinpath(REPORT_DATA, "imr_norfjords.jld2"); columns)
foreach(q -> @printf("%s: point %.0f m deep, %.0f m away (casts to %.0f m)\n", q.name, q.depth, q.offset, q.deepest), selected)
