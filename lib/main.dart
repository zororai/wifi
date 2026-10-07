import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  runApp(
    ProviderScope(
      // Failures must be shown to the user, not silently retried.
      retry: (retryCount, error) => null,
      child: const RssiMapperApp(),
    ),
  );
}
