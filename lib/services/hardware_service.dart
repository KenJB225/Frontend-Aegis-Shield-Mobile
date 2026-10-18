import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class HardwareState {
  final double temperatureC;
  final double humidity;
  final bool isRaining;
  final String rackStatus;
  final DateTime? obstructionEventAt;
  final bool isAutoMode;
  final DateTime? lastUpdated;

  bool get isOnline {
    final updatedAt = lastUpdated;
    if (updatedAt == null) {
      return false;
    }
    return DateTime.now().difference(updatedAt.toLocal()) <=
        const Duration(seconds: 30);
  }

  HardwareState({
    required this.temperatureC,
    required this.humidity,
    required this.isRaining,
    required this.rackStatus,
    required this.obstructionEventAt,
    required this.isAutoMode,
    required this.lastUpdated,
  });

  factory HardwareState.fromMap(Map<String, dynamic> map) {
    return HardwareState(
      temperatureC: (map['temperature_c'] ?? 0).toDouble(),
      humidity: (map['humidity'] ?? 0).toDouble(),
      isRaining: map['is_raining'] ?? false,
      rackStatus: map['rack_status'] ?? 'UNKNOWN',
      obstructionEventAt: DateTime.tryParse(
        map['obstruction_event_at']?.toString() ?? '',
      ),
      isAutoMode: map['is_auto_mode'] ?? true,
      lastUpdated: DateTime.tryParse(map['last_updated']?.toString() ?? ''),
    );
  }
}

class HardwareService {
  static DateTime? _lastAppCommandAt;
  static String? _lastAppCommand;

  final SupabaseClient client;
  final String deviceId;
  final String ownerEmail;

  HardwareService(
    this.client, {
    required this.deviceId,
    required this.ownerEmail,
  });

  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  static void noteAppCommandIssued(String command) {
    final normalized = command.trim().toUpperCase();
    if (normalized.isEmpty) {
      return;
    }
    _lastAppCommand = normalized;
    _lastAppCommandAt = DateTime.now();
  }

  static bool hasRecentAppCommandForAction(
    String action, {
    Duration window = const Duration(minutes: 2),
  }) {
    final issuedAt = _lastAppCommandAt;
    if (issuedAt == null) {
      return false;
    }
    if (DateTime.now().difference(issuedAt) > window) {
      return false;
    }

    final normalizedAction = action.trim().toUpperCase();
    final expectedCommand = switch (normalizedAction) {
      'EXTEND' => 'DEPLOY',
      'RETRACT' => 'RETRACT',
      _ => normalizedAction,
    };
    return _lastAppCommand == expectedCommand;
  }

  void subscribe(void Function(HardwareState) onUpdate) {
    _sub = client.from('device_status').stream(primaryKey: ['id']).listen((
      List<Map<String, dynamic>> rows,
    ) {
      final matches = rows
          .where(
            (row) =>
                row['device_id'] == deviceId &&
                row['owner_email'] == ownerEmail,
          )
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
