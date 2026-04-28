import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

bool _supabaseInitialized = false;
String? _supabaseStartupError;

const String _supabaseUrlFromDefine = String.fromEnvironment('SUPABASE_URL');
const String _supabaseAnonKeyFromDefine = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
);

String _supabaseUrl = '';
String _supabaseAnonKey = '';

String _normalizeEnvValue(String? value) {
  var normalized = (value ?? '').trim();
  if (normalized.length >= 2) {
    final startsWithDouble = normalized.startsWith('"');
    final endsWithDouble = normalized.endsWith('"');
    final startsWithSingle = normalized.startsWith("'");
    final endsWithSingle = normalized.endsWith("'");
    if ((startsWithDouble && endsWithDouble) ||
        (startsWithSingle && endsWithSingle)) {
      normalized = normalized.substring(1, normalized.length - 1).trim();
    }
  }
  return normalized;
}

bool _isSupabaseSecretKey(String key) {
  return key.startsWith('sb_secret_');
}

Future<void> _loadSupabaseConfig() async {
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Keep startup resilient when .env is missing; dart-define fallback still works.
  }

  _supabaseUrl = _normalizeEnvValue(
    dotenv.env['SUPABASE_URL'] ?? _supabaseUrlFromDefine,
  );
  _supabaseAnonKey = _normalizeEnvValue(
    dotenv.env['SUPABASE_ANON_KEY'] ?? _supabaseAnonKeyFromDefine,
  );
}

bool _supabaseConfigIsValid() {
  return _supabaseUrl.trim().isNotEmpty && _supabaseAnonKey.trim().isNotEmpty;
}

String authUnavailableMessage() {
  if (_supabaseStartupError != null) {
    return _supabaseStartupError!;
  }
  if (!_supabaseConfigIsValid()) {
    return 'Supabase is not configured. Set SUPABASE_URL and SUPABASE_ANON_KEY in .env or pass --dart-define values.';
  }
  return 'Authentication service is unavailable right now.';
}

String _resolveProfileName({required User user, String? preferredName}) {
  final explicitName = preferredName?.trim() ?? '';
  if (explicitName.isNotEmpty) {
    return explicitName;
  }

  final metadata = user.userMetadata ?? const <String, dynamic>{};
  final metadataKeys = <String>['full_name', 'username', 'name'];
  for (final key in metadataKeys) {
    final raw = metadata[key];
    if (raw == null) {
      continue;
    }
    final value = raw.toString().trim();
    if (value.isNotEmpty) {
      return value;
    }
  }

  final email = (user.email ?? '').trim();
  if (email.isNotEmpty) {
    final atIndex = email.indexOf('@');
    if (atIndex > 0) {
      return email.substring(0, atIndex);
    }
    return email;
  }

  return 'Aegis User';
}

Future<void> upsertAuthenticatedUserProfile({
  User? user,
  String? preferredName,
}) async {
  if (!_supabaseInitialized) {
    return;
  }

  final client = Supabase.instance.client;
  final activeUser = user ?? client.auth.currentUser;
  if (activeUser == null) {
    return;
  }

  await client.from('user_profiles').upsert(<String, dynamic>{
    'user_id': activeUser.id,
    'full_name': _resolveProfileName(
      user: activeUser,
      preferredName: preferredName,
    ),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  }, onConflict: 'user_id');
}

String _profileSyncErrorMessage(Object error) {
  if (error is PostgrestException) {
    if (error.code == '42P01') {
      return 'Supabase table "user_profiles" is missing. Run the database setup SQL first.';
    }
    if (error.code == '42501') {
      return 'Profile database access was denied. Check user_profiles RLS insert/update policies.';
    }
    final message = error.message.trim();
    if (message.isNotEmpty) {
      return 'Could not sync account profile: $message';
    }
  }

  return 'Could not sync account profile to database.';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _loadSupabaseConfig();

  if (_supabaseConfigIsValid()) {
    if (_isSupabaseSecretKey(_supabaseAnonKey)) {
      _supabaseStartupError =
          'Do not use a Supabase secret key in Flutter. Use the project anon/publishable key in .env.';
      runApp(const AegisDryApp());
      return;
    }

    try {
      await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
      _supabaseInitialized = true;
    } catch (_) {
      _supabaseStartupError =
          'Supabase initialization failed. Check SUPABASE_URL and SUPABASE_ANON_KEY.';
    }
  }

  runApp(const AegisDryApp());
}

class AegisDryApp extends StatelessWidget {
  const AegisDryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Aegis-Dry',
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final width = media.size.width;
        final textScale = (width / 390).clamp(0.74, 1.0);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.surface,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontSize: 42, fontWeight: FontWeight.w700),
          titleLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class AppColors {
  static const Color primary = Color(0xFF169A92);
  static const Color primaryDark = Color(0xFF107F79);
  static const Color accentBlue = Color(0xFF2F62DE);
  static const Color danger = Color(0xFFE9232B);
  static const Color textMain = Color(0xFF1B2236);
  static const Color textMuted = Color(0xFF7B89A5);
  static const Color surface = Color(0xFFF3F6FA);
  static const Color card = Colors.white;
  static const Color line = Color(0xFFD8E0EB);
  static const Color success = Color(0xFF22B573);
}

class AppLocation {
  const AppLocation({
    required this.label,
    required this.latitude,
    required this.longitude,
    this.street,
    this.province,
    this.city,
  });

  final String label;
  final double latitude;
  final double longitude;
  final String? street;
  final String? province;
  final String? city;
}

class LocationStore {
  static const String _labelKey = 'user.location.label';
  static const String _latKey = 'user.location.lat';
  static const String _lonKey = 'user.location.lon';
  static const String _streetKey = 'user.location.street';
  static const String _provinceKey = 'user.location.province';
  static const String _cityKey = 'user.location.city';

  static double? _readDouble(SharedPreferences prefs, String key) {
    final doubleValue = prefs.getDouble(key);
    if (doubleValue != null) {
      return doubleValue;
    }

    final intValue = prefs.getInt(key);
    if (intValue != null) {
      return intValue.toDouble();
    }

    final stringValue = prefs.getString(key);
    if (stringValue == null) {
      return null;
    }

    return double.tryParse(stringValue.trim());
  }

  static double? _parseDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  static String? _buildLabel({String? street, String? city, String? province}) {
    final parts = <String>[];
    if (street != null && street.trim().isNotEmpty) {
      parts.add(street.trim());
    }
    if (city != null && city.trim().isNotEmpty) {
      parts.add(city.trim());
    }
    if (province != null && province.trim().isNotEmpty) {
      parts.add(province.trim());
    }
    if (parts.isEmpty) {
      return null;
    }
    return '${parts.join(', ')}, Philippines';
  }

  static String? _fallbackLabel(SharedPreferences prefs) {
    return _buildLabel(
      street: prefs.getString(_streetKey),
      city: prefs.getString(_cityKey),
      province: prefs.getString(_provinceKey),
    );
  }

  static Future<AppLocation?> loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final label = prefs.getString(_labelKey) ?? _fallbackLabel(prefs);
    final lat = _readDouble(prefs, _latKey);
    final lon = _readDouble(prefs, _lonKey);
    if (label == null || label.trim().isEmpty || lat == null || lon == null) {
      return null;
    }
    return AppLocation(
      label: label,
      latitude: lat,
      longitude: lon,
      street: prefs.getString(_streetKey),
      province: prefs.getString(_provinceKey),
      city: prefs.getString(_cityKey),
    );
  }

  static Future<void> save(AppLocation location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_labelKey, location.label);
    await prefs.setDouble(_latKey, location.latitude);
    await prefs.setDouble(_lonKey, location.longitude);
    if (location.street == null || location.street!.isEmpty) {
      await prefs.remove(_streetKey);
    } else {
      await prefs.setString(_streetKey, location.street!);
    }
    if (location.province == null || location.province!.isEmpty) {
      await prefs.remove(_provinceKey);
    } else {
      await prefs.setString(_provinceKey, location.province!);
    }
    if (location.city == null || location.city!.isEmpty) {
      await prefs.remove(_cityKey);
    } else {
      await prefs.setString(_cityKey, location.city!);
    }
  }

  static Future<AppLocation?> loadFromSupabase() async {
    if (!_supabaseInitialized) {
      return null;
    }
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      return null;
    }

    try {
      final data = await client
          .from('user_profiles')
          .select(
            'location_label, location_lat, location_lon, location_street, location_province, location_city',
          )
          .eq('user_id', user.id)
          .maybeSingle();
      if (data == null) {
        return null;
      }

      final street = (data['location_street'] as String?)?.trim();
      final province = (data['location_province'] as String?)?.trim();
      final city = (data['location_city'] as String?)?.trim();
      final label = (data['location_label'] as String?)?.trim() ??
          _buildLabel(street: street, city: city, province: province);
      final lat = _parseDouble(data['location_lat']);
      final lon = _parseDouble(data['location_lon']);
      if (label == null || label.isEmpty || lat == null || lon == null) {
        return null;
      }

      return AppLocation(
        label: label,
        latitude: lat,
        longitude: lon,
        street: street,
        province: province,
        city: city,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> saveToSupabase(AppLocation location) async {
    if (!_supabaseInitialized) {
      return false;
    }
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      return false;
    }

    try {
      await client.from('user_profiles').upsert(<String, dynamic>{
        'user_id': user.id,
        'full_name': _resolveProfileName(user: user),
        'location_label': location.label,
        'location_lat': location.latitude,
        'location_lon': location.longitude,
        'location_street': location.street,
        'location_province': location.province,
        'location_city': location.city,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
      return true;
    } catch (_) {
      return false;
    }
  }
}

Future<AppLocation?> loadLocationWithFallback() async {
  final local = await LocationStore.loadLocal();
  if (local != null) {
    return local;
  }
  final remote = await LocationStore.loadFromSupabase();
  if (remote != null) {
    await LocationStore.save(remote);
  }
  return remote;
}

class _PhProvinceOption {
  const _PhProvinceOption({required this.code, required this.name});

  final String code;
  final String name;
}

class _PhMunicipalityOption {
  const _PhMunicipalityOption({
    required this.displayName,
    required this.queryName,
  });

  final String displayName;
  final String queryName;
}

class _PhilippinesLocationService {
  static const String _psgcHost = 'psgc.gitlab.io';
  static const String _metroManilaCode = 'NCR';
  static const String _metroManilaName = 'Metro Manila';
  static const String _ncrRegionCode = '130000000';

  static List<_PhProvinceOption>? _provinceCache;
  static List<Map<String, dynamic>>? _municipalityCache;

  static Future<List<_PhProvinceOption>> fetchProvinces() async {
    final cached = _provinceCache;
    if (cached != null) {
      return cached;
    }

    final uri = Uri.https(_psgcHost, '/api/provinces/');
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Failed to load provinces from PSGC (${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic>) {
      throw StateError('Invalid provinces payload from PSGC.');
    }

    final provinces = <_PhProvinceOption>[
      const _PhProvinceOption(code: _metroManilaCode, name: _metroManilaName),
    ];

    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }
      final row = item.map((key, value) => MapEntry(key.toString(), value));
      final code = _readString(row, 'code');
      final name = _readString(row, 'name');
      if (code == null || name == null) {
        continue;
      }
      provinces.add(_PhProvinceOption(code: code, name: name));
    }

    provinces.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    _provinceCache = List<_PhProvinceOption>.unmodifiable(provinces);
    return _provinceCache!;
  }

  static Future<List<_PhMunicipalityOption>> fetchMunicipalities({
    required String provinceCode,
  }) async {
    final rows = await _fetchAllMunicipalities();
    final optionsByKey = <String, _PhMunicipalityOption>{};

    for (final row in rows) {
      final regionCode = _readString(row, 'regionCode');
      final rowProvinceCode = _readString(row, 'provinceCode');

      final belongsToProvince = provinceCode == _metroManilaCode
          ? regionCode == _ncrRegionCode
          : rowProvinceCode == provinceCode;
      if (!belongsToProvince) {
        continue;
      }

      final rawName = _readString(row, 'name');
      if (rawName == null) {
        continue;
      }
      final normalizedName = _normalizeMunicipalityName(rawName);
      final key = normalizedName.toLowerCase();
      optionsByKey[key] = _PhMunicipalityOption(
        displayName: normalizedName,
        queryName: normalizedName,
      );
    }

    final options = optionsByKey.values.toList()
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    return options;
  }

  static Future<List<Map<String, dynamic>>> _fetchAllMunicipalities() async {
    final cached = _municipalityCache;
    if (cached != null) {
      return cached;
    }

    final uri = Uri.https(_psgcHost, '/api/cities-municipalities/');
    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Failed to load municipalities from PSGC (${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic>) {
      throw StateError('Invalid municipalities payload from PSGC.');
    }

    final rows = <Map<String, dynamic>>[];
    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }
      rows.add(item.map((key, value) => MapEntry(key.toString(), value)));
    }

    _municipalityCache = List<Map<String, dynamic>>.unmodifiable(rows);
    return _municipalityCache!;
  }

  static String? _readString(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null || value == false) {
      return null;
    }
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'false') {
      return null;
    }
    return text;
  }

  static String _normalizeMunicipalityName(String name) {
    final cityPrefix = RegExp(r'^City of\s+', caseSensitive: false);
    return name.replaceFirst(cityPrefix, '').trim();
  }
}

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureC,
    required this.sky,
    required this.humidity,
    required this.rainProbability,
    required this.source,
  });

  final double temperatureC;
  final String sky;
  final int humidity;
  final int rainProbability;
  final String source;

  String get temperatureFText => '${((temperatureC * 9 / 5) + 32).round()}°F';
}

class OpenWeatherService {
  static const String _apiKey = String.fromEnvironment(
    'OPENWEATHERMAP_API_KEY',
  );

  static Future<(double, double)> geocodePhilippineLocation({
    required String municipality,
    required String province,
  }) async {
    final queries = <String>[
      '$municipality, $province, Philippines',
      '$municipality, Philippines',
      municipality,
    ];

    for (final query in queries) {
      final result = await _resolveCoordinatesOpenMeteo(
        query: query,
        provinceHint: province,
      );
      if (result != null) {
        return result;
      }
    }

    for (final query in queries) {
      final result = await _resolveCoordinatesNominatim(
        query: query,
        provinceHint: province,
      );
      if (result != null) {
        return result;
      }
    }

    throw StateError(
      'No geocoding result for "$municipality, $province, Philippines".',
    );
  }

  static Future<(double, double)?> _resolveCoordinatesOpenMeteo({
    required String query,
    required String provinceHint,
  }) async {
    final geoUri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': query,
      'count': '10',
      'language': 'en',
      'format': 'json',
    });

    final response = await http.get(geoUri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Failed geocoding lookup (${response.statusCode}).');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final results = decoded['results'];
    if (results is! List<dynamic> || results.isEmpty) {
      return null;
    }

    final normalizedProvince = provinceHint.trim().toLowerCase();
    (double, double)? firstMatch;

    for (final item in results) {
      if (item is! Map) {
        continue;
      }

      final row = item.map((key, value) => MapEntry(key.toString(), value));
      final countryCode = row['country_code']?.toString().toUpperCase();
      if (countryCode != 'PH') {
        continue;
      }

      final lat = (row['latitude'] as num?)?.toDouble();
      final lon = (row['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null) {
        continue;
      }

      firstMatch ??= (lat, lon);

      final admin1 = row['admin1']?.toString().toLowerCase() ?? '';
      final admin2 = row['admin2']?.toString().toLowerCase() ?? '';
      if (normalizedProvince.isNotEmpty &&
          (admin1.contains(normalizedProvince) ||
              admin2.contains(normalizedProvince))) {
        return (lat, lon);
      }
    }

    return firstMatch;
  }

  static Future<(double, double)?> _resolveCoordinatesNominatim({
    required String query,
    required String provinceHint,
  }) async {
    final geoUri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'jsonv2',
      'countrycodes': 'ph',
      'addressdetails': '1',
      'limit': '5',
    });

    final response = await http.get(
      geoUri,
      headers: <String, String>{
        'User-Agent': 'aegis-dry-mobile/1.0 (location-setup)',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Failed geocoding fallback lookup (${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic> || decoded.isEmpty) {
      return null;
    }

    final normalizedProvince = provinceHint.trim().toLowerCase();
    (double, double)? firstMatch;

    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }

      final row = item.map((key, value) => MapEntry(key.toString(), value));
      final lat = double.tryParse(row['lat']?.toString() ?? '');
      final lon = double.tryParse(row['lon']?.toString() ?? '');
      if (lat == null || lon == null) {
        continue;
      }

      firstMatch ??= (lat, lon);

      final display = row['display_name']?.toString().toLowerCase() ?? '';
      if (normalizedProvince.isNotEmpty &&
          display.contains(normalizedProvince)) {
        return (lat, lon);
      }
    }

    return firstMatch;
  }

  static Future<WeatherSnapshot> getSnapshot({
    required double latitude,
    required double longitude,
  }) async {
    if (_apiKey.isNotEmpty) {
      try {
        return await _getSnapshotFromOpenWeather(
          latitude: latitude,
          longitude: longitude,
        );
      } catch (_) {
        // Fallback below keeps forecast mode operational when OpenWeather is unavailable.
      }
    }

    return _getSnapshotFromOpenMeteo(latitude: latitude, longitude: longitude);
  }

  static Future<WeatherSnapshot> _getSnapshotFromOpenWeather({
    required double latitude,
    required double longitude,
  }) async {
    final weatherUri =
        Uri.https('api.openweathermap.org', '/data/2.5/weather', {
          'lat': latitude.toString(),
          'lon': longitude.toString(),
          'appid': _apiKey,
          'units': 'metric',
        });

    final forecastUri =
        Uri.https('api.openweathermap.org', '/data/2.5/forecast', {
          'lat': latitude.toString(),
          'lon': longitude.toString(),
          'appid': _apiKey,
          'units': 'metric',
        });

    final responses = await Future.wait([
      http.get(weatherUri),
      http.get(forecastUri),
    ]);

    final weatherRes = responses[0];
    final forecastRes = responses[1];

    if (weatherRes.statusCode < 200 || weatherRes.statusCode >= 300) {
      throw StateError('Failed weather lookup (${weatherRes.statusCode}).');
    }
    if (forecastRes.statusCode < 200 || forecastRes.statusCode >= 300) {
      throw StateError(
        'Failed rain forecast lookup (${forecastRes.statusCode}).',
      );
    }

    final weatherJson = jsonDecode(weatherRes.body) as Map<String, dynamic>;
    final forecastJson = jsonDecode(forecastRes.body) as Map<String, dynamic>;

    final temp = (weatherJson['main']?['temp'] as num?)?.toDouble() ?? 0;
    final humidity = (weatherJson['main']?['humidity'] as num?)?.toInt() ?? 0;
    final weatherList =
        (weatherJson['weather'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    final sky = weatherList.isNotEmpty
        ? weatherList.first['main']?.toString() ?? 'Unknown'
        : 'Unknown';

    final forecastList =
        (forecastJson['list'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    final firstForecast = forecastList.isNotEmpty ? forecastList.first : null;
    final rainPop = ((firstForecast?['pop'] as num?)?.toDouble() ?? 0) * 100;

    return WeatherSnapshot(
      temperatureC: temp,
      sky: sky,
      humidity: humidity,
      rainProbability: rainPop.round().clamp(0, 100),
      source: 'OpenWeather',
    );
  }

  static Future<WeatherSnapshot> _getSnapshotFromOpenMeteo({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'current': 'temperature_2m,relative_humidity_2m,weather_code',
      'hourly': 'precipitation_probability',
      'forecast_days': '1',
      'timezone': 'auto',
    });

    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Weather providers unavailable (${response.statusCode}). Please check internet and try again.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Invalid weather payload from fallback provider.');
    }

    final current = decoded['current'];
    if (current is! Map<String, dynamic>) {
      throw StateError('Missing current weather data from fallback provider.');
    }

    final temperatureC = (current['temperature_2m'] as num?)?.toDouble() ?? 0;
    final humidity = (current['relative_humidity_2m'] as num?)?.toInt() ?? 0;
    final weatherCode = (current['weather_code'] as num?)?.toInt() ?? 0;
    final sky = _weatherCodeToSky(weatherCode);

    final hourly = decoded['hourly'];
    int rainProbability = 0;
    if (hourly is Map<String, dynamic>) {
      final pops = hourly['precipitation_probability'];
      if (pops is List<dynamic> && pops.isNotEmpty) {
        final first = pops.first;
        final parsed = first is num ? first.toInt() : int.tryParse('$first');
        rainProbability = (parsed ?? 0).clamp(0, 100);
      }
    }

    return WeatherSnapshot(
      temperatureC: temperatureC,
      sky: sky,
      humidity: humidity,
      rainProbability: rainProbability,
      source: 'Open-Meteo',
    );
  }

  static String _weatherCodeToSky(int code) {
    if (code == 0) {
      return 'Clear';
    }
    if (code == 1 || code == 2 || code == 3) {
      return 'Cloudy';
    }
    if (code == 45 || code == 48) {
      return 'Fog';
    }
    if (code == 51 || code == 53 || code == 55 || code == 56 || code == 57) {
      return 'Drizzle';
    }
    if (code == 61 ||
        code == 63 ||
        code == 65 ||
        code == 66 ||
        code == 67 ||
        code == 80 ||
        code == 81 ||
        code == 82) {
      return 'Rain';
    }
    if (code == 71 ||
        code == 73 ||
        code == 75 ||
        code == 77 ||
        code == 85 ||
        code == 86) {
      return 'Snow';
    }
    if (code == 95 || code == 96 || code == 99) {
      return 'Storm';
    }
    return 'Unknown';
  }
}

class ActivityFeedEvent {
  const ActivityFeedEvent({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.response,
    required this.timestamp,
    this.isMuted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String response;
  final DateTime timestamp;
  final bool isMuted;
}

List<ActivityFeedEvent> buildRecentActivityFeed({
  required AppLocation location,
  required WeatherSnapshot? weather,
  required DateTime? lastWeatherSyncAt,
}) {
  final now = DateTime.now();
  final syncAt = lastWeatherSyncAt ?? now.subtract(const Duration(minutes: 1));
  final cityLabel = location.city ?? location.label;
  final provinceLabel = location.province ?? 'Philippines';

  if (weather == null) {
    return <ActivityFeedEvent>[
      ActivityFeedEvent(
        icon: Icons.sync_problem,
        title: 'Weather Sync Pending',
        subtitle: 'Waiting for forecast data for $cityLabel.',
        response:
            'User activity processing is active and will evaluate rain risk once weather sync completes.',
        timestamp: syncAt,
      ),
      ActivityFeedEvent(
        icon: Icons.location_on_outlined,
        title: 'Location Profile Loaded',
        subtitle: 'Monitoring area set to $provinceLabel.',
        response:
            'Forecast jobs are queued for ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}.',
        timestamp: now.subtract(const Duration(minutes: 8)),
      ),
      ActivityFeedEvent(
        icon: Icons.cloud_upload_outlined,
        title: 'Cloud Activity Queue Ready',
        subtitle:
            'Event stream is prepared for user actions and weather updates.',
        response:
            'System is in forecast-only mode while hardware integration is in progress.',
        timestamp: now.subtract(const Duration(hours: 1)),
        isMuted: true,
      ),
    ];
  }

  final rainLevel = weather.rainProbability >= 60
      ? 'HIGH'
      : (weather.rainProbability >= 40 ? 'MODERATE' : 'LOW');

  return <ActivityFeedEvent>[
    ActivityFeedEvent(
      icon: Icons.cloud_done_outlined,
      title: 'Weather Sync Complete',
      subtitle:
          '${weather.source} feed: ${weather.temperatureC.round()}°C, ${weather.humidity}% humidity, ${weather.rainProbability}% rain chance.',
      response:
          'Latest forecast snapshot was processed and appended to user activity records.',
      timestamp: syncAt,
    ),
    ActivityFeedEvent(
      icon: Icons.analytics_outlined,
      title: 'Rain Risk Evaluated',
      subtitle: '$rainLevel risk level for $provinceLabel.',
      response: weather.rainProbability >= 60
          ? 'Auto-retract condition flagged for deployment once hardware is connected.'
          : 'No retract action required under current forecast conditions.',
      timestamp: syncAt.subtract(const Duration(minutes: 7)),
    ),
    ActivityFeedEvent(
      icon: Icons.location_on_outlined,
      title: 'Location-Aware Processing',
      subtitle: 'Forecast checks are pinned to $cityLabel.',
      response:
          'Weather and user activity pipelines remain synchronized for this configured location.',
      timestamp: syncAt.subtract(const Duration(minutes: 19)),
    ),
    ActivityFeedEvent(
      icon: Icons.restore,
      title: 'Routine Backup',
      subtitle: 'User activity and weather summaries were archived.',
      response: 'Cloud backup completed with no conflicts.',
      timestamp: now.subtract(const Duration(days: 1)),
      isMuted: true,
    ),
  ];
}

double responsiveScale(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return (width / 390).clamp(0.78, 1.0);
}

double rs(BuildContext context, double size, {double min = 12}) {
  return math.max(min, size * responsiveScale(context));
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String formatClockTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final meridian = time.hour >= 12 ? 'PM' : 'AM';
  return '$hour:${_twoDigits(time.minute)} $meridian';
}

String formatRelativeTime(DateTime? time) {
  if (time == null) {
    return 'No weather sync yet';
  }
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 30) {
    return 'Last checked: just now';
  }
  if (diff.inMinutes < 60) {
    return 'Last checked: ${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
  }
  if (diff.inHours < 24) {
    return 'Last checked: ${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  }
  return 'Last checked: ${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
}

String formatDayDate(DateTime time) {
  const months = <String>[
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  return '${months[time.month - 1]} ${time.day}, ${time.year}';
}

String formatActivityTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inHours < 24) {
    return formatClockTime(time);
  }
  return formatDayDate(time);
}

class AppViewport extends StatelessWidget {
  const AppViewport({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final maxWidth = width > 460 ? 440.0 : width;

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: maxWidth, child: child),
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final Timer _timer;
  double _progress = 0.35;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 380), (timer) {
      if (!mounted) {
        return;
      }
      setState(() {
        _progress += 0.09;
      });
      if (_progress >= 1) {
        timer.cancel();
        unawaited(_continueAfterSplash());
      }
    });
  }

  Future<void> _continueAfterSplash() async {
    final hasSession =
        _supabaseInitialized &&
        Supabase.instance.client.auth.currentSession != null;

    if (!hasSession) {
      if (!mounted) {
        return;
      }
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }

    try {
      await upsertAuthenticatedUserProfile();
    } catch (_) {
      // Keep splash flow resilient; profile sync is retried on explicit login.
    }

    final savedLocation = await loadLocationWithFallback();
    if (!mounted) {
      return;
    }

    if (savedLocation == null) {
      final location = await Navigator.of(context).push<AppLocation>(
        MaterialPageRoute(
          builder: (_) =>
              const SetLocationScreen(requireBeforeProceeding: true),
        ),
      );

      if (!mounted || location == null) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainNavigationShell(initialLocation: location),
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MainNavigationShell(initialLocation: savedLocation),
      ),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int percent = (_progress.clamp(0, 1) * 100).toInt();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF7FBFD), Color(0xFFEEF4F8)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFD7E0EA)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shield,
                    size: 40,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 28),
                const Text.rich(
                  TextSpan(
                    text: 'Aegis-Dry ',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                    children: [
                      TextSpan(
                        text: 'Smart Dock',
                        style: TextStyle(color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Smart Protection for Your\nLaundry',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: AppColors.textMuted),
                ),
                const SizedBox(height: 64),
                Row(
                  children: [
                    const Text(
                      'INITIALIZING SYSTEM',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: Color(0xFF6E7F9F),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$percent%',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress.clamp(0, 1),
                    minHeight: 6,
                    color: AppColors.primary,
                    backgroundColor: const Color(0xFFD8E0EC),
                  ),
                ),
                const SizedBox(height: 26),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    _PillTag(label: 'SENSORS ONLINE'),
                    SizedBox(width: 8),
                    _PillTag(label: 'CLOUD LINKED'),
                  ],
                ),
                const Spacer(),
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'VERSION 2.4.0  •  SECURED BY AEGIS',
                    style: TextStyle(
                      color: Color(0xFF8C9AB2),
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PillTag extends StatelessWidget {
  const _PillTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD9E1EC)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 14,
            color: AppColors.primary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: Color(0xFF62748F),
            ),
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isSigningIn = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titleSize = rs(context, 40, min: 30);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF7FBFD), Color(0xFFEDF5F8)],
          ),
        ),
        child: AppViewport(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 18,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE3EAF2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFD),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE1E8F1)),
                          ),
                          child: const Icon(
                            Icons.shield,
                            size: 44,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          'Aegis-Dry',
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Center(
                        child: Text(
                          'Smart Protection for Your Laundry',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Email',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMain,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildInput(
                        controller: _emailController,
                        hint: 'name@example.com',
                        icon: Icons.mail_outline,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Text(
                            'Password',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMain,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _buildInput(
                        controller: _passwordController,
                        hint: 'Enter password',
                        icon: Icons.lock_outline,
                        obscure: _obscurePassword,
                        suffix: IconButton(
                          onPressed: () {
                            setState(
                              () => _obscurePassword = !_obscurePassword,
                            );
                          },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 18,
                            color: const Color(0xFF8C9BB2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            onChanged: (value) {
                              setState(() => _rememberMe = value ?? false);
                            },
                            side: const BorderSide(color: Color(0xFFD4DDE9)),
                          ),
                          const Text(
                            'Remember me',
                            style: TextStyle(color: Color(0xFF6F8099)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _isSigningIn ? null : _onLogin,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isSigningIn
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Login',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'New to Aegis-Dry? ',
                            style: TextStyle(color: Color(0xFF8A98AE)),
                          ),
                          TextButton(
                            onPressed: _openRegisterScreen,
                            style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text(
                              'Create an account',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Color(0xFFE5ECF3)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF9AA8BC)),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF97A7BE)),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF6F9FC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFDBE3EE)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFDBE3EE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }

  Future<void> _onLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    late final AuthResponse response;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Enter your email and password.');
      return;
    }

    if (!_supabaseInitialized) {
      _showMessage(authUnavailableMessage());
      return;
    }

    setState(() => _isSigningIn = true);

    try {
      response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isSigningIn = false);
      _showMessage(error.message);
      return;
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isSigningIn = false);
      _showMessage('Could not sign in right now.');
      return;
    }

    try {
      await upsertAuthenticatedUserProfile(
        user: response.user ?? Supabase.instance.client.auth.currentUser,
      );
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isSigningIn = false);
      _showMessage(_profileSyncErrorMessage(error));
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {
        // Ignore sign-out errors after profile sync failure.
      }
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() => _isSigningIn = false);
    await _continueAfterLogin();
  }

  Future<void> _continueAfterLogin() async {
    final savedLocation = await loadLocationWithFallback();
    if (!mounted) {
      return;
    }

    if (savedLocation == null) {
      final location = await Navigator.of(context).push<AppLocation>(
        MaterialPageRoute(
          builder: (_) =>
              const SetLocationScreen(requireBeforeProceeding: true),
        ),
      );

      if (!mounted || location == null) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainNavigationShell(initialLocation: location),
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MainNavigationShell(initialLocation: savedLocation),
      ),
    );
  }

  Future<void> _openRegisterScreen() async {
    final createdEmail = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const RegisterScreen()));

    if (!mounted || createdEmail == null) {
      return;
    }

    _emailController.text = createdEmail;
    _passwordController.clear();
    _showMessage('Account created. You can now sign in.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Create Account',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textMain,
          ),
        ),
      ),
      body: AppViewport(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Register a new account to sign in to Aegis-Dry.',
              style: TextStyle(fontSize: 16, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _usernameController,
              label: 'Username',
              hint: 'jane_doe',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 12),
            _buildField(
              controller: _emailController,
              label: 'Email',
              hint: 'jane@example.com',
              icon: Icons.mail_outline,
            ),
            const SizedBox(height: 12),
            _buildField(
              controller: _passwordController,
              label: 'Password',
              hint: 'At least 6 characters',
              icon: Icons.lock_outline,
              obscure: _obscurePassword,
              suffix: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: const Color(0xFF8C9BB2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildField(
              controller: _confirmPasswordController,
              label: 'Confirm Password',
              hint: 'Re-enter password',
              icon: Icons.verified_user_outlined,
              obscure: _obscureConfirm,
              suffix: IconButton(
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: const Color(0xFF8C9BB2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _isSaving ? null : _onCreateAccount,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Create Account',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textMain,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 18, color: const Color(0xFF97A7BE)),
            suffixIcon: suffix,
            filled: true,
            fillColor: const Color(0xFFF6F9FC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFDBE3EE)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFDBE3EE)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onCreateAccount() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    if (username.length < 3) {
      _showMessage('Username must be at least 3 characters.');
      return;
    }
    if (!emailRegex.hasMatch(email)) {
      _showMessage('Enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      _showMessage('Password must be at least 6 characters.');
      return;
    }
    if (password != confirmPassword) {
      _showMessage('Passwords do not match.');
      return;
    }

    if (!_supabaseInitialized) {
      _showMessage(authUnavailableMessage());
      return;
    }

    setState(() => _isSaving = true);

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: <String, dynamic>{'username': username},
      );

      if (!mounted) {
        return;
      }

      setState(() => _isSaving = false);

      if (response.user == null) {
        _showMessage('Could not create account. Please try again.');
        return;
      }

      if (response.session != null) {
        await upsertAuthenticatedUserProfile(
          user: response.user,
          preferredName: username,
        );
        if (!mounted) {
          return;
        }
      }

      if (response.session == null) {
        _showMessage(
          'Account created. Please check your email to verify your account, then sign in once to sync your profile to database.',
        );
      } else {
        _showMessage('Account created and synced to database.');
      }

      Navigator.of(context).pop(email);
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      _showMessage(error.message);
    } on PostgrestException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      _showMessage(_profileSyncErrorMessage(error));
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {
        // Ignore sign-out errors after profile sync failure.
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      _showMessage('Could not create account. Please try again.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class SetLocationScreen extends StatefulWidget {
  const SetLocationScreen({
    super.key,
    this.initialLocation,
    this.requireBeforeProceeding = false,
  });

  final AppLocation? initialLocation;
  final bool requireBeforeProceeding;

  @override
  State<SetLocationScreen> createState() => _SetLocationScreenState();
}

class _SetLocationScreenState extends State<SetLocationScreen> {
  late final TextEditingController _streetController;
  List<_PhProvinceOption> _provinceOptions = const <_PhProvinceOption>[];
  List<_PhMunicipalityOption> _municipalityOptions =
      const <_PhMunicipalityOption>[];
  String? _selectedProvinceCode;
  String? _selectedProvinceName;
  String? _selectedMunicipality;
  bool _isLoadingProvinces = true;
  bool _isLoadingMunicipalities = false;
  bool _isSavingLocation = false;

  _PhMunicipalityOption? get _selectedMunicipalityOption {
    final selected = _selectedMunicipality;
    if (selected == null) {
      return null;
    }
    for (final option in _municipalityOptions) {
      if (option.displayName == selected) {
        return option;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _streetController = TextEditingController(
      text:
          widget.initialLocation?.street ??
          _extractStreet(widget.initialLocation?.label),
    );
    unawaited(_initializeSelectors());
  }

  Future<void> _initializeSelectors() async {
    final parsedProvince =
        widget.initialLocation?.province ??
        _extractProvince(widget.initialLocation?.label);
    final parsedCity =
        widget.initialLocation?.city ??
        _extractCity(widget.initialLocation?.label);

    try {
      final provinces = await _PhilippinesLocationService.fetchProvinces();
      if (!mounted) {
        return;
      }
      setState(() {
        _provinceOptions = provinces;
        _isLoadingProvinces = false;
      });

      final matchedProvince = _findProvinceByName(parsedProvince);
      if (matchedProvince != null) {
        await _onProvinceChanged(
          matchedProvince.code,
          preselectedMunicipality: parsedCity,
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingProvinces = false;
      });
      _showMessage(
        'Could not load the full Philippines location list right now. Check your internet and try again.',
      );
    }
  }

  @override
  void dispose() {
    _streetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.requireBeforeProceeding,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.requireBeforeProceeding,
          title: Text(
            widget.requireBeforeProceeding
                ? 'Set Location Required'
                : 'Change Location',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textMain,
            ),
          ),
        ),
        body: AppViewport(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Set a Philippine address so OpenWeather can return accurate rain probability for automation decisions.',
                style: TextStyle(fontSize: 16, color: AppColors.textMuted),
              ),
              if (_isLoadingProvinces || _isLoadingMunicipalities)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              const SizedBox(height: 16),
              _buildField(
                controller: _streetController,
                label: 'Street / Barangay',
                hint: 'Blk 5 Lot 2, Brgy. San Isidro',
                icon: Icons.place_outlined,
              ),
              const SizedBox(height: 12),
              _buildProvinceDropdown(),
              const SizedBox(height: 12),
              _buildCityDropdown(),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFCFE0F8)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppColors.accentBlue,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Coordinates are set automatically from your selected city for OpenWeather API requests.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF415B7E),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _isSavingLocation ? null : _saveLocation,
                icon: const Icon(Icons.save_outlined, color: Colors.white),
                label: const Text(
                  'Save Location',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProvinceDropdown() {
    final bool disableDropdown = _isLoadingProvinces || _isSavingLocation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Province',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textMain,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey<String?>(_selectedProvinceCode),
          initialValue: _selectedProvinceCode,
          isExpanded: true,
          decoration: _dropdownDecoration(
            hint: _isLoadingProvinces
                ? 'Loading provinces...'
                : 'Select province',
            icon: Icons.map_outlined,
          ),
          items: _provinceOptions
              .map(
                (province) => DropdownMenuItem<String>(
                  value: province.code,
                  child: Text(province.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: disableDropdown
              ? null
              : (value) {
                  if (value == null) {
                    return;
                  }
                  unawaited(_onProvinceChanged(value));
                },
        ),
      ],
    );
  }

  Widget _buildCityDropdown() {
    final bool disableDropdown =
        _selectedProvinceCode == null ||
        _isLoadingMunicipalities ||
        _isSavingLocation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'City / Municipality',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textMain,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey<String?>(
            '${_selectedProvinceCode ?? 'none'}:${_selectedMunicipality ?? 'none'}',
          ),
          initialValue: _selectedMunicipality,
          isExpanded: true,
          decoration: _dropdownDecoration(
            hint: _selectedProvinceCode == null
                ? 'Select province first'
                : (_isLoadingMunicipalities
                      ? 'Loading cities and municipalities...'
                      : 'Select city or municipality'),
            icon: Icons.location_city_outlined,
          ),
          items: _municipalityOptions
              .map(
                (municipality) => DropdownMenuItem<String>(
                  value: municipality.displayName,
                  child: Text(
                    municipality.displayName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: disableDropdown
              ? null
              : (value) {
                  setState(() {
                    _selectedMunicipality = value;
                  });
                },
        ),
      ],
    );
  }

  InputDecoration _dropdownDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0xFF93A4BC)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD8E1EC)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD8E1EC)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textMain,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: const Color(0xFF93A4BC)),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFD8E1EC)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFD8E1EC)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveLocation() async {
    final street = _streetController.text.trim();
    final province = _selectedProvinceName;
    final municipality = _selectedMunicipalityOption;

    if (street.isEmpty || province == null || municipality == null) {
      _showMessage('Enter street, select province, and select city.');
      return;
    }

    setState(() {
      _isSavingLocation = true;
    });

    try {
      final coordinates = await OpenWeatherService.geocodePhilippineLocation(
        municipality: municipality.queryName,
        province: province,
      );

      final label =
          '$street, ${municipality.displayName}, $province, Philippines';
      final location = AppLocation(
        label: label,
        latitude: coordinates.$1,
        longitude: coordinates.$2,
        street: street,
        province: province,
        city: municipality.displayName,
      );
      await LocationStore.save(location);
      final synced = await LocationStore.saveToSupabase(location);
      if (!mounted) {
        return;
      }
      if (!synced) {
        _showMessage('Saved locally, but could not sync to the cloud.');
      }
      Navigator.of(context).pop(location);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(
        'Could not resolve coordinates for this municipality. Please check your internet and try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingLocation = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _extractStreet(String? label) {
    if (label == null || label.trim().isEmpty) {
      return '';
    }
    final parts = label.split(',').map((part) => part.trim()).toList();
    return parts.isEmpty ? '' : parts.first;
  }

  String? _extractProvince(String? label) {
    if (label == null || label.trim().isEmpty) {
      return null;
    }
    final parts = label.split(',').map((part) => part.trim()).toList();
    if (parts.length >= 3) {
      return parts[parts.length - 2];
    }
    return null;
  }

  String? _extractCity(String? label) {
    if (label == null || label.trim().isEmpty) {
      return null;
    }
    final parts = label.split(',').map((part) => part.trim()).toList();
    if (parts.length >= 2) {
      return parts[1];
    }
    return null;
  }

  _PhProvinceOption? _findProvinceByName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return null;
    }
    final normalized = name.trim().toLowerCase();
    for (final province in _provinceOptions) {
      if (province.name.toLowerCase() == normalized) {
        return province;
      }
    }
    return null;
  }

  Future<void> _onProvinceChanged(
    String provinceCode, {
    String? preselectedMunicipality,
  }) async {
    _PhProvinceOption? selectedProvince;
    for (final province in _provinceOptions) {
      if (province.code == provinceCode) {
        selectedProvince = province;
        break;
      }
    }
    if (selectedProvince == null) {
      return;
    }

    setState(() {
      _selectedProvinceCode = selectedProvince!.code;
      _selectedProvinceName = selectedProvince.name;
      _municipalityOptions = const <_PhMunicipalityOption>[];
      _selectedMunicipality = null;
      _isLoadingMunicipalities = true;
    });

    try {
      final municipalities =
          await _PhilippinesLocationService.fetchMunicipalities(
            provinceCode: selectedProvince.code,
          );
      if (!mounted) {
        return;
      }

      String? selectedName;
      if (preselectedMunicipality != null) {
        final normalized = preselectedMunicipality.trim().toLowerCase();
        for (final option in municipalities) {
          if (option.displayName.toLowerCase() == normalized) {
            selectedName = option.displayName;
            break;
          }
        }
      }

      setState(() {
        _municipalityOptions = municipalities;
        _selectedMunicipality = selectedName;
        _isLoadingMunicipalities = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingMunicipalities = false;
      });
      _showMessage(
        'Could not load municipalities for the selected province. Please try again.',
      );
    }
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key, required this.initialLocation});

  final AppLocation initialLocation;

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _index = 0;
  late AppLocation _location;
  WeatherSnapshot? _weather;
  bool _isWeatherLoading = false;
  String? _weatherError;
  DateTime? _lastWeatherSyncAt;

  @override
  void initState() {
    super.initState();
    _location = widget.initialLocation;
    _refreshWeather();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        onOpenManualControl: _openManualControl,
        onOpenDashboard: () => setState(() => _index = 1),
        location: _location,
        weather: _weather,
        isWeatherLoading: _isWeatherLoading,
        weatherError: _weatherError,
        onRefreshWeather: _refreshWeather,
      ),
      DashboardScreen(
        onOpenHistory: _openActivityHistory,
        location: _location,
        weather: _weather,
        lastWeatherSyncAt: _lastWeatherSyncAt,
      ),
      DeviceScreen(
        onOpenManualControl: _openLiveConsoleManual,
        location: _location,
        weather: _weather,
        lastWeatherSyncAt: _lastWeatherSyncAt,
      ),
      AlertsScreen(
        weather: _weather,
        location: _location,
        lastWeatherSyncAt: _lastWeatherSyncAt,
      ),
      SettingsScreen(
        onOpenThreshold: _openThresholdConfig,
        onChangeLocation: _openChangeLocation,
        onSignOut: _signOut,
        currentLocationLabel: _location.label,
      ),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        height: 74,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        backgroundColor: Colors.white,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'HOME',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'DASHBOARD',
          ),
          NavigationDestination(
            icon: Icon(Icons.memory_outlined),
            selectedIcon: Icon(Icons.memory),
            label: 'DEVICE',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            selectedIcon: Icon(Icons.notifications),
            label: 'ALERTS',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'SETTINGS',
          ),
        ],
      ),
    );
  }

  void _openManualControl() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ManualOverrideScreen()));
  }

  void _openLiveConsoleManual() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ManualOverrideLiveScreen()));
  }

  void _openActivityHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActivityHistoryScreen(
          location: _location,
          weather: _weather,
          lastWeatherSyncAt: _lastWeatherSyncAt,
        ),
      ),
    );
  }

  void _openThresholdConfig() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ThresholdConfigurationScreen()),
    );
  }

  Future<void> _openChangeLocation() async {
    final updatedLocation = await Navigator.of(context).push<AppLocation>(
      MaterialPageRoute(
        builder: (_) => SetLocationScreen(initialLocation: _location),
      ),
    );
    if (updatedLocation == null || !mounted) {
      return;
    }
    setState(() {
      _location = updatedLocation;
      _weatherError = null;
    });
    await _refreshWeather();
  }

  Future<void> _refreshWeather() async {
    setState(() {
      _isWeatherLoading = true;
      _weatherError = null;
    });

    try {
      final weather = await OpenWeatherService.getSnapshot(
        latitude: _location.latitude,
        longitude: _location.longitude,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _weather = weather;
        _lastWeatherSyncAt = DateTime.now();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.toString().replaceFirst('Bad state: ', '').trim();
      setState(() {
        _weatherError = message.isEmpty
            ? 'Weather sync failed. Please check your internet and try again.'
            : message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isWeatherLoading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    if (_supabaseInitialized) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {
        // Ignore sign-out errors and continue returning user to login.
      }
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onOpenDashboard,
    required this.onOpenManualControl,
    required this.location,
    required this.weather,
    required this.isWeatherLoading,
    required this.weatherError,
    required this.onRefreshWeather,
  });

  final VoidCallback onOpenDashboard;
  final VoidCallback onOpenManualControl;
  final AppLocation location;
  final WeatherSnapshot? weather;
  final bool isWeatherLoading;
  final String? weatherError;
  final Future<void> Function() onRefreshWeather;

  @override
  Widget build(BuildContext context) {
    final headline = rs(context, 31, min: 24);
    final greeting = rs(context, 48, min: 34);
    final sectionTitle = rs(context, 32, min: 24);
    final buttonText = rs(context, 26, min: 20);
    final secondaryButtonText = rs(context, 24, min: 18);

    return AppViewport(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(
                    0xFF1B9890,
                  ).withValues(alpha: 0.24),
                  child: const Icon(Icons.person, color: AppColors.textMain),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Aegis-Dry',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: headline,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF0F6),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.notifications_none,
                    color: AppColors.textMain,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Welcome back,',
              style: TextStyle(fontSize: 18, color: Color(0xFF77859E)),
            ),
            Text(
              'Hello, User',
              style: TextStyle(
                fontSize: greeting,
                fontWeight: FontWeight.w700,
                color: AppColors.textMain,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    location.label,
                    style: const TextStyle(
                      color: Color(0xFF5F718E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => onRefreshWeather(),
                  icon: const Icon(Icons.refresh, color: AppColors.primary),
                  tooltip: 'Refresh weather',
                ),
              ],
            ),
            if (isWeatherLoading)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            if (weatherError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  weatherError!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
            _buildStatusCard(context),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    title: 'TEMP',
                    value: weather?.temperatureFText ?? '--',
                    subtitle: 'Indoor average',
                    icon: Icons.thermostat_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    title: 'SKY',
                    value: weather?.sky ?? '--',
                    subtitle: 'Local forecast',
                    icon: Icons.cloud_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onOpenDashboard,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.grid_view_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'Open Dashboard',
                    style: TextStyle(
                      fontSize: buttonText,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFD2DBE8)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: onOpenManualControl,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.info_outline, color: AppColors.textMain),
                  const SizedBox(width: 8),
                  Text(
                    'Manual Control',
                    style: TextStyle(
                      fontSize: secondaryButtonText,
                      color: AppColors.textMain,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Quick Stats',
              style: TextStyle(
                fontSize: sectionTitle,
                fontWeight: FontWeight.w700,
                color: AppColors.textMain,
              ),
            ),
            const SizedBox(height: 10),
            _StatTile(
              icon: Icons.water_drop_outlined,
              label: 'Humidity',
              value: weather == null ? '--' : '${weather!.humidity}%',
            ),
            const SizedBox(height: 8),
            _StatTile(
              icon: Icons.grain,
              label: 'Rain Chance',
              value: weather == null ? '--' : '${weather!.rainProbability}%',
              valueColor: (weather?.rainProbability ?? 0) >= 60
                  ? AppColors.danger
                  : AppColors.success,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final safeText = rs(context, 52, min: 36);
    final isForecastReady = weather != null;
    final statusCopy = isForecastReady
        ? 'Forecast data from ${weather!.source} is active.'
        : 'Forecast pipeline is initializing. No hardware sensor stream yet.';
    final progress = isForecastReady ? 1.0 : 0.62;
    final progressLabel = isForecastReady ? 'Forecast Ready' : 'Syncing';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3FFFA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFE8DA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'SYSTEM STATUS',
                style: TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFDCF6EA),
                  border: Border.all(color: const Color(0xFF88DBC0)),
                ),
                child: const Icon(Icons.check, color: AppColors.success),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Safe',
            style: TextStyle(
              fontSize: safeText,
              fontWeight: FontWeight.w700,
              color: AppColors.textMain,
            ),
          ),
          Text(
            statusCopy,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 17),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: AppColors.success,
                    backgroundColor: const Color(0xFFCAE7D7),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                progressLabel,
                style: TextStyle(
                  color: AppColors.success.withValues(alpha: 0.96),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.onOpenHistory,
    required this.location,
    required this.weather,
    required this.lastWeatherSyncAt,
  });

  final VoidCallback onOpenHistory;
  final AppLocation location;
  final WeatherSnapshot? weather;
  final DateTime? lastWeatherSyncAt;

  @override
  Widget build(BuildContext context) {
    final header = rs(context, 32, min: 24);
    final statusHeadline = rs(context, 44, min: 30);
    final sectionHeader = rs(context, 24, min: 18);
    final isWarning = (weather?.rainProbability ?? 0) >= 60;
    final statusLabel = weather == null
        ? 'Monitoring - Unknown'
        : (isWarning ? 'Monitoring - Warning' : 'Monitoring - Safe');
    final activities = buildRecentActivityFeed(
      location: location,
      weather: weather,
      lastWeatherSyncAt: lastWeatherSyncAt,
    );

    return AppViewport(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          children: [
            Row(
              children: [
                const Icon(Icons.menu, color: AppColors.textMain),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Aegis-Dry System',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: header,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6ECF4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.account_circle_outlined),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFC7EBE6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF79CBC1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SYSTEM STATUS',
                    style: TextStyle(
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• $statusLabel',
                    style: TextStyle(
                      fontSize: statusHeadline,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatRelativeTime(lastWeatherSyncAt),
                    style: TextStyle(fontSize: 20, color: Color(0xFF536579)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'ENVIRONMENTAL METRICS',
              style: TextStyle(
                letterSpacing: 2,
                fontSize: sectionHeader,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5B667A),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    title: '',
                    value: weather == null
                        ? '--'
                        : '${weather!.temperatureC.round()}°C',
                    subtitle: 'Temp',
                    icon: Icons.thermostat,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricCard(
                    title: '',
                    value: weather == null ? '--' : '${weather!.humidity}%',
                    subtitle: 'Humidity',
                    icon: Icons.water_drop,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricCard(
                    title: '',
                    value: weather == null
                        ? '--'
                        : '${weather!.rainProbability}%',
                    subtitle: 'Rain',
                    icon: Icons.grain,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Location: ${location.label}',
              style: const TextStyle(
                color: Color(0xFF6A7891),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  'ACTIVITY LOG',
                  style: TextStyle(
                    letterSpacing: 2,
                    fontSize: sectionHeader,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF5B667A),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onOpenHistory,
                  child: const Text(
                    'View All',
                    style: TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            for (var i = 0; i < math.min(3, activities.length); i++) ...[
              _ActivityTile(
                icon: activities[i].icon,
                title: activities[i].title,
                subtitle: activities[i].subtitle,
                time: formatActivityTime(activities[i].timestamp),
                isMuted: activities[i].isMuted,
              ),
              if (i < math.min(3, activities.length) - 1)
                const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class DeviceScreen extends StatelessWidget {
  const DeviceScreen({
    super.key,
    required this.onOpenManualControl,
    required this.location,
    required this.weather,
    required this.lastWeatherSyncAt,
  });

  final VoidCallback onOpenManualControl;
  final AppLocation location;
  final WeatherSnapshot? weather;
  final DateTime? lastWeatherSyncAt;

  @override
  Widget build(BuildContext context) {
    final titleSize = rs(context, 37, min: 28);
    final networkStateSize = rs(context, 48, min: 34);
    final sensorsTitle = rs(context, 36, min: 26);
    final hasWeather = weather != null;
    final sourceLabel = weather?.source ?? 'Weather API';
    final syncLabel = lastWeatherSyncAt == null
        ? 'PENDING'
        : formatRelativeTime(
            lastWeatherSyncAt,
          ).replaceFirst('Last checked: ', '').toUpperCase();

    return AppViewport(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          children: [
            Row(
              children: [
                const Icon(Icons.shield_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Aegis-Dry',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: onOpenManualControl,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9EFF5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.add),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF6FA),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD1E7F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'NETWORK STATUS',
                    style: TextStyle(
                      letterSpacing: 2,
                      color: Color(0xFF6892A0),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• ${hasWeather ? 'Online' : 'Syncing'}',
                    style: TextStyle(
                      fontSize: networkStateSize,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasWeather
                        ? '$sourceLabel stream active for ${location.city ?? location.province ?? 'Philippines'}'
                        : 'Waiting for weather feed to simulate sensor values',
                    style: const TextStyle(
                      fontSize: 19,
                      color: Color(0xFF667E98),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Active Sensors',
                    style: TextStyle(
                      fontSize: sensorsTitle,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'LAST SYNC: $syncLabel',
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    style: const TextStyle(
                      letterSpacing: 1.4,
                      color: Color(0xFF7A89A2),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SensorTile(
              name: 'Rain Sensor',
              status: hasWeather ? 'Online' : 'Syncing',
              reading: hasWeather
                  ? '${weather!.rainProbability}% chance'
                  : '--',
              time: hasWeather ? 'Live forecast' : 'Pending',
              icon: Icons.water_drop_outlined,
            ),
            const SizedBox(height: 10),
            _SensorTile(
              name: 'Temperature Sensor',
              status: hasWeather ? 'Online' : 'Syncing',
              reading: hasWeather ? '${weather!.temperatureC.round()}°C' : '--',
              time: hasWeather ? 'Live forecast' : 'Pending',
              icon: Icons.thermostat,
            ),
            const SizedBox(height: 10),
            _SensorTile(
              name: 'Humidity Sensor',
              status: hasWeather ? 'Online' : 'Syncing',
              reading: hasWeather ? '${weather!.humidity}% RH' : '--',
              time: hasWeather ? 'Live forecast' : 'Pending',
              icon: Icons.eco_outlined,
            ),
            const SizedBox(height: 10),
            _SensorTile(
              name: 'Sky Condition',
              status: hasWeather ? 'Online' : 'Syncing',
              reading: hasWeather ? weather!.sky : 'Awaiting sync',
              time: hasWeather ? sourceLabel : 'Pending',
              icon: Icons.cloud_outlined,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _InfoStatCard(
                    title: 'Data Source',
                    value: sourceLabel,
                    icon: Icons.dataset_linked_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoStatCard(
                    title: 'Mode',
                    value: 'Forecast',
                    icon: Icons.hub_outlined,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({
    super.key,
    required this.weather,
    required this.location,
    required this.lastWeatherSyncAt,
  });

  final WeatherSnapshot? weather;
  final AppLocation location;
  final DateTime? lastWeatherSyncAt;

  @override
  Widget build(BuildContext context) {
    final titleSize = rs(context, 43, min: 30);
    final now = DateTime.now();
    final rainProbability = weather?.rainProbability ?? 0;
    final shouldWarnRain = rainProbability >= 60;

    return AppViewport(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          children: [
            Row(
              children: [
                const Icon(Icons.arrow_back),
                const SizedBox(width: 10),
                Text(
                  'Alerts',
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.done_all, color: AppColors.primary),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'TODAY',
              style: TextStyle(
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
                color: Color(0xFF66758F),
              ),
            ),
            const SizedBox(height: 10),
            _AlertTile(
              icon: Icons.cloudy_snowing,
              iconColor: Color(0xFFE84E47),
              title: shouldWarnRain
                  ? 'High rain chance - monitor\nauto retract behavior'
                  : 'Rain risk normal for\n${location.label}',
              body:
                  'Current forecast: $rainProbability% rain\nprobability for your configured location.\nAutomation remains active.',
              time: formatClockTime(now.subtract(const Duration(minutes: 3))),
              rightLabel: 'LIVE\nSYNC',
            ),
            const SizedBox(height: 10),
            _AlertTile(
              icon: Icons.check_circle,
              iconColor: Color(0xFF2BB87E),
              title: 'Rack successfully extended',
              body:
                  'Manual command completed. Your\nrack is now fully deployed for drying.',
              time: formatClockTime(now.subtract(const Duration(hours: 2))),
              rightLabel: '2H AGO',
            ),
            const SizedBox(height: 12),
            const Text(
              'YESTERDAY',
              style: TextStyle(
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
                color: Color(0xFF66758F),
              ),
            ),
            const SizedBox(height: 10),
            _AlertTile(
              icon: Icons.warning_amber_rounded,
              iconColor: Color(0xFFF0A63B),
              title: 'High rain probability detected\n($rainProbability%)',
              body:
                  'Forecast is evaluated using your saved\ncoordinates for ${location.label}. Consider\nmanual review when threshold is exceeded.',
              time: formatClockTime(now.subtract(const Duration(hours: 18))),
            ),
            const SizedBox(height: 10),
            _AlertTile(
              icon: Icons.sync,
              iconColor: AppColors.primary,
              title: 'Weather and safety checks updated',
              body:
                  '${formatRelativeTime(lastWeatherSyncAt)}\nLocation-aware forecast logic is running\nfor automation decisions.',
              time: formatClockTime(now.subtract(const Duration(hours: 22))),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.onOpenThreshold,
    required this.onChangeLocation,
    required this.onSignOut,
    required this.currentLocationLabel,
  });

  final VoidCallback onOpenThreshold;
  final Future<void> Function() onChangeLocation;
  final Future<void> Function() onSignOut;
  final String currentLocationLabel;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool darkMode = false;
  bool pushNotifications = true;
  bool emailAlerts = false;

  @override
  Widget build(BuildContext context) {
    final titleSize = rs(context, 30, min: 22);
    final brandSize = rs(context, 44, min: 30);

    return AppViewport(
      child: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.arrow_back),
                  const Spacer(),
                  Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFDDF4EF),
                  border: Border.all(color: const Color(0xFF8ADACA)),
                ),
                child: const Icon(
                  Icons.shield,
                  color: AppColors.primary,
                  size: 34,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Aegis-Dry',
                style: TextStyle(
                  fontSize: brandSize,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain,
                ),
              ),
            ),
            const Center(
              child: Text(
                'Industrial Humidity Control',
                style: TextStyle(color: AppColors.textMuted, fontSize: 15),
              ),
            ),
            const SizedBox(height: 14),
            const _SectionLabel(label: 'PREFERENCES'),
            _SwitchTile(
              icon: Icons.dark_mode_outlined,
              title: 'Dark Mode',
              subtitle: 'Switch between light and dark\nthemes',
              value: darkMode,
              onChanged: (value) => setState(() => darkMode = value),
            ),
            const SizedBox(height: 8),
            const _SectionLabel(label: 'Notifications'),
            _SwitchTile(
              icon: Icons.notifications_none,
              title: 'Push Notifications',
              value: pushNotifications,
              onChanged: (value) => setState(() => pushNotifications = value),
            ),
            _SwitchTile(
              icon: Icons.mail_outline,
              title: 'Email Alerts',
              value: emailAlerts,
              onChanged: (value) => setState(() => emailAlerts = value),
            ),
            const SizedBox(height: 8),
            const _SectionLabel(label: 'DEVICE CALIBRATION'),
            const _ChevronTile(
              title: 'Sensor Calibration',
              subtitle: 'Adjust humidity and temp offsets',
              icon: Icons.tune,
            ),
            GestureDetector(
              onTap: () => widget.onChangeLocation(),
              child: _ChevronTile(
                title: 'Change Location',
                subtitle: widget.currentLocationLabel,
                icon: Icons.location_on_outlined,
              ),
            ),
            GestureDetector(
              onTap: widget.onOpenThreshold,
              child: const _ChevronTile(
                title: 'Threshold Configuration',
                subtitle: 'Set alert limits for all devices',
                icon: Icons.tune_outlined,
              ),
            ),
            const SizedBox(height: 8),
            const _SectionLabel(label: 'APPLICATION INFO'),
            const _SimpleInfoTile(
              title: 'App Version',
              trailing: 'v2.4.1 (Stable)',
            ),
            const _SimpleInfoTile(
              title: 'About Aegis-Dry',
              trailingIcon: Icons.info_outline,
            ),
            GestureDetector(
              onTap: () => widget.onSignOut(),
              child: const _SimpleInfoTile(
                title: 'Sign Out',
                titleColor: Color(0xFFE33131),
                trailingIcon: Icons.logout,
                trailingColor: Color(0xFFE33131),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ThresholdConfigurationScreen extends StatefulWidget {
  const ThresholdConfigurationScreen({super.key});

  @override
  State<ThresholdConfigurationScreen> createState() =>
      _ThresholdConfigurationScreenState();
}

class _ThresholdConfigurationScreenState
    extends State<ThresholdConfigurationScreen> {
  double value = 75;

  @override
  Widget build(BuildContext context) {
    final title = rs(context, 42, min: 30);
    final thresholdLabel = rs(context, 28, min: 20);
    final thresholdValue = rs(context, 40, min: 28);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text(
          'Threshold Configuration',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textMain,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.info_outline, color: AppColors.primary),
          ),
        ],
      ),
      body: AppViewport(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            children: [
              Row(
                children: [
                  const Icon(Icons.eco, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Aegis-Dry Settings',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: title,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMain,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Set the rain probability at which the laundry\nrack should automatically retract to protect\nyour clothes.',
                style: TextStyle(fontSize: 18, color: Color(0xFF60728F)),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFDCE5EF)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Rain Probability Threshold',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: thresholdLabel,
                              color: Color(0xFF3F4F66),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${value.round()}%',
                          style: TextStyle(
                            fontSize: thresholdValue,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: const Color(0xFFD8E0EC),
                        thumbColor: Colors.white,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 10,
                        ),
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        value: value,
                        min: 0,
                        max: 100,
                        onChanged: (v) => setState(() => value = v),
                      ),
                    ),
                    const Row(
                      children: [
                        Text(
                          '0% (LOW)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6F7F98),
                          ),
                        ),
                        Spacer(),
                        Text(
                          '50%',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6F7F98),
                          ),
                        ),
                        Spacer(),
                        Text(
                          '100% (HIGH)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6F7F98),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F8F5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBFEDE2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.analytics_outlined, color: AppColors.primary),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Local Forecast',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            'Rain probability for the next 2 hours is\n12%.',
                            style: TextStyle(color: Color(0xFF4F5F76)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: AppColors.primary,
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Threshold saved at ${value.round()}%'),
                    ),
                  );
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.save_outlined, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Save Settings',
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ManualOverrideScreen extends StatelessWidget {
  const ManualOverrideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final emergencyText = rs(context, 30, min: 22);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text(
          'Manual Override',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textMain,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.info_outline),
          ),
        ],
      ),
      body: AppViewport(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE3E8F1)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.error, color: Color(0xFFFF6B57), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SYSTEM MOVING...',
                          style: TextStyle(
                            color: Color(0xFFFF6B57),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          'Rack is currently transitioning to extended\nposition.',
                          style: TextStyle(color: Color(0xFFFF6B57)),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '45%',
                    style: TextStyle(
                      color: Color(0xFF70809A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDCE4EF)),
              ),
              child: Center(
                child: Container(
                  width: 148,
                  height: 148,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 7),
                  ),
                  child: const Center(
                    child: Text(
                      'Retracted',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(70),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {},
                    child: const Text(
                      'Extend Rack',
                      style: TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentBlue,
                      minimumSize: const Size.fromHeight(70),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {},
                    child: const Text(
                      'Retract Rack',
                      style: TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE4EF)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SAFETY PROTOCOLS',
                    style: TextStyle(
                      letterSpacing: 2,
                      color: Color(0xFF95A3BC),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 10),
                  _SafetyRow(text: 'Clear area of obstacles'),
                  SizedBox(height: 8),
                  _SafetyRow(text: 'Verify weight limit (< 25kg)'),
                  SizedBox(height: 8),
                  _SafetyRow(text: 'Stable power connection'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {},
              child: Text(
                'EMERGENCY STOP',
                style: TextStyle(
                  fontSize: emergencyText,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ManualOverrideLiveScreen extends StatelessWidget {
  const ManualOverrideLiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rackValue = rs(context, 42, min: 30);
    final emergencyText = rs(context, 32, min: 22);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manual Override',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textMain,
              ),
            ),
            Text(
              'AEGIS-DRY SYSTEM',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.primary,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Chip(label: Text('Live Console')),
          ),
        ],
      ),
      body: AppViewport(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDE6F1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'RACK POSITION STATUS',
                    style: TextStyle(
                      letterSpacing: 2,
                      color: Color(0xFF687991),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '50% Extended',
                    style: TextStyle(
                      fontSize: rackValue,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                    child: LinearProgressIndicator(
                      value: 0.5,
                      minHeight: 12,
                      color: AppColors.primary,
                      backgroundColor: Color(0xFFE6ECF5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'RETRACTED PARTIAL (OPTIMAL) FULLY EXTENDED',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7C8AA3),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE9F8F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBAE9DE)),
              ),
              child: const Text(
                'SAFETY PROTOCOL ACTIVE: HOLD BUTTON FOR 2 SECONDS TO INITIATE MOVEMENT. ANY MOVEMENT WILL TRIGGER THE EXTERNAL STROBE LIGHT.',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: Color(0xFF638099),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ConsoleActionButton(
                    title: 'EXTEND RACK',
                    icon: Icons.unfold_more,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ConsoleActionButton(
                    title: 'RETRACT RACK',
                    icon: Icons.unfold_less,
                    darkIcon: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                minimumSize: const Size.fromHeight(58),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {},
              child: Text(
                'EMERGENCY STOP',
                style: TextStyle(
                  fontSize: emergencyText,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'DISENGAGES ALL HYDRAULIC POWER IMMEDIATELY',
                style: TextStyle(
                  letterSpacing: 2,
                  color: Color(0xFF9CA8BC),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ActivityHistoryScreen extends StatelessWidget {
  const ActivityHistoryScreen({
    super.key,
    required this.location,
    required this.weather,
    required this.lastWeatherSyncAt,
  });

  final AppLocation location;
  final WeatherSnapshot? weather;
  final DateTime? lastWeatherSyncAt;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final activities = buildRecentActivityFeed(
      location: location,
      weather: weather,
      lastWeatherSyncAt: lastWeatherSyncAt,
    );

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aegis-Dry',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textMain,
              ),
            ),
            Text(
              'Activity History - ${location.label}',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.info_outline, color: AppColors.primary),
          ),
        ],
      ),
      body: AppViewport(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'Search logs or events...',
                hintStyle: const TextStyle(color: Color(0xFF9AA9C0)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF8FA0BA)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFD8E1EC)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFD8E1EC)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChipActive(label: 'All\nLogs'),
                  SizedBox(width: 8),
                  _FilterChipMute(label: 'Sensors'),
                  SizedBox(width: 8),
                  _FilterChipMute(label: 'System'),
                  SizedBox(width: 8),
                  _FilterChipMute(label: 'Manual'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'TODAY - ${formatDayDate(now)}',
              style: TextStyle(
                color: Color(0xFF7588A4),
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < activities.length; i++)
              _TimelineItem(
                title: activities[i].title,
                subtitle: activities[i].subtitle,
                time: formatActivityTime(activities[i].timestamp),
                response: activities[i].response,
                icon: activities[i].icon,
                isLast: i == activities.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final valueSize = rs(context, 24, min: 18);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E0EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: valueSize,
              fontWeight: FontWeight.w700,
              color: AppColors.textMain,
            ),
          ),
          Text(subtitle, style: const TextStyle(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor = AppColors.textMain,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final labelSize = rs(context, 22, min: 16);
    final valueSize = rs(context, 24, min: 17);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD9E2EE)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFA1B0C9)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: labelSize, color: AppColors.textMain),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: valueSize,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    this.isMuted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String time;
  final bool isMuted;

  @override
  Widget build(BuildContext context) {
    final titleSize = rs(context, 24, min: 18);

    final Color titleColor = isMuted
        ? const Color(0xFF8F9BB1)
        : AppColors.textMain;
    final Color subtitleColor = isMuted
        ? const Color(0xFFAEB9CB)
        : AppColors.textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9E1EC)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: isMuted
                ? const Color(0xFFF2F5FA)
                : const Color(0xFFE6F7F3),
            child: Icon(
              icon,
              color: isMuted ? const Color(0xFFA2B2C7) : AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                Text(subtitle, style: TextStyle(color: subtitleColor)),
              ],
            ),
          ),
          Text(time, style: const TextStyle(color: Color(0xFF8C9DB5))),
        ],
      ),
    );
  }
}

class _SensorTile extends StatelessWidget {
  const _SensorTile({
    required this.name,
    required this.status,
    required this.reading,
    required this.time,
    required this.icon,
  });

  final String name;
  final String status;
  final String reading;
  final String time;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final titleSize = rs(context, 24, min: 18);
    final valueSize = rs(context, 24, min: 17);

    const Color dotColor = Color(0xFF2DB367);
    const Color readColor = AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8E1EC)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FB),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.accentBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status,
                      style: const TextStyle(color: Color(0xFF7888A1)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(time, style: const TextStyle(color: Color(0xFF9BA8BE))),
              Text(
                reading,
                style: TextStyle(fontSize: valueSize, color: readColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoStatCard extends StatelessWidget {
  const _InfoStatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final valueSize = rs(context, 34, min: 24);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8E1ED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(color: Color(0xFF667A98))),
          Text(
            value,
            style: TextStyle(
              fontSize: valueSize,
              color: AppColors.textMain,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.time,
    this.rightLabel,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final String time;
  final String? rightLabel;

  @override
  Widget build(BuildContext context) {
    final titleSize = rs(context, 24, min: 18);
    final bodySize = rs(context, 16, min: 13);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE4EF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: iconColor.withValues(alpha: 0.12),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: bodySize,
                    color: Color(0xFF61738D),
                  ),
                ),
                const SizedBox(height: 8),
                Text(time, style: const TextStyle(color: Color(0xFF8C9BB2))),
              ],
            ),
          ),
          if (rightLabel != null)
            Text(
              rightLabel!,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFFA8B4C8),
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.8,
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF7A8AA3)),
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, color: AppColors.textMain),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
        trailing: Switch(
          value: value,
          activeThumbColor: AppColors.primary,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _ChevronTile extends StatelessWidget {
  const _ChevronTile({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE3E9F3))),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF7D8CA5)),
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, color: AppColors.textMain),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF90A0B8)),
      ),
    );
  }
}

class _SimpleInfoTile extends StatelessWidget {
  const _SimpleInfoTile({
    required this.title,
    this.trailing,
    this.trailingIcon,
    this.titleColor = AppColors.textMain,
    this.trailingColor = const Color(0xFF7E8EA7),
  });

  final String title;
  final String? trailing;
  final IconData? trailingIcon;
  final Color titleColor;
  final Color trailingColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE3E9F2))),
      ),
      child: ListTile(
        title: Text(title, style: TextStyle(fontSize: 18, color: titleColor)),
        trailing: trailing != null
            ? Text(trailing!, style: TextStyle(color: trailingColor))
            : (trailingIcon != null
                  ? Icon(trailingIcon, color: trailingColor)
                  : null),
      ),
    );
  }
}

class _SafetyRow extends StatelessWidget {
  const _SafetyRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle, size: 16, color: Color(0xFF6ACEA1)),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontSize: 16, color: Color(0xFF566A86)),
        ),
      ],
    );
  }
}

class _ConsoleActionButton extends StatelessWidget {
  const _ConsoleActionButton({
    required this.title,
    required this.icon,
    this.darkIcon = false,
  });

  final String title;
  final IconData icon;
  final bool darkIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD9E1EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFEAF3F2),
            child: Icon(
              icon,
              color: darkIcon ? const Color(0xFF70839F) : AppColors.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textMain,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipActive extends StatelessWidget {
  const _FilterChipActive({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FilterChipMute extends StatelessWidget {
  const _FilterChipMute({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E1EC)),
      ),
      child: Text(label, style: const TextStyle(color: Color(0xFF5E6F89))),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.response,
    this.icon = Icons.water_drop_outlined,
    this.isLast = false,
  });

  final String title;
  final String subtitle;
  final String time;
  final String response;
  final IconData icon;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 10,
                  backgroundColor: const Color(0xFFEAF0F7),
                  child: Icon(icon, size: 13, color: const Color(0xFF3E516B)),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.only(top: 4),
                      color: const Color(0xFFD3DDEB),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          color: AppColors.textMain,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      time,
                      style: const TextStyle(color: Color(0xFF8496B0)),
                    ),
                  ],
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF60718A),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFDCE4EF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SYSTEM RESPONSE',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        response,
                        style: const TextStyle(color: Color(0xFF4B5D76)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
