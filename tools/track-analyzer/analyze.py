#!/usr/bin/env python3
"""
MapsPersonal Track Analyzer
Analyze GPX tracks exported from the MapsPersonal iOS app.

Features:
  - Distance, duration, moving/stopped time
  - Pace (min/km) and speed (km/h)
  - Elevation profile with DEM correction (Open-Elevation API)
  - Splits per km (pace + elevation per km)
  - Heart rate analysis (if recorded via HealthKit)
  - Summary chart output as PNG

Usage:
  python analyze.py track.gpx
  python analyze.py track.gpx --dem          # correct elevation via DEM
  python analyze.py track.gpx -o report.png  # custom output path
"""

import argparse
import json
import math
import sys
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

NS = {"g": "http://www.topografix.com/GPX/1/1",
      "gpxtpx": "http://www.garmin.com/xmlschemas/TrackPointExtension/v1"}

MOVE_THRESHOLD = 0.14  # m/s (~0.5 km/h)


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# GPX parsing
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Elevation: filtering, smoothing, DEM
# ---------------------------------------------------------------------------

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


def fetch_dem_elevations(points: list[Point], batch=100) -> np.ndarray:
    """Query DEM API for terrain-based elevations.

    Tries OpenTopoData first (more reliable), falls back to Open-Elevation.
    """
    elevations = []
    n = len(points)

    # OpenTopoData: max 100 locations per request, 1 req/sec
    print("  Using OpenTopoData (SRTM 30m)...")
    for i in range(0, n, batch):
        chunk = points[i:i + batch]
        locations = "|".join(f"{p.lat},{p.lon}" for p in chunk)
        url = f"https://api.opentopodata.org/v1/srtm30m?locations={locations}"

        try:
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read())
                if data.get("status") == "OK":
                    elevations.extend(
                        r["elevation"] if r["elevation"] is not None else None
                        for r in data["results"]
                    )
                else:
                    print(f"  API error (batch {i}): {data.get('error', 'unknown')}", file=sys.stderr)
                    elevations.extend([None] * len(chunk))
        except Exception as e:
            print(f"  API error (batch {i}): {e}", file=sys.stderr)
            elevations.extend([None] * len(chunk))

        # Rate limit: 1 req/sec
        if i + batch < n:
            import time
            time.sleep(1.1)

    return np.array([e if e is not None else np.nan for e in elevations])


# ---------------------------------------------------------------------------
# Stats computation
# ---------------------------------------------------------------------------

def compute_stats(points: list[Point], eles: np.ndarray):
    n = len(points)

    # Cumulative distance
    cum_dist = [0.0]
    for i in range(1, n):
        cum_dist.append(cum_dist[-1] + haversine(
            points[i - 1].lat, points[i - 1].lon,
            points[i].lat, points[i].lon))
    cum_dist = np.array(cum_dist)

    # Speeds per segment
    speeds = [0.0]
    for i in range(1, n):
        dt = (points[i].time - points[i - 1].time).total_seconds()
        d = cum_dist[i] - cum_dist[i - 1]
        speeds.append(d / dt if dt > 0 else 0)
    speeds = np.array(speeds)

    total_dist = cum_dist[-1]
    duration = (points[-1].time - points[0].time).total_seconds()

    # Moving time
    moving = 0.0
    for i in range(1, n):
        dt = (points[i].time - points[i - 1].time).total_seconds()
        if speeds[i] > MOVE_THRESHOLD:
            moving += dt

    # Elevation gain/loss from smoothed data
    gain = loss = 0.0
    valid_eles = eles[~np.isnan(eles)]
    for i in range(1, len(valid_eles)):
        diff = valid_eles[i] - valid_eles[i - 1]
        if diff > 0:
            gain += diff
        else:
            loss -= diff

    # Splits per km (using moving time, like Strava)
    splits = []
    km_idx = 0
    split_start_i = 0
    for i in range(1, n):
        while cum_dist[i] >= (km_idx + 1) * 1000 and km_idx * 1000 < total_dist:
            km_end_i = i
            split_dist = min((km_idx + 1) * 1000, total_dist) - km_idx * 1000

            # Moving time for this split (exclude stopped segments)
            split_moving = 0.0
            for j in range(split_start_i + 1, km_end_i + 1):
                dt = (points[j].time - points[j - 1].time).total_seconds()
                if speeds[j] > MOVE_THRESHOLD:
                    split_moving += dt

            pace = split_moving / (split_dist / 1000) if split_dist > 0 else 0

            start_ele = eles[split_start_i] if not np.isnan(eles[split_start_i]) else 0
            end_ele = eles[km_end_i] if not np.isnan(eles[km_end_i]) else 0
            ele_change = end_ele - start_ele

            splits.append({
                "km": km_idx + 1,
                "pace_s": pace,
                "ele_change": ele_change,
            })
            km_idx += 1
            split_start_i = i

    # Last partial km
    if split_start_i < n - 1:
        remaining_dist = total_dist - km_idx * 1000
        if remaining_dist > 50:  # only if > 50m remaining
            split_moving = 0.0
            for j in range(split_start_i + 1, n):
                dt = (points[j].time - points[j - 1].time).total_seconds()
                if speeds[j] > MOVE_THRESHOLD:
                    split_moving += dt
            pace = split_moving / (remaining_dist / 1000) if remaining_dist > 0 else 0
            start_ele = eles[split_start_i] if not np.isnan(eles[split_start_i]) else 0
            end_ele = eles[-1] if not np.isnan(eles[-1]) else 0
            splits.append({
                "km": km_idx + 1,
                "pace_s": pace,
                "ele_change": end_ele - start_ele,
                "partial_m": remaining_dist,
            })

    # Heart rate
    hrs = [p.hr for p in points if p.hr is not None]
    hr_avg = int(np.mean(hrs)) if hrs else None
    hr_max = max(hrs) if hrs else None

    return {
        "total_dist": total_dist,
        "duration": duration,
        "moving": moving,
        "stopped": duration - moving,
        "avg_speed": total_dist / duration if duration > 0 else 0,
        "avg_moving_speed": total_dist / moving if moving > 0 else 0,
        "ele_min": float(np.nanmin(eles)) if not np.all(np.isnan(eles)) else None,
        "ele_max": float(np.nanmax(eles)) if not np.all(np.isnan(eles)) else None,
        "ele_gain": gain,
        "ele_loss": loss,
        "cum_dist": cum_dist,
        "speeds": speeds,
        "splits": splits,
        "hr_avg": hr_avg,
        "hr_max": hr_max,
        "n_points": n,
    }


# ---------------------------------------------------------------------------
# Plotting
# ---------------------------------------------------------------------------

def fmt_duration(s):
    h, m, sec = int(s // 3600), int((s % 3600) // 60), int(s % 60)
    return f"{h}h {m:02d}m {sec:02d}s"


def fmt_pace(sec_per_km):
    m, s = int(sec_per_km // 60), int(sec_per_km % 60)
    return f"{m}:{s:02d}"


def plot(name, points, eles_smooth, eles_raw, stats, output, has_hr, ele_source="gps"):
    n = len(points)
    cum_dist = stats["cum_dist"]
    dist_km = cum_dist / 1000
    minutes = np.array([(p.time - points[0].time).total_seconds() / 60 for p in points])

    n_rows = 3 if has_hr else 2
    fig, axes = plt.subplots(n_rows, 2, figsize=(14, 5 * n_rows))
    fig.suptitle(f"{name} — {stats['total_dist']/1000:.2f} km", fontsize=16, fontweight="bold")

    # 1. Map
    ax = axes[0, 0]
    lons = [p.lon for p in points]
    lats = [p.lat for p in points]
    ax.plot(lons, lats, color="#2196F3", linewidth=1.5, alpha=0.8)
    ax.plot(lons[0], lats[0], "go", markersize=10, label="Start")
    ax.plot(lons[-1], lats[-1], "rs", markersize=10, label="End")
    ax.set_xlabel("Longitude")
    ax.set_ylabel("Latitude")
    ax.set_title("Route")
    ax.legend()
    ax.set_aspect("equal")
    ax.grid(True, alpha=0.3)

    # 2. Elevation
    ax = axes[0, 1]
    ax.fill_between(dist_km, eles_smooth, alpha=0.3, color="#4CAF50")
    ax.plot(dist_km, eles_smooth, color="#4CAF50", linewidth=1.5, label="Smoothed")
    ax.plot(dist_km, eles_raw, color="#A5D6A7", linewidth=0.5, alpha=0.4, label="Raw GPS")
    ele_range = np.nanmax(eles_smooth) - np.nanmin(eles_smooth)
    ax.set_ylim(np.nanmin(eles_smooth) - max(ele_range * 0.15, 5),
                np.nanmax(eles_smooth) + max(ele_range * 0.15, 5))
    ax.set_xlabel("Distance (km)")
    ax.set_ylabel("Elevation (m)")
    src_label = "DEM SRTM30" if ele_source == "dem" else "GPS"
    ax.set_title(f"Elevation ({src_label}) — +{stats['ele_gain']:.0f}m / -{stats['ele_loss']:.0f}m")
    ax.legend()
    ax.grid(True, alpha=0.3)

    # 3. Speed
    ax = axes[1, 0]
    speeds_smooth = smooth(stats["speeds"] * 3.6, window=15)
    ax.plot(minutes, speeds_smooth, color="#FF9800", linewidth=1.5)
    avg_ms = stats["avg_moving_speed"] * 3.6
    ax.axhline(y=avg_ms, color="#F44336", linestyle="--",
               label=f"Avg moving: {avg_ms:.1f} km/h")
    ax.set_xlabel("Time (min)")
    ax.set_ylabel("Speed (km/h)")
    ax.set_title("Speed")
    ax.legend()
    ax.grid(True, alpha=0.3)
    ax.set_ylim(bottom=0)

    # 4. Stats + Splits
    ax = axes[1, 1]
    ax.axis("off")

    lines = [
        ("Distance", f"{stats['total_dist']/1000:.2f} km"),
        ("Duration", fmt_duration(stats["duration"])),
        ("Moving time", fmt_duration(stats["moving"])),
        ("Stopped time", fmt_duration(stats["stopped"])),
        ("", ""),
        ("Avg pace", f"{fmt_pace(stats['duration']/stats['total_dist']*1000)} /km" if stats["total_dist"] > 0 else "-"),
        ("Avg moving pace", f"{fmt_pace(stats['moving']/stats['total_dist']*1000)} /km" if stats["total_dist"] > 0 else "-"),
        ("Max speed", f"{np.max(speeds_smooth):.1f} km/h"),
        ("", ""),
        ("Elevation min/max", f"{stats['ele_min']:.0f} / {stats['ele_max']:.0f} m" if stats["ele_min"] else "-"),
        ("Elevation gain", f"+{stats['ele_gain']:.0f} m"),
        ("Elevation loss", f"-{stats['ele_loss']:.0f} m"),
    ]

    if stats["hr_avg"]:
        lines += [("", ""), ("Avg HR", f"{stats['hr_avg']} bpm"), ("Max HR", f"{stats['hr_max']} bpm")]

    lines += [
        ("", ""),
        ("Points", f"{stats['n_points']}"),
        ("Start", points[0].time.astimezone().strftime("%H:%M:%S")),
        ("End", points[-1].time.astimezone().strftime("%H:%M:%S")),
    ]

    # Splits table
    if stats["splits"]:
        lines += [("", ""), ("--- Splits ---", "")]
        for sp in stats["splits"]:
            ele_str = f"+{sp['ele_change']:.0f}" if sp["ele_change"] >= 0 else f"{sp['ele_change']:.0f}"
            km_label = f"KM {sp['km']}" if "partial_m" not in sp else f"KM {sp['km']} ({sp['partial_m']:.0f}m)"
            lines.append((f"  {km_label}", f"{fmt_pace(sp['pace_s'])} /km  {ele_str} m"))

    y = 0.98
    for label, val in lines:
        if label == "":
            y -= 0.02
            continue
        ax.text(0.05, y, label, fontsize=10, fontweight="bold", transform=ax.transAxes, va="top")
        ax.text(0.55, y, val, fontsize=10, transform=ax.transAxes, va="top", ha="left")
        y -= 0.045
    ax.set_title("Summary")

    # 5-6. Heart Rate (if available)
    if has_hr:
        hrs_all = np.array([p.hr if p.hr is not None else np.nan for p in points])

        ax = axes[2, 0]
        valid_hr = ~np.isnan(hrs_all)
        if valid_hr.sum() > 0:
            ax.plot(minutes[valid_hr], hrs_all[valid_hr], color="#F44336", linewidth=1, alpha=0.6)
            hr_smooth = smooth(hrs_all, window=15)
            ax.plot(minutes, hr_smooth, color="#D32F2F", linewidth=2)
            ax.axhline(y=stats["hr_avg"], color="#FF9800", linestyle="--",
                       label=f"Avg: {stats['hr_avg']} bpm")
            ax.legend()
        ax.set_xlabel("Time (min)")
        ax.set_ylabel("HR (bpm)")
        ax.set_title("Heart Rate")
        ax.grid(True, alpha=0.3)

        ax = axes[2, 1]
        if valid_hr.sum() > 0:
            ax.plot(dist_km[valid_hr], hrs_all[valid_hr], color="#F44336", linewidth=1, alpha=0.4)
            ax.plot(dist_km, hr_smooth, color="#D32F2F", linewidth=2)
        ax.set_xlabel("Distance (km)")
        ax.set_ylabel("HR (bpm)")
        ax.set_title("Heart Rate vs Distance")
        ax.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(output, dpi=150, bbox_inches="tight")
    print(f"Saved to {output}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Analyze MapsPersonal GPX tracks")
    parser.add_argument("gpx", help="Path to GPX file")
    parser.add_argument("-o", "--output", help="Output PNG path (default: <gpx_name>_analysis.png)")
    parser.add_argument("--elevation", choices=["gps", "dem"], default="gps",
                        help="Elevation source: 'gps' (device, default) or 'dem' (SRTM 30m via API)")
    args = parser.parse_args()

    gpx_path = Path(args.gpx)
    if not gpx_path.exists():
        print(f"Error: {gpx_path} not found", file=sys.stderr)
        sys.exit(1)

    output = args.output or str(gpx_path.with_suffix("")) + "_analysis.png"

    print(f"Parsing {gpx_path.name}...")
    name, points = parse_gpx(str(gpx_path))
    print(f"  {len(points)} points, {name}")

    # Elevation processing
    eles_raw = np.array([p.ele if p.ele is not None else np.nan for p in points])

    ele_source = args.elevation
    if ele_source == "dem":
        print("Fetching DEM elevations...")
        eles_dem = fetch_dem_elevations(points)
        valid_count = np.sum(~np.isnan(eles_dem))
        if valid_count < len(points) * 0.5:
            print(f"  WARNING: DEM returned only {valid_count}/{len(points)} valid elevations, falling back to GPS")
            ele_source = "gps"
            eles_filtered = filter_spikes(eles_raw, max_jump=5.0)
            eles_smooth = smooth(eles_filtered, window=25)
        else:
            eles_smooth = smooth(eles_dem, window=15)
            print(f"  DEM range: {np.nanmin(eles_dem):.0f} - {np.nanmax(eles_dem):.0f} m")
    else:
        eles_filtered = filter_spikes(eles_raw, max_jump=5.0)
        eles_smooth = smooth(eles_filtered, window=25)

    has_hr = any(p.hr is not None for p in points)
    stats = compute_stats(points, eles_smooth)

    # Print summary
    print(f"\n{'='*50}")
    print(f"  {name}")
    print(f"{'='*50}")
    print(f"  Distance:     {stats['total_dist']/1000:.2f} km")
    print(f"  Duration:     {fmt_duration(stats['duration'])}")
    print(f"  Moving:       {fmt_duration(stats['moving'])}")
    print(f"  Avg pace:     {fmt_pace(stats['duration']/stats['total_dist']*1000)} /km")
    print(f"  Moving pace:  {fmt_pace(stats['moving']/stats['total_dist']*1000)} /km")
    print(f"  Elevation:    +{stats['ele_gain']:.0f}m / -{stats['ele_loss']:.0f}m")
    if stats["hr_avg"]:
        print(f"  Avg HR:       {stats['hr_avg']} bpm")
        print(f"  Max HR:       {stats['hr_max']} bpm")
    print(f"{'='*50}")

    if stats["splits"]:
        print("\n  Splits:")
        print(f"  {'KM':>4}  {'Pace':>8}  {'Elev':>6}")
        for sp in stats["splits"]:
            ele_str = f"+{sp['ele_change']:.0f}" if sp["ele_change"] >= 0 else f"{sp['ele_change']:.0f}"
            km_label = f"{sp['km']}" if "partial_m" not in sp else f"{sp['km']}*"
            extra = f" ({sp['partial_m']:.0f}m)" if "partial_m" in sp else ""
            print(f"  {km_label:>4}  {fmt_pace(sp['pace_s']):>5} /km  {ele_str:>5} m{extra}")

    print(f"\nGenerating chart...")
    plot(name, points, eles_smooth, eles_raw, stats, output, has_hr, ele_source)


if __name__ == "__main__":
    main()
