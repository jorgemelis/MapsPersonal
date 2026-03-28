"""Track Manager module — list, analyze, and visualize GPX tracks."""

import math
import sys
from datetime import datetime
from pathlib import Path
from io import BytesIO

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_qtagg import FigureCanvasQTAgg as FigureCanvas

from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QSplitter,
    QTableWidget, QTableWidgetItem, QHeaderView,
    QLabel, QComboBox, QPushButton,
)
from PySide6.QtCore import Qt, QThread, Signal
from PySide6.QtGui import QFont

from gpx_parser import parse_gpx, Point, haversine, smooth, filter_spikes

# iCloud tracks directory
TRACKS_DIR = Path.home() / "Library/Mobile Documents/iCloud~com~jorge~mapspersonal2026/Documents/Tracks"

MOVE_THRESHOLD = 0.14  # m/s


class AnalysisWorker(QThread):
    """Run GPX analysis in background thread."""
    finished = Signal(dict)

    def __init__(self, gpx_path: Path, ele_source: str = "gps"):
        super().__init__()
        self.gpx_path = gpx_path
        self.ele_source = ele_source

    def run(self):
        name, points = parse_gpx(str(self.gpx_path))
        if len(points) < 2:
            self.finished.emit({"error": "Track too short"})
            return

        stats = compute_full_stats(name, points, self.ele_source)
        self.finished.emit(stats)


def compute_full_stats(name, points, ele_source="gps"):
    n = len(points)

    # Cumulative distance
    cum_dist = [0.0]
    for i in range(1, n):
        cum_dist.append(cum_dist[-1] + haversine(
            points[i - 1].lat, points[i - 1].lon,
            points[i].lat, points[i].lon))
    cum_dist = np.array(cum_dist)

    # Speeds
    speeds = [0.0]
    for i in range(1, n):
        dt = (points[i].time - points[i - 1].time).total_seconds()
        d = cum_dist[i] - cum_dist[i - 1]
        speeds.append(d / dt if dt > 0 else 0)
    speeds = np.array(speeds)

    total_dist = cum_dist[-1]
    duration = (points[-1].time - points[0].time).total_seconds()

    # Moving time
    moving = sum(
        (points[i].time - points[i - 1].time).total_seconds()
        for i in range(1, n) if speeds[i] > MOVE_THRESHOLD
    )

    # Elevation
    eles_raw = np.array([p.ele if p.ele is not None else np.nan for p in points])
    eles_filtered = filter_spikes(eles_raw, max_jump=5.0)
    eles_smooth = smooth(eles_filtered, window=25)

    gain = loss = 0.0
    valid = eles_smooth[~np.isnan(eles_smooth)]
    for i in range(1, len(valid)):
        d = valid[i] - valid[i - 1]
        if d > 0:
            gain += d
        else:
            loss -= d

    # Splits
    splits = []
    km_idx = 0
    split_start_i = 0
    for i in range(1, n):
        while cum_dist[i] >= (km_idx + 1) * 1000 and km_idx * 1000 < total_dist:
            km_end_i = i
            split_dist = min((km_idx + 1) * 1000, total_dist) - km_idx * 1000
            split_moving = sum(
                (points[j].time - points[j - 1].time).total_seconds()
                for j in range(split_start_i + 1, km_end_i + 1)
                if speeds[j] > MOVE_THRESHOLD
            )
            pace = split_moving / (split_dist / 1000) if split_dist > 0 else 0
            start_ele = eles_smooth[split_start_i] if not np.isnan(eles_smooth[split_start_i]) else 0
            end_ele = eles_smooth[km_end_i] if not np.isnan(eles_smooth[km_end_i]) else 0
            splits.append({"km": km_idx + 1, "pace_s": pace, "ele_change": end_ele - start_ele})
            km_idx += 1
            split_start_i = i

    # Last partial km
    if split_start_i < n - 1:
        remaining = total_dist - km_idx * 1000
        if remaining > 50:
            split_moving = sum(
                (points[j].time - points[j - 1].time).total_seconds()
                for j in range(split_start_i + 1, n)
                if speeds[j] > MOVE_THRESHOLD
            )
            pace = split_moving / (remaining / 1000) if remaining > 0 else 0
            s_ele = eles_smooth[split_start_i] if not np.isnan(eles_smooth[split_start_i]) else 0
            e_ele = eles_smooth[-1] if not np.isnan(eles_smooth[-1]) else 0
            splits.append({"km": km_idx + 1, "pace_s": pace, "ele_change": e_ele - s_ele, "partial_m": remaining})

    # HR
    hrs = [p.hr for p in points if p.hr is not None]
    hr_avg = int(np.mean(hrs)) if hrs else None
    hr_max = max(hrs) if hrs else None

    return {
        "name": name,
        "points": points,
        "cum_dist": cum_dist,
        "speeds": speeds,
        "eles_raw": eles_raw,
        "eles_smooth": eles_smooth,
        "total_dist": total_dist,
        "duration": duration,
        "moving": moving,
        "ele_gain": gain,
        "ele_loss": loss,
        "ele_min": float(np.nanmin(eles_smooth)) if not np.all(np.isnan(eles_smooth)) else None,
        "ele_max": float(np.nanmax(eles_smooth)) if not np.all(np.isnan(eles_smooth)) else None,
        "splits": splits,
        "hr_avg": hr_avg,
        "hr_max": hr_max,
        "n_points": n,
    }


def fmt_duration(s):
    h, m, sec = int(s // 3600), int((s % 3600) // 60), int(s % 60)
    return f"{h}h {m:02d}m {sec:02d}s"


def fmt_pace(sec_per_km):
    m, s = int(sec_per_km // 60), int(sec_per_km % 60)
    return f"{m}:{s:02d} /km"


class TrackManagerWidget(QWidget):
    def __init__(self):
        super().__init__()
        self.worker = None
        self.current_stats = None

        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 16, 16, 16)

        # Header
        header = QHBoxLayout()
        title = QLabel("Track Manager")
        title.setFont(QFont("", 20, QFont.Weight.Bold))
        header.addWidget(title)
        header.addStretch()

        self.refresh_btn = QPushButton("Refresh")
        self.refresh_btn.clicked.connect(self.load_tracks)
        header.addWidget(self.refresh_btn)

        self.ele_combo = QComboBox()
        self.ele_combo.addItems(["GPS", "DEM (SRTM 30m)"])
        self.ele_combo.setFixedWidth(140)
        header.addWidget(QLabel("Elevation:"))
        header.addWidget(self.ele_combo)

        layout.addLayout(header)

        # Splitter: track list | analysis
        splitter = QSplitter(Qt.Orientation.Horizontal)

        # Left: track list
        self.table = QTableWidget()
        self.table.setColumnCount(4)
        self.table.setHorizontalHeaderLabels(["Track", "Date", "Size", "Points"])
        self.table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QTableWidget.SelectionMode.SingleSelection)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.table.currentCellChanged.connect(lambda row, *_: self.on_track_selected(row))
        self.table.setMinimumWidth(350)
        splitter.addWidget(self.table)

        # Right: analysis panel
        right_panel = QWidget()
        self.right_layout = QVBoxLayout(right_panel)
        self.right_layout.setContentsMargins(8, 0, 0, 0)

        self.status_label = QLabel("Select a track to analyze")
        self.status_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.status_label.setStyleSheet("color: #888; font-size: 16px;")
        self.right_layout.addWidget(self.status_label)

        # Stats summary
        self.stats_label = QLabel()
        self.stats_label.setFont(QFont("", 12))
        self.stats_label.setWordWrap(True)
        self.stats_label.hide()
        self.right_layout.addWidget(self.stats_label)

        # Chart canvas
        self.figure = plt.figure(figsize=(10, 8))
        self.canvas = FigureCanvas(self.figure)
        self.canvas.hide()
        self.right_layout.addWidget(self.canvas, 1)

        splitter.addWidget(right_panel)
        splitter.setSizes([350, 850])

        layout.addWidget(splitter, 1)

        # Load tracks
        self.gpx_files = []
        self.load_tracks()

    def load_tracks(self):
        self.table.setRowCount(0)
        self.gpx_files = []

        if not TRACKS_DIR.exists():
            return

        files = sorted(TRACKS_DIR.glob("*.gpx"), reverse=True)
        self.gpx_files = files

        self.table.setRowCount(len(files))
        for row, f in enumerate(files):
            name = f.stem
            stat = f.stat()
            size = f"{stat.st_size / 1024:.0f} KB"
            date = datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M")

            # Quick count of points
            content = f.read_text(errors="ignore")
            points = content.count("<trkpt")

            self.table.setItem(row, 0, QTableWidgetItem(name))
            self.table.setItem(row, 1, QTableWidgetItem(date))
            self.table.setItem(row, 2, QTableWidgetItem(size))
            self.table.setItem(row, 3, QTableWidgetItem(str(points)))

    def on_track_selected(self, row):
        if row < 0 or row >= len(self.gpx_files):
            return

        gpx_path = self.gpx_files[row]
        self.status_label.setText(f"Analyzing {gpx_path.name}...")
        self.status_label.show()
        self.stats_label.hide()
        self.canvas.hide()

        ele_source = "dem" if self.ele_combo.currentIndex() == 1 else "gps"
        self.worker = AnalysisWorker(gpx_path, ele_source)
        self.worker.finished.connect(self.on_analysis_done)
        self.worker.start()

    def on_analysis_done(self, stats):
        if "error" in stats:
            self.status_label.setText(f"Error: {stats['error']}")
            return

        self.current_stats = stats
        self.status_label.hide()

        # Stats summary
        lines = []
        lines.append(f"<b>{stats['name']}</b>")
        lines.append(f"Distance: <b>{stats['total_dist']/1000:.2f} km</b> | "
                      f"Duration: <b>{fmt_duration(stats['duration'])}</b> | "
                      f"Moving: <b>{fmt_duration(stats['moving'])}</b>")

        if stats['total_dist'] > 0:
            pace = stats['moving'] / stats['total_dist'] * 1000
            lines.append(f"Pace: <b>{fmt_pace(pace)}</b> | "
                          f"Elevation: <b>+{stats['ele_gain']:.0f}m / -{stats['ele_loss']:.0f}m</b>")

        if stats['hr_avg']:
            lines.append(f"HR avg: <b>{stats['hr_avg']} bpm</b> | HR max: <b>{stats['hr_max']} bpm</b>")

        # Splits
        if stats['splits']:
            lines.append("")
            for sp in stats['splits']:
                km_label = f"KM {sp['km']}"
                if 'partial_m' in sp:
                    km_label += f" ({sp['partial_m']:.0f}m)"
                ele_str = f"+{sp['ele_change']:.0f}" if sp['ele_change'] >= 0 else f"{sp['ele_change']:.0f}"
                lines.append(f"  {km_label}: {fmt_pace(sp['pace_s'])}  {ele_str} m")

        self.stats_label.setText("<br>".join(lines))
        self.stats_label.show()

        # Draw charts
        self.draw_charts(stats)

    def draw_charts(self, stats):
        self.figure.clear()
        points = stats["points"]
        n = len(points)
        cum_dist = stats["cum_dist"]
        dist_km = cum_dist / 1000
        minutes = np.array([(p.time - points[0].time).total_seconds() / 60 for p in points])
        has_hr = stats["hr_avg"] is not None

        n_rows = 2 if not has_hr else 3

        # Map
        ax = self.figure.add_subplot(n_rows, 2, 1)
        lons = [p.lon for p in points]
        lats = [p.lat for p in points]
        ax.plot(lons, lats, color="#2196F3", linewidth=1.5)
        ax.plot(lons[0], lats[0], "go", markersize=8, label="Start")
        ax.plot(lons[-1], lats[-1], "rs", markersize=8, label="End")
        ax.set_title("Route")
        ax.legend(fontsize=8)
        ax.set_aspect("equal")
        ax.grid(True, alpha=0.3)

        # Elevation
        ax = self.figure.add_subplot(n_rows, 2, 2)
        eles = stats["eles_smooth"]
        ax.fill_between(dist_km, eles, alpha=0.3, color="#4CAF50")
        ax.plot(dist_km, eles, color="#4CAF50", linewidth=1.5)
        ele_range = np.nanmax(eles) - np.nanmin(eles)
        ax.set_ylim(np.nanmin(eles) - max(ele_range * 0.15, 5),
                     np.nanmax(eles) + max(ele_range * 0.15, 5))
        ax.set_xlabel("Distance (km)")
        ax.set_ylabel("m")
        ax.set_title(f"Elevation — +{stats['ele_gain']:.0f}m / -{stats['ele_loss']:.0f}m")
        ax.grid(True, alpha=0.3)

        # Speed
        ax = self.figure.add_subplot(n_rows, 2, 3)
        speeds_kmh = stats["speeds"] * 3.6
        speeds_smooth = smooth(speeds_kmh, window=15)
        ax.plot(minutes, speeds_smooth, color="#FF9800", linewidth=1.5)
        avg = stats["total_dist"] / stats["moving"] * 3.6 if stats["moving"] > 0 else 0
        ax.axhline(y=avg, color="#F44336", linestyle="--", label=f"Avg: {avg:.1f} km/h")
        ax.set_xlabel("Time (min)")
        ax.set_ylabel("km/h")
        ax.set_title("Speed")
        ax.legend(fontsize=8)
        ax.grid(True, alpha=0.3)
        ax.set_ylim(bottom=0)

        # Pace per km (bar chart)
        ax = self.figure.add_subplot(n_rows, 2, 4)
        if stats["splits"]:
            kms = [sp["km"] for sp in stats["splits"]]
            paces_min = [sp["pace_s"] / 60 for sp in stats["splits"]]
            colors = ["#4CAF50" if sp.get("ele_change", 0) <= 0 else "#FF5722" for sp in stats["splits"]]
            bars = ax.bar(kms, paces_min, color=colors, alpha=0.8)
            ax.set_xlabel("KM")
            ax.set_ylabel("min/km")
            ax.set_title("Pace per KM")
            ax.grid(True, alpha=0.3, axis="y")

            # Label each bar
            for bar, sp in zip(bars, stats["splits"]):
                m = int(sp["pace_s"] // 60)
                s = int(sp["pace_s"] % 60)
                ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height(),
                        f"{m}:{s:02d}", ha="center", va="bottom", fontsize=8)

        # HR
        if has_hr:
            hrs_all = np.array([p.hr if p.hr is not None else np.nan for p in points])

            ax = self.figure.add_subplot(n_rows, 2, 5)
            valid_hr = ~np.isnan(hrs_all)
            if valid_hr.sum() > 0:
                hr_smooth = smooth(hrs_all, window=15)
                ax.plot(minutes, hr_smooth, color="#D32F2F", linewidth=1.5)
                ax.axhline(y=stats["hr_avg"], color="#FF9800", linestyle="--",
                           label=f"Avg: {stats['hr_avg']} bpm")
                ax.legend(fontsize=8)
            ax.set_xlabel("Time (min)")
            ax.set_ylabel("bpm")
            ax.set_title("Heart Rate")
            ax.grid(True, alpha=0.3)

            ax = self.figure.add_subplot(n_rows, 2, 6)
            if valid_hr.sum() > 0:
                ax.plot(dist_km, hr_smooth, color="#D32F2F", linewidth=1.5)
            ax.set_xlabel("Distance (km)")
            ax.set_ylabel("bpm")
            ax.set_title("HR vs Distance")
            ax.grid(True, alpha=0.3)

        self.figure.tight_layout(pad=2.0)
        self.canvas.show()
        self.canvas.draw()
