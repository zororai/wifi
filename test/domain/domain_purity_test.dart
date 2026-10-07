import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Enforces the domain-layer rule: lib/domain is pure Dart. It may import
/// only selected dart: libraries and other files inside lib/domain.
void main() {
  const allowedDartLibs = {'dart:math', 'dart:collection', 'dart:typed_data'};
  final domainDir = Directory(p.join('lib', 'domain'));
  final directive = RegExp(r'''^\s*(import|export|part)\s+['"]([^'"]+)['"]''');

  test('lib/domain exists and has Dart files', () {
    expect(domainDir.existsSync(), isTrue);
    expect(_dartFiles(domainDir), isNotEmpty);
  });

  test('lib/domain imports nothing outside pure Dart and itself', () {
    final violations = <String>[];
    final domainRoot = p.normalize(p.absolute(domainDir.path));
    for (final file in _dartFiles(domainDir)) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final m = directive.firstMatch(lines[i]);
        if (m == null) continue;
        final uri = m.group(2)!;
        final where = '${file.path}:${i + 1} -> $uri';
        if (uri.startsWith('dart:')) {
          if (!allowedDartLibs.contains(uri)) violations.add(where);
        } else if (uri.startsWith('package:')) {
          if (!uri.startsWith('package:rssi_mapper/domain/')) {
            violations.add(where);
          }
        } else {
          final target = p.normalize(
            p.absolute(p.join(p.dirname(file.path), uri)),
          );
          if (!p.isWithin(domainRoot, target)) violations.add(where);
        }
      }
    }
    expect(violations, isEmpty, reason: 'Non-pure imports in lib/domain');
  });
}

List<File> _dartFiles(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();
