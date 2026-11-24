# One day's hourly surface T and S, cut from the run's surface snapshot parts for `ferry_video.jl`. Run by
# `bin/ferry_fields.sh` on a VM:
#
#     julia --project src/ferry_fields.jl <run start> <yyyy-mm-dd> <out.jld2> <snapshots_surface_<tag>_part<N>.jld2>...
#
# The parts are given in written order; a resumed run's part replaces the earlier one's records at the same times.
using Dates, JLD2

run_start, day, out = DateTime(ARGS[1]), DateTime(ARGS[2]), ARGS[3]
fields = Dict{DateTime,Tuple{Matrix{Float32},Matrix{Float32}}}()
for path in ARGS[4:end]
    jldopen(path) do f
        for it in keys(f["timeseries/t"])
            t = round(run_start + Millisecond(round(Int, 1000 * f["timeseries/t/$it"])), Minute)
            day <= t <= day + Day(1) || continue
            fields[t] = (f["timeseries/T/$it"][:, :, 1], f["timeseries/S/$it"][:, :, 1])
        end
    end
end
times = sort(collect(keys(fields)))
length(times) == 25 || error("found $(length(times)) hourly records of $(Date(day)), not 25")
jldsave(out; times, T = stack(first(fields[t]) for t in times), S = stack(last(fields[t]) for t in times))
println("Wrote $out")
