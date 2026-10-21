import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cam_scanner/core/theme/motion_tokens.dart';

void main() {
  group('MotionTokens.sheetAnimationStyle Widget Tests', () {
    testWidgets(
      'Normal mode: sheet opens with animation, settles, and closes completing Future',
      (tester) async {
        String? sheetResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    sheetResult = await showModalBottomSheet<String>(
                      context: context,
                      sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
                      builder: (sheetCtx) => Container(
                        padding: const EdgeInsets.all(24),
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(sheetCtx).pop('normal_closed'),
                          child: const Text('Close Normal Sheet'),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Normal Sheet'),
                ),
              ),
            ),
          ),
        );

        // Tap to open sheet
        await tester.tap(find.text('Open Normal Sheet'));
        await tester.pump(); // Triggers bottom sheet route animation

        // Mid-way through enter duration (e.g., 100ms)
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Close Normal Sheet'), findsOneWidget);

        // Settle completely
        await tester.pumpAndSettle();
        expect(find.text('Close Normal Sheet'), findsOneWidget);
        expect(sheetResult, isNull);

        // Tap to close
        await tester.tap(find.text('Close Normal Sheet'));
        await tester.pump(); // Triggers exit animation

        // Mid-way exit
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Close Normal Sheet'), findsOneWidget);

        // Settle completely
        await tester.pumpAndSettle();
        expect(find.text('Close Normal Sheet'), findsNothing);
        expect(sheetResult, 'normal_closed');
      },
    );

    testWidgets(
      'disableAnimations: true: sheet appears immediately on first frame and Future completes immediately upon dismiss',
      (tester) async {
        String? instantResult;

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () async {
                      instantResult = await showModalBottomSheet<String>(
                        context: context,
                        sheetAnimationStyle: MotionTokens.sheetAnimationStyle(context),
                        builder: (sheetCtx) => Container(
                          padding: const EdgeInsets.all(24),
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(sheetCtx).pop('instant_closed'),
                            child: const Text('Close Instant Sheet'),
                          ),
                        ),
                      );
                    },
                    child: const Text('Open Instant Sheet'),
                  ),
                ),
              ),
            ),
          ),
        );

        // Verify token returns AnimationStyle.noAnimation when animations are disabled
        final contextFinder = find.text('Open Instant Sheet');
        final style = MotionTokens.sheetAnimationStyle(tester.element(contextFinder));
        expect(style.duration, Duration.zero);
        expect(style.reverseDuration, Duration.zero);

        // Tap to open sheet
        await tester.tap(contextFinder);
        // With duration: 0, a single pump immediately finishes the route transition
        await tester.pump();

        expect(find.text('Close Instant Sheet'), findsOneWidget);
        expect(instantResult, isNull);

        // Dismiss immediately
        await tester.tap(find.text('Close Instant Sheet'));
        await tester.pump(); // With reverseDuration: 0, immediately dismissed and future completed

        expect(find.text('Close Instant Sheet'), findsNothing);
        expect(instantResult, 'instant_closed');
      },
    );
  });
}
