// Lingxi Desk: pointer ballistics for the mobile trackpad (mouse) mode.
//
// Pure Dart (no Flutter imports) so it can be unit-tested with plain `dart test`.
//
// Finger movement arrives in Flutter logical pixels. On Android one logical
// pixel is one dp = 1/160 inch, so it maps to a fixed physical distance and the
// gain below feels the same on every phone. The result is still in logical
// pixels on the phone screen ("visual space"); the caller divides by the
// canvas zoom, so zooming in automatically makes the cursor finer.
//
// See docs/design.md, section "手机端虚拟鼠标与触控交互".

import 'dart:math' as math;

/// Millimetres per logical pixel (1 dp = 1/160 inch).
const double kMmPerLogicalPixel = 25.4 / 160.0;

enum TrackpadAccelProfile { off, light, medium, strong }

TrackpadAccelProfile trackpadAccelProfileFromString(String? s) {
  switch (s) {
    case 'off':
      return TrackpadAccelProfile.off;
    case 'light':
      return TrackpadAccelProfile.light;
    case 'strong':
      return TrackpadAccelProfile.strong;
    case 'medium':
    default:
      return TrackpadAccelProfile.medium;
  }
}

String trackpadAccelProfileToString(TrackpadAccelProfile p) => p.name;

/// Gain curve parameters: gain rises smoothly from [gMin] at [v1] mm/s to
/// [gMax] at [v2] mm/s.
class TrackpadCurve {
  final double gMin;
  final double gMax;
  final double v1;
  final double v2;

  const TrackpadCurve(
      {required this.gMin, required this.gMax, this.v1 = 40, this.v2 = 300});

  static TrackpadCurve forProfile(TrackpadAccelProfile p) {
    switch (p) {
      case TrackpadAccelProfile.off:
        return const TrackpadCurve(gMin: 1.0, gMax: 1.0);
      case TrackpadAccelProfile.light:
        return const TrackpadCurve(gMin: 1.0, gMax: 2.2);
      case TrackpadAccelProfile.medium:
        return const TrackpadCurve(gMin: 1.0, gMax: 3.5);
      case TrackpadAccelProfile.strong:
        return const TrackpadCurve(gMin: 0.9, gMax: 5.0, v2: 260);
    }
  }

  /// Gain for a finger speed in mm/s.
  double gain(double speedMmPerSec) {
    if (gMax == gMin) return gMin;
    final t = ((speedMmPerSec - v1) / (v2 - v1)).clamp(0.0, 1.0);
    final s = t * t * (3 - 2 * t); // smoothstep
    return gMin + (gMax - gMin) * s;
  }
}

/// Stateful transformer: feed raw finger deltas, get cursor deltas.
class TrackpadBallistics {
  /// User sensitivity multiplier, 0.2 - 5.0.
  double sensitivity;
  TrackpadCurve curve;

  /// Speed smoothing factor (EMA), higher = more responsive.
  final double speedSmoothing;

  double _speed = 0; // mm/s, smoothed
  int? _lastMicros;

  TrackpadBallistics({
    this.sensitivity = 1.0,
    TrackpadAccelProfile profile = TrackpadAccelProfile.medium,
    this.speedSmoothing = 0.5,
  }) : curve = TrackpadCurve.forProfile(profile);

  static const double minSensitivity = 0.2;
  static const double maxSensitivity = 5.0;

  set profile(TrackpadAccelProfile p) => curve = TrackpadCurve.forProfile(p);

  /// Call when a new pan starts so the previous gesture's speed is forgotten.
  void reset() {
    _speed = 0;
    _lastMicros = null;
  }

  /// Current smoothed speed, mm/s (for tests and debugging).
  double get speedMmPerSec => _speed;

  /// Transform one raw delta (logical px) observed at [timestampMicros].
  /// Returns the cursor delta in logical px of the phone screen.
  (double, double) transform(double dx, double dy, int timestampMicros) {
    final dist = math.sqrt(dx * dx + dy * dy);
    final last = _lastMicros;
    _lastMicros = timestampMicros;
    if (dist == 0) return (0, 0);
    if (last != null) {
      // Clamp dt: events closer than 2 ms are batched samples, gaps longer
      // than 100 ms mean the finger paused, so speed restarts from this sample.
      final dtUs = (timestampMicros - last).clamp(2000, 100000);
      final instant = dist * kMmPerLogicalPixel / (dtUs / 1e6);
      _speed = timestampMicros - last >= 100000
          ? instant
          : _speed + speedSmoothing * (instant - _speed);
    }
    final s = sensitivity.clamp(minSensitivity, maxSensitivity);
    final g = curve.gain(_speed) * s;
    return (dx * g, dy * g);
  }
}
