import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cam_scanner/features/scanner/presentation/splash_screen.dart';
import 'package:cam_scanner/main.dart';

void main() {
  testWidgets('CamScannerApp launches LibraryScreen smoke test', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: CamScannerApp()));
    await tester.pump();
    expect(find.byType(CamScannerApp), findsOneWidget);
    expect(find.byType(SplashScreen), findsOneWidget);
  });
}
