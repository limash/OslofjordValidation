# Run report scripts for one report in one Julia session, each in its own module, so plotting compiles once.
#
#   julia --project src/run_scripts.jl <report> map.jl stations.jl ...
# The scripts read their own `ARGS` (analysis.jl's section numbers), so they get none.
ENV["REPORT"] = ARGS[1]
files = ARGS[2:end]
empty!(ARGS)
for file in files
    println("== ", file)
    m = Module()
    Core.eval(m, :(include(path) = Base.include($m, path)))
    @time Base.include(m, joinpath(@__DIR__, file))
end
