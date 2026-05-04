import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Reads configuration loaded via [dotenv.load] in [main].
class AppEnv {
  AppEnv._();

  static String? _trimmed(String key) {
    if (!dotenv.isInitialized) return null;
    final v = dotenv.env[key];
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  static String get openWeatherApiKey => _trimmed('OPENWEATHER_API_KEY') ?? '';

  static String get agmarknetApiKey => _trimmed('AGMARKNET_API_KEY') ?? '';

  static String get geminiApiKey => _trimmed('GEMINI_API_KEY') ?? '';

  static const _defaultApi =
      'https://cropeye-mobilebackend.onrender.com';
  static const _defaultPlotLayer =
      'https://cropeyeappapis.up.railway.app';
  static const _defaultScanner =
      'https://planeteyefarm12-fruit-grape-counter.hf.space';

  static String get apiBaseUrl => _trimmed('API_BASE_URL') ?? _defaultApi;

  static String get chatbotUrl =>
      _trimmed('CHATBOT_URL') ?? 'http://192.168.42.58:8001';

  static String get soilParamApiUrl =>
      _trimmed('SOIL_PARAM_API_URL') ?? 'http://192.168.42.132:1000';

  static String get faceAuthUrl =>
      _trimmed('FACE_AUTH_URL') ?? 'http://192.168.42.58:5000';

  static String get plotLayerBaseUrl =>
      _trimmed('PLOT_LAYER_BASE_URL') ?? _defaultPlotLayer;

  static String get scannerApiBase =>
      _trimmed('HF_SCANNER_BASE_URL') ?? _defaultScanner;

  static String geminiGenerateContentUrl(
      {String model = 'gemini-2.5-flash'}) {
    final key = geminiApiKey;
    return 'https://generativelanguage.googleapis.com/v1beta/models/'
        '$model:generateContent?key=${Uri.encodeQueryComponent(key)}';
  }
}
