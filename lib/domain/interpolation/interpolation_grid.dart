import 'dart:math' as math;

import '../model/measurement.dart';
import '../model/room.dart';
import 'idw.dart';

/// Default NO DATA distance as a multiple of the survey grid spacing.
const defaultNoDataSpacingFactor = 1.5;

/// Resolution of an interpolation grid. Bounded so that computation and
/// memory stay mobile-appropriate.
final class GridSpec {
  /// Throws [ArgumentError] if either dimension is < 1 or the cell count
  /// exceeds [maxCells].
  GridSpec(this.columns, this.rows, {int maxCells = defaultMaxCells}) {
    if (columns < 1 || rows < 1) {
      throw ArgumentError(
        'Grid needs at least 1x1 cells, got ${columns}x$rows',
      );
    }
    if (columns * rows > maxCells) {
      throw ArgumentError('Grid ${columns}x$rows exceeds $maxCells cells');
    }
  }

  /// Cells of about [targetCellM] metres, reduced uniformly if that would
  /// exceed [maxCells].
  factory GridSpec.forRoom(
    Room room, {
    double targetCellM = 0.1,
    int maxCells = defaultMaxCells,
  }) {
    if (!targetCellM.isFinite || targetCellM <= 0) {
      throw ArgumentError.value(targetCellM, 'targetCellM');
    }
    var cell = targetCellM;
    var cols = (room.widthM / cell).ceil();
    var rows = (room.lengthM / cell).ceil();
    if (cols * rows > maxCells) {
      cell = math.sqrt(room.widthM * room.lengthM / maxCells);
      cols = (room.widthM / cell).floor();
      rows = (room.lengthM / cell).floor();
    }
    return GridSpec(math.max(1, cols), math.max(1, rows), maxCells: maxCells);
  }

  static const defaultMaxCells = 40000;

  final int columns;
  final int rows;

  int get cellCount => columns * rows;
}

/// One grid cell value.
final class GridCell {
  const GridCell(this.column, this.row, this.center, this.rssiDbm);
  final int column;
  final int row;
  final RoomPoint center;
  final double rssiDbm;
}

/// INTERPOLATED (estimated) RSSI over the room. Cells farther than the NO
/// DATA distance from every measured point hold null: they are never filled
/// with extrapolated values.
final class InterpolatedGrid {
  InterpolatedGrid._(this.room, this.spec, this.noDataDistanceM, this._values);

  final Room room;
  final GridSpec spec;
  final double? noDataDistanceM;
  final List<double?> _values;

  double get cellWidthM => room.widthM / spec.columns;
  double get cellHeightM => room.lengthM / spec.rows;

  RoomPoint cellCenter(int column, int row) =>
      RoomPoint((column + 0.5) * cellWidthM, (row + 0.5) * cellHeightM);

  /// Null means NO DATA.
  double? valueAt(int column, int row) => _values[row * spec.columns + column];

  /// Row-major values (null = NO DATA).
  List<double?> get values => List.unmodifiable(_values);

  Iterable<GridCell> get cellsWithData sync* {
    for (var r = 0; r < spec.rows; r++) {
      for (var c = 0; c < spec.columns; c++) {
        final v = valueAt(c, r);
        if (v != null) yield GridCell(c, r, cellCenter(c, r), v);
      }
    }
  }

  /// Highest interpolated cell. This is an ESTIMATE ("predicted/interpolated
  /// maximum"), never the primary strongest-signal result, which must be the
  /// strongest MEASURED point. Null if no cell has data.
  GridCell? get predictedMaximum {
    GridCell? best;
    for (final cell in cellsWithData) {
      if (best == null || cell.rssiDbm > best.rssiDbm) best = cell;
    }
    return best;
  }
}

/// Computes an IDW grid. Pure and synchronous: callers run it off the UI
/// isolate (e.g. `Isolate.run`) since all inputs are plain data.
///
/// [noDataDistanceM]: cells whose centre is farther than this from the
/// nearest measured point are NO DATA. Null disables masking (use only for
/// analysis, never for display). Throws [ArgumentError] if [points] is empty.
InterpolatedGrid computeIdwGrid({
  required List<MeasuredPoint> points,
  required Room room,
  required GridSpec spec,
  required IdwConfig config,
  required double? noDataDistanceM,
}) {
  if (noDataDistanceM != null &&
      (!noDataDistanceM.isFinite || noDataDistanceM <= 0)) {
    throw ArgumentError.value(noDataDistanceM, 'noDataDistanceM');
  }
  final idw = IdwInterpolator(points, config);
  final cw = room.widthM / spec.columns;
  final ch = room.lengthM / spec.rows;
  final values = List<double?>.filled(spec.cellCount, null);
  for (var r = 0; r < spec.rows; r++) {
    for (var c = 0; c < spec.columns; c++) {
      final center = RoomPoint((c + 0.5) * cw, (r + 0.5) * ch);
      if (noDataDistanceM != null) {
        var nearest = double.infinity;
        for (final p in points) {
          nearest = math.min(nearest, p.position.distanceTo(center));
        }
        if (nearest > noDataDistanceM) continue;
      }
      values[r * spec.columns + c] = idw.predict(center);
    }
  }
  return InterpolatedGrid._(room, spec, noDataDistanceM, values);
}
