import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common/widgets/trackpad_ballistics.dart';

void main() {
  group('TrackpadCurve', () {
    test('off profile is linear', () {
      final c = TrackpadCurve.forProfile(TrackpadAccelProfile.off);
      expect(c.gain(0), 1.0);
      expect(c.gain(1000), 1.0);
    });

    test('medium profile rises from gMin to gMax monotonically', () {
      final c = TrackpadCurve.forProfile(TrackpadAccelProfile.medium);
      expect(c.gain(0), closeTo(1.0, 1e-9));
      expect(c.gain(40), closeTo(1.0, 1e-9));
      expect(c.gain(300), closeTo(3.5, 1e-9));
      expect(c.gain(5000), closeTo(3.5, 1e-9));
      var prev = 0.0;
      for (var v = 0.0; v <= 400; v += 5) {
        final g = c.gain(v);
        expect(g, greaterThanOrEqualTo(prev));
        prev = g;
      }
    });
  });

  group('TrackpadBallistics', () {
    test('first sample after reset uses minimum gain times sensitivity', () {
      final b = TrackpadBallistics(sensitivity: 2.0);
      final (dx, dy) = b.transform(3, 4, 0);
      expect(dx, closeTo(6, 1e-9));
      expect(dy, closeTo(8, 1e-9));
    });

    test('slow movement keeps 1:1 for precision', () {
      final b = TrackpadBallistics();
      var t = 0;
      double total = 0;
      // 1 logical px every 8 ms ~= 20 mm/s, below v1.
      for (var i = 0; i < 50; i++) {
        t += 8000;
        total += b.transform(1, 0, t).$1;
      }
      expect(total, closeTo(50, 1e-6));
    });

    test('fast flick is accelerated', () {
      final b = TrackpadBallistics();
      var t = 0;
      double total = 0;
      // 40 logical px every 8 ms ~= 790 mm/s, above v2.
      for (var i = 0; i < 20; i++) {
        t += 8000;
        total += b.transform(40, 0, t).$1;
      }
      expect(total, greaterThan(40 * 20 * 3.0));
    });

    test('a pause resets speed', () {
      final b = TrackpadBallistics();
      var t = 0;
      for (var i = 0; i < 20; i++) {
        t += 8000;
        b.transform(40, 0, t);
      }
      t += 500000; // finger rests for 0.5 s
      final (dx, _) = b.transform(1, 0, t);
      expect(dx, closeTo(1, 1e-9));
    });

    test('sensitivity is clamped', () {
      final b = TrackpadBallistics(sensitivity: 100);
      expect(b.transform(1, 0, 0).$1, TrackpadBallistics.maxSensitivity);
    });

    test('profile parsing falls back to medium', () {
      expect(trackpadAccelProfileFromString(null), TrackpadAccelProfile.medium);
      expect(trackpadAccelProfileFromString('bogus'),
          TrackpadAccelProfile.medium);
      expect(trackpadAccelProfileFromString('off'), TrackpadAccelProfile.off);
    });
  });
}
