import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/mine/account/douyu/douyu_web_login_page.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';

class DouyuAccountPage extends StatefulWidget {
  const DouyuAccountPage({super.key});

  @override
  State<DouyuAccountPage> createState() => _DouyuAccountPageState();
}

class _DouyuAccountPageState extends State<DouyuAccountPage> {
  final _input = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await DouyuAccountService.instance.saveCookie(_input.text);
      _input.clear();
      SmartDialog.showToast('登录信息已保存，请重新进入直播间验证');
    } on FormatException catch (e) {
      SmartDialog.showToast(e.message);
    } catch (_) {
      SmartDialog.showToast('保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = DouyuAccountService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('斗鱼账号')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Obx(() => Text(service.status)),
          const SizedBox(height: 12),
          const Text('使用官方登录会话获取播放地址。是否改善定时断流，需要实际播放验证。'),
          if (!Platform.isLinux) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Get.to(() => const DouyuWebLoginPage()),
              icon: const Icon(Icons.login),
              label: const Text('打开斗鱼官方登录页'),
            ),
          ],
          const SizedBox(height: 24),
          const Text('也可以导入已登录浏览器的 Cookie：需要同一次登录的 '
              'dy_auth 或 acf_jwt_token，以及 dy_did（或 acf_did）。'
              '登录信息仅保存在本机，不随设置导出或 WebDAV 同步。'),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('douyu-cookie-input'),
            controller: _input,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Cookie',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '正在保存…' : '保存登录信息'),
          ),
          const SizedBox(height: 16),
          Obx(() => SwitchListTile(
                title: const Text('使用登录身份取流'),
                subtitle: const Text('关闭可对比游客效果。切换后请退出并重新进入直播间。'),
                value: service.useAccount.value,
                onChanged: !service.hasSession.value
                    ? null
                    : (value) async {
                        try {
                          await service.setUseAccount(value);
                        } catch (_) {
                          SmartDialog.showToast('切换失败，请重试');
                        }
                      },
              )),
          Obx(() => TextButton.icon(
                onPressed: !service.hasSession.value
                    ? null
                    : () async {
                        try {
                          await service.clear();
                          SmartDialog.showToast('已清除取流登录信息');
                        } catch (_) {
                          SmartDialog.showToast('清除失败，请重试');
                        }
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('清除取流登录信息'),
              )),
          const SizedBox(height: 16),
          const Text('若登录失效，请重新登录并保存。开启日志记录后，可对比同一房间、'
              '同一画质和线路的有效期参数及连续播放时长。'),
        ],
      ),
    );
  }
}
