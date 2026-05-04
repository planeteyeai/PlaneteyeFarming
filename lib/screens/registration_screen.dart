import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../constants/app_constants.dart';
import '../constants/crop_data.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';
import 'map_plot_screen.dart';
import 'face_auth_screen.dart';

class RegistrationScreen extends StatefulWidget {
  final void Function(Map<String, dynamic>?) onComplete;
  final VoidCallback onBack;
  const RegistrationScreen({super.key, required this.onComplete, required this.onBack});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _key = GlobalKey<FormState>();
  bool _showMap = false, _loading = false;
  String? _error;

  final _first = TextEditingController();
  final _last = TextEditingController();
  final _user = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _phone = TextEditingController();
  final _village = TextEditingController();
  final _taluka = TextEditingController();
  final _district = TextEditingController();
  final _state = TextEditingController();

  String _cropType = '', _cropVariety = '', _irrigation = irrigationTypes[0];
  DateTime _plantDate = DateTime.now();

  // Face enroll state — shown after registration succeeds
  bool _showFaceEnroll  = false;
  Map<String, dynamic>? _pendingCompleteData; // held until face step done/skipped

  @override
  void dispose() {
    for (final c in [_first,_last,_user,_email,_pass,_phone,_village,_taluka,_district,_state]) c.dispose();
    super.dispose();
  }

  String? req(String? v) => (v == null || v.isEmpty) ? 'Required' : null;

  Future<void> _onMapDone(List<LatLng> polygon) async {
    setState(() { _loading = true; _error = null; });
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_plantDate);

      // ── Step 1: Register farmer ───────────────────────────────────
      final response = await ApiService.registerFarmer(
        firstName: _first.text.trim(), lastName: _last.text.trim(),
        username: _user.text.trim(), email: _email.text.trim(),
        password: _pass.text, phoneNumber: _phone.text.trim(),
        village: _village.text.trim(), taluka: _taluka.text.trim(),
        district: _district.text.trim(), state: _state.text.trim(),
        cropType: _cropType, cropVariety: _cropVariety,
        plantationDate: dateStr, irrigationType: _irrigation,
      );

      // Extract farmer_id from registration response
      final rawId = response['farmer_id'] ??
          response['id'] ??
          response['data']?['farmer_id'] ??
          response['data']?['id'];
      final farmerId = rawId != null
          ? (rawId is int ? rawId : int.tryParse(rawId.toString()))
          : null;

      // ── Step 2: Save the plot via addPlot API ─────────────────────
      String? serverPlotId;
      // FIX 9: Correct area using Shoelace + EPSG:3857 projection
      final areaMetrics = PlotAreaCalculator.calculateFromLatLng(polygon);
      final areaLabel = areaMetrics?.displayLabel ?? '0.00 Ac';
      if (farmerId != null) {
        final avgLat = polygon.map((p) => p.latitude).reduce((a, b) => a + b) / polygon.length;
        final avgLng = polygon.map((p) => p.longitude).reduce((a, b) => a + b) / polygon.length;
        final plotName = '${_cropType.isNotEmpty ? _cropType : "Main"} Plot';
        final polygonCoords = polygon.map((p) => [p.latitude, p.longitude]).toList();

        final plotResult = await ApiService.addPlot(
          farmerId: farmerId,
          name: plotName,
          center: [avgLat, avgLng],
          polygon: polygonCoords,
        );
        serverPlotId = plotResult['id']?.toString();
        // Store in ApiService so further calls use it
        await ApiService.saveFarmerId(farmerId);
        await ApiService.saveFarmLocation(
          district: _district.text.trim(),
          state: _state.text.trim(),
        );
      }

      final completeData = {
        'name': '${_cropType.isNotEmpty ? _cropType : "Main"} Plot',
        'cropType': _cropType, 'cropVariety': _cropVariety,
        'plantationDate': dateStr, 'irrigationType': _irrigation,
        'polygon': polygon,
        'firstName': _first.text.trim(), 'lastName': _last.text.trim(),
        'farmer_id': farmerId,
        'area': areaLabel,
        'plot_id': serverPlotId ??
            response['plot_id']?.toString() ??
            response['field_id']?.toString(),
      };

      // ── Step 3: Proceed directly to dashboard — skip face enroll at registration
      // User can register face later from Profile Settings.
      setState(() { _loading = false; _showMap = false; });
      widget.onComplete(completeData);
    } catch (e) {
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); _showMap = false; });
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context,
      initialDate: _plantDate, firstDate: DateTime(2020), lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: AppColors.primary)),
        child: child!));
    if (d != null) setState(() => _plantDate = d);
  }

  @override
  Widget build(BuildContext context) {
    // ── Face enroll step — shown after successful registration ─────────────
    if (_showFaceEnroll && _pendingCompleteData != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF080F09),
        body: SafeArea(
          child: Column(children: [
            // Header with skip
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Row(children: [
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Register Your Face', style: TextStyle(
                        color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                    SizedBox(height: 3),
                    Text('For one-tap login in the future',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ]),
                ),
                TextButton(
                  onPressed: () {
                    // Skip face enroll → proceed to dashboard
                    widget.onComplete(_pendingCompleteData);
                  },
                  child: const Text('Skip →',
                      style: TextStyle(color: Colors.white38, fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
            // Optional badge
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
                Text('OPTIONAL — You can register later from Profile Settings',
                    style: TextStyle(color: Colors.amber, fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(height: 4),
            // Face enroll screen — uses POST /api/farmers/face/enroll/
            Expanded(
              child: FaceAuthScreen(
                mode: FaceAuthMode.enroll,
                onSuccess: () {
                  // Face enrolled → proceed to dashboard
                  widget.onComplete(_pendingCompleteData);
                },
                onSkip: () {
                  // Skipped → proceed to dashboard
                  widget.onComplete(_pendingCompleteData);
                },
              ),
            ),
          ]),
        ),
      );
    }

    if (_showMap) {
      return MapPlotScreen(
        title: 'Draw Your First Plot',
        onComplete: _loading ? (_) {} : _onMapDone,
        onBack: () => setState(() => _showMap = false),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: Stack(children: [

        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
          child: Form(key: _key, child: ListView(children: [
            const SizedBox(height: 72),

            const Text('Registration',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.textDark, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            const Text('CREATE YOUR FARMER ACCOUNT',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 2)),
            const SizedBox(height: 28),

            if (_error != null) ...[
              Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade200)),
                child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
            ],

            // ─── Personal Info ─────────────────────────────────────────
            Row(children: [
              Expanded(child: LabeledField(label: 'First Name', controller: _first, validator: req)),
              const SizedBox(width: 14),
              Expanded(child: LabeledField(label: 'Last Name', controller: _last, validator: req)),
            ]),
            const SizedBox(height: 20),
            LabeledField(label: 'Username', controller: _user, validator: req),
            const SizedBox(height: 20),
            LabeledField(label: 'Email Address', controller: _email,
              keyboardType: TextInputType.emailAddress,
              validator: (v) => v!.isEmpty ? 'Required' : !v.contains('@') ? 'Invalid email' : null),
            const SizedBox(height: 20),
            LabeledField(label: 'Password', controller: _pass, obscure: true,
              validator: (v) => v!.length < 6 ? 'Min 6 characters' : null),
            const SizedBox(height: 20),
            LabeledField(label: 'Phone Number', controller: _phone,
              hint: '+919876543210', keyboardType: TextInputType.phone, validator: req),
            const SizedBox(height: 20),

            // ─── Location ────────────────────────────────────────────────
            Row(children: [
              Expanded(child: LabeledField(label: 'Village', controller: _village, validator: req)),
              const SizedBox(width: 14),
              Expanded(child: LabeledField(label: 'Taluka', controller: _taluka, validator: req)),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: LabeledField(label: 'District', controller: _district, validator: req)),
              const SizedBox(width: 14),
              Expanded(child: LabeledField(label: 'State', controller: _state, validator: req)),
            ]),
            const SizedBox(height: 28),

            const SectionDivider(),
            const SizedBox(height: 16),

            // ─── Crop Details ─────────────────────────────────────────────
            const Text('Crop Details',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textDark)),
            const SizedBox(height: 4),
            const Text('PRIMARY FIELD INFORMATION',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textLight, letterSpacing: 2)),
            const SizedBox(height: 20),

            AutocompleteSearchField(
              label: 'Crop Type', hint: 'Type to search crops...',
              suggestions: commonCrops,
              onSelected: (v) => setState(() { _cropType = v; _cropVariety = ''; }),
              initial: _cropType,
            ),
            const SizedBox(height: 20),

            AutocompleteSearchField(
              label: 'Crop Variety', hint: 'Type to search variety...',
              suggestions: (_cropType.isNotEmpty && commonVarieties.containsKey(_cropType))
                  ? commonVarieties[_cropType]!
                  : commonVarieties.values.expand((v) => v).toSet().toList(),
              onSelected: (v) => setState(() => _cropVariety = v),
              initial: _cropVariety,
            ),
            const SizedBox(height: 20),

            // Plantation Date picker
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(left: 8, bottom: 8),
                child: Text('PLANTATION DATE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textLight, letterSpacing: 1.5))),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.borderLight, width: 2)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today, size: 18, color: AppColors.textLight),
                    const SizedBox(width: 12),
                    Text(DateFormat('dd-MM-yyyy').format(_plantDate),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  ])),
              ),
            ]),
            const SizedBox(height: 20),

            IrrigationSelector(options: irrigationTypes, selected: _irrigation,
              onSelect: (v) => setState(() => _irrigation = v)),
            const SizedBox(height: 32),

            PrimaryButton(
              label: 'Register',
              loading: _loading,
              icon: Icons.arrow_forward,
              onTap: () {
                if (_key.currentState!.validate()) setState(() => _showMap = true);
              },
            ),
            const SizedBox(height: 40),
          ])),
        ),

        // Back button rendered ON TOP of the ListView so it receives taps
        Positioned(top: 8, left: 16, child: BackCircleButton(onTap: widget.onBack)),
      ])),
    );
  }
}
