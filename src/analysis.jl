# Water level against Kartverket, FjordSim, NorKyst-v3 (`norkyst_columns.jld2`) and NorFjords-160m
# (`norfjords_columns.jld2`), and whole-domain statistics.
#
#   julia analysis.jl [section numbers...]
include("common.jl")
include("tides.jl")
using JLD2, CairoMakie
set_theme!(fontsize = 18)

const SECTIONS = isempty(ARGS) ? (1, 2) : parse.(Int, ARGS)

# =================================================================================================
# 1. Water level
# =================================================================================================
if 1 in SECTIONS
gauges = [(name = "Viker", longitude = 10.949769, latitude = 59.036046),
          (name = "Oscarsborg", longitude = 10.604861, latitude = 59.678073),
          (name = "Oslo", longitude = 10.734510, latitude = 59.908559)]
window = (SPINUP, STOP)
# Only constituents the window separates (Rayleigh: frequencies at least one cycle per window apart),
# taken in order of size at these gauges; over a few months that drops SA, SSA, P1 (beside K1) and K2 (beside S2).
function separable(window)
    window_hours = Dates.value(window[2] - window[1]) / 3.6e6
    set = TidalConstituent[]
    for name in ("M2", "S2", "N2", "K1", "O1", "M4", "Q1", "MS4", "MN4", "K2", "P1", "SSA", "SA")
        c = TIDAL_CONSTITUENTS[findfirst(x -> x.name == name, TIDAL_CONSTITUENTS)]
        all(x -> abs(1 / c.period_hours - 1 / x.period_hours) >= 1 / window_hours, set) && 1 / c.period_hours >= 1 / window_hours &&
            push!(set, c)
    end
    return set
end
fit_set = separable(window)
println("fitted constituents: ", join((c.name for c in fit_set), " "))
ref = SPINUP
nk_levels = load(joinpath(REPORT_DATA, "norkyst_columns.jld2"), "levels")
level = Dict{String,Any}()
for g in gauges
    obs = kartverket_series(g.name, window)
    mod = read_station_jld2(joinpath(RES, "stations_tidegauge_$(STAMP)_$(g.name).jld2"), "η", RUN_START)
    tt, o, mm = match_series(obs, mod; tolerance = Minute(5))
    ok = isfinite.(mm) .& isfinite.(o) .& (window[1] .<= tt .<= window[2]); tt, mm, o = tt[ok], mm[ok], o[ok]
    fo = harmonic_fit(tt, o; constituents = fit_set, reference = ref)
    fm = harmonic_fit(tt, mm; constituents = fit_set, reference = ref)
    ro = o .- reconstruct(fo, tt); rm = mm .- reconstruct(fm, tt)
    # NorKyst, hourly, on the observed hours.
    nk = nk_levels[g.name]
    tn, on, nn = match_series(obs, ModelSeries(g.name, "eta", nk.times, [0.0], reshape(nk.η, :, 1), Dict{String,Any}());
        tolerance = Minute(5))
    okn = isfinite.(nn) .& isfinite.(on) .& (window[1] .<= tn .<= window[2]); tn, on, nn = tn[okn], on[okn], nn[okn]
    fn = harmonic_fit(tn, nn; constituents = fit_set, reference = ref)
    rn = nn .- reconstruct(fn, tn); ron = on .- reconstruct(fo, tn)
    level[g.name] = (; t = tt, o, m = mm, ro, rm, fo, fm, tn, on, nn, rn, ron, fn, grid = nk.grid)
end

# NorFjords keeps hourly ζ for 2024 only, so its tide is fitted over 2024, against Kartverket over the
# same year and with the same reference time; its daily-mean ζ covers the window to 2026-06-30.
nf = load(joinpath(REPORT_DATA, "norfjords_columns.jld2"))
year2024 = (DateTime(2024, 1, 1), DateTime(2025, 1, 1))
fit_year = separable(year2024)
println("fitted over 2024: ", join((c.name for c in fit_year), " "))
nf_tide = Dict{String,Any}()
for g in gauges
    obs = kartverket_series(g.name, year2024)
    h = nf["hourly"][g.name]
    t4, o4, m4 = match_series(obs, ModelSeries(g.name, "eta", h.times, [0.0], reshape(h.η, :, 1), Dict{String,Any}());
        tolerance = Minute(5))
    local ok = isfinite.(o4) .& isfinite.(m4); t4, o4, m4 = t4[ok], o4[ok], m4[ok]
    nf_tide[g.name] = (; n = length(t4), fo = harmonic_fit(t4, o4; constituents = fit_year, reference = ref),
                       ff = harmonic_fit(t4, m4; constituents = fit_year, reference = ref))
end

"Daily means of `x` at `times`, on the days with at least 90 % of `per_day` samples."
function daily_means(times, x, per_day)
    days = Date.(times); out = Dict{Date,Float64}()
    for d in unique(days)
        sel = days .== d
        count(sel) >= 0.9per_day && (out[d] = mean(x[sel]))
    end
    return out
end
# The weather-driven water level of every model as daily means, which leave out the tide without a fit:
# NorFjords' files are daily means.
daily_rows = String[]
daily_level = Dict{Tuple{String,String},Any}()
for g in gauges
    obs = kartverket_series(g.name, window)
    od = daily_means(obs.times, obs.values[:, 1], 144)
    L = level[g.name]; lv = nf["levels"][g.name]
    series = ("FjordSim" => daily_means(L.t, L.m, 144), "NorKyst $(replace(L.grid, "m" => " m"))" => daily_means(L.tn, L.nn, 24),
              "NorFjords 160 m" => Dict(Date(t) => v for (t, v) in zip(lv.days, lv.η) if window[1] <= t <= window[2] && isfinite(v)))
    for (name, md) in series
        days = sort(collect(intersect(keys(od), keys(md))))
        o = [od[d] for d in days]; m = [md[d] for d in days]; o = o .- mean(o); m = m .- mean(m)
        push!(daily_rows, @sprintf("%s,%s,%d,%.3f,%.3f,%.2f,%.2f,%.2f", name, g.name, length(days), cor(o, m), sqrt(mean((o - m) .^ 2)),
            std(m) / std(o), minimum(o), minimum(m)))
        daily_level[(name, g.name)] = (; days, o, m)
    end
end
writecsv(joinpath(TABLES, "waterlevel_daily.csv"), "model,station,days,r,rmse_m,std_ratio,obs_lowest_m,model_lowest_m", daily_rows)

# NorKyst v3's own sea level at its wet point nearest the open boundary south of Viker, before the
# Viker tide correction the prepared boundary file applies (`norkyst_fetch.jl boundary`).
bt, bz = load(joinpath(DATA, "norkyst_v3_stations", "boundary_zeta.jld2"), "times", "η")
ok = isfinite.(bz) .& (window[1] .<= bt .<= window[2])
fb = harmonic_fit(bt[ok], bz[ok]; constituents = fit_set, reference = ref)

index(f, name) = findfirst(c -> c.name == name, f.constituents)
amp(f, name) = 100f.amplitude[index(f, name)]
phase_difference(a, b, name) = mod(a.phase[index(a, name)] - b.phase[index(b, name)] + 180, 360) - 180
consts = ["M2", "S2", "N2", "O1", "K1", "M4"]
rows = String[]
for g in gauges, c in consts
    L = level[g.name]
    push!(rows, @sprintf("%s,%s,%.1f,%.1f,%.0f,%s,%.1f,%.0f,%.1f", g.name, c, amp(L.fo, c), amp(L.fm, c), phase_difference(L.fm, L.fo, c),
        norkyst_key(L.grid), amp(L.fn, c), phase_difference(L.fn, L.fo, c), amp(fb, c)))
end
# `norkyst_model` is the NorKyst grid at the gauge; `norkyst800_boundary_cm` is the 800 m run's sea level at the
# open boundary, which FjordSim's boundary data come from, before the Viker correction.
writecsv(joinpath(TABLES, "tides.csv"), "station,constituent,kartverket_obs_cm,fjordsim_cm,fjordsim_minus_obs_phase_deg,norkyst_model,norkyst_cm,norkyst_minus_obs_phase_deg,norkyst800_boundary_cm", rows)
rows = String[]
for g in gauges, c in consts
    F = nf_tide[g.name]
    push!(rows, @sprintf("%s,%s,%d,%.1f,%.1f,%.0f", g.name, c, F.n, amp(F.fo, c), amp(F.ff, c), phase_difference(F.ff, F.fo, c)))
end
writecsv(joinpath(TABLES, "tides_norfjords_2024.csv"), "station,constituent,hours,kartverket_obs_cm,norfjords_cm,norfjords_minus_obs_phase_deg", rows)
rows = String[]
for g in gauges
    L = level[g.name]
    o = L.o .- mean(L.o); m = L.m .- mean(L.m); ro = L.ro .- mean(L.ro); rm = L.rm .- mean(L.rm)
    push!(rows, @sprintf("FjordSim,%s,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.2f,%.2f,%.2f", g.name, length(o), mean(L.m) - mean(L.o),
        cor(o, m), sqrt(mean((o - m) .^ 2)), cor(ro, rm), sqrt(mean((ro - rm) .^ 2)), std(rm) / std(ro),
        maximum(L.o) - mean(L.o), maximum(L.m) - mean(L.m)))
    o = L.on .- mean(L.on); m = L.nn .- mean(L.nn); ro = L.ron .- mean(L.ron); rm = L.rn .- mean(L.rn)
    push!(rows, @sprintf("NorKyst %s,%s,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.2f,%.2f,%.2f", replace(L.grid, "m" => " m"), g.name, length(o),
        mean(L.nn) - mean(L.on), cor(o, m), sqrt(mean((o - m) .^ 2)), cor(ro, rm), sqrt(mean((ro - rm) .^ 2)), std(rm) / std(ro),
        maximum(L.on) - mean(L.on), maximum(L.nn) - mean(L.nn)))
end
writecsv(joinpath(TABLES, "waterlevel.csv"), "model,station,n,mean_offset_m,r_total,crmse_total_m,r_residual,rmse_residual_m,std_ratio_residual,obs_max_above_mean_m,model_max_above_mean_m", rows)

# The weather-driven water level scored in 5-day windows with Duveiller et al.'s (2016) λ, as Dalsøren et al.
# (2020) score fjord currents: λ is the correlation r lowered for any bias in mean or variance, 0 where r < 0.
# A window is good at λ ≥ 0.05 (their λcrit); below that it is poor when the model's mean anomaly over the window
# has the wrong sign (their "transport in the wrong direction"), else medium. Each series is taken minus its
# mean over the whole window, so a window's offset counts. Windows with under 90 % of their samples are skipped.
"Duveiller et al.'s (2016) λ of model `x` against observed `y`."
function lambda(x, y)
    r = cor(x, y)
    κ = r >= 0 ? 0.0 : 2abs(mean((x .- mean(x)) .* (y .- mean(y))))
    return max(0.0, 1 - mean((x .- y) .^ 2) / (var(x, corrected = false) + var(y, corrected = false) + (mean(x) - mean(y))^2 + κ))
end
const LAMBDA_CRIT = 0.05
lambda_rows = String[]
for g in gauges
    L = level[g.name]
    for (name, t, o, m, per_window) in (("FjordSim", L.t, L.ro .- mean(L.ro), L.rm .- mean(L.rm), 720),
                                         ("NorKyst $(replace(L.grid, "m" => " m"))", L.tn, L.ron .- mean(L.ron), L.rn .- mean(L.rn), 120))
        for w0 in SPINUP:Day(5):(STOP - Day(5))
            sel = findall(x -> w0 <= x < w0 + Day(5), t)
            length(sel) >= 0.9per_window || continue
            λ = lambda(m[sel], o[sel])
            class = λ >= LAMBDA_CRIT ? "good" : (sign(mean(m[sel])) != sign(mean(o[sel])) ? "poor" : "medium")
            push!(lambda_rows, @sprintf("%s,%s,%s,%.3f,%.3f,%.3f,%.3f,%s", name, g.name, Date(w0), λ, cor(m[sel], o[sel]),
                std(m[sel]) / std(o[sel]), std(o[sel]), class))
        end
    end
end
writecsv(joinpath(TABLES, "waterlevel_lambda.csv"), "model,station,window_start,lambda,r,std_ratio,obs_std_m,class", lambda_rows)
fig = Figure(size = (1500, 900))
for (n, g) in enumerate(gauges)
    ax = Axis(fig[n, 1], title = "$(g.name): λ of the weather-driven water level in 5-day windows", ylabel = "λ",
        xlabel = n == length(gauges) ? DAYS_LABEL : "")
    for name in unique(split(r, ",")[1] for r in lambda_rows)
        rs = [split(r, ",") for r in lambda_rows if startswith(r, name * ",") && split(r, ",")[2] == g.name]
        key = name == "FjordSim" ? "fjordsim" : norkyst_key(replace(split(name)[2], " " => ""))
        scatterlines!(ax, days_since_start.(DateTime.(getindex.(rs, 3))) .+ 2.5, parse.(Float64, getindex.(rs, 4)),
            color = COLORS[key], markersize = 7, label = name)
    end
    hlines!(ax, LAMBDA_CRIT, color = :black, linestyle = :dash)
    ylims!(ax, 0, 1)
    n == 1 && axislegend(ax, position = :lb)
end
save(joinpath(FIG, "waterlevel_lambda.png"), fig, px_per_unit = 1.3)

fig = Figure(size = (1500, 520))
for (n, g) in enumerate(gauges)
    ax = Axis(fig[1, n], title = g.name, ylabel = n == 1 ? "amplitude (cm)" : "", xticks = (1:length(consts), consts))
    xs = 1:length(consts); w = 0.2
    L = level[g.name]; F = nf_tide[g.name]
    barplot!(ax, xs .- 1.5w, [amp(L.fo, c) for c in consts], width = w, color = COLORS["obs"], label = "observed (Kartverket)")
    barplot!(ax, xs .- 0.5w, [amp(L.fm, c) for c in consts], width = w, color = COLORS["fjordsim"], label = LABELS["fjordsim"])
    barplot!(ax, xs .+ 0.5w, [amp(L.fn, c) for c in consts], width = w, color = COLORS[norkyst_key(L.grid)])
    barplot!(ax, xs .+ 1.5w, [amp(F.ff, c) for c in consts], width = w, color = COLORS["norfjords"])
    scatter!(ax, xs .+ 1.5w, [amp(F.fo, c) for c in consts], color = :black, marker = :hline, markersize = 20)
    scatter!(ax, xs .+ 0.5w, [amp(fb, c) for c in consts], color = :gray45, marker = :hline, markersize = 20)
end
fig[2, 1:3] = Legend(fig,
    [[PolyElement(color = COLORS[k]) for k in ("obs", ALL_MODELS...)];
     [MarkerElement(color = c, marker = :hline, markersize = 20) for c in (:black, :gray45)]],
    ["observed (Kartverket)", LABELS["fjordsim"], LABELS["norkyst160"], LABELS["norkyst800"],
     "$(LABELS["norfjords"]), fitted over 2024", "observed over 2024",
     "$(LABELS["norkyst800"]) at the open boundary, uncorrected"],
    orientation = :horizontal, nbanks = 2, framevisible = false)
save(joinpath(FIG, "tide_amplitudes.png"), fig, px_per_unit = 1.5)

# Three weeks around the window's largest weather-driven excursion at Oscarsborg.
L = level["Oscarsborg"]
event_day = Date(L.t[argmax(abs.(L.ro .- mean(L.ro)))])
event = (DateTime(event_day) - Day(11), DateTime(event_day) + Day(12))
println("water-level close-up: ", event[1], " .. ", event[2])
fig = Figure(size = (1500, 1000))
for (n, g) in enumerate(gauges)
    L = level[g.name]
    sel = findall(t -> event[1] <= t < event[2], L.t)
    x = [Dates.value(t - event[1]) / 86_400_000 for t in L.t[sel]]
    ax = Axis(fig[n, 1], title = "$(g.name): total water level, each minus its own mean", ylabel = "m",
        xlabel = n == 3 ? "days from $(Date(event[1]))" : "")
    lines!(ax, x, L.o[sel] .- mean(L.o), color = COLORS["obs"], label = "observed")
    lines!(ax, x, L.m[sel] .- mean(L.m), color = COLORS["fjordsim"], label = LABELS["fjordsim"])
    seln = findall(t -> event[1] <= t < event[2], L.tn)
    lines!(ax, [Dates.value(t - event[1]) / 86_400_000 for t in L.tn[seln]], L.nn[seln] .- mean(L.nn),
        color = COLORS[norkyst_key(L.grid)], label = LABELS[norkyst_key(L.grid)])
    axislegend(ax, position = :lt)
end
save(joinpath(FIG, "waterlevel_event.png"), fig, px_per_unit = 1.5)

# The non-tidal residual at Oscarsborg over the whole period, daily means.
fig = Figure(size = (1500, 480))
L = level["Oscarsborg"]
days = unique(Date.(L.t)); dt = Date.(L.t)
dm(x) = [mean(x[dt .== d]) for d in days]
ax = Axis(fig[1, 1], title = "Oscarsborg: non-tidal water level (series minus its own fitted tide), daily means", ylabel = "m",
    xlabel = DAYS_LABEL)
lines!(ax, days_since_start.(DateTime.(days)), dm(L.ro .- mean(L.ro)), color = COLORS["obs"], label = "observed")
lines!(ax, days_since_start.(DateTime.(days)), dm(L.rm .- mean(L.rm)), color = COLORS["fjordsim"], label = LABELS["fjordsim"])
daysn = unique(Date.(L.tn)); dtn = Date.(L.tn)
lines!(ax, days_since_start.(DateTime.(daysn)), [mean((L.rn .- mean(L.rn))[dtn .== d]) for d in daysn],
    color = COLORS[norkyst_key(L.grid)], label = LABELS[norkyst_key(L.grid)])
D = daily_level[("NorFjords 160 m", "Oscarsborg")]
lines!(ax, days_since_start.(DateTime.(D.days)), D.m, color = COLORS["norfjords"], label = "$(LABELS["norfjords"]) (daily-mean output)")
axislegend(ax, position = :lt)
save(joinpath(FIG, "waterlevel_residual.png"), fig, px_per_unit = 1.5)
end

# =================================================================================================
# 2. Whole-domain statistics
# =================================================================================================
if 2 in SECTIONS
X = load(joinpath(REPORT_DATA, "extract.jld2"))
NF = load(joinpath(REPORT_DATA, "norfjords_columns.jld2"))
xf = days_since_start.(DateTime.(NF["days"]) .+ Hour(12)); sf = NF["stats"]; cf = NF["counts"]
fig = Figure(size = (1500, 1300))
x = days_since_start.(X["times"]); s = X["stats"]
ax1 = Axis(fig[1, 1], title = "Volume-mean temperature and salinity", ylabel = "°C")
ax1b = Axis(fig[1, 1], ylabel = "g/kg", yaxisposition = :right); hidespines!(ax1b); hidexdecorations!(ax1b)
lines!(ax1, x, s["meanT"], color = :firebrick, linewidth = 2)
lines!(ax1b, x, s["meanS"], color = COLORS["fjordsim"], linewidth = 2)
axislegend(ax1, [LineElement(color = :firebrick), LineElement(color = COLORS["fjordsim"])], ["mean T (left)", "mean S (right)"], position = :lt, labelsize = 13)
ax2 = Axis(fig[2, 1], title = "Coldest and warmest wet cell", ylabel = "°C")
lines!(ax2, x, s["minT"], color = :navy, linewidth = 2, label = "min T")
lines!(ax2, x, s["maxT"], color = :firebrick, linewidth = 2, label = "max T")
lines!(ax2, xf, sf["minT"], color = :navy, linewidth = 1.5, linestyle = :dash, label = "NorFjords, min T")
lines!(ax2, xf, sf["maxT_top"], color = :firebrick, linewidth = 1.5, linestyle = :dash, label = "NorFjords, max T")
axislegend(ax2, position = :lt, labelsize = 13)
ax3 = Axis(fig[3, 1], title = "Lowest salinity in any wet cell", ylabel = "g/kg")
lines!(ax3, x, s["minS"], color = :black, linewidth = 2, label = "FjordSim")
lines!(ax3, xf, sf["minS_top"], color = COLORS["norfjords"], linewidth = 1.5, linestyle = :dash, label = "NorFjords")
axislegend(ax3, position = :rt, labelsize = 13)
ax4 = Axis(fig[4, 1], title = "Highest salinity in any wet cell", xlabel = DAYS_LABEL, ylabel = "g/kg")
lines!(ax4, x, s["maxS"], color = :black, linewidth = 2, label = "FjordSim")
lines!(ax4, xf, sf["maxS"], color = COLORS["norfjords"], linewidth = 1.5, linestyle = :dash, label = "NorFjords")
axislegend(ax4, position = :lt, labelsize = 13)
save(joinpath(FIG, "domain_stats.png"), fig, px_per_unit = 1.3)
rows = [@sprintf("%s,%.3f,%.3f,%.2f,%.2f,%.2f,%.2f,%d,%d,%d,%d,%d", Date(X["times"][n]), s["meanT"][n], s["meanS"][n], s["minT"][n],
        s["maxT"][n], s["minS"][n], s["maxS"][n], s["cold_cells"][n], s["hot_cells"][n], X["coldest"][n]...) for n in eachindex(X["times"])]
writecsv(joinpath(TABLES, "domain_stats.csv"), "date,meanT,meanS,minT,maxT,minS,maxS,cells_below_m1C,cells_above_25C,coldest_i,coldest_j,coldest_k", rows)
# NorFjords over its points inside FjordSim's box.
rows = [@sprintf("%s,%.2f,%.2f,%.2f,%.2f,%d,%d,%d,%d,%d,%d,%d", NF["days"][n], sf["minT"][n], sf["maxT_top"][n], sf["minS_top"][n], sf["maxS"][n],
        cf["below_m1C"][n], cf["top_above_25C"][n], cf["above_36"][n], cf["nan"][n], NF["saltiest"][n]...) for n in eachindex(NF["days"])]
writecsv(joinpath(TABLES, "norfjords_domain_stats.csv"),
    "date,minT,maxT_top,minS_top,maxS,cells_below_m1C,top_cells_above_25C,cells_above_36,cells_without_value,saltiest_i,saltiest_j,saltiest_k", rows)
end
println("analysis done")
