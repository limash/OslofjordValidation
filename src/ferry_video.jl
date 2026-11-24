# MS Color Fantasy's crossings of one day as videos. Maps of FjordSim's surface T and S, as in the surface videos,
# with the ship's track coloured by the FerryBox's measured values on the same scale; below each map, the values
# along the track: the FerryBox (4 m) and FjordSim's top cell at the ship's cell and minute, fixed once the ship
# has passed. The hourly fields (`bin/vm_run.sh <report> ferry <day>`) are interpolated linearly to each minute,
# one frame per FerryBox minute. One MP4 per crossing, named by its direction, in output/<report>/video/.
#
#   REPORT=<name> julia --project src/ferry_video.jl <yyyy-mm-dd> [frames per second]
include("common.jl")
include("surface_videos.jl")
using .SurfaceVideos: TOWNS, LAND_COLOUR, bathymetry_grid
using JLD2
import CairoMakie as M

const FERRYBOX = joinpath(DATA, "observations", "niva_ferrybox_2024-2026")
const VARIABLES = (("T", "Temperature (°C)", :thermal), ("S", "Salinity (g kg⁻¹)", :haline))

value(x) = isempty(x) ? NaN : parse(Float64, x)

"Color Fantasy's FerryBox minutes on `day`, as `ferrybox_fetch.py` wrote them."
function ferrybox_day(day)
    rows = map(readlines(joinpath(FERRYBOX, "FA_$(Dates.format(day, "yyyymm")).csv"))[2:end]) do l
        f = split(l, ",")
        (time = DateTime(f[1]), lon = value(f[2]), lat = value(f[3]), T = value(f[4]), S = value(f[5]))
    end
    return filter(r -> Date(r.time) == day, rows)
end

"The minutes split into crossings at stops of over 30 minutes (a port call); a crossing has at least 30 minutes."
function crossings(rows)
    ends = [0; findall(>(Minute(30)), diff([r.time for r in rows])); length(rows)]
    return [rows[ends[k]+1:ends[k+1]] for k in 1:length(ends)-1 if ends[k+1] - ends[k] >= 30]
end

"The wet cell nearest the point."
function nearest_wet(grid, wet_cells, lon, lat)
    c = cosd(lat)
    return wet_cells[argmin([((grid.longitude[I[1]] - lon) * c)^2 + (grid.latitude[I[2]] - lat)^2 for I in wet_cells])]
end

"Weight of the next hourly record at `t`, and the record before it."
function hour_weight(times, t)
    k = min(searchsortedlast(times, t), length(times) - 1)
    return k, (t - times[k]) / (times[k+1] - times[k])
end

function field_at(A, times, t)
    k, w = hour_weight(times, t)
    return (1 - w) .* A[:, :, k] .+ w .* A[:, :, k+1]
end

function point_at(A, times, cell, t)
    k, w = hour_weight(times, t)
    return (1 - w) * A[cell, k] + w * A[cell, k+1]
end

km(a, b) = 6371 * 2asin(sqrt(sind((b.lat - a.lat) / 2)^2 + cosd(a.lat) * cosd(b.lat) * sind((b.lon - a.lon) / 2)^2))

"""
    record_crossing(path, rows, grid, times, fields, ranges, fps)

Write one crossing's video: both maps and both along-track panels, one frame per FerryBox minute.
"""
function record_crossing(path, rows, grid, times, fields, ranges, fps)
    (; longitude, latitude, land) = grid
    n = length(rows)
    wet_cells = findall(.!land)
    cells = [nearest_wet(grid, wet_cells, r.lon, r.lat) for r in rows]
    northbound = rows[end].lat > rows[1].lat
    along = cumsum([0; [km(rows[k-1], rows[k]) for k in 2:n]])
    distance = northbound ? along[end] .- along : along

    frame = M.Observable(1)
    title = M.lift(f -> "$(CONFIG["run"]) surface and MS Color Fantasy's FerryBox, " *
                        "$(northbound ? "northbound" : "southbound"), $(Dates.format(rows[f].time, "yyyy-mm-dd HH:MM")) UTC", frame)
    passed(points) = M.lift(f -> [k <= f ? points[k] : M.Point2f(NaN, NaN) for k in 1:n], frame)

    aspect = (last(longitude) - first(longitude)) * cosd((first(latitude) + last(latitude)) / 2) /
             (last(latitude) - first(latitude))
    figure = M.Figure(size = (1400, 1350))
    M.Label(figure[0, 1:4], title; fontsize = 20, font = :bold)
    track = [M.Point2f(r.lon, r.lat) for r in rows]
    ship = M.lift(f -> track[f], frame)
    towns = [M.Point2f(lon, lat) for (_, lon, lat, _) in TOWNS]
    for (c, (var, label, colormap)) in enumerate(VARIABLES)
        colorrange = ranges[var]
        observed = [getfield(r, Symbol(var)) for r in rows]
        modelled = [point_at(fields[var], times, cells[k], rows[k].time) for k in 1:n]

        axis = M.Axis(figure[1, 2c-1]; xlabel = "Longitude (°E)", ylabel = "Latitude (°N)", aspect = M.AxisAspect(aspect))
        M.limits!(axis, extrema(longitude)..., extrema(latitude)...)
        field = M.lift(f -> field_at(fields[var], times, rows[f].time), frame)
        heatmap = M.heatmap!(axis, longitude, latitude, field; colormap, colorrange, nan_color = :magenta)
        M.heatmap!(axis, longitude, latitude, ifelse.(land, 1.0f0, NaN32); colormap = [LAND_COLOUR, LAND_COLOUR],
                   colorrange = (0, 2), nan_color = :transparent)
        M.scatter!(axis, towns; color = :black, markersize = 7)
        M.text!(axis, towns; text = [name for (name, _, _, _) in TOWNS],
                align = [(side == :left ? :right : :left, :center) for (_, _, _, side) in TOWNS],
                offset = [(side == :left ? -6 : 6, 0) for (_, _, _, side) in TOWNS], fontsize = 14, color = :black)
        # A minute without a value (dropped by NIVA's QC) is a gap in the track, outline included.
        measured = [isfinite(v) ? p : M.Point2f(NaN, NaN) for (p, v) in zip(track, observed)]
        M.lines!(axis, passed(measured); color = :black, linewidth = 7)
        M.lines!(axis, passed(measured); color = observed, colormap, colorrange, linewidth = 4)
        M.scatter!(axis, ship; color = :white, strokecolor = :black, strokewidth = 2, markersize = 16)
        M.Colorbar(figure[1, 2c], heatmap; label)

        profile = M.Axis(figure[2, 2c-1]; xlabel = "Distance along the track from its Oslo end (km)", ylabel = label)
        low, high = extrema(filter(isfinite, [observed; modelled]))
        M.limits!(profile, 0, maximum(distance), low - 0.05(high - low), high + 0.05(high - low))
        for (values, colour, name) in ((observed, COLORS["obs"], "FerryBox, 4 m"),
                                       (modelled, COLORS["fjordsim"], "FjordSim, top cell (0–1 m)"))
            points = M.Point2f.(distance, values)
            M.lines!(profile, passed(points); color = colour, linewidth = 2, label = name)
            M.scatter!(profile, M.lift(f -> points[f], frame); color = colour, markersize = 10)
        end
        c == 1 && M.axislegend(profile; position = :lt)
    end
    M.rowsize!(figure.layout, 2, M.Relative(0.22))

    M.record(figure, path, 1:n; framerate = fps) do f
        frame[] = f
    end
    println("Wrote $path")
    return path
end

"The colour range of a variable: the 1st–99th percentile of the day's wet model values, widened to the FerryBox's."
function colour_range(A, wet, observed)
    low, high = quantile(filter(isfinite, A[wet, :]), [0.01, 0.99])
    lo, hi = extrema(filter(isfinite, observed))
    return (min(low, lo), max(high, hi))
end

function main(args)
    day = Date(args[1])
    fps = length(args) > 1 ? parse(Int, args[2]) : 12
    grid = bathymetry_grid(joinpath(RUN_SETUP, "bathymetry.nc"))
    times, fields = jldopen(joinpath(REPORT_DATA, "ferry_fields_$day.jld2")) do f
        f["times"], Dict(var => f[var] for (var, _, _) in VARIABLES)
    end
    rows = ferrybox_day(day)
    ranges = Dict(var => colour_range(fields[var], .!grid.land, [getfield(r, Symbol(var)) for r in rows])
                  for (var, _, _) in VARIABLES)
    out = joinpath(REPORT, "video")
    mkpath(out)
    for crossing in crossings(rows)
        direction = crossing[end].lat > crossing[1].lat ? "northbound" : "southbound"
        record_crossing(joinpath(out, "ferry_$(day)_$direction.mp4"), crossing, grid, times, fields, ranges, fps)
    end
end

main(ARGS)
