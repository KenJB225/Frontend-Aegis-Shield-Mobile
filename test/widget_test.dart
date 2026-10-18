// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:aegis_dry_mobile/main.dart';

void main() {
  testWidgets('App shows startup loading state', (WidgetTester tester) async {
    await tester.pumpWidget(const AegisDryApp());
    expect(find.text('Preparing your account'), findsOneWidget);
  });

  testWidgets('Device stat cards fit long provider names on mobile', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: DeviceScreen(
          onOpenManualControl: () {},
          location: const AppLocation(
            label: 'Quezon City, Philippines',
            latitude: 14.65,
            longitude: 121.05,
          ),
          weather: const WeatherSnapshot(
            temperatureC: 30,
            sky: 'Clouds',
            humidity: 70,
            rainProbability: 20,
            source: 'OpenWeather Cloud',
          ),
          lastWeatherSyncAt: null,
          movementAnalytics: null,
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Data Source'),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Data Source'), findsOneWidget);
    expect(find.text('Mode'), findsOneWidget);
    final sourceValue = tester.widget<Text>(find.text('OpenWeather Cloud'));
    expect(sourceValue.maxLines, 2);
    expect(tester.takeException(), isNull);
  });
}
