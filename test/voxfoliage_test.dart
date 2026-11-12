import 'package:test/test.dart';
import 'package:voxfoliage/voxfoliage.dart';

void main() {
  test('PoissonDiskSampler generates deterministic blue-noise distribution obeying minimum spacing & exclusions', () {
    const sampler = PoissonDiskSampler(
      originX: -10.0,
      originZ: -10.0,
      width: 20.0,
      depth: 20.0,
      minDistance: 2.2,
    );

    bool roadExclusion(double x, double z) => x.abs() < 1.5;

    final a = sampler.generate(seed: 9001, exclusionPredicate: roadExclusion);
    final b = sampler.generate(seed: 9001, exclusionPredicate: roadExclusion);
    expect(a.length, greaterThan(25));
    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(a[i].x, closeTo(b[i].x, 1e-9));
      expect(a[i].z, closeTo(b[i].z, 1e-9));
      expect(roadExclusion(a[i].x, a[i].z), isFalse);
    }

    // Verify all pairs maintain strict minimum spacing invariant.
    const minDistSq = 2.2 * 2.2 - 1e-6;
    for (var i = 0; i < a.length; i++) {
      for (var j = i + 1; j < a.length; j++) {
        final dx = a[i].x - a[j].x;
        final dz = a[i].z - a[j].z;
        expect(dx * dx + dz * dz, greaterThanOrEqualTo(minDistSq));
      }
    }
  });

  test('FoliageBiomeScatterer enforces elevation band, steep slope rejection & density masks', () {
    const scatterer = FoliageBiomeScatterer(
      originX: -20.0,
      originZ: -20.0,
      width: 40.0,
      depth: 40.0,
    );
    const pine = FoliageSpeciesDef(
      id: 'alpine_pine',
      name: 'Alpine Pine',
      minSpacing: 2.4,
      minElevation: 1.0,
      maxElevation: 8.0,
      maxSlopeDegrees: 25.0,
      minDensityThreshold: 0.4,
      minScale: 0.9,
      maxScale: 1.4,
    );

    // Ridge where x > 10 rises very steeply (> 45 deg) and x < -10 is underwater (y = 0)
    double terrainHeight(double x, double z) {
      if (x < -8.0) return 0.2;
      if (x > 8.0) return 2.0 + (x - 8.0) * 1.6;
      return 3.0;
    }

    final instances = scatterer.scatter(
      species: pine,
      heightSampler: terrainHeight,
      densityMaskSampler: (x, z) => z < -12.0 ? 0.1 : 0.8,
      seed: 77,
    );

    expect(instances, isNotEmpty);
    for (final inst in instances) {
      expect(inst.position.y, inInclusiveRange(1.0, 8.0));
      expect(inst.slopeDegrees, lessThanOrEqualTo(25.0));
      expect(inst.position.z, greaterThanOrEqualTo(-12.0));
      expect(inst.scale, inInclusiveRange(0.9, 1.4));
    }
  });

  test('FoliageClusterGrid thins distant LOD tiers and WindSwayInstanceBuffer animates breeze gusts', () {
    final instances = <FoliageInstance>[
      for (var i = 0; i < 12; i++)
        FoliageInstance(
          index: i,
          speciesId: 'fern',
          position: FoliageVec3(2.0 + i * 0.5, 0.0, 2.0), // Near cell (0,0)
          yawRadians: 0.0,
          scale: 1.0,
          slopeDegrees: 0.0,
          phaseOffset: i * 0.3,
          windStiffness: 0.4,
          bendFrequency: 1.8,
        ),
      for (var i = 0; i < 8; i++)
        FoliageInstance(
          index: 100 + i,
          speciesId: 'fern',
          position: FoliageVec3(35.0 + i * 0.4, 0.0, 2.0), // Mid-distance cell (2,0)
          yawRadians: 0.0,
          scale: 1.0,
          slopeDegrees: 0.0,
          phaseOffset: i * 0.3,
          windStiffness: 0.4,
          bendFrequency: 1.8,
        ),
      for (var i = 0; i < 8; i++)
        FoliageInstance(
          index: 200 + i,
          speciesId: 'fern',
          position: FoliageVec3(120.0 + i * 0.4, 0.0, 2.0), // Beyond maxDrawDistance -> culled
          yawRadians: 0.0,
          scale: 1.0,
          slopeDegrees: 0.0,
          phaseOffset: i * 0.3,
          windStiffness: 0.4,
          bendFrequency: 1.8,
        ),
    ];

    final grid = FoliageClusterGrid(cellSize: 16.0)..rebuild(instances);
    expect(grid.clusterCount, 3);

    final batch = grid.queryVisible(
      const FoliageVec3(4.0, 1.5, 2.0),
      lodFullDistance: 20.0,
      lodMidDistance: 50.0,
      maxDrawDistance: 85.0,
    );

    expect(batch.tierInstanceCounts[FoliageLodTier.fullDensity], 12);
    expect(batch.tierInstanceCounts[FoliageLodTier.reduced50], 4);
    expect(batch.tierInstanceCounts[FoliageLodTier.culled], 8);
    expect(batch.visibleInstances.length, 16);

    final wind = WindSwayInstanceBuffer(
      windSpeed: 6.0,
      gustStrength: 0.5,
      windDirection: const FoliageVec2(1.0, 0.0),
    );
    final posesT0 = List<FoliageSwayPose>.of(wind.evaluate(batch.visibleInstances));
    wind.advance(0.45);
    final posesT1 = wind.evaluate(batch.visibleInstances);

    expect(posesT0.length, batch.visibleInstances.length);
    expect(posesT0.first.totalBendRadians, greaterThan(0.01));
    // Strong +X wind predominantly creates tilt around Z
    expect(posesT0.first.bendZRadians.abs(), greaterThan(posesT0.first.bendXRadians.abs()));
    expect(
      (posesT1.first.bendZRadians - posesT0.first.bendZRadians).abs(),
      greaterThan(1e-4),
    );
  });
}
