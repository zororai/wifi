import 'dart:math' as math;

/// A position inside a room, in metres.
///
/// Origin (0, 0) is one corner of the room; x runs along the width and y
/// along the length.
final class RoomPoint {
  const RoomPoint(this.x, this.y);

  final double x;
  final double y;

  double distanceTo(RoomPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  bool operator ==(Object other) =>
      other is RoomPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'RoomPoint($x, $y)';
}

enum RoomField { width, length, gridSpacing }

enum RoomIssueKind {
  /// Input text is not a number.
  notNumeric,

  /// NaN or infinity.
  notFinite,

  /// Zero or negative.
  notPositive,

  /// Grid spacing exceeds the shorter room side, so no grid fits.
  largerThanRoom,
}

final class RoomIssue {
  const RoomIssue(this.field, this.kind);

  final RoomField field;
  final RoomIssueKind kind;

  @override
  bool operator ==(Object other) =>
      other is RoomIssue && other.field == field && other.kind == kind;

  @override
  int get hashCode => Object.hash(field, kind);

  @override
  String toString() => 'RoomIssue(${field.name}, ${kind.name})';
}

/// Rectangular room (v1 supports rectangles only). Units: metres.
final class Room {
  /// Throws [ArgumentError] if the dimensions are invalid; use [validate]
  /// first to obtain user-explainable issues.
  Room({
    required this.widthM,
    required this.lengthM,
    required this.gridSpacingM,
  }) {
    final issues = validate(
      widthM: widthM,
      lengthM: lengthM,
      gridSpacingM: gridSpacingM,
    );
    if (issues.isNotEmpty) {
      throw ArgumentError('Invalid room dimensions: $issues');
    }
  }

  final double widthM;
  final double lengthM;
  final double gridSpacingM;

  /// Validates numeric dimensions. Returns an empty list when valid.
  static List<RoomIssue> validate({
    required double widthM,
    required double lengthM,
    required double gridSpacingM,
  }) {
    final issues = <RoomIssue>[];
    void check(RoomField field, double v) {
      if (!v.isFinite) {
        issues.add(RoomIssue(field, RoomIssueKind.notFinite));
      } else if (v <= 0) {
        issues.add(RoomIssue(field, RoomIssueKind.notPositive));
      }
    }

    check(RoomField.width, widthM);
    check(RoomField.length, lengthM);
    check(RoomField.gridSpacing, gridSpacingM);
    if (issues.isEmpty && gridSpacingM > math.min(widthM, lengthM)) {
      issues.add(
        const RoomIssue(RoomField.gridSpacing, RoomIssueKind.largerThanRoom),
      );
    }
    return issues;
  }

  /// Validates raw text input (e.g. from form fields).
  static List<RoomIssue> validateInput({
    required String width,
    required String length,
    required String gridSpacing,
  }) {
    final w = double.tryParse(width.trim());
    final l = double.tryParse(length.trim());
    final s = double.tryParse(gridSpacing.trim());
    final notNumeric = [
      if (w == null) const RoomIssue(RoomField.width, RoomIssueKind.notNumeric),
      if (l == null)
        const RoomIssue(RoomField.length, RoomIssueKind.notNumeric),
      if (s == null)
        const RoomIssue(RoomField.gridSpacing, RoomIssueKind.notNumeric),
    ];
    if (notNumeric.isNotEmpty) return notNumeric;
    return validate(widthM: w!, lengthM: l!, gridSpacingM: s!);
  }

  /// True when [p] lies inside the room or on its boundary.
  bool contains(RoomPoint p) =>
      p.x.isFinite &&
      p.y.isFinite &&
      p.x >= 0 &&
      p.x <= widthM &&
      p.y >= 0 &&
      p.y <= lengthM;
}
