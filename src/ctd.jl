# Score FjordSim, NorKyst-v3 (160 m and 800 m, as two models) and NorFjords-160m against the NIVA casts and
# FerryBox samples, and draw the CTD figures. FjordSim is sampled from the daily 3D snapshots (`extract.jld2`),
# NorKyst from `norkyst_pairs.csv` and `norkyst_columns.jld2` (`norkyst_columns.jl`), NorFjords from
# `norfjords_pairs.csv` and `norfjords_columns.jld2` (`norfjords_columns.jl`).
include("common.jl")
using JLD2, CairoMakie
set_theme!(fontsize = 16)

run = load(joinpath(REPORT_DATA, "extract.jld2"))
norkyst = load(joinpath(REPORT_DATA, "norkyst_columns.jld2"), "columns")
norkyst_points = Dict(r["station"] => r for r in readcsv(joinpath(REPORT_DATA, "norkyst_points.csv")))
norfjords = load(joinpath(REPORT_DATA, "norfjords_columns.jld2"), "columns")
norfjords_points = Dict(r["station"] => r for r in readcsv(joinpath(REPORT_DATA, "norfjords_points.csv")))
reference = Dict("norkyst160" => norkyst, "norkyst800" => norkyst, "norfjords" => norfjords)
"The NorKyst model a station is read from."
norkyst_of(s) = norkyst_key(norkyst_points[s]["grid"])
cells = Dict(r["station"] => r for r in readcsv(joinpath(REPORT_DATA, "cells.csv")))
RUN_END = min(last(run["times"]), STOP)

# Stations whose position is more than 600 m from any matching wet cell are not scored.
filter!(kv -> num(kv[2]["model_offset_m"]) <= 600, cells)
casts = filter(c -> haskey(cells, c.station), niva_casts(START, RUN_END + Hour(12); with_ferrybox = true))

"FjordSim's column at a station nearest in time to `t`, and how far away that snapshot is (hours)."
function column(station, t, var)
    c = findfirst(==(station), run["names"]); isnothing(c) && return nothing, Inf
    times = run["times"]
    k = argmin(abs.(Dates.value.(times .- t)))
    gap = abs(Dates.value(times[k] - t)) / 3.6e6
    gap > 12.5 && return nothing, gap
    return run[var][:, c, k], gap
end

NK = Dict{Tuple{String,String,Float64},Tuple{Float64,Float64}}()
for r in readcsv(joinpath(REPORT_DATA, "norkyst_pairs.csv"))
    NK[(r["station"], r["time"], num(r["depth"]))] = (num(r["norkyst_T"]), num(r["norkyst_S"]))
end
NF = Dict{Tuple{String,String,Float64},Tuple{Float64,Float64}}()
for r in readcsv(joinpath(REPORT_DATA, "norfjords_pairs.csv"))
    NF[(r["station"], r["time"], num(r["depth"]))] = (num(r["norfjords_T"]), num(r["norfjords_S"]))
end

# --- pair every observation --------------------------------------------------------------------------
pairs = []
for s in sort(unique(c.station for c in casts))
    cs = filter(c -> c.station == s, casts)
    for t in sort(unique(c.time for c in cs))
        cast = sort(filter(c -> c.time == t, cs), by = c -> c.depth)
        mT, gap = column(s, t, "T"); mS, _ = column(s, t, "S")
        isnothing(mT) && continue
        for c in cast
            key = (s, Dates.format(t, "yyyy-mm-ddTHH:MM:SS"), c.depth)
            n = get(NK, key, (NaN, NaN)); f = get(NF, key, (NaN, NaN))
            n160 = norkyst_of(s) == "norkyst160" ? n : (NaN, NaN); n800 = norkyst_of(s) == "norkyst800" ? n : (NaN, NaN)
            push!(pairs, (station = s, time = t, depth = c.depth,
                obs_T = c.T, fjordsim_T = interp(run["z"], mT, c.depth), norkyst160_T = n160[1], norkyst800_T = n800[1],
                norfjords_T = f[1],
                obs_S = c.S, fjordsim_S = interp(run["z"], mS, c.depth), norkyst160_S = n160[2], norkyst800_S = n800[2],
                norfjords_S = f[2], gap))
        end
    end
end
const ALL_KEYS = ("obs", ALL_MODELS...)
open(joinpath(REPORT_DATA, "ctd_pairs.csv"), "w") do io
    println(io, "station,time,depth," * join(["$(k)_T" for k in ALL_KEYS], ",") * "," * join(["$(k)_S" for k in ALL_KEYS], ",") * ",snapshot_gap_h")
    for p in pairs
        println(io, join([p.station, Dates.format(p.time, "yyyy-mm-ddTHH:MM:SS"), p.depth,
            [@sprintf("%.3f", getfield(p, Symbol("$(k)_T"))) for k in ALL_KEYS]...,
            [@sprintf("%.3f", getfield(p, Symbol("$(k)_S"))) for k in ALL_KEYS]..., @sprintf("%.1f", p.gap)], ","))
    end
end
println("pairs: ", length(pairs), "  casts: ", length(unique((p.station, p.time) for p in pairs)),
    "  stations: ", length(unique(p.station for p in pairs)), "  to ", maximum(p.time for p in pairs))

# --- statistics ----------------------------------------------------------------------------------------
# The casts only: the FerryBox lines are scored on their own.
cast_pairs = filter(p -> !ferrybox(p.station), pairs)
bands = [("0-5 m", 0, 5), ("5-20 m", 5, 20), ("20-50 m", 20, 50), (">50 m", 50, 1e4), ("all", 0, 1e4)]
val(p, k, var) = getfield(p, Symbol("$(k)_$(var)"))
"Count, observed mean and per-model (bias, RMSE) on the samples every model in `models` reaches."
function score(ps, var, models)
    o = [val(p, "obs", var) for p in ps]
    m = [[val(p, k, var) for p in ps] for k in models]
    ok = isfinite.(o) .& reduce(.&, [isfinite.(x) for x in m])
    n = count(ok)
    n < 3 && return nothing
    return n, mean(o[ok]), [(mean(x[ok] .- o[ok]), sqrt(mean((x[ok] .- o[ok]) .^ 2))) for x in m]
end
scored = filter(p -> p.time >= SPINUP, cast_pairs)
in_group(p, g) = g == "ALL" || region(p.station) == g
function skill_rows(groups, select; models)
    rows = String[]
    for grp in groups, var in ("S", "T"), (b, lo, hi) in bands
        ps = filter(p -> select(p, grp) && lo <= p.depth < hi, scored)
        r = score(ps, var, models); isnothing(r) && continue
        n, om, st = r
        push!(rows, @sprintf("%s,%s,%s,%d,%.2f,", grp, var, b, n, om) * join([@sprintf("%.2f,%.2f", x...) for x in st], ","))
    end
    return rows
end
columns_of(models) = join(["$(k)_bias,$(k)_rmse" for k in models], ",")
# FjordSim alone on every sample, then FjordSim beside each reference model on the samples both reach: the
# reference models' columns end at their own bottoms, NorKyst's well above the basins' deep water, and
# NorFjords' files end on 2026-06-30.
writecsv(joinpath(TABLES, "ctd_skill_fjordsim.csv"), "group,variable,band,n,obs_mean,fjordsim_bias,fjordsim_rmse",
    skill_rows(("ALL", REGIONS...), in_group; models = ("fjordsim",)))
for k in REFERENCES
    writecsv(joinpath(TABLES, "ctd_skill_$k.csv"), "group,variable,band,n,obs_mean," * columns_of(("fjordsim", k)),
        skill_rows(("ALL", REGIONS...), in_group; models = ("fjordsim", k)))
    writecsv(joinpath(TABLES, "ctd_skill_station_$k.csv"), "station,variable,band,n,obs_mean," * columns_of(("fjordsim", k)),
        skill_rows(sort(unique(p.station for p in scored)), (p, g) -> p.station == g; models = ("fjordsim", k)))
end

# Stratification: salinity at 25 m minus at 1 m, per cast.
strat = []
for (s, t) in unique((p.station, p.time) for p in cast_pairs)
    ps = filter(p -> p.station == s && p.time == t, cast_pairs)
    # Casts are in 1 m bins centred on x.5 m, so each level is interpolated.
    at(k, d) = interp([p.depth for p in ps], [val(p, k, "S") for p in ps], d)
    push!(strat, (; station = s, time = t, (Symbol(k) => at(k, 25.0) - at(k, 1.0) for k in ALL_KEYS)...))
end
open(joinpath(TABLES, "stratification.csv"), "w") do io
    println(io, "station,time,region," * join(["$(k)_dS_1_25" for k in ALL_KEYS], ","))
    for x in strat
        println(io, join([x.station, x.time, region(x.station), [@sprintf("%.2f", x[Symbol(k)]) for k in ALL_KEYS]...], ","))
    end
end
for k in REFERENCES
    models = ("fjordsim", k)
    rows = String[]
    for grp in ("ALL", REGIONS...)
        xs = filter(x -> in_group(x, grp) && x.time >= SPINUP && all(k -> isfinite(x[Symbol(k)]), ("obs", models...)), strat)
        length(xs) < 3 && continue
        o = [x[:obs] for x in xs]
        stats = [@sprintf("%.2f,%.2f", mean(m .- o), sqrt(mean((m .- o) .^ 2))) for m in ([x[Symbol(k)] for x in xs] for k in models)]
        push!(rows, @sprintf("%s,%d,%.2f,", grp, length(xs), mean(o)) * join(stats, ","))
    end
    writecsv(joinpath(TABLES, "stratification_skill_$k.csv"), "group,casts,obs_mean," * columns_of(models), rows)
end

# --- figures -----------------------------------------------------------------------------------------
# Profiles, one column per cast; stations with many casts are split over rows of casts.
for s in ["MO-2", "VAL-1", "LA-1", "SF-3", "TØ-1", "Ø-1", "S-9", "SAN-5", "D-2", "D-3", "Im2", "Gl2", "Fl1", "Dk1", "Ep1", "Bn1"]
    casts_s = sort(unique(p.time for p in cast_pairs if p.station == s)); isempty(casts_s) && continue
    per_row = min(length(casts_s), 7)
    blocks = [casts_s[i:min(i + per_row - 1, end)] for i in 1:per_row:length(casts_s)]
    fig = Figure(size = (max(230 * per_row + 120, 900), 760 * length(blocks)))
    for (b, block) in enumerate(blocks), (c, t) in enumerate(block), (r, var) in enumerate(("S", "T"))
        ps = sort(filter(p -> p.station == s && p.time == t, cast_pairs), by = p -> p.depth)
        d = [p.depth for p in ps]
        ax = Axis(fig[2(b - 1) + r, c], yreversed = true, title = r == 1 ? Dates.format(t, "yyyy-mm-dd") : "",
            xlabel = var == "S" ? "S" : "T (°C)", ylabel = c == 1 ? "depth (m)" : "", xticks = LinearTicks(4))
        for k in (REFERENCES..., "fjordsim", "obs")
            x = [val(p, k, var) for p in ps]
            all(isnan, x) && continue
            lines!(ax, x, d, color = COLORS[k], linewidth = k == "obs" ? 2.2 : (k == "fjordsim" ? 3 : 2), label = LABELS[k])
        end
        t < SPINUP && (ax.backgroundcolor = RGBf(0.95, 0.95, 0.95))
        b == 1 && r == 1 && c == 1 && axislegend(ax, position = :lb, labelsize = 10)
    end
    m = cells[s]; nk = norkyst_points[s]
    Label(fig[0, :], @sprintf("%s: deepest cast %.0f m; water depth FjordSim %.0f m, NorKyst %s %.0f m, NorFjords %.0f m", s,
        num(m["deepest_cast_m"]), num(m["model_depth_m"]), replace(nk["grid"], "m" => " m"), num(nk["norkyst_depth_m"]),
        haskey(norfjords_points, s) ? num(norfjords_points[s]["norfjords_depth_m"]) : NaN), fontsize = 18, font = :bold)
    save(joinpath(FIG, "profiles_$(stem(s)).png"), fig, px_per_unit = 1.2)
end

"Each of `dates` replaced by the station's cast nearest it, if one lies within 20 days."
function nearest_casts(s, dates)
    ts = sort(unique(p.time for p in cast_pairs if p.station == s))
    isempty(ts) && return DateTime[]
    near = [ts[argmin(abs.(ts .- DateTime(d)))] for d in dates]
    return unique(filter(t -> any(d -> abs(t - DateTime(d)) <= Day(20), dates), near))
end

# Selected profiles: one row per `profile_stations`, its casts nearest `profile_dates` (report.toml), salinity
# and temperature side by side.
picked = [(s, nearest_casts(s, CONFIG["profile_dates"])) for s in CONFIG["profile_stations"]]
ncol = maximum(length(last(p)) for p in picked)
fig = Figure(size = (250 * 2ncol, 330 * length(picked) + 60))
for (r, (s, ts)) in enumerate(picked), (j, t) in enumerate(ts), (v, var) in enumerate(("S", "T"))
    ps = sort(filter(p -> p.station == s && p.time == t, cast_pairs), by = p -> p.depth)
    d = [p.depth for p in ps]
    ax = Axis(fig[r, 2(j - 1) + v], yreversed = true, title = v == 1 ? "$s  $(Date(t))" : "", titlealign = :left,
        xlabel = var == "S" ? "S (g/kg)" : "T (°C)", ylabel = j == 1 && v == 1 ? "depth (m)" : "", xticks = LinearTicks(3))
    for k in (REFERENCES..., "fjordsim", "obs")
        x = [val(p, k, var) for p in ps]
        all(isnan, x) && continue
        lines!(ax, x, d, color = COLORS[k], linewidth = k == "fjordsim" ? 3 : 2, label = LABELS[k])
    end
end
Legend(fig[length(picked) + 1, :], [LineElement(color = COLORS[k], linewidth = 3) for k in ("obs", ALL_MODELS...)],
    [LABELS[k] for k in ("obs", ALL_MODELS...)], orientation = :horizontal, framevisible = false)
save(joinpath(FIG, "profiles_selected.png"), fig, px_per_unit = 1.2)

# Bias by station and depth band, one panel per model, each model on every sample it reaches.
order = ["LA-1", "SF-3", "TØ-1", "BO-1", "VAL-1", "KF-1", "Ø-1", "I-1", "I-4", "S-9", "MO-2", "SAN-5", "D-2", "D-3", "Im2", "Im3",
         "Hm4", "En-1", "Gk1", "Gl2", "Fl1", "Ej1", "Dk1", "Dm1", "Ep1", "Gp2", "Cj1", "Bl4", "Bn1", "Cq1", "Cp2", "Br1", "Ap2", "Ap3",
         "Aq2", "Aq3", "ALL"]
stations_scored = Set(p.station for p in scored)
order = filter(s -> s == "ALL" || s in stations_scored, order)
bnames = first.(bands)[1:4]
"Mean error of model `k` at station `s` (or every station, \"ALL\") in depth band `b`, on the samples `k` reaches."
function band_bias(k, s, var, b)
    _, lo, hi = bands[findfirst(x -> x[1] == b, bands)]
    r = score(filter(p -> (s == "ALL" || p.station == s) && lo <= p.depth < hi, scored), var, (k,))
    return isnothing(r) ? NaN : r[3][1][1]
end
fig = Figure(size = (1900, 2300))
for (r, var) in enumerate(("S", "T")), (c, k) in enumerate(ALL_MODELS)
    B = [band_bias(k, s, var, b) for s in order, b in bnames]
    lim = var == "S" ? 4.0 : 2.0
    ax = Axis(fig[r, c], title = LABELS[k], xticks = (1:length(bnames), bnames), yticks = (1:length(order), order),
        yreversed = true, yticklabelsvisible = c == 1)
    hm = heatmap!(ax, 1:length(bnames), 1:length(order), permutedims(B), colormap = :balance, colorrange = (-lim, lim), nan_color = :gray92)
    for i in eachindex(order), j in eachindex(bnames)
        isfinite(B[i, j]) && text!(ax, j, i, text = @sprintf("%.1f", B[i, j]), align = (:center, :center), fontsize = 10)
    end
    c == length(ALL_MODELS) && Colorbar(fig[r, c + 1], hm,
        label = var == "S" ? "model − observed salinity (g/kg)" : "model − observed temperature (°C)")
end
save(joinpath(FIG, "ctd_bias.png"), fig, px_per_unit = 1.2)

# Scatter, each model on the samples it reaches, coloured by region. Region colours stay apart from the models'
# (`COLORS`), so a point's colour is never read as a model; the regions with fewest samples are drawn last.
region_colors = (("Inner Oslofjord", :goldenrod), ("Outer fjord", :gray35), ("Drammensfjord", :crimson))
fig = Figure(size = (1900, 1060))
Legend(fig[0, 1:length(ALL_MODELS)], [MarkerElement(color = col, marker = :circle, markersize = 14) for (_, col) in region_colors],
    collect(first.(region_colors)), orientation = :horizontal, framevisible = false)
for (c, var) in enumerate(("S", "T")), (n, k) in enumerate(ALL_MODELS)
    ax = Axis(fig[c, n], xlabel = "observed", ylabel = n == 1 ? "modelled" : "", aspect = 1,
        title = "$(LABELS[k]), $(var == "S" ? "salinity" : "temperature (°C)")")
    for (grp, color) in region_colors
        ps = filter(p -> region(p.station) == grp && isfinite(val(p, "obs", var)) && isfinite(val(p, k, var)), scored)
        isempty(ps) && continue
        scatter!(ax, [val(p, "obs", var) for p in ps], [val(p, k, var) for p in ps], color = (color, 0.3), markersize = 4)
    end
    lo, hi = var == "S" ? (0, 36) : (-1, 20)
    lines!(ax, [lo, hi], [lo, hi], color = :black); limits!(ax, lo, hi, lo, hi)
end
save(joinpath(FIG, "ctd_scatter.png"), fig, px_per_unit = 1.2)

# Stratification, observed against modelled, each model on the casts it reaches at 25 m.
fig = Figure(size = (1900, 540))
for (c, k) in enumerate(ALL_MODELS)
    ax = Axis(fig[1, c], xlabel = "observed S(25 m) − S(1 m)", ylabel = c == 1 ? "modelled" : "", aspect = 1, title = LABELS[k])
    joint = ("obs", k)
    for (grp, marker) in (("Outer fjord", :circle), ("Inner Oslofjord", :rect), ("Drammensfjord", :diamond))
        xs = filter(x -> region(x.station) == grp && x.time >= SPINUP && all(k -> isfinite(x[Symbol(k)]), joint), strat)
        isempty(xs) && continue
        scatter!(ax, [x[:obs] for x in xs], [x[Symbol(k)] for x in xs], marker = marker, color = (COLORS[k], 0.6), markersize = 11, label = grp)
    end
    lines!(ax, [0, 30], [0, 30], color = :black); limits!(ax, -1, 30, -1, 30)
    c == 1 && axislegend(ax, position = :lt, labelsize = 11)
end
save(joinpath(FIG, "stratification.png"), fig, px_per_unit = 1.3)

# Taylor and target diagrams, per depth band: FjordSim beside each reference model on the samples both reach.
"Samples, observed and modelled standard deviation, correlation, centred RMSE and bias of model `k` on `ps`."
function pattern_stats(ps, var, k)
    o = [val(p, "obs", var) for p in ps]; m = [val(p, k, var) for p in ps]
    so, sm = std(o, corrected = false), std(m, corrected = false)
    bias = mean(m) - mean(o)
    return (n = length(ps), obs_std = so, model_std = sm, r = cor(o, m), crmse = sqrt(max(0, mean((m .- o) .^ 2) - bias^2)), bias)
end
taylor = []
for k in REFERENCES, var in ("S", "T"), (b, lo, hi) in bands[1:4]
    ps = filter(p -> lo <= p.depth < hi && all(m -> isfinite(val(p, m, var)), ("obs", "fjordsim", k)), scored)
    length(ps) < 3 && continue
    for m in ("fjordsim", k)
        push!(taylor, (reference = k, model = m, var, band = b, pattern_stats(ps, var, m)...))
    end
end
writecsv(joinpath(TABLES, "taylor_target.csv"), "reference,model,variable,band,n,obs_std,model_std,correlation,centred_rmse,bias",
    [@sprintf("%s,%s,%s,%s,%d,%.3f,%.3f,%.3f,%.3f,%.3f", x.reference, x.model, x.var, x.band, x.n, x.obs_std, x.model_std, x.r, x.crmse, x.bias)
     for x in taylor])
band_markers = Dict(zip(first.(bands[1:4]), (:circle, :rect, :utriangle, :diamond)))
"The top legend of both diagrams: the models by colour, the depth bands by marker."
function pattern_legend(fig)
    Legend(fig[0, 1:length(REFERENCES)],
        [[MarkerElement(color = COLORS[k], marker = :circle, markersize = 14) for k in ALL_MODELS];
         [MarkerElement(color = :gray40, marker = band_markers[b], markersize = 14) for b in first.(bands[1:4])]],
        [[LABELS[k] for k in ALL_MODELS]; first.(bands[1:4])], orientation = :horizontal, framevisible = false, nbanks = 1)
end
# One panel per variable and reference model: the reference model and FjordSim on the samples both reach.
function pattern_panels(fig, place)
    for (r, var) in enumerate(("S", "T")), (c, k) in enumerate(REFERENCES)
        xs = filter(x -> x.reference == k && x.var == var, taylor)
        isempty(xs) && continue
        ax, point = place(fig[r, c], "$(var == "S" ? "Salinity" : "Temperature"): FjordSim and $(LABELS[k])")
        for x in xs
            scatter!(ax, [point(x)[1]], [point(x)[2]], color = COLORS[x.model], marker = band_markers[x.band], markersize = 16,
                strokecolor = :black, strokewidth = 0.6)
        end
    end
end

# Taylor: angle arccos(r), radius σ_model/σ_obs; the distance to the star is the centred RMSE / σ_obs (dashed arcs).
fig = Figure(size = (1700, 1250))
pattern_legend(fig)
pattern_panels(fig, (pos, title) -> begin
    ax = PolarAxis(pos; title, thetalimits = (0, π / 2), rlimits = (0, 1.75), rticks = 0:0.25:1.75,
        thetaticks = (acos.([1.0, 0.99, 0.95, 0.9, 0.8, 0.6, 0.4, 0.2, 0.0]), ["1", "0.99", "0.95", "0.9", "0.8", "0.6", "0.4", "0.2", "0"]))
    for e in (0.25, 0.5, 0.75, 1.0)
        φ = range(0, π, length = 200)
        x, y = 1 .+ e .* cos.(φ), e .* sin.(φ)
        lines!(ax, atan.(y, x), hypot.(x, y), color = :gray70, linestyle = :dash, linewidth = 1)
    end
    lines!(ax, range(0, π / 2, length = 100), ones(100), color = :gray40, linewidth = 1)
    scatter!(ax, [0.0], [1.0], marker = :star5, markersize = 22, color = :black)
    (ax = ax, point = x -> (acos(clamp(x.r, -1, 1)), x.model_std / x.obs_std))
end)
save(joinpath(FIG, "taylor.png"), fig, px_per_unit = 1.2)

# Target: x = sign(σ_model − σ_obs) × centred RMSE / σ_obs, y = bias / σ_obs; the distance to the origin is RMSE / σ_obs.
fig = Figure(size = (1700, 1250))
pattern_legend(fig)
pattern_panels(fig, (pos, title) -> begin
    ax = Axis(pos; title, aspect = 1, xlabel = "sign(σ_model − σ_obs) × centred RMSE / σ_obs", ylabel = "bias / σ_obs")
    φ = range(0, 2π, length = 200)
    for e in (0.5, 1.0)
        lines!(ax, e .* cos.(φ), e .* sin.(φ), color = :gray60, linestyle = :dash, linewidth = 1)
    end
    hlines!(ax, 0, color = :gray85); vlines!(ax, 0, color = :gray85)
    limits!(ax, -1.75, 1.75, -1.75, 1.75)
    (ax = ax, point = x -> ((x.model_std >= x.obs_std ? 1 : -1) * x.crmse / x.obs_std, x.bias / x.obs_std))
end)
save(joinpath(FIG, "target.png"), fig, px_per_unit = 1.2)

# Deep water through the run: FjordSim and the reference models daily, observations on the cast days.
picks = [("VAL-1", 100.0), ("MO-2", 80.0), ("D-2", 50.0), ("D-2", 100.0), ("D-3", 50.0), ("Im2", 100.0), ("Fl1", 100.0),
         ("Dk1", 60.0), ("Ep1", 60.0), ("Ep1", 120.0)]
function fjordsim_daily(s, var, d)
    c = findfirst(==(s), run["names"])
    return run["times"], [interp(run["z"], run[var][:, c, n], d) for n in eachindex(run["times"])]
end
function reference_daily(k, s, var, d)
    (haskey(reference[k], s) && (!startswith(k, "norkyst") || norkyst_of(s) == k)) || return DateTime[], Float64[]
    col = reference[k][s]; V = var == "S" ? col.daily_S : col.daily_T
    return col.days, [interp(depths(col, n), V[:, n], d) for n in eachindex(col.days)]
end
"Each pick's salinity and temperature at its depth through the window, as `<name>.png` and `<name>.csv`."
function drift_figure(picks, name)
    drift_rows = String[]
    fig = Figure(size = (1500, 270 * length(picks) + 50))
    Legend(fig[0, 1:2], [[LineElement(color = COLORS[k], linewidth = 3) for k in ALL_MODELS]; MarkerElement(color = :black, marker = :circle, markersize = 12)],
        [[LABELS[k] for k in ALL_MODELS]; "observed"], orientation = :horizontal, framevisible = false)
    for (n, (s, d)) in enumerate(picks), (c, var) in enumerate(("S", "T"))
        ax = Axis(fig[n, c], title = @sprintf("%s, %s at %.0f m", s, var == "S" ? "salinity" : "temperature", d), ylabel = var == "S" ? "g/kg" : "°C")
        t, v = fjordsim_daily(s, var, d); lines!(ax, days_since_start.(t), v, color = COLORS["fjordsim"], linewidth = 2.5)
        series = [reference_daily(k, s, var, d) for k in REFERENCES]
        for (k, (tk, vk)) in zip(REFERENCES, series)
            lines!(ax, days_since_start.(tk), vk, color = COLORS[k], linewidth = 2)
        end
        ps = filter(p -> p.station == s && abs(p.depth - d) <= 1.0, cast_pairs)
        ts = unique(p.time for p in ps)
        ob = [mean(val(p, "obs", var) for p in ps if p.time == x) for x in ts]
        isempty(ts) || scatter!(ax, days_since_start.(ts), ob, color = :black, markersize = 14)
        n == length(picks) && (ax.xlabel = DAYS_LABEL)
        xlims!(ax, 0, days_since_start(RUN_END) + 3)
        for x in ts
            # A model's value on the cast's day; NaN where it has no series (the other NorKyst grid) or its
            # series has ended (NorFjords after June 2026).
            nearest(times, values) = isempty(times) ? NaN :
                (k = argmin(abs.(Dates.value.(times .- x))); abs(times[k] - x) <= Day(1) ? values[k] : NaN)
            push!(drift_rows, @sprintf("%s,%.0f,%s,%s,%.2f,%.2f,", s, d, var, Date(x), mean(val(p, "obs", var) for p in ps if p.time == x),
                nearest(t, v)) * join([@sprintf("%.2f", nearest(tk, vk)) for (tk, vk) in series], ","))
        end
    end
    save(joinpath(FIG, "$name.png"), fig, px_per_unit = 1.1)
    writecsv(joinpath(TABLES, "$name.csv"), "station,depth,variable,date,obs,fjordsim," * join(REFERENCES, ","), drift_rows)
end
drift_figure(picks, "basin_drift")
# The surface, outer fjord to Oslo harbour; observations are the casts' 0.5 and 1.5 m samples.
drift_figure([("I-1", 1.0), ("VAL-1", 1.0), ("MO-2", 1.0), ("D-2", 1.0), ("Im2", 1.0), ("Fl1", 1.0), ("Ep1", 1.0), ("Ap2", 1.0)],
             "surface_drift")
# The halocline (5 m), the summer's too-cold layer (15 m) and the spring's (30 m); Cq1, deeper than Ap2, for the harbour.
for d in (5.0, 15.0, 30.0)
    drift_figure([(s, d) for s in ("I-1", "VAL-1", "MO-2", "D-2", "Im2", "Fl1", "Ep1", "Cq1")], @sprintf("drift_%.0fm", d))
end

# FerryBox: 4 m samples against every model's daily 4 m values.
boxes = sort(filter(ferrybox, collect(keys(cells))), by = s -> -num(cells[s]["lat"]))
# The ODM2 casts hold no FerryBox points; with none, the FerryBox figure and table are skipped.
if !isempty(boxes)
samples = filter(c -> c.station in boxes, casts)
fig = Figure(size = (1500, 300 * length(boxes) + 80))
for (n, s) in enumerate(boxes), (c, var) in enumerate(("S", "T"))
    ax = Axis(fig[n, c], title = "$s ($(var == "S" ? "salinity" : "temperature") at 4 m)", ylabel = var == "S" ? "g/kg" : "°C",
        xlabel = n == length(boxes) ? DAYS_LABEL : "")
    t, v = fjordsim_daily(s, var, 4.0)
    lines!(ax, days_since_start.(t), v, color = COLORS["fjordsim"], linewidth = 2, label = LABELS["fjordsim"])
    for k in REFERENCES
        tn, vn = reference_daily(k, s, var, 4.0)
        lines!(ax, days_since_start.(tn), vn, color = COLORS[k], linewidth = 2, label = LABELS[k])
    end
    q = filter(p -> p.station == s && isfinite(getfield(p, Symbol(var))), samples)
    isempty(q) || scatter!(ax, days_since_start.([p.time for p in q]), [getfield(p, Symbol(var)) for p in q], color = :black, markersize = 6, label = "FerryBox")
    xlims!(ax, 0, days_since_start(RUN_END) + 3)
    n == 1 && c == 1 && axislegend(ax, position = :lb, labelsize = 11)
end
save(joinpath(FIG, "ferrybox.png"), fig, px_per_unit = 1.1)
rows = String[]
for s in boxes, var in ("S", "T")
    ps = filter(p -> p.station == s && p.time >= SPINUP, pairs)
    r = score(ps, var, ("fjordsim", norkyst_of(s))); isnothing(r) && continue
    n, om, st = r
    push!(rows, @sprintf("%s,%s,%s,%d,%.2f,", s, var, norkyst_of(s), n, om) * join([@sprintf("%.2f,%.2f", x...) for x in st], ","))
end
writecsv(joinpath(TABLES, "ferrybox_skill.csv"), "station,variable,norkyst_model,n,obs_mean,fjordsim_bias,fjordsim_rmse,norkyst_bias,norkyst_rmse", rows)
end

# Map: salinity bias below 20 m.
lon, lat, h = NCDataset(joinpath(RUN_SETUP, "bathymetry.nc")) do ds
    Float64.(ds["lon"][:]), Float64.(ds["lat"][:]), Float64.(coalesce.(ds["h"][:, :], NaN))
end
depthmap = map(x -> x < 0 ? -x : NaN, h)
"Model `k`'s mean salinity error below 20 m at station `s`, on the samples it reaches."
function deep_bias(s, k)
    r = score(filter(p -> p.station == s && p.depth >= 20, scored), "S", (k,))
    return isnothing(r) ? NaN : r[3][1][1]
end
fig = Figure(size = (2200, 1050))
for (c, k) in enumerate(ALL_MODELS)
    xl, yl = (10.0, 11.2), (58.95, 59.93)
    ax = Axis(fig[1, c], title = LABELS[k], xlabel = "Longitude (°E)", ylabel = c == 1 ? "Latitude (°N)" : "")
    ax.aspect = AxisAspect((xl[2] - xl[1]) * cosd(59.4) / (yl[2] - yl[1]))
    heatmap!(ax, lon, lat, depthmap, colormap = :deep, colorrange = (0, 350), nan_color = RGBf(0.88, 0.87, 0.84))
    pts = filter(p -> isfinite(p[4]), [(num(m["lon"]), num(m["lat"]), s, deep_bias(s, k)) for (s, m) in cells])
    sc = scatter!(ax, [p[1] for p in pts], [p[2] for p in pts], color = [p[4] for p in pts], colormap = :balance,
        colorrange = (-2.5, 2.5), markersize = 18, strokecolor = :black, strokewidth = 1.2)
    limits!(ax, xl..., yl...)
    c == length(ALL_MODELS) && Colorbar(fig[1, length(ALL_MODELS) + 1], sc, label = "model − observed salinity below 20 m (g/kg)", height = Relative(0.6))
end
save(joinpath(FIG, "ctd_map.png"), fig, px_per_unit = 1.2)
println("ctd done")
