import 'dart:math' show Random, pi, sin, cos;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../constants/app_constants.dart';
import '../services/weather_service.dart';
import '../services/plot_layer_api.dart';
import '../services/soil_param_api.dart';
import 'ai_recommendation_centre.dart';
import 'alert_feed_screen.dart' show ActionableAlert;

// ═══════════════════════════════════════════════════════════════════════════
//  FARM INSIGHTS  —  Live data from PlotLayerApi + WeatherService
// ═══════════════════════════════════════════════════════════════════════════

class InsightsFullScreen extends StatefulWidget {
  final SoilData soilData;
  final double? fieldLat;
  final double? fieldLon;
  final String? plotName;
  /// 'moisture' | 'water' | 'pest' | null
  final String? initialSection;
  /// Full field model — used to open AI Recommendation Centre
  final FieldModel? field;
  /// Actionable alerts passed through to AI Recommendation Centre
  final List<ActionableAlert> actionableAlerts;

  const InsightsFullScreen({
    super.key,
    required this.soilData,
    this.fieldLat,
    this.fieldLon,
    this.plotName,
    this.initialSection,
    this.field,
    this.actionableAlerts = const [],
  });

  @override
  State<InsightsFullScreen> createState() => _InsightsFullScreenState();
}

class _InsightsFullScreenState extends State<InsightsFullScreen>
    with TickerProviderStateMixin {

  // ── Live data ─────────────────────────────────────────────────────────────
  WeatherData?        _weather;
  PlotLayerResponse?  _waterData;   // irrigation / NDWI
  PlotLayerResponse?  _pestData;    // pest analysis
  SoilNpkResult?      _npkData;     // nitrogen, phosphorus, potassium
  SoilAnalysisResult? _analysisData;// pH, CEC, OC
  bool _weatherLoading  = true;
  bool _waterLoading    = true;
  bool _pestLoading     = true;
  bool _nutrientLoading = true;
  String? _waterError;
  String? _pestError;

  // ── Soil moisture API state ─────────────────────────────────────────────
  SoilMoistureResult? _soilMoisture;
  bool _soilLoading = true;
  String? _soilError;

  // Drag-to-dismiss
  double _dragOffset = 0;
  bool _isDragging = false;

  // Entry animations
  late AnimationController _entryCtrl;
  late List<Animation<double>> _fadeAnims;
  late List<Animation<Offset>> _slideAnims;
  late AnimationController _counterCtrl;
  int? _touchedIndex;
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _soilSummaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadAll();
    _entryCtrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1000))..forward();
    _fadeAnims = List.generate(8, (i) {
      final s = i * 0.10, e = (s + 0.45).clamp(0.0, 1.0);
      return Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(parent: _entryCtrl,
              curve: Interval(s, e, curve: Curves.easeOut)));
    });
    _slideAnims = List.generate(8, (i) {
      final s = i * 0.10, e = (s + 0.45).clamp(0.0, 1.0);
      return Tween<Offset>(begin: const Offset(0, 0.22), end: Offset.zero)
          .animate(CurvedAnimation(parent: _entryCtrl,
          curve: Interval(s, e, curve: Curves.easeOutCubic)));
    });
    _counterCtrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1500))..forward();

    // Auto-open detail screen if coming from popup tap
    if (widget.initialSection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          final insights = _buildInsights();
          Map<String, dynamic>? target;
          switch (widget.initialSection) {
            case 'water':   target = insights[0]; break; // Irrigation Depth Analysis
            case 'pest':    target = insights[1]; break; // Entomological Forecast
            case 'moisture': // Soil Summary — scroll to the soil moisture chart
              Future.delayed(const Duration(milliseconds: 800), () {
                if (!mounted) return;
                final ctx = _soilSummaryKey.currentContext;
                if (ctx != null) {
                  Scrollable.ensureVisible(ctx,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                  );
                }
              });
              break;
          }
          if (target != null) _openDetailScreen(context, target);
        });
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _entryCtrl.dispose();
    _counterCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final lat  = widget.fieldLat ?? 20.5937;
    final lon  = widget.fieldLon ?? 78.9629;
    final plot = widget.plotName ?? '';

    // Soil moisture (SAR Index Mapping API)
    _loadSoilMoisture();

    // Weather (for Micro-Climate)
    WeatherService.fetchByCoords(lat, lon).then((d) {
      if (mounted) setState(() { _weather = d; _weatherLoading = false; });
    }).catchError((_) {
      if (mounted) setState(() { _weatherLoading = false; });
    });

    // Water uptake → Irrigation Depth Analysis
    if (plot.isNotEmpty) {
      PlotLayerApi.fetchWater(plot).then((r) {
        if (mounted) setState(() { _waterData = r; _waterLoading = false; });
      }).catchError((e) {
        if (mounted) setState(() { _waterError = e.toString(); _waterLoading = false; });
      });

      // Nutrient Uptake → POST /required-n/{plot_name} + /analyze-npk/{plot_name}
      final today = DateTime.now().toString().split(' ')[0];
      SoilParamApi.fetchNpk(plotName: plot, endDate: today).then((r) {
        if (mounted) setState(() { _npkData = r; });
      }).catchError((_) {});
      SoilParamApi.fetchAnalysis(plotName: plot, date: today).then((r) {
        if (mounted) setState(() { _analysisData = r; _nutrientLoading = false; });
      }).catchError((_) {
        if (mounted) setState(() => _nutrientLoading = false);
      });

      // Pest detection → Entomological Forecast
      PlotLayerApi.fetchPest(plot,
          DateTime.now().toString().split(' ')[0]).then((r) {
        if (mounted) setState(() { _pestData = r; _pestLoading = false; });
      }).catchError((e) {
        if (mounted) setState(() { _pestError = e.toString(); _pestLoading = false; });
      });
    } else {
      setState(() { _waterLoading = false; _pestLoading = false; });
    }
  }

  // ── Extract mean value [0-1] from a PlotLayerResponse ───────────────────
  // ── Water uptake score from pixel_summary ─────────────────────────────
  // The /wateruptake API returns pixel counts by moisture category:
  //   deficient  → critically low (weight: 0.0)
  //   less        → low moisture   (weight: 0.25)
  //   adequat     → adequate       (weight: 0.75)
  //   excellent   → excellent      (weight: 1.0)
  //   excess      → waterlogged    (weight: 0.5  — too much is also bad)
  // We compute a weighted score 0→1.
  double _extractWaterScore(PlotLayerResponse? r) {
    if (r == null) return 0.35;
    final ps = r.pixelSummary;
    if (ps == null) return 0.35;

    final defPct  = (ps['deficient_pixel_percentage'] as num?)?.toDouble() ?? 0;
    final lessPct = (ps['less_pixel_percentage']       as num?)?.toDouble() ?? 0;
    final adqPct  = (ps['adequat_pixel_percentage']    as num?)?.toDouble() ?? 0;
    final excPct  = (ps['excellent_pixel_percentage']  as num?)?.toDouble() ?? 0;
    final exsPct  = (ps['excess_pixel_percentage']     as num?)?.toDouble() ?? 0;

    final total = defPct + lessPct + adqPct + excPct + exsPct;
    if (total <= 0) return 0.35;

    final score = (defPct * 0.0 + lessPct * 0.25 +
                   adqPct * 0.75 + excPct * 1.0 + exsPct * 0.5) / total;
    return score.clamp(0.0, 1.0);
  }

  // ── Detailed water pixel counts ─────────────────────────────────────────
  Map<String, double> _extractWaterPixelPcts(PlotLayerResponse? r) {
    if (r?.pixelSummary == null) return {};
    final ps = r!.pixelSummary!;
    return {
      'deficient': (ps['deficient_pixel_percentage'] as num?)?.toDouble() ?? 0,
      'less':      (ps['less_pixel_percentage']       as num?)?.toDouble() ?? 0,
      'adequat':   (ps['adequat_pixel_percentage']    as num?)?.toDouble() ?? 0,
      'excellent': (ps['excellent_pixel_percentage']  as num?)?.toDouble() ?? 0,
      'excess':    (ps['excess_pixel_percentage']     as num?)?.toDouble() ?? 0,
      'total':     (ps['total_pixel_count']           as num?)?.toDouble() ?? 0,
    };
  }

  double _extractMean(PlotLayerResponse? r, {double fallback = 0.5}) {
    if (r == null) return fallback;
    final ps = r.pixelSummary;
    if (ps != null) {
      // Check for pest-style risk/score fields
      for (final k in ['mean','avg','average','value','score','pest_score','risk']) {
        if (ps[k] is num) return (ps[k] as num).toDouble().clamp(0.0, 1.0);
      }
    }
    final features = r.raw['features'];
    if (features is List && features.isNotEmpty) {
      double sum = 0; int cnt = 0;
      for (final f in features) {
        final props = f['properties'];
        if (props is Map) {
          for (final k in ['value','mean','score','pest_score','risk']) {
            if (props[k] is num) { sum += (props[k] as num).toDouble(); cnt++; break; }
          }
        }
      }
      if (cnt > 0) return (sum / cnt).clamp(0.0, 1.0);
    }
    return fallback;
  }

  // ── Extract zone values list from PlotLayerResponse ──────────────────────
  List<double> _extractZoneValues(PlotLayerResponse? r, int count, {double fallback = 0.5}) {
    if (r == null) return List.generate(count, (_) => fallback);
    final features = r.raw['features'];
    if (features is List && features.isNotEmpty) {
      final vals = <double>[];
      for (final f in features) {
        final props = f['properties'];
        if (props is Map) {
          for (final k in ['value','mean','score','ndwi','pest_score']) {
            if (props[k] is num) { vals.add((props[k] as num).toDouble().clamp(0.0, 1.0)); break; }
          }
        }
      }
      if (vals.isNotEmpty) return vals.take(count).toList();
    }
    return List.generate(count, (i) => (fallback + (i - count/2) * 0.05).clamp(0.0, 1.0));
  }

  Future<void> _loadSoilMoisture() async {
    final plot = widget.plotName;
    if (plot == null || plot.isEmpty) {
      if (mounted) setState(() { _soilLoading = false; });
      return;
    }
    try {
      final result = await SoilMoistureApi.fetch(plot);
      if (mounted) setState(() { _soilMoisture = result; _soilLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _soilError = e.toString(); _soilLoading = false; });
    }
  }

  // ── Build insights list from live data ───────────────────────────────────
  List<Map<String, dynamic>> _buildInsights() {
    final waterVal = _extractWaterScore(_waterData);
    final pestVal  = _extractMean(_pestData,  fallback: 0.85);
    final tempC    = _weather?.tempC ?? 29.0;
    final windMs   = _weather?.windSpeedMs ?? 4.0;
    final humidity = _weather?.humidity ?? 65;

    // Water / Irrigation
    final waterPcts = _extractWaterPixelPcts(_waterData);
    final defPct  = waterPcts['deficient'] ?? 0;
    final lessPct = waterPcts['less']      ?? 0;
    final adqPct  = waterPcts['adequat']   ?? 0;
    final excPct  = waterPcts['excellent'] ?? 0;
    final exsPct  = waterPcts['excess']    ?? 0;
    final totalPx = (waterPcts['total'] ?? 0).toInt();

    String waterStatus, waterDetail, waterAction;
    Color waterStatusColor;
    if (waterVal < 0.3) {
      waterStatus = 'LOW';
      waterStatusColor = const Color(0xFF0288D1);
      waterDetail = 'Satellite analysis of ${totalPx > 0 ? "$totalPx pixels" : "your field"} shows '
          '${lessPct.toStringAsFixed(1)}% of the field has LOW moisture and '
          '${defPct.toStringAsFixed(1)}% is DEFICIENT. '
          'Only ${adqPct.toStringAsFixed(1)}% has adequate water. Root zone stress is building.';
      waterAction = 'Immediate irrigation required — ${((1.0 - waterVal) * 25).round()}mm recommended. '
          'Target deficient zones first. Schedule during evening (5–7 PM) for best uptake.';
    } else if (waterVal < 0.6) {
      waterStatus = 'MODERATE';
      waterStatusColor = const Color(0xFF0288D1);
      waterDetail = 'Field moisture analysis: ${adqPct.toStringAsFixed(1)}% adequate, '
          '${lessPct.toStringAsFixed(1)}% low, ${defPct.toStringAsFixed(1)}% deficient '
          '(${totalPx > 0 ? "$totalPx pixels analysed" : "satellite data"}). '
          'Moisture trending downward — monitor closely.';
      waterAction = 'Light irrigation (8–12mm) within 48 hours. '
          'Prioritise zones with less/deficient moisture. Avoid overwatering adequate zones.';
    } else if (exsPct > 20) {
      waterStatus = 'EXCESS';
      waterStatusColor = const Color(0xFF1565C0);
      waterDetail = 'Field shows ${exsPct.toStringAsFixed(1)}% excess moisture and '
          '${adqPct.toStringAsFixed(1)}% adequate levels. '
          'Risk of waterlogging and root rot in excess zones.';
      waterAction = 'Stop irrigation immediately. Check and clear drainage channels. '
          'Monitor for fungal disease in waterlogged areas.';
    } else {
      waterStatus = 'ADEQUATE';
      waterStatusColor = const Color(0xFF2E7D32);
      waterDetail = 'Field is well-hydrated: ${adqPct.toStringAsFixed(1)}% adequate + '
          '${excPct.toStringAsFixed(1)}% excellent moisture '
          '(${totalPx > 0 ? "$totalPx pixels" : "satellite analysis"}). '
          'Crop water uptake is healthy.';
      waterAction = 'No irrigation needed today. Recheck in 2–3 days. '
          'Maintain drainage channels to prevent waterlogging.';
    }

    // Pest
    String pestStatus, pestDetail, pestAction;
    Color pestStatusColor;
    if (pestVal > 0.7) {
      pestStatus = 'HIGH';
      pestStatusColor = const Color(0xFFD32F2F);
      pestDetail = 'Pest detection analysis shows high risk score of ${(pestVal * 100).round()}%. Heat index (${tempC.round()}°C) creates favourable conditions for Aphids and Whitefly infestations.';
      pestAction = 'Immediate scouting required. Apply neem oil spray if pest density exceeds threshold. Target field boundaries first.';
    } else if (pestVal > 0.4) {
      pestStatus = 'MODERATE';
      pestStatusColor = const Color(0xFFF57C00);
      pestDetail = 'Pest risk at ${(pestVal * 100).round()}% — moderate concern. Current temperature (${tempC.round()}°C) supports pest activity.';
      pestAction = 'Inspect field weekly. Prepare preventive biological controls. Avoid pesticide application during high wind periods.';
    } else {
      pestStatus = 'LOW';
      pestStatusColor = const Color(0xFF2E7D32);
      pestDetail = 'Pest detection shows low activity — risk score ${(pestVal * 100).round()}%. Current conditions are unfavourable for major infestations.';
      pestAction = 'Continue routine monitoring. Maintain beneficial insect habitats at field margins.';
    }

    // Weather / Micro-Climate
    String climateStatus, climateDetail, climateAction;
    Color climateStatusColor;
    final wCond = _weather?.condition ?? WeatherCondition.clearDay;
    if (wCond == WeatherCondition.rain || wCond == WeatherCondition.thunderstorm) {
      climateStatus = 'WET';
      climateStatusColor = const Color(0xFF0288D1);
      climateDetail = 'Active precipitation detected. Humidity ${humidity}%, wind ${windMs.toStringAsFixed(1)} m/s. Field operations will be disrupted.';
      climateAction = 'Postpone foliar spraying and harvest operations. Check drainage. Resume after 24h dry period.';
    } else if (windMs > 8) {
      climateStatus = 'WINDY';
      climateStatusColor = const Color(0xFFF57C00);
      climateDetail = 'Wind speed ${windMs.toStringAsFixed(1)} m/s — above safe spray threshold. Temperature ${tempC.round()}°C, humidity ${humidity}%.';
      climateAction = 'Delay pesticide/fertiliser spraying. Secure drip irrigation pipes and covers. Monitor crop lodging risk.';
    } else if (tempC > 38) {
      climateStatus = 'HOT';
      climateStatusColor = const Color(0xFFD32F2F);
      climateDetail = 'Extreme temperature ${tempC.round()}°C detected. High evapotranspiration rates. Humidity ${humidity}%.';
      climateAction = 'Irrigate in early morning (5–7 AM) only. Avoid any field work between 11 AM–3 PM. Monitor heat stress on crops.';
    } else {
      climateStatus = 'FAIR';
      climateStatusColor = const Color(0xFFF57C00);
      climateDetail = 'Favourable micro-climate: ${tempC.round()}°C, humidity ${humidity}%, wind ${windMs.toStringAsFixed(1)} m/s. Clear skies forecast next 48 hours.';
      climateAction = 'Optimal window for foliar application tomorrow 6–10 AM before temperatures rise. Low wind drift risk.';
    }

    return [
      {
        'label': 'Water',
        'status': waterStatus,
        'statusColor': waterStatusColor,
        'bg': const Color(0xFFE3F2FD),
        'icon': '💧',
        'color': const Color(0xFF0288D1),
        'gradColors': [const Color(0xFF0288D1), const Color(0xFF29B6F6)],
        'progress': waterVal,
        'title': 'Irrigation Depth Analysis',
        'detail': waterDetail,
        'action': waterAction,
        'rawValue': waterVal,
        'loading': _waterLoading,
        'apiType': 'water',
      },
      {
        'label': 'Pest Risk',
        'status': pestStatus,
        'statusColor': pestStatusColor,
        'bg': const Color(0xFFFFEBEE),
        'icon': '🪲',
        'color': const Color(0xFFD32F2F),
        'gradColors': [const Color(0xFFD32F2F), const Color(0xFFEF5350)],
        'progress': pestVal,
        'title': 'Entomological Forecast',
        'detail': pestDetail,
        'action': pestAction,
        'rawValue': pestVal,
        'loading': _pestLoading,
        'apiType': 'pest',
      },
      () {
        // ── Nutrient Uptake — live from Soil Parameter Analysis API ──────
        final soilN = _npkData?.soilN ?? widget.soilData.nitrogen;
        final soilP = _npkData?.soilP ?? widget.soilData.phosphorus;
        final soilK = _npkData?.soilK ?? widget.soilData.potassium;
        final ph    = _analysisData?.ph  ?? widget.soilData.ph;
        final oc    = _analysisData?.oc  ?? widget.soilData.oc;

        // Normalise N (0–500), P (0–200), K (0–400) to 0–1 and average
        final nFrac = (soilN / 500.0).clamp(0.0, 1.0);
        final pFrac = (soilP / 200.0).clamp(0.0, 1.0);
        final kFrac = (soilK / 400.0).clamp(0.0, 1.0);
        final progress = (nFrac * 0.5 + pFrac * 0.3 + kFrac * 0.2);

        String status; Color statusColor; String detail; String action;
        if (progress > 0.70) {
          status = 'RICH'; statusColor = const Color(0xFF1B5E20);
          detail = 'Soil nutrients are abundant — N: ${soilN.toStringAsFixed(1)} kg/ha, '
              'P: ${soilP.toStringAsFixed(1)} kg/ha, K: ${soilK.toStringAsFixed(1)} kg/ha. '
              'pH ${ph.toStringAsFixed(1)} is ${ph >= 6.0 && ph <= 7.5 ? "optimal" : "out of range"}. '
              'OC: ${oc.toStringAsFixed(2)}%.';
          action = 'Nutrients are at healthy levels. Maintain with standard schedule. '
              'Monitor pH and avoid over-fertilisation.';
        } else if (progress > 0.40) {
          status = 'READY'; statusColor = const Color(0xFF2E7D32);
          detail = 'Moderate nutrient levels — N: ${soilN.toStringAsFixed(1)} kg/ha, '
              'P: ${soilP.toStringAsFixed(1)} kg/ha, K: ${soilK.toStringAsFixed(1)} kg/ha. '
              'pH ${ph.toStringAsFixed(1)}. OC: ${oc.toStringAsFixed(2)}%.';
          action = 'Consider Nitrogen top-dressing (Urea 46%) within 7 days. '
              'Potassium supplement recommended if K < 80 kg/ha.';
        } else {
          status = 'LOW'; statusColor = const Color(0xFFF57F17);
          detail = 'Low nutrient levels detected — N: ${soilN.toStringAsFixed(1)} kg/ha, '
              'P: ${soilP.toStringAsFixed(1)} kg/ha, K: ${soilK.toStringAsFixed(1)} kg/ha. '
              'Immediate intervention required. pH ${ph.toStringAsFixed(1)}.';
          action = 'Apply NPK fertiliser immediately (20:20:20). '
              'Schedule soil amendment for pH correction if outside 6.0–7.5 range.';
        }

        return {
          'label': 'Fertilizer',
          'status': status,
          'statusColor': statusColor,
          'bg': const Color(0xFFE8F5E9),
          'icon': '🌾',
          'color': const Color(0xFF2E7D32),
          'gradColors': [const Color(0xFF2E7D32), const Color(0xFF66BB6A)],
          'progress': progress,
          'title': 'Nutrient Uptake Status',
          'detail': detail,
          'action': action,
          'rawValue': progress,
          'loading': _nutrientLoading,
          'apiType': 'nutrient',
        };
      }(),
      {
        'label': 'Weather',
        'status': climateStatus,
        'statusColor': climateStatusColor,
        'bg': const Color(0xFFFFF3E0),
        'icon': _weather == null ? '🌤' : _weatherIcon(_weather!.condition),
        'color': const Color(0xFFF57C00),
        'gradColors': [const Color(0xFFF57C00), const Color(0xFFFFB74D)],
        'progress': _weatherProgress(_weather),
        'title': 'Micro-Climate Window',
        'detail': climateDetail,
        'action': climateAction,
        'rawValue': _weatherProgress(_weather),
        'loading': _weatherLoading,
        'apiType': 'weather',
        'weather': _weather,
      },
    ];
  }

  String _weatherIcon(WeatherCondition c) {
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

  double _weatherProgress(WeatherData? w) {
    if (w == null) return 0.55;
    if (w.condition == WeatherCondition.rain || w.condition == WeatherCondition.thunderstorm) return 0.2;
    if (w.windSpeedMs > 8) return 0.45;
    if (w.tempC > 38) return 0.3;
    return 0.75;
  }

  // ── Recommendations banner ────────────────────────────────────────────────
  List<Map<String, dynamic>> _buildRecommendations() {
    final insights = _buildInsights();
    return [
      {
        'icon': '💧',
        'title': 'Irrigation Alert',
        'text': insights[0]['action'],
        'priority': 'urgent',
        'color': const Color(0xFF0288D1),
      },
      {
        'icon': '🐛',
        'title': 'Pest Activity',
        'text': insights[1]['action'],
        'priority': 'high',
        'color': const Color(0xFFD32F2F),
      },
      {
        'icon': '🌾',
        'title': 'Fertilizer Ready',
        'text': insights[2]['action'],
        'priority': 'medium',
        'color': const Color(0xFF2E7D32),
      },
      {
        'icon': '☀️',
        'title': 'Climate Window',
        'text': insights[3]['action'],
        'priority': 'low',
        'color': const Color(0xFFF57C00),
      },
    ];
  }

  void _close() => Navigator.of(context).pop();

  void _openDetailScreen(BuildContext context, Map<String, dynamic> insight) {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, __, ___) => _FieldDetailScreen(
        insight:      insight,
        weather:      _weather,
        soilData:     widget.soilData,
        waterData:    _waterData,
        pestData:     _pestData,
        npkData:      _npkData,
        analysisData: _analysisData,
        plotName:     widget.plotName ?? '',
      ),
      transitionsBuilder: (_, anim, __, page) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(curve),
          child: page,
        );
      },
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 280),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final topPad = MediaQuery.of(context).padding.top;
    final insights = _buildInsights();
    final recs     = _buildRecommendations();

    return GestureDetector(
      onVerticalDragStart: (_) => setState(() => _isDragging = true),
      onVerticalDragUpdate: (d) {
        if (d.delta.dy > 0) setState(() => _dragOffset += d.delta.dy);
      },
      onVerticalDragEnd: (_) {
        if (_dragOffset > 120) { _close(); return; }
        setState(() { _dragOffset = 0; _isDragging = false; });
      },
      child: Transform.translate(
        offset: Offset(0, _dragOffset * 0.4),
        child: Scaffold(
          backgroundColor: const Color(0xFFF0F4F0),
          body: CustomScrollView(controller: _scrollCtrl, slivers: [
            // ── Sticky header ───────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              expandedHeight: 100,
              backgroundColor: AppColors.primary,
              elevation: 0,
              automaticallyImplyLeading: false,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(20, topPad + 4, 20, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end, children: [
                    Row(children: [
                      GestureDetector(
                        onTap: _close,
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.18),
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 18),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Farm Insights', style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w900,
                              color: Colors.white, height: 1.1)),
                          Text('AI-powered field intelligence · Live data',
                              style: TextStyle(fontSize: 11,
                                  color: Colors.white60, fontWeight: FontWeight.w600)),
                        ],
                      )),
                      Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(Icons.refresh_rounded,
                            color: Colors.white, size: 18),
                      ).also(() {}),
                    ]),
                  ]),
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(0),
                child: Container(
                  height: 4,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0F4F0),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              sliver: SliverList(delegate: SliverChildListDelegate([

                // ── Field Analysis Grid ──────────────────────────────────
                _buildSectionHeader(0, 'Field Analysis', 'Tap for deep dive'),
                const SizedBox(height: 10),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, crossAxisSpacing: 8,
                    mainAxisSpacing: 8, childAspectRatio: 1.65,
                  ),
                  itemCount: insights.length,
                  itemBuilder: (_, i) => _FieldAnalysisCard(
                    data: insights[i],
                    onTap: () => _openDetailScreen(context, insights[i]),
                  ),
                ),

                const SizedBox(height: 24),

                // ── AI Recommendations → opens AI Recommendation Centre ──
                _buildSectionHeader(1, 'AI Recommendations', 'Prioritised actions'),
                const SizedBox(height: 10),

                // Show preview tiles
                ...recs.asMap().entries.map((e) =>
                    _buildRecommendationTile(e.value, e.key + 2)),

                const SizedBox(height: 12),

                // Open full AI Recommendation Centre button
                if (widget.field != null)
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => AiRecommendationCentre(
                        field:   widget.field!,
                        alerts:  widget.actionableAlerts,
                        onClose: () => Navigator.of(context).pop(),
                      )),
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7B1FA2).withOpacity(0.35),
                            blurRadius: 12, offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.auto_awesome_rounded,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          const Text('Open AI Recommendation Centre',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.3)),
                          if (widget.actionableAlerts.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('${widget.actionableAlerts.length}',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // ── Soil summary ─────────────────────────────────────────
                _buildSectionHeader(4, 'Soil Summary', '', key: _soilSummaryKey),
                const SizedBox(height: 10),
                _buildSoilTrendsGraph(),

              ])),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(int animIdx, String title, String sub, {Key? key}) {
    final idx = animIdx.clamp(0, _fadeAnims.length - 1);
    return FadeTransition(
      key: key,
      opacity: _fadeAnims[idx],
      child: SlideTransition(
        position: _slideAnims[idx],
        child: Row(children: [
          Text(title, style: const TextStyle(fontSize: 16,
              fontWeight: FontWeight.w900, color: AppColors.textDark)),
          if (sub.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.greenLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(sub, style: const TextStyle(fontSize: 9,
                  fontWeight: FontWeight.w700, color: AppColors.primary,
                  letterSpacing: 0.3)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildRecommendationTile(Map<String, dynamic> rec, int animIdx) {
    final idx = animIdx.clamp(0, _fadeAnims.length - 1);
    final color = rec['color'] as Color;
    return FadeTransition(
      opacity: _fadeAnims[idx],
      child: SlideTransition(
        position: _slideAnims[idx],
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.15)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
                blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: Text(rec['icon'] as String,
                  style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rec['title'] as String, style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800,
                  color: AppColors.textDark)),
              const SizedBox(height: 3),
              Text(rec['text'] as String, style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w500,
                  color: AppColors.textMedium, height: 1.4),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text((rec['priority'] as String).toUpperCase(),
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900,
                      color: color, letterSpacing: 0.5)),
            ),
          ]),
        ),
      ),
    );
  }

  // ── 2. Soil Moisture Levels Graph (live API data) ──────────────────────────

  Widget _buildSoilTrendsGraph() {
    // ── Loading skeleton ────────────────────────────────────────────────────
    if (_soilLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          height: 260,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 16, offset: const Offset(0, 5))],
          ),
          child: const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Color(0xFF0288D1))),
              SizedBox(height: 12),
              Text('Fetching soil moisture data…',
                  style: TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w600, color: Color(0xFF555555))),
            ]),
          ),
        ),
      );
    }

    // ── Resolve data source ─────────────────────────────────────────────────
    final List<double> moistureData;
    final List<String> dateLabels;
    final List<double> rainfallData;
    bool isLive = false;
    String footerSource;

    if (_soilMoisture != null && _soilMoisture!.stack.isNotEmpty) {
      final stack = _soilMoisture!.stack;
      moistureData = stack.map((d) => d.soilMoisture).toList();
      dateLabels   = stack.map((d) => d.shortLabel).toList();
      rainfallData = stack.map((d) => d.rainfallMm).toList();
      isLive       = true;
      footerSource = 'SAR Index Mapping API · plot ${_soilMoisture!.plotName}';
    } else {
      final baseMoisture = widget.soilData.moisture.clamp(0.0, 100.0);
      final rng = Random(42);
      moistureData = List.generate(7, (i) =>
          (baseMoisture + (rng.nextDouble() - 0.3) * 4.0 * (7 - i) / 7)
              .clamp(0.0, 100.0));
      final now = DateTime.now();
      dateLabels = List.generate(7, (i) {
        final d = now.subtract(Duration(days: 6 - i));
        return '${d.day}/${d.month}';
      });
      rainfallData = List.filled(7, 0.0);
      footerSource = _soilError != null
          ? 'Fallback · API unavailable'
          : 'Open-Meteo Soil API';
    }

    final avg = moistureData.isEmpty
        ? 0.0
        : moistureData.reduce((a, b) => a + b) / moistureData.length;

    String statusLabel;
    Color statusColor;
    if (avg < 40)      { statusLabel = 'LOW';  statusColor = const Color(0xFFD32F2F); }
    else if (avg < 80) { statusLabel = 'GOOD'; statusColor = const Color(0xFF2E7D32); }
    else               { statusLabel = 'HIGH'; statusColor = const Color(0xFF0288D1); }

    final hasRain = rainfallData.any((r) => r > 0);

    // ── Y-axis: snap to clean multiples of 5 so labels are always round ──────
    // Example: data 79.6–80.7 → rawMin=69.6→snappedMin=65, rawMax=90.7→snappedMax=90
    // Gives interval=5 → labels: 65, 70, 75, 80, 85, 90 — clean, no overlaps.
    final dataMin = moistureData.reduce((a, b) => a < b ? a : b);
    final dataMax = moistureData.reduce((a, b) => a > b ? a : b);
    final dataRange = (dataMax - dataMin).clamp(5.0, 100.0);
    // Padding: 20% of range on each side, min 3, max 8
    final pad = (dataRange * 0.20).clamp(3.0, 8.0);
    // Snap down to nearest 5
    final rawMin = dataMin - pad;
    final rawMax = dataMax + pad;
    final minY = ((rawMin / 5).floor() * 5.0).clamp(0.0, 90.0);
    final maxY = ((rawMax / 5).ceil() * 5.0).clamp(10.0, 100.0);
    // Interval: aim for 4-6 labels — pick 5 for tight ranges, 10 for wider
    final yInterval = (maxY - minY) <= 20 ? 5.0 : 10.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 20, offset: const Offset(0, 6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Header row ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0288D1), Color(0xFF29B6F6)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(
                      color: const Color(0xFF0288D1).withOpacity(0.35),
                      blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: const Icon(Icons.water_drop_rounded,
                    color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Soil Moisture Levels',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900,
                        color: Color(0xFF1A237E))),
                Row(children: [
                  const Text('Optimal: 60–80%',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                          color: Color(0xFF888888))),
                  if (isLive) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D32).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFF2E7D32).withOpacity(0.35)),
                      ),
                      child: const Text('LIVE',
                          style: TextStyle(fontSize: 8,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF2E7D32), letterSpacing: 0.8)),
                    ),
                  ],
                ]),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.30)),
                ),
                child: Text(statusLabel,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                        color: statusColor, letterSpacing: 0.5)),
              ),
            ]),
          ),

          // ── Legend (compact, one row) ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Wrap(spacing: 12, runSpacing: 4, children: [
              _moistureLegend('Low <40%',  const Color(0xFFEF5350)),
              _moistureLegend('Good 40–80%', const Color(0xFF1565C0)),
              _moistureLegend('High >80%',  const Color(0xFF0288D1)),
              if (hasRain) _moistureLegend('Rain',  const Color(0xFF7B1FA2)),
            ]),
          ),

          const SizedBox(height: 12),

          // ── Main chart — moisture line only, clean and readable ──────────
          SizedBox(
            height: 200,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, right: 12, bottom: 0),
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  clipData: const FlClipData.all(),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    handleBuiltInTouches: true,
                    touchCallback: (evt, resp) {
                      setState(() => _touchedIndex =
                          resp?.lineBarSpots?.firstOrNull?.spotIndex);
                    },
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF1A237E),
                      tooltipRoundedRadius: 10,
                      tooltipPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      getTooltipItems: (spots) => spots.map((s) =>
                        LineTooltipItem(
                          '${s.y.toStringAsFixed(1)}%',
                          const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w900, fontSize: 12),
                        )).toList(),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: yInterval,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: Colors.grey.withOpacity(0.10),
                            strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: yInterval,
                        reservedSize: 40,
                        getTitlesWidget: (v, _) {
                          // Only show labels that sit on clean multiples of yInterval
                          if (v < minY || v > maxY) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              '${v.toInt()}%',
                              style: const TextStyle(fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF999999)),
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        reservedSize: 26,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= dateLabels.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(dateLabels[i],
                                style: const TextStyle(fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF666666))),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      bottom: BorderSide(
                          color: Colors.grey.withOpacity(0.20), width: 1),
                      left: BorderSide(
                          color: Colors.grey.withOpacity(0.20), width: 1),
                    ),
                  ),
                  extraLinesData: ExtraLinesData(horizontalLines: [
                    // Only draw threshold lines if they fall within the visible Y range
                    if (80 >= minY && 80 <= maxY)
                      HorizontalLine(
                        y: 80,
                        color: const Color(0xFF0288D1).withOpacity(0.40),
                        strokeWidth: 1.2, dashArray: [6, 4],
                      ),
                    if (40 >= minY && 40 <= maxY)
                      HorizontalLine(
                        y: 40,
                        color: const Color(0xFFEF5350).withOpacity(0.40),
                        strokeWidth: 1.2, dashArray: [6, 4],
                      ),
                  ]),
                  lineBarsData: [
                    // ── Soil moisture line ─────────────────────────────────
                    LineChartBarData(
                      spots: List.generate(moistureData.length,
                          (i) => FlSpot(i.toDouble(), moistureData[i])),
                      isCurved: true,
                      curveSmoothness: 0.35,
                      color: const Color(0xFF1565C0),
                      barWidth: 3,
                      shadow: const Shadow(
                          color: Color(0x331565C0), blurRadius: 6,
                          offset: Offset(0, 3)),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF42A5F5).withOpacity(0.28),
                            const Color(0xFF42A5F5).withOpacity(0.03),
                          ],
                        ),
                      ),
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, _, __, i) {
                          final touched = _touchedIndex == i;
                          return FlDotCirclePainter(
                            radius: touched ? 6.5 : 4.5,
                            color: touched
                                ? const Color(0xFF1565C0)
                                : Colors.white,
                            strokeWidth: 2.5,
                            strokeColor: const Color(0xFF1565C0),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Rain indicator row (clean pill chips, not text dump) ─────────
          if (isLive && hasRain)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                const Icon(Icons.water, size: 12, color: Color(0xFF7B1FA2)),
                const SizedBox(width: 6),
                Expanded(
                  child: Wrap(spacing: 6, children: [
                    for (int i = 0; i < rainfallData.length; i++)
                      if (rainfallData[i] > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7B1FA2).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFF7B1FA2).withOpacity(0.25)),
                          ),
                          child: Text(
                            '${dateLabels[i]}  ${rainfallData[i].toStringAsFixed(1)}mm',
                            style: const TextStyle(fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF7B1FA2)),
                          ),
                        ),
                  ]),
                ),
              ]),
            ),

          // ── Footer ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(children: [
              Text(footerSource,
                  style: const TextStyle(fontSize: 8.5,
                      fontWeight: FontWeight.w600, color: Color(0xFFAAAAAA))),
              const Spacer(),
              Text('Avg: ${avg.toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                      color: statusColor)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _moistureLegend(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10, height: 3,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 5),
      Text(label,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color.withOpacity(0.85))),
    ],
  );
}

// ── Moisture Zone Painter (kept for compatibility) ────────────────────────
class _MoistureZonePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(_) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
//  FIELD ANALYSIS CARD
// ═══════════════════════════════════════════════════════════════════════════
class _FieldAnalysisCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  const _FieldAnalysisCard({required this.data, required this.onTap});
  @override State<_FieldAnalysisCard> createState() => _FieldAnalysisCardState();
}

class _FieldAnalysisCardState extends State<_FieldAnalysisCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 150));
    _scale = Tween<double>(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final color      = d['color']       as Color;
    final gradColors = d['gradColors']  as List<Color>;
    final progress   = (d['progress']   as double).clamp(0.0, 1.0);
    final loading    = d['loading']     as bool;

    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) { _ctrl.reverse(); widget.onTap(); },
        onTapCancel: () => _ctrl.reverse(),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06),
                blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradColors,
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(child: Text(d['icon'] as String,
                    style: const TextStyle(fontSize: 16))),
              ),
              const Spacer(),
              if (loading)
                SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: color))
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (d['statusColor'] as Color).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(d['status'] as String,
                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900,
                          color: d['statusColor'] as Color, letterSpacing: 0.5)),
                ),
            ]),
            const SizedBox(height: 6),
            Text(d['label'] as String, style: const TextStyle(fontSize: 9,
                fontWeight: FontWeight.w700, color: AppColors.textLight,
                letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Text(d['title'] as String, style: const TextStyle(fontSize: 11,
                fontWeight: FontWeight.w900, color: AppColors.textDark, height: 1.2),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const Spacer(),
            Row(children: [
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: loading ? null : progress,
                  minHeight: 4,
                  backgroundColor: color.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 14, color: AppColors.textLight),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  FIELD DETAIL SCREEN  — Live data for each analysis type
// ═══════════════════════════════════════════════════════════════════════════
class _FieldDetailScreen extends StatefulWidget {
  final Map<String, dynamic> insight;
  final WeatherData?         weather;
  final SoilData             soilData;
  final PlotLayerResponse?   waterData;
  final PlotLayerResponse?   pestData;
  final SoilNpkResult?       npkData;
  final SoilAnalysisResult?  analysisData;
  final String               plotName;

  const _FieldDetailScreen({
    required this.insight,
    required this.weather,
    required this.soilData,
    this.waterData,
    this.pestData,
    this.npkData,
    this.analysisData,
    this.plotName = '',
  });

  @override
  State<_FieldDetailScreen> createState() => _FieldDetailScreenState();
}

class _FieldDetailScreenState extends State<_FieldDetailScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 600))..forward();
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }
  @override void dispose() { _animCtrl.dispose(); super.dispose(); }

  // ── Extract 7-day trend from API response ─────────────────────────────
  List<FlSpot> _buildTrendSpots(String apiType) {
    // ── Water: use pixel_summary percentages as zone breakdown trend ────
    if (apiType == 'water' && widget.waterData != null) {
      final ps = widget.waterData!.pixelSummary;
      if (ps != null) {
        // Show the 5 moisture categories as a 5-point "distribution" chart
        // X-axis = moisture level (deficient→excess), Y-axis = % of field
        final defPct  = (ps['deficient_pixel_percentage'] as num?)?.toDouble() ?? 0;
        final lessPct = (ps['less_pixel_percentage']       as num?)?.toDouble() ?? 0;
        final adqPct  = (ps['adequat_pixel_percentage']    as num?)?.toDouble() ?? 0;
        final excPct  = (ps['excellent_pixel_percentage']  as num?)?.toDouble() ?? 0;
        final exsPct  = (ps['excess_pixel_percentage']     as num?)?.toDouble() ?? 0;

        // Pad to 7 points by interpolating between categories
        return [
          FlSpot(0, defPct),
          FlSpot(1, (defPct + lessPct) / 2),
          FlSpot(2, lessPct),
          FlSpot(3, (lessPct + adqPct) / 2),
          FlSpot(4, adqPct),
          FlSpot(5, excPct),
          FlSpot(6, exsPct),
        ];
      }
    }

    PlotLayerResponse? r;
    if (apiType == 'pest') r = widget.pestData;

    // Try to get time-series from raw response
    if (r != null) {
      final ts = r.raw['timeseries'] ?? r.raw['time_series'] ??
                 r.raw['daily'] ?? r.raw['history'];
      if (ts is List && ts.length >= 3) {
        final spots = <FlSpot>[];
        for (var i = 0; i < ts.length && i < 7; i++) {
          final v = ts[i] is Map ? (ts[i]['value'] ?? ts[i]['mean'] ?? ts[i]['score']) : ts[i];
          if (v is num) spots.add(FlSpot(i.toDouble(), (v as num).toDouble()));
        }
        if (spots.length >= 2) return spots;
      }
    }

    // No real trend data available — return empty (shown as "unavailable")
    return [];
  }

  // ── Build historical rows from API response ───────────────────────────
  List<Map<String, String>> _buildHistoricalRows(String apiType) {
    // ── Water: show pixel zone breakdown as the "historical" table ─────
    if (apiType == 'water' && widget.waterData != null) {
      final ps = widget.waterData!.pixelSummary;
      if (ps != null) {
        final totalPx  = (ps['total_pixel_count'] as num?)?.toInt() ?? 0;
        final startDt  = ps['analysis_start_date']?.toString() ?? '';
        final endDt    = ps['analysis_end_date']?.toString()   ?? '';
        return [
          {
            'date': 'Deficient',
            'val':  '${(ps['deficient_pixel_percentage'] as num?)?.toStringAsFixed(1) ?? '0'}%',
            'delta': '${(ps['deficient_pixel_count'] as num?)?.toInt() ?? 0} px 🔴',
          },
          {
            'date': 'Low',
            'val':  '${(ps['less_pixel_percentage'] as num?)?.toStringAsFixed(1) ?? '0'}%',
            'delta': '${(ps['less_pixel_count'] as num?)?.toInt() ?? 0} px 🟡',
          },
          {
            'date': 'Adequate',
            'val':  '${(ps['adequat_pixel_percentage'] as num?)?.toStringAsFixed(1) ?? '0'}%',
            'delta': '${(ps['adequat_pixel_count'] as num?)?.toInt() ?? 0} px 🟢',
          },
          {
            'date': 'Excellent',
            'val':  '${(ps['excellent_pixel_percentage'] as num?)?.toStringAsFixed(1) ?? '0'}%',
            'delta': '${(ps['excellent_pixel_count'] as num?)?.toInt() ?? 0} px 💧',
          },
          {
            'date': 'Excess',
            'val':  '${(ps['excess_pixel_percentage'] as num?)?.toStringAsFixed(1) ?? '0'}%',
            'delta': '${(ps['excess_pixel_count'] as num?)?.toInt() ?? 0} px 🔵',
          },
          {
            'date': 'Analysis',
            'val':  '$totalPx px',
            'delta': '${startDt.isNotEmpty ? startDt : "–"} → ${endDt.isNotEmpty ? endDt : "–"}',
          },
        ];
      }
    }

    PlotLayerResponse? r;
    if (apiType == 'pest') r = widget.pestData;

    if (r != null) {
      final features = r.raw['features'];
      if (features is List && features.isNotEmpty) {
        final rows = <Map<String, String>>[];
        double? prev;
        for (var i = 0; i < features.length && i < 6; i++) {
          final props = features[i]['properties'] as Map?;
          if (props == null) continue;
          double? val;
          for (final k in ['value','mean','score','pest_score']) {
            if (props[k] is num) { val = (props[k] as num).toDouble(); break; }
          }
          if (val == null) continue;
          final date = props['date'] ?? props['time'] ?? props['timestamp'];
          final pct  = (val * 100).toStringAsFixed(0);
          final delta = prev == null ? '+0%'
              : '${val > prev ? '+' : ''}${((val - prev) * 100).toStringAsFixed(0)}%';
          rows.add({'date': date?.toString() ?? 'Day ${i+1}',
                    'val': '$pct%', 'delta': delta});
          prev = val;
        }
        if (rows.length >= 3) return rows;
      }
    }

    // No real historical data from pest API — return empty
    return [];
  }

  // ── Weather 7-day using live data ─────────────────────────────────────
  List<FlSpot> _buildWeatherTrend() {
    // Only current temperature is available — no 7-day forecast API connected.
    final w = widget.weather;
    if (w == null) return [];
    // Show single point — current reading only
    return [FlSpot(3, w.tempC)]; // single dot at midpoint
  }

  List<Map<String, String>> _buildWeatherHistory() {
    // No historical weather API connected — only current conditions available.
    final w = widget.weather;
    if (w == null) return [];
    return [
      {'date': 'Now',      'val': '${w.tempC.round()}°C',              'delta': '${w.humidity}% RH'},
      {'date': 'Wind',     'val': '${w.windSpeedMs.toStringAsFixed(1)} m/s', 'delta': w.description},
      {'date': 'Cloud',    'val': '${w.cloudCoverPct.round()}%',        'delta': 'Cover'},
      {'date': 'Rain 1h',  'val': w.rainMmLastHour != null ? '${w.rainMmLastHour!.toStringAsFixed(1)}mm' : '0mm', 'delta': 'Precipitation'},
      {'date': 'Feels',    'val': '${w.feelsLikeC.round()}°C',          'delta': 'Feels like'},
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ins        = widget.insight;
    final color      = ins['color']      as Color;
    final gradColors = ins['gradColors'] as List<Color>;
    final apiType    = ins['apiType']    as String;
    final topPad     = MediaQuery.of(context).padding.top;

    final trendSpots = apiType == 'weather'
        ? _buildWeatherTrend()
        : _buildTrendSpots(apiType);
    final histRows   = apiType == 'weather'
        ? _buildWeatherHistory()
        : _buildHistoricalRows(apiType);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F0),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(children: [
          // ── Gradient header ────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradColors,
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
              boxShadow: [BoxShadow(color: gradColors[0].withOpacity(0.35),
                  blurRadius: 20, offset: const Offset(0, 6))],
            ),
            child: Column(children: [
              Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(width: 38, height: 38,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.18)),
                    child: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 15),
                  ),
                ),
                const SizedBox(width: 12),
                Text(ins['label'] as String,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                        color: Colors.white.withOpacity(0.65), letterSpacing: 1.2)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(ins['status'] as String,
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900,
                          color: Colors.white, letterSpacing: 0.5)),
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Text(ins['icon'] as String, style: const TextStyle(fontSize: 36)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ins['title'] as String,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                          color: Colors.white, height: 1.2)),
                  const SizedBox(height: 4),
                  Text(
                    apiType == 'water'   ? 'Live data · Water Uptake API' :
                    apiType == 'pest'    ? 'Live data · Pest Detection API' :
                    apiType == 'weather' ? 'Live data · Real-time climate' :
                                           'Analysis · Soil nutrient data',
                    style: TextStyle(fontSize: 11,
                        color: Colors.white.withOpacity(0.65),
                        fontWeight: FontWeight.w600),
                  ),
                ])),
              ]),
            ]),
          ),

          // ── Scrollable body ────────────────────────────────────────
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Field Analysis card
              _sectionCard(
                header: _cardHeader(Icons.info_outline, 'FIELD ANALYSIS', gradColors),
                child: Text(ins['detail'] as String,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                        color: AppColors.textDark, height: 1.6)),
              ),
              const SizedBox(height: 14),

              // 7-Day Trend chart
              _sectionCard(
                header: Text(
                  apiType == 'water' ? 'Field Moisture Distribution' : '7-Day Trend',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color)),
                child: trendSpots.isEmpty
                  ? Container(
                      height: 80,
                      alignment: Alignment.center,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.info_outline, color: color.withOpacity(0.4), size: 22),
                        const SizedBox(height: 6),
                        Text('Trend data not available from API',
                            style: TextStyle(fontSize: 12, color: color.withOpacity(0.55),
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('Only current snapshot data is available',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                      ]),
                    )
                  : SizedBox(
                  height: 130,
                  child: LineChart(LineChartData(
                    gridData: FlGridData(show: true, drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) =>
                            const FlLine(color: Color(0xFFF0F0F0), strokeWidth: 1)),
                    titlesData: const FlTitlesData(
                      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles:    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [LineChartBarData(
                      spots: trendSpots,
                      isCurved: true, curveSmoothness: 0.45,
                      color: color, barWidth: 2.5,
                      belowBarData: BarAreaData(show: true,
                          gradient: LinearGradient(
                              begin: Alignment.topCenter, end: Alignment.bottomCenter,
                              colors: [color.withOpacity(0.20), color.withOpacity(0.0)])),
                      dotData: FlDotData(show: true,
                          getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                              radius: 3.5, color: color,
                              strokeWidth: 2, strokeColor: Colors.white)),
                    )],
                  )),
                ),
              ),
              const SizedBox(height: 14),

              // AI Action Plan
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [gradColors[0].withOpacity(0.08), gradColors[1].withOpacity(0.05)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: color.withOpacity(0.20)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _cardHeader(Icons.auto_awesome, 'AI ACTION PLAN', gradColors),
                  const SizedBox(height: 12),
                  Text(ins['action'] as String,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: AppColors.textDark, height: 1.55)),
                ]),
              ),
              const SizedBox(height: 14),

              // Historical Data
              _sectionCard(
                header: Text(
                  apiType == 'water' ? 'Pixel Zone Breakdown' : 'Historical Data',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color)),
                child: histRows.isEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.history_toggle_off, color: color.withOpacity(0.4), size: 22),
                        const SizedBox(height: 6),
                        Text('Historical data not available',
                            style: TextStyle(fontSize: 12, color: color.withOpacity(0.55),
                                fontWeight: FontWeight.w600)),
                        Text('API does not provide historical records for this metric',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                      ]),
                    )
                  : Column(children: histRows.map((row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Text(row['date']!, style: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w700, color: AppColors.textLight)),
                    const Spacer(),
                    Text(row['val']!, style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w900, color: AppColors.textDark)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (row['delta']!.startsWith('+') || !row['delta']!.contains('%'))
                            ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(row['delta']!, style: TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w900,
                          color: (row['delta']!.startsWith('+') || !row['delta']!.contains('%'))
                              ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F))),
                    ),
                  ]),
                )).toList()),
              ),
              const SizedBox(height: 14),

              // Apply button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Apply Recommendation',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                ),
              ),
            ]),
          )),
        ]),
      ),
    );
  }

  Widget _sectionCard({required Widget header, required Widget child}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
              blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          header,
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _cardHeader(IconData icon, String label, List<Color> grad) =>
      Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: grad,
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 13),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 10,
            fontWeight: FontWeight.w900, color: AppColors.textDark,
            letterSpacing: 1)),
      ]);
}

// ── Weather detail card (kept for compatibility) ──────────────────────────
class _WeatherDetailCard extends StatelessWidget {
  final WeatherData weather;
  const _WeatherDetailCard({required this.weather});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// Extension helper
extension _AlsoExt<T> on T {
  T also(void Function() fn) { fn(); return this; }
}
