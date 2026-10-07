import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rssi_mapper/app.dart';
import 'package:rssi_mapper/core/errors.dart';
import 'package:rssi_mapper/core/result.dart';
import 'package:rssi_mapper/data/database/app_database.dart';
import 'package:rssi_mapper/data/database/database_providers.dart';

Widget _app(Result<DatabaseInfo> status) => ProviderScope(
  overrides: [databaseStatusProvider.overrideWith((ref) async => status)],
  child: const RssiMapperApp(),
);

void main() {
  testWidgets('dashboard shows the three entry points', (tester) async {
    await tester.pumpWidget(
      _app(
        const Ok(
          DatabaseInfo(
            sqliteVersion: '3.50.0',
            schemaVersion: 1,
            foreignKeysEnabled: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('RSSI Mapper'), findsOneWidget);
    expect(find.text('New survey'), findsOneWidget);
    expect(find.text('Previous surveys'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('dashboard states the measurement limits honestly', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Ok(
          DatabaseInfo(
            sqliteVersion: '3.50.0',
            schemaVersion: 1,
            foreignKeysEnabled: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('camera cannot see Wi-Fi'), findsOneWidget);
    expect(find.textContaining('cannot locate the router'), findsOneWidget);
  });

  testWidgets('reports a ready database', (tester) async {
    await tester.pumpWidget(
      _app(
        const Ok(
          DatabaseInfo(
            sqliteVersion: '3.50.0',
            schemaVersion: 1,
            foreignKeysEnabled: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Local database ready'), findsOneWidget);
    expect(find.textContaining('SQLite 3.50.0'), findsOneWidget);
  });

  testWidgets('reports a database failure and never claims it is ready', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const Err(DatabaseError('The local database could not be opened.'))),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('The local database could not be opened.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Local database ready'), findsNothing);
  });
}
