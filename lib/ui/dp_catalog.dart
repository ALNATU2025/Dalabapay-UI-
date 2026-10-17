// lib/ui/dp_catalog.dart
// Services catalogue and promo banner shared by Home, All Services and
// Pay Bills.
import 'package:flutter/material.dart';

import 'dp_logo.dart';
import 'dp_motion.dart';
import 'dp_tokens.dart';

/// One entry in the services catalogue.
class DPService {
  final String name;
  final IconData icon;
  final String route;
  final String? image;
  final Color color;
  const DPService(this.name, this.icon, this.route, this.image, this.color);
}

/// Services the app really offers. Special routes the dashboard handles:
/// '/bills' (Pay Bills screen), '/wallet:add', '/wallet:send', '/commission'.
const List<DPService> kDalabapayServices = [
  DPService('Airtime', DPIcons.smartphone, '/airtime', DPAssets.svcAirtime, DP.navyIcon),
  DPService('Data', DPIcons.wifi, '/data', DPAssets.svcData, DP.navyIcon),
  DPService('TV Packages', DPIcons.tv, '/cable', DPAssets.svcTv, DP.navyIcon),
  DPService('Electricity', DPIcons.bolt, '/electricity', DPAssets.svcElectricity, DP.green),
  DPService('WAEC PIN', DPIcons.badge, '/education', DPAssets.waec, DP.amber),
  DPService('Insurance', DPIcons.shield, '/insurance', DPAssets.svcInsurance, DP.green),
  DPService('Education', DPIcons.school, '/education', DPAssets.svcEducation, DP.navyIcon),
  DPService('International Airtime', DPIcons.globe, '/international-airtime', DPAssets.svcInternational, DP.navyIcon),
  DPService('Pay Bills', DPIcons.receipt, '/bills', DPAssets.svcBills, DP.navyIcon),
  DPService('Add Money', DPIcons.plus, '/wallet:add', DPAssets.svcAddMoney, DP.green),
  DPService('Send Money', DPIcons.upRight, '/wallet:send', DPAssets.svcSendMoney, DP.navyIcon),
  DPService('Earnings', DPIcons.sparkle, '/commission', DPAssets.svcEarnings, DP.green),
];

/// Navy promo banner with an illustration on the right (Refer a Friend,
/// Quick & Easy Bill Payments).
class DPPromoBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final String image;
  final IconData icon;
  final VoidCallback? onTap;

  const DPPromoBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.image,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DPPressable(
      enabled: onTap != null,
      pressedScale: 0.98,
      child: Material(
        borderRadius: BorderRadius.circular(DP.rLg),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(gradient: DP.navyGradient),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  DPImage(
                    image,
                    width: 84,
                    height: 72,
                    fallback: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: const Color(0xFFFFC542), size: 34),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
