# Handoff: automatic document detection in the default scanning path

Read this before touching the code. It covers where the work stands, what the
measurements decided, what is left, and the traps already found.

## Goal

Make ML document detection the default way to start a scan. The target flow:

1. An in-app camera shows a live quad over the page.
2. The user taps the shutter, which takes a full-resolution photo.
3. The existing corner editor (`TransformPage`) opens with the **detected**
   corners instead of the image's edges.

Gallery imports get the same detection on the picked image.

## Ground rules (from the user)

- **Work only on the `Machine-Learning` branch.** `master` must keep matching
  the version published on Google Play: never commit or merge to it.
- **Commit or push only when the user asks.**
- **Never commit `android/key.properties` or `android/upload-keystore.jks`.**
  They hold the release-signing credentials.
- **Bump the build number** in `pubspec.yaml` (`x.y.z+N`) for every Play
  upload.
- **A quad slightly too small is preferred to one too large.** `maskToQuad`'s
  quads come out about 1.5 mask px inside the page, and the user decided to
  leave that as it is.
- **Book mode is deferred** until document mode is done. Don't touch
  `book_frame.dart` / `book_transform_page.dart` yet (see Deferred below).
- **No page found:** the editor opens with the corners at the image's own
  corners, exactly as today. Show no hint or banner.

## State of the working tree

**Phases 0-3 are all done and about to be committed** on `Machine-Learning`
(previous commit: `d61d748`, pushed to `origin/Machine-Learning`). `git
status` before that commit shows:

| Area | Files | What changed |
|---|---|---|
| Home page | `lib/main.dart`, `lib/my_home_page.dart` | The endless rebuild loop is fixed. `build()` used to list the scan directory on every frame. The page now uses a `RouteObserver` (`routeObserver` in `main.dart`) with `RouteAware`: it loads in `initState` and refreshes in `didPopNext`. This is a real bug in the published app. The FAB dialog is now Scanner/Gallery (Phase 3). |
| Detection module | `lib/detection/` (moved by `git mv` from `lib/debug/`): `document_model.dart`, `frame_math.dart`, `mask_to_quad.dart`, `ort_tensor_io.dart` | Phase 1, see below. |
| Debug pages | `lib/debug/live_preview_page.dart`, `benchmark_page.dart` | Phase 0 instrumentation, the import fixes after the move, and (Phase 3) the old EXIF-rotate timing branch in `_captureTest` is gone along with the `flutter_exif_rotation` import. |
| Corner editor | `lib/frame.dart`, `lib/transform_page.dart` | Phase 2, see below. |
| Scanner (new, Phase 3) | `lib/scan_camera_page.dart`, `lib/scan_input.dart` | See "Phase 3: done" below. |
| Loading/helpers | `lib/loading_page.dart` (`LoadingThen<T>`), `lib/helpers.dart` (`loadImageFile`) | Phase 3, see below. |
| Camera plugin | `third_party/camera_android_camerax/`, `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` | Vendored, patched copy of the plugin. The analyzer excludes `third_party/**`. `pubspec.yaml` also drops `flutter_exif_rotation` (Phase 3) now that nothing imports it. |
| Strings | `lib/l10n/*.arb` plus the generated `app_localizations*.dart` | Phase 3 strings added; `chooseSourceTitle`/`imageSource` (the old camera/gallery import dialog) removed now that nothing references them, and `flutter gen-l10n` re-run. |
| ML | `ml/dataset.py`, `ml/eval.py` | New eval flags `--crop-aspect W:H`, `--view landscape\|portrait`, `--resample area\|nearest`. |
| Path mentions | `ml/postprocess.py`, `ml/make_postprocess_fixture.py`, `native/image_processing/yuv_to_tensor.{h,cpp}` | Updated for the `lib/detection/` move. |
| Tests | `test/frame_math_test.dart`, `test/frame_controller_test.dart`, `test/loading_then_test.dart` (all new) | New tests, see "Tests" below. |
| Tests | `test/widget_test.dart` | Deleted. It was the stale counter-app template and always failed. |
| Docs | `CLAUDE.md` | Page-navigation diagram, pipeline step 1, and a new "Document Detection" section. |
| Not ours | `ml/model.py` | The user's own uncommitted edit to its `__main__` block. Leave it alone. |

`flutter analyze` is clean and `flutter test` passes 26 tests. The native tests
(`native/test/run_tests.sh`) are unaffected: no native code changed apart from
comments.

## Phase 0: measured on the SM-A137F, decision gate passed

Device: Samsung SM-A137F, Android 14, 32-bit userspace. Camera hardware level
LIMITED. Sensor orientation 90.

| Gate item | Result |
|---|---|
| Photo | **4080×3060 (12.5 MP)**, 4:3, same field of view as the preview |
| Detection rate (live) | **6.0/s** with 2 threads (gate ≥ 5) |
| Jank | **0.5–1.7%** with 2 threads (gate ≤ 5%) |
| `takePicture` | median **479 ms** over 10 captures |
| Decoding a 12 MP JPEG (`bytesToImage`) | median **~1.3 s**, the biggest cost |
| Detection on the photo (`detectImage`) | **215–233 ms** |
| Shutter → decoded → detected | **~2.0–2.1 s** estimated (gate ≤ 2.5 s); confirm once the scanner exists |
| Memory | flat at ~550 MB over 10 captures, no OOM (it holds one decoded 12 MP image, ~50 MB) |
| Heat | detection rate ~100% after ~12 min of continuous running; battery settled at 37 °C (while charging) |

**Thread sweep** (camera streaming, two rounds, consistent):

| Threads | Detections/s | Jank |
|---|---|---|
| 4 | 6.75 | 12–13% ❌ |
| 3 | 6.4 | 3.4–4.5% |
| 2 | 6.0 | 0.5–1.5% |

`DocumentModel.xnnpackThreads` is now **2**.

**Decisions:**
- The camera runs three outputs at once, each at its own size:
  - preview 1440×1080;
  - analysis stream **320×240** (the model's input size; the camera's
    hardware scaler does the downscale);
  - photo 4080×3060.
- **Pull-mode streaming** is not needed.
- **Model input:** the sensor's own landscape frame, *not* rotated to
  portrait. Only the 4 output corners are rotated upright
  (`sensorToUpright`). The old path rotated the frame to portrait and
  squashed it into the 4:3 input, which was a bug.
  - SmartDoc, cropped to 4:3: median corner error 0.73% landscape vs 0.84%
    portrait-squash; IoU > 0.95 on 19% vs 11% of frames.
  - Nearest-neighbour vs area resampling made no measurable difference.
  - The overlay was checked on the phone and sits on the page.
- **`flutter_exif_rotation` goes.** Flutter's decoder already applies the EXIF
  orientation: stored 4080×3060 with EXIF 6 decodes to 3060×4080. The old
  rotate step costs **1.9 s** per 12 MP photo and re-encodes the JPEG at
  quality 100.

## Why the camera plugin is patched (`third_party/camera_android_camerax`)

Read `third_party/camera_android_camerax/MISCAN_PATCH.md`; `miscan.patch` is
the full diff. In short:

- **Upstream applies one `ResolutionSelector` to preview, analysis and
  photo.** The patch gives `ResolutionPreset.max` separate selectors: preview
  bounded at 1440×1080, analysis at 320×240, photo at highest available, all
  4:3.
- **CameraX's default mode only picks sizes that sustain 20 fps.** This camera
  has `BURST_CAPTURE`, so Android files 4080×3060 (15 fps) under
  "high-resolution" sizes, and the default mode never considers those. The
  largest 4:3 photo was therefore 1440×1080. The Java side of the patch sets
  `PREFER_HIGHER_RESOLUTION_OVER_CAPTURE_RATE` whenever the highest-available
  strategy is used.
- **To verify on a device:** `adb logcat | grep onSuggestedStreamSpecUpdated`
  should show `ImageCapture ... 4080x3060` and `ImageAnalysis ... 320x240`.
  Formally, Android guarantees this three-output combination only with a
  *normal* size for the photo. It works on this phone, but other phones are
  untested.
- **Upgrading the `camera` plugin** means re-applying the patch; the steps are
  in `MISCAN_PATCH.md`.

## Phase 1: done (`lib/detection/`)

**`DocumentModel`**

| API | Behaviour |
|---|---|
| `DocumentModel.shared()` | App-wide instance, loaded and warmed up on first use and kept for the app's lifetime. **Never dispose it.** A failed load resets, so the next call retries. There's no ORT build for x86_64 emulators or ChromeOS: callers must treat a failure as "no detection". |
| `DocumentModel.load(threads:)` | A private instance; only the debug pages use it, and the caller disposes it. |
| `_exclusive()` | Serial queue for **every** inference. The plugin's `runAsync` is not safe to overlap: concurrent calls share one broadcast result stream, so outputs get swapped and released twice (onnxruntime 1.4.1, `ort_isolate_session.dart`). `dispose()` waits for the queue. |
| `predict(CameraImage, sensorOrientation)` | Live frames. The converter runs with rotation 0, and the corners come back through `sensorToUpright`. |
| `detectImage(ui.Image)` | Photos. Returns upright normalised corners (TL, TR, BR, BL), or null when no page is found; **throws** if inference fails. |

`detectImage` works like this:
1. A portrait photo is turned a quarter anticlockwise, i.e. into the sensor's
   own view.
2. It's drawn into 320×240 over white with `FilterQuality.medium` (GPU
   mipmaps).
3. `toByteData(rawRgba)` → `rgbaToChw` into the model's own photo buffer →
   inference → `maskToQuad` → `sensorToUpright(…, portrait ? 90 : 0)`.

**`frame_math.dart`**

| Name | Purpose |
|---|---|
| `kModelInputLength` | Floats in one network input. |
| `rgbaToChw` | Photo pixels → model input. |
| `sensorToUpright` | Rotates corners to screen orientation and restarts the order at the top-left corner. |
| `mapWidgetToNormalized` | The inverse of `mapCornersToWidget`; returns null over the letterbox bars. For tap-to-focus. |
| `kPreviewFit = BoxFit.contain` | The preview shows exactly what the model sees. |

**Parity check (photo detection vs Python)**
- The method: pull the photo with `adb pull`, then run in Python: EXIF
  transpose → rotate anticlockwise if portrait → resize to 320×240 → ORT
  `segmentation.onnx` → `ml/postprocess.mask_to_quad` → un-rotate
  `(x, y) → (1 - y, x)`.
- Results across three photos:
  - two matched within 1.4 and 0.02 mask px;
  - one differed by 7 px on one ragged corner (a torn spiral edge);
  - with a mipmap-like resize in Python (a `pyrDown` chain + bilinear) that
    photo matched to 1 px.
- So the phone's pipeline is right, and corner placement is sensitive to the
  downscale filter at ambiguous corners.
- The script lived in the session scratchpad and is gone; it's ~60 lines to
  recreate.

## Phase 2: document part done

- **`FrameController({List<Offset>? initialCorners})`:** normalised TL, TR,
  BR, BL; copied by `FrameController.from`. `startingCorners(size)` uses them
  if they're 4 finite points, clamped into [0, 1], and otherwise uses the
  image's corners.
- **The rescale in `_FrameState.handleChildSizeChange`** now uses
  `controller.boundary`, guarded by `isEmpty`. It used to use the State's own
  `boundary`, which starts at `Rect.zero` in a fresh State, so a pre-laid-out
  controller got NaN corners.
- **`TransformPage({required image, List<Offset>? initialCorners})`:** null
  gives today's full-image corners. The planned "no document" hint was
  dropped at the user's request.
- **Corner order is consistent.** `FrameController` uses TL, TR, BR, BL on
  screen; `CLAUDE.md` calls this "counterclockwise from bottom-left" because
  it describes math coordinates with y up. `maskToQuad` and `sensorToUpright`
  both produce this order.
- **Unrelated pre-existing oddity:** `FrameController.isConvex()` returns
  false even for the default rectangle (sign convention). Nothing calls it
  today; fix its sign before using it for validation.

## Phase 3: done (scanner page and entry points)

1. **`lib/helpers.dart`:** `loadImageFile(path)` (bytes → `bytesToImage`; the
   engine handles EXIF).
2. **`lib/loading_page.dart`:** `LoadingThen<T>`. Shows `LoadingPage` while a
   future runs, then `pushReplacement`s to the result page. On error it pops
   itself and shows a SnackBar (`imageLoadFailed`) via
   `ScaffoldMessenger.of(navigatorKey.currentContext!)` -- the same
   navigatorKey-based pattern `file_export.dart` already used, which works
   because `MaterialApp` wraps its `Navigator` in a `ScaffoldMessenger`.
   Before this, a decode error left `LoadingPage` up forever, because the
   pages used builder-created `FutureBuilder`s.
3. **`lib/scan_input.dart` (new):**
   - `prepareScanInput(path, {deleteFile})` → `ScanInput(image, corners)`.
   - Decodes the image, then runs `DocumentModel.shared()` + `detectImage`
     with a 5 s timeout.
   - **Any** detection error or timeout gives `corners = null`, and the
     editor then uses the full-image corners.
   - Deletes the temp capture file after decoding when `deleteFile` is true
     (the scanner passes true; gallery imports leave the picked file alone).
4. **`lib/scan_camera_page.dart` (new): `ScanCameraPage`** -- built as
   planned: back camera, `ResolutionPreset.max`, `ImageFormatGroup.yuv420`,
   portrait lock, `DocumentModel.shared()` started early; live overlay
   (`FittedBox(fit: kPreviewFit)` + `CameraPreview` + `BorderPainter` via
   `mapCornersToWidget`, busy-flag throttled); shutter stops the stream,
   takes the photo, tears the camera down, and pushes
   `LoadingThen(prepareScanInput(path, deleteFile: true)) → TransformPage`;
   `_pendingDispose` + `_generation` teardown safety copied from
   `live_preview_page.dart`; flash cycles off → auto → torch, forced off
   before every dispose and reapplied after every start; tap-to-focus via
   `mapWidgetToNormalized`; localised permission flow, rechecked on resume
   via `RouteAware`/`didPopNext` (also restarts the camera for a retake when
   coming back from the editor) and `WidgetsBindingObserver` (stops the
   camera on inactive/paused, unconditionally rechecks permission+camera on
   resume -- this covers a controller-less resume too, e.g. granting the
   permission from Settings and coming back).
   - **On-device fix:** right after the OS permission dialog is granted,
     CameraX can fail to bind once before the grant has fully propagated to
     the camera service -- `controller.initialize()` throws, "camera
     unavailable" shows, and the very next attempt (re-entering the scanner)
     succeeds. `_startCamera` now retries once, 300 ms later, before giving
     up, which absorbs this without a user-visible failure.
5. **`lib/my_home_page.dart`:** the FAB dialog is now **Scanner / Gallery**
   (`newScanTitle`, `scannerOption`, `galleryOption`) and pops itself before
   navigating (it never used to). Scanner pushes `ScanCameraPage`; Gallery
   runs `ImagePicker().pickImage(gallery)` → `LoadingThen(prepareScanInput)` →
   `TransformPage`. `crossFileToImage` and the `flutter_exif_rotation` import
   are gone, and so is the camera `ImageSource` branch.
6. **`pubspec.yaml`:** `flutter_exif_rotation` removed (`flutter pub get`
   run); its only other importer, the debug capture test in
   `live_preview_page.dart`, had its old-path (`oldExifRotateMs`) timing
   block stripped too.
7. **`CLAUDE.md`:** page-navigation diagram, pipeline step 1, and a
   "Document Detection" section covering `lib/detection/`, the shared model
   and its queue, landscape sensor input, the three camera outputs and the
   patched plugin, and the 2-thread choice.

**On-device findings (SM-A137F, profile build, 2026-09-11/12) -- both are
resolved, neither needed a code change beyond the retry above:**
- **The permission-grant race above** was the one real bug found; fixed as
  described in step 4.
- **Torch appeared to never turn on.** Traced to the phone's stock camera
  app's flashlight also being unresponsive -- a device-level glitch, cleared
  by rebooting the phone (the user rebooted into safe mode and back). Not
  caused by this code; if it recurs, check the stock camera app's flash
  first before assuming a regression here.
- **Torch stays on continuously while active, not just during capture.**
  This is intentional, not a bug: the flash cycle is off → auto → **torch**
  (a steady light), which is a different mode from the stock camera app's
  brief flash-at-capture. A continuous light is deliberately better for
  scanning -- it lets the user frame the shot and gives even illumination,
  where a single flash pop tends to cause glare/hot spots on paper. If the
  user ever wants stock-camera-style flash-at-capture instead, that would be
  a new `FlashMode.always` cycle state, not a fix to the current one.
- Everything else on the on-device checklist below passed as planned:
  overlay tracking, tap-to-focus, capture → detected quad in the editor, no
  camera-in-use indicator while the editor is open, camera resuming on
  return from the editor, background/foreground robustness, fast
  re-entries, gallery import, and release-build parity with profile.

**New strings, already added and generated (use them, don't re-add):**

| Key | English |
|---|---|
| `newScanTitle` | New scan |
| `scannerOption` | Scanner |
| `galleryOption` | Gallery |
| `takePictureTooltip` | Take picture |
| `flashTooltip` | Flash |
| `cameraPermissionTitle` | Camera access |
| `cameraPermissionContent` | MIScan needs the camera to scan documents. |
| `cameraPermissionDeniedContent` | Camera access is turned off for MIScan. You can turn it on in the app settings. |
| `cameraUnavailable` | The camera could not be started. |
| `captureFailed` | Could not take the picture. Please try again. |
| `imageLoadFailed` | Could not open this image. |

Reuse the existing `openSettings`, `tryAgain` and `cancel`. **The Croatian
strings are drafts; the user should review them.** They follow the file's
register: informal imperative on buttons, formal "vi" in sentences.

### Tests: done

- `test/loading_then_test.dart`: written and passing -- success replaces the
  loading page; an error pops it and shows a SnackBar. Note for anyone
  extending it: don't `pumpAndSettle()` while `LoadingPage`'s
  `CircularProgressIndicator` (indeterminate) is the only thing on screen --
  it never stops scheduling frames on its own, so `pumpAndSettle` times out.
  Use bounded `pump()`/`pump(duration)` calls instead, as the test does.
- The optional widget test for the home dialog (Scanner/Gallery, and that it
  pops) was **skipped deliberately**: tapping either option immediately
  navigates into code that hits unmocked platform channels
  (`permission_handler`, `camera` or `image_picker`), which would need
  channel-level mocking to test reliably rather than add a flaky test for an
  optional case.

### On-device verification (SM-A137F): done, profile build then release

All done and passing:
- **Scanner:** permission flows (deny, deny permanently, grant from
  settings -- including the fix above); the overlay tracks the page;
  tap-to-focus works; capture opens the editor with the detected quad; no
  camera-in-use indicator while the editor is open; back resumes the
  preview/retake; torch survives a retake.
- **Editor and saving:** Save → ImagePage → Home lists the new scan (the
  `didPopNext` refresh).
- **Robustness:** background/foreground on the scanner and the editor; fast
  re-entries into the scanner; repeated captures.
- **Gallery:** import works.
- **Strings:** Croatian displays correctly (still drafts -- see the note
  below the strings table).
- **Release build** (`flutter build apk --release`): everything above works
  the same as the profile build after R8 shrinking.

### Deferred

- **Book mode with detected corners.** `BookFrame` hangs each curve handle
  75–150 px *below* its point on the page's top edge
  (`splineSelectorDelta`), and the handle's drag bounds assume room below.
  With full-image corners the top edge is at y = 0, so that's fine. A detected
  top edge can sit near the image's bottom, especially in landscape. The
  handle is then drawn outside the widget, where it can't be grabbed, and the
  first drag makes the curve point jump.
  - Planned fix: per handle, put it *above* the curve when there's no room
    below. That means flipping the painter's offset and the Glider's bounds,
    and compensating for the Glider reporting positions relative to its own
    bounds.
  - Until then, the book button still works; the handles can just be awkward
    when the page is low in the frame.
- **Before any Play release (out of scope here, but blockers):**
  - **16 KB page size.** The plugin-bundled `libonnxruntime.so` is 4 KB-aligned
    (`align=0x1000`, both ABIs), and Play requires 16 KB for arm64 at this
    target SDK. Vendor or build a 16 KB-aligned ORT.
  - **On merge to master:** minSdk goes 21 → 24 (required by the camera
    plugin), and the app grows by the ~13 MB model plus the ORT native
    libraries.
  - **The camera patch** is verified only on the SM-A137F; test other phones.
- **Later ideas:**
  - Auto-capture once the quad is stable.
  - Faster shutter → editor. Decoding the 12 MP JPEG takes ~1.3 s. Detection
    could use a small decode, and the editor could show a screen-sized image
    while the full-resolution decode, needed for the transform, finishes in
    the background.

## Debug tooling (left in place, debug/profile builds only)

- **`lib/debug/live_preview_page.dart`** (home-page icon ⊡ at the top right):
  - MED/MAX preset toggle, thread toggle (x2 / x3 / x4), and an A/B sweep
    button (▶);
  - a capture test that logs `takePicture`, decode and `detectImage` timings,
    EXIF orientation and memory;
  - it draws the photo's detected corners in green on a thumbnail;
  - it saves each photo to
    `/sdcard/Android/data/com.miscan.android/files/phase0/capture_N.jpg` for
    `adb pull`. Delete those files eventually.
  - Every measurement is a one-line `PHASE0 kind=... k=v` log record.
- **`lib/debug/benchmark_page.dart`** (⏱ icon): compares execution providers.
- **`ml/eval.py`**, for example:
  - `--task seg --crop-aspect 4:3 --view portrait --resample nearest` scores
    SmartDoc the way the phone feeds it;
  - baseline SmartDoc (full frame): mean IoU 0.9035, corner error 1.22%.

## Device and workflow notes

- **adb:** `~/Library/Android/sdk/platform-tools/adb`; device `RF8T80CFE6L`.
- **Build:** `flutter run --profile -d RF8T80CFE6L`. Debug-mode timings are
  meaningless; release builds hide the debug icons.
- **Useful taps** (1080×2408 screen):

  | Target | Coordinates |
  |---|---|
  | Home → live preview icon | (1009, 148) |
  | Live preview → MED/MAX | (675, 147) |
  | Live preview → threads | (853, 147) |
  | Live preview → sweep ▶ | (1015, 147) |
  | Live preview → shutter | (957, 2146) |

  **Always confirm which screen is showing before tapping.** The ▶ button
  sits where the home page's preview icon is, and a blind tap started a sweep
  twice.
- **The user often holds and taps the phone during tests.** Coordinate with
  them, or ask them to do the taps.
- **The phone has a secure lock screen,** so the user must unlock it. Never
  try to enter credentials.
- **Frame-rate note:** the phone's display is 60 Hz, so the jank budget is
  16.7 ms. `jankPct` counts frames whose build or raster step exceeded it.
- **Python:** `ml/.venv/bin/python`. The venv has onnxruntime 1.28, OpenCV 5
  and Pillow.
