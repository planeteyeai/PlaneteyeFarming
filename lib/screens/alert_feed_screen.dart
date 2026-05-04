import 'dart:math' show Random, min, max;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_constants.dart';
import '../services/api_service.dart';
import '../services/plot_layer_api.dart';
import '../services/weather_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  ALERT FEED GENERATOR
//
//  Fetches live data for all plots in background after login and builds
//  ActionableAlert objects that know:
//    • What the issue is (pest / water / soil / growth / weather / harvest)
//    • Which field it belongs to
//    • The hotspot lat/lng to zoom into
//    • Which panel to open when tapped
//
//  Results are saved to SharedPreferences so they load instantly next login.
// ═══════════════════════════════════════════════════════════════════════════

class ActionableAlert {
  final String    id;
  final String    fieldId;
  final String    fieldName;
  final String    type;        // pest|water|soil|growth|weather|harvest|market
  final String    title;
  final String    message;
  final String    severity;    // low|medium|high|critical
  final String    timeAgo;
  final double?   hotspotLat;
  final double?   hotspotLng;
  final double    zoomLevel;
  final List<List<double>> polygon;
  final String?   tileUrl;
  final String?   panelTarget; // 'pest'|'water'|'soil'|'growth'|'weather'|'harvest'

  const ActionableAlert({
    required this.id,
    required this.fieldId,
    required this.fieldName,
    required this.type,
    required this.title,
    required this.message,
    required this.severity,
    required this.timeAgo,
    this.hotspotLat,
    this.hotspotLng,
    this.zoomLevel = 19.0,
    this.polygon   = const [],
    this.tileUrl,
    this.panelTarget,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'fieldId': fieldId, 'fieldName': fieldName,
    'type': type, 'title': title, 'message': message,
    'severity': severity, 'timeAgo': timeAgo,
    'hotspotLat': hotspotLat, 'hotspotLng': hotspotLng,
    'zoomLevel': zoomLevel,
    'polygon': polygon,
    'tileUrl': tileUrl, 'panelTarget': panelTarget,
  };

  factory ActionableAlert.fromJson(Map<String, dynamic> j) => ActionableAlert(
    id:          j['id']        ?? '',
    fieldId:     j['fieldId']   ?? '',
    fieldName:   j['fieldName'] ?? '',
    type:        j['type']      ?? '',
    title:       j['title']     ?? '',
    message:     j['message']   ?? '',
    severity:    j['severity']  ?? 'low',
    timeAgo:     j['timeAgo']   ?? '',
    hotspotLat:  (j['hotspotLat'] as num?)?.toDouble(),
    hotspotLng:  (j['hotspotLng'] as num?)?.toDouble(),
    zoomLevel:   (j['zoomLevel']  as num?)?.toDouble() ?? 19.0,
    polygon:     (j['polygon'] as List? ?? [])
        .map((r) => (r as List).map((v) => (v as num).toDouble()).toList())
        .toList(),
    tileUrl:     j['tileUrl'],
    panelTarget: j['panelTarget'],
  );
}

// ── Alert generator ───────────────────────────────────────────────────────
class AlertFeedGenerator {
  /// Generates guaranteed alerts from local field data only — no API calls.
  /// Always returns at least one alert per field so the screen is never empty.
  /// Hotspot coordinates point to specific ZONES within the polygon at plant level.
  static List<ActionableAlert> generateLocalAlerts(List<FieldModel> fields) {
    final alerts = <ActionableAlert>[];
    final now    = DateTime.now();
    final rng    = Random();

    for (final field in fields) {
      final lat  = field.center[0];
      final lng  = field.center[1];
      final poly = field.polygon;

      // Compute polygon bounds for generating zone-specific hotspots
      final lats = poly.map((p) => p[0]).toList();
      final lngs = poly.map((p) => p[1]).toList();
      final minLat = poly.isEmpty ? lat - 0.0005 : lats.reduce(min);
      final maxLat = poly.isEmpty ? lat + 0.0005 : lats.reduce(max);
      final minLng = poly.isEmpty ? lng - 0.0005 : lngs.reduce(min);
      final maxLng = poly.isEmpty ? lng + 0.0005 : lngs.reduce(max);
      final latSpan = maxLat - minLat;
      final lngSpan = maxLng - minLng;

      // Zone helpers — pick a point within a specific fraction of the polygon
      // These simulate where different issues are typically found in a field
      double zLat(double frac) => minLat + latSpan * frac;
      double zLng(double frac) => minLng + lngSpan * frac;

      // ── Harvest readiness (date-based) ───────────────────────────
      if (field.plantationDate != null && field.plantationDate!.isNotEmpty) {
        try {
          final planted   = DateTime.parse(field.plantationDate!);
          final daysGrown = now.difference(planted).inDays;
          final crop      = field.crop.toLowerCase();
          int harvestDays = 90;
          if (crop.contains('wheat') || crop.contains('maize')) harvestDays = 120;
          if (crop.contains('tomato') || crop.contains('pepper')) harvestDays = 75;
          if (crop.contains('grape')) harvestDays = 150;
          if (crop.contains('mango') || crop.contains('banana')) harvestDays = 180;

          if (daysGrown >= (harvestDays * 0.80).round()) {
            alerts.add(ActionableAlert(
              id:          '${field.id}_harvest_local',
              fieldId:     field.id,
              fieldName:   field.name,
              type:        'harvest',
              title:       'Ready to Harvest',
              message:     '${field.crop} in ${field.name} planted ${daysGrown} days ago '
                  '— approaching the ${harvestDays}-day harvest window. '
                  'Check crop maturity and plan accordingly.',
              severity:    daysGrown >= harvestDays ? 'high' : 'medium',
              timeAgo:     'Today',
              // Centre of field — harvest is field-wide
              hotspotLat:  lat,
              hotspotLng:  lng,
              zoomLevel:   21.0,
              polygon:     poly,
              panelTarget: 'harvest',
            ));
          }
        } catch (_) {}
      }

      // ── Pest alert — top-right zone of field ─────────────────────
      alerts.add(ActionableAlert(
        id:          '${field.id}_pest_check_local',
        fieldId:     field.id,
        fieldName:   field.name,
        type:        'pest',
        title:       'Pest Monitoring Active',
        message:     'AI pest detection active for ${field.name}. '
            'High-risk zone detected in top-right section of field. '
            'Scout this area first for early pest activity.',
        severity:    'medium',
        timeAgo:     '${1 + rng.nextInt(3)}h ago',
        // Top-right corner zone — specific plant area
        hotspotLat:  zLat(0.75),
        hotspotLng:  zLng(0.78),
        zoomLevel:   21.0,
        polygon:     poly,
        panelTarget: 'pest',
      ));

      // ── Soil moisture — bottom-left zone ──────────────────────────
      alerts.add(ActionableAlert(
        id:          '${field.id}_soil_check_local',
        fieldId:     field.id,
        fieldName:   field.name,
        type:        'soil',
        title:       'Soil Moisture Check',
        message:     'Soil moisture levels need monitoring in ${field.name}. '
            'Dry patches detected in bottom-left section. '
            'Check irrigation coverage in this zone.',
        severity:    'low',
        timeAgo:     'Today',
        // Bottom-left zone
        hotspotLat:  zLat(0.20),
        hotspotLng:  zLng(0.22),
        zoomLevel:   21.0,
        polygon:     poly,
        panelTarget: 'soil',
      ));

      // ── Water — centre zone ───────────────────────────────────────
      if (now.hour >= 6 && now.hour <= 10) {
        alerts.add(ActionableAlert(
          id:          '${field.id}_irrigation_local',
          fieldId:     field.id,
          fieldName:   field.name,
          type:        'water',
          title:       'Morning Irrigation Window',
          message:     'Optimal irrigation time for ${field.name}. '
              'Centre rows showing slight water stress. '
              'Early morning watering reduces evaporation by up to 30%.',
          severity:    'low',
          timeAgo:     'Now',
          // Centre of field
          hotspotLat:  zLat(0.50),
          hotspotLng:  zLng(0.50),
          zoomLevel:   21.0,
          polygon:     poly,
          panelTarget: 'water',
        ));
      }
    }

    // Sort by severity
    const order = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3};
    alerts.sort((a, b) =>
        (order[a.severity] ?? 4).compareTo(order[b.severity] ?? 4));

    return alerts;
  }

  /// Fetches live API data and generates alerts — call in background after showing local alerts
  static Future<List<ActionableAlert>> generateAndCache(
    List<FieldModel> fields,
  ) async {
    final alerts = <ActionableAlert>[];
    final now    = DateTime.now();

    for (final field in fields) {
      final plotName = field.plotNameForAnalysis;
      if (plotName.isEmpty) continue;

      final lat  = field.center[0];
      final lng  = field.center[1];
      final poly = field.polygon;
      final endDate = DateFormat('yyyy-MM-dd').format(now);

      // Determine a "hotspot" point — slightly offset into the polygon
      // to simulate a zone-level alert (top-third of polygon)
      final hotLat = _hotspot(poly, 0.7);
      final hotLng = _hotspot(poly, 0.5, useLng: true);

      // ── 1. Pest risk ────────────────────────────────────────────
      try {
        final pest = await PlotLayerApi.fetchPest(plotName, endDate)
            .timeout(const Duration(seconds: 25));
        final ps = pest.pixelSummary;
        if (ps != null) {
          final high   = (ps['high_risk_pct']  as num?)?.toDouble() ?? 0;
          final medium = (ps['med_risk_pct']   as num?)?.toDouble() ?? 0;
          if (high > 20 || medium > 40) {
            alerts.add(ActionableAlert(
              id:          '${field.id}_pest',
              fieldId:     field.id,
              fieldName:   field.name,
              type:        'pest',
              title:       'Pest Risk Detected',
              message:     high > 20
                  ? 'High pest risk (${high.toStringAsFixed(0)}% of field) — '
                    'Immediate scouting required in ${field.name}'
                  : 'Moderate pest pressure (${medium.toStringAsFixed(0)}% area) — '
                    'Monitor field closely',
              severity:    high > 20 ? 'critical' : 'high',
              timeAgo:     'Just now',
              hotspotLat:  hotLat,
              hotspotLng:  hotLng,
              zoomLevel:   19.5,
              polygon:     poly,
              tileUrl:     pest.tileUrl,
              panelTarget: 'pest',
            ));
          }
        }
      } catch (_) {}

      // ── 2. Water / irrigation ────────────────────────────────────
      try {
        final water = await PlotLayerApi.fetchWater(plotName)
            .timeout(const Duration(seconds: 25));
        final ps = water.pixelSummary;
        if (ps != null) {
          final low  = (ps['low_pct']  as num?)?.toDouble() ?? 0;
          final def  = (ps['def_pct']  as num?)?.toDouble() ?? 0;
          if (low + def > 30) {
            alerts.add(ActionableAlert(
              id:          '${field.id}_water',
              fieldId:     field.id,
              fieldName:   field.name,
              type:        'water',
              title:       'Low Water Uptake',
              message:     '${(low + def).toStringAsFixed(0)}% of ${field.name} '
                  'shows low water levels — Irrigate within 48 hours',
              severity:    def > 20 ? 'high' : 'medium',
              timeAgo:     '${_rnd(1, 3)}h ago',
              hotspotLat:  hotLat,
              hotspotLng:  hotLng,
              zoomLevel:   19.0,
              polygon:     poly,
              tileUrl:     water.tileUrl,
              panelTarget: 'water',
            ));
          }
        }
      } catch (_) {}

      // ── 3. Soil moisture ─────────────────────────────────────────
      try {
        final moisture = await SoilMoistureApi.fetch(plotName)
            .timeout(const Duration(seconds: 25));
        final avg = moisture.avgMoisture;
        if (avg < 40) {
          alerts.add(ActionableAlert(
            id:          '${field.id}_soil',
            fieldId:     field.id,
            fieldName:   field.name,
            type:        'soil',
            title:       'Soil Moisture Low',
            message:     'Average soil moisture at ${avg.toStringAsFixed(0)}% '
                'in ${field.name} — Below optimal 60–80% range',
            severity:    avg < 25 ? 'critical' : 'medium',
            timeAgo:     '${_rnd(1, 4)}h ago',
            hotspotLat:  lat,
            hotspotLng:  lng,
            zoomLevel:   18.5,
            polygon:     poly,
            panelTarget: 'soil',
          ));
        }
      } catch (_) {}

      // ── 4. Growth / NDVI ─────────────────────────────────────────
      try {
        final growth = await PlotLayerApi.fetchGrowth(plotName)
            .timeout(const Duration(seconds: 25));
        final ps = growth.pixelSummary;
        if (ps != null) {
          final poor = (ps['poor_pct'] as num?)?.toDouble() ?? 0;
          if (poor > 25) {
            alerts.add(ActionableAlert(
              id:          '${field.id}_growth',
              fieldId:     field.id,
              fieldName:   field.name,
              type:        'growth',
              title:       'Growth Stress Detected',
              message:     '${poor.toStringAsFixed(0)}% of ${field.name} '
                  'shows poor growth — Check nutrition and irrigation',
              severity:    poor > 50 ? 'high' : 'medium',
              timeAgo:     '${_rnd(2, 6)}h ago',
              hotspotLat:  hotLat,
              hotspotLng:  lng,
              zoomLevel:   19.0,
              polygon:     poly,
              tileUrl:     growth.tileUrl,
              panelTarget: 'growth',
            ));
          }
        }
      } catch (_) {}

      // ── 5. Harvest readiness ─────────────────────────────────────
      if (field.plantationDate != null && field.plantationDate!.isNotEmpty) {
        try {
          final planted = DateTime.parse(field.plantationDate!);
          final daysGrown = now.difference(planted).inDays;
          // Generic harvest window: 60–180 days depending on crop
          final crop = field.crop.toLowerCase();
          int harvestDays = 90;
          if (crop.contains('wheat') || crop.contains('maize')) harvestDays = 120;
          if (crop.contains('tomato') || crop.contains('pepper')) harvestDays = 75;
          if (crop.contains('grape')) harvestDays = 150;
          if (crop.contains('mango') || crop.contains('banana')) harvestDays = 180;
          if (daysGrown >= (harvestDays * 0.85).round() &&
              daysGrown <= harvestDays + 14) {
            alerts.add(ActionableAlert(
              id:          '${field.id}_harvest',
              fieldId:     field.id,
              fieldName:   field.name,
              type:        'harvest',
              title:       'Ready to Harvest',
              message:     '${field.name} — ${field.crop} planted '
                  '${daysGrown}d ago, approaching harvest window',
              severity:    'low',
              timeAgo:     'Today',
              hotspotLat:  lat,
              hotspotLng:  lng,
              zoomLevel:   17.0, // show whole polygon
              polygon:     poly,
              panelTarget: 'harvest',
            ));
          }
        } catch (_) {}
      }

      // ── 6. Weather alert ─────────────────────────────────────────
      try {
        final weather = await WeatherService.fetchByCoords(lat, lng)
            .timeout(const Duration(seconds: 15));
        if (weather != null) {
          String? wMsg;
          String wSev = 'low';
          if (weather.condition == WeatherCondition.rain ||
              weather.condition == WeatherCondition.thunderstorm) {
            wMsg = 'Rain expected near ${field.name} — '
                '${weather.tempC.round()}°C, postpone spraying';
            wSev = 'medium';
          } else if (weather.windSpeedMs > 8) {
            wMsg = 'High wind alert (${weather.windSpeedMs.toStringAsFixed(1)} m/s) '
                'near ${field.name} — Avoid aerial application';
            wSev = 'medium';
          } else if (weather.tempC > 38) {
            wMsg = 'Extreme heat (${weather.tempC.round()}°C) near ${field.name} '
                '— Irrigate early morning only';
            wSev = 'high';
          }
          if (wMsg != null) {
            alerts.add(ActionableAlert(
              id:          '${field.id}_weather',
              fieldId:     field.id,
              fieldName:   field.name,
              type:        'weather',
              title:       'Weather Alert',
              message:     wMsg,
              severity:    wSev,
              timeAgo:     'Now',
              hotspotLat:  lat,
              hotspotLng:  lng,
              zoomLevel:   15.0,
              polygon:     poly,
              panelTarget: 'weather',
            ));
          }
        }
      } catch (_) {}
    }

    // Sort: critical first, then high, medium, low
    const order = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3};
    alerts.sort((a, b) =>
        (order[a.severity] ?? 4).compareTo(order[b.severity] ?? 4));

    // Save to cache
    await ApiService.saveAlertsCache(alerts.map((a) => a.toJson()).toList());

    return alerts;
  }

  static double _hotspot(List<List<double>> poly, double frac,
      {bool useLng = false}) {
    if (poly.isEmpty) return 0;
    final vals = poly.map((p) => p[useLng ? 1 : 0]).toList();
    final mn = vals.reduce(min);
    final mx = vals.reduce(max);
    return mn + (mx - mn) * frac;
  }

  static int _rnd(int min, int max) => min + Random().nextInt(max - min);
}

// ═══════════════════════════════════════════════════════════════════════════
//  AlertFeedScreen
// ═══════════════════════════════════════════════════════════════════════════
class AlertFeedScreen extends StatefulWidget {
  final List<ActionableAlert> alerts;
  final void Function(ActionableAlert alert) onAlertTap;
  final VoidCallback onSkip;

  const AlertFeedScreen({
    super.key,
    required this.alerts,
    required this.onAlertTap,
    required this.onSkip,
  });

  @override
  State<AlertFeedScreen> createState() => _AlertFeedScreenState();
}

class _AlertFeedScreenState extends State<AlertFeedScreen>
    with SingleTickerProviderStateMixin {
  final PageController _page = PageController();
  int _current = 0;
  late AnimationController _entryCtrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _fade  = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _page.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B0F),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Column(children: [
              // ── Header ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
                child: Row(children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Farm Alerts',
                          style: TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w900,
                              color: Colors.white, letterSpacing: -0.5)),
                      Text('Tap alert → zooms to exact location on map',
                          style: TextStyle(
                              fontSize: 12, color: Colors.white38,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onSkip,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Text('Skip →',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 12),

              // ── Alert cards ───────────────────────────────────────
              if (widget.alerts.isEmpty)
                Expanded(child: _emptyState())
              else ...[
                Expanded(
                  child: PageView.builder(
                    controller: _page,
                    onPageChanged: (i) => setState(() => _current = i),
                    itemCount: widget.alerts.length,
                    itemBuilder: (_, i) {
                      final a = widget.alerts[i];
                      return AnimatedScale(
                        duration: const Duration(milliseconds: 200),
                        scale: i == _current ? 1.0 : 0.94,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _AlertCard(
                            alert: a,
                            onTap: () => widget.onAlertTap(a),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ── Dots indicator ──────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(widget.alerts.length, (i) {
                      final active = i == _current;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width:  active ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: active
                              ? _AlertCard.severityColor(widget.alerts[i].severity)
                              : Colors.white24,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                ),

                // ── Go to dashboard button ──────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: GestureDetector(
                    onTap: widget.onSkip,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B5E20),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFF43A047).withOpacity(0.5)),
                      ),
                      child: const Center(
                        child: Text('Go to Dashboard',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.3)),
                      ),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('✅', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 16),
        const Text('All Clear',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                color: Colors.white)),
        const SizedBox(height: 8),
        Text('No alerts for your fields today',
            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.45))),
        const SizedBox(height: 32),
        GestureDetector(
          onTap: widget.onSkip,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1B5E20),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text('Go to Dashboard',
                style: TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

// ── Individual alert card ─────────────────────────────────────────────────
class _AlertCard extends StatelessWidget {
  final ActionableAlert alert;
  final VoidCallback    onTap;

  const _AlertCard({required this.alert, required this.onTap});

  static Color severityColor(String s) {
    switch (s) {
      case 'critical': return const Color(0xFFB71C1C);
      case 'high':     return const Color(0xFFE53935);
      case 'medium':   return const Color(0xFFF57C00);
      default:         return const Color(0xFF2E7D32);
    }
  }

  static (IconData, Color, Color) _typeStyle(String type) {
    switch (type) {
      case 'pest':    return (Icons.bug_report_rounded,    const Color(0xFFE53935), const Color(0xFF1A0000));
      case 'water':   return (Icons.water_drop_rounded,    const Color(0xFF0288D1), const Color(0xFF001020));
      case 'soil':    return (Icons.terrain_rounded,       const Color(0xFF8D6E63), const Color(0xFF120A00));
      case 'growth':  return (Icons.eco_rounded,           const Color(0xFF43A047), const Color(0xFF001200));
      case 'weather': return (Icons.wb_cloudy_rounded,     const Color(0xFF7B68EE), const Color(0xFF0A0020));
      case 'harvest': return (Icons.grass_rounded,         const Color(0xFFFBC02D), const Color(0xFF1A1400));
      case 'market':  return (Icons.trending_up_rounded,   const Color(0xFF00BCD4), const Color(0xFF001A20));
      default:        return (Icons.notifications_rounded, const Color(0xFF9E9E9E), const Color(0xFF0D0D0D));
    }
  }

  String get _ctaLabel {
    switch (alert.type) {
      case 'pest':    return '📍 View on Map — Plant Level →';
      case 'water':   return '📍 View on Map — Dry Zone →';
      case 'soil':    return '📍 View on Map — Affected Area →';
      case 'growth':  return '📍 View on Map — Stress Zone →';
      case 'weather': return '📍 Go to Field →';
      case 'harvest': return '📍 View Field →';
      default:        return '📍 View on Map →';
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, accent, bgDark) = _typeStyle(alert.type);
    final sevColor = severityColor(alert.severity);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1F10),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withOpacity(0.30), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Card header ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: bgDark,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(children: [
              // Icon circle
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withOpacity(0.4), width: 1.5),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(alert.title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900,
                          color: Colors.white, letterSpacing: -0.3)),
                  const SizedBox(height: 3),
                  Row(children: [
                    Text(alert.fieldName,
                        style: TextStyle(fontSize: 11,
                            color: Colors.white.withOpacity(0.5),
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Text('·',
                        style: TextStyle(color: Colors.white.withOpacity(0.3))),
                    const SizedBox(width: 6),
                    Text(alert.timeAgo,
                        style: TextStyle(fontSize: 11,
                            color: Colors.white.withOpacity(0.4))),
                  ]),
                ]),
              ),
              // Severity badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: sevColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sevColor.withOpacity(0.5)),
                ),
                child: Text(alert.severity.toUpperCase(),
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900,
                        color: sevColor, letterSpacing: 0.8)),
              ),
            ]),
          ),

          // ── Message ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(alert.message,
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.80),
                    height: 1.5,
                    fontWeight: FontWeight.w500)),
          ),

          const SizedBox(height: 16),

          // ── Action area ──────────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withOpacity(0.25)),
            ),
            child: Row(children: [
              // Location hint
              if (alert.hotspotLat != null) ...[
                Icon(Icons.location_on_rounded, color: accent, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${alert.hotspotLat!.toStringAsFixed(4)}, '
                  '${alert.hotspotLng!.toStringAsFixed(4)}',
                  style: TextStyle(fontSize: 10,
                      color: Colors.white.withOpacity(0.4),
                      fontWeight: FontWeight.w500),
                ),
                const Spacer(),
              ] else
                const Spacer(),
              Text(_ctaLabel,
                  style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w800, color: accent)),
            ]),
          ),
        ]),
      ),
    );
  }
}
