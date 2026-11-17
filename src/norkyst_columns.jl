# NorKyst-v3 at the scored stations over the validated window, from the monthly files `norkyst_fetch.jl`
# writes: each station from the 160 m Oslofjord nest (m71) where the nest covers it, otherwise from the
# 800 m reference run (m00). Writes `norkyst_columns.jld2` (hourly and daily-mean T/S columns per cast
# station, hourly ζ per gauge), `norkyst_points.csv`, and `norkyst_pairs.csv`, NorKyst at every cast
# sample at the hour nearest the cast.
include("common.jl")
using JLD2

const SOURCE = joinpath(DATA, "norkyst_v3_stations")

"Every monthly file of `grid` in the window, joined along time: names, points, depth, times, T, S, η."
function load_grid(grid)
    months = Date(START):Month(1):Date(STOP - Millisecond(1))
    files = [joinpath(SOURCE, grid, Dates.format(m, "yyyymm") * ".jld2") for m in months]
    missing_files = filter(!isfile, files)
    isempty(missing_files) || error("$grid: not fetched yet: ", join(basename.(missing_files), ", "))
    X = [load(f) for f in files]
    nh(x) = length(x["times"])
    # Stored as level × hour × point × day; joined as level × (hour, day) × point, hours varying fastest.
    times = reduce(vcat, vec(x["times"]) for x in X)
    T = reduce(hcat, [reshape(permutedims(x["T"], (1, 2, 4, 3)), 15, nh(x), :) for x in X])
    S = reduce(hcat, [reshape(permutedims(x["S"], (1, 2, 4, 3)), 15, nh(x), :) for x in X])
    η = reduce(vcat, [reshape(permutedims(x["η"], (1, 3, 2)), nh(x), :) for x in X])
    keep = findall(t -> START <= t <= STOP, times)
    return (; names = X[1]["names"], points = X[1]["points"], depth = X[1]["depth"], times = times[keep],
            T = T[:, keep, :], S = S[:, keep, :], η = η[keep, :])
end

grids = Dict(g => load_grid(g) for g in ("160m", "800m"))
columns = Dict{String,Any}()
levels = Dict{String,Any}()
point_rows = String[]
for name in unique(vcat(grids["160m"].names, grids["800m"].names))
    g = name in grids["160m"].names ? "160m" : "800m"
    G = grids[g]; p = findfirst(==(name), G.names); pt = G.points[p]
    push!(point_rows, @sprintf("%s,%s,%d,%d,%.5f,%.5f,%.1f,%.0f", name, g, pt.i, pt.j, pt.longitude, pt.latitude, pt.depth, pt.offset))
    if isnan(pt.deepest)
        levels[name] = (; grid = g, times = G.times, η = Float64.(G.η[:, p]))
    else
        T = Float64.(G.T[:, :, p]); S = Float64.(G.S[:, :, p])
        days = unique(Date.(G.times))
        daymean(A) = reduce(hcat, [vec(mean(A[:, Date.(G.times) .== d], dims = 2)) for d in days])
        columns[name] = (; grid = g, z = G.depth, times = G.times, T, S,
                         days = DateTime.(days) .+ Hour(12), daily_T = daymean(T), daily_S = daymean(S))
    end
end
jldsave(joinpath(REPORT_DATA, "norkyst_columns.jld2"); columns, levels)
writecsv(joinpath(REPORT_DATA, "norkyst_points.csv"), "station,grid,i,j,longitude,latitude,norkyst_depth_m,offset_m", sort(point_rows))

rows = String[]
for c in niva_casts(START, STOP; with_ferrybox = true)
    haskey(columns, c.station) || continue
    col = columns[c.station]
    k = argmin(abs.(Dates.value.(col.times .- c.time)))
    abs(col.times[k] - c.time) <= Minute(90) || continue
    push!(rows, @sprintf("%s,%s,%.1f,%.3f,%.3f", c.station, Dates.format(c.time, "yyyy-mm-ddTHH:MM:SS"), c.depth,
        interp(col.z, col.T[:, k], c.depth), interp(col.z, col.S[:, k], c.depth)))
end
writecsv(joinpath(REPORT_DATA, "norkyst_pairs.csv"), "station,time,depth,norkyst_T,norkyst_S", rows)
println("norkyst: ", length(columns), " cast stations, ", length(levels), " gauges, ", length(rows), " pairs")
