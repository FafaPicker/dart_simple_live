import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_core/simple_live_core.dart';

class DouyuAccountService extends GetxService {
  static DouyuAccountService get instance => Get.find<DouyuAccountService>();

  // Separate from exported/synced settings. Never use LocalStorageService's
  // value logging for session credentials.
  late Box<String> _box;
  final hasSession = false.obs;
  final useAccount = false.obs;
  String _cookie = '';

  String get status => !hasSession.value
      ? '未配置，使用游客身份'
      : useAccount.value
          ? '已配置登录信息，实际身份待取流验证'
          : '已配置登录信息，当前使用游客身份';

  Future<DouyuAccountService> init() async {
    _box = await Hive.openBox<String>('DouyuAccount');
    _cookie = _box.get('cookie', defaultValue: '')!;
    useAccount.value = _box.get('enabled') == 'true';
    try {
      hasSession.value = DouyuAccountCookies.parse(_cookie).canUseForPlayback;
    } on FormatException {
      hasSession.value = false;
    }
    useAccount.value = useAccount.value && hasSession.value;
    _apply();
    return this;
  }

  Future<void> saveCookie(String input) async {
    final account = DouyuAccountCookies.parse(input.trim());
    if (!account.canUseForPlayback) {
      throw const FormatException(
          '需要同一次登录的 dy_auth 或 acf_jwt_token，以及 dy_did（或 acf_did）');
    }
    await _box.putAll({'cookie': account.playbackCookie, 'enabled': 'true'});
    _cookie = account.playbackCookie;
    hasSession.value = true;
    useAccount.value = true;
    _apply();
  }

  Future<void> setUseAccount(bool enabled) async {
    await _box.put('enabled', (enabled && hasSession.value).toString());
    useAccount.value = enabled && hasSession.value;
    _apply();
  }

  Future<void> clear() async {
    await _box.clear();
    _cookie = '';
    hasSession.value = false;
    useAccount.value = false;
    _apply();
  }

  void _apply() {
    final site = Sites.allSites[Constant.kDouyu]!.liveSite as DouyuSite;
    site.cookie = hasSession.value && useAccount.value ? _cookie : '';
  }
}
