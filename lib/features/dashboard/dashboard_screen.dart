import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';

import '../../core/result.dart';
import '../../data/database/app_database.dart';
import '../../data/database/database_providers.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RSSI Mapper')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _IntroCard(),
          SizedBox(height: 16),
          _ActionsCard(),
          SizedBox(height: 16),
          _DatabaseStatusCard(),
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Indoor Wi-Fi RSSI mapping', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Measure Wi-Fi RSSI (a device-reported signal strength '
              'indicator, in dBm) at known positions in a rectangular room. '
              'Maps are built only from the points you measure plus '
              'interpolation between them. The camera cannot see Wi-Fi, '
              'and the app cannot locate the router.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'All data stays on this device unless you export it.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard();

  @override
  Widget build(BuildContext context) {
    // Destinations are enabled by the phases that implement them.
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _ActionTile(
            icon: Icons.add_location_alt_outlined,
            title: 'New survey',
            subtitle: 'Choose the Wi-Fi access point to measure',
            onTap: () => context.push(AppRoutes.scanner),
          ),
          const Divider(height: 1),
          const _ActionTile(icon: Icons.history, title: 'Previous surveys'),
          const Divider(height: 1),
          const _ActionTile(icon: Icons.tune, title: 'Settings'),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Null while the destination is not implemented yet.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: onTap != null,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle ?? 'Not available in this build yet'),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _DatabaseStatusCard extends ConsumerWidget {
  const _DatabaseStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(databaseStatusProvider);
    final scheme = Theme.of(context).colorScheme;

    final Widget tile = switch (status) {
      AsyncData(value: Ok(value: final DatabaseInfo info)) => ListTile(
        leading: Icon(Icons.check_circle_outline, color: scheme.primary),
        title: const Text('Local database ready'),
        subtitle: Text(
          'SQLite ${info.sqliteVersion} · schema v${info.schemaVersion}'
          '${info.foreignKeysEnabled ? '' : ' · foreign keys OFF'}',
        ),
      ),
      AsyncData(value: Err(:final error)) => ListTile(
        leading: Icon(Icons.error_outline, color: scheme.error),
        title: Text(error.message),
        subtitle: const Text('Surveys cannot be saved until this is fixed.'),
        trailing: TextButton(
          // Recreates the database instance, which re-runs the status check.
          onPressed: () => ref.invalidate(appDatabaseProvider),
          child: const Text('Retry'),
        ),
      ),
      AsyncError() => ListTile(
        leading: Icon(Icons.error_outline, color: scheme.error),
        title: const Text('The local database could not be opened.'),
        trailing: TextButton(
          // Recreates the database instance, which re-runs the status check.
          onPressed: () => ref.invalidate(appDatabaseProvider),
          child: const Text('Retry'),
        ),
      ),
      _ => const ListTile(
        leading: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Opening local database…'),
      ),
    };

    return Card(child: tile);
  }
}
