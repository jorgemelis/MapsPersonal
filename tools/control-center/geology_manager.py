"""Geology Manager module — browse map, search places, download geological tiles."""

import json
import math
import os
import sqlite3
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QLineEdit, QPushButton, QComboBox, QSpinBox,
    QProgressBar, QTextEdit, QGroupBox, QSplitter, QMessageBox,
)
from PySide6.QtCore import Qt, QUrl, QTimer
from PySide6.QtGui import QFont
from PySide6.QtWebEngineWidgets import QWebEngineView
from PySide6.QtWebChannel import QWebChannel


# Local storage (Mac/PC — the main library)
import platform
if platform.system() == "Darwin":
    LOCAL_MAPS_DIR = Path.home() / "Library/Application Support/MapsPersonal/Maps"
elif platform.system() == "Windows":
    LOCAL_MAPS_DIR = Path(os.environ.get("APPDATA", "")) / "MapsPersonal/Maps"
else:
    LOCAL_MAPS_DIR = Path.home() / ".local/share/MapsPersonal/Maps"

# iCloud (only for transfer to iPhone/iPad)
ICLOUD_MAPS_DIR = Path.home() / "Library/Mobile Documents/iCloud~com~jorge~mapspersonal2026/Documents/Maps"


# ---------------------------------------------------------------------------
# Geological map sources
# ---------------------------------------------------------------------------

@dataclass
class GeoSource:
    id: str
    name: str
    country: str
    scale: str
    attribution: str
    tile_url: str
    source_type: str       # "arcgis_rest" or "wms"
    format: str
    max_zoom: int
    min_zoom: int
    layers: str
    wms_version: str = "1.1.1"
    srs: str = "EPSG:3857"


SOURCES = {
    "spain": GeoSource(
        id="spain_igme", name="IGME MAGNA 50", country="Spain",
        scale="1:50,000", attribution="IGME",
        tile_url="https://mapas.igme.es/gis/rest/services/Cartografia_Geologica/IGME_MAGNA_50/MapServer/export",
        source_type="arcgis_rest", format="png", max_zoom=15, min_zoom=10,
        layers="show:0,2",
    ),
    "france": GeoSource(
        id="france_brgm", name="BRGM Carte Géologique",
        country="France", scale="1:50,000", attribution="BRGM",
        tile_url="http://geoservices.brgm.fr/geologie",
        source_type="wms", format="png", max_zoom=15, min_zoom=10,
        layers="SCAN_D_GEOL50",
    ),
    "belgium": GeoSource(
        id="belgium_gsb", name="GSB Geological Map",
        country="Belgium", scale="1:40,000",
        attribution="Royal Belgian Institute of Natural Sciences",
        tile_url="https://gisel.naturalsciences.be/geoserver/gisel/bel40k/ows",
        source_type="wms", format="png", max_zoom=15, min_zoom=10,
        layers="bel40k",
    ),
    "canada": GeoSource(
        id="canada_nrcan", name="NRCan Bedrock Geology",
        country="Canada", scale="1:5,000,000", attribution="NRCan",
        tile_url="https://maps-cartes.services.geo.ca/server_serveur/services/NRCan/gsc_bedrock_geology_en/MapServer/WMSServer",
        source_type="wms", format="png", max_zoom=12, min_zoom=6,
        layers="gsc_bedrock_geology_en", wms_version="1.3.0",
    ),
}

COUNTRY_BOUNDS = {
    "spain":   (35.7, -9.5, 43.8, 4.4),
    "france":  (41.3, -5.2, 51.1, 9.6),
    "belgium": (49.5, 2.5, 51.5, 6.4),
    "canada":  (41.7, -141.0, 83.1, -52.6),
}


def detect_country(lat, lon):
    """Detect country, preferring smaller/more specific regions over larger ones."""
    matches = []
    for country, (s, w, n, e) in COUNTRY_BOUNDS.items():
        if s <= lat <= n and w <= lon <= e:
            area = (n - s) * (e - w)
            matches.append((area, country))
    if not matches:
        return None
    # Return smallest matching region (most specific)
    matches.sort()
    return matches[0][1]


# ---------------------------------------------------------------------------
# Tile math
# ---------------------------------------------------------------------------

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


def count_tiles(min_lat, min_lon, max_lat, max_lon, min_zoom, max_zoom):
    total = 0
    for z in range(min_zoom, max_zoom + 1):
        x_min, y_max = lat_lon_to_tile(min_lat, min_lon, z)
        x_max, y_min = lat_lon_to_tile(max_lat, max_lon, z)
        total += (x_max - x_min + 1) * (y_max - y_min + 1)
    return total


# ---------------------------------------------------------------------------
# Geocoding
# ---------------------------------------------------------------------------

def geocode(query: str) -> list[dict]:
    """Search for places using Nominatim."""
    params = urllib.parse.urlencode({
        "q": query, "format": "json", "limit": 5,
        "addressdetails": 1,
    })
    url = f"https://nominatim.openstreetmap.org/search?{params}"
    req = urllib.request.Request(url, headers={"User-Agent": "MapsPersonal/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception:
        return []


# ---------------------------------------------------------------------------
# Leaflet map HTML
# ---------------------------------------------------------------------------

MAP_HTML = """
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9/dist/leaflet.js"></script>
<style>
  html, body, #map { margin: 0; padding: 0; width: 100%; height: 100%; }
</style>
</head>
<body>
<div id="map"></div>
<script>
var map = L.map('map').setView([40.38, -3.32], 10);

L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', {
    attribution: '© OpenStreetMap, © CARTO',
    subdomains: 'abcd',
    maxZoom: 19
}).addTo(map);

var rect = null;
var center = null;
var radiusKm = 5;

function updateRect(lat, lon, km) {
    center = [lat, lon];
    radiusKm = km;
    var dlat = km / 111.0;
    var dlon = km / (111.0 * Math.cos(lat * Math.PI / 180));
    var bounds = [[lat - dlat, lon - dlon], [lat + dlat, lon + dlon]];

    if (rect) {
        rect.setBounds(bounds);
    } else {
        rect = L.rectangle(bounds, {
            color: '#F44336', weight: 2, fillOpacity: 0.15
        }).addTo(map);
    }
}

function flyTo(lat, lon, zoom) {
    map.flyTo([lat, lon], zoom || 12);
    updateRect(lat, lon, radiusKm);
}

function setRadius(km) {
    radiusKm = km;
    if (center) {
        updateRect(center[0], center[1], km);
    }
}

function getBounds() {
    if (!center) return null;
    var lat = center[0], lon = center[1];
    var dlat = radiusKm / 111.0;
    var dlon = radiusKm / (111.0 * Math.cos(lat * Math.PI / 180));
    return JSON.stringify({
        south: lat - dlat, north: lat + dlat,
        west: lon - dlon, east: lon + dlon,
        lat: lat, lon: lon, radius: radiusKm
    });
}

// Click to set center
map.on('click', function(e) {
    updateRect(e.latlng.lat, e.latlng.lng, radiusKm);
    // Notify Python
    document.title = "CLICK:" + e.latlng.lat.toFixed(6) + "," + e.latlng.lng.toFixed(6);
});
</script>
</body>
</html>
"""


# ---------------------------------------------------------------------------
# Download worker (same as before)
# ---------------------------------------------------------------------------

class DownloadProcess:
    """Runs download_worker.py as a separate process to avoid WebEngine crashes."""

    def __init__(self, source, min_lat, min_lon, max_lat, max_lon, output_path):
        self.source = source
        self.min_lat, self.min_lon = min_lat, min_lon
        self.max_lat, self.max_lon = max_lat, max_lon
        self.output_path = output_path
        self.process = None

    def start(self, on_progress, on_finished, timer_parent=None):
        import subprocess
        self.on_progress = on_progress
        self.on_finished = on_finished

        src = self.source
        config = json.dumps({
            "output_path": self.output_path,
            "min_lat": self.min_lat, "min_lon": self.min_lon,
            "max_lat": self.max_lat, "max_lon": self.max_lon,
            "min_zoom": src.min_zoom, "max_zoom": src.max_zoom,
            "source_type": src.source_type,
            "tile_url": src.tile_url,
            "layers": src.layers,
            "format": src.format,
            "wms_version": src.wms_version,
            "srs": src.srs,
            "name": f"{src.name} ({src.scale})",
            "attribution": src.attribution,
        })

        worker_script = str(Path(__file__).parent / "download_worker.py")

        # Write config to a temp file instead of stdin (more reliable)
        self._config_file = self.output_path + ".job.json"
        with open(self._config_file, "w") as f:
            f.write(config)

        # Progress file: worker writes JSON lines here
        self._progress_file = self.output_path + ".progress"
        with open(self._progress_file, "w") as f:
            pass  # create empty

        # Find venv python
        script_dir = Path(__file__).resolve().parent
        venv_python = None
        for parent in script_dir.parents:
            candidate = parent / ".venv" / "bin" / "python3"
            if candidate.exists():
                venv_python = str(candidate)
                break
        if venv_python is None:
            venv_python = sys.executable

        self.process = subprocess.Popen(
            [venv_python, worker_script, self._config_file, self._progress_file],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        # Poll progress file with QTimer
        self._lines_read = 0
        self._timer = QTimer(timer_parent)
        self._timer.timeout.connect(self._check_progress)
        self._timer.start(500)  # check every 500ms

    def _check_progress(self):
        # Read new lines from progress file
        try:
            with open(self._progress_file, "r") as f:
                lines = f.readlines()
        except Exception:
            return

        for line in lines[self._lines_read:]:
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
                if "done" in data:
                    self._timer.stop()
                    msg = f"Done! {data['downloaded']} tiles ({data['errors']} errors). {data['size_mb']} MB"
                    self.on_finished(msg)
                    self._cleanup()
                    return
                else:
                    current = data["downloaded"] + data["errors"]
                    total = data["total"]
                    msg = f"Zoom {data['zoom']}: {data['downloaded']} ok, {data['errors']} err"
                    self.on_progress(current, total, msg)
            except (json.JSONDecodeError, KeyError):
                pass
        self._lines_read = len(lines)

        # Check if process died
        if self.process.poll() is not None and self._lines_read == len(lines):
            self._timer.stop()
            rc = self.process.returncode
            if rc != 0:
                stderr = self.process.stderr.read().decode(errors="ignore")
                self.on_finished(f"Process error (code {rc}): {stderr[:300]}")
            self._cleanup()

    def _cleanup(self):
        for f in [self._config_file, self._progress_file]:
            try:
                os.unlink(f)
            except Exception:
                pass

    def cancel(self):
        if self.process:
            self.process.terminate()


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

class GeologyManagerWidget(QWidget):
    def __init__(self):
        super().__init__()
        self.worker = None
        self.selected_lat = 40.38
        self.selected_lon = -3.32

        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(8)

        # Title
        title = QLabel("Geological Map Manager")
        title.setFont(QFont("", 18, QFont.Weight.Bold))
        layout.addWidget(title)

        # Search bar
        search_layout = QHBoxLayout()
        search_layout.addWidget(QLabel("Search place:"))
        self.search_input = QLineEdit()
        self.search_input.setPlaceholderText("e.g. Chamonix, Dolomites, Sierra de Guadarrama...")
        self.search_input.returnPressed.connect(self.on_search)
        search_layout.addWidget(self.search_input, 1)

        self.search_btn = QPushButton("Search")
        self.search_btn.clicked.connect(self.on_search)
        search_layout.addWidget(self.search_btn)

        self.results_combo = QComboBox()
        self.results_combo.setMinimumWidth(300)
        self.results_combo.currentIndexChanged.connect(self.on_result_selected)
        self.results_combo.hide()
        search_layout.addWidget(self.results_combo)

        layout.addLayout(search_layout)

        # Main splitter: map | controls
        splitter = QSplitter(Qt.Orientation.Horizontal)

        # Map
        self.map_view = QWebEngineView()
        self.map_view.setHtml(MAP_HTML, QUrl("https://localhost/"))
        self.map_view.titleChanged.connect(self.on_map_title_changed)
        splitter.addWidget(self.map_view)

        # Right panel
        right = QWidget()
        right_layout = QVBoxLayout(right)
        right_layout.setContentsMargins(8, 0, 0, 0)

        # Coverage info
        self.coverage_label = QLabel("Click the map or search a place to begin")
        self.coverage_label.setWordWrap(True)
        self.coverage_label.setFont(QFont("", 12))
        self.coverage_label.setStyleSheet("padding: 8px; background: #2b2b2b; border-radius: 6px;")
        right_layout.addWidget(self.coverage_label)

        # Source
        src_layout = QHBoxLayout()
        src_layout.addWidget(QLabel("Source:"))
        self.source_combo = QComboBox()
        for key, src in SOURCES.items():
            self.source_combo.addItem(f"{src.country} — {src.name} ({src.scale})", key)
        src_layout.addWidget(self.source_combo, 1)
        right_layout.addLayout(src_layout)

        # Radius
        rad_layout = QHBoxLayout()
        rad_layout.addWidget(QLabel("Radius (km):"))
        self.radius_spin = QSpinBox()
        self.radius_spin.setRange(1, 100)
        self.radius_spin.setValue(5)
        self.radius_spin.valueChanged.connect(self.on_radius_changed)
        rad_layout.addWidget(self.radius_spin)

        self.estimate_label = QLabel("")
        self.estimate_label.setStyleSheet("color: #888;")
        rad_layout.addWidget(self.estimate_label, 1)
        right_layout.addLayout(rad_layout)

        # Download
        btn_layout = QHBoxLayout()
        self.download_btn = QPushButton("Download Geological Map")
        self.download_btn.setStyleSheet("font-size: 13px; padding: 8px 16px; background: #4CAF50; color: white; border-radius: 4px;")
        self.download_btn.clicked.connect(self.on_download)
        btn_layout.addWidget(self.download_btn)

        self.cancel_btn = QPushButton("Cancel")
        self.cancel_btn.setEnabled(False)
        self.cancel_btn.clicked.connect(self.on_cancel)
        btn_layout.addWidget(self.cancel_btn)
        right_layout.addLayout(btn_layout)

        # Progress
        self.progress_bar = QProgressBar()
        self.progress_bar.hide()
        right_layout.addWidget(self.progress_bar)

        # Downloaded maps library
        lib_group = QGroupBox("Downloaded Maps (local)")
        lib_layout = QVBoxLayout(lib_group)

        self.maps_list = QComboBox()
        self.maps_list.setMinimumWidth(280)
        lib_layout.addWidget(self.maps_list)

        lib_btn_layout = QHBoxLayout()
        self.transfer_btn = QPushButton("Send to iPhone")
        self.transfer_btn.setStyleSheet("font-size: 12px; padding: 6px 12px;")
        self.transfer_btn.clicked.connect(self.on_transfer)
        lib_btn_layout.addWidget(self.transfer_btn)

        self.refresh_lib_btn = QPushButton("Refresh")
        self.refresh_lib_btn.clicked.connect(self.load_maps_library)
        lib_btn_layout.addWidget(self.refresh_lib_btn)

        self.delete_map_btn = QPushButton("Delete")
        self.delete_map_btn.setStyleSheet("color: #F44336;")
        self.delete_map_btn.clicked.connect(self.on_delete_map)
        lib_btn_layout.addWidget(self.delete_map_btn)

        lib_layout.addLayout(lib_btn_layout)

        self.lib_info = QLabel("")
        self.lib_info.setStyleSheet("color: #888; font-size: 11px;")
        self.lib_info.setWordWrap(True)
        lib_layout.addWidget(self.lib_info)

        right_layout.addWidget(lib_group)

        # Log
        self.log = QTextEdit()
        self.log.setReadOnly(True)
        self.log.setMaximumHeight(150)
        self.log.setFont(QFont("Menlo", 10))
        right_layout.addWidget(self.log)

        right.setMinimumWidth(350)
        splitter.addWidget(right)
        splitter.setSizes([700, 380])

        layout.addWidget(splitter, 1)

        self.update_estimate()
        self.load_maps_library()

    # -- Search --

    def on_search(self):
        query = self.search_input.text().strip()
        if not query:
            return

        self.search_btn.setEnabled(False)
        self.search_btn.setText("...")

        results = geocode(query)

        self.search_btn.setEnabled(True)
        self.search_btn.setText("Search")

        if not results:
            self.coverage_label.setText("No results found")
            return

        self.search_results = results
        self.results_combo.clear()
        for r in results:
            display = r.get("display_name", "?")
            self.results_combo.addItem(display[:80])
        self.results_combo.show()

        # Auto-select first result
        self.results_combo.setCurrentIndex(0)

    def on_result_selected(self, idx):
        if idx < 0 or not hasattr(self, "search_results"):
            return
        r = self.search_results[idx]
        lat = float(r["lat"])
        lon = float(r["lon"])
        self.selected_lat = lat
        self.selected_lon = lon

        # Fly map to location
        self.map_view.page().runJavaScript(f"flyTo({lat}, {lon}, 12);")
        self.update_coverage(lat, lon)
        self.update_estimate()

    # -- Map interaction --

    def on_map_title_changed(self, title):
        """Receive click events from the map via title change hack."""
        if title.startswith("CLICK:"):
            parts = title[6:].split(",")
            lat, lon = float(parts[0]), float(parts[1])
            self.selected_lat = lat
            self.selected_lon = lon
            self.update_coverage(lat, lon)
            self.update_estimate()

    def on_radius_changed(self, value):
        self.map_view.page().runJavaScript(f"setRadius({value});")
        self.update_estimate()

    # -- Coverage detection --

    def update_coverage(self, lat, lon):
        country = detect_country(lat, lon)
        if country:
            src = SOURCES[country]
            self.coverage_label.setText(
                f"<b style='color: #4CAF50;'>Coverage available</b><br>"
                f"<b>{src.country}</b> — {src.name}<br>"
                f"Scale: {src.scale}<br>"
                f"Position: {lat:.4f}, {lon:.4f}"
            )
            # Auto-select source
            for i in range(self.source_combo.count()):
                if self.source_combo.itemData(i) == country:
                    self.source_combo.setCurrentIndex(i)
                    break
        else:
            self.coverage_label.setText(
                f"<b style='color: #F44336;'>No geological map coverage</b><br>"
                f"Position: {lat:.4f}, {lon:.4f}<br>"
                f"No geological WMS service found for this area.<br>"
                f"You can still try a manual source from the dropdown."
            )

    def update_estimate(self):
        key = self.source_combo.currentData()
        if not key or key not in SOURCES:
            return
        src = SOURCES[key]
        radius = self.radius_spin.value()
        lat = self.selected_lat
        dlat = radius / 111.0
        dlon = radius / (111.0 * math.cos(math.radians(lat)))
        total = count_tiles(lat - dlat, self.selected_lon - dlon,
                            lat + dlat, self.selected_lon + dlon,
                            src.min_zoom, src.max_zoom)
        est_mb = total * 15 / 1024
        self.estimate_label.setText(f"~{total} tiles (~{est_mb:.0f} MB)")

    # -- Download --

    def on_download(self):
        key = self.source_combo.currentData()
        if not key or key not in SOURCES:
            return

        src = SOURCES[key]
        lat, lon = self.selected_lat, self.selected_lon
        radius = self.radius_spin.value()
        dlat = radius / 111.0
        dlon = radius / (111.0 * math.cos(math.radians(lat)))

        LOCAL_MAPS_DIR.mkdir(parents=True, exist_ok=True)
        filename = f"{src.id}_{lat:.2f}_{lon:.2f}_r{radius}km.mbtiles"
        output = str(LOCAL_MAPS_DIR / filename)

        total_est = count_tiles(lat - dlat, self.selected_lon - dlon,
                                lat + dlat, self.selected_lon + dlon,
                                src.min_zoom, src.max_zoom)
        self.log.clear()
        self.log.append(f"Source: {src.name} ({src.country})")
        self.log.append(f"Center: {lat:.4f}, {lon:.4f} | Radius: {radius} km")
        self.log.append(f"Output: {filename}")
        self.log.append(f"Tiles: ~{total_est}")
        self.log.append("")

        self.progress_bar.setRange(0, total_est)
        self.progress_bar.setValue(0)
        self.progress_bar.setFormat("0% — Starting download...")
        self.progress_bar.show()
        self.download_btn.setEnabled(False)
        self.cancel_btn.setEnabled(True)

        self.worker = DownloadProcess(src, lat - dlat, self.selected_lon - dlon,
                                      lat + dlat, self.selected_lon + dlon, output)
        self.worker.start(self.on_progress, self.on_finished, timer_parent=self)

    def on_cancel(self):
        if self.worker:
            self.worker.cancel()

    def _safe_progress(self, current, total, message):
        """Thread-safe: schedule UI update on main thread."""
        QTimer.singleShot(0, lambda: self.on_progress(current, total, message))

    def _safe_finished(self, message):
        """Thread-safe: schedule UI update on main thread."""
        QTimer.singleShot(0, lambda: self.on_finished(message))

    def on_progress(self, current, total, message):
        self.progress_bar.setMaximum(total)
        self.progress_bar.setValue(current)
        pct = int(current * 100 / total) if total > 0 else 0
        self.progress_bar.setFormat(f"{pct}% — {current}/{total} tiles — {message}")

    def on_finished(self, message):
        self.log.append(f"\n{message}")
        self.progress_bar.hide()
        self.download_btn.setEnabled(True)
        self.cancel_btn.setEnabled(False)
        self.worker = None
        self.load_maps_library()

    # -- Maps library --

    def load_maps_library(self):
        self.maps_list.clear()
        if not LOCAL_MAPS_DIR.exists():
            self.lib_info.setText("No maps downloaded yet")
            return

        files = sorted(LOCAL_MAPS_DIR.glob("*.mbtiles"), reverse=True)
        if not files:
            self.lib_info.setText("No maps downloaded yet")
            return

        total_size = 0
        for f in files:
            size = f.stat().st_size
            total_size += size
            size_mb = size / (1024 * 1024)
            self.maps_list.addItem(f"{f.stem}  ({size_mb:.1f} MB)", str(f))

        # Check which are already on iPhone
        icloud_files = set()
        if ICLOUD_MAPS_DIR.exists():
            icloud_files = {f.name for f in ICLOUD_MAPS_DIR.glob("*.mbtiles")}

        on_phone = sum(1 for f in files if f.name in icloud_files)
        self.lib_info.setText(
            f"{len(files)} maps ({total_size / (1024*1024):.0f} MB total) · "
            f"{on_phone} on iPhone"
        )

    def on_transfer(self):
        idx = self.maps_list.currentIndex()
        if idx < 0:
            return

        src_path = Path(self.maps_list.currentData())
        if not src_path.exists():
            QMessageBox.warning(self, "Error", "Map file not found")
            return

        if platform.system() != "Darwin":
            QMessageBox.information(self, "Transfer",
                "iCloud transfer is only available on macOS.\n"
                "On other platforms, connect your iPhone and copy the .mbtiles file "
                "to the MapsPersonal app via Finder/iTunes file sharing.")
            return

        ICLOUD_MAPS_DIR.mkdir(parents=True, exist_ok=True)
        dest = ICLOUD_MAPS_DIR / src_path.name

        import shutil
        try:
            shutil.copy2(str(src_path), str(dest))
            size_mb = dest.stat().st_size / (1024 * 1024)
            self.log.append(f"\nTransferred to iPhone: {src_path.name} ({size_mb:.1f} MB)")
            self.load_maps_library()
        except Exception as e:
            QMessageBox.warning(self, "Error", f"Transfer failed: {e}")

    def on_delete_map(self):
        idx = self.maps_list.currentIndex()
        if idx < 0:
            return

        src_path = Path(self.maps_list.currentData())
        name = src_path.name

        reply = QMessageBox.question(
            self, "Delete Map",
            f"Delete {name} from local storage?\n"
            f"(iPhone copy will not be affected)",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if reply == QMessageBox.StandardButton.Yes:
            try:
                src_path.unlink()
                self.log.append(f"Deleted: {name}")
                self.load_maps_library()
            except Exception as e:
                QMessageBox.warning(self, "Error", f"Delete failed: {e}")
