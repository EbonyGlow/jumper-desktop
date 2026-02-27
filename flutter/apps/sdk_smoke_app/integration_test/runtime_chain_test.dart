import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sdk_smoke_app/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('runs start -> proxies -> stop chain', (tester) async {
    await tester.pumpWidget(const SmokeApp());
    await _waitForStartEnabled(tester);

    await tester.tap(find.byKey(kStartButtonKey));
    await tester.pump(const Duration(seconds: 2));

    final count = await _waitForPositiveProxyCount(tester);
    expect(count, greaterThan(0));

    await tester.tap(find.byKey(kStopButtonKey));
    await tester.pump(const Duration(seconds: 1));
  });
}

Future<void> _waitForStartEnabled(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    final button = tester.widget<ElevatedButton>(find.byKey(kStartButtonKey));
    if (button.onPressed != null) {
      return;
    }
  }
  fail('Start button was not enabled in time');
}

Future<void> _waitForLoadProxiesEnabled(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    final button = tester.widget<OutlinedButton>(find.byKey(kLoadProxiesButtonKey));
    if (button.onPressed != null) {
      return;
    }
  }
  fail('Load Proxies button was not enabled in time');
}

int _extractProxyCount(String value) {
  final match = RegExp(r'Proxy groups loaded:\s*(\d+)').firstMatch(value);
  if (match == null) {
    return 0;
  }
  return int.tryParse(match.group(1) ?? '') ?? 0;
}

Future<int> _waitForPositiveProxyCount(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await _waitForLoadProxiesEnabled(tester);
    await tester.tap(find.byKey(kLoadProxiesButtonKey));
    await tester.pump(const Duration(seconds: 1));
    final proxyText = tester.widget<Text>(find.byKey(kProxyCountTextKey));
    final count = _extractProxyCount(proxyText.data ?? '');
    if (count > 0) {
      return count;
    }
  }
  return 0;
}
