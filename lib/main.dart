import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'constants/app_constants.dart';
import 'screens/onboarding_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/add_plot_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/no_plots_screen.dart';
import 'screens/face_auth_screen.dart';
import 'screens/alert_feed_screen.dart';
import 'services/plot_layer_api.dart';
import 'services/api_service.dart';
import 'services/soil_param_api.dart';
import 'services/streak_service.dart';
import 'services/notification_service.dart';

// FIX 6: Global locale notifier — changed by ProfilePanel language picker
final ValueNotifier<Locale> appLocale = ValueNotifier(const Locale('en'));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: 'assets/.env', isOptional: true);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const CropEyeApp());
}

class CropEyeApp extends StatelessWidget {
  const CropEyeApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Locale>(
    valueListenable: appLocale,
    builder: (_, locale, __) => MaterialApp(
      title: 'CropEye',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      locale: locale,
      supportedLocales: const [
        Locale('en'),
        Locale('hi'),
        Locale('mr'),
        Locale('kn'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AppNavigator(),
    ),
  );
}

enum AppView { onboarding, registration, addPlot, dashboard, noPlots, faceAuth, faceEnroll, alertFeed }

class AppNavigator extends StatefulWidget {
  const AppNavigator({super.key});
  @override
  State<AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<AppNavigator> {
  AppView _view    = AppView.onboarding;
  bool _loading    = false;

  List<FieldModel> _fields = [];
  String? _selectedFieldId;
  List<AlertModel> _alerts = [];
  List<ActionableAlert> _actionableAlerts = []; // new rich alert feed
  ActionableAlert? _pendingAlert; // alert to act on when dashboard opens
  String _userName = 'Farmer';
  String _registeredUsername = '';
  int _streak  = 0;
  int _longest = 0;
  bool _newDayOpen = false;

  @override
  void initState() {
    super.initState();
    _tryRestoreSession();
  }

  // On cold start: restore session from SharedPreferences.
  // RULES:
  //   - If a token exists → farmer is logged in → never show onboarding.
  //   - Fetch plots from server; if offline → use cached plots.
  //   - Only show onboarding when there is genuinely no saved token.
  Future<void> _tryRestoreSession() async {
    setState(() => _loading = true);

    bool hasToken = false;
    try {
      hasToken = await ApiService.restoreSession();
    } catch (_) {
      // SharedPreferences read failed — treat as no token
    }

    if (!hasToken) {
      // No saved token → fresh install or after explicit logout → show onboarding
      if (mounted) setState(() { _loading = false; _view = AppView.onboarding; });
      return;
    }

    // Token exists — farmer is logged in. Load plots (network or cache).
    try {
      await _fetchAndLoadPlots();
    } catch (_) {
      // _fetchAndLoadPlots already falls back to cache internally;
      // this outer catch is a last-resort safety net.
    }

    if (!mounted) return;

    // ── Record today's open ──────────────────────────────────────────────────
    try {
      await StreakService.instance.recordOpen();
      await NotificationService.instance.scheduleStreakReminder();
      _streak     = StreakService.instance.currentStreak;
      _longest    = StreakService.instance.longestStreak;
      _newDayOpen = StreakService.instance.isNewDayOpen;
    } catch (_) { /* streak errors must never crash the app */ }

    if (_fields.isEmpty) {
      setState(() { _loading = false; _view = AppView.noPlots; });
      return;
    }

    // ── Load cached alerts instantly ────────────────────────────────────────
    final cachedAlertMaps = await ApiService.loadAlertsCache();
    if (cachedAlertMaps.isNotEmpty) {
      _actionableAlerts = cachedAlertMaps
          .map((m) => ActionableAlert.fromJson(m))
          .toList();
    }
    // Always generate local alerts from field data so screen is never empty
    final localAlerts = AlertFeedGenerator.generateLocalAlerts(_fields);
    final existingIds = _actionableAlerts.map((a) => a.id).toSet();
    for (final a in localAlerts) {
      if (!existingIds.contains(a.id)) _actionableAlerts.add(a);
    }

    setState(() {
      _loading = false;
      // Show alert feed every time app opens when there are fields
      _view = AppView.alertFeed;
    });

    // Refresh alerts from live APIs in background
    AlertFeedGenerator.generateAndCache(_fields).then((fresh) {
      if (mounted) setState(() => _actionableAlerts = fresh);
    }).catchError((_) {});
  }

  FieldModel? get _currentField => _selectedFieldId == null
      ? (_fields.isEmpty ? null : _fields.first)
      : _fields.firstWhere((f) => f.id == _selectedFieldId,
          orElse: () => _fields.first);

  // ────────────────────────────────────────────────────────────────
  // Convert one plot from GET /api/farmers/plots/ → FieldModel
  // DB shape: { farmer_id, name, field_id, location: {type:"Point", coordinates:[lng,lat]},
  //             boundary: {type:"Polygon", coordinates:[[[lng,lat],...,[lng,lat]]]} }
  // ────────────────────────────────────────────────────────────────
  // Parse center from GeoJSON Point or legacy flat array.
  // GeoJSON coordinates order is [lng, lat] — we return [lat, lng] for the app.
  static List<double> _parseCenter(dynamic raw) {
    if (raw == null) return [20.5937, 78.9629];

    // ── GeoJSON Point: { "type": "Point", "coordinates": [lng, lat] } ──
    if (raw is Map) {
      final coords = raw['coordinates'];
      if (coords is List && coords.length >= 2) {
        try {
          final lng = (coords[0] as num).toDouble();
          final lat = (coords[1] as num).toDouble();
          return [lat, lng]; // app uses [lat, lng]
        } catch (_) {}
      }
    }

    // ── Legacy flat array [lat, lng] or [lng, lat] ──
    if (raw is List && raw.length >= 2) {
      try {
        return [(raw[0] as num).toDouble(), (raw[1] as num).toDouble()];
      } catch (_) {}
    }

    // ── Stored as JSON string ──
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        return _parseCenter(decoded); // recurse with decoded value
      } catch (_) {}
    }

    return [20.5937, 78.9629];
  }

  // Parse polygon from GeoJSON Polygon or legacy nested array.
  // GeoJSON coordinates order is [lng, lat] — we return [[lat, lng], ...] for the app.
  static List<List<double>> _parsePolygon(dynamic raw) {
    if (raw == null) return [];

    // ── GeoJSON Polygon: { "type": "Polygon", "coordinates": [[[lng,lat], ...]] } ──
    if (raw is Map) {
      final coords = raw['coordinates'];
      if (coords is List && coords.isNotEmpty) {
        // GeoJSON Polygon: first ring is the exterior
        final ring = coords[0];
        if (ring is List) {
          final result = <List<double>>[];
          for (final pt in ring) {
            if (pt is List && pt.length >= 2) {
              try {
                final lng = (pt[0] as num).toDouble();
                final lat = (pt[1] as num).toDouble();
                result.add([lat, lng]); // app uses [lat, lng]
              } catch (_) {}
            }
          }
          return result;
        }
      }
    }

    // ── Legacy flat nested array or JSON string ──
    List? pts;
    if (raw is List) {
      pts = raw;
    } else if (raw is String && raw.isNotEmpty) {
      try {
        pts = jsonDecode(raw) as List;
      } catch (_) {
        return [];
      }
    } else {
      return [];
    }

    final result = <List<double>>[];
    for (final pt in pts!) {
      if (pt is List && pt.length >= 2) {
        try {
          result.add([(pt[0] as num).toDouble(), (pt[1] as num).toDouble()]);
        } catch (_) {}
      }
    }
    return result;
  }

  /// Key for `plot_name` on analysis APIs — must match backend row for this farmer.
  /// Prefer explicit `plot_name` / `field_id` over display `name` (e.g. EE uses "11", name may differ).
  static String _analysisPlotNameFromPayload(Map<String, dynamic> p) {
    for (final key in ['plot_name', 'field_id', 'name', 'id']) {
      final v = p[key];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return 'My Plot';
  }

  FieldModel _plotToField(Map<String, dynamic> p) {
    // Support both GeoJSON fields (location/boundary) and legacy (center/polygon)
    final center  = _parseCenter(p['location']  ?? p['center']);
    final polygon = _parsePolygon(p['boundary'] ?? p['polygon']);

    // Use server id — keeps re-fetches idempotent
    final id = p['id']?.toString() ??
        p['field_id']?.toString() ??
        'plot-${DateTime.now().millisecondsSinceEpoch}';

    final displayName = p['name']?.toString().isNotEmpty == true
        ? p['name'].toString()
        : 'My Plot';

    // Crop info — handle crops array (from list endpoint), crop_details map, or flat fields
    Map<String, dynamic>? cropDetails = p['crop_details'] as Map<String, dynamic>?;

    // The list endpoint returns crops as an array: [{crop_type_name, crop_variety_name, ...}]
    if (cropDetails == null && p['crops'] is List) {
      final cropsList = p['crops'] as List;
      if (cropsList.isNotEmpty) {
        final firstCrop = cropsList.first as Map<String, dynamic>;
        cropDetails = {
          'crop_type':       firstCrop['crop_type_name'] ?? firstCrop['crop_type'],
          'crop_variety':    firstCrop['crop_variety_name'] ?? firstCrop['crop_variety'],
          'plantation_date': firstCrop['plantation_date'],
          'irrigation_type': firstCrop['irrigation_type_name'] ?? firstCrop['irrigation_type'],
        };
      }
    }

    // Always prefer the human-readable name fields over numeric IDs
    // so the crop animation classifier can match "Wheat" not "1"
    final cropType = cropDetails?['crop_type_name']  ??
                     cropDetails?['crop_type']        ??
                     p['crop_type_name']              ??
                     p['crop_type']                   ??
                     p['crop']                        ?? 'Crop';
    final cropVariety = cropDetails?['crop_variety_name'] ??
                        cropDetails?['crop_variety']       ??
                        p['crop_variety_name']             ??
                        p['crop_variety']                  ?? p['variety'];
    final plantDate   = cropDetails?['plantation_date'] ?? p['plantation_date'];
    final irrigType   = cropDetails?['irrigation_type_name'] ??
                        cropDetails?['irrigation_type']       ??
                        p['irrigation_type'];

    dev.log('_plotToField id=${p['id']} cropType=$cropType polygon_pts=${_parsePolygon(p['boundary'] ?? p['polygon']).length}');

    // FIX 1: Compute real area from polygon boundary
    final areaMetrics = PlotAreaCalculator.calculate(polygon);
    final computedArea = areaMetrics?.displayLabel;
    final serverArea   = p['area']?.toString();
    final areaLabel    = (serverArea != null && serverArea.isNotEmpty && serverArea != '5.0 Acres')
        ? serverArea
        : (computedArea ?? '0.00 Ac');

    return FieldModel(
      id:             id,
      name:           displayName,
      plotNameForAnalysis: _analysisPlotNameFromPayload(p),
      center:         center,
      polygon:        polygon,
      soilData:       MockData.soilData,
      crop:           cropType.toString(),
      cropVariety:    cropVariety?.toString(),
      plantationDate: plantDate?.toString(),
      irrigationType: irrigType?.toString(),
      area:           areaLabel,
      stage:          p['stage']?.toString() ?? 'Sowing (0%)',
      rowSpacingM:    (p['row_spacing_m'] as num?)?.toDouble() ?? 0.0,
      plantSpacingM:  (p['plant_spacing_m'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Fetch plots from server and update _fields
  // Strategy: first try with farmer_id, fallback to no param
  // ────────────────────────────────────────────────────────────────
  Future<void> _fetchAndLoadPlots({String? selectId}) async {
    List<Map<String, dynamic>> plots = [];
    bool fromNetwork = false;

    // 1. Try fetching from server
    try {
      plots = await ApiService.getPlots();
      fromNetwork = true;
      dev.log('_fetchAndLoadPlots: server returned ${plots.length} plots');
    } catch (e) {
      dev.log('_fetchAndLoadPlots: server error — $e');
    }

    // 2. If network returned nothing, fall back to local cache
    //    so the farmer sees their fields even when offline.
    if (plots.isEmpty) {
      try {
        plots = await ApiService.loadPlotsCache();
        if (plots.isNotEmpty) {
          dev.log('_fetchAndLoadPlots: using cached ${plots.length} plots (offline)');
        } else {
          dev.log('_fetchAndLoadPlots: cache also empty — farmerId=${ApiService.farmerId}');
        }
      } catch (_) {}
    }

    // 3. If we got fresh data from the server, update the cache
    if (fromNetwork && plots.isNotEmpty) {
      ApiService.savePlotsCache(plots); // fire-and-forget
    }

    if (!mounted) return;
    final loaded = plots.map((p) => _plotToField(p)).toList();
    setState(() {
      _fields = loaded;
      if (loaded.isNotEmpty) {
        if (selectId != null && loaded.any((f) => f.id == selectId)) {
          // Caller wants a specific plot selected (e.g. after adding a new one)
          _selectedFieldId = selectId;
        } else if (_selectedFieldId == null ||
            !loaded.any((f) => f.id == _selectedFieldId)) {
          _selectedFieldId = loaded.first.id;
        }
        // else: keep current selection — user is just browsing
      } else {
        _selectedFieldId = null;
      }
    });
  }

  // ────────────────────────────────────────────────────────────────
  // Login success handler (phone + google both call this)
  // ────────────────────────────────────────────────────────────────
  // ── Background soil data fetch ─────────────────────────────────────────
  Future<void> _fetchAndApplySoilData() async {
    if (_fields.isEmpty) return;
    final today = DateTime.now().toString().split(' ')[0];

    for (var i = 0; i < _fields.length; i++) {
      final field = _fields[i];
      final plotName = field.plotNameForAnalysis;
      if (plotName.isEmpty) continue;

      final pDate = field.plantationDate ?? today;
      SoilNpkResult? npk;
      SoilAnalysisResult? analysis;

      try {
        npk = await SoilParamApi.fetchNpk(
            plotName: plotName, plantationDate: pDate, endDate: today);
      } catch (_) {}

      try {
        analysis = await SoilParamApi.fetchAnalysis(
            plotName: plotName, plantationDate: pDate, date: today);
      } catch (_) {}

      if (!mounted) return;
      if (npk == null && analysis == null) continue;

      final existing = field.soilData;
      final liveSoilData = SoilData(
        nitrogen:   npk?.soilN       ?? existing.nitrogen,
        phosphorus: npk?.soilP       ?? existing.phosphorus,
        potassium:  npk?.soilK       ?? existing.potassium,
        ph:         analysis?.ph     ?? existing.ph,
        cec:        analysis?.cec    ?? existing.cec,
        oc:         analysis?.oc     ?? existing.oc,
        moisture:   existing.moisture,
        bd:         existing.bd,
        fe:         existing.fe,
        soc:        existing.soc,
      );

      setState(() {
        _fields = List.of(_fields)..[i] = _fields[i].copyWithSoilData(liveSoilData);
      });
    }
  }

  Future<void> _handleLoginSuccess(Map<String, dynamic> data) async {
    ApiService.diagnoseLoginResponse();

    final user      = data['user']   as Map<String, dynamic>?;
    final farmer    = data['farmer'] as Map<String, dynamic>?;
    final firstName = (farmer?['first_name'] ?? user?['first_name'] ?? data['first_name'] ?? '').toString();
    final lastName  = (farmer?['last_name']  ?? user?['last_name']  ?? data['last_name']  ?? '').toString();
    final fullName  = '$firstName $lastName'.trim();
    if (fullName.isNotEmpty) _userName = fullName;

    setState(() => _loading = true);
    await ApiService.clearPlotsCache();
    await ApiService.restoreFarmerId();
    await _fetchAndLoadPlots();
    if (!mounted) return;

    if (_fields.isEmpty) {
      setState(() { _loading = false; _view = AppView.noPlots; });
      return;
    }

    _selectedFieldId = _fields.first.id;

    // ── Step 1: Load cached alerts instantly (fast) ──────────────
    final cachedAlertMaps = await ApiService.loadAlertsCache();
    if (cachedAlertMaps.isNotEmpty) {
      _actionableAlerts = cachedAlertMaps
          .map((m) => ActionableAlert.fromJson(m))
          .toList();
    }

    // ── Step 2: Always generate guaranteed local alerts from field
    //    data (no API needed) so there is always something to show ─
    final localAlerts = AlertFeedGenerator.generateLocalAlerts(_fields);
    // Merge: prefer cached API alerts, supplement with local ones
    final existingIds = _actionableAlerts.map((a) => a.id).toSet();
    for (final a in localAlerts) {
      if (!existingIds.contains(a.id)) _actionableAlerts.add(a);
    }

    setState(() {
      _loading = false;
      _view = AppView.alertFeed;
    });

    _fetchAndApplySoilData();

    // ── Step 3: Refresh from live APIs in background ──────────────
    AlertFeedGenerator.generateAndCache(_fields).then((fresh) {
      if (mounted) setState(() => _actionableAlerts = fresh);
    }).catchError((_) {});
  }

  // ────────────────────────────────────────────────────────────────
  // After registration completes
  // ────────────────────────────────────────────────────────────────
  // After registration: build local field + fetch from server + save cache
  Future<void> _onRegistered(Map<String, dynamic>? data) async {
    if (data == null) { setState(() => _view = AppView.dashboard); return; }

    // Store farmer_id
    final rawId = data['farmer_id'] ?? data['id'];
    if (rawId != null) {
      final id = rawId is int ? rawId : int.tryParse(rawId.toString());
      if (id != null) await ApiService.saveFarmerId(id);
    }

    // Build local field immediately so farmer never sees "No Plots" right away
    if (data['polygon'] != null) {
      _buildFieldFromFormData(data);
    }

    // Fetch from server + populate cache so next login/logout shows the plot
    setState(() => _loading = true);
    await _fetchAndLoadPlots();

    if (!mounted) return;
    setState(() {
      _loading = false;
      _view = _fields.isNotEmpty ? AppView.dashboard : AppView.noPlots;
    });
  }

  // ────────────────────────────────────────────────────────────────
  // After adding a new plot (add_plot_screen)
  // Re-fetch from server so IDs and list are always in sync
  // ────────────────────────────────────────────────────────────────
  Future<void> _onPlotAdded(Map<String, dynamic>? data) async {
    if (data == null) { setState(() => _view = AppView.dashboard); return; }

    // ── Step 1: Build a local FieldModel immediately from form data ──
    // This guarantees the farmer ALWAYS sees their plot even if the server
    // fetch is slow, fails, or returns empty.
    _buildFieldFromFormData(data);
  }

  // ────────────────────────────────────────────────────────────────
  // Build a FieldModel locally from registration form data
  // (used only for registration — subsequent plots re-fetch from API)
  // ────────────────────────────────────────────────────────────────
  void _buildFieldFromFormData(Map<String, dynamic> data) {
    final rawPolygon = data['polygon'];
    List<List<double>> polygon = [];

    if (rawPolygon is List && rawPolygon.isNotEmpty) {
      for (final p in rawPolygon) {
        try {
          // Handle LatLng objects (from map_plot_screen)
          if (p != null && p.runtimeType.toString().contains('LatLng')) {
            polygon.add([
              (p as dynamic).latitude  as double,
              (p as dynamic).longitude as double,
            ]);
          // Handle [lat, lng] double lists (from API responses)
          } else if (p is List && p.length >= 2) {
            polygon.add([(p[0] as num).toDouble(), (p[1] as num).toDouble()]);
          }
        } catch (_) {}
      }
    }

    List<double> center = [20.5937, 78.9629];
    if (polygon.isNotEmpty) {
      center = [
        polygon.map((p) => p[0]).reduce((a, b) => a + b) / polygon.length,
        polygon.map((p) => p[1]).reduce((a, b) => a + b) / polygon.length,
      ];
    }

    // Prefer server-assigned id if registration returned one
    final id = data['plot_id']?.toString() ??
        data['id']?.toString() ??
        'field-${DateTime.now().millisecondsSinceEpoch}';

    final displayName = data['name']?.toString().isNotEmpty == true
        ? data['name'].toString()
        : '${data['cropType'] ?? 'Main'} Plot';
    String? pick(String k) {
      final v = data[k]?.toString().trim();
      return (v != null && v.isNotEmpty) ? v : null;
    }

    final analysisName = pick('plot_name') ??
        pick('plot_id') ??
        pick('field_id') ??
        pick('name') ??
        id;

    final newField = FieldModel(
      id:             id,
      name:           displayName,
      plotNameForAnalysis: analysisName,
      center:         center,
      polygon:        polygon,
      soilData:       MockData.soilData,
      crop:           data['cropType']?.toString() ?? 'Crop',
      cropVariety:    data['cropVariety']?.toString(),
      plantationDate: data['plantationDate']?.toString(),
      irrigationType: data['irrigationType']?.toString(),
      area:           data['area']?.toString() ?? '0.00 Ac',
      stage:          'Sowing (0%)',
      rowSpacingM:    (data['rowSpacingM'] as num?)?.toDouble() ?? 0.0,
      plantSpacingM:  (data['plantSpacingM'] as num?)?.toDouble() ?? 0.0,
    );

    // ── Step 1: Show dashboard IMMEDIATELY with the local field ────
    // Farmer sees their plot right away without waiting for the server.
    setState(() {
      // Add field locally if not already in list
      if (!_fields.any((f) => f.id == id)) {
        _fields = [..._fields, newField];
      }
      _selectedFieldId = id;
      _view = AppView.dashboard;
      _loading = false;
    });

    // ── Step 2: Silently refresh from server in the background ──────
    // If server returns the plot, replace the local copy with the
    // server-authoritative version. If server returns nothing (race
    // condition or network failure), local copy stays and works fine.
    Future.delayed(const Duration(milliseconds: 1200), () async {
      try {
        final plots = await ApiService.getPlots();
        if (!mounted || plots.isEmpty) return;
        final loaded = plots.map((p) => _plotToField(p)).toList();
        if (!mounted) return;
        // Cache the fresh server data
        ApiService.savePlotsCache(plots);
        setState(() {
          _fields = loaded;
          // Keep the newly added plot selected
          if (loaded.any((f) => f.id == id)) {
            _selectedFieldId = id;
          } else if (!loaded.any((f) => f.id == _selectedFieldId)) {
            _selectedFieldId = loaded.last.id;
          }
        });
      } catch (_) {
        // Silently ignore — local field is already showing correctly
      }
    });
  }

  Future<void> _deleteField(String id) async {
    if (_fields.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('You must have at least one field.'),
          backgroundColor: AppColors.primary));
      return;
    }

    // Optimistically remove from UI immediately
    final updated = _fields.where((f) => f.id != id).toList();
    setState(() {
      _fields = updated;
      if (_selectedFieldId == id) _selectedFieldId = updated.first.id;
    });

    // Call server to delete from database
    final success = await ApiService.deletePlot(id);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Plot deleted successfully.'),
          backgroundColor: AppColors.primary,
          duration: Duration(seconds: 2)));
    } else {
      // Server delete failed — re-fetch to restore accurate state
      await _fetchAndLoadPlots();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not delete plot from server. Please try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3)));
      }
    }
  }

  Future<void> _renameField(String id, String name) async {
    final field = _fields.firstWhere((f) => f.id == id, orElse: () => _fields.first);
    final oldName = field.name;

    // Optimistic local update for snappy UI
    setState(() => _fields = _fields
        .map((f) => f.id == id
            ? f.copyWith(name: name, plotNameForAnalysis: name)
            : f)
        .toList());

    // Persist to backend — PUT /api/farmers/plots/{id}/
    final ok = await ApiService.renamePlot(
      id,
      name,
      center:  field.center,
      polygon: field.polygon,
    );

    if (!ok && mounted) {
      // Revert to original name on failure
      setState(() => _fields = _fields
          .map((f) => f.id == id
              ? f.copyWith(name: oldName, plotNameForAnalysis: oldName)
              : f)
          .toList());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save plot name. Please try again.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _resolveAlert(String id) => setState(() =>
      _alerts = _alerts.where((a) => a.id != id).toList());

  /// Called when user taps an alert card.
  /// Switches to the field the alert belongs to,
  /// navigates to dashboard, then passes the alert
  /// to DashboardScreen via a pending alert state.
  void _onAlertTap(ActionableAlert alert) {
    // Switch to the correct field
    final field = _fields.firstWhere(
      (f) => f.id == alert.fieldId,
      orElse: () => _fields.first,
    );
    setState(() {
      _selectedFieldId  = field.id;
      _pendingAlert     = alert;
      _view             = AppView.dashboard;
    });
  }

  Future<void> _handleLogout() async {
    await ApiService.logout();
    setState(() {
      _fields          = [];
      _selectedFieldId = null;
      _userName        = 'Farmer';
      _alerts          = [];
      _view            = AppView.onboarding;
    });
  }

  // ────────────────────────────────────────────────────────────────
  // Loading overlay
  // ────────────────────────────────────────────────────────────────
  Widget _buildLoader(String message) => Scaffold(
    backgroundColor: AppColors.background,
    body: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80, height: 80,
          decoration: const BoxDecoration(
              color: AppColors.greenLight, shape: BoxShape.circle),
          child: const Icon(Icons.agriculture,
              color: AppColors.primary, size: 40),
        ),
        const SizedBox(height: 28),
        const CircularProgressIndicator(
            color: AppColors.primary, strokeWidth: 3),
        const SizedBox(height: 16),
        Text(message,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textMedium,
                fontSize: 15)),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoader('Loading your fields...');

    switch (_view) {
      // ── Face enroll (optional, after first-time registration) ─────────
      case AppView.faceAuth:
      case AppView.faceEnroll:
        return _FaceEnrollOptionalScreen(
          username: _registeredUsername,
          onDone: () => setState(() =>
              _view = _fields.isNotEmpty ? AppView.dashboard : AppView.noPlots),
        );

      case AppView.onboarding:
        return OnboardingScreen(
          onAction: (action) {
            if (action == 'register') {
              setState(() => _view = AppView.registration);
            } else {
              setState(() => _view = AppView.dashboard);
            }
          },
          onLoginSuccess: _handleLoginSuccess,
          // Face ID login: farmer verified → load cached plots → dashboard
          onFaceLogin: () async {
            setState(() => _loading = true);
            await _fetchAndLoadPlots();
            if (mounted) setState(() {
              _loading = false;
              _view = _fields.isNotEmpty ? AppView.dashboard : AppView.noPlots;
            });
          },
        );

      case AppView.registration:
        return RegistrationScreen(
          onComplete: _onRegistered,
          onBack: () => setState(() => _view = AppView.onboarding),
        );

      case AppView.addPlot:
        return AddPlotScreen(
          farmerId: ApiService.farmerId,
          onComplete: _onPlotAdded,
          onBack: () => setState(() =>
              _view = _fields.isEmpty ? AppView.noPlots : AppView.dashboard),
        );

      case AppView.noPlots:
        return NoPlotsScreen(
          onAddPlot: () => setState(() => _view = AppView.addPlot),
          onLogout:  _handleLogout,
        );

      case AppView.alertFeed:
        return AlertFeedScreen(
          alerts: _actionableAlerts,
          onSkip: () => setState(() => _view = AppView.dashboard),
          onAlertTap: _onAlertTap,
        );

      case AppView.dashboard:
        if (_fields.isEmpty) {
          // Show a brief loading indicator while background fetch completes.
          // If still empty after loading, show NoPlots.
          if (_loading) {
            return _buildLoader('Loading your fields...');
          }
          return NoPlotsScreen(
            onAddPlot: () => setState(() => _view = AppView.addPlot),
            onLogout:  _handleLogout,
          );
        }
        return DashboardScreen(
          key: ValueKey('${_selectedFieldId}_${_pendingAlert?.id}'),
          field:           _currentField!,
          fields:          _fields,
          alerts:          _alerts,
          userName:        _userName,
          streak:          _streak,
          longestStreak:   _longest,
          isNewDayOpen:    _newDayOpen,
          onSelectField:   (id) => setState(() => _selectedFieldId = id),
          onDeleteField:   _deleteField,
          onRenameField:   _renameField,
          onAddNewField:   () => setState(() => _view = AppView.addPlot),
          onResolveAlert:  _resolveAlert,
          onLogout:        _handleLogout,
          pendingAlert:    _pendingAlert,
          actionableAlerts: _actionableAlerts,
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  OPTIONAL FACE ENROLL SCREEN
//  Shown after registration. Has a prominent "Skip for Now" option.
//  Farmer can skip and register face later from Profile Settings.
// ═══════════════════════════════════════════════════════════════════════════
class _FaceEnrollOptionalScreen extends StatelessWidget {
  final String? username;
  final VoidCallback onDone;

  const _FaceEnrollOptionalScreen({
    required this.onDone,
    this.username,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080F09),
      body: SafeArea(
        child: Column(children: [
          // ── Top skip button ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Row(children: [
              const Spacer(),
              TextButton(
                onPressed: onDone,
                child: const Text(
                  'Skip for Now →',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ]),
          ),

          // ── Optional badge ───────────────────────────────────────────
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.amber.withOpacity(0.4)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.info_outline, color: Colors.amber, size: 14),
              SizedBox(width: 6),
              Text('OPTIONAL — You can do this later',
                  style: TextStyle(
                      color: Colors.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ]),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Register your face now for quick one-tap login in the future, '
              'or skip and do it later from Profile Settings.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
              ),
            ),
          ),

          // ── The actual face enroll screen (expanded) ─────────────────
          Expanded(
            child: FaceAuthScreen(
              mode: FaceAuthMode.enroll,
              username: username,
              onSuccess: onDone,
              onSkip: onDone,
            ),
          ),
        ]),
      ),
    );
  }
}
