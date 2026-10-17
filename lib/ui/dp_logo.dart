// lib/ui/dp_logo.dart
import 'package:flutter/material.dart';

import 'dp_motion.dart';
import 'dp_tokens.dart';
import 'dp_widgets.dart';

/// Brand assets supplied with the app:
///   assets/images/dabalogo.png    – the chevron mark
///   assets/images/dalabapay2.png  – the mark with the "Dalabapay" wordmark
class DPAssets {
  DPAssets._();
  static const String mark = 'assets/images/dabalogo.png';
  static const String wordmark = 'assets/images/dalabapay2.png';
}

/// The square chevron mark. Falls back to a drawn version of the same mark
/// if the image is missing so a screen never shows a broken image.
class DPLogoMark extends StatelessWidget {
  final double size;
  final bool tile;
  const DPLogoMark({super.key, this.size = 40, this.tile = false});

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(
      DPAssets.mark,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _MarkPainter()),
      ),
    );
    if (!tile) return img;
    return Container(
      width: size + 16,
      height: size + 16,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: DP.surface,
        borderRadius: BorderRadius.circular(DP.rMd),
      ),
      child: img,
    );
  }
}

/// Mark + "Dalabapay" wordmark.
class DPWordmark extends StatelessWidget {
  final double height;
  const DPWordmark({super.key, this.height = 34});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      DPAssets.wordmark,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DPLogoMark(size: height),
          SizedBox(width: height * 0.12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Dalaba',
                  style: TextStyle(color: DP.navy, fontSize: height * 0.82),
                ),
                TextSpan(
                  text: 'pay',
                  style: TextStyle(color: DP.green, fontSize: height * 0.82),
                ),
              ],
            ),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Top bar with the Dalabapay logo in the centre — used on receipts.
/// [leadingIcon] defaults to back; pass [DPIcons.close] for dialogs.
class DPLogoBar extends StatelessWidget {
  final VoidCallback? onLeading;
  final IconData leadingIcon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  const DPLogoBar({
    super.key,
    this.onLeading,
    this.leadingIcon = DPIcons.back,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 8),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: SizedBox(
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: DPIconSquare(
                icon: leadingIcon,
                semanticLabel:
                    leadingIcon == DPIcons.close ? 'Close' : 'Back',
                onTap: onLeading ?? () => Navigator.of(context).maybePop(),
              ),
            ),
            const DPAppear(
              scaleFrom: 0.85,
              offsetY: 0,
              child: DPWordmark(height: 28),
            ),
            if (actionLabel != null)
              Align(
                alignment: Alignment.centerRight,
                child: DPTextLink(label: actionLabel!, onTap: onAction),
              ),
          ],
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    Path chevron(double top, double depth, double thick) => Path()
      ..moveTo(w * 0.10, h * top)
      ..lineTo(w * 0.50, h * (top + depth))
      ..lineTo(w * 0.90, h * top)
      ..lineTo(w * 0.90, h * (top + thick))
      ..lineTo(w * 0.50, h * (top + depth + thick))
      ..lineTo(w * 0.10, h * (top + thick))
      ..close();
    final caret = Path()
      ..moveTo(w * 0.30, h * 0.22)
      ..lineTo(w * 0.50, h * 0.04)
      ..lineTo(w * 0.70, h * 0.22)
      ..lineTo(w * 0.62, h * 0.29)
      ..lineTo(w * 0.50, h * 0.18)
      ..lineTo(w * 0.38, h * 0.29)
      ..close();
    canvas.drawPath(caret, Paint()..color = const Color(0xFF9CE2A3));
    canvas.drawPath(
      chevron(0.30, 0.24, 0.17),
      Paint()..color = const Color(0xFF219C7E),
    );
    canvas.drawPath(
      chevron(0.56, 0.24, 0.20),
      Paint()..color = const Color(0xFF243889),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
