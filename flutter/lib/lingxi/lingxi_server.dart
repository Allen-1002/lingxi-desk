// Lingxi: which server this device uses. The address and key are kept only
// in this device's settings (never in the source), and a pairing QR passes
// them on to the phone that scans it.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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

/// Settings row showing the current server, with a dialog to change it.
class LxServerTile extends StatefulWidget {
  const LxServerTile({super.key});
  @override
  State<LxServerTile> createState() => _LxServerTileState();
}

class _LxServerTileState extends State<LxServerTile> {
  late String _server = lxServerAddress();

  Future<void> _edit() async {
    final addr = TextEditingController(text: lxServerAddress());
    final key = TextEditingController(text: lxServerKey());
    InputDecoration deco(String label, String hint) => InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('服务器'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('手机和电脑要用同一台服务器才能互相连上。扫码配对时，手机会自动用上电脑的服务器设置。',
                style: TextStyle(
                    fontSize: 13, height: 1.45, color: LxColors.subtext(ctx))),
            const SizedBox(height: 14),
            TextField(
                controller: addr,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: deco('地址', '例如 1.2.3.4')),
            const SizedBox(height: 12),
            TextField(
                controller: key,
                autocorrect: false,
                decoration: deco('公钥', '服务器给出的公钥')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok == true) {
      await lxSetServer(addr.text, key.text);
      if (mounted) setState(() => _server = lxServerAddress());
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _edit,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('服务器',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: LxColors.text(context))),
              const SizedBox(height: 2),
              Text(_server.isEmpty ? '未设置（使用公共服务器）' : _server,
                  style: TextStyle(
                      fontSize: 13, color: LxColors.subtext(context))),
            ]),
          ),
          Icon(Icons.chevron_right, color: LxColors.subtext(context)),
        ]),
      ),
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

/// Settings row that opens the deploy dialog. [onDone] runs after the local
/// server setting has been changed.
class LxDeployServerTile extends StatelessWidget {
  final VoidCallback? onDone;
  const LxDeployServerTile({super.key, this.onDone});

  @override
  Widget build(BuildContext context) {
    if (!lxCanDeployServer) return const SizedBox.shrink();
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final changed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => const _DeployDialog());
        if (changed == true) onDone?.call();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('部署服务器',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: LxColors.text(context))),
              const SizedBox(height: 2),
              Text('把灵犀服务器一键装到你自己的 Linux 云服务器上',
                  style: TextStyle(
                      fontSize: 13, color: LxColors.subtext(context))),
            ]),
          ),
          Icon(Icons.chevron_right, color: LxColors.subtext(context)),
        ]),
      ),
    );
  }
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
