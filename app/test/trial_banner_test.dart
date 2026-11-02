import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clique_pix/features/paywall/domain/trial_status.dart';
import 'package:clique_pix/features/paywall/presentation/trial_banner.dart';

Widget _host(TrialStatus status, VoidCallback onSubscribe) => MaterialApp(
      home: Scaffold(
        body: TrialBanner(status: status, onSubscribe: onSubscribe),
      ),
    );

void main() {
  testWidgets('shows the countdown and a Subscribe action', (tester) async {
    await tester.pumpWidget(
        _host(const TrialStatus(Duration(days: 5)), () {}));

    expect(find.text('5 days left in your free trial'), findsOneWidget);
    expect(find.text('Subscribe'), findsOneWidget);
  });

  testWidgets('tapping Subscribe opens the subscribe flow', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
        _host(const TrialStatus(Duration(days: 5)), () => taps++));

    await tester.tap(find.text('Subscribe'));
    expect(taps, 1);
  });

  testWidgets('the whole banner is a tap target', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
        _host(const TrialStatus(Duration(hours: 3)), () => taps++));

    await tester.tap(find.text('Your free trial ends in 3 hours'));
    expect(taps, 1);
  });

  testWidgets('meets the 48px minimum tap height', (tester) async {
    await tester.pumpWidget(
        _host(const TrialStatus(Duration(days: 2)), () {}));

    final size = tester.getSize(find.byType(InkWell).first);
    expect(size.height, greaterThanOrEqualTo(48));
  });
}
