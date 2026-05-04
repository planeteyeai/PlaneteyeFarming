import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_env.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  SOIL PARAMETER API  —  Soil Parameter Analysis API with NPK & SAR-Fe
//  Base URL: http://192.168.42.132:1000
//
//  Endpoints used:
//    POST /required-n/{plot_name}?plantation_date=YYYY-MM-DD&end_date=YYYY-MM-DD
//      → soilN, soilP, soilK (Nitrogen, Phosphorus, Potassium in mg/kg)
//
//    POST /analyze-npk/{plot_name}?plantation_date=YYYY-MM-DD&date=YYYY-MM-DD&fe_days_back=30
//      → soil_statistics.phh2o (pH), cation_exchange_capacity (CEC),
//        organic_carbon_stock (OC), potassium, phosphorus
//
//  Moisture is sourced from SoilMoistureApi (existing, Railway endpoint).
// ═══════════════════════════════════════════════════════════════════════════

class SoilParamApi {
  static String get baseUrl => AppEnv.soilParamApiUrl;

  // ── POST /required-n/{plot_name} → N, P, K ─────────────────────────────
  static Future<SoilNpkResult> fetchNpk({
    required String plotName,
    String? plantationDate,
    String? endDate,
  }) async {
    final today = DateTime.now().toString().split(' ')[0];
    final pDate = plantationDate ?? today;
    final eDate = endDate ?? today;

    final uri = Uri.parse(
      '$baseUrl/required-n/$plotName'
      '?plantation_date=$pDate&end_date=$eDate',
    );

    final r = await http.post(uri,
        headers: const {'accept': 'application/json'})
        .timeout(const Duration(seconds: 30));

    if (r.statusCode != 200) {
      throw SoilParamException('HTTP ${r.statusCode}: ${r.body.length > 200 ? r.body.substring(0, 200) : r.body}');
    }
    final j = jsonDecode(r.body);
    if (j is! Map<String, dynamic>) throw const SoilParamException('Invalid JSON');
    return SoilNpkResult.fromJson(j);
  }

  // ── POST /analyze-npk/{plot_name} → pH, CEC, OC ───────────────────────
  static Future<SoilAnalysisResult> fetchAnalysis({
    required String plotName,
    String? plantationDate,
    String? date,
    int feDaysBack = 30,
  }) async {
    final today = DateTime.now().toString().split(' ')[0];
    final pDate = plantationDate ?? '2025-01-01';
    final aDate = date ?? today;

    final uri = Uri.parse(
      '$baseUrl/analyze-npk/$plotName'
      '?plantation_date=$pDate&date=$aDate&fe_days_back=$feDaysBack',
    );

    final r = await http.post(uri,
        headers: const {'accept': 'application/json'})
        .timeout(const Duration(seconds: 45));

    if (r.statusCode != 200) {
      throw SoilParamException('HTTP ${r.statusCode}: ${r.body.length > 200 ? r.body.substring(0, 200) : r.body}');
    }
    final j = jsonDecode(r.body);
    if (j is! Map<String, dynamic>) throw const SoilParamException('Invalid JSON');
    return SoilAnalysisResult.fromJson(j);
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  RESULT MODELS
// ─────────────────────────────────────────────────────────────────────────

/// From POST /required-n/{plot_name}
class SoilNpkResult {
  final double soilN;  // Nitrogen mg/kg
  final double soilP;  // Phosphorus mg/kg
  final double soilK;  // Potassium mg/kg
  final double gndvi;
  final int    daysSincePlantation;

  const SoilNpkResult({
    required this.soilN,
    required this.soilP,
    required this.soilK,
    required this.gndvi,
    required this.daysSincePlantation,
  });

  factory SoilNpkResult.fromJson(Map<String, dynamic> j) => SoilNpkResult(
    soilN:                (j['soilN']  as num?)?.toDouble() ?? 0.0,
    soilP:                (j['soilP']  as num?)?.toDouble() ?? 0.0,
    soilK:                (j['soilK']  as num?)?.toDouble() ?? 0.0,
    gndvi:                (j['gndvi']  as num?)?.toDouble() ?? 0.0,
    daysSincePlantation:  (j['days_since_plantation'] as num?)?.toInt() ?? 0,
  );
}

/// From POST /analyze-npk/{plot_name}
class SoilAnalysisResult {
  final double ph;   // phh2o
  final double cec;  // cation_exchange_capacity
  final double oc;   // organic_carbon_stock
  final double potassium;
  final double phosphorus;
  final String plotName;
  final String date;

  const SoilAnalysisResult({
    required this.ph,
    required this.cec,
    required this.oc,
    required this.potassium,
    required this.phosphorus,
    required this.plotName,
    required this.date,
  });

  factory SoilAnalysisResult.fromJson(Map<String, dynamic> j) {
    final ss = j['soil_statistics'] as Map<String, dynamic>? ?? j;
    return SoilAnalysisResult(
      ph:          (ss['phh2o']  as num?)?.toDouble()
                ?? (j['phh2o']  as num?)?.toDouble() ?? 7.0,
      cec:         (ss['cation_exchange_capacity']  as num?)?.toDouble()
                ?? (j['cation_exchange_capacity']   as num?)?.toDouble() ?? 0.0,
      oc:          (ss['organic_carbon_stock']       as num?)?.toDouble()
                ?? (j['organic_carbon_stock']        as num?)?.toDouble() ?? 0.0,
      potassium:   (j['potassium']   as num?)?.toDouble() ?? 0.0,
      phosphorus:  (j['phosphorus']  as num?)?.toDouble() ?? 0.0,
      plotName:    (j['plot_name']   as String?) ?? '',
      date:        (j['date']        as String?) ?? '',
    );
  }
}

class SoilParamException implements Exception {
  final String message;
  const SoilParamException(this.message);
  @override String toString() => message;
}
