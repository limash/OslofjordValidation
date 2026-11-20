# The Drammensfjord section DS-00..DS-76 (Drammenselva mouth, basin, Svelvik sill, Sandebukta, Breiangen)
# as read from the run's hourly section file from START to STOP, its geometry along the path, and where the D-2
# and D-3 casts fall on it. Shared by `section.jl` and `sill_exchange.jl`.
include("common.jl")

# The section file has no grid faces or dry-cell mask; the faces are a hydrography station file's (the
# same grid) and a level is dry where its top face lies below the station's model water depth.
faces = NCDataset(ds -> -Float64.(ds["z_aaf"][:]), first(run_files("stations_hydrography", "_D_2.nc")))
section_files = run_files("stations_section", ".nc")
sections = NCDataset(first(section_files)) do ds
    read(var) = read_joined(file -> Float64.(coalesce.(file[var][:, :, :], NaN)), section_files)
    times, T = read("T")
    keep = findall(t -> START <= t <= STOP, times)
    T, S, u, v = T[:, :, keep], read("S")[2][:, :, keep], read("u")[2][:, :, keep], read("v")[2][:, :, keep]
    names = ds["station_name"][:]; lon = Float64.(ds["model_longitude"][:]); lat = Float64.(ds["model_latitude"][:])
    depth = Float64.(ds["model_water_depth"][:])
    map(eachindex(names)) do n
        dry = [faces[k+1] >= depth[n] for k in 1:length(faces)-1]
        cut(A) = (V = A[n, :, :]; V[dry, :] .= NaN; V)
        (name = string(names[n]), lon = lon[n], lat = lat[n], depth = depth[n], times = times[keep],
         T = cut(T), S = cut(S), u = cut(u), v = cut(v))
    end
end
haversine(a, b) = 2 * 6371.0 * asind(sqrt(sind((b.lat - a.lat) / 2)^2 + cosd(a.lat) * cosd(b.lat) * sind((b.lon - a.lon) / 2)^2)) * π / 180
distance = cumsum(vcat(0.0, [haversine(sections[n-1], sections[n]) for n in 2:length(sections)]))
edges = vcat(distance[1] - 0.2, [(distance[n] + distance[n+1]) / 2 for n in 1:length(distance)-1], distance[end] + 0.2)
centres = [(faces[k] + faces[k+1]) / 2 for k in 1:length(faces)-1]
sill = argmin([s.name == "DS-53" ? 0 : 1 for s in sections])

# The velocity along the path, + towards Breiangen (out of the fjord), from the cell-centred u and v
# and the path direction between each station's neighbours.
along = map(eachindex(sections)) do n
    a, b = sections[max(n - 1, 1)], sections[min(n + 1, end)]
    east, north = (b.lon - a.lon) * cosd((a.lat + b.lat) / 2), b.lat - a.lat
    return (sections[n].u .* east .+ sections[n].v .* north) ./ hypot(east, north)
end

# Where the D-2 and D-3 casts fall on the section: the nearest section station.
casts = filter(c -> c.station in ("D-2", "D-3"), niva_casts(START, STOP))
place = Dict(s => argmin([hypot((p.lon - c.lon) * cosd(c.lat), p.lat - c.lat) for p in sections])
             for (s, c) in ((s, first(filter(c -> c.station == s, casts))) for s in ("D-2", "D-3")))
