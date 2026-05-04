import 'dart:math' show Random, sin, cos, pi, sqrt, max;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/weather_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  LIVE ENVIRONMENT OVERLAY  v4 — Premium Immersive Weather Engine
// ═══════════════════════════════════════════════════════════════════════════

class LiveEnvironmentOverlay extends StatefulWidget {
  final WeatherData? weather;
  final bool isLoading;
  const LiveEnvironmentOverlay({super.key, required this.weather, this.isLoading = false});
  @override
  State<LiveEnvironmentOverlay> createState() => _LiveEnvironmentOverlayState();
}

class _LiveEnvironmentOverlayState extends State<LiveEnvironmentOverlay>
    with TickerProviderStateMixin {

  late AnimationController _sceneClock;  // 24s — clouds / rain / haze
  late AnimationController _windClock;   // 8s  — wind streaks (dedicated fast loop)
  late AnimationController _sunDrift;    // 18s slow position drift
  late AnimationController _sunPulse;    // 4s breathing
  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  WeatherData? _currentWeather;
  final _rng = Random(42);

  // Wind streak definitions — instance-level so each layer has its own positions
  late final List<_StreakDef> _bgStreaks;
  late final List<_StreakDef> _midStreaks;
  late final List<_StreakDef> _fgStreaks;

  late final List<_CloudDef> _bgClouds;
  late final List<_CloudDef> _midClouds;
  late final List<_CloudDef> _fgClouds;

  @override
  void initState() {
    super.initState();
    _sceneClock = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();
    _windClock  = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _sunDrift   = AnimationController(vsync: this, duration: const Duration(seconds: 18)); // static — not started
    _sunPulse   = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    _fadeCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _fadeAnim   = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);

    // Build instance-level streak defs — unique positions per layer
    final rngBg  = Random(101);
    final rngMid = Random(202);
    final rngFg  = Random(303);
    _bgStreaks  = List.generate(22, (_) => _StreakDef.generate(rngBg,  lengthMin: 0.18, lengthMax: 0.32, opMin: 0.040, opMax: 0.090, wMin: 0.5, wMax: 1.1));
    _midStreaks = List.generate(16, (_) => _StreakDef.generate(rngMid, lengthMin: 0.09, lengthMax: 0.18, opMin: 0.060, opMax: 0.130, wMin: 0.6, wMax: 1.2));
    _fgStreaks  = List.generate(11, (_) => _StreakDef.generate(rngFg,  lengthMin: 0.04, lengthMax: 0.09, opMin: 0.070, opMax: 0.150, wMin: 0.5, wMax: 0.9));

    _bgClouds  = _buildBgClouds();
    _midClouds = _buildMidClouds();
    _fgClouds  = _buildFgClouds();

    _currentWeather = widget.weather;
    if (_currentWeather != null) _fadeCtrl.value = 1.0;
  }

  List<_CloudDef> _buildBgClouds() => [
    _CloudDef(startFrac:  0.05, yFrac: 0.03, widthFrac: 0.65, heightFrac: 0.10, opacity: 0.38, speedFrac: 0.010, puffs: 8),
    _CloudDef(startFrac:  0.45, yFrac: 0.08, widthFrac: 0.55, heightFrac: 0.08, opacity: 0.32, speedFrac: 0.008, puffs: 7),
    _CloudDef(startFrac:  0.78, yFrac: 0.02, widthFrac: 0.48, heightFrac: 0.09, opacity: 0.35, speedFrac: 0.011, puffs: 7),
    _CloudDef(startFrac: -0.25, yFrac: 0.13, widthFrac: 0.42, heightFrac: 0.07, opacity: 0.28, speedFrac: 0.007, puffs: 6),
    _CloudDef(startFrac:  0.60, yFrac: 0.17, widthFrac: 0.40, heightFrac: 0.07, opacity: 0.26, speedFrac: 0.009, puffs: 6),
  ];

  List<_CloudDef> _buildMidClouds() => [
    _CloudDef(startFrac:  0.20, yFrac: 0.19, widthFrac: 0.46, heightFrac: 0.09, opacity: 0.60, speedFrac: 0.016, puffs: 7),
    _CloudDef(startFrac:  0.68, yFrac: 0.24, widthFrac: 0.38, heightFrac: 0.08, opacity: 0.55, speedFrac: 0.014, puffs: 6),
    _CloudDef(startFrac: -0.08, yFrac: 0.28, widthFrac: 0.34, heightFrac: 0.07, opacity: 0.50, speedFrac: 0.017, puffs: 5),
  ];

  List<_CloudDef> _buildFgClouds() => [
    _CloudDef(startFrac:  0.12, yFrac: 0.22, widthFrac: 0.40, heightFrac: 0.09, opacity: 0.80, speedFrac: 0.026, puffs: 6),
    _CloudDef(startFrac:  0.65, yFrac: 0.29, widthFrac: 0.32, heightFrac: 0.07, opacity: 0.72, speedFrac: 0.022, puffs: 5),
    _CloudDef(startFrac: -0.15, yFrac: 0.33, widthFrac: 0.28, heightFrac: 0.07, opacity: 0.68, speedFrac: 0.024, puffs: 5),
    _CloudDef(startFrac:  0.85, yFrac: 0.25, widthFrac: 0.26, heightFrac: 0.06, opacity: 0.65, speedFrac: 0.028, puffs: 4),
  ];

  @override
  void didUpdateWidget(LiveEnvironmentOverlay old) {
    super.didUpdateWidget(old);
    if (old.weather?.condition != widget.weather?.condition ||
        (widget.weather != null && _currentWeather == null)) {
      _currentWeather = widget.weather;
      _fadeCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _sceneClock.dispose(); _windClock.dispose(); _sunDrift.dispose(); _sunPulse.dispose(); _fadeCtrl.dispose();
    super.dispose();
  }

  int    get _hour    => TimeOfDay.now().hour;
  bool   get _isNight => _hour >= 19 || _hour < 6;
  bool   get _isDawn  => _hour >= 5  && _hour < 8;
  bool   get _isDusk  => _hour >= 17 && _hour < 19;

  WeatherCondition? get _cond => _currentWeather?.condition;

  bool get _showSun =>
      !_isNight && (_cond == WeatherCondition.clearDay || _cond == WeatherCondition.partlyCloudyDay || _cond == null);
  bool get _showClouds =>
      _cond == WeatherCondition.cloudy || _cond == WeatherCondition.partlyCloudyDay ||
      _cond == WeatherCondition.partlyCloudyNight || _cond == WeatherCondition.rain ||
      _cond == WeatherCondition.thunderstorm;
  bool get _showRain  => _cond == WeatherCondition.rain || _cond == WeatherCondition.thunderstorm;
  bool get _showWind  => (_currentWeather?.windSpeedMs ?? 0) > 2.0;
  bool get _showStars =>
      _isNight && (_cond == WeatherCondition.clearNight || _cond == WeatherCondition.partlyCloudyNight || _cond == null);
  bool get _showHaze  =>
      _cond == WeatherCondition.foggy || _cond == WeatherCondition.rain || _cond == WeatherCondition.thunderstorm;

  double _cloudOpacity(double base) {
    switch (_cond) {
      case WeatherCondition.cloudy:       return base * 1.0;
      case WeatherCondition.thunderstorm: return base * 1.25;
      case WeatherCondition.rain:         return base * 1.15;
      case WeatherCondition.partlyCloudyDay:
      case WeatherCondition.partlyCloudyNight: return base * 0.80;
      default: return base * 0.35;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([_sceneClock, _windClock, _sunPulse, _fadeCtrl]),
        builder: (ctx, _) {
          final scene = _sceneClock.value;
          final wind  = _windClock.value;
          final drift = 0.0; // fixed position — no drift
          final pulse = _sunPulse.value;
          final fade  = _fadeAnim.value;
          final windDeg = _currentWeather?.windDeg ?? 270.0;
          final windSpd = _currentWeather?.windSpeedMs ?? 3.0;

          return SizedBox.expand(child: Stack(children: [

            // 0. Sky tint
            _SkyTintLayer(isNight: _isNight, isDawn: _isDawn, isDusk: _isDusk, condition: _cond, fade: fade),

            // 1. Sun
            if (_showSun)
              Opacity(opacity: fade.clamp(0.0, 1.0),
                child: CustomPaint(painter: _SunPainter(pulse: pulse, drift: drift), size: Size.infinite)),

            // 2. Background clouds
            if (_showClouds || _showSun)
              Opacity(opacity: _cloudOpacity(fade).clamp(0.0, 1.0),
                child: CustomPaint(
                  painter: _CloudLayerPainter(clouds: _bgClouds, scene: scene, dark: _showRain,
                    baseBlur: 22, windSpeedMul: (windSpd / 6.0).clamp(0.5, 2.0)),
                  size: Size.infinite)),

            // 3. Mid clouds
            if (_showClouds || _showSun)
              Opacity(opacity: _cloudOpacity(fade * 0.85).clamp(0.0, 1.0),
                child: CustomPaint(
                  painter: _CloudLayerPainter(clouds: _midClouds, scene: scene, dark: _showRain,
                    baseBlur: 13, windSpeedMul: (windSpd / 5.0).clamp(0.5, 2.2)),
                  size: Size.infinite)),

            // 4. Foreground clouds
            if (_showClouds || _showSun)
              Opacity(opacity: _cloudOpacity(fade * 0.70).clamp(0.0, 1.0),
                child: CustomPaint(
                  painter: _CloudLayerPainter(clouds: _fgClouds, scene: scene, dark: _showRain,
                    baseBlur: 7, windSpeedMul: (windSpd / 4.5).clamp(0.5, 2.5)),
                  size: Size.infinite)),

            // 5. Wind streaks — 3-layer parallax (bg/mid/fg)
            //    'wind' is from _windClock (8s loop) → much faster than scene (24s)
            //    speedMul: bg=0.30×, mid=0.60×, fg=1.00× for depth parallax
            if (_showWind && !_showRain) ...[
              Opacity(opacity: (fade * 0.85).clamp(0.0, 1.0),
                child: CustomPaint(
                  painter: _WindStreakLayer(
                    defs: _bgStreaks, wind: wind, windDeg: windDeg,
                    windSpeed: windSpd, speedMul: 0.30),
                  size: Size.infinite)),
              Opacity(opacity: (fade * 0.90).clamp(0.0, 1.0),
                child: CustomPaint(
                  painter: _WindStreakLayer(
                    defs: _midStreaks, wind: wind, windDeg: windDeg,
                    windSpeed: windSpd, speedMul: 0.60),
                  size: Size.infinite)),
              Opacity(opacity: (fade * 0.95).clamp(0.0, 1.0),
                child: CustomPaint(
                  painter: _WindStreakLayer(
                    defs: _fgStreaks, wind: wind, windDeg: windDeg,
                    windSpeed: windSpd, speedMul: 1.00),
                  size: Size.infinite)),
            ],

            // 6. Rain: bg blurred + fg sharp
            if (_showRain) ...[
              Opacity(opacity: (fade * 0.45).clamp(0.0, 1.0),
                child: CustomPaint(
                  painter: _RainPainter(scene: scene, heavy: _cond == WeatherCondition.thunderstorm,
                    windDeg: windDeg, rng: _rng, bgLayer: true),
                  size: Size.infinite)),
              Opacity(opacity: fade.clamp(0.0, 1.0),
                child: CustomPaint(
                  painter: _RainPainter(scene: scene, heavy: _cond == WeatherCondition.thunderstorm,
                    windDeg: windDeg, rng: _rng, bgLayer: false),
                  size: Size.infinite)),
            ],

            // 7. Haze
            if (_showHaze)
              Opacity(opacity: (fade * 0.42).clamp(0.0, 1.0),
                child: CustomPaint(painter: _HazePainter(scene: scene), size: Size.infinite)),

            // 8. Stars
            if (_showStars)
              Opacity(opacity: fade,
                child: CustomPaint(painter: _StarsPainter(scene: scene, rng: _rng), size: Size.infinite)),

            // 9. Lightning
            if (_cond == WeatherCondition.thunderstorm)
              const _LightningFlash(),

            // 10. Context banner
            Positioned(top: 0, left: 0, right: 0,
              child: _ContextBanner(weather: _currentWeather, condition: _cond, fade: fade)),

          ]));
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  LAYER 0 — SKY TINT
// ═══════════════════════════════════════════════════════════════════════════

class _SkyTintLayer extends StatelessWidget {
  final bool isNight, isDawn, isDusk;
  final WeatherCondition? condition;
  final double fade;
  const _SkyTintLayer({required this.isNight, required this.isDawn, required this.isDusk,
    required this.condition, required this.fade});

  @override
  Widget build(BuildContext context) {
    if (isNight) {
      return Opacity(opacity: fade * 0.52, child: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF01091A), Color(0xFF061325), Colors.transparent],
          stops: [0.0, 0.45, 1.0]))));
    }
    if (isDawn) {
      return Opacity(opacity: fade * 0.38, child: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomCenter,
          colors: [Color(0xFFFFB347), Color(0xFFFF7043), Colors.transparent],
          stops: [0.0, 0.4, 1.0]))));
    }
    if (isDusk) {
      return Opacity(opacity: fade * 0.40, child: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topRight, end: Alignment.bottomCenter,
          colors: [Color(0xFFFF5722), Color(0xFFFF9800), Colors.transparent],
          stops: [0.0, 0.4, 1.0]))));
    }
    switch (condition) {
      case WeatherCondition.clearDay:
      case WeatherCondition.partlyCloudyDay:
        return Opacity(opacity: fade * 0.18, child: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF5BA4CF), Color(0xFF87CEEB), Colors.transparent],
            stops: [0.0, 0.28, 1.0]))));
      case WeatherCondition.cloudy:
        return Opacity(opacity: fade * 0.26, child: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF607D8B), Color(0xFF78909C), Colors.transparent],
            stops: [0.0, 0.5, 1.0]))));
      case WeatherCondition.rain:
        return Opacity(opacity: fade * 0.38, child: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF102030), Color(0xFF1A3040), Colors.transparent],
            stops: [0.0, 0.55, 1.0]))));
      case WeatherCondition.thunderstorm:
        return Opacity(opacity: fade * 0.55, child: Container(color: const Color(0xFF0A1820)));
      case WeatherCondition.foggy:
        return Opacity(opacity: fade * 0.22, child: Container(color: const Color(0xFFB0BEC5)));
      default:
        return Opacity(opacity: fade * 0.14, child: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF87CEEB), Colors.transparent]))));
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  LAYER 1 — SUN PAINTER  (disc + rays + glow, slow drift, breathing pulse)
// ═══════════════════════════════════════════════════════════════════════════

class _SunPainter extends CustomPainter {
  final double pulse;
  final double drift;
  const _SunPainter({required this.pulse, required this.drift});

  @override
  void paint(Canvas canvas, Size size) {
    final driftX = sin(drift * pi * 2) * 0.018;
    final driftY = sin(drift * pi * 2 * 0.7) * 0.012;
    final cx = (0.82 + driftX) * size.width;
    final cy = (0.18 + driftY) * size.height;

    // Outer atmospheric glow
    final outerR = size.width * (0.30 + pulse * 0.04);
    canvas.drawCircle(Offset(cx, cy), outerR, Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFFFFEB80).withOpacity(0.20 + pulse * 0.06),
        const Color(0xFFFFB300).withOpacity(0.09 + pulse * 0.03),
        const Color(0xFFFF8F00).withOpacity(0.02),
        Colors.transparent,
      ], stops: const [0.0, 0.30, 0.65, 1.0])
        .createShader(Rect.fromCircle(center: Offset(cx, cy), radius: outerR)));

    // Corona
    final midR = size.width * (0.13 + pulse * 0.018);
    canvas.drawCircle(Offset(cx, cy), midR, Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFFFFF176).withOpacity(0.55 + pulse * 0.12),
        const Color(0xFFFFCA28).withOpacity(0.22 + pulse * 0.06),
        Colors.transparent,
      ], stops: const [0.0, 0.50, 1.0])
        .createShader(Rect.fromCircle(center: Offset(cx, cy), radius: midR)));

    // Rays — 16 alternating sizes
    final rayInner = size.width * 0.052;
    final rayOuter = size.width * (0.090 + pulse * 0.016);
    final rayPaint = Paint()
      ..color = const Color(0xFFFFF59D).withOpacity(0.42 + pulse * 0.16)
      ..strokeWidth = 1.6..strokeCap = StrokeCap.round;
    for (int i = 0; i < 16; i++) {
      final angle = (i / 16) * pi * 2;
      final len = i % 4 == 0 ? rayOuter : i.isEven ? rayOuter * 0.80 : rayOuter * 0.60;
      canvas.drawLine(
        Offset(cx + cos(angle) * rayInner, cy + sin(angle) * rayInner),
        Offset(cx + cos(angle) * len,      cy + sin(angle) * len), rayPaint);
    }

    // Disc soft edge
    final discR = size.width * 0.042;
    canvas.drawCircle(Offset(cx, cy), discR + 4, Paint()
      ..color = const Color(0xFFFFF8E1).withOpacity(0.58)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    // Disc core with radial gradient
    canvas.drawCircle(Offset(cx, cy), discR, Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withOpacity(0.95),
        const Color(0xFFFFF9C4).withOpacity(0.90),
        const Color(0xFFFFE082).withOpacity(0.85),
      ], stops: const [0.0, 0.5, 1.0])
        .createShader(Rect.fromCircle(center: Offset(cx, cy), radius: discR)));
    // Highlight
    canvas.drawCircle(Offset(cx - discR * 0.28, cy - discR * 0.28), discR * 0.40, Paint()
      ..color = Colors.white.withOpacity(0.72)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  }

  @override
  bool shouldRepaint(_SunPainter old) => old.pulse != pulse || old.drift != drift;
}

// ═══════════════════════════════════════════════════════════════════════════
//  CLOUD DEFINITION
// ═══════════════════════════════════════════════════════════════════════════

class _CloudDef {
  final double startFrac, yFrac, widthFrac, heightFrac, opacity, speedFrac;
  final int puffs;
  const _CloudDef({required this.startFrac, required this.yFrac,
    required this.widthFrac, required this.heightFrac,
    required this.opacity, required this.speedFrac, required this.puffs});
}

// ═══════════════════════════════════════════════════════════════════════════
//  LAYERS 2-4 — CLOUD LAYER PAINTER
//  Structured fluffy cumulus: distinct puffs with sharp inner + soft outer.
//  baseBlur controls crispness: low = crisper foreground; high = soft bg.
// ═══════════════════════════════════════════════════════════════════════════

class _CloudLayerPainter extends CustomPainter {
  final List<_CloudDef> clouds;
  final double scene, baseBlur, windSpeedMul;
  final bool dark;

  const _CloudLayerPainter({required this.clouds, required this.scene,
    required this.dark, required this.baseBlur, required this.windSpeedMul});

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in clouds) {
      double rawX = c.startFrac + scene * c.speedFrac * 24 * windSpeedMul;
      rawX = ((rawX + 0.6) % 2.1) - 0.6;
      _drawCloud(canvas, rawX * size.width, c.yFrac * size.height,
          c.widthFrac * size.width, c.heightFrac * size.height, c.opacity, c.puffs);
    }
  }

  void _drawCloud(Canvas canvas, double cx, double cy,
      double w, double h, double opacity, int puffs) {
    final bodyColor    = dark ? const Color(0xFF6E7E8E) : const Color(0xFFE4EEF7);
    final shadowColor  = dark ? const Color(0xFF2E3E4E) : const Color(0xFFA8BED4);
    final hlColor      = dark ? const Color(0xFF90A4AE) : Colors.white;

    // Underbelly shadow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + h * 0.52), width: w * 0.82, height: h * 0.32),
      Paint()
        ..color = shadowColor.withOpacity(opacity * 0.50)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, baseBlur * 0.85));

    // Puff circles
    for (int i = 0; i < puffs; i++) {
      final t = puffs == 1 ? 0.5 : i / (puffs - 1);
      final curvature = 1 - (2 * t - 1) * (2 * t - 1);
      final px = (cx - w * 0.48) + t * w * 0.96;
      final r  = h * (0.35 + 0.28 * curvature);
      final py = cy - h * 0.06 * curvature;
      final puffOp = opacity * (0.70 + 0.30 * curvature);

      // Soft outer bloom
      canvas.drawCircle(Offset(px, py), r + baseBlur * 0.4, Paint()
        ..color = bodyColor.withOpacity(puffOp * 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, baseBlur * 1.1));
      // Crisp core
      canvas.drawCircle(Offset(px, py), r, Paint()
        ..color = bodyColor.withOpacity(puffOp)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, baseBlur * 0.32));
    }

    // Sunlit top highlight
    if (!dark) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx - w * 0.04, cy - h * 0.18), width: w * 0.50, height: h * 0.42),
        Paint()
          ..color = hlColor.withOpacity(opacity * 0.45)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, baseBlur * 0.55));
    }
  }

  @override
  bool shouldRepaint(_CloudLayerPainter old) =>
      old.scene != scene || old.dark != dark || old.windSpeedMul != windSpeedMul;
}

// ═══════════════════════════════════════════════════════════════════════════
//  LAYER 5 — WIND STREAK SYSTEM  (3-layer parallax, proper animation)
//
//  Architecture:
//   • _StreakDef   — immutable per-streak properties, built ONCE at initState
//                    with a factory constructor.  No more static fields.
//   • _WindStreakLayer — single unified CustomPainter used for all 3 layers.
//                    speedMul (0.30 / 0.60 / 1.00) controls parallax depth.
//
//  Animation driver:
//   • Uses _windClock (8-second loop) — NOT _sceneClock (24s).
//     This means streaks visibly move at 60 fps instead of crawling.
//
//  Each streak:
//   • Spawns from the upwind edge, travels in true wind bearing direction.
//   • Has a gentle quadratic Bézier curve (natural micro-bend).
//   • Fades in over first 25% of life, fades out over last 25% — no pop.
//   • Gradient shader: transparent → opaque → transparent along the stroke.
//   • Opacity + count scale with wind speed (2 m/s threshold to show).
// ═══════════════════════════════════════════════════════════════════════════

// Immutable streak descriptor — one instance per streak, built at initState.
class _StreakDef {
  final double xFrac;       // normalised spawn X [0..1]
  final double yFrac;       // normalised spawn Y [0..1]
  final double lengthFrac;  // streak length as fraction of screen width
  final double phase;       // per-streak phase offset [0..1]  (spreads timing)
  final double curvature;   // perpendicular bend [-0.04 .. 0.04]
  final double strokeWidth;
  final double baseOpacity; // peak opacity when fully visible

  const _StreakDef({
    required this.xFrac, required this.yFrac, required this.lengthFrac,
    required this.phase,  required this.curvature,
    required this.strokeWidth, required this.baseOpacity,
  });

  /// Factory: generates a random streak within the supplied bounds.
  factory _StreakDef.generate(
    Random rng, {
    required double lengthMin, required double lengthMax,
    required double opMin,     required double opMax,
    required double wMin,      required double wMax,
  }) {
    return _StreakDef(
      xFrac:        rng.nextDouble(),
      yFrac:        0.02 + rng.nextDouble() * 0.88,
      lengthFrac:   lengthMin + rng.nextDouble() * (lengthMax - lengthMin),
      phase:        rng.nextDouble(),
      curvature:    (rng.nextDouble() - 0.5) * 0.08,
      strokeWidth:  wMin + rng.nextDouble() * (wMax - wMin),
      baseOpacity:  opMin + rng.nextDouble() * (opMax - opMin),
    );
  }
}

// Single unified painter — handles bg, mid, and fg via speedMul.
class _WindStreakLayer extends CustomPainter {
  final List<_StreakDef> defs;
  final double wind;       // _windClock.value  [0..1], 8-second loop
  final double windDeg;    // meteorological FROM-direction
  final double windSpeed;  // m/s from weather API
  final double speedMul;   // parallax: 0.30=bg, 0.60=mid, 1.00=fg

  const _WindStreakLayer({
    required this.defs, required this.wind, required this.windDeg,
    required this.windSpeed, required this.speedMul,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (windSpeed < 2.0) return;

    // How fast streaks advance: ramps from 0 at 2 m/s → full at 12 m/s.
    final speedNorm = ((windSpeed - 2.0) / 10.0).clamp(0.0, 1.0);

    // Meteorological convention: wind blows FROM windDeg.
    // Streaks travel in the OPPOSITE direction (toward windDeg + 180).
    final travelRad = (windDeg + 180.0) * pi / 180.0 - pi / 2.0;
    final dx = cos(travelRad);  // X component of travel unit vector
    final dy = sin(travelRad);  // Y component

    // 'advance' is how far through their cycle the streaks currently are.
    // wind (0→1 over 8s) × speedNorm × speedMul drives the motion.
    final advance = wind * speedNorm * speedMul;

    for (final s in defs) {
      // Each streak has its own phase offset so they don't all move together.
      final t = (s.phase + advance) % 1.0;

      // Smooth fade-in (0→1 over first 25%) and fade-out (1→0 over last 25%).
      final fadeIn  = t < 0.25 ? t / 0.25 : 1.0;
      final fadeOut = t > 0.75 ? (1.0 - t) / 0.25 : 1.0;
      final envelope = fadeIn * fadeOut;

      final alpha = (s.baseOpacity * envelope * (0.35 + speedNorm * 0.65))
          .clamp(0.0, 1.0);
      if (alpha < 0.004) continue;

      // Streak origin: drifts across the screen driven by t + direction.
      // The % 1.2 - 0.1 wraps it just outside screen edges (no sudden pop).
      final startX = ((s.xFrac + dx * t) % 1.2 - 0.1) * size.width;
      final startY = ((s.yFrac + dy * t) % 1.2 - 0.1) * size.height;
      final len    = s.lengthFrac * size.width;

      // Control point: slightly off-axis for a natural air-current bend.
      final perpX = -dy * s.curvature * len;
      final perpY =  dx * s.curvature * len;
      final midX  = startX + dx * len * 0.5 + perpX;
      final midY  = startY + dy * len * 0.5 + perpY;
      final endX  = startX + dx * len;
      final endY  = startY + dy * len;

      final shaderRect = Rect.fromPoints(Offset(startX, startY), Offset(endX, endY));
      // Guard against zero-size rect (would crash LinearGradient shader).
      if (shaderRect.width.abs() < 1 && shaderRect.height.abs() < 1) continue;

      final path = Path()
        ..moveTo(startX, startY)
        ..quadraticBezierTo(midX, midY, endX, endY);

      canvas.drawPath(path, Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withOpacity(0.0),
            Colors.white.withOpacity(alpha),
            Colors.white.withOpacity(alpha * 0.85),
            Colors.white.withOpacity(0.0),
          ],
          stops: const [0.0, 0.20, 0.80, 1.0],
        ).createShader(shaderRect)
        ..strokeWidth = s.strokeWidth
        ..strokeCap   = StrokeCap.round
        ..style       = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(_WindStreakLayer o) =>
      o.wind != wind || o.windSpeed != windSpeed || o.windDeg != windDeg;
}

// ═══════════════════════════════════════════════════════════════════════════
//  LAYER 6 — RAIN PAINTER  (bg blurred pass + fg sharp pass)
// ═══════════════════════════════════════════════════════════════════════════

class _RainPainter extends CustomPainter {
  final double scene, windDeg;
  final bool heavy, bgLayer;
  final Random rng;

  static List<List<double>>? _fgDrops;
  static List<List<double>>? _bgDrops;

  _RainPainter({required this.scene, required this.heavy, required this.windDeg,
    required this.rng, required this.bgLayer}) {
    _fgDrops ??= List.generate(90, (_) => [
      rng.nextDouble(), rng.nextDouble(),
      0.50 + rng.nextDouble() * 0.60, 10 + rng.nextDouble() * 10,
      0.28 + rng.nextDouble() * 0.30]);
    _bgDrops ??= List.generate(50, (_) => [
      rng.nextDouble(), rng.nextDouble(),
      0.35 + rng.nextDouble() * 0.40, 7 + rng.nextDouble() * 7,
      0.12 + rng.nextDouble() * 0.16]);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final windRad = windDeg * pi / 180.0;
    final slantX  = sin(windRad - pi) * 0.18;
    final drops   = bgLayer ? _bgDrops! : _fgDrops!;
    final count   = heavy ? drops.length : (drops.length * 0.60).round();
    final stroke  = bgLayer ? (heavy ? 1.8 : 1.3) : (heavy ? 1.4 : 1.0);

    final paint = Paint()..strokeCap = StrokeCap.round..strokeWidth = stroke;
    if (bgLayer) paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

    for (int i = 0; i < count; i++) {
      final d = drops[i];
      final x   = ((d[0] + scene * 0.06 * d[2]) % 1.0) * size.width;
      final y   = ((d[1] + scene * d[2]) % 1.0) * size.height;
      final len = d[3] * (heavy ? 1.4 : 1.0);
      paint.color = const Color(0xFF90CAF9).withOpacity(d[4] * (bgLayer ? 0.55 : 1.0));
      canvas.drawLine(Offset(x, y), Offset(x + len * slantX, y + len), paint);
    }
  }

  @override
  bool shouldRepaint(_RainPainter old) => old.scene != scene || old.windDeg != windDeg;
}

// ═══════════════════════════════════════════════════════════════════════════
//  LAYER 7 — ATMOSPHERIC HAZE  (slow-drifting horizontal mist bands)
// ═══════════════════════════════════════════════════════════════════════════

class _HazePainter extends CustomPainter {
  final double scene;
  const _HazePainter({required this.scene});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);
    final bands = [[0.10, 0.25, 0.08], [0.28, 0.38, 0.06], [0.55, 0.30, 0.05], [0.72, 0.45, 0.07]];

    for (int i = 0; i < bands.length; i++) {
      final driftX = sin(scene * pi * 2 * 0.4 + i * 1.3) * 0.08 * size.width;
      final opacity = (bands[i][2] + sin(scene * pi * 2 * 0.6 + i) * 0.018).clamp(0.03, 0.12);
      paint.color = const Color(0xFFB0BEC5).withOpacity(opacity);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(size.width * 0.5 + driftX, bands[i][0] * size.height),
          width: size.width * (1.2 + bands[i][1]), height: 55),
        paint);
    }
  }

  @override
  bool shouldRepaint(_HazePainter old) => old.scene != scene;
}

// ═══════════════════════════════════════════════════════════════════════════
//  LAYER 8 — MOON ONLY (stars removed — they were always static anyway)
// ═══════════════════════════════════════════════════════════════════════════

class _StarsPainter extends CustomPainter {
  final double scene;
  final Random rng;

  const _StarsPainter({required this.scene, required this.rng});

  @override
  void paint(Canvas canvas, Size size) {
    const mx = 0.78, my = 0.20;
    final moonCx = mx * size.width;
    final moonCy = my * size.height;
    const r = 18.0;

    // ── Real lunar phase from current date ───────────────────────────────
    // Known new moon: Jan 29 2025. Lunar cycle = 29.53059 days.
    final now = DateTime.now();
    final ref = DateTime(2025, 1, 29);
    final daysSince = now.difference(ref).inMinutes / 1440.0;
    final phase = (daysSince % 29.53059) / 29.53059; // 0=new, 0.5=full, 1=new

    // ── Outer atmospheric glow ───────────────────────────────────────────
    canvas.drawCircle(Offset(moonCx, moonCy), r + 22, Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFFE8F0FF).withOpacity(0.18),
        const Color(0xFFB0C8FF).withOpacity(0.08),
        Colors.transparent,
      ], stops: const [0.0, 0.5, 1.0])
        .createShader(Rect.fromCircle(center: Offset(moonCx, moonCy), radius: r + 22)));

    // ── Draw phase-accurate moon using Path operations ───────────────────
    // Technique: moon disc - shadow ellipse. The shadow ellipse x-radius
    // varies from r (new moon, fully shadowed) through 0 (full, no shadow)
    // to -r (new moon again). The sign flips the shadow side.
    //
    // phase:  0.00 = new moon (invisible)
    //         0.25 = first quarter (right half lit)
    //         0.50 = full moon
    //         0.75 = last quarter (left half lit)
    //         1.00 = new moon again

    final moonPath = ui.Path()
      ..addOval(Rect.fromCircle(center: Offset(moonCx, moonCy), radius: r));

    if (phase < 0.02 || phase > 0.98) {
      // New moon — draw a very dim disc only
      canvas.drawCircle(Offset(moonCx, moonCy), r,
        Paint()..color = const Color(0xFF3A4060).withOpacity(0.35));
      return;
    }

    // Compute the shadow ellipse x-radius and which side it's on.
    // 0→0.5: waxing (shadow on left, shrinks), 0.5→1: waning (shadow on right, grows)
    final double shadowXRadius;
    final double shadowOffsetX;

    if (phase <= 0.5) {
      // Waxing: shadow covers left side, shrinks as we approach full
      shadowXRadius = r * (1.0 - phase * 2.0).abs();
      shadowOffsetX = phase < 0.25 ? -r * 0.0 : r * 0.0;
    } else {
      // Waning: shadow covers right side, grows as we move away from full
      shadowXRadius = r * ((phase - 0.5) * 2.0);
      shadowOffsetX = 0.0;
    }

    // The shadow is an ellipse: full height (r), variable width (shadowXRadius)
    // For waxing phases (0–0.5): shadow is on the LEFT
    // For waning phases (0.5–1): shadow is on the RIGHT
    final bool shadowOnLeft = phase <= 0.5;

    ui.Path litPath;

    if ((phase - 0.5).abs() < 0.02) {
      // Full moon — entire disc lit
      litPath = moonPath;
    } else if (shadowXRadius >= r * 0.98) {
      // Nearly new — almost completely dark
      canvas.drawCircle(Offset(moonCx, moonCy), r,
        Paint()..color = const Color(0xFF3A4060).withOpacity(0.40));
      return;
    } else {
      // Crescent or gibbous — subtract shadow ellipse from disc
      final shadowRect = Rect.fromCenter(
        center: Offset(moonCx, moonCy),
        width:  shadowXRadius * 2,
        height: r * 2,
      );
      final shadowPath = ui.Path()..addOval(shadowRect);

      if (shadowOnLeft) {
        // Waxing: right side lit — shadow on left
        litPath = ui.Path.combine(
          ui.PathOperation.difference, moonPath, shadowPath);
      } else {
        // Waning: left side lit — shadow on right
        litPath = ui.Path.combine(
          ui.PathOperation.difference, moonPath, shadowPath);
      }
    }

    // ── Draw the lit portion ─────────────────────────────────────────────
    // Dark unlit side
    canvas.drawCircle(Offset(moonCx, moonCy), r, Paint()
      ..color = const Color(0xFF1A2040).withOpacity(0.55));

    // Lit face — soft gradient
    final litPaint = Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withOpacity(0.96),
        const Color(0xFFFFF9E6).withOpacity(0.92),
        const Color(0xFFE8E0C8).withOpacity(0.85),
      ], stops: const [0.0, 0.55, 1.0])
        .createShader(Rect.fromCircle(center: Offset(moonCx, moonCy), radius: r));

    canvas.drawPath(litPath, litPaint);

    // Subtle surface texture — a few soft crater hints
    final craterPaint = Paint()
      ..color = const Color(0xFFD0C8B0).withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.save();
    canvas.clipPath(litPath);
    canvas.drawCircle(Offset(moonCx - r * 0.25, moonCy + r * 0.15), r * 0.22, craterPaint);
    canvas.drawCircle(Offset(moonCx + r * 0.18, moonCy - r * 0.30), r * 0.16, craterPaint);
    canvas.drawCircle(Offset(moonCx + r * 0.05, moonCy + r * 0.40), r * 0.12, craterPaint);
    canvas.restore();

    // Soft edge glow on the lit side
    canvas.drawPath(litPath, Paint()
      ..color = const Color(0xFFF0E8D0).withOpacity(0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  }

  @override
  bool shouldRepaint(_StarsPainter old) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
//  LAYER 9 — LIGHTNING FLASH
// ═══════════════════════════════════════════════════════════════════════════

class _LightningFlash extends StatefulWidget {
  const _LightningFlash();
  @override
  State<_LightningFlash> createState() => _LightningFlashState();
}

class _LightningFlashState extends State<_LightningFlash>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final _rng = Random();
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 110));
    _schedule();
  }
  void _schedule() {
    Future.delayed(Duration(milliseconds: 2800 + _rng.nextInt(7000)), () {
      if (!mounted) return;
      _ctrl.forward(from: 0).then((_) { if (mounted) _ctrl.reverse().then((_) => _schedule()); });
    });
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => IgnorePointer(
      child: Opacity(opacity: _ctrl.value * 0.30, child: Container(color: const Color(0xFFDCEEFF)))));
}

// ═══════════════════════════════════════════════════════════════════════════
//  LAYER 10 — CONTEXT BANNER
// ═══════════════════════════════════════════════════════════════════════════

class _ContextBanner extends StatelessWidget {
  final WeatherData? weather;
  final WeatherCondition? condition;
  final double fade;
  const _ContextBanner({required this.weather, required this.condition, required this.fade});

  @override
  Widget build(BuildContext context) {
    if (weather == null || fade < 0.3) return const SizedBox.shrink();
    String? msg; Color? color; IconData? icon;
    switch (condition) {
      case WeatherCondition.rain:
      case WeatherCondition.thunderstorm:
        msg = 'Irrigation not needed today'; color = const Color(0xFF0288D1); icon = Icons.water_drop_rounded; break;
      case WeatherCondition.clearDay:
        if (weather!.tempC > 32) { msg = 'High evaporation expected'; color = const Color(0xFFE65100); icon = Icons.wb_sunny_rounded; }
        break;
      case WeatherCondition.foggy:
        msg = 'Reduced visibility — check field manually'; color = const Color(0xFF546E7A); icon = Icons.visibility_off_rounded; break;
      default: break;
    }
    if (msg == null) return const SizedBox.shrink();
    return AnimatedOpacity(
      opacity: fade, duration: const Duration(milliseconds: 500),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 168, 80, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: (color ?? Colors.black).withOpacity(0.26),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: (color ?? Colors.white).withOpacity(0.22))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: Colors.white, size: 13),
                const SizedBox(width: 6),
                Text(msg, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: Colors.white, letterSpacing: 0.3)),
              ]))))));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  POLYGON PULSE PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class PolygonPulsePainter extends CustomPainter {
  final List<Offset> points;
  final double phase;
  final Color color;
  const PolygonPulsePainter({required this.points, required this.phase, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 3) return;
    final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) path.lineTo(points[i].dx, points[i].dy);
    path.close();
    final glow = 8 + sin(phase * pi * 2) * 4;
    canvas.drawPath(path, Paint()
      ..color = color.withOpacity(0.22 + sin(phase * pi * 2) * 0.12)
      ..style = PaintingStyle.stroke..strokeWidth = glow
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow));
    canvas.drawPath(path, Paint()
      ..color = color.withOpacity(0.78)..style = PaintingStyle.stroke..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(PolygonPulsePainter old) => old.phase != phase || old.points != points;
}

// ═══════════════════════════════════════════════════════════════════════════
//  WEATHER-AWARE FAB GLOW
// ═══════════════════════════════════════════════════════════════════════════

class WeatherAwareFabGlow extends StatefulWidget {
  final Widget child;
  final Color glowColor;
  final bool active;
  const WeatherAwareFabGlow({super.key, required this.child, required this.glowColor, this.active = false});
  @override
  State<WeatherAwareFabGlow> createState() => _WeatherAwareFabGlowState();
}

class _WeatherAwareFabGlowState extends State<WeatherAwareFabGlow>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;
  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Container(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(
          color: widget.glowColor.withOpacity(_pulse.value * 0.55),
          blurRadius: 18 + _pulse.value * 10, spreadRadius: 2 + _pulse.value * 4)]),
        child: child),
      child: widget.child);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  TIME-OF-DAY PALETTE
// ═══════════════════════════════════════════════════════════════════════════

class TimeOfDayPalette {
  static Color get headerTint {
    final h = TimeOfDay.now().hour;
    if (h >= 19 || h < 6) return const Color(0xFF0D1B2A);
    if (h >= 17)          return const Color(0xFF4A1A00);
    if (h >= 7 && h < 10) return const Color(0xFF1A2F00);
    return const Color(0xFF1B5E20);
  }
  static List<Color> get skyGradient {
    final h = TimeOfDay.now().hour;
    if (h >= 20 || h < 5)  return [const Color(0xFF050D1A), const Color(0xFF0A1628)];
    if (h >= 5  && h < 7)  return [const Color(0xFFFF6B35), const Color(0xFFFF8C00)];
    if (h >= 17 && h < 20) return [const Color(0xFFFF4500), const Color(0xFFFF8C00)];
    return [const Color(0xFF1B5E20), const Color(0xFF2E7D32)];
  }
  static double get overlayOpacity {
    final h = TimeOfDay.now().hour;
    return (h >= 20 || h < 6) ? 0.55 : 0.0;
  }
}
