# MS Color Fantasy's FerryBox crossings of one day and FjordSim's hourly surface fields along them, for
# `ferry_video.jl` and `ferry_gap.jl`.
include("common.jl")
include("surface_videos.jl")
using .SurfaceVideos: TOWNS, LAND_COLOUR, bathymetry_grid
using JLD2

const FERRYBOX = joinpath(DATA, "observations", "niva_ferrybox_2024-2026")
const VARIABLES = (("T", "Temperature (°C)", :thermal), ("S", "Salinity (g kg⁻¹)", :haline))

value(x) = isempty(x) ? NaN : parse(Float64, x)

"Color Fantasy's FerryBox minutes on `day`, as `ferrybox_fetch.py` wrote them."
function ferrybox_day(day)
    rows = map(readlines(joinpath(FERRYBOX, "FA_$(Dates.format(day, "yyyymm")).csv"))[2:end]) do l
        f = split(l, ",")
        (time = DateTime(f[1]), lon = value(f[2]), lat = value(f[3]), T = value(f[4]), S = value(f[5]))
    end
    return filter(r -> Date(r.time) == day, rows)
end

"The minutes split into crossings at stops of over 30 minutes (a port call); a crossing has at least 30 minutes."
function crossings(rows)
    ends = [0; findall(>(Minute(30)), diff([r.time for r in rows])); length(rows)]
    return [rows[ends[k]+1:ends[k+1]] for k in 1:length(ends)-1 if ends[k+1] - ends[k] >= 30]
end

"The wet cell nearest the point."
function nearest_wet(grid, wet_cells, lon, lat)
    c = cosd(lat)
    return wet_cells[argmin([((grid.longitude[I[1]] - lon) * c)^2 + (grid.latitude[I[2]] - lat)^2 for I in wet_cells])]
end

"Weight of the next hourly record at `t`, and the record before it."
function hour_weight(times, t)
    k = min(searchsortedlast(times, t), length(times) - 1)
    return k, (t - times[k]) / (times[k+1] - times[k])
end

function field_at(A, times, t)
    k, w = hour_weight(times, t)
    return (1 - w) .* A[:, :, k] .+ w .* A[:, :, k+1]
end

function point_at(A, times, cell, t)
    k, w = hour_weight(times, t)
    return (1 - w) * A[cell, k] + w * A[cell, k+1]
end

km(a, b) = 6371 * 2asin(sqrt(sind((b.lat - a.lat) / 2)^2 + cosd(a.lat) * cosd(b.lat) * sind((b.lon - a.lon) / 2)^2))

"The day's hourly surface fields (`bin/vm_run.sh <report> ferry <day>`): their times and a Dict of T and S."
function ferry_fields(day)
    return jldopen(joinpath(REPORT_DATA, "ferry_fields_$day.jld2")) do f
        f["times"], Dict(var => f[var] for (var, _, _) in VARIABLES)
    end
end
