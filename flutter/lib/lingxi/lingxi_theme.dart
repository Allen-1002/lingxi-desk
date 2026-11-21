// Nimbo visual language: soft aurora background, frosted glass panels.
//
// On macOS the main window is made translucent natively (NSVisualEffectView,
// see macos/Runner/MainFlutterWindow.swift), so the desktop background there
// is the real system blur and these panels sit on top of it. Elsewhere we
// paint an aurora gradient and blur it inside each glass panel.

import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Display name of the app, in one place so a rename touches one line.
const String kLxAppName = 'Nimbo';

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
  static Color solidGlassFill(BuildContext c) => isDark(c)
      ? const Color(0xFF1C1E26).withOpacity(0.82)
      : Colors.white.withOpacity(0.78);
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

/// Phones skip the live backdrop blur (see [Glass]).
bool get lxCheapGlass => Platform.isAndroid || Platform.isIOS;

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
    // A live blur under every panel costs a full re-blur each frame on phones
    // and made scrolling and sheet animations stutter. Phones get a solid
    // frosted fill over the aurora instead, which looks almost the same.
    if (lxCheapGlass) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: LxColors.solidGlassFill(context),
          borderRadius: r,
          border: Border.all(color: LxColors.glassBorder(context), width: 1),
        ),
        child: child,
      );
    }
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

/// The app mark: a white cloud on the teal-to-indigo tile (Nimbo).
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
    // Same drawing as res/lingxi/make_icons.py: glyph box is 80% of the tile.
    final g = s.width * 0.8, o = s.width * 0.1, oy = s.width * 0.12;
    final white = Paint()..color = Colors.white;
    const dy = 0.03;
    for (final (cx, cy, rr) in const [
      (0.33, 0.56 + dy, 0.17),
      (0.54, 0.44 + dy, 0.22),
      (0.72, 0.58 + dy, 0.15),
    ]) {
      canvas.drawCircle(Offset(o + cx * g, oy + cy * g), rr * g, white);
    }
    canvas.drawRRect(
        RRect.fromLTRBR(o + 0.16 * g, oy + (0.55 + dy) * g, o + 0.87 * g,
            oy + (0.73 + dy) * g, Radius.circular(0.09 * g)),
        white);
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

// ---------------------------------------------------------------------------
// Settings building blocks: grouped cards of rows, like system settings.

/// Large page title with an optional line under it.
class LxPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const LxPageHeader(this.title, {super.key, this.subtitle});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  fontSize: 28,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: LxColors.text(context))),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!,
                style: TextStyle(fontSize: 14, color: LxColors.subtext(context))),
          ],
        ]),
      );
}

/// A titled card holding [children] separated by inset hairlines.
class LxGroup extends StatelessWidget {
  final String? title;
  final String? footer;
  final List<Widget> children;
  const LxGroup({super.key, this.title, this.footer, required this.children});

  static Color fill(BuildContext c) => LxColors.isDark(c)
      ? const Color(0xFF1B1D26).withOpacity(lxCheapGlass ? 0.92 : 0.72)
      : Colors.white.withOpacity(lxCheapGlass ? 0.90 : 0.74);

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 60),
          child: Divider(height: 1, thickness: 1, color: LxColors.hairline(context)),
        ));
      }
      rows.add(children[i]);
    }
    final card = Container(
      decoration: BoxDecoration(
        color: fill(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LxColors.hairline(context)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(LxColors.isDark(context) ? 0.25 : 0.04),
              blurRadius: 18,
              offset: const Offset(0, 6)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Text(title!.toUpperCase(),
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: LxColors.subtext(context))),
          ),
        card,
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
            child: Text(footer!,
                style: TextStyle(
                    fontSize: 12.5, height: 1.45, color: LxColors.subtext(context))),
          ),
      ]),
    );
  }
}

/// Rounded tinted square with an icon, used at the start of a row.
class LxIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const LxIconBadge(this.icon, this.color, {super.key, this.size = 32});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.85), color],
          ),
        ),
        child: Icon(icon, size: size * 0.56, color: Colors.white),
      );
}

/// One settings row: badge, title, optional subtitle, trailing control, and
/// an optional [below] widget (a slider, a segmented control).
class LxRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? below;
  final VoidCallback? onTap;
  final bool chevron;
  const LxRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.trailing,
    this.below,
    this.onTap,
    this.chevron = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(children: [
        Row(children: [
          LxIconBadge(icon, color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: LxColors.text(context))),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle!,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: LxColors.subtext(context))),
              ],
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          if (chevron)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(Icons.chevron_right_rounded,
                  size: 22, color: LxColors.subtext(context).withOpacity(0.7)),
            ),
        ]),
        if (below != null)
          Padding(padding: const EdgeInsets.only(left: 46, top: 10), child: below!),
      ]),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

/// Switch in the app's colors.
class LxSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const LxSwitch({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeColor: Colors.white,
        activeTrackColor: LxColors.indigoDeep,
      );
}

/// Pill-shaped segmented control.
class LxSegmented<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final bool compact;
  const LxSegmented(
      {super.key,
      required this.items,
      required this.value,
      required this.onChanged,
      this.compact = false});

  @override
  Widget build(BuildContext context) {
    final dark = LxColors.isDark(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: LxColors.chip(context), borderRadius: BorderRadius.circular(11)),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: items.map((e) {
          final sel = e.$1 == value;
          final cell = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(e.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              height: compact ? 30 : 34,
              padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel
                    ? (dark ? Colors.white.withOpacity(0.16) : Colors.white)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                boxShadow: sel && !dark
                    ? [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2))
                      ]
                    : null,
              ),
              child: Text(e.$2,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                      color: sel
                          ? (dark ? Colors.white : LxColors.indigoDeep)
                          : LxColors.subtext(context))),
            ),
          );
          return compact ? cell : Expanded(child: cell);
        }).toList(),
      ),
    );
  }
}

/// Small colored status pill ("已连接").
class LxStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const LxStatusPill(this.label, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      );
}
