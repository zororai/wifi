import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/result.dart';
import 'app_database.dart';

/// Single database instance for the app's lifetime.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Opens the database and reports whether it is usable. Failures are returned
/// as [Err] so the UI can explain them; they are never shown as success.
final databaseStatusProvider = FutureProvider<Result<DatabaseInfo>>((
  ref,
) async {
  try {
    final info = await ref.watch(appDatabaseProvider).healthCheck();
    return Ok(info);
  } catch (e, st) {
    return Err(
      DatabaseError(
        'The local database could not be opened.',
        cause: e,
        stackTrace: st,
      ),
    );
  }
});
