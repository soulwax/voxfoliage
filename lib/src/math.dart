import 'dart:math' as math;

/// Immutable 2D vector for XZ plane foliage scattering.
final class FoliageVec2 {
  final double x;
  final double z;

  const FoliageVec2(this.x, this.z);

  static const zero = FoliageVec2(0.0, 0.0);

  FoliageVec2 operator +(FoliageVec2 o) => FoliageVec2(x + o.x, z + o.z);
  FoliageVec2 operator -(FoliageVec2 o) => FoliageVec2(x - o.x, z - o.z);
  FoliageVec2 operator *(double s) => FoliageVec2(x * s, z * s);

  double dot(FoliageVec2 o) => x * o.x + z * o.z;
  double get lengthSquared => x * x + z * z;
  double get length => math.sqrt(lengthSquared);

  FoliageVec2 get normalized {
    final len = length;
    if (len < 1e-12) return const FoliageVec2(1.0, 0.0);
    return FoliageVec2(x / len, z / len);
  }
}

/// Immutable 3D vector for foliage world placement & camera coordinates.
final class FoliageVec3 {
  final double x;
  final double y;
  final double z;

  const FoliageVec3(this.x, this.y, this.z);

  static const zero = FoliageVec3(0.0, 0.0, 0.0);

  FoliageVec3 operator +(FoliageVec3 o) => FoliageVec3(x + o.x, y + o.y, z + o.z);
  FoliageVec3 operator -(FoliageVec3 o) => FoliageVec3(x - o.x, y - o.y, z - o.z);
  FoliageVec3 operator *(double s) => FoliageVec3(x * s, y * s, z * s);

  double distanceSquaredTo(FoliageVec3 o) {
    final dx = x - o.x;
    final dy = y - o.y;
    final dz = z - o.z;
    return dx * dx + dy * dy + dz * dz;
  }

  double distanceTo(FoliageVec3 o) => math.sqrt(distanceSquaredTo(o));
}

/// Deterministic fast Mulberry32 PRNG for reproducible blue-noise scattering.
final class FoliageRng {
  int _state;

  FoliageRng(int seed) : _state = seed == 0 ? 0x6D2B79F5 : seed;

  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _state;
    t = ((t ^ (t >>> 15)) * (t | 1)) & 0xFFFFFFFF;
    t = (t ^ (t + ((t ^ (t >>> 7)) * (t | 61)))) & 0xFFFFFFFF;
    return (t ^ (t >>> 14)) & 0xFFFFFFFF;
  }

  double nextDouble() => nextUint32() / 4294967296.0;

  double range(double minVal, double maxVal) =>
      minVal + (maxVal - minVal) * nextDouble();
}
