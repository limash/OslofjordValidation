# Join the per-part extracts `extract_part<N>.jld2` (`bin/extract_run.sh`) into the one `extract.jld2` the
# report reads, in time order; where parts overlap, the later part wins.
#
#   REPORT=<name> julia --project src/merge_extract.jl [<prefix>]     (default extract: extract_part<N>.jld2 -> extract.jld2)
include("common.jl")
using JLD2

prefix = isempty(ARGS) ? "extract" : ARGS[1]
parts = sort(filter(f -> occursin(Regex("^$(prefix)_part\\d+\\.jld2\$"), f), readdir(REPORT_DATA)),
             by = f -> parse(Int, match(r"_part(\d+)", f)[1]))
X = [load(joinpath(REPORT_DATA, f)) for f in parts]
keep = [i == length(X) ? trues(length(x["times"])) : x["times"] .< first(X[i+1]["times"]) for (i, x) in enumerate(X)]
cat_time(key) = cat((x[key][:, :, k] for (x, k) in zip(X, keep))...; dims = 3)
times = reduce(vcat, x["times"][k] for (x, k) in zip(X, keep))
issorted(times) || error("records out of order across parts")
# A part pulled while the bucket still held an older copy of it ends early; it shows here as a gap.
gaps = [(a, b) for (a, b) in zip(times[1:end-1], times[2:end]) if b - a > Day(1) + Hour(1)]  # snapshots fall seconds after midnight
isempty(gaps) || error("gaps in the daily records (re-extract those parts): ", gaps)
stats = Dict(name => reduce(vcat, x["stats"][name][k] for (x, k) in zip(X, keep)) for name in keys(X[1]["stats"]))
coldest = reduce(vcat, x["coldest"][k] for (x, k) in zip(X, keep))
jldsave(joinpath(REPORT_DATA, "$prefix.jld2"); names = X[1]["names"], ij = X[1]["ij"], z = X[1]["z"], times,
        T = cat_time("T"), S = cat_time("S"), stats, coldest)
println("$prefix.jld2: ", length(parts), " parts, ", length(times), " records, ", first(times), " .. ", last(times))
