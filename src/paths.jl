# The project's folders: code in `src/` and `reports/`, inputs in `data/`, everything generated in `output/`.
const PROJECT = dirname(@__DIR__)
const DATA = joinpath(PROJECT, "data", "inputs")   # observations, reference models
const RUNS = joinpath(PROJECT, "data", "runs")     # one folder per run, as pulled from the bucket

# The observation files are named as FjordSim's Observations module writes them, Norwegian letters transliterated.
obs_stem(code) = replace(code, 'Æ' => "AE", 'æ' => "ae", 'Ø' => "O", 'ø' => "o", 'Å' => "A", 'å' => "a", r"[^A-Za-z0-9]+" => "_")
