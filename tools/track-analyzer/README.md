# MapsPersonal Track Analyzer

Analyze GPX tracks exported from the MapsPersonal iOS app.

## Features

- Distance, duration, moving/stopped time
- Pace (min/km) and speed (km/h) with splits per km
- Elevation profile with spike filtering and smoothing
- Optional DEM elevation correction via Open-Elevation API
- Heart rate analysis (when recorded via HealthKit)
- Summary chart exported as PNG

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Usage

```bash
# Basic analysis
python analyze.py path/to/track.gpx

# With DEM elevation correction (requires internet)
python analyze.py path/to/track.gpx --dem

# Custom output path
python analyze.py path/to/track.gpx -o my_report.png
```

## Getting tracks from the app

From MapsPersonal on your iPhone:
1. Open **Track Manager**
2. Tap the **cloud icon** to copy the track to iCloud
3. On your Mac, find it at: `~/Library/Mobile Documents/iCloud~com~jorge~mapspersonal2026/Documents/Tracks/`

Alternatively, use the **share button** to send via AirDrop or save to Files.

## GPX extensions

The app records heart rate data from HealthKit using the standard Garmin TrackPointExtension format:

```xml
<extensions>
  <gpxtpx:TrackPointExtension>
    <gpxtpx:hr>96</gpxtpx:hr>
  </gpxtpx:TrackPointExtension>
</extensions>
```

This is compatible with Strava, Garmin Connect, and other GPX tools.
