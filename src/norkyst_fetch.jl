# Operational NorKyst-v3 at the scored stations, the reference model, into `data/inputs/norkyst_v3_stations/`:
#
#   julia --project src/norkyst_fetch.jl <grid> <first yyyymm> <last yyyymm>
#       hourly T and S columns (15 z levels to 300 m) and ζ at every NIVA CTD station in the domain and at the
#       three tide gauges. `<grid>` is `160` (member m71, the 160 m Oslofjord nest, 59.24-60.03°N only) or `800`
#       (member m00, the 800 m reference run, the whole domain). One file per month under `<grid>m/`; a month
#       already there or claimed by another process is skipped, so several processes can share a range and a
#       rerun after a failure fetches only the rest.
#   julia --project src/norkyst_fetch.jl imr
#       daily-mean T and S columns at the IMR stations on every day of their casts, under `imr/` (`fetch_imr`).
#   julia --project src/norkyst_fetch.jl boundary <directory of the boundary files>
#       NorKyst's own hourly ζ near the open boundary south of Viker, `boundary_zeta.jld2` (`fetch_boundary`).
#
# Each folder's `points.csv` is written by its first fetch and read by every later one, so every month has the
# same points; delete it and the month files to choose them again.
@isdefined(PROJECT) || include("paths.jl")
using NCDatasets, Dates, Printf, JLD2, Statistics

const OBS = joinpath(DATA, "observations", "niva_ctd_odm2_2024-2026")
const IMR_OBS = joinpath(DATA, "observations", "imr_ctd_2024-2026")
const BASE = "https://thredds.met.no/thredds/dodsC/fou-hi/norkystv3_his_files"
const MEMBER = Dict("160" => "m71", "800" => "m00")
const RADIUS = Dict("160" => 1500.0, "800" => 2500.0)   # farthest a station may be from its point, m

# AquaMonitor's OF-1 lies in 70-100 m of water but its casts reach 440 m; METreport 11/2017 Table 2's
# position is used instead, as in the 2014-15 report.
const POSITION_OVERRIDES = Dict("OF-1" => (10.754, 59.041))
const GAUGES = [("Viker", 10.949769, 59.036046), ("Oscarsborg", 10.604861, 59.678073), ("Oslo", 10.734510, 59.908559)]

url(grid, date) = string(BASE, "/", Dates.format(date, "yyyy/mm/dd"), "/norkyst", grid, "_his_zdepth_",
                         Dates.format(date, "yyyymmdd"), "T00Z_", MEMBER[grid], "_AN.nc")

"`f(NCDataset(path))`, retried with a growing pause: THREDDS times out and rate-limits now and then."
function retrying(f, path; attempts = 8)
    for attempt in 1:attempts
        try
            return NCDataset(f, path)
        catch e
            e isa InterruptException && rethrow()
            attempt == attempts && rethrow()
            println("retry ", attempt, " on ", path, ": ", sprint(showerror, e)[1:min(end, 200)]); flush(stdout)
            sleep(15attempt)
        end
    end
end

"Name, longitude, latitude and deepest observed depth (NaN for a gauge) of every station to fetch, the casts' from `dir`."
function stations(dir = OBS)
    list = Tuple{String,Float64,Float64,Float64}[]
    for l in readlines(joinpath(dir, "stations.csv"))[2:end]
        f = split(l, ",")   # some names are quoted and hold a comma: read the position from the end
        code = String(f[1])
        lon, lat = get(POSITION_OVERRIDES, code, (parse(Float64, f[end-2]), parse(Float64, f[end-1])))
        sfile = joinpath(dir, "$(obs_stem(code))_S.csv")
        (isfile(sfile) && 10.0 <= lon <= 11.2 && 58.95 <= lat <= 59.93) || continue
        deepest = maximum(parse(Float64, split(r, ",")[2]) for r in readlines(sfile)[2:end])
        push!(list, (code, lon, lat, deepest))
    end
    append!(list, [(name, lon, lat, NaN) for (name, lon, lat) in GAUGES])
    return list
end

"The grid's wet point for each station: near it, and for a cast station as deep as its casts."
function points(grid, dir = OBS)
    lon, lat, h, wet = retrying(url(grid, Date(2025, 3, 15))) do ds
        Float64.(ds["lon"][:, :]), Float64.(ds["lat"][:, :]), Float64.(ds["h"][:, :]),
        .!ismissing.(ds["temperature"][:, :, 1, 1])
    end
    selected = []
    for (name, slon, slat, deepest) in stations(dir)
        best = (Inf, CartesianIndex(0, 0), Inf)
        for I in CartesianIndices(lon)
            wet[I] || continue
            distance = hypot((lon[I] - slon) * cosd(slat), lat[I] - slat) * 111.2e3
            distance > RADIUS[grid] && continue
            # Only a cast is matched in depth: a gauge or a FerryBox line (4 m) is matched by distance.
            mismatch = isnan(deepest) || deepest < 10 ? 0.0 : abs(min(h[I], 450) - min(deepest, 450)) / max(deepest, 10)
            score = mismatch + distance / 600
            score < best[1] && (best = (score, I, distance))
        end
        best[2] == CartesianIndex(0, 0) && continue   # outside this grid
        push!(selected, (; name, i = best[2][1], j = best[2][2], longitude = lon[best[2]], latitude = lat[best[2]],
                         depth = h[best[2]], offset = best[3], deepest))
    end
    return selected
end

function fetch_month(grid, month, selected, path)
    days = Date(month):Day(1):(Date(month) + Month(1) - Day(1))
    np, nd = length(selected), length(days)
    T = fill(NaN32, 15, 24, np, nd); S = fill(NaN32, 15, 24, np, nd); η = fill(NaN32, 24, np, nd)
    times = Matrix{DateTime}(undef, 24, nd)
    depth = Float64[]
    for (d, day) in enumerate(days)
        # A failed read reopens the file and carries on from the point it failed at, not from the
        # day's first. A gauge needs only ζ and a cast station only T and S.
        done = 0
        retrying(url(grid, day)) do ds
            times[:, d] = ds["time"][:]
            isempty(depth) && append!(depth, ds["depth"][:])
            for (p, s) in enumerate(selected)
                p <= done && continue
                if isnan(s.deepest)
                    η[:, p, d] = coalesce.(ds["zeta"][s.i, s.j, :], NaN32)
                else
                    T[:, :, p, d] = coalesce.(ds["temperature"][s.i, s.j, :, :], NaN32)
                    S[:, :, p, d] = coalesce.(ds["salinity"][s.i, s.j, :, :], NaN32)
                end
                done = p
            end
        end
        println(grid, " m ", day); flush(stdout)
    end
    jldsave(path * ".tmp"; names = [s.name for s in selected], points = selected, depth, times, T, S, η)
    mv(path * ".tmp", path; force = true)
end

"The points of `points.csv` in `directory`, or `choose()`'s, then written there. Each point is the station's name,
its cell, position, depth and offset from the station, the deepest cast (NaN for a gauge), and for the IMR
points the grid."
function fixed_points(choose, directory)
    path = joinpath(directory, "points.csv")
    if !isfile(path)
        selected = choose()
        open(path, "w") do io
            println(io, "station,grid,i,j,longitude,latitude,norkyst_depth_m,offset_m,deepest_cast_m")
            for s in selected
                @printf(io, "%s,%s,%d,%d,%.5f,%.5f,%.1f,%.0f,%.1f\n", s.name, get(s, :grid, basename(directory)), s.i, s.j,
                        s.longitude, s.latitude, s.depth, s.offset, s.deepest)
            end
        end
    end
    lines = readlines(path)
    header = split(lines[1], ",")
    return map(lines[2:end]) do l
        r = Dict(zip(header, split(l, ",")))
        (; name = String(r["station"]), grid = String(get(r, "grid", basename(directory))), i = parse(Int, r["i"]),
         j = parse(Int, r["j"]), longitude = parse(Float64, r["longitude"]), latitude = parse(Float64, r["latitude"]),
         depth = parse(Float64, r["norkyst_depth_m"]), offset = parse(Float64, r["offset_m"]),
         deepest = parse(Float64, r["deepest_cast_m"]))
    end
end

function main(grid, first_month, last_month)
    directory = joinpath(DATA, "norkyst_v3_stations", grid * "m")
    mkpath(directory)
    selected = fixed_points(() -> points(grid), directory)
    println(length(selected), " points on the ", grid, " m grid")
    for month in first_month:Month(1):last_month
        path = joinpath(directory, Dates.format(month, "yyyymm") * ".jld2")
        # A month another process has claimed or finished is skipped; a claim left by a killed process
        # has to be deleted by hand.
        (isfile(path) || isfile(path * ".claim")) && continue
        touch(path * ".claim")
        fetch_month(grid, month, selected, path)
        rm(path * ".claim")
    end
end

"""
NorKyst at the IMR stations (`imr_fetch.py`) as daily means on the days of their casts: Vannmiljø dates a cast
without a time of day. A station on the 160 m nest is read there, the others from the 800 m run. One file per
month of cast days under `imr/`; a month whose file already holds all its cast days is skipped.
"""
function fetch_imr()
    directory = joinpath(DATA, "norkyst_v3_stations", "imr")
    mkpath(directory)
    selected = fixed_points(directory) do
        chosen = []
        for grid in ("160", "800"), p in points(grid, IMR_OBS)
            (isnan(p.deepest) || any(q -> q.name == p.name, chosen)) && continue   # a gauge, or on the 160 m nest
            push!(chosen, (; p..., grid = grid * "m"))
        end
        chosen
    end
    days = sort(unique(Date(split(r, ",")[1][1:10]) for f in readdir(IMR_OBS; join = true) if endswith(f, "_S.csv")
                       for r in readlines(f)[2:end]))
    for month in unique(firstdayofmonth.(days))
        path = joinpath(directory, Dates.format(month, "yyyymm") * ".jld2")
        wanted = filter(d -> firstdayofmonth(d) == month, days)
        isfile(path) && issubset(wanted, load(path, "days")) && continue
        T = fill(NaN, 15, length(selected), length(wanted)); S = similar(T)
        depth = Float64[]
        for (d, day) in enumerate(wanted), grid in ("160", "800")
            here = findall(q -> q.grid == grid * "m", selected)
            isempty(here) && continue
            retrying(url(grid, day)) do ds
                isempty(depth) && append!(depth, ds["depth"][:])
                for p in here
                    q = selected[p]
                    T[:, p, d] = vec(mean(Float64.(coalesce.(ds["temperature"][q.i, q.j, :, :], NaN)), dims = 2))
                    S[:, p, d] = vec(mean(Float64.(coalesce.(ds["salinity"][q.i, q.j, :, :], NaN)), dims = 2))
                end
            end
            println(grid, " m ", day); flush(stdout)
        end
        jldsave(path; days = wanted, names = [q.name for q in selected], depth, T, S)
    end
end

"""
NorKyst's own hourly sea level at its wet point nearest the open boundary south of Viker, before the Viker tide
correction FjordSim's prepared boundary file applies, from the monthly boundary files FjordSim's
`download_boundary_data` writes (`gs://fjordsim/data/oslofjorden/norkyst_v3_hourly/`): `analysis.jl` fits
NorKyst's tide on it. Writes `boundary_zeta.jld2`.
"""
function fetch_boundary(source)
    times = DateTime[]; η = Float64[]
    for f in sort(filter(f -> occursin(r"_\d{6}\.nc$", f), readdir(source; join = true)))
        NCDataset(f) do ds
            lon = ds["lon"][:, :]; lat = ds["lat"][:, :]; mask = .!ismissing.(ds["zeta"][:, :, 1])
            _, I = findmin(I -> mask[I] ? hypot((lon[I] - 10.95) * cosd(59), lat[I] - 58.97) : Inf, CartesianIndices(lon))
            append!(times, ds["time"][:]); append!(η, Float64.(coalesce.(ds["zeta"][I[1], I[2], :], NaN)))
        end
    end
    jldsave(joinpath(DATA, "norkyst_v3_stations", "boundary_zeta.jld2"); times, η)
    println("boundary ζ: ", length(times), " hours, ", first(times), " .. ", last(times))
end

if abspath(PROGRAM_FILE) == (@__FILE__)
    if ARGS[1] == "imr"
        fetch_imr()
    elseif ARGS[1] == "boundary"
        fetch_boundary(ARGS[2])
    else
        main(ARGS[1], DateTime(ARGS[2], "yyyymm"), DateTime(ARGS[3], "yyyymm"))
    end
end
