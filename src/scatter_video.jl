# Observed against modelled S and T as a video: a window of five stations slides along a route through the
# Oslofjord, one station per frame, for each depth layer from the bottom up, and ends each layer on the
# Drammensfjord (D-3, D-2). A map on the right shows the window's stations. The route and the samples:
# `scatter_route.jl`; the NorKyst panel's title names the grids of the stations shown.
#
#   REPORT=<name> julia --project src/scatter_video.jl [frames per second]
include("scatter_route.jl")
using CairoMakie
set_theme!(fontsize = 16)

fps = isempty(ARGS) ? 2 : parse(Int, ARGS[1])
out = joinpath(REPORT, "video", "scatter_route")
mkpath(dirname(out))

const MIN_SAMPLES = 10
const PALETTE = parse.(RGBf, PALETTE_HEX)

# --- frames: (layer, stations, areas) ----------------------------------------------------------------
frames = []
for (name, lo, hi) in LAYERS
    has(s) = count(p -> p["station"] == s && in_layer(p, lo, hi), pairs) >= MIN_SAMPLES
    route = [(area, s) for (area, ss) in ROUTE for s in ss if has(s)]
    # A station keeps its colour along the layer's route: consecutive stations never share one.
    colour = [PALETTE[mod1(i, WINDOW)] for i in eachindex(route)]
    for k in 1:(length(route) - WINDOW + 1)
        w = k:(k + WINDOW - 1)
        push!(frames, (layer = name, lo, hi, stations = last.(route[w]), colours = colour[w], areas = unique(first.(route[w]))))
    end
    final = filter(has, last(FINAL))
    for _ in 1:2fps   # held two seconds at the end of the layer
        push!(frames, (layer = name, lo, hi, stations = final, colours = PALETTE[eachindex(final)], areas = [first(FINAL)]))
    end
end

limits_of = Dict((lo, v) => layer_limits(lo, hi, v) for (_, lo, hi) in LAYERS for v in ("S", "T"))

# --- the figure --------------------------------------------------------------------------------------
fig = Figure(size = (2000, 1060))
header = Label(fig[0, 1:4], "", fontsize = 26, font = :bold, tellwidth = false)
VAR_NAME = Dict("S" => "salinity (g/kg)", "T" => "temperature (°C)")
panels = Dict((v, k) => Axis(fig[r, c], aspect = 1, xlabel = "observed", ylabel = c == 1 ? "modelled" : "")
             for (r, v) in enumerate(("S", "T")) for (c, k) in enumerate(MODELS))
mapax = Axis(fig[1:2, 4], title = "Stations in the panels", xlabel = "Longitude (°E)", ylabel = "Latitude (°N)",
    aspect = AxisAspect((lon[end] - lon[1]) * cosd(59.4) / (lat[end] - lat[1])))
heatmap!(mapax, lon, lat, depth, colormap = cgrad([RGBf(0.93, 0.95, 0.97), RGBf(0.55, 0.62, 0.70)]), colorrange = (0, 350),
    nan_color = RGBf(0.97, 0.96, 0.93))
everyone = sort(unique(p["station"] for p in pairs))
for (imr, marker) in ((false, :circle), (true, :diamond))
    ss = filter(s -> (s in imr_names) == imr, everyone)
    scatter!(mapax, [station_position[s][1] for s in ss], [station_position[s][2] for s in ss], marker = marker, color = :gray60,
        markersize = 9, strokecolor = :gray30, strokewidth = 0.5, label = imr ? "IMR casts" : "NIVA casts")
end
axislegend(mapax, position = :lt, labelsize = 14)
limits!(mapax, lon[1], lon[end], lat[1], lat[end])
Label(fig[3, 1:4], NORKYST_NOTE * " NIVA and IMR casts from $(Date(SPINUP)); NorFjords ends on 2026-06-30. Stations with at least $MIN_SAMPLES samples in the layer.",
    fontsize = 15, color = :gray30, tellwidth = false)
colsize!(fig.layout, 4, Auto(1.25))
overlay = []

function draw!(f)
    header.text[] = "Depth $(f.layer) · $(join(f.areas, " → "))"
    for v in ("S", "T"), k in MODELS
        ax = panels[(v, k)]; empty!(ax)
        ps = filter(p -> p["station"] in f.stations && in_layer(p, f.lo, f.hi) && isfinite(p["obs_$v"]) && isfinite(p["$(k)_$v"]), pairs)
        grids = sort(unique(p["grid_$v"] for p in ps))
        name = k == "norkyst" ? "NorKyst v3 " * (isempty(grids) ? "" : join(grids, " + ")) : LABELS[k]
        ax.title = "$name, $(VAR_NAME[v])"
        for (s, c) in zip(f.stations, f.colours)
            q = filter(p -> p["station"] == s, ps)
            isempty(q) || scatter!(ax, [p["obs_$v"] for p in q], [p["$(k)_$v"] for p in q], color = (c, 0.5), markersize = 6)
        end
        a, b = limits_of[(f.lo, v)]
        lines!(ax, [a, b], [a, b], color = :black)
        limits!(ax, a, b, a, b)
    end
    foreach(p -> delete!(mapax, p), overlay); empty!(overlay)
    # A label goes left of its station when another station of the frame lies just to its right.
    for (s, c) in zip(f.stations, f.colours)
        x, y = station_position[s]
        right = !any(0 < station_position[o][1] - x < 0.25 && abs(station_position[o][2] - y) < 0.02 for o in f.stations)
        push!(overlay, scatter!(mapax, [x], [y], marker = s in imr_names ? :diamond : :circle, color = c, markersize = 20,
            strokecolor = :black, strokewidth = 1.2))
        push!(overlay, text!(mapax, x + (right ? 0.015 : -0.015), y, text = s, font = :bold, fontsize = 17,
            align = (right ? :left : :right, :center)))
    end
end

for ext in (".mp4", ".gif")
    record(draw!, fig, out * ext, frames; framerate = fps)
end
println("frames: ", length(frames), "  ", out, ".{mp4,gif}")
