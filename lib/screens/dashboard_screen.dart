import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../constants/app_constants.dart';
import '../widgets/common_widgets.dart';
import '../widgets/weather_widgets.dart';
import '../widgets/market_marquee_widget.dart';
import '../widgets/windy_overlay.dart';
import '../widgets/live_environment_overlay.dart';
import '../widgets/wind_particles_overlay.dart';
import '../widgets/rain_overlay.dart';
import '../widgets/weather_alert_banner.dart';
import '../widgets/cluster_fab.dart';
import '../services/weather_service.dart';
import '../services/plot_layer_api.dart';
import '../services/soil_param_api.dart';
import 'side_panels.dart';
import 'face_auth_screen.dart';
import 'chatbot_screen.dart';
import '../widgets/api_debug_panel.dart';
import 'screen_share_panel.dart';
import '../main.dart' show appLocale;
import 'ai_recommendation_centre.dart';
import '../constants/app_strings.dart';
import 'insights_screen.dart';
import '../widgets/crop_field_overlay.dart';
import '../services/streak_service.dart';
import '../services/api_service.dart';
import 'alert_feed_screen.dart' show ActionableAlert;

class DashboardScreen extends StatefulWidget {
  final FieldModel field;
  final List<FieldModel> fields;
  final List<AlertModel> alerts;
  final String userName;
  final int streak;
  final int longestStreak;
  final bool isNewDayOpen;
  final void Function(String) onSelectField;
  final Future<void> Function(String) onDeleteField;
  final void Function(String, String) onRenameField;
  final VoidCallback onAddNewField;
  final void Function(String) onResolveAlert;
  final Future<void> Function() onLogout;
  /// Alert tapped from the feed — dashboard will zoom to it and open the panel
  final ActionableAlert? pendingAlert;
  /// Full list of actionable alerts for AI Recommendation Centre
  final List<ActionableAlert> actionableAlerts;

  const DashboardScreen({
    super.key,
    required this.field,
    required this.fields,
    required this.alerts,
    required this.userName,
    this.streak       = 0,
    this.longestStreak = 0,
    this.isNewDayOpen  = false,
    required this.onSelectField,
    required this.onDeleteField,
    required this.onRenameField,
    required this.onAddNewField,
    required this.onResolveAlert,
    required this.onLogout,
    this.pendingAlert,
    this.actionableAlerts = const [],
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  ActivePanel _panel = ActivePanel.none;
  bool _is3D = false;
  bool _showMapSettings = false;
  String _mapType = 'satellite';
  bool _showProfile     = false;   // profile/settings panel
  bool _showFaceEnroll  = false;   // face enroll from profile settings
  bool _loggingOut      = false;
  bool _showStreakToast  = false;  // new-day streak celebration toast
  final MapController _mapCtrl = MapController();

  LatLng? _userPos;
  double _bearing = 0;
  double _deviceHeading = 0; // device compass heading (like Google Maps arrow)
  bool _isMoving = false;     // true when walking speed > 0.5 m/s
  String? _distance;

  // ── Footprint trail ──────────────────────────────────────────────
  final List<LatLng> _footprintTrail = [];
  final List<double> _footprintOpacity = [];
  static const int _maxFootprints = 40;  // max trail length

  // ── Weather ──────────────────────────────────────────────────────
  WeatherData? _weather;
  bool _weatherLoading = true;
  bool _showDebug = false;       // API debug panel

  // ── Cluster FAB state ─────────────────────────────────────────
  String? _openCluster; // 'ai_help' | 'farm_board' | 'map_layers' | null

  // ── Crop visualization (maize tiles, vector crops, etc.) ──────
  bool _showCrops = true;

  /// Railway analysis raster overlays (GROWTH / WATER / SOIL / PESTS tile URLs)
  static const _plotLayerOrder = ['GROWTH', 'WATER', 'SOIL', 'PESTS'];
  final Map<String, String> _plotAnalysisTileUrls = {};

  // ── Live environment animations ────────────────────────────────
  late AnimationController _pulseCtrl;

  // ── Main map field-data popup ────────────────────────────────────
  bool _showFieldPopup    = false;
  // Alert pin — shown on map when farmer taps an alert card
  LatLng? _alertPinPos;
  String? _alertPinType;  // pest|water|soil|growth|weather|harvest
  bool _loadingFieldPopup = false;
  Map<String, String> _fieldPopupValues = {};
  // Pre-fetched compact values (icon → numeric string) ready before tap
  Map<String, String> _bgValues = {};
  bool _bgFetching = false;
  bool _bgReady    = false;
  // Tap position for the floating popup
  Offset _popupTapPos = Offset.zero;
  Timer? _popupDismissTimer;

  // ── Google Earth zoom-in animation ───────────────────────────────
  late AnimationController _zoomInCtrl;
  late Animation<double>   _zoomAnim;
  late Animation<double>   _latAnim;
  late Animation<double>   _lngAnim;
  bool _zoomInDone = false;
  LatLng? _zoomTarget;

  @override
  void initState() {
    super.initState();
    _startLocationWatch();
    // Fetch weather for the field center immediately
    _fetchWeather(widget.field.center[0], widget.field.center[1]);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    // Google Earth zoom-in — 5-second fly-in from whole earth to field
    _zoomTarget = LatLng(widget.field.center[0], widget.field.center[1]);
    _zoomInCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8500),
    );
    // Zoom: starts at 2 (whole earth), ends at 18 (field level)
    // Uses a custom easeIn curve — slow at start, accelerates as it "falls"
    _zoomAnim = Tween<double>(begin: 2.0, end: 18.0).animate(
      CurvedAnimation(parent: _zoomInCtrl,
          curve: const _EarthZoomCurve()),
    );
    // Lat/Lng: fly from near (0,0) centre of earth toward the field
    _latAnim = Tween<double>(
      begin: 20.5937,  // India geographic centre
      end:   widget.field.center[0],
    ).animate(CurvedAnimation(parent: _zoomInCtrl,
        curve: const Interval(0.20, 1.0, curve: Curves.easeInOutCubic)));
    _lngAnim = Tween<double>(
      begin: 78.9629,  // India geographic centre
      end:   widget.field.center[1],
    ).animate(CurvedAnimation(parent: _zoomInCtrl,
        curve: const Interval(0.20, 1.0, curve: Curves.easeInOutCubic)));

    // Trigger the fly-in after the map is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startZoomIn(widget.field);
    });

    // Pre-fetch field analysis values in background so popup shows instantly
    WidgetsBinding.instance.addPostFrameCallback((_) => _bgFetchValues());

    // Show streak celebration toast on the first frame if this is a new day open
    if (widget.isNewDayOpen && widget.streak > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _showStreakToast = true);
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) setState(() => _showStreakToast = false);
          });
        }
      });
    }

    // ── Handle alert tap — zoom to exact plant-level hotspot + show pin ──
    if (widget.pendingAlert != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          final a = widget.pendingAlert!;

          if (a.hotspotLat != null && a.hotspotLng != null) {
            final pinPos = LatLng(a.hotspotLat!, a.hotspotLng!);

            // Set pin on map
            setState(() {
              _alertPinPos  = pinPos;
              _alertPinType = a.type;
            });

            // Animate zoom to plant level — zoom 22 shows individual plants
            _mapCtrl.move(pinPos, 22.0);

            // Show snackbar with alert info
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('📍 ${a.title} — ${a.message}',
                  style: const TextStyle(fontSize: 12)),
              backgroundColor: const Color(0xFF1B2E1B),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 6),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              action: SnackBarAction(
                label: 'Clear Pin',
                textColor: const Color(0xFF69F0AE),
                onPressed: () => setState(() {
                  _alertPinPos  = null;
                  _alertPinType = null;
                }),
              ),
            ));
          } else if (a.polygon.isNotEmpty) {
            final lats = a.polygon.map((p) => p[0]).toList();
            final lngs = a.polygon.map((p) => p[1]).toList();
            _mapCtrl.fitCamera(CameraFit.bounds(
              bounds: LatLngBounds(
                LatLng(lats.reduce(min), lngs.reduce(min)),
                LatLng(lats.reduce(max), lngs.reduce(max)),
              ),
              padding: const EdgeInsets.all(40),
              maxZoom: 22,
            ));
          }
        });
      });
    }
  }

  Future<void> _fetchWeather(double lat, double lon) async {
    final data = await WeatherService.fetchByCoords(lat, lon);
    if (mounted) setState(() { _weather = data; _weatherLoading = false; });
  }

  @override
  void dispose() {
    _popupDismissTimer?.cancel();
    _pulseCtrl.dispose();
    _zoomInCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DashboardScreen old) {
    super.didUpdateWidget(old);
    // Re-fetch background values whenever we switch to a different field
    if (old.field.id != widget.field.id) {
      _bgValues   = {};
      _bgReady    = false;
      _bgFetching = false;
      _bgFetchValues();
    }
    if (old.field.id != widget.field.id) {
      _plotAnalysisTileUrls.clear();
      _footprintTrail.clear();
      _footprintOpacity.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startZoomIn(widget.field);
      });
    }
  }

  // ── Google Earth fly-in animation ─────────────────────────────────
  // Called on app open and every time the farmer switches plots.
  // Starts at zoom=2 (whole earth), flies to zoom=18 (field level).
  void _startZoomIn(FieldModel field) {
    if (!mounted) return;
    _zoomTarget = LatLng(field.center[0], field.center[1]);

    // Re-create animations targeting the NEW field
    _zoomAnim = Tween<double>(begin: 2.0, end: 18.0).animate(
      CurvedAnimation(parent: _zoomInCtrl, curve: const _EarthZoomCurve()),
    );
    _latAnim = Tween<double>(
      begin: 20.5937, end: field.center[0],
    ).animate(CurvedAnimation(parent: _zoomInCtrl,
        curve: const Interval(0.15, 1.0, curve: Curves.easeInOutCubic)));
    _lngAnim = Tween<double>(
      begin: 78.9629, end: field.center[1],
    ).animate(CurvedAnimation(parent: _zoomInCtrl,
        curve: const Interval(0.15, 1.0, curve: Curves.easeInOutCubic)));

    setState(() => _zoomInDone = false);
    _zoomInCtrl.reset();

    // Move map to starting position (whole earth view)
    _mapCtrl.move(const LatLng(20.5937, 78.9629), 2.0);

    // Animate on every tick
    void onTick() {
      if (!mounted) return;
      final zoom = _zoomAnim.value;
      final lat  = _latAnim.value;
      final lng  = _lngAnim.value;
      _mapCtrl.move(LatLng(lat, lng), zoom);
      if (_zoomInCtrl.isCompleted) {
        if (mounted) {
          setState(() => _zoomInDone = true);
          // Final fit-to-bounds after fly-in
          final poly = field.polygon
              .map((p) => LatLng(p[0], p[1])).toList();
          if (poly.length >= 3) {
            final lats = poly.map((p) => p.latitude).toList();
            final lngs = poly.map((p) => p.longitude).toList();
            _mapCtrl.fitCamera(CameraFit.bounds(
              bounds: LatLngBounds(
                LatLng(lats.reduce((a,b) => a<b?a:b),
                       lngs.reduce((a,b) => a<b?a:b)),
                LatLng(lats.reduce((a,b) => a>b?a:b),
                       lngs.reduce((a,b) => a>b?a:b)),
              ),
              padding: const EdgeInsets.all(80),
              maxZoom: 22,
            ));
          }
        }
      }
    }

    _zoomInCtrl.addListener(onTick);
    _zoomInCtrl.forward().then((_) {
      _zoomInCtrl.removeListener(onTick);
    });
  }

  void _onPlotAnalysisLayer(
    String layerLabel,
    bool active,
    String? tileUrl,
    Map<String, dynamic>? pixelSummary,
  ) {
    setState(() {
      if (active && tileUrl != null && tileUrl.isNotEmpty) {
        // ── Only one layer at a time: clear all others first ────────
        _plotAnalysisTileUrls.clear();
        _plotAnalysisTileUrls[layerLabel] = tileUrl;
      } else {
        _plotAnalysisTileUrls.remove(layerLabel);
      }
    });
  }

  // ── Background pre-fetch (runs silently on initState / field change) ───────
  // All 5 APIs are called in parallel via Future.wait so total wait time
  // equals the slowest single call, not the sum of all.
  Future<void> _bgFetchValues() async {
    if (_bgFetching) return;
    final plot = widget.field.plotNameForAnalysis;
    if (plot.isEmpty) return;

    if (mounted) setState(() => _bgFetching = true);

    final today = DateTime.now().toString().split(' ')[0];
    final pDate = widget.field.plantationDate ?? today;

    // Run all fetches in parallel
    final results = await Future.wait([
      // 0 — Soil Moisture
      SoilMoistureApi.fetch(plot).then<String>((r) {
        final avg = r.avgMoisture;
        return '${avg.toStringAsFixed(1)}%';
      }).catchError((e) { dev.log('BG soil: $e'); return '--'; }),

      // 1 — Water Uptake: show adequate% / low%
      PlotLayerApi.fetchWater(plot).then<String>((r) {
        final ps = r.pixelSummary;
        if (ps == null) return '--';
        final adq  = (ps['adequat_pixel_percentage']   as num?)?.toDouble() ?? 0;
        final less = (ps['less_pixel_percentage']       as num?)?.toDouble() ?? 0;
        final exc  = (ps['excellent_pixel_percentage']  as num?)?.toDouble() ?? 0;
        if (adq == 0 && less == 0 && exc == 0) return '--';
        return '${(adq + exc).toStringAsFixed(0)}% ok';
      }).catchError((e) { dev.log('BG water: $e'); return '--'; }),

      // 2 — Growth: latest NDVI date + image count
      PlotLayerApi.fetchGrowth(plot).then<String>((r) {
        final features = r.raw['features'] as List?;
        final props = features?.isNotEmpty == true
            ? features![0]['properties'] as Map?
            : null;
        if (props == null) return '--';
        // API has a typo: "letest_image_date"
        final date  = props['letest_image_date']
                   ?? props['latest_image_date']
                   ?? '';
        final count = (props['image_count']
                    ?? props['image_count_in_range']
                    ?? 0) as int;
        // Show short date (dd/mm) + count
        String shortDate = '--';
        if (date is String && date.length >= 10) {
          final parts = date.split('-');
          if (parts.length == 3) shortDate = '${parts[2]}/${parts[1]}';
        }
        return count > 0 ? '$count imgs ($shortDate)' : shortDate;
      }).catchError((e) { dev.log('BG growth: $e'); return '--'; }),

      // 3 — Pest Risk: percentage + level label
      PlotLayerApi.fetchPest(plot, today).then<String>((r) {
        final ps = r.pixelSummary;
        if (ps == null || ps.isEmpty) return '--';
        final score = (ps['mean'] ?? ps['score'] ?? ps['risk']) as num?;
        if (score == null) return '--';
        final pct   = (score * 100).toStringAsFixed(0);
        final level = score > 0.7 ? 'HIGH'
                    : score > 0.4 ? 'MOD'
                    : 'LOW';
        return '$pct% $level';
      }).catchError((e) { dev.log('BG pest: $e'); return '--'; }),

      // 4 — NPK from soil-param API
      SoilParamApi.fetchNpk(
        plotName:       plot,
        plantationDate: pDate,
        endDate:        today,
      ).then<String>((r) {
        final n = r.soilN.toStringAsFixed(0);
        final p = r.soilP.toStringAsFixed(0);
        final k = r.soilK.toStringAsFixed(0);
        return 'N$n P$p K$k';
      }).catchError((e) { dev.log('BG npk: $e'); return '--'; }),
    ]);

    if (mounted) {
      setState(() {
        _bgValues = {
          '💧': results[0],
          '🌊': results[1],
          '🌱': results[2],
          '🐛': results[3],
          '🌾': results[4],
        };
        _bgReady    = true;
        _bgFetching = false;
        if (_showFieldPopup) _fieldPopupValues = _expandedValues(_bgValues);
      });
    }
  }

  // Expand compact bg values into the full-label map used by the old popup
  Map<String, String> _expandedValues(Map<String, String> v) => {
    '💧 Soil Moisture':  v['💧'] ?? '--',
    '🌊 Water Uptake':   v['🌊'] ?? '--',
    '🌱 Growth (NDVI)':  v['🌱'] ?? '--',
    '🐛 Pest Risk':      v['🐛'] ?? '--',
    '🌾 N-P-K':          v['🌾'] ?? '--',
  };

  // ── Fetch all field values for main map popup ────────────────────────────
  // Show popup at a given screen-pixel position, then auto-dismiss after 7 s
  void _showPopupAt(Offset localPos) {
    _popupDismissTimer?.cancel();
    setState(() {
      _popupTapPos    = localPos;
      _showFieldPopup = true;
    });
    _popupDismissTimer = Timer(const Duration(seconds: 7), () {
      if (mounted) setState(() => _showFieldPopup = false);
    });
    // If not yet fetched, kick off now
    if (!_bgReady && !_bgFetching) _bgFetchValues();
  }

  // ── Ray-casting point-in-polygon test ──────────────────────────────────
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    int crossings = 0;
    final double px = point.longitude;
    final double py = point.latitude;
    for (int i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final double ax = a.longitude, ay = a.latitude;
      final double bx = b.longitude, by = b.latitude;
      if (((ay <= py && py < by) || (by <= py && py < ay)) &&
          px < (bx - ax) * (py - ay) / (by - ay) + ax) {
        crossings++;
      }
    }
    return crossings.isOdd;
  }

  Future<void> _fetchMainMapPopup() async {
    // If bg pre-fetch already has values, just show the compact pill instantly
    if (_bgReady) {
      setState(() { _showFieldPopup = true; });
      return;
    }
    if (_loadingFieldPopup) return;
    setState(() { _loadingFieldPopup = true; _showFieldPopup = true; _fieldPopupValues = {}; });

    final plot = widget.field.plotNameForAnalysis;
    if (plot.isEmpty) {
      setState(() { _loadingFieldPopup = false; _fieldPopupValues = {'Error': 'No plot name'}; });
      return;
    }

    final results = <String, String>{};

    try {
      final r = await SoilMoistureApi.fetch(plot);
      final avg = r.avgMoisture;
      final label = avg >= 80 ? '🔵 High' : avg >= 40 ? '🟢 Good' : '🟡 Low';
      results['💧 Soil Moisture'] = '\${avg.toStringAsFixed(1)}%  \$label';
    } catch (_) { results['💧 Soil Moisture'] = 'Unavailable'; }

    try {
      final r = await PlotLayerApi.fetchWater(plot);
      final ps = r.pixelSummary;
      if (ps != null) {
        final less = (ps['less_pixel_percentage'] as num?)?.toDouble() ?? 0;
        final adq  = (ps['adequat_pixel_percentage'] as num?)?.toDouble() ?? 0;
        final exc  = (ps['excellent_pixel_percentage'] as num?)?.toDouble() ?? 0;
        final icon = adq + exc > 50 ? '🟢' : less > 70 ? '🔴' : '🟡';
        results['🌊 Water Uptake'] = '\$icon  Adequate \${adq.toStringAsFixed(0)}%  Low \${less.toStringAsFixed(0)}%';
      } else {
        results['🌊 Water Uptake'] = 'No data';
      }
    } catch (_) { results['🌊 Water Uptake'] = 'Unavailable'; }

    try {
      final r = await PlotLayerApi.fetchGrowth(plot);
      final features = r.raw['features'] as List?;
      final props = features?.isNotEmpty == true ? features![0]['properties'] as Map? : null;
      final date  = props?['letest_image_date'] ?? props?['latest_image_date'] ?? '—';
      final count = props?['image_count'] ?? props?['image_count_in_range'] ?? 0;
      results['🌱 Growth (NDVI)'] = 'Latest: \$date  Images: \$count';
    } catch (_) { results['🌱 Growth (NDVI)'] = 'Unavailable'; }

    try {
      final today = DateTime.now().toString().split(' ')[0];
      final r = await PlotLayerApi.fetchPest(plot, today);
      final ps = r.pixelSummary;
      if (ps != null && ps.isNotEmpty) {
        final score = (ps['mean'] ?? ps['score'] ?? ps['risk']) as num?;
        if (score != null) {
          final pct  = (score * 100).toStringAsFixed(0);
          final icon = score > 0.7 ? '🔴 HIGH' : score > 0.4 ? '🟡 MOD' : '🟢 LOW';
          results['🐛 Pest Risk'] = '\$icon  Score: \$pct%';
        } else {
          results['🐛 Pest Risk'] = 'Monitored';
        }
      } else {
        results['🐛 Pest Risk'] = 'Monitored';
      }
    } catch (_) { results['🐛 Pest Risk'] = 'Unavailable'; }

    try {
      final today = DateTime.now().toString().split(' ')[0];
      final r = await SoilParamApi.fetchNpk(
        plotName: plot,
        plantationDate: widget.field.plantationDate ?? today,
        endDate: today,
      );
      results['🌾 N-P-K'] =
          'N: \${r.soilN.toStringAsFixed(0)} | P: \${r.soilP.toStringAsFixed(0)} | K: \${r.soilK.toStringAsFixed(0)} kg/ha';
    } catch (_) { results['🌾 N-P-K'] = 'Unavailable'; }

    if (mounted) setState(() { _fieldPopupValues = results; _loadingFieldPopup = false; });
  }

  void _startLocationWatch() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).listen((pos) {
        if (!mounted) return;
        final bearing = _calcBearing(pos.latitude, pos.longitude,
            widget.field.center[0], widget.field.center[1]);
        final dist = _calcDistance(pos.latitude, pos.longitude,
            widget.field.center[0], widget.field.center[1]);
        final isFirst = _userPos == null;
        setState(() {
          final newPos = LatLng(pos.latitude, pos.longitude);
          // Add footprint dot if moved > 3m (avoids GPS jitter noise)
          if (_userPos != null && _calcDistanceM(
              _userPos!.latitude, _userPos!.longitude,
              newPos.latitude, newPos.longitude) > 3.0) {
            _footprintTrail.add(newPos);
            _footprintOpacity.add(1.0);
            if (_footprintTrail.length > _maxFootprints) {
              _footprintTrail.removeAt(0);
              _footprintOpacity.removeAt(0);
            }
            // Fade oldest → newest
            for (int i = 0; i < _footprintOpacity.length; i++) {
              _footprintOpacity[i] = (i + 1) / _footprintOpacity.length;
            }
          }
          _userPos = newPos;
          _bearing = bearing;
          _deviceHeading = (pos.heading != null && pos.heading! >= 0)
              ? pos.heading!
              : bearing;
          // Walking animation when speed > 0.5 m/s
          _isMoving = (pos.speed) > 0.5;
          _distance = dist;
        });
        // Refresh weather using actual GPS on first fix
        if (isFirst) _fetchWeather(pos.latitude, pos.longitude);
      });
    } catch (_) {}
  }

  double _calcBearing(
      double lat1, double lng1, double lat2, double lng2) {
    final y = sin((lng2 - lng1) * pi / 180) * cos(lat2 * pi / 180);
    final x = cos(lat1 * pi / 180) * sin(lat2 * pi / 180) -
        sin(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            cos((lng2 - lng1) * pi / 180);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  String _calcDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const R = 6371e3;
    final p1 = lat1 * pi / 180, p2 = lat2 * pi / 180;
    final dp = (lat2 - lat1) * pi / 180, dl = (lng2 - lng1) * pi / 180;
    final a = sin(dp / 2) * sin(dp / 2) +
        cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2);
    final d = R * 2 * atan2(sqrt(a), sqrt(1 - a));
    return d > 1000
        ? '${(d / 1000).toStringAsFixed(1)}KM'
        : '${d.round()}M';
  }

  // Returns raw metres between two coordinates
  double _calcDistanceM(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371e3;
    final p1 = lat1 * pi / 180, p2 = lat2 * pi / 180;
    final dp = (lat2 - lat1) * pi / 180, dl = (lng2 - lng1) * pi / 180;
    final a = sin(dp / 2) * sin(dp / 2) +
        cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  String get _tileUrl {
    switch (_mapType) {
      case 'satellite':
        return 'http://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}';
      case 'hybrid':
        // Google Hybrid — satellite + road/village labels
        return 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
      case 'esri':
        // ESRI World Imagery — sharp satellite, great fallback
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case 'terrain':
        // Google Terrain — elevation, contours, physical map
        return 'https://mt1.google.com/vt/lyrs=p&x={x}&y={y}&z={z}';
      case 'osm':
        // OpenStreetMap — village names, canals, field tracks
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case 'mapbox':
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}';
      case 'google_satellite':
        return 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}';
      case 'google_hybrid':
        return 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
      default:
        return 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
  }

  // ── Initials avatar ─────────────────────────────────────────────
  String get _initials {
    final parts = widget.userName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return widget.userName.isNotEmpty
        ? widget.userName[0].toUpperCase()
        : 'F';
  }

  // ── Full-screen swipe-up push (shared by all action buttons) ─────
  void _pushFullScreen(BuildContext context, Widget child) {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, __, ___) => Scaffold(
        backgroundColor: Colors.white,
        body: child,
      ),
      transitionsBuilder: (_, anim, __, page) {
        final curve =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curve),
          child: page,
        );
      },
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 300),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final fieldCenter =
        LatLng(widget.field.center[0], widget.field.center[1]);
    final polygon =
        widget.field.polygon.map((p) => LatLng(p[0], p[1])).toList();
    final hasAlerts = widget.alerts.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Stack(children: [

        // ─── MAP ─────────────────────────────────────────────────
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: const LatLng(20.5937, 78.9629),
              initialZoom: 2,
              minZoom: 10,
              maxZoom: 22,                    // raised to 22 for deep zoom
              // ── Smooth interactive zoom/pan ──────────────────────
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,   // pinch, double-tap, scroll, drag
                pinchZoomThreshold: 0.1,      // very sensitive pinch-to-zoom
                scrollWheelVelocity: 0.005,   // smooth scroll wheel speed
                rotationThreshold: 5.0,
                pinchMoveThreshold: 5.0,
              ),
              onMapReady: () {
                // Map ready — zoom-in animation is started by initState
                // via addPostFrameCallback, so nothing needed here.
              },
              onTap: (tapPos, latLng) {
                // Only show popup when tapping INSIDE the plot polygon
                if (polygon.isNotEmpty && _isPointInPolygon(latLng, polygon)) {
                  _showPopupAt(tapPos.relative ?? tapPos.global);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _tileUrl,
                maxZoom: 22,
                panBuffer: 2,     // pre-loads adjacent tiles for smooth panning
              ),
              // ── Plot polygon fill with animated pulse ──────────
              if (polygon.length >= 3)
                PolygonLayer(polygons: [
                  Polygon(
                    points: polygon,
                    color: AppColors.accent.withOpacity(0.15),
                    borderColor: Colors.transparent,
                    borderStrokeWidth: 0,
                    isFilled: true,
                  ),
                ]),
              // ── Animated glow border ───────────────────────────
              if (polygon.length >= 2)
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) {
                    final glow = 2.5 + _pulseCtrl.value * 2.5;
                    return PolylineLayer(polylines: [
                      Polyline(
                        points: [...polygon, polygon.first],
                        color: AppColors.accent.withOpacity(0.4 + _pulseCtrl.value * 0.35),
                        strokeWidth: glow,
                        strokeCap: StrokeCap.round,
                        strokeJoin: StrokeJoin.round,
                      ),
                      Polyline(
                        points: [...polygon, polygon.first],
                        color: Colors.white.withOpacity(0.6 + _pulseCtrl.value * 0.25),
                        strokeWidth: 1.5,
                        strokeCap: StrokeCap.round,
                      ),
                    ]);
                  },
                ),
              // ── Corner markers ─────────────────────────────────
              if (polygon.length >= 3)
                MarkerLayer(
                  markers: polygon.asMap().entries.map((e) {
                    final isFirst = e.key == 0;
                    return Marker(
                      point: e.value,
                      width: 18,
                      height: 18,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isFirst ? AppColors.primary : AppColors.accent,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [BoxShadow(
                            color: (isFirst ? AppColors.primary : AppColors.accent).withOpacity(0.6),
                            blurRadius: 6,
                          )],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              // ── Farm-status heatmap tiles on main map — BELOW crop animation ──
              // Crop animation renders ON TOP with heatmapActive:true (skips soil fill)
              if (_plotAnalysisTileUrls.isNotEmpty && polygon.length >= 3)
                ..._plotAnalysisTileUrls.values.map((url) => Opacity(
                  opacity: 0.82,
                  child: TileLayer(urlTemplate: url, maxZoom: 22),
                )),

              // ── Crop field animation — ABOVE farm-status heatmaps ────────
              if (_showCrops && polygon.length >= 3)
                CropFieldLayer(
                  // Key on field-id + crop so the state is fully disposed and
                  // recreated whenever you switch to a different field or a field's
                  // crop type changes.  Without this key Flutter reuses the old
                  // _CropFieldLayerState and the previous crop's animation
                  // controllers/plant-grid bleed into the new plot.
                  key:           ValueKey('${widget.field.id}_${widget.field.crop}'),
                  polygon:       polygon,
                  cropType:      widget.field.crop,
                  fieldName:     widget.field.name,
                  fieldId:       widget.field.id,
                  windSpeedMs:   _weather?.windSpeedMs ?? 0.0,
                  windDeg:       _weather?.windDeg     ?? 270.0,
                  heatmapActive: _plotAnalysisTileUrls.isNotEmpty,
                  rowSpacingM:    widget.field.rowSpacingM,
                  plantSpacingM:  widget.field.plantSpacingM,
                  plantationDate: widget.field.plantationDate,
                ),

              // ── Dotted path trail (Google Maps style) ────────────
              if (_footprintTrail.isNotEmpty)
                MarkerLayer(
                  markers: List.generate(_footprintTrail.length, (i) {
                    final opacity = _footprintOpacity[i];
                    // Alternating dot sizes for a natural dotted-path look
                    final isMajor = i % 3 == 0;
                    final dotSize = isMajor ? 10.0 : 7.0;
                    return Marker(
                      point: _footprintTrail[i],
                      width: dotSize,
                      height: dotSize,
                      child: Opacity(
                        opacity: opacity.clamp(0.20, 0.95),
                        child: Container(
                          width: dotSize,
                          height: dotSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF4FC3F7),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.85),
                              width: isMajor ? 2.0 : 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF29B6F6).withOpacity(0.5),
                                blurRadius: isMajor ? 6 : 3,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              if (_userPos != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _userPos!,
                    width: 56,
                    height: 56,
                    child: WalkingManMarker(
                      heading: _deviceHeading,
                      isMoving: _isMoving,
                    ),
                  ),
                ]),

              // ── Alert pin — shown when farmer taps an alert card ──
              if (_alertPinPos != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _alertPinPos!,
                    width: 80,
                    height: 100,
                    alignment: Alignment.bottomCenter,
                    child: _AlertPin(type: _alertPinType ?? 'pest',
                        onDismiss: () => setState(() {
                          _alertPinPos  = null;
                          _alertPinType = null;
                        })),
                  ),
                ]),
            ],
          ),
        ),

        // ─── LIVE ENVIRONMENT OVERLAY (weather + time-of-day) ─────────
        Positioned.fill(
          child: LiveEnvironmentOverlay(
            weather: _weather,
            isLoading: _weatherLoading,
          ),
        ),

        // ─── WIND PARTICLES OVERLAY ───────────────────────────────────
        Positioned.fill(
          child: WindParticlesOverlay(weather: _weather),
        ),

        // ─── RAIN OVERLAY (only when raining / thunderstorm) ──────────
        Positioned.fill(
          child: RainOverlay(weather: _weather),
        ),

        // ─── BASE GRADIENT (always-on vignette for UI legibility) ─────
        IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.45),
                  Colors.transparent,
                  Colors.black.withOpacity(0.6),
                ],
                stops: const [0, 0.4, 1],
              ),
            ),
          ),
        ),

        // ─── WEATHER ALERT BANNER ────────────────────────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: WeatherAlertBanner(weather: _weather),
        ),

        // ─── MAIN MAP FIELD DATA POPUP (tap-position floating box) ────
        if (_showFieldPopup)
          _FloatingFieldPopup(
            tapPos:    _popupTapPos,
            values:    _bgReady ? _bgValues : null,
            isLoading: _bgFetching || _loadingFieldPopup,
            onDismiss: () {
              _popupDismissTimer?.cancel();
              setState(() => _showFieldPopup = false);
            },
            onRetry: () {
              setState(() { _bgReady = false; _bgFetching = false; _bgValues = {}; });
              _bgFetchValues();
            },
            onNavigate: (panel) {
              _popupDismissTimer?.cancel();
              setState(() => _showFieldPopup = false);
              switch (panel) {
                case ActivePanel.soilMoisture:
                  // Soil Moisture → Soil Summary graph in InsightsFullScreen
                  _pushFullScreen(context, InsightsFullScreen(
                    soilData: widget.field.soilData,
                    fieldLat: widget.field.center[0],
                    fieldLon: widget.field.center[1],
                    plotName: widget.field.plotNameForAnalysis,
                field: widget.field,
                actionableAlerts: widget.actionableAlerts,
                    initialSection: 'moisture',
                  ));
                  break;
                case ActivePanel.waterUptake:
                  // Water Uptake → Irrigation Depth Analysis
                  _pushFullScreen(context, InsightsFullScreen(
                    soilData: widget.field.soilData,
                    fieldLat: widget.field.center[0],
                    fieldLon: widget.field.center[1],
                    plotName: widget.field.plotNameForAnalysis,
                field: widget.field,
                actionableAlerts: widget.actionableAlerts,
                    initialSection: 'water',
                  ));
                  break;
                case ActivePanel.pestRisk:
                  // Pest Risk → Entomological Forecast
                  _pushFullScreen(context, InsightsFullScreen(
                    soilData: widget.field.soilData,
                    fieldLat: widget.field.center[0],
                    fieldLon: widget.field.center[1],
                    plotName: widget.field.plotNameForAnalysis,
                field: widget.field,
                actionableAlerts: widget.actionableAlerts,
                    initialSection: 'pest',
                  ));
                  break;
                case ActivePanel.soil:
                  // N-P-K → Soil Nutrients panel
                  _pushFullScreen(context, SoilPanel(
                    soilData: widget.field.soilData,
                    polygon:  widget.field.polygon,
                    center:   widget.field.center,
                    plotName: widget.field.plotNameForAnalysis,
                    plantationDate: widget.field.plantationDate,
                    onClose: () => Navigator.of(context).pop(),
                  ));
                  break;
                default:
                  setState(() => _panel = panel);
              }
            },
          ),

        // ─── WINDY ANIMATED OVERLAY ──────────────────────────────────

        // ─── LEFT COLUMN: Wind badge + Map type + Nav arrow ─────────
        Positioned(
          bottom: 100, left: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Map Layers button (single, expands on tap) ──────
              _MapLayersButton(
                current: _mapType,
                onChanged: (t) => setState(() => _mapType = t),
              ),
              const SizedBox(height: 10),

              GestureDetector(
                onTap: () {
                  if (_userPos != null) _mapCtrl.move(_userPos!, 18);
                },
                child: Column(
                  children: [
                    AnimatedRotation(
                      turns: _deviceHeading / 360,
                      duration: const Duration(milliseconds: 200),
                      child: SizedBox(
                        width: 48, height: 48,
                        child: CustomPaint(
                          painter: _GoogleMapsArrowPainter(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: Text(_distance ?? 'Locating...',
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 0.5)),
                    ),
                  ],
                ),
              ),
              // FIX 5: Go-to-field button — flies back to the registered plot
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  final poly = widget.field.polygon.map((p) => LatLng(p[0], p[1])).toList();
                  if (poly.length >= 3) {
                    final lats = poly.map((p) => p.latitude).toList();
                    final lngs = poly.map((p) => p.longitude).toList();
                    final bounds = LatLngBounds(
                      LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
                      LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
                    );
                    _mapCtrl.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80), maxZoom: 22));
                  } else {
                    _mapCtrl.move(LatLng(widget.field.center[0], widget.field.center[1]), 18);
                  }
                },
                child: Column(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(color: AppColors.primary.withOpacity(0.50), blurRadius: 14, offset: const Offset(0, 5)),
                        BoxShadow(color: Colors.black.withOpacity(0.30), blurRadius: 4, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: const Icon(Icons.agriculture, color: Colors.white, size: 22),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 4)],
                    ),
                    child: Builder(builder: (ctx) => Text(AppStrings.of(ctx).myField, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 0.5))),
                  ),
                ]),
              ),
            ],
          ),
        ),

        // ─── MARKET MARQUEE – pinned to very top of screen ───────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            bottom: false,
            child: MarketMarqueeWidget(
              onTap: () => setState(() => _panel = ActivePanel.market),
            ),
          ),
        ),

        // ─── TOP LEFT: ACTIVE FIELD badge ──────────────────────────────
        Positioned(
          top: 108, left: 12,
          child: IgnorePointer(
                  child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 9),
                        decoration: const BoxDecoration(),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Active plot info
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(mainAxisSize: MainAxisSize.min, children: [
                                    Container(
                                      width: 6, height: 6,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Color(0xFF69F0AE),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Builder(builder: (ctx) => Text(AppStrings.of(ctx).activeField,
                                        style: const TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFFF59E0B),
                                            letterSpacing: 1.5))),
                                  ]),
                                  const SizedBox(height: 2),
                                  Text(widget.field.name,
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          letterSpacing: -0.5)),
                                ],
                              ),
                              // Weather chip right beside active plot name
                              if (_weather != null || _weatherLoading) ...[
                                const SizedBox(width: 10),
                                GestureDetector(
                                  onTap: _weather == null ? null : () => showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (_) => _WeatherForecastSheet(weather: _weather!),
                                  ),
                                  child: WindyInfoBadge(
                                    weather: _weather,
                                    isLoading: _weatherLoading,
                                  ),
                                ),
                              ],
                            ]),
                      ),
                )
        ),

        // ─── FLOATING LAYER POLYGON — top-left, shown when layer active ──
        if (_plotAnalysisTileUrls.isNotEmpty && widget.field.polygon.length >= 3)
          Positioned(
            top: 162, left: 12,
            child: _FloatingLayerPolygon(
              polygon:    widget.field.polygon,
              layerLabel: _plotAnalysisTileUrls.keys.first,
              tileUrl:    _plotAnalysisTileUrls.values.first,
              mapCtrl:    _mapCtrl,
            ),
          ),

        // ─── TOP RIGHT: PROFILE AVATAR + STREAK FLAME BADGE ─────
        Positioned(
          top: 110, right: 16,
          child: GestureDetector(
            onTap: () => setState(() => _showProfile = true),
            onLongPress: () => setState(() => _showDebug = true),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10)
                    ],
                  ),
                  child: ClipOval(
                    child: Center(
                      child: Text(_initials,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16)),
                    ),
                  ),
                ),
                // Streak flame badge — shown only when streak > 0
                if (widget.streak > 0)
                  Positioned(
                    right: -4, bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: widget.streak >= 7
                            ? const Color(0xFFFF6D00)
                            : const Color(0xFFFFA000),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.orange.withOpacity(0.5),
                              blurRadius: 6)
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            StreakService.streakEmoji(widget.streak),
                            style: const TextStyle(fontSize: 9),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${widget.streak}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ─── STREAK CELEBRATION TOAST ─────────────────────────────
        if (_showStreakToast)
          Positioned(
            top: 140, left: 16, right: 16,
            child: _StreakToast(
              streak: widget.streak,
              onDismiss: () => setState(() => _showStreakToast = false),
            ),
          ),

        // map btn moved into unified left column above
        // nav arrow moved into unified left column above

        // ─── RIGHT: CLUSTER FABs ──────────────────────────────────
        // All cluster trigger buttons align exactly right: 16 from screen edge.
        // ClusterFab's trigger is at right:0 of its 180px SizedBox, so this
        // Positioned(right:16) gives every FAB the same 16px right margin.
        Positioned(
          right: 16, top: 0, bottom: 0,
          child: Center(
            child: TapRegion(
              onTapOutside: (_) {
                if (_openCluster != null) {
                  setState(() => _openCluster = null);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // ── AI HELP cluster (AI Scan, Assist, AI Cam) ──
                  ClusterFab(
                      clusterName: 'AI HELP',
                      clusterIcon: Icons.auto_awesome,
                      clusterColor: AppColors.accent,
                      isOpen: _openCluster == 'ai_help',
                      onToggle: () => setState(() =>
                          _openCluster =
                              _openCluster == 'ai_help' ? null : 'ai_help'),
                      onClose: () => setState(() => _openCluster = null),
                      arcStartDeg: 185.0,  // wide arc for 3 items; shifted right so AI CAM stays visible
                      arcEndDeg:   262.0,
                      arcRadius:   100.0,
                      sizeBox:     202.0,
                      items: [
                        ClusterFabItem(
                          icon: Icons.document_scanner,
                          label: 'AI SCAN',
                          color: AppColors.accent,
                          onTap: () => _pushFullScreen(context,
                              ScanPanel(
                                  onClose: () => Navigator.of(context).pop())),
                        ),
                        ClusterFabItem(
                          icon: Icons.smart_toy_outlined,
                          label: 'ASSIST',
                          color: AppColors.primary,
                          onTap: () => _pushFullScreen(context,
                              ChatbotScreen(
                                field:     widget.field,
                                sessionId: ApiService.farmerId?.toString() ??
                                    widget.field.id,
                              )),
                        ),
                        ClusterFabItem(
                          icon: Icons.screen_share_outlined,
                          label: 'SHARE',
                          color: const Color(0xFF00BCD4),
                          onTap: () => _pushFullScreen(context,
                              ScreenSharePanel(
                                field: widget.field,
                                onClose: () => Navigator.of(context).pop(),
                              )),
                        ),
                        ClusterFabItem(
                          icon: Icons.camera_enhance_outlined,
                          label: 'AI CAM',
                          color: const Color(0xFF7C3AED),
                          onTap: () => _pushFullScreen(context,
                              GrapeCountPanel(
                                  onClose: () => Navigator.of(context).pop())),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // ── FARM BOARD cluster (Insights, Soil) ──────
                    ClusterFab(
                      clusterName: 'FARM BOARD',
                      clusterIcon: Icons.dashboard_outlined,
                      clusterColor: const Color(0xFFFBC02D),
                      isOpen: _openCluster == 'farm_board',
                      onToggle: () => setState(() =>
                          _openCluster =
                              _openCluster == 'farm_board' ? null : 'farm_board'),
                      onClose: () => setState(() => _openCluster = null),
                      arcStartDeg: 190.0,  // 2 items: INSIGHTS, SOIL
                      arcEndDeg:   250.0,
                      arcRadius:   88.0,
                      sizeBox:     162.0,
                      items: [
                        ClusterFabItem(
                          icon: Icons.lightbulb_outline,
                          label: 'INSIGHTS',
                          color: const Color(0xFFFBC02D),
                          onTap: () => _pushFullScreen(context,
                              InsightsFullScreen(
                                soilData: widget.field.soilData,
                                fieldLat: widget.field.center[0],
                                fieldLon: widget.field.center[1],
                                plotName: widget.field.plotNameForAnalysis,
                field: widget.field,
                actionableAlerts: widget.actionableAlerts,
                              )),
                        ),
                        ClusterFabItem(
                          icon: Icons.terrain,
                          label: 'SOIL',
                          color: AppColors.secondary,
                          onTap: () => _pushFullScreen(context,
                              SoilPanel(
                                soilData:       widget.field.soilData,
                                polygon:        widget.field.polygon,
                                center:         widget.field.center,
                                plotName:       widget.field.plotNameForAnalysis,
                                plantationDate: widget.field.plantationDate,
                                onClose: () => Navigator.of(context).pop(),
                              )),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // ── MAP LAYERS cluster ────────────────────────
                    MapLayersCluster(
                      key: ValueKey<String>(widget.field.id),
                      isOpen: _openCluster == 'map_layers',
                      onToggle: () => setState(() =>
                          _openCluster =
                              _openCluster == 'map_layers' ? null : 'map_layers'),
                      plotName: widget.field.plotNameForAnalysis,
                      analysisEndDate:
                          DateFormat('yyyy-MM-dd').format(DateTime.now()),
                      onAnalysisLayer: _onPlotAnalysisLayer,
                    ),
                ],
              ),
            ),
          ),
        ),

        // ── BOTTOM STATUS BAR (weather-aware glassmorphism) ──────────
        Positioned(
          bottom: 24, left: 20, right: 82,
          child: Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.25), width: 1),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 20)
                      ],
                    ),
                    child: Row(children: [
                      Row(children: [
                        const Icon(Icons.water_drop,
                            size: 18, color: Color(0xFF4FC3F7)),
                        const SizedBox(width: 6),
                        Text(
                          _weather?.rainMmLastHour != null && _weather!.rainMmLastHour! > 0
                              ? '${(_weather!.rainMmLastHour! * 10).round()}mm rain'
                              : '–– L',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: Colors.white),
                        ),
                      ]),
                      Container(
                          width: 1,
                          height: 20,
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12),
                          color: Colors.white.withOpacity(0.25)),
                      Row(children: [
                        const Icon(Icons.eco,
                            size: 18, color: Color(0xFF81C784)),
                        const SizedBox(width: 6),
                        Text(
                          '–– kg',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: Colors.white),
                        ),
                      ]),
                      const Spacer(),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Field Status',
                                style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white60,
                                    letterSpacing: 1)),
                            Text(
                              _weather == null ? 'LOADING'
                              : (_weather!.condition == WeatherCondition.rain ||
                                 _weather!.condition == WeatherCondition.thunderstorm)
                                  ? 'IRRIGATED' : 'GOOD',
                              style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF69F0AE),
                                  letterSpacing: 1)),
                          ]),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),

        // ── BOTTOM RIGHT: LAND / FIELDS ICON ─────────────────────────
        // Positioned with right: 16 to match all other right-side FABs.
        Positioned(
          bottom: 24, right: 16,
          child: GestureDetector(
            onTap: () => setState(() => _panel = ActivePanel.lands),
            child: Stack(children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF5C6BC0),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10)
                  ],
                ),
                child: const Icon(Icons.landscape,
                    color: Colors.white, size: 22),
              ),
              if (hasAlerts)
                Positioned(
                  top: 0, right: 0,
                  child: Container(
                    width: 16, height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red,
                      border:
                          Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ]),
          ),
        ),

        // ─── MAP SETTINGS MODAL ───────────────────────────────────
        if (_showMapSettings)
          GestureDetector(
            onTap: () =>
                setState(() => _showMapSettings = false),
            child: Container(
              color: Colors.black54,
              child: Center(
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32)),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Expanded(
                              child: Text('Map Details',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900)),
                            ),
                            IconButton(
                                onPressed: () => setState(
                                    () => _showMapSettings = false),
                                icon: const Icon(Icons.close)),
                          ]),
                          const SizedBox(height: 16),
                          const Text('Map Type',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900)),
                          const SizedBox(height: 12),
                          Row(children: [
                            _mapTypeBtn('default', 'Default', '🗺️'),
                            const SizedBox(width: 12),
                            _mapTypeBtn('satellite', 'Satellite', '🛰️'),
                          ]),
                          const SizedBox(height: 12),
                          Row(children: [
                            _mapTypeBtn('mapbox', 'Streets', '🛣️'),
                            const SizedBox(width: 12),
                            _mapTypeBtn('google_satellite', 'Google Sat', '🌍'),
                          ]),
                          const SizedBox(height: 12),
                          Row(children: [
                            _mapTypeBtn('google_hybrid', 'Google Hybrid', '🔀'),
                            const SizedBox(width: 12),
                            const Expanded(child: SizedBox()),
                          ]),
                          const SizedBox(height: 20),
                          const Text('Layers',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900)),
                          const SizedBox(height: 12),
                        ]),
                  ),
                ),
              ),
            ),
          ),

        // ─── PROFILE / SETTINGS PANEL ─────────────────────────────
        if (_showProfile)
          _ProfilePanel(
            userName:      widget.userName,
            plotCount:     widget.fields.length,
            streak:        widget.streak,
            longestStreak: widget.longestStreak,
            loggingOut:    _loggingOut,
            onClose: () => setState(() => _showProfile = false),
            onLogout: () async {
              setState(() => _loggingOut = true);
              await widget.onLogout();
              if (mounted) setState(() => _loggingOut = false);
            },
            onRegisterFace: () => setState(() => _showFaceEnroll = true),
          ),

        // ─── FACE ENROLL FROM PROFILE SETTINGS ───────────────────
        if (_showFaceEnroll)
          Positioned.fill(
            child: _FaceEnrollFromSettings(
              onDone: () => setState(() => _showFaceEnroll = false),
            ),
          ),

        // ─── SIDE PANELS ─────────────────────────────────────────
        if (_panel != ActivePanel.none)
          Positioned.fill(
            child: SidePanelController(
              type: _panel,
              onClose: () =>
                  setState(() => _panel = ActivePanel.none),
              soilData: widget.field.soilData,
              alerts: widget.alerts,
              fields: widget.fields,
              selectedFieldId: widget.field.id,
              onSelectField: widget.onSelectField,
              onDeleteField: widget.onDeleteField,
              onRenameField: widget.onRenameField,
              onAddNewField: widget.onAddNewField,
              onResolveAlert: widget.onResolveAlert,
              fieldLat: widget.field.center[0],
              fieldLon: widget.field.center[1],
            ),
          ),

        // ─── API DEBUG PANEL (long-press FP avatar to open) ───────
        if (_showDebug)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _showDebug = false),
              child: Container(
                color: Colors.black.withOpacity(0.65),
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: ApiDebugPanel(
                      onClose: () => setState(() => _showDebug = false),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _mapBtn({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
    required String tooltip,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary
                : Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.2), blurRadius: 8)
            ],
          ),
          child: Icon(icon,
              color: active ? Colors.white : AppColors.textDark,
              size: 22),
        ),
      );

  Widget _mapTypeBtn(String val, String label, String emoji) =>
      Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _mapType = val),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _mapType == val
                  ? AppColors.greenLight
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _mapType == val
                      ? AppColors.primary
                      : AppColors.borderLight,
                  width: 2),
            ),
            child: Column(children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: _mapType == val
                          ? AppColors.primary
                          : AppColors.textLight)),
            ]),
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════
// PROFILE PANEL
// ═══════════════════════════════════════════════════════════════════
class _ProfilePanel extends StatefulWidget {
  final String userName;
  final int plotCount;
  final int streak;
  final int longestStreak;
  final bool loggingOut;
  final VoidCallback onClose;
  final Future<void> Function() onLogout;
  final VoidCallback onRegisterFace;

  const _ProfilePanel({
    required this.userName,
    required this.plotCount,
    this.streak       = 0,
    this.longestStreak = 0,
    required this.loggingOut,
    required this.onClose,
    required this.onLogout,
    required this.onRegisterFace,
  });

  @override
  State<_ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<_ProfilePanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<Offset> _slide;
  late String _language;
  bool _showLangPicker = false;

  String _localeToLanguage(String code) {
    switch (code) {
      case 'hi': return 'हिंदी (Hindi)';
      case 'mr': return 'मराठी (Marathi)';
      case 'kn': return 'ಕನ್ನಡ (Kannada)';
      default:   return 'English';
    }
  }

  // FIX 6: Only 4 supported languages; each maps to a real locale code
  static const _languages = ['English', 'हिंदी (Hindi)', 'मराठी (Marathi)', 'ಕನ್ನಡ (Kannada)'];
  static const _localeCodes = ['en', 'hi', 'mr', 'kn'];

  @override
  void initState() {
    super.initState();
    _language = _localeToLanguage(appLocale.value.languageCode);
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _slide = Tween<Offset>(
            begin: const Offset(1, 0), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _anim.reverse();
    widget.onClose();
  }

  // Initials
  String get _initials {
    final parts = widget.userName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return widget.userName.isNotEmpty
        ? widget.userName[0].toUpperCase()
        : 'F';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return GestureDetector(
      onTap: _close,
      child: Container(
        color: Colors.black54,
        child: Align(
          alignment: Alignment.topRight,
          child: GestureDetector(
            onTap: () {}, // prevent close on panel tap
            child: SlideTransition(
              position: _slide,
              child: SafeArea(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.80,
                  margin: const EdgeInsets.only(top: 8, right: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 30,
                          offset: const Offset(-4, 4))
                    ],
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    // ── Header ─────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.secondary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28)),
                      ),
                      child: Row(children: [
                        Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.2),
                            border: Border.all(
                                color: Colors.white, width: 2),
                          ),
                          child: Center(
                            child: Text(_initials,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20)),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(widget.userName,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18)),
                                const SizedBox(height: 2),
                                Text(
                                  '${widget.plotCount} ${widget.plotCount == 1 ? 'Plot' : 'Plots'}',
                                  style: TextStyle(
                                      color: Colors.white
                                          .withOpacity(0.8),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                ),
                              ]),
                        ),
                        IconButton(
                          onPressed: _close,
                          icon: const Icon(Icons.close,
                              color: Colors.white, size: 22),
                        ),
                      ]),
                    ),

                    // ── Stats row ──────────────────────────────
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.greenLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceAround,
                          children: [
                            _stat('${widget.plotCount}', 'Plots'),
                            Container(
                                width: 1,
                                height: 36,
                                color: AppColors.borderLight),
                            _stat(t.active, t.status),
                            Container(
                                width: 1,
                                height: 36,
                                color: AppColors.borderLight),
                            _stat('CropEye', t.app),
                          ]),
                    ),

                    // ── Streak Card ─────────────────────────────
                    _StreakCard(
                      streak:        widget.streak,
                      longestStreak: widget.longestStreak,
                    ),

                    // ── Settings label ─────────────────────────
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Text('SETTINGS',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textLight,
                              letterSpacing: 1.5)),
                    ),

                    // ── Language picker ─────────────────────────
                    _settingRow(
                      icon: Icons.language_outlined,
                      label: t.language,
                      trailing: Row(children: [
                        Text(_language,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textMedium)),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right,
                            color: AppColors.textLight, size: 18),
                      ]),
                      onTap: () =>
                          setState(() => _showLangPicker = true),
                    ),

                    if (_showLangPicker) ...[
                      Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: AppColors.borderLight),
                        ),
                        child: Column(
                          children: _languages.map((lang) {
                            final sel = lang == _language;
                            return InkWell(
                              onTap: () {
                                final idx = _languages.indexOf(lang);
                                if (idx >= 0) {
                                  // FIX 6: Switch app locale immediately
                                  appLocale.value = Locale(_localeCodes[idx]);
                                }
                                setState(() {
                                  _language = lang;
                                  _showLangPicker = false;
                                });
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 11),
                                child: Row(children: [
                                  Expanded(
                                    child: Text(lang,
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: sel
                                                ? FontWeight.w900
                                                : FontWeight.w600,
                                            color: sel
                                                ? AppColors.primary
                                                : AppColors.textDark)),
                                  ),
                                  if (sel)
                                    const Icon(Icons.check_circle,
                                        color: AppColors.primary,
                                        size: 18),
                                ]),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],

                    // ── Register Face ──────────────────────────
                    _settingRow(
                      icon: Icons.face_retouching_natural_outlined,
                      label: 'Register Face ID',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('SET UP',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                                letterSpacing: 0.8)),
                      ),
                      onTap: () {
                        widget.onClose();
                        widget.onRegisterFace();
                      },
                    ),

                    const Spacer(),

                    // ── Logout ──────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: widget.loggingOut
                              ? null
                              : widget.onLogout,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade50,
                            foregroundColor: Colors.red.shade700,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(20)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            side: BorderSide(
                                color: Colors.red.shade200, width: 1),
                          ),
                          child: widget.loggingOut
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.red))
                              : Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.logout, size: 18),
                                    const SizedBox(width: 8),
                                    Text(t.signOut,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15)),
                                  ]),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(String value, String label) => Column(children: [
        Text(value,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.primary)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
                letterSpacing: 0.5)),
      ]);

  Widget _settingRow({
    required IconData icon,
    required String label,
    required Widget trailing,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 14),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.greenLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark)),
            ),
            trailing,
          ]),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════
// FACE ENROLL FROM PROFILE SETTINGS
// Shows face enroll screen as an overlay on the dashboard.
// ═══════════════════════════════════════════════════════════════════
class _FaceEnrollFromSettings extends StatelessWidget {
  final VoidCallback onDone;
  const _FaceEnrollFromSettings({required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      child: Column(children: [
        // Header with close button
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              const Text(
                'Register Face ID',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              IconButton(
                onPressed: onDone,
                icon: const Icon(Icons.close, color: Colors.white70),
              ),
            ]),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Register your face to enable one-tap Face ID login in the future.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        Expanded(
          child: FaceAuthScreen(
            mode: FaceAuthMode.enroll,
            onSuccess: onDone,
            onSkip: onDone,
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  MINI LAYER PREVIEW WINDOW  —  StatefulWidget with:
//  • Polygon fills entire window (tight CameraFit)
//  • Pinch-to-zoom + drag enabled
//  • Tap anywhere on map → popup with all layer values from APIs
// ═══════════════════════════════════════════════════════════════════
class _PopupRow extends StatelessWidget {
  final String label, value;
  final Color color;
  const _PopupRow({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
          fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white70)),
      const SizedBox(width: 6),
      Expanded(child: Text(value, style: const TextStyle(
          fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
          textAlign: TextAlign.right)),
    ]),
  );
}
// ═══════════════════════════════════════════════════════════════════
// FOOTPRINT PAINTER — draws a simple boot-print shape
// ═══════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════
//  EARTH ZOOM CURVE  — custom easing for Google Earth fly-in
//  Slow at start (hovering over earth), accelerates through atmosphere,
//  then eases softly as it approaches the field.
// ═══════════════════════════════════════════════════════════════════════════
class _EarthZoomCurve extends Curve {
  const _EarthZoomCurve();

  @override
  double transformInternal(double t) {
    // Phase 1 (0–0.30): very slow pull — looking at the whole earth
    // Phase 2 (0.30–0.75): rapid acceleration — falling through atmosphere
    // Phase 3 (0.75–1.0): decelerate softly — landing on the field
    if (t < 0.30) {
      // Quadratic ease-in: starts almost still
      return (t / 0.30) * (t / 0.30) * 0.05;
    } else if (t < 0.75) {
      // Exponential burst
      final s = (t - 0.30) / 0.45;
      return 0.05 + s * s * s * 0.80;
    } else {
      // Ease-out landing
      final s = (t - 0.75) / 0.25;
      return 0.85 + (1 - (1 - s) * (1 - s)) * 0.15;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  GOOGLE MAPS STYLE NAVIGATION ARROW
//  Matches the provided reference image: cyan arrow on transparent bg,
//  pointing upward with a notched tail (the "A" / arrowhead shape).
// ═══════════════════════════════════════════════════════════════════════════
class _GoogleMapsArrowPainter extends CustomPainter {
  const _GoogleMapsArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Drop-shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.30)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Main arrow fill — cyan matching the reference
    final fillPaint = Paint()
      ..color = const Color(0xFF29B6F6)
      ..style = PaintingStyle.fill;

    // Build the Google Maps arrow path:
    //  • Tip: top-centre
    //  • Left side: curves down-left
    //  • Notch: concave cutout at bottom-centre (like reference image)
    //  • Right side: mirrors left
    final path = ui.Path();

    // Tip — top centre
    path.moveTo(w * 0.50, h * 0.04);

    // Left edge — sweep down and out
    path.cubicTo(
      w * 0.50, h * 0.04,
      w * 0.05, h * 0.72,
      w * 0.10, h * 0.78,
    );

    // Left wing bottom
    path.lineTo(w * 0.18, h * 0.72);

    // Inner notch — left side curves to bottom centre
    path.cubicTo(
      w * 0.28, h * 0.65,
      w * 0.38, h * 0.60,
      w * 0.50, h * 0.62,
    );

    // Inner notch — bottom centre to right side
    path.cubicTo(
      w * 0.62, h * 0.60,
      w * 0.72, h * 0.65,
      w * 0.82, h * 0.72,
    );

    // Right wing bottom
    path.lineTo(w * 0.90, h * 0.78);

    // Right edge — sweep up to tip
    path.cubicTo(
      w * 0.95, h * 0.72,
      w * 0.50, h * 0.04,
      w * 0.50, h * 0.04,
    );

    path.close();

    // Draw shadow slightly offset
    canvas.save();
    canvas.translate(0, 2);
    canvas.drawPath(path, shadowPaint);
    canvas.restore();

    // Draw main fill
    canvas.drawPath(path, fillPaint);

    // White outline for crisp edge
    final outlinePaint = Paint()
      ..color = Colors.white.withOpacity(0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, outlinePaint);
  }

  @override
  bool shouldRepaint(_GoogleMapsArrowPainter _) => false;
}

class _FootprintPainter extends CustomPainter {
  final bool isLeft;
  const _FootprintPainter({required this.isLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Mirror for right foot
    if (!isLeft) {
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
    }

    // ── Foot silhouette matching reference image ───────────────────────
    // Drawn in a normalised 0→1 space then scaled to canvas size.
    // Shape: rounded heel at bottom, narrows at arch, widens at ball,
    // big toe curves up-left, smaller toes step down to the right.

    final path = ui.Path();

    // Helper to convert normalised coords to canvas coords
    Offset p(double nx, double ny) => Offset(nx * w, ny * h);

    // Start at heel bottom-left
    path.moveTo(p(0.35, 0.95).dx, p(0.35, 0.95).dy);

    // Heel — rounded bottom
    path.cubicTo(
      p(0.10, 0.95).dx, p(0.10, 0.95).dy,   // control 1
      p(0.05, 0.82).dx, p(0.05, 0.82).dy,   // control 2
      p(0.10, 0.72).dx, p(0.10, 0.72).dy,   // end: heel left side mid
    );

    // Arch — inner edge curves inward
    path.cubicTo(
      p(0.14, 0.58).dx, p(0.14, 0.58).dy,
      p(0.18, 0.48).dx, p(0.18, 0.48).dy,
      p(0.22, 0.40).dx, p(0.22, 0.40).dy,
    );

    // Ball of foot — widens
    path.cubicTo(
      p(0.20, 0.28).dx, p(0.20, 0.28).dy,
      p(0.18, 0.18).dx, p(0.18, 0.18).dy,
      p(0.22, 0.12).dx, p(0.22, 0.12).dy,
    );

    // Big toe — rounds up
    path.cubicTo(
      p(0.24, 0.04).dx, p(0.24, 0.04).dy,
      p(0.40, 0.01).dx, p(0.40, 0.01).dy,
      p(0.48, 0.06).dx, p(0.48, 0.06).dy,
    );

    // 2nd toe
    path.cubicTo(
      p(0.54, 0.10).dx, p(0.54, 0.10).dy,
      p(0.60, 0.05).dx, p(0.60, 0.05).dy,
      p(0.64, 0.09).dx, p(0.64, 0.09).dy,
    );

    // 3rd toe
    path.cubicTo(
      p(0.70, 0.13).dx, p(0.70, 0.13).dy,
      p(0.74, 0.09).dx, p(0.74, 0.09).dy,
      p(0.77, 0.14).dx, p(0.77, 0.14).dy,
    );

    // 4th toe
    path.cubicTo(
      p(0.82, 0.18).dx, p(0.82, 0.18).dy,
      p(0.84, 0.15).dx, p(0.84, 0.15).dy,
      p(0.86, 0.20).dx, p(0.86, 0.20).dy,
    );

    // 5th (little) toe — smallest
    path.cubicTo(
      p(0.89, 0.24).dx, p(0.89, 0.24).dy,
      p(0.90, 0.22).dx, p(0.90, 0.22).dy,
      p(0.91, 0.27).dx, p(0.91, 0.27).dy,
    );

    // Outer right edge of ball — curves down
    path.cubicTo(
      p(0.92, 0.34).dx, p(0.92, 0.34).dy,
      p(0.90, 0.42).dx, p(0.90, 0.42).dy,
      p(0.86, 0.50).dx, p(0.86, 0.50).dy,
    );

    // Outer edge — heel right
    path.cubicTo(
      p(0.88, 0.62).dx, p(0.88, 0.62).dy,
      p(0.88, 0.75).dx, p(0.88, 0.75).dy,
      p(0.82, 0.88).dx, p(0.82, 0.88).dy,
    );

    // Heel bottom-right
    path.cubicTo(
      p(0.76, 0.97).dx, p(0.76, 0.97).dy,
      p(0.58, 0.99).dx, p(0.58, 0.99).dy,
      p(0.35, 0.95).dx, p(0.35, 0.95).dy,
    );

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_FootprintPainter old) => old.isLeft != isLeft;
}

// ═══════════════════════════════════════════════════════════════════════════
//  FIX 4 — WEATHER FORECAST SHEET
//  Full today's weather shown when farmer taps the weather symbol badge.
// ═══════════════════════════════════════════════════════════════════════════
class _WeatherForecastSheet extends StatelessWidget {
  final WeatherData weather;
  const _WeatherForecastSheet({required this.weather});

  String _condIcon(WeatherCondition c) {
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

  String _windDir(double deg) {
    const dirs = ['N','NE','E','SE','S','SW','W','NW'];
    return dirs[((deg + 22.5) / 45).floor() % 8];
  }

  // Pick a soft gradient based on condition
  List<Color> _bgGradient(WeatherCondition c) {
    switch (c) {
      case WeatherCondition.clearDay:
        return [const Color(0xFFFFF9ED), const Color(0xFFFFF3CC)];
      case WeatherCondition.clearNight:
        return [const Color(0xFFEEF2FF), const Color(0xFFE0E7FF)];
      case WeatherCondition.partlyCloudyDay:
        return [const Color(0xFFF0FDF4), const Color(0xFFDCFCE7)];
      case WeatherCondition.partlyCloudyNight:
        return [const Color(0xFFF5F3FF), const Color(0xFFEDE9FE)];
      case WeatherCondition.cloudy:
        return [const Color(0xFFF8FAFC), const Color(0xFFEFF2F7)];
      case WeatherCondition.rain:
        return [const Color(0xFFF0F7FF), const Color(0xFFDBEAFE)];
      case WeatherCondition.thunderstorm:
        return [const Color(0xFFF5F3FF), const Color(0xFFDDD6FE)];
      case WeatherCondition.snow:
        return [const Color(0xFFF0F9FF), const Color(0xFFE0F2FE)];
      case WeatherCondition.foggy:
        return [const Color(0xFFF9FAFB), const Color(0xFFF3F4F6)];
    }
  }

  Color _accentColor(WeatherCondition c) {
    switch (c) {
      case WeatherCondition.clearDay:          return const Color(0xFFF59E0B);
      case WeatherCondition.clearNight:        return const Color(0xFF6366F1);
      case WeatherCondition.partlyCloudyDay:   return const Color(0xFF10B981);
      case WeatherCondition.partlyCloudyNight: return const Color(0xFF8B5CF6);
      case WeatherCondition.cloudy:            return const Color(0xFF64748B);
      case WeatherCondition.rain:              return const Color(0xFF3B82F6);
      case WeatherCondition.thunderstorm:      return const Color(0xFF7C3AED);
      case WeatherCondition.snow:              return const Color(0xFF0EA5E9);
      case WeatherCondition.foggy:             return const Color(0xFF94A3B8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = weather;
    final t = AppStrings.of(context);
    final condition = w.condition;
    final accent = _accentColor(condition);
    final gradient = _bgGradient(condition);
    // Text colours for light background
    const textDark   = Color(0xFF1A2E1B);
    const textMedium = Color(0xFF4B5563);
    const textLight  = Color(0xFF9CA3AF);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: accent.withOpacity(0.20), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle bar
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.25),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 20),

        // Location + date row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(children: [
            Icon(Icons.location_on_rounded, color: accent, size: 16),
            const SizedBox(width: 4),
            Expanded(child: Text(
              w.cityName.isNotEmpty ? w.cityName : 'Your Field',
              style: TextStyle(color: textDark, fontSize: 13, fontWeight: FontWeight.w800),
            )),
            Text(
              DateFormat('EEEE, d MMM').format(DateTime.now()),
              style: const TextStyle(color: textLight, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ]),
        ),
        const SizedBox(height: 24),

        // Main temp + condition
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_condIcon(condition), style: const TextStyle(fontSize: 60)),
          const SizedBox(width: 20),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${w.tempC.round()}°C',
                style: TextStyle(
                    fontSize: 54,
                    fontWeight: FontWeight.w900,
                    color: textDark,
                    height: 1)),
            Text(w.description.toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accent,
                    letterSpacing: 1.5)),
          ]),
        ]),
        const SizedBox(height: 24),

        // Stats grid — row 1
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _stat('🌡️', t.feelsLike,  '${w.feelsLikeC.round()}°C', accent),
            _stat('💧', t.humidity,   '${w.humidity}%', accent),
            _stat('💨', t.wind,       '${w.windSpeedMs.toStringAsFixed(1)} m/s', accent),
            _stat('🧭', t.direction,  _windDir(w.windDeg), accent),
          ]),
        ),
        const SizedBox(height: 10),

        // Stats grid — row 2
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _stat('☁️', t.cloudCover, '${w.cloudCoverPct.round()}%', accent),
            _stat('🌧️', t.rain1h,
                w.rainMmLastHour != null
                    ? '${w.rainMmLastHour!.toStringAsFixed(1)} mm'
                    : '0.0 mm',
                accent),
            _stat(w.isDay ? '🌅' : '🌙', t.time,
                w.isDay ? t.daytime : t.night, accent),
            _stat('🌿', t.irrigationLabel,
                (w.condition == WeatherCondition.rain ||
                    w.condition == WeatherCondition.thunderstorm)
                    ? t.notNeeded
                    : t.checkField,
                accent),
          ]),
        ),
        const SizedBox(height: 20),

        // Farming tip banner
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withOpacity(0.25)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('🌾', style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(child: Text(
              _farmingTip(w),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: textDark,
                  height: 1.5),
            )),
          ]),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _stat(String emoji, String label, String value, Color accent) =>
      Expanded(
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.60),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1A2E1B)),
                    maxLines: 1),
              ),
              const SizedBox(height: 3),
              Text(label,
                  style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  String _farmingTip(WeatherData w) {
    if (w.condition == WeatherCondition.rain ||
        w.condition == WeatherCondition.thunderstorm)
      return 'Rain expected — skip irrigation today. Check for waterlogging in low-lying areas.';
    if (w.condition == WeatherCondition.foggy)
      return 'Foggy conditions — watch for fungal disease. Avoid spraying pesticides.';
    if (w.tempC > 35)
      return 'High heat — irrigate in early morning or evening to reduce evaporation losses.';
    if (w.windSpeedMs > 8)
      return 'Strong winds — avoid spraying fertilisers or pesticides. Secure loose covers.';
    if (w.humidity > 80)
      return 'High humidity — risk of fungal infections. Monitor crops closely.';
    return 'Good farming conditions today. Ideal time for field inspection and routine work.';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  STREAK CARD — shown inside _ProfilePanel
// ═══════════════════════════════════════════════════════════════════════════

class _StreakCard extends StatefulWidget {
  final int streak;
  final int longestStreak;

  const _StreakCard({required this.streak, required this.longestStreak});

  @override
  State<_StreakCard> createState() => _StreakCardState();
}

class _StreakCardState extends State<_StreakCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _flicker;
  late Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _flicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _flicker, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  // Progress toward next milestone (0.0 – 1.0)
  double _progress(int streak) {
    final milestones = [1, 3, 7, 14, 30, 100, 365];
    for (final m in milestones) {
      if (streak < m) {
        final prev = milestones[milestones.indexOf(m) - 1 < 0
            ? 0
            : milestones.indexOf(m) - 1];
        return (streak - prev) / (m - prev).clamp(1, 999).toDouble();
      }
    }
    return 1.0;
  }

  int _nextMilestone(int streak) {
    for (final m in [1, 3, 7, 14, 30, 100, 365]) {
      if (streak < m) return m;
    }
    return streak + 1;
  }

  @override
  Widget build(BuildContext context) {
    final streak  = widget.streak;
    final longest = widget.longestStreak;
    final emoji   = StreakService.streakEmoji(streak);
    final label   = StreakService.streakLabel(streak);
    final next    = _nextMilestone(streak);
    final prog    = _progress(streak);

    // Colour theme: cold (grey) when no streak, warm (orange→red) as it grows
    final Color cardBg;
    final Color flameColor;
    final Color textColor;
    if (streak == 0) {
      cardBg     = const Color(0xFFF5F5F5);
      flameColor = Colors.grey.shade400;
      textColor  = Colors.grey.shade600;
    } else if (streak < 7) {
      cardBg     = const Color(0xFFFFF8E1);
      flameColor = const Color(0xFFFFA000);
      textColor  = const Color(0xFFE65100);
    } else if (streak < 30) {
      cardBg     = const Color(0xFFFFF3E0);
      flameColor = const Color(0xFFFF6D00);
      textColor  = const Color(0xFFBF360C);
    } else {
      cardBg     = const Color(0xFFFFEBEE);
      flameColor = const Color(0xFFD50000);
      textColor  = const Color(0xFFB71C1C);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: streak > 0 ? flameColor.withOpacity(0.35) : Colors.grey.shade200,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: flame + count + label ───────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                // Animated flame emoji
                AnimatedBuilder(
                  animation: _glow,
                  builder: (_, child) => Transform.scale(
                    scale: streak > 0 ? (0.92 + 0.08 * _glow.value) : 1.0,
                    child: child,
                  ),
                  child: Text(emoji,
                      style: TextStyle(
                          fontSize: streak > 0 ? 36 : 28)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$streak',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: streak > 0 ? textColor : Colors.grey.shade400,
                              height: 1.0,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5, left: 4),
                            child: Text(
                              streak == 1 ? 'day' : 'days',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: textColor.withOpacity(0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: streak > 0
                              ? flameColor.withOpacity(0.15)
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: streak > 0 ? flameColor : Colors.grey.shade500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Longest streak pill
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Best',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade500),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text('🏅', style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 3),
                        Text(
                          '$longest',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Progress bar toward next milestone ────────────────────
          if (streak < 365) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Next milestone: $next days',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  Text(
                    '${streak}/$next',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: streak > 0 ? flameColor : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: prog.clamp(0.0, 1.0),
                  minHeight: 7,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    streak > 0 ? flameColor : Colors.grey.shade300,
                  ),
                ),
              ),
            ),
          ],

          // ── Milestone chips row ───────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(
              children: [
                for (final m in [1, 3, 7, 14, 30, 100, 365])
                  _MilestoneChip(
                    days:     m,
                    achieved: streak >= m,
                    isCurrent: streak < m &&
                        (m == _nextMilestone(streak)),
                    flameColor: flameColor,
                  ),
              ],
            ),
          ),

          // ── Zero-streak nudge ─────────────────────────────────────
          if (streak == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                '🌱 Open the app every day to build your streak!',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Milestone chip ─────────────────────────────────────────────────────────

class _MilestoneChip extends StatelessWidget {
  final int days;
  final bool achieved;
  final bool isCurrent;
  final Color flameColor;

  const _MilestoneChip({
    required this.days,
    required this.achieved,
    required this.isCurrent,
    required this.flameColor,
  });

  String _label(int d) {
    if (d >= 365) return '1yr';
    if (d >= 30)  return '${d}d';
    return '${d}d';
  }

  String _emoji(int d) {
    if (d >= 365) return '🏆';
    if (d >= 100) return '💎';
    if (d >= 30)  return '🌟';
    if (d >= 14)  return '🔥';
    if (d >= 7)   return '⚡';
    if (d >= 3)   return '🌿';
    return '🌱';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: achieved
            ? flameColor.withOpacity(0.15)
            : isCurrent
                ? flameColor.withOpacity(0.06)
                : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: achieved
              ? flameColor.withOpacity(0.5)
              : isCurrent
                  ? flameColor.withOpacity(0.3)
                  : Colors.grey.shade300,
          width: isCurrent ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_emoji(days), style: TextStyle(
            fontSize: 12,
            color: achieved ? null : const Color(0x88000000),
          )),
          const SizedBox(width: 4),
          Text(
            _label(days),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: achieved
                  ? flameColor
                  : isCurrent
                      ? flameColor.withOpacity(0.7)
                      : Colors.grey.shade400,
            ),
          ),
          if (achieved) ...[
            const SizedBox(width: 3),
            Icon(Icons.check_circle_rounded,
                size: 11, color: flameColor),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  STREAK TOAST — animated celebration shown on new-day open
// ═══════════════════════════════════════════════════════════════════════════

class _StreakToast extends StatefulWidget {
  final int streak;
  final VoidCallback onDismiss;

  const _StreakToast({required this.streak, required this.onDismiss});

  @override
  State<_StreakToast> createState() => _StreakToastState();
}

class _StreakToastState extends State<_StreakToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.4)));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _message {
    final s = widget.streak;
    if (s == 1)       return "First day! Let's build that streak 🌱";
    if (s < 7)        return '$s days in a row! Keep going! 💪';
    if (s == 7)       return "One full week! You're on fire! 🔥";
    if (s < 14)       return '$s days strong! Amazing dedication! ⚡';
    if (s == 14)      return "Two weeks! You're a true farmer! 🌾";
    if (s < 30)       return '$s day streak! Nothing stops you! 🌟';
    if (s == 30)      return 'One month streak! Legendary! 🏆';
    if (s < 100)      return '$s days! Your crops feel the love 💎';
    if (s == 100)     return '100 DAYS! Diamond farmer! 💎👑';
    if (s >= 365)     return "365 days! You're a CropEye Legend! 🏆";
    return '$s day streak! Incredible! 🔥';
  }

  @override
  Widget build(BuildContext context) {
    final emoji = StreakService.streakEmoji(widget.streak);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(scale: _scale.value, child: child),
      ),
      child: GestureDetector(
        onTap: widget.onDismiss,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF6D00), Color(0xFFFFA000)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withOpacity(0.45),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text(
                        '🔥 STREAK',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${widget.streak} ${widget.streak == 1 ? "DAY" : "DAYS"}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 3),
                    Text(
                      _message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.close, color: Colors.white70, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════════════════════
//  _FloatingFieldPopup
//  Small vertical card that appears exactly at the tap point.
//  Shows live API values: Soil Moisture, Water Uptake, Growth, Pest, NPK.
//  Auto-dismisses after 7 s. Tap outside to close early.
// ═══════════════════════════════════════════════════════════════════════════

class _FloatingFieldPopup extends StatefulWidget {
  final Offset tapPos;
  final Map<String, String>? values;
  final bool isLoading;
  final VoidCallback onDismiss;
  final VoidCallback onRetry;
  final void Function(ActivePanel) onNavigate;

  const _FloatingFieldPopup({
    required this.tapPos,
    required this.values,
    required this.isLoading,
    required this.onDismiss,
    required this.onRetry,
    required this.onNavigate,
  });

  @override
  State<_FloatingFieldPopup> createState() => _FloatingFieldPopupState();
}

class _FloatingFieldPopupState extends State<_FloatingFieldPopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;

  static const double _cardW  = 148;
  static const double _cardH  = 185;
  static const double _margin = 12;

  // Metric definitions: (emoji key, label, target panel)
  static const _rows = [
    ('💧', 'Soil Moisture',  ActivePanel.soilMoisture),  // → Farm Insights 7-day moisture chart
    ('🌊', 'Water Uptake',   ActivePanel.waterUptake),   // → Irrigation Depth Analysis
    ('🐛', 'Pest Risk',      ActivePanel.pestRisk),      // → Entomological Forecast
    ('🌾', 'N-P-K',          ActivePanel.soil),          // → Soil Nutrients panel
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 240));
    _scale = Tween<double>(begin: 0.78, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade  = Tween<double>(begin: 0.0,  end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.4)));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Offset _clampedPos(Size screen) {
    double left = widget.tapPos.dx - _cardW / 2;
    double top  = widget.tapPos.dy - _cardH - 14;
    if (top < _margin) top = widget.tapPos.dy + 16;
    left = left.clamp(_margin, screen.width  - _cardW  - _margin);
    top  = top .clamp(_margin, screen.height - _cardH  - _margin);
    return Offset(left, top);
  }

  // Colour-code value text based on content
  Color _valueColor(String emoji, String val) {
    if (val == '--') return Colors.white24;
    switch (emoji) {
      case '💧': // soil moisture: <40 bad, 40-80 ok, >80 high
        final n = double.tryParse(val.replaceAll('%', '').trim());
        if (n == null) return Colors.white;
        if (n >= 60) return const Color(0xFF4FC3F7);  // good — blue
        if (n >= 30) return const Color(0xFF81C784);  // ok — green
        return const Color(0xFFFFB74D);               // low — orange
      case '🌊': // water: higher adequate = greener
        final n = double.tryParse(val.split('%').first.trim());
        if (n == null) return Colors.white;
        if (n >= 60) return const Color(0xFF4FC3F7);
        if (n >= 30) return const Color(0xFF81C784);
        return const Color(0xFFFFB74D);
      case '🐛': // pest: HIGH=red MOD=amber LOW=green
        if (val.contains('HIGH')) return const Color(0xFFEF5350);
        if (val.contains('MOD'))  return const Color(0xFFFFB74D);
        if (val.contains('LOW'))  return const Color(0xFF81C784);
        return Colors.white;
      default:
        return Colors.white;
    }
  }

  Widget _row(String emoji, String label, String? rawVal, ActivePanel panel) {
    final val   = rawVal ?? '--';
    final color = _valueColor(emoji, val);
    return GestureDetector(
      onTap: () => widget.onNavigate(panel),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(val,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                color: Colors.white.withOpacity(0.2), size: 12),
          ],
        ),
      ),
    );
  }

  bool get _allMissing =>
      widget.values != null &&
      widget.values!.values.every((v) => v == '--');

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final pos    = _clampedPos(screen);

    return Stack(
      children: [
        // Full-screen tap-outside dismiss
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onDismiss,
          ),
        ),

        Positioned(
          left: pos.dx,
          top:  pos.dy,
          width: _cardW,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) => Opacity(
              opacity: _fade.value,
              child: Transform.scale(scale: _scale.value, child: child),
            ),
            child: GestureDetector(
              onTap: () {},   // swallow so Positioned.fill doesn't fire
              child: Container(
                padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1A0B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF2E7D32).withOpacity(0.6),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 20,
                      offset: const Offset(0, 5),
                    ),
                    BoxShadow(
                      color: const Color(0xFF2E7D32).withOpacity(0.15),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Header ────────────────────────────────────────
                    Row(children: [
                      Container(
                        width: 18, height: 18,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Center(
                          child: Text('📊', style: TextStyle(fontSize: 10)),
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text('Field Stats',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: widget.onDismiss,
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white24, size: 13),
                      ),
                    ]),
                    const SizedBox(height: 7),
                    Container(height: 0.8,
                        color: Colors.white.withOpacity(0.08)),
                    const SizedBox(height: 6),

                    // ── Body ──────────────────────────────────────────
                    if (widget.isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(child: SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: AppColors.primary, strokeWidth: 2),
                        )),
                      )
                    else ...[
                      for (final r in _rows)
                        _row(r.$1, r.$2, widget.values?[r.$1], r.$3),

                      // Retry button when all values failed
                      if (_allMissing) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: widget.onRetry,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                  color: AppColors.primary.withOpacity(0.4)),
                            ),
                            child: const Center(
                              child: Text('↻  Retry',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                )),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}


// ═══════════════════════════════════════════════════════════════════════════
//  MAP LAYERS BUTTON
//  Single button above the nav arrow. Tap to expand 3 map options:
//    • Satellite  — Google high-res satellite (best for farming, field detail)
//    • Terrain    — Google Terrain (elevation, contours, great for slope view)
//    • Street     — OpenStreetMap standard (road labels, offline-friendly)
//
//  Best free tile options used:
//    Satellite : Google Maps lyrs=s  — clearest imagery, no key needed
//    Terrain   : Google Maps lyrs=p  — physical terrain with labels
//    Street    : OpenStreetMap.org   — open-source, always free, great detail
// ═══════════════════════════════════════════════════════════════════════════
class _MapLayersButton extends StatefulWidget {
  final String current;
  final ValueChanged<String> onChanged;

  const _MapLayersButton({required this.current, required this.onChanged});

  @override
  State<_MapLayersButton> createState() => _MapLayersButtonState();
}

class _MapLayersButtonState extends State<_MapLayersButton>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  static const _options = [
    ('satellite', '🛰️', 'Satellite', 'Google high-res imagery'),
    ('esri',      '🌍', 'ESRI',      'World imagery, sharp tiles'),
    ('terrain',   '🏔️', 'Terrain',   'Elevation & contour lines'),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 220));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(-0.3, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Expanded options (slide in from left) ──────────────────
        if (_expanded)
          FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.72),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(0.30),
                    blurRadius: 16, offset: const Offset(0, 4),
                  )],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header label
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text('MAP TYPE',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: Colors.white.withOpacity(0.45),
                            letterSpacing: 1.5,
                          )),
                    ),
                    const SizedBox(height: 4),
                    ..._options.map((opt) {
                      final (type, emoji, label, desc) = opt;
                      final active = widget.current == type;
                      return GestureDetector(
                        onTap: () {
                          widget.onChanged(type);
                          _toggle(); // close after selection
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.only(bottom: 3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.primary.withOpacity(0.88)
                                : Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: active
                                  ? AppColors.primary
                                  : Colors.white.withOpacity(0.08),
                              width: active ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(emoji,
                                  style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(label,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: active
                                            ? Colors.white
                                            : Colors.white70,
                                      )),
                                  Text(desc,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: active
                                            ? Colors.white70
                                            : Colors.white38,
                                      )),
                                ],
                              ),
                              if (active) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.check_circle_rounded,
                                    color: Colors.white, size: 14),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),

        // ── Single trigger button ───────────────────────────────────
        GestureDetector(
          onTap: _toggle,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: _expanded
                      ? AppColors.primary.withOpacity(0.85)
                      : Colors.black.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _expanded
                        ? AppColors.primary
                        : Colors.white.withOpacity(0.15),
                    width: 1.5,
                  ),
                  boxShadow: _expanded ? [
                    BoxShadow(color: AppColors.primary.withOpacity(0.40),
                        blurRadius: 12, offset: const Offset(0, 4)),
                  ] : [],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _expanded ? Icons.close_rounded : Icons.layers_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _expanded ? 'CLOSE' : 'LAYERS',
                      style: const TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}


// ═══════════════════════════════════════════════════════════════════════════
//  _FloatingLayerPolygon  —  real FlutterMap, bidirectional zoom sync
//
//  • Small 140×140 FlutterMap with its own MapController (_miniCtrl)
//  • Satellite tiles + heatmap layer + polygon outline
//  • Main map zoom/pan → mini map synced via _mainSub stream
//  • Mini map zoom/pan → main map synced via _miniSub stream
//  • Pinch-to-zoom + drag enabled on the mini map
//  • Layer badge top-left, no card border — just a rounded map tile
// ═══════════════════════════════════════════════════════════════════════════
class _FloatingLayerPolygon extends StatefulWidget {
  final List<List<double>> polygon;
  final String             layerLabel;
  final String             tileUrl;
  final MapController      mapCtrl;   // main map controller

  const _FloatingLayerPolygon({
    required this.polygon,
    required this.layerLabel,
    required this.tileUrl,
    required this.mapCtrl,
  });

  @override
  State<_FloatingLayerPolygon> createState() => _FloatingLayerPolygonState();
}

class _FloatingLayerPolygonState extends State<_FloatingLayerPolygon> {
  final MapController _miniCtrl = MapController();
  StreamSubscription<MapEvent>? _miniSub;
  StreamSubscription<MapEvent>? _mainSub;
  bool _syncing = false; // single flag prevents both directions firing at once

  Color get _layerColor {
    switch (widget.layerLabel.toUpperCase()) {
      case 'GROWTH': return const Color(0xFF43A047);
      case 'WATER':  return const Color(0xFF0288D1);
      case 'SOIL':   return const Color(0xFF8D6E63);
      case 'PESTS':  return const Color(0xFFE53935);
      default:       return const Color(0xFF2E7D32);
    }
  }

  String get _emoji {
    switch (widget.layerLabel.toUpperCase()) {
      case 'GROWTH': return '🌱';
      case 'WATER':  return '💧';
      case 'SOIL':   return '🏔️';
      case 'PESTS':  return '🐛';
      default:       return '📊';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Mini → main: only on user gesture events, not programmatic moves
      _miniSub = _miniCtrl.mapEventStream.listen((e) {
        if (_syncing) return;
        if (e is MapEventMoveStart || e is MapEventDoubleTapZoom ||
            e is MapEventScrollWheelZoom || e is MapEventFlingAnimation) {
          _syncing = true;
          widget.mapCtrl.move(e.camera.center, e.camera.zoom);
          Future.microtask(() => _syncing = false);
        }
      });
      // Main → mini: only on user gesture events
      _mainSub = widget.mapCtrl.mapEventStream.listen((e) {
        if (_syncing) return;
        if (e is MapEventMoveStart || e is MapEventDoubleTapZoom ||
            e is MapEventScrollWheelZoom || e is MapEventFlingAnimation) {
          _syncing = true;
          _miniCtrl.move(e.camera.center, e.camera.zoom);
          Future.microtask(() => _syncing = false);
        }
      });
    });
  }

  @override
  void dispose() {
    _miniSub?.cancel();
    _mainSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.polygon.map((p) => LatLng(p[0], p[1])).toList();
    if (pts.length < 3) return const SizedBox.shrink();

    final lats = pts.map((p) => p.latitude).toList();
    final lngs = pts.map((p) => p.longitude).toList();
    final color = _layerColor;

    const double w = 240;
    const double h = 220;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: w, height: h,
        child: Stack(children: [
          // ── Real FlutterMap ──────────────────────────────────────────
          FlutterMap(
            mapController: _miniCtrl,
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: LatLngBounds(
                  LatLng(lats.reduce((a,b)=>a<b?a:b), lngs.reduce((a,b)=>a<b?a:b)),
                  LatLng(lats.reduce((a,b)=>a>b?a:b), lngs.reduce((a,b)=>a>b?a:b)),
                ),
                padding: const EdgeInsets.all(6),
                maxZoom: 22,
              ),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
              ),
            ),
            children: [
              // Satellite base
              TileLayer(
                urlTemplate: 'http://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
                maxZoom: 22,
                userAgentPackageName: 'com.example.cropeye',
              ),
              // Heatmap layer
              Opacity(
                opacity: 0.85,
                child: TileLayer(urlTemplate: widget.tileUrl, maxZoom: 22),
              ),
              // Polygon outline
              PolygonLayer(polygons: [
                Polygon(
                  points: pts,
                  color: Colors.transparent,
                  borderColor: color.withOpacity(0.90),
                  borderStrokeWidth: 2.0,
                ),
              ]),
            ],
          ),

          // ── Layer badge top-left ──────────────────────────────────
          Positioned(
            top: 6, left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.90),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 4,
                )],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_emoji, style: const TextStyle(fontSize: 9)),
                const SizedBox(width: 3),
                Text(widget.layerLabel,
                  style: const TextStyle(
                    fontSize: 8, fontWeight: FontWeight.w900,
                    color: Colors.white, letterSpacing: 0.4,
                  )),
              ]),
            ),
          ),

          // ── Zoom buttons top-right ────────────────────────────────
          Positioned(
            top: 4, right: 4,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _miniZoomBtn(Icons.add, () {
                final z = (_miniCtrl.camera.zoom + 0.8).clamp(1.0, 22.0);
                _syncing = true;
                _miniCtrl.move(_miniCtrl.camera.center, z);
                widget.mapCtrl.move(_miniCtrl.camera.center, z);
                Future.microtask(() => _syncing = false);
              }),
              const SizedBox(height: 3),
              _miniZoomBtn(Icons.remove, () {
                final z = (_miniCtrl.camera.zoom - 0.8).clamp(1.0, 22.0);
                _syncing = true;
                _miniCtrl.move(_miniCtrl.camera.center, z);
                widget.mapCtrl.move(_miniCtrl.camera.center, z);
                Future.microtask(() => _syncing = false);
              }),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _miniZoomBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 14),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _AlertPin  —  pulsing map pin shown at plant-level alert location
// ═══════════════════════════════════════════════════════════════════════════
class _AlertPin extends StatefulWidget {
  final String       type;
  final VoidCallback onDismiss;
  const _AlertPin({required this.type, required this.onDismiss});
  @override State<_AlertPin> createState() => _AlertPinState();
}

class _AlertPinState extends State<_AlertPin>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _pulse;

  Color get _color {
    switch (widget.type) {
      case 'pest':    return const Color(0xFFE53935);
      case 'water':   return const Color(0xFF0288D1);
      case 'soil':    return const Color(0xFF8D6E63);
      case 'growth':  return const Color(0xFF43A047);
      case 'weather': return const Color(0xFF7B68EE);
      case 'harvest': return const Color(0xFFFBC02D);
      default:        return const Color(0xFFE53935);
    }
  }

  String get _emoji {
    switch (widget.type) {
      case 'pest':    return '🐛';
      case 'water':   return '💧';
      case 'soil':    return '🟤';
      case 'growth':  return '🌱';
      case 'weather': return '⛅';
      case 'harvest': return '🌾';
      default:        return '⚠️';
    }
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return GestureDetector(
      onTap: widget.onDismiss,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing ring + pin head
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) => Stack(
              alignment: Alignment.center,
              children: [
                // Outer pulsing ring
                Container(
                  width: 56 * _pulse.value,
                  height: 56 * _pulse.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(0.18 * _pulse.value),
                    border: Border.all(
                        color: color.withOpacity(0.5 * _pulse.value),
                        width: 2),
                  ),
                ),
                // Middle ring
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(0.25),
                    border: Border.all(color: color.withOpacity(0.7), width: 2),
                  ),
                ),
                // Pin head
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.7),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(_emoji,
                        style: const TextStyle(fontSize: 11)),
                  ),
                ),
              ],
            ),
          ),
          // Pin stem
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.5), blurRadius: 4),
              ],
            ),
          ),
          // Stem tip
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
