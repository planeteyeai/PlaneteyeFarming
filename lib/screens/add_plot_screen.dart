import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../constants/app_constants.dart';
import '../constants/crop_data.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';
import 'map_plot_screen.dart';

class AddPlotScreen extends StatefulWidget {
  final void Function(Map<String, dynamic>?) onComplete;
  final VoidCallback onBack;
  // farmer_id from registration; null = not yet registered (fallback)
  final int? farmerId;

  const AddPlotScreen({
    super.key,
    required this.onComplete,
    required this.onBack,
    this.farmerId,
  });

  @override
  State<AddPlotScreen> createState() => _AddPlotScreenState();
}

class _AddPlotScreenState extends State<AddPlotScreen> {
  final _key = GlobalKey<FormState>();
  bool _showMap = false, _loading = false;
  String? _error;

  String _cropType = '', _cropVariety = '', _irrigation = irrigationTypes[0];
  DateTime _plantDate = DateTime.now();
  final _plotName = TextEditingController();
  // Crop spacing — farmer-entered, used for accurate animation
  double _rowSpacingM  = 0.0;  // metres between rows  (0 = use default)
  double _plantSpacingM = 0.0; // metres between plants (0 = use default)

  @override
  void dispose() {
    _plotName.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _plantDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme:
                const ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (d != null) setState(() => _plantDate = d);
  }

  Future<void> _onMapDone(List<LatLng> polygon) async {
    setState(() { _loading = true; _error = null; });

    final dateStr = DateFormat('yyyy-MM-dd').format(_plantDate);
    final name = _plotName.text.trim().isNotEmpty
        ? _plotName.text.trim()
        : '${_cropType.isNotEmpty ? _cropType : "New"} Plot';

    // Compute center and polygon coords from LatLng points
    final avgLat = polygon.map((p) => p.latitude).reduce((a, b) => a + b) /
        polygon.length;
    final avgLng = polygon.map((p) => p.longitude).reduce((a, b) => a + b) /
        polygon.length;
    final center = [avgLat, avgLng];
    final polygonCoords =
        polygon.map((p) => [p.latitude, p.longitude]).toList();

    // FIX 9: Correct area using Shoelace + EPSG:3857 projection
    final areaMetrics = PlotAreaCalculator.calculateFromLatLng(polygon);
    final areaLabel = areaMetrics?.displayLabel ?? '0.00 Ac';

    try {
      String? serverPlotId;

      // Use prop farmerId first, then fall back to globally stored one
      final fid = widget.farmerId ?? ApiService.farmerId;

      if (fid != null) {
        final result = await ApiService.addPlot(
          farmerId: fid,
          name: name,
          center: center,
          polygon: polygonCoords,
        );
        serverPlotId = result['id']?.toString();
      }

      // Pass everything back — main.dart will re-fetch the full list
      widget.onComplete({
        'name':            name,
        'cropType':        _cropType,
        'cropVariety':     _cropVariety,
        'plantationDate':  dateStr,
        'irrigationType':  _irrigation,
        'polygon':         polygon,
        'plot_id':         serverPlotId,
        'area':            areaLabel,
        'rowSpacingM':     _rowSpacingM,
        'plantSpacingM':   _plantSpacingM,
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
        _showMap = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showMap) {
      return MapPlotScreen(
        title: 'Draw Your Plot',
        onComplete: _loading ? (_) {} : _onMapDone,
        onBack: () => setState(() => _showMap = false),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
            child: Form(
              key: _key,
              child: ListView(children: [
                const SizedBox(height: 72),

                // ─── Header ─────────────────────────────────────────
                Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.greenLight,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.add_location_alt_outlined,
                        color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('New Plot',
                            style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textDark,
                                letterSpacing: -0.5)),
                        Text('ADD CROP DETAILS',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textLight,
                                letterSpacing: 2)),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 32),

                // ─── Error banner ────────────────────────────────────
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.red.shade200)),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_error!,
                            style: TextStyle(
                                color: Colors.red.shade700, fontSize: 13)),
                      ),
                    ]),
                  ),

                // ─── Plot Name ───────────────────────────────────────
                LabeledField(
                  label: 'Plot Name',
                  controller: _plotName,
                  hint: 'e.g. North Wheat Field',
                ),
                const SizedBox(height: 20),

                // ─── Crop Type ───────────────────────────────────────
                AutocompleteSearchField(
                  label: 'Crop Type',
                  hint: 'Type to search crops...',
                  suggestions: commonCrops,
                  onSelected: (v) => setState(() {
                    _cropType = v;
                    _cropVariety = '';
                  }),
                  initial: _cropType,
                ),
                const SizedBox(height: 20),

                // ─── Crop Variety ────────────────────────────────────
                AutocompleteSearchField(
                  label: 'Crop Variety',
                  hint: 'Type to search variety...',
                  suggestions: (_cropType.isNotEmpty &&
                          commonVarieties.containsKey(_cropType))
                      ? commonVarieties[_cropType]!
                      : commonVarieties.values
                          .expand((v) => v)
                          .toSet()
                          .toList(),
                  onSelected: (v) => setState(() => _cropVariety = v),
                  initial: _cropVariety,
                ),
                const SizedBox(height: 20),

                // ─── Plantation Date ─────────────────────────────────
                Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 8),
                    child: Text('PLANTATION DATE',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textLight,
                            letterSpacing: 1.5)),
                  ),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: AppColors.borderLight, width: 2)),
                      child: Row(children: [
                        const Icon(Icons.calendar_today,
                            size: 18, color: AppColors.textLight),
                        const SizedBox(width: 12),
                        Text(
                          DateFormat('dd-MM-yyyy').format(_plantDate),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark),
                        ),
                        const Spacer(),
                        const Icon(Icons.chevron_right,
                            color: AppColors.textLight, size: 20),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                // ─── Irrigation ──────────────────────────────────────
                IrrigationSelector(
                  options: irrigationTypes,
                  selected: _irrigation,
                  onSelect: (v) => setState(() => _irrigation = v),
                ),
                const SizedBox(height: 28),

                // ─── Crop Spacing ─────────────────────────────────────
                _SpacingSection(
                  rowSpacingM:   _rowSpacingM,
                  plantSpacingM: _plantSpacingM,
                  cropType:      _cropType,
                  onChanged: (row, plant) => setState(() {
                    _rowSpacingM   = row;
                    _plantSpacingM = plant;
                  }),
                ),
                const SizedBox(height: 32),

                // ─── API info chip ───────────────────────────────────
                if (widget.farmerId != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.greenLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.cloud_done_outlined,
                          color: AppColors.primary, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Will sync to server (Farmer #${widget.farmerId})',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary),
                      ),
                    ]),
                  ),

                // ─── Submit ──────────────────────────────────────────
                PrimaryButton(
                  label: 'Draw Plot on Map',
                  loading: _loading,
                  icon: Icons.map_outlined,
                  onTap: () {
                    if (_cropType.isEmpty) {
                      setState(
                          () => _error = 'Please select a crop type.');
                      return;
                    }
                    setState(() {
                      _error = null;
                      _showMap = true;
                    });
                  },
                ),
                const SizedBox(height: 40),
              ]),
            ),
          ),

          // Back button on top of everything
          Positioned(
            top: 8, left: 16,
            child: BackCircleButton(onTap: widget.onBack),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SPACING SECTION WIDGET
//
//  Lets the farmer enter row spacing and plant spacing in centimetres.
//  Shows crop-specific suggested defaults so the farmer knows what to
//  expect, and converts cm → metres before passing back to the parent.
//
//  Visual design:
//    • Labelled section header with a ruler icon
//    • Suggested default chips (tap to autofill)
//    • Two side-by-side number inputs (row gap | plant gap)
//    • Live preview bar showing relative spacing scale
//    • Hint text: "Leave blank to use crop defaults"
// ═══════════════════════════════════════════════════════════════════════════

class _SpacingSection extends StatefulWidget {
  final double rowSpacingM;
  final double plantSpacingM;
  final String cropType;
  final void Function(double rowM, double plantM) onChanged;

  const _SpacingSection({
    required this.rowSpacingM,
    required this.plantSpacingM,
    required this.cropType,
    required this.onChanged,
  });

  @override
  State<_SpacingSection> createState() => _SpacingSectionState();
}

class _SpacingSectionState extends State<_SpacingSection> {
  late TextEditingController _rowCtrl;
  late TextEditingController _plantCtrl;
  bool _expanded = false;

  // Suggested spacings per common crop (row cm, plant cm)
  static const Map<String, (int, int)> _suggestions = {
    'wheat':      (22, 10),
    'rice':       (25, 15),
    'corn':       (75, 25),
    'maize':      (75, 25),
    'cotton':     (90, 60),
    'soybean':    (45, 5),
    'sugarcane':  (90, 60),
    'potato':     (60, 30),
    'onion':      (15, 10),
    'tomato':     (60, 45),
    'cabbage':    (60, 45),
    'cauliflower':(60, 50),
    'sunflower':  (90, 30),
    'mustard':    (30, 10),
    'chickpea':   (30, 10),
    'groundnut':  (30, 10),
    'sesame':     (30, 10),
    'marigold':   (45, 30),
    'grape':      (300, 100),
  };

  (int, int) get _suggested {
    final s = widget.cropType.toLowerCase();
    for (final entry in _suggestions.entries) {
      if (s.contains(entry.key)) return entry.value;
    }
    return (30, 15); // generic default
  }

  @override
  void initState() {
    super.initState();
    _rowCtrl = TextEditingController(
        text: widget.rowSpacingM > 0
            ? (widget.rowSpacingM * 100).round().toString()
            : '');
    _plantCtrl = TextEditingController(
        text: widget.plantSpacingM > 0
            ? (widget.plantSpacingM * 100).round().toString()
            : '');
  }

  @override
  void dispose() {
    _rowCtrl.dispose();
    _plantCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    final rowCm    = double.tryParse(_rowCtrl.text)   ?? 0;
    final plantCm  = double.tryParse(_plantCtrl.text) ?? 0;
    widget.onChanged(rowCm / 100.0, plantCm / 100.0);
  }

  void _applyPreset((int, int) preset) {
    _rowCtrl.text   = preset.$1.toString();
    _plantCtrl.text = preset.$2.toString();
    _notify();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sug = _suggested;
    final rowCm   = double.tryParse(_rowCtrl.text)   ?? 0;
    final plantCm = double.tryParse(_plantCtrl.text) ?? 0;
    final hasCustom = rowCm > 0 || plantCm > 0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Section header ──────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 12),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: hasCustom
                  ? AppColors.primary.withOpacity(0.12)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.straighten_rounded,
                size: 17,
                color: hasCustom ? AppColors.primary : Colors.grey.shade500),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('CROP SPACING',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textLight,
                      letterSpacing: 1.5)),
              Text(
                hasCustom
                    ? '${rowCm.round()} cm rows · ${plantCm.round()} cm plants'
                    : 'Optional — uses crop defaults if blank',
                style: TextStyle(
                    fontSize: 11,
                    color: hasCustom
                        ? AppColors.primary
                        : Colors.grey.shade400,
                    fontWeight: FontWeight.w600),
              ),
            ]),
          ),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _expanded
                    ? AppColors.primary.withOpacity(0.10)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_expanded ? 'Hide' : 'Set',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _expanded
                            ? AppColors.primary
                            : Colors.grey.shade600)),
                const SizedBox(width: 4),
                Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: _expanded
                        ? AppColors.primary
                        : Colors.grey.shade500),
              ]),
            ),
          ),
        ]),
      ),

      // ── Expanded panel ──────────────────────────────────────────────
      AnimatedCrossFade(
        duration: const Duration(milliseconds: 250),
        crossFadeState: _expanded
            ? CrossFadeState.showSecond
            : CrossFadeState.showFirst,
        firstChild: const SizedBox.shrink(),
        secondChild: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderLight, width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // Suggested preset chip
            Row(children: [
              const Text('Suggested for crop:',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textLight,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _applyPreset(sug),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.greenLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.auto_fix_high_rounded,
                        size: 12, color: AppColors.primary),
                    const SizedBox(width: 5),
                    Text('${sug.$1} × ${sug.$2} cm',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 16),

            // Row spacing + Plant spacing inputs
            Row(children: [
              Expanded(child: _SpacingInput(
                label: 'Row Gap',
                hint: '${sug.$1}',
                icon: Icons.swap_vert_rounded,
                controller: _rowCtrl,
                onChanged: (_) => _notify(),
              )),
              const SizedBox(width: 14),
              Expanded(child: _SpacingInput(
                label: 'Plant Gap',
                hint: '${sug.$2}',
                icon: Icons.swap_horiz_rounded,
                controller: _plantCtrl,
                onChanged: (_) => _notify(),
              )),
            ]),
            const SizedBox(height: 14),

            // Live spacing preview bar
            if (rowCm > 0 || plantCm > 0)
              _SpacingPreviewBar(
                  rowCm: rowCm > 0 ? rowCm : sug.$1.toDouble(),
                  plantCm: plantCm > 0 ? plantCm : sug.$2.toDouble()),

            const SizedBox(height: 10),
            // Info note
            Row(children: [
              Icon(Icons.info_outline_rounded,
                  size: 12, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Enter spacing in centimetres. '
                  'This makes the field animation match your actual farm layout.',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade400,
                      height: 1.4),
                ),
              ),
            ]),
          ]),
        ),
      ),
    ]);
  }
}

// ── Single spacing number input ───────────────────────────────────────────

class _SpacingInput extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final void Function(String) onChanged;

  const _SpacingInput({
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Row(children: [
          Icon(icon, size: 13, color: AppColors.textLight),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textLight,
                  letterSpacing: 1.2)),
        ]),
      ),
      Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight, width: 1.5),
        ),
        child: Row(children: [
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey.shade300),
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('cm',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textLight)),
          ),
        ]),
      ),
    ]);
  }
}

// ── Live spacing preview — visual dot-grid diagram ────────────────────────

class _SpacingPreviewBar extends StatelessWidget {
  final double rowCm;
  final double plantCm;

  const _SpacingPreviewBar({required this.rowCm, required this.plantCm});

  @override
  Widget build(BuildContext context) {
    // Normalise spacing for display (max 4 rows × 8 plants in preview)
    final rowRatio   = (plantCm / rowCm).clamp(0.2, 5.0);
    const dotR = 4.0;
    const previewW = 220.0;
    const previewH = 48.0;
    const cols = 8;
    const rows = 3;
    final colStep = previewW / (cols + 1);
    final rowStep = previewH / (rows + 1);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Preview  (${rowCm.round()} cm × ${plantCm.round()} cm)',
          style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade400,
              fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Container(
        width: double.infinity,
        height: previewH + 8,
        decoration: BoxDecoration(
          color: const Color(0xFF6D4C41).withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: CustomPaint(
          painter: _DotGridPainter(
              cols: cols, rows: rows,
              colStep: colStep, rowStep: rowStep, dotR: dotR),
        ),
      ),
    ]);
  }
}

class _DotGridPainter extends CustomPainter {
  final int cols, rows;
  final double colStep, rowStep, dotR;
  const _DotGridPainter({
    required this.cols, required this.rows,
    required this.colStep, required this.rowStep, required this.dotR,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.primary.withOpacity(0.65);
    final shadow = Paint()..color = Colors.black.withOpacity(0.08);
    for (var r = 1; r <= rows; r++) {
      for (var c = 1; c <= cols; c++) {
        final offset = r % 2 == 0 ? colStep * 0.5 : 0.0;
        final x = c * colStep + offset;
        final y = r * rowStep;
        if (x > size.width) continue;
        canvas.drawCircle(Offset(x, y + 1.5), dotR, shadow);
        canvas.drawCircle(Offset(x, y), dotR, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) =>
      old.cols != cols || old.rows != rows;
}
