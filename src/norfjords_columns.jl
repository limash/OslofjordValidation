# NorFjords-160m (IMR's ROMS hindcast A01) at the scored stations over the validated window, up to the end of
# its daily-mean files (2026-06-30), from the monthly files `norfjords_fetch.jl` writes: points as chosen there.
# Writes `norfjords_columns.jld2` (daily T/S columns with each day's level depths below the surface, daily ζ at
# the gauges, hourly ζ at the gauges over 2024, and daily statistics of the points inside FjordSim's box),
# `norfjords_points.csv` and `norfjords_pairs.csv`, NorFjords at every cast sample on the cast's day.
#
#   REPORT=<name> julia --project src/norfjords_columns.jl
include("common.jl")
using JLD2

const SOURCE = joinpath(DATA, "norfjords_stations")

points = readcsv(joinpath(SOURCE, "points.csv"))
# The NIVA cast stations of this report and the gauges; the IMR stations are `imr_norfjords.jl`'s.
selected = filter(q -> q["source"] in (CONFIG["niva_casts"], "gauge"), points)
any(q -> q["source"] == CONFIG["niva_casts"], points) || error("no NorFjords points for the casts of $(CONFIG["niva_casts"])")

months = Date(START):Month(1):(Date(STOP) - Day(1))
X = [load(f) for f in (joinpath(SOURCE, Dates.format(m, "yyyymm") * ".jld2") for m in months) if isfile(f)]
keep = [findall(d -> Date(START) <= d < Date(STOP), x["days"]) for x in X]
days = reduce(vcat, x["days"][k] for (x, k) in zip(X, keep))
along_days(key) = cat((x[key][:, :, k] for (x, k) in zip(X, keep))...; dims = 3)
Z, T, S = along_days("Z"), along_days("T"), along_days("S")
η = reduce(hcat, x["η"][:, k] for (x, k) in zip(X, keep))
stats = Dict(name => reduce(vcat, x["stats"][name][k] for (x, k) in zip(X, keep)) for name in keys(X[1]["stats"]))
counts = Dict(name => reduce(vcat, x["counts"][name][k] for (x, k) in zip(X, keep)) for name in keys(X[1]["counts"]))
saltiest = reduce(vcat, x["saltiest"][k] for (x, k) in zip(X, keep))
casts, gauges = X[1]["casts"], X[1]["gauges"]
hourly = load(joinpath(SOURCE, "tides_2024.jld2"), "hourly")

columns = Dict{String,Any}()
for (p, name) in enumerate(casts)
    any(q -> q["station"] == name && q["source"] == CONFIG["niva_casts"], selected) || continue
    columns[name] = (; grid = "160m", days = DateTime.(days) .+ Hour(12), z = Float64.(Z[:, p, :]),
                     daily_T = Float64.(T[:, p, :]), daily_S = Float64.(S[:, p, :]))
end
levels = Dict(name => (; days = DateTime.(days) .+ Hour(12), η = Float64.(η[p, :])) for (p, name) in enumerate(gauges))
jldsave(joinpath(REPORT_DATA, "norfjords_columns.jld2"); columns, levels, hourly, stats, counts, saltiest, days)
writecsv(joinpath(REPORT_DATA, "norfjords_points.csv"), "station,i,j,longitude,latitude,norfjords_depth_m,offset_m",
    sort([join((q["station"], q["i"], q["j"], q["longitude"], q["latitude"], q["norfjords_depth_m"], q["offset_m"]), ",")
          for q in selected]))

rows = String[]
for c in niva_casts(START, STOP; with_ferrybox = true)
    haskey(columns, c.station) || continue
    col = columns[c.station]
    d = findfirst(==(Date(c.time)), days); isnothing(d) && continue
    push!(rows, @sprintf("%s,%s,%.1f,%.3f,%.3f", c.station, Dates.format(c.time, "yyyy-mm-ddTHH:MM:SS"), c.depth,
        interp(col.z[:, d], col.daily_T[:, d], c.depth), interp(col.z[:, d], col.daily_S[:, d], c.depth)))
end
writecsv(joinpath(REPORT_DATA, "norfjords_pairs.csv"), "station,time,depth,norfjords_T,norfjords_S", rows)
println("norfjords: ", length(columns), " cast stations, ", length(levels), " gauges, ", length(rows), " pairs")
