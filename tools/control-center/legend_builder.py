"""Legend Builder — extracts geological legends from IGME ArcGIS REST service.

For each downloaded geological map, queries the MapServer for all geological
units in the area, then renders a tile and uses identify calls on a grid to
map each unit to its actual rendered color. Generates a PNG legend image.

Currently supports: IGME MAGNA 50 (Spain)
"""

import io
import json
import math
import time
import urllib.parse
import urllib.request
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np


MAPSERVER_BASE = "https://mapas.igme.es/gis/rest/services/Cartografia_Geologica/IGME_MAGNA_50/MapServer"


# ---------------------------------------------------------------------------
# Data fetching
# ---------------------------------------------------------------------------

def fetch_units_for_bbox(min_lat: float, min_lon: float,
                         max_lat: float, max_lon: float) -> list[dict]:
    """Query layer 11 for all geological units in a bounding box."""
    params = urllib.parse.urlencode({
        "where": "1=1",
        "geometry": f"{min_lon},{min_lat},{max_lon},{max_lat}",
        "geometryType": "esriGeometryEnvelope",
        "inSR": "4326",
        "spatialRel": "esriSpatialRelIntersects",
        "outFields": "HOJA,ID,DLO",
        "returnGeometry": "false",
        "resultRecordCount": "2000",
        "f": "json",
    })
    url = f"{MAPSERVER_BASE}/11/query?{params}"
    req = urllib.request.Request(url, headers={"User-Agent": "MapsPersonal/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
    except Exception:
        return []

    if "error" in data:
        return []

    seen = {}
    for f in data.get("features", []):
        a = f["attributes"]
        uid = a.get("ID")
        if uid is not None and uid not in seen:
            seen[uid] = {"ID": uid, "DLO": a.get("DLO", ""), "HOJA": a.get("HOJA", "")}
    return sorted(seen.values(), key=lambda u: u["ID"])


def fetch_units_for_sheet(hoja: str) -> list[dict]:
    """Query layer 11 for all geological units in a specific sheet."""
    params = urllib.parse.urlencode({
        "where": f"HOJA = '{hoja}'",
        "outFields": "HOJA,ID,DLO",
        "returnGeometry": "false",
        "resultRecordCount": "2000",
        "f": "json",
    })
    url = f"{MAPSERVER_BASE}/11/query?{params}"
    req = urllib.request.Request(url, headers={"User-Agent": "MapsPersonal/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
    except Exception:
        return []

    if "error" in data:
        return []

    seen = {}
    for f in data.get("features", []):
        a = f["attributes"]
        uid = a.get("ID")
        if uid is not None and uid not in seen:
            seen[uid] = {"ID": uid, "DLO": a.get("DLO", ""), "HOJA": a.get("HOJA", "")}
    return sorted(seen.values(), key=lambda u: u["ID"])


def _identify_point(lat: float, lon: float) -> dict | None:
    """Identify at a point, returns attributes dict or None."""
    params = urllib.parse.urlencode({
        "geometry": f"{lon},{lat}",
        "geometryType": "esriGeometryPoint",
        "sr": "4326",
        "layers": "all:11",
        "tolerance": "1",
        "mapExtent": f"{lon-0.2},{lat-0.2},{lon+0.2},{lat+0.2}",
        "imageDisplay": "256,256,96",
        "returnGeometry": "false",
        "f": "json",
    })
    url = f"{MAPSERVER_BASE}/identify?{params}"
    req = urllib.request.Request(url, headers={"User-Agent": "MapsPersonal/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read())
        results = data.get("results", [])
        if results:
            return results[0].get("attributes", {})
    except Exception:
        pass
    return None


def _bbox_4326_to_3857(min_lon, min_lat, max_lon, max_lat):
    """Convert WGS84 bbox to Web Mercator (EPSG:3857)."""
    def to_3857(lon, lat):
        x = lon * 20037508.342789244 / 180.0
        y = math.log(math.tan((90 + lat) * math.pi / 360.0)) / (math.pi / 180.0)
        y = y * 20037508.342789244 / 180.0
        return x, y
    x1, y1 = to_3857(min_lon, min_lat)
    x2, y2 = to_3857(max_lon, max_lat)
    return (x1, y1, x2, y2)


# ---------------------------------------------------------------------------
# Main builder
# ---------------------------------------------------------------------------

def build_legend_quick(bbox: tuple[float, float, float, float],
                       output_path: Path,
                       title: str = "Geological Legend",
                       progress_callback=None) -> Path | None:
    """Build a geological legend by grid-sampling a rendered tile.

    Strategy:
    1. Query all units in the bbox (or by sheet number)
    2. Render a tile of the area (layer 11 only — color polygons)
    3. Identify on a grid of points, reading the pixel color at each
    4. Map each unit ID to its rendered pixel color
    5. Generate the legend image with color swatches + descriptions

    Args:
        bbox: (min_lat, min_lon, max_lat, max_lon)
        output_path: where to save the PNG
        title: legend title
        progress_callback: optional callable(msg: str)
    """
    from PIL import Image

    min_lat, min_lon, max_lat, max_lon = bbox
    log = progress_callback or (lambda msg: None)

    # 1. Get units
    log("Querying geological units in area...")
    units = fetch_units_for_bbox(min_lat, min_lon, max_lat, max_lon)
    if not units:
        center_lat = (min_lat + max_lat) / 2
        center_lon = (min_lon + max_lon) / 2
        result = _identify_point(center_lat, center_lon)
        if result:
            hoja = result.get("HOJA") or result.get("nº de hoja")
            if hoja:
                log(f"Querying units for sheet {hoja}...")
                units = fetch_units_for_sheet(hoja)

    if not units:
        log("No geological units found in this area.")
        return None

    log(f"Found {len(units)} geological units")

    # 2. Render tile (layer 11 only)
    log("Rendering map tile for color sampling...")
    tile_size = 512
    bbox_3857 = _bbox_4326_to_3857(min_lon, min_lat, max_lon, max_lat)
    params = urllib.parse.urlencode({
        "bbox": f"{bbox_3857[0]},{bbox_3857[1]},{bbox_3857[2]},{bbox_3857[3]}",
        "bboxSR": "3857", "imageSR": "3857",
        "size": f"{tile_size},{tile_size}",
        "format": "png32", "transparent": "true",
        "layers": "show:11", "f": "image",
    })
    tile_url = f"{MAPSERVER_BASE}/export?{params}"
    req = urllib.request.Request(tile_url, headers={"User-Agent": "MapsPersonal/1.0"})

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            tile_data = resp.read()
        img = Image.open(io.BytesIO(tile_data)).convert("RGBA")
        pixels = np.array(img)
    except Exception as e:
        log(f"Failed to fetch tile: {e}")
        return _render_legend(units, {}, output_path, title)

    # 3. Grid identify — sample points and read pixel colors
    #    Skip transparent pixels and stop early when all units are found
    grid = 10  # 10x10 = 100 points max
    unit_colors = {}  # unit_id -> (R, G, B)
    seen_colors = set()  # colors already identified
    unit_ids = {u["ID"] for u in units}
    calls = 0

    log(f"Identifying geological units on {grid}x{grid} grid ({len(unit_ids)} units to find)...")
    for gy in range(grid):
        # Stop early if we found all units
        if len(unit_colors) >= len(unit_ids):
            log(f"  All {len(unit_ids)} units found, stopping early")
            break

        for gx in range(grid):
            lat = min_lat + (max_lat - min_lat) * (gy + 0.5) / grid
            lon = min_lon + (max_lon - min_lon) * (gx + 0.5) / grid

            # Read pixel color — skip transparent
            px = int((lon - min_lon) / (max_lon - min_lon) * tile_size)
            py = int((max_lat - lat) / (max_lat - min_lat) * tile_size)
            px = max(0, min(tile_size - 1, px))
            py = max(0, min(tile_size - 1, py))

            r, g, b, a = pixels[py, px]
            if a < 128:
                continue

            # Skip if this exact color is already mapped to a unit
            rgb = (int(r), int(g), int(b))
            if rgb in seen_colors:
                continue
            seen_colors.add(rgb)

            result = _identify_point(lat, lon)
            calls += 1
            if result:
                uid_str = result.get("ID") or result.get("unidad cartográfica")
                if uid_str:
                    try:
                        uid = int(uid_str)
                        if uid not in unit_colors:
                            unit_colors[uid] = rgb
                    except ValueError:
                        pass

        log(f"  Row {gy+1}/{grid} — {len(unit_colors)}/{len(unit_ids)} units, {calls} API calls")

    log(f"Mapped {len(unit_colors)}/{len(units)} units to colors. Rendering legend...")

    # 4. Render legend
    result = _render_legend(units, unit_colors, output_path, title)
    log(f"Legend saved: {output_path}")
    return result


# ---------------------------------------------------------------------------
# Legend rendering
# ---------------------------------------------------------------------------

def _render_legend(units: list[dict], unit_colors: dict[int, tuple],
                   output_path: Path, title: str) -> Path:
    """Render the legend as a PNG image using matplotlib.

    Args:
        units: list of unit dicts (ID, DLO, HOJA)
        unit_colors: dict mapping unit ID -> (R, G, B) pixel color
        output_path: where to save
        title: legend title
    """
    n = len(units)
    if n == 0:
        return output_path

    row_height = 0.45
    fig_height = max(3, n * row_height + 1.5)
    fig, ax = plt.subplots(figsize=(10, fig_height))
    ax.set_xlim(0, 10)
    ax.set_ylim(0, n + 1)
    ax.axis("off")
    ax.set_title(title, fontsize=14, fontweight="bold", pad=15)

    for i, unit in enumerate(units):
        y = n - i - 0.5
        uid = unit["ID"]
        dlo = unit["DLO"]

        # Get color (from pixel sampling, or gray fallback)
        rgb = unit_colors.get(uid)
        if rgb:
            color = (rgb[0] / 255, rgb[1] / 255, rgb[2] / 255)
        else:
            color = (0.85, 0.85, 0.85)

        # Color swatch
        rect = mpatches.FancyBboxPatch(
            (0.1, y - 0.18), 0.8, 0.36,
            boxstyle="round,pad=0.02",
            facecolor=color, edgecolor="black", linewidth=0.5
        )
        ax.add_patch(rect)

        # Unit ID
        ax.text(1.1, y, str(uid), fontsize=8, va="center",
                fontweight="bold", fontfamily="monospace")

        # Lithological description
        desc = dlo.strip()
        if len(desc) > 90:
            desc = desc[:87] + "..."
        ax.text(1.6, y, desc, fontsize=7.5, va="center", fontfamily="sans-serif")

    plt.tight_layout()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(str(output_path), dpi=150, bbox_inches="tight",
                facecolor="white", edgecolor="none")
    plt.close(fig)
    return output_path
