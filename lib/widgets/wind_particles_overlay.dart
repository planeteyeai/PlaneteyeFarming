import 'dart:math';
import 'package:flutter/material.dart';
import '../services/weather_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  ATMOSPHERIC PARTICLES OVERLAY  — dust · pollen · fine debris
//
//  Renders barely-visible floating motes that drift in the wind direction.
//  Tiny dots (0.8–2.2px radius) with ultra-low opacity (max 0.18).
//  Wind < 1.5 m/s  → nothing (still air = no visible particles)
//  Wind 1.5–4 m/s  → sparse slow motes
//  Wind 4–9 m/s    → moderate, gentle drift
//  Wind 9+ m/s     → denser, faster (still subtle)
//
//  Performance: Canvas dots only, no blur, no images. ~60fps.
// ═══════════════════════════════════════════════════════════════════════════

class WindParticlesOverlay extends StatefulWidget {
  final WeatherData? weather;
  const WindParticlesOverlay({super.key, required this.weather});

  @override
  State<WindParticlesOverlay> createState() => _WindParticlesOverlayState();
}

class _WindParticlesOverlayState extends State<WindParticlesOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final List<_AtmosphericMote> _motes = [];
  final _rng = Random(1337);
  double _time = 0.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..addListener(_tick)
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.removeListener(_tick);
    _ctrl.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final w = widget.weather;
    final windSpeed = w?.windSpeedMs ?? 0.0;

    if (windSpeed < 1.5) {
      if (_motes.isNotEmpty) setState(() => _motes.clear());
      return;
    }

    const dt = 1.0 / 60.0;
    _time += dt;

    final windDeg   = w?.windDeg ?? 270.0;
    final travelRad = (windDeg + 180.0) * pi / 180.0 - pi / 2.0;
    final baseDx    = cos(travelRad);
    final baseDy    = sin(travelRad);
    final speedScale = ((windSpeed - 1.5) / 10.5).clamp(0.0, 1.0);
    final motionSpeed = 0.08 + speedScale * 0.22;
    final maxMotes   = (4 + speedScale * 16).round().clamp(4, 20);

    if (_motes.length < maxMotes && _rng.nextDouble() < (0.06 + speedScale * 0.10)) {
      _motes.add(_AtmosphericMote.spawn(_rng, windDeg));
    }

    for (final m in _motes) {
      m.x += baseDx * motionSpeed * m.speedFactor * dt * 60;
      m.y += baseDy * motionSpeed * m.speedFactor * dt * 60;
      final wobble = sin(_time * m.wobbleFreq + m.wobblePhase) * 0.0008;
      m.x += -baseDy * wobble;
      m.y +=  baseDx * wobble;
      m.life -= dt * (0.12 + speedScale * 0.06);
    }

    _motes.removeWhere((m) =>
        m.life <= 0 ||
        m.x < -0.12 || m.x > 1.12 ||
        m.y < -0.12 || m.y > 1.12);

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final windSpeed = widget.weather?.windSpeedMs ?? 0.0;
    if (windSpeed < 1.5 || _motes.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      child: CustomPaint(
        painter: _AtmosphericMotesPainter(motes: List.unmodifiable(_motes)),
        size: Size.infinite,
      ),
    );
  }
}

class _AtmosphericMote {
  double x, y, life;
  final double radius, opacity, speedFactor, wobbleFreq, wobblePhase;
  final Color color;

  _AtmosphericMote({
    required this.x, required this.y, required this.life,
    required this.radius, required this.opacity,
    required this.speedFactor, required this.wobbleFreq,
    required this.wobblePhase, required this.color,
  });

  factory _AtmosphericMote.spawn(Random rng, double windDeg) {
    final travelRad = (windDeg + 180.0) * pi / 180.0 - pi / 2.0;
    final dx = cos(travelRad);
    final dy = sin(travelRad);
    double x, y;
    if (dx.abs() >= dy.abs()) {
      x = dx > 0 ? -0.05 : 1.05;
      y = rng.nextDouble();
    } else {
      y = dy > 0 ? -0.05 : 1.05;
      x = rng.nextDouble();
    }
    if (rng.nextDouble() < 0.35) { x = rng.nextDouble(); y = rng.nextDouble(); }

    final colorChoice = rng.nextInt(3);
    final color = colorChoice == 0
        ? const Color(0xFFF5F0E8)   // warm dust
        : colorChoice == 1
            ? const Color(0xFFEDE8D5) // sand/pollen
            : const Color(0xFFDDE8D0); // faint green pollen

    return _AtmosphericMote(
      x: x, y: y,
      life: 0.7 + rng.nextDouble() * 0.30,
      radius: 0.8 + rng.nextDouble() * 1.4,
      opacity: 0.06 + rng.nextDouble() * 0.12,
      speedFactor: 0.5 + rng.nextDouble() * 1.0,
      wobbleFreq: 0.8 + rng.nextDouble() * 1.6,
      wobblePhase: rng.nextDouble() * pi * 2,
      color: color,
    );
  }
}

class _AtmosphericMotesPainter extends CustomPainter {
  final List<_AtmosphericMote> motes;
  const _AtmosphericMotesPainter({required this.motes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final m in motes) {
      final fadeIn  = m.life > 0.8 ? (1.0 - m.life) / 0.2 : 1.0;
      final fadeOut = m.life < 0.2 ? m.life / 0.2 : 1.0;
      final alpha   = (m.opacity * fadeIn * fadeOut).clamp(0.0, 0.18);
      if (alpha < 0.01) continue;
      paint.color = m.color.withOpacity(alpha);
      canvas.drawCircle(Offset(m.x * size.width, m.y * size.height), m.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AtmosphericMotesPainter old) => true;
}
