import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_env.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  SOIL MOISTURE API  — GET /soil-moisture/{plot_name}
//  Returns a 7-day stack from the SAR Index Mapping Railway API.
// ═══════════════════════════════════════════════════════════════════════════

class SoilMoistureApi {
  static String get baseUrl => AppEnv.plotLayerBaseUrl;

  /// Fetches soil moisture stack for [plotName].
  /// Endpoint: GET {baseUrl}/soil-moisture/{plotName}
  static Future<SoilMoistureResult> fetch(String plotName) async {
    final uri = Uri.parse('$baseUrl/soil-moisture/$plotName');
    late http.Response r;
    try {
      r = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw SoilMoistureApiException('Network error: $e');
    }
    if (r.statusCode != 200) {
      throw SoilMoistureApiException(
          'HTTP ${r.statusCode}: ${r.body.length > 200 ? r.body.substring(0, 200) : r.body}');
    }
    final decoded = jsonDecode(r.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SoilMoistureApiException('Invalid JSON — expected object');
    }
    return SoilMoistureResult.fromJson(decoded);
  }
}

class SoilMoistureApiException implements Exception {
  final String message;
  const SoilMoistureApiException(this.message);
  @override
  String toString() => message;
}

/// One day entry in the soil moisture stack.
class SoilMoistureDay {
  final String day;          // "2026-03-30"
  final double soilMoisture; // percentage 0–100
  final double rainfallMm;   // mm yesterday
  final double etMeanMm;     // evapotranspiration mm yesterday

  const SoilMoistureDay({
    required this.day,
    required this.soilMoisture,
    required this.rainfallMm,
    required this.etMeanMm,
  });

  factory SoilMoistureDay.fromJson(Map<String, dynamic> j) => SoilMoistureDay(
    day:           (j['day'] as String?) ?? '',
    soilMoisture:  (j['soil_moisture'] as num?)?.toDouble() ?? 0.0,
    rainfallMm:    (j['rainfall_mm_yesterday'] as num?)?.toDouble() ?? 0.0,
    etMeanMm:      (j['et_mean_mm_yesterday'] as num?)?.toDouble() ?? 0.0,
  );

  /// Short label for X-axis: "30/3"
  String get shortLabel {
    final parts = day.split('-');
    if (parts.length < 3) return day;
    return '${parts[2]}/${parts[1]}';
  }
}

/// Full API response.
class SoilMoistureResult {
  final String plotName;
  final double latitude;
  final double longitude;
  final List<SoilMoistureDay> stack;

  const SoilMoistureResult({
    required this.plotName,
    required this.latitude,
    required this.longitude,
    required this.stack,
  });

  factory SoilMoistureResult.fromJson(Map<String, dynamic> j) {
    final rawStack = j['soil_moisture_stack'];
    final stack = (rawStack is List)
        ? rawStack
            .whereType<Map<String, dynamic>>()
            .map(SoilMoistureDay.fromJson)
            .toList()
        : <SoilMoistureDay>[];
    return SoilMoistureResult(
      plotName:  (j['plot_name'] as String?) ?? '',
      latitude:  (j['latitude']  as num?)?.toDouble() ?? 0.0,
      longitude: (j['longitude'] as num?)?.toDouble() ?? 0.0,
      stack:     stack,
    );
  }

  double get avgMoisture =>
      stack.isEmpty ? 0.0 : stack.map((d) => d.soilMoisture).reduce((a, b) => a + b) / stack.length;
}

/// Railway CropEye analysis APIs → GeoJSON FeatureCollection with `tile_url`
/// on the first feature's properties.
class PlotLayerApi {
  static String get baseUrl => AppEnv.plotLayerBaseUrl;

  static Future<PlotLayerResponse> fetchGrowth(String plotName) =>
      _fetch('/analyze_Growth', {'plot_name': plotName});

  static Future<PlotLayerResponse> fetchWater(String plotName) =>
      _fetch('/wateruptake', {'plot_name': plotName});

  static Future<PlotLayerResponse> fetchSoil(
          String plotName, String endDate) =>
      _fetch('/SoilMoisture', {'plot_name': plotName, 'end_date': endDate});

  static Future<PlotLayerResponse> fetchPest(
          String plotName, String endDate) =>
      _fetch('/pest-detection', {'plot_name': plotName, 'end_date': endDate});

  static const _acceptJson = {'Accept': 'application/json'};

  /// FastAPI exposes `plot_name` / `end_date` as **query** parameters. Requests
  /// must use `?plot_name=…` (and `end_date` when required), not JSON body only.
  static Future<PlotLayerResponse> _fetch(
    String path,
    Map<String, String> fields,
  ) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: fields);

    http.Response r = await http
        .get(uri, headers: _acceptJson)
        .timeout(const Duration(seconds: 45));

    if (r.statusCode == 405) {
      r = await http
          .post(uri, headers: _acceptJson)
          .timeout(const Duration(seconds: 45));
    }

    if (r.statusCode != 200) {
      throw PlotLayerApiException(
          'HTTP ${r.statusCode}: ${r.body.length > 200 ? r.body.substring(0, 200) : r.body}');
    }
    final decoded = jsonDecode(r.body);
    if (decoded is! Map<String, dynamic>) {
      throw const PlotLayerApiException('Invalid JSON (expected object)');
    }
    return PlotLayerResponse.fromJson(decoded);
  }
}

class PlotLayerApiException implements Exception {
  final String message;
  const PlotLayerApiException(this.message);

  @override
  String toString() => message;
}

class PlotLayerResponse {
  final String? tileUrl;
  final Map<String, dynamic>? pixelSummary;
  final Map<String, dynamic> raw;

  PlotLayerResponse({
    required this.tileUrl,
    required this.pixelSummary,
    required this.raw,
  });

  factory PlotLayerResponse.fromJson(Map<String, dynamic> json) {
    final ps = json['pixel_summary'];
    String? tile;

    final feats = json['features'];
    if (feats is List && feats.isNotEmpty) {
      final f0 = feats.first;
      if (f0 is Map<String, dynamic>) {
        final props = f0['properties'];
        if (props is Map<String, dynamic>) {
          final u = props['tile_url'];
          if (u is String && u.isNotEmpty) tile = u;
        }
      }
    }

    return PlotLayerResponse(
      tileUrl: tile,
      pixelSummary: ps is Map<String, dynamic> ? ps : null,
      raw: json,
    );
  }
}
