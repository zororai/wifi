import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Local SQLite database (offline only).
///
/// Phase 1 initialises the database with no tables. The Survey and
/// Measurement tables (spec section 17) are added in Phase 6 together with the
/// migration from schema version 1.
@DriftDatabase(tables: [])
class AppDatabase extends _$AppDatabase {
  /// Pass an [executor] in tests (e.g. `NativeDatabase.memory()`).
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  static const fileName = 'rssi_mapper';

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // Required later for Measurement -> Survey ON DELETE CASCADE.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// drift_flutter runs SQLite in a background isolate, so queries never
  /// block the UI isolate. The file lives in the app documents directory.
  static QueryExecutor _openConnection() => driftDatabase(name: fileName);

  /// Opens the database (running migrations) and reports basic facts.
  Future<DatabaseInfo> healthCheck() async {
    final version = await customSelect('SELECT sqlite_version() AS v')
        .getSingle();
    final fk = await customSelect('PRAGMA foreign_keys').getSingle();
    return DatabaseInfo(
      sqliteVersion: version.read<String>('v'),
      schemaVersion: schemaVersion,
      foreignKeysEnabled: fk.read<int>('foreign_keys') == 1,
    );
  }
}

class DatabaseInfo {
  const DatabaseInfo({
    required this.sqliteVersion,
    required this.schemaVersion,
    required this.foreignKeysEnabled,
  });

  final String sqliteVersion;
  final int schemaVersion;
  final bool foreignKeysEnabled;
}
