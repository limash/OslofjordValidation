# The Drammensfjord section as a video: daily-mean S, T and velocity along the path, one frame per day,
# with the D-2 and D-3 casts shown for three days either side of their date, and the velocity profile
# on the Svelvik sill (DS-53): the day's mean and its hourly range.
#
#   REPORT=<name> julia --project src/section_video.jl [frames per second]
include("section_data.jl")
using CairoMakie

fps = isempty(ARGS) ? 15 : parse(Int, ARGS[1])
out = joinpath(REPORT, "video", "section_drammensfjord.mp4")
mkpath(dirname(out))

days = (length(sections[1].times) - 1) ÷ 24
dates = [START + Day(d - 1) for d in 1:days]
hours(d) = (24(d - 1) + 1):(24d)
field(var, n) = var == "along" ? along[n] : getfield(sections[n], Symbol(var))
"Daily mean of one variable along the section, station × level, surface last."
daily(var, d) = reduce(vcat, [[mean(field(var, n)[k, hours(d)]) for k in axes(field(var, n), 1)]' for n in eachindex(sections)])
flip(M) = M[:, end:-1:1]
nearby(var, d, code) = filter(p -> p.station == code && abs(Dates.value(Date(p.time) - Date(dates[d]))) <= 3 &&
                                   isfinite(getfield(p, Symbol(var))), casts)
"Cast strips at their place on the section: rectangle centres and values, or one invisible point."
function strips(var, d)
    xs, ys, vs = Float64[], Float64[], Float64[]
    for (code, n) in place, p in nearby(var, d, code)
        push!(xs, distance[n]); push!(ys, p.depth); push!(vs, getfield(p, Symbol(var)))
    end
    isempty(xs) && return [Point2f(NaN, NaN)], [NaN]
    return Point2f.(xs, ys), vs
end
"Outlines of the casts within three days, one closed rectangle each, separated by NaN."
function outlines(d)
    pts = Point2f[]
    for (code, n) in place
        ps = nearby("S", d, code); isempty(ps) && continue
        x = distance[n]; lo = minimum(p.depth for p in ps) - 0.5; hi = maximum(p.depth for p in ps) + 0.5
        append!(pts, Point2f.([x - 0.3, x + 0.3, x + 0.3, x - 0.3, x - 0.3, NaN], [lo, lo, hi, hi, lo, NaN]))
    end
    return isempty(pts) ? [Point2f(NaN, NaN)] : pts
end
sill_wet = findall(isfinite, along[sill][:, 1])
sill_depths = centres[sill_wet]
"The sill's velocity profile on day `d`: daily mean, and the lowest and highest hourly value, as (velocity, depth) points."
function sill_profile(d)
    V = along[sill][sill_wet, hours(d)]
    return (Point2f.(vec(mean(V, dims = 2)), sill_depths), Point2f.(vec(minimum(V, dims = 2)), sill_depths),
            Point2f.(vec(maximum(V, dims = 2)), sill_depths))
end

set_theme!(fontsize = 20)
fig = Figure(size = (2000, 1500))
title = Observable("")
Label(fig[0, 1:3], title, fontsize = 24, font = :bold)
fields = Dict{String,Any}()
outline = Observable(outlines(1))
route = "Drammenselva mouth (left) → Svelvik sill (dashed) → Breiangen (right)"
for (r, (var, label, crange, contours, cmap)) in enumerate((
        ("S", "Salinity (g/kg)", (24, 34), [25, 28, 29, 30, 31, 32, 33], :haline),
        ("T", "Temperature (°C)", (0, 20), [4, 6, 7, 8, 9, 10, 12, 15], :thermal),
        ("along", "Velocity (m/s), + out of the fjord", (-0.15, 0.15), Float64[], :balance)))
    M = Observable(flip(daily(var, 1)))
    fields[var] = M
    ax = Axis(fig[r, 1], title = "$label: $route", yreversed = true, ylabel = "depth (m)",
        xlabel = r == 3 ? "distance along the section (km)" : "")
    hm = heatmap!(ax, edges, reverse(faces), M, colormap = cmap, colorrange = crange, nan_color = :gray80)
    isempty(contours) || contour!(ax, distance, reverse(centres), M, levels = contours, color = :black, linewidth = 0.8,
        labels = true, labelsize = 13, labelcolor = :black)
    lines!(ax, distance, [s.depth for s in sections], color = :black, linewidth = 1.5)
    vlines!(ax, [distance[sill]], color = :black, linestyle = :dash, linewidth = 1)
    if var != "along"
        cast = Observable(strips(var, 1))
        fields["$(var)_casts"] = cast
        scatter!(ax, lift(first, cast), color = lift(last, cast), marker = Rect, markerspace = :data,
            markersize = (0.6, 1.0), colormap = cmap, colorrange = crange)
        lines!(ax, outline, color = :black, linewidth = 1)
        for (code, n) in place
            text!(ax, distance[n], 158, text = code, align = (:center, :bottom), fontsize = 15)
        end
    end
    xlims!(ax, edges[1], edges[end]); ylims!(ax, 160, 0)
    Colorbar(fig[r, 2], hm, label = label)
end

profile = Observable(sill_profile(1))
ax = Axis(fig[1:3, 3], title = "Svelvik sill (DS-53)", yreversed = true, ylabel = "depth (m)",
    xlabel = "velocity along the section (m/s)\n+ out of the fjord, − in")
band!(ax, lift(p -> p[2], profile), lift(p -> p[3], profile), color = (:gray50, 0.35), label = "hourly range in the day")
scatterlines!(ax, lift(first, profile), color = :black, linewidth = 3, markersize = 10, label = "daily mean")
vlines!(ax, [0], color = :black, linewidth = 0.8)
xlims!(ax, -1.2, 1.2); ylims!(ax, ceil(sections[sill].depth), 0)
axislegend(ax, position = :rb, labelsize = 15)
colsize!(fig.layout, 3, Relative(0.17))

record(fig, out, 1:days; framerate = fps) do d
    for var in ("S", "T", "along")
        fields[var][] = flip(daily(var, d))
    end
    fields["S_casts"][] = strips("S", d); fields["T_casts"][] = strips("T", d)
    outline[] = outlines(d)
    profile[] = sill_profile(d)
    title[] = "FjordSim Drammensfjord section, daily mean: " * Dates.format(dates[d], "yyyy-mm-dd") * "  (day $(d - 1))" *
              (isempty(nearby("S", d, "D-2")) && isempty(nearby("S", d, "D-3")) ? "" : "   outlined: NIVA casts within 3 days")
end
println("wrote ", out, ": ", days, " frames at ", fps, " fps")
