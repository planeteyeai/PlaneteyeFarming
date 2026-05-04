import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../constants/app_constants.dart';

// ─── Nominatim result model ───────────────────────────────────────────────

class _PlaceResult {
  final String displayName;
  final String shortName;
  final double lat;
  final double lng;

  const _PlaceResult({
    required this.displayName,
    required this.shortName,
    required this.lat,
    required this.lng,
  });

  factory _PlaceResult.fromJson(Map<String, dynamic> j) {
    final full = j['display_name'] as String? ?? '';
    final parts = full.split(',');
    final short = parts.take(2).join(',').trim();
    return _PlaceResult(
      displayName: full,
      shortName: short,
      lat: double.tryParse(j['lat'] as String? ?? '') ?? 0,
      lng: double.tryParse(j['lon'] as String? ?? '') ?? 0,
    );
  }
}

// ─── Nominatim geocoding service ─────────────────────────────────────────

class _NominatimService {
  static const _base = 'https://nominatim.openstreetmap.org/search';

  static Future<List<_PlaceResult>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final uri = Uri.parse(_base).replace(queryParameters: {
      'q': query,
      'format': 'json',
      'limit': '6',
      'addressdetails': '1',
    });
    try {
      final res = await http
          .get(uri, headers: {'User-Agent': 'CropEyeApp/1.0'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final list = jsonDecode(res.body) as List<dynamic>;
      return list
          .map((e) => _PlaceResult.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  MAP PLOT SCREEN — draw plot boundary with location search
// ═══════════════════════════════════════════════════════════════════════════

class MapPlotScreen extends StatefulWidget {
  final void Function(List<LatLng>) onComplete;
  final VoidCallback onBack;
  final String title;

  const MapPlotScreen({
    super.key,
    required this.onComplete,
    required this.onBack,
    this.title = 'Draw Your Plot',
  });

  @override
  State<MapPlotScreen> createState() => _MapPlotScreenState();
}

class _MapPlotScreenState extends State<MapPlotScreen>
    with TickerProviderStateMixin {
  final MapController _mapCtrl = MapController();
  final GlobalKey _mapKey = GlobalKey();

  List<LatLng> _pts = [];
  LatLng _gpsCenter = const LatLng(20.5937, 78.9629);
  bool _locating = true;

  // Dragging
  int? _draggingIndex;
  bool _isDragging = false;

  // Animations
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;
  final List<AnimationController> _dotCtrl = [];
  final List<Animation<double>> _dotAnim = [];

  // ── Search state ──────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchActive = false;
  bool _searching = false;
  List<_PlaceResult> _suggestions = [];
  Timer? _debounce;

  static const int _minPoints = 3;

  // ── Init / dispose ────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _searchFocus.addListener(() {
      setState(() => _searchActive = _searchFocus.hasFocus);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    for (final c in _dotCtrl) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Search ────────────────────────────────────────────────────────────

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final results = await _NominatimService.search(query);
      if (mounted) {
        setState(() {
          _suggestions = results;
          _searching = false;
        });
      }
    });
  }

  void _selectPlace(_PlaceResult place) {
    final loc = LatLng(place.lat, place.lng);
    _mapCtrl.move(loc, 16);
    _searchCtrl.text = place.shortName;
    _searchFocus.unfocus();
    setState(() {
      _searchActive = false;
      _suggestions = [];
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() {
      _suggestions = [];
      _searching = false;
    });
    _searchFocus.requestFocus();
  }

  Future<void> _useMyLocation() async {
    _searchFocus.unfocus();
    setState(() {
      _searchActive = false;
      _suggestions = [];
      _searching = false;
    });
    await _locate();
  }

  // ── GPS ───────────────────────────────────────────────────────────────

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _locating = false);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _locating = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _gpsCenter = loc;
        _locating = false;
      });
      _mapCtrl.move(loc, 18);
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ── Plot drawing ──────────────────────────────────────────────────────

  void _onTap(TapPosition _, LatLng ll) {
    if (_isDragging) return;
    if (_searchFocus.hasFocus) {
      _searchFocus.unfocus();
      setState(() {
        _searchActive = false;
        _suggestions = [];
      });
      return;
    }
    // FIX 8: Only add the point — do NOT call _mapCtrl.move() here.
    // Moving the map on every tap causes the view to jump/refresh while
    // the farmer is trying to mark adjacent corners, making it unusable.
    setState(() => _pts = [..._pts, ll]);
    _addDotAnimation();
  }

  void _addDotAnimation() {
    final ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    final anim = CurvedAnimation(parent: ctrl, curve: Curves.elasticOut);
    _dotCtrl.add(ctrl);
    _dotAnim.add(anim);
    ctrl.forward();
  }

  void _removeDotAnimation(int index) {
    if (index < _dotCtrl.length) {
      _dotCtrl[index].dispose();
      _dotCtrl.removeAt(index);
      _dotAnim.removeAt(index);
    }
  }

  void _undoLast() {
    if (_pts.isEmpty) return;
    _removeDotAnimation(_pts.length - 1);
    setState(() => _pts = _pts.sublist(0, _pts.length - 1));
  }

  void _reset() {
    for (final c in _dotCtrl) {
      c.dispose();
    }
    _dotCtrl.clear();
    _dotAnim.clear();
    setState(() => _pts = []);
  }

  void _finish() {
    if (_pts.length < _minPoints) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Mark at least $_minPoints points to define your plot.'),
          backgroundColor: AppColors.primary));
      return;
    }
    widget.onComplete(_pts);
  }

  String get _statusText {
    if (_locating) return 'Getting your GPS location...';
    if (_isDragging) return 'Drag to fine-tune point position';
    if (_pts.isEmpty) return 'Tap on the map to mark plot corners';
    if (_pts.length < _minPoints) {
      final rem = _minPoints - _pts.length;
      return 'Add $rem more point${rem > 1 ? "s" : ""} (${_pts.length} added)';
    }
    return '${_pts.length} points · tap to add more or drag to adjust';
  }

  bool get _canFinish => _pts.length >= _minPoints;

  // ── Marker ────────────────────────────────────────────────────────────

  Marker _buildMarker(int idx, LatLng pt) {
    final isFirst = idx == 0;
    final isDraggingThis = _draggingIndex == idx;
    final baseColor = isFirst ? const Color(0xFF2E7D32) : AppColors.accent;
    final markerSize = isDraggingThis ? 52.0 : 36.0;

    Widget dotWidget = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) =>
          setState(() { _draggingIndex = idx; _isDragging = true; }),
      onPanUpdate: (details) {
        if (_draggingIndex != idx) return;
        final RenderBox? mapBox =
            _mapKey.currentContext?.findRenderObject() as RenderBox?;
        if (mapBox == null) return;
        final local = mapBox.globalToLocal(details.globalPosition);
        final newLatLng =
            _mapCtrl.camera.pointToLatLng(Point(local.dx, local.dy));
        setState(() {
          final updated = List<LatLng>.from(_pts);
          updated[idx] = newLatLng;
          _pts = updated;
        });
      },
      onPanEnd: (_) =>
          setState(() { _draggingIndex = null; _isDragging = false; }),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: markerSize,
          height: markerSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDraggingThis ? Colors.white : baseColor,
            border: Border.all(
              color: isDraggingThis ? baseColor : Colors.white,
              width: isDraggingThis ? 3 : 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: baseColor.withOpacity(isDraggingThis ? 0.75 : 0.45),
                blurRadius: isDraggingThis ? 22 : 10,
                spreadRadius: isDraggingThis ? 5 : 2,
              ),
              if (isDraggingThis)
                const BoxShadow(
                    color: Colors.black38,
                    blurRadius: 12,
                    offset: Offset(0, 5)),
            ],
          ),
          child: Center(
            child: isDraggingThis
                ? Icon(Icons.open_with,
                    color: baseColor, size: markerSize * 0.42)
                : Text(
                    '${idx + 1}',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: markerSize * 0.30,
                        fontWeight: FontWeight.w900,
                        height: 1),
                  ),
          ),
        ),
      ),
    );

    if (!isDraggingThis) {
      dotWidget = AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, -3 + 6 * (1 - _pulse.value)),
          child: Stack(alignment: Alignment.center, children: [
            Container(
              width: markerSize + 18,
              height: markerSize + 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: baseColor.withOpacity(0.35 * _pulse.value),
                  width: 1.5,
                ),
              ),
            ),
            Container(
              width: markerSize + 10,
              height: markerSize + 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: baseColor.withOpacity(0.08 * _pulse.value),
              ),
            ),
            child!,
          ]),
        ),
        child: dotWidget,
      );
    }

    if (idx < _dotAnim.length) {
      return Marker(
        point: pt,
        width: markerSize + 40,
        height: markerSize + 40,
        child: AnimatedBuilder(
          animation: _dotAnim[idx],
          builder: (_, child) =>
              Transform.scale(scale: _dotAnim[idx].value, child: child),
          child: dotWidget,
        ),
      );
    }

    return Marker(
        point: pt,
        width: markerSize + 40,
        height: markerSize + 40,
        child: dotWidget);
  }

  // ── Search bar widget ─────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Input pill
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.20),
                  blurRadius: 18,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Row(children: [
            const SizedBox(width: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _searching
                  ? const SizedBox(
                      key: ValueKey('spin'),
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: AppColors.primary),
                    )
                  : Icon(
                      key: const ValueKey('icon'),
                      Icons.search_rounded,
                      color: _searchActive
                          ? AppColors.primary
                          : Colors.grey.shade500,
                      size: 22,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onChanged: _onSearchChanged,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111111)),
                decoration: InputDecoration(
                  hintText: 'Search village, city, district...',
                  hintStyle: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade400,
                      fontWeight: FontWeight.w500),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (v) => _onSearchChanged(v),
              ),
            ),
            // Clear button
            AnimatedOpacity(
              opacity: _searchCtrl.text.isNotEmpty ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: GestureDetector(
                onTap: _clearSearch,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade200, shape: BoxShape.circle),
                    child: Icon(Icons.close_rounded,
                        size: 14, color: Colors.grey.shade600),
                  ),
                ),
              ),
            ),
            // GPS location button
            GestureDetector(
              onTap: _useMyLocation,
              child: Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: AppColors.greenLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _locating
                    ? const Padding(
                        padding: EdgeInsets.all(9),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary),
                      )
                    : const Icon(Icons.my_location_rounded,
                        color: AppColors.primary, size: 18),
              ),
            ),
          ]),
        ),

        // Suggestions dropdown
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: (!_searchActive && _suggestions.isEmpty && !_searching)
              ? const SizedBox.shrink()
              : Container(
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.14),
                          blurRadius: 20,
                          offset: const Offset(0, 6)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _searching && _suggestions.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: AppColors.primary),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding:
                                const EdgeInsets.symmetric(vertical: 6),
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _suggestions.length + 1,
                            separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: Colors.grey.shade100,
                                indent: 52,
                                endIndent: 16),
                            itemBuilder: (ctx, i) {
                              // First item: Use My Location
                              if (i == 0) {
                                return InkWell(
                                  onTap: _useMyLocation,
                                  splashColor: AppColors.greenLight,
                                  highlightColor:
                                      AppColors.greenLight.withOpacity(0.5),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                    child: Row(children: [
                                      Container(
                                        width: 34,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          color: AppColors.primary
                                              .withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(9),
                                        ),
                                        child: const Icon(
                                            Icons.my_location_rounded,
                                            color: AppColors.primary,
                                            size: 18),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: const [
                                          Text('Use My Current Location',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.primary)),
                                          SizedBox(height: 2),
                                          Text('Navigate map to your GPS position',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFF888888),
                                                  fontWeight:
                                                      FontWeight.w500)),
                                        ]),
                                      ),
                                      const Icon(Icons.arrow_forward_ios_rounded,
                                          size: 12, color: AppColors.primary),
                                    ]),
                                  ),
                                );
                              }
                              final p = _suggestions[i - 1];
                              return _SuggestionTile(
                                  place: p, onTap: () => _selectPlace(p));
                            },
                          ),
                  ),
                ),
        ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(children: [

        // ── Map ──────────────────────────────────────────────────────
        FlutterMap(
          key: _mapKey,
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: _gpsCenter,
            initialZoom: 18,
            minZoom: 4,
            maxZoom: 22,
            onTap: _onTap,
            interactionOptions: InteractionOptions(
              flags: _isDragging
                  ? InteractiveFlag.none
                  : InteractiveFlag.all,
              pinchZoomThreshold: 0.1,
              scrollWheelVelocity: 0.005,
              rotationThreshold: 5.0,
              pinchMoveThreshold: 5.0,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'http://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
              maxZoom: 22,
              panBuffer: 2,
            ),
            if (_pts.length >= 3)
              PolygonLayer(polygons: [
                Polygon(
                  points: _pts,
                  color: AppColors.accent.withOpacity(0.18),
                  borderColor: AppColors.accent,
                  borderStrokeWidth: 2.5,
                ),
              ]),
            if (_pts.length >= 2)
              PolylineLayer(polylines: [
                Polyline(
                  points: [..._pts, _pts.first],
                  color: AppColors.accent.withOpacity(0.85),
                  strokeWidth: 2,
                  isDotted: true,
                ),
              ]),
            MarkerLayer(
              markers: _pts.asMap().entries
                  .map((e) => _buildMarker(e.key, e.value))
                  .toList(),
            ),
          ],
        ),

        // Top + bottom gradient scrim
        IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.5),
                  Colors.transparent,
                  Colors.black.withOpacity(0.65),
                ],
                stops: const [0, 0.35, 1],
              ),
            ),
          ),
        ),

        // ── Search bar — always on top ────────────────────────────────
        Positioned(
          top: topPad + 10,
          left: 16,
          right: 16,
          child: _buildSearchBar(),
        ),

        // ── Info card (below search, hidden when search is active) ────
        Positioned(
          top: topPad + 72,
          left: 20,
          right: 20,
          child: AnimatedOpacity(
            opacity: _searchActive ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: _searchActive,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.72),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                      color: AppColors.accent.withOpacity(0.35), width: 1),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20),
                  ],
                ),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _canFinish
                          ? AppColors.primary.withOpacity(0.2)
                          : Colors.white.withOpacity(0.1),
                    ),
                    child: Icon(
                      _isDragging
                          ? Icons.open_with
                          : (_canFinish
                              ? Icons.check_circle_outline
                              : Icons.touch_app_outlined),
                      color: _canFinish ? AppColors.accent : Colors.white70,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(widget.title,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.3)),
                      const SizedBox(height: 2),
                      Text(_statusText,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.7))),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _canFinish
                          ? AppColors.primary.withOpacity(0.25)
                          : Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _canFinish
                              ? AppColors.accent.withOpacity(0.5)
                              : Colors.white24),
                    ),
                    child: Text(
                      '${_pts.length} pts',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: _canFinish
                              ? AppColors.accent
                              : Colors.white60),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),

        // GPS spinner
        if (_locating)
          Positioned(
            top: 180,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: const [
                  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white)),
                  SizedBox(width: 10),
                  Text('Locking GPS...',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ]),
              ),
            ),
          ),

        // Drag hint
        if (_pts.isNotEmpty && !_isDragging && !_searchActive)
          Positioned(
            top: 200,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => Opacity(
                    opacity: _pulse.value * 0.85,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B5E20).withOpacity(0.88),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.accent.withOpacity(0.5)),
                      ),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                        Icon(Icons.open_with, color: Colors.white, size: 14),
                        SizedBox(width: 8),
                        Text('Hold & drag any point to adjust',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Right-side FABs
        if (!kIsWeb)
          Positioned(
            bottom: 185,
            right: 18,
            child: Column(children: [
              _iconBtn(
                  icon: Icons.my_location,
                  color: AppColors.primary,
                  onTap: () => _mapCtrl.move(_gpsCenter, 18)),
              const SizedBox(height: 10),
              _iconBtn(
                  icon: Icons.undo,
                  color: _pts.isEmpty
                      ? Colors.grey.shade400
                      : Colors.orange.shade700,
                  onTap: _pts.isEmpty ? null : _undoLast),
            ]),
          ),

        // Bottom controls
        Positioned(
          bottom: 28,
          left: 20,
          right: 20,
          child: Column(children: [
            Row(children: [
              Expanded(child: _ghostBtn('Reset', _reset)),
              const SizedBox(width: 12),
              Expanded(child: _ghostBtn('Back', widget.onBack)),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canFinish ? _finish : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canFinish
                      ? AppColors.primary
                      : const Color(0xFF333333),
                  foregroundColor: _canFinish
                      ? Colors.white
                      : const Color(0xFF666666),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32)),
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  elevation: _canFinish ? 6 : 0,
                  shadowColor: AppColors.primary.withOpacity(0.4),
                ),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Text(
                    _canFinish
                        ? 'Confirm Plot  ·  ${_pts.length} points'
                        : 'Add at least $_minPoints points',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                  if (_canFinish) ...const [
                    SizedBox(width: 10),
                    Icon(Icons.check_circle, size: 20),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Helper widgets ────────────────────────────────────────────────────

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    Color? bg,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: bg ?? Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.2), blurRadius: 10),
            ],
          ),
          child: Icon(icon, color: color, size: 22),
        ),
      );

  Widget _ghostBtn(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white24),
          ),
          alignment: Alignment.center,
          child: Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1.5)),
        ),
      );
}

// ─── Suggestion tile ──────────────────────────────────────────────────────

class _SuggestionTile extends StatelessWidget {
  final _PlaceResult place;
  final VoidCallback onTap;

  const _SuggestionTile({required this.place, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: AppColors.greenLight,
      highlightColor: AppColors.greenLight.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.greenLight,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.location_on_rounded,
                color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(
                place.shortName,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111111)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                place.displayName,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          const SizedBox(width: 6),
          Icon(Icons.north_west_rounded,
              size: 14, color: Colors.grey.shade400),
        ]),
      ),
    );
  }
}
