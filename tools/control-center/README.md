# MapsPersonal Control Center

Desktop companion app for the MapsPersonal iOS hiking app. Analyze your tracks, download geological maps, and manage offline data — all from your computer.

## What you need

- A computer (Mac, Windows, or Linux)
- Python 3.10 or newer installed
- An internet connection (for downloading maps and searching places)

## Setup — step by step

If you have **Claude Code** installed, you can simply say:

> "Set up the MapsPersonal Control Center for me"

Claude will handle everything below automatically.

### Manual setup

**1. Open a terminal**

- Mac: open **Terminal** (in Applications → Utilities)
- Windows: open **Command Prompt** or **PowerShell**
- Linux: open your terminal

**2. Navigate to the control center folder**

```bash
cd path/to/MapsPersonal/tools/control-center
```

**3. Create a virtual environment**

```bash
python3 -m venv .venv
```

**4. Activate it**

Mac/Linux:
```bash
source .venv/bin/activate
```

Windows:
```
.venv\Scripts\activate
```

**5. Install dependencies**

```bash
pip install -r requirements.txt
```

**6. Run the app**

```bash
python main.py
```

## Features

### Track Manager
- Lists all GPX tracks from your iCloud MapsPersonal folder
- Click a track to see full analysis: route map, elevation profile, speed chart, pace splits
- Choose between GPS and DEM (satellite terrain data) for elevation
- Heart rate visualization when recorded with Apple Watch

### Geology Manager
- Search any place in the world by name
- Interactive map to select download area
- Automatic geological map source detection by country:
  - **Spain**: IGME MAGNA 50 (1:50,000)
  - **France**: BRGM Carte Géologique (1:50,000)
  - **Belgium**: GSB Geological Map (1:40,000)
  - **Canada**: NRCan Bedrock Geology (1:5,000,000)
- Download tiles as MBTiles for offline use
- Transfer maps to iPhone/iPad via iCloud with one click

## Transferring maps to your iPhone

1. Download a geological map in the Geology Manager
2. The map appears in the "Downloaded Maps" list
3. Click **"Send to iPhone"**
4. On your iPhone, open MapsPersonal → menu (···) → **Offline Maps**
5. The map will appear there — tap to activate

## Troubleshooting

**"No module named PySide6"**: You forgot to activate the virtual environment. Run `source .venv/bin/activate` (Mac/Linux) or `.venv\Scripts\activate` (Windows).

**Map shows "Access blocked"**: This is a tile server issue. Restart the app — it should resolve automatically.

**Download crashes**: The app runs downloads in a separate process. If it crashes, your progress is saved. Just restart and try again.

**Maps don't appear on iPhone**: Make sure iCloud Drive is enabled on both your Mac and iPhone. The map file needs to sync — this can take a few minutes.
