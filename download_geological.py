"""
Download IGME MAGNA 50 geological map tiles as MBTiles.
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

# Zoom levels to download (10-15 gives good coverage from overview to detail)
MIN_ZOOM = 10
MAX_ZOOM = 15

# IGME MAGNA 50 ArcGIS REST endpoint (more reliable than WMS)
REST_URL = "https://mapas.igme.es/gis/rest/services/Cartografia_Geologica/IGME_MAGNA_50/MapServer/export"

# Output file
OUTPUT_FILE = os.path.join(os.path.dirname(__file__), "data", "geologico_magna50.mbtiles")

TILE_SIZE = 256


def lat_lon_to_tile(lat, lon, zoom):
    """Convert lat/lon to tile x,y at given zoom."""
    n = 2 ** zoom
    x = int((lon + 180.0) / 360.0 * n)
    lat_rad = math.radians(lat)
    y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return x, y


def tile_to_bbox_3857(x, y, zoom):
    """Convert tile x,y,z to bounding box in EPSG:3857 (meters)."""
    n = 2 ** zoom
    # World bounds in EPSG:3857
    world = 20037508.342789244

    tile_size = 2 * world / n
    min_x = -world + x * tile_size
    max_x = min_x + tile_size
    max_y = world - y * tile_size
    min_y = max_y - tile_size

    return min_x, min_y, max_x, max_y


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

    # Metadata
    metadata = {
        "name": "IGME MAGNA 50 - Geological Map",
        "format": "png",
        "bounds": f"{MIN_LON},{MIN_LAT},{MAX_LON},{MAX_LAT}",
        "center": f"{(MIN_LON+MAX_LON)/2},{(MIN_LAT+MAX_LAT)/2},{MAX_ZOOM}",
        "minzoom": str(MIN_ZOOM),
        "maxzoom": str(MAX_ZOOM),
        "type": "overlay",
        "description": "IGME MAGNA 50 geological map (1:50,000)",
        "attribution": "© IGME - Instituto Geológico y Minero de España",
    }
    for k, v in metadata.items():
        c.execute("INSERT INTO metadata VALUES (?, ?)", (k, v))

    conn.commit()
    return conn


def download_tile(session, x, y, zoom):
    """Download a single tile from ArcGIS REST export."""
    bbox = tile_to_bbox_3857(x, y, zoom)
    params = {
        "bbox": f"{bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]}",
        "bboxSR": "3857",
        "imageSR": "3857",
        "size": f"{TILE_SIZE},{TILE_SIZE}",
        "format": "png32",
        "transparent": "true",
        "layers": "show:0,2",  # Lithology color + contacts/faults
        "f": "image",
    }

    resp = session.get(REST_URL, params=params, timeout=30)
    if resp.status_code == 200 and resp.headers.get("content-type", "").startswith("image"):
        return resp.content
    return None


def main():
    # Count total tiles
    total = 0
    for z in range(MIN_ZOOM, MAX_ZOOM + 1):
        x_min, y_max = lat_lon_to_tile(MIN_LAT, MIN_LON, z)  # SW corner
        x_max, y_min = lat_lon_to_tile(MAX_LAT, MAX_LON, z)  # NE corner
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
    session.headers["User-Agent"] = "MapsPersonal/1.0 (geological tile downloader)"

    downloaded = 0
    errors = 0

    for z in range(MIN_ZOOM, MAX_ZOOM + 1):
        x_min, y_max = lat_lon_to_tile(MIN_LAT, MIN_LON, z)
        x_max, y_min = lat_lon_to_tile(MAX_LAT, MAX_LON, z)

        tiles_at_zoom = (x_max - x_min + 1) * (y_max - y_min + 1)
        print(f"Zoom {z}: {tiles_at_zoom} tiles ({x_max-x_min+1}x{y_max-y_min+1})")

        for x in range(x_min, x_max + 1):
            for y in range(y_min, y_max + 1):
                tile_data = download_tile(session, x, y, z)
                if tile_data:
                    # MBTiles uses TMS y-flip
                    tms_y = (2 ** z) - 1 - y
                    cursor.execute(
                        "INSERT OR REPLACE INTO tiles VALUES (?, ?, ?, ?)",
                        (z, x, tms_y, tile_data),
                    )
                    downloaded += 1
                else:
                    errors += 1

                if (downloaded + errors) % 10 == 0:
                    print(f"  Progress: {downloaded + errors}/{total} (errors: {errors})", end="\r")

                # Small delay to be respectful to IGME servers
                time.sleep(0.1)

        conn.commit()

    conn.close()

    file_size = os.path.getsize(OUTPUT_FILE) / (1024 * 1024)
    print(f"\nDone! Downloaded {downloaded} tiles ({errors} errors)")
    print(f"File: {OUTPUT_FILE} ({file_size:.1f} MB)")


if __name__ == "__main__":
    main()
