import 'dart:math';
import 'package:flutter/material.dart';
import '../services/weather_service.dart';

// ═══════════════════════════════════════════════════════════════════
// WEATHER ANIMATION OVERLAY
// Drop this as a child of a Stack over the map.
// ═══════════════════════════════════════════════════════════════════

class WeatherAnimationOverlay extends StatefulWidget {
  final WeatherData? weather;
  const WeatherAnimationOverlay({super.key, required this.weather});

  @override
  State<WeatherAnimationOverlay> createState() =>
      _WeatherAnimationOverlayState();
}

class _WeatherAnimationOverlayState extends State<WeatherAnimationOverlay>
    with TickerProviderStateMixin {
  // Shared slow pulsing for sun glow
  late AnimationController _sunCtrl;
  // Wind / cloud drift
  late AnimationController _windCtrl;
  // Rain drops
  late AnimationController _rainCtrl;
  // Stars twinkle (night)
  late AnimationController _starCtrl;
  // Lightning flash (thunderstorm)
  late AnimationController _lightningCtrl;
  // Snow drift
  late AnimationController _snowCtrl;

  final _rng = Random(42);

  @override
  void initState() {
    super.initState();
    _sunCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _windCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
    _rainCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat();
    _starCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _lightningCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200))
      ..repeat(reverse: true);
    _snowCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
  }

  @override
  void dispose() {
    _sunCtrl.dispose();
    _windCtrl.dispose();
    _rainCtrl.dispose();
    _starCtrl.dispose();
    _lightningCtrl.dispose();
    _snowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.weather;
    if (w == null) return const SizedBox.shrink();

    return IgnorePointer(
      child: SizedBox.expand(
        child: _buildForCondition(w.condition, w),
      ),
    );
  }

  Widget _buildForCondition(WeatherCondition cond, WeatherData w) {
    switch (cond) {
      case WeatherCondition.clearDay:
        return _ClearDayLayer(ctrl: _sunCtrl);
      case WeatherCondition.clearNight:
        return _NightLayer(ctrl: _starCtrl, rng: _rng);
      case WeatherCondition.partlyCloudyDay:
        return _PartlyCloudyDayLayer(
            sunCtrl: _sunCtrl, windCtrl: _windCtrl, rng: _rng);
      case WeatherCondition.partlyCloudyNight:
        return _PartlyCloudyNightLayer(
            windCtrl: _windCtrl, starCtrl: _starCtrl, rng: _rng);
      case WeatherCondition.cloudy:
        return _CloudyLayer(ctrl: _windCtrl, rng: _rng);
      case WeatherCondition.rain:
        return _RainLayer(
            rainCtrl: _rainCtrl, windCtrl: _windCtrl, rng: _rng);
      case WeatherCondition.thunderstorm:
        return _ThunderstormLayer(
            rainCtrl: _rainCtrl,
            windCtrl: _windCtrl,
            lightningCtrl: _lightningCtrl,
            rng: _rng);
      case WeatherCondition.snow:
        return _SnowLayer(ctrl: _snowCtrl, rng: _rng);
      case WeatherCondition.foggy:
        return _FogLayer(ctrl: _windCtrl);
    }
  }
}

// ─────────────────────────────────────────────────────────────
// CLEAR DAY – glowing sun top-right
// ─────────────────────────────────────────────────────────────
class _ClearDayLayer extends StatelessWidget {
  final AnimationController ctrl;
  const _ClearDayLayer({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final glow = 80 + ctrl.value * 40;
        return CustomPaint(
          painter: _SunPainter(
            glowRadius: glow,
            opacity: 0.55 + ctrl.value * 0.15,
          ),
        );
      },
    );
  }
}

class _SunPainter extends CustomPainter {
  final double glowRadius;
  final double opacity;
  const _SunPainter({required this.glowRadius, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width - 60;
    const cy = 80.0;

    // outer glow
    final paint = Paint()
      ..shader = RadialGradient(colors: [
        Colors.yellow.withOpacity(opacity * 0.4),
        Colors.orange.withOpacity(opacity * 0.15),
        Colors.transparent,
      ]).createShader(Rect.fromCircle(
          center: Offset(cx, cy), radius: glowRadius));
    canvas.drawCircle(Offset(cx, cy), glowRadius, paint);

    // sun disc
    canvas.drawCircle(
        Offset(cx, cy),
        28,
        Paint()
          ..color = Colors.yellow.shade300.withOpacity(0.85)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  }

  @override
  bool shouldRepaint(covariant _SunPainter old) =>
      old.glowRadius != glowRadius || old.opacity != opacity;
}

// ─────────────────────────────────────────────────────────────
// CLEAR NIGHT – stars
// ─────────────────────────────────────────────────────────────
class _NightLayer extends StatelessWidget {
  final AnimationController ctrl;
  final Random rng;
  const _NightLayer({required this.ctrl, required this.rng});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => CustomPaint(
        painter: _StarsPainter(phase: ctrl.value, rng: rng),
      ),
    );
  }
}

class _StarsPainter extends CustomPainter {
  final double phase;
  final Random rng;
  static List<Offset>? _positions;
  static List<double>? _sizes;

  _StarsPainter({required this.phase, required this.rng}) {
    _positions ??= List.generate(
        60, (_) => Offset(rng.nextDouble(), rng.nextDouble()));
    _sizes ??= List.generate(60, (_) => 1.0 + rng.nextDouble() * 2.5);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // dark night gradient
    final grad = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xCC050D1A), Color(0x44020812)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), grad);

    final paint = Paint();
    for (int i = 0; i < _positions!.length; i++) {
      final twinkle = (sin(phase * pi * 2 + i) + 1) / 2;
      paint.color = Colors.white.withOpacity(0.3 + twinkle * 0.65);
      final pos = Offset(
          _positions![i].dx * size.width, _positions![i].dy * size.height * 0.6);
      canvas.drawCircle(pos, _sizes![i], paint);
    }

    // moon
    final mx = size.width * 0.78, my = size.height * 0.12;
    canvas.drawCircle(
        Offset(mx, my),
        22,
        Paint()
          ..color = Colors.yellow.shade100.withOpacity(0.8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    // shadow to make crescent
    canvas.drawCircle(
        Offset(mx + 10, my - 6),
        18,
        Paint()..color = const Color(0xFF060F22).withOpacity(0.85));
  }

  @override
  bool shouldRepaint(covariant _StarsPainter old) => old.phase != phase;
}

// ─────────────────────────────────────────────────────────────
// PARTLY CLOUDY DAY
// ─────────────────────────────────────────────────────────────
class _PartlyCloudyDayLayer extends StatelessWidget {
  final AnimationController sunCtrl;
  final AnimationController windCtrl;
  final Random rng;
  const _PartlyCloudyDayLayer(
      {required this.sunCtrl, required this.windCtrl, required this.rng});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([sunCtrl, windCtrl]),
      builder: (_, __) => CustomPaint(
        painter: _PartlyCloudyDayPainter(
            sunPhase: sunCtrl.value, windPhase: windCtrl.value, rng: rng),
      ),
    );
  }
}

class _PartlyCloudyDayPainter extends CustomPainter {
  final double sunPhase, windPhase;
  final Random rng;
  _PartlyCloudyDayPainter(
      {required this.sunPhase, required this.windPhase, required this.rng});

  @override
  void paint(Canvas canvas, Size size) {
    // faint warm sky tint
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height * 0.5),
        Paint()
          ..color = Colors.lightBlue.withOpacity(0.08));

    // sun (slightly hidden)
    final cx = size.width - 70.0;
    const cy = 70.0;
    final glow = 60 + sunPhase * 30;
    canvas.drawCircle(
        Offset(cx, cy),
        glow,
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.yellow.withOpacity(0.35),
            Colors.transparent
          ]).createShader(Rect.fromCircle(
              center: Offset(cx, cy), radius: glow)));
    canvas.drawCircle(
        Offset(cx, cy),
        22,
        Paint()
          ..color = Colors.yellow.shade200.withOpacity(0.75)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));

    // drifting clouds
    _drawCloud(canvas, size, 0.15 + windPhase * 0.18, 0.18, 90, 0.7);
    _drawCloud(canvas, size, 0.55 + windPhase * 0.12, 0.08, 65, 0.5);
  }

  void _drawCloud(Canvas canvas, Size sz, double xFrac, double yFrac,
      double r, double op) {
    final cx = (xFrac % 1.0) * sz.width;
    final cy = yFrac * sz.height;
    final paint = Paint()
      ..color = Colors.white.withOpacity(op)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    for (final off in [
      Offset(cx, cy),
      Offset(cx - r * 0.6, cy + r * 0.3),
      Offset(cx + r * 0.6, cy + r * 0.3),
      Offset(cx - r * 0.35, cy + r * 0.6),
      Offset(cx + r * 0.35, cy + r * 0.6),
    ]) {
      canvas.drawCircle(off, r * 0.65, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PartlyCloudyDayPainter old) =>
      old.sunPhase != sunPhase || old.windPhase != windPhase;
}

// ─────────────────────────────────────────────────────────────
// PARTLY CLOUDY NIGHT
// ─────────────────────────────────────────────────────────────
class _PartlyCloudyNightLayer extends StatelessWidget {
  final AnimationController windCtrl, starCtrl;
  final Random rng;
  const _PartlyCloudyNightLayer(
      {required this.windCtrl, required this.starCtrl, required this.rng});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([windCtrl, starCtrl]),
      builder: (_, __) => CustomPaint(
        painter: _PartlyCloudyNightPainter(
            windPhase: windCtrl.value, starPhase: starCtrl.value, rng: rng),
      ),
    );
  }
}

class _PartlyCloudyNightPainter extends CustomPainter {
  final double windPhase, starPhase;
  final Random rng;
  static List<Offset>? _starPos;

  _PartlyCloudyNightPainter(
      {required this.windPhase, required this.starPhase, required this.rng}) {
    _starPos ??=
        List.generate(30, (_) => Offset(rng.nextDouble(), rng.nextDouble()));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // night tint
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0x88030A18));

    // stars (fewer)
    final sp = Paint();
    for (int i = 0; i < _starPos!.length; i++) {
      final tw = (sin(starPhase * pi * 2 + i) + 1) / 2;
      sp.color = Colors.white.withOpacity(0.2 + tw * 0.55);
      canvas.drawCircle(
          Offset(_starPos![i].dx * size.width,
              _starPos![i].dy * size.height * 0.55),
          1.2 + rng.nextDouble(),
          sp);
    }

    // moon
    const mx = 0.8, my = 0.1;
    canvas.drawCircle(
        Offset(size.width * mx, size.height * my),
        18,
        Paint()
          ..color = Colors.yellow.shade50.withOpacity(0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawCircle(
        Offset(size.width * mx + 8, size.height * my - 5),
        14,
        Paint()..color = const Color(0xFF030D22).withOpacity(0.82));

    // drifting cloud covering moon partially
    _drawCloud(canvas, size, 0.62 + windPhase * 0.22, 0.07, 70, 0.45);
    _drawCloud(canvas, size, 0.25 + windPhase * 0.15, 0.2, 55, 0.35);
  }

  void _drawCloud(Canvas canvas, Size sz, double xFrac, double yFrac,
      double r, double op) {
    final cx = (xFrac % 1.0) * sz.width;
    final cy = yFrac * sz.height;
    final p = Paint()
      ..color = Colors.blueGrey.shade800.withOpacity(op)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    for (final off in [
      Offset(cx, cy),
      Offset(cx - r * 0.55, cy + r * 0.3),
      Offset(cx + r * 0.55, cy + r * 0.3),
    ]) {
      canvas.drawCircle(off, r * 0.6, p);
    }
  }

  @override
  bool shouldRepaint(covariant _PartlyCloudyNightPainter old) =>
      old.windPhase != windPhase || old.starPhase != starPhase;
}

// ─────────────────────────────────────────────────────────────
// CLOUDY
// ─────────────────────────────────────────────────────────────
class _CloudyLayer extends StatelessWidget {
  final AnimationController ctrl;
  final Random rng;
  const _CloudyLayer({required this.ctrl, required this.rng});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => CustomPaint(
        painter: _CloudyPainter(phase: ctrl.value, rng: rng),
      ),
    );
  }
}

class _CloudyPainter extends CustomPainter {
  final double phase;
  final Random rng;
  _CloudyPainter({required this.phase, required this.rng});

  @override
  void paint(Canvas canvas, Size sz) {
    canvas.drawRect(
        Rect.fromLTWH(0, 0, sz.width, sz.height),
        Paint()..color = const Color(0x33697D8E));

    final data = [
      [0.1 + phase * 0.2, 0.05, 110.0, 0.65],
      [0.4 + phase * 0.15, 0.12, 90.0, 0.5],
      [0.7 + phase * 0.18, 0.06, 100.0, 0.6],
      [0.2 + phase * 0.1, 0.22, 80.0, 0.4],
    ];
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    for (final d in data) {
      final cx = (d[0] % 1.0) * sz.width;
      final cy = (d[1] as double) * sz.height;
      final r = d[2] as double;
      paint.color = Colors.blueGrey.shade300.withOpacity(d[3] as double);
      for (final off in [
        Offset(cx, cy),
        Offset(cx - r * 0.55, cy + r * 0.3),
        Offset(cx + r * 0.55, cy + r * 0.3),
        Offset(cx, cy + r * 0.55),
      ]) {
        canvas.drawCircle(off, r * 0.65, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CloudyPainter old) => old.phase != phase;
}

// ─────────────────────────────────────────────────────────────
// RAIN
// ─────────────────────────────────────────────────────────────
class _RainLayer extends StatelessWidget {
  final AnimationController rainCtrl, windCtrl;
  final Random rng;
  const _RainLayer(
      {required this.rainCtrl, required this.windCtrl, required this.rng});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([rainCtrl, windCtrl]),
      builder: (_, __) => CustomPaint(
        painter: _RainPainter(
            rainPhase: rainCtrl.value, windPhase: windCtrl.value, rng: rng),
      ),
    );
  }
}

class _RainPainter extends CustomPainter {
  final double rainPhase, windPhase;
  final Random rng;
  static List<List<double>>? _drops;

  _RainPainter({required this.rainPhase, required this.windPhase, required this.rng}) {
    _drops ??= List.generate(
        60, (_) => [rng.nextDouble(), rng.nextDouble(), 0.4 + rng.nextDouble() * 0.6]);
  }

  @override
  void paint(Canvas canvas, Size sz) {
    // dark rain overlay
    canvas.drawRect(
        Rect.fromLTWH(0, 0, sz.width, sz.height),
        Paint()..color = const Color(0x44263040));

    // clouds at top
    final cp = Paint()
      ..color = Colors.blueGrey.shade700.withOpacity(0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(Offset(sz.width * 0.2, sz.height * 0.05), 80, cp);
    canvas.drawCircle(Offset(sz.width * 0.6, sz.height * 0.03), 100, cp);
    canvas.drawCircle(Offset(sz.width * 0.9, sz.height * 0.07), 70, cp);

    const angle = 0.18; // slant
    final rp = Paint()
      ..color = Colors.lightBlue.shade200.withOpacity(0.5)
      ..strokeWidth = 1.2;
    for (final d in _drops!) {
      final x = d[0] * sz.width + windPhase * 30;
      final y = ((d[1] + rainPhase) % 1.0) * sz.height;
      final len = 14 * d[2];
      canvas.drawLine(
          Offset(x, y),
          Offset(x + angle * len, y + len),
          rp);
    }
  }

  @override
  bool shouldRepaint(covariant _RainPainter old) =>
      old.rainPhase != rainPhase || old.windPhase != windPhase;
}

// ─────────────────────────────────────────────────────────────
// THUNDERSTORM
// ─────────────────────────────────────────────────────────────
class _ThunderstormLayer extends StatelessWidget {
  final AnimationController rainCtrl, windCtrl, lightningCtrl;
  final Random rng;
  const _ThunderstormLayer(
      {required this.rainCtrl,
      required this.windCtrl,
      required this.lightningCtrl,
      required this.rng});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([rainCtrl, windCtrl, lightningCtrl]),
      builder: (_, __) => CustomPaint(
        painter: _ThunderstormPainter(
          rainPhase: rainCtrl.value,
          windPhase: windCtrl.value,
          lightningPhase: lightningCtrl.value,
          rng: rng,
        ),
      ),
    );
  }
}

class _ThunderstormPainter extends CustomPainter {
  final double rainPhase, windPhase, lightningPhase;
  final Random rng;
  static List<List<double>>? _drops;

  _ThunderstormPainter({
    required this.rainPhase,
    required this.windPhase,
    required this.lightningPhase,
    required this.rng,
  }) {
    _drops ??= List.generate(
        90, (_) => [rng.nextDouble(), rng.nextDouble(), 0.5 + rng.nextDouble()]);
  }

  @override
  void paint(Canvas canvas, Size sz) {
    // dark stormy overlay
    canvas.drawRect(
        Rect.fromLTWH(0, 0, sz.width, sz.height),
        Paint()..color = const Color(0x771A2030));

    // lightning flash
    if (lightningPhase > 0.85) {
      canvas.drawRect(
          Rect.fromLTWH(0, 0, sz.width, sz.height),
          Paint()..color = Colors.yellow.withOpacity((lightningPhase - 0.85) * 3));
      // bolt
      final bx = sz.width * 0.45;
      final bp = Paint()
        ..color = Colors.yellow.withOpacity(0.9)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(bx, 0), Offset(bx - 15, sz.height * 0.25), bp);
      canvas.drawLine(Offset(bx - 15, sz.height * 0.25),
          Offset(bx + 10, sz.height * 0.35), bp);
      canvas.drawLine(
          Offset(bx + 10, sz.height * 0.35), Offset(bx - 5, sz.height * 0.55), bp);
    }

    // heavy rain
    final rp = Paint()
      ..color = Colors.lightBlue.shade100.withOpacity(0.55)
      ..strokeWidth = 1.5;
    for (final d in _drops!) {
      final x = d[0] * sz.width + windPhase * 60;
      final y = ((d[1] + rainPhase) % 1.0) * sz.height;
      final len = 18 * d[2];
      canvas.drawLine(Offset(x, y), Offset(x + 0.3 * len, y + len), rp);
    }
  }

  @override
  bool shouldRepaint(covariant _ThunderstormPainter old) =>
      old.rainPhase != rainPhase ||
      old.windPhase != windPhase ||
      old.lightningPhase != lightningPhase;
}

// ─────────────────────────────────────────────────────────────
// SNOW
// ─────────────────────────────────────────────────────────────
class _SnowLayer extends StatelessWidget {
  final AnimationController ctrl;
  final Random rng;
  const _SnowLayer({required this.ctrl, required this.rng});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => CustomPaint(
        painter: _SnowPainter(phase: ctrl.value, rng: rng),
      ),
    );
  }
}

class _SnowPainter extends CustomPainter {
  final double phase;
  final Random rng;
  static List<List<double>>? _flakes;

  _SnowPainter({required this.phase, required this.rng}) {
    _flakes ??= List.generate(
        50, (_) => [rng.nextDouble(), rng.nextDouble(), 1.5 + rng.nextDouble() * 4]);
  }

  @override
  void paint(Canvas canvas, Size sz) {
    canvas.drawRect(
        Rect.fromLTWH(0, 0, sz.width, sz.height),
        Paint()..color = const Color(0x33B0C4D8));

    final sp = Paint()..color = Colors.white.withOpacity(0.75);
    for (final f in _flakes!) {
      final drift = sin(phase * pi * 2 + f[0] * 10) * 8;
      final x = f[0] * sz.width + drift;
      final y = ((f[1] + phase * 0.4) % 1.0) * sz.height;
      canvas.drawCircle(Offset(x, y), f[2], sp);
    }
  }

  @override
  bool shouldRepaint(covariant _SnowPainter old) => old.phase != phase;
}

// ─────────────────────────────────────────────────────────────
// FOG
// ─────────────────────────────────────────────────────────────
class _FogLayer extends StatelessWidget {
  final AnimationController ctrl;
  const _FogLayer({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) => CustomPaint(
        painter: _FogPainter(phase: ctrl.value),
      ),
    );
  }
}

class _FogPainter extends CustomPainter {
  final double phase;
  _FogPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size sz) {
    final paint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    for (int i = 0; i < 5; i++) {
      final y = (0.1 + i * 0.18 + sin(phase * pi * 2 + i) * 0.04) * sz.height;
      final x = (phase * 0.15 + i * 0.05) * sz.width;
      paint.color = Colors.blueGrey.shade100
          .withOpacity(0.12 + sin(phase * pi + i) * 0.05);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(x + sz.width * 0.5, y),
                  width: sz.width * 1.4,
                  height: 40),
              const Radius.circular(20)),
          paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FogPainter old) => old.phase != phase;
}

// ─────────────────────────────────────────────────────────────

// ═══════════════════════════════════════════════════════════════════
// MINI WEATHER BADGE – shown in top-right corner of map
// ═══════════════════════════════════════════════════════════════════
class WeatherBadge extends StatelessWidget {
  final WeatherData? weather;
  final bool isLoading;
  const WeatherBadge({super.key, required this.weather, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
    }
    if (weather == null) return const SizedBox.shrink();

    final w = weather!;
    final icon = _timeOfDayIcon(w.condition);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.58),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(w.tempLabel,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900)),
          Text(w.description,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
        ]),
        const SizedBox(width: 10),
        Row(children: [
          Icon(Icons.water_drop, color: Colors.lightBlue.shade200, size: 10),
          const SizedBox(width: 2),
          Text(w.humidityLabel,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 9,
                  fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }

  /// Returns a simple time-of-day icon — no wind emoji
  String _timeOfDayIcon(WeatherCondition c) {
    switch (c) {
      case WeatherCondition.clearDay:         return '☀️';
      case WeatherCondition.clearNight:       return '🌙';
      case WeatherCondition.partlyCloudyDay:  return '⛅';
      case WeatherCondition.partlyCloudyNight:return '🌤';
      case WeatherCondition.cloudy:           return '☁️';
      case WeatherCondition.rain:             return '🌧️';
      case WeatherCondition.thunderstorm:     return '⛈️';
      case WeatherCondition.snow:             return '❄️';
      case WeatherCondition.foggy:            return '🌫️';
    }
  }
}
