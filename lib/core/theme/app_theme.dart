import 'package:flutter/material.dart';

/// Material 3 theme. Signal-strength colours are NOT defined here: they belong
/// to the classification scale (Phase 2/5) so the legend and the map share one
/// source of truth.
abstract final class AppTheme {
  static const _seed = Color(0xFF00696E);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }
}
