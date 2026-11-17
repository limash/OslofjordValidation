# One pass over the daily 3D snapshots: T and S columns at the CTD stations' model cells, and
# whole-domain statistics. Reading a column time series straight from the file would read every chunk
# once per station, since the chunks are one record each.
#
#   REPORT=<name> julia --project src/extract.jl <out.jld2> <cells.csv> <snapshots.nc>
include("common.jl")
using JLD2

out, cellfile = ARGS[1], ARGS[2]
files = ARGS[3:end]
cells = readcsv(cellfile)
names = [c["station"] for c in cells]
ij = [(parse(Int, c["model_i"]), parse(Int, c["model_j"])) for c in cells]

z, dry, volume = NCDataset(files[end]) do ds
    dry = Array(ds["inactive_nodes_ccc"][:, :, :]) .!= 0
    area = Float64.(ds["Δx_cca"][:, :]) .* Float64.(ds["Δy_cca"][:, :])
    dz = Float64.(ds["Δz_aac"][:])
    -Float64.(ds["z_aac"][:]), dry, [area[i, j] * dz[k] for i in axes(dry, 1), j in axes(dry, 2), k in axes(dry, 3)]
end
wet = .!dry
wetvolume = sum(volume[wet])

# Records in time order; where files overlap, the later file wins.
records = Tuple{Int,Int,DateTime}[]
for (f, path) in enumerate(files)
    NCDataset(path) do ds
        start = DateTime(ds.attrib["start_date"])
        for (n, s) in enumerate(ds["time"][:])
            push!(records, (f, n, start + Millisecond(round(Int, 1000s))))
        end
    end
end
for f in 2:length(files)
    cut = minimum(r[3] for r in records if r[1] == f)
    filter!(r -> r[1] >= f || r[3] < cut, records)
end
sort!(records, by = last)

Nz, Nc, Nt = length(z), length(cells), length(records)
T = fill(NaN, Nz, Nc, Nt); S = fill(NaN, Nz, Nc, Nt)
stats = Dict(k => fill(NaN, Nt) for k in ("meanT", "meanS", "minT", "maxT", "minS", "maxS", "cold_cells", "hot_cells"))
coldest = Vector{NTuple{3,Int}}(undef, Nt)
for (f, path) in enumerate(files)
    NCDataset(path) do ds
        for (m, (rf, n, t)) in enumerate(records)
            rf == f || continue
            for (name, A) in (("T", T), ("S", S))
                x = Float64.(coalesce.(ds[name][:, :, :, n], NaN))
                x[dry] .= NaN
                for (c, (i, j)) in enumerate(ij)
                    A[:, c, m] = x[i, j, :]
                end
                values = x[wet]
                stats["mean$name"][m] = sum(values .* volume[wet]) / wetvolume
                stats["min$name"][m], k = findmin(x -> isfinite(x) ? x : Inf, x)
                name == "T" && (coldest[m] = Tuple(k))
                stats["max$name"][m] = maximum(x -> isfinite(x) ? x : -Inf, x)
                if name == "T"
                    stats["cold_cells"][m] = count(<(-1.0), values)
                    stats["hot_cells"][m] = count(>(25.0), values)
                end
            end
            m % 25 == 0 && println(t, "  ", round(stats["minT"][m], digits = 2), " ", coldest[m])
        end
    end
end
jldsave(out; names, ij, z, times = last.(records), T, S, stats, coldest)
println("wrote ", out, ": ", Nt, " records")
