import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

/// World point in ARCore world space (metres, y up).
class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;

  Map<String, double> toJson() => {'x': x, 'y': y, 'z': z};
}

/// Projects a world point to screen pixels using OpenGL column-major
/// view and projection matrices (as returned by ARCore Camera).
/// Returns null when the point is behind or too close to the camera.
Offset? projectToScreen(Vec3 p, Float32List view, Float32List proj, Size size) {
  // v = view * [x, y, z, 1]
  final vx = view[0] * p.x + view[4] * p.y + view[8] * p.z + view[12];
  final vy = view[1] * p.x + view[5] * p.y + view[9] * p.z + view[13];
  final vz = view[2] * p.x + view[6] * p.y + view[10] * p.z + view[14];
  final vw = view[3] * p.x + view[7] * p.y + view[11] * p.z + view[15];
  // c = proj * v
  final cx = proj[0] * vx + proj[4] * vy + proj[8] * vz + proj[12] * vw;
  final cy = proj[1] * vx + proj[5] * vy + proj[9] * vz + proj[13] * vw;
  final cw = proj[3] * vx + proj[7] * vy + proj[11] * vz + proj[15] * vw;
  if (cw <= 0.05) return null;
  final ndcX = cx / cw;
  final ndcY = cy / cw;
  return Offset((ndcX + 1) / 2 * size.width, (1 - ndcY) / 2 * size.height);
}
