# MS Color Fantasy's crossings of one day as videos. Maps of FjordSim's surface T and S, as in the surface videos,
# with the ship's track coloured by the FerryBox's measured values on the same scale; below each map, the values
# along the track: the FerryBox (4 m) and FjordSim's top cell at the ship's cell and minute, fixed once the ship
# has passed. The hourly fields (`bin/vm_run.sh <report> ferry <day>`) are interpolated linearly to each minute,
# one frame per FerryBox minute. One MP4 per crossing, named by its direction, in output/<report>/video/.
#
#   REPORT=<name> julia --project src/ferry_video.jl <yyyy-mm-dd> [frames per second]
include("ferry_track.jl")
import CairoMakie as M

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
    times, fields = ferry_fields(day)
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
