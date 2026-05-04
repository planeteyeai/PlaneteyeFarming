import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/weather_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  WEATHER ALERT BANNER
//
//  Shown at the top of the dashboard when weather conditions need attention.
//
//  Alert types (priority order — lower number = more urgent):
//    0. Thunderstorm          — purple, ⛈️
//    1. Cyclone/Severe wind   — deep red, 🌀
//    2. Heavy rain            — dark blue, 🌧️
//    3. Extreme heat (>42°C)  — deep orange, 🔥
//    4. Frost warning (<2°C)  — teal, 🥶
//    5. Strong wind (>13 m/s) — slate, 💨
//    6. Rain warning          — blue, 🌦️
//    7. High temp (38–42°C)   — amber, ☀️
//    8. Cold alert (2–8°C)    — blue, ❄️
//    9. Heavy overcast        — grey-blue, ☁️
//   10. Humidity alert (>90%) — green-teal, 💧
//   11. Drought risk (dry+hot)— brown-orange, 🏜️
//
//  Features:
//    • Slides in from top with spring curve
//    • Multiple alerts cycle every 4 s with animated indicator dots
//    • Left-side coloured accent bar pulses gently
//    • Auto-dismisses after 10 s; swipe-up to dismiss
//    • Actionable advice tailored to farmers (not just weather info)
// ═══════════════════════════════════════════════════════════════════════════

class WeatherAlertBanner extends StatefulWidget {
  final WeatherData? weather;
  const WeatherAlertBanner({super.key, required this.weather});

  @override
  State<WeatherAlertBanner> createState() => _WeatherAlertBannerState();
}

class _WeatherAlertBannerState extends State<WeatherAlertBanner>
    with TickerProviderStateMixin {

  List<_WeatherAlert> _alerts = [];
  int  _currentIndex = 0;
  bool _dismissed    = false;

  Timer? _cycleTimer;
  Timer? _autoDismissTimer;

  late AnimationController _slideCtrl;
  late AnimationController _pulseCtrl;  // accent bar pulse
  late Animation<Offset> _slide;
  late Animation<double>  _fade;
  late Animation<double>  _pulse;

  @override
  void initState() {
    super.initState();

    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _slide = Tween<Offset>(begin: const Offset(0, -1.4), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _slideCtrl, curve: Curves.easeOutBack));
    _fade = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _buildAlerts();
  }

  @override
  void didUpdateWidget(WeatherAlertBanner old) {
    super.didUpdateWidget(old);
    final w = widget.weather;
    final o = old.weather;
    if (w?.conditionCode != o?.conditionCode ||
        w?.windSpeedMs   != o?.windSpeedMs   ||
        w?.tempC         != o?.tempC         ||
        w?.humidity      != o?.humidity      ||
        w?.cloudCoverPct != o?.cloudCoverPct) {
      _dismissed = false;
      _buildAlerts();
    }
  }

  // ── Build alert list from current weather ─────────────────────────────

  void _buildAlerts() {
    final w = widget.weather;
    if (w == null) { setState(() => _alerts = []); return; }

    final List<_WeatherAlert> found = [];

    // 0 — Thunderstorm
    if (w.condition == WeatherCondition.thunderstorm) {
      found.add(const _WeatherAlert(
        icon: '⛈️',
        title: 'Thunderstorm Warning',
        message: 'Severe thunderstorm. Stay indoors, secure farm equipment '
            'and livestock. Do not work in open fields.',
        bg: Color(0xFF311B92), accent: Color(0xFFCE93D8), priority: 0,
      ));
    }

    // 1 — Cyclone / extreme wind
    if (w.windSpeedMs > 28) {
      found.add(_WeatherAlert(
        icon: '🌀',
        title: 'Cyclone / Severe Gale Warning',
        message: 'Wind ${w.windSpeedMs.toStringAsFixed(0)} m/s — '
            'extreme danger. Evacuate livestock to shelter immediately.',
        bg: const Color(0xFFB71C1C), accent: const Color(0xFFFF8A80),
        priority: 1,
      ));
    }

    // 2 — Heavy rain
    final mm = w.rainMmLastHour ?? 0;
    if (w.condition == WeatherCondition.rain && mm > 10) {
      found.add(_WeatherAlert(
        icon: '🌧️',
        title: 'Heavy Rain Alert',
        message: '${mm.toStringAsFixed(1)} mm/hr rainfall. Risk of '
            'waterlogging and soil erosion. Delay fertiliser application.',
        bg: const Color(0xFF0D47A1), accent: const Color(0xFF82B1FF),
        priority: 2,
      ));
    }

    // 3 — Extreme heat
    if (w.tempC > 42) {
      found.add(_WeatherAlert(
        icon: '🔥',
        title: 'Extreme Heat Warning',
        message: '${w.tempC.round()}°C — severe crop stress risk. '
            'Double irrigation frequency. Avoid field work 11 am–4 pm.',
        bg: const Color(0xFFBF360C), accent: const Color(0xFFFF8A65),
        priority: 3,
      ));
    }

    // 4 — Frost
    if (w.tempC < 2) {
      found.add(_WeatherAlert(
        icon: '🥶',
        title: 'Frost Warning',
        message: '${w.tempC.round()}°C — frost risk tonight. '
            'Cover sensitive crops immediately. Protect seedlings.',
        bg: const Color(0xFF006064), accent: const Color(0xFF80DEEA),
        priority: 4,
      ));
    }

    // 5 — Strong wind
    if (w.windSpeedMs > 20 && w.windSpeedMs <= 28) {
      found.add(_WeatherAlert(
        icon: '💨',
        title: 'Strong Wind Advisory',
        message: 'Wind ${w.windSpeedMs.toStringAsFixed(1)} m/s — '
            'risk of lodging. Do not spray pesticides or irrigate.',
        bg: const Color(0xFF263238), accent: const Color(0xFFB0BEC5),
        priority: 5,
      ));
    } else if (w.windSpeedMs > 13 && w.windSpeedMs <= 20) {
      found.add(_WeatherAlert(
        icon: '🌬️',
        title: 'Moderate Wind Warning',
        message: 'Wind ${w.windSpeedMs.toStringAsFixed(1)} m/s — '
            'avoid pesticide spraying. Secure irrigation pipes.',
        bg: const Color(0xFF37474F), accent: const Color(0xFFCFD8DC),
        priority: 5,
      ));
    }

    // 6 — Light rain
    if (w.condition == WeatherCondition.rain && mm <= 10) {
      found.add(_WeatherAlert(
        icon: '🌦️',
        title: 'Rain in Your Area',
        message: 'Rainfall detected. Consider delaying irrigation, '
            'spraying, and harvesting operations.',
        bg: const Color(0xFF1565C0), accent: const Color(0xFF90CAF9),
        priority: 6,
      ));
    }

    // 7 — High temp (not extreme)
    if (w.tempC >= 38 && w.tempC <= 42) {
      found.add(_WeatherAlert(
        icon: '☀️',
        title: 'High Temperature Alert',
        message: '${w.tempC.round()}°C — ensure adequate soil moisture. '
            'Mulch to retain water. Watch for heat stress signs.',
        bg: const Color(0xFFE65100), accent: const Color(0xFFFFCC80),
        priority: 7,
      ));
    }

    // 8 — Cold alert
    if (w.tempC >= 2 && w.tempC < 8) {
      found.add(_WeatherAlert(
        icon: '❄️',
        title: 'Cold Temperature Alert',
        message: '${w.tempC.round()}°C — cold stress possible for warm-season '
            'crops. Delay transplanting. Monitor for root damage.',
        bg: const Color(0xFF01579B), accent: const Color(0xFFB3E5FC),
        priority: 8,
      ));
    }

    // 9 — Heavy overcast / low light
    if (w.cloudCoverPct > 88 &&
        w.condition != WeatherCondition.rain &&
        w.condition != WeatherCondition.thunderstorm) {
      found.add(const _WeatherAlert(
        icon: '☁️',
        title: 'Heavy Overcast',
        message: 'Very low light — photosynthesis reduced. '
            'Avoid fungicide spraying. Monitor for fungal disease pressure.',
        bg: Color(0xFF546E7A), accent: Color(0xFFECEFF1),
        priority: 9,
      ));
    }

    // 10 — High humidity
    if (w.humidity > 90 &&
        w.condition != WeatherCondition.rain &&
        w.condition != WeatherCondition.thunderstorm) {
      found.add(_WeatherAlert(
        icon: '💧',
        title: 'High Humidity Alert',
        message: '${w.humidity}% humidity — high risk of fungal and '
            'bacterial disease. Inspect crops for blight and mildew.',
        bg: const Color(0xFF00695C), accent: const Color(0xFF80CBC4),
        priority: 10,
      ));
    }

    // 11 — Drought risk (hot + dry + no rain)
    if (w.tempC > 35 && w.humidity < 30 &&
        w.condition == WeatherCondition.clearDay &&
        mm == 0) {
      found.add(_WeatherAlert(
        icon: '🏜️',
        title: 'Drought Risk Advisory',
        message: '${w.tempC.round()}°C, ${w.humidity}% humidity — '
            'drought stress risk. Prioritise irrigation. Check soil moisture.',
        bg: const Color(0xFF4E342E), accent: const Color(0xFFBCAAA4),
        priority: 11,
      ));
    }

    found.sort((a, b) => a.priority.compareTo(b.priority));

    final wasEmpty = _alerts.isEmpty;
    setState(() { _alerts = found; _currentIndex = 0; });

    if (found.isNotEmpty && !_dismissed) {
      _slideCtrl.forward(from: 0);
      _startTimers();
    }
  }

  void _startTimers() {
    _cycleTimer?.cancel();
    _autoDismissTimer?.cancel();

    if (_alerts.length > 1) {
      _cycleTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted) return;
        setState(() => _currentIndex = (_currentIndex + 1) % _alerts.length);
      });
    }

    _autoDismissTimer = Timer(const Duration(seconds: 12), () {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() {
    _cycleTimer?.cancel();
    _autoDismissTimer?.cancel();
    _slideCtrl.reverse().then((_) {
      if (mounted) setState(() => _dismissed = true);
    });
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    _autoDismissTimer?.cancel();
    _slideCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_alerts.isEmpty || _dismissed) return const SizedBox.shrink();

    final alert = _alerts[_currentIndex];

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: SafeArea(
          bottom: false,
          child: GestureDetector(
            onVerticalDragEnd: (d) {
              if (d.velocity.pixelsPerSecond.dy < -60) _dismiss();
            },
            onTap: () {
              // Tap to cycle through alerts manually
              if (_alerts.length > 1) {
                setState(() =>
                    _currentIndex = (_currentIndex + 1) % _alerts.length);
              }
            },
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              decoration: BoxDecoration(
                color: alert.bg.withOpacity(0.94),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: alert.accent.withOpacity(0.30), width: 1.2),
                boxShadow: [
                  BoxShadow(
                      color: alert.bg.withOpacity(0.55),
                      blurRadius: 20,
                      offset: const Offset(0, 5)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  // Pulsing left accent bar
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, __) => Container(
                      width: 5,
                      color: alert.accent.withOpacity(0.65 * _pulse.value),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 11),
                      child: Row(children: [
                        // Icon
                        Text(alert.icon,
                            style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 10),
                        // Title + message
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                            Row(children: [
                              Expanded(
                                child: Text(alert.title,
                                    style: TextStyle(
                                        color: alert.accent,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12.5,
                                        letterSpacing: 0.2)),
                              ),
                              // Alert count indicator dots
                              if (_alerts.length > 1)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(
                                    min(_alerts.length, 5),
                                    (i) => Container(
                                      width: i == _currentIndex ? 12 : 5,
                                      height: 5,
                                      margin: const EdgeInsets.only(left: 3),
                                      decoration: BoxDecoration(
                                        color: alert.accent.withOpacity(
                                            i == _currentIndex ? 0.9 : 0.35),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ),
                            ]),
                            const SizedBox(height: 3),
                            Text(alert.message,
                                style: TextStyle(
                                    color: alert.accent.withOpacity(0.82),
                                    fontSize: 11.5,
                                    height: 1.38)),
                          ]),
                        ),
                        const SizedBox(width: 6),
                        // Dismiss X
                        GestureDetector(
                          onTap: _dismiss,
                          child: Container(
                            width: 26, height: 26,
                            decoration: BoxDecoration(
                              color: alert.accent.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.close_rounded,
                                color: alert.accent.withOpacity(0.65),
                                size: 15),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Alert data model ──────────────────────────────────────────────────────

class _WeatherAlert {
  final String icon;
  final String title;
  final String message;
  final Color  bg;      // banner background
  final Color  accent;  // text + bar colour
  final int    priority; // 0 = most urgent

  const _WeatherAlert({
    required this.icon,
    required this.title,
    required this.message,
    required this.bg,
    required this.accent,
    required this.priority,
  });
}
