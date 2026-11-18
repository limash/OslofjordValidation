# Currents in the Svelvik strait from the hourly section, beside the currents Staalstrøm and Hjelmervik (2017,
# Vann 52(1), 104-115) measured there, and the surface outflow beside Drammenselva's discharge (their Fig. 8).
# The strait is the section station with the strongest depth-mean current, the model's narrowest cross-section;
# the sill (DS-53), the section's shallowest point, lies about 2 km south of it.
# Writes `svelvik_currents.csv`, `svelvik_outflow.csv` and `svelvik_currents.png`.
include("section_data.jl")
using CairoMakie
set_theme!(fontsize = 17)

# Their Table 1: one month of ADCP in the strait in 1999. Depth (m), the month's mean current and the upper
# quartile of the speed (m/s), signed by the direction of the strongest currents. Their sign is − out of the
# fjord; here + is out, as `along` is.
const OBSERVED = [(1, 0.6, 1.1), (3, 0.7, 1.3), (5, 0.6, 1.2), (7, 0.2, 0.8), (9, -0.1, -0.7), (11, -0.2, -0.8)]

keep = findall(>=(SPINUP), sections[1].times)
times = sections[1].times[keep]
wet(A) = [k for k in axes(A, 1) if all(isfinite, A[k, :])]
"The thickness-weighted mean of `A` over `levels`, hour by hour."
layer_mean(A, levels) = (dz = [faces[k] - faces[k+1] for k in levels]; vec(sum(A[levels, :] .* dz, dims = 1) ./ sum(dz)))
strait = argmax([quantile(abs.(layer_mean(along[n][:, keep], wet(along[n]))), 0.75) for n in eachindex(sections)])
s = sections[strait]
println("strait: ", s.name, @sprintf(", %.1f m deep, %.4f°E %.4f°N", s.depth, s.lon, s.lat))
A = along[strait][:, keep]
levels = wet(A)
months = unique((year(t), month(t)) for t in times)

rows = String[]
for (d, m, q) in OBSERVED
    push!(rows, @sprintf("observed,strait,%.1f,%.2f,NaN,NaN,%.2f,NaN", d, m, q))
end
for k in sort(levels, by = k -> centres[k])
    a = A[k, :]
    monthly = [mean(a[[(year(t), month(t)) == ym for t in times]]) for ym in months]
    q = quantile(abs.(a), 0.75)
    direction = sign(mean(a[abs.(a) .>= q]))
    push!(rows, @sprintf("fjordsim,%s,%.1f,%.3f,%.3f,%.3f,%.3f,%.3f", s.name, centres[k], mean(a), minimum(monthly), maximum(monthly),
        direction * q, count(x -> abs(x) > 1.3, a) / length(a)))
end
writecsv(joinpath(TABLES, "svelvik_currents.csv"),
    "source,station,depth_m,mean_ms,monthly_mean_min_ms,monthly_mean_max_ms,upper_quartile_ms,fraction_over_1.3ms", rows)
foreach(println, rows)

# The outflowing layer: the top three cells (0-3.7 m), thickness-weighted, as a 60 h running mean (their Fig. 8
# smooths the top 3 m of the Saltskjær ADCP so), read at noon each day beside the day's Drammenselva discharge.
layer = layer_mean(A, [k for k in levels if faces[k+1] < 3.71])
smooth = [mean(layer[max(1, n - 30):min(end, n + 29)]) for n in eachindex(layer)]
river_times, discharge = NCDataset(joinpath(RUN_SETUP, "rivers_nve.nc")) do ds
    r = findfirst(==("Drammenselva"), ds["river_name"][:])
    ds["time"][:], Float64.(ds["discharge"][r, :])
end
out = String[]
for (n, t) in enumerate(times)
    hour(t) == 12 || continue
    r = findfirst(==(DateTime(Date(t))), river_times)
    isnothing(r) || push!(out, @sprintf("%s,%.3f,%.1f", Date(t), smooth[n], discharge[r]))
end
writecsv(joinpath(TABLES, "svelvik_outflow.csv"), "date,outflow_0_3.7m_ms,drammenselva_m3s", out)

fig = Figure(size = (1600, 620))
ax = Axis(fig[1, 1], title = "$(s.name), along-strait current (+ out of the fjord)", xlabel = "m/s", ylabel = "depth (m)",
    yreversed = true)
z = [centres[k] for k in sort(levels, by = k -> centres[k])]
model = filter(r -> startswith(r, "fjordsim"), rows) .|> (r -> parse.(Float64, split(r, ",")[3:end]))
band!(ax, z, [m[3] for m in model], [m[4] for m in model], direction = :y, color = (COLORS["fjordsim"], 0.2))
lines!(ax, [m[2] for m in model], z, color = COLORS["fjordsim"], linewidth = 3, label = "FjordSim mean (band: monthly means)")
lines!(ax, [m[5] for m in model], z, color = COLORS["fjordsim"], linewidth = 2, linestyle = :dash,
    label = "FjordSim upper-quartile speed")
scatter!(ax, [o[2] for o in OBSERVED], [o[1] for o in OBSERVED], color = :black, markersize = 14, label = "observed 1999, mean")
scatter!(ax, [o[3] for o in OBSERVED], [o[1] for o in OBSERVED], color = :white, strokecolor = :black, strokewidth = 2,
    markersize = 14, label = "observed 1999, upper-quartile speed")
vlines!(ax, 0, color = :gray60)
ylims!(ax, 13.5, 0)
axislegend(ax, position = :rb, labelsize = 13)
dates = [Date(split(r, ",")[1]) for r in out]
x = days_since_start.(DateTime.(dates))
ax2 = Axis(fig[1, 2], title = "$(s.name), top 3.7 m: 60 h running mean current (left) and Drammenselva discharge (right)",
    xlabel = DAYS_LABEL, ylabel = "m/s out of the fjord")
ax3 = Axis(fig[1, 2], ylabel = "m³/s", yaxisposition = :right)
hidespines!(ax3); hidexdecorations!(ax3)
lines!(ax2, x, [parse(Float64, split(r, ",")[2]) for r in out], color = COLORS["fjordsim"], linewidth = 2)
lines!(ax3, x, [parse(Float64, split(r, ",")[3]) for r in out], color = :black, linewidth = 1.5)
linkxaxes!(ax2, ax3)
colsize!(fig.layout, 1, Relative(0.35))
save(joinpath(FIG, "svelvik_currents.png"), fig, px_per_unit = 1.2)
println("svelvik done")
