// Lingxi Desk: in-app update from GitHub Releases.
//
// A release is a tag vX.Y.Z on Allen-1002/nimbo. All platforms share
// the version in flutter/pubspec.yaml, and each has one asset:
//   Android  LingxiDesk-X.Y.Z-android-arm64.apk  (res/lingxi/release-android.sh)
//   macOS    LingxiDesk-X.Y.Z-macos-arm64.zip    (res/lingxi/release-macos.sh)
//   Windows  LingxiDesk-X.Y.Z-windows-x64.zip    (.github/workflows/lingxi-windows.yml)
// Android hands the APK to the system installer, which refuses an update
// not signed with the installed app's key. macOS checks the new bundle is
// signed by the same team before swapping it in. Windows swaps the program
// folder after the app exits.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../common.dart';
import 'lingxi_theme.dart';

const _kOwner = 'Allen-1002';
const _kRepo = 'lingxi-desk';
const _kLatestUrl =
    'https://api.github.com/repos/$_kOwner/$_kRepo/releases/latest';
const kLxReleasesPage = 'https://github.com/$_kOwner/$_kRepo/releases';
const _kCheckEvery = Duration(hours: 6);

String lxAndroidAssetName(String version) =>
    'LingxiDesk-$version-android-arm64.apk';
String lxMacAssetName(String version) => 'LingxiDesk-$version-macos-arm64.zip';
String lxWindowsAssetName(String version) =>
    'LingxiDesk-$version-windows-x64.zip';

String? _assetNameFor(String version) {
  if (Platform.isAndroid) return lxAndroidAssetName(version);
  if (Platform.isMacOS) return lxMacAssetName(version);
  if (Platform.isWindows) return lxWindowsAssetName(version);
  return null;
}

/// "v1.2.3" / "1.2" / "1.2.3-beta" -> [1, 2, 3]; null when unparsable.
List<int>? lxParseVersion(String s) {
  var t = s.trim();
  if (t.startsWith('v') || t.startsWith('V')) t = t.substring(1);
  final cut = t.indexOf(RegExp(r'[-+]'));
  if (cut >= 0) t = t.substring(0, cut);
  final parts = t.split('.');
  if (parts.isEmpty || parts.length > 4) return null;
  final out = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0) return null;
    out.add(n);
  }
  return out;
}

bool lxIsNewer(String latest, String current) {
  final a = lxParseVersion(latest), b = lxParseVersion(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

enum LxUpdateState {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  installing,
  error
}

class LxUpdater extends ChangeNotifier {
  static final LxUpdater instance = LxUpdater._();
  LxUpdater._();

  LxUpdateState state = LxUpdateState.idle;
  String current = '';
  String latest = '';
  String notes = '';
  String error = '';
  double progress = 0;
  String? _apkUrl;
  int _apkSize = 0;
  DateTime? _checkedAt;

  bool get supported =>
      Platform.isAndroid || Platform.isMacOS || Platform.isWindows;
  bool get busy =>
      state == LxUpdateState.checking ||
      state == LxUpdateState.downloading ||
      state == LxUpdateState.installing;

  void _set(LxUpdateState s, {String err = ''}) {
    state = s;
    error = err;
    notifyListeners();
  }

  Future<void> loadCurrent() async {
    if (current.isNotEmpty) return;
    try {
      current = (await PackageInfo.fromPlatform()).version;
      notifyListeners();
    } catch (_) {}
  }

  /// Ask GitHub for the latest release. Quiet checks skip when one ran in
  /// the last few hours.
  Future<void> check({bool force = false}) async {
    if (!supported || busy) return;
    if (!force &&
        _checkedAt != null &&
        DateTime.now().difference(_checkedAt!) < _kCheckEvery) {
      return;
    }
    await loadCurrent();
    _set(LxUpdateState.checking);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(_kLatestUrl));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'LingxiDesk-Updater');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 404) {
        _checkedAt = DateTime.now();
        _set(LxUpdateState.upToDate);
        return;
      }
      if (res.statusCode != 200) {
        throw '更新服务器返回 ${res.statusCode}';
      }
      final j = jsonDecode(body) as Map<String, dynamic>;
      final tag = (j['tag_name'] ?? '') as String;
      latest = tag.startsWith('v') ? tag.substring(1) : tag;
      notes = _notesSnippet((j['body'] ?? '') as String);
      _apkUrl = null;
      _apkSize = 0;
      for (final a in (j['assets'] as List? ?? const [])) {
        if (a is Map && a['name'] == _assetNameFor(latest)) {
          _apkUrl = a['browser_download_url'] as String?;
          _apkSize = (a['size'] as num?)?.toInt() ?? 0;
        }
      }
      _checkedAt = DateTime.now();
      _set(lxIsNewer(latest, current) && _apkUrl != null
          ? LxUpdateState.available
          : LxUpdateState.upToDate);
    } catch (e) {
      _set(LxUpdateState.error, err: '检查更新失败：${_friendly(e)}');
    } finally {
      client.close(force: true);
    }
  }

  /// Download the new APK and open the system installer.
  Future<void> downloadAndInstall() async {
    final url = _apkUrl;
    if (!supported || busy || url == null) return;
    if (Platform.isAndroid && !await _ensureInstallPermission()) return;
    progress = 0;
    _set(LxUpdateState.downloading);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    File? file;
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      file = File('${dir.path}/${_assetNameFor(latest)}');
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'LingxiDesk-Updater');
      final res = await req.close();
      if (res.statusCode != 200) throw '下载失败（${res.statusCode}）';
      final total = res.contentLength > 0 ? res.contentLength : _apkSize;
      final sink = file.openWrite();
      var done = 0;
      var lastNotify = DateTime.now();
      try {
        await for (final chunk
            in res.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          done += chunk.length;
          if (total > 0 &&
              DateTime.now().difference(lastNotify).inMilliseconds > 150) {
            progress = (done / total).clamp(0.0, 1.0);
            lastNotify = DateTime.now();
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      if (_apkSize > 0 && done != _apkSize) {
        throw '安装包下载不完整，请重试';
      }
      progress = 1;
      _set(LxUpdateState.installing);
      if (Platform.isMacOS) {
        await _installMac(file, dir);
        return;
      }
      if (Platform.isWindows) {
        await _installWindows(file, dir);
        return;
      }
      final err = await gFFI.invokeMethodWithResult<String>(
          'lingxi_install_apk', file.path);
      if (err != null && err.isNotEmpty) throw err;
      // The system installer takes over from here. If the person cancels it,
      // the button is still there to try again.
      Timer(const Duration(seconds: 3), () {
        if (state == LxUpdateState.installing) _set(LxUpdateState.available);
      });
    } catch (e) {
      try {
        await file?.delete();
      } catch (_) {}
      _set(LxUpdateState.error, err: _friendly(e));
    } finally {
      client.close(force: true);
    }
  }

  /// Unpack the new LingxiDesk.app, check it is signed by the same team as
  /// the running one, then swap it in after this app quits and reopen it.
  Future<void> _installMac(File zip, Directory dir) async {
    final exe = File(Platform.resolvedExecutable);
    // .../LingxiDesk.app/Contents/MacOS/LingxiDesk
    final current = exe.parent.parent.parent.path;
    if (!current.endsWith('.app')) throw '找不到当前程序的位置';
    final out = Directory('${dir.path}/unpacked');
    var r = await Process.run('/usr/bin/ditto', ['-x', '-k', zip.path, out.path]);
    if (r.exitCode != 0) throw '解压失败：${r.stderr}';
    final apps = out
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.endsWith('.app'))
        .toList();
    if (apps.length != 1) throw '安装包里没有找到程序';
    final fresh = apps.first.path;
    r = await Process.run('/usr/bin/codesign', ['--verify', '--deep', '--strict', fresh]);
    if (r.exitCode != 0) throw '新版本的签名校验失败，已停止更新';
    final mine = await _macTeam(current), theirs = await _macTeam(fresh);
    if (mine == null || mine != theirs) {
      throw '新版本的签名和当前版本不一致，已停止更新';
    }
    final script = File('${dir.path}/swap.sh');
    await script.writeAsString('''#!/bin/bash
# Lingxi Desk updater: swap the app bundle once the old one has quit.
while kill -0 $pid 2>/dev/null; do sleep 0.3; done
rm -rf "$current.old"
mv "$current" "$current.old" && mv "$fresh" "$current" && rm -rf "$current.old"
/usr/bin/xattr -dr com.apple.quarantine "$current" 2>/dev/null
/usr/bin/open "$current"
''');
    await Process.start('/bin/bash', [script.path],
        mode: ProcessStartMode.detached);
    exit(0);
  }

  static Future<String?> _macTeam(String app) async {
    final r = await Process.run('/usr/bin/codesign', ['-dv', '--verbose=2', app]);
    final m = RegExp(r'TeamIdentifier=(\S+)').firstMatch('${r.stderr}');
    final team = m?.group(1);
    return team == null || team == 'not' ? null : team;
  }

  /// Unpack the new program folder, then copy it over the current one after
  /// this app quits and start it again.
  Future<void> _installWindows(File zip, Directory dir) async {
    final exe = File(Platform.resolvedExecutable);
    final current = exe.parent.path;
    final out = Directory('${dir.path}\\unpacked');
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      "Expand-Archive -LiteralPath '${zip.path}' -DestinationPath '${out.path}' -Force",
    ]);
    if (r.exitCode != 0) throw '解压失败：${r.stderr}';
    var src = out.path;
    final inner = out.listSync().whereType<Directory>().toList();
    if (!File('$src\\${exe.uri.pathSegments.last}').existsSync() &&
        inner.length == 1) {
      src = inner.first.path;
    }
    if (!File('$src\\${exe.uri.pathSegments.last}').existsSync()) {
      throw '安装包里没有找到程序';
    }
    final script = File('${dir.path}\\swap.cmd');
    await script.writeAsString('''@echo off
rem Lingxi Desk updater: replace the program folder once the app has quit.
:wait
tasklist /FI "PID eq $pid" 2>NUL | find "$pid" >NUL && (timeout /t 1 /nobreak >NUL & goto wait)
robocopy "$src" "$current" /E /R:5 /W:1 >NUL
start "" "${exe.path}"
''');
    await Process.start('cmd', ['/c', script.path],
        mode: ProcessStartMode.detached);
    exit(0);
  }

  Future<bool> _ensureInstallPermission() async {
    final ok = await gFFI.invokeMethodWithResult<bool>('lingxi_can_install');
    if (ok == true) return true;
    await gFFI.invokeMethod('lingxi_open_install_permission');
    _set(LxUpdateState.error,
        err: '请在刚打开的页面里允许「Nimbo」安装应用，然后回来再点一次更新');
    return false;
  }

  static String _friendly(Object e) {
    if (e is SocketException || e is HandshakeException) {
      return '连不上 GitHub，请检查网络';
    }
    if (e is TimeoutException) return '网络超时，请稍后再试';
    if (e is HttpException) return '网络中断，请重试';
    return e.toString();
  }

  /// First paragraph plus the "更新内容" section, without Markdown symbols.
  static String _notesSnippet(String body) {
    final lines = body.split(RegExp(r'\r?\n'));
    final start = lines.indexWhere((l) => l.startsWith('#') && l.contains('更新内容'));
    Iterable<String> picked = lines;
    if (start >= 0) {
      final rest = lines.sublist(start + 1);
      final end = rest.indexWhere((l) => l.startsWith('## '));
      picked = end >= 0 ? rest.sublist(0, end) : rest;
    }
    final text = picked
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('|') && !l.startsWith('---'))
        .map((l) => l.replaceAll(RegExp(r'^#+\s*'), '').replaceAll('**', ''))
        .join('\n');
    return text.length > 300 ? '${text.substring(0, 300)}…' : text;
  }
}

/// The update row: version, status and the action button.
class LxUpdateTile extends StatelessWidget {
  /// Banner style hides itself unless an update is ready or running.
  final bool banner;
  const LxUpdateTile({super.key, this.banner = false});

  @override
  Widget build(BuildContext context) {
    final u = LxUpdater.instance;
    return AnimatedBuilder(
      animation: u,
      builder: (context, _) {
        if (!u.supported) return const SizedBox.shrink();
        final active = u.state == LxUpdateState.available ||
            u.state == LxUpdateState.downloading ||
            u.state == LxUpdateState.installing;
        if (banner && !active) return const SizedBox.shrink();
        final sub = TextStyle(fontSize: 13, color: LxColors.subtext(context));
        String status;
        Widget? action;
        switch (u.state) {
          case LxUpdateState.checking:
            status = '正在检查更新…';
            break;
          case LxUpdateState.upToDate:
            status = '已是最新版本';
            action = _small(context, '再查一次', () => u.check(force: true));
            break;
          case LxUpdateState.available:
            status = '发现新版本 ${u.latest}';
            action = LxButton('更新', height: 36, onPressed: u.downloadAndInstall);
            break;
          case LxUpdateState.downloading:
            status = '正在下载 ${(u.progress * 100).round()}%';
            break;
          case LxUpdateState.installing:
            status = '下载完成，请在弹出的窗口里点「安装」';
            break;
          case LxUpdateState.error:
            status = u.error;
            action = _small(context, '重试', () {
              if (u.latest.isNotEmpty && lxIsNewer(u.latest, u.current)) {
                u.downloadAndInstall();
              } else {
                u.check(force: true);
              }
            });
            break;
          case LxUpdateState.idle:
            status = '';
            action = _small(context, '检查更新', () => u.check(force: true));
        }
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (banner) ...[
                const Icon(Icons.system_update_rounded,
                    color: LxColors.indigoDeep, size: 22),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!banner)
                      Text('当前版本 ${u.current}',
                          style: TextStyle(
                              fontSize: 15, color: LxColors.text(context))),
                    if (status.isNotEmpty) ...[
                      if (!banner) const SizedBox(height: 2),
                      Text(status,
                          style: banner
                              ? TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: LxColors.text(context))
                              : sub),
                    ],
                  ],
                ),
              ),
              if (u.state == LxUpdateState.checking)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              if (action != null) action,
            ]),
            if (u.state == LxUpdateState.downloading) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: u.progress,
                  minHeight: 6,
                  color: LxColors.indigoDeep,
                  backgroundColor: LxColors.chip(context),
                ),
              ),
            ],
            if (u.state == LxUpdateState.available && u.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(u.notes,
                  maxLines: banner ? 2 : 8,
                  overflow: TextOverflow.ellipsis,
                  style: sub),
            ],
          ],
        );
        if (!banner) return body;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Glass(child: body),
        );
      },
    );
  }

  Widget _small(BuildContext context, String label, VoidCallback onTap) =>
      TextButton(
        onPressed: onTap,
        child: Text(label,
            style: const TextStyle(
                color: LxColors.indigoDeep, fontWeight: FontWeight.w600)),
      );
}
