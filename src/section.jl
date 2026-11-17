# The Drammensfjord section: monthly-mean T and S against distance along the path and depth, with the
# D-2 and D-3 casts of that month drawn at their place on the section in the same colour scale.
include("section_data.jl")
using CairoMakie
set_theme!(fontsize = 17)

for (s, n) in place
    println(s, " -> ", sections[n].name, @sprintf(" at %.1f km", distance[n]))
end

# At most twelve months, evenly spread over the window.
all_months = [(year(d), month(d)) for d in Date(START):Month(1):(Date(STOP) - Day(1))]
months = all_months[1:cld(length(all_months), 12):end]
rows = cld(length(months), 2)
function monthly(var, y, m)
    M = fill(NaN, length(sections), length(centres))
    for (n, s) in enumerate(sections)
        sel = findall(t -> year(t) == y && month(t) == m, s.times)
        V = getfield(s, Symbol(var))
        M[n, :] = [mean(V[k, sel]) for k in axes(V, 1)]
    end
    return M
end

for (var, crange, contours, cmap, unit) in (("S", (24, 34), [25, 28, 29, 30, 31, 32, 33], :haline, "g/kg"),
                                            ("T", (2, 16), [5, 6, 7, 8, 9, 10, 12, 15], :thermal, "°C"))
    fig = Figure(size = (1900, 375rows))
    Label(fig[0, 1:2], "Drammensfjord section, monthly mean $(var == "S" ? "salinity" : "temperature"): " *
        "Drammenselva mouth (left) → Svelvik sill → Breiangen (right)", fontsize = 22, font = :bold)
    local hm
    for (i, (y, m)) in enumerate(months)
        r, c = fldmod1(i, 2)
        M = monthly(var, y, m)
        ax = Axis(fig[r, c], title = "$(Dates.monthname(m)) $y", yreversed = true, ylabel = c == 1 ? "depth (m)" : "",
            xlabel = r == rows ? "distance along the section (km)" : "")
        hm = heatmap!(ax, edges, reverse(faces), M[:, end:-1:1], colormap = cmap, colorrange = crange, nan_color = :gray80)
        contour!(ax, distance, reverse(centres), M[:, end:-1:1], levels = contours, color = :black, linewidth = 0.8,
            labels = true, labelsize = 12, labelcolor = :black)
        lines!(ax, distance, [s.depth for s in sections], color = :black, linewidth = 1.5)
        vlines!(ax, [distance[sill]], color = :black, linestyle = :dash, linewidth = 1)
        for (code, n) in place
            cs = filter(p -> p.station == code && year(p.time) == y && month(p.time) == m &&
                isfinite(getfield(p, Symbol(var))), casts)
            text!(ax, distance[n], 158, text = code, align = (:center, :bottom), fontsize = 13)
            isempty(cs) && continue
            d = [p.depth for p in cs]
            scatter!(ax, fill(distance[n], length(cs)), d, marker = Rect, markerspace = :data, markersize = (0.6, 1.0),
                color = [getfield(p, Symbol(var)) for p in cs], colormap = cmap, colorrange = crange)
            lines!(ax, distance[n] .+ [-0.3, 0.3, 0.3, -0.3, -0.3], [minimum(d) - 0.5, minimum(d) - 0.5, maximum(d) + 0.5,
                maximum(d) + 0.5, minimum(d) - 0.5], color = :black, linewidth = 0.8)
        end
        xlims!(ax, edges[1], edges[end]); ylims!(ax, 160, 0)
    end
    Colorbar(fig[1:rows, 3], hm, label = "$var ($unit)")
    save(joinpath(FIG, "section_drammensfjord_$(var).png"), fig, px_per_unit = 1.1)
    println("saved section ", var)
end
