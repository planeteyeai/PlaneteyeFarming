import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_env.dart';

class ApiService {
  static String get baseUrl => AppEnv.apiBaseUrl;

  static const _headers = {
    'Content-Type': 'application/json',
    'Accept':       'application/json',
  };

  static String? accessToken;
  static String? refreshToken;
  static int?    farmerId;
  static Map<String, dynamic> lastAuthResponse = {};
  static String? farmDistrict;
  static String? farmState;

  // ─────────────────────────────────────────────────────────────────
  // PERSISTENCE
  // ─────────────────────────────────────────────────────────────────
  static Future<void> saveFarmerId(int id) async {
    farmerId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('farmer_id', id);
    dev.log('saveFarmerId → $id');
  }

  static Future<void> saveFarmLocation({
    required String district,
    required String state,
  }) async {
    farmDistrict = district.trim();
    farmState    = state.trim();
    final prefs  = await SharedPreferences.getInstance();
    await prefs.setString('farm_district', district.trim());
    await prefs.setString('farm_state',    state.trim());
  }

  static Future<void> restoreFarmerId() async {
    if (farmerId != null) return;
    final prefs  = await SharedPreferences.getInstance();
    final stored = prefs.getInt('farmer_id');
    if (stored != null && stored > 0) {
      farmerId = stored;
      dev.log('restoreFarmerId → $stored');
    }
    farmDistrict = prefs.getString('farm_district');
    farmState    = prefs.getString('farm_state');
  }

  static Future<void> clearFarmerId() async {
    farmerId     = null;
    farmDistrict = null;
    farmState    = null;
    final prefs  = await SharedPreferences.getInstance();
    await prefs.remove('farmer_id');
    await prefs.remove('farm_district');
    await prefs.remove('farm_state');
  }

  static Future<void> saveTokens() async {
    if (accessToken == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token',  accessToken!);
    if (refreshToken != null)
      await prefs.setString('refresh_token', refreshToken!);
  }

  static Future<bool> restoreSession() async {
    final prefs   = await SharedPreferences.getInstance();
    final access  = prefs.getString('access_token');
    final refresh = prefs.getString('refresh_token');
    if (access == null || access.isEmpty) return false;
    accessToken  = access;
    refreshToken = refresh;
    await restoreFarmerId();
    dev.log('restoreSession: farmerId=$farmerId');
    return true;
  }

  static Future<void> clearTokens() async {
    accessToken  = null;
    refreshToken = null;
    final prefs  = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
  }

  // ─────────────────────────────────────────────────────────────────
  // PLOT CACHE
  // ─────────────────────────────────────────────────────────────────
  static const _kPlotsCache = 'plots_cache_json';

  static Future<void> savePlotsCache(List<Map<String, dynamic>> plots) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPlotsCache, jsonEncode(plots));
    } catch (e) { dev.log('savePlotsCache error: $e'); }
  }

  static Future<List<Map<String, dynamic>>> loadPlotsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_kPlotsCache);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is List)
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) { dev.log('loadPlotsCache error: $e'); }
    return [];
  }

  static Future<void> clearPlotsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPlotsCache);
    } catch (e) { dev.log('clearPlotsCache error: $e'); }
  }

  // ─────────────────────────────────────────────────────────────────
  // ALERT CACHE  — persisted so alerts load instantly on next login
  // ─────────────────────────────────────────────────────────────────
  static const _kAlertsCache = 'alerts_cache_json';

  static Future<void> saveAlertsCache(List<Map<String, dynamic>> alerts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAlertsCache, jsonEncode(alerts));
    } catch (e) { dev.log('saveAlertsCache error: $e'); }
  }

  static Future<List<Map<String, dynamic>>> loadAlertsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kAlertsCache);
      if (raw == null) return [];
      final list = jsonDecode(raw);
      return (list as List).cast<Map<String, dynamic>>();
    } catch (e) { dev.log('loadAlertsCache error: $e'); return []; }
  }

  static Future<void> clearAlertsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAlertsCache);
    } catch (e) { dev.log('clearAlertsCache error: $e'); }
  }


  static Map<String, String> get _authHeaders => {
    ..._headers,
    if (accessToken != null) 'Authorization': 'Bearer $accessToken',
  };

  static Future<http.Response> _post(String url, Map body,
      {bool auth = false}) async {
    final hdrs = auth ? _authHeaders : _headers;
    dev.log('► POST $url');
    var r = await http.post(Uri.parse(url),
        headers: hdrs, body: jsonEncode(body));
    dev.log('◄ ${r.statusCode} $url');
    if (r.statusCode == 401 && auth &&
        !url.contains('token/refresh') && !url.contains('login')) {
      try {
        await refreshAccessToken();
        r = await http.post(Uri.parse(url),
            headers: _authHeaders, body: jsonEncode(body));
        dev.log('◄ ${r.statusCode} $url (after refresh)');
      } catch (e) { dev.log('auto-refresh failed: $e'); }
    }
    return r;
  }

  static Future<http.Response> _get(String url) async {
    dev.log('► GET $url');
    var r = await http.get(Uri.parse(url), headers: _authHeaders);
    dev.log('◄ ${r.statusCode} $url');
    if (r.statusCode == 401 && !url.contains('token/refresh')) {
      try {
        await refreshAccessToken();
        r = await http.get(Uri.parse(url), headers: _authHeaders);
        dev.log('◄ ${r.statusCode} $url (after refresh)');
      } catch (e) { dev.log('auto-refresh failed: $e'); }
    }
    return r;
  }

  // ─────────────────────────────────────────────────────────────────
  // LOGIN  POST /api/farmers/login/
  // ─────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> login({
    required String phoneNumber,
    required String password,
  }) async {
    final r = await _post(
      '$baseUrl/api/farmers/login/',
      {'phone_number': phoneNumber, 'password': password},
    );
    if (r.statusCode == 200 || r.statusCode == 201) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      accessToken      = data['access']  as String?;
      refreshToken     = data['refresh'] as String?;
      lastAuthResponse = data;
      _extractFarmerId(data);
      await saveTokens();
      dev.log('LOGIN → farmerId=$farmerId');
      return data;
    }
    final err = _safeJson(r.body);
    throw Exception(err['error'] ?? err['detail'] ?? 'Login failed (${r.statusCode})');
  }

  // ─────────────────────────────────────────────────────────────────
  // LOGOUT  POST /api/farmers/logout/
  // ─────────────────────────────────────────────────────────────────
  static Future<void> logout() async {
    try {
      if (refreshToken != null) {
        await _post(
          '$baseUrl/api/farmers/logout/',
          {'refresh': refreshToken},
          auth: true,
        );
      }
    } catch (_) {}
    accessToken      = null;
    refreshToken     = null;
    lastAuthResponse = {};
    await clearFarmerId();
    await clearTokens();
    await clearPlotsCache();
  }

  // ─────────────────────────────────────────────────────────────────
  // GOOGLE SIGN-IN  POST /api/farmers/auth/google/
  // ─────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> googleSignIn({
    required String idToken,
  }) async {
    final r = await _post(
      '$baseUrl/api/farmers/auth/google/',
      {'id_token': idToken},
    );
    if (r.statusCode == 200 || r.statusCode == 201) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      accessToken      = data['access']  as String?;
      refreshToken     = data['refresh'] as String?;
      lastAuthResponse = data;
      _extractFarmerId(data);
      await saveTokens();
      return data;
    }
    final err = _safeJson(r.body);
    throw Exception(err['error'] ?? err['detail'] ?? 'Google sign-in failed');
  }

  // ─────────────────────────────────────────────────────────────────
  // TOKEN REFRESH  POST /api/farmers/token/refresh/
  // ─────────────────────────────────────────────────────────────────
  static Future<String> refreshAccessToken() async {
    if (refreshToken == null) throw Exception('No refresh token');
    final r = await http.post(
      Uri.parse('$baseUrl/api/farmers/token/refresh/'),
      headers: _headers,
      body: jsonEncode({'refresh': refreshToken}),
    );
    dev.log('◄ ${r.statusCode} token/refresh');
    if (r.statusCode == 200) {
      accessToken = (jsonDecode(r.body) as Map)['access'] as String;
      await saveTokens();
      return accessToken!;
    }
    throw Exception('Token refresh failed: ${r.statusCode}');
  }

  // ─────────────────────────────────────────────────────────────────
  // REGISTER  POST /api/farmers/register/
  // ─────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> registerFarmer({
    required String firstName,   required String lastName,
    required String username,    required String email,
    required String password,    required String phoneNumber,
    required String village,     required String taluka,
    required String district,    required String state,
    required String cropType,    required String cropVariety,
    required String plantationDate, required String irrigationType,
  }) async {
    final r = await _post('$baseUrl/api/farmers/register/', {
      'registration': {
        'personal_info': {
          'username':      username,
          'password':      password,
          'first_name':    firstName,
          'last_name':     lastName,
          'email_address': email,
          'phone_number':  phoneNumber,
          'village':       village,
          'taluka':        taluka,
          'district':      district,
          'state':         state,
        },
        'location_info': {
          'village':  village,
          'taluka':   taluka,
          'district': district,
          'state':    state,
        },
        'crop_details': {
          'crop_type':       cropType,
          'crop_variety':    cropVariety,
          'plantation_date': plantationDate,
          'irrigation_type': irrigationType,
        },
      }
    });

    if (r.statusCode == 200 || r.statusCode == 201) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      lastAuthResponse = data;
      if (data['access']  != null) accessToken  = data['access']  as String?;
      if (data['refresh'] != null) refreshToken = data['refresh'] as String?;
      _extractFarmerId(data);
      if (accessToken != null) await saveTokens();
      dev.log('REGISTER → farmerId=$farmerId');
      return data;
    }
    throw Exception('Registration failed (${r.statusCode}): ${r.body}');
  }

  // ─────────────────────────────────────────────────────────────────
  // FORGOT PASSWORD (Email Link)  POST /api/farmers/forgot-password/
  // ─────────────────────────────────────────────────────────────────
  static Future<String> forgotPassword({required String email}) async {
    final r = await _post(
      '$baseUrl/api/farmers/forgot-password/',
      {'email': email},
    );
    if (r.statusCode == 200 || r.statusCode == 201) {
      final data = _safeJson(r.body);
      return data['message']?.toString() ??
          'If an account exists with this email, a reset link has been sent.';
    }
    final err = _safeJson(r.body);
    throw Exception(err['detail'] ?? err['message'] ?? 'Request failed (${r.statusCode})');
  }

  // ─────────────────────────────────────────────────────────────────
  // FORGOT PASSWORD OTP  POST /api/farmers/forgot-password/otp/
  // ─────────────────────────────────────────────────────────────────
  static Future<String> forgotPasswordOtp({required String email}) async {
    final r = await _post(
      '$baseUrl/api/farmers/forgot-password/otp/',
      {'email': email},
    );
    if (r.statusCode == 200 || r.statusCode == 201) {
      final data = _safeJson(r.body);
      return data['detail']?.toString() ??
          'A verification code has been sent to your email.';
    }
    final err = _safeJson(r.body);
    throw Exception(err['detail'] ?? err['message'] ?? 'OTP request failed (${r.statusCode})');
  }

  // ─────────────────────────────────────────────────────────────────
  // VERIFY OTP  POST /api/farmers/verify-password-otp/
  // ─────────────────────────────────────────────────────────────────
  static Future<String> verifyPasswordOtp({
    required String email,
    required String otp,
  }) async {
    final r = await _post(
      '$baseUrl/api/farmers/verify-password-otp/',
      {'email': email, 'otp': otp},
    );
    if (r.statusCode == 200 || r.statusCode == 201) {
      final data = _safeJson(r.body);
      return data['detail']?.toString() ?? 'Code verified.';
    }
    final err = _safeJson(r.body);
    throw Exception(err['detail'] ?? err['message'] ?? 'OTP verification failed (${r.statusCode})');
  }

  // ─────────────────────────────────────────────────────────────────
  // RESET PASSWORD (Token)  POST /api/farmers/reset-password/
  // ─────────────────────────────────────────────────────────────────
  static Future<void> resetPassword({
    required String token,
    required String newPassword,
    String? uid,
  }) async {
    final body = <String, dynamic>{
      'token':        token,
      'new_password': newPassword,
    };
    if (uid != null) body['uid'] = uid;

    final r = await _post('$baseUrl/api/farmers/reset-password/', body);
    if (r.statusCode == 200 || r.statusCode == 201) return;
    final err = _safeJson(r.body);
    throw Exception(err['detail'] ?? err['message'] ??
        'Password reset failed (${r.statusCode})');
  }

  // ─────────────────────────────────────────────────────────────────
  // RESET PASSWORD AFTER OTP  POST /api/farmers/reset-password/otp/
  // ─────────────────────────────────────────────────────────────────
  static Future<void> resetPasswordOtp({
    required String email,
    required String newPassword,
  }) async {
    final r = await _post(
      '$baseUrl/api/farmers/reset-password/otp/',
      {'email': email, 'new_password': newPassword},
    );
    if (r.statusCode == 200 || r.statusCode == 201) return;
    final err = _safeJson(r.body);
    throw Exception(err['detail'] ?? err['message'] ??
        'Password reset failed (${r.statusCode})');
  }

  // ─────────────────────────────────────────────────────────────────
  // CREATE PLOT  POST /api/farmers/plots/
  // ─────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> addPlot({
    required int    farmerId,
    required String name,
    required List<double> center,        // [lat, lng]
    required List<List<double>> polygon, // [[lat,lng], ...]
  }) async {
    // GeoJSON uses [lng, lat] order
    final locationGeoJson = {
      'type': 'Point',
      'coordinates': [center[1], center[0]],
    };

    List<List<double>> ring = polygon.map((p) => [p[1], p[0]]).toList();
    if (ring.isNotEmpty &&
        (ring.first[0] != ring.last[0] || ring.first[1] != ring.last[1])) {
      ring = [...ring, ring.first];
    }
    final boundaryGeoJson = {
      'type': 'Polygon',
      'coordinates': [ring],
    };

    final body = {
      'farmer_id': farmerId,
      'name':      name,
      'location':  locationGeoJson,
      'boundary':  boundaryGeoJson,
    };

    dev.log('► ADD PLOT  body=${jsonEncode(body)}');
    final r = await http.post(
      Uri.parse('$baseUrl/api/farmers/plots/'),
      headers: _authHeaders,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 20));

    dev.log('◄ ADD PLOT ${r.statusCode}  ${r.body}');

    if (r.statusCode == 200 || r.statusCode == 201) {
      return _safeJson(r.body);
    }
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw Exception('Auth error — please login again');
    }
    throw Exception('addPlot failed (${r.statusCode}): ${r.body}');
  }

  // ─────────────────────────────────────────────────────────────────
  // LIST PLOTS  GET /api/farmers/plots/list/
  // The server uses JWT auth to return only the logged-in farmer's plots.
  // We trust the server's filtering — no client-side filter needed.
  // ─────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getPlots() async {
    if (accessToken == null) return [];

    final endpoints = [
      '$baseUrl/api/farmers/plots/list/',
      '$baseUrl/api/farmers/plots/',
    ];

    for (final url in endpoints) {
      try {
        final r = await _get(url);
        dev.log('getPlots $url → ${r.statusCode}');
        dev.log('getPlots body: ${r.body.length > 400 ? r.body.substring(0, 400) : r.body}');

        if (r.statusCode == 200) {
          final plots = _parseList(r.body);
          dev.log('getPlots: ${plots.length} plots returned by server');

          if (plots.isEmpty) continue;

          // The JWT-authenticated endpoint already returns only this
          // farmer's plots — trust it directly.
          // Only apply client-side filter as a secondary sanity check
          // when we have a farmerId AND the response contains farmer fields
          // that clearly belong to a different farmer.
          if (farmerId != null) {
            // Check if ANY plot has a farmer field that looks like ours
            final hasMatchingFarmer = plots.any((p) {
              final fid = p['farmer_id'] ?? p['farmer'];
              if (fid is int)    return fid == farmerId;
              if (fid is String) return int.tryParse(fid) == farmerId;
              if (fid is Map)    return fid['id'] == farmerId;
              // No farmer field present — trust server auth filtering
              return true;
            });

            if (hasMatchingFarmer) {
              // Filter to only this farmer's plots
              final mine = plots.where((p) {
                final fid = p['farmer_id'] ?? p['farmer'];
                if (fid == null) return true; // no farmer field = trust server
                if (fid is int)    return fid == farmerId;
                if (fid is String) return int.tryParse(fid) == farmerId;
                if (fid is Map)    return fid['id'] == farmerId;
                return false;
              }).toList();
              dev.log('getPlots: ${mine.length}/${plots.length} after filter for farmerId=$farmerId');
              return mine;
            }

            // No plots matched our farmerId — could be ID mismatch between
            // user.id (from login) and farmer profile id.
            // In this case trust the server JWT response entirely.
            dev.log('getPlots: farmerId=$farmerId not found in response — trusting server auth');
          }

          return plots;
        }
      } catch (e) {
        dev.log('getPlots $url error: $e');
      }
    }
    return [];
  }

  // ─────────────────────────────────────────────────────────────────
  // DELETE PLOT  DELETE /api/farmers/plots/{pk}/
  // ─────────────────────────────────────────────────────────────────
  static Future<bool> deletePlot(String plotId) async {
    if (accessToken == null) return false;
    final url = '$baseUrl/api/farmers/plots/$plotId/';
    dev.log('► DELETE $url');
    try {
      final r = await http.delete(
        Uri.parse(url),
        headers: _authHeaders,
      ).timeout(const Duration(seconds: 15));
      dev.log('◄ ${r.statusCode} DELETE $url');
      // 204 No Content = success for DELETE
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (e) {
      dev.log('deletePlot error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // RENAME PLOT  PUT /api/farmers/plots/{pk}/
  // Server returns 405 on PATCH and GET — only PUT is allowed.
  // We build the full required body from the local FieldModel so no
  // prior GET is needed.
  // Required fields: farmer_id, name, location (GeoJSON Point), boundary (GeoJSON Polygon)
  // ─────────────────────────────────────────────────────────────────
  static Future<bool> renamePlot(
    String plotId,
    String newName, {
    required List<double> center,        // [lat, lng]
    required List<List<double>> polygon, // [[lat, lng], ...]
  }) async {
    if (accessToken == null) {
      dev.log('renamePlot: no accessToken — aborting');
      return false;
    }
    if (farmerId == null) {
      dev.log('renamePlot: no farmerId — aborting');
      return false;
    }

    final url = '$baseUrl/api/farmers/plots/$plotId/';

    // Build GeoJSON location (Point) — server expects [lng, lat]
    final locationGeoJson = {
      'type': 'Point',
      'coordinates': [center[1], center[0]],
    };

    // Build GeoJSON boundary (Polygon) — server expects [lng, lat] and closed ring
    List<List<double>> ring = polygon.map((p) => [p[1], p[0]]).toList();
    if (ring.isNotEmpty &&
        (ring.first[0] != ring.last[0] || ring.first[1] != ring.last[1])) {
      ring = [...ring, ring.first];
    }
    final boundaryGeoJson = {
      'type': 'Polygon',
      'coordinates': [ring],
    };

    final body = jsonEncode({
      'farmer_id': farmerId,
      'name':      newName,
      'location':  locationGeoJson,
      'boundary':  boundaryGeoJson,
    });

    dev.log('► PUT $url  body=$body');
    try {
      var r = await http.put(
        Uri.parse(url),
        headers: _authHeaders,
        body: body,
      ).timeout(const Duration(seconds: 15));
      dev.log('◄ ${r.statusCode} PUT $url  resp=${r.body}');

      // Token expired — refresh and retry once
      if (r.statusCode == 401) {
        await refreshAccessToken();
        r = await http.put(
          Uri.parse(url),
          headers: _authHeaders,
          body: body,
        ).timeout(const Duration(seconds: 15));
        dev.log('◄ ${r.statusCode} PUT retry after token refresh');
      }

      if (r.statusCode >= 200 && r.statusCode < 300) return true;
      dev.log('renamePlot failed: ${r.statusCode}  ${r.body}');
      return false;
    } catch (e) {
      dev.log('renamePlot error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // FACE ENROLL  POST /api/farmers/face/enroll/
  // Requires JWT auth (farmer must be logged in).
  // ─────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> faceEnroll({
    required List<double> embedding,
    String? imageBase64,
  }) async {
    if (accessToken == null) throw Exception('Not logged in');
    final body = <String, dynamic>{'embedding': embedding};
    if (imageBase64 != null) body['image_base64'] = imageBase64;

    final r = await http.post(
      Uri.parse('$baseUrl/api/farmers/face/enroll/'),
      headers: _authHeaders,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 25));

    dev.log('◄ ${r.statusCode} faceEnroll');
    if (r.statusCode == 200 || r.statusCode == 201) {
      return jsonDecode(r.body) as Map<String, dynamic>;
    }
    final err = _safeJson(r.body);
    throw Exception(err['detail'] ?? err['error'] ?? 'Enroll failed (${r.statusCode})');
  }

  // ─────────────────────────────────────────────────────────────────
  // FACE VERIFY  POST /api/farmers/face/verify/
  // Requires JWT auth.
  // ─────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> faceVerify({
    required List<double> embedding,
  }) async {
    if (accessToken == null) throw Exception('Not logged in');

    final r = await http.post(
      Uri.parse('$baseUrl/api/farmers/face/verify/'),
      headers: _authHeaders,
      body: jsonEncode({'embedding': embedding}),
    ).timeout(const Duration(seconds: 20));

    dev.log('◄ ${r.statusCode} faceVerify');
    if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    final err = _safeJson(r.body);
    throw Exception(err['detail'] ?? err['error'] ?? 'Verify failed (${r.statusCode})');
  }

  // ─────────────────────────────────────────────────────────────────
  // FACE LOGIN (Phone + Face)  POST /api/farmers/face/login/
  // No auth required.
  // ─────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> faceLogin({
    required String phoneNumber,
    required List<double> embedding,
  }) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/farmers/face/login/'),
      headers: _headers,
      body: jsonEncode({
        'phone_number': phoneNumber,
        'embedding':    embedding,
      }),
    ).timeout(const Duration(seconds: 20));

    dev.log('◄ ${r.statusCode} faceLogin');
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      accessToken  = data['access']  as String?;
      refreshToken = data['refresh'] as String?;
      if (accessToken != null) await saveTokens();
      _extractFarmerId(data);
      return data;
    }
    final err = _safeJson(r.body);
    throw Exception(err['detail'] ?? err['error'] ?? 'Face login failed (${r.statusCode})');
  }

  // ─────────────────────────────────────────────────────────────────
  // FACE IDENTIFY LOGIN (Face Only)  POST /api/farmers/face/login/identify/
  // No auth required — finds best matching profile, returns JWT tokens.
  // ─────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> faceIdentifyLogin({
    required List<double> embedding,
  }) async {
    final r = await http.post(
      Uri.parse('$baseUrl/api/farmers/face/login/identify/'),
      headers: _headers,
      body: jsonEncode({'embedding': embedding}),
    ).timeout(const Duration(seconds: 20));

    dev.log('◄ ${r.statusCode} faceIdentifyLogin');
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      accessToken  = data['access']  as String?;
      refreshToken = data['refresh'] as String?;
      if (accessToken != null) await saveTokens();
      _extractFarmerId(data);
      return data;
    }
    final err = _safeJson(r.body);
    throw Exception(err['detail'] ?? err['error'] ??
        'Face identify login failed (${r.statusCode})');
  }

  // ─────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────
  static List<Map<String, dynamic>> _parseList(String body) {
    try {
      final data = jsonDecode(body);
      if (data is List) return data.cast<Map<String, dynamic>>();
      if (data is Map) {
        for (final key in ['results', 'plots', 'data', 'fields', 'list']) {
          if (data[key] is List)
            return (data[key] as List).cast<Map<String, dynamic>>();
        }
      }
    } catch (_) {}
    return [];
  }

  static void _extractFarmerId(Map<String, dynamic> data) {
    dev.log('_extractFarmerId keys: ${data.keys.toList()}');
    final user   = data['user']   is Map ? data['user']   as Map : null;
    final farmer = data['farmer'] is Map ? data['farmer'] as Map : null;
    if (user   != null) dev.log('  user   keys: ${user.keys.toList()}');
    if (farmer != null) dev.log('  farmer keys: ${farmer.keys.toList()}');

    final candidates = [
      data['farmer_id'],
      farmer?['id'],
      farmer?['farmer_id'],
      user?['farmer_id'],
      user?['id'],
      data['id'],
    ];

    for (final c in candidates) {
      if (c != null && c is! Map && c is! List) {
        final parsed = c is int ? c : int.tryParse(c.toString());
        if (parsed != null && parsed > 0) {
          farmerId = parsed;
          saveFarmerId(parsed);
          dev.log('_extractFarmerId → $farmerId');
          return;
        }
      }
    }

    final rawFarmer = data['farmer'];
    if (rawFarmer is int && rawFarmer > 0) {
      farmerId = rawFarmer;
      saveFarmerId(rawFarmer);
    } else if (rawFarmer is String) {
      final p = int.tryParse(rawFarmer);
      if (p != null && p > 0) {
        farmerId = p;
        saveFarmerId(p);
      }
    }
  }

  static Map<String, dynamic> _safeJson(String body) {
    try { return jsonDecode(body) as Map<String, dynamic>; } catch (_) { return {}; }
  }

  static void diagnoseLoginResponse() {
    dev.log('═══ AUTH RESPONSE ═══');
    dev.log('farmerId=$farmerId  token=${accessToken != null}');
    dev.log('keys=${lastAuthResponse.keys.toList()}');
    dev.log('═════════════════════');
  }
}
