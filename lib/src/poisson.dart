import 'dart:math' as math;

import 'math.dart';

/// Generated blue-noise point on the XZ plane with its assigned spacing radius.
final class PoissonDiskSample {
  final double x;
  final double z;
  final double radius;

  const PoissonDiskSample(this.x, this.z, this.radius);

  FoliageVec2 get xz => FoliageVec2(x, z);
}

/// Fast Bridson 2D Poisson-disk sampler generating naturally spaced organic distributions.
final class PoissonDiskSampler {
  final double width;
  final double depth;
  final double minDistance;
  final int maxAttemptsPerPoint;
  final double originX;
  final double originZ;

  const PoissonDiskSampler({
    required this.width,
    required this.depth,
    required this.minDistance,
    this.maxAttemptsPerPoint = 30,
    this.originX = 0.0,
    this.originZ = 0.0,
  });

  /// Samples points inside `[originX, originX + width) x [originZ, originZ + depth)`.
  /// Optional [exclusionPredicate] returns `true` for blocked positions (roads, water, buildings).
  List<PoissonDiskSample> generate({
    int seed = 1337,
    int maxSamples = 10000,
    bool Function(double x, double z)? exclusionPredicate,
  }) {
    if (width <= 0.0 || depth <= 0.0 || minDistance <= 1e-6 || maxSamples <= 0) {
      return const [];
    }
    final rng = FoliageRng(seed);
    final r = minDistance;
    final rSq = r * r;
    final cellSize = r / math.sqrt2;
    final cols = math.max(1, (width / cellSize).ceil());
    final rows = math.max(1, (depth / cellSize).ceil());
    final grid = List<int>.filled(cols * rows, -1);

    final samples = <PoissonDiskSample>[];
    final active = <int>[];

    bool inBounds(double lx, double lz) =>
        lx >= 0.0 && lx < width && lz >= 0.0 && lz < depth;

    bool fits(double lx, double lz) {
      final wx = originX + lx;
      final wz = originZ + lz;
      if (exclusionPredicate != null && exclusionPredicate(wx, wz)) {
        return false;
      }
      final gx = (lx / cellSize).floor().clamp(0, cols - 1);
      final gz = (lz / cellSize).floor().clamp(0, rows - 1);
      final minGx = math.max(0, gx - 2);
      final maxGx = math.min(cols - 1, gx + 2);
      final minGz = math.max(0, gz - 2);
      final maxGz = math.min(rows - 1, gz + 2);
      for (var nz = minGz; nz <= maxGz; nz++) {
        for (var nx = minGx; nx <= maxGx; nx++) {
          final idx = grid[nz * cols + nx];
          if (idx >= 0) {
            final other = samples[idx];
            final dx = other.x - wx;
            final dz = other.z - wz;
            if (dx * dx + dz * dz < rSq) return false;
          }
        }
      }
      return true;
    }

    void addSample(double lx, double lz) {
      final wx = originX + lx;
      final wz = originZ + lz;
      final sampleIdx = samples.length;
      samples.add(PoissonDiskSample(wx, wz, r));
      active.add(sampleIdx);
      final gx = (lx / cellSize).floor().clamp(0, cols - 1);
      final gz = (lz / cellSize).floor().clamp(0, rows - 1);
      grid[gz * cols + gx] = sampleIdx;
    }

    void growActiveQueue() {
      while (active.isNotEmpty && samples.length < maxSamples) {
        final activePos = rng.nextUint32() % active.length;
        final base = samples[active[activePos]];
        var found = false;
        for (var k = 0; k < maxAttemptsPerPoint; k++) {
          final angle = rng.nextDouble() * math.pi * 2.0;
          final dist = r * (1.0 + rng.nextDouble());
          final candLx = (base.x - originX) + math.cos(angle) * dist;
          final candLz = (base.z - originZ) + math.sin(angle) * dist;
          if (inBounds(candLx, candLz) && fits(candLx, candLz)) {
            addSample(candLx, candLz);
            found = true;
            break;
          }
        }
        if (!found) {
          active.removeAt(activePos);
        }
      }
    }

    // Try a few initial seed points in case the first hit an exclusion zone.
    for (var sTry = 0; sTry < 32 && samples.isEmpty; sTry++) {
      final sx = rng.nextDouble() * width;
      final sz = rng.nextDouble() * depth;
      if (fits(sx, sz)) {
        addSample(sx, sz);
      }
    }
    growActiveQueue();

    // Multi-island fallback: seed any disconnected valid patches separated by exclusions.
    for (var gz = 0; gz < rows && samples.length < maxSamples; gz++) {
      for (var gx = 0; gx < cols && samples.length < maxSamples; gx++) {
        if (grid[gz * cols + gx] >= 0) continue;
        final sx = (gx + rng.nextDouble()) * cellSize;
        final sz = (gz + rng.nextDouble()) * cellSize;
        if (inBounds(sx, sz) && fits(sx, sz)) {
          addSample(sx, sz);
          growActiveQueue();
        }
      }
    }
    return samples;
  }
}
