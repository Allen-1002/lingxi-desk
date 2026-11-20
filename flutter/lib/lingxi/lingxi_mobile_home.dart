// Lingxi Desk phone home: my devices, add device, settings.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';

import '../common.dart';
import '../common/widgets/trackpad_ballistics.dart';
import '../consts.dart';
import '../models/platform_model.dart';
import 'lingxi_devices.dart';
import 'lingxi_theme.dart';
import 'lingxi_update.dart';

class LingxiMobileHome extends StatefulWidget {
  const LingxiMobileHome({super.key});

  @override
  State<LingxiMobileHome> createState() => _LingxiMobileHomeState();
}

class _LingxiMobileHomeState extends State<LingxiMobileHome> {
  int _tab = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    gFFI.lanPeersModel.addListener(_changed);
    gFFI.recentPeersModel.addListener(_changed);
    lxRefreshDevices();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => lxRefreshDevices());
    LxUpdater.instance.check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    gFFI.lanPeersModel.removeListener(_changed);
    gFFI.recentPeersModel.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final overlay = LxColors.isDark(context)
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: LxBackground(
          forceAurora: true,
          child: SafeArea(
            bottom: false,
            child: _tab == 0 ? _devicesTab(context) : const _SettingsTab(),
          ),
        ),
        bottomNavigationBar: _bottomBar(context),
      ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    Widget item(int i, IconData icon, String label) {
      final sel = _tab == i;
      final color = sel ? LxColors.indigoDeep : LxColors.subtext(context);
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: color),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
            ]),
          ),
        ),
      );
    }

    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, math.max(bottom, 12)),
      child: Glass(
        radius: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(children: [
          item(0, Icons.devices_rounded, '设备'),
          item(1, Icons.tune_rounded, '设置'),
        ]),
      ),
    );
  }

  Widget _devicesTab(BuildContext context) {
    final devices = lxCollectDevices('');
    final paired = devices.where((d) => d.paired).toList();
    final others = devices.where((d) => !d.paired).toList();
    return RefreshIndicator(
      onRefresh: () async {
        lxRefreshDevices();
        await Future.delayed(const Duration(milliseconds: 800));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Row(children: [
            const LxLogo(size: 32),
            const SizedBox(width: 10),
            Text('灵犀',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: LxColors.text(context))),
            const Spacer(),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton.filled(
                tooltip: '添加设备',
                style: IconButton.styleFrom(backgroundColor: LxColors.indigoDeep),
                onPressed: () => _showAdd(context),
                icon: const Icon(Icons.add_rounded, color: Colors.white),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          const LxUpdateTile(banner: true),
          if (devices.isEmpty) _emptyState(context),
          if (paired.isNotEmpty) ...[
            LxSectionTitle('我的设备 · ${paired.length}'),
            Glass(
              padding: const EdgeInsets.all(4),
              child: Column(
                  children: paired
                      .map((d) => LxDeviceTile(
                          device: d, onTap: () => lxConnect(context, d.id)))
                      .toList()),
            ),
            const SizedBox(height: 18),
          ],
          if (others.isNotEmpty) ...[
            LxSectionTitle(paired.isEmpty ? '附近和最近的设备' : '其他设备'),
            Glass(
              padding: const EdgeInsets.all(4),
              child: Column(
                  children: others
                      .map((d) => LxDeviceTile(
                          device: d, onTap: () => _showPairChoice(context, d)))
                      .toList()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) => Glass(
        padding: const EdgeInsets.all(22),
        child: Column(children: [
          Icon(Icons.wifi_find_rounded, size: 40, color: LxColors.indigoDeep),
          const SizedBox(height: 12),
          Text('还没有设备',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: LxColors.text(context))),
          const SizedBox(height: 6),
          Text('在电脑上打开灵犀，用右上角的「+」扫它窗口里的二维码。\n同一个 Wi-Fi 里的电脑也会自动出现在这里。',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.6, color: LxColors.subtext(context))),
          const SizedBox(height: 16),
          LxButton('扫码添加',
              icon: Icons.qr_code_scanner_rounded,
              onPressed: () => _openScanner(context)),
        ]),
      );

  void _showAdd(BuildContext context) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Glass(
            radius: 26,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('添加设备',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: LxColors.text(ctx))),
                const SizedBox(height: 16),
                LxButton('扫电脑上的二维码（推荐）',
                    icon: Icons.qr_code_scanner_rounded, onPressed: () {
                  Navigator.pop(ctx);
                  _openScanner(context);
                }),
                const SizedBox(height: 8),
                Text('扫一次就配对好，以后点一下就连，不用密码。',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 12, color: LxColors.subtext(ctx))),
                const SizedBox(height: 20),
                Text('或输入 6 位设备码',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: LxColors.subtext(ctx))),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  autofocus: false,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 28,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w600,
                      color: LxColors.text(ctx)),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '000000',
                    filled: true,
                    fillColor: LxColors.chip(ctx),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 6),
                Text('用设备码连接时，需要在电脑上点一次「接受」。',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 12, color: LxColors.subtext(ctx))),
                const SizedBox(height: 14),
                LxButton('连接', secondary: true, onPressed: () {
                  final code = ctrl.text.trim();
                  if (code.length != 6) return;
                  Navigator.pop(ctx);
                  lxConnect(context, code);
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// An unpaired device: offer QR pairing first (no password ever after),
  /// or a one-off connection the computer has to accept.
  void _showPairChoice(BuildContext context, LxDevice d) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(12),
        child: Glass(
          radius: 26,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(d.name,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: LxColors.text(ctx))),
              const SizedBox(height: 4),
              Text('这台设备还没配对',
                  style: TextStyle(fontSize: 13, color: LxColors.subtext(ctx))),
              const SizedBox(height: 18),
              LxButton('扫码配对（推荐）',
                  icon: Icons.qr_code_scanner_rounded, onPressed: () {
                Navigator.pop(ctx);
                _openScanner(context);
              }),
              const SizedBox(height: 6),
              Text('扫它窗口里的二维码，以后点一下就连，不用密码',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: LxColors.subtext(ctx))),
              const SizedBox(height: 14),
              LxButton('只连这一次', secondary: true, onPressed: () {
                Navigator.pop(ctx);
                lxConnect(context, d.id);
              }),
              const SizedBox(height: 6),
              Text('需要在电脑上点「接受」',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: LxColors.subtext(ctx))),
            ],
          ),
        ),
      ),
    );
  }

  void _openScanner(BuildContext context) async {
    final id = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const _PairScanPage()));
    if (id != null && mounted) {
      setState(() {});
      lxConnect(this.context, id);
    }
  }
}

class _PairScanPage extends StatefulWidget {
  const _PairScanPage();
  @override
  State<_PairScanPage> createState() => _PairScanPageState();
}

class _PairScanPageState extends State<_PairScanPage> {
  final _qrKey = GlobalKey(debugLabel: 'lingxi-qr');
  QRViewController? _ctrl;
  StreamSubscription? _sub;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _sub?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('扫码配对'),
      ),
      body: Stack(children: [
        QRView(
          key: _qrKey,
          overlay: QrScannerOverlayShape(
            borderColor: LxColors.teal,
            borderRadius: 16,
            borderLength: 34,
            borderWidth: 6,
            cutOutSize: 240,
          ),
          onQRViewCreated: (c) {
            _ctrl = c;
            _sub = c.scannedDataStream.listen((d) async {
              final code = d.code;
              if (_done || code == null) return;
              final id = await lxApplyPairingPayload(code);
              if (!mounted) return;
              if (id == null) {
                setState(() => _error = '这不是灵犀的配对二维码');
                return;
              }
              _done = true;
              Navigator.of(context).pop(id);
            });
          },
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 48,
          child: Text(
            _error ?? '对准电脑上灵犀窗口里的二维码',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: _error == null ? Colors.white : const Color(0xFFFCA5A5),
                fontSize: 15),
          ),
        ),
      ]),
    );
  }
}

String _controlHint(String mode) {
  const common = '双指上下滑动＝滚动，双指张合＝放大缩小，三指上滑＝调度中心（Windows 为任务视图），三指左右滑＝切换桌面。';
  switch (mode) {
    case 'touch':
      return '手指点哪里就点到哪里，长按＝右键。$common';
    case 'trackpad':
      return '屏幕当触控板用，单指移动箭头，轻点＝左键，长按＝右键。$common';
    default:
      return '屏幕上有一个鼠标，按住它拖动来移动箭头，点它的左键、右键，按滚轮来滚动。一会儿不用它会自动缩小，点一下就展开。$common';
  }
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();
  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  late double _sensitivity;
  late TrackpadAccelProfile _accel;
  late String _quality;
  late String _control;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _sensitivity = double.tryParse(
            bind.mainGetLocalOption(key: kOptionTrackpadSensitivity)) ??
        1.0;
    _accel = trackpadAccelProfileFromString(
        bind.mainGetLocalOption(key: kOptionTrackpadAccel));
    _quality = bind.mainGetUserDefaultOption(key: kOptionImageQuality);
    final touch = bind.mainGetLocalOption(key: kOptionTouchMode) != 'N';
    final vm = bind.mainGetLocalOption(key: kOptionShowVirtualMouse);
    _control = touch ? (vm == 'N' ? 'touch' : 'mouse') : 'trackpad';
    LxUpdater.instance.loadCurrent();
    bind.mainGetVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lnMin = math.log(TrackpadBallistics.minSensitivity);
    final lnMax = math.log(TrackpadBallistics.maxSensitivity);
    Widget segmented<T>(List<(T, String)> items, T value, ValueChanged<T> on) {
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
            color: LxColors.chip(context),
            borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: items.map((e) {
            final sel = e.$1 == value;
            return Expanded(
              child: GestureDetector(
                onTap: () => on(e.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel
                        ? (LxColors.isDark(context)
                            ? Colors.white.withOpacity(0.16)
                            : Colors.white)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(e.$2,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                          color: sel
                              ? LxColors.indigoDeep
                              : LxColors.subtext(context))),
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    TextStyle label() => TextStyle(fontSize: 15, color: LxColors.text(context));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        Text('设置',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: LxColors.text(context))),
        const SizedBox(height: 20),
        const LxSectionTitle('鼠标与触控'),
        Glass(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('操控方式', style: label()),
            const SizedBox(height: 10),
            segmented<String>([
              ('mouse', '虚拟鼠标'),
              ('trackpad', '触控板'),
              ('touch', '直接触摸'),
            ], _control, (v) {
              setState(() => _control = v);
              bind.mainSetLocalOption(
                  key: kOptionTouchMode, value: v == 'trackpad' ? 'N' : 'Y');
              bind.mainSetLocalOption(
                  key: kOptionShowVirtualMouse,
                  value: v == 'mouse' ? 'Y' : 'N');
            }),
            const SizedBox(height: 8),
            Text(_controlHint(_control),
                style: TextStyle(
                    fontSize: 13, height: 1.45, color: LxColors.subtext(context))),
            const SizedBox(height: 14),
            Row(children: [
              Text('指针速度', style: label()),
              const Spacer(),
              Text('${_sensitivity.toStringAsFixed(1)}×',
                  style: TextStyle(color: LxColors.subtext(context))),
            ]),
            Slider(
              value: ((math.log(_sensitivity) - lnMin) / (lnMax - lnMin))
                  .clamp(0.0, 1.0),
              activeColor: LxColors.indigoDeep,
              onChanged: (t) => setState(() =>
                  _sensitivity = math.exp(lnMin + t * (lnMax - lnMin))),
              onChangeEnd: (_) => bind.mainSetLocalOption(
                  key: kOptionTrackpadSensitivity,
                  value: _sensitivity.toStringAsFixed(2)),
            ),
            const SizedBox(height: 6),
            Text('指针加速', style: label()),
            const SizedBox(height: 10),
            segmented<TrackpadAccelProfile>([
              (TrackpadAccelProfile.off, '关'),
              (TrackpadAccelProfile.light, '轻'),
              (TrackpadAccelProfile.medium, '中'),
              (TrackpadAccelProfile.strong, '强'),
            ], _accel, (v) {
              setState(() => _accel = v);
              bind.mainSetLocalOption(
                  key: kOptionTrackpadAccel,
                  value: trackpadAccelProfileToString(v));
            }),
            const SizedBox(height: 4),
          ]),
        ),
        const SizedBox(height: 18),
        const LxSectionTitle('画质'),
        Glass(
          child: segmented<String>([
            (kRemoteImageQualityLow, '流畅'),
            (kRemoteImageQualityBalanced, '平衡'),
            (kRemoteImageQualityBest, '清晰'),
          ], _quality.isEmpty ? kRemoteImageQualityBalanced : _quality, (v) {
            setState(() => _quality = v);
            bind.mainSetUserDefaultOption(key: kOptionImageQuality, value: v);
          }),
        ),
        const SizedBox(height: 18),
        const LxSectionTitle('关于'),
        Glass(
          child: Column(children: [
            Row(children: [
              const LxLogo(size: 28),
              const SizedBox(width: 12),
              Text('灵犀', style: label()),
              const Spacer(),
              Text('内核 $_version',
                  style: TextStyle(color: LxColors.subtext(context))),
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
