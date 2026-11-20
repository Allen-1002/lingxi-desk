// Lingxi Desk visual language: soft aurora background, frosted glass panels.
//
// On macOS the main window is made translucent natively (NSVisualEffectView,
// see macos/Runner/MainFlutterWindow.swift), so the desktop background there
// is the real system blur and these panels sit on top of it. Elsewhere we
// paint an aurora gradient and blur it inside each glass panel.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class LxColors {
  static const indigo = Color(0xFF4F46E5);
  static const indigoDeep = Color(0xFF4338CA);
  static const teal = Color(0xFF14B8A6);
  static const online = Color(0xFF10B981);
  static const warn = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);

  static bool isDark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color text(BuildContext c) =>
      isDark(c) ? const Color(0xFFF3F4F8) : const Color(0xFF12141C);
  static Color subtext(BuildContext c) =>
      isDark(c) ? const Color(0xFFB4B8C5) : const Color(0xFF555B6B);
  static Color glassFill(BuildContext c) => isDark(c)
      ? const Color(0xFF1C1E26).withOpacity(0.55)
      : Colors.white.withOpacity(0.62);
  static Color glassBorder(BuildContext c) => isDark(c)
      ? Colors.white.withOpacity(0.10)
      : Colors.white.withOpacity(0.75);
  static Color hairline(BuildContext c) => isDark(c)
      ? Colors.white.withOpacity(0.08)
      : const Color(0xFF12141C).withOpacity(0.07);
  static Color chip(BuildContext c) => isDark(c)
      ? Colors.white.withOpacity(0.08)
      : const Color(0xFF12141C).withOpacity(0.05);
}

/// True when the native window already provides the blur. Off for now: the
/// behind-window NSVisualEffectView swallowed input on macOS, so every
/// platform draws the aurora background and blurs it in Flutter.
const bool lxNativeVibrancy = false;

/// Full-screen aurora background. Transparent on macOS desktop so the native
/// vibrancy shows through.
class LxBackground extends StatelessWidget {
  final Widget child;
  final bool forceAurora;
  const LxBackground({super.key, required this.child, this.forceAurora = false});

  @override
  Widget build(BuildContext context) {
    if (lxNativeVibrancy && !forceAurora) {
      return Container(
        color: LxColors.isDark(context)
            ? Colors.black.withOpacity(0.10)
            : Colors.white.withOpacity(0.18),
        child: child,
      );
    }
    final dark = LxColors.isDark(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [Color(0xFF0E1018), Color(0xFF141726)]
                  : const [Color(0xFFF3F5FB), Color(0xFFE9ECF7)],
            ),
          ),
        ),
        _blob(const Alignment(-1.1, -0.9), 420,
            LxColors.teal.withOpacity(dark ? 0.30 : 0.35)),
        _blob(const Alignment(1.2, -0.3), 380,
            LxColors.indigo.withOpacity(dark ? 0.35 : 0.30)),
        _blob(const Alignment(-0.4, 1.2), 360,
            const Color(0xFF8B5CF6).withOpacity(dark ? 0.22 : 0.20)),
        child,
      ],
    );
  }

  Widget _blob(Alignment a, double size, Color color) => Align(
        alignment: a,
        child: IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [color, color.withOpacity(0)]),
            ),
          ),
        ),
      );
}

/// A frosted glass panel.
class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
    this.blur = 24,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: LxColors.glassFill(context),
            borderRadius: r,
            border: Border.all(color: LxColors.glassBorder(context), width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The app mark: two arcs holding one point (心有灵犀一点通).
class LxLogo extends StatelessWidget {
  final double size;
  const LxLogo({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _LogoPainter()),
      );
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final r = RRect.fromRectAndRadius(
        Offset.zero & s, Radius.circular(s.width * 0.225));
    canvas.drawRRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [LxColors.teal, LxColors.indigo],
        ).createShader(Offset.zero & s),
    );
    final u = s.width / 100;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8 * u
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
        Path()
          ..moveTo(38.8 * u, 77.2 * u)
          ..quadraticBezierTo(18 * u, 50 * u, 43.6 * u, 42 * u),
        stroke);
    canvas.drawPath(
        Path()
          ..moveTo(61.2 * u, 77.2 * u)
          ..quadraticBezierTo(82 * u, 50 * u, 56.4 * u, 42 * u),
        stroke);
    canvas.drawCircle(Offset(50 * u, 30 * u), 6.4 * u, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Primary pill button.
class LxButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;
  final IconData? icon;
  final double height;
  const LxButton(this.label,
      {super.key,
      this.onPressed,
      this.secondary = false,
      this.icon,
      this.height = 44});

  @override
  Widget build(BuildContext context) {
    final fg = secondary ? LxColors.text(context) : Colors.white;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
        Text(label,
            style: TextStyle(
                color: fg, fontSize: 15, fontWeight: FontWeight.w600)),
      ],
    );
    return SizedBox(
      height: height,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: secondary ? LxColors.chip(context) : LxColors.indigoDeep,
          disabledBackgroundColor: LxColors.chip(context),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(height / 2)),
        ),
        child: child,
      ),
    );
  }
}

/// Six-digit device codes are shown as "123 456".
String lxFormatCode(String id) {
  if (id.length == 6 && int.tryParse(id) != null) {
    return '${id.substring(0, 3)} ${id.substring(3)}';
  }
  return id;
}

IconData lxPlatformIcon(String platform) {
  final p = platform.toLowerCase();
  if (p.contains('mac')) return Icons.laptop_mac_rounded;
  if (p.contains('win')) return Icons.desktop_windows_rounded;
  if (p.contains('android')) return Icons.phone_android_rounded;
  if (p.contains('ios')) return Icons.phone_iphone_rounded;
  if (p.contains('linux')) return Icons.computer_rounded;
  return Icons.devices_rounded;
}

class LxSectionTitle extends StatelessWidget {
  final String text;
  const LxSectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: LxColors.subtext(context))),
      );
}
