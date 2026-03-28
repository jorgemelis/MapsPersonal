# MapsPersonal

Personal hiking & mapping app for iOS with a desktop companion (Control Center) for track analysis and offline map management.

## Project Structure

```
MapsPersonal/
  MapsPersonal/           # iOS app (SwiftUI + MapLibre)
    Models/               # Data models (GPXTrack, MapState, MapLayer, etc.)
    Views/                # SwiftUI views
    Services/             # Business logic (TrackRecorder, HealthKit, Tractive, etc.)
    Helpers/              # Utilities (GPXExporter)
    Resources/            # Secrets.plist (gitignored), blank-style.json
  MapsPersonal.xcodeproj  # Xcode project
  Info.plist              # App configuration
  tools/
    track-analyzer/       # CLI track analysis (Python)
    control-center/       # Desktop companion app (PySide6)
  data/                   # MBTiles offline map files (gitignored)
```

## iOS App

- **Map engine**: MapLibre Native 6.23.0 (not MapKit)
- **Target**: iOS 17+, iPhone & iPad
- **Bundle ID**: `com.jorge.mapspersonal2026`
- **iCloud container**: `iCloud.com.jorge.mapspersonal2026`
- **Build**: Xcode, Swift, SwiftUI

### Key APIs & Services
- MapTiler (terrain tiles, contours) — key in `Secrets.plist`
- Tractive (pet GPS tracking) — credentials in `Secrets.plist`
- HealthKit (heart rate during track recording)
- Nominatim/OSM (place search, peak data)
- Open-Meteo (weather)

### Architecture
- `MapViewRepresentable` wraps MLNMapView as UIViewRepresentable
- `MapState` (@Observable) persists all map settings to UserDefaults
- `Coordinator` handles all layer sync, annotations, peaks
- Blank style — all layers (base, overlays, terrain, peaks) added programmatically

## Desktop Control Center

PySide6 app with modules for track analysis and offline map management.

### Setup (for anyone with Python 3.10+)

```bash
cd MapsPersonal/tools/control-center
python3 -m venv .venv
source .venv/bin/activate        # macOS/Linux
# .venv\Scripts\activate         # Windows
pip install -r requirements.txt
python main.py
```

### requirements.txt needed:
```
PySide6
matplotlib
numpy
requests
```

## Track Analyzer (CLI)

```bash
cd MapsPersonal/tools/track-analyzer
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Analyze a GPX track
python analyze.py path/to/track.gpx

# With DEM elevation correction
python analyze.py path/to/track.gpx --elevation dem
```

## For Claude: Development Guidelines

- The user (Jorge) speaks Spanish; code and comments in English
- Always verify builds compile: `xcodebuild -project MapsPersonal.xcodeproj -scheme MapsPersonal -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro' build`
- MapLibre, not MapKit — use MLN* classes
- Secrets are in `Resources/Secrets.plist` (gitignored) — never hardcode API keys
- iCloud container: `iCloud.com.jorge.mapspersonal2026`
- Python venv at project root `.venv/` — never use system Python
- Prefer Polars over Pandas when applicable
- TestFlight is set up — archive with `Product → Archive` in Xcode
