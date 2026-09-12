# camera_android_camerax 0.7.2, patched for MIScan

A copy of the pub.dev package (BSD licence, see `LICENSE`), used through
`dependency_overrides` in the app's `pubspec.yaml`. Only `lib/`, `android/`
and the package metadata are kept; the upstream example app and tests are not.

## Why

The document scanner needs three camera outputs at once, each at its own size:

| Output         | Size (SM-A137F) | For                                  |
|----------------|-----------------|--------------------------------------|
| Preview        | 1440x1080       | the viewfinder                       |
| Image analysis | 320x240         | the detector (its input size)        |
| Photo          | 4080x3060       | the scan itself                      |

Upstream applies one `ResolutionSelector` to all three, so `ResolutionPreset.max`
gave a 1440x1080 photo *and* a 1440x1080 analysis stream, and `medium` a
640x480 photo. Two things were wrong:

1. **One selector for every output.** The patch gives `ResolutionPreset.max`
   separate selectors: preview bounded at 1440x1080, analysis at 320x240, photo
   at the highest available -- all 4:3. Other presets are unchanged.
2. **"Highest available" was not.** CameraX's default resolution mode only
   picks sizes that sustain 20 fps. On cameras with the `BURST_CAPTURE`
   capability, Android files the slower full-resolution sizes (4080x3060 runs at
   15 fps on a SM-A137F) under "high resolution" sizes, which that mode never
   considers -- so the largest 4:3 photo was 1440x1080. The patch sets
   `PREFER_HIGHER_RESOLUTION_OVER_CAPTURE_RATE` whenever the highest-available
   strategy is used. Only the capture request uses that size; preview and
   analysis keep their normal frame rate.

Measured on a SM-A137F: a 12.5 MP photo in ~480 ms, 6 detections/s alongside,
no memory growth over 10 captures.

## The patch

`miscan.patch` is the complete diff against the pub.dev release (two files).

## Upgrading the camera plugin

1. Check the new release still lacks per-output resolutions and the resolution
   mode; if upstream has them, drop this copy and the override instead.
2. Copy `lib/`, `android/`, `pubspec.yaml`, `LICENSE`, `AUTHORS`, `README.md`
   and `CHANGELOG.md` from `~/.pub-cache/hosted/pub.dev/camera_android_camerax-<version>/`
   over this directory.
3. `patch -p1 -d third_party/camera_android_camerax < third_party/camera_android_camerax/miscan.patch`
4. On a device, CameraX should log (with `adb logcat | grep onSuggestedStreamSpecUpdated`)
   `ImageCapture ... resolution=4080x3060` and `ImageAnalysis ... resolution=320x240`
   once the scanner opens.
