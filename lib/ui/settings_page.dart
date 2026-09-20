import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../services/trakt_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AppState _app;
  late final TextEditingController _traktId;
  late final TextEditingController _traktSecret;
  late final TextEditingController _mdb;
  bool _mdbSaved = false;

  @override
  void initState() {
    super.initState();
    _app = AppScope.read(context);
    _traktId = TextEditingController(text: _app.trakt.clientId);
    _traktSecret = TextEditingController(text: _app.trakt.clientSecret);
    _mdb = TextEditingController(text: _app.mdblistKey);
    _app.trakt.addListener(_onTraktChanged);
  }

  @override
  void dispose() {
    _app.trakt.removeListener(_onTraktChanged);
    _traktId.dispose();
    _traktSecret.dispose();
    _mdb.dispose();
    super.dispose();
  }

  void _onTraktChanged() {
    if (mounted) setState(() {});
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceHi,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      );

  Future<void> _connectTrakt() async {
    final trakt = _app.trakt;
    await trakt.saveCredentials(_traktId.text, _traktSecret.text);
    if (!trakt.configured) {
      _snack('请先填写 Client ID 和 Client Secret');
      return;
    }
    try {
      final code = await trakt.requestDeviceCode();
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DeviceCodeDialog(trakt: trakt, code: code),
      );
      if (ok == true) {
        _snack('已连接 Trakt');
        trakt.flushPending();
      }
    } catch (e) {
      _snack('$e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final emby = _app.emby;
    final trakt = _app.trakt;
    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 48),
      children: [
        const Text('设置', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 28),
        _Section(
          title: 'Emby 账号',
          children: [
            Text('${emby?.userName ?? ''}  @  ${emby?.baseUrl ?? ''}',
                style: const TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () => _app.logout(),
              child: const Text('退出登录'),
            ),
          ],
        ),
        _Section(
          title: '评分来源(MDBList)',
          children: [
            const Text(
              '填入 MDBList API Key 后,详情页会显示 IMDb、烂番茄、Metacritic、TMDb、Trakt、Letterboxd 评分,'
              '结果在本机缓存 7 天。没有 Key 时只显示 Emby 自带的评分。',
              style: TextStyle(color: AppColors.textDim, height: 1.5),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: TextField(controller: _mdb, decoration: _dec('API Key'), obscureText: true)),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () async {
                    await _app.setMdblistKey(_mdb.text);
                    setState(() => _mdbSaved = true);
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
            if (_mdbSaved)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('已保存,评分缓存已清空', style: TextStyle(fontSize: 12.5, color: AppColors.accent)),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => launchUrl(Uri.parse('https://mdblist.com/preferences/')),
              child: const Text('去 mdblist.com 获取 Key(免费)'),
            ),
          ],
        ),
        _Section(
          title: 'Trakt 同步',
          children: [
            const Text(
              '只在开始、暂停/恢复、拖动进度、结束时各发送一次 scrobble,没有定时心跳。'
              '如果你的 Emby 服务器已经装了官方 Trakt 插件,请不要在这里重复连接,否则会重复记录。',
              style: TextStyle(color: AppColors.textDim, height: 1.5),
            ),
            const SizedBox(height: 14),
            if (!trakt.connected) ...[
              Row(
                children: [
                  Expanded(child: TextField(controller: _traktId, decoration: _dec('Client ID'))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(controller: _traktSecret, decoration: _dec('Client Secret'), obscureText: true),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton(onPressed: _connectTrakt, child: const Text('连接 Trakt')),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse('https://trakt.tv/oauth/applications/new')),
                    child: const Text('创建 Trakt 应用'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '创建应用时 Redirect URI 填 urn:ietf:wg:oauth:2.0:oob,然后把 Client ID / Secret 粘贴到上面。',
                style: TextStyle(fontSize: 12.5, color: AppColors.textDim),
              ),
            ] else ...[
              Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.accent, size: 20),
                  const SizedBox(width: 8),
                  Text('已连接${trakt.username != null ? ':${trakt.username}' : ''}'),
                  const Spacer(),
                  OutlinedButton(onPressed: () => trakt.disconnect(), child: const Text('断开连接')),
                ],
              ),
              if (trakt.pendingCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      Text('有 ${trakt.pendingCount} 条离线观看记录待补录',
                          style: const TextStyle(color: AppColors.textDim)),
                      TextButton(
                        onPressed: () async {
                          await trakt.flushPending();
                          if (mounted) setState(() {});
                        },
                        child: const Text('立即补录'),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 18),
            const Text('最近的 Trakt 请求', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ValueListenableBuilder<List<String>>(
              valueListenable: trakt.log,
              builder: (_, lines, __) => Container(
                height: 160,
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHi,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: lines.isEmpty
                    ? const Text('还没有请求。播放一部影片后,这里会逐条列出发送过的 scrobble。',
                        style: TextStyle(color: AppColors.textDim, fontSize: 12.5))
                    : ListView(
                        children: [
                          for (final l in lines)
                            Text(l, style: const TextStyle(fontSize: 12.5, fontFamily: 'Consolas', height: 1.5)),
                        ],
                      ),
              ),
            ),
          ],
        ),
        _Section(
          title: '快捷键(播放时)',
          children: const [
            Text(
              '空格 播放/暂停    ← → 快退/快进 10 秒    ↑ ↓ 音量    F 或 F11 全屏    M 静音\n'
              'N / P 下一集 / 上一集    Esc 退出全屏或返回    双击画面 全屏',
              style: TextStyle(color: AppColors.textDim, height: 1.8),
            ),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 22),
        padding: const EdgeInsets.all(22),
        constraints: const BoxConstraints(maxWidth: 820),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );
}

class _DeviceCodeDialog extends StatefulWidget {
  const _DeviceCodeDialog({required this.trakt, required this.code});
  final TraktService trakt;
  final TraktDeviceCode code;

  @override
  State<_DeviceCodeDialog> createState() => _DeviceCodeDialogState();
}

class _DeviceCodeDialogState extends State<_DeviceCodeDialog> {
  bool _cancelled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  Future<void> _poll() async {
    try {
      final ok = await widget.trakt.pollForToken(widget.code, () => _cancelled);
      if (mounted) Navigator.of(context).pop(ok);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.code;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('在浏览器里授权'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('打开 ${c.verificationUrl},输入下面的授权码:',
                style: const TextStyle(color: AppColors.textDim, height: 1.5)),
            const SizedBox(height: 16),
            Center(
              child: SelectableText(
                c.userCode,
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 4),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => Clipboard.setData(ClipboardData(text: c.userCode)),
                  child: const Text('复制授权码'),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: () => launchUrl(Uri.parse(c.verificationUrl), mode: LaunchMode.externalApplication),
                  child: const Text('打开网页'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Color(0xFFFF7B72)))
            else
              const Row(
                children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('等待授权完成…', style: TextStyle(color: AppColors.textDim)),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _cancelled = true;
            Navigator.of(context).pop(false);
          },
          child: Text(_error != null ? '关闭' : '取消'),
        ),
      ],
    );
  }
}
