import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cam_scanner/core/theme/motion_tokens.dart';

void main() {
  group('RawPressFeedback Widget Tests', () {
    Widget buildTestHarness({
      Key? key,
      double targetScale = 0.97,
      Duration duration = const Duration(milliseconds: 120),
      Duration pressDelay = const Duration(milliseconds: 50),
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: RawPressFeedback(
              key: key,
              targetScale: targetScale,
              duration: duration,
              pressDelay: pressDelay,
              child: Container(
                width: 100,
                height: 100,
                color: Colors.blue,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('(أ) لمسة ثم pump 30ms: لا يحدث scale (scale = 1.0)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestHarness());

      final targetFinder = find.byType(Container).first;
      final gesture = await tester.startGesture(tester.getCenter(targetFinder));

      // Pump 30ms (أقل من pressFeedbackDelay البالغ 50ms)
      await tester.pump(const Duration(milliseconds: 30));

      final animatedScale = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale),
      );
      expect(animatedScale.scale, 1.0, reason: 'Target scale must remain 1.0 before 50ms delay');

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('(ب) pump 60ms: بعد انقضاء الـ 50ms يصبح scale = 0.97', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestHarness(targetScale: 0.97));

      final targetFinder = find.byType(Container).first;
      final gesture = await tester.startGesture(tester.getCenter(targetFinder));

      // Pump 60ms (تجاوز الـ 50ms)
      await tester.pump(const Duration(milliseconds: 60));

      final animatedScale = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale),
      );
      expect(animatedScale.scale, 0.97, reason: 'Target scale must become 0.97 once pressDelay elapses');

      // اكتمال حركة التصغير (120ms)
      await tester.pump(const Duration(milliseconds: 120));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('(ج) تحريك أكبر من kTouchSlop (18dp): scale يعود إلى 1.0 فوراً', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestHarness(targetScale: 0.97));

      final targetFinder = find.byType(Container).first;
      final center = tester.getCenter(targetFinder);
      final gesture = await tester.startGesture(center);

      // الانتظار حتى تنكمش البطاقة (60ms)
      await tester.pump(const Duration(milliseconds: 60));
      var animatedScale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(animatedScale.scale, 0.97);

      // تحريك المؤشر بمقدار 25dp (أكبر من kTouchSlop = 18dp)
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump();

      animatedScale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(animatedScale.scale, 1.0, reason: 'Moving beyond kTouchSlop must immediately reset target scale to 1.0');

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('(د) رفع الإصبع (PointerUpEvent): scale يعود إلى 1.0', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestHarness(targetScale: 0.97));

      final targetFinder = find.byType(Container).first;
      final gesture = await tester.startGesture(tester.getCenter(targetFinder));

      // وصول الانكماش
      await tester.pump(const Duration(milliseconds: 60));
      var animatedScale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(animatedScale.scale, 0.97);

      // رفع الإصبع
      await gesture.up();
      await tester.pump();

      animatedScale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(animatedScale.scale, 1.0, reason: 'Pointer up must reset scale to 1.0');

      await tester.pumpAndSettle();
    });

    testWidgets('(هـ) لمسة أقصر من 50ms (لمس 30ms ثم رفع مباشر): لا ينكمش إطلاقاً', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildTestHarness(targetScale: 0.97));

      final targetFinder = find.byType(Container).first;
      final gesture = await tester.startGesture(tester.getCenter(targetFinder));

      // لمس لمدة 30ms فقط
      await tester.pump(const Duration(milliseconds: 30));
      var animatedScale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(animatedScale.scale, 1.0);

      // رفع مباشر قبل اكتمال الـ 50ms
      await gesture.up();
      await tester.pump();

      animatedScale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(animatedScale.scale, 1.0);

      // الانتظار للتأكد أن التايمر الملغي لا يطلق setState بعد انقضاء وقته
      await tester.pump(const Duration(milliseconds: 100));
      animatedScale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(animatedScale.scale, 1.0, reason: 'Cancelled timer must not trigger scale down after release');

      await tester.pumpAndSettle();
    });

    testWidgets('(و) تكامل مع LongPressDraggable: onDragStarted يعيد الـ scale إلى 1.0 صراحةً', (
      WidgetTester tester,
    ) async {
      final pressKey = GlobalKey<RawPressFeedbackState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: LongPressDraggable<String>(
                data: 'item_1',
                delay: const Duration(milliseconds: 450),
                onDragStarted: () => pressKey.currentState?.reset(),
                feedback: const Material(
                  child: Text('Dragging...'),
                ),
                child: RawPressFeedback(
                  key: pressKey,
                  targetScale: 0.97,
                  child: Container(
                    width: 120,
                    height: 120,
                    color: Colors.amber,
                    child: const Text('Target Card'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final targetFinder = find.text('Target Card');
      final gesture = await tester.startGesture(tester.getCenter(targetFinder));

      // بعد 60ms: انكماش اللمس يبدأ
      await tester.pump(const Duration(milliseconds: 60));
      var animatedScale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(animatedScale.scale, 0.97, reason: 'Card must shrink while held before drag triggers');

      // عند الوصول إلى 450ms (عتبة LongPressDraggable):
      // تنطلق onDragStarted ويتم استدعاء pressKey.currentState?.reset()
      await tester.pump(const Duration(milliseconds: 400)); // مجموع الوقت الآن 460ms > 450ms

      animatedScale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(
        animatedScale.scale,
        1.0,
        reason: 'LongPressDraggable.onDragStarted must reset card scale back to 1.0 immediately',
      );

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
