import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class HardwareState {
  final double temperatureC;
  final double humidity;
  final bool isRaining;
  final String rackStatus;
  final bool isAutoMode;

  HardwareState({required this.temperatureC, required this.humidity, required this.isRaining, required this.rackStatus, required this.isAutoMode});

  factory HardwareState.fromMap(Map<String, dynamic> map) {
    return HardwareState(
      temperatureC: (map['temperature_c'] ?? 0).toDouble(),
      humidity: (map['humidity'] ?? 0).toDouble(),
      isRaining: map['is_raining'] ?? false,
      rackStatus: map['rack_status'] ?? 'UNKNOWN',
      isAutoMode: map['is_auto_mode'] ?? true,
    );
  }
}

class HardwareService {
  final SupabaseClient client;
  final String deviceId;
  final String ownerEmail;

  HardwareService(this.client, {required this.deviceId, required this.ownerEmail});

  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  void subscribe(void Function(HardwareState) onUpdate) {
    _sub = client
        .from('device_status')
        .stream(primaryKey: ['id'])
        .listen((List<Map<String, dynamic>> rows) {
      final matches = rows
          .where((row) => row['device_id'] == deviceId && row['owner_email'] == ownerEmail)
          .toList();
      if (matches.isNotEmpty) {
        onUpdate(HardwareState.fromMap(matches.first));
      }
    });
  }

  Future<void> sendCommand(String command) async {
    await client
        .from('device_status')
        .update({'command': command})
        .eq('device_id', deviceId)
        .eq('owner_email', ownerEmail);
  }

  Future<void> setAutoMode(bool enabled) async {
    await client
        .from('device_status')
        .update({'is_auto_mode': enabled})
        .eq('device_id', deviceId)
        .eq('owner_email', ownerEmail);
  }

  void dispose() {
    if (_sub != null) {
      _sub!.cancel();
      _sub = null;
    }
  }
}
