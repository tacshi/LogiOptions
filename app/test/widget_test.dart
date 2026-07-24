import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logi_options/app.dart';

void main() {
  testWidgets('Home shell shows LogiOptions branding', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const LogiOptionsApp());
    await tester.pumpAndSettle();

    // App title is MaterialApp title (not always on screen); device header
    // shows connection prompt when offline.
    expect(find.textContaining('Connect a supported Logitech'), findsOneWidget);
    expect(find.text('Buttons'), findsWidgets);
  });
}
