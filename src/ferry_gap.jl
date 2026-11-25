# FjordSim's surface minus MS Color Fantasy's FerryBox (4 m) along each crossing, by stretch of the fjord: the mean
# over the crossing's minutes south of 59.2° N (the outer fjord, next to the open boundary), between 59.2 and
# 59.6° N, and north of 59.6° N (Drøbak and inwards). For every day with ferry fields (`bin/vm_run.sh <report>
# ferry <day>`). Writes tables/ferry_gap.csv.
#
#   REPORT=<name> julia --project src/ferry_gap.jl
include("ferry_track.jl")

const STRETCHES = ((-Inf, 59.2), (59.2, 59.6), (59.6, Inf))

grid = bathymetry_grid(joinpath(RUN_SETUP, "bathymetry.nc"))
wet_cells = findall(.!grid.land)
rows = String[]
days = sort([Date(m[1]) for m in match.(r"^ferry_fields_(\d{4}-\d{2}-\d{2})\.jld2$", readdir(REPORT_DATA)) if m !== nothing])
for day in days
    times, fields = ferry_fields(day)
    for crossing in crossings(ferrybox_day(day))
        direction = crossing[end].lat > crossing[1].lat ? "northbound" : "southbound"
        cells = [nearest_wet(grid, wet_cells, r.lon, r.lat) for r in crossing]
        for (lo, hi) in STRETCHES, (var, _, _) in VARIABLES
            gap = filter(isfinite, [point_at(fields[var], times, cells[k], r.time) - getfield(r, Symbol(var))
                                    for (k, r) in enumerate(crossing) if lo <= r.lat < hi])
            push!(rows, @sprintf("%s,%s,%s,%s,%s,%d,%.2f", day, direction, lo, hi, var, length(gap), mean(gap)))
        end
    end
end
writecsv(joinpath(TABLES, "ferry_gap.csv"), "day,direction,lat_from,lat_to,variable,minutes,fjordsim_minus_ferrybox", rows)
foreach(println, rows)
