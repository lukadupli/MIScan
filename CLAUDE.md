# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MIScan is a Flutter-based Android document scanner app featuring custom algorithms for quadrilateral transformation of images and straightening curved book pages. It uses native C++ libraries via FFI for the core image processing. The app is published on Google Play (`com.miscan.android`).

## Commands

```bash
# Run the app on a connected Android device
flutter run

# Build release APK (for direct install)
flutter build apk --release

# Build release App Bundle (for Google Play upload)
flutter build appbundle --release

# Lint
flutter analyze

# Run tests
flutter test

# Run a single test file
flutter test test/<filename>_test.dart

# Run the native C++ transform tests on the host (no device needed)
native/test/run_tests.sh

# Regenerate localization files after editing .arb files
flutter gen-l10n
```

## Android Build System

The Android build uses **Kotlin DSL** (`.gradle.kts` files), **AGP 8.11.1**, and **Gradle 8.13**.

### Release Signing

Signing credentials are loaded from `android/key.properties` (not committed to git):
```
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=../upload-keystore.jks   # relative to android/app/, so resolves to android/
```

The keystore file lives at `android/upload-keystore.jks` (also not committed).

### Build Directory Remapping

`android/build.gradle.kts` redirects all build output to the Flutter-standard `build/` directory at the project root (instead of `android/build/`). This is required for `flutter build` to locate the APK/AAB. Each subproject's build dir is also remapped to `build/<subproject-name>/`.

### Native C++ Build

`android/app/CMakeLists.txt` compiles three shared libraries from sources in `native/`:
- `libstraighten.so` — quad + book page transforms (links against `transform` + `basic_linear` static libs)
- `libjpg_encode.so` — JPEG encoding (links against `jpeg_compressor` static lib)
- `libimage_processing.so` — contrast/brightness on JPEG files (links against `jpeg_compressor`)

The `externalNativeBuild { cmake { path = file("CMakeLists.txt") } }` block in `android/app/build.gradle.kts` wires CMake into the Gradle build — **do not remove it**.

### Native Tests

`native/test/` holds a standalone host build (`native/test/CMakeLists.txt`, separate from the Android one) that exercises the transform maths without a device. Run it with `native/test/run_tests.sh` after **any** change under `native/transform/` or `native/basic_linear/` — the geometry has no runtime safety net, and a wrong plane normal shows up as a multi-gigabyte allocation request rather than a visible error.

`synthetic_scene.h` builds the ground truth: it takes a rectangle that really is flat and rectangular in 3D, projects it through the same pinhole camera the transforms assume, and hands back the quadrilateral a photo would have contained. `QuadTransform` then has to recover the camera height, plane normal, and aspect ratio it was built from. `test_util.h` is a small zero-dependency harness (`TEST`, `CHECK*`); add new files to the `add_executable` list in `CMakeLists.txt`.

### When the Quad Transform Cannot Recover the Camera Height

`QuadTransform` gets the camera height from the two vanishing points of the selected quadrilateral, which only works while both are close enough to the picture to say anything. Photograph a page square-on, or tilted about one axis only, and an edge pair comes out parallel — its vanishing point is at infinity and the height drops out of the equations entirely. The constraint is already noise-dominated well before that point, and corners are dragged with a fingertip.

So `loadCoordinates` solves for the height only while both vanishing points are within `VANISHING_POINT_REACH` scene scales of the principal point, clamps the result to a plausible focal-length range, and otherwise assumes `DEFAULT_HEIGHT_FACTOR` (all in `quad_transform.cpp`). The scan then comes out stable and usable but with an approximate aspect ratio — which is the best available, since the picture genuinely does not contain the information. Do not replace these with an exact-zero or absolute-epsilon test on `Sh.z`/`Th.z`: those are homogeneous coordinates whose scale depends on the picture resolution, so a fixed epsilon means nothing.

### What Sets the Output Resolution

The rectified page is built by projecting onto `fplane`, so how far that plane sits from the camera decides how many pixels the result gets. `fplane.b` used to be left at zero, putting it through the principal point — output size then tracked `h * fplane.v.z`, the camera height times the tilt, which says nothing about how finely the photo resolved the page. That quietly discarded up to 25% of the linear resolution on angled shots, and since the height above is only *assumed* for a square-on page, the output size of the most common scan was following a guessed constant.

`loadCoordinates` now scales the plane so one output pixel covers at most one source pixel, taking the longest source edge on each axis and applying the larger of the two ratios **uniformly**, so the recovered aspect ratio is untouched. The scale is clamped to `MAX_OUTPUT_SIDE` per side and `MAX_OUTPUT_PIXELS` (25 MP / 100 MB RGBA, matching the guards in `lib/transform.dart`) in total; when it binds, the scale is clamped and detail lost rather than the scan being refused.

Edge lengths are averages, so this is exact for the axis parallel to the near edge and falls short by `sqrt(|AB|/|CD|)` on the perpendicular one — a few percent at normal tilts. Closing that needs per-point magnification sampling and grows the output by the square of the same factor; deliberately not done. `BookTransform` needs nothing here: it works in the same floor-plane units and inherits the scale (measured worst case 17 MP, comfortably inside the guard).

### 16KB Page Size

The NDK version bundled with Android Studio (r28+) produces 16KB-aligned `.so` files automatically. No explicit linker flags are needed as long as `ndkVersion = flutter.ndkVersion` resolves to r28 or later.

### Version

The version string and build number are set in `pubspec.yaml` (`version: x.y.z+N`). The build number (`N`) is the Google Play version code and **must be incremented** for every Play Console upload — Play Console does not allow deleting uploaded bundles.

## Architecture

### Page Navigation Flow

```
main.dart (FirstLaunchChecker)
  ├─ FirstLaunchPage  (introduction screen, shown once)
  └─ MyHomePage       (scan list)
       └─ TransformPage     (quadrilateral corner selection)
            ├─ BookTransformPage  (book page curve selection)
            │    └─ EditPage → ImagePage
            └─ EditPage          (contrast/brightness/rotation)
                 └─ ImagePage    (view/share/export/rename)
```

`navigatorKey` in `main.dart` is a global key used by non-widget code (like FFI callbacks and `FileExport`) to push dialogs and navigate without a `BuildContext`.

### Native FFI Layer (`lib/transform.dart`, `lib/jpg_encode.dart`, `lib/jpg_process.dart`)

Three separate `.so` libraries are loaded at runtime on Android:
- `libstraighten.so` — quadrilateral and book page transforms (`QuadTransform`, `BookTransform`)
- `libjpg_encode.so` — JPEG encoding of raw RGBA pixel buffers (`JpgEncode`)
- `libimage_processing.so` — contrast/brightness adjustment on JPEG files (`JpgProcess`)

The native source is in `native/` (subdirectories: `straighten`, `jpg_encode`, `image_processing`, `basic_linear`, `jpeg_compressor`, `transform`). On non-Android platforms, `DynamicLibrary.process()` is used as a fallback.

Heavy FFI calls run in a separate isolate via `compute()` to avoid blocking the UI thread.

### Image Processing Pipeline

1. User picks image from camera or gallery → EXIF rotation corrected (`flutter_exif_rotation`)
2. `TransformPage`: user drags 4 corners of the `Frame` widget to define the document boundary
   - Corners are tracked by `FrameController` in counterclockwise order starting from bottom-left
   - `CornerShowcase` shows a magnified view of the active corner while dragging
3. `QuadTransform.transform()` is called in an isolate → result saved to a temp JPEG via `JpgEncode`
4. **Alternative path** — `BookTransformPage`: user adjusts a cubic spline (via `BookFrameController` / `BookFrame`) to define page curvature, then `BookTransform.transformFromSpline()` is called
5. `EditPage`: user adjusts contrast/brightness (via color matrix), rotates (via EXIF `Orientation` attribute), and sets the filename
6. On save, `JpgProcess.process()` applies contrast/brightness, and `native_exif` writes EXIF back; the file is saved to `{applicationDocumentsDirectory}/Scans/`
7. `ImagePage`: view (via `photo_view`), share, export to gallery (`saver_gallery`), export as PDF (`pdf` package), or rename

### Frame / Dragging UI (`lib/frame.dart`, `lib/book_frame.dart`, `lib/glider.dart`)

- `Glider` is the primitive draggable widget constrained to a `Rect` boundary
- `Frame` wraps a child with 4 `Glider` corners and a `CustomPaint` overlay (`BorderPainter`) that draws the quadrilateral
- `BookFrame` wraps a child with the same 4 corners plus N spline control points (also `Glider`s); `BookFramePainter` draws the frame and the computed cubic spline curve
- On resize/orientation change, corner positions are scaled proportionally to the new child size

### Cubic Spline (`lib/cubic_spline.dart`)

Pure-Dart implementation of natural cubic spline interpolation (uses `scidart` for matrix solving). `BookTransform` uses this to densely sample the curve and pass the resulting points to the native C++ function.

### Localization

English (`lib/l10n/app_en.arb`) and Croatian (`lib/l10n/app_hr.arb`) are supported. Generated code lives in `lib/l10n/` (`app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_hr.dart`) — these are committed to git and should not be edited manually. Re-run `flutter gen-l10n` after changing `.arb` files. The `l10n.yaml` config sets output class to `AppLocalizations`.

### Storage

- Internal scans: `{applicationDocumentsDirectory}/Scans/` (managed by `Locations.getAppInternalSaveDirectory()`)
- Gallery export: `Pictures/MIScan/` on external storage via `saver_gallery`
- Downloads export: standard Downloads directory via `external_path`
- Temporary transform output: system temp dir, filename format `Scan_YYYYMMDD_HHMMSS.jpg`