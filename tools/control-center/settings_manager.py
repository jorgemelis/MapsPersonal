"""Settings Manager — sync user profile between Mac and iPhone via iCloud."""

import json
import os
from pathlib import Path

from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QFormLayout,
    QLabel, QSpinBox, QDoubleSpinBox, QCheckBox,
    QPushButton, QGroupBox, QFrame, QMessageBox,
)
from PySide6.QtCore import Qt


# iCloud container path on macOS
ICLOUD_CONTAINER = Path.home() / "Library/Mobile Documents/iCloud~com~jorge~mapspersonal2026/Documents"
PROFILE_FILE = ICLOUD_CONTAINER / "profile.json"

DEFAULT_ZONES = [
    {"name": "Recovery", "minPct": 50, "maxPct": 60},
    {"name": "Aerobic", "minPct": 60, "maxPct": 70},
    {"name": "Tempo", "minPct": 70, "maxPct": 80},
    {"name": "Threshold", "minPct": 80, "maxPct": 90},
    {"name": "Maximum", "minPct": 90, "maxPct": 100},
]


def load_profile():
    """Load profile from iCloud JSON."""
    if PROFILE_FILE.exists():
        try:
            with open(PROFILE_FILE) as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            pass
    return {}


def save_profile(data):
    """Save profile to iCloud JSON."""
    ICLOUD_CONTAINER.mkdir(parents=True, exist_ok=True)
    with open(PROFILE_FILE, "w") as f:
        json.dump(data, f, indent=2)


class SettingsManager(QWidget):
    def __init__(self):
        super().__init__()
        self.profile = load_profile()
        self.init_ui()
        self.populate()

    def init_ui(self):
        layout = QVBoxLayout(self)

        # Personal Data
        personal_group = QGroupBox("Personal Data")
        personal_form = QFormLayout()

        self.age_check = QCheckBox()
        self.age_spin = QSpinBox()
        self.age_spin.setRange(10, 120)
        self.age_spin.setSuffix(" years")
        self.age_check.toggled.connect(self.age_spin.setEnabled)
        age_row = QHBoxLayout()
        age_row.addWidget(self.age_check)
        age_row.addWidget(self.age_spin, 1)
        personal_form.addRow("Age:", age_row)

        self.weight_check = QCheckBox()
        self.weight_spin = QDoubleSpinBox()
        self.weight_spin.setRange(30, 200)
        self.weight_spin.setSingleStep(0.5)
        self.weight_spin.setDecimals(1)
        self.weight_spin.setSuffix(" kg")
        self.weight_check.toggled.connect(self.weight_spin.setEnabled)
        weight_row = QHBoxLayout()
        weight_row.addWidget(self.weight_check)
        weight_row.addWidget(self.weight_spin, 1)
        personal_form.addRow("Weight:", weight_row)

        self.height_check = QCheckBox()
        self.height_spin = QDoubleSpinBox()
        self.height_spin.setRange(1.0, 2.5)
        self.height_spin.setSingleStep(0.01)
        self.height_spin.setDecimals(2)
        self.height_spin.setSuffix(" m")
        self.height_check.toggled.connect(self.height_spin.setEnabled)
        height_row = QHBoxLayout()
        height_row.addWidget(self.height_check)
        height_row.addWidget(self.height_spin, 1)
        personal_form.addRow("Height:", height_row)

        self.waist_check = QCheckBox()
        self.waist_spin = QDoubleSpinBox()
        self.waist_spin.setRange(50, 200)
        self.waist_spin.setSingleStep(0.5)
        self.waist_spin.setDecimals(1)
        self.waist_spin.setSuffix(" cm")
        self.waist_check.toggled.connect(self.waist_spin.setEnabled)
        waist_row = QHBoxLayout()
        waist_row.addWidget(self.waist_check)
        waist_row.addWidget(self.waist_spin, 1)
        personal_form.addRow("Waist:", waist_row)

        personal_group.setLayout(personal_form)
        layout.addWidget(personal_group)

        # Heart Rate
        hr_group = QGroupBox("Heart Rate")
        hr_layout = QVBoxLayout()

        hr_form = QFormLayout()
        self.hr_calculated = QLabel("—")
        hr_form.addRow("Calculated Max HR (Tanaka):", self.hr_calculated)

        self.hr_override_check = QCheckBox("Custom Max HR")
        self.hr_override_check.toggled.connect(self.on_hr_override_toggle)
        hr_form.addRow(self.hr_override_check)

        self.hr_override_spin = QSpinBox()
        self.hr_override_spin.setRange(100, 220)
        self.hr_override_spin.setSuffix(" bpm")
        self.hr_override_spin.setEnabled(False)
        hr_form.addRow("Max HR:", self.hr_override_spin)

        hr_layout.addLayout(hr_form)

        # Zones display
        self.zones_label = QLabel()
        self.zones_label.setStyleSheet("font-family: 'Menlo', 'Courier New', monospace; font-size: 12px;")
        hr_layout.addWidget(self.zones_label)

        hr_group.setLayout(hr_layout)
        layout.addWidget(hr_group)

        # Body Metrics (calculated, read-only)
        metrics_group = QGroupBox("Body Metrics (calculated)")
        metrics_form = QFormLayout()

        bmi_row = QHBoxLayout()
        self.bmi_label = QLabel("—")
        self.bmi_tag = QLabel("")
        bmi_row.addWidget(self.bmi_label)
        bmi_row.addWidget(self.bmi_tag)
        bmi_row.addStretch()
        metrics_form.addRow("BMI (weight/height²):", bmi_row)

        bri_row = QHBoxLayout()
        self.bri_label = QLabel("—")
        self.bri_tag = QLabel("")
        bri_row.addWidget(self.bri_label)
        bri_row.addWidget(self.bri_tag)
        bri_row.addStretch()
        metrics_form.addRow("BRI (waist/height roundness):", bri_row)

        metrics_group.setLayout(metrics_form)
        layout.addWidget(metrics_group)

        # Track Recording
        track_group = QGroupBox("Track Recording")
        track_form = QFormLayout()

        self.autosave_check = QCheckBox("Auto-save to iCloud")
        track_form.addRow(self.autosave_check)

        self.temp_interval_spin = QSpinBox()
        self.temp_interval_spin.setRange(1, 30)
        self.temp_interval_spin.setSuffix(" min")
        track_form.addRow("Temp interval:", self.temp_interval_spin)

        self.temp_elev_spin = QSpinBox()
        self.temp_elev_spin.setRange(50, 500)
        self.temp_elev_spin.setSingleStep(50)
        self.temp_elev_spin.setSuffix(" m")
        track_form.addRow("Temp elevation threshold:", self.temp_elev_spin)

        track_group.setLayout(track_form)
        layout.addWidget(track_group)

        # Buttons
        btn_layout = QHBoxLayout()

        save_btn = QPushButton("💾 Save to iCloud")
        save_btn.setStyleSheet("font-size: 14px; padding: 8px 16px;")
        save_btn.clicked.connect(self.on_save)
        btn_layout.addWidget(save_btn)

        reload_btn = QPushButton("🔄 Reload from iCloud")
        reload_btn.clicked.connect(self.on_reload)
        btn_layout.addWidget(reload_btn)

        layout.addLayout(btn_layout)

        # Status
        self.status_label = QLabel()
        self.status_label.setAlignment(Qt.AlignCenter)
        layout.addWidget(self.status_label)

        layout.addStretch()

        # Connect signals for live update of calculated fields
        self.age_spin.valueChanged.connect(self.update_calculated)
        self.age_check.toggled.connect(self.update_calculated)
        self.weight_spin.valueChanged.connect(self.update_calculated)
        self.weight_check.toggled.connect(self.update_calculated)
        self.height_spin.valueChanged.connect(self.update_calculated)
        self.height_check.toggled.connect(self.update_calculated)
        self.waist_spin.valueChanged.connect(self.update_calculated)
        self.waist_check.toggled.connect(self.update_calculated)
        self.hr_override_spin.valueChanged.connect(self.update_calculated)
        self.hr_override_check.toggled.connect(self.update_calculated)

    def populate(self):
        """Fill UI from profile data."""
        p = self.profile

        has_age = "age" in p and p["age"] is not None
        self.age_check.setChecked(has_age)
        self.age_spin.setEnabled(has_age)
        self.age_spin.setValue(p.get("age", 50))

        has_weight = "weightKg" in p and p["weightKg"] is not None
        self.weight_check.setChecked(has_weight)
        self.weight_spin.setEnabled(has_weight)
        self.weight_spin.setValue(p.get("weightKg", 75.0))

        has_height = "heightM" in p and p["heightM"] is not None
        self.height_check.setChecked(has_height)
        self.height_spin.setEnabled(has_height)
        self.height_spin.setValue(p.get("heightM", 1.75))

        has_waist = "waistCm" in p and p["waistCm"] is not None
        self.waist_check.setChecked(has_waist)
        self.waist_spin.setEnabled(has_waist)
        self.waist_spin.setValue(p.get("waistCm", 85.0))

        override = p.get("maxHROverride")
        if override is not None:
            self.hr_override_check.setChecked(True)
            self.hr_override_spin.setValue(override)
        else:
            self.hr_override_check.setChecked(False)

        self.autosave_check.setChecked(p.get("autoSaveICloud", False))
        self.temp_interval_spin.setValue(p.get("tempIntervalMinutes", 5))
        self.temp_elev_spin.setValue(p.get("tempElevationThreshold", 100))

        self.update_calculated()

    def on_hr_override_toggle(self, checked):
        self.hr_override_spin.setEnabled(checked)

    def update_calculated(self):
        has_age = self.age_check.isChecked()
        has_weight = self.weight_check.isChecked()
        has_height = self.height_check.isChecked()
        has_waist = self.waist_check.isChecked()

        # Tanaka: HRmax = 208 - 0.7 * age
        if has_age:
            age = self.age_spin.value()
            calc_hr = int(208 - 0.7 * age)
            self.hr_calculated.setText(f"{calc_hr} bpm")
        else:
            calc_hr = None
            self.hr_calculated.setText("— (set age first)")

        # Effective max HR
        if self.hr_override_check.isChecked():
            max_hr = self.hr_override_spin.value()
        elif calc_hr:
            max_hr = calc_hr
        else:
            max_hr = None

        # Zones
        if max_hr:
            zones = self.profile.get("zones", DEFAULT_ZONES)
            lines = []
            colors = ["🔵", "🟢", "🟡", "🟠", "🔴"]
            for i, z in enumerate(zones):
                lo = int(z["minPct"] * max_hr / 100)
                hi = int(z["maxPct"] * max_hr / 100)
                c = colors[i] if i < len(colors) else "⚪"
                lines.append(f"{c} Z{i+1} {z['name']:<12s}  {z['minPct']:>3d}–{z['maxPct']:<3d}%   {lo:>3d}–{hi:<3d} bpm")
            self.zones_label.setText("\n".join(lines))
        else:
            self.zones_label.setText("Set age or custom max HR to see zones")

        # BMI
        if has_weight and has_height:
            weight = self.weight_spin.value()
            height = self.height_spin.value()
            bmi = weight / (height ** 2)
            if bmi < 18.5:
                tag, color = "Underweight", "#5599ff"
            elif bmi < 25:
                tag, color = "Healthy", "#44bb44"
            elif bmi < 30:
                tag, color = "Overweight", "#ee8800"
            else:
                tag, color = "Obese", "#dd3333"
            self.bmi_label.setText(f"{bmi:.1f}")
            self.bmi_label.setStyleSheet(f"color: {color}; font-weight: bold;")
            self.bmi_tag.setText(tag)
            self.bmi_tag.setStyleSheet(f"color: {color};")
        else:
            self.bmi_label.setText("—")
            self.bmi_label.setStyleSheet("")
            self.bmi_tag.setText("need weight + height")
            self.bmi_tag.setStyleSheet("color: #888;")

        # BRI
        if has_waist and has_height:
            import math
            waist = self.waist_spin.value()
            height = self.height_spin.value()
            waist_m = waist / 100.0
            ratio = waist_m / (height * math.pi)
            sq = ratio ** 2
            if sq < 1:
                bri = 364.2 - 365.5 * math.sqrt(1 - sq)
                if bri < 3.41:
                    tag, color = "Lean", "#5599ff"
                elif bri < 4.45:
                    tag, color = "Healthy", "#44bb44"
                elif bri < 5.73:
                    tag, color = "Overweight", "#ee8800"
                else:
                    tag, color = "Obese", "#dd3333"
                self.bri_label.setText(f"{bri:.1f}")
                self.bri_label.setStyleSheet(f"color: {color}; font-weight: bold;")
                self.bri_tag.setText(tag)
                self.bri_tag.setStyleSheet(f"color: {color};")
            else:
                self.bri_label.setText("—")
                self.bri_label.setStyleSheet("")
                self.bri_tag.setText("")
        else:
            self.bri_label.setText("—")
            self.bri_label.setStyleSheet("")
            self.bri_tag.setText("need waist + height")
            self.bri_tag.setStyleSheet("color: #888;")

    def gather_data(self):
        """Collect all UI values into a dict. Unchecked fields are omitted."""
        data = {
            "autoSaveICloud": self.autosave_check.isChecked(),
            "tempIntervalMinutes": self.temp_interval_spin.value(),
            "tempElevationThreshold": self.temp_elev_spin.value(),
            "zones": self.profile.get("zones", DEFAULT_ZONES),
        }
        if self.age_check.isChecked():
            data["age"] = self.age_spin.value()
        if self.weight_check.isChecked():
            data["weightKg"] = self.weight_spin.value()
        if self.height_check.isChecked():
            data["heightM"] = self.height_spin.value()
        if self.waist_check.isChecked():
            data["waistCm"] = self.waist_spin.value()
        if self.hr_override_check.isChecked():
            data["maxHROverride"] = self.hr_override_spin.value()

        return data

    def on_save(self):
        data = self.gather_data()
        try:
            save_profile(data)
            self.profile = data
            self.status_label.setText(f"✅ Saved to {PROFILE_FILE.name} — will sync to iPhone via iCloud")
            self.status_label.setStyleSheet("color: green;")
        except Exception as e:
            self.status_label.setText(f"❌ Error: {e}")
            self.status_label.setStyleSheet("color: red;")

    def on_reload(self):
        self.profile = load_profile()
        self.populate()
        if self.profile:
            self.status_label.setText("🔄 Reloaded from iCloud")
            self.status_label.setStyleSheet("color: blue;")
        else:
            self.status_label.setText("⚠️ No profile found in iCloud")
            self.status_label.setStyleSheet("color: orange;")
