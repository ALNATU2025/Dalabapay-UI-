// lib/ui/dp_logo.dart
import 'package:flutter/material.dart';

import 'dp_motion.dart';
import 'dp_tokens.dart';
import 'dp_widgets.dart';

/// Every image the app uses. All live in assets/images/ (one folder, so
/// pubspec never needs changing). Any file that is missing simply shows a
/// matching icon instead — drop the real file in and it appears.
class DPAssets {
  DPAssets._();
  static const String _d = 'assets/images/';

  // Brand
  static const String mark = '${_d}dabalogo.png';
  static const String wordmark = '${_d}dalabapay2.png';

  // Onboarding illustrations (portrait, transparent PNG)
  static const String onboarding1 = '${_d}onboarding_1.png';
  static const String onboarding2 = '${_d}onboarding_2.png';
  static const String onboarding3 = '${_d}onboarding_3.png';

  // Service icons (3D style, square, transparent PNG)
  static const String svcAirtime = '${_d}svc_airtime.png';
  static const String svcData = '${_d}svc_data.png';
  static const String svcTv = '${_d}svc_tv.png';
  static const String svcElectricity = '${_d}svc_electricity.png';
  static const String svcBills = '${_d}svc_bills.png';
  static const String svcInsurance = '${_d}svc_insurance.png';
  static const String svcEducation = '${_d}svc_education.png';
  static const String svcInternational = '${_d}svc_international.png';
  static const String svcSendMoney = '${_d}svc_send_money.png';
  static const String svcAddMoney = '${_d}svc_add_money.png';
  static const String svcEarnings = '${_d}svc_earnings.png';
  static const String svcMore = '${_d}svc_more.png';

  // Provider logos (square, transparent PNG)
  static const String mtn = '${_d}provider_mtn.png';
  static const String airtel = '${_d}provider_airtel.png';
  static const String glo = '${_d}provider_glo.png';
  static const String nineMobile = '${_d}provider_9mobile.png';
  static const String dstv = '${_d}provider_dstv.png';
  static const String gotv = '${_d}provider_gotv.png';
  static const String startimes = '${_d}provider_startimes.png';
  static const String showmax = '${_d}provider_showmax.png';
  static const String waec = '${_d}provider_waec.png';
  static const String jamb = '${_d}provider_jamb.png';

  // Promo banners (wide illustrations)
  static const String bannerRefer = '${_d}banner_refer.png';
  static const String bannerBills = '${_d}banner_bills.png';

  /// Logo for a network / provider name or VTpass service ID, if we have one.
  static String? providerFor(String nameOrId) {
    final n = nameOrId.toLowerCase();
    if (n.contains('mtn')) return mtn;
    if (n.contains('airtel')) return airtel;
    if (n.contains('glo')) return glo;
    if (n.contains('9mobile') || n.contains('etisalat')) return nineMobile;
    if (n.contains('dstv')) return dstv;
    if (n.contains('gotv')) return gotv;
    if (n.contains('startimes')) return startimes;
    if (n.contains('showmax')) return showmax;
    if (n.contains('waec')) return waec;
    if (n.contains('jamb')) return jamb;
    return null;
  }
}

/// Asset image that quietly falls back to [fallback] (or nothing) when the
/// file hasn't been added yet.
class DPImage extends StatelessWidget {
  final String asset;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? fallback;

  const DPImage(
    this.asset, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) =>
          fallback ?? SizedBox(width: width, height: height),
    );
  }
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
