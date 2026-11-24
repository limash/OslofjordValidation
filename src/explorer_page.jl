# What the explorer pages share: plotly.js from a CDN, their data as JSON, and the map background.
using CairoMakie, Base64

const PLOTLY = "https://cdn.jsdelivr.net/npm/plotly.js-dist-min@2.35.2/plotly.min.js"

# JSON for the pages' data: numbers to 3 decimals, NaN as null.
json(io, x::Bool) = print(io, x)
json(io, x::Real) = isfinite(x) ? print(io, round(x, digits = 3)) : print(io, "null")
json(io, x::AbstractString) = print(io, '"', replace(x, "\\" => "\\\\", "\"" => "\\\""), '"')
json(io, x::Symbol) = json(io, string(x))
function json(io, x::Union{AbstractVector,Tuple})
    print(io, '[')
    for (i, v) in enumerate(x)
        i > 1 && print(io, ','); json(io, v)
    end
    print(io, ']')
end
function json(io, x::Union{AbstractDict,NamedTuple})
    print(io, '{')
    for (i, k) in enumerate(keys(x))
        i > 1 && print(io, ','); json(io, string(k)); print(io, ':'); json(io, x[k])
    end
    print(io, '}')
end
json(x) = sprint(json, x)

"The map's extent: the outer edges of the model grid's cells."
function map_extent(lon, lat)
    dlon, dlat = lon[2] - lon[1], lat[2] - lat[1]
    return (x0 = lon[1] - dlon / 2, x1 = lon[end] + dlon / 2, y0 = lat[1] - dlat / 2, y1 = lat[end] + dlat / 2)
end

"The model depth, light, as a PNG data URL to lay under a map."
function map_background(lon, lat, depth)
    extent = map_extent(lon, lat)
    mktempdir() do dir
        fig = Figure(size = (length(lon), length(lat)), figure_padding = 0)
        ax = Axis(fig[1, 1]); hidedecorations!(ax); hidespines!(ax)
        heatmap!(ax, lon, lat, depth, colormap = cgrad([RGBf(0.93, 0.95, 0.97), RGBf(0.55, 0.62, 0.70)]), colorrange = (0, 350),
            nan_color = RGBf(0.97, 0.96, 0.93))
        limits!(ax, extent.x0, extent.x1, extent.y0, extent.y1)
        path = joinpath(dir, "map.png"); save(path, fig, px_per_unit = 2)
        "data:image/png;base64," * base64encode(read(path))
    end
end
