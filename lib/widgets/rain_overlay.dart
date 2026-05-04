import 'dart:math';
import 'package:flutter/material.dart';
import '../services/weather_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  RAIN OVERLAY  —  visually stunning multi-layer rain animation
//
//  Only shown when condition == rain or thunderstorm.
//
//  Layers (back → front):
//    1. Dark atmospheric sky vignette
//    2. Mist / fog layer (slow drifting translucent bands)
//    3. Background rain  — 140 thin, fast, pale streaks (distant)
//    4. Mid rain         —  70 medium streaks + oval splash rings
//    5. Foreground rain  —  28 thick, slow, bright streaks + big splashes
//    6. Puddle ripples   —  12 expanding concentric rings on "ground"
//    7. Lightning flash  —  full-screen white pulse (thunderstorm only)
//
//  Wind angle from WeatherData leans all streaks realistically.
//  Rain intensity scales opacity & density from rainMmLastHour.
// ═══════════════════════════════════════════════════════════════════════════

class RainOverlay extends StatefulWidget {
  final WeatherData? weather;
  const RainOverlay({super.key, required this.weather});

  @override
  State<RainOverlay> createState() => _RainOverlayState();
}

class _RainOverlayState extends State<RainOverlay>
    with TickerProviderStateMixin {
  // Main animation controllers
  late AnimationController _rainCtrl;   // rain streaks (fast)
  late AnimationController _mistCtrl;   // mist drift  (slow)
  late AnimationController _rippleCtrl; // puddle ripples (medium)
  late AnimationController _flashCtrl;  // lightning flash

  late Animation<double> _flash;

  final _rng = Random(42);

  late List<_Drop>   _bgDrops;
  late List<_Drop>   _midDrops;
  late List<_Drop>   _fgDrops;
  late List<_Ripple> _ripples;
  late List<_MistBand> _mist;

  bool get _isRaining {
    final c = widget.weather?.condition;
    return c == WeatherCondition.rain || c == WeatherCondition.thunderstorm;
  }

  bool get _isThunder =>
      widget.weather?.condition == WeatherCondition.thunderstorm;

  double get _intensity {
    final mm = widget.weather?.rainMmLastHour ?? 0;
    if (mm > 10) return 1.0;
    if (mm > 3)  return 0.75;
    if (mm > 0)  return 0.50;
    return _isRaining ? 0.65 : 0.0;
  }

  // Wind lean: -1 (right) to +1 (left), derived from wind direction
  double get _lean {
    final deg = widget.weather?.windDeg ?? 270;
    return sin((deg - 90) * pi / 180) * 0.22;
  }

  // ── Init ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _rainCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat();

    _mistCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 12))
      ..repeat();

    _rippleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();

    _flashCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 140));
    _flash = Tween<double>(begin: 0.0, end: 0.22)
        .animate(CurvedAnimation(parent: _flashCtrl, curve: Curves.easeIn));

    _buildParticles();
    if (_isThunder) _scheduleFlash();
  }

  void _buildParticles() {
    // Streaks
    _bgDrops  = _makeDrops(140, size: 0.7,  speed: 1.00, phaseOff: 0.00);
    _midDrops = _makeDrops(70,  size: 1.35, speed: 0.78, phaseOff: 0.33);
    _fgDrops  = _makeDrops(28,  size: 2.10, speed: 0.55, phaseOff: 0.66);
    // Puddle ripples — spread across bottom 35% of screen
    _ripples = List.generate(12, (i) => _Ripple(
      x:     _rng.nextDouble(),
      yFrac: 0.68 + _rng.nextDouble() * 0.28,  // bottom 28–96%
      phase: _rng.nextDouble(),
      maxR:  14 + _rng.nextDouble() * 22,
      speed: 0.5 + _rng.nextDouble() * 0.5,
    ));
    // Mist bands — slow horizontal drifters
    _mist = List.generate(5, (i) => _MistBand(
      yFrac:   0.1 + i * 0.16 + _rng.nextDouble() * 0.08,
      phase:   _rng.nextDouble(),
      opacity: 0.04 + _rng.nextDouble() * 0.06,
      height:  40 + _rng.nextDouble() * 60,
    ));
  }

  List<_Drop> _makeDrops(int n,
      {required double size, required double speed, required double phaseOff}) =>
      List.generate(n, (i) => _Drop(
        x:       _rng.nextDouble(),
        phase:   (_rng.nextDouble() + phaseOff) % 1.0,
        length:  (9 + _rng.nextDouble() * 20) * size,
        width:   size * (0.7 + _rng.nextDouble() * 0.5),
        speed:   speed * (0.65 + _rng.nextDouble() * 0.7),
        opacity: 0.38 + _rng.nextDouble() * 0.42,
      ));

  void _scheduleFlash() {
    final delay = Duration(milliseconds: 2500 + _rng.nextInt(5000));
    Future.delayed(delay, () {
      if (!mounted) return;
      _flashCtrl.forward().then((_) {
        _flashCtrl.reverse().then((_) {
          // Double flash (realistic lightning)
          Future.delayed(const Duration(milliseconds: 80), () {
            if (!mounted) return;
            _flashCtrl.forward().then((_) {
              _flashCtrl.reverse().then((_) {
                if (mounted && _isThunder) _scheduleFlash();
              });
            });
          });
        });
      });
    });
  }

  @override
  void didUpdateWidget(RainOverlay old) {
    super.didUpdateWidget(old);
    if (_isThunder &&
        old.weather?.condition != WeatherCondition.thunderstorm) {
      _scheduleFlash();
    }
  }

  @override
  void dispose() {
    _rainCtrl.dispose();
    _mistCtrl.dispose();
    _rippleCtrl.dispose();
    _flashCtrl.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_isRaining) return const SizedBox.shrink();

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge(
            [_rainCtrl, _mistCtrl, _rippleCtrl, _flash]),
        builder: (_, __) {
          final intensity = _intensity;
          final lean      = _lean;

          return Stack(children: [
            // ── 1. Atmospheric dark vignette ──────────────────────────
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.0, -0.3),
                    radius: 1.2,
                    colors: [
                      Colors.transparent,
                      const Color(0xFF0D1B2A)
                          .withOpacity(0.30 * intensity),
                    ],
                  ),
                ),
              ),
            ),

            // ── 2. Mist / fog bands ───────────────────────────────────
            Positioned.fill(
              child: CustomPaint(
                painter: _MistPainter(
                  bands:    _mist,
                  progress: _mistCtrl.value,
                  intensity: intensity,
                ),
              ),
            ),

            // ── 3–5. Rain streaks (all layers) ────────────────────────
            Positioned.fill(
              child: CustomPaint(
                painter: _RainPainter(
                  bgDrops:  _bgDrops,
                  midDrops: _midDrops,
                  fgDrops:  _fgDrops,
                  progress: _rainCtrl.value,
                  intensity: intensity,
                  lean:      lean,
                  isThunder: _isThunder,
                ),
              ),
            ),

            // ── 6. Puddle ripples ─────────────────────────────────────
            Positioned.fill(
              child: CustomPaint(
                painter: _RipplePainter(
                  ripples:  _ripples,
                  progress: _rippleCtrl.value,
                  intensity: intensity,
                ),
              ),
            ),

            // ── 7. Sky colour tint ────────────────────────────────────
            Positioned.fill(
              child: Container(
                color: const Color(0xFF1A2B3C)
                    .withOpacity(0.14 * intensity),
              ),
            ),

            // ── 8. Lightning flash ────────────────────────────────────
            if (_isThunder)
              Positioned.fill(
                child: Container(
                  color: const Color(0xFFF0F8FF)
                      .withOpacity(_flash.value),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

// ── Drop data ─────────────────────────────────────────────────────────────

class _Drop {
  final double x, phase, length, width, speed, opacity;
  const _Drop({
    required this.x, required this.phase, required this.length,
    required this.width, required this.speed, required this.opacity,
  });
}

// ── Ripple data ───────────────────────────────────────────────────────────

class _Ripple {
  final double x, yFrac, phase, maxR, speed;
  const _Ripple({
    required this.x, required this.yFrac, required this.phase,
    required this.maxR, required this.speed,
  });
}

// ── Mist band data ────────────────────────────────────────────────────────

class _MistBand {
  final double yFrac, phase, opacity, height;
  const _MistBand({
    required this.yFrac, required this.phase,
    required this.opacity, required this.height,
  });
}

// ── Rain painter ──────────────────────────────────────────────────────────

class _RainPainter extends CustomPainter {
  final List<_Drop> bgDrops, midDrops, fgDrops;
  final double progress, intensity, lean;
  final bool isThunder;

  const _RainPainter({
    required this.bgDrops, required this.midDrops, required this.fgDrops,
    required this.progress, required this.intensity,
    required this.lean, required this.isThunder,
  });

  void _drawLayer(Canvas canvas, Size size, List<_Drop> drops,
      Color color, double lenMult) {
    for (final d in drops) {
      final t = (progress * d.speed + d.phase) % 1.0;
      final y = t * (size.height + d.length * 2) - d.length;
      final x = d.x * size.width + lean * size.width * t;
      final len = d.length * lenMult;
      final dx = lean * len * 0.35;

      final paint = Paint()
        ..color = color.withOpacity(d.opacity * intensity)
        ..strokeWidth = d.width
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(x, y), Offset(x - dx, y + len), paint);

      // Splash ring when near ground
      final groundY = y + len;
      if (groundY > size.height * 0.88 && groundY < size.height + 10) {
        final splashT = (groundY - size.height * 0.88) /
            (size.height * 0.12 + 10);
        final splashR = d.width * 4 * splashT;
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(x - dx, size.height - 3),
              width: splashR * 2.5,
              height: splashR * 0.6),
          Paint()
            ..color =
                color.withOpacity(d.opacity * intensity * (1 - splashT) * 0.45)
            ..strokeWidth = d.width * 0.55
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Background — thin, pale, blue-grey streaks
    _drawLayer(canvas, size, bgDrops, const Color(0xFF9BB8D4), 0.80);
    // Mid — brighter, slightly blue-white
    _drawLayer(canvas, size, midDrops, const Color(0xFFBED4EC), 1.00);
    // Foreground — thick, bright, close — most visible
    _drawLayer(canvas, size, fgDrops, const Color(0xFFDEEEFF), 1.25);
  }

  @override
  bool shouldRepaint(_RainPainter old) =>
      old.progress != progress || old.intensity != intensity;
}

// ── Ripple painter ────────────────────────────────────────────────────────

class _RipplePainter extends CustomPainter {
  final List<_Ripple> ripples;
  final double progress, intensity;

  const _RipplePainter({
    required this.ripples, required this.progress, required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final r in ripples) {
      final t = (progress * r.speed + r.phase) % 1.0;
      final cx = r.x * size.width;
      final cy = r.yFrac * size.height;
      // 2 concentric rings per ripple — inner and outer
      for (var ring = 0; ring < 2; ring++) {
        final rt = ((t + ring * 0.35) % 1.0);
        final radius = rt * r.maxR;
        final opacity = (1 - rt) * 0.28 * intensity;
        if (opacity <= 0) continue;
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(cx, cy),
              width: radius * 2.8,
              height: radius * 0.85),
          Paint()
            ..color = const Color(0xFFADD8FF).withOpacity(opacity)
            ..strokeWidth = (1.2 - rt * 0.8).clamp(0.3, 1.2)
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.progress != progress;
}

// ── Mist painter ──────────────────────────────────────────────────────────

class _MistPainter extends CustomPainter {
  final List<_MistBand> bands;
  final double progress, intensity;

  const _MistPainter({
    required this.bands, required this.progress, required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bands) {
      // Slow horizontal drift
      final drift = (progress + b.phase) % 1.0;
      final dx = drift * size.width * 0.25 - size.width * 0.12;
      final cy = b.yFrac * size.height;

      final rect = Rect.fromCenter(
          center: Offset(size.width / 2 + dx, cy),
          width: size.width * 1.4,
          height: b.height);

      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent,
              const Color(0xFFCDE8FF)
                  .withOpacity(b.opacity * intensity),
              const Color(0xFFCDE8FF)
                  .withOpacity(b.opacity * intensity * 1.3),
              const Color(0xFFCDE8FF)
                  .withOpacity(b.opacity * intensity),
              Colors.transparent,
            ],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_MistPainter old) => old.progress != progress;
}
