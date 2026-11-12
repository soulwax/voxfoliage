import 'dart:math' as math;

import 'math.dart';
import 'poisson.dart';

/// Biome & placement rules for a single procedural foliage species.
final class FoliageSpeciesDef {
  final String id;
  final String name;
  final double minSpacing;
  final double minScale;
  final double maxScale;
  final double minElevation;
  final double maxElevation;
  final double maxSlopeDegrees;
  final double minDensityThreshold;
  final double windStiffness;
  final double bendFrequency;
  final bool alignToNormal;

  const FoliageSpeciesDef({
    required this.id,
    required this.name,
    this.minSpacing = 2.5,
    this.minScale = 0.85,
    this.maxScale = 1.25,
    this.minElevation = -1000.0,
    this.maxElevation = 1000.0,
    this.maxSlopeDegrees = 35.0,
    this.minDensityThreshold = 0.0,
    this.windStiffness = 0.75,
    this.bendFrequency = 1.6,
    this.alignToNormal = false,
  });
}

/// Placed individual plant/tree/grass clump instance metadata.
final class FoliageInstance {
  final int index;
  final String speciesId;
  final FoliageVec3 position;
  final double yawRadians;
  final double scale;
  final double slopeDegrees;
  final double phaseOffset;
  final double windStiffness;
  final double bendFrequency;

  const FoliageInstance({
    required this.index,
    required this.speciesId,
    required this.position,
    required this.yawRadians,
    required this.scale,
    required this.slopeDegrees,
    required this.phaseOffset,
    required this.windStiffness,
    required this.bendFrequency,
  });
}

/// Scatters species using Bridson blue-noise filtered by height, slope & biome density masks.
final class FoliageBiomeScatterer {
  final double originX;
  final double originZ;
  final double width;
  final double depth;

  const FoliageBiomeScatterer({
    this.originX = -50.0,
    this.originZ = -50.0,
    this.width = 100.0,
    this.depth = 100.0,
  });

  List<FoliageInstance> scatter({
    required FoliageSpeciesDef species,
    required double Function(double x, double z) heightSampler,
    double Function(double x, double z)? slopeDegreesSampler,
    double Function(double x, double z)? densityMaskSampler,
    bool Function(double x, double z)? exclusionPredicate,
    int seed = 42,
    int maxSamples = 6000,
  }) {
    final sampler = PoissonDiskSampler(
      originX: originX,
      originZ: originZ,
      width: width,
      depth: depth,
      minDistance: species.minSpacing,
    );
    final points = sampler.generate(
      seed: seed,
      maxSamples: maxSamples,
      exclusionPredicate: exclusionPredicate,
    );
    final rng = FoliageRng(seed ^ species.id.hashCode);
    final instances = <FoliageInstance>[];

    double estimateSlopeDegrees(double x, double z) {
      if (slopeDegreesSampler != null) return slopeDegreesSampler(x, z);
      const eps = 0.5;
      final hx1 = heightSampler(x + eps, z);
      final hx0 = heightSampler(x - eps, z);
      final hz1 = heightSampler(x, z + eps);
      final hz0 = heightSampler(x, z - eps);
      final dx = (hx1 - hx0) / (2.0 * eps);
      final dz = (hz1 - hz0) / (2.0 * eps);
      final grad = math.sqrt(dx * dx + dz * dz);
      return math.atan(grad) * 180.0 / math.pi;
    }

    for (final p in points) {
      final y = heightSampler(p.x, p.z);
      if (y < species.minElevation || y > species.maxElevation) continue;
      final slope = estimateSlopeDegrees(p.x, p.z);
      if (slope > species.maxSlopeDegrees) continue;
      if (densityMaskSampler != null) {
        final mask = densityMaskSampler(p.x, p.z);
        if (mask < species.minDensityThreshold) continue;
      }

      instances.add(
        FoliageInstance(
          index: instances.length,
          speciesId: species.id,
          position: FoliageVec3(p.x, y, p.z),
          yawRadians: rng.nextDouble() * math.pi * 2.0,
          scale: rng.range(species.minScale, species.maxScale),
          slopeDegrees: slope,
          phaseOffset: rng.nextDouble() * math.pi * 2.0,
          windStiffness: species.windStiffness,
          bendFrequency: species.bendFrequency,
        ),
      );
    }
    return instances;
  }
}
