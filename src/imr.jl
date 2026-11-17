# Score FjordSim, NorKyst-v3 and NorFjords-160m against IMR's casts in the outer fjord (`imr_fetch.py`):
# the ØkoKyst stations Færder, Torbjørnskjær (OF-1), Missingene (OF-2), Bastøy (OF-4) and Breiangen vest
# (OF-5), and Tisler. Vannmiljø dates a cast without a time of day, so each model is taken over the cast's
# day: FjordSim as the mean of the snapshots at its start and end (`extract.jld2`), NorKyst and NorFjords as
# their daily means (`imr_norkyst.jld2`, `imr_norfjords.jld2`). Writes `imr_pairs.csv`, `imr_skill.csv`
# (FjordSim and NorKyst on the samples both reach), `imr_skill_norfjords.csv` (FjordSim and NorFjords on the
# samples both reach), `imr_skill_each.csv` (each model on every sample it reaches) and the figures
# `imr_bias.png` and `imr_series_<station>.png`.
include("common.jl")
using JLD2, CairoMakie
set_theme!(fontsize = 16)

run = load(joinpath(REPORT_DATA, "extract.jld2"))   # the NIVA and IMR cells were extracted together
cells = Dict(r["station"] => r for r in readcsv(joinpath(REPORT_DATA, "imr_cells.csv")))
reference = Dict(k => load(joinpath(REPORT_DATA, "imr_$k.jld2"), "columns") for k in ("norkyst", "norfjords"))
# South to north.
const STATIONS = ["Færder", "Torbjørnskjær", "Tisler-1", "Tisler-5", "Missingene", "Bastøy", "Breiangen vest"]
const KEYS = ("obs", ALL_MODELS...)

"FjordSim's `var` column on `day`: the mean of the snapshots at its start and end."
function fjordsim_column(station, day, var)
    c = findfirst(==(station), run["names"])
    k = findfirst(t -> Date(t) == day, run["times"])
    (isnothing(k) || k == length(run["times"])) && return nothing
    return (run[var][:, c, k] .+ run[var][:, c, k+1]) ./ 2
end

"A reference model's daily mean of `var` at `depth` on `day`."
function reference_value(model, station, day, var, depth)
    col = get(reference[model], station, nothing); isnothing(col) && return NaN
    d = findfirst(==(day), col.days); isnothing(d) && return NaN
    z = col.z isa AbstractMatrix ? col.z[:, d] : col.z
    return interp(z, (var == "T" ? col.daily_T : col.daily_S)[:, d], depth)
end

pairs = []
for c in niva_casts(START, STOP; dir = IMR_OBS)
    day = Date(c.time)
    mT = fjordsim_column(c.station, day, "T"); mS = fjordsim_column(c.station, day, "S")
    isnothing(mT) && continue
    push!(pairs, (station = c.station, time = c.time, depth = c.depth,
        obs_T = c.T, fjordsim_T = interp(run["z"], mT, c.depth),
        norkyst_T = reference_value("norkyst", c.station, day, "T", c.depth),
        norfjords_T = reference_value("norfjords", c.station, day, "T", c.depth),
        obs_S = c.S, fjordsim_S = interp(run["z"], mS, c.depth),
        norkyst_S = reference_value("norkyst", c.station, day, "S", c.depth),
        norfjords_S = reference_value("norfjords", c.station, day, "S", c.depth)))
end
sort!(pairs, by = p -> (p.station, p.time, p.depth))
val(p, k, var) = getfield(p, Symbol("$(k)_$(var)"))
writecsv(joinpath(REPORT_DATA, "imr_pairs.csv"), "station,time,depth," * join(["$(k)_T" for k in KEYS], ",") * "," *
    join(["$(k)_S" for k in KEYS], ","),
    [join([p.station, Dates.format(p.time, "yyyy-mm-dd"), p.depth, [@sprintf("%.3f", val(p, k, v)) for v in ("T", "S") for k in KEYS]...], ",")
     for p in pairs])
println("pairs: ", length(pairs), "  casts: ", length(unique((p.station, p.time) for p in pairs)))

# --- statistics, from November on as for the NIVA casts --------------------------------------------------
scored = filter(p -> p.time >= SPINUP, pairs)
bands = [("0-5 m", 0, 5), ("5-20 m", 5, 20), ("20-50 m", 20, 50), ("50-150 m", 50, 150), (">150 m", 150, 1e4), ("all", 0, 1e4)]
"Count, observed mean and per-model (bias, RMSE) on the samples every model in `models` reaches."
function score(ps, var, models)
    o = [val(p, "obs", var) for p in ps]
    m = [[val(p, k, var) for p in ps] for k in models]
    ok = isfinite.(o) .& reduce(.&, [isfinite.(x) for x in m])
    count(ok) < 3 && return nothing
    return count(ok), mean(o[ok]), [(mean(x[ok] .- o[ok]), sqrt(mean((x[ok] .- o[ok]) .^ 2))) for x in m]
end
groups = ["ALL"; STATIONS]
in_group(p, g) = g == "ALL" || p.station == g
for (models, file) in ((MODELS, "imr_skill.csv"), (("fjordsim", "norfjords"), "imr_skill_norfjords.csv"))
    rows = String[]
    for g in groups, var in ("S", "T"), (b, lo, hi) in bands
        r = score(filter(p -> in_group(p, g) && lo <= p.depth < hi, scored), var, models); isnothing(r) && continue
        n, om, st = r
        push!(rows, @sprintf("%s,%s,%s,%d,%.2f,", g, var, b, n, om) * join([@sprintf("%.2f,%.2f", x...) for x in st], ","))
    end
    writecsv(joinpath(TABLES, file), "station,variable,band,n,obs_mean," * join(["$(k)_bias,$(k)_rmse" for k in models], ","), rows)
end
rows = String[]
for g in groups, var in ("S", "T"), (b, lo, hi) in bands
    each = [score(filter(p -> in_group(p, g) && lo <= p.depth < hi, scored), var, (k,)) for k in ALL_MODELS]
    all(isnothing, each) && continue
    push!(rows, "$g,$var,$b," * join([isnothing(e) ? "0,NaN,NaN" : @sprintf("%d,%.2f,%.2f", e[1], e[3][1]...) for e in each], ","))
end
writecsv(joinpath(TABLES, "imr_skill_each.csv"), "station,variable,band," * join(["$(k)_n,$(k)_bias,$(k)_rmse" for k in ALL_MODELS], ","), rows)

# --- figures -----------------------------------------------------------------------------------------
# Mean error against depth at each station over the scored window, each model on its own samples.
finite_mean(x) = (y = filter(isfinite, x); isempty(y) ? NaN : mean(y))
fig = Figure(size = (2000, 1150))
for (c, s) in enumerate(STATIONS), (r, var) in enumerate(("S", "T"))
    ps = filter(p -> p.station == s, scored)
    depths = sort(unique(p.depth for p in ps))
    ax = Axis(fig[r, c], yreversed = true, title = r == 1 ? s : "", ylabel = c == 1 ? "depth (m)" : "",
        xlabel = var == "S" ? "salinity error" : "temperature error (°C)", xticks = LinearTicks(4))
    vlines!(ax, 0, color = :gray60)
    for k in ALL_MODELS
        e = [(d, finite_mean([val(p, k, var) - val(p, "obs", var) for p in ps if p.depth == d])) for d in depths]
        e = filter(x -> isfinite(x[2]) && count(p -> p.depth == x[1] && isfinite(val(p, k, var)), ps) >= 3, e)
        isempty(e) && continue
        scatterlines!(ax, last.(e), first.(e), color = COLORS[k], linewidth = k == "fjordsim" ? 3 : 2, markersize = 7, label = LABELS[k])
    end
    m = cells[s]
    r == 2 && text!(ax, 0.02, 0.02, space = :relative, align = (:left, :bottom), fontsize = 12,
        text = @sprintf("FjordSim %.0f m", num(m["model_depth_m"])))
    c == 1 && r == 1 && axislegend(ax, position = :lb, labelsize = 11)
end
save(joinpath(FIG, "imr_bias.png"), fig, px_per_unit = 1.1)

# Each station's casts through the window at fixed depths: FjordSim's daily snapshots as a line, the
# reference models on the cast days.
for s in STATIONS
    ps = filter(p -> p.station == s, pairs)
    deepest = maximum(p.depth for p in ps)
    levels = filter(d -> d <= deepest, [0.0, 10.0, 30.0, 75.0, 150.0, 300.0])
    local fig = Figure(size = (1500, 230 * length(levels) + 60))
    c = findfirst(==(s), run["names"])
    keep = findall(t -> t <= STOP, run["times"])
    x = days_since_start.(run["times"][keep])
    for (r, d) in enumerate(levels), (col, var) in enumerate(("S", "T"))
        ax = Axis(fig[r, col], title = @sprintf("%s, %.0f m", var == "S" ? "salinity" : "temperature (°C)", d),
            xlabel = r == length(levels) ? DAYS_LABEL : "")
        y = [interp(run["z"], run[var][:, c, k], d) for k in keep]
        lines!(ax, x, y, color = COLORS["fjordsim"], linewidth = 2, label = LABELS["fjordsim"])
        at = filter(p -> p.depth == d, ps)
        isempty(at) && continue   # no sample at this depth
        for k in ("norkyst", "norfjords")
            scatterlines!(ax, days_since_start.([p.time + Hour(12) for p in at]), [val(p, k, var) for p in at],
                color = COLORS[k], markersize = 8, linewidth = 1.5, label = LABELS[k])
        end
        scatter!(ax, days_since_start.([p.time + Hour(12) for p in at]), [val(p, "obs", var) for p in at],
            color = COLORS["obs"], markersize = 11, label = LABELS["obs"])
        r == 1 && col == 1 && axislegend(ax, position = :lb, labelsize = 11)
    end
    m = cells[s]
    Label(fig[0, :], @sprintf("%s: casts to %.0f m; FjordSim %.0f m deep", s, deepest, num(m["model_depth_m"])), fontsize = 18, font = :bold)
    save(joinpath(FIG, "imr_series_$(stem(s)).png"), fig, px_per_unit = 1.1)
end
println("figures written")
