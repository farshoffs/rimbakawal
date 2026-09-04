import 'package:flutter/material.dart';

/// Standard paired actions for RimbaKawal dialogs.
///
/// Peer actions always have the same height. On wide layouts they share the
/// available width equally; on narrow layouts they stack at full width.
class RimbaDialogActions extends StatelessWidget {
  const RimbaDialogActions({
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    this.primaryIcon,
    this.secondaryIcon,
    this.primaryStyle,
    this.secondaryStyle,
    this.stackBelow = 340,
    this.forceStacked = false,
    super.key,
  });

  static const double buttonHeight = 56;
  static const double gap = 8;

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String secondaryLabel;
  final VoidCallback? onSecondary;
  final IconData? primaryIcon;
  final IconData? secondaryIcon;
  final ButtonStyle? primaryStyle;
  final ButtonStyle? secondaryStyle;
  final double stackBelow;
  final bool forceStacked;

  Widget _primary() => SizedBox(
    height: buttonHeight,
    child: primaryIcon == null
        ? FilledButton(
            onPressed: onPrimary,
            style: primaryStyle,
            child: Text(primaryLabel, textAlign: TextAlign.center),
          )
        : FilledButton.icon(
            onPressed: onPrimary,
            style: primaryStyle,
            icon: Icon(primaryIcon),
            label: Text(primaryLabel, textAlign: TextAlign.center),
          ),
  );

  Widget _secondary() => SizedBox(
    height: buttonHeight,
    child: secondaryIcon == null
        ? OutlinedButton(
            onPressed: onSecondary,
            style: secondaryStyle,
            child: Text(secondaryLabel, textAlign: TextAlign.center),
          )
        : OutlinedButton.icon(
            onPressed: onSecondary,
            style: secondaryStyle,
            icon: Icon(secondaryIcon),
            label: Text(secondaryLabel, textAlign: TextAlign.center),
          ),
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked = forceStacked || constraints.maxWidth < stackBelow;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _primary(),
              const SizedBox(height: gap),
              _secondary(),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: _secondary()),
            const SizedBox(width: gap),
            Expanded(child: _primary()),
          ],
        );
      },
    ),
  );
}
