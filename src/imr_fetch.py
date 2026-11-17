"""Havforskningsinstituttet's (IMR) CTD casts in the model domain from Vannmiljø: the ØkoKyst Skagerrak
stations (Torbjørnskjær VT3/OF-1, Missingene VT65/OF-2, Bastøy VT2/OF-4, Breiangen vest VT10/OF-5,
Færder VT84) and the ocean-acidification station Tisler, salinity and temperature from 2024-06-01 on.
Written as `niva_ctd_2024-2025` is: `stations.csv` and `<station>_S.csv`/`<station>_T.csv` (time, depth,
value). Vannmiljø holds each value twice, with and without a sample id, and dates the casts without a
time of day.

    uv run src/imr_fetch.py
"""
import json
import re
from pathlib import Path

import pandas as pd
import requests
from pyproj import Transformer

API = "https://vannmiljoapi.miljodirektoratet.no/api/Public/"
KEY_FILE = Path.home() / ".config" / "niva-data" / "vannmiljo_api_token.json"
OUT = Path(__file__).resolve().parent.parent / "data" / "inputs" / "observations" / "imr_ctd_2024-2026"
BOX = (10.0, 11.2, 58.95, 59.93)

headers = {"vannmiljoWebAPIKey": json.loads(KEY_FILE.read_text())["VANNMILJO_API_KEY"]}
utm = Transformer.from_crs(4326, 25833, always_xy=True)
xs, ys = zip(*[utm.transform(lon, lat) for lon in BOX[:2] for lat in BOX[2:]])
query = {
    "BoundingBox": {"xmin": min(xs), "ymin": min(ys), "xmax": max(xs), "ymax": max(ys)},
    "FromDateSamplingTime": "2024-06-01", "ToDateSamplingTime": "2026-12-31", "FromRegDate": "2024-01-01",
    "WaterLocationCategoryFilter": ["C"], "ParameterIDFilter": ["SALIN", "TEMP"],
    "Contractor": "Havforskningsinstituttet",
}
response = requests.post(API + "GetRegistrations", json=query, headers=headers, timeout=600)
response.raise_for_status()
df = pd.DataFrame(response.json()["Result"])
df = df[df.SamplingMethodName == "Marint vann: Målesonde in situ"]

locations = requests.post(API + "GetWaterLocations", json={"WaterLocationIDFilter": [int(i) for i in df.WaterLocationID.unique()]},
                          headers=headers, timeout=120).json()["Result"]
# Tisler is two locations 1 km apart, told apart by their alternative names 1 and 5.
code = {l["WaterLocationID"]: (l["Name"] if l["Name"] != "Tisler" else None) for l in locations}
for i, alternative in df.groupby("WaterLocationID").Name_Alternative.first().items():
    if code[i] is None:
        code[i] = f"Tisler-{alternative}"
programme = {"Økosystemovervåking i kystvann (ØkoKyst)": "OkoKyst", "Overvåking av havforsuring": "Havforsuring"}

OUT.mkdir(parents=True, exist_ok=True)
LETTERS = str.maketrans({"Æ": "AE", "æ": "ae", "Ø": "O", "ø": "o", "Å": "A", "å": "a"})
stem = lambda c: re.sub(r"[^A-Za-z0-9]+", "_", c.translate(LETTERS))   # as common.jl's `obs_stem`
rows = []
for l in sorted(locations, key=lambda l: code[l["WaterLocationID"]]):
    i = l["WaterLocationID"]
    d = df[df.WaterLocationID == i]
    name = code[i]
    rows.append(f'{name},"{l["Name"]} {d.Name_Alternative.iloc[0]}",{l["CoordX_dg"]:.6f},{l["CoordY_dg"]:.6f},{programme[d.ActivityName.iloc[0]]}')
    for parameter, suffix in (("SALIN", "S"), ("TEMP", "T")):
        x = d[d.ParameterID == parameter].drop_duplicates(["SamplingTime", "UpperDepth"])
        x = x.sort_values(["SamplingTime", "UpperDepth"])
        lines = [f"{t},{z:g},{v:.3f}" for t, z, v in zip(x.SamplingTime.str[:19], x.UpperDepth, x.RegValue)]
        (OUT / f"{stem(name)}_{suffix}.csv").write_text("time,depth,value\n" + "\n".join(lines) + "\n")
    print(f"{name}: {d.SamplingTime.nunique()} casts, {d.SamplingTime.min()[:10]} .. {d.SamplingTime.max()[:10]}, to {d.UpperDepth.max():g} m")
(OUT / "stations.csv").write_text("station_code,station_name,longitude,latitude,project_id\n" + "\n".join(rows) + "\n")
print("wrote", OUT)
