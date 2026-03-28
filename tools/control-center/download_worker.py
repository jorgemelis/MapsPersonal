#!/usr/bin/env python3
"""Standalone geological tile downloader — runs as separate process."""

import json
import math
import os
import sqlite3
import sys
import time
import requests


def lat_lon_to_tile(lat, lon, zoom):
    n = 2 ** zoom
    x = int((lon + 180.0) / 360.0 * n)
    lat_rad = math.radians(lat)
    y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return x, y


def tile_to_bbox_3857(x, y, zoom):
    n = 2 ** zoom
    world = 20037508.342789244
    tile_size = 2 * world / n
    min_x = -world + x * tile_size
    max_x = min_x + tile_size
    max_y = world - y * tile_size
    min_y = max_y - tile_size
    return min_x, min_y, max_x, max_y


def fetch_arcgis(session, url, layers, x, y, z):
    bbox = tile_to_bbox_3857(x, y, z)
    params = {
        "bbox": f"{bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]}",
        "bboxSR": "3857", "imageSR": "3857",
        "size": "256,256", "format": "png32",
        "transparent": "true", "layers": layers, "f": "image",
    }
    try:
        r = session.get(url, params=params, timeout=30)
        if r.status_code == 200 and "image" in r.headers.get("content-type", ""):
            return r.content
    except Exception:
        pass
    return None


def fetch_wms(session, url, layers, wms_version, srs, x, y, z):
    bbox = tile_to_bbox_3857(x, y, z)
    if wms_version == "1.3.0":
        bbox_str = f"{bbox[1]},{bbox[0]},{bbox[3]},{bbox[2]}"
        crs = "CRS"
    else:
        bbox_str = f"{bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]}"
        crs = "SRS"
    params = {
        "SERVICE": "WMS", "VERSION": wms_version,
        "REQUEST": "GetMap", "LAYERS": layers,
        crs: srs, "BBOX": bbox_str,
        "WIDTH": "256", "HEIGHT": "256",
        "FORMAT": "image/png", "TRANSPARENT": "TRUE",
    }
    try:
        r = session.get(url, params=params, timeout=30)
        if r.status_code == 200 and "image" in r.headers.get("content-type", ""):
            return r.content
    except Exception:
        pass
    return None


def main():
    """Download tiles. Config from file arg 1, progress written to file arg 2."""
    if len(sys.argv) >= 3:
        config_file = sys.argv[1]
        progress_file = sys.argv[2]
    else:
        # Fallback: stdin/stdout mode
        config_file = None
        progress_file = None

    if config_file:
        with open(config_file) as f:
            config = json.load(f)
    else:
        config = json.loads(sys.stdin.read())

    output_path = config["output_path"]
    min_lat, min_lon = config["min_lat"], config["min_lon"]
    max_lat, max_lon = config["max_lat"], config["max_lon"]
    min_zoom, max_zoom = config["min_zoom"], config["max_zoom"]
    source_type = config["source_type"]
    tile_url = config["tile_url"]
    layers = config["layers"]
    fmt = config.get("format", "png")
    wms_version = config.get("wms_version", "1.1.1")
    srs = config.get("srs", "EPSG:3857")
    name = config.get("name", "Geological Map")
    attribution = config.get("attribution", "")

    # Count tiles
    total = 0
    for z in range(min_zoom, max_zoom + 1):
        x_min, y_max = lat_lon_to_tile(min_lat, min_lon, z)
        x_max, y_min = lat_lon_to_tile(max_lat, max_lon, z)
        total += (x_max - x_min + 1) * (y_max - y_min + 1)

    # Init MBTiles
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    if os.path.exists(output_path):
        os.remove(output_path)

    conn = sqlite3.connect(output_path)
    c = conn.cursor()
    c.execute("CREATE TABLE metadata (name TEXT, value TEXT)")
    c.execute("""CREATE TABLE tiles (
        zoom_level INTEGER, tile_column INTEGER,
        tile_row INTEGER, tile_data BLOB,
        PRIMARY KEY (zoom_level, tile_column, tile_row))""")
    for k, v in {
        "name": name, "format": fmt,
        "bounds": f"{min_lon},{min_lat},{max_lon},{max_lat}",
        "minzoom": str(min_zoom), "maxzoom": str(max_zoom),
        "type": "overlay",
        "description": name,
        "attribution": f"© {attribution}",
    }.items():
        c.execute("INSERT INTO metadata VALUES (?, ?)", (k, v))
    conn.commit()

    # Download
    session = requests.Session()
    session.headers["User-Agent"] = "MapsPersonal/1.0"

    downloaded = errors = 0
    batch = []

    for z in range(min_zoom, max_zoom + 1):
        x_min, y_max = lat_lon_to_tile(min_lat, min_lon, z)
        x_max, y_min = lat_lon_to_tile(max_lat, max_lon, z)

        for x in range(x_min, x_max + 1):
            for y in range(y_min, y_max + 1):
                if source_type == "arcgis_rest":
                    data = fetch_arcgis(session, tile_url, layers, x, y, z)
                else:
                    data = fetch_wms(session, tile_url, layers, wms_version, srs, x, y, z)

                if data:
                    tms_y = (2 ** z) - 1 - y
                    batch.append((z, x, tms_y, data))
                    downloaded += 1
                else:
                    errors += 1

                if len(batch) >= 100:
                    c.executemany("INSERT OR REPLACE INTO tiles VALUES (?,?,?,?)", batch)
                    conn.commit()
                    batch = []

                if (downloaded + errors) % 10 == 0 or downloaded + errors == total:
                    progress_data = {
                        "downloaded": downloaded,
                        "errors": errors,
                        "total": total,
                        "zoom": z,
                    }
                    _report(progress_data, progress_file)

                time.sleep(0.05)

        if batch:
            c.executemany("INSERT OR REPLACE INTO tiles VALUES (?,?,?,?)", batch)
            batch = []
        conn.commit()

    conn.close()
    size = os.path.getsize(output_path) / (1024 * 1024)
    _report({"done": True, "downloaded": downloaded, "errors": errors, "size_mb": round(size, 1)}, progress_file)


def _report(data, progress_file):
    line = json.dumps(data)
    if progress_file:
        with open(progress_file, "a") as f:
            f.write(line + "\n")
    else:
        print(line, flush=True)


if __name__ == "__main__":
    main()
