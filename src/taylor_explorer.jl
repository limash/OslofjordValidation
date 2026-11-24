# The Taylor diagrams of the report (Fig. 4, `ctd.jl`) as an interactive page, `output/<report>/taylor_explorer.html`.
# Sliders pick the vertical resolution (the figure's layers on FjordSim's cell faces, or uniform layers 20 to 1 m
# thick; every layer is one point per model), the number of stations in the window, from one to all, and the
# window's place along the route of `scatter_route.jl`, which ends on the Drammensfjord. A map shows the window's
# stations. As in the figure: the NIVA casts from SPINUP, FjordSim beside NorKyst v3 160 m and beside NorFjords
# 160 m on the samples both have, and with every station in the window the figure itself. The statistics are
# computed on the page from `ctd_pairs.csv`; plotly.js comes from a CDN.
#
#   REPORT=<name> julia --project src/taylor_explorer.jl
include("scatter_route.jl")
include("explorer_page.jl")
using CairoMakie: Makie

const THICKNESSES = [20, 10, 5, 2, 1]   # m, the uniform layers after the figure's
const MIN_STATIONS = 5   # the figure's; a smaller window needs every one of its stations
const MIN_SAMPLES = 10
const REFS = ("norkyst160", "norfjords")
out = joinpath(REPORT, "taylor_explorer.html")

# --- samples, by depth so a layer is one slice ------------------------------------------------------------
rows = [r for r in readcsv(joinpath(REPORT_DATA, "ctd_pairs.csv")) if DateTime(r["time"]) >= SPINUP && !ferrybox(r["station"])]
sort!(rows, by = r -> num(r["depth"]))
station_names = sort(unique(r["station"] for r in rows))
index = Dict(s => i - 1 for (i, s) in enumerate(station_names))
col(k) = [num(r[k]) for r in rows]
samples = (st = [index[r["station"]] for r in rows], d = col("depth"),
           oS = col("obs_S"), fS = col("fjordsim_S"), kS = col("norkyst160_S"), nS = col("norfjords_S"),
           oT = col("obs_T"), fT = col("fjordsim_T"), kT = col("norkyst160_T"), nT = col("norfjords_T"))

# --- layers: the figure's (the run's cell faces nearest these depths, as in ctd.jl), then uniform -------------
cell_faces = -NCDataset(ds -> Float64.(ds["z_faces"][:]), joinpath(RUN_SETUP, "bathymetry.nc"))
edges = [0.0; [cell_faces[argmin(abs.(cell_faces .- d))] for d in (2, 5, 10, 20, 30, 50, 75, 100, 130)]]
metres(z) = @sprintf("%g", round(z, digits = 1))
deepest = floor(Int, maximum(samples.d))
resolutions = [(name = "Fig. 4's $(length(edges) - 1) layers", layers = [(name = "$(metres(edges[l]))–$(metres(edges[l + 1])) m",
                lo = edges[l], hi = edges[l + 1]) for l in 1:length(edges) - 1]);
               [(name = "$t m layers", layers = [(name = "$(k)–$(k + t) m", lo = k, hi = k + t) for k in 0:t:deepest]) for t in THICKNESSES]]

# The route's NIVA stations (IMR's are not in the figure) on to the Drammensfjord, so the widest window is the figure's.
route = [(area = a, station = index[s]) for (a, ss) in [ROUTE; FINAL] for s in ss if haskey(index, s)]
length(unique(r.station for r in route)) == length(station_names) || error("a NIVA station is not on the route")

hexcolour(k) = "#" * Makie.Colors.hex(Makie.to_color(COLORS[k]))
data = (names = station_names, samples = samples, resolutions = resolutions,
        models = [(key = k, label = LABELS[k], colour = hexcolour(k)) for k in ("fjordsim", REFS...)],
        route = route, final = (area = first(FINAL), stations = [index[s] for s in last(FINAL)]),
        stations = [(x = station_position[s][1], y = station_position[s][2]) for s in station_names],
        extent = map_extent(lon, lat), background = map_background(lon, lat, depth), aspect = 1 / cosd(59.4))
note = "NIVA casts from $(Date(SPINUP)); NorFjords ends on 2026-06-30. Run $(CONFIG["run"]). In each panel FjordSim and " *
       "the reference model share each layer's samples and σ_obs. A layer needs $MIN_SAMPLES samples and $MIN_STATIONS " *
       "stations, or every station of a smaller window."

page = """
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Taylor diagram explorer</title>
<script src="$PLOTLY"></script>
<style>
  :root { --ink: #1f2328; --muted: #5b636d; --surface: #ffffff; }
  body { margin: 0; padding: 16px; font-family: system-ui, -apple-system, "Segoe UI", sans-serif; color: var(--ink);
         background: var(--surface); }
  h1 { font-size: 20px; margin: 0 0 4px; }
  .note { color: var(--muted); font-size: 13px; margin: 0 0 12px; max-width: 1200px; }
  .controls { display: grid; grid-template-columns: minmax(160px, 1fr) minmax(160px, 1fr) minmax(280px, 3fr); gap: 12px 32px;
              max-width: 1500px; }
  .control label { display: block; font-size: 13px; color: var(--muted); }
  .control output { display: block; font-weight: 600; font-size: 15px; min-height: 1.3em; }
  .control input { width: 100%; }
  .legend { display: flex; flex-wrap: wrap; gap: 4px 20px; margin: 12px 0 4px; font-size: 14px; }
  .legend span { display: inline-flex; align-items: center; gap: 6px; }
  .legend i { width: 11px; height: 11px; border-radius: 50%; display: inline-block; }
  .layout { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)) minmax(0, 1.1fr); gap: 4px; max-width: 1500px; }
  .panel { aspect-ratio: 1.08; min-width: 0; }
  #map { grid-column: 3; grid-row: 1 / span 2; min-height: 0; }
  #layers { color: var(--muted); font-size: 13px; max-width: 1500px; margin-top: 6px; }
  @media (max-width: 900px) {
    .controls, .layout { grid-template-columns: 1fr; }
    #map { grid-column: 1; grid-row: auto; height: 640px; }
  }
</style>
</head>
<body>
<h1>Taylor diagrams by depth layer</h1>
<p class="note">$note</p>
<div class="controls">
  <div class="control">
    <label for="res">Vertical resolution</label>
    <output id="res-out"></output>
    <input id="res" type="range" min="0" max="$(length(resolutions) - 1)" step="1" value="0">
  </div>
  <div class="control">
    <label for="width">Stations in the window</label>
    <output id="width-out"></output>
    <input id="width" type="range" min="1" max="$(length(route))" step="1" value="$(length(route))">
  </div>
  <div class="control">
    <label for="stop">Region: the window's place along the route, Inner Oslofjord to Drammensfjord</label>
    <output id="stop-out"></output>
    <input id="stop" type="range" min="0" step="1" value="0">
  </div>
</div>
<div class="legend">$(join(["<span><i style=\"background:$(m.colour)\"></i>$(m.label)</span>" for m in data.models]))
  <span>★ observations</span></div>
<p class="note">Angle: correlation; radius: σ_model / σ_obs; dashed arcs: centred RMSE / σ_obs of 0.25 to 1.</p>
<div class="layout">
  <div class="panel" id="p-S-norkyst160"></div><div class="panel" id="p-S-norfjords"></div><div id="map"></div>
  <div class="panel" id="p-T-norkyst160"></div><div class="panel" id="p-T-norfjords"></div>
</div>
<p id="layers"></p>
<script>
const DATA = $(json(data));
const RMAX = 2, MIN_STATIONS = $MIN_STATIONS, MIN_SAMPLES = $MIN_SAMPLES;
const PICKED = "#CC79A7";   // the window's stations on the map, apart from the models' colours
const LABELLED = 12;        // the most stations named on the map
const LETTER = {fjordsim: "f", norkyst160: "k", norfjords: "n"};
const MODEL = Object.fromEntries(DATA.models.map(m => [m.key, m]));
const VARS = {S: "Salinity", T: "Temperature"};
const CORR = [1, 0.99, 0.95, 0.9, 0.8, 0.6, 0.4, 0.2, 0];
const MILESTONES = [0, 10, 20, 50, 100];   // the layers labelled at fine resolution
const FONT = {family: "system-ui, -apple-system, 'Segoe UI', sans-serif", size: 12, color: "#1f2328"};
const deg = x => x * 180 / Math.PI;
const el = id => document.getElementById(id);
const D = DATA.samples;

/** The first sample at or below depth `z` (the samples are sorted by depth). */
function lowerBound(z) {
  let a = 0, b = D.d.length;
  while (a < b) { const m = (a + b) >> 1; if (D.d[m] < z) a = m + 1; else b = m; }
  return a;
}

/** The windows of `width` stations along the route, then the Drammensfjord alone (unless the last window is it). */
function stopsOf(width) {
  const R = DATA.route, out = [];
  for (let k = 0; k + width <= R.length; k++) {
    const w = R.slice(k, k + width);
    out.push({label: width === R.length ? "All NIVA stations, as Fig. 4" : [...new Set(w.map(r => r.area))].join(" → "),
              stations: [...new Set(w.map(r => r.station))]});
  }
  if (width !== DATA.final.stations.length) out.push({label: DATA.final.area, stations: DATA.final.stations});
  return out;
}

// Start from the sliders as they are: a browser may restore them on reload.
let stops = stopsOf(+el("width").value);
const inWindow = new Uint8Array(DATA.names.length);

/** A new width keeps the window's first station; the Drammensfjord stays the Drammensfjord. */
function setWidth() {
  const k = +el("stop").value, wasFinal = k === stops.length - 1;
  stops = stopsOf(+el("width").value);
  el("stop").max = stops.length - 1;
  el("stop").value = wasFinal ? stops.length - 1 : Math.min(k, stops.length - 2);
}

/** FjordSim and reference `ref` on the samples of the window's stations in the layer that both have: n, stations and
 *  the statistics of each, or null for a layer with too few samples or stations. */
function stats(layer, v, ref, need) {
  const o = [], f = [], r = [], st = new Set();
  for (let i = lowerBound(layer.lo), end = lowerBound(layer.hi); i < end; i++) {
    const a = D["o" + v][i], b = D["f" + v][i], c = D[LETTER[ref] + v][i];
    if (!inWindow[D.st[i]] || a === null || b === null || c === null) continue;
    o.push(a); f.push(b); r.push(c); st.add(D.st[i]);
  }
  if (st.size < need || o.length < MIN_SAMPLES) return null;
  const n = o.length, mean = x => x.reduce((p, q) => p + q, 0) / n;
  const mo = mean(o), so = Math.sqrt(o.reduce((p, x) => p + (x - mo) ** 2, 0) / n);
  const one = m => {
    const mm = mean(m), sm = Math.sqrt(m.reduce((p, x) => p + (x - mm) ** 2, 0) / n);
    const cov = o.reduce((p, x, i) => p + (x - mo) * (m[i] - mm), 0) / n;
    const mse = o.reduce((p, x, i) => p + (m[i] - x) ** 2, 0) / n, bias = mm - mo;
    return {sd: sm / so, r: cov / (so * sm), crmse: Math.sqrt(Math.max(0, mse - bias * bias)) / so, bias: bias / so};
  };
  return {n, stations: st.size, fjordsim: one(f), [ref]: one(r)};
}

/** The fixed parts of a Taylor diagram: centred-RMSE arcs around the star, the σ_model = σ_obs arc, the star. */
function guides() {
  const out = [];
  for (const e of [0.25, 0.5, 0.75, 1]) {
    const rr = [], th = [];
    for (let k = 0; k <= 200; k++) {
      const p = Math.PI * k / 200, x = 1 + e * Math.cos(p), y = e * Math.sin(p);
      rr.push(Math.hypot(x, y)); th.push(deg(Math.atan2(y, x)));
    }
    out.push({type: "scatterpolar", mode: "lines", r: rr, theta: th, hoverinfo: "skip", showlegend: false,
              line: {color: "#b0b7bf", width: 1, dash: "dash"}});
  }
  const q = Array.from({length: 91}, (_, k) => k);
  out.push({type: "scatterpolar", mode: "lines", r: q.map(() => 1), theta: q, hoverinfo: "skip", showlegend: false,
            line: {color: "#6e7781", width: 1}});
  out.push({type: "scatterpolar", mode: "markers", r: [1], theta: [0], hoverinfo: "skip", showlegend: false, cliponaxis: false,
            marker: {symbol: "star", size: 16, color: "#1f2328"}});
  return out;
}

function draw() {
  const res = DATA.resolutions[+el("res").value], few = res.layers.length <= 12;
  const stop = stops[+el("stop").value], need = Math.min(MIN_STATIONS, stop.stations.length);
  el("res-out").textContent = res.name;
  const width = +el("width").value;
  el("width-out").textContent = width === DATA.route.length ? `all \${width}` : width;
  el("stop-out").textContent = stop.label + (stop.stations.length > LABELLED ? ` (\${stop.stations.length} stations)`
    : ": " + stop.stations.map(i => DATA.names[i]).join(", "));
  inWindow.fill(0); stop.stations.forEach(i => inWindow[i] = 1);
  for (const v of ["S", "T"]) for (const ref of ["norkyst160", "norfjords"]) {
    const rows = res.layers.map((l, i) => ({l, i, s: stats(l, v, ref, need)})).filter(x => x.s);
    const traces = guides();
    for (const key of [ref, "fjordsim"]) {   // FjordSim on top
      const m = MODEL[key];
      const pts = rows.map(({l, i, s}) => {
        const x = s[key], th = deg(Math.acos(Math.max(-1, Math.min(1, x.r)))), out = th > 90 || x.sd > RMAX;
        const label = few ? String(i + 1) : (MILESTONES.includes(l.lo) ? l.lo + " m" : "");
        return {th: Math.min(th, 90), rho: Math.min(x.sd, RMAX), out, label,
          hover: `<b>\${m.label}</b><br>\${few ? "layer " + (i + 1) + ": " : ""}\${l.name}<br>\${s.stations} stations, \${s.n} samples<br>` +
                 `r \${x.r.toFixed(3)}, σ_model/σ_obs \${x.sd.toFixed(2)}<br>centred RMSE/σ_obs \${x.crmse.toFixed(2)}, ` +
                 `bias/σ_obs \${x.bias.toFixed(2)}` + (out ? "<br>beyond the axis: drawn at its edge" : "")};
      });
      traces.push({type: "scatterpolar", mode: "lines+markers+text", cliponaxis: false,
        r: pts.map(p => p.rho), theta: pts.map(p => p.th), text: pts.map(p => p.label),
        textposition: few ? "middle center" : "top right",
        textfont: few ? {color: "#ffffff", size: 11} : {color: "#1f2328", size: 11},
        hovertext: pts.map(p => p.hover), hoverinfo: "text", showlegend: false,
        line: {color: m.colour, width: few ? 2 : 1.5},
        marker: {color: m.colour, size: few ? 19 : 7, line: {color: "#1f2328", width: few ? 0.6 : 0.3}}});
      const ringed = pts.filter(p => p.out);
      if (ringed.length) traces.push({type: "scatterpolar", mode: "markers", hoverinfo: "skip", showlegend: false, cliponaxis: false,
        r: ringed.map(p => p.rho), theta: ringed.map(p => p.th),
        marker: {symbol: "circle-open", size: few ? 28 : 14, color: m.colour, line: {width: 2.5}}});
    }
    Plotly.react(`p-\${v}-\${ref}`, traces, {
      title: {text: `<b>\${VARS[v]}</b>: FjordSim and \${MODEL[ref].label}`, font: {size: 14}}, font: FONT,
      margin: {l: 40, r: 40, t: 50, b: 30}, paper_bgcolor: "#fff", showlegend: false,
      polar: {sector: [0, 90], bgcolor: "#fff",
        radialaxis: {range: [0, RMAX], tickvals: [0, 0.5, 1, 1.5, 2], angle: 0, tickangle: 0, gridcolor: "#eaeef2",
                     linecolor: "#8c959f"},
        angularaxis: {rotation: 0, direction: "counterclockwise", tickvals: CORR.map(c => deg(Math.acos(c))),
                      ticktext: CORR.map(String), gridcolor: "#eaeef2", linecolor: "#8c959f"}},
      annotations: [{text: "correlation", showarrow: false, xref: "paper", yref: "paper", x: 0.82, y: 0.86,
                     textangle: 45, font: {size: 12, color: "#5b636d"}}],
    }, {responsive: true, displayModeBar: false});
  }
  drawMap(stop);
  const L = res.layers;
  el("layers").textContent = few
    ? "Layers from the surface: " + L.map((l, i) => `\${i + 1}: \${l.name}`).join(", ") + ". "
      + "A ringed point lies beyond the axis and is drawn at its edge."
    : `Layers of \${L[0].hi - L[0].lo} m from the surface; labels mark the layers from `
      + MILESTONES.map(z => z + " m").join(", ") + ". Hover a point for its layer and statistics. "
      + "A ringed point lies beyond the axis and is drawn at its edge.";
}
/** The map: every NIVA station grey, the window's in colour and named when there are few. */
function drawMap(stop) {
  const S = DATA.stations, on = new Set(stop.stations), AXIS = {zeroline: false, linecolor: "#8c959f", mirror: true,
    ticks: "outside", showgrid: false};
  const rest = DATA.names.map((_, i) => i).filter(i => !on.has(i)), w = stop.stations;
  // A label goes left of its station when another station of the window lies just to its right.
  const left = i => w.some(o => S[o].x - S[i].x > 0 && S[o].x - S[i].x < 0.25 && Math.abs(S[o].y - S[i].y) < 0.02);
  const named = w.length <= LABELLED;
  const E = DATA.extent;
  Plotly.react("map", [
    {type: "scatter", mode: "markers", name: "NIVA casts", hoverinfo: "text", x: rest.map(i => S[i].x), y: rest.map(i => S[i].y),
     text: rest.map(i => DATA.names[i]), marker: {size: 7, color: "#9aa1a9", line: {color: "#57606a", width: 0.5}}},
    {type: "scatter", mode: named ? "markers+text" : "markers", name: "in the window", hoverinfo: "text",
     x: w.map(i => S[i].x), y: w.map(i => S[i].y), text: w.map(i => DATA.names[i]),
     textposition: w.map(i => left(i) ? "middle left" : "middle right"), textfont: {size: 13, color: "#1f2328"},
     marker: {size: named ? 13 : 10, color: PICKED, line: {color: "#1f2328", width: 1}}},
  ], {
    title: {text: "<b>Stations in the diagrams</b>", font: {size: 13}}, font: FONT,
    margin: {l: 48, r: 8, t: 40, b: 40}, paper_bgcolor: "#fff", plot_bgcolor: "#f7f6f2",
    legend: {x: 0.01, y: 0.99, bgcolor: "rgba(255,255,255,0.85)", bordercolor: "#d0d7de", borderwidth: 1},
    xaxis: {...AXIS, range: [E.x0, E.x1], constrain: "domain", title: {text: "Longitude (°E)", standoff: 4}},
    yaxis: {...AXIS, range: [E.y0, E.y1], scaleanchor: "x", scaleratio: DATA.aspect, constrain: "domain",
            title: {text: "Latitude (°N)", standoff: 8}, automargin: true},
    images: [{source: DATA.background, xref: "x", yref: "y", x: E.x0, y: E.y1, sizex: E.x1 - E.x0, sizey: E.y1 - E.y0,
              sizing: "stretch", layer: "below"}],
  }, {responsive: true, displayModeBar: false});
}

el("res").addEventListener("input", draw);
el("width").addEventListener("input", () => { setWidth(); draw(); });
el("stop").addEventListener("input", draw);
el("stop").max = stops.length - 1;
el("stop").value = Math.min(+el("stop").value, stops.length - 1);
draw();
</script>
</body>
</html>
"""
write(out, page)
println(out, "  ", round(filesize(out) / 1e6, digits = 1), " MB")
