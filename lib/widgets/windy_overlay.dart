import 'dart:math';
import 'package:flutter/material.dart';
import '../services/weather_service.dart';

// WindyMapOverlay is kept as a no-op so existing references compile cleanly.
// Wind particles have been permanently disabled per product requirements.
class WindyMapOverlay extends StatelessWidget {
  final WeatherData? weather;
  final bool enabled;
  const WindyMapOverlay({super.key, required this.weather, this.enabled = false});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ═══════════════════════════════════════════════════════════════════════════
//  WINDY INFO BADGE  — minimal: emoji · temp · trend arrow  (no border/bg)
// ═══════════════════════════════════════════════════════════════════════════
class WindyInfoBadge extends StatelessWidget {
  final WeatherData? weather;
  final bool isLoading;

  // Optional previous temperature to derive trend arrow.
  // If null we omit the arrow.
  final double? previousTempC;

  const WindyInfoBadge({
    super.key,
    required this.weather,
    this.isLoading = false,
    this.previousTempC,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        width: 14, height: 14,
        child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white70),
      );
    }
    if (weather == null) return const SizedBox.shrink();

    final w = weather!;

    // Trend: +1 rising, -1 falling, 0 stable (±0.5 °C threshold)
    int trend = 0;
    if (previousTempC != null) {
      final delta = w.tempC - previousTempC!;
      if (delta > 0.5)       trend =  1;
      else if (delta < -0.5) trend = -1;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Weather emoji
        Text(
          _conditionIcon(w.condition),
          style: const TextStyle(fontSize: 18),
        ),
        const SizedBox(width: 5),

        // Temperature
        Text(
          w.tempLabel,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
          ),
        ),

        // Trend arrow — only when trend ≠ 0
        if (trend != 0) ...[
          const SizedBox(width: 3),
          Icon(
            trend > 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            size: 16,
            color: trend > 0
                ? const Color(0xFFFF7043)  // warm orange = rising
                : const Color(0xFF4FC3F7), // cool blue = falling
            shadows: const [Shadow(color: Colors.black38, blurRadius: 4)],
          ),
        ],
      ],
    );
  }

  String _conditionIcon(WeatherCondition c) {
    switch (c) {
      case WeatherCondition.clearDay:          return '☀️';
      case WeatherCondition.clearNight:        return '🌙';
      case WeatherCondition.partlyCloudyDay:   return '⛅';
      case WeatherCondition.partlyCloudyNight: return '🌤';
      case WeatherCondition.cloudy:            return '☁️';
      case WeatherCondition.rain:              return '🌧️';
      case WeatherCondition.thunderstorm:      return '⛈️';
      case WeatherCondition.snow:              return '❄️';
      case WeatherCondition.foggy:             return '🌫️';
    }
  }
}


// ═══════════════════════════════════════════════════════════════════════════
//  WALKING MAN MARKER  –  Google Maps-style animated person on the map
//  • Legs animate when moving, static when stopped
//  • Rotates to face direction of travel (device heading)
//  • Ripple ring + blue glow halo
//  • Direction cone (blue triangular wedge)
// ═══════════════════════════════════════════════════════════════════════════
class WalkingManMarker extends StatefulWidget {
  final double heading;   // degrees clockwise from north
  final bool isMoving;

  const WalkingManMarker({
    super.key,
    this.heading = 0,
    this.isMoving = false,
  });

  @override
  State<WalkingManMarker> createState() => _WalkingManMarkerState();
}

class _WalkingManMarkerState extends State<WalkingManMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        final headingRad = widget.heading * pi / 180.0;
        return SizedBox(
          width: 56, height: 56,
          child: Stack(alignment: Alignment.center, children: [

            // Accuracy ripple ring
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF29B6F6).withOpacity(0.12),
                border: Border.all(
                  color: const Color(0xFF29B6F6).withOpacity(0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF29B6F6)
                        .withOpacity(0.25 * _pulse.value),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),

            // Navigation arrow — rotates with heading
            Transform.rotate(
              angle: headingRad,
              child: CustomPaint(
                size: const Size(40, 40),
                painter: _ArrowPainter(pulse: _pulse.value),
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ── Navigation arrow painter ─────────────────────────────────────────────
// Draws the hollow cursor/arrow shape from the reference image.
// Arrow points UP in its own coordinate system; the Transform.rotate
// above applies the heading so it always faces the direction of travel.
class _ArrowPainter extends CustomPainter {
  final double pulse;
  const _ArrowPainter({required this.pulse});

  @override
  void paint(Canvas canvas, Size s) {
    final cx = s.width  / 2;
    final cy = s.height / 2;
    final sc = s.width  / 40.0;

    // Arrow tip points upward (north in the rotated frame).
    // Shape matches the reference: pointy tip, two wing points,
    // and an indented notch at the tail — classic navigation cursor.
    //
    //        tip  (0, -17)
    //       /        // (-12, 14)  (12, 14)   ← wing corners
    //       \    /
    //        (0, 8)         ← tail notch (indented inward)

    final tip        = Offset(cx,          cy - 17 * sc);
    final wingLeft   = Offset(cx - 12 * sc, cy + 14 * sc);
    final wingRight  = Offset(cx + 12 * sc, cy + 14 * sc);
    final tailNotch  = Offset(cx,           cy +  8 * sc);
    // Inner notch points (where the outline folds in)
    final innerLeft  = Offset(cx -  4 * sc, cy +  4 * sc);
    final innerRight = Offset(cx +  4 * sc, cy +  4 * sc);

    // ── Filled arrow (white with slight blue tint) ────────────────────
    final fillPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(wingRight.dx, wingRight.dy)
      ..lineTo(tailNotch.dx, tailNotch.dy)
      ..lineTo(wingLeft.dx, wingLeft.dy)
      ..close();

    canvas.drawPath(fillPath, Paint()
      ..color = Colors.white.withOpacity(0.90 * pulse)
      ..style = PaintingStyle.fill);

    // ── Outline stroke ────────────────────────────────────────────────
    // Drawn as two triangles with a shared tip — left half and right half —
    // leaving the centre of the arrow hollow (matches reference image).
    final strokePaint = Paint()
      ..color = const Color(0xFF1565C0).withOpacity(0.95)
      ..strokeWidth = 1.8 * sc
      ..strokeJoin = StrokeJoin.round
      ..strokeCap  = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Left wing outline: tip → left wing → tail notch → inner-left → tip
    final leftPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(wingLeft.dx, wingLeft.dy)
      ..lineTo(tailNotch.dx, tailNotch.dy)
      ..lineTo(innerLeft.dx, innerLeft.dy)
      ..lineTo(tip.dx, tip.dy);
    canvas.drawPath(leftPath, strokePaint);

    // Right wing outline
    final rightPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(wingRight.dx, wingRight.dy)
      ..lineTo(tailNotch.dx, tailNotch.dy)
      ..lineTo(innerRight.dx, innerRight.dy)
      ..lineTo(tip.dx, tip.dy);
    canvas.drawPath(rightPath, strokePaint);

    // Centre dividing line (tip → tail notch) to show the hollow middle
    canvas.drawLine(tip, tailNotch, strokePaint);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.pulse != pulse;
}

