# Map of the domain with the stations this report scores and the open boundary; plus effective sill depths
# and station depths.
include("common.jl")
using CairoMakie

lon, lat, h = NCDataset(joinpath(RUN_SETUP, "bathymetry.nc")) do ds
    Float64.(ds["lon"][:]), Float64.(ds["lat"][:]), Float64.(coalesce.(ds["h"][:, :], NaN))
end
depth = map(x -> x < 0 ? -x : NaN, h)

# Stations as placed by the run (model cell), from the station file attributes.
function stations(stem)
    out = []
    for f in sort(readdir(RES))
        m = match(Regex("^$(stem)_$(STAMP)_(.+)\\.nc\$"), f)
        isnothing(m) && continue
        NCDataset(joinpath(RES, f)) do ds
            a = ds.attrib
            push!(out, (name = string(a["station_name"]), lon = Float64(a["station_longitude"]), lat = Float64(a["station_latitude"]),
                mlon = Float64(a["model_longitude"]), mlat = Float64(a["model_latitude"]), depth = Float64(a["model_water_depth"]),
                moved = Float64(a["snap_offset_metres"])))
        end
    end
    return out
end
ctd = stations("stations_hydrography")
# The stations with a station writer, whose hourly output the report draws.
written = Set(s.name for s in ctd)
gauges = [(name = "Viker", lon = 10.949769, lat = 59.036046), (name = "Oscarsborg", lon = 10.604861, lat = 59.678073), (name = "Oslo", lon = 10.734510, lat = 59.908559)]
# River inflow columns: the ownership map of the river file.
rivers = NCDataset(joinpath(RUN_SETUP, "rivers_nve.nc")) do ds
    owner = ds["river"][:, :]
    [(lon[I[1]], lat[I[2]]) for I in CartesianIndices(owner) if coalesce(owner[I], 0) > 0]
end

# Effective sill depth between two cells: the deepest bottleneck over all wet paths (maximin path).
function connected(a, b, threshold)
    seen = falses(size(depth)); stack = [a]; seen[a...] = true
    while !isempty(stack)
        i, j = pop!(stack)
        (i, j) == b && return true
        for (di, dj) in ((1, 0), (-1, 0), (0, 1), (0, -1))
            ni, nj = i + di, j + dj
            (1 <= ni <= size(depth, 1) && 1 <= nj <= size(depth, 2)) || continue
            (seen[ni, nj] || !(depth[ni, nj] >= threshold)) && continue
            seen[ni, nj] = true; push!(stack, (ni, nj))
        end
    end
    return false
end
function sill_depth(a, b)
    levels = sort(unique(filter(isfinite, depth)))
    lo, hi = 1, length(levels)
    while lo < hi   # the deepest threshold that still connects a and b
        mid = (lo + hi + 1) ÷ 2
        connected(a, b, levels[mid]) ? (lo = mid) : (hi = mid - 1)
    end
    return levels[lo]
end
cell(lo, la) = (argmin(abs.(lon .- lo)), argmin(abs.(lat .- la)))
st(name) = only(filter(s -> s.name == name, ctd))
sills = [
    ("Drøbak (Ep1 ↔ OF-5)", sill_depth(cell(st("Ep1").mlon, st("Ep1").mlat), cell(st("OF-5").mlon, st("OF-5").mlat)), "≈20 (natural sill east of the jetty)"),
    ("Svelvik (D-2 ↔ OF-5)", sill_depth(cell(st("D-2").mlon, st("D-2").mlat), cell(st("OF-5").mlon, st("OF-5").mlat)), "11 (minimum), 180 m wide"),
]
open(joinpath(TABLES, "sills.csv"), "w") do io
    println(io, "sill,model_m,real_m")
    for (n, d, r) in sills; println(io, "$n,$(round(d, digits=1)),$r"); end
end
# Wet columns and wet cells of the model grid: a cell is wet where its top face is above the column's bottom.
z_faces = NCDataset(ds -> Float64.(ds["z_faces"][:]), joinpath(RUN_SETUP, "bathymetry.nc"))
nz = length(z_faces) - 1
open(joinpath(TABLES, "grid_cells.csv"), "w") do io
    println(io, "nx,ny,nz,wet_columns,wet_cells")
    println(io, join((length(lon), length(lat), nz, count(<(0), h), sum(count(>(x), z_faces[2:end]) for x in h if x < 0)), ","))
end
open(joinpath(TABLES, "station_depths.csv"), "w") do io
    println(io, "type,name,lon,lat,model_water_depth,moved_m")
    for s in ctd
        @printf(io, "%s,%s,%.4f,%.4f,%.1f,%.0f\n", "CTD", s.name, s.lon, s.lat, s.depth, s.moved)
    end
end

# --- the map -----------------------------------------------------------------------------------
# Only the stations this report scores: NIVA cast stations with casts in the window (those with the run's
# hourly output filled), IMR's stations, and the tide gauges.
with_casts = Set(r["station"] for r in readcsv(joinpath(REPORT_DATA, "ctd_pairs.csv")))
niva = [(name = r["station"], lon = num(r["lon"]), lat = num(r["lat"])) for r in readcsv(joinpath(REPORT_DATA, "cells.csv"))
        if r["station"] in with_casts]
niva_hourly = filter(s -> s.name in written, niva)
niva_daily = filter(s -> !(s.name in written), niva)
# IMR's Torbjørnskjær and Breiangen vest are the run's hourly stations OF-1 and OF-5.
imr_alias = Dict("Torbjørnskjær" => "Torbjørnskjær (OF-1)", "Breiangen vest" => "Breiangen vest (OF-5)")
imr = [(name = get(imr_alias, r["station"], r["station"]), lon = num(r["lon"]), lat = num(r["lat"]))
       for r in readcsv(joinpath(REPORT_DATA, "imr_cells.csv"))]

fig = Figure(size = (1350, 1650), fontsize = 20)
aspect = cosd(59.4)
ax = Axis(fig[1, 1], xlabel = "Longitude (°E)", ylabel = "Latitude (°N)",
    title = "Stations scored in this report, on the model depth", titlesize = 24)
ax.aspect = AxisAspect((lon[end] - lon[1]) * aspect / (lat[end] - lat[1]))
hm = heatmap!(ax, lon, lat, depth, colormap = :deep, colorrange = (0, 350), nan_color = RGBf(0.88, 0.87, 0.84))
Colorbar(fig[1, 2], hm, label = "Model depth (m)", height = Relative(0.5))
colgap!(fig.layout, 10)
hlines!(ax, [lat[1] + 0.002], color = :red, linewidth = 7)
text!(ax, 10.08, lat[1] + 0.008, text = "open boundary (south)", color = :red, fontsize = 18, font = :bold)
scatter!(ax, first.(rivers), last.(rivers), marker = :utriangle, color = :deepskyblue, markersize = 8, strokecolor = :black,
    strokewidth = 0.4, label = "river inflow column (volume source)")
scatter!(ax, [s.lon for s in niva_hourly], [s.lat for s in niva_hourly], marker = :circle, color = :limegreen, markersize = 20,
    strokecolor = :black, strokewidth = 1.5, label = "NIVA casts, with the run's hourly station output")
scatter!(ax, [s.lon for s in niva_daily], [s.lat for s in niva_daily], marker = :circle, color = :white, markersize = 15,
    strokecolor = :darkgreen, strokewidth = 2.5, label = "NIVA casts, scored from the daily 3D output")
scatter!(ax, [s.lon for s in imr], [s.lat for s in imr], marker = :diamond, color = :darkorange, markersize = 22,
    strokecolor = :black, strokewidth = 1.5, label = "IMR casts (ØkoKyst, Tisler)")
scatter!(ax, [g.lon for g in gauges], [g.lat for g in gauges], marker = :rect, color = :gold, markersize = 22,
    strokecolor = :black, strokewidth = 1.5, label = "tide gauge (Kartverket)")
# The Oslo harbour stations sit within a few kilometres of each other; their labels are spread by hand.
small_offsets = Dict("Ap2" => (-0.04, -0.004), "Aq3" => (0.008, -0.009), "Cq1" => (-0.042, -0.002), "Cp2" => (-0.045, -0.004),
    "Bn1" => (-0.04, 0.004), "Bl4" => (-0.04, 0.0), "Hm4" => (-0.058, -0.004), "Aq2" => (0.008, 0.006), "Br1" => (0.008, 0.0),
    "Ap3" => (-0.04, 0.008))
offsets = Dict("S-9" => (-0.06, 0.014), "D-2" => (0.013, 0.004), "Oscarsborg" => (0.015, 0.0), "Oslo" => (0.015, 0.007),
    "Viker" => (0.015, 0.006), "Dk1" => (0.015, -0.004), "Ep1" => (0.015, 0.0), "Tisler-5" => (-0.085, 0.008),
    "Tisler-1" => (0.012, -0.006), "Breiangen vest (OF-5)" => (-0.235, 0.0), "Bastøy" => (-0.085, 0.0),
    "Færder" => (0.013, 0.006), "Torbjørnskjær (OF-1)" => (-0.215, -0.008))
for s in niva_daily
    dx, dy = get(small_offsets, s.name, (0.008, 0.0))
    text!(ax, s.lon + dx, s.lat + dy, text = s.name, fontsize = 13, align = (:left, :center), color = :darkgreen, font = :bold)
end
for s in vcat(niva_hourly, gauges)
    dx, dy = get(offsets, s.name, (0.013, 0.0))
    text!(ax, s.lon + dx, s.lat + dy, text = s.name, fontsize = 16, align = (:left, :center), font = :bold)
end
for s in imr
    dx, dy = get(offsets, s.name, (0.013, 0.0))
    text!(ax, s.lon + dx, s.lat + dy, text = s.name, fontsize = 15, align = (:left, :center), color = :darkorange3, font = :bold)
end
for (name, lo, la) in (("Drammensfjord", 10.10, 59.69), ("Inner Oslofjord", 10.80, 59.76), ("Breiangen", 10.27, 59.46), ("Skagerrak", 10.12, 58.975),
        ("Drøbak Sound", 10.68, 59.635), ("Svelvik ↗", 10.30, 59.585), ("Hvaler", 11.07, 59.06), ("Larvik", 10.03, 59.07))
    text!(ax, lo, la, text = name, fontsize = 17, color = :gray20, font = :italic)
end
axislegend(ax, position = :lt, framevisible = true, labelsize = 15)
limits!(ax, lon[1], lon[end], lat[1], lat[end])
save(joinpath(FIG, "map.png"), fig, px_per_unit = 1.4)
println(sills)
