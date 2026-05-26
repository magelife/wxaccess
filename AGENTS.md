# wxaccess Project Instructions

## Accessibility Is Protected

wxaccess is an accessibility-first macOS weather radar app written by a blind developer. Do not change accessibility behavior unless the user explicitly asks for it.

Treat these as protected surfaces:

- VoiceOver output
- Focus behavior
- Keyboard access
- Accessibility labels and help text
- Announcements and live updates
- Accessibility summaries and the `AccessibilityPanel`

The map canvas is intentionally `accessibilityHidden(true)`. The `AccessibilityPanel` is the authoritative nonvisual radar readout.

Warn the user before any proposed visual, structural, or interaction change that could jeopardize accessibility. If visual meaning changes, make sure the nonvisual description remains accurate without casually rewriting accessibility copy.

## Radar Debugging Workflow

When investigating radar rendering bugs, separate failures into fetch/catalog, decode/framing, sweep selection, rasterization, and MapKit placement before choosing a fix.

If behavior depends on current weather data, verify the live feed. THREDDS catalogs and radar volume contents change over time.

Inspect radial counts, gate counts, selected product, selected sweep, azimuth coverage, range coverage, and generated overlay image before assuming the data source is bad.

Prefer focused diagnostics and regression tests, then remove temporary logging unless the user asks to keep it.

## Lessons From The Ray/Sliver Bug

- Level 2 sweeps can contain multiple radials at the same rounded azimuth with different range coverage or gate geometry. Never collapse radials into `[azimuthKey: Radial]`; preserve `[azimuthKey: [Radial]]` and choose a radial that covers the pixel's range.
- Partial elevation slices and transition cuts can contain only a few radials. Select sweeps by broad azimuth coverage near the requested tilt, not simply the first sweep with a matching elevation.
- Use explicit RGBA byte buffers for raster output, for example `[UInt8]` with `premultipliedLast` and `byteOrder32Big`. Avoid `[UInt32]` image buffers where byte order can become ambiguous.
- Weak reflectivity may be hidden by palette transparency. Distinguish "the decoder has no data" from "the palette made valid data invisible."
- If all products show the same tiny ray but colors change, product switching is probably working and the shared overlay, sweep, or radial logic is suspect.

## Useful Commands

Run tests with:

```sh
xcodebuild test -project wxaccess.xcodeproj -scheme wxaccess -destination 'platform=macOS' -derivedDataPath /private/tmp/wxaccess-derived-data
```

After rebuilding, quit the running `wxaccess` app before opening the new build; `open` may otherwise foreground an old process.

Relaunch with:

```sh
open /private/tmp/wxaccess-derived-data/Build/Products/Debug/wxaccess.app
```

## Review Checklist

- No accessibility surfaces changed unless explicitly requested.
- Radar products switch without crashing.
- The selected sweep has broad azimuth coverage where expected.
- The overlay image is nonblank and uses all relevant radials and range segments.
- Focused regression tests cover the rendering bug that was fixed.
