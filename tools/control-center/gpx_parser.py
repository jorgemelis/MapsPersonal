"""GPX parsing and elevation processing utilities."""

import math
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import numpy as np

NS = {"g": "http://www.topografix.com/GPX/1/1",
      "gpxtpx": "http://www.garmin.com/xmlschemas/TrackPointExtension/v1"}


@dataclass
class Point:
    lat: float
    lon: float
    ele: float | None
    time: datetime
    hr: int | None


def haversine(lat1, lon1, lat2, lon2):
    R = 6371000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def parse_gpx(path: str) -> tuple[str, list[Point]]:
    tree = ET.parse(path)
    root = tree.getroot()

    name_el = root.find(".//g:trk/g:name", NS)
    if name_el is None:
        name_el = root.find(".//g:metadata/g:name", NS)
    name = name_el.text if name_el is not None else Path(path).stem

    points = []
    for p in root.findall(".//g:trkpt", NS):
        lat = float(p.get("lat"))
        lon = float(p.get("lon"))

        ele_el = p.find("g:ele", NS)
        ele = float(ele_el.text) if ele_el is not None else None

        t = p.find("g:time", NS).text
        time = datetime.fromisoformat(t.replace("Z", "+00:00"))

        hr_el = p.find(".//gpxtpx:hr", NS)
        hr = int(hr_el.text) if hr_el is not None else None

        points.append(Point(lat, lon, ele, time, hr))

    return name, points


def smooth(arr, window=25):
    result = np.copy(arr)
    valid = ~np.isnan(arr)
    if valid.sum() < window:
        return result
    vals = arr[valid]
    kernel = np.ones(window) / window
    smoothed = np.convolve(vals, kernel, mode="same")
    half = window // 2
    for i in range(half):
        w = i + 1 + half
        smoothed[i] = np.mean(vals[:w])
        smoothed[-(i + 1)] = np.mean(vals[-w:])
    result[valid] = smoothed
    return result


def filter_spikes(eles, max_jump=5.0):
    filtered = np.copy(eles)
    valid = ~np.isnan(filtered)
    vals = filtered[valid]
    for i in range(1, len(vals)):
        if abs(vals[i] - vals[i - 1]) > max_jump:
            vals[i] = vals[i - 1]
    filtered[valid] = vals
    return filtered
