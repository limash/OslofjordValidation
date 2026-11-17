# Exchange over the Svelvik sill and where the inflow goes in the Drammensfjord basin: the run-mean
# velocity along the section at the sill (DS-53) and in the basin (DS-40), and how often the inflow
# reaches each basin depth.
include("section_data.jl")

days = (length(sections[1].times) - 1) ÷ 24
daily(V) = [mean(V[k, (24(d - 1) + 1):(24d)]) for k in axes(V, 1), d in 1:days]
rows = String[]
for name in ("DS-53", "DS-44", "DS-40", "DS-30")
    n = findfirst(s -> s.name == name, sections)
    D = daily(along[n])
    for k in axes(D, 1)
        isfinite(D[k, 1]) || continue
        push!(rows, @sprintf("%s,%.1f,%.4f,%.2f,%.3f", name, centres[k], mean(D[k, :]), count(<(-0.01), D[k, :]) / days,
            minimum(D[k, :])))
    end
end
writecsv(joinpath(TABLES, "sill_exchange.csv"), "station,depth_m,mean_along_ms,fraction_days_inflow_gt_1cms,strongest_daily_inflow_ms", rows)
foreach(println, rows)
