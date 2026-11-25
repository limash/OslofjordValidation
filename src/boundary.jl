# Does the error come in over the open boundary? FjordSim takes its boundary water from NorKyst v3 800 m (m00),
# so where both are wrong by the same amount in the outer fjord, the error is the boundary data's. As Dalsøren et
# al. (2020, Fig. 12) checked their fjord model against its parent near the boundary: the monthly bias of FjordSim
# and NorKyst v3 800 m on the same samples, in the upper layer (5–20 m) and below 50 m, at the NIVA stations
# NorKyst v3 800 m serves (`ctd_pairs.csv`) and at IMR's (`imr_pairs.csv`). Writes `boundary.csv` and
# `boundary.png`.
include("common.jl")
using CairoMakie
set_theme!(fontsize = 17)

const SOURCES = (("NIVA", "ctd_pairs.csv"), ("IMR", "imr_pairs.csv"))
const BANDS = (("5-20 m", 5, 20, "5–20 m"), (">50 m", 50, Inf, "Below 50 m"))
rows = String[]
series = Dict{Tuple{String,String,String},Any}()
for (source, file) in SOURCES, (band, top, bottom, _) in BANDS, var in ("T", "S")
    errors = Dict{Date,Vector{Tuple{Float64,Float64}}}()
    for p in readcsv(joinpath(REPORT_DATA, file))
        (ferrybox(p["station"]) || !(top <= num(p["depth"]) < bottom)) && continue
        t = DateTime(p["time"]); t >= SPINUP || continue
        o, f, n = num(p["obs_$var"]), num(p["fjordsim_$var"]), num(p["norkyst800_$var"])
        all(isfinite, (o, f, n)) || continue
        push!(get!(errors, Date(year(t), month(t)), Tuple{Float64,Float64}[]), (f - o, n - o))
    end
    months = sort(collect(keys(errors)))
    fs = [mean(first.(errors[m])) for m in months]; nk = [mean(last.(errors[m])) for m in months]
    series[(source, band, var)] = (; months, fs, nk)
    for (i, m) in enumerate(months)
        push!(rows, @sprintf("%s,%s,%s,%s,%d,%.2f,%.2f", source, band, var, Dates.format(m, "yyyy-mm"), length(errors[m]), fs[i], nk[i]))
    end
end
writecsv(joinpath(TABLES, "boundary.csv"), "source,band,variable,month,n,fjordsim_bias,norkyst800_bias", rows)

fig = Figure(size = (1800, 820))
for (r, var) in enumerate(("T", "S")), (c, (band, _, _, name)) in enumerate(BANDS)
    ax = Axis(fig[r, c], title = "$name: mean $(var == "T" ? "temperature" : "salinity") error by month",
        ylabel = c == 1 ? (var == "T" ? "°C" : "g/kg") : "", xlabel = r == 2 ? DAYS_LABEL : "")
    for (source, _) in SOURCES
        x = series[(source, band, var)]
        d = days_since_start.(DateTime.(x.months) .+ Day(14))
        style = source == "NIVA" ? :solid : :dash
        scatterlines!(ax, d, x.fs, color = COLORS["fjordsim"], linestyle = style, label = "FjordSim, $source casts")
        scatterlines!(ax, d, x.nk, color = COLORS["norkyst800"], linestyle = style, label = "NorKyst v3 800 m, $source casts")
    end
    hlines!(ax, 0, color = :gray60)
    (r, c) == (1, 2) && axislegend(ax, position = :lb, labelsize = 13)
end
save(joinpath(FIG, "boundary.png"), fig, px_per_unit = 1.2)
foreach(println, rows)
