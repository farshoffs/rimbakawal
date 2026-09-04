import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rimbakawal/core/ui/rimba_dialog_actions.dart';

Widget _host({required double width, bool forceStacked = false}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: RimbaDialogActions(
            primaryLabel: 'LIHAT',
            primaryIcon: Icons.visibility_rounded,
            onPrimary: () {},
            secondaryLabel: 'TUTUP',
            secondaryIcon: Icons.close_rounded,
            onSecondary: () {},
            forceStacked: forceStacked,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('wide peer actions have exactly equal width and height', (
    tester,
  ) async {
    await tester.pumpWidget(_host(width: 420));

    final primary = tester.getSize(find.byType(FilledButton));
    final secondary = tester.getSize(find.byType(OutlinedButton));

    expect(primary.height, RimbaDialogActions.buttonHeight);
    expect(secondary.height, RimbaDialogActions.buttonHeight);
    expect(primary.width, secondary.width);
  });

  testWidgets('narrow peer actions stack full width with equal dimensions', (
    tester,
  ) async {
    await tester.pumpWidget(_host(width: 300));

    final primary = tester.getSize(find.byType(FilledButton));
    final secondary = tester.getSize(find.byType(OutlinedButton));

    expect(primary.height, RimbaDialogActions.buttonHeight);
    expect(secondary.height, RimbaDialogActions.buttonHeight);
    expect(primary.width, secondary.width);
    expect(primary.width, 300);
  });

  testWidgets('long action can be forced to stack without changing size', (
    tester,
  ) async {
    await tester.pumpWidget(_host(width: 500, forceStacked: true));

    final primary = tester.getSize(find.byType(FilledButton));
    final secondary = tester.getSize(find.byType(OutlinedButton));

    expect(primary.height, RimbaDialogActions.buttonHeight);
    expect(secondary.height, RimbaDialogActions.buttonHeight);
    expect(primary.width, secondary.width);
    expect(primary.width, 500);
  });
}
