import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class DouyuWebLoginPage extends StatefulWidget {
  const DouyuWebLoginPage({super.key});

  @override
  State<DouyuWebLoginPage> createState() => _DouyuWebLoginPageState();
}

class _DouyuWebLoginPageState extends State<DouyuWebLoginPage> {
  WebViewEnvironment? _environment;
  InAppWebViewController? _controller;
  late final Future<void> _ready = _prepare();
  bool _saving = false;

  Future<void> _prepare() async {
    if (Platform.isWindows) {
      final dir = await getApplicationSupportDirectory();
      final environment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: '${dir.path}/douyu_webview',
        ),
      );
      if (!mounted) {
        await environment.dispose();
        return;
      }
      _environment = environment;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final manager = CookieManager.instance(webViewEnvironment: _environment);
      // Only cookies visible to the actual playback API's host are imported.
      // Do not collect passport-only refresh credentials.
      final cookies = await manager.getCookies(
        url: WebUri('https://www.douyu.com/'),
        webViewController: _controller,
      );
      await DouyuAccountService.instance.saveCookie(
        cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; '),
      );
      if (!mounted) return;
      SmartDialog.showToast('已保存，请重新进入直播间验证');
      Navigator.of(context).pop();
    } on FormatException {
      SmartDialog.showToast('尚未读取到完整登录信息，请完成登录后再保存；也可返回导入 Cookie');
    } catch (_) {
      SmartDialog.showToast('读取登录信息失败，可返回使用 Cookie 导入');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _environment?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('斗鱼官方登录')),
      body: FutureBuilder<void>(
        future: _ready,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('无法打开登录页，请返回使用 Cookie 导入'));
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Expanded(child: Text('在官方页面完成扫码或密码登录后，点击保存。')),
                    FilledButton(
                      onPressed: _saving || _controller == null ? null : _save,
                      child: Text(_saving ? '正在读取…' : '保存登录信息'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InAppWebView(
                  webViewEnvironment: _environment,
                  initialUrlRequest: URLRequest(
                    url: WebUri('https://passport.douyu.com/member/login'),
                  ),
                  initialSettings: InAppWebViewSettings(
                    userAgent: DouyuSite.userAgent,
                    useShouldOverrideUrlLoading: true,
                  ),
                  onWebViewCreated: (controller) {
                    setState(() => _controller = controller);
                  },
                  shouldOverrideUrlLoading: (_, navigation) async {
                    final uri = navigation.request.url;
                    if (uri == null || uri.scheme != 'https') {
                      return NavigationActionPolicy.CANCEL;
                    }
                    // The official login can embed third-party CAPTCHA frames.
                    if (!navigation.isForMainFrame) {
                      return NavigationActionPolicy.ALLOW;
                    }
                    return uri.host == 'douyu.com' ||
                            uri.host.endsWith('.douyu.com')
                        ? NavigationActionPolicy.ALLOW
                        : NavigationActionPolicy.CANCEL;
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
