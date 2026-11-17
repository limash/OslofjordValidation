# Time-depth diagrams of T and S at the CTD stations: FjordSim, NorKyst-v3 and NorFjords-160m (daily means,
# NorFjords to 2026-06-30), each at the column the CTD scoring uses, with the casts drawn over them in the same
# colour scale.
include("common.jl")
using JLD2, CairoMakie
set_theme!(fontsize = 17)

run = load(joinpath(REPORT_DATA, "extract.jld2"))
norkyst = load(joinpath(REPORT_DATA, "norkyst_columns.jld2"), "columns")
norfjords = load(joinpath(REPORT_DATA, "norfjords_columns.jld2"), "columns")
cells = Dict(r["station"] => r for r in readcsv(joinpath(REPORT_DATA, "cells.csv")))
pairs = readcsv(joinpath(REPORT_DATA, "ctd_pairs.csv"))
const RUN_END = min(last(run["times"]), STOP)

"Each model's daily columns at a station on a 1 m depth grid, as (label, days since start, depths, matrix depth × day)."
function panels(s, var, zmax)
    z = collect(0.5:1.0:zmax)
    c = findfirst(==(s), run["names"])
    fs = reduce(hcat, [[interp(run["z"], run[var][:, c, n], d) for d in z] for n in eachindex(run["times"])])
    reference(col) = (V = var == "S" ? col.daily_S : col.daily_T;
        reduce(hcat, [[interp(depths(col, k), V[:, k], d) for d in z] for k in eachindex(col.days)]))
    return [("FjordSim", days_since_start.(run["times"]), z, fs),
            ("NorKyst v3 $(replace(norkyst[s].grid, "m" => " m"))", days_since_start.(norkyst[s].days), z, reference(norkyst[s])),
            ("NorFjords 160 m", days_since_start.(norfjords[s].days), z, reference(norfjords[s]))]
end

groups = [
    ("outer", "Outer fjord", ["LA-1", "VAL-1", "S-9", "Ø-1"], (20, 35.5), [25, 30, 33, 34.5]),
    ("middle", "Breiangen, Mossesundet and the Drøbak Sound", ["SAN-5", "MO-2", "Im2"], (20, 35.5), [25, 30, 33, 34.5]),
    ("drammen", "Drammensfjord", ["D-2", "D-3"], (0, 35), [10, 20, 30, 32]),
    ("inner", "Inner Oslofjord", ["Fl1", "Dk1", "Ep1"], (20, 35.5), [25, 30, 32, 33, 34]),
]
for (key, title, stations, srange, scontours) in groups, (var, crange, contours, cmap, unit) in
        (("S", srange, scontours, :haline, "g/kg"), ("T", (0, 24), [5, 10, 15], :thermal, "°C"))
    fig = Figure(size = (520 * length(stations) + 160, 1150))
    Label(fig[0, 1:length(stations)], "$title: $(var == "S" ? "salinity" : "temperature") against time and depth, casts overlaid",
        fontsize = 22, font = :bold)
    local hm
    for (c, s) in enumerate(stations)
        ps = filter(p -> p["station"] == s && isfinite(num(p["obs_$var"])), pairs)
        zmax = min(maximum((num(p["depth"]) for p in ps); init = Inf), num(cells[s]["model_depth_m"])) + 2
        for (r, (label, x, z, M)) in enumerate(panels(s, var, zmax))
            ax = Axis(fig[r, c], title = "$s  $label", yreversed = true, ylabel = c == 1 ? "depth (m)" : "",
                xlabel = r == 3 ? DAYS_LABEL : "")
            hm = heatmap!(ax, x, z, permutedims(M), colormap = cmap, colorrange = crange, nan_color = :gray85)
            any(isfinite, M) && contour!(ax, x, z, permutedims(M), levels = contours, color = :white, linewidth = 1.2)
            # Each cast as a strip six days wide, one 1 m sample per row, outlined as a whole.
            for t in unique(p["time"] for p in ps)
                q = filter(p -> p["time"] == t, ps)
                x0 = days_since_start(DateTime(t)); d = [num(p["depth"]) for p in q]
                scatter!(ax, fill(x0, length(q)), d, marker = Rect, markerspace = :data, markersize = (6, 1.0),
                    color = [num(p["obs_$var"]) for p in q], colormap = cmap, colorrange = crange)
                lines!(ax, [x0 - 3, x0 + 3, x0 + 3, x0 - 3, x0 - 3], [minimum(d) - 0.5, minimum(d) - 0.5, maximum(d) + 0.5,
                    maximum(d) + 0.5, minimum(d) - 0.5], color = :black, linewidth = 0.8)
            end
            xlims!(ax, 0, days_since_start(RUN_END)); ylims!(ax, zmax, 0)
        end
    end
    Colorbar(fig[1:3, length(stations) + 1], hm, label = "$var ($unit)")
    save(joinpath(FIG, "hovmoller_$(key)_$(var).png"), fig, px_per_unit = 1.1)
    println("saved ", key, " ", var)
end
