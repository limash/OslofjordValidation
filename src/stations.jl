# Time-depth diagrams of T and S from the hourly hydrography station files (daily means), with the
# NIVA casts at each station drawn over them in the same colour scale.
include("common.jl")
using CairoMakie
set_theme!(fontsize = 17)

"Daily means of one variable at a station: day midpoints (days since START; the file starts at RUN_START), level faces as depths, matrix day × level."
function daily(code, var)
    paths = run_files("stations_hydrography", "_$(stem(code)).nc")
    _, V = read_joined(file -> Float64.(coalesce.(file[var][1, 1, :, :], NaN)), paths)
    NCDataset(first(paths)) do ds
        V[Array(ds["inactive_nodes_ccc"][1, 1, :]) .!= 0, :] .= NaN
        hours = size(V, 2) - 1
        days = hours ÷ 24
        D = [mean(V[k, (24(d - 1) + 1):(24d)]) for d in 1:days, k in axes(V, 1)]
        return collect(0.5:1:days) .+ days_since_start(RUN_START), -Float64.(ds["z_aaf"][:]), D, Float64(ds.attrib["model_water_depth"])
    end
end

# Sandefjord is SF-1 in the earlier runs and SF-3 from the 2026-11-20 run on: the stations the run wrote.
stations = filter(s -> !isempty(run_files("stations_hydrography", "_$(stem(s)).nc")),
                  ["OF-1", "LA-1", "SF-1", "SF-3", "TØ-1", "Ø-1", "S-9", "OF-5", "MO-2", "D-3", "D-2", "Dk1", "Ep1"])
casts = niva_casts(START, STOP + Day(1))
for (var, crange, contours, cmap, unit) in (("S", (20, 35.5), [30, 33], :haline, "g/kg"),
                                            ("T", (0, 22), [6, 12], :thermal, "°C"))
    fig = Figure(size = (1900, 1650))
    Label(fig[0, 1:3], "Hourly station output, daily means: $(var == "S" ? "salinity" : "temperature") against time and depth",
        fontsize = 22, font = :bold)
    local hm
    for (n, s) in enumerate(stations)
        r, c = fldmod1(n, 3)
        x, faces, D, depth = daily(s, var)
        # The deep water at OF-1 is uniform, so 200 m keeps its upper layers readable.
        zmax = min(depth, 200) + 2
        ax = Axis(fig[r, c], title = @sprintf("%s (%.0f m)", s, depth), yreversed = true,
            ylabel = c == 1 ? "depth (m)" : "", xlabel = r == 4 ? DAYS_LABEL : "")
        # Edges, so the irregular levels are drawn at their true thickness.
        hm = heatmap!(ax, vcat(0.0, x .+ 0.5), reverse(faces), D[:, end:-1:1], colormap = cmap, colorrange = crange,
            nan_color = :gray85)
        centres = [(faces[k] + faces[k+1]) / 2 for k in 1:length(faces)-1]
        any(isfinite, D) && contour!(ax, x, reverse(centres), D[:, end:-1:1], levels = contours, color = :white, linewidth = 1)
        cs = filter(p -> p.station == s && isfinite(getfield(p, Symbol(var))), casts)
        for t in unique(p.time for p in cs)
            q = filter(p -> p.time == t, cs)
            x0 = days_since_start(t); d = [p.depth for p in q]
            scatter!(ax, fill(x0, length(q)), d, marker = Rect, markerspace = :data, markersize = (6, 1.0),
                color = [getfield(p, Symbol(var)) for p in q], colormap = cmap, colorrange = crange)
            lines!(ax, [x0 - 3, x0 + 3, x0 + 3, x0 - 3, x0 - 3], [minimum(d) - 0.5, minimum(d) - 0.5, maximum(d) + 0.5,
                maximum(d) + 0.5, minimum(d) - 0.5], color = :black, linewidth = 0.8)
        end
        xlims!(ax, 0, days_since_start(STOP)); ylims!(ax, zmax, 0)
    end
    Colorbar(fig[1:4, 4], hm, label = "$var ($unit)")
    save(joinpath(FIG, "stations_$(var).png"), fig, px_per_unit = 1.1)
    println("saved stations ", var)
end
