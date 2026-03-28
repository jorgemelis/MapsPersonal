# MapsPersonal

A personal hiking and mapping app for iOS, with a desktop companion for track analysis and offline geological map management.

## What is this?

MapsPersonal is a hiking-focused map app built for iPhone and iPad. It combines multiple map sources (topographic, satellite, geological) with GPS track recording, heart rate monitoring, and offline map support. A desktop companion app lets you analyze your tracks and download geological maps for offline use.

## For users — Getting started

### iOS App

You need a Mac with Xcode to build the app:

1. Clone this repository
2. Open `MapsPersonal.xcodeproj` in Xcode
3. Connect your iPhone
4. Product → Run

The app requires:
- A MapTiler API key (free tier works) — add it to `Resources/Secrets.plist`
- iOS 17 or later

### Desktop Control Center

The Control Center runs on Mac, Windows, or Linux. You need Python 3.10+.

```bash
cd tools/control-center
python3 -m venv .venv
source .venv/bin/activate    # Mac/Linux
pip install -r requirements.txt
python main.py
```

If you have **Claude Code** installed, just say: *"Set up and run the Control Center"*

### Track Analyzer (CLI)

Analyze GPX tracks from the command line:

```bash
cd tools/track-analyzer
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python analyze.py path/to/track.gpx
python analyze.py path/to/track.gpx --elevation dem   # DEM correction
```

## Features

### iOS App
- Multiple base maps: OpenStreetMap, ESRI Satellite, IGN Topographic (Spain), PNOA Orthophoto
- Geological map overlays (IGME MAGNA 50)
- Offline maps from MBTiles files
- GPS track recording with HealthKit heart rate from Apple Watch
- GPX export with heart rate extensions (compatible with Strava/Garmin)
- Place search (Nominatim/OpenStreetMap)
- Mountain peak identification (OpenStreetMap data)
- Hillshade and contour lines (MapTiler)
- Pet tracking via Tractive GPS
- Weather display (Open-Meteo)
- Checklists synced via iCloud

### Desktop Control Center
- **Track Manager**: analyze GPX tracks with elevation profiles, speed charts, pace splits, heart rate graphs
- **Geology Manager**: search places, browse an interactive map, download geological map tiles for Spain, France, Belgium, and Canada. Transfer to iPhone with one click.

### Track Analyzer
- Elevation analysis: GPS (filtered/smoothed) or DEM (SRTM 30m via OpenTopoData)
- Splits per km with moving-time pace (matches Strava)
- Heart rate visualization
- PNG chart export

## Architecture

The iOS app uses **MapLibre Native** (not Apple MapKit) for full control over map rendering. All layers are added programmatically to a blank style. Map state persists to UserDefaults.

The desktop tools are built with **PySide6** (Qt for Python) and **matplotlib**.

Track data flows: iPhone → iCloud → Mac (analysis) and Mac → iCloud → iPhone (offline maps).

## License

Personal project. Feel free to use as inspiration for your own hiking app.
