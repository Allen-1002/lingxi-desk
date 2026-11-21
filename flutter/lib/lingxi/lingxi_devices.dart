// Lingxi Desk: device list, pairing and connecting.
//
// Pairing (until server-backed device groups land, see docs/design.md):
// the controlled computer keeps a random pairing key as its permanent
// password and shows it inside a QR code together with its six-digit code
// and LAN address. A phone that scans it stores the key and address, and
// from then on connects with no password and no prompt.

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../common.dart';
import '../models/peer_model.dart';
import '../models/platform_model.dart';
import 'lingxi_server.dart';
import 'lingxi_theme.dart';

const _kSelfPairKey = 'lingxi-self-pair-key';
String _pairKeyOption(String id) => 'lingxi-pair-$id';
String _ipOption(String id) => 'lingxi-ip-$id';
String _nameOption(String id) => 'lingxi-name-$id';

class LxDevice {
  final String id;
  final String name;
  final String platform;
  final bool online;
  final bool onLan;
  final bool paired;
  LxDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.online,
    required this.onLan,
    required this.paired,
  });
}

String lxPairKeyFor(String id) => bind.mainGetLocalOption(key: _pairKeyOption(id));

String _nameFor(Peer p) {
  final saved = bind.mainGetLocalOption(key: _nameOption(p.id));
  if (saved.isNotEmpty) return saved;
  if (p.alias.isNotEmpty) return p.alias;
  if (p.hostname.isNotEmpty) return p.hostname;
  return '设备 ${lxFormatCode(p.id)}';
}

/// Devices to show: everything seen on the LAN plus recent connections,
/// paired ones first. [selfId] is left out.
List<LxDevice> lxCollectDevices(String selfId) {
  final byId = <String, LxDevice>{};
  for (final p in gFFI.lanPeersModel.peers) {
    if (p.id.isEmpty || p.id == selfId) continue;
    byId[p.id] = LxDevice(
      id: p.id,
      name: _nameFor(p),
      platform: p.platform,
      online: true,
      onLan: true,
      paired: lxPairKeyFor(p.id).isNotEmpty,
    );
  }
  for (final p in gFFI.recentPeersModel.peers) {
    if (p.id.isEmpty || p.id == selfId || byId.containsKey(p.id)) continue;
    byId[p.id] = LxDevice(
      id: p.id,
      name: _nameFor(p),
      platform: p.platform,
      online: p.online || _serverOnline.contains(p.id),
      onLan: false,
      paired: lxPairKeyFor(p.id).isNotEmpty,
    );
  }
  final list = byId.values.toList();
  list.sort((a, b) {
    if (a.paired != b.paired) return a.paired ? -1 : 1;
    if (a.online != b.online) return a.online ? -1 : 1;
    return a.name.compareTo(b.name);
  });
  return list;
}

/// Device ids the server last reported online / offline. Kept here rather than
/// on the peer objects, which are replaced every time the list reloads.
final Set<String> _serverOnline = {};

/// Bumped when the server's online answer arrives.
final lxDevicesChanged = ValueNotifier<int>(0);
bool _onlineHandlerSet = false;

void lxRefreshDevices() {
  bind.mainDiscover();
  bind.mainLoadLanPeers();
  bind.mainLoadRecentPeers();
  _queryServerOnline();
}

/// Ask the server which known devices are online, so a device away from the
/// local network still shows as online.
void _queryServerOnline() {
  if (!_onlineHandlerSet) {
    _onlineHandlerSet = true;
    platformFFI.registerEventHandler('callback_query_onlines', 'lingxi',
        (evt) async {
      for (final id in '${evt['onlines'] ?? ''}'.split(',')) {
        if (id.isNotEmpty) _serverOnline.add(id);
      }
      for (final id in '${evt['offlines'] ?? ''}'.split(',')) {
        _serverOnline.remove(id);
      }
      lxDevicesChanged.value++;
    });
  }
  final ids = gFFI.recentPeersModel.peers
      .map((p) => p.id)
      .where((id) => id.isNotEmpty)
      .toList();
  if (ids.isNotEmpty) bind.queryOnlines(ids: ids);
}

/// Connect to a device by its six-digit code; paired devices log in with
/// their pairing key, others fall back to the controlled side's approval.
void lxConnect(BuildContext context, String id) {
  final code = id.replaceAll(' ', '');
  if (code.isEmpty) return;
  final key = lxPairKeyFor(code);
  connect(context, code, password: key.isEmpty ? null : key);
}

/// Handle a scanned pairing QR. Returns the device code, or null when the
/// text is not a Lingxi pairing code.
Future<String?> lxApplyPairingPayload(String text) async {
  final uri = Uri.tryParse(text.trim());
  if (uri == null || uri.scheme != 'lingxi' || uri.host != 'pair') return null;
  final id = uri.queryParameters['id'] ?? '';
  final key = uri.queryParameters['key'] ?? '';
  if (id.isEmpty || key.isEmpty) return null;
  await bind.mainSetLocalOption(key: _pairKeyOption(id), value: key);
  final ip = uri.queryParameters['ip'] ?? '';
  if (ip.isNotEmpty) {
    await bind.mainSetLocalOption(key: _ipOption(id), value: ip);
  }
  final name = uri.queryParameters['name'] ?? '';
  if (name.isNotEmpty) {
    await bind.mainSetLocalOption(key: _nameOption(id), value: name);
  }
  // Use the computer's server, so both sides meet on the same one.
  final srv = uri.queryParameters['srv'] ?? '';
  final srvKey = uri.queryParameters['srvkey'] ?? '';
  if (srv.isNotEmpty &&
      (srv != lxServerAddress() || srvKey != lxServerKey())) {
    await lxSetServer(srv, srvKey);
  }
  return id;
}

/// Controlled side: make sure a pairing key exists and is the permanent
/// password. Returns the key, or '' if it could not be set.
Future<String> lxEnsureSelfPairKey() async {
  var key = bind.mainGetLocalOption(key: _kSelfPairKey);
  if (key.isNotEmpty) return key;
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
  final rnd = Random.secure();
  key = List.generate(20, (_) => chars[rnd.nextInt(chars.length)]).join();
  final ok = await bind.mainSetPermanentPasswordWithResult(password: key);
  if (!ok) return '';
  await bind.mainSetLocalOption(key: _kSelfPairKey, value: key);
  return key;
}

/// Private IPv4 addresses of this machine, for the pairing QR.
Future<List<String>> lxLocalIps() async {
  final out = <String>[];
  try {
    final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final i in ifs) {
      for (final a in i.addresses) {
        final s = a.address;
        if (s.startsWith('192.168.') ||
            s.startsWith('10.') ||
            RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(s)) {
          out.add(s);
        }
      }
    }
  } catch (_) {}
  return out;
}

String lxPairingPayload(
        {required String id,
        required String key,
        required List<String> ips,
        required String name}) =>
    Uri(scheme: 'lingxi', host: 'pair', queryParameters: {
      'id': id,
      'key': key,
      if (ips.isNotEmpty) 'ip': ips.join(','),
      if (name.isNotEmpty) 'name': name,
      if (lxServerAddress().isNotEmpty) 'srv': lxServerAddress(),
      if (lxServerAddress().isNotEmpty && lxServerKey().isNotEmpty)
        'srvkey': lxServerKey(),
    }).toString();

/// One row in a device list.
class LxDeviceTile extends StatelessWidget {
  final LxDevice device;
  final VoidCallback? onTap;
  final Widget? trailing;
  const LxDeviceTile(
      {super.key, required this.device, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final d = device;
    final status = [
      d.online ? (d.onLan ? '在线 · 局域网' : '在线') : '离线',
      '设备码 ${lxFormatCode(d.id)}',
      if (d.paired) '已配对',
    ].join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: d.online
                      ? LxColors.indigo.withOpacity(0.12)
                      : LxColors.chip(context),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(lxPlatformIcon(d.platform),
                    color: d.online
                        ? LxColors.indigoDeep
                        : LxColors.subtext(context)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: LxColors.text(context))),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: d.online ? LxColors.online : Colors.transparent,
                          border: d.online
                              ? null
                              : Border.all(
                                  color: LxColors.subtext(context), width: 1.5),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                color: LxColors.subtext(context))),
                      ),
                    ]),
                  ],
                ),
              ),
              trailing ??
                  Icon(Icons.chevron_right_rounded,
                      color: LxColors.subtext(context)),
            ],
          ),
        ),
      ),
    );
  }
}
