import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aegis_dry_mobile/services/hardware_service.dart';
import 'package:aegis_dry_mobile/widgets/silong_logo_image.dart';

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

String _weatherSyncErrorMessage(Object error) {
  final raw = error.toString().replaceFirst('Bad state: ', '').trim();
  if (raw.isEmpty) {
    return 'Weather sync is temporarily unavailable. Please try again.';
  }

  final lower = raw.toLowerCase();
  final looksLikeNetworkFailure =
      lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('no address associated with hostname') ||
      lower.contains('name or service not known') ||
      lower.contains('temporary failure in name resolution') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('connection timed out') ||
      lower.contains('timed out') ||
      lower.contains('api.open-meteo.com') ||
      lower.contains('api.openweathermap.org') ||
      lower.contains('geocoding-api.open-meteo.com');

  if (looksLikeNetworkFailure) {
    return 'Weather sync is temporarily unavailable. Check your internet connection and try again.';
  }

  return raw;
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

  return 'SILONG User';
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

String firstNameFromDisplayName(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return 'User';
  }

  final emailName = trimmed.contains('@') ? trimmed.split('@').first : trimmed;
  final cleaned = emailName.replaceAll(RegExp(r'[_\.]+'), ' ').trim();
  if (cleaned.isEmpty) {
    return 'User';
  }

  final first = cleaned.split(RegExp(r'\s+')).first.trim();
  if (first.isEmpty) {
    return 'User';
  }
  return first[0].toUpperCase() + first.substring(1);
}

Future<String> loadCurrentUserFirstName() async {
  if (!_supabaseInitialized) {
    return 'User';
  }
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) {
    return 'User';
  }

  try {
    final data = await client
        .from('user_profiles')
        .select('full_name')
        .eq('user_id', user.id)
        .maybeSingle();
    final fullName = (data?['full_name'] as String?)?.trim();
    if (fullName != null && fullName.isNotEmpty) {
      return firstNameFromDisplayName(fullName);
    }
  } catch (_) {
    // Fall back to auth metadata/email when profile lookup is unavailable.
  }

  return firstNameFromDisplayName(_resolveProfileName(user: user));
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
      title: 'SILONG',
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
        textTheme: GoogleFonts.josefinSansTextTheme(
          const TextTheme(
            headlineLarge: TextStyle(fontSize: 42, fontWeight: FontWeight.w700),
            titleLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
            titleMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
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
      final label =
          (data['location_label'] as String?)?.trim() ??
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

class ThresholdStore {
  static const String _rainProbabilityKey =
      'automation.rain_probability_threshold';
  static const int defaultRainProbability = 75;

  static Future<int> loadRainProbability() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_rainProbabilityKey);
    return (value ?? defaultRainProbability).clamp(0, 100);
  }

  static Future<void> saveRainProbability(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_rainProbabilityKey, value.clamp(0, 100));
  }
}

class NotificationPreferences {
  static const String _enabledKey = 'notifications.push_enabled';

  static Future<bool> loadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  static Future<void> saveEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }
}

class PushNotificationService {
  static const MethodChannel _channel = MethodChannel('sun_dry/notifications');

  static Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> show({
    required String title,
    required String body,
  }) async {
    if (!await NotificationPreferences.loadEnabled()) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('showNotification', {
            'title': title,
            'body': body,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}

class SavedAlert {
  const SavedAlert({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
    this.rightLabel,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool isRead;
  final String? rightLabel;

  static SavedAlert? fromMap(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final row = raw.map((key, value) => MapEntry(key.toString(), value));
    final id = row['id']?.toString();
    final type = row['type']?.toString();
    final title = row['title']?.toString();
    final body = row['body']?.toString();
    final timestamp = DateTime.tryParse(row['timestamp']?.toString() ?? '');
    if (id == null ||
        type == null ||
        title == null ||
        body == null ||
        timestamp == null) {
      return null;
    }
    return SavedAlert(
      id: id,
      type: type,
      title: title,
      body: body,
      timestamp: timestamp,
      isRead: row['is_read'] == true,
      rightLabel: row['right_label']?.toString(),
    );
  }
}

class AlertStore {
  static Future<List<SavedAlert>> load() async {
    if (!_supabaseInitialized) {
      return const <SavedAlert>[];
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return const <SavedAlert>[];
    }

    final rows = await Supabase.instance.client
        .from('user_alerts')
        .select('id, type, title, body, timestamp, right_label, is_read')
        .eq('user_id', user.id)
        .order('timestamp', ascending: false)
        .limit(40);
    return (rows as List<dynamic>)
        .map(SavedAlert.fromMap)
        .whereType<SavedAlert>()
        .toList();
  }

  static Future<bool> saveAlert(SavedAlert alert) async {
    if (!_supabaseInitialized) {
      return false;
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return false;
    }

    try {
      await Supabase.instance.client.from('user_alerts').insert({
        'id': alert.id,
        'user_id': user.id,
        'type': alert.type,
        'title': alert.title,
        'body': alert.body,
        'timestamp': alert.timestamp.toUtc().toIso8601String(),
        'right_label': alert.rightLabel,
        'is_read': alert.isRead,
      });
      return true;
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        return false;
      }
      debugPrint('Alert persistence failed: ${error.message}');
      return false;
    } catch (error) {
      debugPrint('Alert persistence failed: $error');
      return false;
    }
  }

  static Future<void> markAllRead() async {
    if (!_supabaseInitialized) {
      return;
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return;
    }
    await Supabase.instance.client
        .from('user_alerts')
        .update({'is_read': true})
        .eq('user_id', user.id)
        .eq('is_read', false);
  }
}

class RackMovementEvent {
  const RackMovementEvent({
    required this.id,
    required this.deviceId,
    required this.action,
    required this.trigger,
    required this.mode,
    required this.status,
    required this.startedAt,
    this.completedAt,
    this.durationMs,
  });

  final String id;
  final String deviceId;
  final String action;
  final String trigger;
  final String mode;
  final String status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int? durationMs;

  factory RackMovementEvent.fromMap(Map<String, dynamic> row) {
    return RackMovementEvent(
      id: row['id']?.toString() ?? '',
      deviceId: row['device_id']?.toString() ?? 'ESP32_RACK_01',
      action: row['action']?.toString() ?? 'UNKNOWN',
      trigger: row['trigger']?.toString() ?? 'SYSTEM',
      mode: row['mode']?.toString() ?? 'AUTO',
      status: row['status']?.toString() ?? 'COMPLETED',
      startedAt:
          DateTime.tryParse(row['started_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      completedAt: DateTime.tryParse(
        row['completed_at']?.toString() ?? '',
      )?.toLocal(),
      durationMs: row['duration_ms'] is num
          ? (row['duration_ms'] as num).round()
          : int.tryParse(row['duration_ms']?.toString() ?? ''),
    );
  }
}

class RackMovementAnalytics {
  const RackMovementAnalytics({
    required this.events,
    required this.rangeStart,
    required this.rangeEnd,
  });

  final List<RackMovementEvent> events;
  final DateTime rangeStart;
  final DateTime rangeEnd;

  int get extensions =>
      events.where((event) => event.action == 'EXTEND').length;
  int get retractions =>
      events.where((event) => event.action == 'RETRACT').length;
  int get automaticEvents =>
      events.where((event) => event.mode == 'AUTO').length;
  int get manualEvents =>
      events.where((event) => event.mode == 'MANUAL').length;
  int get rainSensorEvents =>
      events.where((event) => event.trigger == 'RAIN_SENSOR').length;
  int get weatherThresholdEvents =>
      events.where((event) => event.trigger == 'WEATHER_THRESHOLD').length;
  int get manualTriggerEvents =>
      events.where((event) => event.trigger == 'MANUAL').length;
  int get systemEvents =>
      events.where((event) => event.trigger == 'SYSTEM').length;
  int get completedEvents =>
      events.where((event) => event.status == 'COMPLETED').length;
  int get failedEvents =>
      events.where((event) => event.status == 'FAILED').length;
  bool get hasData => events.isNotEmpty;
  int get totalEvents => events.length;

  RackMovementEvent? get latest => events.isEmpty ? null : events.first;

  Duration? get averageDuration {
    final durations = events
        .map((event) => event.durationMs)
        .whereType<int>()
        .where((value) => value >= 0)
        .toList();
    if (durations.isEmpty) {
      return null;
    }
    final average =
        durations.fold<int>(0, (sum, value) => sum + value) ~/ durations.length;
    return Duration(milliseconds: average);
  }

  String get interpretation {
    if (!hasData) {
      return 'No rack movement history is available for this period.';
    }
    if (failedEvents > 0) {
      return '$failedEvents movement${failedEvents == 1 ? '' : 's'} need attention.';
    }
    if (manualEvents > automaticEvents) {
      return 'The rack was mostly managed manually for operator control.';
    }
    if (automaticEvents > manualEvents) {
      return 'The rack was mostly managed automatically for weather protection.';
    }
    if (extensions + retractions >= 8) {
      return 'The rack moved frequently during this period.';
    }
    return 'Rack movement activity is within a normal range.';
  }

  static RackMovementAnalytics fromEvents(
    List<RackMovementEvent> source, {
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    final events =
        source
            .where(
              (event) =>
                  !event.startedAt.isBefore(rangeStart) &&
                  event.startedAt.isBefore(rangeEnd),
            )
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return RackMovementAnalytics(
      events: List<RackMovementEvent>.unmodifiable(events),
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
  }
}

class RackMovementStore {
  static const String _deviceId = 'ESP32_RACK_01';

  static String? _ownerEmail() {
    if (!_supabaseInitialized) {
      return null;
    }
    return Supabase.instance.client.auth.currentUser?.email
        ?.trim()
        .toLowerCase();
  }

  static Future<bool> record({
    required String action,
    required String trigger,
    required String mode,
    String status = 'COMPLETED',
    DateTime? startedAt,
    DateTime? completedAt,
    int? durationMs,
  }) async {
    final user = _supabaseInitialized
        ? Supabase.instance.client.auth.currentUser
        : null;
    final ownerEmail = _ownerEmail();
    if (user == null || ownerEmail == null || ownerEmail.isEmpty) {
      return false;
    }

    try {
      await Supabase.instance.client.from('rack_movement_events').insert({
        'user_id': user.id,
        'owner_email': ownerEmail,
        'device_id': _deviceId,
        'action': action,
        'trigger': trigger,
        'mode': mode,
        'status': status,
        'started_at': (startedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'completed_at': completedAt?.toUtc().toIso8601String(),
        'duration_ms': durationMs,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> completePending(String action) async {
    final user = _supabaseInitialized
        ? Supabase.instance.client.auth.currentUser
        : null;
    if (user == null) {
      return;
    }

    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('rack_movement_events')
          .select('id, started_at')
          .eq('user_id', user.id)
          .eq('device_id', _deviceId)
          .eq('action', action)
          .eq('status', 'REQUESTED')
          .order('started_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) {
        return;
      }

      final row = rows.first;
      final completedAt = DateTime.now();
      final startedAt =
          DateTime.tryParse(row['started_at']?.toString() ?? '') ?? completedAt;
      await client
          .from('rack_movement_events')
          .update({
            'status': 'COMPLETED',
            'completed_at': completedAt.toUtc().toIso8601String(),
            'duration_ms': completedAt.difference(startedAt).inMilliseconds,
          })
          .eq('id', row['id'].toString())
          .eq('user_id', user.id);
    } catch (_) {
      // Keep realtime device updates flowing if analytics persistence fails.
    }
  }

  static Future<RackMovementAnalytics> load({int days = 7}) async {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));
    final end = now.add(const Duration(days: 1));
    if (!_supabaseInitialized || _ownerEmail() == null) {
      return RackMovementAnalytics.fromEvents(
        const <RackMovementEvent>[],
        rangeStart: start,
        rangeEnd: end,
      );
    }

    try {
      final rows = await Supabase.instance.client
          .from('rack_movement_events')
          .select(
            'id, device_id, action, trigger, mode, status, started_at, completed_at, duration_ms',
          )
          .eq('device_id', _deviceId)
          .gte('started_at', start.toUtc().toIso8601String())
          .lt('started_at', end.toUtc().toIso8601String())
          .order('started_at', ascending: false);
      final events = (rows as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(RackMovementEvent.fromMap)
          .toList();
      return RackMovementAnalytics.fromEvents(
        events,
        rangeStart: start,
        rangeEnd: end,
      );
    } catch (_) {
      return RackMovementAnalytics.fromEvents(
        const <RackMovementEvent>[],
        rangeStart: start,
        rangeEnd: end,
      );
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
    this.forecast = const <ForecastPoint>[],
    this.predictive,
  });

  final double temperatureC;
  final String sky;
  final int humidity;
  final int rainProbability;
  final String source;
  final List<ForecastPoint> forecast;
  final PredictiveAnalytics? predictive;

  String get temperatureFText => '${((temperatureC * 9 / 5) + 32).round()}°F';
}

class ForecastPoint {
  const ForecastPoint({
    required this.timestamp,
    required this.rainProbability,
    this.temperatureC,
    this.cloudCover,
  });

  final DateTime timestamp;
  final int rainProbability;
  final double? temperatureC;
  final int? cloudCover;
}

class PredictiveAnalytics {
  const PredictiveAnalytics({
    required this.windowHours,
    required this.nextRainProbability,
    required this.nextForecastTime,
    required this.maxRainProbability,
    required this.avgRainProbability,
    required this.peakTime,
    required this.dryingWindowHours,
    required this.bestDryingWindowHours,
    required this.bestDryingStartTime,
    required this.bestDryingEndTime,
    required this.dryingScore,
    required this.riskLevel,
    required this.recommendation,
    required this.firstHighRiskTime,
  });

  final int windowHours;
  final int nextRainProbability;
  final DateTime nextForecastTime;
  final int maxRainProbability;
  final int avgRainProbability;
  final DateTime? peakTime;
  final int dryingWindowHours;
  final int bestDryingWindowHours;
  final DateTime? bestDryingStartTime;
  final DateTime? bestDryingEndTime;
  final int dryingScore;
  final String riskLevel;
  final String recommendation;
  final DateTime? firstHighRiskTime;

  String get bestDryingWindowLabel {
    final start = bestDryingStartTime;
    final end = bestDryingEndTime;
    if (!hasClearBestDryingWindow || start == null || end == null) {
      return 'No best drying weather at this time period';
    }
    return formatForecastWindow(start, end);
  }

  bool get hasClearBestDryingWindow {
    if (bestDryingStartTime == null || bestDryingEndTime == null) {
      return false;
    }
    if (bestDryingWindowHours >= windowHours) {
      return false;
    }
    return dryingScore >= 50;
  }

  String get nextBestAction {
    final start = bestDryingStartTime;
    final end = bestDryingEndTime;
    if (!hasClearBestDryingWindow || start == null || end == null) {
      return 'No best drying weather at this time period';
    }

    final now = DateTime.now();
    final startDiff = start.difference(now);
    if (startDiff.inMinutes.abs() <= 30 &&
        now.isAfter(start.subtract(const Duration(minutes: 30))) &&
        now.isBefore(end.add(const Duration(minutes: 30)))) {
      return 'Dry now';
    }

    if (riskLevel == 'HIGH') {
      return firstHighRiskTime == null
          ? 'Retract soon'
          : 'Retract by ${formatClockTime(firstHighRiskTime!)}';
    }

    if (startDiff.inMinutes > 0) {
      return 'Wait until ${formatClockTime(start)}';
    }

    return 'Keep drying through ${formatClockTime(end)}';
  }

  String get nextRainRiskLabel {
    final riskTime = firstHighRiskTime;
    if (riskTime == null) {
      return 'No major rain spike in range';
    }
    return 'Rain risk rises at ${formatClockTime(riskTime)}';
  }
}

class OpenWeatherService {
  static const String _apiKeyFromDefine = String.fromEnvironment(
    'OPENWEATHERMAP_API_KEY',
  );
  static const String _edgeFunctionNameFromDefine = String.fromEnvironment(
    'OPENWEATHER_EDGE_FUNCTION',
  );

  static String get _edgeFunctionName => _normalizeEnvValue(
    dotenv.env['OPENWEATHER_EDGE_FUNCTION'] ?? _edgeFunctionNameFromDefine,
  );

  static String get _apiKey => _normalizeEnvValue(
    dotenv.env['OPENWEATHERMAP_API_KEY'] ?? _apiKeyFromDefine,
  );

  static bool get hasApiKey => _apiKey.trim().isNotEmpty;

  static bool get hasCloudProvider =>
      _supabaseInitialized && _edgeFunctionName.trim().isNotEmpty;

  static bool get hasAnyOpenWeatherProvider => hasCloudProvider || hasApiKey;

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
        'User-Agent': 'sun-daing-dry-mobile/1.0 (location-setup)',
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
    try {
      if (hasCloudProvider) {
        try {
          return await _getSnapshotFromSupabaseEdge(
            latitude: latitude,
            longitude: longitude,
          );
        } catch (_) {
          // Fall through to the direct/fallback providers while the cloud function
          // is being deployed or its OpenWeather secret is being configured.
        }
      }

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

      return await _getSnapshotFromOpenMeteo(
        latitude: latitude,
        longitude: longitude,
      );
    } catch (error) {
      throw StateError(_weatherSyncErrorMessage(error));
    }
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

    return _buildSnapshotFromOpenWeatherPayload(
      weatherJson: weatherJson,
      forecastJson: forecastJson,
      sourceLabel: 'OpenWeather',
    );
  }

  static Future<WeatherSnapshot> _getSnapshotFromSupabaseEdge({
    required double latitude,
    required double longitude,
  }) async {
    if (!hasCloudProvider) {
      throw StateError(
        'OpenWeather edge function is not configured. Set OPENWEATHER_EDGE_FUNCTION in .env.',
      );
    }

    final client = Supabase.instance.client;
    final response = await client.functions.invoke(
      _edgeFunctionName,
      body: <String, dynamic>{
        'lat': latitude,
        'lon': longitude,
        'latitude': latitude,
        'longitude': longitude,
      },
    );

    if (response.status < 200 || response.status >= 300) {
      final details = _extractFunctionError(response.data);
      throw StateError(
        'OpenWeather edge function failed (${response.status}): $details',
      );
    }

    final payload = _coercePayload(response.data);
    if (payload.isEmpty) {
      throw StateError('OpenWeather edge function returned empty data.');
    }

    final normalized = _coercePayload(payload['data'] ?? payload);
    return _parseEdgePayload(normalized);
  }

  static Future<WeatherSnapshot> _getSnapshotFromOpenMeteo({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'current': 'temperature_2m,relative_humidity_2m,weather_code',
      'hourly': 'precipitation_probability,cloud_cover,temperature_2m',
      'forecast_days': '7',
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
    final forecastPoints = <ForecastPoint>[];
    if (hourly is Map<String, dynamic>) {
      final pops = hourly['precipitation_probability'];
      final times = hourly['time'];
      final cloudCover = hourly['cloud_cover'];
      final temperatures = hourly['temperature_2m'];
      if (times is List<dynamic> && pops is List<dynamic>) {
        final count = math.min(
          times.length,
          cloudCover is List<dynamic>
              ? math.min(pops.length, cloudCover.length)
              : pops.length,
        );
        for (var i = 0; i < count; i++) {
          final timestamp = _parseTimestamp(times[i]);
          final pop = _readInt(pops[i]) ?? 0;
          if (timestamp != null) {
            forecastPoints.add(
              ForecastPoint(
                timestamp: timestamp,
                rainProbability: pop.clamp(0, 100),
                cloudCover: cloudCover is List<dynamic>
                    ? (_readInt(cloudCover[i]) ?? 0).clamp(0, 100)
                    : null,
                temperatureC: temperatures is List<dynamic>
                    ? _readDouble(temperatures[i])
                    : null,
              ),
            );
          }
        }
      }
    }

    final rainProbability = _rainProbabilityForAutomation(forecastPoints);
    final predictive = _buildPredictiveAnalytics(
      forecastPoints,
      currentHumidity: humidity,
    );

    return WeatherSnapshot(
      temperatureC: temperatureC,
      sky: sky,
      humidity: humidity,
      rainProbability: rainProbability,
      source: 'Open-Meteo',
      forecast: forecastPoints,
      predictive: predictive,
    );
  }

  static WeatherSnapshot _buildSnapshotFromOpenWeatherPayload({
    required Map<String, dynamic> weatherJson,
    required Map<String, dynamic> forecastJson,
    required String sourceLabel,
  }) {
    final temp = _readDouble(weatherJson['main']?['temp']) ?? 0;
    final humidity = _readInt(weatherJson['main']?['humidity']) ?? 0;
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
    final forecastPoints = _buildForecastPointsFromOpenWeather(forecastList);
    final rainPop = _rainProbabilityForAutomation(forecastPoints);
    final predictive = _buildPredictiveAnalytics(
      forecastPoints,
      currentHumidity: humidity,
    );

    return WeatherSnapshot(
      temperatureC: temp,
      sky: sky,
      humidity: humidity,
      rainProbability: rainPop.clamp(0, 100),
      source: sourceLabel,
      forecast: forecastPoints,
      predictive: predictive,
    );
  }

  static WeatherSnapshot _parseEdgePayload(Map<String, dynamic> payload) {
    if (payload.containsKey('weather') && payload.containsKey('forecast')) {
      final weatherJson = _coercePayload(payload['weather']);
      final forecastJson = _coercePayload(payload['forecast']);
      return _buildSnapshotFromOpenWeatherPayload(
        weatherJson: weatherJson,
        forecastJson: forecastJson,
        sourceLabel: 'OpenWeather Cloud',
      );
    }

    if (payload.containsKey('current') && payload.containsKey('hourly')) {
      return _buildSnapshotFromOneCall(
        payload,
        sourceLabel: 'OpenWeather Cloud',
      );
    }

    if (payload.containsKey('current') && payload.containsKey('forecast')) {
      return _buildSnapshotFromCompactForecast(
        payload,
        sourceLabel: 'OpenWeather Cloud',
      );
    }

    if (payload.containsKey('main') && payload.containsKey('weather')) {
      return _buildSnapshotFromOpenWeatherPayload(
        weatherJson: payload,
        forecastJson: const <String, dynamic>{'list': []},
        sourceLabel: 'OpenWeather Cloud',
      );
    }

    throw StateError(
      'Unsupported OpenWeather edge payload. Expected weather/forecast or current/hourly fields.',
    );
  }

  static WeatherSnapshot _buildSnapshotFromOneCall(
    Map<String, dynamic> payload, {
    required String sourceLabel,
  }) {
    final current = _coercePayload(payload['current']);
    final hourly = payload['hourly'] as List<dynamic>? ?? const <dynamic>[];

    final temp = _readDouble(current['temp']) ?? 0;
    final humidity = _readInt(current['humidity']) ?? 0;
    final skyList =
        (current['weather'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    final sky = skyList.isNotEmpty
        ? skyList.first['main']?.toString() ?? 'Unknown'
        : 'Unknown';

    final forecastPoints = _buildForecastPointsFromOneCall(hourly);
    final rainPop = _rainProbabilityForAutomation(forecastPoints);
    final predictive = _buildPredictiveAnalytics(
      forecastPoints,
      currentHumidity: humidity,
    );

    return WeatherSnapshot(
      temperatureC: temp,
      sky: sky,
      humidity: humidity,
      rainProbability: rainPop.clamp(0, 100),
      source: sourceLabel,
      forecast: forecastPoints,
      predictive: predictive,
    );
  }

  static WeatherSnapshot _buildSnapshotFromCompactForecast(
    Map<String, dynamic> payload, {
    required String sourceLabel,
  }) {
    final current = _coercePayload(payload['current']);
    final forecast = payload['forecast'] as List<dynamic>? ?? const <dynamic>[];

    final temp =
        _readDouble(current['temp']) ?? _readDouble(current['tempC']) ?? 0;
    final humidity = _readInt(current['humidity']) ?? 0;
    final sky =
        _readString(current['sky']) ??
        _readString(current['condition']) ??
        'Unknown';

    final forecastPoints = _buildForecastPointsFromCompact(forecast);
    final rainPop =
        _readInt(current['rainProbability']) ??
        _readInt(current['rain_probability']) ??
        _rainProbabilityForAutomation(forecastPoints);
    final predictive = _buildPredictiveAnalytics(
      forecastPoints,
      currentHumidity: humidity,
    );

    return WeatherSnapshot(
      temperatureC: temp,
      sky: sky,
      humidity: humidity,
      rainProbability: rainPop.clamp(0, 100),
      source: sourceLabel,
      forecast: forecastPoints,
      predictive: predictive,
    );
  }

  static List<ForecastPoint> _buildForecastPointsFromOpenWeather(
    List<Map<String, dynamic>> forecastList,
  ) {
    final forecastPoints = <ForecastPoint>[];
    for (final entry in forecastList) {
      final timestamp = _parseTimestamp(entry['dt']);
      if (timestamp == null) {
        continue;
      }
      final popValue = ((_readDouble(entry['pop']) ?? 0) * 100).round();
      final tempValue = _readDouble(entry['main']?['temp']);
      final cloudCover = _readInt(entry['clouds']?['all']);
      forecastPoints.add(
        ForecastPoint(
          timestamp: timestamp,
          rainProbability: popValue.clamp(0, 100),
          temperatureC: tempValue,
          cloudCover: cloudCover?.clamp(0, 100),
        ),
      );
    }
    return forecastPoints;
  }

  static List<ForecastPoint> _buildForecastPointsFromOneCall(
    List<dynamic> hourly,
  ) {
    final points = <ForecastPoint>[];
    for (final entry in hourly) {
      if (entry is! Map) {
        continue;
      }
      final row = entry.map((key, value) => MapEntry(key.toString(), value));
      final timestamp = _parseTimestamp(row['dt']);
      if (timestamp == null) {
        continue;
      }
      final popValue = ((_readDouble(row['pop']) ?? 0) * 100).round();
      final tempValue = _readDouble(row['temp']);
      final cloudCover = _readInt(row['clouds'] ?? row['cloud_cover']);
      points.add(
        ForecastPoint(
          timestamp: timestamp,
          rainProbability: popValue.clamp(0, 100),
          temperatureC: tempValue,
          cloudCover: cloudCover?.clamp(0, 100),
        ),
      );
    }
    return points;
  }

  static List<ForecastPoint> _buildForecastPointsFromCompact(
    List<dynamic> forecast,
  ) {
    final points = <ForecastPoint>[];
    for (final entry in forecast) {
      if (entry is! Map) {
        continue;
      }
      final row = entry.map((key, value) => MapEntry(key.toString(), value));
      final timestamp = _parseTimestamp(
        row['dt'] ?? row['timestamp'] ?? row['time'],
      );
      if (timestamp == null) {
        continue;
      }
      final popValue =
          _readInt(
            row['rainProbability'] ??
                row['rain_probability'] ??
                row['pop'] ??
                row['chance'],
          ) ??
          0;
      final tempValue = _readDouble(row['temp'] ?? row['tempC']);
      final cloudCover = _readInt(row['cloudCover'] ?? row['cloud_cover']);
      points.add(
        ForecastPoint(
          timestamp: timestamp,
          rainProbability: popValue.clamp(0, 100),
          temperatureC: tempValue,
          cloudCover: cloudCover?.clamp(0, 100),
        ),
      );
    }
    return points;
  }

  static Map<String, dynamic> _coercePayload(dynamic data) {
    if (data == null) {
      return <String, dynamic>{};
    }
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    if (data is Uint8List) {
      try {
        final decoded = jsonDecode(utf8.decode(data));
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }

  static String _extractFunctionError(dynamic data) {
    if (data == null) {
      return 'No error details returned.';
    }
    if (data is String) {
      return data.trim().isEmpty ? 'Unknown error.' : data.trim();
    }
    if (data is Uint8List) {
      final text = utf8.decode(data, allowMalformed: true).trim();
      return text.isEmpty ? 'Unknown error.' : text;
    }
    final payload = _coercePayload(data);
    final message =
        payload['error'] ?? payload['message'] ?? payload['details'];
    if (message != null) {
      return message.toString();
    }
    return data.toString();
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is num) {
      final millis = value < 1000000000000 ? value.toInt() * 1000 : value;
      return DateTime.fromMillisecondsSinceEpoch(
        millis.toInt(),
        isUtc: true,
      ).toLocal();
    }
    if (value is String) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  static double? _readDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  static String? _readString(dynamic value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static List<ForecastPoint> _upcomingForecastPoints(
    List<ForecastPoint> points,
  ) {
    final now = DateTime.now();
    final sorted = points.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (sorted.isEmpty) {
      return sorted;
    }

    // OpenWeather's forecast is bucketed, so the most recent bucket is still
    // relevant for "right now" if the current time is between forecast slots.
    final lastCurrentIndex = sorted.lastIndexWhere(
      (point) => !point.timestamp.isAfter(now),
    );
    if (lastCurrentIndex >= 0) {
      return sorted.sublist(lastCurrentIndex);
    }

    return sorted;
  }

  static int _rainProbabilityForAutomation(List<ForecastPoint> points) {
    final upcoming = _upcomingForecastPoints(points);
    if (upcoming.isEmpty) {
      return 0;
    }

    final lookAheadCount = math.min(upcoming.length, 3);
    final nearTermWindow = upcoming.take(lookAheadCount);
    final peakChance = nearTermWindow.fold<int>(
      0,
      (peak, point) => math.max(peak, point.rainProbability),
    );
    return peakChance.clamp(0, 100);
  }

  static int _estimateForecastIntervalHours(List<ForecastPoint> points) {
    if (points.length < 2) {
      return 3;
    }
    final sorted = points.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final minutes = sorted[1].timestamp
        .difference(sorted[0].timestamp)
        .inMinutes;
    if (minutes <= 0) {
      return 3;
    }
    return (minutes / 60).round().clamp(1, 3);
  }

  static PredictiveAnalytics? _buildPredictiveAnalytics(
    List<ForecastPoint> points, {
    required int currentHumidity,
  }) {
    if (points.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    final upcoming = _upcomingForecastPoints(points);
    if (upcoming.isEmpty) {
      return null;
    }

    final horizonEnd = now.add(const Duration(days: 7));
    final horizon = upcoming
        .where((point) => point.timestamp.isBefore(horizonEnd))
        .toList();
    final windowPoints = horizon.isNotEmpty
        ? horizon
        : upcoming.take(8).toList();
    if (windowPoints.isEmpty) {
      return null;
    }

    final peakPoint = windowPoints.reduce(
      (current, next) =>
          next.rainProbability >= current.rainProbability ? next : current,
    );
    final intervalHours = _estimateForecastIntervalHours(windowPoints);
    final maxPop = peakPoint.rainProbability;
    final avgPop =
        (windowPoints.fold<int>(
                  0,
                  (sum, point) => sum + point.rainProbability,
                ) /
                windowPoints.length)
            .round();
    final windowHours = math.min(
      7 * 24,
      math.max(1, windowPoints.length * intervalHours),
    );

    final firstHighRiskIndex = windowPoints.indexWhere(
      (point) => point.rainProbability >= 60,
    );
    final firstHighRiskTime = firstHighRiskIndex >= 0
        ? windowPoints[firstHighRiskIndex].timestamp
        : null;
    final dryingWindowHours = firstHighRiskIndex < 0
        ? windowHours
        : math.max(0, firstHighRiskIndex * intervalHours);

    final dayBuckets = <DateTime, List<ForecastPoint>>{};
    for (final point in windowPoints) {
      final dayKey = DateTime(
        point.timestamp.year,
        point.timestamp.month,
        point.timestamp.day,
      );
      dayBuckets.putIfAbsent(dayKey, () => <ForecastPoint>[]).add(point);
    }

    ({DateTime day, List<ForecastPoint> points, double averageScore})? bestDay;
    for (final entry in dayBuckets.entries) {
      final dayScores = entry.value
          .map(
            (point) => _calculateDryingScore(
              point: point,
              currentHumidity: currentHumidity,
            ),
          )
          .toList();
      if (dayScores.isEmpty) {
        continue;
      }

      final averageScore =
          dayScores.fold<double>(0, (sum, value) => sum + value) /
          dayScores.length;
      final candidate = (
        day: entry.key,
        points: entry.value,
        averageScore: averageScore,
      );
      if (bestDay == null ||
          candidate.averageScore > bestDay.averageScore ||
          (candidate.averageScore == bestDay.averageScore &&
              candidate.day.isBefore(bestDay.day))) {
        bestDay = candidate;
      }
    }

    final selectedDayPoints = bestDay?.points ?? windowPoints;
    final selectedIntervalHours = _estimateForecastIntervalHours(
      selectedDayPoints,
    );
    final bestWindow = _findBestDryingWindow(
      selectedDayPoints,
      intervalHours: selectedIntervalHours,
      currentHumidity: currentHumidity,
    );
    final bestDryingStartTime = bestWindow == null
        ? null
        : selectedDayPoints[bestWindow.startIndex].timestamp;
    final bestDryingEndTime = bestWindow == null
        ? null
        : selectedDayPoints[bestWindow.endIndex].timestamp.add(
            Duration(hours: selectedIntervalHours),
          );
    final int bestDryingWindowHours = bestWindow == null
        ? 0
        : (math.max(1, bestWindow.endIndex - bestWindow.startIndex + 1) *
                  selectedIntervalHours)
              .toInt();
    final int dryingScore = bestWindow == null
        ? _calculateDryingScore(
            point: selectedDayPoints.first,
            currentHumidity: currentHumidity,
          )
        : bestWindow.averageScore.round().clamp(0, 100).toInt();
    final riskLevel = dryingScore >= 75
        ? 'LOW'
        : (dryingScore >= 50 ? 'MODERATE' : 'HIGH');

    return PredictiveAnalytics(
      windowHours: windowHours,
      nextRainProbability: windowPoints.first.rainProbability,
      nextForecastTime: windowPoints.first.timestamp,
      maxRainProbability: maxPop,
      avgRainProbability: avgPop,
      peakTime: peakPoint.timestamp,
      dryingWindowHours: dryingWindowHours,
      bestDryingWindowHours: bestDryingWindowHours,
      bestDryingStartTime: bestDryingStartTime,
      bestDryingEndTime: bestDryingEndTime,
      dryingScore: dryingScore,
      riskLevel: riskLevel,
      recommendation: _buildDryingRecommendation(
        dryingScore: dryingScore,
        maxPop: maxPop,
        dryingWindowHours: dryingWindowHours,
        bestStartTime: bestDryingStartTime,
        bestEndTime: bestDryingEndTime,
        firstHighRiskTime: firstHighRiskTime,
      ),
      firstHighRiskTime: firstHighRiskTime,
    );
  }

  static int _calculateDryingScore({
    required ForecastPoint point,
    required int currentHumidity,
  }) {
    final rainPenalty = point.rainProbability * 0.9;
    final humidityPenalty = currentHumidity <= 0
        ? 0.0
        : math.max(0, currentHumidity - 55) * 0.65;
    final cloudPenalty = (point.cloudCover ?? 55) * 0.45;
    final tempBonus = point.temperatureC == null
        ? 0.0
        : math.max(0, point.temperatureC! - 26) * 1.2;
    final score =
        100 - rainPenalty - humidityPenalty - cloudPenalty + tempBonus;
    return score.clamp(0, 100).round();
  }

  static ({int startIndex, int endIndex, double averageScore})?
  _findBestDryingWindow(
    List<ForecastPoint> points, {
    required int intervalHours,
    required int currentHumidity,
  }) {
    if (points.isEmpty) {
      return null;
    }

    final maxWindowPoints = intervalHours >= 3
        ? math.min(points.length, 4)
        : math.min(points.length, 6);
    final minWindowPoints = points.length >= 3 ? 3 : 1;

    ({int startIndex, int endIndex, double averageScore})? best;

    for (var length = maxWindowPoints; length >= minWindowPoints; length--) {
      for (var start = 0; start + length <= points.length; start++) {
        final end = start + length - 1;
        final slice = points.sublist(start, end + 1);
        final scores = slice
            .map(
              (point) => _calculateDryingScore(
                point: point,
                currentHumidity: currentHumidity,
              ),
            )
            .toList();
        final averageScore =
            scores.fold<double>(0, (sum, value) => sum + value) / scores.length;
        final candidate = (
          startIndex: start,
          endIndex: end,
          averageScore: averageScore,
        );

        if (best == null ||
            candidate.averageScore > best.averageScore ||
            (candidate.averageScore == best.averageScore &&
                start < best.startIndex)) {
          best = candidate;
        }
      }
      if (best != null) {
        break;
      }
    }

    return best;
  }

  static String _buildDryingRecommendation({
    required int dryingScore,
    required int maxPop,
    required int dryingWindowHours,
    required DateTime? bestStartTime,
    required DateTime? bestEndTime,
    required DateTime? firstHighRiskTime,
  }) {
    final now = DateTime.now();
    final highRiskSoon =
        firstHighRiskTime != null &&
        firstHighRiskTime.difference(now).inHours <= 3;

    if (maxPop >= 70 || dryingScore < 40) {
      if (highRiskSoon || dryingWindowHours <= 2) {
        return 'Recommendation: retract or cover the rack soon to protect daing/tuyo from incoming rain.';
      }
      return 'Recommendation: drying looks risky today. Wait for a better drying window.';
    }

    if (dryingScore >= 75 && bestStartTime != null && bestEndTime != null) {
      if (bestStartTime.isBefore(now.add(const Duration(minutes: 30))) &&
          bestEndTime.isAfter(now)) {
        return 'Recommendation: dry now. Current sunlight looks best for daing/tuyo.';
      }
      return 'Recommendation: the next best drying window opens before rain risk rises.';
    }

    if (maxPop >= 45) {
      return 'Recommendation: monitor closely and keep covers nearby for quick rack protection.';
    }

    return 'Recommendation: dry now if the rack is exposed. Conditions look favorable.';
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

List<ActivityFeedEvent> buildRecentActivityFeed(
  RackMovementAnalytics? movementAnalytics,
) {
  return (movementAnalytics?.events ?? const <RackMovementEvent>[]).map((
    event,
  ) {
    final action = _rackActionLabel(event.action);
    final failed = event.status == 'FAILED';
    return ActivityFeedEvent(
      icon: failed
          ? Icons.warning_amber_rounded
          : (event.action == 'EXTEND'
                ? Icons.north_east_rounded
                : Icons.south_west_rounded),
      title: failed ? '$action movement failed' : 'Rack $action',
      subtitle:
          '${_rackTriggerLabel(event.trigger)} · ${event.mode.toLowerCase()} control',
      response: event.status,
      timestamp: event.startedAt,
    );
  }).toList();
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

String? rackActionFromStatus(String status) {
  final normalized = status.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  if (normalized.contains('moving') ||
      normalized.contains('extending') ||
      normalized.contains('retracting')) {
    return null;
  }
  if (normalized.contains('extend') ||
      normalized.contains('open') ||
      normalized.contains('deploy')) {
    return 'EXTEND';
  }
  if (normalized.contains('retract') || normalized.contains('close')) {
    return 'RETRACT';
  }
  return null;
}

bool isRackMovingStatus(String status) {
  final normalized = status.trim().toLowerCase();
  return normalized.contains('moving') ||
      normalized.contains('extending') ||
      normalized.contains('retracting');
}

bool isRackSafetyStatus(String status) {
  final normalized = status.trim().toUpperCase();
  return normalized == 'RETURNED_TO_START' ||
      normalized == 'LIMIT_SWITCH_CONFLICT' ||
      normalized == 'OBSTRUCTED' ||
      normalized.startsWith('FAILSAFE_') ||
      normalized.endsWith('_TIMEOUT');
}

String rackSafetyTitle(String status) {
  final normalized = status.trim().toUpperCase();
  if (normalized == 'LIMIT_SWITCH_CONFLICT') {
    return 'Limit switch conflict';
  }
  if (normalized == 'RETURNED_TO_START') {
    return 'Rack returned to starting limit';
  }
  if (normalized.startsWith('FAILSAFE_')) {
    return 'Rack returning to starting limit';
  }
  if (normalized == 'RETURN_TIMEOUT') {
    return 'Rack could not return to start';
  }
  if (normalized.endsWith('_TIMEOUT')) {
    return 'Rack movement timed out';
  }
  return normalized == 'OBSTRUCTED'
      ? 'Obstruction detected'
      : 'Rack retracted for safety';
}

String rackSafetyBody(String status) {
  final normalized = status.trim().toUpperCase();
  if (normalized == 'LIMIT_SWITCH_CONFLICT') {
    return 'Both end-stop inputs are active. Rack movement is blocked; check switch wiring and alignment.';
  }
  if (normalized == 'RETURNED_TO_START') {
    return 'The rack missed its target limit within 10 seconds, reversed once, and reached its starting limit.';
  }
  if (normalized.startsWith('FAILSAFE_')) {
    return 'Rack movement exceeded 10 seconds; the controller is making one attempt to return to the starting limit.';
  }
  if (normalized == 'RETURN_TIMEOUT') {
    return 'The rack missed its target and starting limits within 10 seconds. It stopped; check the travel path, limit switches, and motor.';
  }
  if (normalized.endsWith('_TIMEOUT')) {
    return 'Rack stopped because it did not reach its limit in time. Check the travel path, limit switches, and motor.';
  }
  return normalized == 'OBSTRUCTED'
      ? 'Rack movement stopped because an obstructing object may be blocking the rack.'
      : 'The rack automatically retracted because an obstruction was detected.';
}

String formatAlertRelativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) {
    return 'Just Now';
  }
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} mins ago';
  }
  if (diff.inHours < 24) {
    final hours = diff.inHours;
    return hours == 1 ? '1hr ago' : '${hours}hrs ago';
  }
  if (diff.inDays < 7) {
    final days = diff.inDays;
    return days == 1 ? '1 day ago' : '${days} days ago';
  }
  return formatDayDate(time);
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

String formatForecastDayDate(DateTime time) {
  const days = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[time.weekday - 1]}, ${formatDayDate(time)}';
}

String formatForecastWindow(DateTime start, DateTime end) {
  return '${formatClockTime(start)} - ${formatClockTime(end)}';
}

String formatCompactDuration(Duration duration) {
  if (duration.inSeconds <= 0) {
    return 'Now';
  }

  if (duration.inMinutes < 1) {
    return 'Less than 1m';
  }

  final days = duration.inDays;
  final hours = duration.inHours.remainder(24);
  final minutes = duration.inMinutes.remainder(60);
  final parts = <String>[];

  if (days > 0) {
    parts.add('${days}d');
  }
  if (hours > 0) {
    parts.add('${hours}h');
  }
  if (minutes > 0 || parts.isEmpty) {
    parts.add('${minutes}m');
  }

  return parts.join(' ');
}

String formatTimeLeft(DateTime target) {
  return '${formatCompactDuration(target.difference(DateTime.now()))} left';
}

String formatDryingWindowCountdown({
  required DateTime? start,
  required DateTime? end,
  required bool hasBestWindow,
}) {
  if (!hasBestWindow || start == null || end == null) {
    return 'No best drying weather at this time period';
  }

  final now = DateTime.now();
  if (now.isBefore(start)) {
    return 'Starts in ${formatCompactDuration(start.difference(now))}';
  }
  if (now.isBefore(end)) {
    return '${formatCompactDuration(end.difference(now))} left';
  }

  return 'No best drying weather at this time period';
}

_OptimalSunlightDay? _buildOptimalSunlightWindow(List<ForecastPoint> points) {
  if (points.isEmpty) {
    return null;
  }

  final now = DateTime.now();
  final horizonEnd = now.add(const Duration(days: 7));
  final horizon =
      points
          .where(
            (point) =>
                !point.timestamp.isBefore(
                  now.subtract(const Duration(minutes: 1)),
                ) &&
                point.timestamp.isBefore(horizonEnd),
          )
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  if (horizon.isEmpty) {
    return null;
  }

  final dayBuckets = <DateTime, List<ForecastPoint>>{};
  for (final point in horizon) {
    final dayKey = DateTime(
      point.timestamp.year,
      point.timestamp.month,
      point.timestamp.day,
    );
    dayBuckets.putIfAbsent(dayKey, () => <ForecastPoint>[]).add(point);
  }

  _OptimalSunlightDay? best;
  for (final entry in dayBuckets.entries) {
    final dayPoints = entry.value
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (dayPoints.isEmpty) {
      continue;
    }

    final scores = dayPoints.map(_sunlightScoreFromForecastPoint).toList();
    final averageSunlight =
        scores.fold<double>(0, (sum, value) => sum + value) / scores.length;
    final peakScore = scores.reduce(math.max);
    final peakIndex = scores.indexOf(peakScore);
    final peakPoint = dayPoints[peakIndex];

    final candidate = _OptimalSunlightDay(
      dayStart: entry.key,
      peakTime: peakPoint.timestamp,
      averageSunlight: averageSunlight,
      peakSunlight: peakScore,
    );

    if (best == null ||
        candidate.averageSunlight > best.averageSunlight ||
        (candidate.averageSunlight == best.averageSunlight &&
            candidate.dayStart.isBefore(best.dayStart))) {
      best = candidate;
    }
  }

  return best;
}

double _sunlightScoreFromForecastPoint(ForecastPoint point) {
  final rainSunlight = 100 - point.rainProbability;
  final cloudSunlight = point.cloudCover == null
      ? rainSunlight
      : 100 - point.cloudCover!.clamp(0, 100);
  return ((rainSunlight * 0.45) + (cloudSunlight * 0.55))
      .clamp(0, 100)
      .toDouble();
}

_WeeklySunlightWindow? _buildWeeklySunlightWindow(
  List<_WeatherTrendPoint> points,
) {
  if (points.isEmpty) {
    return null;
  }

  final now = DateTime.now();
  final horizonEnd = now.add(const Duration(days: 7));
  final horizon =
      points
          .where(
            (point) =>
                !point.time.isBefore(
                  now.subtract(const Duration(minutes: 1)),
                ) &&
                point.time.isBefore(horizonEnd),
          )
          .toList()
        ..sort((a, b) => a.time.compareTo(b.time));

  if (horizon.isEmpty) {
    return null;
  }

  final dayBuckets = <DateTime, List<_WeatherTrendPoint>>{};
  for (final point in horizon) {
    final dayKey = DateTime(point.time.year, point.time.month, point.time.day);
    dayBuckets.putIfAbsent(dayKey, () => <_WeatherTrendPoint>[]).add(point);
  }

  _WeeklySunlightWindow? best;
  for (final entry in dayBuckets.entries) {
    final dayPoints = entry.value..sort((a, b) => a.time.compareTo(b.time));
    if (dayPoints.isEmpty) {
      continue;
    }

    final dayBest = _findBestSunWindow(dayPoints);
    if (dayBest == null) {
      continue;
    }

    final candidate = _WeeklySunlightWindow(
      dayStart: entry.key,
      windowStart: dayPoints[dayBest.startIndex].time,
      windowEnd: dayPoints[dayBest.endIndex].endTime,
      averageSunlight: dayBest.averageScore,
      windowPoints: dayBest.endIndex - dayBest.startIndex + 1,
      totalDayPoints: dayPoints.length,
    );

    if (best == null ||
        candidate.averageSunlight > best.averageSunlight ||
        (candidate.averageSunlight == best.averageSunlight &&
            candidate.dayStart.isBefore(best.dayStart))) {
      best = candidate;
    }
  }

  if (best == null) {
    return null;
  }

  return best;
}

class _OptimalSunlightDay {
  const _OptimalSunlightDay({
    required this.dayStart,
    required this.peakTime,
    required this.averageSunlight,
    required this.peakSunlight,
  });

  final DateTime dayStart;
  final DateTime peakTime;
  final double averageSunlight;
  final double peakSunlight;

  String get dayLabel => formatForecastDayDate(dayStart);
  String get timeLabel => 'Most sunny day';
}

({int startIndex, int endIndex, double averageScore})? _findBestSunWindow(
  List<_WeatherTrendPoint> points,
) {
  if (points.isEmpty) {
    return null;
  }

  final maxWindowPoints = points.length >= 4 ? 4 : points.length;
  final minWindowPoints = points.length >= 3 ? 2 : 1;
  ({int startIndex, int endIndex, double averageScore})? best;

  for (var length = maxWindowPoints; length >= minWindowPoints; length--) {
    for (var start = 0; start + length <= points.length; start++) {
      final end = start + length - 1;
      final slice = points.sublist(start, end + 1);
      final averageScore =
          slice.fold<double>(
            0,
            (sum, point) => sum + point.sunlightProbability,
          ) /
          slice.length;
      final candidate = (
        startIndex: start,
        endIndex: end,
        averageScore: averageScore,
      );

      if (best == null ||
          candidate.averageScore > best.averageScore ||
          (candidate.averageScore == best.averageScore &&
              start < best.startIndex)) {
        best = candidate;
      }
    }

    if (best != null) {
      break;
    }
  }

  if (best == null) {
    return null;
  }

  return best;
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
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
  Widget build(BuildContext context) {
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
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SilongLogoImage(width: 220, height: 220),
                const SizedBox(height: 18),
                const Text(
                  'Preparing your account',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 16),
                ),
                const SizedBox(height: 20),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ),
          ),
        ),
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
                          'SILONG',
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
                          'Smart Protection for Daing/Tuyo Drying',
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
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'New to SILONG? ',
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
              'Register a new account to sign in to SILONG.',
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
  bool _isResolvingGps = false;
  bool _isAutoFilling = false;
  bool _hasManualEdits = false;
  String? _gpsStatusMessage;
  AppLocation? _gpsLocation;
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
    unawaited(
      _initializeSelectors().whenComplete(() {
        if (mounted) {
          unawaited(_autoDetectLocation());
        }
      }),
    );
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
                'Set a Philippine drying location so OpenWeather can return accurate rain probability for daing/tuyo protection.',
                style: TextStyle(fontSize: 16, color: AppColors.textMuted),
              ),
              if (_isLoadingProvinces || _isLoadingMunicipalities)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isSavingLocation || _isResolvingGps
                    ? null
                    : () => _autoDetectLocation(showErrors: true),
                icon: const Icon(Icons.my_location, color: AppColors.primary),
                label: Text(
                  _isResolvingGps ? 'Locating...' : 'Use Current GPS',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  side: const BorderSide(color: Color(0xFFD2DBE8)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              if (_gpsStatusMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _gpsStatusMessage!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5F718E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
                  _markManualEdit();
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
                  _markManualEdit();
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
          onChanged: (_) => _markManualEdit(),
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

  void _markManualEdit() {
    if (_isAutoFilling) {
      return;
    }
    _hasManualEdits = true;
  }

  String _pickFirstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
  }

  String _buildLocationLabel({
    required String street,
    String? city,
    String? province,
  }) {
    final parts = <String>[];
    final trimmedStreet = street.trim();
    if (trimmedStreet.isNotEmpty) {
      parts.add(trimmedStreet);
    }
    final trimmedCity = city?.trim() ?? '';
    if (trimmedCity.isNotEmpty) {
      parts.add(trimmedCity);
    }
    final trimmedProvince = province?.trim() ?? '';
    if (trimmedProvince.isNotEmpty) {
      parts.add(trimmedProvince);
    }
    parts.add('Philippines');
    return parts.join(', ');
  }

  bool _gpsMatchesSelection(AppLocation gpsLocation) {
    final selectedProvince = _normalizeLocationName(_selectedProvinceName);
    final selectedCity = _normalizeLocationName(_selectedMunicipality);
    if ((selectedProvince == null || selectedProvince.isEmpty) &&
        (selectedCity == null || selectedCity.isEmpty)) {
      return true;
    }

    final gpsProvince = _normalizeLocationName(gpsLocation.province) ?? '';
    final gpsCity = _normalizeLocationName(gpsLocation.city) ?? '';

    final provinceMatches =
        selectedProvince == null ||
        selectedProvince.isEmpty ||
        gpsProvince.contains(selectedProvince) ||
        selectedProvince.contains(gpsProvince);
    final cityMatches =
        selectedCity == null ||
        selectedCity.isEmpty ||
        gpsCity.contains(selectedCity) ||
        selectedCity.contains(gpsCity);

    return provinceMatches && cityMatches;
  }

  String? _normalizeLocationName(String? value) {
    final text = value
        ?.toLowerCase()
        .replaceAll(RegExp(r'\b(province|city|municipality|of)\b'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text.replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _namesMatch(String? left, String? right) {
    final a = _normalizeLocationName(left);
    final b = _normalizeLocationName(right);
    if (a == null || b == null) {
      return false;
    }
    return a == b || a.contains(b) || b.contains(a);
  }

  Future<({String? street, String? province, String? city})?>
  _reverseGeocodeWithNominatim({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'format': 'jsonv2',
      'addressdetails': '1',
      'zoom': '18',
    });

    final response = await http.get(
      uri,
      headers: const <String, String>{
        'User-Agent': 'sun-daing-dry-mobile/1.0 (gps-location-setup)',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final address = decoded['address'];
    if (address is! Map) {
      return null;
    }
    final row = address.map((key, value) => MapEntry(key.toString(), value));
    final street = _pickFirstNonEmpty([
      row['road']?.toString(),
      row['suburb']?.toString(),
      row['quarter']?.toString(),
      row['neighbourhood']?.toString(),
      row['village']?.toString(),
    ]);
    final province = _pickFirstNonEmpty([
      row['state']?.toString(),
      row['province']?.toString(),
      row['county']?.toString(),
    ]);
    final city = _pickFirstNonEmpty([
      row['city']?.toString(),
      row['town']?.toString(),
      row['municipality']?.toString(),
      row['village']?.toString(),
      row['suburb']?.toString(),
      row['county']?.toString(),
    ]);
    return (
      street: street.isEmpty ? null : street,
      province: province.isEmpty ? null : province,
      city: city.isEmpty ? null : city,
    );
  }

  Future<void> _applyGpsSelection({
    required String? province,
    required String? city,
  }) async {
    final provinceName = province?.trim() ?? '';
    if (provinceName.isEmpty) {
      return;
    }

    final matchedProvince = _findProvinceByName(provinceName);
    if (matchedProvince == null) {
      return;
    }

    await _onProvinceChanged(
      matchedProvince.code,
      preselectedMunicipality: city,
    );
  }

  Future<void> _autoDetectLocation({bool showErrors = false}) async {
    if (_isResolvingGps) {
      return;
    }

    setState(() {
      _isResolvingGps = true;
      _gpsStatusMessage = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) {
          return;
        }
        setState(() {
          _gpsStatusMessage =
              'Location services are disabled. Enable GPS to auto-fill.';
        });
        if (showErrors) {
          _showMessage('Enable location services to use GPS auto-fill.');
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        if (!mounted) {
          return;
        }
        setState(() {
          _gpsStatusMessage = 'Location permission denied.';
        });
        if (showErrors) {
          _showMessage('Allow location access to use GPS auto-fill.');
        }
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        if (!mounted) {
          return;
        }
        setState(() {
          _gpsStatusMessage =
              'Location permission is permanently denied. Enable it in settings.';
        });
        if (showErrors) {
          _showMessage('Enable location permission in settings to use GPS.');
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      final placemark = placemarks.isNotEmpty ? placemarks.first : null;
      final reverse = await _reverseGeocodeWithNominatim(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      final street = _pickFirstNonEmpty([
        reverse?.street,
        placemark?.street,
        placemark?.thoroughfare,
        placemark?.subLocality,
        placemark?.name,
      ]);
      final city = _pickFirstNonEmpty([
        reverse?.city,
        placemark?.locality,
        placemark?.subLocality,
        placemark?.subAdministrativeArea,
      ]);
      final province = _pickFirstNonEmpty([
        reverse?.province,
        placemark?.subAdministrativeArea,
        placemark?.administrativeArea,
      ]);
      final cityName = city.isEmpty ? null : city;
      final provinceName = province.isEmpty ? null : province;

      final label = _buildLocationLabel(
        street: street,
        city: cityName,
        province: provinceName,
      );
      final gpsLocation = AppLocation(
        label: label,
        latitude: position.latitude,
        longitude: position.longitude,
        street: street,
        province: provinceName,
        city: cityName,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _gpsLocation = gpsLocation;
        _gpsStatusMessage =
            'GPS detected near ${cityName ?? provinceName ?? 'your area'}.';
      });

      final shouldApply = !_hasManualEdits || showErrors;
      if (shouldApply) {
        _isAutoFilling = true;
        if (street.isNotEmpty) {
          _streetController.text = street;
        }
        await _applyGpsSelection(province: provinceName, city: cityName);
        _hasManualEdits = false;
      } else {
        setState(() {
          _gpsStatusMessage =
              'GPS detected. Tap "Use Current GPS" to apply it.';
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      const message =
          'Unable to retrieve GPS location. Check permissions and try again.';
      setState(() {
        _gpsStatusMessage = message;
      });
      if (showErrors) {
        _showMessage(message);
      }
    } finally {
      _isAutoFilling = false;
      if (mounted) {
        setState(() {
          _isResolvingGps = false;
        });
      }
    }
  }

  Future<void> _saveLocation() async {
    final street = _streetController.text.trim();
    final province = _selectedProvinceName;
    final municipality = _selectedMunicipalityOption;
    final gpsLocation = _gpsLocation;
    final canUseGps = gpsLocation != null && _gpsMatchesSelection(gpsLocation);

    if (!canUseGps &&
        (street.isEmpty || province == null || municipality == null)) {
      _showMessage('Enter street, select province, and select city.');
      return;
    }

    setState(() {
      _isSavingLocation = true;
    });

    try {
      AppLocation location;

      if (canUseGps) {
        final effectiveStreet = street.isNotEmpty
            ? street
            : (gpsLocation.street ?? '');
        final effectiveProvince = province ?? gpsLocation.province;
        final effectiveCity =
            municipality?.displayName ??
            _selectedMunicipality ??
            gpsLocation.city;

        if (effectiveStreet.isEmpty ||
            effectiveProvince == null ||
            effectiveCity == null) {
          _showMessage(
            'GPS detected, but please confirm street, province, and city before saving.',
          );
          return;
        }

        final label = _buildLocationLabel(
          street: effectiveStreet,
          city: effectiveCity,
          province: effectiveProvince,
        );
        location = AppLocation(
          label: label,
          latitude: gpsLocation.latitude,
          longitude: gpsLocation.longitude,
          street: effectiveStreet,
          province: effectiveProvince,
          city: effectiveCity,
        );
      } else {
        final selectedMunicipality = municipality;
        final selectedProvince = province;
        if (selectedMunicipality == null || selectedProvince == null) {
          _showMessage('Enter street, select province, and select city.');
          return;
        }
        final coordinates = await OpenWeatherService.geocodePhilippineLocation(
          municipality: selectedMunicipality.queryName,
          province: selectedProvince,
        );

        final label = _buildLocationLabel(
          street: street,
          city: selectedMunicipality.displayName,
          province: selectedProvince,
        );
        location = AppLocation(
          label: label,
          latitude: coordinates.$1,
          longitude: coordinates.$2,
          street: street,
          province: selectedProvince,
          city: selectedMunicipality.displayName,
        );
      }

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
    final normalized = _normalizeLocationName(name);
    for (final province in _provinceOptions) {
      final provinceName = _normalizeLocationName(province.name);
      if (provinceName == normalized ||
          (provinceName?.contains(normalized ?? '') ?? false) ||
          (normalized?.contains(provinceName ?? '') ?? false)) {
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
        for (final option in municipalities) {
          if (_namesMatch(option.displayName, preselectedMunicipality)) {
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
  int _rainProbabilityThreshold = ThresholdStore.defaultRainProbability;
  bool _thresholdCommandSentForCurrentRisk = false;
  String _firstName = 'User';
  RackMovementAnalytics? _movementAnalytics;
  HardwareService? _movementObserverService;
  HardwareState? _lastObservedHardwareState;

  @override
  void initState() {
    super.initState();
    _location = widget.initialLocation;
    unawaited(_loadThreshold());
    unawaited(_loadFirstName());
    unawaited(_loadMovementAnalytics());
    _startMovementObserver();
    _refreshWeather();
  }

  @override
  void dispose() {
    _movementObserverService?.dispose();
    super.dispose();
  }

  Future<void> _loadMovementAnalytics() async {
    final analytics = await RackMovementStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _movementAnalytics = analytics;
    });
  }

  Future<void> _loadFirstName() async {
    final firstName = await loadCurrentUserFirstName();
    if (!mounted) {
      return;
    }
    setState(() {
      _firstName = firstName;
    });
  }

  Future<void> _loadThreshold() async {
    final threshold = await ThresholdStore.loadRainProbability();
    if (!mounted) {
      return;
    }
    setState(() {
      _rainProbabilityThreshold = threshold;
    });
    await _evaluateRainThresholdAutomation();
  }

  void _startMovementObserver() {
    if (!_supabaseInitialized) {
      return;
    }
    final ownerEmail =
        Supabase.instance.client.auth.currentUser?.email
            ?.trim()
            .toLowerCase() ??
        '';
    if (ownerEmail.isEmpty) {
      return;
    }

    _movementObserverService = HardwareService(
      Supabase.instance.client,
      deviceId: 'ESP32_RACK_01',
      ownerEmail: ownerEmail,
    );
    _movementObserverService!.subscribe(_handleHardwareObservation);
  }

  void _handleHardwareObservation(HardwareState state) {
    final previous = _lastObservedHardwareState;
    _lastObservedHardwareState = state;
    final obstructionEventChanged =
        state.obstructionEventAt != null &&
        (previous == null
            ? DateTime.now().difference(state.obstructionEventAt!.toLocal()) <=
                  const Duration(minutes: 5)
            : state.obstructionEventAt != previous.obstructionEventAt);
    if (obstructionEventChanged) {
      unawaited(
        _recordHardwareSafetyAlert(
          'OBSTRUCTED',
          eventAt: state.obstructionEventAt,
        ),
      );
    } else if (isRackSafetyStatus(state.rackStatus) &&
        (previous == null || previous.rackStatus != state.rackStatus)) {
      unawaited(_recordHardwareSafetyAlert(state.rackStatus));
    }
    if (previous == null) {
      return;
    }
    if (!isRackMovingStatus(previous.rackStatus) ||
        isRackMovingStatus(state.rackStatus)) {
      return;
    }

    final action = rackActionFromStatus(state.rackStatus);
    if (action == null) {
      return;
    }
    if (HardwareService.hasRecentAppCommandForAction(action)) {
      unawaited(_completeObservedMovement(action));
      return;
    }

    final trigger = state.isRaining && action == 'EXTEND'
        ? 'RAIN_SENSOR'
        : (!state.isRaining && action == 'RETRACT'
              ? 'WEATHER_THRESHOLD'
              : 'SYSTEM');
    unawaited(_recordObservedMovement(action, trigger));
  }

  Future<void> _completeObservedMovement(String action) async {
    await RackMovementStore.completePending(action);
    await _loadMovementAnalytics();
  }

  Future<void> _recordObservedMovement(String action, String trigger) async {
    await RackMovementStore.record(
      action: action,
      trigger: trigger,
      mode: 'AUTO',
    );
    await _loadMovementAnalytics();
  }

  Future<void> _recordHardwareSafetyAlert(
    String status, {
    DateTime? eventAt,
  }) async {
    final timestamp = eventAt ?? DateTime.now();
    final alert = SavedAlert(
      id: 'hardware-safety-${timestamp.microsecondsSinceEpoch}',
      type: 'safety',
      title: rackSafetyTitle(status),
      body: rackSafetyBody(status),
      timestamp: timestamp,
      rightLabel: 'SAFETY',
    );
    final inserted = await AlertStore.saveAlert(alert);
    if (inserted) {
      await PushNotificationService.show(
        title: rackSafetyTitle(status),
        body: rackSafetyBody(status),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        onOpenDashboard: () => setState(() => _index = 1),
        onOpenAlerts: () => setState(() => _index = 3),
        location: _location,
        weather: _weather,
        isWeatherLoading: _isWeatherLoading,
        weatherError: _weatherError,
        onRefreshWeather: _refreshWeather,
        firstName: _firstName,
        movementAnalytics: _movementAnalytics,
      ),
      DashboardScreen(
        onOpenHistory: _openActivityHistory,
        location: _location,
        weather: _weather,
        lastWeatherSyncAt: _lastWeatherSyncAt,
        movementAnalytics: _movementAnalytics,
      ),
      DeviceScreen(
        onOpenManualControl: _openManualControl,
        location: _location,
        weather: _weather,
        lastWeatherSyncAt: _lastWeatherSyncAt,
        movementAnalytics: _movementAnalytics,
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
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: WidgetStatePropertyAll(
            Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontSize: 10, height: 1),
          ),
        ),
        child: NavigationBar(
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
      ),
    );
  }

  void _openManualControl() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ManualOverrideScreen()));
  }

  void _openActivityHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActivityHistoryScreen(
          location: _location,
          movementAnalytics: _movementAnalytics,
        ),
      ),
    );
  }

  void _openThresholdConfig() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThresholdConfigurationScreen(
          weather: _weather,
          initialThreshold: _rainProbabilityThreshold,
          onSaved: (threshold) async {
            setState(() {
              _rainProbabilityThreshold = threshold;
              _thresholdCommandSentForCurrentRisk = false;
            });
            await _evaluateRainThresholdAutomation();
          },
        ),
      ),
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
      await _recordWeatherAlert(weather);
      await _evaluateRainThresholdAutomation();
      await _loadMovementAnalytics();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _weatherError = _weatherSyncErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isWeatherLoading = false;
        });
      }
    }
  }

  Future<void> _evaluateRainThresholdAutomation() async {
    final weather = _weather;
    if (weather == null) {
      _thresholdCommandSentForCurrentRisk = false;
      return;
    }
    final isHighRisk = weather.rainProbability >= _rainProbabilityThreshold;
    if (!isHighRisk) {
      if (_thresholdCommandSentForCurrentRisk) {
        await _sendAutoRetractCommand(weather);
      }
      _thresholdCommandSentForCurrentRisk = false;
      return;
    }
    if (_thresholdCommandSentForCurrentRisk || !_supabaseInitialized) {
      return;
    }
    final ownerEmail =
        Supabase.instance.client.auth.currentUser?.email
            ?.trim()
            .toLowerCase() ??
        '';
    if (ownerEmail.isEmpty) {
      return;
    }
    try {
      final service = HardwareService(
        Supabase.instance.client,
        deviceId: 'ESP32_RACK_01',
        ownerEmail: ownerEmail,
      );
      await service.sendCommand('DEPLOY');
      HardwareService.noteAppCommandIssued('DEPLOY');
      _thresholdCommandSentForCurrentRisk = true;
      await _recordAutomationAlert(weather);
    } catch (_) {
      // Keep weather refresh usable even if the hardware command cannot be sent.
    }
  }

  Future<void> _sendAutoRetractCommand(WeatherSnapshot weather) async {
    if (!_supabaseInitialized) {
      return;
    }
    final ownerEmail =
        Supabase.instance.client.auth.currentUser?.email
            ?.trim()
            .toLowerCase() ??
        '';
    if (ownerEmail.isEmpty) {
      return;
    }

    try {
      final service = HardwareService(
        Supabase.instance.client,
        deviceId: 'ESP32_RACK_01',
        ownerEmail: ownerEmail,
      );
      await service.sendCommand('RETRACT');
      HardwareService.noteAppCommandIssued('RETRACT');
      await _recordAutomationRetractAlert(weather);
    } catch (_) {
      // Keep weather refresh usable even if the hardware command cannot be sent.
    }
  }

  Future<void> _recordWeatherAlert(WeatherSnapshot weather) async {
    final now = DateTime.now();
    final highRisk = weather.rainProbability >= _rainProbabilityThreshold;
    final alert = SavedAlert(
      id: 'weather-${now.year}-${now.month}-${now.day}-${now.hour}-$_rainProbabilityThreshold-${highRisk ? 'high' : 'normal'}',
      type: highRisk ? 'rain_high' : 'rain_normal',
      title: highRisk
          ? 'High rain probability detected (${weather.rainProbability}%)'
          : 'Rain risk normal for ${_location.city ?? _location.province ?? 'your area'}',
      body:
          'Near-term forecast: ${weather.rainProbability}% rain probability for ${_location.label}.',
      timestamp: now,
    );
    final inserted = await AlertStore.saveAlert(alert);
    if (inserted && highRisk) {
      await PushNotificationService.show(title: alert.title, body: alert.body);
    }
  }

  Future<void> _recordAutomationAlert(WeatherSnapshot weather) async {
    final now = DateTime.now();
    final alert = SavedAlert(
      id: 'automation-deploy-${now.year}-${now.month}-${now.day}-${now.hour}-${weather.rainProbability}-$_rainProbabilityThreshold',
      type: 'rack_deploy',
      title: 'Rack protection command sent',
      body:
          'Rain probability reached ${weather.rainProbability}%, so SILONG sent DEPLOY to extend the rack.',
      timestamp: now,
      rightLabel: 'AUTO',
    );
    final inserted = await AlertStore.saveAlert(alert);
    if (inserted) {
      await PushNotificationService.show(title: alert.title, body: alert.body);
    }
    await RackMovementStore.record(
      action: 'EXTEND',
      trigger: 'WEATHER_THRESHOLD',
      mode: 'AUTO',
      status: 'REQUESTED',
    );
  }

  Future<void> _recordAutomationRetractAlert(WeatherSnapshot weather) async {
    final now = DateTime.now();
    final alert = SavedAlert(
      id: 'automation-retract-${now.year}-${now.month}-${now.day}-${now.hour}-${weather.rainProbability}-$_rainProbabilityThreshold',
      type: 'rack_retract',
      title: 'Rack protection cleared',
      body:
          'Rain probability dropped to ${weather.rainProbability}%, so SILONG sent RETRACT to bring the rack back.',
      timestamp: now,
      rightLabel: 'AUTO',
    );
    final inserted = await AlertStore.saveAlert(alert);
    if (inserted) {
      await PushNotificationService.show(title: alert.title, body: alert.body);
    }
    await RackMovementStore.record(
      action: 'RETRACT',
      trigger: 'WEATHER_THRESHOLD',
      mode: 'AUTO',
      status: 'REQUESTED',
    );
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
    required this.onOpenAlerts,
    required this.location,
    required this.weather,
    required this.isWeatherLoading,
    required this.weatherError,
    required this.onRefreshWeather,
    required this.firstName,
    required this.movementAnalytics,
  });

  final VoidCallback onOpenDashboard;
  final VoidCallback onOpenAlerts;
  final AppLocation location;
  final WeatherSnapshot? weather;
  final bool isWeatherLoading;
  final String? weatherError;
  final Future<void> Function() onRefreshWeather;
  final String firstName;
  final RackMovementAnalytics? movementAnalytics;

  @override
  Widget build(BuildContext context) {
    final greeting = rs(context, 48, min: 34);
    final sectionTitle = rs(context, 32, min: 24);
    final buttonText = rs(context, 26, min: 20);

    return AppViewport(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          children: [
            Row(
              children: [
                const SilongLogoImage(width: 112, height: 44),
                const SizedBox(width: 10),
                const Spacer(),
                IconButton(
                  onPressed: onOpenAlerts,
                  tooltip: 'Open alerts',
                  icon: const Icon(
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
              'Hello, $firstName',
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
            _PredictiveAnalyticsCard(weather: weather, location: location),
            const SizedBox(height: 14),
            _RackMovementSummaryCard(analytics: movementAnalytics),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    title: 'TEMP',
                    value: weather?.temperatureFText ?? '--',
                    subtitle: 'Outdoor forecast',
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
    final isRainRisk = (weather?.rainProbability ?? 0) >= 60;
    final statusColor = isRainRisk ? AppColors.danger : AppColors.success;
    final statusLabel = !isForecastReady
        ? 'Waiting'
        : (isRainRisk ? 'Rain Risk' : 'Monitoring');
    final statusCopy = isForecastReady
        ? 'Forecast data from ${weather!.source} is active.'
        : 'Forecast pipeline is initializing. No hardware sensor stream yet.';
    final progress = isRainRisk ? 0.35 : (isForecastReady ? 1.0 : 0.0);
    final progressLabel = isRainRisk
        ? 'Rain Risk'
        : (isForecastReady ? 'Forecast Ready' : 'Waiting');

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
              Text(
                'FORECAST STATUS',
                style: TextStyle(
                  color: statusColor,
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
                  color: statusColor.withValues(alpha: 0.12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Icon(
                  isRainRisk ? Icons.warning_amber_rounded : Icons.cloud_done,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            statusLabel,
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
                    color: statusColor,
                    backgroundColor: statusColor.withValues(alpha: 0.14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                progressLabel,
                style: TextStyle(
                  color: statusColor.withValues(alpha: 0.96),
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
    required this.movementAnalytics,
  });

  final VoidCallback onOpenHistory;
  final AppLocation location;
  final WeatherSnapshot? weather;
  final DateTime? lastWeatherSyncAt;
  final RackMovementAnalytics? movementAnalytics;

  @override
  Widget build(BuildContext context) {
    final header = rs(context, 32, min: 24);
    final statusHeadline = rs(context, 44, min: 30);
    final sectionHeader = rs(context, 24, min: 18);
    final isWarning = (weather?.rainProbability ?? 0) >= 60;
    final statusLabel = weather == null
        ? 'Forecast - Loading'
        : (isWarning ? 'Forecast - Rain Risk' : 'Forecast - Normal');
    final activities = buildRecentActivityFeed(movementAnalytics);

    return AppViewport(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'SILONG System',
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
                    'FORECAST STATUS',
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
            const SizedBox(height: 14),
            _RackMovementAnalyticsCard(analytics: movementAnalytics),
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
            if (activities.isEmpty)
              const _SimpleInfoTile(
                title: 'No recent rack movement',
                trailing: 'No events',
              ),
          ],
        ),
      ),
    );
  }
}

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({
    super.key,
    required this.onOpenManualControl,
    required this.location,
    required this.weather,
    required this.lastWeatherSyncAt,
    required this.movementAnalytics,
  });

  final VoidCallback onOpenManualControl;
  final AppLocation location;
  final WeatherSnapshot? weather;
  final DateTime? lastWeatherSyncAt;
  final RackMovementAnalytics? movementAnalytics;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  HardwareService? _hwService;
  HardwareState? _hwState;
  Timer? _onlineRefreshTimer;
  bool _isLoading = true;

  String _currentOwnerEmail() {
    return Supabase.instance.client.auth.currentUser?.email
            ?.trim()
            .toLowerCase() ??
        '';
  }

  @override
  void initState() {
    super.initState();
    _onlineRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        setState(() {});
      }
    });
    if (_supabaseInitialized) {
      final ownerEmail = _currentOwnerEmail();
      if (ownerEmail.isNotEmpty) {
        _hwService = HardwareService(
          Supabase.instance.client,
          deviceId: 'ESP32_RACK_01',
          ownerEmail: ownerEmail,
        );
        _hwService!.subscribe((state) {
          if (!mounted) return;
          setState(() {
            _hwState = state;
            _isLoading = false;
          });
        });
      } else {
        _isLoading = false;
      }
    }
  }

  @override
  void dispose() {
    _onlineRefreshTimer?.cancel();
    _hwService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titleSize = rs(context, 37, min: 28);
    final networkStateSize = rs(context, 48, min: 34);
    final sensorsTitle = rs(context, 36, min: 26);
    final secondaryButtonText = rs(context, 24, min: 18);
    final hasWeather = widget.weather != null;
    final sourceLabel = widget.weather?.source ?? 'Weather API';
    final syncLabel = widget.lastWeatherSyncAt == null
        ? 'PENDING'
        : formatRelativeTime(
            widget.lastWeatherSyncAt!,
          ).replaceFirst('Last checked: ', '').toUpperCase();

    final hw = _hwState;
    final deviceOnline = hw?.isOnline ?? false;

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
                    'SILONG',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
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
                  if (deviceOnline && isRackSafetyStatus(hw!.rackStatus))
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE7B66A)),
                      ),
                      child: Text(
                        rackSafetyBody(hw.rackStatus),
                        style: const TextStyle(
                          color: Color(0xFF7A4B00),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  SizedBox(height: 8),
                  Text(
                    '• ${deviceOnline ? 'Online' : (_isLoading ? 'Connecting' : 'Offline')}',
                    style: TextStyle(
                      fontSize: networkStateSize,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    deviceOnline
                        ? 'Device: ${hw!.rackStatus} — Auto: ${hw.isAutoMode ? 'ON' : 'OFF'}'
                        : (hasWeather
                              ? '$sourceLabel stream active for ${widget.location.city ?? widget.location.province ?? 'Philippines'}'
                              : 'Waiting for hardware or weather feed'),
                    style: const TextStyle(
                      fontSize: 19,
                      color: Color(0xFF667E98),
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
              onPressed: widget.onOpenManualControl,
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
              status: deviceOnline ? 'Online' : 'Offline',
              reading: deviceOnline ? (hw!.isRaining ? 'Wet' : 'Dry') : '--',
              time: deviceOnline ? 'Live' : 'Pending',
              icon: Icons.water_drop_outlined,
            ),
            const SizedBox(height: 10),
            _SensorTile(
              name: 'Temperature Sensor',
              status: deviceOnline ? 'Online' : 'Offline',
              reading: deviceOnline ? '${hw!.temperatureC.round()}°C' : '--',
              time: deviceOnline ? 'Live' : 'Pending',
              icon: Icons.thermostat,
            ),
            const SizedBox(height: 10),
            _SensorTile(
              name: 'Humidity Sensor',
              status: deviceOnline ? 'Online' : 'Offline',
              reading: deviceOnline
                  ? '${hw!.humidity.toStringAsFixed(1)}% RH'
                  : '--',
              time: deviceOnline ? 'Live' : 'Pending',
              icon: Icons.eco_outlined,
            ),
            const SizedBox(height: 10),
            _SensorTile(
              name: 'Rack Status',
              status: deviceOnline ? 'Online' : 'Offline',
              reading: deviceOnline ? hw!.rackStatus : 'Unknown',
              time: deviceOnline ? 'Live' : 'Pending',
              icon: Icons.cloud_outlined,
            ),
            const SizedBox(height: 14),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _InfoStatCard(
                      title: 'Data Source',
                      value: deviceOnline ? 'Hardware' : sourceLabel,
                      icon: Icons.dataset_linked_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _InfoStatCard(
                      title: 'Mode',
                      value: deviceOnline
                          ? (hw!.isAutoMode ? 'Auto' : 'Manual')
                          : 'Forecast',
                      icon: Icons.hub_outlined,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _RackMovementAnalyticsCard(
              analytics: widget.movementAnalytics,
              compact: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _RackMovementSummaryCard extends StatelessWidget {
  const _RackMovementSummaryCard({required this.analytics});

  final RackMovementAnalytics? analytics;

  @override
  Widget build(BuildContext context) {
    final latest = analytics?.latest;
    final latestText = latest == null
        ? 'No rack movement recorded yet.'
        : '${_rackActionLabel(latest.action)} ${formatActivityTime(latest.startedAt)} via ${_rackTriggerLabel(latest.trigger)}.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCFE6EE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.swap_vert_circle_outlined, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RACK ACTIVITY',
                  style: TextStyle(
                    letterSpacing: 1.5,
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  latestText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMain,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            analytics == null
                ? '--'
                : '${analytics!.extensions + analytics!.retractions}',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RackMovementAnalyticsCard extends StatelessWidget {
  const _RackMovementAnalyticsCard({
    required this.analytics,
    this.compact = false,
  });

  final RackMovementAnalytics? analytics;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final data = analytics;
    if (data == null) {
      return const _RackMovementEmptyCard();
    }

    final latest = data.latest;
    final duration = data.averageDuration;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E0EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.swap_vert_circle_outlined,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Rack Movement Analytics',
                  style: TextStyle(
                    fontSize: compact ? 18 : 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMain,
                  ),
                ),
              ),
              const Text(
                '7 DAYS',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            data.interpretation,
            style: TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 12.5 : 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RackMetric(
                label: 'Extended',
                value: '${data.extensions}',
                color: AppColors.primary,
              ),
              _RackMetric(
                label: 'Retracted',
                value: '${data.retractions}',
                color: AppColors.accentBlue,
              ),
              _RackMetric(
                label: 'Auto',
                value: '${data.automaticEvents}',
                color: AppColors.success,
              ),
              _RackMetric(
                label: 'Manual',
                value: '${data.manualEvents}',
                color: const Color(0xFFD49B17),
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 12),
            Text(
              duration == null
                  ? 'Movement duration is not available yet.'
                  : 'Average movement duration: ${_formatMovementDuration(duration)}',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            if (latest != null) _RackMovementEventTile(event: latest),
            if (data.events.length > 1) ...[
              const SizedBox(height: 8),
              _RackMovementEventTile(event: data.events[1]),
            ],
          ],
        ],
      ),
    );
  }
}

class _RackMovementEmptyCard extends StatelessWidget {
  const _RackMovementEmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E0EC)),
      ),
      child: const Row(
        children: [
          Icon(Icons.history_toggle_off, color: AppColors.textMuted),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Rack movement analytics will appear after the app records a movement.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RackMetric extends StatelessWidget {
  const _RackMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE0E7F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RackMovementEventTile extends StatelessWidget {
  const _RackMovementEventTile({required this.event});

  final RackMovementEvent event;

  @override
  Widget build(BuildContext context) {
    final isExtend = event.action == 'EXTEND';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE0E7F1)),
      ),
      child: Row(
        children: [
          Icon(
            isExtend ? Icons.open_in_full : Icons.close_fullscreen,
            color: isExtend ? AppColors.primary : AppColors.accentBlue,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_rackActionLabel(event.action)} via ${_rackTriggerLabel(event.trigger)}',
              style: const TextStyle(
                color: AppColors.textMain,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            formatActivityTime(event.startedAt),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _rackActionLabel(String action) {
  switch (action) {
    case 'EXTEND':
      return 'Extended';
    case 'RETRACT':
      return 'Retracted';
    default:
      return 'Movement';
  }
}

String _rackTriggerLabel(String trigger) {
  switch (trigger) {
    case 'WEATHER_THRESHOLD':
      return 'weather protection';
    case 'RAIN_SENSOR':
      return 'rain sensor';
    case 'MANUAL':
      return 'manual control';
    default:
      return 'system';
  }
}

String _formatMovementDuration(Duration duration) {
  if (duration.inSeconds < 60) {
    return '${duration.inSeconds}s';
  }
  return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
}

class AlertsScreen extends StatefulWidget {
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
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late Future<List<SavedAlert>> _alertsFuture;

  @override
  void initState() {
    super.initState();
    _alertsFuture = AlertStore.load();
  }

  Future<void> _markAllRead() async {
    try {
      await AlertStore.markAllRead();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update alerts in the database.'),
          ),
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _alertsFuture = AlertStore.load();
    });
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'rain_high':
        return Icons.warning_amber_rounded;
      case 'rack_deploy':
        return Icons.check_circle;
      case 'sync':
        return Icons.sync;
      default:
        return Icons.cloudy_snowing;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'rain_high':
        return const Color(0xFFF0A63B);
      case 'rack_deploy':
        return const Color(0xFF2BB87E);
      case 'sync':
        return AppColors.primary;
      default:
        return const Color(0xFFE84E47);
    }
  }

  String _sectionFor(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final alertDay = DateTime(timestamp.year, timestamp.month, timestamp.day);
    if (alertDay == today) {
      return 'TODAY';
    }
    if (alertDay == today.subtract(const Duration(days: 1))) {
      return 'YESTERDAY';
    }
    return formatForecastDayDate(timestamp).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final titleSize = rs(context, 43, min: 30);

    return AppViewport(
      child: SafeArea(
        child: FutureBuilder<List<SavedAlert>>(
          future: _alertsFuture,
          builder: (context, snapshot) {
            final alerts = snapshot.data ?? const <SavedAlert>[];
            final children = <Widget>[
              Row(
                children: [
                  Text(
                    'Alerts',
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: alerts.any((alert) => !alert.isRead)
                        ? _markAllRead
                        : null,
                    icon: const Icon(Icons.done_all, color: AppColors.primary),
                    tooltip: 'Mark all read',
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ];

            if (snapshot.connectionState == ConnectionState.waiting) {
              children.add(const Center(child: CircularProgressIndicator()));
            } else if (snapshot.hasError) {
              children.add(
                Column(
                  children: [
                    const Text('Alerts could not be loaded from the database.'),
                    TextButton(
                      onPressed: () => setState(() {
                        _alertsFuture = AlertStore.load();
                      }),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            } else if (alerts.isEmpty) {
              children.add(
                const _SimpleInfoTile(
                  title: 'No saved alerts yet',
                  trailing: 'Ready',
                ),
              );
            } else {
              String? activeSection;
              for (final alert in alerts) {
                final section = _sectionFor(alert.timestamp);
                if (section != activeSection) {
                  if (activeSection != null) {
                    children.add(const SizedBox(height: 12));
                  }
                  children.add(
                    Text(
                      section,
                      style: const TextStyle(
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF66758F),
                      ),
                    ),
                  );
                  children.add(const SizedBox(height: 10));
                  activeSection = section;
                }
                children.add(
                  _AlertTile(
                    icon: _iconForType(alert.type),
                    iconColor: _colorForType(alert.type),
                    title: alert.title,
                    body: alert.body,
                    time: formatClockTime(alert.timestamp),
                    isRead: alert.isRead,
                    rightLabel:
                        alert.rightLabel ??
                        formatAlertRelativeTime(alert.timestamp),
                  ),
                );
                children.add(const SizedBox(height: 10));
              }
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
              children: children,
            );
          },
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
  bool pushNotifications = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadNotificationPreference());
  }

  Future<void> _loadNotificationPreference() async {
    var enabled = await NotificationPreferences.loadEnabled();
    if (enabled) {
      enabled = await PushNotificationService.requestPermission();
      await NotificationPreferences.saveEnabled(enabled);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      pushNotifications = enabled;
    });
  }

  Future<void> _onPushNotificationChanged(bool value) async {
    if (!value) {
      await NotificationPreferences.saveEnabled(false);
      if (!mounted) {
        return;
      }
      setState(() {
        pushNotifications = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App notifications disabled.')),
      );
      return;
    }

    final allowed = await PushNotificationService.requestPermission();
    await NotificationPreferences.saveEnabled(allowed);
    if (!mounted) {
      return;
    }
    setState(() {
      pushNotifications = allowed;
    });
    if (allowed) {
      await PushNotificationService.show(
        title: 'SILONG notifications enabled',
        body: 'This is a test notification from your device.',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App notification enabled.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification permission was denied.')),
      );
    }
  }

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
                'SILONG',
                style: TextStyle(
                  fontSize: brandSize,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain,
                ),
              ),
            ),
            const Center(
              child: Text(
                'Daing/Tuyo Drying Control',
                style: TextStyle(color: AppColors.textMuted, fontSize: 15),
              ),
            ),
            const SizedBox(height: 14),
            const _SectionLabel(label: 'PREFERENCES'),
            const _SectionLabel(label: 'Notifications'),
            _SwitchTile(
              icon: Icons.notifications_none,
              title: 'Push Notifications',
              value: pushNotifications,
              onChanged: (value) =>
                  unawaited(_onPushNotificationChanged(value)),
            ),
            const SizedBox(height: 8),
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
                subtitle: 'Set rain risk for automatic rack response',
                icon: Icons.tune_outlined,
              ),
            ),
            const SizedBox(height: 8),
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
  const ThresholdConfigurationScreen({
    super.key,
    required this.weather,
    required this.initialThreshold,
    required this.onSaved,
  });

  final WeatherSnapshot? weather;
  final int initialThreshold;
  final Future<void> Function(int threshold) onSaved;

  @override
  State<ThresholdConfigurationScreen> createState() =>
      _ThresholdConfigurationScreenState();
}

class _ThresholdConfigurationScreenState
    extends State<ThresholdConfigurationScreen> {
  late double value;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    value = widget.initialThreshold.toDouble();
  }

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
                      'SILONG Settings',
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
                'Set the rain probability at which the daing/tuyo\ndrying rack should automatically extend its protection mode.',
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
                child: Row(
                  children: [
                    const Icon(
                      Icons.analytics_outlined,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Local Forecast',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            widget.weather == null
                                ? 'Rain probability is still syncing.'
                                : 'Rain probability is ${widget.weather!.rainProbability}%.',
                            style: const TextStyle(color: Color(0xFF4F5F76)),
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
                onPressed: _isSaving
                    ? null
                    : () async {
                        final threshold = value.round();
                        final messenger = ScaffoldMessenger.of(context);
                        setState(() {
                          _isSaving = true;
                        });
                        try {
                          await ThresholdStore.saveRainProbability(threshold);
                          await widget.onSaved(threshold);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Threshold saved at $threshold%'),
                            ),
                          );
                        } finally {
                          if (mounted) {
                            setState(() {
                              _isSaving = false;
                            });
                          }
                        }
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

class ManualOverrideScreen extends StatefulWidget {
  const ManualOverrideScreen({super.key});

  @override
  State<ManualOverrideScreen> createState() => _ManualOverrideScreenState();
}

class _ManualOverrideScreenState extends State<ManualOverrideScreen> {
  HardwareService? _hwService;
  bool _busy = false;
  String? _statusMessage;
  String _rackStatusLabel = 'Unknown';
  DateTime? _lastManualStatusUpdateAt;

  String _currentOwnerEmail() {
    return Supabase.instance.client.auth.currentUser?.email
            ?.trim()
            .toLowerCase() ??
        '';
  }

  @override
  void initState() {
    super.initState();
    if (_supabaseInitialized) {
      final ownerEmail = _currentOwnerEmail();
      if (ownerEmail.isNotEmpty) {
        _hwService = HardwareService(
          Supabase.instance.client,
          deviceId: 'ESP32_RACK_01',
          ownerEmail: ownerEmail,
        );
        _hwService!.subscribe((state) {
          if (!mounted) {
            return;
          }
          final manualUpdateAt = _lastManualStatusUpdateAt;
          if (manualUpdateAt != null &&
              DateTime.now().difference(manualUpdateAt) <
                  const Duration(seconds: 8)) {
            return;
          }
          setState(() {
            _rackStatusLabel = state.isOnline
                ? _rackStatusFromHardware(state.rackStatus)
                : 'Offline';
          });
        });
      }
    }
  }

  @override
  void dispose() {
    _hwService?.dispose();
    super.dispose();
  }

  String _rackStatusFromHardware(String status) {
    final normalized = status.trim().toUpperCase();
    if (normalized.isEmpty || normalized == 'UNKNOWN') {
      return 'Unknown';
    }
    if (isRackSafetyStatus(normalized)) {
      return normalized;
    }
    if (normalized.contains('OPEN') ||
        normalized.contains('EXTEND') ||
        normalized.contains('DEPLOY')) {
      return 'Extended';
    }
    if (normalized.contains('MOVING')) {
      return 'Moving';
    }
    return 'Retracted';
  }

  String _rackStatusFromCommand(String command) {
    return command == 'DEPLOY' ? 'Extending...' : 'Retracting...';
  }

  Future<void> _sendCommand(String command) async {
    if (_hwService == null || _busy) {
      return;
    }
    final previousRackStatus = _rackStatusLabel;
    setState(() {
      _busy = true;
      _statusMessage = null;
      _rackStatusLabel = command == 'DEPLOY' ? 'Extending...' : 'Retracting...';
    });
    try {
      await _hwService!.sendCommand(command);
      HardwareService.noteAppCommandIssued(command);
      await RackMovementStore.record(
        action: command == 'DEPLOY' ? 'EXTEND' : 'RETRACT',
        trigger: 'MANUAL',
        mode: 'MANUAL',
        status: 'REQUESTED',
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lastManualStatusUpdateAt = DateTime.now();
        _rackStatusLabel = _rackStatusFromCommand(command);
        _statusMessage = '$command sent. Waiting for hardware...';
      });
      final isDeploy = command == 'DEPLOY';
      final alert = SavedAlert(
        id: 'manual-$command-${DateTime.now().millisecondsSinceEpoch}',
        type: isDeploy ? 'rack_deploy' : 'sync',
        title: isDeploy ? 'Rack extend requested' : 'Rack retract requested',
        body: isDeploy
            ? 'Manual DEPLOY was sent. The rack is waiting to confirm extension.'
            : 'Manual RETRACT was sent. The rack is waiting to confirm retraction.',
        timestamp: DateTime.now(),
        rightLabel: 'REQUEST',
      );
      await AlertStore.saveAlert(alert);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _rackStatusLabel = previousRackStatus;
        _statusMessage = 'Failed to send $command';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
      ),
      body: AppViewport(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (isRackSafetyStatus(_rackStatusLabel))
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE7B66A)),
                ),
                child: Text(
                  rackSafetyBody(_rackStatusLabel),
                  style: const TextStyle(
                    color: Color(0xFF7A4B00),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (isRackSafetyStatus(_rackStatusLabel))
              const SizedBox(height: 12),
            if (_statusMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF6FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD1E7F0)),
                ),
                child: Text(
                  _statusMessage!,
                  style: const TextStyle(
                    color: Color(0xFF5D758E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
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
                  child: Center(
                    child: Text(
                      _rackStatusLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
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
                    onPressed: _hwService == null || _busy
                        ? null
                        : () => _sendCommand('DEPLOY'),
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
                    onPressed: _hwService == null || _busy
                        ? null
                        : () => _sendCommand('RETRACT'),
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
              onPressed: _hwService == null || _busy
                  ? null
                  : () => _sendCommand('RETRACT'),
              child: Text(
                'RETRACT RACK',
                style: TextStyle(
                  fontSize: rs(context, 24, min: 18),
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

class ActivityHistoryScreen extends StatelessWidget {
  const ActivityHistoryScreen({
    super.key,
    required this.location,
    required this.movementAnalytics,
  });

  final AppLocation location;
  final RackMovementAnalytics? movementAnalytics;

  @override
  Widget build(BuildContext context) {
    final activities = buildRecentActivityFeed(movementAnalytics);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SILONG',
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
      ),
      body: AppViewport(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
          children: [
            const SizedBox(height: 12),
            Text(
              'RACK MOVEMENTS · LAST 7 DAYS',
              style: TextStyle(
                color: Color(0xFF7588A4),
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (activities.isEmpty)
              const _SimpleInfoTile(
                title: 'No rack movement history yet',
                trailing: 'No events',
              )
            else
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

class _PredictiveAnalyticsCard extends StatelessWidget {
  const _PredictiveAnalyticsCard({
    required this.weather,
    required this.location,
  });

  final WeatherSnapshot? weather;
  final AppLocation location;

  List<_WeatherTrendPoint> _trendPoints() {
    final upcoming =
        weather?.forecast
            .where(
              (point) => point.timestamp.isAfter(
                DateTime.now().subtract(const Duration(minutes: 1)),
              ),
            )
            .toList() ??
        <ForecastPoint>[];
    upcoming.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (upcoming.isEmpty) {
      return const <_WeatherTrendPoint>[];
    }

    final windows = <_WeatherTrendPoint>[];
    var cursor = upcoming.first.timestamp;
    var index = 0;

    while (index < upcoming.length && windows.length < 8) {
      final end = cursor.add(const Duration(hours: 2));
      final bucket = <ForecastPoint>[];
      while (index < upcoming.length &&
          !upcoming[index].timestamp.isBefore(cursor) &&
          upcoming[index].timestamp.isBefore(end)) {
        bucket.add(upcoming[index]);
        index++;
      }

      if (bucket.isEmpty) {
        final point = upcoming[index];
        cursor = point.timestamp;
        bucket.add(point);
        index++;
      }

      final avgRain =
          (bucket.fold<int>(0, (sum, point) => sum + point.rainProbability) /
                  bucket.length)
              .round()
              .clamp(0, 100);
      final temps = bucket
          .map((point) => point.temperatureC ?? weather?.temperatureC)
          .whereType<double>()
          .toList();
      final avgTemp = temps.isEmpty
          ? weather?.temperatureC
          : temps.reduce((sum, value) => sum + value) / temps.length;
      final cloudValues = bucket
          .map((point) => point.cloudCover)
          .whereType<int>()
          .toList();
      final avgCloudCover = cloudValues.isEmpty
          ? null
          : (cloudValues.fold<int>(0, (sum, value) => sum + value) /
                    cloudValues.length)
                .round()
                .clamp(0, 100);

      windows.add(
        _WeatherTrendPoint(
          time: cursor,
          endTime: cursor.add(const Duration(hours: 2)),
          rainProbability: avgRain,
          temperatureC: avgTemp,
          cloudCover: avgCloudCover,
        ),
      );
      cursor = end;
    }

    return windows;
  }

  IconData _weatherIconForPoint(_WeatherTrendPoint point) {
    if (point.rainProbability >= 70) {
      return Icons.thunderstorm_outlined;
    }
    if ((point.cloudCover ?? 100) <= 25 && point.rainProbability <= 35) {
      return Icons.wb_sunny_outlined;
    }
    if ((point.cloudCover ?? 100) <= 55) {
      return Icons.wb_cloudy_outlined;
    }
    if (point.rainProbability >= 45) {
      return Icons.water_drop_outlined;
    }
    return Icons.cloud_outlined;
  }

  Color _riskColor(int probability) {
    if (probability >= 60) {
      return AppColors.danger;
    }
    if (probability >= 40) {
      return const Color(0xFFD49B17);
    }
    return AppColors.success;
  }

  Color _sunlightColor(int probability) {
    if (probability >= 60) {
      return AppColors.success;
    }
    if (probability >= 40) {
      return const Color(0xFFD49B17);
    }
    return AppColors.danger;
  }

  bool _isWithinBestWindow(DateTime time, DateTime? start, DateTime? end) {
    if (start == null || end == null) {
      return false;
    }
    return !time.isBefore(start) && time.isBefore(end);
  }

  @override
  Widget build(BuildContext context) {
    final predictive = weather?.predictive;
    final bool usesOpenWeather = (weather?.source ?? '').contains(
      'OpenWeather',
    );
    final bool openWeatherConfigured =
        OpenWeatherService.hasAnyOpenWeatherProvider;
    final titleSize = rs(context, 22, min: 17);
    final bodySize = rs(context, 14, min: 12);
    final target = location.city ?? location.province ?? location.label;
    final trendPoints = _trendPoints();
    final optimalSunlightWindow = _buildOptimalSunlightWindow(
      weather?.forecast ?? const <ForecastPoint>[],
    );
    final currentRain =
        weather?.rainProbability ?? predictive?.nextRainProbability ?? 0;
    final peakRain = predictive?.maxRainProbability ?? currentRain;
    final rainColor = _riskColor(peakRain);
    final peakSunlight = optimalSunlightWindow?.peakSunlight.round() ?? 0;
    final sunlightColor = _sunlightColor(peakSunlight);
    final bestWindowLabel =
        predictive?.bestDryingWindowLabel ??
        'No best drying weather at this time period';
    final dryingScoreLabel = predictive == null
        ? '--'
        : '${predictive.dryingScore}/100';
    final nextActionLabel =
        predictive?.nextBestAction ?? 'Monitor forecast updates';
    final rainRiskLabel =
        predictive?.nextRainRiskLabel ?? 'No major rain spike in range';
    final recommendationText =
        predictive?.recommendation ??
        'Forecast is still syncing for drying guidance.';
    final bestWindowStart = predictive?.bestDryingStartTime;
    final bestWindowEnd = predictive?.bestDryingEndTime;
    final safeHoursLabel = predictive == null
        ? 'No best drying weather at this time period'
        : formatDryingWindowCountdown(
            start: bestWindowStart,
            end: bestWindowEnd,
            hasBestWindow: predictive.hasClearBestDryingWindow,
          );
    final safeHoursDetail = predictive == null
        ? 'No best drying weather at this time period'
        : (predictive.hasClearBestDryingWindow &&
                  bestWindowStart != null &&
                  bestWindowEnd != null
              ? formatForecastWindow(bestWindowStart, bestWindowEnd)
              : 'No best drying weather at this time period');
    final optimalSunlightDayLabel =
        optimalSunlightWindow?.dayLabel ?? 'No sunny day found';
    final optimalSunlightTimeLabel =
        optimalSunlightWindow?.timeLabel ?? 'No sunny day found';
    final optimalSunlightDetail = optimalSunlightWindow == null
        ? 'Forecast is still syncing for drying guidance.'
        : 'Highest sunlight chance this week';

    String statusLine;
    if (predictive != null) {
      statusLine =
          '${weather?.source ?? 'Weather'} '
          'forecast for $target.';
    } else if (weather == null) {
      statusLine = openWeatherConfigured
          ? 'Forecast data is syncing for predictive analytics.'
          : 'OpenWeather cloud function not configured.';
    } else if (usesOpenWeather) {
      statusLine = 'Forecast data is syncing for predictive analytics.';
    } else if (openWeatherConfigured) {
      statusLine = 'OpenWeather is unavailable. Using fallback provider.';
    } else {
      statusLine = 'OpenWeather cloud function not configured.';
    }

    final conditionLabel = peakRain >= 70
        ? 'High rain risk'
        : (peakRain >= 40 ? 'Rain possible' : 'Good drying window');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF6FAFD)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E0EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 340;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: compact ? 48 : 56,
                    height: compact ? 48 : 56,
                    decoration: BoxDecoration(
                      color: rainColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      predictive == null
                          ? Icons.cloud_outlined
                          : (predictive.riskLevel == 'HIGH'
                                ? Icons.shield_moon_outlined
                                : Icons.wb_sunny_outlined),
                      color: rainColor,
                      size: compact ? 26 : 30,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Predictive Drying Decision Support',
                          style: TextStyle(
                            fontSize: titleSize,
                            height: 1,
                            color: AppColors.textMain,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          target,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        predictive == null ? 'Syncing' : predictive.riskLevel,
                        style: TextStyle(
                          fontSize: compact ? 12 : 13,
                          fontWeight: FontWeight.w800,
                          color: rainColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        predictive == null
                            ? 'Waiting'
                            : '${predictive.dryingScore}/100',
                        style: TextStyle(
                          fontSize: compact ? 20 : 24,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMain,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'drying score',
                        style: TextStyle(
                          fontSize: compact ? 11 : 12,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (compact) ...[
                const SizedBox(height: 6),
                Text(
                  conditionLabel,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                predictive == null ? statusLine : nextActionLabel,
                style: TextStyle(
                  fontSize: bodySize,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                bestWindowLabel,
                style: const TextStyle(
                  color: AppColors.textMain,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                rainRiskLabel,
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _PredictiveCompactStat(
                      label: 'Drying score',
                      value: dryingScoreLabel,
                      valueColor: rainColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PredictiveCompactStat(
                      label: 'Best drying window',
                      value: predictive == null
                          ? '--'
                          : predictive.bestDryingWindowLabel,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PredictiveCompactStat(
                      label: 'Rain risk',
                      value: predictive?.riskLevel ?? 'SYNC',
                      valueColor: rainColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F8FC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDDE6F0)),
                ),
                child: Text(
                  recommendationText,
                  style: TextStyle(
                    fontSize: bodySize,
                    color: const Color(0xFF5D6F88),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _PredictiveCompactStat(
                      label: 'Time left',
                      value: safeHoursLabel,
                      detail: safeHoursDetail,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PredictiveCompactStat(
                      label: 'Current rain',
                      value: '$currentRain%',
                      valueColor: currentRain >= 60
                          ? AppColors.danger
                          : AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PredictiveCompactStat(
                      label: 'Humidity',
                      value: '${weather?.humidity ?? 0}%',
                      valueColor: (weather?.humidity ?? 0) >= 75
                          ? AppColors.danger
                          : AppColors.textMain,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _PredictiveSunlightCard(
                title: 'Optimal sunlight',
                dayLabel: optimalSunlightDayLabel,
                timeLabel: optimalSunlightTimeLabel,
                detail: optimalSunlightDetail,
                accentColor: optimalSunlightWindow == null
                    ? const Color(0xFF9AA7B8)
                    : (optimalSunlightWindow?.averageSunlight ?? 0) >= 75
                    ? AppColors.success
                    : ((optimalSunlightWindow?.averageSunlight ?? 0) >= 50
                          ? const Color(0xFFD49B17)
                          : AppColors.danger),
                actionLabel: optimalSunlightWindow == null
                    ? 'No sunny day found'
                    : 'Dry on this day',
              ),
              const SizedBox(height: 14),
              const _WeatherTab(label: 'Sunlight forecast'),
              const SizedBox(height: 8),
              SizedBox(
                height: 142,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _WeatherTrendChart(
                    points: trendPoints,
                    lineColor: sunlightColor,
                    emptyLabel: weather == null
                        ? 'Forecast is still syncing'
                        : 'No forecast points available',
                  ),
                ),
              ),
              if (trendPoints.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 168,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: trendPoints.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final point = trendPoints[index];
                      return _ForecastStripTile(
                        point: point,
                        icon: _weatherIconForPoint(point),
                        active: _isWithinBestWindow(
                          point.time,
                          bestWindowStart,
                          bestWindowEnd,
                        ),
                        color:
                            (point.cloudCover ?? 100) <= 25 &&
                                point.sunlightProbability >= 75
                            ? AppColors.success
                            : _sunlightColor(point.sunlightProbability),
                      );
                    },
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PredictiveCompactStat extends StatelessWidget {
  const _PredictiveCompactStat({
    required this.label,
    required this.value,
    this.detail,
    this.valueColor = AppColors.textMain,
  });

  final String label;
  final String value;
  final String? detail;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final hasDetail = detail != null && detail!.trim().isNotEmpty;
    return Container(
      constraints: BoxConstraints(minHeight: hasDetail ? 86 : 70),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E7F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              height: 1.05,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
          if (hasDetail) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10.5,
                height: 1.05,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PredictiveSunlightCard extends StatelessWidget {
  const _PredictiveSunlightCard({
    required this.title,
    required this.dayLabel,
    required this.timeLabel,
    required this.detail,
    required this.accentColor,
    required this.actionLabel,
  });

  final String title;
  final String dayLabel;
  final String timeLabel;
  final String detail;
  final Color accentColor;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE4F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wb_sunny_outlined, color: accentColor, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textMain,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Best period',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            dayLabel,
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 15,
              height: 1.05,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            timeLabel,
            style: TextStyle(
              color: accentColor,
              fontSize: 18,
              height: 1.05,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12.5,
              height: 1.1,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Next action: $actionLabel',
            style: TextStyle(
              color: accentColor,
              fontSize: 11.5,
              height: 1.05,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherTab extends StatelessWidget {
  const _WeatherTab({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const SizedBox(
            height: 3,
            width: 88,
            child: ColoredBox(color: Color(0xFFF4BE00)),
          ),
        ],
      ),
    );
  }
}

class _ForecastStripTile extends StatelessWidget {
  const _ForecastStripTile({
    required this.point,
    required this.icon,
    required this.color,
    required this.active,
  });

  final _WeatherTrendPoint point;
  final IconData icon;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tempF = point.temperatureC == null
        ? null
        : ((point.temperatureC! * 9 / 5) + 32).round();
    return Container(
      width: 112,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE9EDF5) : const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? const Color(0xFFD2DAE8) : const Color(0xFFE3E9F2),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _compactForecastLabel(point.time),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              height: 1.02,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            _compactForecastTimeRange(point.time, point.endTime),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 10,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            _sunlightLabel(point),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
          Icon(icon, color: color, size: 21),
          Text(
            tempF == null ? '${point.sunlightProbability}%' : '$tempF°',
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '${point.sunlightProbability}%',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _compactForecastLabel(DateTime time) {
    const days = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${days[time.weekday - 1]}, ${months[time.month - 1]} ${time.day}';
  }

  String _compactForecastTimeRange(DateTime start, DateTime end) {
    return '${_shortClockTime(start)} - ${_shortClockTime(end)}';
  }

  String _shortClockTime(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final meridian = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour $meridian';
  }

  String _sunlightLabel(_WeatherTrendPoint point) {
    if ((point.cloudCover ?? 100) <= 25 && point.sunlightProbability >= 75) {
      return 'Best sunlight';
    }
    if ((point.cloudCover ?? 100) <= 55 || point.sunlightProbability >= 45) {
      return 'Partial sun';
    }
    return 'Low sun';
  }

  _WeeklySunlightWindow? _weeklySunlightWindow(
    List<_WeatherTrendPoint> points,
  ) {
    if (points.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    final horizonEnd = now.add(const Duration(days: 7));
    final horizon =
        points
            .where(
              (point) =>
                  !point.time.isBefore(
                    now.subtract(const Duration(minutes: 1)),
                  ) &&
                  point.time.isBefore(horizonEnd),
            )
            .toList()
          ..sort((a, b) => a.time.compareTo(b.time));

    if (horizon.isEmpty) {
      return null;
    }

    final dayBuckets = <DateTime, List<_WeatherTrendPoint>>{};
    for (final point in horizon) {
      final dayKey = DateTime(
        point.time.year,
        point.time.month,
        point.time.day,
      );
      dayBuckets.putIfAbsent(dayKey, () => <_WeatherTrendPoint>[]).add(point);
    }

    _WeeklySunlightWindow? best;
    for (final entry in dayBuckets.entries) {
      final dayPoints = entry.value..sort((a, b) => a.time.compareTo(b.time));
      if (dayPoints.isEmpty) {
        continue;
      }

      final dayBest = _findBestSunWindow(dayPoints);
      if (dayBest == null) {
        continue;
      }

      final candidate = _WeeklySunlightWindow(
        dayStart: entry.key,
        windowStart: dayPoints[dayBest.startIndex].time,
        windowEnd: dayPoints[dayBest.endIndex].endTime,
        averageSunlight: dayBest.averageScore,
        windowPoints: dayBest.endIndex - dayBest.startIndex + 1,
        totalDayPoints: dayPoints.length,
      );

      if (best == null ||
          candidate.averageSunlight > best.averageSunlight ||
          (candidate.averageSunlight == best.averageSunlight &&
              candidate.dayStart.isBefore(best.dayStart))) {
        best = candidate;
      }
    }

    if (best == null || !best.hasClearBestWindow) {
      return null;
    }

    return best;
  }

  ({int startIndex, int endIndex, double averageScore})? _findBestSunWindow(
    List<_WeatherTrendPoint> points,
  ) {
    if (points.isEmpty) {
      return null;
    }

    final maxWindowPoints = points.length >= 4 ? 4 : points.length;
    final minWindowPoints = points.length >= 3 ? 2 : 1;
    ({int startIndex, int endIndex, double averageScore})? best;

    for (var length = maxWindowPoints; length >= minWindowPoints; length--) {
      for (var start = 0; start + length <= points.length; start++) {
        final end = start + length - 1;
        final slice = points.sublist(start, end + 1);
        final averageScore =
            slice.fold<double>(
              0,
              (sum, point) => sum + point.sunlightProbability,
            ) /
            slice.length;
        final candidate = (
          startIndex: start,
          endIndex: end,
          averageScore: averageScore,
        );

        if (best == null ||
            candidate.averageScore > best.averageScore ||
            (candidate.averageScore == best.averageScore &&
                start < best.startIndex)) {
          best = candidate;
        }
      }

      if (best != null) {
        break;
      }
    }

    if (best == null || best.averageScore < 55) {
      return null;
    }

    return best;
  }
}

class _WeeklySunlightWindow {
  const _WeeklySunlightWindow({
    required this.dayStart,
    required this.windowStart,
    required this.windowEnd,
    required this.averageSunlight,
    required this.windowPoints,
    required this.totalDayPoints,
  });

  final DateTime dayStart;
  final DateTime windowStart;
  final DateTime windowEnd;
  final double averageSunlight;
  final int windowPoints;
  final int totalDayPoints;

  bool get hasClearBestWindow =>
      windowPoints > 0 && windowPoints < totalDayPoints;

  String get dayLabel => formatForecastDayDate(dayStart);
  String get timeLabel => 'Next sunny day';
}

class _WeatherTrendPoint {
  const _WeatherTrendPoint({
    required this.time,
    required this.endTime,
    required this.rainProbability,
    this.temperatureC,
    this.cloudCover,
  });

  final DateTime time;
  final DateTime endTime;
  final int rainProbability;
  final double? temperatureC;
  final int? cloudCover;

  int get sunlightProbability {
    final rainSunlight = 100 - rainProbability;
    final cloudSunlight = cloudCover == null
        ? rainSunlight
        : 100 - cloudCover!.clamp(0, 100);
    return ((rainSunlight * 0.45) + (cloudSunlight * 0.55)).round().clamp(
      0,
      100,
    );
  }
}

class _WeatherTrendChart extends StatelessWidget {
  const _WeatherTrendChart({
    required this.points,
    required this.lineColor,
    required this.emptyLabel,
  });

  final List<_WeatherTrendPoint> points;
  final Color lineColor;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        width: MediaQuery.sizeOf(context).width - 56,
        child: Center(
          child: Text(
            emptyLabel,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    final chartWidth = math.max(
      MediaQuery.sizeOf(context).width - 56,
      points.length * 136.0,
    );

    return SizedBox(
      width: chartWidth,
      height: 142,
      child: CustomPaint(
        painter: _WeatherTrendPainter(points: points, lineColor: lineColor),
      ),
    );
  }
}

class _WeatherTrendPainter extends CustomPainter {
  const _WeatherTrendPainter({required this.points, required this.lineColor});

  final List<_WeatherTrendPoint> points;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final chartTop = 14.0;
    final chartBottom = size.height - 52;
    final chartHeight = chartBottom - chartTop;
    final stepX = points.length == 1 ? 0.0 : size.width / (points.length - 1);
    final path = Path();
    final fillPath = Path();
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);
    final coordinates = <Offset>[];

    for (var i = 0; i < points.length; i++) {
      final value = points[i].sunlightProbability.clamp(0, 100);
      final x = points.length == 1 ? size.width / 2 : stepX * i;
      final y = chartBottom - ((value / 100) * chartHeight);
      final offset = Offset(x, y);
      coordinates.add(offset);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, chartBottom);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(coordinates.last.dx, chartBottom);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()..color = lineColor.withValues(alpha: 0.18),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (var i = 0; i < points.length; i++) {
      final offset = coordinates[i];
      final sunText = '${points[i].sunlightProbability}%';
      labelPainter.text = TextSpan(
        text: sunText,
        style: const TextStyle(
          color: Color(0xFF75829A),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      );
      labelPainter.layout();
      labelPainter.paint(
        canvas,
        Offset(
          (offset.dx - labelPainter.width / 2).clamp(
            0,
            size.width - labelPainter.width,
          ),
          (offset.dy - 20).clamp(0, chartBottom - 18),
        ),
      );

      labelPainter.text = TextSpan(
        text:
            '${formatForecastDayDate(points[i].time)}\n${formatForecastWindow(points[i].time, points[i].endTime)}',
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 9,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      );
      labelPainter.textAlign = TextAlign.center;
      labelPainter.layout();
      labelPainter.paint(
        canvas,
        Offset(
          (offset.dx - labelPainter.width / 2).clamp(
            0,
            size.width - labelPainter.width,
          ),
          size.height - 38,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherTrendPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.lineColor != lineColor;
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

    final isOnline = status == 'Online';
    final dotColor = isOnline ? const Color(0xFF2DB367) : AppColors.textMuted;
    final readColor = reading == '--' || reading == 'Unknown'
        ? AppColors.textMuted
        : AppColors.primary;

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
                    Flexible(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF7888A1)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF9BA8BE)),
                ),
                Text(
                  reading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: valueSize, color: readColor),
                ),
              ],
            ),
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
    final valueSize = rs(context, 26, min: 20);

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
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF667A98)),
          ),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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
    required this.isRead,
    this.rightLabel,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final String time;
  final bool isRead;
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
                    color: isRead ? AppColors.textMuted : AppColors.textMain,
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
        const Icon(Icons.circle_outlined, size: 16, color: Color(0xFF6ACEA1)),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontSize: 16, color: Color(0xFF566A86)),
        ),
      ],
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
