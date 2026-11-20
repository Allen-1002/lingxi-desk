// Lingxi Desk computer main window: this computer, pairing QR, my devices,
// settings. Replaces the upstream tabbed home page.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../common.dart';
import '../consts.dart';
import '../models/platform_model.dart';
import '../utils/multi_window_manager.dart';
import 'lingxi_devices.dart';
import 'lingxi_server.dart';
import 'lingxi_theme.dart';
import 'lingxi_update.dart';

class LingxiDesktopHome extends StatefulWidget {
  const LingxiDesktopHome({super.key});

  @override
  State<LingxiDesktopHome> createState() => _LingxiDesktopHomeState();
}

enum _Page { thisMac, devices, settings }

class _LingxiDesktopHomeState extends State<LingxiDesktopHome>
    with WindowListener {
  _Page _page = _Page.thisMac;
  Timer? _timer;
  String _id = '';
  String _pairKey = '';
  List<String> _ips = [];
  bool _serviceOn = true;
  bool _screen = true, _access = true, _daemon = true;

  String get _hostname {
    try {
      return Platform.localHostname.replaceAll('.local', '');
    } catch (_) {
      return '这台电脑';
    }
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    gFFI.lanPeersModel.addListener(_changed);
    gFFI.recentPeersModel.addListener(_changed);
    lxRefreshDevices();
    lxEnsureSelfPairKey().then((k) {
      if (mounted) setState(() => _pairKey = k);
    });
    _tick();
    LxUpdater.instance.check();
    _timer = Timer.periodic(const Duration(seconds: 2), (t) {
      _tick();
      if (t.tick % 5 == 0) lxRefreshDevices();
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _timer?.cancel();
    gFFI.lanPeersModel.removeListener(_changed);
    gFFI.recentPeersModel.removeListener(_changed);
    super.dispose();
  }

  /// The close button hides the main window (upstream prevents a real
  /// close): the app keeps running so this computer stays reachable.
  @override
  void onWindowClose() async {
    if (rustDeskWinManager.getActiveWindows().contains(kMainWindowId)) {
      await rustDeskWinManager.unregisterActiveWindow(kMainWindowId);
    }
    if (isMacOS && await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
      await Future.delayed(const Duration(milliseconds: 800));
    }
    await windowManager.hide();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _tick() async {
    await gFFI.serverModel.fetchID();
    final id = gFFI.serverModel.serverId.text.replaceAll(" ", "");
    final ips = await lxLocalIps();
    final stopped = await mainGetBoolOption(kOptionStopService);
    bool screen = true, access = true, daemon = true;
    if (isMacOS) {
      screen = bind.mainIsCanScreenRecording(prompt: false);
      access = bind.mainIsProcessTrusted(prompt: false);
      daemon = !bind.mainIsInstalled() || bind.mainIsInstalledDaemon(prompt: false);
    }
    if (!mounted) return;
    setState(() {
      _id = id;
      _ips = ips;
      _serviceOn = !stopped;
      _screen = screen;
      _access = access;
      _daemon = daemon;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LxBackground(
        child: Row(children: [
          _sidebar(context),
          Expanded(
            child: Column(children: [
              // Window drag area across the top (traffic lights live left).
              const SizedBox(height: 36, child: _DragArea()),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: switch (_page) {
                    _Page.thisMac => _thisComputer(context),
                    _Page.devices => _devices(context),
                    _Page.settings => const _DesktopSettings(),
                  },
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _sidebar(BuildContext context) {
    Widget nav(_Page p, IconData icon, String label) {
      final sel = _page == p;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: sel ? LxColors.indigo.withOpacity(0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _page = p),
            child: SizedBox(
              height: 38,
              child: Row(children: [
                const SizedBox(width: 12),
                Icon(icon,
                    size: 19,
                    color: sel ? LxColors.indigoDeep : LxColors.subtext(context)),
                const SizedBox(width: 10),
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                        color: sel ? LxColors.indigoDeep : LxColors.text(context))),
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 210,
      decoration: BoxDecoration(
        color: lxNativeVibrancy ? Colors.transparent : LxColors.glassFill(context),
        border: Border(right: BorderSide(color: LxColors.hairline(context))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 52, child: _DragArea()),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Row(children: [
            const LxLogo(size: 28),
            const SizedBox(width: 10),
            Text('灵犀',
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: LxColors.text(context))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(children: [
            nav(_Page.thisMac, Icons.computer_rounded, '本机'),
            nav(_Page.devices, Icons.devices_other_rounded, '我的设备'),
            nav(_Page.settings, Icons.tune_rounded, '设置'),
          ]),
        ),
      ]),
    );
  }

  Widget _thisComputer(BuildContext context) {
    final ready = _serviceOn && _screen && _access && _daemon;
    final payload = (_id.isNotEmpty && _pairKey.isNotEmpty)
        ? lxPairingPayload(id: _id, key: _pairKey, ips: _ips, name: _hostname)
        : '';
    return ListView(
      key: const ValueKey('this'),
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
      children: [
        const LxUpdateTile(banner: true),
        LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth > 760;
          final info = Glass(
            radius: 20,
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('本机',
                            style: TextStyle(
                                fontSize: 13, color: LxColors.subtext(context))),
                        const SizedBox(height: 4),
                        Text(_hostname,
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: LxColors.text(context))),
                      ]),
                ),
                Text('允许被控制',
                    style: TextStyle(fontSize: 14, color: LxColors.text(context))),
                const SizedBox(width: 8),
                Switch(
                  value: _serviceOn,
                  activeColor: Colors.white,
                  activeTrackColor: LxColors.indigoDeep,
                  onChanged: (v) async {
                    await bind.mainSetOption(
                        key: kOptionStopService, value: v ? '' : 'Y');
                    _tick();
                  },
                ),
              ]),
              const SizedBox(height: 18),
              Text('设备码',
                  style: TextStyle(fontSize: 13, color: LxColors.subtext(context))),
              const SizedBox(height: 4),
              Row(children: [
                SelectableText(_id.isEmpty ? '······' : lxFormatCode(_id),
                    style: TextStyle(
                        fontSize: 40,
                        letterSpacing: 4,
                        fontWeight: FontWeight.w700,
                        color: LxColors.text(context),
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '复制设备码',
                  icon: Icon(Icons.copy_rounded,
                      size: 18, color: LxColors.subtext(context)),
                  onPressed: _id.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: _id));
                          showToast('已复制');
                        },
                ),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ready ? LxColors.online : LxColors.warn),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ready
                        ? '可以被控制${_ips.isEmpty ? '' : ' · 局域网 ${_ips.first}'}'
                        : (_serviceOn ? '还差几步设置，见下方' : '已关闭，别人连不上这台电脑'),
                    style: TextStyle(fontSize: 14, color: LxColors.subtext(context)),
                  ),
                ),
              ]),
            ]),
          );
          final qr = Glass(
            radius: 20,
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Text('用手机扫码，添加这台电脑',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: LxColors.text(context))),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: payload.isEmpty
                    ? const SizedBox(
                        width: 160,
                        height: 160,
                        child: Center(child: CircularProgressIndicator()))
                    : QrImageView(
                        data: payload,
                        size: 160,
                        padding: EdgeInsets.zero,
                        eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square, color: Color(0xFF12141C)),
                        dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFF12141C)),
                      ),
              ),
              const SizedBox(height: 12),
              Text('扫过一次后，手机点一下就能连，不用密码',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: LxColors.subtext(context))),
            ]),
          );
          return wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: info),
                  const SizedBox(width: 18),
                  Expanded(flex: 2, child: qr),
                ])
              : Column(children: [info, const SizedBox(height: 18), qr]);
        }),
        if (isMacOS) ...[
          const SizedBox(height: 22),
          const LxSectionTitle('系统权限'),
          Glass(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(children: [
              _permRow(context, '屏幕录制', '让手机看到这台电脑的画面', _screen, () {
                bind.mainIsCanScreenRecording(prompt: true);
                launchUrl(Uri.parse(
                    'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture'));
              }),
              Divider(height: 1, color: LxColors.hairline(context)),
              _permRow(context, '辅助功能', '让手机操作鼠标和键盘', _access, () {
                // macOS shows its own prompt only once per app; open the
                // settings pane so the button always does something.
                bind.mainIsProcessTrusted(prompt: true);
                launchUrl(Uri.parse(
                    'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'));
              }),
              Divider(height: 1, color: LxColors.hairline(context)),
              _permRow(context, '后台服务', '锁屏、没登录时也能连（需要输入一次 Mac 密码）',
                  _daemon, () {
                bind.mainIsInstalledDaemon(prompt: true);
              }),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _permRow(BuildContext context, String title, String sub, bool ok,
      VoidCallback fix) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded,
            color: ok ? LxColors.online : LxColors.warn, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: LxColors.text(context))),
            const SizedBox(height: 2),
            Text(sub,
                style: TextStyle(fontSize: 13, color: LxColors.subtext(context))),
          ]),
        ),
        ok
            ? Text('已开启',
                style: TextStyle(
                    fontSize: 14,
                    color: LxColors.online,
                    fontWeight: FontWeight.w600))
            : LxButton('去开启', height: 34, onPressed: fix),
      ]),
    );
  }

  Widget _devices(BuildContext context) {
    final devices = lxCollectDevices(_id);
    final ctrl = TextEditingController();
    return ListView(
      key: const ValueKey('devices'),
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
      children: [
        Text('我的设备',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: LxColors.text(context))),
        const SizedBox(height: 18),
        Glass(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(
                    fontSize: 18, letterSpacing: 3, color: LxColors.text(context)),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '输入 6 位设备码',
                  filled: true,
                  fillColor: LxColors.chip(context),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
                onSubmitted: (v) => lxConnect(context, v),
              ),
            ),
            const SizedBox(width: 12),
            LxButton('连接', onPressed: () => lxConnect(context, ctrl.text)),
          ]),
        ),
        const SizedBox(height: 20),
        if (devices.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('同一网络里的灵犀设备会自动出现在这里',
                textAlign: TextAlign.center,
                style: TextStyle(color: LxColors.subtext(context))),
          )
        else
          Glass(
            padding: const EdgeInsets.all(4),
            child: Column(
              children: devices
                  .map((d) => LxDeviceTile(
                        device: d,
                        onTap: () => lxConnect(context, d.id),
                        trailing: LxButton('连接',
                            height: 34,
                            secondary: true,
                            onPressed: () => lxConnect(context, d.id)),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _DesktopSettings extends StatefulWidget {
  const _DesktopSettings();
  @override
  State<_DesktopSettings> createState() => _DesktopSettingsState();
}

class _DesktopSettingsState extends State<_DesktopSettings> {
  late bool _lanDirect;
  late String _quality;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _lanDirect = option2bool(kOptionDirectServer,
        bind.mainGetOptionSync(key: kOptionDirectServer));
    _quality = bind.mainGetUserDefaultOption(key: kOptionImageQuality);
    LxUpdater.instance.loadCurrent();
    bind.mainGetVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    TextStyle t() => TextStyle(fontSize: 15, color: LxColors.text(context));
    TextStyle s() => TextStyle(fontSize: 13, color: LxColors.subtext(context));
    Widget qualityChip(String v, String label) {
      final sel = (_quality.isEmpty ? kRemoteImageQualityBalanced : _quality) == v;
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: sel,
          selectedColor: LxColors.indigo.withOpacity(0.18),
          onSelected: (_) {
            setState(() => _quality = v);
            bind.mainSetUserDefaultOption(key: kOptionImageQuality, value: v);
          },
        ),
      );
    }

    return ListView(
      key: const ValueKey('settings'),
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
      children: [
        Text('设置',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: LxColors.text(context))),
        const SizedBox(height: 18),
        const LxSectionTitle('连接'),
        Glass(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('局域网直连', style: t()),
                const SizedBox(height: 2),
                Text('同一网络里的设备不经过服务器，直接连接这台电脑', style: s()),
              ]),
            ),
            Switch(
              value: _lanDirect,
              activeColor: Colors.white,
              activeTrackColor: LxColors.indigoDeep,
              onChanged: (v) async {
                setState(() => _lanDirect = v);
                await bind.mainSetOption(
                    key: kOptionDirectServer, value: v ? 'Y' : 'N');
              },
            ),
          ]),
        ),
        const SizedBox(height: 18),
        const LxSectionTitle('控制别的电脑时的画质'),
        Glass(
          child: Row(children: [
            Expanded(child: Text('画质偏好', style: t())),
            qualityChip(kRemoteImageQualityLow, '流畅'),
            qualityChip(kRemoteImageQualityBalanced, '平衡'),
            qualityChip(kRemoteImageQualityBest, '清晰'),
          ]),
        ),
        const SizedBox(height: 18),
        const LxSectionTitle('连接'),
        const Glass(child: LxServerTile()),
        const SizedBox(height: 18),
        const LxSectionTitle('关于'),
        Glass(
          child: Column(children: [
            Row(children: [
              const LxLogo(size: 28),
              const SizedBox(width: 12),
              Text('灵犀', style: t()),
              const Spacer(),
              Text('内核 $_version', style: s()),
            ]),
            const SizedBox(height: 12),
            Divider(height: 1, color: LxColors.hairline(context)),
            const SizedBox(height: 10),
            const LxUpdateTile(),
          ]),
        ),
      ],
    );
  }
}

/// Empty strip that moves the window when dragged (the title bar is hidden).
class _DragArea extends StatelessWidget {
  const _DragArea();
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => windowManager.startDragging(),
        onDoubleTap: () async {
          if (await windowManager.isMaximized()) {
            windowManager.unmaximize();
          } else {
            windowManager.maximize();
          }
        },
        child: const SizedBox.expand(),
      );
}
