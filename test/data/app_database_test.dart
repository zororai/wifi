import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rssi_mapper/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('initialises and reports schema version 1', () async {
    final info = await db.healthCheck();
    expect(info.schemaVersion, 1);
    expect(info.sqliteVersion, matches(RegExp(r'^3\.\d+\.\d+')));
  });

  test('enables foreign keys on open (needed for cascade delete)', () async {
    final info = await db.healthCheck();
    expect(info.foreignKeysEnabled, isTrue);
  });
}
