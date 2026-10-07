import 'package:flutter_test/flutter_test.dart';
import 'package:rssi_mapper/domain/geometry/canvas_mapping.dart';
import 'package:rssi_mapper/domain/model/room.dart';

void main() {
  group('CanvasMapping', () {
    final m = CanvasMapping(
      canvasWidthPx: 400,
      canvasHeightPx: 800,
      roomWidthM: 5,
      roomLengthM: 10,
    );

    test('pixels to metres uses the actual drawing area', () {
      final c = m.toRoom(200, 400);
      expect(c.x, closeTo(2.5, 1e-12));
      expect(c.y, closeTo(5, 1e-12));
      expect(m.toRoom(0, 0), const RoomPoint(0, 0));
      final far = m.toRoom(400, 800);
      expect(far.x, closeTo(5, 1e-12));
      expect(far.y, closeTo(10, 1e-12));
    });

    test('non-square scaling is handled per axis', () {
      final n = CanvasMapping(
        canvasWidthPx: 300,
        canvasHeightPx: 300,
        roomWidthM: 6,
        roomLengthM: 3,
      );
      final p = n.toRoom(150, 150);
      expect(p.x, closeTo(3, 1e-12));
      expect(p.y, closeTo(1.5, 1e-12));
    });

    test('metres to pixels is the inverse', () {
      final px = m.toCanvas(const RoomPoint(1.25, 7.5));
      expect(px.x, closeTo(100, 1e-9));
      expect(px.y, closeTo(600, 1e-9));
      final back = m.toRoom(px.x, px.y);
      expect(back.x, closeTo(1.25, 1e-9));
      expect(back.y, closeTo(7.5, 1e-9));
    });

    test('invalid dimensions throw', () {
      expect(
        () => CanvasMapping(
          canvasWidthPx: 0,
          canvasHeightPx: 1,
          roomWidthM: 1,
          roomLengthM: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => CanvasMapping(
          canvasWidthPx: 1,
          canvasHeightPx: 1,
          roomWidthM: double.nan,
          roomLengthM: 1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('fitRoomToArea', () {
    test('keeps the room aspect ratio (to scale)', () {
      final a = fitRoomToArea(
        availableWidthPx: 400,
        availableHeightPx: 400,
        roomWidthM: 5,
        roomLengthM: 10,
      );
      expect(a.width, closeTo(200, 1e-9));
      expect(a.height, closeTo(400, 1e-9));
    });
    test('wide room is limited by width', () {
      final a = fitRoomToArea(
        availableWidthPx: 300,
        availableHeightPx: 600,
        roomWidthM: 6,
        roomLengthM: 3,
      );
      expect(a.width, closeTo(300, 1e-9));
      expect(a.height, closeTo(150, 1e-9));
    });
  });

  group('Room', () {
    test('valid room', () {
      expect(Room.validate(widthM: 5, lengthM: 4, gridSpacingM: 1), isEmpty);
      expect(Room(widthM: 5, lengthM: 4, gridSpacingM: 1).widthM, 5);
    });

    test('zero, negative and non-finite values are rejected', () {
      expect(Room.validate(widthM: 0, lengthM: -1, gridSpacingM: double.nan), [
        const RoomIssue(RoomField.width, RoomIssueKind.notPositive),
        const RoomIssue(RoomField.length, RoomIssueKind.notPositive),
        const RoomIssue(RoomField.gridSpacing, RoomIssueKind.notFinite),
      ]);
      expect(
        () => Room(widthM: 0, lengthM: 4, gridSpacingM: 1),
        throwsArgumentError,
      );
    });

    test('grid spacing larger than the room is rejected', () {
      expect(Room.validate(widthM: 5, lengthM: 2, gridSpacingM: 2.5), [
        const RoomIssue(RoomField.gridSpacing, RoomIssueKind.largerThanRoom),
      ]);
      expect(Room.validate(widthM: 5, lengthM: 2, gridSpacingM: 2), isEmpty);
    });

    test('non-numeric text input is rejected', () {
      expect(Room.validateInput(width: 'abc', length: '4', gridSpacing: ''), [
        const RoomIssue(RoomField.width, RoomIssueKind.notNumeric),
        const RoomIssue(RoomField.gridSpacing, RoomIssueKind.notNumeric),
      ]);
      expect(
        Room.validateInput(width: ' 5.5 ', length: '4', gridSpacing: '0.5'),
        isEmpty,
      );
    });

    test('contains is inclusive of the boundary', () {
      final r = Room(widthM: 5, lengthM: 4, gridSpacingM: 1);
      expect(r.contains(const RoomPoint(0, 0)), isTrue);
      expect(r.contains(const RoomPoint(5, 4)), isTrue);
      expect(r.contains(const RoomPoint(5.01, 2)), isFalse);
      expect(r.contains(const RoomPoint(2, -0.01)), isFalse);
      expect(r.contains(const RoomPoint(double.nan, 1)), isFalse);
    });
  });
}
