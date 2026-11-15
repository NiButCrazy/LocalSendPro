import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/widget/rotating_widget.dart';

void main() {
  group('RotatingWidget', () {
    testWidgets('does not rotate while TickerMode is disabled', (tester) async {
      final tickerEnabled = ValueNotifier<bool>(false);

      await tester.pumpWidget(
        ValueListenableBuilder<bool>(
          valueListenable: tickerEnabled,
          builder: (context, enabled, child) => TickerMode(enabled: enabled, child: child!),
          child: const MaterialApp(
            home: Center(
              child: RotatingWidget(
                duration: Duration(seconds: 2),
                child: SizedBox.square(dimension: 10),
              ),
            ),
          ),
        ),
      );

      final initial = _rotation(tester);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_rotation(tester), orderedEquals(initial));

      tickerEnabled.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_rotation(tester), isNot(orderedEquals(initial)));

      await tester.pumpWidget(const SizedBox());
      tickerEnabled.dispose();
    });

    testWidgets('does not rotate while spinning is false', (tester) async {
      final spinning = ValueNotifier<bool>(false);

      await tester.pumpWidget(
        ValueListenableBuilder<bool>(
          valueListenable: spinning,
          builder: (context, value, child) => RotatingWidget(
            duration: const Duration(seconds: 2),
            spinning: value,
            child: const SizedBox.square(dimension: 10),
          ),
        ),
      );

      final initial = _rotation(tester);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_rotation(tester), orderedEquals(initial));

      spinning.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_rotation(tester), isNot(orderedEquals(initial)));

      await tester.pumpWidget(const SizedBox());
      spinning.dispose();
    });

    testWidgets('stops while the app lifecycle is hidden and resumes afterwards', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: RotatingWidget(
              duration: Duration(seconds: 2),
              child: SizedBox.square(dimension: 10),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      final beforeHidden = _rotation(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_rotation(tester), orderedEquals(beforeHidden));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_rotation(tester), isNot(orderedEquals(beforeHidden)));

      await tester.pumpWidget(const SizedBox());
    });
  });
}

List<double> _rotation(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(of: find.byType(RotatingWidget), matching: find.byType(Transform)).first,
  );
  return List<double>.of(transform.transform.storage);
}
