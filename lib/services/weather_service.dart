import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/app_env.dart';

/// Weather condition categories for UI rendering
enum WeatherCondition {
  clearDay,
  clearNight,
  partlyCloudyDay,
  partlyCloudyNight,
  cloudy,
  rain,
  thunderstorm,
  snow,
  foggy,
}

class WeatherData {
  final double tempC;
  final double feelsLikeC;
  final int humidity;
  final double windSpeedMs;
  final double windDeg;
  final String description;
  final String cityName;
  final int conditionCode;  // OWM code
  final bool isDay;
  final double cloudCoverPct;
  final double? rainMmLastHour;

  const WeatherData({
    required this.tempC,
    required this.feelsLikeC,
    required this.humidity,
    required this.windSpeedMs,
    required this.windDeg,
    required this.description,
    required this.cityName,
    required this.conditionCode,
    required this.isDay,
    required this.cloudCoverPct,
    this.rainMmLastHour,
  });

  /// Derive a high-level condition for animation
  WeatherCondition get condition {
    // Thunderstorm
    if (conditionCode >= 200 && conditionCode < 300) {
      return WeatherCondition.thunderstorm;
    }
    // Rain / drizzle
    if ((conditionCode >= 300 && conditionCode < 600)) {
      return WeatherCondition.rain;
    }
    // Snow
    if (conditionCode >= 600 && conditionCode < 700) {
      return WeatherCondition.snow;
    }
    // Fog / mist
    if (conditionCode >= 700 && conditionCode < 800) {
      return WeatherCondition.foggy;
    }
    // Clear sky
    if (conditionCode == 800) {
      // Windy clear?
      
      return isDay ? WeatherCondition.clearDay : WeatherCondition.clearNight;
    }
    // Few clouds
    if (conditionCode == 801 || conditionCode == 802) {
      return isDay
          ? WeatherCondition.partlyCloudyDay
          : WeatherCondition.partlyCloudyNight;
    }
    // Heavy clouds
    return WeatherCondition.cloudy;
  }

  String get tempLabel => '${tempC.round()}°C';
  String get windLabel => '${windSpeedMs.toStringAsFixed(1)} m/s';
  String get humidityLabel => '$humidity%';

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final weather = json['weather'][0];
    final main = json['main'];
    final wind = json['wind'];
    final clouds = json['clouds'];
    final sys = json['sys'];
    final rain = json['rain'];

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sunrise = sys['sunrise'] as int;
    final sunset = sys['sunset'] as int;
    final isDay = now >= sunrise && now < sunset;

    return WeatherData(
      tempC: (main['temp'] as num).toDouble() - 273.15,
      feelsLikeC: (main['feels_like'] as num).toDouble() - 273.15,
      humidity: main['humidity'] as int,
      windSpeedMs: (wind['speed'] as num).toDouble(),
      windDeg: ((wind['deg'] ?? 0) as num).toDouble(),
      description: weather['description'] as String,
      cityName: json['name'] as String,
      conditionCode: weather['id'] as int,
      isDay: isDay,
      cloudCoverPct: ((clouds['all'] ?? 0) as num).toDouble(),
      rainMmLastHour: rain != null ? (rain['1h'] as num?)?.toDouble() : null,
    );
  }
}

class WeatherService {
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';

  /// Returns a realistic mock based on current time (for dev/no-key scenario)
  static WeatherData mockForNow({double windDeg = 225}) {
    final h = DateTime.now().hour;
    final isDay = h >= 6 && h < 19;
    return WeatherData(
      tempC: isDay ? 28.5 : 21.2,
      feelsLikeC: isDay ? 31.0 : 20.0,
      humidity: 65,
      windSpeedMs: 6.8,
      windDeg: windDeg,
      description: isDay ? 'partly cloudy' : 'clear sky',
      cityName: 'Farm',
      conditionCode: isDay ? 802 : 800,
      isDay: isDay,
      cloudCoverPct: isDay ? 45 : 5,
      rainMmLastHour: null,
    );
  }

  static Future<WeatherData?> fetchByCoords(double lat, double lon) async {
    final apiKey = AppEnv.openWeatherApiKey;
    if (apiKey.isEmpty) {
      return mockForNow(windDeg: ((lat + lon) * 37) % 360);
    }
    try {
      final uri = Uri.parse(
          '$_baseUrl/weather?lat=$lat&lon=$lon&appid=$apiKey');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return WeatherData.fromJson(json.decode(res.body));
      }
      return mockForNow();
    } catch (_) {
      return mockForNow();
    }
  }
}
