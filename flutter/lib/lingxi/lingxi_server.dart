// Lingxi: which server this device uses. The address and key are kept only
// in this device's settings (never in the source), and a pairing QR passes
// them on to the phone that scans it.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io' show Platform, Socket;

import 'package:ffi/ffi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common.dart';
import '../models/platform_model.dart';
import 'lingxi_theme.dart';

const _kServerOption = 'custom-rendezvous-server';
const _kKeyOption = 'key';

String lxServerAddress() => bind.mainGetOptionSync(key: _kServerOption).trim();
String lxServerKey() => bind.mainGetOptionSync(key: _kKeyOption).trim();

/// Use [server] with [key] on this device. An empty [server] goes back to the
/// built-in default.
Future<void> lxSetServer(String server, String key) async {
  await setServerConfig(
      null,
      null,
      ServerConfig(
          idServer: server.trim(),
          relayServer: '',
          apiServer: '',
          key: server.trim().isEmpty ? '' : key.trim()));
}

/// Edit the server by hand. Returns true when it changed.
Future<bool> lxEditServer(BuildContext context) async {
  final addr = TextEditingController(text: lxServerAddress());
  final key = TextEditingController(text: lxServerKey());
  InputDecoration deco(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      );
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('填写服务器'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('填你已经部署好的服务器。手机和电脑要用同一台服务器才能在外面互相连上。',
              style: TextStyle(
                  fontSize: 13, height: 1.45, color: LxColors.subtext(ctx))),
          const SizedBox(height: 14),
          TextField(
              controller: addr,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: deco('地址', 'IP 或域名，例如 1.2.3.4')),
          const SizedBox(height: 12),
          TextField(
              controller: key,
              autocorrect: false,
              decoration: deco('公钥', '部署时显示的公钥')),
        ]),
      ),
      actions: [
        if (lxServerAddress().isNotEmpty)
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'clear'),
              child: Text('不用自己的服务器',
                  style: TextStyle(color: LxColors.danger.withOpacity(0.9)))),
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('保存')),
      ],
    ),
  );
  if (r == 'save') {
    await lxSetServer(addr.text, key.text);
    return true;
  }
  if (r == 'clear') {
    await lxSetServer('', '');
    return true;
  }
  return false;
}

/// Short form of a key for display: "UqFcIP…C1WI=".
String _shortKey(String k) =>
    k.length <= 14 ? k : '${k.substring(0, 6)}…${k.substring(k.length - 5)}';

/// The whole server story in one card: which server this device uses, whether
/// it can be reached, and the actions that fit (deploy / fill in / change).
class LxServerCard extends StatefulWidget {
  const LxServerCard({super.key});
  @override
  State<LxServerCard> createState() => _LxServerCardState();
}

enum _Reach { checking, ok, down }

class _LxServerCardState extends State<LxServerCard> {
  String _server = '';
  String _key = '';
  _Reach _reach = _Reach.checking;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _reload();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _server = lxServerAddress();
      _key = lxServerKey();
      _reach = _Reach.checking;
    });
    _check();
  }

  /// Desktop: registered with the server. Phone: the server port answers.
  Future<void> _check() async {
    final host = _server;
    if (host.isEmpty) return;
    var ok = false;
    if (lxCanDeployServer) {
      try {
        final m = jsonDecode(await bind.mainGetConnectStatus())
            as Map<String, dynamic>;
        ok = (m['status_num'] ?? 0) == 1;
      } catch (_) {}
    }
    if (!ok) {
      final h = host.contains(':') ? host.split(':').first : host;
      final port = host.contains(':')
          ? int.tryParse(host.split(':').last) ?? 21116
          : 21116;
      try {
        final s = await Socket.connect(h, port,
            timeout: const Duration(seconds: 4));
        s.destroy();
        ok = true;
      } catch (_) {}
    }
    if (mounted && host == _server) {
      setState(() => _reach = ok ? _Reach.ok : _Reach.down);
    }
  }

  Future<void> _edit() async {
    if (await lxEditServer(context)) _reload();
  }

  Future<void> _deploy() async {
    if (await lxShowDeployDialog(context)) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final desktop = lxCanDeployServer;
    final has = _server.isNotEmpty;
    final sub = TextStyle(
        fontSize: 13, height: 1.45, color: LxColors.subtext(context));
    final (String label, Color color) = !has
        ? ('未设置', LxColors.warn)
        : switch (_reach) {
            _Reach.ok => ('正常', LxColors.online),
            _Reach.down => ('连不上', LxColors.danger),
            _Reach.checking => ('检查中', LxColors.subtext(context)),
          };

    Widget actions() {
      final buttons = <Widget>[
        if (desktop)
          LxButton(has ? '重新部署' : '一键部署到我的服务器',
              icon: Icons.rocket_launch_rounded,
              height: 38,
              secondary: has,
              onPressed: _deploy),
        LxButton(has ? '修改' : '填写已有服务器',
            icon: has ? Icons.edit_rounded : Icons.dns_rounded,
            height: 38,
            secondary: desktop || has,
            onPressed: _edit),
      ];
      return Wrap(spacing: 10, runSpacing: 10, children: buttons);
    }

    return LxGroup(
      title: '服务器',
      footer: desktop
          ? '手机扫这台电脑的配对二维码，会自动用上同一台服务器。'
          : '扫电脑上的配对二维码会自动同步服务器，一般不用手动填。',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const LxIconBadge(Icons.dns_rounded, LxColors.indigo, size: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(has ? _server : '还没有自己的服务器',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: LxColors.text(context))),
                      const SizedBox(height: 3),
                      if (has)
                        Row(children: [
                          Text('公钥 ${_shortKey(_key)}', style: sub),
                          if (_key.isNotEmpty)
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: _key));
                                showToast('公钥已复制');
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.copy_rounded,
                                    size: 14, color: LxColors.subtext(context)),
                              ),
                            ),
                        ])
                      else
                        Text('现在用的是公共服务器，手机在外面可能连不上',
                            style: sub),
                    ]),
              ),
              LxStatusPill(label, color),
            ]),
            if (has && _reach == _Reach.down) ...[
              const SizedBox(height: 12),
              Text(
                  '连不上服务器。请检查服务器是否开着，以及云控制台的安全组或防火墙是否放行了 TCP 21115-21119 和 UDP 21116。',
                  style: sub.copyWith(color: LxColors.danger)),
            ],
            if (!has && desktop) ...[
              const SizedBox(height: 12),
              Text('有一台 Linux 云服务器就行，填上 IP 和登录密码，几秒钟装好，不需要 Docker。',
                  style: sub),
            ],
            const SizedBox(height: 14),
            actions(),
          ]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// One-click server deploy (desktop). The work happens in the Rust core
// (src/lingxi_deploy.rs) through three plain C functions.

typedef _StartN = Int32 Function(Pointer<Utf8>);
typedef _StartD = int Function(Pointer<Utf8>);
typedef _PollN = Pointer<Utf8> Function();
typedef _PollD = Pointer<Utf8> Function();
typedef _FreeN = Void Function(Pointer<Utf8>);
typedef _FreeD = void Function(Pointer<Utf8>);

class _DeployFfi {
  final _StartD start;
  final _PollD poll;
  final _FreeD free;
  _DeployFfi(this.start, this.poll, this.free);

  static _DeployFfi? _instance;
  static bool _tried = false;
  static _DeployFfi? get instance {
    if (_tried) return _instance;
    _tried = true;
    try {
      final lib = Platform.isWindows
          ? DynamicLibrary.open('librustdesk.dll')
          : Platform.isLinux
              ? DynamicLibrary.open('librustdesk.so')
              : DynamicLibrary.process();
      _instance = _DeployFfi(
        lib.lookupFunction<_StartN, _StartD>('lingxi_deploy_start'),
        lib.lookupFunction<_PollN, _PollD>('lingxi_deploy_poll'),
        lib.lookupFunction<_FreeN, _FreeD>('lingxi_free_cstring'),
      );
    } catch (e) {
      debugPrint('lingxi deploy ffi: $e');
    }
    return _instance;
  }

  Map<String, dynamic> status() {
    final p = poll();
    if (p == nullptr) return {};
    try {
      return jsonDecode(p.toDartString()) as Map<String, dynamic>;
    } finally {
      free(p);
    }
  }
}

bool get lxCanDeployServer =>
    (Platform.isMacOS || Platform.isWindows || Platform.isLinux) &&
    _DeployFfi.instance != null;

/// Show the deploy dialog. Returns true when this device's server changed.
Future<bool> lxShowDeployDialog(BuildContext context) async {
  final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeployDialog());
  return changed == true;
}

class _DeployDialog extends StatefulWidget {
  const _DeployDialog();
  @override
  State<_DeployDialog> createState() => _DeployDialogState();
}

class _DeployDialogState extends State<_DeployDialog> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _user = TextEditingController(text: 'root');
  final _password = TextEditingController();
  final _keyPass = TextEditingController();
  String _keyPath = '';
  bool _useKey = false;

  bool _running = false;
  Map<String, dynamic> _st = {};
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _password.dispose();
    _keyPass.dispose();
    super.dispose();
  }

  Future<void> _pickKey() async {
    final r = await FilePicker.platform
        .pickFiles(dialogTitle: '选择 SSH 私钥文件', lockParentWindow: true);
    final path = r?.files.single.path;
    if (path != null) setState(() => _keyPath = path);
  }

  void _start() {
    final ffi = _DeployFfi.instance;
    if (ffi == null || _host.text.trim().isEmpty) return;
    final req = jsonEncode({
      'host': _host.text.trim(),
      'port': int.tryParse(_port.text.trim()) ?? 22,
      'user': _user.text.trim(),
      'password': _useKey ? '' : _password.text,
      'key_path': _useKey ? _keyPath : '',
      'key_passphrase': _useKey ? _keyPass.text : '',
    });
    final p = req.toNativeUtf8();
    final rc = ffi.start(p);
    malloc.free(p);
    // The password stays in the Rust core only for this deploy.
    _password.clear();
    _keyPass.clear();
    if (rc != 0) {
      setState(() => _st = {
            'done': true,
            'error': rc == 1 ? '已经有一个部署在进行' : '请填写服务器地址'
          });
      return;
    }
    setState(() {
      _running = true;
      _st = {};
    });
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      final st = ffi.status();
      if (!mounted) return;
      setState(() => _st = st);
      if (st['done'] == true) {
        _timer?.cancel();
        _running = false;
        if (st['ok'] == true) {
          await lxSetServer(st['host'] ?? '', st['key'] ?? '');
          if (mounted) setState(() {});
        }
      }
    });
  }

  InputDecoration _deco(String label, [String? hint]) => InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      isDense: true);

  Widget _form() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('需要一台 Linux 云服务器（Ubuntu、Debian、CentOS 等），用 root 或能 sudo 的用户登录。不需要装 Docker。',
          style: TextStyle(
              fontSize: 13, height: 1.45, color: LxColors.subtext(context))),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
            child: TextField(
                controller: _host,
                autocorrect: false,
                decoration: _deco('服务器 IP 或域名'))),
        const SizedBox(width: 10),
        SizedBox(
            width: 80,
            child: TextField(
                controller: _port, decoration: _deco('SSH 端口'))),
      ]),
      const SizedBox(height: 12),
      TextField(controller: _user, decoration: _deco('用户名')),
      const SizedBox(height: 12),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('密码')),
          ButtonSegment(value: true, label: Text('密钥文件')),
        ],
        selected: {_useKey},
        onSelectionChanged: (v) => setState(() => _useKey = v.first),
      ),
      const SizedBox(height: 12),
      if (!_useKey)
        TextField(
            controller: _password,
            obscureText: true,
            decoration: _deco('密码', '只在这次部署时使用，不会保存'))
      else ...[
        Row(children: [
          Expanded(
            child: Text(_keyPath.isEmpty ? '未选择（默认用 ~/.ssh 里的密钥）' : _keyPath,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: LxColors.subtext(context))),
          ),
          TextButton(onPressed: _pickKey, child: const Text('选择…')),
        ]),
        const SizedBox(height: 8),
        TextField(
            controller: _keyPass,
            obscureText: true,
            decoration: _deco('密钥口令（没有就不填）')),
      ],
    ]);
  }

  Widget _progress() {
    final log = (_st['log'] as List?)?.cast<String>() ?? const [];
    final done = _st['done'] == true;
    final ok = _st['ok'] == true;
    final err = (_st['error'] ?? '') as String;
    final closed = (_st['closed_ports'] as List?)?.cast<int>() ?? const [];
    final style =
        TextStyle(fontSize: 13, height: 1.5, color: LxColors.text(context));
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in log) Text('· $l', style: style),
          if (!done)
            const Padding(
                padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator()),
          if (done && !ok) ...[
            const SizedBox(height: 10),
            Text('部署失败：$err',
                style: style.copyWith(color: Colors.red.shade400)),
          ],
          if (ok) ...[
            const SizedBox(height: 10),
            Text('部署完成，本机已改用这台服务器。', style: style.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
                closed.isEmpty
                    ? '从这台电脑能连上服务器的所有端口。'
                    : '从这台电脑连不上端口 ${closed.join('、')}。',
                style: style),
            const SizedBox(height: 6),
            Text(
                '请在云服务器控制台的「安全组」或「防火墙」里放行：TCP 21115-21119，UDP 21116，来源 0.0.0.0/0。少了任何一条，手机在外面就连不上。',
                style: style.copyWith(color: LxColors.subtext(context))),
            const SizedBox(height: 6),
            Text('手机扫一下这台电脑的配对二维码，就会自动用上同一台服务器。',
                style: style.copyWith(color: LxColors.subtext(context))),
          ],
        ]);
  }

  @override
  Widget build(BuildContext context) {
    final started = _running || _st.isNotEmpty;
    final done = _st['done'] == true;
    final ok = _st['ok'] == true;
    return AlertDialog(
      title: const Text('部署服务器'),
      content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
              child: started ? _progress() : _form())),
      actions: [
        if (!_running)
          TextButton(
              onPressed: () => Navigator.pop(context, ok),
              child: Text(ok ? '完成' : '关闭')),
        if (!started || (done && !ok))
          FilledButton(
              onPressed: () {
                if (done) {
                  setState(() => _st = {});
                } else {
                  _start();
                }
              },
              child: Text(done ? '返回修改' : '开始部署')),
      ],
    );
  }
}
