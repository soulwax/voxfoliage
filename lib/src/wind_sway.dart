import 'dart:math' as math;

import 'math.dart';
import 'scatter.dart';

/// Instantaneous animated pose evaluated by [WindSwayInstanceBuffer] for one foliage instance.
final class FoliageSwayPose {
  final FoliageInstance instance;
  final double bendXRadians;
  final double bendZRadians;
  final double animatedYawRadians;

  const FoliageSwayPose({
    required this.instance,
    required this.bendXRadians,
    required this.bendZRadians,
    required this.animatedYawRadians,
  });

  double get totalBendRadians =>
      math.sqrt(bendXRadians * bendXRadians + bendZRadians * bendZRadians);
}

/// Evaluates dual-octave harmonic wind gusts across visible [FoliageInstance]s without heap churn.
final class WindSwayInstanceBuffer {
  double timeSeconds = 0.0;
  double windSpeed;
  double gustStrength;
  FoliageVec2 windDirection;

  final List<FoliageSwayPose> _poses = [];

  WindSwayInstanceBuffer({
    this.windSpeed = 3.5,
    this.gustStrength = 0.35,
    FoliageVec2 windDirection = const FoliageVec2(1.0, 0.35),
  }) : windDirection = windDirection.normalized;

  List<FoliageSwayPose> get poses => List.unmodifiable(_poses);

  void advance(double dt) {
    if (dt > 0.0) timeSeconds += dt;
  }

  /// Evaluates harmonic sway tilt angles across [visibleInstances].
  List<FoliageSwayPose> evaluate(Iterable<FoliageInstance> visibleInstances) {
    _poses.clear();
    final dir = windDirection.normalized;
    // Steady breeze + turbulent traveling spatial gust wave
    final baseTilt = (windSpeed * 0.028).clamp(0.0, 0.42);
    for (final inst in visibleInstances) {
      final invStiff = (1.0 - inst.windStiffness * 0.7).clamp(0.15, 1.25);
      final spatialPhase =
          (inst.position.x * dir.x + inst.position.z * dir.z) * 0.22;
      final primaryWave = math.sin(
        timeSeconds * inst.bendFrequency + inst.phaseOffset + spatialPhase,
      );
      final gustWave = math.sin(
        timeSeconds * (inst.bendFrequency * 2.35) - spatialPhase * 0.65,
      );
      final mag = (baseTilt + gustStrength * 0.14 * (primaryWave * 0.7 + gustWave * 0.3)) *
          invStiff;

      // Crosswind flutter along perpendicular tangent
      final perp = FoliageVec2(-dir.z, dir.x);
      final flutter = gustWave * 0.045 * invStiff * (windSpeed > 0.1 ? 1.0 : 0.0);

      // Rotate tilt axes into pitch/roll bend angles relative to wind vector
      final leanVecX = dir.x * mag + perp.x * flutter;
      final leanVecZ = dir.z * mag + perp.z * flutter;

      _poses.add(
        FoliageSwayPose(
          instance: inst,
          bendXRadians: leanVecZ, // rotation around +X leans toward +Z
          bendZRadians: -leanVecX, // rotation around -Z leans toward +X
          animatedYawRadians: inst.yawRadians + primaryWave * 0.025 * invStiff,
        ),
      );
    }
    return _poses;
  }
}
