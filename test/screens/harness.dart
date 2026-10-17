// Screenshot harness: renders widgets at phone size with the real fonts.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dalabapay/ui/ui.dart';

Future<void> loadFonts() async {
  final loader = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/Inter-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

void mockPlatform([Map<String, Object> prefs = const {}]) {
  SharedPreferences.setMockInitialValues(prefs);
  const channels = [
    'plugins.it_nomads.com/flutter_secure_storage',
    'plugins.flutter.io/local_auth',
    'dev.fluttercommunity.plus/connectivity',
    'dev.fluttercommunity.plus/package_info',
    'plugins.flutter.io/firebase_messaging',
    'plugins.flutter.io/firebase_core',
  ];
  for (final c in channels) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(c), (call) async => null);
  }
}

Future<void> shoot(
  WidgetTester tester,
  String name,
  Widget child, {
  double height = 844,
  Map<String, WidgetBuilder>? routes,
  Duration settle = const Duration(milliseconds: 600),
}) async {
  tester.view.physicalSize = Size(390 * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: DPTheme.light(),
    home: child,
    routes: routes ?? const {},
    onUnknownRoute: (s) => MaterialPageRoute(
      builder: (_) => Scaffold(body: Center(child: Text('route ${s.name}'))),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(settle ~/ 6));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
}
