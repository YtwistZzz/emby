import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _user;
  final _pass = TextEditingController();
  String _scheme = 'http';
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  static const _httpPort = '8096';
  static const _httpsPort = '8920';

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    var host = '';
    var port = _httpPort;
    final uri = Uri.tryParse(app.lastServer);
    if (uri != null && uri.host.isNotEmpty) {
      _scheme = uri.scheme == 'https' ? 'https' : 'http';
      host = uri.host;
      port = uri.hasPort ? '${uri.port}' : '';
    }
    _host = TextEditingController(text: host);
    _port = TextEditingController(text: port);
    _user = TextEditingController(text: app.lastUser);
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _setScheme(String s) {
    setState(() {
      // 端口还是另一种协议的默认值时,自动换成当前协议的默认端口
      if (s == 'https' && _port.text == _httpPort) _port.text = _httpsPort;
      if (s == 'http' && _port.text == _httpsPort) _port.text = _httpPort;
      _scheme = s;
    });
  }

  /// 组合成 协议://主机:端口。主机框里如果自己写了协议或端口,以主机框为准。
  String _buildUrl() {
    var host = _host.text.trim();
    var scheme = _scheme;
    final m = RegExp(r'^(https?)://', caseSensitive: false).firstMatch(host);
    if (m != null) {
      scheme = m.group(1)!.toLowerCase();
      host = host.substring(m.end);
    }
    host = host.split('/').first;
    if (host.contains(':')) return '$scheme://$host';
    final port = _port.text.trim();
    return port.isEmpty ? '$scheme://$host' : '$scheme://$host:$port';
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_host.text.trim().isEmpty || _user.text.trim().isEmpty) {
      setState(() => _error = '请填写服务器地址和用户名');
      return;
    }
    final port = _port.text.trim();
    if (port.isNotEmpty) {
      final n = int.tryParse(port);
      if (n == null || n < 1 || n > 65535) {
        setState(() => _error = '端口应为 1~65535 之间的数字');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).login(_buildUrl(), _user.text.trim(), _pass.text);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String label, {String? hint, Widget? suffix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.surfaceHi,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.6, -0.8),
            radius: 1.3,
            colors: [Color(0xFF232849), AppColors.bg],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('连接到 Emby',
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.1)),
                    const SizedBox(height: 8),
                    const Text('输入服务器地址和账号,媒体库会保存在本机。',
                        style: TextStyle(color: AppColors.textDim, fontSize: 14)),
                    const SizedBox(height: 26),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'http', label: Text('HTTP')),
                        ButtonSegment(value: 'https', label: Text('HTTPS')),
                      ],
                      selected: {_scheme},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => _setScheme(s.first),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _host,
                            decoration: _dec('服务器地址', hint: '192.168.1.10 或 emby.example.com'),
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 96,
                          child: TextField(
                            controller: _port,
                            decoration: _dec('端口'),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 6, left: 2),
                      child: Text(
                        'Emby 默认端口:HTTP 8096,HTTPS 8920。通过域名反向代理访问时,端口留空。',
                        style: TextStyle(fontSize: 12, color: AppColors.textDim, height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _user,
                      decoration: _dec('用户名'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _pass,
                      obscureText: _obscure,
                      decoration: _dec(
                        '密码',
                        suffix: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: const TextStyle(color: Color(0xFFFF7B72), fontSize: 13, height: 1.4)),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.4),
                              )
                            : const Text('连接', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
