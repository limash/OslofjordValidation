# NorKyst-v3 at the IMR stations on the days of their casts in the validated window, as daily means, from the
# files `norkyst_fetch.jl imr` writes (data/inputs/norkyst_v3_stations/imr/). Writes `imr_norkyst.jld2`.
#
#   REPORT=<name> julia --project src/imr_norkyst.jl
include("common.jl")
using JLD2

const SOURCE = joinpath(DATA, "norkyst_v3_stations", "imr")

X = [load(joinpath(SOURCE, f)) for f in sort(readdir(SOURCE)) if endswith(f, ".jld2")]
keep = [findall(d -> Date(START) <= d < Date(STOP), x["days"]) for x in X]
days = reduce(vcat, x["days"][k] for (x, k) in zip(X, keep))
along_days(key) = cat((x[key][:, :, k] for (x, k) in zip(X, keep))...; dims = 3)
T, S = along_days("T"), along_days("S")
index = Dict(name => p for (p, name) in enumerate(X[1]["names"]))
println(length(days), " cast days")

columns = Dict{String,Any}()
for q in readcsv(joinpath(SOURCE, "points.csv"))
    point = (; name = q["station"], i = parse(Int, q["i"]), j = parse(Int, q["j"]), longitude = num(q["longitude"]),
             latitude = num(q["latitude"]), depth = num(q["norkyst_depth_m"]), offset = num(q["offset_m"]),
             deepest = num(q["deepest_cast_m"]))
    p = index[point.name]
    columns[point.name] = (; grid = q["grid"], point, z = X[1]["depth"], days, daily_T = T[:, p, :], daily_S = S[:, p, :])
end
jldsave(joinpath(REPORT_DATA, "imr_norkyst.jld2"); columns)
println("wrote imr_norkyst.jld2: ", length(columns), " stations")
