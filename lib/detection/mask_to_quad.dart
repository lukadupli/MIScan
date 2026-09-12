import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../frame.dart' show ccw;

/// Turns a predicted document mask into four corners, on-device.
///
/// A deliberate transcription of ml/postprocess.py -- same steps, same order,
/// same thresholds. The app has no OpenCV (the native layer is hand-written and
/// dependency-free), so this could not have been a library call; keeping it a
/// line-by-line mirror of the Python is what stops the number measured by
/// eval.py and the behaviour seen on the phone from drifting apart.
///
/// If you change the algorithm, change it in both.
///
/// Returns null when the mask does not reduce to a plausible quadrilateral,
/// which is the model saying it did not find a document -- something the old
/// 8-float regression could not express.

class _Pt {
  final double x, y;
  const _Pt(this.x, this.y);
  Offset get offset => Offset(x, y);
}

/// Keep only the biggest 4-connected blob. Explicit stack over flat indices:
/// no recursion, since a mask is far too big for the call stack.
Uint8List _largestComponent(Uint8List binary, int width, int height) {
  final seen = Uint8List(binary.length);
  final out = Uint8List(binary.length);
  final stack = Int32List(binary.length);
  var bestStart = -1, bestSize = 0;
  final componentStarts = <int>[];
  final componentSizes = <int>[];

  for (int start = 0; start < binary.length; start++) {
    if (binary[start] == 0 || seen[start] != 0) continue;
    var top = 0;
    stack[top++] = start;
    seen[start] = 1;
    var size = 0;
    while (top > 0) {
      final idx = stack[--top];
      size++;
      final x = idx % width;
      final y = idx ~/ width;
      if (x > 0 && binary[idx - 1] != 0 && seen[idx - 1] == 0) {
        seen[idx - 1] = 1;
        stack[top++] = idx - 1;
      }
      if (x < width - 1 && binary[idx + 1] != 0 && seen[idx + 1] == 0) {
        seen[idx + 1] = 1;
        stack[top++] = idx + 1;
      }
      if (y > 0 && binary[idx - width] != 0 && seen[idx - width] == 0) {
        seen[idx - width] = 1;
        stack[top++] = idx - width;
      }
      if (y < height - 1 && binary[idx + width] != 0 && seen[idx + width] == 0) {
        seen[idx + width] = 1;
        stack[top++] = idx + width;
      }
    }
    componentStarts.add(start);
    componentSizes.add(size);
    if (size > bestSize) {
      bestSize = size;
      bestStart = start;
    }
  }
  if (bestStart < 0) return out;

  // Second pass over just the winning component, re-flooding it into `out`.
  final seen2 = Uint8List(binary.length);
  var top = 0;
  stack[top++] = bestStart;
  seen2[bestStart] = 1;
  while (top > 0) {
    final idx = stack[--top];
    out[idx] = 1;
    final x = idx % width;
    final y = idx ~/ width;
    if (x > 0 && binary[idx - 1] != 0 && seen2[idx - 1] == 0) {
      seen2[idx - 1] = 1;
      stack[top++] = idx - 1;
    }
    if (x < width - 1 && binary[idx + 1] != 0 && seen2[idx + 1] == 0) {
      seen2[idx + 1] = 1;
      stack[top++] = idx + 1;
    }
    if (y > 0 && binary[idx - width] != 0 && seen2[idx - width] == 0) {
      seen2[idx - width] = 1;
      stack[top++] = idx - width;
    }
    if (y < height - 1 && binary[idx + width] != 0 && seen2[idx + width] == 0) {
      seen2[idx + width] = 1;
      stack[top++] = idx + width;
    }
  }
  return out;
}

/// Pixels that are set and have at least one unset 4-neighbour, counting
/// outside the frame as unset so a clipped page still contributes its edge.
List<_Pt> _boundaryPoints(Uint8List blob, int width, int height) {
  final points = <_Pt>[];
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final idx = y * width + x;
      if (blob[idx] == 0) continue;
      final edge = x == 0 ||
          y == 0 ||
          x == width - 1 ||
          y == height - 1 ||
          blob[idx - 1] == 0 ||
          blob[idx + 1] == 0 ||
          blob[idx - width] == 0 ||
          blob[idx + width] == 0;
      if (edge) points.add(_Pt(x.toDouble(), y.toDouble()));
    }
  }
  return points;
}

/// Andrew's monotone chain, using frame.dart's own orientation primitive.
List<_Pt> _convexHull(List<_Pt> points) {
  if (points.length < 3) return points;
  final pts = List<_Pt>.from(points)
    ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));

  List<_Pt> half(List<_Pt> seq) {
    final out = <_Pt>[];
    for (final p in seq) {
      while (out.length >= 2 &&
          ccw(out[out.length - 2].offset, out[out.length - 1].offset, p.offset) <= 0) {
        out.removeLast();
      }
      out.add(p);
    }
    return out.sublist(0, out.length - 1);
  }

  return [...half(pts), ...half(pts.reversed.toList())];
}

double _pointLineDistance(_Pt p, _Pt a, _Pt b) {
  final abx = b.x - a.x, aby = b.y - a.y;
  final length = math.sqrt(abx * abx + aby * aby);
  if (length < 1e-9) {
    return math.sqrt(math.pow(p.x - a.x, 2) + math.pow(p.y - a.y, 2));
  }
  return ((abx * (p.y - a.y) - aby * (p.x - a.x)).abs()) / length;
}

List<_Pt> _douglasPeucker(List<_Pt> points, double epsilon) {
  if (points.length < 3) return points;
  var worst = 0;
  var worstDist = -1.0;
  for (int i = 1; i < points.length - 1; i++) {
    final d = _pointLineDistance(points[i], points.first, points.last);
    if (d > worstDist) {
      worstDist = d;
      worst = i;
    }
  }
  if (worstDist <= epsilon) return [points.first, points.last];
  final left = _douglasPeucker(points.sublist(0, worst + 1), epsilon);
  final right = _douglasPeucker(points.sublist(worst), epsilon);
  return [...left.sublist(0, left.length - 1), ...right];
}

/// Douglas-Peucker around a closed ring, anchored at the two furthest-apart
/// vertices so the recursion cannot delete a real corner adjacent to an
/// arbitrary starting point.
List<_Pt> _simplifyClosed(List<_Pt> hull, double epsilon) {
  if (hull.length <= 4) return hull;
  var bestI = 0, bestJ = 0;
  var best = -1.0;
  for (int i = 0; i < hull.length; i++) {
    for (int j = i + 1; j < hull.length; j++) {
      final dx = hull[i].x - hull[j].x, dy = hull[i].y - hull[j].y;
      final d = dx * dx + dy * dy;
      if (d > best) {
        best = d;
        bestI = i;
        bestJ = j;
      }
    }
  }
  final first = _douglasPeucker(hull.sublist(bestI, bestJ + 1), epsilon);
  final second = _douglasPeucker(
    [...hull.sublist(bestJ), ...hull.sublist(0, bestI + 1)],
    epsilon,
  );
  return [
    ...first.sublist(0, first.length - 1),
    ...second.sublist(0, second.length - 1),
  ];
}

double _quadArea(List<_Pt> quad) {
  var sum = 0.0;
  for (int i = 0; i < quad.length; i++) {
    final a = quad[i], b = quad[(i + 1) % quad.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum.abs() / 2.0;
}

/// The 4 hull vertices enclosing the most area. Only reached when
/// simplification misses exactly four, and only ever run on an already
/// simplified hull, so the brute force stays cheap.
List<_Pt>? _largestQuadrilateral(List<_Pt> hull) {
  final n = hull.length;
  if (n < 4) return null;
  List<_Pt>? best;
  var bestArea = -1.0;
  for (int a = 0; a < n - 3; a++) {
    for (int b = a + 1; b < n - 2; b++) {
      for (int c = b + 1; c < n - 1; c++) {
        for (int d = c + 1; d < n; d++) {
          final quad = [hull[a], hull[b], hull[c], hull[d]];
          final area = _quadArea(quad);
          if (area > bestArea) {
            bestArea = area;
            best = quad;
          }
        }
      }
    }
  }
  return best;
}

/// Fix winding and starting corner, matching synth.py's canonicalize_corners
/// and therefore FrameController's own default order (TL, TR, BR, BL).
List<Offset> _canonicalize(List<_Pt> quad) {
  var pts = List<_Pt>.from(quad);
  var signed = 0.0;
  for (int i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    signed += a.x * b.y - b.x * a.y;
  }
  // In image coordinates (y down) a positive signed area is clockwise on
  // screen, which is the order frame.dart uses.
  if (signed < 0) pts = pts.reversed.toList();

  var start = 0;
  var bestDist = double.infinity;
  for (int i = 0; i < pts.length; i++) {
    final d = pts[i].x * pts[i].x + pts[i].y * pts[i].y;
    if (d < bestDist) {
      bestDist = d;
      start = i;
    }
  }
  return [for (int i = 0; i < 4; i++) pts[(start + i) % 4].offset];
}

/// What maskToQuad did on one frame. Diagnostic only: the debug preview shows
/// it, so where postprocessing time goes -- and how often the O(n^4) fallback
/// runs, on how many points -- is measured rather than guessed.
class MaskToQuadStats {
  /// How the frame ended: 'eps0.02' etc. names the simplification factor that
  /// landed on four vertices, 'fallback' means the brute-force search produced
  /// the quad, and a 'reject:' prefix means no quad came out at all.
  String path = '';
  int hullSize = 0;

  /// Whether the brute-force search ran. Tracked apart from [path] because a
  /// fallback whose result is then rejected as too small still cost the time.
  bool fallbackRan = false;

  /// Vertex count fed to the brute-force search. Its cost is C(n, 4) quad
  /// areas, so this number matters far more than whether it ran at all:
  /// n = 20 is ~4.8k combinations, n = 60 is ~490k.
  int fallbackN = 0;

  int thresholdUs = 0;
  int componentUs = 0;
  int boundaryUs = 0;
  int hullUs = 0;
  int simplifyUs = 0;
  int fallbackUs = 0;
}

/// Mask logits (row-major, [height] x [width]) -> 4 corners in mask pixels,
/// or null if nothing document-shaped is there.
///
/// Pass [stats] to record the path taken and per-step timings. It observes
/// only; the result is identical with or without it.
List<Offset>? maskToQuad(
  Float32List logits,
  int width,
  int height, {
  double threshold = 0.5,
  double minAreaFraction = 0.01,
  MaskToQuadStats? stats,
}) {
  final sw = Stopwatch()..start();
  int lap() {
    final t = sw.elapsedMicroseconds;
    sw.reset();
    return t;
  }

  final total = width * height;
  // Comparing logits against logit(threshold) avoids a sigmoid per pixel;
  // sigmoid is monotonic so the decision is identical.
  final cut = math.log(threshold / (1.0 - threshold));
  final binary = Uint8List(total);
  var on = 0;
  for (int i = 0; i < total; i++) {
    if (logits[i] >= cut) {
      binary[i] = 1;
      on++;
    }
  }
  stats?.thresholdUs = lap();
  if (on < minAreaFraction * total) {
    stats?.path = 'reject:empty';
    return null;
  }

  final blob = _largestComponent(binary, width, height);
  stats?.componentUs = lap();
  final points = _boundaryPoints(blob, width, height);
  stats?.boundaryUs = lap();
  if (points.length < 4) {
    stats?.path = 'reject:few-points';
    return null;
  }

  final hull = _convexHull(points);
  stats?.hullUs = lap();
  stats?.hullSize = hull.length;
  if (hull.length < 4) {
    stats?.path = 'reject:small-hull';
    return null;
  }

  final scale = math.sqrt(_quadArea(hull));
  final eps = scale <= 0 ? 1.0 : scale;
  List<_Pt>? quad;
  for (final factor in const [0.02, 0.04, 0.01, 0.08, 0.005]) {
    final simplified = _simplifyClosed(hull, factor * eps);
    if (simplified.length == 4) {
      quad = simplified;
      stats?.path = 'eps$factor';
      break;
    }
  }
  final reduced = quad == null ? _simplifyClosed(hull, 0.02 * eps) : null;
  stats?.simplifyUs = lap();

  if (quad == null) {
    final candidates = reduced!;
    stats?.fallbackRan = true;
    stats?.fallbackN = candidates.length;
    quad = _largestQuadrilateral(candidates);
    stats?.fallbackUs = lap();
    stats?.path = 'fallback';
  }
  if (quad == null || _quadArea(quad) < minAreaFraction * total) {
    stats?.path = 'reject:tiny-quad';
    return null;
  }

  return _canonicalize(quad);
}
