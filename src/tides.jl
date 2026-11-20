# Sea level against the tide gauges: Kartverket's cached observations, a run's tide-gauge station files, pairing
# the two in time, and least-squares harmonic analysis. Copied from FjordSim.jl (`src/Validation/metrics.jl`,
# `src/Validation/results.jl`, `src/Observations/kartverket.jl`, `src/Observations/Observations.jl`) so the
# reports do not depend on FjordSim's code; only what `analysis.jl` uses.
using Dates, JLD2, LinearAlgebra, Statistics

"A tidal constituent, named and with its period in hours."
struct TidalConstituent
    name::String
    period_hours::Float64
end

# The thirteen constituents METreport 11/2017 Table 3 reports, by period, longest first.
const TIDAL_CONSTITUENTS = [
    TidalConstituent("SA", 8764.0),
    TidalConstituent("SSA", 4382.0),
    TidalConstituent("Q1", 26.8684),
    TidalConstituent("O1", 25.8193),
    TidalConstituent("P1", 24.0659),
    TidalConstituent("K1", 23.9345),
    TidalConstituent("N2", 12.6584),
    TidalConstituent("M2", 12.4206),
    TidalConstituent("S2", 12.0000),
    TidalConstituent("K2", 11.9672),
    TidalConstituent("MN4", 6.2692),
    TidalConstituent("M4", 6.2103),
    TidalConstituent("MS4", 6.1033),
]

"""
The result of `harmonic_fit`: a mean, and an amplitude and phase (degrees in [0, 360), from `reference`) per
constituent, with one standard error each. Phases are relative to `reference`, not Greenwich: no nodal
correction is applied, so only the difference between two fits with the same `reference` is meaningful.
"""
struct HarmonicFit
    constituents::Vector{TidalConstituent}
    mean::Float64
    amplitude::Vector{Float64}
    phase::Vector{Float64}
    amplitude_error::Vector{Float64}
    phase_error::Vector{Float64}
    reference::DateTime
    residual_std::Float64
    count::Int
end

"""
    harmonic_fit(times, values; constituents = TIDAL_CONSTITUENTS, reference = first(times))

Least-squares fit of `mean + Σ aₖcos(ωₖt) + bₖsin(ωₖt)`, as `t_tide` without nodal corrections. Non-finite
samples are dropped. Warns when the record is shorter than the longest period fitted.
"""
function harmonic_fit(times, values; constituents = TIDAL_CONSTITUENTS, reference = first(times))
    keep = [i for i in eachindex(values) if isfinite(values[i])]
    n = length(keep)
    m = 1 + 2 * length(constituents)
    n > m || throw(ArgumentError("harmonic_fit needs more finite samples than unknowns: $n against $m"))

    span_hours = Dates.value(Millisecond(times[keep[end]] - times[keep[1]])) / 3_600_000
    longest = maximum(constituent.period_hours for constituent in constituents)
    span_hours >= longest || @warn("Record is shorter than the longest constituent fitted",
        record_days = round(span_hours / 24; digits = 1), longest_period_days = round(longest / 24; digits = 1))

    t = [Dates.value(Millisecond(times[i] - reference)) / 3_600_000 for i in keep]
    y = Float64[values[i] for i in keep]
    design = ones(Float64, n, m)
    for (k, constituent) in enumerate(constituents)
        ω = 2π / constituent.period_hours
        design[:, 2k] = cos.(ω .* t)
        design[:, 2k + 1] = sin.(ω .* t)
    end
    coefficients = design \ y
    residual = y .- design * coefficients
    variance = sum(abs2, residual) / (n - m)
    covariance = variance .* inv(design' * design)

    amplitude, phase, amplitude_error, phase_error = Float64[], Float64[], Float64[], Float64[]
    for k in eachindex(constituents)
        a, b = coefficients[2k], coefficients[2k + 1]
        magnitude = hypot(a, b)
        push!(amplitude, magnitude)
        push!(phase, mod(rad2deg(atan(b, a)), 360))
        σa², σb² = covariance[2k, 2k], covariance[2k + 1, 2k + 1]
        if magnitude > 0
            push!(amplitude_error, sqrt((a^2 * σa² + b^2 * σb²) / magnitude^2))
            push!(phase_error, rad2deg(sqrt((b^2 * σa² + a^2 * σb²) / magnitude^4)))
        else
            push!(amplitude_error, sqrt(max(σa², σb²)))
            push!(phase_error, NaN)
        end
    end
    return HarmonicFit(collect(constituents), coefficients[1], amplitude, phase, amplitude_error, phase_error,
                       reference, std(residual; corrected = false), n)
end

"The elevation `fit` predicts at `times`; the series minus it is the non-tidal residual."
function reconstruct(fit::HarmonicFit, times)
    output = fill(fit.mean, length(times))
    for (index, time) in enumerate(times)
        t = Dates.value(Millisecond(time - fit.reference)) / 3_600_000
        for k in eachindex(fit.constituents)
            ω = 2π / fit.constituents[k].period_hours
            output[index] += fit.amplitude[k] * cos(ω * t - deg2rad(fit.phase[k]))
        end
    end
    return output
end

"""
A series at one station: `values` is `(length(times), length(depths))`, depths in metres below the surface,
ascending. Used for both the run's output and the observations.
"""
struct ModelSeries
    station::String
    variable::String
    times::Vector{DateTime}
    depths::Vector{Float64}
    values::Matrix{Float64}
    metadata::Dict{String,Any}
end

"""
    read_station_jld2(path, variable, reference)

One variable of a run's JLD2 station file (Oceananigans' layout: `timeseries/<name>/<iteration>`, model time in
`timeseries/t/<iteration>` as seconds from `reference`, the run's start date).
"""
function read_station_jld2(path, variable::AbstractString, reference::DateTime)
    return jldopen(path, "r") do file
        group = "timeseries/$variable"
        haskey(file, group) || throw(ArgumentError("Station file $path has no timeseries for $variable."))
        iterations = sort([parse(Int, key) for key in keys(file[group]) if all(isdigit, key)])
        times = [reference + Millisecond(round(Int, 1000 * file["timeseries/t/$i"])) for i in iterations]
        columns = [[ismissing(v) ? NaN : Float64(v) for v in vec(file["$group/$i"])] for i in iterations]
        levels = isempty(columns) ? 1 : length(first(columns))
        values = Matrix{Float64}(undef, length(columns), levels)
        for (index, column) in enumerate(columns)
            values[index, :] = column
        end
        stem = first(splitext(basename(path)))
        tag = match(r"_\d{8}T\d{6}(?:_loop\d+)?_(.+)$", stem)
        return ModelSeries(isnothing(tag) ? stem : String(tag.captures[1]), String(variable), times,
                           levels == 1 ? [0.0] : collect(0.0:(levels - 1)), values, Dict{String,Any}())
    end
end

"""
    join_station_series(series)

One station's `ModelSeries` from its files in written order. A resumed run writes under a new run tag from its
checkpoint on, so each file replaces every earlier record from its own first time on.
"""
function join_station_series(series)
    joined = first(series)
    for next in series[2:end]
        isempty(next.times) && continue
        next.depths == joined.depths ||
            throw(ArgumentError("Station $(next.station)'s files differ in depths, so they are not one run."))
        keep = joined.times .< first(next.times)
        joined = ModelSeries(joined.station, joined.variable, vcat(joined.times[keep], next.times), joined.depths,
                             vcat(joined.values[keep, :], next.values), joined.metadata)
    end
    return joined
end

"""
    kartverket_series(name, window)

A gauge's observed sea level over `window` in metres (on the datum the cache was fetched on, mean sea level),
from the monthly files FjordSim's `download_observations` caches in `observations/kartverket/`.
"""
function kartverket_series(name, window)
    start, stop = window
    times, values = DateTime[], Float64[]
    for first_day in Date(year(start), month(start)):Month(1):Date(year(stop), month(stop))
        path = joinpath(DATA, "observations", "kartverket", "$(obs_stem(name))_$(Dates.format(first_day, "yyyymm")).xml")
        isfile(path) || continue
        for m in eachmatch(r"<waterlevel\s+value=\"([^\"]+)\"\s+time=\"([^\"]+)\"", read(path, String))
            value = tryparse(Float64, m.captures[1]); time = tryparse(DateTime, first(m.captures[2], 19))
            (isnothing(value) || isnothing(time) || !(start <= time <= stop)) && continue
            push!(times, time); push!(values, value / 100)
        end
    end
    order = sortperm(times)
    return ModelSeries(name, "eta", times[order], [0.0], reshape(values[order], :, 1), Dict{String,Any}())
end

"""
    match_series(observation, model; depth = nothing, tolerance = Hour(1))

`(times, observed, modelled)`: each observation time paired with the nearest model record within `tolerance`,
at `depth` (default the shallowest level of each), the model's profile interpolated onto it.
"""
function match_series(observation, model; depth = nothing, tolerance = Hour(1))
    target = isnothing(depth) ? min(first(observation.depths), first(model.depths)) : Float64(depth)
    observed_column = depth_column(observation.depths, observation.values, target)
    modelled_column = depth_column(model.depths, model.values, target)
    times, observed, modelled = DateTime[], Float64[], Float64[]
    for (index, time) in enumerate(observation.times)
        record = nearest_record(model.times, time, tolerance)
        isnothing(record) && continue
        push!(times, time); push!(observed, observed_column[index]); push!(modelled, modelled_column[record])
    end
    return (times, observed, modelled)
end

"The index of the entry of the sorted `times` nearest `time`, or `nothing` when it is further than `tolerance`."
function nearest_record(times, time, tolerance)
    limit = Millisecond(tolerance)
    nearest = searchsortedfirst(times, time)
    best = nothing
    for candidate in (nearest - 1, nearest)
        checkbounds(Bool, times, candidate) || continue
        gap = abs(Millisecond(times[candidate] - time))
        if gap <= limit && (isnothing(best) || gap < best[2])
            best = (candidate, gap)
        end
    end
    return isnothing(best) ? nothing : best[1]
end

"The column of `values` at `target` depth, interpolated between the bracketing levels, NaN outside them."
function depth_column(depths, values, target)
    length(depths) == 1 && return values[:, 1]
    upper = searchsortedfirst(depths, target)
    upper > length(depths) && return fill(NaN, size(values, 1))
    depths[upper] == target && return values[:, upper]
    upper == 1 && return fill(NaN, size(values, 1))
    lower = upper - 1
    weight = (target - depths[lower]) / (depths[upper] - depths[lower])
    return (1 - weight) .* values[:, lower] .+ weight .* values[:, upper]
end
