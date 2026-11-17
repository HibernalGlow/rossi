import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr/service/app_identity/data_migration.dart';

void main() {
  late Directory temp;
  late Directory legacy;
  late Directory current;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('rossi-identity-test-');
    legacy = Directory(p.join(temp.path, 'legacy'));
    current = Directory(p.join(temp.path, 'current'));
    await File(p.join(legacy.path, 'db', 'breeze_db', 'data.mdb'))
        .create(recursive: true);
    await File(p.join(legacy.path, 'db', 'breeze_db', 'data.mdb'))
        .writeAsString('database');
    await File(p.join(legacy.path, 'files', 'downloads', 'book.cbz'))
        .create(recursive: true);
    await File(p.join(legacy.path, 'files', 'downloads', 'book.cbz'))
        .writeAsString('comic');
  });

  tearDown(() => temp.delete(recursive: true));

  test('copies legacy data, validates it, and preserves source', () async {
    final result = await AppDataMigration(current)
        .run([LegacyAppData(legacy.path)]);

    expect(result['status'], 'copied');
    expect(
      await File(p.join(current.path, 'db', 'breeze_db', 'data.mdb'))
          .readAsString(),
      'database',
    );
    expect(
      await File(p.join(current.path, 'files', 'downloads', 'book.cbz'))
          .readAsString(),
      'comic',
    );
    expect(
      await File(p.join(legacy.path, 'db', 'breeze_db', 'data.mdb'))
          .readAsString(),
      'database',
    );
    expect(
      await File(p.join(current.path, AppDataMigration.markerName)).exists(),
      isTrue,
    );
  });

  test('does not recopy after a marker exists', () async {
    final migration = AppDataMigration(current);
    await migration.run([LegacyAppData(legacy.path)]);
    await File(p.join(legacy.path, 'files', 'downloads', 'book.cbz'))
        .writeAsString('changed');

    final result = await migration.run([LegacyAppData(legacy.path)]);
    expect(result['status'], 'copied');
    expect(
      await File(p.join(current.path, 'files', 'downloads', 'book.cbz'))
          .readAsString(),
      'comic',
    );
  });

  test('preserves both source and destination when validation fails', () async {
    await current.create();
    await File(p.join(current.path, 'keep.txt')).writeAsString('keep');
    await expectLater(
      AppDataMigration(current).run(
        [LegacyAppData(legacy.path)],
        validateCopy: (_) async => throw const FormatException('bad database'),
      ),
      throwsFormatException,
    );
    expect(
      await File(p.join(legacy.path, 'db', 'breeze_db', 'data.mdb'))
          .readAsString(),
      'database',
    );
    expect(await File(p.join(current.path, 'keep.txt')).readAsString(), 'keep');
    expect(
      await File(p.join(current.path, AppDataMigration.markerName)).exists(),
      isFalse,
    );
    final stages = await temp
        .list()
        .where(
          (entry) => p.basename(entry.path).startsWith('current.migrating-'),
        )
        .toList();
    expect(stages, hasLength(1));
    expect(
      await File(p.join(stages.single.path, 'db', 'breeze_db', 'data.mdb'))
          .exists(),
      isTrue,
    );
  });

  test(
    'keeps pre-existing new data and never overwrites an existing database',
    () async {
      final file = File(p.join(current.path, 'db', 'breeze_db', 'data.mdb'));
      await file.create(recursive: true);
      await file.writeAsString('new database');
      final result = await AppDataMigration(current)
          .run([LegacyAppData(legacy.path)]);
      expect(result['status'], 'existing');
      expect(await file.readAsString(), 'new database');
    },
  );

  test(
    'renames pre-existing destination and skips lock files and executables',
    () async {
      await current.create();
      await File(p.join(current.path, 'keep.txt')).writeAsString('keep');
      await File(p.join(legacy.path, 'db', 'breeze_db', 'lock.mdb'))
          .writeAsString('lock');
      await File(p.join(legacy.path, 'zephyr.exe')).writeAsString('binary');
      await AppDataMigration(current).run([LegacyAppData(legacy.path)]);
      final saved = await temp
          .list()
          .where(
            (entry) =>
                p.basename(entry.path).startsWith('current.before-migration-'),
          )
          .toList();
      expect(saved, hasLength(1));
      expect(
        await File(p.join(saved.single.path, 'keep.txt')).readAsString(),
        'keep',
      );
      expect(
        await File(p.join(current.path, 'db', 'breeze_db', 'lock.mdb'))
            .exists(),
        isFalse,
      );
      expect(await File(p.join(current.path, 'zephyr.exe')).exists(), isFalse);
    },
  );

  test('refuses symlinks and preserves source', () async {
    await Link(p.join(legacy.path, 'files', 'escape')).create(temp.path);
    await expectLater(
      AppDataMigration(current).run([LegacyAppData(legacy.path)]),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      await File(p.join(legacy.path, 'db', 'breeze_db', 'data.mdb')).exists(),
      isTrue,
    );
    expect(
      await File(p.join(current.path, AppDataMigration.markerName)).exists(),
      isFalse,
    );
  });

  test('quarantines an unopenable copy and records it', () async {
    final migration = AppDataMigration(current);
    final result = await migration.run([LegacyAppData(legacy.path)]);
    final error = Exception(
      "DB's last entity ID 27 is higher than 26 from model",
    );

    final next = await migration.quarantineDatabase(result, error);

    expect(next['status'], 'incompatible');
    expect(next['sourcePreserved'], isTrue);
    expect(next['source'], legacy.path);
    expect(
      await Directory(p.join(current.path, 'db', 'breeze_db')).exists(),
      isFalse,
    );
    final quarantined = await Directory(p.join(current.path, 'db'))
        .list()
        .where((entry) => entry.path.contains('breeze_db.incompatible-'))
        .toList();
    expect(quarantined, hasLength(1));
    expect(
      await File(p.join(quarantined.single.path, 'data.mdb')).readAsString(),
      'database',
    );
    final marker = jsonDecode(
      await File(p.join(current.path, AppDataMigration.markerName))
          .readAsString(),
    ) as Map<String, dynamic>;
    expect(marker['status'], 'incompatible');
    // 旧应用目录原样保留。
    expect(
      await File(p.join(legacy.path, 'db', 'breeze_db', 'data.mdb')).exists(),
      isTrue,
    );
  });
}
