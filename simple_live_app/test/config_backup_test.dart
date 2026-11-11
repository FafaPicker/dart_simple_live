import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/services/config_backup_service.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  late Directory directory;
  late LocalStorageService storage;
  late DBService db;
  late DouyuAccountService account;
  late ConfigBackupService backup;
  const cookieA = 'dy_auth=test-account-a; dy_did=test-device-a';
  const cookieB = 'dy_auth=test-account-b; dy_did=test-device-b';

  FollowUser follow(String room, {String tag = '全部'}) => FollowUser(
        id: 'douyu_$room',
        siteId: 'douyu',
        roomId: room,
        userName: 'User $room',
        face: '',
        addTime: DateTime(2026, 1, 1),
        tag: tag,
      );

  Map<String, dynamic> legacy() => {
        'type': 'simple_live',
        'platform': Platform.operatingSystem,
        'version': 1,
        'time': 1,
        'config': <String, dynamic>{},
        'shield': <String, String>{},
      };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('simple-live-backup-');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(FollowUserAdapter());
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(FollowUserTagAdapter());
    }
    storage = LocalStorageService();
    await storage.init();
    db = DBService();
    db.followBox = await Hive.openBox<FollowUser>('FollowUser');
    db.tagBox = await Hive.openBox<FollowUserTag>('FollowUserTag');
    account = await DouyuAccountService().init();
    backup = ConfigBackupService(storage, db, account);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('export keeps the old envelope and includes follows and account',
      () async {
    await db.addFollow(follow('1', tag: '游戏'));
    await storage.settingsBox.put('ThemeMode', 2);
    await storage.shieldBox.put('keyword', 'keyword');
    await account.saveCookie(cookieA);
    final exported = jsonDecode(jsonEncode(backup.exportData()));
    expect(exported['type'], 'simple_live');
    expect(exported['version'], 1);
    expect(exported['platform'], Platform.operatingSystem);
    expect(exported['time'], isA<int>());
    expect(exported['config'], {'ThemeMode': 2});
    expect(exported['config'].containsKey('DanmuSize'), false);
    expect(exported['shield'], {'keyword': 'keyword'});
    expect(exported['follows'], [follow('1', tag: '游戏').toJson()]);
    expect(exported['douyuAccount'], {'cookie': cookieA, 'enabled': 'true'});
    expect(ConfigBackup.parse(exported).follows.single.tag, '游戏');
  });

  test('follows use union, preserve local duplicates, and import idempotently',
      () async {
    for (final room in ['1', '2', '3']) {
      await db.addFollow(follow(room));
    }
    final data = legacy()
      ..['follows'] = [
        follow('3', tag: 'Imported').toJson(),
        follow('4', tag: '游戏').toJson(),
        follow('5', tag: '游戏').toJson(),
        follow('4', tag: '游戏').toJson(),
      ];
    await backup.importData(ConfigBackup.parse(data));
    await backup.importData(ConfigBackup.parse(data));
    expect(db.getFollowList().map((item) => item.roomId),
        ['1', '2', '3', '4', '5']);
    expect(db.followBox.get('douyu_3')!.tag, '全部');
    expect(db.getFollowTagList(), hasLength(1));
    expect(db.getFollowTag('游戏')!.userId, ['douyu_4', 'douyu_5']);
  });

  test('settings overwrite present keys and retain absent keys and cookies',
      () async {
    await storage.settingsBox.putAll({
      'DanmuSize': 24.0,
      'ThemeMode': 1,
      'BilibiliCookie': 'test-old-cookie',
      'DouyinCookie': 'test-local-cookie',
    });
    final data = legacy()
      ..['config'] = {'ThemeMode': 2, 'BilibiliCookie': 'test-new-cookie'};
    await backup.importData(ConfigBackup.parse(data));
    expect(storage.settingsBox.toMap(), {
      'DanmuSize': 24.0,
      'ThemeMode': 2,
      'BilibiliCookie': 'test-new-cookie',
      'DouyinCookie': 'test-local-cookie',
    });
  });

  test('imported account B replaces A in storage and live playback', () async {
    await account.saveCookie(cookieA);
    final data = legacy()
      ..['douyuAccount'] = {'cookie': cookieB, 'enabled': 'true'};
    await backup.importData(ConfigBackup.parse(data));
    expect(account.exportData(), {'cookie': cookieB, 'enabled': 'true'});
    expect(account.hasSession.value, true);
    expect(account.useAccount.value, true);
    final site = Sites.allSites[Constant.kDouyu]!.liveSite as DouyuSite;
    expect(site.cookie, cookieB);
    final reopened = await DouyuAccountService().init();
    expect(reopened.exportData()['cookie'], cookieB);
  });

  test('disabled account stays disabled; empty exported account clears login',
      () async {
    await account.saveCookie(cookieA);
    final data = legacy()
      ..['douyuAccount'] = {'cookie': cookieB, 'enabled': 'false'};
    await backup.importData(ConfigBackup.parse(data));
    expect(account.hasSession.value, true);
    expect(account.useAccount.value, false);
    expect((Sites.allSites[Constant.kDouyu]!.liveSite as DouyuSite).cookie, '');
    data['douyuAccount'] = <String, String>{};
    await backup.importData(ConfigBackup.parse(data));
    expect(account.exportData()['cookie'], '');
    expect(account.hasSession.value, false);
  });

  test(
      'old backup leaves follows/account and keeps shield replacement behavior',
      () async {
    await db.addFollow(follow('1'));
    await account.saveCookie(cookieA);
    await storage.shieldBox.put('old', 'old');
    final data = legacy()..['shield'] = {'new': 'new'};
    await backup.importData(ConfigBackup.parse(data));
    expect(db.getFollowList(), hasLength(1));
    expect(account.exportData()['cookie'], cookieA);
    expect(storage.shieldBox.toMap(), {'new': 'new'});
  });

  test('invalid sections are rejected before any local data changes', () async {
    await storage.settingsBox.put('ThemeMode', 1);
    await storage.shieldBox.put('local', 'local');
    await account.saveCookie(cookieA);
    final malformed = [
      legacy()..['config'] = [],
      legacy()..['shield'] = {'bad': 1},
      legacy()..['follows'] = {},
      legacy()..['follows'] = [follow('1').toJson()..['id'] = 'wrong'],
      legacy()..['follows'] = [follow('1').toJson()..['addTime'] = 'bad-date'],
      legacy()..['douyuAccount'] = {'cookie': 'dy_auth=incomplete'},
      legacy()..['douyuAccount'] = {'cookie': '', 'enabled': 'true'},
      legacy()..['version'] = 99,
    ];
    for (final data in malformed) {
      await expectLater(
        () async => backup.importData(ConfigBackup.parse(data)),
        throwsFormatException,
      );
    }
    expect(storage.settingsBox.toMap(), {'ThemeMode': 1});
    expect(storage.shieldBox.toMap(), {'local': 'local'});
    expect(account.exportData()['cookie'], cookieA);
    expect(db.getFollowList(), isEmpty);
  });
}
