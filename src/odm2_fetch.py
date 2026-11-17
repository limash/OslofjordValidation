"""NIVA's CTD casts at the stations of `niva_ctd_2024-2025` from NIVA's ODM2 database
(https://odm2.p.niva.no), October 2024 to October 2026: AquaMonitor's export ends in December 2025.
Written in the same layout, `stations.csv` (the FerryBox points left out) and `<station>_S.csv` /
`<station>_T.csv` (time, depth, value), with only values flagged Good. ODM2 labels each 1 m bin by its
top; the depth written is the bin's centre, as in the AquaMonitor export of the same casts. A cast's time
is its first value's.

    uv run src/odm2_fetch.py
"""
import json
import re
from pathlib import Path

import pandas as pd
import requests

API = "https://odm2.p.niva.no"
KEY_FILE = Path.home() / ".config" / "niva-data" / "odm2_api_key.json"
OBSERVATIONS = Path(__file__).resolve().parent.parent / "data" / "inputs" / "observations"
SOURCE = OBSERVATIONS / "niva_ctd_2024-2025"
OUT = OBSERVATIONS / "niva_ctd_odm2_2024-2026"
# AquaMonitor's project ids and an ODM2 project name for each; the query needs one.
PROJECT = {"6302": "Indre Oslofjord", "12914": "Eutrofiovervåkning i Ytre Oslofjord 2025-2029"}

headers = {"X-API-Key": json.loads(KEY_FILE.read_text())["ODM2-READ-API-KEY"]}
LETTERS = str.maketrans({"Æ": "AE", "æ": "ae", "Ø": "O", "ø": "o", "Å": "A", "å": "a"})
stem = lambda c: re.sub(r"[^A-Za-z0-9]+", "_", c.translate(LETTERS))   # as common.jl's `obs_stem`

lines = (SOURCE / "stations.csv").read_text().splitlines()
OUT.mkdir(parents=True, exist_ok=True)
kept = [lines[0]]
for line in lines[1:]:
    code, project = line.split(",")[0], line.split(",")[-1]
    if code.endswith("-FB") or not (SOURCE / f"{stem(code)}_S.csv").exists():
        continue
    r = requests.get(API + "/ctd/profiles/values", headers=headers, timeout=600, params={
        "projectname": PROJECT[project], "station_code": code, "start_time": "2024-10-01T00:00:00",
        "end_time": "2026-10-02T00:00:00", "parameters": ["Salinity", "Temp"]})
    r.raise_for_status()
    df = pd.DataFrame(r.json())
    if df.empty:
        print(f"{code}: none")
        continue
    df = df[(df.projectstationcode == code) & (df.qualitycodecv == "Good")].drop_duplicates("valueid")
    df["t"] = pd.to_datetime(df.valuedatetime, format="ISO8601")
    # A re-processed cast is stored as a new result beside the old one: keep each day's latest result,
    # the one AquaMonitor holds.
    latest = df.groupby([df.t.dt.date, "variablecode"]).resultid.transform("max")
    df = df[df.resultid == latest]
    # One result per variable per cast; a cast's temperature takes the time of its salinity profile.
    start = df.groupby("resultid").t.min()
    df["cast"] = df.resultid.map(start)
    salinity = sorted(df[df.variablecode == "Salinity"].cast.unique())
    nearest = lambda t: min(salinity, key=lambda s: abs(s - t)) if salinity else t
    df["cast"] = [c if v == "Salinity" else nearest(c) for c, v in zip(df.cast, df.variablecode)]
    df["depth"] = df.zlocation + 0.5
    for variable, suffix in (("Salinity", "S"), ("Temp", "T")):
        x = df[df.variablecode == variable].drop_duplicates(["cast", "depth"]).sort_values(["cast", "depth"])
        rows = [f"{t.strftime('%Y-%m-%dT%H:%M:%S')},{z:g},{v:.3f}" for t, z, v in zip(x.cast, x.depth, x.datavalue)]
        (OUT / f"{stem(code)}_{suffix}.csv").write_text("time,depth,value\n" + "\n".join(rows) + "\n")
    kept.append(line)
    print(f"{code}: {len(salinity)} casts, {df.t.min():%Y-%m-%d} .. {df.t.max():%Y-%m-%d}, projects {sorted(df.projectname.unique())}")
(OUT / "stations.csv").write_text("\n".join(kept) + "\n")
print("wrote", OUT)
