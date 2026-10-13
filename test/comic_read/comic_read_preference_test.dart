import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/config/global/global_setting.dart';
import 'package:zephyr/cubit/comic_read_preference_cubit.dart';
import 'package:zephyr/object_box/model.dart';

ComicReadPreference _preference({String patch = '{}', bool deleted = false}) =>
    ComicReadPreference(
      uniqueKey: 'source:comic',
      source: 'source',
      comicId: 'comic',
      overridesJson: patch,
      updatedAt: DateTime.utc(2026, 10, 13),
      deleted: deleted,
    );

void main() {
  test('本漫显式默认值覆盖全局，其余字段继续跟随全局更新', () {
    final preference = _preference(patch: '{"readMode":0}');
    const global = ReadSettingState(readMode: 2, doublePageMode: true);
    final effective = ComicReadPreferenceService.resolveEffective(
      global,
      preference.overrideSetting,
    );
    expect(effective.readMode, 0);
    expect(effective.doublePageMode, isTrue);
    final changedGlobal = global.copyWith(doublePageMode: false);
    expect(
      ComicReadPreferenceService.resolveEffective(
        changedGlobal,
        preference.overrideSetting,
      ).doublePageMode,
      isFalse,
    );
  });

  test('只记录本次修改的键，保留已有覆盖，不把全局快照写进本漫', () {
    final preference = _preference(patch: '{"readMode":2}');
    const global = ReadSettingState(autoScroll: true, doublePageMode: true);
    final effective = ComicReadPreferenceService.resolveEffective(
      global,
      preference.overrideSetting,
    );
    expect(
      preference.applyChanges(
        effective,
        effective.copyWith(doublePageMode: false),
      ),
      {'doublePageMode'},
    );
    expect(jsonDecode(preference.overridesJson), {
      'readMode': 2,
      'doublePageMode': false,
    });
    expect(preference.applyChanges(effective, effective), isEmpty);
  });

  test('旧备份的 readMode 迁移为单键 patch，可往返新版备份', () {
    final legacy = ComicReadPreference.fromJson({
      'id': 0,
      'uniqueKey': 'source:comic',
      'source': 'source',
      'comicId': 'comic',
      'readMode': 2,
      'updatedAt': DateTime.utc(2026, 10, 13).toIso8601String(),
      'deleted': false,
    });
    expect(legacy.overrideSetting!.keys, {'readMode'});
    expect(legacy.overrideSetting!.setting.readMode, 2);
    final exported = legacy.toJson();
    expect(exported.containsKey('readMode'), isFalse);
    final imported = ComicReadPreference.fromJson(exported);
    expect(imported.overrideSetting!.keys, {'readMode'});
    expect(imported.overrideSetting!.setting.readMode, 2);
  });

  test('删除墓碑、非法 JSON 和错误字段类型均不能覆盖全局', () {
    const global = ReadSettingState(readMode: 1);
    for (final preference in [
      _preference(patch: '{"readMode":2}', deleted: true),
      _preference(patch: 'not json'),
      _preference(patch: '{"readMode":"2","doublePageMode":1,"unknown":true}'),
    ]) {
      expect(preference.overrideSetting, isNull);
      expect(
        ComicReadPreferenceService.resolveEffective(
          global,
          preference.overrideSetting,
        ),
        global,
      );
    }
  });
}
