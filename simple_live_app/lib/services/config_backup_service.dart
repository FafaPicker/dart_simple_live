import 'dart:io';

import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

/// The existing version-1 envelope, extended with optional backup sections.
class ConfigBackup {
  final String platform;
  final Map<String, dynamic> config;
  final Map<String, String> shield;
  final List<FollowUser> follows;
  final Map<String, String>? douyuAccount;

  ConfigBackup._(
      this.platform, this.config, this.shield, this.follows, this.douyuAccount);

  static Map<String, dynamic> _object(dynamic value) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('配置内容格式错误');
    }
    return Map<String, dynamic>.from(value);
  }

  factory ConfigBackup.parse(dynamic value) {
    final data = _object(value);
    if (data['type'] != 'simple_live' ||
        data['version'] != 1 ||
        data['platform'] is! String) {
      throw const FormatException('不支持的配置文件');
    }
    final config = _object(data['config']);
    final shield = _object(data['shield']);
    if (shield.values.any((value) => value is! String)) {
      throw const FormatException('屏蔽词格式错误');
    }
    final follows = <FollowUser>[];
    if (data.containsKey('follows')) {
      if (data['follows'] is! List) {
        throw const FormatException('关注列表格式错误');
      }
      for (final value in data['follows']) {
        final item = _object(value);
        for (final key in ['id', 'siteId', 'roomId', 'userName', 'face']) {
          if (item[key] is! String) {
            throw const FormatException('关注信息格式错误');
          }
        }
        if ((item['siteId'] as String).isEmpty ||
            (item['roomId'] as String).isEmpty ||
            item['id'] != '${item['siteId']}_${item['roomId']}' ||
            item['addTime'] is! String ||
            DateTime.tryParse(item['addTime']) == null ||
            (item['tag'] != null && item['tag'] is! String)) {
          throw const FormatException('关注信息格式错误');
        }
        follows.add(FollowUser.fromJson(item));
      }
    }
    final account = data.containsKey('douyuAccount')
        ? DouyuAccountService.validateBackup(_object(data['douyuAccount']))
        : null;
    return ConfigBackup._(data['platform'], config,
        Map<String, String>.from(shield), follows, account);
  }
}

class ConfigBackupService {
  final LocalStorageService storage;
  final DBService db;
  final DouyuAccountService account;

  ConfigBackupService(this.storage, this.db, this.account);

  Map<String, dynamic> exportData() => {
        'type': 'simple_live',
        'platform': Platform.operatingSystem,
        'version': 1,
        'time': DateTime.now().millisecondsSinceEpoch,
        'config': storage.settingsBox.toMap(),
        'shield': storage.shieldBox.toMap(),
        'follows': db.getFollowList().map((item) => item.toJson()).toList(),
        'douyuAccount': account.exportData(),
      };

  Future<void> importData(ConfigBackup backup) async {
    // Missing settings retain their local values; imported values win.
    await storage.settingsBox.putAll(backup.config);
    // Preserve the existing replacement semantics for shield keywords.
    await storage.shieldBox.clear();
    await storage.shieldBox.putAll(backup.shield);
    for (final follow in backup.follows) {
      // Keep local metadata and tags for an already-followed room.
      if (db.getFollowExist(follow.id)) continue;
      if (follow.tag != '全部') {
        final tag =
            db.getFollowTag(follow.tag) ?? await db.addFollowTag(follow.tag);
        if (!tag.userId.contains(follow.id)) {
          tag.userId.add(follow.id);
          await db.updateFollowTag(tag);
        }
      }
      await db.addFollow(follow);
    }
    // Old backups without this section leave the local account untouched.
    if (backup.douyuAccount != null) {
      await account.importData(backup.douyuAccount!);
    }
  }
}
