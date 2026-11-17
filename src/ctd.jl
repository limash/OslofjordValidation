# Score FjordSim, NorKyst-v3 and NorFjords-160m against the NIVA casts and FerryBox samples, and draw the CTD
# figures. FjordSim is sampled from the daily 3D snapshots (`extract.jld2`), NorKyst from `norkyst_pairs.csv`
# and `norkyst_columns.jld2` (`norkyst_columns.jl`), NorFjords from `norfjords_pairs.csv` and
# `norfjords_columns.jld2` (`norfjords_columns.jl`).
include("common.jl")
using JLD2, CairoMakie
set_theme!(fontsize = 16)

run = load(joinpath(REPORT_DATA, "extract.jld2"))
norkyst = load(joinpath(REPORT_DATA, "norkyst_columns.jld2"), "columns")
norkyst_points = Dict(r["station"] => r for r in readcsv(joinpath(REPORT_DATA, "norkyst_points.csv")))
norfjords = load(joinpath(REPORT_DATA, "norfjords_columns.jld2"), "columns")
norfjords_points = Dict(r["station"] => r for r in readcsv(joinpath(REPORT_DATA, "norfjords_points.csv")))
reference = Dict("norkyst" => norkyst, "norfjords" => norfjords)
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
            push!(pairs, (station = s, time = t, depth = c.depth,
                obs_T = c.T, fjordsim_T = interp(run["z"], mT, c.depth), norkyst_T = n[1], norfjords_T = f[1],
                obs_S = c.S, fjordsim_S = interp(run["z"], mS, c.depth), norkyst_S = n[2], norfjords_S = f[2], gap))
        end
    end
end
const KEYS = ("obs", MODELS...)
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
function skill_rows(groups, select; models = MODELS)
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
header = "group,variable,band,n,obs_mean," * columns_of(MODELS)
writecsv(joinpath(TABLES, "ctd_skill.csv"), header, skill_rows(("ALL", REGIONS...), in_group))
# FjordSim alone on every sample: NorKyst's columns end at its own, shallower, bottom, so the joint
# tables leave out most of the deep water.
writecsv(joinpath(TABLES, "ctd_skill_fjordsim.csv"), "group,variable,band,n,obs_mean,fjordsim_bias,fjordsim_rmse",
    skill_rows(("ALL", REGIONS...), in_group; models = ("fjordsim",)))
# NorKyst's 160 m nest and its 800 m run separately, each on the stations it serves.
writecsv(joinpath(TABLES, "ctd_skill_grid.csv"), "group,variable,band,n,obs_mean," * columns_of(("fjordsim", "norkyst")),
    skill_rows(("160m", "800m"), (p, g) -> norkyst_points[p.station]["grid"] == g; models = ("fjordsim", "norkyst")))
writecsv(joinpath(TABLES, "ctd_skill_station.csv"), replace(header, "group" => "station"),
    skill_rows(sort(unique(p.station for p in scored)), (p, g) -> p.station == g))
# FjordSim and NorFjords on the samples both reach, to 2026-06-30: NorFjords' columns go to its bottom, so
# this includes most of the deep water.
const NF_MODELS = ("fjordsim", "norfjords")
writecsv(joinpath(TABLES, "ctd_skill_norfjords.csv"), "group,variable,band,n,obs_mean," * columns_of(NF_MODELS),
    skill_rows(("ALL", REGIONS...), in_group; models = NF_MODELS))
writecsv(joinpath(TABLES, "ctd_skill_station_norfjords.csv"), "station,variable,band,n,obs_mean," * columns_of(NF_MODELS),
    skill_rows(sort(unique(p.station for p in scored)), (p, g) -> p.station == g; models = NF_MODELS))

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
for (models, file) in ((MODELS, "stratification_skill.csv"), (NF_MODELS, "stratification_skill_norfjords.csv"))
    rows = String[]
    for grp in ("ALL", REGIONS...)
        xs = filter(x -> in_group(x, grp) && x.time >= SPINUP && all(k -> isfinite(x[Symbol(k)]), ("obs", models...)), strat)
        length(xs) < 3 && continue
        o = [x[:obs] for x in xs]
        stats = [@sprintf("%.2f,%.2f", mean(m .- o), sqrt(mean((m .- o) .^ 2))) for m in ([x[Symbol(k)] for x in xs] for k in models)]
        push!(rows, @sprintf("%s,%d,%.2f,", grp, length(xs), mean(o)) * join(stats, ","))
    end
    writecsv(joinpath(TABLES, file), "group,casts,obs_mean," * columns_of(models), rows)
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
        for k in ("norkyst", "norfjords", "fjordsim", "obs")
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

# Bias by station and depth band.
skill = readcsv(joinpath(TABLES, "ctd_skill_station.csv")); skillall = readcsv(joinpath(TABLES, "ctd_skill.csv"))
# NorFjords' row is from its scores beside FjordSim, on the samples those two reach.
skill_nf = readcsv(joinpath(TABLES, "ctd_skill_station_norfjords.csv")); skillall_nf = readcsv(joinpath(TABLES, "ctd_skill_norfjords.csv"))
order = ["LA-1", "SF-3", "TØ-1", "BO-1", "VAL-1", "KF-1", "Ø-1", "I-1", "I-4", "S-9", "MO-2", "SAN-5", "D-2", "D-3", "Im2", "Im3",
         "Hm4", "En-1", "Gk1", "Gl2", "Fl1", "Ej1", "Dk1", "Dm1", "Ep1", "Gp2", "Cj1", "Bl4", "Bn1", "Cq1", "Cp2", "Br1", "Ap2", "Ap3",
         "Aq2", "Aq3", "ALL"]
order = filter(s -> s == "ALL" || any(r -> r["station"] == s, skill), order)
bnames = first.(bands)[1:4]
fig = Figure(size = (1500, 2100))
for (c, var) in enumerate(("S", "T")), (r, k) in enumerate(ALL_MODELS)
    B = fill(NaN, length(order), length(bnames))
    for (i, s) in enumerate(order), (j, b) in enumerate(bnames)
        src, key = s == "ALL" ? (k == "norfjords" ? skillall_nf : skillall, "group") : (k == "norfjords" ? skill_nf : skill, "station")
        row = findfirst(x -> x[key] == s && x["variable"] == var && x["band"] == b, src)
        isnothing(row) || (B[i, j] = num(src[row]["$(k)_bias"]))
    end
    lim = var == "S" ? 4.0 : 2.0
    ax = Axis(fig[r, 2c-1], title = "$(LABELS[k]) − observed, $(var == "S" ? "salinity" : "temperature (°C)")",
        xticks = (1:length(bnames), bnames), yticks = (1:length(order), order), yreversed = true)
    hm = heatmap!(ax, 1:length(bnames), 1:length(order), permutedims(B), colormap = :balance, colorrange = (-lim, lim), nan_color = :gray92)
    for i in eachindex(order), j in eachindex(bnames)
        isfinite(B[i, j]) && text!(ax, j, i, text = @sprintf("%.1f", B[i, j]), align = (:center, :center), fontsize = 10)
    end
    r == 1 && Colorbar(fig[1:length(ALL_MODELS), 2c], hm)
end
save(joinpath(FIG, "ctd_bias.png"), fig, px_per_unit = 1.2)

# Scatter, FjordSim and NorKyst on the samples both reach, NorFjords on the samples it and FjordSim reach,
# coloured by region.
common_pairs = filter(p -> isfinite(p.obs_S) && isfinite(p.obs_T) && all(k -> isfinite(val(p, k, "S")), MODELS), scored)
nf_pairs = filter(p -> isfinite(p.obs_S) && isfinite(p.obs_T) && all(k -> isfinite(val(p, k, "S")), NF_MODELS), scored)
fig = Figure(size = (1500, 1050))
for (c, var) in enumerate(("S", "T")), (n, k) in enumerate(ALL_MODELS)
    ax = Axis(fig[c, n], xlabel = "observed", ylabel = n == 1 ? "modelled" : "", aspect = 1,
        title = "$(LABELS[k]), $(var == "S" ? "salinity" : "temperature (°C)")")
    for (grp, color) in zip(REGIONS, (:dodgerblue, :darkorange, :seagreen))
        ps = filter(p -> region(p.station) == grp, k == "norfjords" ? nf_pairs : common_pairs)
        isempty(ps) && continue
        scatter!(ax, [val(p, "obs", var) for p in ps], [val(p, k, var) for p in ps], color = (color, 0.3), markersize = 4, label = grp)
    end
    lo, hi = var == "S" ? (0, 36) : (-1, 20)
    lines!(ax, [lo, hi], [lo, hi], color = :black); limits!(ax, lo, hi, lo, hi)
    c == 1 && n == 1 && axislegend(ax, position = :lt, labelsize = 11, markersize = 10)
end
save(joinpath(FIG, "ctd_scatter.png"), fig, px_per_unit = 1.2)

# Stratification, observed against modelled.
fig = Figure(size = (1500, 540))
for (c, k) in enumerate(ALL_MODELS)
    ax = Axis(fig[1, c], xlabel = "observed S(25 m) − S(1 m)", ylabel = c == 1 ? "modelled" : "", aspect = 1, title = LABELS[k])
    joint = k == "norfjords" ? ("obs", NF_MODELS...) : KEYS
    for (grp, marker) in (("Outer fjord", :circle), ("Inner Oslofjord", :rect), ("Drammensfjord", :diamond))
        xs = filter(x -> region(x.station) == grp && x.time >= SPINUP && all(k -> isfinite(x[Symbol(k)]), joint), strat)
        isempty(xs) && continue
        scatter!(ax, [x[:obs] for x in xs], [x[Symbol(k)] for x in xs], marker = marker, color = (COLORS[k], 0.6), markersize = 11, label = grp)
    end
    lines!(ax, [0, 30], [0, 30], color = :black); limits!(ax, -1, 30, -1, 30)
    c == 1 && axislegend(ax, position = :lt, labelsize = 11)
end
save(joinpath(FIG, "stratification.png"), fig, px_per_unit = 1.3)

# Deep water through the run: FjordSim and the reference models daily, observations on the cast days.
picks = [("VAL-1", 100.0), ("MO-2", 80.0), ("D-2", 50.0), ("D-2", 100.0), ("D-3", 50.0), ("Im2", 100.0), ("Fl1", 100.0),
         ("Dk1", 60.0), ("Ep1", 60.0), ("Ep1", 120.0)]
function fjordsim_daily(s, var, d)
    c = findfirst(==(s), run["names"])
    return run["times"], [interp(run["z"], run[var][:, c, n], d) for n in eachindex(run["times"])]
end
function reference_daily(k, s, var, d)
    haskey(reference[k], s) || return DateTime[], Float64[]
    col = reference[k][s]; V = var == "S" ? col.daily_S : col.daily_T
    return col.days, [interp(depths(col, n), V[:, n], d) for n in eachindex(col.days)]
end
"Each pick's salinity and temperature at its depth through the window, as `<name>.png` and `<name>.csv`."
function drift_figure(picks, name)
    drift_rows = String[]
    fig = Figure(size = (1500, 270 * length(picks)))
    for (n, (s, d)) in enumerate(picks), (c, var) in enumerate(("S", "T"))
        ax = Axis(fig[n, c], title = @sprintf("%s, %s at %.0f m", s, var == "S" ? "salinity" : "temperature", d), ylabel = var == "S" ? "g/kg" : "°C")
        t, v = fjordsim_daily(s, var, d); lines!(ax, days_since_start.(t), v, color = COLORS["fjordsim"], linewidth = 2.5, label = LABELS["fjordsim"])
        tn, vn = reference_daily("norkyst", s, var, d); lines!(ax, days_since_start.(tn), vn, color = COLORS["norkyst"], linewidth = 2, label = LABELS["norkyst"])
        tf, vf = reference_daily("norfjords", s, var, d); lines!(ax, days_since_start.(tf), vf, color = COLORS["norfjords"], linewidth = 2, label = LABELS["norfjords"])
        ps = filter(p -> p.station == s && abs(p.depth - d) <= 1.0, cast_pairs)
        ts = unique(p.time for p in ps)
        ob = [mean(val(p, "obs", var) for p in ps if p.time == x) for x in ts]
        isempty(ts) || scatter!(ax, days_since_start.(ts), ob, color = :black, markersize = 14, label = "observed")
        n == length(picks) && (ax.xlabel = DAYS_LABEL)
        xlims!(ax, 0, days_since_start(RUN_END) + 3)
        n == 1 && c == 1 && axislegend(ax, position = :lb, labelsize = 10)
        for x in ts
            # A model's value on the cast's day; NaN where its series has ended (NorFjords after June 2026).
            nearest(times, values) = isempty(times) ? NaN :
                (k = argmin(abs.(Dates.value.(times .- x))); abs(times[k] - x) <= Day(1) ? values[k] : NaN)
            push!(drift_rows, @sprintf("%s,%.0f,%s,%s,%.2f,%.2f,%.2f,%.2f", s, d, var, Date(x), mean(val(p, "obs", var) for p in ps if p.time == x),
                nearest(t, v), nearest(tn, vn), nearest(tf, vf)))
        end
    end
    save(joinpath(FIG, "$name.png"), fig, px_per_unit = 1.1)
    writecsv(joinpath(TABLES, "$name.csv"), "station,depth,variable,date,obs,fjordsim,norkyst,norfjords", drift_rows)
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
    for k in ("norkyst",)
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
    r = score(ps, var, MODELS); isnothing(r) && continue
    n, om, st = r
    push!(rows, @sprintf("%s,%s,%d,%.2f,", s, var, n, om) * join([@sprintf("%.2f,%.2f", x...) for x in st], ","))
end
writecsv(joinpath(TABLES, "ferrybox_skill.csv"), "station,variable,n,obs_mean," * columns_of(MODELS), rows)
end

# Map: salinity bias below 20 m.
lon, lat, h = NCDataset(joinpath(RUN_SETUP, "bathymetry.nc")) do ds
    Float64.(ds["lon"][:]), Float64.(ds["lat"][:]), Float64.(coalesce.(ds["h"][:, :], NaN))
end
depthmap = map(x -> x < 0 ? -x : NaN, h)
function deep_bias(s, k)
    rows = filter(r -> r["station"] == s && r["variable"] == "S" && r["band"] in ("20-50 m", ">50 m"), k == "norfjords" ? skill_nf : skill)
    isempty(rows) && return NaN
    n = [num(r["n"]) for r in rows]; b = [num(r["$(k)_bias"]) for r in rows]
    return sum(n .* b) / sum(n)
end
fig = Figure(size = (1700, 1050))
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
