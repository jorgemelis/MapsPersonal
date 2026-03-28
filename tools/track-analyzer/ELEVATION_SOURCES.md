# Elevation Sources: GPS vs DEM

## Quick comparison

| | GPS (device) | DEM (SRTM 30m) |
|---|---|---|
| **Source** | GPS/GNSS satellites + barometer (if available) | Shuttle Radar Topography Mission terrain model |
| **Resolution** | Per-point, real-time | 30m × 30m grid cells |
| **Vertical accuracy** | ±10-50m (GPS only), ±1-3m (barometric) | ±8m (RMSE), ±5m (bias) |
| **Requires internet** | No | Yes (API query) |
| **Speed** | Instant (recorded with track) | ~12 sec per 1000 points (rate limited) |
| **Noise** | High — affected by signal, buildings, trees | Low — consistent terrain model |
| **Tracks bridges/tunnels** | Yes (records actual altitude) | No (gives ground elevation) |
| **Tracks floors in buildings** | Yes (with barometer) | No |
| **Available offline** | Always | Needs pre-cached data or local DEM files |

## When to use each

### GPS elevation is better when:
- You're on a bridge, overpass, or elevated structure
- You're inside a building (multi-floor)
- You're in a tunnel or underground
- You have a device with barometric altimeter (Apple Watch, modern iPhones)
- You need offline analysis
- The track is short and you want instant results

### DEM elevation is better when:
- You're hiking on natural terrain (hills, mountains)
- Your device only has GPS (no barometer)
- GPS signal is poor (dense forest, canyons, urban canyons)
- You want consistent, repeatable elevation data
- You're comparing tracks across different devices
- You need accurate total elevation gain/loss for training analysis

## Elevation gain comparison (real track, 4 km hike)

| Source | Gain | Loss | Min | Max |
|---|---|---|---|---|
| Strava (reference) | +72 m | — | — | — |
| DEM SRTM 30m | +66 m | -64 m | 802 m | 830 m |
| GPS (filtered + smoothed) | +59 m | -44 m | 798 m | 832 m |
| GPS (raw, no filtering) | +617 m | -616 m | 798 m | 832 m |

The raw GPS elevation is wildly inaccurate for gain/loss calculation (+617m vs real ~70m).
Both filtered GPS and DEM are reasonable, with DEM closer to Strava's value.

## Available DEM APIs

| API | Resolution | Rate limit | Coverage | Best for |
|---|---|---|---|---|
| **OpenTopoData** (srtm30m) | 30m | 100 pts/req, 1 req/sec, 1000/day | Global 60°N-60°S | Personal use, reliable |
| **OpenTopoData** (eudem25m) | 25m | Same | Europe only | European tracks, better resolution |
| **Open-Elevation** | ~30m | 1000 req/month (free) | Global | Backup option |
| **MapTiler Terrain** | 30m (5m premium) | API key required | Global | Already used in app |
| **AWS Terrain Tiles** | 30m (10m USA) | No limit | Global | Offline/bulk processing |

## Future: offline DEM

For fully offline analysis, download SRTM HGT tiles for your region:
- Each tile covers 1° × 1° (about 111 km × 85 km at 40°N)
- SRTM1 (30m): ~25 MB per tile
- Spain (36°N-44°N, 10°W-4°E): ~112 tiles ≈ 2.8 GB
- Could be bundled with the app or downloaded on demand
