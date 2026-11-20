// Lingxi: which server this device uses. The address and key are kept only
// in this device's settings (never in the source), and a pairing QR passes
// them on to the phone that scans it.
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
