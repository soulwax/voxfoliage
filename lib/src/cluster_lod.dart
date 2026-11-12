import 'dart:math' as math;

import 'math.dart';
import 'scatter.dart';

/// Density thinning tier for foliage clusters based on camera distance.
enum FoliageLodTier {
  fullDensity(1),
  reduced50(2),
  sparse25(4),
  culled(0);

  final int stride;
  const FoliageLodTier(this.stride);
}

/// Spatial hash bucket holding nearby foliage instances for fast cluster culling.
final class FoliageClusterCell {
  final int cellX;
  final int cellZ;
  final List<FoliageInstance> instances = [];
  FoliageVec3 center = FoliageVec3.zero;
  double radius = 0.0;

  FoliageClusterCell(this.cellX, this.cellZ);

  void finalizeBounds() {
    if (instances.isEmpty) {
      center = FoliageVec3.zero;
      radius = 0.0;
      return;
    }
    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var maxZ = -double.infinity;
    for (final inst in instances) {
      final p = inst.position;
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.z < minZ) minZ = p.z;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
      if (p.z > maxZ) maxZ = p.z;
    }
    center = FoliageVec3(
      (minX + maxX) * 0.5,
      (minY + maxY) * 0.5,
      (minZ + maxZ) * 0.5,
    );
    final dx = maxX - center.x;
    final dy = maxY - center.y;
    final dz = maxZ - center.z;
    radius = math.sqrt(dx * dx + dy * dy + dz * dz) + 1.0;
  }
}

/// Culled query result partitioned by [FoliageLodTier].
final class FoliageVisibleBatch {
  final List<FoliageInstance> visibleInstances;
  final int activeClusterCount;
  final int culledClusterCount;
  final Map<FoliageLodTier, int> tierInstanceCounts;

  const FoliageVisibleBatch({
    required this.visibleInstances,
    required this.activeClusterCount,
    required this.culledClusterCount,
    required this.tierInstanceCounts,
  });
}

/// Buckets foliage into square spatial cells for fast distance & frustum-sphere LOD thinning.
final class FoliageClusterGrid {
  final double cellSize;
  final Map<(int, int), FoliageClusterCell> _cells = {};
  int _totalInstances = 0;

  FoliageClusterGrid({this.cellSize = 16.0});

  int get clusterCount => _cells.length;
  int get totalInstances => _totalInstances;
  Iterable<FoliageClusterCell> get cells => _cells.values;

  void rebuild(Iterable<FoliageInstance> instances) {
    _cells.clear();
    _totalInstances = 0;
    final inv = 1.0 / math.max(1.0, cellSize);
    for (final inst in instances) {
      final cx = (inst.position.x * inv).floor();
      final cz = (inst.position.z * inv).floor();
      final cell = _cells.putIfAbsent((cx, cz), () => FoliageClusterCell(cx, cz));
      cell.instances.add(inst);
      _totalInstances++;
    }
    for (final cell in _cells.values) {
      cell.finalizeBounds();
    }
  }

  FoliageLodTier tierForDistance(
    double dist, {
    double lodFullDistance = 25.0,
    double lodMidDistance = 55.0,
    double maxDrawDistance = 95.0,
  }) {
    if (dist > maxDrawDistance) return FoliageLodTier.culled;
    if (dist <= lodFullDistance) return FoliageLodTier.fullDensity;
    if (dist <= lodMidDistance) return FoliageLodTier.reduced50;
    return FoliageLodTier.sparse25;
  }

  /// Queries visible instances around [cameraPosition], deterministically thinning distant cells.
  FoliageVisibleBatch queryVisible(
    FoliageVec3 cameraPosition, {
    double lodFullDistance = 25.0,
    double lodMidDistance = 55.0,
    double maxDrawDistance = 95.0,
  }) {
    final out = <FoliageInstance>[];
    final counts = {
      FoliageLodTier.fullDensity: 0,
      FoliageLodTier.reduced50: 0,
      FoliageLodTier.sparse25: 0,
      FoliageLodTier.culled: 0,
    };
    var activeClusters = 0;
    var culledClusters = 0;

    for (final cell in _cells.values) {
      final rawDist = cell.center.distanceTo(cameraPosition);
      final surfaceDist = math.max(0.0, rawDist - cell.radius);
      final tier = tierForDistance(
        surfaceDist,
        lodFullDistance: lodFullDistance,
        lodMidDistance: lodMidDistance,
        maxDrawDistance: maxDrawDistance,
      );
      if (tier == FoliageLodTier.culled) {
        culledClusters++;
        counts[FoliageLodTier.culled] =
            counts[FoliageLodTier.culled]! + cell.instances.length;
        continue;
      }
      activeClusters++;
      final stride = tier.stride;
      for (var i = 0; i < cell.instances.length; i += stride) {
        out.add(cell.instances[i]);
        counts[tier] = counts[tier]! + 1;
      }
    }

    return FoliageVisibleBatch(
      visibleInstances: out,
      activeClusterCount: activeClusters,
      culledClusterCount: culledClusters,
      tierInstanceCounts: counts,
    );
  }
}
