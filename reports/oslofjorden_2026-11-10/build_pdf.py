"""Assemble the full-period validation report of the oslofjorden run 20261107T210205 (2024-10-01 to 2026-10-01)
from the figures and CSV tables in output/oslofjorden_2026-11-10/.

    bin/build_pdf.sh oslofjorden_2026-11-10
"""
import math
from pathlib import Path

from pdf_helpers import *  # noqa: F401,F403  (styles, para, bullets, figure, table, read, HERE, FIG, OUT)

# Noto Sans has no glyph for these, and silently drops them: a minus sign would vanish from every bias.
GLYPHS = {"−": "-", "→": "to", "≈": "~", "↔": "-"}


def plain(text):
    text = str(text)
    for a, b in GLYPHS.items():
        text = text.replace(a, b)
    return text


_para, _table, _bullets, _figure = para, table, bullets, figure
para = lambda text, style=body: _para(plain(text), style)  # noqa: E731
bullets = lambda items: _bullets([plain(i) for i in items])  # noqa: E731
table = lambda rows, widths=None, header_rows=1: _table([[plain(c) for c in r] for r in rows], widths, header_rows)  # noqa: E731
figure = lambda path, text, **kw: _figure(path, plain(text), **kw)  # noqa: E731

FOOTER = "FjordSim · oslofjorden · run 20261107T210205 · full period, 2024-10-01 to 2026-10-01"


def on_page(canvas, doc):
    canvas.saveState()
    canvas.setFont("DejaVu", 7.5)
    canvas.setFillColor(colors.grey)
    canvas.drawString(1.8 * cm, 1.1 * cm, FOOTER)
    canvas.drawRightString(A4[0] - 1.8 * cm, 1.1 * cm, f"{doc.page}")
    canvas.restoreState()


def pair(r, k):
    return f'{float(r[k + "_bias"]):+.2f} / {float(r[k + "_rmse"]):.2f}'


def stat(errors):
    if not errors:
        return ""
    return f"{sum(errors) / len(errors):+.2f} / {math.sqrt(sum(e * e for e in errors) / len(errors)):.2f}"


# The CTD pairs by run year, region and depth band, and by month. Project 6302 is the Inner Oslofjord programme.
STATIONS = HERE.parent.parent / "data" / "inputs" / "observations" / "niva_ctd_odm2_2024-2026" / "stations.csv"
INNER = {l.split(",")[0] for l in STATIONS.read_text().splitlines()[1:] if l.split(",")[-1] == "6302"}
region = lambda s: "Drammensfjord" if s in ("D-2", "D-3") else ("Inner Oslofjord" if s in INNER else "Outer fjord")  # noqa: E731
BANDS = (("0-5 m", 0, 5), ("5-20 m", 5, 20), ("20-50 m", 20, 50), (">50 m", 50, 1e9))
by_year, monthly = {}, {}
for r in read("ctd_pairs.csv"):
    t = r["time"]
    o, f, n, nf = ({v: float(r[k + "_" + v]) for v in "ST"} for k in ("obs", "fjordsim", "norkyst", "norfjords"))
    band = next(name for name, lo, hi in BANDS if lo <= float(r["depth"]) < hi)
    m = monthly.setdefault(t[:7], {})
    m.setdefault("casts", set()).add((r["station"], t))
    year = None if t < "2024-11" else ("Year 1" if t < "2025-10" else "Year 2")
    for v in "ST":
        if math.isnan(o[v]) or math.isnan(f[v]):
            continue
        m.setdefault((v, band), []).append(f[v] - o[v])
        if year is None:
            continue
        for g in ("ALL", region(r["station"])):
            for b in ("all", band):
                by_year.setdefault((g, v, b, year, "every"), []).append(f[v] - o[v])
                if not math.isnan(n[v]):
                    by_year.setdefault((g, v, b, year, "fjordsim"), []).append(f[v] - o[v])
                    by_year.setdefault((g, v, b, year, "norkyst"), []).append(n[v] - o[v])
                if not math.isnan(nf[v]):
                    by_year.setdefault((g, v, b, year, "nf_fjordsim"), []).append(f[v] - o[v])
                    by_year.setdefault((g, v, b, year, "norfjords"), []).append(nf[v] - o[v])

story = []
S = story.append

# --------------------------------------------------------------------------------------------------
S(para("Oslofjord 2024–2026 run: validation of the full period", title))
S(para("FjordSim setup <i>examples/oslofjorden/oslofjorden.jl</i> · GPU run <i>oslofjorden-run_simulation-20261107-220117</i>, "
       "stamp 20261107T210205, 2024-10-01 to 2026-10-01, finished and archived as <i>oslofjorden_2026-11-10</i> · this report "
       "covers the whole run · scored against NIVA CTD casts (ODM2), IMR's ØkoKyst and Tisler casts (Vannmiljø) and the "
       "Kartverket tide gauges, with the operational NorKyst v3 and IMR's NorFjords 160 m hindcast (to June 2026) as "
       "reference models · report generated 2026-11-12, NorFjords added 2026-11-16", small))
S(Spacer(1, 6))
S(para("Summary", h1))
S(para("This report scores the whole two-year run in one pass: 898 NIVA casts at 36 stations from November 2024 to "
       "18 September 2026 (65 273 samples), 115 IMR casts at seven outer-fjord stations (October 2024 to March 2026), "
       "and 23 months of water level. October 2024, the adjustment from the initial state, is shown but not scored, as in "
       "the first-year report. The run's two years are compared side by side: year 1 is November 2024 – September "
       "2025, year 2 October 2025 – September 2026. IMR's NorFjords hindcast is the second reference model, as in the "
       "first-year report. Its daily means end on 30 June 2026, so it is scored beside FjordSim on the samples both "
       "reach, November 2024 – June 2026 (47 348 samples), and the FjordSim–NorKyst scores keep the whole window."))
S(para("Main findings", h2))
for item in bullets([
    "<b>Over the two years FjordSim beats NorKyst in salinity and trails it in temperature.</b> On the 28 363 samples "
    "both models reach, salinity +1.11 / 2.24 g/kg (bias / RMSE) against NorKyst's +1.30 / 2.53, temperature "
    "−0.48 / 1.58 °C against −0.58 / 1.32. On every sample FjordSim scores +0.47 / 1.61 g/kg and −0.72 / 1.60 °C. "
    "FjordSim is better in salinity on both NorKyst grids (160 m nest: RMSE 2.04 against 2.23; 800 m run: 3.47 "
    "against 4.32 g/kg).",
    "<b>Against NorFjords FjordSim is better in salinity and about even in temperature.</b> On the 47 348 samples "
    "both reach to June 2026, salinity +0.61 / 1.76 g/kg against NorFjords' +1.04 / 2.12, temperature −0.68 / 1.53 °C "
    "against −0.42 / 1.49. Below 50 m NorFjords is the warmer and better in temperature (−0.22 / 1.38 against "
    "−0.90 / 1.48 °C) but 0.50 g/kg too salty where FjordSim is unbiased (−0.05).",
    "<b>The second year is worse than the first, in both models.</b> FjordSim's salinity RMSE goes from 1.52 to "
    "1.71 g/kg and its temperature RMSE from 1.32 to 1.84 °C; NorKyst's, on the joint samples, from 2.49 to 2.57 g/kg "
    "and 1.21 to 1.42 °C. Most of FjordSim's temperature loss is below 50 m (RMSE 1.20 to 1.90 °C) and in the "
    "top 5 m (1.45 to 2.07 °C).",
    "<b>The start state washes out of the inner basins and leaves an error the other way.</b> Below 50 m in the "
    "Inner Oslofjord salinity goes from +0.20 g/kg in year 1 to −0.53 in year 2. Bunnefjorden at 120 m is never "
    "renewed in the model: it freshens steadily from 34.0 to 32.5 g/kg while the casts stay at 32.6–33.0, and it "
    "stays at 6.1–6.8 °C against 7.7–9.1 in the casts. NorFjords renews it and overshoots: 33.4–34.8 g/kg from "
    "June 2025 on. The Drammensfjord basin halves its excess (below 50 m "
    "+1.52 to +0.67 g/kg); D-2 at 100 m reaches 32.1 g/kg in September 2026 against 31.6 observed.",
    "<b>The renewals of the inner basins are missed or late.</b> The casts show warm, salty inflows to Vestfjorden "
    "and Steilene in May 2025 and February 2026. FjordSim catches part of the first and misses the second, so from "
    "March to July 2026 Fl1 at 100 m and Dk1 at 60 m are 2.0–3.1 °C too cold. The model renews both basins in early "
    "August 2026, which brings them to the casts' temperature; the casts show no inflow then. NorKyst and NorFjords "
    "both carry the February 2026 inflow in salinity (Dk1 60 m 33.8 and 34.1 against 33.5 g/kg; FjordSim 32.7), "
    "but by April all three are 2–3 °C too cold there.",
    "<b>Spring 2026 is too cold below 50 m in both models</b>: in March–May, on the samples both reach, by 1.8–2.5 °C "
    "in FjordSim and 1.8–2.1 °C in NorKyst. NorKyst's water enters FjordSim's open boundary, and at the fjord mouth "
    "(IMR, March 2026) both are about 3 °C too cold at 30–75 m. NorFjords, with its own boundary and atmosphere, is "
    "too cold below 50 m as well (−1.1 to −1.6 °C in March–June 2026 against FjordSim's −1.5 to −2.2 on the same "
    "samples), and 1.8–2.5 °C at Torbjørnskjær in March.",
    "<b>The surface is too salty in every month of both years</b>: top 5 m +2.15 g/kg overall (NorKyst +3.12), "
    "+1.84 in year 1 and +2.47 in year 2. The Glomma plume at I-1 is missing throughout (+9.0 g/kg at 1 m). In the "
    "Drammensfjord FjordSim keeps the brackish layer that NorKyst and NorFjords lack (top 5 m +2.6 against +10.4 "
    "g/kg; NorFjords +10.6 to June 2026).",
    "<b>Near-surface temperature errors are FjordSim's own.</b> Summer heat stays in too thin a layer. In July 2025 "
    "5–20 m is 1.8 °C too cold. In July 2026 the inner-fjord casts hold 17–19 °C down to 4.5 m where FjordSim has "
    "10–15 °C, and the top 5 m are 3.0 °C too cold (NorKyst −0.8). In January–February 2026 the top 5 m are "
    "1.5–2.3 °C too warm.",
    "<b>Water level and tide.</b> FjordSim carries 70–72 % of the observed weather-driven variability (NorKyst "
    "63–66 %), as daily means 74 % (67–69 %), with higher correlation at every gauge. Its M2 is within 0.2 cm at "
    "all three gauges, S2, N2 and O1 within 0.3 cm; M4 is 58–78 % of the observed. NorKyst's M2 is 44–45 % too "
    "large. NorFjords' daily means, to June 2026, carry 89 % of the observed variability at r 0.93–0.94, more than "
    "either; its tide, fitted over 2024, has M2 27–36 % too large.",
    "<b>Unphysical cells grow in the second year.</b> The saltiest cell exceeds 36 g/kg on 157 of 334 days in year "
    "1 and on all 365 in year 2 (maximum 38.0 g/kg, 2 January 2026). Cells below −1 °C: at most 1887 in year 1, "
    "46 905 on 15 February 2026. The warmest cell is 35.3 °C on 17 July 2026.",
]):
    S(item)

# --------------------------------------------------------------------------------------------------
S(para("1  The run and the data", h1))
S(para("Grid: 424 × 681 cells of about 160 m, 39 z-levels to 467 m, 10.00–11.20 °E, 58.95–59.93 °N. Forcing: NORA3 "
       "atmosphere; hourly operational NorKyst v3 (m00) on the open southern boundary, its tide corrected to the Viker "
       "gauge. Initial state on 2024-10-01 from NorKyst v3, before the cast-corrected start existed. Rivers from NVE; "
       "CATKE mixing; WENO tracers, bounded salinity, upwind at the river mouths and in narrow coastal columns; the "
       "water is held at or above freezing, with no ice. The first-year report "
       "(<i>report_full/oslofjorden_validation_2025-10.pdf</i>) describes the setup in full."))
S(para("<b>Window.</b> 2024-10-01 to 2026-10-01: the 731 daily 3D snapshots of all 24 monthly parts, and the hourly "
       "station, section and tide-gauge files. Scores start on 2024-11-01. The station columns and domain statistics "
       "were taken from the snapshots on a cloud preprocessing VM beside the bucket, so the 180 GB of snapshots never "
       "left it."))
S(para("<b>Observations.</b> NIVA's CTD casts from NIVA's ODM2 database (odm2.p.niva.no), the Inner Oslofjord and Outer "
       "Oslofjord programmes, to September 2026. ODM2 holds the same cast days as the AquaMonitor export the first-year "
       "report used, 87 % of the values identical; its depths are the 1 m bins' tops and are written here as their "
       "centres. IMR's ØkoKyst casts (Færder, Torbjørnskjær = OF-1, Missingene = OF-2, Bastøy = OF-4, Breiangen vest = "
       "OF-5) and the ocean-acidification casts at Tisler, from Vannmiljø, monthly to March 2026, on standard depths. "
       "Kartverket water level every 10 minutes at Viker, Oscarsborg and Oslo. FerryBox samples are not scored: the 4 m "
       "columns at the FerryBox points were not extracted."))
S(para("<b>Reference models.</b> NorKyst v3 hourly from thredds.met.no at each station: the 160 m Oslofjord nest (m71) "
       "where it covers the station, otherwise the 800 m run (m00), compared at the hour nearest each cast. At the IMR "
       "stations, whose casts have no time of day, every model is taken over the cast's day: FjordSim as the mean of "
       "the day's two snapshots, NorKyst and NorFjords as their daily means."))
S(para("<b>NorFjords 160 m.</b> IMR's NorFjords model, run A01 (version v3): ROMS 3.9 on a 1501 × 721 grid of 160 m "
       "along the Skagerrak coast (8.2–12.0 °E, 57.7–60.1 °N), 40 terrain-following levels, minimum depth 10 m, GLS "
       "vertical mixing, third-order upstream horizontal advection, AROME atmosphere, no data assimilation; its archive "
       "starts in 2017. Only daily means are kept, plus hourly sea level for 2024; the daily means end on 30 June 2026 "
       "and 14 March 2026 is missing. NorFjords is compared on each cast's day, its levels placed below that day's mean "
       "surface; a daily mean is smoother than a cast, which if anything lowers its RMSE. Its bathymetry is smoothed, "
       "so the point is the wet cell within 1.5 km closest in depth to the casts, distance only breaking ties: 23–1493 m "
       "from the NIVA stations, 182–1472 m from the IMR ones. It is scored beside FjordSim on the samples both reach, "
       "not jointly with NorKyst, so that the FjordSim–NorKyst scores keep the run's last three months."))
nf = {r["station"]: r for r in read("norfjords_points.csv")}
nk = {r["station"]: r for r in read("norkyst_points.csv")}
cells = {r["station"]: r for r in read("cells.csv")}
rows = [["Basin (station)", "Deepest cast (m)", "FjordSim column (m)", "NorKyst column (m)", "NorFjords column (m)"]]
for s, name in (("Ep1", "Bunnefjorden"), ("Fl1", "Vestfjorden"), ("Dk1", "Steilene"), ("Im2", "Drøbak Sound"), ("D-2", "Drammensfjord")):
    rows.append([f"{name} ({s})", cells[s]["deepest_cast_m"], f'{float(cells[s]["model_depth_m"]):.0f}',
                 f'{float(nk[s]["norkyst_depth_m"]):.0f}', f'{float(nf[s]["norfjords_depth_m"]):.0f}'])
S(KeepTogether([para("Basin depths", h2), table(rows, widths=[3.6 * cm, 2.8 * cm, 3.2 * cm, 3.2 * cm, 3.2 * cm]),
                para("NorKyst's columns end well above the basins' deep water, so the joint tables hold 28 363 of the "
                     "65 273 scored samples, few of them below 50 m. NorFjords' columns reach most of it; at Fl1 its "
                     "91 m column has no value at 100 m.", caption)]))
S(figure(FIG / "map.png", "<b>Figure 1.</b> The stations this report scores, on the model depth. Green circles: NIVA "
         "cast stations with casts in the window, filled where the run also writes hourly station output; orange "
         "diamonds: IMR's ØkoKyst and Tisler stations, Torbjørnskjær and Breiangen vest being the run's hourly stations "
         "OF-1 and OF-5; yellow squares: the Kartverket tide gauges; blue triangles: the model columns the rivers "
         "enter. The red line marks the open southern boundary.",
         max_height=20 * cm))

# --------------------------------------------------------------------------------------------------
S(PageBreak())
S(para("2  CTD profiles against NIVA casts, NorKyst v3 and NorFjords", h1))
S(para("FjordSim is sampled from the daily snapshot nearest each cast, NorKyst at the hour nearest the cast, NorFjords "
       "from the daily mean of the cast's day. Model minus observed throughout; bias / RMSE in g/kg and °C."))
rows = [["Region", "Var.", "Depth", "Y1 FjordSim", "Y2 FjordSim", "Y1 joint: FjordSim", "Y1 NorKyst", "Y2 joint: FjordSim", "Y2 NorKyst"]]
for g in ("ALL", "Outer fjord", "Inner Oslofjord", "Drammensfjord"):
    for v in "ST":
        for b in ("all", "0-5 m", ">50 m"):
            rows.append([g, v, b] + [stat(by_year.get((g, v, b, y, "every"), [])) for y in ("Year 1", "Year 2")] +
                        [stat(by_year.get((g, v, b, y, k), [])) for y in ("Year 1", "Year 2") for k in ("fjordsim", "norkyst")])
S(KeepTogether([para("The two years", h2),
                table(rows, widths=[2.4 * cm, 1.0 * cm, 1.2 * cm] + [2.1 * cm] * 6),
                para("Year 1: November 2024 – September 2025; year 2: October 2025 – September 2026. First FjordSim on every "
                     "sample, then both models on the samples both reach. Every region and both models score worse in "
                     "year 2 except the Drammensfjord, whose start-state excess below 50 m halves. Inside the sills the "
                     "deep salinity changes sign (+0.20 to −0.53 g/kg) and the deep temperature error grows (−0.82 to "
                     "−1.40 °C); in the outer fjord the deep water becomes too fresh (+0.02 to −0.84 g/kg), in NorKyst "
                     "as well (+0.03 to −0.70 on the joint samples).", caption)]))
rows = [["Region", "Var.", "Depth", "Y1 FjordSim", "Y1 NorFjords", "Y2 FjordSim", "Y2 NorFjords"]]
for g in ("ALL", "Outer fjord", "Inner Oslofjord", "Drammensfjord"):
    for v in "ST":
        for b in ("all", "0-5 m", ">50 m"):
            rows.append([g, v, b] + [stat(by_year.get((g, v, b, y, k), [])) for y in ("Year 1", "Year 2")
                                     for k in ("nf_fjordsim", "norfjords")])
S(KeepTogether([para("The two years against NorFjords", h2),
                table(rows, widths=[2.6 * cm, 1.0 * cm, 1.3 * cm] + [2.6 * cm] * 4),
                para("FjordSim and NorFjords on the samples both reach; NorFjords' year 2 ends in June 2026. NorFjords "
                     "loses in year 2 as well (salinity RMSE 2.03 to 2.25 g/kg, FjordSim 1.63 to 1.95), and below 50 m "
                     "its temperature goes from unbiased (+0.00 / 1.10 °C) to −0.54 / 1.70, FjordSim's from −0.61 / 1.13 "
                     "to −1.31 / 1.88. In the Drammensfjord NorFjords' deep salinity is within 0.3 g/kg in both years, "
                     "its top 5 m 8.6 and 15.9 g/kg too salty.", caption)]))
skill = read("ctd_skill_fjordsim.csv")
rows = [["Region", "Variable", "Depth", "Samples", "Obs. mean", "FjordSim bias / RMSE"]]
for r in skill:
    rows.append([r["group"], r["variable"], r["band"], r["n"], r["obs_mean"], pair(r, "fjordsim")])
S(KeepTogether([para("FjordSim, every sample, November 2024 – September 2026", h2),
                table(rows, widths=[3.4 * cm, 1.6 * cm, 1.8 * cm, 1.8 * cm, 2 * cm, 3.8 * cm]),
                para("Outer fjord: the Outer Oslofjord programme's stations outside the sills. Inner Oslofjord: the Inner "
                     "Oslofjord programme, north of the Drøbak sill. Drammensfjord: D-2 and D-3. The top 20 m are "
                     "1.8–3.5 g/kg too salty in every region but the Drammensfjord's 5–20 m. Below 20 m the Inner "
                     "Oslofjord is too cold (−0.73 °C at 20–50 m, −1.11 below 50 m), the outer fjord at 20–50 m "
                     "(−0.48); the Drammensfjord is 0.2–0.3 °C too warm.", caption)]))
skill = read("ctd_skill.csv")
rows = [["Region", "Variable", "Depth", "Samples", "Obs. mean", "FjordSim", "NorKyst v3"]]
for r in skill:
    rows.append([r["group"], r["variable"], r["band"], r["n"], r["obs_mean"], pair(r, "fjordsim"), pair(r, "norkyst")])
S(KeepTogether([para("Both models on the samples NorKyst reaches", h2),
                table(rows, widths=[3 * cm, 1.6 * cm, 1.6 * cm, 1.6 * cm, 1.8 * cm, 3.3 * cm, 3.3 * cm]),
                para("FjordSim's salinity is the better overall (RMSE 2.24 against 2.53 g/kg), most of all in the "
                     "Drammensfjord (1.78 against 4.23) and the outer fjord (3.64 against 4.32); in the Inner Oslofjord "
                     "the two are even. NorKyst's temperature is the better (1.32 against 1.58 °C), in every region but "
                     "the Drammensfjord.", caption)]))
skill = read("ctd_skill_norfjords.csv")
rows = [["Region", "Variable", "Depth", "Samples", "Obs. mean", "FjordSim", "NorFjords"]]
for r in skill:
    rows.append([r["group"], r["variable"], r["band"], r["n"], r["obs_mean"], pair(r, "fjordsim"), pair(r, "norfjords")])
S(KeepTogether([para("FjordSim and NorFjords on the samples both reach, November 2024 – June 2026", h2),
                table(rows, widths=[3 * cm, 1.6 * cm, 1.6 * cm, 1.6 * cm, 1.8 * cm, 3.3 * cm, 3.3 * cm]),
                para("NorFjords reaches 47 348 samples, most of the deep water among them. FjordSim's salinity is the "
                     "better overall (RMSE 1.76 against 2.12 g/kg) and in every region; the temperatures are even (1.53 "
                     "and 1.49 °C). Below 50 m NorFjords is warmer and better in temperature (−0.22 / 1.38 against "
                     "−0.90 / 1.48 °C; Inner Oslofjord −0.21 against −1.04) but too salty (+0.50 g/kg, +0.58 in the "
                     "Inner Oslofjord) where FjordSim is unbiased. In the Drammensfjord below 50 m NorFjords is "
                     "+0.22 / 0.55 g/kg against FjordSim's +1.23 / 1.30, the start state; its top 5 m are +10.55 g/kg, "
                     "FjordSim's +2.14.", caption)]))
grid = read("ctd_skill_grid.csv")
rows = [["NorKyst grid", "Variable", "Depth", "Samples", "FjordSim", "NorKyst v3"]]
for r in grid:
    if r["band"] in ("0-5 m", "5-20 m", "all"):
        rows.append([r["group"].replace("m", " m"), r["variable"], r["band"], r["n"], pair(r, "fjordsim"), pair(r, "norkyst")])
S(KeepTogether([para("By NorKyst grid", h2), table(rows, widths=[3 * cm, 1.6 * cm, 1.8 * cm, 1.8 * cm, 3.6 * cm, 3.6 * cm]),
                para("FjordSim against NorKyst's 160 m nest on its stations and the 800 m run on the outer ones.", caption)]))
rows = [["Month", "Casts"] + [f"S {name}" for name, _, _ in BANDS] + [f"T {name}" for name, _, _ in BANDS]]
for month in sorted(monthly):
    m = monthly[month]
    rows.append([month, str(len(m["casts"]))] + [f'{sum(m[(v, name)]) / len(m[(v, name)]):+.2f}' if m.get((v, name)) else ""
                                               for v in ("S", "T") for name, _, _ in BANDS])
S(KeepTogether([para("By month", h2), table(rows, widths=[1.7 * cm, 1.3 * cm] + [1.75 * cm] * 8),
                para("FjordSim's bias on every sample, by month and depth band (g/kg, °C); October 2024 is the "
                     "unscored first month. The top 5 m are too salty in every month, by 0.6–4.5 g/kg. Both "
                     "springs are too cold below 50 m, 2026 the more (−1.9 to −2.2 °C in March–May, against −0.6 "
                     "to −1.2 in 2025). Both summers are too cold at 5–20 m, by up to 1.8 °C in July 2025 and 1.6 °C "
                     "in June 2026. July 2026's top 5 m are 3.0 °C too cold, January 2026's 2.3 °C too warm. Below "
                     "50 m salinity goes from +0.8 g/kg in winter 2024–25 to −0.8 in spring 2026. On the samples both "
                     "models reach, NorKyst's spring cold below 50 m is about as large (March–May 2026: −2.0, −1.8, "
                     "−2.1 °C against FjordSim's −2.2, −2.5, −1.8).", caption)]))
strat = read("stratification_skill.csv")
rows = [["Region", "Casts", "Observed mean", "FjordSim", "NorKyst v3"]]
for r in strat:
    rows.append([r["group"], r["casts"], r["obs_mean"], pair(r, "fjordsim"), pair(r, "norkyst")])
S(KeepTogether([para("Stratification", h2), table(rows, widths=[3.4 * cm, 1.6 * cm, 2.6 * cm, 3.4 * cm, 3.4 * cm]),
                para("Salinity at 25 m minus at 1 m, per cast, on the casts both reach at 25 m. FjordSim's halocline is "
                     "1.2 g/kg too weak, NorKyst's 2.5; in the Drammensfjord FjordSim's is 1.2 and NorKyst's 6.8 g/kg too "
                     "weak.", caption)]))
strat = read("stratification_skill_norfjords.csv")
rows = [["Region", "Casts", "Observed mean", "FjordSim", "NorFjords"]]
for r in strat:
    rows.append([r["group"], r["casts"], r["obs_mean"], pair(r, "fjordsim"), pair(r, "norfjords")])
S(KeepTogether([table(rows, widths=[3.4 * cm, 1.6 * cm, 2.6 * cm, 3.4 * cm, 3.4 * cm]),
                para("The same, FjordSim and NorFjords on the casts both reach to June 2026: NorFjords' halocline is 1.8 "
                     "g/kg too weak (FjordSim 1.4), 8.4 g/kg in the Drammensfjord (FjordSim 0.8).", caption)]))
S(figure(FIG / "stratification.png", "<b>Figure 2.</b> Salinity difference between 25 m and 1 m, observed against "
         "modelled, one point per cast: FjordSim and NorKyst on the casts both reach at 25 m, NorFjords (right) on the "
         "casts it and FjordSim reach.", max_height=6.5 * cm))
S(figure(FIG / "ctd_bias.png", "<b>Figure 3.</b> Bias by station and depth band: FjordSim (top) and NorKyst (middle) "
         "on the samples both reach, November 2024 – September 2026; NorFjords (bottom) on the samples it and FjordSim "
         "reach, to June 2026; salinity left, temperature right. Stations run from the outer fjord (top of each panel) "
         "to the Oslo harbour (bottom).", max_height=22 * cm))
S(figure(FIG / "ctd_scatter.png", "<b>Figure 4.</b> Every observed value against each model, coloured by region: "
         "FjordSim and NorKyst on the samples both reach, NorFjords on the samples it and FjordSim reach.",
         max_height=12 * cm))
S(figure(FIG / "basin_drift.png", "<b>Figure 5.</b> Deep water through the run: FjordSim (blue), NorKyst (orange) and "
         "NorFjords (green, to June 2026) daily, observations on the cast days (black); where a line is missing that "
         "model's column does not reach that depth. Bunnefjorden at 120 m (Ep1) is never renewed in the model: salinity falls from 34.0 to 32.5 g/kg "
         "and temperature stays at 6.1–6.8 °C while the casts hold 32.6–33.0 g/kg and 7.7–9.1 °C. The casts show "
         "renewals of Vestfjorden (Fl1) and Steilene (Dk1) in May 2025 (about day 230) and February 2026 (about day "
         "500); FjordSim takes part of the first, misses the second, and renews both in early August 2026 (about day "
         "670). Outside the Drøbak sill (Im2 100 m) the casts read 34.9–35.0 g/kg from February to June 2026, "
         "FjordSim 33.8–34.6, NorKyst 33.8–34.7 and NorFjords 34.5–35.2. D-2 at 100 m freshens from 34.0 g/kg in "
         "November 2024 to 32.1 in September 2026, against 31.6 in the casts. NorFjords renews the inner basins and "
         "overshoots: Ep1 at 120 m reaches 34.8 g/kg in August 2025 and April 2026 against 32.6–33.0 observed. It "
         "carries the February 2026 inflow at Dk1 60 m in salinity (34.1 against 33.5 g/kg), as NorKyst does, but is "
         "1.7–2.6 °C too cold there from April. In the Drammensfjord its deep salinity is near the casts' (D-2 100 m "
         "31.3–33.1 against 31.6 g/kg) while its temperature swings between 5 and 10 °C against the casts' steady 8 °C.",
         max_height=21 * cm))
S(figure(FIG / "surface_drift.png", "<b>Figure 6.</b> The surface through the run: salinity and temperature at 1 m "
         "from the outer fjord (top) to the Oslo harbour (bottom); an observation is the mean of the cast's 0.5 and "
         "1.5 m samples. At I-1, in the Glomma plume, FjordSim is 9.0 g/kg too salty on average (NorKyst 3.3). At D-2 "
         "FjordSim keeps the Drammenselva's fresh layer (+1.2 g/kg) where NorKyst is 8.2 g/kg too salty. NorFjords "
         "(green), November 2024 – June 2026: +5.5 g/kg at I-1 and +9.2 at D-2.",
         max_height=21 * cm))
S(figure(FIG / "drift_5m.png", "<b>Figure 7.</b> As Figure 6 at 5 m; Cq1, in the harbour like Ap2 but deeper, ends "
         "the list. The two models' salinity errors are alike outside the Drammensfjord, 1.4–5.9 g/kg too salty on "
         "average, NorFjords' too. At D-2 FjordSim is 4.1 g/kg too salty, NorKyst 13.7 and NorFjords 14.2 (to June "
         "2026). In July 2026 FjordSim is up to 5–9 °C too "
         "cold at 5 m in the inner fjord (Fl1, Cq1, Ep1), its warm layer too thin.", max_height=21 * cm))
S(figure(FIG / "drift_15m.png", "<b>Figure 8.</b> As Figure 7 at 15 m. Both summers are too cold inside Drøbak in "
         "every model, at the coldest cast by 3.7–6.7 °C in FjordSim, 3.9–4.8 °C in NorKyst and 5.3–6.5 °C in "
         "NorFjords at Fl1, Ep1 and Cq1.",
         max_height=21 * cm))
S(figure(FIG / "drift_30m.png", "<b>Figure 9.</b> As Figure 7 at 30 m. NorKyst has no line where its point is "
         "shallower than 50 m (I-1, MO-2, Fl1, Cq1). In February–May 2026 FjordSim is too cold at most stations, by up "
         "to 3.1 °C at MO-2, 3.0 at Fl1 and 2.7 at Cq1.", max_height=21 * cm))
S(figure(FIG / "ctd_map.png", "<b>Figure 10.</b> Mean salinity error below 20 m at each station: FjordSim and "
         "NorKyst on the samples both reach, November 2024 – September 2026; NorFjords (right) on the samples it and "
         "FjordSim reach, to June 2026.", max_height=10 * cm))
S(para("Profile figures, one panel per cast, are in <i>fig/profiles_&lt;station&gt;.png</i>; over two years they hold "
       "up to 50 casts per station and are too dense to print here."))

# --------------------------------------------------------------------------------------------------
S(PageBreak())
S(para("3  IMR's outer-fjord stations", h1))
S(para("Havforskningsinstituttet's ØkoKyst stations and Tisler, October 2024 to March 2026, are the only casts near the "
       "open boundary and in the Hvaler trench: Torbjørnskjær to 440 m, Missingene to 350 m. FjordSim's column at "
       "Missingene is 110 m deep, the deepest within three cells, and Færder's lies 1.9 km from the southern edge, "
       "inside the 3.2 km boundary sponge. Model minus observed, from November 2024: FjordSim and NorKyst on the "
       "samples both reach, then FjordSim and NorFjords on the samples both reach."))
im = read("imr_skill.csv")
rows = [["Station", "Variable", "Depth", "Samples", "Obs. mean", "FjordSim", "NorKyst v3"]]
for r in im:
    if r["band"] in ("0-5 m", "50-150 m", ">150 m", "all"):
        rows.append([r["station"], r["variable"], r["band"], r["n"], r["obs_mean"], pair(r, "fjordsim"), pair(r, "norkyst")])
S(table(rows, widths=[3 * cm, 1.6 * cm, 1.8 * cm, 1.6 * cm, 1.8 * cm, 3.2 * cm, 3.2 * cm]))
S(para("Over all samples the two models are alike (salinity RMSE 2.48 and 2.50 g/kg, temperature 1.21 and 1.18 °C). "
       "The top 5 m are too salty in both (+2.39 and +3.75 g/kg). Below 150 m FjordSim is within 0.01 g/kg and NorKyst "
       "1.47 g/kg too salty. In March 2026 at Torbjørnskjær and Færder the casts read 7.9–8.3 °C and 34.5–34.9 g/kg at "
       "30–75 m; FjordSim 4.7–5.0 °C and 32.6–33.6 g/kg, NorKyst 4.4–5.3 °C.", caption))
im = read("imr_skill_norfjords.csv")
rows = [["Station", "Variable", "Depth", "Samples", "Obs. mean", "FjordSim", "NorFjords"]]
for r in im:
    if r["band"] in ("0-5 m", "50-150 m", ">150 m", "all"):
        rows.append([r["station"], r["variable"], r["band"], r["n"], r["obs_mean"], pair(r, "fjordsim"), pair(r, "norfjords")])
S(table(rows, widths=[3 * cm, 1.6 * cm, 1.8 * cm, 1.6 * cm, 1.8 * cm, 3.2 * cm, 3.2 * cm]))
S(para("FjordSim and NorFjords: salinity RMSE 2.21 and 2.25 g/kg, temperature 1.19 and 1.08 °C. Below 150 m NorFjords "
       "is the closest of the three models (+0.07 / 0.18 g/kg, +0.13 / 0.64 °C). In March 2026 at 30–75 m it is "
       "1.8–2.5 °C too cold at Torbjørnskjær and within 0.7 °C at Færder, where FjordSim and NorKyst are 2.0–3.5 °C too "
       "cold.", caption))
S(figure(FIG / "imr_bias.png", "<b>Figure 11.</b> Mean error against depth at the IMR stations, November 2024 – March "
         "2026, each model on the samples it reaches (FjordSim blue, NorKyst orange, NorFjords green); salinity top, "
         "temperature bottom; south to north.",
         max_height=13 * cm))
S(figure(FIG / "imr_series_Torbj_rnskj_r.png", "<b>Figure 12.</b> Torbjørnskjær (OF-1), at the open boundary: "
         "FjordSim's daily snapshots (line), NorKyst and NorFjords on the cast days, casts in black.", max_height=20 * cm))
S(figure(FIG / "imr_series_F_rder.png", "<b>Figure 13.</b> As Figure 12, Færder.", max_height=17 * cm))

# --------------------------------------------------------------------------------------------------
S(PageBreak())
S(para("4  Time-depth sections at the stations", h1))
for n, (key, title_) in enumerate((("inner", "Inner Oslofjord"), ("drammen", "Drammensfjord"), ("middle", "Breiangen, "
                                   "Mossesundet and the Drøbak Sound"), ("outer", "Outer fjord"))):
    for var in ("S", "T"):
        S(figure(FIG / f"hovmoller_{key}_{var}.png", f"<b>Figure {14 + 2 * n + (var == 'T')}.</b> {title_}: "
                 f"{'salinity' if var == 'S' else 'temperature'}, FjordSim (top), NorKyst (middle) and NorFjords (bottom, "
                 "to June 2026), casts overlaid in the same colour scale.", max_height=15 * cm))
S(figure(FIG / "stations_S.png", "<b>Figure 22.</b> Hourly station output (daily means) at the twelve hydrography stations, "
         "salinity, NIVA casts overlaid.", max_height=20 * cm))
S(figure(FIG / "stations_T.png", "<b>Figure 23.</b> As Figure 22, temperature.", max_height=20 * cm))

# --------------------------------------------------------------------------------------------------
S(PageBreak())
S(para("5  Water level (Kartverket tide gauges)", h1))
wl = read("waterlevel.csv")
rows = [["Model", "Gauge", "Pairs", "Mean offset (m)", "r total", "cRMSE total (m)", "r residual", "RMSE residual (m)",
         "σ model / σ obs, residual", "Highest obs. / model (m above mean)"]]
for r in wl:
    rows.append([r["model"], r["station"], r["n"], f'{float(r["mean_offset_m"]):+.2f}', f'{float(r["r_total"]):.2f}',
                 f'{float(r["crmse_total_m"]):.3f}', f'{float(r["r_residual"]):.2f}', f'{float(r["rmse_residual_m"]):.3f}',
                 f'{float(r["std_ratio_residual"]):.2f}',
                 f'{float(r["obs_max_above_mean_m"]):.2f} / {float(r["model_max_above_mean_m"]):.2f}'])
S(table(rows, widths=[2 * cm, 1.8 * cm, 1.3 * cm, 1.5 * cm, 1.2 * cm, 1.6 * cm, 1.4 * cm, 1.7 * cm, 1.9 * cm, 3 * cm]))
S(para("2024-11-01 to 2026-10-01; FjordSim every 10 minutes, NorKyst hourly. Residual: the series minus its own fitted "
       "tide. FjordSim correlates at 0.81–0.82 in the residual and carries 70–72 % of its standard deviation, NorKyst "
       "0.79–0.80 and 63–66 %; the highest observed levels, 0.88–1.11 m above the mean, reach 0.66–0.75 m in "
       "FjordSim.", caption))
wd = read("waterlevel_daily.csv")
rows = [["Model", "Gauge", "Days", "r", "RMSE (m)", "σ model / σ obs", "Lowest obs. / model (m)"]]
for r in wd:
    rows.append([r["model"], r["station"], r["days"], f'{float(r["r"]):.2f}', f'{float(r["rmse_m"]):.3f}',
                 f'{float(r["std_ratio"]):.2f}', f'{float(r["obs_lowest_m"]):.2f} / {float(r["model_lowest_m"]):.2f}'])
S(KeepTogether([para("Daily means", h2), table(rows, widths=[3 * cm, 2.2 * cm, 1.3 * cm, 1.2 * cm, 1.8 * cm, 2.6 * cm, 3.6 * cm]),
                para("Daily-mean water level, each series minus its own mean, on the days each model and the "
                     "observations both cover; daily means leave out the tide without a fit, and are all NorFjords keeps "
                     "for this window. FjordSim carries 74 % of the observed standard deviation (r 0.87–0.89), NorKyst "
                     "67–69 % (0.86). NorFjords, on its 606 days to June 2026, carries 89 % (r 0.93–0.94). All three come "
                     "within 0.03 m of the lowest daily mean (−0.51 to −0.58 m observed).", caption)]))
S(figure(FIG / "waterlevel_residual.png", "<b>Figure 24.</b> The weather-driven water level at Oscarsborg, daily means; "
         "NorFjords (green) is its daily-mean output, to June 2026.", max_height=7 * cm))
S(figure(FIG / "waterlevel_event.png", "<b>Figure 25.</b> Total water level around the run's largest weather-driven "
         "excursion at Oscarsborg, 24 September – 17 October 2025.", max_height=12 * cm))
S(figure(FIG / "tide_amplitudes.png", "<b>Figure 26.</b> Tidal amplitudes. Black: Kartverket; blue: FjordSim; orange: "
         "NorKyst at the gauge; grey dashes: NorKyst's sea level at the open boundary south of Viker, before the "
         "correction; green: NorFjords fitted over 2024, with Kartverket over 2024 as black dashes.", max_height=8 * cm))
tides = read("tides.csv")
rows = [["Gauge", "Const.", "Observed", "FjordSim", "FjordSim − obs. phase (°)", "NorKyst", "NorKyst − obs. phase (°)",
         "NorKyst at boundary"]]
for r in tides:
    rows.append([r["station"], r["constituent"], r["kartverket_obs_cm"], r["fjordsim_cm"],
                 f'{int(r["fjordsim_minus_obs_phase_deg"]):+d}', r["norkyst_cm"], f'{int(r["norkyst_minus_obs_phase_deg"]):+d}',
                 r["norkyst_boundary_cm"]])
S(KeepTogether([table(rows, widths=[2 * cm, 1.2 * cm, 1.8 * cm, 1.6 * cm, 2.6 * cm, 1.6 * cm, 2.6 * cm, 2.2 * cm]),
                para("Amplitudes in cm, fitted over the 23 months with the thirteen constituents they separate. FjordSim's "
                     "M2 is within 0.2 cm of Kartverket at every gauge and within 9° in phase; S2, N2 and O1 are within "
                     "0.3 cm. M4 is 58–78 % of the observed and 32–48° early. NorKyst's M2 is 44–45 % too large: the "
                     "correction to Viker is what makes FjordSim's tide right.", caption)]))
tn = read("tides_norfjords_2024.csv")
rows = [["Gauge", "Const.", "Observed 2024", "NorFjords 2024", "NorFjords − obs. phase (°)"]]
for r in tn:
    rows.append([r["station"], r["constituent"], r["kartverket_obs_cm"], r["norfjords_cm"], f'{int(r["norfjords_minus_obs_phase_deg"]):+d}'])
S(KeepTogether([para("NorFjords' tide, 2024", h2), table(rows, widths=[2.4 * cm, 1.4 * cm, 2.6 * cm, 2.6 * cm, 3.6 * cm]),
                para("NorFjords keeps hourly sea level only for 2024, so its tide is fitted over 2024 (13 constituents) "
                     "against Kartverket over the same hours, with the same reference time. Its M2 is 27–36 % too large "
                     "and 8–22° early, S2 62–68 % and N2 36–46 % too large, O1 a third too small, and M4 150–180° out of "
                     "phase.", caption)]))

# --------------------------------------------------------------------------------------------------
S(PageBreak())
S(para("6  The Drammensfjord section", h1))
S(figure(FIG / "section_drammensfjord_S.png", "<b>Figure 27.</b> Monthly-mean salinity along the Drammensfjord, every "
         "second month of the run, the Drammenselva mouth on the left, the Svelvik sill (dashed) and Breiangen on the "
         "right, with the month's D-2 and D-3 casts at their place.", max_height=22 * cm))
S(figure(FIG / "section_drammensfjord_T.png", "<b>Figure 28.</b> As Figure 27, temperature.", max_height=22 * cm))
sx = read("sill_exchange.csv")
rows = [["Station", "Depth (m)", "Mean along-section velocity (m/s)", "Days with inflow > 1 cm/s", "Strongest daily inflow (m/s)"]]
for r in sx:
    if r["station"] == "DS-53":
        rows.append([r["station"], r["depth_m"], r["mean_along_ms"], r["fraction_days_inflow_gt_1cms"], r["strongest_daily_inflow_ms"]])
S(KeepTogether([para("The exchange over the Svelvik sill (DS-53)", h2), table(rows, widths=[2 * cm, 2 * cm, 4.4 * cm, 3.6 * cm, 3.8 * cm]),
                para("Daily means of the velocity along the section over the whole run, + out of the fjord. Out at "
                     "0.18–0.35 m/s in the top 2 m, in at 4.6–6.7 m on 90–98 % of days.", caption)]))

# --------------------------------------------------------------------------------------------------
S(para("7  Whole-domain diagnostics", h1))
S(figure(FIG / "domain_stats.png", "<b>Figure 29.</b> Daily statistics over all wet cells: volume means, the coldest and "
         "warmest cell, and the lowest and highest salinity; dashed, NorFjords' daily means over its points inside "
         "FjordSim's box, to June 2026 (its warmest and freshest top cell).", max_height=16 * cm))
for item in bullets([
    "Volume-mean temperature ranges from 4.4 °C (19 March 2026) to 13.7 °C (22 September 2025). In July 2026 the "
    "volume-mean salinity rises 1.1 g/kg and the temperature falls 2.2 °C in three weeks, a large inflow of cold, "
    "salty water that reaches the inner basins in early August.",
    "<b>Hot cells.</b> More than 1000 cells above 25 °C on 23 days, 15 in July 2025, 2 in June and 6 in July 2026; at "
    "most 48 088 cells (21 July 2025). The warmest cell is 35.3 °C (17 July 2026).",
    "<b>Cold cells.</b> 211 days have cells below −1 °C. In year 1 at most 1887 (5 January 2025); in the cold spell of "
    "February 2026 46 905 (15 February), the freezing clamp's limit in brackish water. Outside winter single cells "
    "reach −1.9 °C on 21 days of May–September 2025, on nine of them (346, 39, 24), the 64 m dead end south of "
    "Hvaler, and on 28 days of May–September 2026, most often (208, 632, 32), (251, 649, 32) and again "
    "(346, 39, 24).",
    "<b>Salinity overshoots.</b> The saltiest cell exceeds 36 g/kg on 522 of the 730 days, 157 of 334 in year 1 and "
    "all 365 in year 2, and 37 g/kg on 13; the maximum is 38.0 g/kg on 2 January 2026. The extracts keep no position "
    "for the saltiest cell; in the first year it was mostly the isolated 182 m pit in Breiangen (213, 418, 9).",
    "<b>NorFjords over the same box</b>, November 2024 – June 2026 (daily means, so its extremes are milder than a "
    "snapshot's): its warmest top cell is 25.0 °C (26 July 2025). Its saltiest cell exceeds 36 g/kg on 260 of 606 days "
    "(99 of 334 in year 1, 161 of 272 in year 2) and 37 g/kg on 76; on 56 of them it is the Drøbak Sound's deepest "
    "cell (193 m, up to 37.2 g/kg), on about 66 the bottom cell of a 10.6 m column at the Glomma mouth in Fredrikstad "
    "(10.95 °E, 59.20 °N), which reaches 46.4 g/kg (8 June 2026). It has no freezing limit: up to 28 270 cells below "
    "−1 °C in February 2025 and 60 671 in February 2026, the coldest −2.6 °C. So salinity overshoots in the second "
    "year are not FjordSim's alone.",
]):
    S(item)

# --------------------------------------------------------------------------------------------------
S(para("8  Interpretation and next steps", h1))
for item in bullets([
    "<b>The start state.</b> Two years are not enough to forget it everywhere. The Drammensfjord basin is still "
    "0.5 g/kg too salty at 100 m in September 2026, freshening at about 0.07 g/kg a month. Bunnefjorden's deep water "
    "is never renewed in the model: its start-state salinity drains away and leaves it 0.4 g/kg too fresh and "
    "2.4 °C too cold. A run from the cast-corrected initial state (now in the setup) would separate this from the "
    "renewal errors.",
    "<b>Renewals of the inner basins</b> are the largest deep error after the start state: the casts' May 2025 and "
    "February 2026 inflows are weak or missing in the model, and it renews in August 2026 instead. The water "
    "available outside the Drøbak sill is too fresh in both models (Im2 100 m 0.3–1.1 g/kg in FjordSim in February–June "
    "2026), so the first suspect is the boundary water, NorKyst's, rather than the sill itself. NorFjords has the "
    "salty water there (34.5–35.2 g/kg) and renews the inner basins, if anything too much.",
    "<b>Spring 2026 cold below 20 m</b> is shared with NorKyst and present at the mouth, so it comes in through the "
    "open boundary. NorFjords, with another boundary, is too cold below 50 m in March–June 2026 as well (−1.1 to "
    "−1.6 °C), though less at the mouth, so the Skagerrak water of that spring, or the winter that cooled it, is the "
    "common cause. Worth checking: NorKyst's Skagerrak water at 30–100 m in January–March 2026 against the IMR casts.",
    "<b>The salty surface</b> persists in both models in every month, so its cause is most likely an input they share "
    "(the river discharge and how it enters) rather than FjordSim's mixing; the Glomma plume at I-1 is missing in "
    "every season.",
    "<b>The near-surface temperature errors are FjordSim's own</b>: summer heat trapped in too thin a layer (both "
    "Julys, hot cells to 35 °C) and a winter surface too warm in January–February 2026, when up to 46 905 cells sit "
    "at the freezing clamp with no ice. The vertical mixing of heat under strong summer stratification, and the clamp, "
    "are the first suspects.",
    "<b>Unphysical salinity cells</b> exceed 36 g/kg on every day of the second year. Their positions should be "
    "recorded in the extraction (as the coldest cell's are) to tell whether the Breiangen pit keeps climbing.",
    "<b>NorFjords</b> shares the salty surface, the summer's cold 5–20 m and the cold spring of 2026, so those are "
    "unlikely to be FjordSim's mixing alone; its better deep temperature and weather-driven water level are what a "
    "spun-up model with its own boundary and atmosphere gives, and point at FjordSim's start state and at the set-ups "
    "coming in through NorKyst's boundary.",
]):
    S(item)

S(para("Sources and method", h2))
for item in bullets([
    "Scripts: <i>validation/report_2024-10_2026-10/scripts/</i>, copied from the second-window report's, set to the "
    "full run in <i>common.jl</i>, NorFjords removed. <i>extract.jl</i> took the station columns (NIVA and IMR cells "
    "together, <i>cells_extract.csv</i>) and domain statistics from each monthly snapshot on the preprocessing VM, "
    "<i>merge_extract.jl</i> joined them; <i>norkyst_fetch.jl</i> (the 800 m months June–September 2026 on the same "
    "VM), <i>norkyst_columns.jl</i> and <i>imr_norkyst.jl</i> read NorKyst; <i>ctd.jl</i>, <i>imr.jl</i>, "
    "<i>hovmoller.jl</i>, <i>analysis.jl</i>, <i>stations.jl</i>, <i>section.jl</i>, <i>sill_exchange.jl</i> and "
    "<i>map.jl</i> make the tables and figures; the year and month tables are computed here from "
    "<i>ctd_pairs.csv</i>.",
    "NorFjords, added 2026-11-16: <i>norfjords_columns.jl</i> and <i>imr_norfjords.jl</i>, copied from the first-year "
    "report and limited to the daily-mean files that exist, read the A01 archive's daily means (to 2026-06-30) at the "
    "NIVA and IMR stations and its 2024 hourly sea level; <i>ctd.jl</i>, <i>imr.jl</i>, <i>hovmoller.jl</i> and "
    "<i>analysis.jl</i> were rerun with NorFjords restored beside FjordSim. Every FjordSim–NorKyst table is unchanged. "
    "<i>common.jl</i> now finds the IMR files by their transliterated names (<i>Bastoy</i>, <i>Faerder</i>, "
    "<i>Torbjornskjaer</i>), as FjordSim's Observations module writes them, and <i>analysis.jl</i> reads Kartverket "
    "through that module.",
]):
    S(item)

doc = SimpleDocTemplate(str(OUT), pagesize=A4, leftMargin=1.8 * cm, rightMargin=1.8 * cm, topMargin=1.6 * cm,
                        bottomMargin=1.7 * cm, title="Oslofjord 2024–2026 run: validation of the full period", author="FjordSim")
doc.build(story, onFirstPage=on_page, onLaterPages=on_page)
print(OUT)
