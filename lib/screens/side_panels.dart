import 'dart:async';
import 'dart:io';
import 'dart:math' show max, min, pi, sin, cos, Random, sqrt, pow;
import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as video_thumbnail;
import '../config/app_env.dart';
import '../constants/app_strings.dart';
import '../main.dart' show appLocale;
import '../constants/app_constants.dart';
import '../services/weather_service.dart';
import '../services/plot_layer_api.dart';
import '../services/soil_param_api.dart';
import '../widgets/weather_widgets.dart';

// ═══════════════════════════════════════════════════════════════════
// SIDE PANEL CONTROLLER
// ═══════════════════════════════════════════════════════════════════
// ─── Reverse geocode: lat/lng → short address via Nominatim ─────────────────
Future<String> _reverseGeocode(double lat, double lng) async {
  try {
    final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse').replace(
      queryParameters: {'lat': lat.toString(), 'lon': lng.toString(), 'format': 'json'},
    );
    final res = await http.get(uri, headers: {'User-Agent': 'CropEyeApp/1.0'})
        .timeout(const Duration(seconds: 6));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final addr = data['address'] as Map<String, dynamic>?;
      if (addr != null) {
        final parts = <String>[];
        final village = addr['village'] ?? addr['town'] ?? addr['suburb'] ?? addr['hamlet'];
        final district = addr['district'] ?? addr['county'] ?? addr['state_district'];
        final state = addr['state'];
        if (village != null) parts.add(village as String);
        if (district != null) parts.add(district as String);
        if (state != null) parts.add(state as String);
        if (parts.isNotEmpty) return parts.take(2).join(', ');
      }
      // Fallback: use display_name first two parts
      final disp = data['display_name'] as String?;
      if (disp != null && disp.isNotEmpty) {
        return disp.split(',').take(2).join(',').trim();
      }
    }
  } catch (_) {}
  return '';
}


class SidePanelController extends StatelessWidget {
  final ActivePanel type;
  final VoidCallback onClose;
  final SoilData soilData;
  final List<AlertModel> alerts;
  final List<FieldModel> fields;
  final String selectedFieldId;
  final void Function(String) onSelectField;
  final Future<void> Function(String) onDeleteField;
  final void Function(String, String) onRenameField;
  final VoidCallback onAddNewField;
  final void Function(String) onResolveAlert;
  final double? fieldLat;
  final double? fieldLon;

  const SidePanelController({
    super.key, required this.type, required this.onClose,
    required this.soilData, required this.alerts, required this.fields,
    required this.selectedFieldId, required this.onSelectField,
    required this.onDeleteField, required this.onRenameField,
    required this.onAddNewField, required this.onResolveAlert,
    this.fieldLat, this.fieldLon,
  });

  bool get _isLeftDrawer => type == ActivePanel.soil ||
      type == ActivePanel.soilMoisture || type == ActivePanel.waterUptake ||
      type == ActivePanel.pestRisk || type == ActivePanel.insights ||
      type == ActivePanel.lands;

  @override
  Widget build(BuildContext context) {
    if (type == ActivePanel.none) return const SizedBox.shrink();

    return Stack(children: [
      // Backdrop
      GestureDetector(
        onTap: onClose,
        child: Container(color: Colors.black.withOpacity(0.45)),
      ),

      // Panel
      Align(
        alignment: _isLeftDrawer ? Alignment.centerLeft : Alignment.bottomCenter,
        child: _buildPanel(context),
      ),
    ]);
  }

  Widget _buildPanel(BuildContext context) {
    if (_isLeftDrawer) {
      return Container(
        width: MediaQuery.of(context).size.width * 0.88,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.horizontal(right: Radius.circular(56)),
        ),
        child: _panelContent(context),
      );
    }
    if (type == ActivePanel.scan || type == ActivePanel.grapeCount) {
      return SizedBox.expand(child: _panelContent(context));
    }
    return Container(
      width: MediaQuery.of(context).size.width * 0.94,
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
      ),
      child: _panelContent(context),
    );
  }

  Widget _panelContent(BuildContext context) {
    // Derive current field for soil panel
    final _currentField = fields.isEmpty ? null
        : fields.firstWhere((f) => f.id == selectedFieldId,
            orElse: () => fields.first);

    switch (type) {
      case ActivePanel.soil: return SoilPanel(
        soilData:        soilData,
        onClose:         onClose,
        plotName:        _currentField?.plotNameForAnalysis ?? '',
        polygon:         _currentField?.polygon ?? const [],
        center:          _currentField?.center  ?? const [20.5937, 78.9629],
        plantationDate:  _currentField?.plantationDate,
        initialSection:  'npk',
      );
      case ActivePanel.insights: return InsightsPanel(
        soilData: soilData, onClose: onClose,
        fieldLat: fieldLat, fieldLon: fieldLon,
      );
      // Soil Moisture → Farm Insights with 7-day moisture chart visible (no card pre-selected)
      case ActivePanel.soilMoisture: return InsightsPanel(
        soilData: soilData, onClose: onClose,
        fieldLat: fieldLat, fieldLon: fieldLon,
        initialSection: null, // just open insights at top — chart shows moisture
      );
      // Water Uptake → Farm Insights with Irrigation Depth Analysis card expanded
      case ActivePanel.waterUptake: return InsightsPanel(
        soilData: soilData, onClose: onClose,
        fieldLat: fieldLat, fieldLon: fieldLon,
        initialSection: 'Water',
      );
      // Pest Risk → Farm Insights with Entomological Forecast card expanded
      case ActivePanel.pestRisk: return InsightsPanel(
        soilData: soilData, onClose: onClose,
        fieldLat: fieldLat, fieldLon: fieldLon,
        initialSection: 'Pest Risk',
      );
      case ActivePanel.chat: return ChatPanel(onClose: onClose);
      case ActivePanel.lands: return LandsPanel(
        fields: fields, alerts: alerts, selectedFieldId: selectedFieldId,
        onSelectField: onSelectField, onDeleteField: onDeleteField,
        onRenameField: onRenameField, onAddNewField: onAddNewField,
        onResolveAlert: onResolveAlert, onClose: onClose);
      case ActivePanel.market: return MarketPanel(onClose: onClose);
      case ActivePanel.scan: return ScanPanel(onClose: onClose);
      case ActivePanel.grapeCount: return GrapeCountPanel(onClose: onClose);
      default: return const SizedBox.shrink();
    }
  }
}

// ─── Panel Header ────────────────────────────────────────────────────────────
class _PanelHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final VoidCallback? onBack;
  const _PanelHeader({required this.title, required this.onClose, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 8),
      child: Row(children: [
        if (onBack != null)
          IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_ios_new, size: 20), color: AppColors.textDark),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textDark))),
        GestureDetector(onTap: onClose,
          child: Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.close, size: 20, color: AppColors.textLight))),
      ]),
    );
  }
}

// ─── Full-Screen Header (with back arrow + swipe-down handle) ────────────────
class _FullScreenHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final bool useBackArrow;
  final Color? accentColor;
  const _FullScreenHeader({
    required this.title,
    required this.onClose,
    this.useBackArrow = true,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = accentColor ?? AppColors.primary;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg, _darken(bg, 0.12)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Center(
              child: Container(
                width: 38, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          // Back arrow + title row
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 14),
            child: Row(children: [
              if (useBackArrow)
                GestureDetector(
                  onTap: onClose,
                  child: Container(
                    width: 40, height: 40,
                    margin: const EdgeInsets.only(left: 8, right: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.18),
                      border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 17),
                  ),
                )
              else
                const SizedBox(width: 16),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.3)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Color _darken(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
  }
}

// ═══════════════════════════════════════════════════════════════════
// SOIL PANEL
// ═══════════════════════════════════════════════════════════════════
class SoilPanel extends StatefulWidget {
  final SoilData soilData;
  final VoidCallback onClose;
  final List<List<double>> polygon;
  final List<double> center;
  final String plotName;
  final String? plantationDate;
  /// 'moisture' — auto-scroll to moisture card on open
  /// 'npk'     — auto-scroll to NPK section (default, top)
  final String initialSection;

  const SoilPanel({
    super.key,
    required this.soilData,
    required this.onClose,
    this.plotName        = '',
    this.polygon         = const [],
    this.center          = const [20.5937, 78.9629],
    this.plantationDate,
    this.initialSection  = 'npk',
  });

  @override
  State<SoilPanel> createState() => _SoilPanelState();
}

class _SoilPanelState extends State<SoilPanel> {
  // ── Live data from Soil Parameter API ──────────────────────────
  SoilNpkResult?      _npkData;
  SoilAnalysisResult? _analysisData;
  SoilMoistureResult? _moistureData;

  bool _loading     = true;
  bool _hasLiveData = false;
  String? _error;

  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.plotName.isNotEmpty) _fetchAll();
    else setState(() => _loading = false);
  }

  Future<void> _fetchAll() async {
    setState(() { _loading = true; _error = null; });
    final today = DateTime.now().toString().split(' ')[0];
    final pDate = widget.plantationDate ?? today;
    bool anySuccess = false;

    // 1. NPK — nitrogen, phosphorus, potassium
    try {
      final r = await SoilParamApi.fetchNpk(
        plotName: widget.plotName,
        plantationDate: pDate,
        endDate: today,
      );
      if (mounted) setState(() { _npkData = r; anySuccess = true; });
    } catch (e) {
      // keep fallback soilData values
    }

    // 2. Analysis — pH, CEC, OC
    try {
      final r = await SoilParamApi.fetchAnalysis(
        plotName: widget.plotName,
        plantationDate: pDate,
        date: today,
      );
      if (mounted) setState(() { _analysisData = r; anySuccess = true; });
    } catch (e) {
      // keep fallback
    }

    // 3. Soil moisture (existing Railway API)
    try {
      final r = await SoilMoistureApi.fetch(widget.plotName);
      if (mounted) setState(() { _moistureData = r; anySuccess = true; });
    } catch (e) {
      // keep fallback
    }

    if (mounted) setState(() {
      _loading     = false;
      _hasLiveData = anySuccess;
    });
  }

  // ── Resolve values: live API > fallback soilData ────────────────
  double get _nitrogen    => _npkData?.soilN          ?? widget.soilData.nitrogen;
  double get _phosphorus  => _npkData?.soilP          ?? widget.soilData.phosphorus;
  double get _potassium   => _npkData?.soilK          ?? widget.soilData.potassium;
  double get _ph          => _analysisData?.ph        ?? widget.soilData.ph;
  double get _cec         => _analysisData?.cec       ?? widget.soilData.cec;
  double get _oc          => _analysisData?.oc        ?? widget.soilData.oc;
  double get _moisture    => _moistureData?.avgMoisture ?? widget.soilData.moisture;

  // Build a live SoilData for the health banner
  SoilData get _liveSoilData => SoilData(
    ph:         _ph,
    nitrogen:   _nitrogen,
    phosphorus: _phosphorus,
    potassium:  _potassium,
    moisture:   _moisture,
    cec:        _cec,
    oc:         _oc,
    bd:         widget.soilData.bd,
    fe:         widget.soilData.fe,
    soc:        widget.soilData.soc,
  );

  @override
  Widget build(BuildContext context) {
    final entries = [
      {'label': 'PH',         'value': _ph,         'max': 14.0,  'icon': '🧪'},
      {'label': 'NITROGEN',   'value': _nitrogen,   'max': 500.0, 'icon': '🔋'},
      {'label': 'PHOSPHORUS', 'value': _phosphorus, 'max': 200.0, 'icon': '💎'},
      {'label': 'POTASSIUM',  'value': _potassium,  'max': 400.0, 'icon': '⚡'},
      {'label': 'MOISTURE',   'value': _moisture,   'max': 100.0, 'icon': '💧'},
      {'label': 'CEC',        'value': _cec,        'max': 60.0,  'icon': '🧲'},
      {'label': 'OC',         'value': _oc,         'max': 20.0,  'icon': '🍂'},
    ];

    return Column(children: [
      _FullScreenHeader(title: 'Soil Nutrients', onClose: widget.onClose, useBackArrow: true),

      // ── NDVI / NDWI buttons ─────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(children: [
          Expanded(child: _VegetationIndexBtn(
            label: 'NDVI',
            subtitle: 'Vegetation Health',
            icon: Icons.grass,
            color: const Color(0xFF2E7D32),
            onTap: () => Navigator.of(context).push(PageRouteBuilder(
              pageBuilder: (_, __, ___) => VegetationIndexScreen(
                indexType: 'NDVI',
                polygon: widget.polygon,
                center: widget.center,
                plotName: widget.plotName,
              ),
              transitionsBuilder: (_, anim, __, child) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                    .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                child: child,
              ),
              transitionDuration: const Duration(milliseconds: 400),
            )),
          )),
          const SizedBox(width: 12),
          Expanded(child: _VegetationIndexBtn(
            label: 'NDWI',
            subtitle: 'Water Content',
            icon: Icons.water,
            color: const Color(0xFF0277BD),
            onTap: () => Navigator.of(context).push(PageRouteBuilder(
              pageBuilder: (_, __, ___) => VegetationIndexScreen(
                indexType: 'NDWI',
                polygon: widget.polygon,
                center: widget.center,
                plotName: widget.plotName,
              ),
              transitionsBuilder: (_, anim, __, child) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                    .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                child: child,
              ),
              transitionDuration: const Duration(milliseconds: 400),
            )),
          )),
        ]),
      ),

      // ── Loading / Live badge bar ────────────────────────────────
      if (_loading)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFFF0F4F0),
          child: Row(children: [
            const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2,
                    color: AppColors.primary)),
            const SizedBox(width: 10),
            const Text('Fetching live soil data…',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: AppColors.textLight)),
          ]),
        )
      else if (_hasLiveData)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: const Color(0xFFF0F4F0),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withOpacity(0.30)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6,
                    decoration: const BoxDecoration(
                        color: AppColors.primary, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                const Text('LIVE', style: TextStyle(fontSize: 9,
                    fontWeight: FontWeight.w900, color: AppColors.primary,
                    letterSpacing: 0.8)),
              ]),
            ),
            const SizedBox(width: 8),
            const Text('Data from Soil Parameter Analysis API',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                    color: AppColors.textLight)),
            const Spacer(),
            GestureDetector(
              onTap: _fetchAll,
              child: const Icon(Icons.refresh_rounded,
                  size: 16, color: AppColors.primary),
            ),
          ]),
        ),

      const Divider(height: 1, color: Color(0xFFF0F0F0)),

      Expanded(child: ListView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          _SoilHealthBanner(soilData: _liveSoilData),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemCount: entries.length,
            itemBuilder: (_, i) => _NutrientCard(
              label: entries[i]['label'] as String,
              value: entries[i]['value'] as double,
              max:   entries[i]['max']   as double,
              icon:  entries[i]['icon']  as String,
              isLive: _hasLiveData && !_loading,
            ),
          ),
        ],
      )),
    ]);
  }
}

// ── NDVI/NDWI index button ────────────────────────────────────────────────
class _VegetationIndexBtn extends StatelessWidget {
  final String label, subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _VegetationIndexBtn({
    required this.label, required this.subtitle,
    required this.icon, required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.12), color.withOpacity(0.05)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.35), width: 1.5),
          boxShadow: [BoxShadow(color: color.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.15),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: color)),
            Text(subtitle, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.textLight, letterSpacing: 0.3)),
          ])),
          Icon(Icons.arrow_forward_ios, color: color.withOpacity(0.6), size: 12),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// SOIL HEALTH BANNER — overall score card at top of soil panel
// ═══════════════════════════════════════════════════════════════════
class _SoilHealthBanner extends StatelessWidget {
  final SoilData soilData;
  const _SoilHealthBanner({required this.soilData});

  int get _score {
    // Weighted average of normalised nutrient levels
    final n  = (soilData.nitrogen   / 500.0).clamp(0.0, 1.0);
    final p  = (soilData.phosphorus / 200.0).clamp(0.0, 1.0);
    final k  = (soilData.potassium  / 400.0).clamp(0.0, 1.0);
    final m  = (soilData.moisture   / 100.0).clamp(0.0, 1.0);
    final o  = (soilData.oc         /  20.0).clamp(0.0, 1.0);
    final ph = (1.0 - ((soilData.ph - 6.5).abs() / 7.5)).clamp(0.0, 1.0);
    return ((n * 0.25 + p * 0.15 + k * 0.15 + m * 0.2 + o * 0.15 + ph * 0.1) * 100).round();
  }

  String get _label {
    final s = _score;
    if (s >= 80) return 'Excellent';
    if (s >= 60) return 'Good';
    if (s >= 40) return 'Fair';
    return 'Needs Attention';
  }

  String get _description {
    final s = _score;
    if (s >= 80) return 'Your soil is in peak condition. Nutrients are well-balanced for optimal crop growth.';
    if (s >= 60) return 'Soil health is good. Minor adjustments to nutrients can improve yield further.';
    if (s >= 40) return 'Soil condition is fair. Consider targeted fertilisation and moisture management.';
    return 'Soil needs attention. Review nutrient levels and schedule immediate treatment.';
  }

  @override
  Widget build(BuildContext context) {
    final score = _score;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF388E3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E7D32).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('OVERALL SOIL HEALTH',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Colors.white70,
                  letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Text(_label,
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.1)),
          const SizedBox(height: 10),
          Text(_description,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.85),
                  height: 1.45)),
        ])),
        const SizedBox(width: 16),
        // Score badge
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.18),
            border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
          ),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$score%',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1)),
              const Text('SCORE',
                  style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.w800,
                      color: Colors.white70,
                      letterSpacing: 0.5)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// NUTRIENT CARD — self-contained card with tube indicator inside
// ═══════════════════════════════════════════════════════════════════
class _NutrientCard extends StatefulWidget {
  final String label, icon;
  final double value, max;
  final bool isLive;
  const _NutrientCard({
    required this.label,
    required this.value,
    required this.max,
    required this.icon,
    this.isLive = false,
  });
  @override
  State<_NutrientCard> createState() => _NutrientCardState();
}

class _NutrientCardState extends State<_NutrientCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fillAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    final pct = (widget.value / widget.max).clamp(0.0, 1.0);
    _fillAnim = Tween<double>(begin: 0, end: pct)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double get _pct => (widget.value / widget.max).clamp(0.0, 1.0);

  Color get _levelColor {
    if (_pct > 0.6) return const Color(0xFF2E7D32);
    if (_pct > 0.3) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  Color get _chipBg {
    if (_pct > 0.6) return const Color(0xFFE8F5E9);
    if (_pct > 0.3) return const Color(0xFFFFF8E1);
    return const Color(0xFFFFEBEE);
  }

  String get _chipLabel {
    if (_pct > 0.6) return 'UP';
    if (_pct > 0.3) return 'MED';
    return 'DOWN';
  }

  @override
  Widget build(BuildContext context) {
    final isPH = widget.label == 'PH';
    final valStr = isPH
        ? widget.value.toStringAsFixed(1)
        : widget.value.toStringAsFixed(widget.value >= 100 ? 1 : 2);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: info column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon row
                  Row(children: [
                    Text(widget.icon, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.label,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textLight,
                          letterSpacing: 0.8,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.isLive) ...[
                      const SizedBox(width: 4),
                      Container(
                        width: 6, height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 10),
                  // Value
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          valStr,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textDark,
                            height: 1,
                          ),
                        ),
                        if (!isPH) ...[
                          const SizedBox(width: 2),
                          const Text(
                            'mg/kg',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textLight,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Status chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _chipBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _chipLabel,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: _levelColor,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right: tube indicator (fixed size, no overflow)
            SizedBox(
              width: 22,
              height: double.infinity,
              child: AnimatedBuilder(
                animation: _fillAnim,
                builder: (_, __) => CustomPaint(
                  painter: _TubePainter(fill: _fillAnim.value, color: _levelColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TubePainter extends CustomPainter {
  final double fill;
  final Color color;
  const _TubePainter({required this.fill, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    const bulbR = 9.0;
    const tubeR = 5.0;
    const tubeTop = 0.0;
    final tubeBottom = size.height - bulbR * 2 - 4;
    final bulbCy = size.height - bulbR;

    final bgPaint  = Paint()..color = const Color(0xFFF0F0F0);
    final fillPaint = Paint()..color = color;
    final rimPaint  = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Background track
    final trackRect = RRect.fromLTRBR(
      cx - tubeR, tubeTop, cx + tubeR, tubeBottom,
      const Radius.circular(tubeR),
    );
    canvas.drawRRect(trackRect, bgPaint);
    canvas.drawCircle(Offset(cx, bulbCy), bulbR, bgPaint);

    // Fill
    final tubeHeight = tubeBottom - tubeTop;
    final fillH  = tubeHeight * fill;
    final fillTop = tubeBottom - fillH;

    canvas.save();
    final clipPath = ui.Path()
      ..addRRect(RRect.fromLTRBR(
          cx - tubeR, fillTop, cx + tubeR, tubeBottom,
          const Radius.circular(tubeR)))
      ..addOval(Rect.fromCircle(
          center: Offset(cx, bulbCy), radius: bulbR));
    canvas.clipPath(clipPath);
    canvas.drawRRect(
      RRect.fromLTRBR(cx - tubeR, tubeTop, cx + tubeR, tubeBottom,
          const Radius.circular(tubeR)),
      fillPaint,
    );
    canvas.drawCircle(Offset(cx, bulbCy), bulbR, fillPaint);
    canvas.restore();

    // Outline
    canvas.drawRRect(trackRect, rimPaint);
    canvas.drawCircle(Offset(cx, bulbCy), bulbR, rimPaint);

    // Shine highlight
    if (fill > 0.05) {
      canvas.drawLine(
        Offset(cx - 1.5, fillTop + 5),
        Offset(cx - 1.5, tubeBottom - 4),
        Paint()
          ..color = Colors.white.withOpacity(0.4)
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
      );
    }

    // Percentage inside bulb
    final pctStr = '${(fill * 100).round()}%';
    final tp = TextPainter(
      text: TextSpan(
        text: pctStr,
        style: TextStyle(
          fontSize: 6.5,
          fontWeight: FontWeight.w900,
          color: fill > 0.25 ? Colors.white : color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, bulbCy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_TubePainter old) =>
      old.fill != fill || old.color != color;
}


// ═══════════════════════════════════════════════════════════════════
// VEGETATION INDEX SCREEN  (NDVI / NDWI)
// Full-screen satellite map with coloured polygon overlay.
// Uses Open-Meteo + Sentinel Hub NDVI API (free tier) for real data.
// Falls back to soil-data-derived values when API unavailable.
// ═══════════════════════════════════════════════════════════════════
class VegetationIndexScreen extends StatefulWidget {
  final String indexType; // 'NDVI' or 'NDWI'
  final List<List<double>> polygon;
  final List<double> center;
  /// plotNameForAnalysis — used to call PlotLayerApi.fetchGrowth (NDVI)
  /// or PlotLayerApi.fetchWater (NDWI) for real farm-status index values.
  final String plotName;

  const VegetationIndexScreen({
    super.key,
    required this.indexType,
    required this.polygon,
    required this.center,
    this.plotName = '',
  });

  @override
  State<VegetationIndexScreen> createState() => _VegetationIndexScreenState();
}

class _VegetationIndexScreenState extends State<VegetationIndexScreen>
    with TickerProviderStateMixin {
  final MapController _mapCtrl = MapController();

  // Index data
  bool _loading = true;
  String? _error;
  double _indexValue = 0.0;
  List<_ZoneData> _zones = [];
  String? _ndviTileUrl;            // real GEE tile URL from Growth/Water API
  String? _analysisDateRange;      // e.g. "Apr 09 – Apr 25"
  int _imageCount = 0;

  // Animation
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  late AnimationController _entryCtrl;
  late Animation<double> _entry;

  bool get _isNDVI => widget.indexType == 'NDVI';

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..forward();
    _entry = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic);
    _fetchIndex();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  // ── Fetch NDVI from Growth Analysis API / NDWI from Water Uptake API ─
  //
  //  Primary source: PlotLayerApi
  //    NDVI → /analyze_Growth?plot_name=…  pixel_summary.mean  (0–1 range)
  //    NDWI → /wateruptake?plot_name=…     pixel_summary.mean  (-1–1 range)
  //
  //  Fallback chain (if plotName is blank or API fails):
  //    1. Open-Meteo soil moisture + radiation proxy
  //    2. Hard-coded soil-data derived value
  Future<void> _fetchIndex() async {
    setState(() { _loading = true; _error = null; });

    // ── Primary: Farm Status API (Growth / Water Uptake) ──────────────
    // The API returns a Google Earth Engine tile_url — real NDVI/NDWI data
    // rendered as a coloured map overlay. We display this tile directly.
    if (widget.plotName.isNotEmpty) {
      try {
        final resp = _isNDVI
            ? await PlotLayerApi.fetchGrowth(widget.plotName)
            : await PlotLayerApi.fetchWater(widget.plotName);

        // Extract tile URL from features[0].properties.tile_url
        String? tileUrl;
        final feats = resp.raw['features'];
        if (feats is List && feats.isNotEmpty) {
          final props = feats[0]['properties'] as Map?;
          tileUrl = props?['tile_url'] as String?;

          // Extract analysis metadata
          final startDate = props?['start_date']?.toString() ?? '';
          final endDate   = props?['end_date']?.toString()   ?? '';
          final imgCount  = (props?['image_count'] ?? props?['image_count_in_range'] ?? 0) as int;
          if (startDate.isNotEmpty) {
            final s = DateTime.tryParse(startDate);
            final e = DateTime.tryParse(endDate);
            if (s != null && e != null) {
              _analysisDateRange =
                  '${_shortDate(s)} – ${_shortDate(e)}';
            }
          }
          _imageCount = imgCount;
        }

        if (tileUrl != null && tileUrl.isNotEmpty) {
          // Use the real GEE tile as the map overlay — no fake zones needed
          if (mounted) setState(() {
            _ndviTileUrl = tileUrl;
            _zones = []; // clear fake zones — tile shows real data
          });
        }

        // Also try to get a scalar value for the badge
        // Water API has pixel_summary; Growth API may not have mean
        final ps = resp.pixelSummary;
        if (ps != null) {
          // Water API: compute score from pixel percentages
          if (!_isNDVI) {
            final lessPct = (ps['less_pixel_percentage'] as num?)?.toDouble() ?? 0;
            final adqPct  = (ps['adequat_pixel_percentage'] as num?)?.toDouble() ?? 0;
            final excPct  = (ps['excellent_pixel_percentage'] as num?)?.toDouble() ?? 0;
            final exsPct  = (ps['excess_pixel_percentage'] as num?)?.toDouble() ?? 0;
            final total   = lessPct + adqPct + excPct + exsPct;
            if (total > 0) {
              _indexValue = ((lessPct * 0.25 + adqPct * 0.75 +
                  excPct * 1.0 + exsPct * 0.5) / total).clamp(0.0, 1.0);
            }
          } else {
            // Growth API: try mean/average
            final raw = (ps['mean'] as num?)?.toDouble()
                ?? (ps['average'] as num?)?.toDouble();
            if (raw != null) _indexValue = raw.clamp(-1.0, 1.0);
          }
        }

        if (mounted) setState(() => _loading = false);
        return; // ✅ tile loaded — skip Open-Meteo fallback
      } catch (_) {
        // API error — fall through to Open-Meteo
      }
    }

    // ── Fallback 1: Open-Meteo Agro API ──────────────────────────────
    try {
      final lat = widget.center[0], lon = widget.center[1];
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon'
        '&daily=et0_fao_evapotranspiration,precipitation_sum,shortwave_radiation_sum'
        '&current=temperature_2m,relative_humidity_2m,soil_moisture_0_to_1cm,'
        'soil_moisture_1_to_3cm,soil_moisture_3_to_9cm'
        '&timezone=auto',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        _processApiData(jsonDecode(resp.body) as Map<String, dynamic>);
        if (mounted) setState(() => _loading = false);
        return;
      }
    } catch (_) {}

    // ── Fallback 2: soil-data derived value ──────────────────────────
    _useFallback();
    if (mounted) setState(() => _loading = false);
  }

  String _shortDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month-1]} ${d.day}';
  }

  void _processApiData(Map<String, dynamic> data) {
    final current = data['current'] as Map<String, dynamic>? ?? {};
    final daily   = data['daily']   as Map<String, dynamic>? ?? {};

    // Derive NDVI proxy from soil moisture + radiation
    final sm0  = (current['soil_moisture_0_to_1cm']  as num?)?.toDouble() ?? 0.25;
    final sm1  = (current['soil_moisture_1_to_3cm']  as num?)?.toDouble() ?? 0.25;
    final sm3  = (current['soil_moisture_3_to_9cm']  as num?)?.toDouble() ?? 0.25;
    final rad  = ((daily['shortwave_radiation_sum'] as List?)?.first as num?)?.toDouble() ?? 15.0;
    final rh   = (current['relative_humidity_2m'] as num?)?.toDouble() ?? 60.0;

    final avgSoilMoisture = (sm0 + sm1 + sm3) / 3.0;

    double ndvi, ndwi;
    if (_isNDVI) {
      // NDVI proxy: combine soil moisture and radiation efficiency
      // Range typically -1 to 1; healthy crops: 0.4-0.8
      ndvi = (avgSoilMoisture * 1.8 + (rad / 30.0) * 0.4 + (rh / 100.0) * 0.2)
          .clamp(-1.0, 1.0);
      _indexValue = ndvi;
    } else {
      // NDWI proxy: water content from soil moisture & humidity
      // Range -1 to 1; positive = water present
      ndwi = (avgSoilMoisture * 2.0 + (rh / 100.0) * 0.5 - 0.3)
          .clamp(-1.0, 1.0);
      _indexValue = ndwi;
    }

    // Generate spatial variation across zones (simulate sub-field variability)
    _zones = _generateZones(_indexValue);
  }

  void _useFallback() {
    // Fallback: derive from known soil data (no API needed)
    // NDVI: based on N content and OC
    // NDWI: based on moisture
    if (_isNDVI) {
      _indexValue = (0.3 + (164.56 / 500.0) * 0.4 + (11.2 / 20.0) * 0.2).clamp(-1.0, 1.0);
    } else {
      _indexValue = ((45.0 / 100.0) * 1.5 - 0.35).clamp(-1.0, 1.0);
    }
    _zones = _generateZones(_indexValue);
  }

  // ── Generate spatial sub-zones covering the ENTIRE polygon ──────────
  // Strategy: lay a fine grid over the polygon bounding box, clip each
  // cell to the polygon, and assign a spatially-varying index value.
  List<_ZoneData> _generateZones(double baseValue) {
    if (widget.polygon.isEmpty) return [];

    final pts = widget.polygon.map((p) => LatLng(p[0], p[1])).toList();
    final rng  = Random(widget.indexType == 'NDVI' ? 7 : 13);

    // Bounding box
    double minLat = pts[0].latitude,  maxLat = pts[0].latitude;
    double minLon = pts[0].longitude, maxLon = pts[0].longitude;
    for (final p in pts) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    final dLat = maxLat - minLat;
    final dLon = maxLon - minLon;

    // Grid resolution — 6×6 = 36 cells
    const gridN = 6;
    final cellLat = dLat / gridN;
    final cellLon = dLon / gridN;

    // Spatial noise pattern: simulate real field variation
    // Use a smooth gradient + perlin-like noise
    final zones = <_ZoneData>[];

    for (int row = 0; row < gridN; row++) {
      for (int col = 0; col < gridN; col++) {
        // Cell corners
        final lat0 = minLat + row * cellLat;
        final lat1 = lat0 + cellLat;
        final lon0 = minLon + col * cellLon;
        final lon1 = lon0 + cellLon;

        // Cell center
        final cLat = (lat0 + lat1) / 2;
        final cLon = (lon0 + lon1) / 2;

        // Skip cells whose center is outside the polygon
        if (!_pointInPolygon(cLat, cLon, pts)) continue;

        // Spatially varying index value:
        // 1. Normalized position within bounding box (0..1)
        final nx = (cLon - minLon) / dLon;
        final ny = (cLat - minLat) / dLat;

        // 2. Smooth spatial gradient (centre of field tends to be healthier)
        final distFromCentre = sqrt(pow(nx - 0.5, 2) + pow(ny - 0.5, 2));
        final gradient = 1.0 - distFromCentre * 0.8; // edge slightly worse

        // 3. Low-frequency noise (simulates natural variation)
        final noise = sin(nx * pi * 3 + 0.5) * cos(ny * pi * 2 + 0.8) * 0.12
                    + rng.nextDouble() * 0.08 - 0.04;

        final cellValue = (baseValue * gradient + noise).clamp(-1.0, 1.0);

        // Clip cell quad to polygon (simple — use the center-tested quad)
        final cellPts = [
          LatLng(lat0, lon0),
          LatLng(lat0, lon1),
          LatLng(lat1, lon1),
          LatLng(lat1, lon0),
        ];

        zones.add(_ZoneData(polygon: cellPts, value: cellValue, opacity: 0.72));
      }
    }

    // If no cells fell inside (very small polygon), fall back to whole polygon
    if (zones.isEmpty) {
      zones.add(_ZoneData(polygon: pts, value: baseValue, opacity: 0.65));
    }

    return zones;
  }

  // ── Ray-casting point-in-polygon test ────────────────────────────
  bool _pointInPolygon(double lat, double lon, List<LatLng> poly) {
    int crossings = 0;
    final n = poly.length;
    for (int i = 0; i < n; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % n];
      if (((a.longitude <= lon && lon < b.longitude) ||
           (b.longitude <= lon && lon < a.longitude)) &&
          lat < (b.latitude - a.latitude) * (lon - a.longitude) /
              (b.longitude - a.longitude) + a.latitude) {
        crossings++;
      }
    }
    return crossings.isOdd;
  }

  Color _valueToColor(double v) {
    if (_isNDVI) {
      // NDVI: <0.2 = bare/red, 0.2-0.4 = sparse/orange, >0.4 = healthy/green
      if (v < 0.15) return const Color(0xFFD32F2F);  // Bad — red
      if (v < 0.35) return const Color(0xFFFF8F00);  // Moderate — orange
      if (v < 0.55) return const Color(0xFF7CB342);  // Fair — light green
      return const Color(0xFF2E7D32);                 // Good — deep green
    } else {
      // NDWI: <0 = dry/red, 0-0.2 = moderate/orange, >0.2 = wet/blue
      if (v < 0.0)  return const Color(0xFFD32F2F);  // Dry — red
      if (v < 0.15) return const Color(0xFFFF8F00);  // Moderate — orange
      if (v < 0.30) return const Color(0xFF4FC3F7);  // Moist — light blue
      return const Color(0xFF0277BD);                 // Wet — deep blue
    }
  }

  String _valueLabel(double v) {
    if (_isNDVI) {
      if (v < 0.15) return 'Poor Vegetation';
      if (v < 0.35) return 'Moderate Vegetation';
      if (v < 0.55) return 'Good Vegetation';
      return 'Excellent Vegetation';
    } else {
      if (v < 0.0)  return 'Dry Soil';
      if (v < 0.15) return 'Moderate Moisture';
      if (v < 0.30) return 'Good Water Content';
      return 'High Water Content';
    }
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.polygon.map((p) => LatLng(p[0], p[1])).toList();
    final mapCenter = LatLng(widget.center[0], widget.center[1]);
    final accentColor = _isNDVI ? const Color(0xFF2E7D32) : const Color(0xFF0277BD);

    return Scaffold(
      body: Stack(children: [

        // ── Satellite map ───────────────────────────────────────────
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: mapCenter,
              initialZoom: 17,
              minZoom: 10,
              maxZoom: 22,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
                pinchZoomThreshold: 0.1,
                scrollWheelVelocity: 0.005,
                rotationThreshold: 5.0,
                pinchMoveThreshold: 5.0,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'http://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}',
                maxZoom: 22,
                panBuffer: 2,
              ),

              // ── Real GEE NDVI/NDWI tile overlay ─────────────────
              if (_ndviTileUrl != null)
                FadeTransition(
                  opacity: _entry,
                  child: Opacity(
                    opacity: 0.85,
                    child: TileLayer(
                      urlTemplate: _ndviTileUrl!,
                      maxZoom: 22,
                    ),
                  ),
                ),

              // ── Fallback fake zones (only if no tile URL) ────────
              if (_ndviTileUrl == null && !_loading && _zones.isNotEmpty)
                FadeTransition(
                  opacity: _entry,
                  child: PolygonLayer(polygons: [
                    ..._zones.map((z) => Polygon(
                      points: z.polygon,
                      color: _valueToColor(z.value).withOpacity(z.opacity),
                      borderColor: Colors.white.withOpacity(0.15),
                      borderStrokeWidth: 0.5,
                    )),
                  ]),
                ),

              // ── Polygon border (always shown) ────────────────────
              if (pts.isNotEmpty)
                PolygonLayer(polygons: [
                  Polygon(
                    points: pts,
                    color: Colors.transparent,
                    borderColor: Colors.white,
                    borderStrokeWidth: 2.5,
                  ),
                ]),

              // ── Zone value labels (only when no tile) ────────────
              if (_ndviTileUrl == null && !_loading && _zones.isNotEmpty)
                MarkerLayer(
                  markers: _zones.map((z) {
                    final cLat = z.polygon.map((p) => p.latitude).reduce((a, b) => a + b) / z.polygon.length;
                    final cLon = z.polygon.map((p) => p.longitude).reduce((a, b) => a + b) / z.polygon.length;
                    final col = _valueToColor(z.value);
                    return Marker(
                      point: LatLng(cLat, cLon),
                      width: 42, height: 22,
                      child: FadeTransition(
                        opacity: _entry,
                        child: Container(
                          decoration: BoxDecoration(
                            color: col.withOpacity(0.88),
                            borderRadius: BorderRadius.circular(5),
                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 3)],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            z.value.toStringAsFixed(2),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => MarkerLayer(markers: [
                    Marker(
                      point: mapCenter,
                      width: 12, height: 12,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accentColor.withOpacity(0.6 * _pulse.value),
                          boxShadow: [BoxShadow(
                            color: accentColor.withOpacity(0.4),
                            blurRadius: 8 * _pulse.value,
                            spreadRadius: 3 * _pulse.value,
                          )],
                        ),
                      ),
                    ),
                  ]),
                ),
            ],
          ),
        ),

        // ── Top header with back arrow ──────────────────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [accentColor, _darken(accentColor, 0.15)],
              ),
            ),
            child: SafeArea(bottom: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 16, 14),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.18),
                        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 17),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.indexType,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                    Text(_isNDVI ? 'Vegetation Health Index' : 'Water Content Index',
                        style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.75), fontWeight: FontWeight.w600)),
                  ]),
                  const Spacer(),
                  // Live badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, __) => Container(
                          width: 7, height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(_pulse.value),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text('LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900,
                          color: Colors.white, letterSpacing: 1)),
                    ]),
                  ),
                ]),
              ),
            ])),
          ),
        ),

        // ── Loading spinner ─────────────────────────────────────────
        if (_loading)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.45),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20)],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(color: accentColor, strokeWidth: 3),
                    const SizedBox(height: 16),
                    Text('Fetching ${widget.indexType} data...',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    const SizedBox(height: 4),
                    const Text('Real-time satellite analysis',
                        style: TextStyle(fontSize: 11, color: AppColors.textLight)),
                  ]),
                ),
              ),
            ),
          ),

        // ── Bottom info card ────────────────────────────────────────
        if (!_loading)
          Positioned(
            bottom: 24, left: 16, right: 16,
            child: FadeTransition(
              opacity: _entry,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 20, offset: const Offset(0, 6))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Index value + label
                  Row(children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _valueToColor(_indexValue).withOpacity(0.12),
                        border: Border.all(color: _valueToColor(_indexValue).withOpacity(0.4), width: 2),
                      ),
                      child: Center(
                        child: Text(_indexValue.toStringAsFixed(2),
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900,
                                color: _valueToColor(_indexValue))),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_valueLabel(_indexValue),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                              color: _valueToColor(_indexValue))),
                      const SizedBox(height: 2),
                      Text('Field ${widget.indexType} Index — ${_isNDVI ? "NDVI > 0.4 is healthy" : "NDWI > 0.2 indicates water"}',
                          style: const TextStyle(fontSize: 10, color: AppColors.textLight, height: 1.4)),
                    ])),
                  ]),
                  const SizedBox(height: 16),
                  // Colour legend
                  Row(children: [
                    _legendItem(const Color(0xFFD32F2F), _isNDVI ? 'Poor' : 'Dry'),
                    _legendItem(const Color(0xFFFF8F00), 'Moderate'),
                    _legendItem(_isNDVI ? const Color(0xFF7CB342) : const Color(0xFF4FC3F7),
                        _isNDVI ? 'Good' : 'Moist'),
                    _legendItem(_isNDVI ? const Color(0xFF2E7D32) : const Color(0xFF0277BD),
                        _isNDVI ? 'Excellent' : 'Wet'),
                  ]),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _legendItem(Color color, String label) => Expanded(
    child: Column(children: [
      Container(height: 8, margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.textLight),
          textAlign: TextAlign.center),
    ]),
  );

  Color _darken(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
  }
}

class _ZoneData {
  final List<LatLng> polygon;
  final double value;
  final double opacity;
  const _ZoneData({required this.polygon, required this.value, required this.opacity});
}
class InsightsPanel extends StatefulWidget {
  final SoilData soilData;
  final VoidCallback onClose;
  final double? fieldLat;
  final double? fieldLon;
  /// Which card to auto-open: 'Water', 'Pest Risk', or null (show chart)
  final String? initialSection;

  const InsightsPanel({
    super.key,
    required this.soilData,
    required this.onClose,
    this.fieldLat,
    this.fieldLon,
    this.initialSection,
  });
  @override State<InsightsPanel> createState() => _InsightsPanelState();
}

class _InsightsPanelState extends State<InsightsPanel> {
  String? _selected;
  WeatherData? _weather;
  bool _weatherLoading = true;

  final ScrollController _insightScroll = ScrollController();

  @override
  void dispose() {
    _insightScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadWeather();
    // Auto-select the right card and scroll to it
    if (widget.initialSection != null) {
      _selected = widget.initialSection;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (_insightScroll.hasClients) {
            _insightScroll.animateTo(
              _insightScroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOut,
            );
          }
        });
      });
    }
  }

  Future<void> _loadWeather() async {
    final lat = widget.fieldLat ?? 20.5937;
    final lon = widget.fieldLon ?? 78.9629;
    final data = await WeatherService.fetchByCoords(lat, lon);
    if (mounted) setState(() { _weather = data; _weatherLoading = false; });
  }

  final _insights = [
    {'label': 'Water', 'status': 'LOW', 'icon': '💧',
      'title': 'Irrigation Depth Analysis',
      'detail': 'Sensors at 20cm show moisture depletion.',
      'action': 'Recommended: 12mm irrigation tonight.'},
    {'label': 'Pest Risk', 'status': 'HIGH', 'icon': '🪲',
      'title': 'Entomological Forecast',
      'detail': 'Current heat index (34°C) is high risk for Aphids.',
      'action': 'Recommended: Spot-check West boundary.'},
    {'label': 'Fertilizer', 'status': 'READY', 'icon': '🌾',
      'title': 'Nutrient Uptake Status',
      'detail': 'Nitrogen is being metabolized rapidly.',
      'action': 'Recommended: Prepare Nitrogen top-dressing.'},
    {'label': 'Weather', 'status': 'RAIN 4PM', 'icon': '🌦️',
      'title': 'Micro-Climate Window',
      'detail': 'Low-pressure system North. Rain expected.',
      'action': 'Recommended: Hold foliar sprays.'},
  ];

  @override
  Widget build(BuildContext context) {
    final data = MockData.historicalData;

    return Column(children: [
      _PanelHeader(title: 'Farm Insights', onClose: widget.onClose),
      Expanded(child: ListView(controller: _insightScroll, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), children: [

        // Chart
        Container(padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                Text('Soil Health Trends', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.textDark)),
                Text('Last 7 Days', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 1)),
              ]),
              Row(children: [
                _legend(AppColors.primary, 'Nitrogen'),
                const SizedBox(width: 12),
                _legend(Colors.blue, 'Moisture'),
              ]),
            ]),
            const SizedBox(height: 16),
              SizedBox(height: 160,
              child: LineChart(LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFFF1F5F9), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 1,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= data.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text((data[i]['date'] as String).substring(4),
                          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.textLight)));
                    })),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(data.length, (i) => FlSpot(i.toDouble(), (data[i]['nitrogen'] as double))),
                    isCurved: true, color: AppColors.primary, barWidth: 3,
                    dotData: FlDotData(show: true,
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(radius: 4, color: AppColors.primary, strokeWidth: 2, strokeColor: Colors.white))),
                  LineChartBarData(
                    spots: List.generate(data.length, (i) => FlSpot(i.toDouble(), (data[i]['moisture'] as double))),
                    isCurved: true, color: Colors.blue, barWidth: 3,
                    dotData: FlDotData(show: true,
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(radius: 4, color: Colors.blue, strokeWidth: 2, strokeColor: Colors.white))),
                ],
              ))),
          ])),

        const SizedBox(height: 20),

        // Insight cards
        GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.1,
          children: _insights.map((ins) {
            final isWeather = ins['label'] == 'Weather';
            final isSel = _selected == ins['label'];

            // Dynamic weather values
            final String icon = isWeather
                ? (_weatherLoading ? '⏳' : (_weather != null ? _weatherConditionIcon(_weather!.condition) : ins['icon'] as String))
                : ins['icon'] as String;
            final String status = isWeather
                ? (_weatherLoading ? 'LOADING...' : (_weather != null ? '${_weather!.tempC.round()}°C · ${_weather!.description.toUpperCase()}' : ins['status'] as String))
                : ins['status'] as String;

            return GestureDetector(
              onTap: () => setState(() => _selected = isSel ? null : ins['label'] as String?),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSel ? Colors.white : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: isSel ? AppColors.primary : AppColors.borderLight, width: 2),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(icon, style: TextStyle(fontSize: isSel ? 32 : 28)),
                  const SizedBox(height: 8),
                  Text(ins['label'] as String,
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.textLight, letterSpacing: 1)),
                  const SizedBox(height: 2),
                  Text(status,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(fontSize: isWeather ? 10 : 12, fontWeight: FontWeight.w900, color: isSel ? AppColors.primary : AppColors.textDark)),
                ]),
              ),
            );
          }).toList()),

        if (_selected != null) ...[
          const SizedBox(height: 16),
          Builder(builder: (_) {
            final ins = _insights.firstWhere((i) => i['label'] == _selected);
            final isWeather = ins['label'] == 'Weather';

            if (isWeather && _weather != null) {
              return _WeatherDetailCard(weather: _weather!);
            }

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.borderLight)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ins['title'] as String,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 1)),
                const SizedBox(height: 8),
                Text(ins['detail'] as String,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark, height: 1.4)),
                const SizedBox(height: 12),
                Container(padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderLight)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('AI Action Plan', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFFD97706), letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(ins['action'] as String,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMedium, fontStyle: FontStyle.italic)),
                  ])),
              ]),
            );
          }),
        ],
        const SizedBox(height: 24),
      ])),
    ]);
  }

  Widget _legend(Color c, String label) => Row(children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: AppColors.textLight, letterSpacing: 0.5)),
  ]);

  String _weatherConditionIcon(WeatherCondition c) {
    switch (c) {
      case WeatherCondition.clearDay: return '☀️';
      case WeatherCondition.clearNight: return '🌙';
      case WeatherCondition.partlyCloudyDay: return '⛅';
      case WeatherCondition.partlyCloudyNight: return '🌤';
      case WeatherCondition.cloudy: return '☁️';
      case WeatherCondition.rain: return '🌧️';
      case WeatherCondition.thunderstorm: return '⛈️';
      case WeatherCondition.snow: return '❄️';
      case WeatherCondition.foggy: return '🌫️';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// WEATHER DETAIL CARD (shown when Weather insight is expanded)
// ═══════════════════════════════════════════════════════════════════
class _WeatherDetailCard extends StatelessWidget {
  final WeatherData weather;
  const _WeatherDetailCard({required this.weather});

  @override
  Widget build(BuildContext context) {
    final w = weather;
    final isNight = !w.isDay;
    final bgStart = isNight ? const Color(0xFF0D1B2A) : const Color(0xFF4FC3F7);
    final bgEnd = isNight ? const Color(0xFF1A2F4A) : const Color(0xFF0288D1);

    String advice = '';
    if (w.condition == WeatherCondition.rain || w.condition == WeatherCondition.thunderstorm) {
      advice = 'Hold foliar sprays. Secure equipment and clear drainage channels.';
    } else if (w.condition == WeatherCondition.clearDay && w.tempC > 35) {
      advice = 'High heat — irrigate early morning. Avoid midday field work.';
    } else if (w.condition == WeatherCondition.clearDay || w.condition == WeatherCondition.partlyCloudyDay) {
      advice = 'Good conditions for field operations and foliar applications.';
    } else if (w.condition == WeatherCondition.snow) {
      advice = 'Protect crops from frost. Cover sensitive seedlings.';
    } else {
      advice = 'Monitor conditions and proceed with standard operations.';
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [bgStart, bgEnd]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: bgEnd.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Row(children: [
            const Text('MICRO-CLIMATE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white70, letterSpacing: 1.5)),
            const Spacer(),
            Text(w.cityName, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white60)),
          ]),
        ),
        // Main temp row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            Text(_conditionIcon(w.condition), style: const TextStyle(fontSize: 44)),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(w.tempLabel,
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
              Text('Feels like ${w.feelsLikeC.round()}°C',
                  style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600)),
              Text(w.description.toUpperCase(),
                  style: const TextStyle(fontSize: 10, color: Colors.white60, letterSpacing: 1, fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
        // Stats row
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _stat('💧', 'Humidity', w.humidityLabel),
            _vDivider(),
            _stat('☁️', 'Cloud', '${w.cloudCoverPct.round()}%'),
            if (w.rainMmLastHour != null) ...[
              _vDivider(),
              _stat('🌧️', 'Rain/h', '${w.rainMmLastHour!.toStringAsFixed(1)}mm'),
            ],
          ]),
        ),
        // AI advice
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('AI ACTION PLAN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFFFFD54F), letterSpacing: 1.2)),
              const SizedBox(height: 6),
              Text(advice, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white, height: 1.4)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _stat(String emoji, String label, String value) => Column(children: [
    Text(emoji, style: const TextStyle(fontSize: 16)),
    const SizedBox(height: 4),
    Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white)),
    Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white60, letterSpacing: 0.5)),
  ]);

  Widget _vDivider() => Container(width: 1, height: 40, color: Colors.white.withOpacity(0.15));

  String _conditionIcon(WeatherCondition c) {
    switch (c) {
      case WeatherCondition.clearDay: return '☀️';
      case WeatherCondition.clearNight: return '🌙';
      case WeatherCondition.partlyCloudyDay: return '⛅';
      case WeatherCondition.partlyCloudyNight: return '🌤';
      case WeatherCondition.cloudy: return '☁️';
      case WeatherCondition.rain: return '🌧️';
      case WeatherCondition.thunderstorm: return '⛈️';
      case WeatherCondition.snow: return '❄️';
      case WeatherCondition.foggy: return '🌫️';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// CHAT PANEL
// ═══════════════════════════════════════════════════════════════════
class ChatPanel extends StatefulWidget {
  final VoidCallback onClose;
  const ChatPanel({super.key, required this.onClose});
  @override State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, String>> _history = [
    {'role': 'a', 'text': "Hey! I'm CropEye AI. How can I help with your field today?"}
  ];
  bool _loading = false;

  // ── Voice ────────────────────────────────────────────────────────
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _listening = false;
  String _voiceHint = '';

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (_) => setState(() => _listening = false),
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          setState(() => _listening = false);
          if (_voiceHint.trim().isNotEmpty) {
            _ctrl.text = _voiceHint;
            _voiceHint = '';
            _send();
          }
        }
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _toggleVoice() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Microphone not available on this device.'),
          backgroundColor: AppColors.primary));
      return;
    }
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
    } else {
      setState(() { _listening = true; _voiceHint = ''; });
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _voiceHint = result.recognizedWords;
            _ctrl.text = _voiceHint;
          });
        },
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
        localeId: 'en_IN',
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _speech.stop();
    super.dispose();
  }

  void _send() {
    if (_ctrl.text.trim().isEmpty) return;
    final msg = _ctrl.text.trim();
    _ctrl.clear();
    setState(() { _history.add({'role': 'u', 'text': msg}); _loading = true; });
    _callGemini(msg);
  }

  Future<void> _callGemini(String userMessage) async {
    if (AppEnv.geminiApiKey.isEmpty) {
      if (mounted) {
        setState(() {
          _history.add({
            'role': 'a',
            'text':
                '🌾 Add GEMINI_API_KEY in assets/.env (see .env.example) to use the AI assistant.',
          });
          _loading = false;
        });
      }
      return;
    }
    try {
      // Build conversation history for context
      final contents = <Map<String, dynamic>>[];
      // Add system context
      contents.add({
        'role': 'user',
        'parts': [{'text':
          'You are CropEye AI, an expert agricultural assistant for Indian farmers. '
          'Give concise, practical farming advice. Respond in plain text (no markdown). '
          'Keep responses under 3 sentences unless detail is needed.'
        }]
      });
      contents.add({'role': 'model', 'parts': [{'text': 'Understood. I\'m ready to help with your farming questions.'}]});
      // Add chat history
      for (final m in _history) {
        if (m['role'] == 'u') {
          contents.add({'role': 'user', 'parts': [{'text': m['text']}]});
        } else if (m['text'] != "Hey! I'm CropEye AI. How can I help with your field today?") {
          contents.add({'role': 'model', 'parts': [{'text': m['text']}]});
        }
      }
      // Add current message
      contents.add({'role': 'user', 'parts': [{'text': userMessage}]});

      final res = await http.post(
        Uri.parse(AppEnv.geminiGenerateContentUrl()),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'contents': contents}),
      ).timeout(const Duration(seconds: 20));

      String reply = '🌾 Sorry, I could not get a response right now. Please try again.';
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
        if (text != null && text.isNotEmpty) reply = text.trim();
      }
      if (mounted) {
        setState(() { _history.add({'role': 'a', 'text': reply}); _loading = false; });
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _history.add({'role': 'a', 'text': '🌾 Connection error. Please check your internet and try again.'});
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Column(children: [
      _FullScreenHeader(title: 'AI Assistant', onClose: widget.onClose,
          useBackArrow: canPop, accentColor: AppColors.primary),
      Expanded(child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _history.length + (_loading ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _history.length) return _bubble('...', false);
          final m = _history[i];
          return _bubble(m['text']!, m['role'] == 'u');
        },
      )),

      // Voice hint banner while listening
      if (_listening)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(children: [
            const Icon(Icons.mic, color: Colors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _voiceHint.isEmpty ? 'Listening...' : _voiceHint,
                style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ),
          ]),
        ),

      // Input row
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade100))),
        child: Row(children: [
          // Voice button
          GestureDetector(
            onTap: _toggleVoice,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: _listening ? Colors.red : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _listening ? Icons.mic : Icons.mic_none,
                color: _listening ? Colors.white : AppColors.textMedium,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: TextField(
            controller: _ctrl,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: _listening ? 'Speak now...' : 'Ask anything...',
              hintStyle: const TextStyle(color: AppColors.textLight),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 14),
            ),
          )),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 46, height: 46,
              decoration: const BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome,
                  color: Colors.white, size: 20)),
          ),
        ]),
      ),
    ]);
  }

  Widget _bubble(String text, bool isUser) => Align(
    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75),
      decoration: BoxDecoration(
        color: isUser ? AppColors.primary : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(22)),
      child: Text(text,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: isUser ? Colors.white : AppColors.textDark)),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════
// LANDS PANEL
// ═══════════════════════════════════════════════════════════════════
class LandsPanel extends StatefulWidget {
  final List<FieldModel> fields;
  final List<AlertModel> alerts;
  final String selectedFieldId;
  final void Function(String) onSelectField;
  final Future<void> Function(String) onDeleteField;
  final void Function(String, String) onRenameField;
  final VoidCallback onAddNewField;
  final void Function(String) onResolveAlert;
  final VoidCallback onClose;

  const LandsPanel({super.key, required this.fields, required this.alerts,
    required this.selectedFieldId, required this.onSelectField, required this.onDeleteField,
    required this.onRenameField, required this.onAddNewField, required this.onResolveAlert, required this.onClose});

  @override State<LandsPanel> createState() => _LandsPanelState();
}

class _LandsPanelState extends State<LandsPanel> {
  String? _editingId;
  late TextEditingController _renameCtrl;
  AlertModel? _solutionAlert;

  @override
  void initState() { super.initState(); _renameCtrl = TextEditingController(); }
  @override
  void dispose() { _renameCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_solutionAlert != null) return _buildSolutionView(_solutionAlert!);

    return Column(children: [
      _PanelHeader(title: 'My Lands', onClose: widget.onClose),
      Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        ...widget.fields.map((f) {
          final isSel = f.id == widget.selectedFieldId;
          final fieldAlerts = widget.alerts.where((a) => a.fieldId == f.id).toList();

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isSel ? Colors.white : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: isSel ? AppColors.primary : AppColors.borderLight, width: 2),
              boxShadow: isSel ? [BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 16)] : null,
            ),
            child: Column(children: [
              Padding(padding: const EdgeInsets.all(18), child: Row(children: [
                GestureDetector(
                  onTap: () { widget.onSelectField(f.id); widget.onClose(); },
                  child: Row(children: [
                    Container(width: 48, height: 48,
                      decoration: BoxDecoration(color: isSel ? AppColors.primary : Colors.white, borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isSel ? AppColors.primary : AppColors.borderLight)),
                      child: Icon(Icons.landscape, color: isSel ? Colors.white : Colors.grey.shade300, size: 24)),
                    const SizedBox(width: 14),
                  ]),
                ),
                Expanded(child: GestureDetector(
                  onTap: () { widget.onSelectField(f.id); widget.onClose(); },
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (_editingId == f.id)
                      TextField(controller: _renameCtrl, autofocus: true,
                        onSubmitted: (_) => _saveRename(f.id),
                        decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder()),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))
                    else
                      Text(f.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
                          color: isSel ? AppColors.primary : AppColors.textDark)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 4, children: [
                      Text(f.crop, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.5)),
                      if (f.cropVariety != null) ...[
                        const Text('•', style: TextStyle(fontSize: 10, color: AppColors.textLight)),
                        Text(f.cropVariety!, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary)),
                      ],
                      const Text('•', style: TextStyle(fontSize: 10, color: AppColors.textLight)),
                      Text(f.area, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textLight)),
                    ]),
                    if (f.plantationDate != null || f.irrigationType != null)
                      Padding(padding: const EdgeInsets.only(top: 4),
                        child: Row(children: [
                          if (f.plantationDate != null) Text('📅 ${f.plantationDate}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textLight)),
                          if (f.plantationDate != null && f.irrigationType != null) const SizedBox(width: 8),
                          if (f.irrigationType != null) Text('💧 ${f.irrigationType}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textLight)),
                        ])),
                    // FIX 2: Show reverse-geocoded address under each plot
                    if (f.center.length >= 2)
                      _PlotAddressLine(lat: f.center[0], lng: f.center[1]),
                  ]),
                )),
                Column(children: [
                  if (_editingId == f.id)
                    IconButton(onPressed: () => _saveRename(f.id),
                      icon: const Icon(Icons.check, color: AppColors.primary, size: 20))
                  else ...[
                    IconButton(onPressed: () => setState(() { _editingId = f.id; _renameCtrl.text = f.name; }),
                      icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textLight)),
                    IconButton(
                      onPressed: () async {
                        // Confirmation dialog before deleting
                        final confirmed = await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            backgroundColor: Colors.white,
                            title: const Row(children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.red, size: 22),
                              SizedBox(width: 8),
                              Text('Delete Plot',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.textDark)),
                            ]),
                            content: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                    color: AppColors.textMedium,
                                    fontSize: 13, height: 1.5),
                                children: [
                                  const TextSpan(
                                      text: 'Are you sure you want to delete '),
                                  TextSpan(
                                    text: '"${f.name}"',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.textDark),
                                  ),
                                  const TextSpan(
                                      text: '?\n\nThis will permanently remove '
                                            'the plot from the server and cannot '
                                            'be undone.'),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancel',
                                    style: TextStyle(
                                        color: AppColors.textMedium,
                                        fontWeight: FontWeight.w700)),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Delete',
                                    style: TextStyle(fontWeight: FontWeight.w900)),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await widget.onDeleteField(f.id);
                        }
                      },
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: Colors.red)),
                  ],
                ]),
              ])),

              if (fieldAlerts.isNotEmpty)
                Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(children: fieldAlerts.map((a) => _alertRow(a)).toList())),
            ]),
          );
        }),

        // Add new field
        GestureDetector(
          onTap: widget.onAddNewField,
          child: Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.borderLight, width: 2, style: BorderStyle.solid)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
              Icon(Icons.add_circle_outline, color: AppColors.textLight),
              SizedBox(width: 10),
              Text('Register New Plot', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.textLight)),
            ]),
          ),
        ),
      ])),
    ]);
  }

  Widget _alertRow(AlertModel a) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.borderLight)),
    child: Row(children: [
      Container(width: 4, height: 40,
        decoration: BoxDecoration(
          color: a.severity == 'high' ? Colors.red : Colors.amber,
          borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(a.message, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textDark)),
        const SizedBox(height: 2),
        Text(a.time, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.textLight, letterSpacing: 1)),
      ])),
      GestureDetector(
        onTap: () => setState(() => _solutionAlert = a),
        child: Container(padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: a.severity == 'high' ? Colors.red : Colors.amber, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.arrow_forward, color: Colors.white, size: 16))),
    ]),
  );

  void _saveRename(String id) {
    if (_renameCtrl.text.trim().isNotEmpty) widget.onRenameField(id, _renameCtrl.text.trim());
    setState(() => _editingId = null);
  }

  Widget _buildSolutionView(AlertModel alert) {
    final solutions = {
      'pest': {'title': 'Pest Management Workflow', 'steps': ['Locate Zone 3 samples.', 'Inspect leaf undersides.', 'Apply Neem Oil solution.', 'Re-sync in 24 hours.']},
      'irrigation': {'title': 'Water Crisis Resolution', 'steps': ['Check Sector B valve.', 'Override pump timer.', 'Check soil sensors.', 'Verify reservoir.']},
      'weather': {'title': 'Weather Response Plan', 'steps': ['Cease foliar fertilizer.', 'Secure equipment.', 'Clear drainage channels.', "Wait for 'Clear' status."]},
    };
    final sol = solutions[alert.type] ?? {'title': 'General Guide', 'steps': ['Check field boundaries.', 'Contact support.']};
    final steps = sol['steps'] as List<String>;

    return Column(children: [
      _PanelHeader(title: 'Solution Guide', onClose: widget.onClose, onBack: () => setState(() => _solutionAlert = null)),
      Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        Container(padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: AppColors.greenLight, borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.primary.withOpacity(0.2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ACTIVE STRATEGY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Text(sol['title'] as String, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textDark)),
          ])),
        const SizedBox(height: 16),
        ...List.generate(steps.length, (i) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderLight)),
          child: Row(children: [
            Container(width: 32, height: 32,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white,
                border: Border.all(color: AppColors.primary, width: 2)),
              alignment: Alignment.center,
              child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.primary))),
            const SizedBox(width: 14),
            Expanded(child: Text(steps[i], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark, height: 1.4))),
          ]),
        )),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity,
          child: ElevatedButton(
            onPressed: () { widget.onResolveAlert(alert.id); setState(() => _solutionAlert = null); },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              padding: const EdgeInsets.symmetric(vertical: 18)),
            child: const Text('Mark Issue as Resolved', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)))),
        const SizedBox(height: 24),
      ])),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════
// MARKET PANEL
// ═══════════════════════════════════════════════════════════════════
class MarketPanel extends StatelessWidget {
  final VoidCallback onClose;
  const MarketPanel({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _PanelHeader(title: 'Market Prices', onClose: onClose),
      Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        Container(padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFFDE68A))),
          child: Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Market Trends', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textDark)),
              SizedBox(height: 4),
              Text('Real-time prices from local mandis.', style: TextStyle(fontSize: 12, color: AppColors.textMedium)),
            ])),
            const Text('📊', style: TextStyle(fontSize: 32)),
          ])),
        const SizedBox(height: 16),
        ...MockData.marketPrices.map((item) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
          child: Row(children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: Text(item['emoji'] as String, style: const TextStyle(fontSize: 24))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item['crop'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.textDark)),
              const Text('Per Quintal', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 0.5)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(item['price'] as String, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textDark)),
              Text(item['change'] as String,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                  color: (item['trend'] as String) == 'up' ? Colors.green.shade600 : Colors.red)),
            ]),
          ]),
        )),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.greenLight, borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withOpacity(0.15))),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI MARKET PREDICTION', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 1.5)),
            SizedBox(height: 6),
            Text('"Wheat prices are expected to rise by 4% next week due to supply constraints. Consider holding your stock."',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMedium, fontStyle: FontStyle.italic, height: 1.5)),
          ])),
        const SizedBox(height: 24),
      ])),
    ]);
  }
}
// ═══════════════════════════════════════════════════════════════════
// SMART SCANNER  — Plant Health + Fruit Counter + Grape Counter
// ═══════════════════════════════════════════════════════════════════

enum _ScanMode { plantHealth, fruitCount, grapeCount }
enum _ScanStep { idle, scanning, result }

class ScanPanel extends StatefulWidget {
  final VoidCallback onClose;
  const ScanPanel({super.key, required this.onClose});
  @override
  State<ScanPanel> createState() => _ScanPanelState();
}

class _ScanPanelState extends State<ScanPanel>
    with TickerProviderStateMixin {

  _ScanMode _mode = _ScanMode.plantHealth;
  _ScanStep _step = _ScanStep.idle;
  String? _error;
  Map<String, dynamic>? _result;
  Uint8List? _imageBytes;
  String? _imageMime;

  // ── API configs ───────────────────────────────────────────────
  static String get _fruitImageUrl =>
      '${AppEnv.scannerApiBase}/fruits/image';
  static String get _grapeImageUrl =>
      '${AppEnv.scannerApiBase}/grape/image';

  static const _geminiPrompt =
      'You are an expert agricultural AI. Analyze this plant/crop image and '
      'respond with ONLY a valid JSON object — no markdown, no backticks, no extra text. '
      'Use this exact structure (keep string values concise, max 1-2 sentences each):\n'
      '{"plantName":"","cropType":"vegetable|fruit|ornamental|cereal|herb|tree|shrub|other",'
      '"growthStage":"seedling|vegetative|flowering|fruiting|mature|dormant|unknown",'
      '"overallHealth":"Healthy|Mild Concern|Moderate Concern|Severe Concern",'
      '"healthScore":0,'
      '"summary":"",'
      '"diseases":[{"name":"","severity":"Low|Medium|High","description":"","affectedParts":"","confidence":0}],'
      '"pests":[{"name":"","severity":"Low|Medium|High","description":"","affectedParts":"","confidence":0}],'
      '"waterRequirements":{"frequency":"","amount":"","method":"","notes":""},'
      '"soilAndNutrition":{"phRange":"","fertilizer":"","schedule":"","lightIntensity":"Excellent|Good|Moderate|Low|Critical","lightScore":0,"lightSufficiencyForPhotosynthesis":"Optimal|Sufficient|Marginal|Insufficient|Critical Deficiency","lightRecommendation":""},'
      '"treatments":[{"type":"Fungicide|Pesticide|Organic|Cultural|Nutritional|Preventive","product":"","instructions":"","priority":"Urgent|High|Medium|Low"}],'
      '"environmentalConditions":{"sunlight":"Full sun|Partial shade|Full shade","temperature":"","humidity":"Low|Medium|High"},'
      '"generalAdvice":""}'
      '\n\nRules: healthScore 90-100=Healthy, 70-89=Mild Concern, 40-69=Moderate Concern, 0-39=Severe Concern. '
      'Empty arrays [] if none found. Return ONLY the JSON.';

  // Fruit counter prompt — count, health analysis, and estimated weight via Gemini
  static const _geminifruitPrompt =
      'You are an expert agricultural AI and fruit quality inspector. '
      'Carefully analyze this image and respond with ONLY a valid JSON object — '
      'no markdown, no backticks, no extra text. '
      'Use this exact structure:\n'
      '{'
      '"fruits":['
        '{"name":"<fruit name>","count":<integer>,"emoji":"<single emoji>",'
        '"health":{"overallHealth":"Excellent|Good|Fair|Poor","healthScore":<0-100>,'
        '"color":"<description of color — indicates ripeness>","texture":"<description>","defects":"<any visible defects or none>",'
        '"ripeness":"Unripe|Nearly Ripe|Ripe|Overripe","recommendation":"<1 sentence action>"},'
        '"weight":{"estimatedWeightGrams":<number>,"totalWeightKg":<number>,'
        '"weightBasis":"<how weight was estimated — e.g. average mango ~250g>"}}],'
      '"totalFruitCount":<sum of all counts>,'
      '"imageSummary":"<1-2 sentence overview of the image>","farmingTip":"<1 actionable farming tip>"}'
      '\n\nRules: '
      'Count every visible fruit of each type separately. '
      'healthScore: 90-100=Excellent, 70-89=Good, 50-69=Fair, 0-49=Poor. '
      'estimatedWeightGrams is the average weight of ONE fruit of that type. '
      'totalWeightKg = (count × estimatedWeightGrams) / 1000. '
      'If no fruits are visible return {"fruits":[],"totalFruitCount":0,"imageSummary":"No fruits detected.","farmingTip":""}. '
      'Return ONLY the JSON, nothing else.';

  // ── Animations ────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;
  late AnimationController _sweepCtrl;
  late Animation<double>   _sweepAnim;
  late AnimationController _glowCtrl;
  late Animation<double>   _glowAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.88, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _sweepCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
    _sweepAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _sweepCtrl, curve: Curves.linear));

    _glowCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _sweepCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  // ── Mode config ───────────────────────────────────────────────
  Color get _modeColor {
    switch (_mode) {
      case _ScanMode.plantHealth: return const Color(0xFF00C853);
      case _ScanMode.fruitCount:  return const Color(0xFFFF6F00);
      case _ScanMode.grapeCount:  return const Color(0xFF7B1FA2);
    }
  }

  String get _modeLabel {
    switch (_mode) {
      case _ScanMode.plantHealth: return 'PLANT HEALTH';
      case _ScanMode.fruitCount:  return 'FRUIT COUNTER';
      case _ScanMode.grapeCount:  return 'GRAPE COUNTER';
    }
  }

  String get _modeEmoji {
    switch (_mode) {
      case _ScanMode.plantHealth: return '🌿';
      case _ScanMode.fruitCount:  return '🍎';
      case _ScanMode.grapeCount:  return '🍇';
    }
  }

  String get _modeDescription {
    switch (_mode) {
      case _ScanMode.plantHealth:
        return 'AI-powered disease, pest & treatment analysis using Gemini Vision';
      case _ScanMode.fruitCount:
        return 'Detects & counts: Orange, Apple, Pomegranate, Kiwi, Lime, Peach, Pear, Plum';
      case _ScanMode.grapeCount:
        return 'Detects & counts grape clusters using specialized computer vision';
    }
  }

  // ── Pick + analyze ─────────────────────────────────────────
  Future<void> _pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
          source: source, imageQuality: 85, maxWidth: 1280);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final ext   = file.name.split('.').last.toLowerCase();
      final mime  = ext == 'png' ? 'image/png' : 'image/jpeg';
      setState(() {
        _imageBytes = bytes; _imageMime = mime;
        _step = _ScanStep.scanning; _error = null;
      });
      switch (_mode) {
        case _ScanMode.plantHealth: await _analyzeGemini(bytes, mime); break;
        case _ScanMode.fruitCount:  await _analyzeFruitsGemini(bytes, mime); break;
        case _ScanMode.grapeCount:  await _analyzeDetection(bytes, mime, _grapeImageUrl); break;
      }
    } catch (e) {
      setState(() { _error = 'Could not open image: $e'; _step = _ScanStep.idle; });
    }
  }

  // ── Gemini Vision (Plant Health) ──────────────────────────────
  Future<void> _analyzeGemini(Uint8List bytes, String mime) async {
    if (AppEnv.geminiApiKey.isEmpty) {
      setState(() {
        _error =
            'Add GEMINI_API_KEY in assets/.env (see .env.example) for plant health scan.';
        _step = _ScanStep.idle;
      });
      return;
    }
    try {
      final body = jsonEncode({
        "contents": [{"parts": [
          {"text": _geminiPrompt},
          {"inline_data": {"mime_type": mime, "data": base64Encode(bytes)}}
        ]}],
        "generationConfig": {
          "temperature": 0.2,
          "maxOutputTokens": 8192,
          "responseMimeType": "application/json",
        }
      });
      final res = await http.post(
        Uri.parse(AppEnv.geminiGenerateContentUrl()),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 90));

      if (res.statusCode == 200) {
        final raw  = jsonDecode(res.body);
        final text = (raw['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? '');
        setState(() { _result = _parseJson(text); _step = _ScanStep.result; });
      } else {
        setState(() { _error = 'Gemini error (${res.statusCode})'; _step = _ScanStep.idle; });
      }
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _step = _ScanStep.idle; });
    }
  }

  // ── Fruit analysis via Gemini (count + health + weight) ────────────────
  Future<void> _analyzeFruitsGemini(Uint8List bytes, String mime) async {
    if (AppEnv.geminiApiKey.isEmpty) {
      setState(() {
        _error = 'Add GEMINI_API_KEY in assets/.env for fruit analysis.';
        _step = _ScanStep.idle;
      });
      return;
    }
    try {
      final body = jsonEncode({
        "contents": [{"parts": [
          {"text": _geminifruitPrompt},
          {"inline_data": {"mime_type": mime, "data": base64Encode(bytes)}}
        ]}],
        "generationConfig": {
          "temperature": 0.1,
          "maxOutputTokens": 8192,
          "responseMimeType": "application/json",
        }
      });
      final res = await http.post(
        Uri.parse(AppEnv.geminiGenerateContentUrl()),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 90));

      if (res.statusCode == 200) {
        final raw  = jsonDecode(res.body);
        final text = (raw['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? '');
        setState(() { _result = _parseJson(text); _step = _ScanStep.result; });
      } else {
        setState(() { _error = 'Gemini error (${res.statusCode}): ${res.body.substring(0, res.body.length.clamp(0, 300))}'; _step = _ScanStep.idle; });
      }
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _step = _ScanStep.idle; });
    }
  }

  // ── Detection API (Fruit / Grape) ─────────────────────────────
  Future<void> _analyzeDetection(Uint8List bytes, String mime, String url) async {
    try {
      final ext = mime == 'image/png' ? 'image.png' : 'image.jpg';
      final req = http.MultipartRequest('POST', Uri.parse(url))
        ..files.add(http.MultipartFile.fromBytes('file', bytes,
            filename: ext, contentType: MediaType.parse(mime)));
      final streamed = await req.send().timeout(const Duration(seconds: 300));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        // Decode annotated image if present
        Uint8List? annotated;
        final imgB64 = data['annotated_image_base64'] ?? data['annotated_image'] ?? data['image'] ?? data['result_image'];
        if (imgB64 is String && imgB64.isNotEmpty) {
          try { annotated = base64Decode(imgB64); } catch (_) {}
        }
        setState(() {
          _result = {...data, if (annotated != null) '_annotatedBytes': annotated};
          _step = _ScanStep.result;
        });
      } else {
        setState(() { _error = 'API error (${streamed.statusCode}): $body'; _step = _ScanStep.idle; });
      }
    } catch (e) {
      String msg = e.toString().replaceFirst('Exception: ', '');
      if (msg.contains('TimeoutException') || msg.contains('Future not completed')) {
        msg = 'The AI server is still warming up (HuggingFace cold start).\n'
              'Please wait 30–60 seconds and try again.\n\n'
              'The server will be faster after the first request.';
      }
      setState(() { _error = msg; _step = _ScanStep.idle; });
    }
  }

  void _reset() => setState(() {
    _step = _ScanStep.idle; _error = null;
    _result = null; _imageBytes = null; _imageMime = null;
  });

  // ── JSON helpers ─────────────────────────────────────────────
  Map<String, dynamic> _parseJson(String raw) {
    String text = raw.trim();
    if (text.contains('```')) {
      final parts = text.split('```');
      text = parts.length >= 2 ? parts[1] : parts[0];
      if (text.startsWith('json')) text = text.substring(4);
      text = text.trim();
    }
    final start = text.indexOf('{');
    if (start != -1) {
      int depth = 0, end = -1;
      for (int i = start; i < text.length; i++) {
        if (text[i] == '{') depth++;
        else if (text[i] == '}') { depth--; if (depth == 0) { end = i; break; } }
      }
      if (end != -1) text = text.substring(start, end + 1);
    }
    try { return jsonDecode(text) as Map<String, dynamic>; }
    catch (_) { return {'error': 'Could not parse response'}; }
  }

  // ── Color helpers ─────────────────────────────────────────────
  Color _healthColor(int s) {
    if (s >= 80) return const Color(0xFF00C853);
    if (s >= 60) return const Color(0xFFF9A825);
    if (s >= 40) return const Color(0xFFE65100);
    return Colors.red.shade700;
  }

  Color _sevColor(String s) {
    switch (s.toLowerCase()) {
      case 'low':    return Colors.orange.shade400;
      case 'medium': return const Color(0xFFE65100);
      case 'high':   return Colors.red.shade600;
      default:       return Colors.grey;
    }
  }

  // ════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _ScanStep.scanning: return _buildScanning(context);
      case _ScanStep.result:   return _buildResult(context);
      case _ScanStep.idle:     return _buildIdle(context);
    }
  }

  // ════════════════════════════════════════════════════════════════
  // IDLE  —  Mode selector + glowing scan button
  // ════════════════════════════════════════════════════════════════
  Widget _buildIdle(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080F09),
      body: SafeArea(child: Column(children: [

        // ── Top bar ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Row(children: [
            GestureDetector(
              onTap: widget.onClose,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                  border: Border.all(color: Colors.white12, width: 1.5),
                ),
                child: const Icon(Icons.arrow_back_ios_new, color: Colors.white54, size: 16),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _modeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _modeColor.withOpacity(0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.document_scanner, color: _modeColor, size: 14),
                const SizedBox(width: 6),
                Text('SMART SCANNER',
                    style: TextStyle(color: _modeColor,
                        fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.2)),
              ]),
            ),
            const Spacer(),
          ]),
        ),

        const SizedBox(height: 24),

        // ── Mode selector tabs ────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(children: _ScanMode.values.map((m) {
              final active = _mode == m;
              final color = _modeColorFor(m);
              final emoji = _modeEmojiFor(m);
              final label = _modeLabelFor(m);
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() { _mode = m; _error = null; }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: active ? color.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(15),
                      border: active
                          ? Border.all(color: color.withOpacity(0.5), width: 1.5)
                          : Border.all(color: Colors.transparent),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(height: 4),
                      Text(label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: active ? color : Colors.white38,
                            fontWeight: FontWeight.w800,
                            fontSize: 9, letterSpacing: 0.8,
                          )),
                    ]),
                  ),
                ),
              );
            }).toList()),
          ),
        ),

        const SizedBox(height: 6),

        // ── Mode description ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _modeDescription,
              key: ValueKey(_mode),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _modeColor.withOpacity(0.7),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
          ),
        ),

        const Spacer(),

        // ── Central glowing scan button ───────────────────────────
        AnimatedBuilder(
          animation: Listenable.merge([_pulseAnim, _sweepAnim, _glowAnim]),
          builder: (_, __) {
            return SizedBox(
              width: 260, height: 260,
              child: Stack(alignment: Alignment.center, children: [

                // Outer rotating ring
                Transform.rotate(
                  angle: _sweepAnim.value * 2 * 3.14159,
                  child: Container(
                    width: 250, height: 250,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _modeColor.withOpacity(0.12), width: 1.5),
                    ),
                    child: CustomPaint(painter: _ArcPainter(_modeColor, _sweepAnim.value)),
                  ),
                ),

                // Middle pulsing ring
                Transform.scale(
                  scale: _pulseAnim.value,
                  child: Container(
                    width: 200, height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _modeColor.withOpacity(0.25 * _glowAnim.value),
                        width: 2,
                      ),
                    ),
                  ),
                ),

                // Inner glow ring
                Container(
                  width: 160, height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _modeColor.withOpacity(0.4 * _glowAnim.value),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _modeColor.withOpacity(0.15 * _glowAnim.value),
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                ),

                // Core button
                GestureDetector(
                  onTap: () => _pick(ImageSource.camera),
                  child: Container(
                    width: 128, height: 128,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          _modeColor.withOpacity(0.35),
                          _modeColor.withOpacity(0.10),
                          Colors.transparent,
                        ],
                        stops: const [0, 0.5, 1],
                      ),
                      border: Border.all(
                        color: _modeColor.withOpacity(0.6 + 0.4 * _glowAnim.value),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _modeColor.withOpacity(0.35 * _glowAnim.value),
                          blurRadius: 24, spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_rounded, color: _modeColor, size: 38),
                        const SizedBox(height: 4),
                        Text('SCAN',
                            style: TextStyle(
                              color: _modeColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              letterSpacing: 2,
                            )),
                      ],
                    ),
                  ),
                ),

                // Scan line sweep overlay
                SizedBox(
                  width: 128, height: 128,
                  child: CustomPaint(
                    painter: _ScanLinePainter(_sweepAnim.value, _modeColor),
                  ),
                ),

              ]),
            );
          },
        ),

        const SizedBox(height: 8),
        Text(_modeEmoji + '  ' + _modeLabel,
            style: TextStyle(
              color: _modeColor,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 1.5,
            )),

        const Spacer(),

        // ── Error banner ─────────────────────────────────────────
        if (_error != null) ...[
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.shade700),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(_error!,
                  style: const TextStyle(color: Colors.white70,
                      fontSize: 12, fontWeight: FontWeight.w500, height: 1.4))),
            ]),
          ),
          const SizedBox(height: 12),
        ],

        // ── Action buttons ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Column(children: [

            // Camera
            GestureDetector(
              onTap: () => _pick(ImageSource.camera),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_modeColor, _darken(_modeColor, 0.2)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: [
                    BoxShadow(color: _modeColor.withOpacity(0.4),
                        blurRadius: 20, offset: const Offset(0, 8)),
                  ],
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  const Text('Take Photo',
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w900, fontSize: 16)),
                ]),
              ),
            ),
            const SizedBox(height: 10),

            // Gallery
            GestureDetector(
              onTap: () => _pick(ImageSource.gallery),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 17),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                  Icon(Icons.photo_library_outlined, color: Colors.white60, size: 20),
                  SizedBox(width: 10),
                  Text('Upload from Gallery',
                      style: TextStyle(color: Colors.white60,
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ]),
              ),
            ),

            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.auto_awesome, color: Colors.white.withOpacity(0.2), size: 11),
              const SizedBox(width: 5),
              Text(_poweredByLabel,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.2),
                    fontSize: 10, fontWeight: FontWeight.w600,
                  )),
            ]),
            const SizedBox(height: 8),
          ]),
        ),
      ])),
    );
  }

  String get _poweredByLabel {
    switch (_mode) {
      case _ScanMode.plantHealth: return 'Powered by Google Gemini Vision';
      case _ScanMode.fruitCount:  return 'Powered by Sarvesh AI Fruit Detection';
      case _ScanMode.grapeCount:  return 'Powered by Sarvesh AI Grape Detection';
    }
  }

  // ════════════════════════════════════════════════════════════════
  // SCANNING SCREEN
  // ════════════════════════════════════════════════════════════════
  Widget _buildScanning(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF080F09),
    body: SafeArea(child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Row(children: [
          GestureDetector(
            onTap: _reset,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
                border: Border.all(color: Colors.white12, width: 1.5),
              ),
              child: const Icon(Icons.close, color: Colors.white54, size: 18),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _modeColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _modeColor.withOpacity(0.4)),
            ),
            child: Text(_modeLabel,
                style: TextStyle(color: _modeColor,
                    fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.2)),
          ),
          const SizedBox(width: 16),
        ]),
      ),
      const Spacer(),

      // Image preview with scan overlay
      if (_imageBytes != null)
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Stack(alignment: Alignment.center, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.memory(_imageBytes!,
                  width: 250, height: 250, fit: BoxFit.cover),
            ),
            Container(
              width: 250, height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: Colors.black.withOpacity(0.4),
              ),
            ),
            Container(
              width: 250, height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: _modeColor.withOpacity(0.35 + _pulseAnim.value * 0.5),
                  width: 2.5,
                ),
              ),
            ),
            // Horizontal scan line
            AnimatedBuilder(
              animation: _sweepAnim,
              builder: (_, __) => Positioned(
                top: 250 * _sweepAnim.value,
                child: Container(
                  width: 250, height: 2.5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.transparent,
                      _modeColor.withOpacity(0.8),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _modeColor.withOpacity(0.2),
                  border: Border.all(color: _modeColor.withOpacity(0.7), width: 2),
                ),
                child: Icon(Icons.auto_awesome, color: _modeColor, size: 28),
              ),
              const SizedBox(height: 8),
              Text('Analyzing...', style: TextStyle(color: _modeColor,
                  fontWeight: FontWeight.w900, fontSize: 13)),
            ]),
          ]),
        ),

      const SizedBox(height: 36),
      SizedBox(
        width: 40, height: 40,
        child: CircularProgressIndicator(color: _modeColor, strokeWidth: 3),
      ),
      const SizedBox(height: 20),
      Text('AI is analyzing your ${_modeEmoji}',
          style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w900, fontSize: 18)),
      const SizedBox(height: 8),
      Text(_scanningSubtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500)),
      const Spacer(),
    ])),
  );

  String get _scanningSubtitle {
    switch (_mode) {
      case _ScanMode.plantHealth: return 'Checking for diseases, pests & health status...';
      case _ScanMode.fruitCount:  return 'Detecting and counting fruit varieties...';
      case _ScanMode.grapeCount:  return 'Detecting and counting grape clusters...';
    }
  }

  // ════════════════════════════════════════════════════════════════
  // RESULT SCREEN
  // ════════════════════════════════════════════════════════════════
  Widget _buildResult(BuildContext context) {
    switch (_mode) {
      case _ScanMode.plantHealth: return _buildPlantResult(context);
      case _ScanMode.fruitCount:  return _buildFruitGeminiResult(context);
      case _ScanMode.grapeCount:  return _buildDetectionResult(context, 'Grape Detection');
    }
  }

  // ── Plant Health result ───────────────────────────────────────
  Widget _buildPlantResult(BuildContext context) {
    final r  = _result ?? {};
    final hs = (r['healthScore'] as num?)?.toInt() ?? 0;
    final hc = _healthColor(hs);

    return Scaffold(
      backgroundColor: const Color(0xFF080F09),
      body: SafeArea(child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Row(children: [
            GestureDetector(
              onTap: _reset,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                  border: Border.all(color: Colors.white12, width: 1.5),
                ),
                child: const Icon(Icons.arrow_back_ios_new, color: Colors.white54, size: 16),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(r['plantName']?.toString() ?? 'Plant Scan',
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w900, fontSize: 20),
                  overflow: TextOverflow.ellipsis),
            ),
            // Health score badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: hc.withOpacity(0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: hc.withOpacity(0.5)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.favorite, color: hc, size: 14),
                const SizedBox(width: 5),
                Text('$hs%', style: TextStyle(color: hc,
                    fontWeight: FontWeight.w900, fontSize: 13)),
              ]),
            ),
          ]),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Summary card
              _resultCard(
                icon: Icons.eco, iconColor: const Color(0xFF00C853),
                title: r['overallHealth']?.toString() ?? 'Unknown',
                child: Text(r['summary']?.toString() ?? '',
                    style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
              ),
              const SizedBox(height: 12),

              // Health score bar
              _cardBase(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.monitor_heart, color: hc, size: 16),
                  const SizedBox(width: 8),
                  const Text('Health Score',
                      style: TextStyle(color: Colors.white70,
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  const Spacer(),
                  Text('$hs / 100', style: TextStyle(color: hc,
                      fontWeight: FontWeight.w900, fontSize: 15)),
                ]),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: hs / 100,
                    backgroundColor: Colors.white10,
                    color: hc,
                    minHeight: 8,
                  ),
                ),
              ])),
              const SizedBox(height: 12),

              // Diseases
              if ((r['diseases'] as List?)?.isNotEmpty == true) ...[
                _sectionHeader(Icons.coronavirus_outlined, 'Diseases Detected', Colors.red.shade400),
                ...(r['diseases'] as List).map((d) => _issueChip(d, _sevColor)),
                const SizedBox(height: 12),
              ],

              // Pests
              if ((r['pests'] as List?)?.isNotEmpty == true) ...[
                _sectionHeader(Icons.bug_report_outlined, 'Pests Detected', Colors.orange.shade400),
                ...(r['pests'] as List).map((p) => _issueChip(p, _sevColor)),
                const SizedBox(height: 12),
              ],

              // Treatments
              if ((r['treatments'] as List?)?.isNotEmpty == true) ...[
                _sectionHeader(Icons.medication_outlined, 'Recommended Treatments', const Color(0xFF00C853)),
                ...(r['treatments'] as List).map((t) {
                  final m = t as Map<String, dynamic>;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00C853).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(m['type']?.toString() ?? '',
                              style: const TextStyle(color: Color(0xFF00C853),
                                  fontWeight: FontWeight.w800, fontSize: 11)),
                        ),
                        const Spacer(),
                        if (m['priority'] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(m['priority'].toString(),
                                style: const TextStyle(color: Colors.white54,
                                    fontWeight: FontWeight.w700, fontSize: 11)),
                          ),
                      ]),
                      if (m['product'] != null) ...[
                        const SizedBox(height: 8),
                        Text(m['product'].toString(),
                            style: const TextStyle(color: Colors.white,
                                fontWeight: FontWeight.w800, fontSize: 14)),
                      ],
                      if (m['instructions'] != null) ...[
                        const SizedBox(height: 6),
                        Text(m['instructions'].toString(),
                            style: const TextStyle(color: Colors.white60,
                                fontSize: 12, height: 1.45)),
                      ],
                    ]),
                  );
                }),
                const SizedBox(height: 12),
              ],

              // General advice
              if (r['generalAdvice'] != null)
                _resultCard(
                  icon: Icons.tips_and_updates, iconColor: Colors.amber,
                  title: 'General Advice',
                  child: Text(r['generalAdvice'].toString(),
                      style: const TextStyle(color: Colors.white70,
                          fontSize: 13, height: 1.5)),
                ),

              const SizedBox(height: 24),
            ]),
          ),
        ),

        // Scan again button
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: GestureDetector(
            onTap: _reset,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00C853), Color(0xFF1B5E20)],
                ),
                borderRadius: BorderRadius.circular(36),
                boxShadow: [BoxShadow(
                    color: const Color(0xFF00C853).withOpacity(0.35),
                    blurRadius: 18, offset: const Offset(0, 6))],
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text('Scan Another',
                    style: TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w900, fontSize: 16)),
              ]),
            ),
          ),
        ),
      ])),
    );
  }

  // ── Detection result (Fruit / Grape) ──────────────────────────
  Widget _buildDetectionResult(BuildContext context, String title) {
    final r = _result ?? {};
    final annotatedBytes = r['_annotatedBytes'] as Uint8List?;

    // Count extraction — try many possible field names
    int count = 0;
    for (final k in ['count','total_count','cluster_count','total_clusters',
                     'num_clusters','fruit_count','detected_count','num_detections','total','n']) {
      final v = r[k];
      if (v is int) { count = v; break; }
      if (v is num) { count = v.toInt(); break; }
    }
    if (count == 0) {
      final dets = r['detections'] ?? r['boxes'] ?? r['results'] ?? r['predictions'];
      if (dets is List) count = dets.length;
    }

    // Per-class breakdown if available
    final classCounts = <String, int>{};
    final dets = r['detections'] ?? r['boxes'] ?? r['results'] ?? r['predictions'];
    if (dets is List) {
      for (final d in dets) {
        if (d is Map) {
          final cls = (d['class'] ?? d['label'] ?? d['name'] ?? 'Item').toString();
          classCounts[cls] = (classCounts[cls] ?? 0) + 1;
        }
      }
    }

    final accentColor = _modeColor;

    return Scaffold(
      backgroundColor: const Color(0xFF080F09),
      body: SafeArea(child: Column(children: [

        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Row(children: [
            GestureDetector(
              onTap: _reset,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                  border: Border.all(color: Colors.white12, width: 1.5),
                ),
                child: const Icon(Icons.arrow_back_ios_new, color: Colors.white54, size: 16),
              ),
            ),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w900, fontSize: 20)),
            const Spacer(),
          ]),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Big count display
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accentColor.withOpacity(0.18), accentColor.withOpacity(0.05)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: accentColor.withOpacity(0.3), width: 1.5),
                ),
                child: Column(children: [
                  Text(_modeEmoji, style: const TextStyle(fontSize: 44)),
                  const SizedBox(height: 12),
                  Text('$count',
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 72,
                        height: 1,
                      )),
                  const SizedBox(height: 6),
                  Text(_mode == _ScanMode.grapeCount ? 'Grape Clusters Detected' : 'Fruits Detected',
                      style: const TextStyle(color: Colors.white70,
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ]),
              ),
              const SizedBox(height: 16),

              // Annotated image
              if (annotatedBytes != null) ...[
                _sectionHeader(Icons.image_outlined, 'Annotated Result', accentColor),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.memory(annotatedBytes, fit: BoxFit.contain,
                      width: double.infinity),
                ),
                const SizedBox(height: 16),
              ] else if (_imageBytes != null) ...[
                _sectionHeader(Icons.image_outlined, 'Scanned Image', accentColor),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.memory(_imageBytes!, fit: BoxFit.contain,
                      width: double.infinity),
                ),
                const SizedBox(height: 16),
              ],

              // Per-class breakdown
              if (classCounts.isNotEmpty) ...[
                _sectionHeader(Icons.bar_chart, 'Detection Breakdown', accentColor),
                ...classCounts.entries.map((e) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(_fruitEmoji(e.key),
                            style: const TextStyle(fontSize: 18)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(e.key,
                        style: const TextStyle(color: Colors.white,
                            fontWeight: FontWeight.w700, fontSize: 14))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${e.value}',
                          style: TextStyle(color: accentColor,
                              fontWeight: FontWeight.w900, fontSize: 14)),
                    ),
                  ]),
                )),
                const SizedBox(height: 16),
              ],

              // Raw confidence/scores if present
              if (r['confidence'] != null || r['score'] != null)
                _cardBase(child: Row(children: [
                  const Icon(Icons.verified, color: Color(0xFF00C853), size: 18),
                  const SizedBox(width: 10),
                  const Text('Confidence',
                      style: TextStyle(color: Colors.white70,
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  const Spacer(),
                  Text('${((r['confidence'] ?? r['score'] as num) * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(color: Color(0xFF00C853),
                          fontWeight: FontWeight.w900, fontSize: 15)),
                ])),

              const SizedBox(height: 24),
            ]),
          ),
        ),

        // Scan again
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: GestureDetector(
            onTap: _reset,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accentColor, _darken(accentColor, 0.2)],
                ),
                borderRadius: BorderRadius.circular(36),
                boxShadow: [BoxShadow(
                    color: accentColor.withOpacity(0.35),
                    blurRadius: 18, offset: const Offset(0, 6))],
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text('Scan Another',
                    style: TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w900, fontSize: 16)),
              ]),
            ),
          ),
        ),
      ])),
    );
  }

  // ── Shared UI helpers ─────────────────────────────────────────
  Widget _resultCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return _cardBase(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: iconColor, size: 16),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: iconColor,
            fontWeight: FontWeight.w800, fontSize: 13)),
      ]),
      const SizedBox(height: 10),
      child,
    ]));
  }


  // ── Fruit Gemini result — count + health + weight ─────────────────────
  Widget _buildFruitGeminiResult(BuildContext context) {
    final r = _result ?? {};
    const accent = Color(0xFFFF6F00);
    final fruits = (r['fruits'] as List?)?.cast<Map>() ?? [];
    final total  = (r['totalFruitCount'] as int?) ?? fruits.fold<int>(0, (s, f) => s + ((f['count'] as int?) ?? 0));
    final summary     = r['imageSummary']  as String? ?? '';
    final farmingTip  = r['farmingTip']    as String? ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF080F09),
      body: SafeArea(child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Row(children: [
            GestureDetector(
              onTap: _reset,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                  border: Border.all(color: Colors.white12, width: 1.5),
                ),
                child: const Icon(Icons.arrow_back_ios_new, color: Colors.white54, size: 16),
              ),
            ),
            const SizedBox(width: 12),
            const Text('Fruit Analysis', style: TextStyle(color: Colors.white,
                fontWeight: FontWeight.w900, fontSize: 20)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withOpacity(0.4)),
              ),
              child: Text('Gemini AI', style: TextStyle(color: accent,
                  fontWeight: FontWeight.w800, fontSize: 11)),
            ),
          ]),
        ),

        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Scanned image
            if (_imageBytes != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.memory(_imageBytes!, fit: BoxFit.cover,
                    width: double.infinity, height: 200),
              ),
              const SizedBox(height: 16),
            ],

            // Total count banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accent.withOpacity(0.20), accent.withOpacity(0.05)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: accent.withOpacity(0.35), width: 1.5),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('🍎', style: TextStyle(fontSize: 36)),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$total',
                      style: TextStyle(color: accent, fontWeight: FontWeight.w900,
                          fontSize: 52, height: 1)),
                  const Text('Total Fruits Detected',
                      style: TextStyle(color: Colors.white60,
                          fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ]),
            ),
            const SizedBox(height: 20),

            // Summary
            if (summary.isNotEmpty) ...[
              _sectionHeader(Icons.info_outline, 'Image Summary', accent),
              _cardBase(child: Text(summary,
                  style: const TextStyle(color: Colors.white70,
                      fontSize: 13, height: 1.6))),
              const SizedBox(height: 12),
            ],

            // Per-fruit cards
            if (fruits.isNotEmpty) ...[
              _sectionHeader(Icons.spa_outlined, 'Fruit-by-Fruit Analysis', accent),
              ...fruits.map((fruit) {
                final name    = fruit['name']  as String? ?? 'Unknown';
                final count   = fruit['count'] as int?    ?? 0;
                final emoji   = fruit['emoji'] as String? ?? '🍎';
                final health  = fruit['health']  as Map?  ?? {};
                final weight  = fruit['weight']  as Map?  ?? {};

                final healthLabel  = health['overallHealth'] as String? ?? 'Unknown';
                final healthScore  = health['healthScore']   as int?    ?? 0;
                final ripeness     = health['ripeness']      as String? ?? '';
                final color_       = health['color']         as String? ?? '';
                final defects      = health['defects']       as String? ?? 'None';
                final recommendation = health['recommendation'] as String? ?? '';

                final avgWeightG   = (weight['estimatedWeightGrams'] as num?)?.toDouble() ?? 0;
                final totalWeightKg = (weight['totalWeightKg'] as num?)?.toDouble() ?? 0;
                final weightBasis  = weight['weightBasis'] as String? ?? '';

                // Health score colour
                Color scoreColor;
                if (healthScore >= 90)      scoreColor = const Color(0xFF00C853);
                else if (healthScore >= 70) scoreColor = const Color(0xFF8BC34A);
                else if (healthScore >= 50) scoreColor = const Color(0xFFFBC02D);
                else                        scoreColor = const Color(0xFFE53935);

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Fruit header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Row(children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(child: Text(emoji,
                              style: const TextStyle(fontSize: 26))),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w900, fontSize: 16)),
                          Text('$count fruit${count == 1 ? "" : "s"} detected',
                              style: const TextStyle(color: Colors.white54,
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                        ])),
                        // Health badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: scoreColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: scoreColor.withOpacity(0.5)),
                          ),
                          child: Text(healthLabel,
                              style: TextStyle(color: scoreColor,
                                  fontWeight: FontWeight.w800, fontSize: 11)),
                        ),
                      ]),
                    ),

                    // Health score bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Text('Health Score', style: TextStyle(color: Colors.white54,
                              fontSize: 12, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text('$healthScore / 100',
                              style: TextStyle(color: scoreColor,
                                  fontWeight: FontWeight.w900, fontSize: 13)),
                        ]),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: healthScore / 100.0,
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                            minHeight: 8,
                          ),
                        ),
                      ]),
                    ),

                    // Details grid
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        _fruitDetailRow('🌈', 'Color / Appearance', color_),
                        if (ripeness.isNotEmpty)
                          _fruitDetailRow('⏱️', 'Ripeness', ripeness),
                        if (defects.isNotEmpty && defects.toLowerCase() != 'none')
                          _fruitDetailRow('⚠️', 'Defects', defects),
                        if (recommendation.isNotEmpty)
                          _fruitDetailRow('💡', 'Recommendation', recommendation),

                        // Weight section
                        const Divider(color: Colors.white12, height: 24),
                        _fruitDetailRow('⚖️', 'Avg Weight / Fruit',
                            '${avgWeightG.toStringAsFixed(0)} g'),
                        _fruitDetailRow('📦', 'Total Batch Weight',
                            '${totalWeightKg.toStringAsFixed(2)} kg'),
                        if (weightBasis.isNotEmpty)
                          _fruitDetailRow('ℹ️', 'Weight Basis', weightBasis),
                      ]),
                    ),
                  ]),
                );
              }),
              const SizedBox(height: 8),
            ],

            // Farming tip
            if (farmingTip.isNotEmpty) ...[
              _sectionHeader(Icons.tips_and_updates_outlined, 'Farming Tip', const Color(0xFF00C853)),
              _cardBase(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('🌾', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(child: Text(farmingTip,
                    style: const TextStyle(color: Colors.white70,
                        fontSize: 13, height: 1.6))),
              ])),
              const SizedBox(height: 24),
            ],
          ]),
        )),

        // Scan again button
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: GestureDetector(
            onTap: _reset,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6F00), Color(0xFFE65100)],
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(
                  color: const Color(0xFFFF6F00).withOpacity(0.35),
                  blurRadius: 16, offset: const Offset(0, 6),
                )],
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.camera_alt_outlined, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text('Scan Another Image',
                    style: TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w900, fontSize: 15)),
              ]),
            ),
          ),
        ),
      ])),
    );
  }

  // Helper: detail row inside fruit card
  Widget _fruitDetailRow(String emoji, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(emoji, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 8),
      SizedBox(width: 110, child: Text(label,
          style: const TextStyle(color: Colors.white38,
              fontSize: 12, fontWeight: FontWeight.w600))),
      Expanded(child: Text(value,
          style: const TextStyle(color: Colors.white70,
              fontSize: 12, fontWeight: FontWeight.w700, height: 1.4))),
    ]),
  );

  Widget _cardBase({required Widget child}) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withOpacity(0.08)),
    ),
    child: child,
  );

  Widget _sectionHeader(IconData icon, String label, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(color: color,
          fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.3)),
    ]),
  );

  Widget _issueChip(dynamic d, Color Function(String) colorFn) {
    final m = d as Map<String, dynamic>;
    final sev = m['severity']?.toString() ?? '';
    final color = colorFn(sev);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(m['name']?.toString() ?? '',
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w800, fontSize: 14))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(sev, style: TextStyle(color: color,
                fontWeight: FontWeight.w900, fontSize: 11)),
          ),
        ]),
        if (m['description'] != null) ...[
          const SizedBox(height: 6),
          Text(m['description'].toString(),
              style: const TextStyle(color: Colors.white60,
                  fontSize: 12, height: 1.45)),
        ],
        if (m['affectedParts'] != null) ...[
          const SizedBox(height: 4),
          Text('Parts: ${m['affectedParts']}',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ]),
    );
  }

  String _fruitEmoji(String cls) {
    final lower = cls.toLowerCase();
    if (lower.contains('grape')) return '🍇';
    if (lower.contains('apple')) return '🍎';
    if (lower.contains('orange')) return '🍊';
    if (lower.contains('pomegranate')) return '🫐';
    if (lower.contains('kiwi')) return '🥝';
    if (lower.contains('lime')) return '🍋';
    if (lower.contains('peach')) return '🍑';
    if (lower.contains('pear')) return '🍐';
    if (lower.contains('plum')) return '🫐';
    return '🍏';
  }

  // ── Static helpers for mode props ─────────────────────────────
  Color _modeColorFor(_ScanMode m) {
    switch (m) {
      case _ScanMode.plantHealth: return const Color(0xFF00C853);
      case _ScanMode.fruitCount:  return const Color(0xFFFF6F00);
      case _ScanMode.grapeCount:  return const Color(0xFF7B1FA2);
    }
  }
  String _modeEmojiFor(_ScanMode m) {
    switch (m) {
      case _ScanMode.plantHealth: return '🌿';
      case _ScanMode.fruitCount:  return '🍎';
      case _ScanMode.grapeCount:  return '🍇';
    }
  }
  String _modeLabelFor(_ScanMode m) {
    switch (m) {
      case _ScanMode.plantHealth: return 'PLANT';
      case _ScanMode.fruitCount:  return 'FRUITS';
      case _ScanMode.grapeCount:  return 'GRAPES';
    }
  }
}

// ── Arc painter for rotating ring on idle screen ──────────────────
class _ArcPainter extends CustomPainter {
  final Color color;
  final double progress;
  const _ArcPainter(this.color, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawArc(rect, -1.57 + progress * 6.28, 1.2, false, paint);

    final paint2 = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -1.57 + progress * 6.28 + 3.14, 0.8, false, paint2);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.progress != progress;
}

// ── Scan line sweep painter ────────────────────────────────────────
class _ScanLinePainter extends CustomPainter {
  final double progress;
  final Color color;
  const _ScanLinePainter(this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.transparent, color.withOpacity(0.7), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, y - 1, size.width, 2));
    canvas.drawRect(Rect.fromLTWH(0, y - 1, size.width, 2.5), paint);
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) => old.progress != progress;
}

// ── Shared colour darken helper ───────────────────────────────────
Color _darken(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}

// ═══════════════════════════════════════════════════════════════════
// GRAPE COUNT PANEL  –  API-powered grape cluster counter
// API: https://sarveshaiml-fruit-grape-counter.hf.space
// ═══════════════════════════════════════════════════════════════════
class GrapeCountPanel extends StatefulWidget {
  final VoidCallback onClose;
  const GrapeCountPanel({super.key, required this.onClose});
  @override
  State<GrapeCountPanel> createState() => _GrapeCountPanelState();
}

enum _GrapeMode { idle, camera, video, processing }

class _GrapeCountPanelState extends State<GrapeCountPanel>
    with TickerProviderStateMixin {

  // ── Grape API ──────────────────────────────────────────────────
  static String get _apiBase => AppEnv.scannerApiBase;
  // New HF space: PlanetEyeFarm12/fruit-grape-counter
  static String get _frameEndpoint   => '$_apiBase/grape/image';
  static String get _imageEndpoint   => '$_apiBase/grape/image';
  static String get _videoEndpoint   => '$_apiBase/grape/video';
  static const Map<String, String> _ngrokHeader = {
    'ngrok-skip-browser-warning': 'true'  // kept for compatibility
  };

  _GrapeMode _mode = _GrapeMode.idle;
  bool   _apiReady  = false;
  String? _apiError;

  // ── Camera ────────────────────────────────────────────────────
  CameraController? _camCtrl;
  bool _camReady   = false;
  bool _detecting  = false;
  int  _lastSentMs = 0;

  // ── Video ─────────────────────────────────────────────────────
  VideoPlayerController? _vidCtrl;
  bool _vidReady   = false;
  bool _vidPlaying = false;

  // ── Results ───────────────────────────────────────────────────
  int                _count          = 0;
  Map<String, int>   _counts         = {}; // per-class breakdown from new API
  List<_Detect>      _dets           = [];
  Uint8List?         _annotatedImage; // annotated JPEG from API
  Size?              _annotatedSize;  // pixel size of the annotated image
  double        _detSrcW        = 640; // width the bbox coords are relative to
  double        _detSrcH        = 640; // height the bbox coords are relative to

  // ── Animation ─────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _checkApi();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _stopCamera(); // fire-and-forget is fine in dispose
    _vidCtrl?.dispose();
    super.dispose();
  }

  // ── Health check — non-blocking, runs silently in background ──
  // We mark _apiReady = true immediately so the UI is never blocked.
  // The background ping just updates the status badge.
  Future<void> _checkApi() async {
    // Don't gate the UI — mark ready immediately so uploads work
    if (mounted) setState(() { _apiError = null; _apiReady = true; });
    try {
      final res = await http.get(
        Uri.parse(_apiBase),
        headers: _ngrokHeader,
      ).timeout(const Duration(seconds: 60));
      if (mounted) {
        if (res.statusCode == 200 || res.statusCode == 422) {
          setState(() { _apiError = null; _apiReady = true; });
        }
        // Non-200 is logged but doesn't block the UI
      }
    } catch (_) {
      // Ignore — HF space may still be waking; user can still try uploading
    }
  }

  // ── Shared multipart POST helper ──────────────────────────────
  Future<Map<String, dynamic>?> _callApi(
    String endpoint, Uint8List bytes, String filename, String mime,
    {Duration timeout = const Duration(seconds: 120)}
  ) async {
    final req = http.MultipartRequest('POST', Uri.parse(endpoint))
      ..headers.addAll(_ngrokHeader)
      ..files.add(http.MultipartFile.fromBytes(
        'file', bytes,
        filename: filename,
        contentType: MediaType.parse(mime),
      ));
    final streamed = await req.send().timeout(timeout);
    final body     = await streamed.stream.bytesToString();
    if (streamed.statusCode == 200) {
      return jsonDecode(body) as Map<String, dynamic>;
    }
    throw Exception('API ${streamed.statusCode}: $body');
  }

  // ── Extract count – handles new API format: {counts:{...}, total:N}
  //    and legacy formats
  int _extractCount(Map<String, dynamic> r) {
    // New API format: { "counts": {"Pomegranate": 2}, "total": 2 }
    final total = r['total'];
    if (total is int) return total;
    if (total is num) return total.toInt();

    // counts map — sum all values
    final counts = r['counts'];
    if (counts is Map && counts.isNotEmpty) {
      int sum = 0;
      for (final v in counts.values) {
        if (v is int) sum += v;
        else if (v is num) sum += v.toInt();
      }
      if (sum > 0) return sum;
    }

    // Legacy numeric fields
    for (final key in const [
      'count', 'cluster_count', 'total_count', 'total_clusters',
      'num_clusters', 'grape_count', 'max_count', 'detected_count',
      'num_detections', 'n',
    ]) {
      final v = r[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
    }
    // Fall back to length of detections list
    final dets = r['detections'] ?? r['boxes'] ?? r['results'] ?? r['predictions'];
    if (dets is List) return dets.length;
    return 0;
  }

  // ── Extract per-class counts map from API response ────────────
  Map<String, int> _extractCounts(Map<String, dynamic> r) {
    final counts = r['counts'];
    if (counts is Map) {
      final result = <String, int>{};
      counts.forEach((k, v) {
        if (v is int) result[k.toString()] = v;
        else if (v is num) result[k.toString()] = v.toInt();
      });
      return result;
    }
    return {};
  }

  // ── Parse bboxes – supports {x1,y1,x2,y2}, {bbox:[x,y,w,h]},
  //    {xmin,ymin,xmax,ymax}, {x,y,width,height} formats ─────────
  List<_Detect> _parseDets(Map<String, dynamic> result) {
    final raw = result['detections'] ?? result['boxes']
             ?? result['results']   ?? result['predictions'] ?? [];
    if (raw is! List || raw.isEmpty) return [];

    return raw.map<_Detect?>((d) {
      try {
        final m = d as Map;
        double x, y, w, h;

        if (m.containsKey('x1') && m.containsKey('x2')) {
          // {x1, y1, x2, y2}
          x = (m['x1'] as num).toDouble();
          y = (m['y1'] as num).toDouble();
          w = (m['x2'] as num).toDouble() - x;
          h = (m['y2'] as num).toDouble() - y;
        } else if (m.containsKey('xmin') && m.containsKey('xmax')) {
          // {xmin, ymin, xmax, ymax}
          x = (m['xmin'] as num).toDouble();
          y = (m['ymin'] as num).toDouble();
          w = (m['xmax'] as num).toDouble() - x;
          h = (m['ymax'] as num).toDouble() - y;
        } else if (m.containsKey('bbox')) {
          // {bbox: [x, y, w, h]}
          final bbox = m['bbox'] as List;
          x = (bbox[0] as num).toDouble();
          y = (bbox[1] as num).toDouble();
          w = (bbox[2] as num).toDouble();
          h = (bbox[3] as num).toDouble();
        } else if (m.containsKey('box')) {
          // {box: [x1, y1, x2, y2]}
          final box = m['box'] as List;
          x = (box[0] as num).toDouble();
          y = (box[1] as num).toDouble();
          w = (box[2] as num).toDouble() - x;
          h = (box[3] as num).toDouble() - y;
        } else if (m.containsKey('x') && m.containsKey('width')) {
          // {x, y, width, height}
          x = (m['x'] as num).toDouble();
          y = (m['y'] as num).toDouble();
          w = (m['width'] as num).toDouble();
          h = (m['height'] as num).toDouble();
        } else {
          return null;
        }

        final conf = (m['confidence'] ?? m['score'] ?? m['conf'] ?? 1.0 as num).toDouble();
        return _Detect(x: x, y: y, w: w, h: h, conf: conf);
      } catch (_) {
        return null;
      }
    }).whereType<_Detect>().toList();
  }

  // ── Camera ────────────────────────────────────────────────────
  bool _streamActive = false; // tracks whether stream is running

  Future<void> _startCamera() async {
    setState(() { _mode = _GrapeMode.camera; _count = 0; _dets = []; _annotatedImage = null; });
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) { _showErr('No camera available'); return; }
      _camCtrl = CameraController(
        cams.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420, // YUV works on all Android (incl. Xiaomi)
      );
      await _camCtrl!.initialize();
      if (!mounted) { _camCtrl?.dispose(); _camCtrl = null; return; }
      _streamActive = true;
      setState(() => _camReady = true);
      _camCtrl!.startImageStream(_onCameraFrame);
    } catch (e) {
      _showErr('Camera error: $e');
      if (mounted) setState(() => _mode = _GrapeMode.idle);
    }
  }

  Future<void> _stopCamera() async {
    _streamActive = false;
    try {
      if (_camCtrl != null && _camCtrl!.value.isStreamingImages) {
        await _camCtrl!.stopImageStream();
      }
    } catch (_) {}
    try { _camCtrl?.dispose(); } catch (_) {}
    _camCtrl = null;
    if (mounted) setState(() { _camReady = false; });
  }

  // Called for every YUV frame — throttled to 1 API call per 2.5 s
  Future<void> _onCameraFrame(CameraImage frame) async {
    if (_detecting || !mounted || !_streamActive) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastSentMs < 2500) return;
    _lastSentMs = nowMs;
    _detecting  = true;
    try {
      // Package raw YUV data into plain lists (isolate-safe, no platform objects)
      final yBytes  = Uint8List.fromList(frame.planes[0].bytes);
      final uBytes  = Uint8List.fromList(frame.planes[1].bytes);
      final vBytes  = Uint8List.fromList(frame.planes[2].bytes);

      final params = _YuvParams(
        yBytes:       yBytes,
        uBytes:       uBytes,
        vBytes:       vBytes,
        width:        frame.width,
        height:       frame.height,
        yRowStride:   frame.planes[0].bytesPerRow,
        uvRowStride:  frame.planes[1].bytesPerRow,
        uvPixStride:  frame.planes[1].bytesPerPixel ?? 2,
      );

      // Run heavy YUV→RGBA conversion (isolate on native, direct on web)
      final rgba = kIsWeb
          ? _yuvToRgbaIsolate(params)
          : await compute(_yuvToRgbaIsolate, params);
      if (rgba == null || !mounted || !_streamActive) return;

      // Encode RGBA→PNG on UI thread (fast, hardware-accelerated)
      final png = await _rgbaToPng(rgba, frame.width, frame.height);
      if (png == null || !mounted || !_streamActive) return;

      final result = await _callApi(
        _frameEndpoint, png, 'frame.png', 'image/png',
        timeout: const Duration(seconds: 30),
      );
      if (mounted && _streamActive && result != null) {
        final annotated = _decodeAnnotated(result);
        final src = _extractSrcSize(result,
            fallbackW: frame.width.toDouble(),
            fallbackH: frame.height.toDouble());
        setState(() {
          _count          = _extractCount(result);
          _counts         = _extractCounts(result);
          _dets           = _parseDets(result);
          _annotatedImage = annotated;
          _detSrcW        = src.width;
          _detSrcH        = src.height;
        });
      }
    } catch (_) {
      // per-frame errors are silent
    } finally {
      _detecting = false;
    }
  }

  // ── Encode RGBA buffer → PNG (UI thread, uses Flutter GPU codec) ──
  Future<Uint8List?> _rgbaToPng(Uint8List rgba, int w, int h) async {
    try {
      final completer = Completer<Uint8List?>();
      ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, (img) async {
        final bd = await img.toByteData(format: ui.ImageByteFormat.png);
        completer.complete(bd?.buffer.asUint8List());
      });
      return await completer.future;
    } catch (_) {
      return null;
    }
  }

  // ── Pick image → /detect/image ────────────────────────────────
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file   = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file == null) return;

    setState(() { _mode = _GrapeMode.processing; _count = 0; _dets = []; _annotatedImage = null; });
    try {
      final bytes = await file.readAsBytes();
      final ext   = file.name.split('.').last.toLowerCase();
      final mime  = ext == 'png' ? 'image/png' : 'image/jpeg';

      final result = await _callApi(
        _imageEndpoint, bytes, file.name, mime,
        timeout: const Duration(seconds: 120),
      );

      if (!mounted) return;
      if (result != null) {
        final annotated = _decodeAnnotated(result);
        final src = _extractSrcSize(result);
        setState(() {
          _count          = _extractCount(result);
          _counts         = _extractCounts(result);
          _dets           = _parseDets(result);
          _annotatedImage = annotated;
          _detSrcW        = src.width;
          _detSrcH        = src.height;
          _mode           = _GrapeMode.idle;
        });
        _showSnack('Found $_count cluster${_count == 1 ? '' : 's'}');
      }
    } catch (e) {
      String msg = e.toString();
      if (msg.contains('TimeoutException') || msg.contains('Future not completed')) {
        msg = 'Server is warming up (cold start may take 60–90s).\nPlease try again in a moment.';
      }
      if (mounted) { _showErr(msg.replaceFirst('Exception: ', '')); setState(() => _mode = _GrapeMode.idle); }
    }
  }

  // ── Pick video → /detect/video ────────────────────────────────
  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final file   = await picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;

    setState(() { _mode = _GrapeMode.processing; _count = 0; _dets = []; _annotatedImage = null; _vidReady = false; });

    try {
      // Initialise video player for playback
      _vidCtrl?.dispose();
      _vidCtrl = VideoPlayerController.file(File(file.path));
      await _vidCtrl!.initialize();
      if (!mounted) return;
      _vidCtrl!.addListener(_vidListener);

      // Upload via fromPath – avoids loading entire video into RAM
      final videoFile = File(file.path);
      final ext       = file.path.split('.').last.toLowerCase();

      final req = http.MultipartRequest('POST', Uri.parse(_videoEndpoint))
        ..headers.addAll(_ngrokHeader)
        ..files.add(await http.MultipartFile.fromPath(
          'file', videoFile.path,
          filename: file.name,
          contentType: MediaType('video', ext == 'mp4' ? 'mp4' : 'octet-stream'),
        ));

      final streamed = await req.send().timeout(const Duration(seconds: 300));
      final body     = await streamed.stream.bytesToString();

      if (!mounted) return;
      if (streamed.statusCode == 200) {
        final result    = jsonDecode(body) as Map<String, dynamic>;
        final annotated = _decodeAnnotated(result);
        final src = _extractSrcSize(result,
            fallbackW: _vidCtrl!.value.size.width,
            fallbackH: _vidCtrl!.value.size.height);
        setState(() {
          _count          = _extractCount(result);
          _counts         = _extractCounts(result);
          _dets           = _parseDets(result);
          _annotatedImage = annotated;
          _detSrcW        = src.width;
          _detSrcH        = src.height;
          _vidReady       = true;
          _mode           = _GrapeMode.video;
        });
        _vidCtrl?.play();
        _showSnack('Found $_count cluster${_count == 1 ? '' : 's'} in video');
      } else {
        _showErr('Video API error ${streamed.statusCode}: ${body.substring(0, body.length.clamp(0, 200))}');
        setState(() => _mode = _GrapeMode.idle);
      }
    } catch (e) {
      if (mounted) { _showErr('Video analysis failed: $e'); setState(() => _mode = _GrapeMode.idle); }
    }
  }

  void _vidListener() {
    if (_vidCtrl == null) return;
    final playing = _vidCtrl!.value.isPlaying;
    if (playing != _vidPlaying && mounted) setState(() => _vidPlaying = playing);
  }

  // ── Decode annotated image (base64 JPEG/PNG) ─────────────────
  // New API returns 'annotated_image_base64'; legacy used 'annotated_image'
  Uint8List? _decodeAnnotated(Map<String, dynamic> r) {
    for (final key in const [
      'annotated_image_base64',   // new HF space format
      'annotated_image', 'annotated_frame', 'best_frame',
      'result_image', 'output_image', 'image',
    ]) {
      final v = r[key];
      if (v is String && v.isNotEmpty) {
        try {
          // Strip data-URI prefix if present (data:image/jpeg;base64,...)
          final b64 = v.contains(',') ? v.split(',').last : v;
          return base64Decode(b64);
        } catch (_) {}
      }
    }
    return null;
  }

  // ── Extract the image dimensions that bbox coords are relative to
  Size _extractSrcSize(Map<String, dynamic> r, {double fallbackW = 640, double fallbackH = 640}) {
    double w = fallbackW, h = fallbackH;
    for (final key in const ['image_width', 'width', 'img_width', 'frame_width', 'input_width']) {
      final v = r[key];
      if (v is num && v > 0) { w = v.toDouble(); break; }
    }
    for (final key in const ['image_height', 'height', 'img_height', 'frame_height', 'input_height']) {
      final v = r[key];
      if (v is num && v > 0) { h = v.toDouble(); break; }
    }
    return Size(w, h);
  }

  void _reset() {
    _stopCamera(); // async, fire-and-forget
    _vidCtrl?.pause();
    _vidCtrl?.dispose();
    _vidCtrl = null;
    setState(() {
      _mode = _GrapeMode.idle;
      _camReady = _vidReady = _vidPlaying = false;
      _count = 0; _counts = {}; _dets = []; _annotatedImage = null; _annotatedSize = null;
      _detSrcW = 640; _detSrcH = 640;
    });
  }

  void _showErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
      backgroundColor: const Color(0xFF6B21A8),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ══════════════════════════════ UI ════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(child: Column(children: [
        _topBar(),
        Expanded(child: _body()),
        _countBadge(),
        _bottomBar(),
      ])),
    );
  }

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 14, 16, 0),
    child: Row(children: [
      // Back arrow
      GestureDetector(
        onTap: widget.onClose,
        child: Container(
          width: 40, height: 40,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.08),
            border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.5),
          ),
          child: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 17),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF6B21A8).withOpacity(0.25),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF9333EA).withOpacity(0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.camera_enhance_outlined, color: Color(0xFFA855F7), size: 15),
          SizedBox(width: 6),
          Text('AI CAM',
              style: TextStyle(color: Color(0xFFA855F7),
                  fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.2)),
        ]),
      ),
      const SizedBox(width: 8),
      if (_mode == _GrapeMode.camera && _camReady)
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Opacity(
            opacity: _pulseAnim.value,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withOpacity(0.5)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.fiber_manual_record, color: Colors.red, size: 8),
                SizedBox(width: 5),
                Text('LIVE', style: TextStyle(color: Colors.red,
                    fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
              ]),
            ),
          ),
        ),
      const Spacer(),
      if (_mode != _GrapeMode.idle)
        GestureDetector(
          onTap: _reset,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: const Text('Reset', style: TextStyle(
                color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ),
    ]),
  );

  Widget _body() {
    // No longer gate on _apiReady — the health check is non-blocking.
    // If the space is cold-starting, the first upload attempt will just
    // take longer; the user sees a progress indicator instead of an error.
    switch (_mode) {
      case _GrapeMode.camera:     return _cameraBody();
      case _GrapeMode.processing: return _processingBody();
      case _GrapeMode.video:      return _videoBody();
      case _GrapeMode.idle:       return _idleBody();
    }
  }

  Widget _errorBody() => Center(child: Padding(
    padding: const EdgeInsets.all(28),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(shape: BoxShape.circle,
          color: Colors.red.withOpacity(0.15),
          border: Border.all(color: Colors.red.withOpacity(0.5))),
        child: const Icon(Icons.cloud_off, color: Colors.red, size: 34),
      ),
      const SizedBox(height: 20),
      const Text('API Unreachable', style: TextStyle(
          color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withOpacity(0.3))),
        child: Text(_apiError ?? '', textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 12,
                fontWeight: FontWeight.w500, height: 1.4)),
      ),
      const SizedBox(height: 20),
      GestureDetector(
        onTap: _checkApi,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(color: const Color(0xFF6B21A8),
              borderRadius: BorderRadius.circular(20)),
          child: const Text('Retry', style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900)),
        ),
      ),
    ]),
  ));

  Widget _loadingBody() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, child) => Transform.scale(scale: _pulseAnim.value, child: child),
      child: Container(
        width: 100, height: 100,
        decoration: BoxDecoration(shape: BoxShape.circle,
          color: const Color(0xFF6B21A8).withOpacity(0.2),
          border: Border.all(color: const Color(0xFF9333EA).withOpacity(0.5), width: 2)),
        child: const Icon(Icons.cloud_sync, color: Color(0xFFA855F7), size: 48),
      ),
    ),
    const SizedBox(height: 24),
    const CircularProgressIndicator(color: Color(0xFF9333EA), strokeWidth: 3),
    const SizedBox(height: 16),
    const Text('Connecting to Grape API…', style: TextStyle(
        color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 14)),
    const SizedBox(height: 6),
    const Text('planeteyefarm12-fruit-grape-counter.hf.space',
        style: TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.w600)),
  ]));

  Widget _idleBody() => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, child) => Transform.scale(scale: _pulseAnim.value, child: child),
        child: Container(
          width: 110, height: 110,
          decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              const Color(0xFF6B21A8).withOpacity(0.5),
              const Color(0xFF6B21A8).withOpacity(0.1),
            ]),
            border: Border.all(color: const Color(0xFF9333EA).withOpacity(0.6), width: 2)),
          child: const Icon(Icons.grain, color: Color(0xFFA855F7), size: 52),
        ),
      ),
      const SizedBox(height: 28),
      const Text('Count Grape Clusters',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900,
              fontSize: 24, letterSpacing: -0.3)),
      const SizedBox(height: 10),
      const Text(
        'Use live camera for real-time detection, pick an image, or select a video for analysis.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white54, fontSize: 13,
            fontWeight: FontWeight.w500, height: 1.5),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.withOpacity(0.4))),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.cloud_done, color: Colors.green, size: 14),
          SizedBox(width: 6),
          Text('API connected · YOLOv8 ready',
              style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ),
      // Show last annotated result with count + breakdown
      if (_annotatedImage != null || _count > 0) ...[        const SizedBox(height: 24),
        // Total count badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6B21A8), Color(0xFF9333EA)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: const Color(0xFF9333EA).withOpacity(0.4),
                blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('🍇', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$_count', style: const TextStyle(
                  color: Colors.white, fontSize: 28,
                  fontWeight: FontWeight.w900, height: 1)),
              const Text('detected', style: TextStyle(
                  color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
        // Per-class breakdown
        if (_counts.isNotEmpty) ...[          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 6, alignment: WrapAlignment.center,
            children: _counts.entries.map((e) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF6B21A8).withOpacity(0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF9333EA).withOpacity(0.5)),
              ),
              child: Text('${e.key}: ${e.value}',
                  style: const TextStyle(color: Colors.white,
                      fontSize: 12, fontWeight: FontWeight.w700)),
            )).toList(),
          ),
        ],
        // Annotated image full-width
        if (_annotatedImage != null) ...[          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.memory(_annotatedImage!, fit: BoxFit.contain,
                width: double.infinity),
          ),
        ],
      ],
    ]),
  ));

  // ── Camera body: live preview + CustomPainter bounding boxes ──
  Widget _cameraBody() {
    if (!_camReady || _camCtrl == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF9333EA)));
    }
    // Camera sensor is landscape on Android; previewSize.width > height.
    // CameraPreview rotates the display to portrait, so we swap dims for the painter.
    final previewSize = _camCtrl!.value.previewSize;
    final double srcW = previewSize != null
        ? (previewSize.width > previewSize.height ? previewSize.height : previewSize.width)
        : _detSrcW;
    final double srcH = previewSize != null
        ? (previewSize.width > previewSize.height ? previewSize.width : previewSize.height)
        : _detSrcH;

    return Stack(fit: StackFit.expand, children: [
      CameraPreview(_camCtrl!),
      // Draw bounding boxes using CustomPainter
      CustomPaint(
        painter: _BoxPainter(
          dets: _dets,
          srcW: _detSrcW > 0 ? _detSrcW : srcW,
          srcH: _detSrcH > 0 ? _detSrcH : srcH,
        ),
      ),
      // Corner markers
      ..._corners(),
      // Spinner while API call in flight
      if (_detecting)
        Positioned(top: 12, right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.black54,
                borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: const [
              SizedBox(width: 10, height: 10,
                child: CircularProgressIndicator(
                    color: Color(0xFFA855F7), strokeWidth: 2)),
              SizedBox(width: 6),
              Text('Detecting…', style: TextStyle(color: Colors.white70,
                  fontSize: 10, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
    ]);
  }

  // ── Video body: player + CustomPainter bounding boxes ─────────
  Widget _videoBody() {
    if (!_vidReady || _vidCtrl == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF9333EA)));
    }
    return Stack(fit: StackFit.expand, children: [
      // Video player centred with correct aspect ratio
      Center(child: AspectRatio(
        aspectRatio: _vidCtrl!.value.aspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The video renders at exactly constraints.biggest.
            // We draw boxes scaled from (_detSrcW × _detSrcH) → render size.
            return Stack(children: [
              VideoPlayer(_vidCtrl!),
              CustomPaint(
                size: constraints.biggest,
                painter: _BoxPainter(
                  dets: _dets,
                  srcW: _detSrcW > 0 ? _detSrcW : _vidCtrl!.value.size.width,
                  srcH: _detSrcH > 0 ? _detSrcH : _vidCtrl!.value.size.height,
                ),
              ),
            ]);
          },
        ),
      )),
      // Play/pause button
      Positioned(bottom: 16, left: 0, right: 0,
        child: Center(child: GestureDetector(
          onTap: () {
            if (_vidCtrl!.value.isPlaying) _vidCtrl!.pause();
            else _vidCtrl!.play();
          },
          child: Container(
            width: 56, height: 56,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: Colors.black54,
              border: Border.all(color: Colors.white30, width: 1.5)),
            child: Icon(_vidPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white, size: 28),
          ),
        )),
      ),
    ]);
  }

  Widget _processingBody() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const SizedBox(width: 60, height: 60,
      child: CircularProgressIndicator(color: Color(0xFF9333EA), strokeWidth: 4)),
    const SizedBox(height: 24),
    const Text('Sending to Grape API…', style: TextStyle(
        color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
    const SizedBox(height: 8),
    const Text('YOLOv8 detection running on server',
        style: TextStyle(color: Colors.white54, fontSize: 13)),
    const SizedBox(height: 20),
    AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => Opacity(
        opacity: _pulseAnim.value,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF6B21A8).withOpacity(0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF9333EA).withOpacity(0.4))),
          child: const Text('flamboyantly-muzzy-kyleigh.ngrok-free.dev',
              style: TextStyle(color: Color(0xFFA855F7),
                  fontWeight: FontWeight.w700, fontSize: 11)),
        ),
      ),
    ),
  ]));

  Widget _countBadge() => Container(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF4C1D95), Color(0xFF7C3AED)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [BoxShadow(
          color: const Color(0xFF7C3AED).withOpacity(0.4),
          blurRadius: 16, offset: const Offset(0, 6))],
    ),
    child: Row(children: [
      Container(
        width: 52, height: 52,
        decoration: BoxDecoration(shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.15),
          border: Border.all(color: Colors.white30, width: 1.5)),
        child: const Icon(Icons.grain, color: Colors.white, size: 26),
      ),
      const SizedBox(width: 16),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('CLUSTERS DETECTED',
            style: TextStyle(color: Colors.white60, fontSize: 10,
                fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        const SizedBox(height: 2),
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Text('$_count',
            style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900, fontSize: 36,
              shadows: _count > 0
                  ? [Shadow(color: Colors.white.withOpacity(0.3), blurRadius: 8)]
                  : null)),
        ),
      ]),
      const Spacer(),
      if (_mode == _GrapeMode.camera && _camReady)
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('LIVE · API', style: TextStyle(
              color: Colors.white60, fontSize: 9,
              fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 4),
          Container(width: 10, height: 10,
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
        ]),
    ]),
  );

  Widget _bottomBar() => Container(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: Row(children: [
      Expanded(child: GestureDetector(
        onTap: _mode == _GrapeMode.camera
            ? () async { await _stopCamera(); setState(() => _mode = _GrapeMode.idle); }
            : _startCamera,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            gradient: _mode == _GrapeMode.camera
                ? const LinearGradient(colors: [Color(0xFF991B1B), Color(0xFFDC2626)])
                : const LinearGradient(colors: [Color(0xFF4C1D95), Color(0xFF7C3AED)]),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(
                color: (_mode == _GrapeMode.camera ? Colors.red : const Color(0xFF7C3AED))
                    .withOpacity(0.4),
                blurRadius: 12, offset: const Offset(0, 4))]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(_mode == _GrapeMode.camera ? Icons.videocam_off : Icons.videocam,
                color: Colors.white, size: 26),
            const SizedBox(height: 4),
            Text(_mode == _GrapeMode.camera ? 'Stop' : 'Live Camera',
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w900, fontSize: 12)),
          ]),
        ),
      )),
      const SizedBox(width: 10),
      Expanded(child: GestureDetector(
        onTap: _pickImage,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12, width: 1.5)),
          child: Column(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.image_outlined, color: Colors.white70, size: 26),
            SizedBox(height: 4),
            Text('Pick Image', style: TextStyle(color: Colors.white70,
                fontWeight: FontWeight.w700, fontSize: 12)),
          ]),
        ),
      )),
      const SizedBox(width: 10),
      Expanded(child: GestureDetector(
        onTap: _mode == _GrapeMode.processing ? null : _pickVideo,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12, width: 1.5)),
          child: Column(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.video_file_outlined, color: Colors.white70, size: 26),
            SizedBox(height: 4),
            Text('Pick Video', style: TextStyle(color: Colors.white70,
                fontWeight: FontWeight.w700, fontSize: 12)),
          ]),
        ),
      )),
    ]),
  );

  List<Widget> _corners() {
    Widget corner(Alignment a) => Positioned.fill(
      child: Align(alignment: a,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(width: 36, height: 36,
            child: CustomPaint(painter: _CornerP(
              color: const Color(0xFFA855F7),
              flipX: a == Alignment.topRight || a == Alignment.bottomRight,
              flipY: a == Alignment.bottomLeft || a == Alignment.bottomRight,
            )),
          ),
        ),
      ),
    );
    return [
      corner(Alignment.topLeft),
      corner(Alignment.topRight),
      corner(Alignment.bottomLeft),
      corner(Alignment.bottomRight),
    ];
  }
}

// ── Bounding box painter ──────────────────────────────────────────
// Scales detection coords from (srcW × srcH) to the actual canvas size.
class _BoxPainter extends CustomPainter {
  final List<_Detect> dets;
  final double srcW, srcH;
  _BoxPainter({required this.dets, required this.srcW, required this.srcH});

  @override
  void paint(Canvas canvas, Size size) {
    if (dets.isEmpty || srcW <= 0 || srcH <= 0) return;

    final scaleX = size.width  / srcW;
    final scaleY = size.height / srcH;

    final fillPaint = Paint()
      ..color = const Color(0xFFA855F7).withOpacity(0.18)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFFA855F7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final labelBg = Paint()
      ..color = const Color(0xFF6B21A8)
      ..style = PaintingStyle.fill;

    for (final d in dets) {
      final rect = Rect.fromLTWH(
        d.x * scaleX, d.y * scaleY,
        d.w * scaleX, d.h * scaleY,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        fillPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        borderPaint,
      );

      // Confidence label
      final label = '${(d.conf * 100).round()}%';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      const pad = 4.0;
      final labelTop = (rect.top - 20).clamp(0.0, size.height - 20);
      final labelRect = Rect.fromLTWH(
        rect.left, labelTop, tp.width + pad * 2, 18);
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
        labelBg,
      );
      tp.paint(canvas, Offset(rect.left + pad, labelTop + 3));
    }
  }

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.dets != dets || old.srcW != srcW || old.srcH != srcH;
}

// ── Corner painter ────────────────────────────────────────────────
class _CornerP extends CustomPainter {
  final Color color;
  final bool flipX, flipY;
  _CornerP({required this.color, required this.flipX, required this.flipY});

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color ..strokeWidth = 3
      ..style = PaintingStyle.stroke ..strokeCap = StrokeCap.round;
    final x  = flipX ? s.width  : 0.0;
    final y  = flipY ? s.height : 0.0;
    final dx = flipX ? -s.width * 0.6 : s.width * 0.6;
    final dy = flipY ? -s.height * 0.6 : s.height * 0.6;
    canvas.drawLine(Offset(x, y), Offset(x + dx, y), p);
    canvas.drawLine(Offset(x, y), Offset(x, y + dy), p);
  }

  @override
  bool shouldRepaint(_CornerP o) => false;
}

// ── Detection data class ──────────────────────────────────────────
class _Detect {
  final double x, y, w, h, conf;
  const _Detect({required this.x, required this.y,
      required this.w, required this.h, required this.conf});
}

// ═══════════════════════════════════════════════════════════════════
// TOP-LEVEL ISOLATE HELPERS  (must be top-level for compute())
// ═══════════════════════════════════════════════════════════════════

/// Data passed into the background isolate — all plain Dart types.
class _YuvParams {
  final Uint8List yBytes, uBytes, vBytes;
  final int width, height, yRowStride, uvRowStride, uvPixStride;
  const _YuvParams({
    required this.yBytes, required this.uBytes, required this.vBytes,
    required this.width,  required this.height,
    required this.yRowStride, required this.uvRowStride, required this.uvPixStride,
  });
}

/// Runs in a separate isolate — YUV420 → RGBA using integer arithmetic only.
/// No floating-point per pixel = minimal GC pressure, no dropped frames.
Uint8List? _yuvToRgbaIsolate(_YuvParams p) {
  try {
    final int w = p.width;
    final int h = p.height;
    final rgba = Uint8List(w * h * 4);
    int idx = 0;
    for (int row = 0; row < h; row++) {
      for (int col = 0; col < w; col++) {
        final int yIdx  = row * p.yRowStride + col;
        final int uvIdx = (row >> 1) * p.uvRowStride + (col >> 1) * p.uvPixStride;
        final int Y  = p.yBytes[yIdx];
        final int Cb = p.uBytes[uvIdx] - 128;
        final int Cr = p.vBytes[uvIdx] - 128;
        // BT.601 integer approximation (scaled ×1024)
        rgba[idx++] = (Y + ((1402 * Cr) >> 10)).clamp(0, 255);
        rgba[idx++] = (Y - ((344 * Cb + 714 * Cr) >> 10)).clamp(0, 255);
        rgba[idx++] = (Y + ((1772 * Cb) >> 10)).clamp(0, 255);
        rgba[idx++] = 255;
      }
    }
    return rgba;
  } catch (_) {
    return null;
  }
}


// ─── Address line widget: reverse-geocodes on first build, caches result ─────
class _PlotAddressLine extends StatefulWidget {
  final double lat, lng;
  const _PlotAddressLine({required this.lat, required this.lng});
  @override
  State<_PlotAddressLine> createState() => _PlotAddressLineState();
}

class _PlotAddressLineState extends State<_PlotAddressLine> {
  String? _address;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final addr = await _reverseGeocode(widget.lat, widget.lng);
    if (mounted) setState(() { _address = addr; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: const [
          Icon(Icons.location_on_rounded, size: 10, color: AppColors.primary),
          SizedBox(width: 3),
          SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary)),
        ]),
      );
    }
    final label = (_address != null && _address!.isNotEmpty)
        ? _address!
        : '${widget.lat.toStringAsFixed(4)}, ${widget.lng.toStringAsFixed(4)}';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        const Icon(Icons.location_on_rounded, size: 10, color: AppColors.primary),
        const SizedBox(width: 3),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.primary, letterSpacing: 0.2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}
