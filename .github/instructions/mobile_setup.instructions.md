# Flutter Mobile App Setup Guide

This guide provides comprehensive step-by-step instructions for setting up the Aegis-Dry Flutter mobile application with Supabase as the backend-as-a-service (BaaS) provider.

---

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Flutter Project Setup](#flutter-project-setup)
3. [Supabase Integration](#supabase-integration)
4. [Authentication Setup](#authentication-setup)
5. [Real-time Database Integration](#real-time-database-integration)
6. [Direct Supabase Data Access](#direct-supabase-data-access)
7. [State Management](#state-management)
8. [Project Structure](#project-structure)
9. [Running the App](#running-the-app)
10. [Testing and Validation](#testing-and-validation)

---

## Prerequisites

### System Requirements
- **Flutter SDK:** v3.0 or higher ([Download](https://flutter.dev/docs/get-started/install))
- **Dart:** v2.17 or higher (comes with Flutter)
- **IDE:** Android Studio, VS Code, or IntelliJ IDEA
- **Device/Emulator:** Android 7+ or iOS 12+

### Verify Installation
```bash
flutter --version
dart --version
```

### Required Accounts
1. **Supabase Account** - For backend-as-a-service
2. **OpenWeatherMap Account** - For weather API (optional for development)

---

## Flutter Project Setup

### Step 1: Create a New Flutter Project
```bash
flutter create aegis_dry_mobile
cd aegis_dry_mobile
```

### Step 2: Update Project Structure
```
aegis_dry_mobile/
├── lib/
│   ├── main.dart                    # App entry point
│   ├── config/
│   │   └── env.dart                 # Environment variables
│   ├── screens/
│   │   ├── auth/
│   │   │   ├── login_screen.dart
│   │   │   ├── signup_screen.dart
│   │   │   └── forgot_password_screen.dart
│   │   ├── home/
│   │   │   └── home_screen.dart
│   │   ├── device/
│   │   │   ├── device_detail_screen.dart
│   │   │   ├── device_control_screen.dart
│   │   │   └── manual_override_screen.dart
│   │   ├── logs/
│   │   │   └── activity_logs_screen.dart
│   │   ├── settings/
│   │   │   └── settings_screen.dart
│   │   └── splash/
│   │       └── splash_screen.dart
│   ├── services/
│   │   ├── supabase_service.dart       # Supabase client initialization
│   │   ├── auth_service.dart           # Authentication logic
│   │   ├── device_service.dart         # Device management
│   │   ├── sensor_service.dart         # Sensor data fetching
│   │   └── weather_service.dart        # Weather API integration
│   ├── models/
│   │   ├── user_model.dart
│   │   ├── device_model.dart
│   │   ├── sensor_reading_model.dart
│   │   ├── event_log_model.dart
│   │   └── weather_model.dart
│   ├── providers/
│   │   ├── auth_provider.dart          # Authentication state (Riverpod)
│   │   ├── device_provider.dart        # Device state
│   │   ├── sensor_provider.dart        # Sensor data state
│   │   └── theme_provider.dart         # Theme state
│   ├── widgets/
│   │   ├── device_card.dart
│   │   ├── sensor_display.dart
│   │   ├── status_indicator.dart
│   │   └── common_widgets.dart
│   └── utils/
│       ├── constants.dart             # App-wide constants
│       ├── validators.dart            # Input validators
│       └── logging.dart               # Logging utilities
├── assets/
│   ├── images/
│   │   └── logo.png
│   └── icons/
│       └── device_icon.png
├── test/
│   └── widget_test.dart
├── pubspec.yaml                       # Dependencies
├── pubspec.lock
└── analysis_options.yaml

```

### Step 3: Update pubspec.yaml
```yaml
name: aegis_dry_mobile
description: Aegis-Dry mobile application for IoT rain detection system.
version: 1.0.0+1

environment:
  sdk: ">=2.17.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  
  # Supabase
  supabase_flutter: ^1.10.0
  
  # State Management
  riverpod: ^2.4.0
  flutter_riverpod: ^2.4.0
  
  # HTTP & Networking
  http: ^1.1.0
  dio: ^5.3.0
  
  # Local Storage
  shared_preferences: ^2.2.2
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  
  # Date & Time
  intl: ^0.18.1
  
  # UI & UX
  google_fonts: ^6.1.0
  flutter_svg: ^2.0.7
  cached_network_image: ^3.3.0
  shimmer: ^3.0.0
  
  # Form & Validation
  formz: ^0.7.0
  
  # Firebase (for push notifications - optional)
  firebase_core: ^2.24.0
  firebase_messaging: ^14.6.0
  
  # Logging
  logger: ^2.0.1
  
  # Environment variables
  flutter_dotenv: ^5.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^2.0.0
  build_runner: ^2.4.0
  hive_generator: ^2.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/icons/
    - .env
  fonts:
    - family: GoogleFonts
      fonts:
        - asset: assets/fonts/roboto/Roboto-Regular.ttf
```

### Step 4: Install Dependencies
```bash
flutter pub get
```

---

## Supabase Integration

### Step 1: Create Environment Configuration (lib/config/env.dart)

```dart
class Env {
  static const String supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
  static const String openWeatherMapApiKey = 'YOUR_OPENWEATHERMAP_KEY';
  
  // Static values that don't require secrets
  static const String appName = 'Aegis Dry';
  static const String appVersion = '1.0.0';
}
```

### Step 2: Create Supabase Service (lib/services/supabase_service.dart)

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aegis_dry_mobile/config/env.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  
  late SupabaseClient _client;
  
  SupabaseService._internal();
  
  factory SupabaseService() {
    return _instance;
  }
  
  // Initialize Supabase
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );
  }
  
  // Get Supabase client
  SupabaseClient get client => Supabase.instance.client;
  
  // Get Auth instance
  GotrueClient get auth => client.auth;
  
  // Get current session
  Session? get currentSession => auth.currentSession;
  
  // Get current user
  User? get currentUser => auth.currentUser;
  
  // Check if user is authenticated
  bool get isAuthenticated => currentUser != null;
  
  // Sign out
  Future<void> signOut() async {
    await auth.signOut();
  }
}
```

### Step 3: Create Models (lib/models/)

#### User Model (lib/models/user_model.dart)
```dart
class UserModel {
  final String id;
  final String email;
  final String fullName;
  final String? phone;
  final String? companyName;
  final String? profilePictureUrl;
  final String role;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    this.phone,
    this.companyName,
    this.profilePictureUrl,
    required this.role,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });
  
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['user_id'] ?? '',
      email: json['email'] ?? '',
      fullName: json['full_name'] ?? '',
      phone: json['phone'],
      companyName: json['company_name'],
      profilePictureUrl: json['profile_picture_url'],
      role: json['role'] ?? 'USER',
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toString()),
      updatedAt: DateTime.parse(json['updated_at'] ?? DateTime.now().toString()),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'user_id': id,
      'email': email,
      'full_name': fullName,
      'phone': phone,
      'company_name': companyName,
      'profile_picture_url': profilePictureUrl,
      'role': role,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
```

#### Device Model (lib/models/device_model.dart)
```dart
class DeviceModel {
  final String deviceId;
  final String userId;
  final String macAddress;
  final String status; // EXTENDED or DOCKED
  final int rainThreshold;
  final String mode; // AUTO or MANUAL
  final String systemHealthStatus; // Safe, Warning, Critical
  final DateTime? lastCheckedAt;
  final DateTime updatedAt;
  final DateTime createdAt;
  
  DeviceModel({
    required this.deviceId,
    required this.userId,
    required this.macAddress,
    required this.status,
    required this.rainThreshold,
    required this.mode,
    required this.systemHealthStatus,
    this.lastCheckedAt,
    required this.updatedAt,
    required this.createdAt,
  });
  
  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      deviceId: json['device_id'] ?? '',
      userId: json['user_id'] ?? '',
      macAddress: json['mac_address'] ?? '',
      status: json['status'] ?? 'EXTENDED',
      rainThreshold: json['rain_threshold'] ?? 75,
      mode: json['mode'] ?? 'AUTO',
      systemHealthStatus: json['system_health_status'] ?? 'Safe',
      lastCheckedAt: json['last_checked_at'] != null
          ? DateTime.parse(json['last_checked_at'])
          : null,
      updatedAt: DateTime.parse(json['updated_at'] ?? DateTime.now().toString()),
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toString()),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'user_id': userId,
      'mac_address': macAddress,
      'status': status,
      'rain_threshold': rainThreshold,
      'mode': mode,
      'system_health_status': systemHealthStatus,
      'last_checked_at': lastCheckedAt?.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
```

#### Sensor Reading Model (lib/models/sensor_reading_model.dart)
```dart
class SensorReadingModel {
  final String readingId;
  final String deviceId;
  final String sensorType; // RAIN, TEMPERATURE, HUMIDITY, SOIL_MOISTURE
  final double value;
  final String unit;
  final int? batteryLevel;
  final String? signalStrength;
  final String status; // Online, Offline, LinkLost
  final DateTime timestamp;
  
  SensorReadingModel({
    required this.readingId,
    required this.deviceId,
    required this.sensorType,
    required this.value,
    required this.unit,
    this.batteryLevel,
    this.signalStrength,
    required this.status,
    required this.timestamp,
  });
  
  factory SensorReadingModel.fromJson(Map<String, dynamic> json) {
    return SensorReadingModel(
      readingId: json['reading_id'] ?? '',
      deviceId: json['device_id'] ?? '',
      sensorType: json['sensor_type'] ?? '',
      value: (json['value'] ?? 0).toDouble(),
      unit: json['unit'] ?? '',
      batteryLevel: json['battery_level'],
      signalStrength: json['signal_strength'],
      status: json['status'] ?? 'Online',
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toString()),
    );
  }
}
```

---

## Authentication Setup

### Step 1: Create Auth Service (lib/services/auth_service.dart)

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aegis_dry_mobile/services/supabase_service.dart';

class AuthService {
  final _supabaseService = SupabaseService();
  
  // Sign up with email and password
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final response = await _supabaseService.auth.signUp(
        email: email,
        password: password,
      );
      
      // Create user profile
      if (response.user != null) {
        await _supabaseService.client.from('user_profiles').insert({
          'user_id': response.user!.id,
          'full_name': fullName,
          'email': email,
        });
      }
      
      return response;
    } catch (e) {
      rethrow;
    }
  }
  
  // Sign in with email and password
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _supabaseService.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      rethrow;
    }
  }
  
  // Sign out
  Future<void> signOut() async {
    try {
      await _supabaseService.signOut();
    } catch (e) {
      rethrow;
    }
  }
  
  // Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _supabaseService.auth.resetPasswordForEmail(email);
    } catch (e) {
      rethrow;
    }
  }
  
  // Get current user
  User? getCurrentUser() {
    return _supabaseService.currentUser;
  }
  
  // Get authentication state stream
  Stream<AuthState> authStateChanges() {
    return _supabaseService.auth.onAuthStateChange;
  }
}
```

### Step 2: Create Auth Provider (lib/providers/auth_provider.dart)

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aegis_dry_mobile/services/auth_service.dart';

final authServiceProvider = Provider((ref) => AuthService());

final authStateProvider = StreamProvider<AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges();
});

final currentUserProvider = StateProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.getCurrentUser();
});

final isAuthenticatedProvider = StateProvider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  return user != null;
});
```

---

## Real-time Database Integration

### Step 1: Create Device Service (lib/services/device_service.dart)

```dart
import 'package:aegis_dry_mobile/models/device_model.dart';
import 'package:aegis_dry_mobile/services/supabase_service.dart';

class DeviceService {
  final _supabaseService = SupabaseService();
  
  // Fetch all devices for current user
  Future<List<DeviceModel>> getUserDevices(String userId) async {
    try {
      final response = await _supabaseService.client
          .from('devices')
          .select()
          .eq('user_id', userId);
      
      return (response as List)
          .map((device) => DeviceModel.fromJson(device))
          .toList();
    } catch (e) {
      rethrow;
    }
  }
  
  // Get single device
  Future<DeviceModel> getDevice(String deviceId) async {
    try {
      final response = await _supabaseService.client
          .from('devices')
          .select()
          .eq('device_id', deviceId)
          .single();
      
      return DeviceModel.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }
  
  // Update rain threshold
  Future<void> updateRainThreshold(String deviceId, int threshold) async {
    try {
      await _supabaseService.client
          .from('devices')
          .update({'rain_threshold': threshold})
          .eq('device_id', deviceId);
    } catch (e) {
      rethrow;
    }
  }
  
  // Subscribe to real-time device updates
  Stream<List<DeviceModel>> subscribeToDevices(String userId) {
    return _supabaseService.client
        .from('devices')
        .stream(primaryKey: ['device_id'])
        .eq('user_id', userId)
        .map((devices) => devices
            .map((device) => DeviceModel.fromJson(device))
            .toList());
  }
}
```

### Step 2: Create Device Provider (lib/providers/device_provider.dart)

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aegis_dry_mobile/models/device_model.dart';
import 'package:aegis_dry_mobile/services/device_service.dart';
import 'package:aegis_dry_mobile/providers/auth_provider.dart';

final deviceServiceProvider = Provider((ref) => DeviceService());

final devicesProvider = StreamProvider<List<DeviceModel>>((ref) {
  final user = ref.watch(currentUserProvider);
  final deviceService = ref.watch(deviceServiceProvider);
  
  if (user == null) {
    return Stream.value([]);
  }
  
  // Get user profile to get the user_profiles.id
  return deviceService.subscribeToDevices(user.id);
});

final deviceProvider = FutureProvider.family<DeviceModel, String>((ref, deviceId) {
  final deviceService = ref.watch(deviceServiceProvider);
  return deviceService.getDevice(deviceId);
});
```

---

## Direct Supabase Data Access

The mobile app does **not** depend on Next.js routes. It reads and writes directly to Supabase tables using the anon key and RLS policies.

### Step 1: Use Supabase Queries in Service Layer

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

class MobileDataService {
  final SupabaseClient client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getSensorReadings(String deviceId) async {
    final rows = await client
        .from('sensor_readings')
        .select()
        .eq('device_id', deviceId)
        .order('timestamp', ascending: false)
        .limit(100);

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> getEventLogs(String deviceId) async {
    final rows = await client
        .from('event_logs')
        .select()
        .eq('device_id', deviceId)
        .order('timestamp', ascending: false)
        .limit(100);

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> updateRainThreshold(String deviceId, int threshold) async {
    await client
        .from('devices')
        .update({'rain_threshold': threshold, 'updated_at': DateTime.now().toIso8601String()})
        .eq('device_id', deviceId);
  }

  Future<void> sendManualOverride(String deviceId, String action) async {
    await client.from('event_logs').insert({
      'device_id': deviceId,
      'event_type': 'MANUAL_OVERRIDE',
      'action_taken': action,
      'details': {'source': 'mobile_app'},
    });
  }
}
```

### Step 2: Use Realtime Streams for Live UI

```dart
final deviceStream = Supabase.instance.client
    .from('devices')
    .stream(primaryKey: ['device_id'])
    .eq('device_id', deviceId);

final sensorStream = Supabase.instance.client
    .from('sensor_readings')
    .stream(primaryKey: ['reading_id'])
    .eq('device_id', deviceId);
```

### Step 3: Optional Server Logic Path

For privileged or computed operations, call Supabase **Edge Functions** or **RPC** instead of Next.js.

```dart
final result = await Supabase.instance.client.functions.invoke(
  'compute_device_instruction',
  body: {'device_id': deviceId},
);
```

---

## State Management

### Step 1: Setup Main App with Riverpod (lib/main.dart)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aegis_dry_mobile/config/env.dart';
import 'package:aegis_dry_mobile/services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase
  await SupabaseService.initialize();
  
  runApp(
    const ProviderScope(
      child: AegisDryApp(),
    ),
  );
}

class AegisDryApp extends ConsumerWidget {
  const AegisDryApp({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: Env.appName,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    
    return authState.when(
      data: (state) {
        if (state.session != null) {
          return const HomeScreen();
        } else {
          return const LoginScreen();
        }
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        body: Center(child: Text('Error: $error')),
      ),
    );
  }
}
```

---

## Project Structure Summary

- **Screens**: User interface pages (login, home, device details, etc.)
- **Services**: Business logic and API communication
- **Models**: Data structures and serialization
- **Providers**: State management using Riverpod
- **Widgets**: Reusable UI components
- **Config**: Environment variables and constants

---

## Running the App

### Android
```bash
flutter run -d android
```

### iOS
```bash
flutter run -d iphone
```

### Web (Development)
```bash
flutter run -d chrome
```

### Build for Release
```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release
```

---

## Testing and Validation

### Step 1: Test Authentication
1. Run the app on an emulator or device
2. Navigate to login/signup screen
3. Create a test account
4. Verify email confirmation (should be sent)
5. Log in with the test account

### Step 2: Test Real-time Sync
1. Open the app on two devices with the same account
2. Change the rain threshold on one device
3. Verify the change appears on the other device in real-time

### Step 3: Test Device Communication
1. Ensure Supabase project is online and keys are valid
2. Fetch device status and sensor readings directly from Supabase
3. Verify data displays correctly

### Step 4: Test Manual Override
1. Navigate to Manual Override screen
2. Send a DOCK/EXTEND command
3. Verify corresponding records update in `event_logs` and `devices`

### Step 5: Test Activity Logs
1. View activity logs for a device
2. Verify pagination and filtering work
3. Check that logs display correct timestamps

---

## Common Issues and Solutions

### Issue: Supabase Connection Fails
- **Cause:** Incorrect URL or API keys
- **Solution:** Verify `Env.supabaseUrl` and `Env.supabaseAnonKey` in `lib/config/env.dart`

### Issue: Real-time Updates Not Working
- **Cause:** Realtime not enabled in Supabase dashboard
- **Solution:** Ensure tables are added to the `realtime_updates` publication (see [Supabase Setup Guide](supabase_setup.instructions.md#realtime-configuration))

### Issue: Authentication Token Expired
- **Cause:** User session expired after 24 hours
- **Solution:** Implement token refresh logic in auth service

### Issue: Slow App Performance
- **Cause:** Too many database queries or large datasets
- **Solution:** Implement pagination, caching, and lazy loading

---

## Next Steps

1. **Implement UI Screens** - Design and implement all user-facing screens
2. **Add Push Notifications** - Configure Firebase Cloud Messaging (FCM)
3. **Implement Offline Support** - Use Hive for local caching
4. **Add Analytics** - Track user behavior and app performance
5. **Deploy to App Stores** - Publish to Google Play Store and Apple App Store

---

## Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Supabase Flutter Docs](https://supabase.com/docs/reference/flutter/introduction)
- [Riverpod Documentation](https://riverpod.dev)
- [Material Design Guidelines](https://material.io/design)


