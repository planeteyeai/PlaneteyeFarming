import 'dart:math' as math;
import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF2E7D32);
  static const secondary = Color(0xFF5D4037);
  static const accent = Color(0xFFA4C639);
  static const background = Color(0xFFFAF9F6);
  static const water = Color(0xFF0288D1);
  static const alert = Color(0xFFD32F2F);
  static const warning = Color(0xFFFBC02D);
  static const cardWhite = Colors.white;
  static const textDark = Color(0xFF292524);
  static const textMedium = Color(0xFF78716C);
  static const textLight = Color(0xFFA8A29E);
  static const borderLight = Color(0xFFF5F5F4);
  static const greenLight = Color(0xFFE8F5E9);
  static const darkBg = Color(0xFF0A0A0A);

  static const statusVeryLow = Color(0xFFEF4444);
  static const statusLow = Color(0xFFF59E0B);
  static const statusMedium = Color(0xFFFACC15);
  static const statusOptimal = Color(0xFF15803D);
  static const statusVeryHigh = Color(0xFF2DD4BF);
}

class AppTheme {
  static ThemeData get theme => ThemeData(
        fontFamily: 'sans-serif',
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.light(primary: AppColors.primary),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: AppColors.borderLight, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: AppColors.borderLight, width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      );
}

// ─── Fix 9: Correct area calculation using Shoelace + EPSG:3857 projection ───
// Mirrors the JS reference implementation provided, adapted for Dart/Flutter.
// Input: list of [lat, lng] pairs (the polygon ring, may or may not be closed).
// Returns a record with sqm, hectares, and acres.
class AreaMetrics {
  final double sqm;
  final double hectares;
  final double acres;
  const AreaMetrics({required this.sqm, required this.hectares, required this.acres});

  /// Friendly display string — picks the most readable unit automatically.
  String get displayLabel {
    if (acres >= 0.1) return '${acres.toStringAsFixed(2)} Ac';
    return '${sqm.toStringAsFixed(0)} m²';
  }
}

class PlotAreaCalculator {
  static const double _sqmPerAcre = 4046.8564224;

  /// Projects a geographic [lat, lng] point to Web Mercator (EPSG:3857) metres.
  static (double x, double y) _project(double lat, double lng) {
    const r = 6378137.0; // WGS-84 equatorial radius in metres
    final x = r * lng * math.pi / 180.0;
    final y = r * math.log(math.tan(math.pi / 4 + lat * math.pi / 360.0));
    return (x, y);
  }

  /// Calculates the area of a polygon defined by [points] (list of [lat, lng]).
  /// Returns null if polygon has fewer than 3 distinct points.
  static AreaMetrics? calculate(List<List<double>> points) {
    if (points.length < 3) return null;

    // Project all points to metres
    final projected = points.map((p) => _project(p[0], p[1])).toList();

    // Shoelace formula on projected coordinates
    double area = 0.0;
    final n = projected.length;
    for (int i = 0; i < n; i++) {
      final (x1, y1) = projected[i];
      final (x2, y2) = projected[(i + 1) % n];
      area += x1 * y2 - x2 * y1;
    }
    final sqm = area.abs() / 2.0;
    return AreaMetrics(
      sqm: sqm,
      hectares: sqm / 10000.0,
      acres: sqm / _sqmPerAcre,
    );
  }

  /// Overload that accepts List<LatLng> from flutter_map / latlong2.
  static AreaMetrics? calculateFromLatLng(List<dynamic> latLngPoints) {
    try {
      final pts = latLngPoints.map<List<double>>((p) =>
          [(p as dynamic).latitude as double, (p as dynamic).longitude as double]
      ).toList();
      return calculate(pts);
    } catch (_) {
      return null;
    }
  }
}

// Mock data
class MockData {
  static const soilData = SoilData(
    ph: 7.30,
    nitrogen: 164.56,
    phosphorus: 54.31,
    potassium: 110.26,
    moisture: 45,
    cec: 37.47,
    oc: 11.20,
    bd: 1.57,
    fe: 22.52,
    soc: 8.4,
  );

  static const historicalData = [
    {'date': 'Feb 26', 'moisture': 42.0, 'nitrogen': 158.0},
    {'date': 'Feb 27', 'moisture': 40.0, 'nitrogen': 155.0},
    {'date': 'Feb 28', 'moisture': 38.0, 'nitrogen': 152.0},
    {'date': 'Mar 01', 'moisture': 45.0, 'nitrogen': 168.0},
    {'date': 'Mar 02', 'moisture': 44.0, 'nitrogen': 166.0},
    {'date': 'Mar 03', 'moisture': 45.0, 'nitrogen': 164.0},
  ];

  static const marketPrices = [
    {'crop': 'Wheat', 'price': '₹2,125', 'change': '+1.2%', 'trend': 'up', 'emoji': '🌾'},
    {'crop': 'Corn', 'price': '₹1,850', 'change': '-0.5%', 'trend': 'down', 'emoji': '🌽'},
    {'crop': 'Rice', 'price': '₹3,400', 'change': '+2.1%', 'trend': 'up', 'emoji': '🍚'},
    {'crop': 'Soybean', 'price': '₹4,200', 'change': '+0.8%', 'trend': 'up', 'emoji': '🌱'},
  ];
}

class SoilData {
  final double ph;
  final double nitrogen;
  final double phosphorus;
  final double potassium;
  final double moisture;
  final double cec;
  final double oc;
  final double bd;
  final double fe;
  final double soc;

  const SoilData({
    required this.ph,
    required this.nitrogen,
    required this.phosphorus,
    required this.potassium,
    required this.moisture,
    required this.cec,
    required this.oc,
    required this.bd,
    required this.fe,
    required this.soc,
  });

  Map<String, double> toMap() => {
    'PH': ph, 'NITROGEN': nitrogen, 'PHOSPHORUS': phosphorus,
    'POTASSIUM': potassium, 'CEC': cec, 'OC': oc,
  };
}

class FieldModel {
  final String id;
  final String name;
  /// Railway analysis APIs (`?plot_name=`) — must match the plot row for this login.
  /// Filled from GET plots: `plot_name` → `field_id` → `name` → `id`.
  final String plotNameForAnalysis;
  final List<double> center;
  final SoilData soilData;
  final String crop;
  final String? cropVariety;
  final String? plantationDate;
  final String? irrigationType;
  final String area;
  final String stage;
  final List<List<double>> polygon;
  /// Farmer-entered spacing in metres (0 = use crop default)
  final double rowSpacingM;
  final double plantSpacingM;

  FieldModel({
    required this.id,
    required this.name,
    required this.plotNameForAnalysis,
    required this.center,
    required this.soilData,
    required this.crop,
    this.cropVariety,
    this.plantationDate,
    this.irrigationType,
    required this.area,
    required this.stage,
    required this.polygon,
    this.rowSpacingM   = 0.0,
    this.plantSpacingM = 0.0,
  });

  FieldModel copyWith({String? name, String? plotNameForAnalysis}) =>
      FieldModel(
    id: id,
    name: name ?? this.name,
    plotNameForAnalysis: plotNameForAnalysis ?? this.plotNameForAnalysis,
    center: center,
    soilData: soilData,
    crop: crop,
    cropVariety: cropVariety,
    plantationDate: plantationDate,
    irrigationType: irrigationType,
    area: area,
    stage: stage,
    polygon: polygon,
    rowSpacingM:   rowSpacingM,
    plantSpacingM: plantSpacingM,
  );

  FieldModel copyWithSoilData(SoilData newSoilData) => FieldModel(
    id: id,
    name: name,
    plotNameForAnalysis: plotNameForAnalysis,
    center: center,
    soilData: newSoilData,
    crop: crop,
    cropVariety: cropVariety,
    plantationDate: plantationDate,
    irrigationType: irrigationType,
    area: area,
    stage: stage,
    polygon: polygon,
    rowSpacingM:   rowSpacingM,
    plantSpacingM: plantSpacingM,
  );
}

class AlertModel {
  final String id;
  final String fieldId;
  final String fieldName;
  final String type;      // pest | water | soil | growth | weather | harvest | market
  final String message;
  final String time;
  final String severity;  // low | medium | high
  final double? hotspotLat;  // zoom-to point on polygon
  final double? hotspotLng;
  final double? zoomLevel;   // how far to zoom in
  final String? tileUrl;     // layer tile for context
  final String? panelTarget; // which analysis panel to open

  const AlertModel({
    required this.id,
    required this.fieldId,
    this.fieldName = '',
    required this.type,
    required this.message,
    required this.time,
    required this.severity,
    this.hotspotLat,
    this.hotspotLng,
    this.zoomLevel,
    this.tileUrl,
    this.panelTarget,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'fieldId': fieldId, 'fieldName': fieldName,
    'type': type, 'message': message, 'time': time, 'severity': severity,
    'hotspotLat': hotspotLat, 'hotspotLng': hotspotLng, 'zoomLevel': zoomLevel,
    'tileUrl': tileUrl, 'panelTarget': panelTarget,
  };

  factory AlertModel.fromJson(Map<String, dynamic> j) => AlertModel(
    id: j['id'] ?? '', fieldId: j['fieldId'] ?? '',
    fieldName: j['fieldName'] ?? '',
    type: j['type'] ?? '', message: j['message'] ?? '',
    time: j['time'] ?? '', severity: j['severity'] ?? 'low',
    hotspotLat: (j['hotspotLat'] as num?)?.toDouble(),
    hotspotLng: (j['hotspotLng'] as num?)?.toDouble(),
    zoomLevel: (j['zoomLevel'] as num?)?.toDouble(),
    tileUrl: j['tileUrl'], panelTarget: j['panelTarget'],
  );
}

enum ActivePanel { none, insights, soil, soilMoisture, waterUptake, pestRisk, chat, scan, lands, market, grapeCount }

final defaultField = FieldModel(
  id: 'field-1',
  name: 'North Wheat Field',
  plotNameForAnalysis: 'North Wheat Field',
  center: [20.5937, 78.9629],
  polygon: [
    [20.5960, 78.9600],
    [20.5960, 78.9660],
    [20.5910, 78.9660],
    [20.5910, 78.9600],
    [20.5960, 78.9600],
  ],
  soilData: MockData.soilData,
  crop: 'Wheat',
  cropVariety: 'Kalyansona',
  plantationDate: '2026-03-04',
  irrigationType: 'Drip Irrigation',
  area: '12.5 Acres',
  stage: 'Tillering (40%)',
);

final defaultAlerts = [
  const AlertModel(id: '1', fieldId: 'field-1', type: 'pest', message: 'Aphid risk high in Zone 3', time: '10m ago', severity: 'high'),
  const AlertModel(id: '2', fieldId: 'field-1', type: 'irrigation', message: 'Soil moisture low (32%)', time: '1h ago', severity: 'medium'),
  const AlertModel(id: '3', fieldId: 'field-1', type: 'weather', message: 'Light rain expected at 4 PM', time: '2h ago', severity: 'low'),
];
