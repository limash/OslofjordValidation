"""NIVA's FerryBox tracks in the model box, October 2024 to September 2026, from NIVA's FerryBox API
(https://ferrybox-api.niva.no, the service `pyniva` reads). Two ships cross the box: MS Color Fantasy (FA,
Oslo-Kiel, the whole fjord) and MS Color Hybrid (CH, Sandefjord-Stromstad, the mouth; data from July 2025).
Written as `<ship>_<yyyymm>.csv` (time in UTC, lon, lat, temperature, salinity), one row per minute: the
temperature at the hull intake (SBE38), the salinity of the FerryBox's thermosalinograph (SBE45), both
from water pumped in at about 4 m. Only values that passed NIVA's QC, which drops almost everything taken
in port, and only while the ship moves at 1 m/s or more, since a stopped ship's intake holds standing water.
A month already written is skipped.

    uv run src/ferrybox_fetch.py
"""
import json
from pathlib import Path

import jwt
import pandas as pd
import requests

API = "https://ferrybox-api.niva.no/v1/"
KEY_FILE = Path.home() / ".config" / "niva-data" / "niva-service-account.json"
OUT = Path(__file__).resolve().parent.parent / "data" / "inputs" / "observations" / "niva_ferrybox_2024-2026"
SHIPS = ("FA", "CH")
SIGNALS = {"temperature": "INLET/SBE38/TEMPERATURE/RAW", "salinity": "FERRYBOX/SBE45/SALINITY/RAW",
           "speed": "NAVIGATION/GPS/SPEED/RAW", "track": "gpstrack"}

# The API takes a token signed with the service account's key, as `pyniva.token2header` makes it.
account = json.loads(KEY_FILE.read_text())
claims = {"iss": account["client_email"], "sub": account["client_email"], "email": account["client_email"],
          "aud": "ferrybox-api.niva.no"}
headers = {"Authorization": "Bearer " + jwt.encode(claims, account["private_key"], algorithm="RS256")}


def get(endpoint, **params):
    r = requests.get(API + endpoint, headers=headers, params=params, timeout=900)
    r.raise_for_status()
    return r.json()["t"]


OUT.mkdir(parents=True, exist_ok=True)
for ship in SHIPS:
    uuid = {k: get("metaflow/", path=f"{ship}/{p}")[0]["uuid"] for k, p in SIGNALS.items()}
    for month in pd.date_range("2024-10-01", "2026-09-01", freq="MS"):
        file = OUT / f"{ship}_{month:%Y%m}.csv"
        if file.exists():
            continue
        # dt=0: the raw minutes; without it the API averages to about 1000 points.
        t = get("tsb/", uuid=",".join(uuid.values()), dt=0, start=month.isoformat(),
                end=(month + pd.offsets.MonthBegin()).isoformat())
        df = pd.DataFrame(t, columns=["time", "longitude", "latitude", *uuid.values()]).rename(
            columns={u: k for k, u in uuid.items()})
        df = df[df.longitude.between(10.0, 11.2) & df.latitude.between(58.95, 59.93) & (df.speed >= 1)
                & (df.temperature.notna() | df.salinity.notna())]
        df["time"] = pd.to_datetime(df.time).dt.strftime("%Y-%m-%dT%H:%M:%S")
        df[["time", "longitude", "latitude", "temperature", "salinity"]].round(
            {"longitude": 5, "latitude": 5, "temperature": 3, "salinity": 3}).rename(
            columns={"longitude": "lon", "latitude": "lat"}).to_csv(file, index=False)
        print(f"{file.name}: {len(df)} minutes, {df.salinity.notna().sum()} with salinity")
print("wrote", OUT)
