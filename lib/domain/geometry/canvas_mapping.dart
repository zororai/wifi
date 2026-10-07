import 'dart:math' as math;

import '../model/room.dart';

/// Converts between canvas pixels and room metres using the ACTUAL drawing
/// area of the room on screen:
///
///   xM = xPx / canvasWidthPx  * roomWidthM
///   yM = yPx / canvasHeightPx * roomLengthM
///
/// Pixels are never used as distances; interpolation works in metres only.
final class CanvasMapping {
  /// Throws [ArgumentError] unless every dimension is positive and finite.
  CanvasMapping({
    required this.canvasWidthPx,
    required this.canvasHeightPx,
    required this.roomWidthM,
    required this.roomLengthM,
  }) {
    _requirePositive(canvasWidthPx, 'canvasWidthPx');
    _requirePositive(canvasHeightPx, 'canvasHeightPx');
    _requirePositive(roomWidthM, 'roomWidthM');
    _requirePositive(roomLengthM, 'roomLengthM');
  }

  final double canvasWidthPx;
  final double canvasHeightPx;
  final double roomWidthM;
  final double roomLengthM;

  RoomPoint toRoom(double xPx, double yPx) => RoomPoint(
    xPx / canvasWidthPx * roomWidthM,
    yPx / canvasHeightPx * roomLengthM,
  );

  ({double x, double y}) toCanvas(RoomPoint p) => (
    x: p.x / roomWidthM * canvasWidthPx,
    y: p.y / roomLengthM * canvasHeightPx,
  );
}

/// Largest drawing area with the room's aspect ratio that fits in the
/// available space, so the grid is drawn to scale.
({double width, double height}) fitRoomToArea({
  required double availableWidthPx,
  required double availableHeightPx,
  required double roomWidthM,
  required double roomLengthM,
}) {
  _requirePositive(availableWidthPx, 'availableWidthPx');
  _requirePositive(availableHeightPx, 'availableHeightPx');
  _requirePositive(roomWidthM, 'roomWidthM');
  _requirePositive(roomLengthM, 'roomLengthM');
  final scale = math.min(
    availableWidthPx / roomWidthM,
    availableHeightPx / roomLengthM,
  );
  return (width: roomWidthM * scale, height: roomLengthM * scale);
}

void _requirePositive(double v, String name) {
  if (!v.isFinite || v <= 0) {
    throw ArgumentError.value(v, name, 'must be positive and finite');
  }
}
