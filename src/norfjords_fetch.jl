# NorFjords-160m (IMR's ROMS hindcast A01: 160 m over the Skagerrak coast, 40 s-levels, daily means) at every
# station, read once from a local copy of its daily files, which are not in the bucket; reports read the
# result (`norfjords_columns.jl`, `imr_norfjords.jl`). A cast station's point is the wet point within 1.5 km
# closest in depth to its deepest cast, distance only breaking ties: the smoothed bathymetry is 30-110 m
# shallower than the casts in the sill basins near the stations, and NorKyst's rule (`norkyst_fetch.jl`, 600 m
# counting as much as a 100 % depth mismatch) picks points well above their deep water. A gauge's point is the
# nearest wet point.
#
# Writes to `data/inputs/norfjords_stations/`: `points.csv` (chosen on the first call and kept, so every month
# has the same points), one `<yyyymm>.jld2` per month (each day's T/S columns and level depths at the cast
# stations, ζ at the gauges, and statistics of the points inside the model box), and `tides_2024.jld2`, hourly ζ
# at the gauges over 2024, the only year of hourly output. A month already there is skipped.
#
#   julia --project src/norfjords_fetch.jl <directory holding the yearly folders> <first yyyymm> <last yyyymm>
@isdefined(PROJECT) || include("paths.jl")
using NCDatasets, Dates, Printf, JLD2

const SOURCE = ARGS[1]
const FIRST, LAST = Date(ARGS[2], dateformat"yyyymm"), Date(ARGS[3], dateformat"yyyymm")
const OUT = joinpath(DATA, "norfjords_stations")
const CASTS = ("niva_ctd_odm2_2024-2026", "imr_ctd_2024-2026")   # folders in data/inputs/observations/
const RADIUS = 1500.0   # farthest a station may be from its point, m
const POSITION_OVERRIDES = Dict("OF-1" => (10.754, 59.041))   # as in norkyst_fetch.jl
const GAUGES = [("Viker", 10.949769, 59.036046), ("Oscarsborg", 10.604861, 59.678073), ("Oslo", 10.734510, 59.908559)]
const BOX = (10.0, 11.2, 58.95, 59.93)   # FjordSim's domain

daily_file(day) = joinpath(SOURCE, string(year(day)), "norfjords_160m_avg.nc4_" * Dates.format(day, "yyyymmdd") * "12")
field(ds, name) = Float32.(nomissing(ds[name][:, :, :, 1], NaN))
in_box(lon, lat) = BOX[1] <= lon <= BOX[2] && BOX[3] <= lat <= BOX[4]

"Name, cast folder (`gauge` for a gauge), longitude, latitude and deepest cast (NaN for a gauge) of every station."
function stations()
    list = Tuple{String,String,Float64,Float64,Float64}[]
    for folder in CASTS, l in readlines(joinpath(DATA, "observations", folder, "stations.csv"))[2:end]
        f = split(l, ",")
        code = String(f[1])
        lon, lat = get(POSITION_OVERRIDES, code, (parse(Float64, f[end-2]), parse(Float64, f[end-1])))
        sfile = joinpath(DATA, "observations", folder, "$(obs_stem(code))_S.csv")
        (isfile(sfile) && in_box(lon, lat)) || continue
        deepest = maximum(parse(Float64, split(r, ",")[2]) for r in readlines(sfile)[2:end])
        push!(list, (code, folder, lon, lat, deepest))
    end
    append!(list, [(name, "gauge", lon, lat, NaN) for (name, lon, lat) in GAUGES])
    return list
end

function choose_points(lon, lat, h, wet)
    points = []
    for (name, source, slon, slat, deepest) in stations()
        best = (Inf, CartesianIndex(0, 0), Inf)
        for I in CartesianIndices(lon)
            wet[I] || continue
            distance = hypot((lon[I] - slon) * cosd(slat), lat[I] - slat) * 111.2e3
            distance > RADIUS && continue
            mismatch = isnan(deepest) || deepest < 10 ? 0.0 : abs(min(h[I], 450) - min(deepest, 450)) / max(deepest, 10)
            score = mismatch + distance / 1e6
            score < best[1] && (best = (score, I, distance))
        end
        best[2] == CartesianIndex(0, 0) && continue
        push!(points, (; name, source, i = best[2][1], j = best[2][2], longitude = lon[best[2]], latitude = lat[best[2]],
                       depth = h[best[2]], offset = best[3], deepest))
    end
    return points
end

function read_points(path)
    lines = readlines(path)
    header = split(lines[1], ",")
    return map(lines[2:end]) do l
        r = Dict(zip(header, split(l, ",")))
        (; name = String(r["station"]), source = String(r["source"]), i = parse(Int, r["i"]), j = parse(Int, r["j"]),
         longitude = parse(Float64, r["longitude"]), latitude = parse(Float64, r["latitude"]),
         depth = parse(Float64, r["norfjords_depth_m"]), offset = parse(Float64, r["offset_m"]),
         deepest = parse(Float64, r["deepest_cast_m"]))
    end
end

mkpath(OUT)
first_day = something(findfirst(isfile ∘ daily_file, FIRST:Day(1):(LAST + Month(1) - Day(1))), 0)
first_day == 0 && error("no daily files in $(SOURCE) from $(FIRST) to the end of $(LAST)")
lon, lat, h, wet, Cs, s, hc = NCDataset(daily_file(FIRST + Day(first_day - 1))) do ds
    Float64.(ds["lon_rho"][:, :]), Float64.(ds["lat_rho"][:, :]), Float64.(ds["h"][:, :]), ds["mask_rho"][:, :] .== 1,
    Float64.(ds["Cs_r"][:]), Float64.(ds["s_rho"][:]), Float64(ds["hc"][])
end

points_file = joinpath(OUT, "points.csv")
if !isfile(points_file)
    open(points_file, "w") do io
        println(io, "station,source,i,j,longitude,latitude,norfjords_depth_m,offset_m,deepest_cast_m")
        for q in choose_points(lon, lat, h, wet)
            @printf(io, "%s,%s,%d,%d,%.5f,%.5f,%.1f,%.0f,%.1f\n", q.name, q.source, q.i, q.j, q.longitude, q.latitude,
                    q.depth, q.offset, q.deepest)
        end
    end
end
points = read_points(points_file)
casts_at = filter(q -> q.source != "gauge", points); gauges_at = filter(q -> q.source == "gauge", points)
println(length(casts_at), " cast stations and ", length(gauges_at), " gauges on the NorFjords grid")

tides_file = joinpath(OUT, "tides_2024.jld2")
if !isfile(tides_file)
    hourly = NCDataset(joinpath(SOURCE, "Tides", "norfjords_160m_baro_2024.nc")) do ds
        times = ds["ocean_time"][:]
        Dict(q.name => (; times, η = Float64.(nomissing(ds["zeta"][q.i, q.j, :], NaN))) for q in gauges_at)
    end
    jldsave(tides_file; hourly)
end

# The points inside FjordSim's box, for the domain statistics.
box = wet .& in_box.(lon, lat)
finite_extremum(f, x) = (y = filter(isfinite, x); isempty(y) ? NaN : f(y))
nk = length(s)
for month in FIRST:Month(1):LAST
    path = joinpath(OUT, Dates.format(month, "yyyymm") * ".jld2")
    isfile(path) && continue
    days = filter(isfile ∘ daily_file, month:Day(1):(month + Month(1) - Day(1)))
    isempty(days) && continue
    nd = length(days)
    Z = fill(NaN32, nk, length(casts_at), nd); T = similar(Z); S = similar(Z)
    η = fill(NaN32, length(gauges_at), nd)
    stats = Dict(k => fill(NaN, nd) for k in ("maxT_top", "minT", "maxS", "minS_top"))
    counts = Dict(k => zeros(Int, nd) for k in ("top_above_25C", "below_m1C", "above_36", "nan"))
    saltiest = fill((0, 0, 0), nd)
    for (d, day) in enumerate(days)
        NCDataset(daily_file(day)) do ds
            ζ = Float32.(nomissing(ds["zeta"][:, :, 1], NaN))
            t = field(ds, "temp"); sa = field(ds, "salt")
            for (p, q) in enumerate(casts_at)
                ζp, hp = ζ[q.i, q.j], h[q.i, q.j]
                # ROMS Vtransform 2, as depth below the day's mean surface.
                Z[:, p, d] = [-(ζp + hp) * (hc * s[k] + hp * Cs[k]) / (hc + hp) for k in 1:nk]
                T[:, p, d] = t[q.i, q.j, :]; S[:, p, d] = sa[q.i, q.j, :]
            end
            for (p, q) in enumerate(gauges_at)
                η[p, d] = ζ[q.i, q.j]
            end
            # Some wet cells hold no value on some days; the statistics skip them and count them.
            top = t[:, :, end][box]; ts = t[box, :]; ss = sa[box, :]
            stats["maxT_top"][d] = finite_extremum(maximum, top); stats["minT"][d] = finite_extremum(minimum, ts)
            stats["maxS"][d] = finite_extremum(maximum, ss); stats["minS_top"][d] = finite_extremum(minimum, sa[:, :, end][box])
            counts["top_above_25C"][d] = count(>(25), top); counts["below_m1C"][d] = count(<(-1), ts)
            counts["above_36"][d] = count(>(36), ss); counts["nan"][d] = count(isnan, ss)
            boxed = ifelse.(box, sa, -Inf32); boxed[isnan.(boxed)] .= -Inf32
            saltiest[d] = Tuple(argmax(boxed))
        end
        println(day); flush(stdout)
    end
    jldsave(path; days, casts = [q.name for q in casts_at], gauges = [q.name for q in gauges_at], Z, T, S, η, stats,
            counts, saltiest)
end
