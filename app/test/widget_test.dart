import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logi_options/app.dart';

void main() {
  testWidgets('Home shell shows LogiOptions branding', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const LogiOptionsApp());
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'LogiOptions',
    );
    expect(find.text('Buttons'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('opening a window only checks existing permissions', (
    tester,
  ) async {
    const channel = MethodChannel('com.logioptions/permissions');
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return <String, dynamic>{'accessibility': true, 'inputMonitoring': false};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const LogiOptionsApp());
    await tester.pump();

    expect(calls, contains('getStatus'));
    expect(calls, isNot(contains('request')));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
