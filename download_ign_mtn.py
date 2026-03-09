"""
Download IGN MTN 1:50.000 topographic map tiles as MBTiles.
Zone: Torres de la Alameda - Pozuelo del Rey - Valverde de Alcalá triangle.
"""

import math
import os
import sqlite3
import time
import requests

# Bounding box: triangle with ~500m margin
MIN_LAT = 40.3600
MAX_LAT = 40.4071
MIN_LON = -3.3637
MAX_LON = -3.2938

# Zoom levels (10-16 for topographic detail)
MIN_ZOOM = 10
MAX_ZOOM = 16

# IGN WMTS endpoint (tiles already prepared, fast)
WMTS_TEMPLATE = "https://www.ign.es/wmts/mapa-raster?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=MTN&STYLE=default&TILEMATRIXSET=GoogleMapsCompatible&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/jpeg"

OUTPUT_FILE = os.path.join(os.path.dirname(__file__), "data", "ign_mtn50.mbtiles")

TILE_SIZE = 256


def lat_lon_to_tile(lat, lon, zoom):
    """Convert lat/lon to tile x,y at given zoom."""
    n = 2 ** zoom
    x = int((lon + 180.0) / 360.0 * n)
    lat_rad = math.radians(lat)
    y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return x, y


def init_mbtiles(path):
    """Create MBTiles SQLite database."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        os.remove(path)

    conn = sqlite3.connect(path)
    c = conn.cursor()

    c.execute("""
        CREATE TABLE metadata (
            name TEXT,
            value TEXT
        )
    """)
    c.execute("""
        CREATE TABLE tiles (
            zoom_level INTEGER,
            tile_column INTEGER,
            tile_row INTEGER,
            tile_data BLOB,
            PRIMARY KEY (zoom_level, tile_column, tile_row)
        )
    """)

    metadata = {
        "name": "IGN MTN 1:50.000 - Topographic Map",
        "format": "jpg",
        "bounds": f"{MIN_LON},{MIN_LAT},{MAX_LON},{MAX_LAT}",
        "center": f"{(MIN_LON+MAX_LON)/2},{(MIN_LAT+MAX_LAT)/2},{MAX_ZOOM}",
        "minzoom": str(MIN_ZOOM),
        "maxzoom": str(MAX_ZOOM),
        "type": "baselayer",
        "description": "IGN Mapa Topográfico Nacional 1:50.000",
        "attribution": "© IGN España",
    }
    for k, v in metadata.items():
        c.execute("INSERT INTO metadata VALUES (?, ?)", (k, v))

    conn.commit()
    return conn


def main():
    total = 0
    for z in range(MIN_ZOOM, MAX_ZOOM + 1):
        x_min, y_max = lat_lon_to_tile(MIN_LAT, MIN_LON, z)
        x_max, y_min = lat_lon_to_tile(MAX_LAT, MAX_LON, z)
        total += (x_max - x_min + 1) * (y_max - y_min + 1)

    print(f"Zone: Torres de la Alameda - Pozuelo del Rey - Valverde de Alcalá")
    print(f"Bbox: [{MIN_LAT}, {MIN_LON}] to [{MAX_LAT}, {MAX_LON}]")
    print(f"Zoom levels: {MIN_ZOOM}-{MAX_ZOOM}")
    print(f"Total tiles to download: {total}")
    print(f"Output: {OUTPUT_FILE}")
    print()

    conn = init_mbtiles(OUTPUT_FILE)
    cursor = conn.cursor()
    session = requests.Session()
    session.headers["User-Agent"] = "MapsPersonal/1.0 (topographic tile downloader)"

    downloaded = 0
    errors = 0

    for z in range(MIN_ZOOM, MAX_ZOOM + 1):
        x_min, y_max = lat_lon_to_tile(MIN_LAT, MIN_LON, z)
        x_max, y_min = lat_lon_to_tile(MAX_LAT, MAX_LON, z)

        tiles_at_zoom = (x_max - x_min + 1) * (y_max - y_min + 1)
        print(f"Zoom {z}: {tiles_at_zoom} tiles ({x_max-x_min+1}x{y_max-y_min+1})")

        for x in range(x_min, x_max + 1):
            for y in range(y_min, y_max + 1):
                url = WMTS_TEMPLATE.replace("{z}", str(z)).replace("{x}", str(x)).replace("{y}", str(y))
                try:
                    resp = session.get(url, timeout=30)
                    if resp.status_code == 200 and resp.headers.get("content-type", "").startswith("image"):
                        tms_y = (2 ** z) - 1 - y
                        cursor.execute(
                            "INSERT OR REPLACE INTO tiles VALUES (?, ?, ?, ?)",
                            (z, x, tms_y, resp.content),
                        )
                        downloaded += 1
                    else:
                        errors += 1
                except Exception:
                    errors += 1

                if (downloaded + errors) % 10 == 0:
                    print(f"  Progress: {downloaded + errors}/{total} (errors: {errors})", end="\r")

                time.sleep(0.05)  # WMTS is faster, less delay needed

        conn.commit()

    conn.close()

    file_size = os.path.getsize(OUTPUT_FILE) / (1024 * 1024)
    print(f"\nDone! Downloaded {downloaded} tiles ({errors} errors)")
    print(f"File: {OUTPUT_FILE} ({file_size:.1f} MB)")


if __name__ == "__main__":
    main()
