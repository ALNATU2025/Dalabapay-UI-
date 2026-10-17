// lib/presentation/screens/help/help_screen.dart
// "Help & support" from the redesign. Uses features the app already has:
// disputes (/user-disputes), payment validation (/transaction-validation),
// activity (/transactions) and the support WhatsApp line / email.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../ui/ui.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _Faq {
  final IconData icon;
  final String title;
  final String subtitle;
  final String answer;
  final String? actionLabel;
  final String? route;
  const _Faq(
    this.icon,
    this.title,
    this.subtitle,
    this.answer, {
    this.actionLabel,
    this.route,
  });
}

class _HelpScreenState extends State<HelpScreen> {
  static const _supportWhatsApp = '2349163207050';
  static const _supportEmail = 'support@dalabapay.com';

  String _query = '';

  static const List<_Faq> _faqs = [
    _Faq(
      DPIcons.downLeft,
      'My transfer hasn\'t arrived',
      'Track a wallet top-up',
      'Bank transfers to your funding account usually arrive within minutes. If it\'s been longer, check the payment with your bank reference and we\'ll match it to your wallet.',
      actionLabel: 'Check a payment',
      route: '/transaction-validation',
    ),
    _Faq(
      DPIcons.phone,
      'Airtime or data not received',
      'Check a payment\'s delivery status',
      'Most top-ups arrive instantly. If your activity shows "Pending", give it a few minutes. If it shows "Successful" but nothing arrived, report it and we\'ll investigate with the network.',
      actionLabel: 'Report a problem',
      route: '/user-disputes',
    ),
    _Faq(
      DPIcons.bolt,
      'Where is my electricity token?',
      'Find it in your receipt',
      'Your token is on the payment receipt and is also sent by SMS to the phone number you entered. Open the payment in Activity to see it again.',
      actionLabel: 'Open activity',
      route: '/transactions',
    ),
    _Faq(
      DPIcons.shield,
      'Keep my account safe',
      'PIN, password and fraud guidance',
      'Never share your password, OTP or payment PIN — not even with Dalabapay staff. Turn on biometric login in Profile, and change your PIN if you think someone has seen it.',
      actionLabel: 'Go to profile',
      route: '/settings',
    ),
    _Faq(
      DPIcons.sparkle,
      'How do I use my commission?',
      'Earnings and moving them to your wallet',
      'You earn commission on eligible payments. Open Earnings and tap "Move to wallet" once you have at least ₦500.',
      actionLabel: 'Open earnings',
      route: '/commission',
    ),
  ];

  Future<void> _openWhatsApp() async {
    final uri = Uri.parse(
      'https://wa.me/$_supportWhatsApp?text=${Uri.encodeComponent('Hello Dalabapay support, I need help with: ')}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _emailSupport();
  }

  Future<void> _emailSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {'subject': 'Dalabapay support'},
    );
    final ok = await launchUrl(uri);
    if (!ok && mounted) {
      dpSnack(context, 'Email us at $_supportEmail');
    }
  }

  void _openFaq(_Faq f) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DPSheetHandle(),
              const SizedBox(height: 8),
              DPIconBadge.blue(f.icon, size: 48),
              const SizedBox(height: 14),
              Text(f.title, style: DP.title),
              const SizedBox(height: 10),
              Text(f.answer, style: DP.body.copyWith(color: DP.inkSoft)),
              const SizedBox(height: 22),
              if (f.route != null)
                DPButton(
                  label: f.actionLabel ?? 'Continue',
                  icon: DPIcons.forward,
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushNamed(context, f.route!);
                  },
                ),
              const SizedBox(height: 8),
              Center(
                child: DPTextLink(
                  label: 'Still stuck? Talk to us',
                  onTap: () {
                    Navigator.pop(ctx);
                    _openWhatsApp();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final faqs = q.isEmpty
        ? _faqs
        : _faqs
            .where(
              (f) =>
                  f.title.toLowerCase().contains(q) ||
                  f.subtitle.toLowerCase().contains(q) ||
                  f.answer.toLowerCase().contains(q),
            )
            .toList();

    return Scaffold(
      backgroundColor: DP.bg,
      body: SafeArea(
        child: Column(
          children: [
            DPTopBar(
              title: 'Help & support',
              actionLabel: 'My tickets',
              onAction: () => Navigator.pushNamed(context, '/user-disputes'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                children: [
                  const DPHeadline(
                    'A little help,\nright here.',
                    subtitle: 'Let\'s get your day back on track.',
                    bottom: 20,
                  ),
                  const DPLabel('Search the help centre'),
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    decoration: DPField.decoration(
                      hint: 'Try "missing transfer"',
                      suffix: const Icon(DPIcons.search),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
                    decoration: BoxDecoration(
                      color: DP.navy,
                      borderRadius: BorderRadius.circular(DP.rXl),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Talk to a real person.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Chat with us on WhatsApp or email $_supportEmail. Leave a message anytime.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.78),
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          DPIcons.messageCircle,
                          color: Colors.white.withValues(alpha: 0.9),
                          size: 30,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  DPButton(
                    label: 'Start a conversation',
                    icon: DPIcons.messageCircle,
                    onPressed: _openWhatsApp,
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: DPTextLink(
                      label: 'Email support instead',
                      onTap: _emailSupport,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const DPSectionHeader('Popular questions'),
                  if (faqs.isEmpty)
                    const DPEmptyState(
                      icon: DPIcons.search,
                      title: 'No matching questions',
                      message: 'Start a conversation and we\'ll help directly.',
                    )
                  else
                    for (final f in faqs)
                      DPListRow(
                        onTap: () => _openFaq(f),
                        leading: DPIconBadge.blue(f.icon, size: 40, iconSize: 20),
                        title: f.title,
                        subtitle: f.subtitle,
                        trailing: const Icon(
                          DPIcons.chevronRight,
                          color: DP.muted,
                        ),
                      ),
                  const SizedBox(height: 16),
                  const DPBanner(
                    'Our team will never ask for your password, OTP or payment PIN. Report any suspicious request.',
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: DPTextLink(
                      label: 'Report a payment problem',
                      onTap: () => Navigator.pushNamed(context, '/user-disputes'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
