# wxaccess

VoiceOver-first NEXRAD weather radar viewer for macOS. A native Swift + MapKit alternative to GRLevel3 / RadarScope built around the principle that weather data should be fully accessible.

## Features (Phase 1)

- Live NEXRAD Level 2 reflectivity from NOAA's public AWS S3 bucket — free, no API key
- Standard NWS reflectivity color table
- Active NWS watches, warnings, and advisories with polygon overlays
- **Accessible data panel** — all radar metadata and alerts readable by VoiceOver without touching the map canvas
- All ~160 WSR-88D CONUS + AK/HI/PR/GU sites

## Planned

- Level 3 product suite (velocity, dual-pol: ZDR, CC, KDP)
- GOES-16/17/18 satellite tiles
- SPC convective outlooks and mesoscale discussions
- GRLevel3 placefile support (AllisonHouse compatible)
- HRRR/GFS model data
- Loop animation
- Sonification option for accessibility

## Requirements

- macOS 14.0+
- Xcode 16+

## Build

```
cd wxaccess
xcodegen generate
open wxaccess.xcodeproj
```

## Data Sources

All free, no account required:

| Source | Data |
|---|---|
| `noaa-nexrad-level2.s3.amazonaws.com` | NEXRAD Level 2 (real-time + archive) |
| `api.weather.gov` | NWS alerts, forecasts, observations |
| `spc.noaa.gov` | SPC outlooks, MDs, watches (Phase 3) |
| `noaa-goes16.s3.amazonaws.com` | GOES-16 satellite (Phase 4) |

## Architecture

```
NEXRAD/    — Level 2 fetcher (AWS S3), Archive II binary decoder, bzip2 decompressor
NWS/       — Alerts fetcher (api.weather.gov), GeoJSON parser
Map/       — MKMapView wrapper, RadarOverlay (CGImage rasterizer), alert polygons
UI/        — SiteSelector, AlertsList, AccessibilityPanel (VoiceOver live regions)
```

## License

MIT — © 2026 Justin Mann (AI5OS / @w9fyi)
