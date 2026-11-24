# Observed against modelled S and T as an interactive page, `output/<report>/scatter_explorer.html`. Sliders pick
# the vertical resolution (the report's four layers, or uniform layers 20 to 1 m thick), the depth layer, the
# number of stations in the window, and the window's place along the route of `scatter_route.jl` (the video's),
# which ends on the Drammensfjord (D-3, D-2). A map shows the window's stations. The page is one file: data and
# map are inside it, plotly.js comes from a CDN.
#
#   REPORT=<name> julia --project src/scatter_explorer.jl
include("scatter_route.jl")
include("explorer_page.jl")

out = joinpath(REPORT, "scatter_explorer.html")
const THICKNESSES = [20, 10, 5, 2, 1]   # m, the uniform layers after the report's four
# Okabe–Ito without its pale yellow: the most stations a window can hold with a colour each.
const COLOURS = [PALETTE_HEX; "#56B4E9"; "#1F2328"]

# --- data --------------------------------------------------------------------------------------------
route = [(area, s) for (area, ss) in ROUTE for s in ss]
station_names = sort(unique([last.(route); last(FINAL)]))
index = Dict(s => i - 1 for (i, s) in enumerate(station_names))   # 0-based for the page
grid_code(g) = g == "160 m" ? 1 : g == "800 m" ? 2 : 0
samples = map(station_names) do s
    ps = sort(filter(p -> p["station"] == s, pairs), by = p -> (p["time"], p["depth"]))
    col(k) = [p[k] for p in ps]
    (d = col("depth"), t = [Dates.format(p["time"], "yyyy-mm-dd") for p in ps],
     oS = col("obs_S"), fS = col("fjordsim_S"), kS = col("norkyst_S"), nS = col("norfjords_S"), gS = grid_code.(col("grid_S")),
     oT = col("obs_T"), fT = col("fjordsim_T"), kT = col("norkyst_T"), nT = col("norfjords_T"), gT = grid_code.(col("grid_T")))
end
everyone = sort(unique(p["station"] for p in pairs))
stations = [(n = s, x = station_position[s][1], y = station_position[s][2], imr = s in imr_names)
            for s in everyone]
# Each resolution's layers, surface first; a uniform layer without samples is left out.
deepest = maximum(p["depth"] for p in pairs)
uniform(t) = [(name = "$(k)–$(k + t) m", lo = k, hi = k + t) for k in 0:t:floor(Int, deepest) if any(p -> k <= p["depth"] < k + t, pairs)]
resolutions = [(name = "the report's $(length(LAYERS)) layers", layers = [(name = n, lo = lo, hi = hi) for (n, lo, hi) in reverse(LAYERS)]);
               [(name = "$t m layers", layers = uniform(t)) for t in THICKNESSES]]
extent = map_extent(lon, lat)

data = (names = station_names, stations = stations, resolutions = resolutions, samples = samples, extent = extent,
        route = [(area = a, station = index[s]) for (a, s) in route],
        final = (area = first(FINAL), stations = [index[s] for s in last(FINAL)]), colours = COLOURS,
        background = map_background(lon, lat, depth), aspect = 1 / cosd(59.4))
note = NORKYST_NOTE * " NIVA and IMR casts from $(Date(SPINUP)); NorFjords ends on 2026-06-30. Run $(CONFIG["run"])."

page = """
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Oslofjord scatter explorer</title>
<script src="$PLOTLY"></script>
<style>
  :root { --ink: #1f2328; --muted: #5b636d; --line: #d0d7de; --surface: #ffffff; }
  body { margin: 0; padding: 16px; font-family: system-ui, -apple-system, "Segoe UI", sans-serif; color: var(--ink);
         background: var(--surface); }
  h1 { font-size: 20px; margin: 0 0 4px; }
  .note { color: var(--muted); font-size: 13px; margin: 0 0 12px; }
  .controls { display: grid; grid-template-columns: minmax(180px, 1fr) minmax(280px, 3fr); gap: 12px 32px; max-width: 1500px; }
  .control label { display: block; font-size: 13px; color: var(--muted); }
  .control output { display: block; font-weight: 600; font-size: 15px; min-height: 1.3em; }
  .control input { width: 100%; }
  .ticks { display: flex; justify-content: space-between; font-size: 12px; color: var(--muted); }
  .legend { display: flex; flex-wrap: wrap; gap: 4px 16px; margin: 10px 0 4px; font-size: 14px; }
  .legend span { display: inline-flex; align-items: center; gap: 6px; }
  .legend i { width: 11px; height: 11px; border-radius: 50%; display: inline-block; }
  .legend .none { color: var(--muted); }
  .layout { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)) minmax(0, 1.1fr); gap: 4px; max-width: 1500px; }
  .panel { aspect-ratio: 1; min-width: 0; }
  #map { grid-column: 4; grid-row: 1 / span 2; min-height: 0; }
  @media (max-width: 900px) {
    .controls, .layout { grid-template-columns: 1fr; }
    #map { grid-column: 1; grid-row: auto; height: 640px; }
  }
</style>
</head>
<body>
<h1>Observed against modelled salinity and temperature, by depth and region</h1>
<p class="note">$note</p>
<div class="controls">
  <div class="control">
    <label for="res">Vertical resolution</label>
    <output id="res-out"></output>
    <input id="res" type="range" min="0" max="$(length(resolutions) - 1)" step="1" value="$(length(resolutions) - 1)">
  </div>
  <div class="control">
    <label for="layer">Depth layer</label>
    <output id="layer-out"></output>
    <input id="layer" type="range" min="0" step="1" value="0">
    <div class="ticks"><span id="layer-first"></span><span id="layer-last"></span></div>
  </div>
  <div class="control">
    <label for="width">Stations in the window</label>
    <output id="width-out"></output>
    <input id="width" type="range" min="1" max="$(length(COLOURS))" step="1" value="$WINDOW">
  </div>
  <div class="control">
    <label for="stop">Region: the window's place along the route, Inner Oslofjord to Drammensfjord</label>
    <output id="stop-out"></output>
    <input id="stop" type="range" min="0" step="1" value="0">
  </div>
</div>
<div class="legend" id="legend"></div>
<div class="layout">
  <div class="panel" id="p-S-f"></div><div class="panel" id="p-S-k"></div><div class="panel" id="p-S-n"></div>
  <div id="map"></div>
  <div class="panel" id="p-T-f"></div><div class="panel" id="p-T-k"></div><div class="panel" id="p-T-n"></div>
</div>
<script>
const DATA = $(json(data));
const MODELS = [["f", "FjordSim"], ["k", "NorKyst v3"], ["n", "NorFjords 160 m"]];
const VARS = [["S", "salinity (g/kg)"], ["T", "temperature (°C)"]];
const GRID = {1: "160 m", 2: "800 m"};
const CONFIG = {responsive: true, displayModeBar: false};
const FONT = {family: "system-ui, -apple-system, 'Segoe UI', sans-serif", size: 12, color: "#1f2328"};
const AXIS = {gridcolor: "#eaeef2", zeroline: false, linecolor: "#8c959f", mirror: true, ticks: "outside"};

/** Indices of one station's samples in the layer where the observation and the model both have a value. */
function rows(st, layer, v, m) {
  const s = DATA.samples[st], out = [];
  for (let i = 0; i < s.d.length; i++)
    if (s.d[i] >= layer.lo && s.d[i] < layer.hi && s["o" + v][i] !== null && s[m + v][i] !== null) out.push(i);
  return out;
}

const el = id => document.getElementById(id);

/** The windows of `width` stations along the route, then the Drammensfjord. A station's colour is fixed by its
 *  place on the route, so it keeps it while the window slides. */
function stopsOf(width) {
  const R = DATA.route, out = [];
  for (let k = 0; k + width <= R.length; k++) {
    const w = R.slice(k, k + width);
    out.push({label: [...new Set(w.map(r => r.area))].join(" → "), stations: w.map(r => r.station),
              colours: w.map((_, j) => DATA.colours[(k + j) % width])});
  }
  out.push({label: DATA.final.area, stations: DATA.final.stations, colours: DATA.final.stations.map((_, j) => DATA.colours[j])});
  return out;
}

/** Square axis limits of one layer and variable: 0.2–99.8 % of every value in it, padded. */
const LIMITS = {};
function limits(layer, v) {
  const key = `\${layer.lo}-\${layer.hi}-\${v}`;
  if (LIMITS[key]) return LIMITS[key];
  const xs = [];
  for (const s of DATA.samples) for (let i = 0; i < s.d.length; i++)
    if (s.d[i] >= layer.lo && s.d[i] < layer.hi) for (const m of "ofkn") { const x = s[m + v][i]; if (x !== null) xs.push(x); }
  xs.sort((p, q) => p - q);
  const q = f => xs[Math.min(xs.length - 1, Math.floor(f * (xs.length - 1)))];
  const a = q(0.002), b = q(0.998), pad = 0.05 * (b - a || 1);
  return (LIMITS[key] = [a - pad, b + pad]);
}

// Start from the sliders as they are: a browser may restore them on reload.
let stops = stopsOf(+el("width").value), layers = DATA.resolutions[+el("res").value].layers;

/** A new resolution keeps the depth: the layer holding the middle of the one shown. */
function setResolution() {
  const old = layers[+el("layer").value], mid = (old.lo + Math.min(old.hi, old.lo + 50)) / 2;
  layers = DATA.resolutions[+el("res").value].layers;
  let k = layers.findIndex(l => l.lo <= mid && mid < l.hi);
  if (k < 0) k = mid < layers[0].lo ? 0 : layers.length - 1;
  el("layer").max = layers.length - 1; el("layer").value = k;
}
/** A new width keeps the window's first station; the Drammensfjord stays the Drammensfjord. */
function setWidth() {
  const k = +el("stop").value, wasFinal = k === stops.length - 1;
  stops = stopsOf(+el("width").value);
  el("stop").max = stops.length - 1;
  el("stop").value = wasFinal ? stops.length - 1 : Math.min(k, stops.length - 2);
}

function draw() {
  const layer = layers[+el("layer").value];
  const stop = stops[+el("stop").value];
  el("res-out").textContent = DATA.resolutions[+el("res").value].name;
  el("layer-out").textContent = layer.name;
  el("layer-first").textContent = layers[0].name; el("layer-last").textContent = layers[layers.length - 1].name;
  el("width-out").textContent = el("width").value;
  el("stop-out").textContent = stop.label + ": " + stop.stations.map(i => DATA.names[i]).join(", ");

  // Samples per station in this layer (salinity, observed): the legend and the hollow map markers.
  const count = stop.stations.map(st => DATA.samples[st].d.filter(d => d >= layer.lo && d < layer.hi).length);
  document.getElementById("legend").innerHTML = stop.stations.map((st, j) =>
    `<span class="\${count[j] ? "" : "none"}"><i style="background:\${stop.colours[j]}"></i>\${DATA.names[st]}` +
    ` · \${count[j] ? count[j] + " samples" : "no samples in this layer"}</span>`).join("");

  for (const [v, vname] of VARS) for (const [m, mname] of MODELS) {
    const [a, b] = limits(layer, v);
    let n = 0; const grids = new Set();
    const traces = stop.stations.map((st, j) => {
      const s = DATA.samples[st], r = rows(st, layer, v, m);
      n += r.length;
      if (m === "k") r.forEach(i => s["g" + v][i] && grids.add(GRID[s["g" + v][i]]));
      return {type: "scattergl", mode: "markers", name: DATA.names[st],
        x: r.map(i => s["o" + v][i]), y: r.map(i => s[m + v][i]),
        customdata: r.map(i => [s.t[i], s.d[i]]),
        marker: {color: stop.colours[j], size: 5, opacity: 0.6},
        hovertemplate: `<b>\${DATA.names[st]}</b><br>%{customdata[0]}, %{customdata[1]} m<br>` +
          "observed %{x:.2f}<br>modelled %{y:.2f}<extra></extra>"};
    });
    const name = m === "k" ? mname + (grids.size ? " " + [...grids].sort().join(" + ") : "") : mname;
    Plotly.react(`p-\${v}-\${m}`, traces, {
      title: {text: `<b>\${name}</b>, \${vname}<br><span style="font-size:11px;color:#5b636d">\${n} samples</span>`, font: {size: 13}},
      font: FONT, showlegend: false, margin: {l: 44, r: 8, t: 46, b: 40}, paper_bgcolor: "#fff", plot_bgcolor: "#fff",
      xaxis: {...AXIS, range: [a, b], constrain: "domain", title: {text: "observed", standoff: 4}},
      yaxis: {...AXIS, range: [a, b], scaleanchor: "x", constrain: "domain", title: {text: m === "f" ? "modelled" : "", standoff: 4}},
      shapes: [{type: "line", x0: a, y0: a, x1: b, y1: b, line: {color: "#1f2328", width: 1}}],
    }, CONFIG);
  }

  // The map: every station grey, the window's in its colour, hollow where the layer has no samples.
  const S = DATA.stations, on = new Set(stop.stations.map(i => DATA.names[i]));
  const grey = imr => ({type: "scatter", mode: "markers", name: imr ? "IMR casts" : "NIVA casts", hoverinfo: "text",
    x: S.filter(s => s.imr === imr && !on.has(s.n)).map(s => s.x), y: S.filter(s => s.imr === imr && !on.has(s.n)).map(s => s.y),
    text: S.filter(s => s.imr === imr && !on.has(s.n)).map(s => s.n),
    marker: {symbol: imr ? "diamond" : "circle", size: 7, color: "#9aa1a9", line: {color: "#57606a", width: 0.5}}});
  const pos = Object.fromEntries(S.map(s => [s.n, s]));
  const picked = stop.stations.map((st, j) => {
    const s = pos[DATA.names[st]];
    // A label goes left of its station when another station of the window lies just to its right.
    const left = stop.stations.some(o => { const p = pos[DATA.names[o]]; return p.x - s.x > 0 && p.x - s.x < 0.25 && Math.abs(p.y - s.y) < 0.02; });
    return {type: "scatter", mode: "markers+text", showlegend: false, hoverinfo: "text", x: [s.x], y: [s.y], text: [s.n],
      textposition: left ? "middle left" : "middle right", textfont: {size: 13, color: "#1f2328"},
      marker: {symbol: s.imr ? "diamond" : "circle", size: 14, color: count[j] ? stop.colours[j] : "#ffffff",
               line: {color: count[j] ? "#1f2328" : stop.colours[j], width: count[j] ? 1 : 2.5}}};
  });
  const E = DATA.extent;
  Plotly.react("map", [grey(false), grey(true), ...picked], {
    title: {text: "<b>Stations in the panels</b>", font: {size: 13}}, font: FONT,
    margin: {l: 48, r: 8, t: 40, b: 40}, paper_bgcolor: "#fff", plot_bgcolor: "#f7f6f2",
    legend: {x: 0.01, y: 0.99, bgcolor: "rgba(255,255,255,0.85)", bordercolor: "#d0d7de", borderwidth: 1},
    xaxis: {...AXIS, range: [E.x0, E.x1], constrain: "domain", title: {text: "Longitude (°E)", standoff: 4}, showgrid: false},
    yaxis: {...AXIS, range: [E.y0, E.y1], scaleanchor: "x", scaleratio: DATA.aspect, constrain: "domain", title: {text: "Latitude (°N)", standoff: 4},
            showgrid: false},
    images: [{source: DATA.background, xref: "x", yref: "y", x: E.x0, y: E.y1, sizex: E.x1 - E.x0, sizey: E.y1 - E.y0,
              sizing: "stretch", layer: "below"}],
  }, CONFIG);
}
el("res").addEventListener("input", () => { setResolution(); draw(); });
el("width").addEventListener("input", () => { setWidth(); draw(); });
el("layer").addEventListener("input", draw);
el("stop").addEventListener("input", draw);
el("layer").max = layers.length - 1; el("stop").max = stops.length - 1;
el("layer").value = Math.min(+el("layer").value, layers.length - 1);
draw();
</script>
</body>
</html>
"""
write(out, page)
println(out, "  ", round(filesize(out) / 1e6, digits = 1), " MB")
