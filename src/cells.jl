# The model column each station is scored at: for a CTD station, the wet cell within three cells whose
# depth best matches the deepest cast, with a penalty for distance; for a FerryBox point, the nearest wet cell.
#
#   julia cells.jl [<casts directory> <output csv>]     (default: the NIVA casts, cells.csv)
include("common.jl")

lon, lat, h = NCDataset(joinpath(RUN_SETUP, "bathymetry.nc")) do ds
    Float64.(ds["lon"][:]), Float64.(ds["lat"][:]), Float64.(coalesce.(ds["h"][:, :], NaN))
end

function model_cell(slon, slat, obsmax, by_depth)
    i0 = argmin(abs.(lon .- slon)); j0 = argmin(abs.(lat .- slat))
    best = (Inf, 0, 0)
    for i in max(1, i0 - 3):min(length(lon), i0 + 3), j in max(1, j0 - 3):min(length(lat), j0 + 3)
        h[i, j] < 0 || continue
        dist = hypot((lon[i] - slon) * cosd(slat) * 111.2e3, (lat[j] - slat) * 111.2e3)
        score = (by_depth ? abs(min(-h[i, j], 470) - min(obsmax, 470)) / max(obsmax, 10) : 0.0) + dist / 600
        score < best[1] && (best = (score, i, j))
    end
    _, i, j = best
    i == 0 && return nothing
    return i, j, -h[i, j], hypot((lon[i] - slon) * cosd(slat) * 111.2e3, (lat[j] - slat) * 111.2e3)
end

dir, out = isempty(ARGS) ? (OBS, joinpath(REPORT_DATA, "cells.csv")) : (ARGS[1], ARGS[2])
casts = niva_casts(START, STOP; with_ferrybox = true, dir)
rows = String[]
for s in sort(unique(c.station for c in casts))
    cs = filter(c -> c.station == s, casts)
    obsmax = maximum(c.depth for c in cs)
    cell = model_cell(cs[1].lon, cs[1].lat, obsmax, !ferrybox(s))
    isnothing(cell) && (println("no wet cell near ", s); continue)
    i, j, d, dist = cell
    push!(rows, @sprintf("%s,%s,%.4f,%.4f,%.0f,%d,%d,%.1f,%.0f,%d", s, cs[1].project, cs[1].lon, cs[1].lat, obsmax, i, j, d, dist,
        length(unique(c.time for c in cs))))
end
writecsv(out, "station,project,lon,lat,deepest_cast_m,model_i,model_j,model_depth_m,model_offset_m,casts", rows)
foreach(println, rows)
