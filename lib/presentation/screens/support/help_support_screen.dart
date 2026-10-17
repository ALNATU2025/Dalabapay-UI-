// lib/presentation/screens/support/help_support_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../ui/ui.dart';

/// Help & support: answers to common questions plus ways to reach the team.
/// Contacts are the same ones already used elsewhere in the app.
class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key});

  static const supportEmail = 'support@dalabapay.com';
  static const supportWhatsApp = '2349163207050';

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _Faq {
  final DPIconData icon;
  final String question;
  final String hint;
  final String answer;
  const _Faq(this.icon, this.question, this.hint, this.answer);
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final _search = TextEditingController();
  int? _expanded;

  static const _faqs = [
    _Faq(
      DPIcons.arrowDownLeft,
      'My transfer hasn’t arrived',
      'Track a wallet top-up',
      'Bank transfers to your funding account usually arrive within minutes. If it has been more than 30 minutes, open Activity to check for the top-up, then report it from “Report a payment problem” with your bank’s transfer reference.',
    ),
    _Faq(
      DPIcons.phone,
      'Airtime or data not received',
      'Check a payment’s delivery status',
      'Open Activity and tap the payment to see its status. If it shows Successful but nothing arrived after 15 minutes, report it with the payment reference and we’ll check with the network.',
    ),
    _Faq(
      DPIcons.zap,
      'Where is my electricity token?',
      'Find it in your receipt',
      'Your token is on the payment receipt (tap the payment in Activity) and is also sent by SMS to the phone number you entered.',
    ),
    _Faq(
      DPIcons.shield,
      'Keep my account safe',
      'PIN, password and fraud guidance',
      'Never share your password, OTP or payment PIN — not even with Dalabapay staff. Turn on biometric login in Profile, and change your PIN immediately if you think someone else knows it.',
    ),
    _Faq(
      DPIcons.sparkles,
      'How does commission work?',
      'Earnings from eligible payments',
      'Eligible payments earn a small commission that goes to your separate earnings balance. You can move earnings to your wallet from Commission & earnings.',
    ),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _launch(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) dpSnack(context, 'Couldn’t open that app on this device.', error: true);
    } catch (_) {
      if (mounted) dpSnack(context, 'Couldn’t open that app on this device.', error: true);
    }
  }

  void _contactSheet() {
    showDPSheet(
      context,
      title: 'Start a conversation',
      builder: (ctx) => Column(
        children: [
          DPOptionRow(
            leading: const DPIcon(DPIcons.messageCircle, size: 22, color: DP.green),
            title: 'Chat on WhatsApp',
            subtitle: '+234 916 320 7050',
            onTap: () {
              Navigator.pop(ctx);
              _launch(Uri.parse(
                  'https://wa.me/${HelpSupportScreen.supportWhatsApp}?text=${Uri.encodeComponent('Hello Dalabapay, I need help with ')}'));
            },
          ),
          DPOptionRow(
            leading: const DPIcon(DPIcons.mail, size: 22, color: DP.green),
            title: 'Send an email',
            subtitle: HelpSupportScreen.supportEmail,
            onTap: () {
              Navigator.pop(ctx);
              _launch(Uri(
                scheme: 'mailto',
                path: HelpSupportScreen.supportEmail,
                query: 'subject=${Uri.encodeComponent('Dalabapay support')}',
              ));
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final faqs = q.isEmpty
        ? _faqs
        : _faqs
            .where((f) => '${f.question} ${f.hint} ${f.answer}'.toLowerCase().contains(q))
            .toList();
    return DPPage(
      title: 'Help & support',
      actionLabel: 'My tickets',
      onAction: () => Navigator.pushNamed(context, '/user-disputes'),
      children: [
        const DPHeadline('A little help,\nright here.', subtitle: 'Let’s get your day back on track.'),
        DPField(
          label: 'Search the help centre',
          controller: _search,
          hint: 'Try “missing transfer”',
          suffixIcon: DPIcons.search,
          onChanged: (_) => setState(() => _expanded = null),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 18, 20),
          decoration: BoxDecoration(
            color: DP.navy,
            borderRadius: BorderRadius.circular(DP.rLg + 2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Talk to a real person.',
                        style: DPText.title.copyWith(color: Colors.white, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    Text('Chat with us on WhatsApp or send an email. Leave a message anytime.',
                        style: DPText.small.copyWith(color: const Color(0xFFC4CFE6), fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const DPIcon(DPIcons.messagesSquare, size: 32, color: Colors.white, strokeWidth: 1.5),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DPButton(
          label: 'Start a conversation',
          icon: DPIcons.messageCircle,
          onPressed: _contactSheet,
        ),
        const DPSectionHeader('Popular questions'),
        if (faqs.isEmpty)
          const DPEmptyState(icon: DPIcons.search, title: 'No answers found', message: 'Try different words, or start a conversation with us.'),
        for (var i = 0; i < faqs.length; i++) ...[
          DPMenuRow(
            icon: faqs[i].icon,
            title: faqs[i].question,
            subtitle: faqs[i].hint,
            trailing: DPIcon(_expanded == i ? DPIcons.chevronDown : DPIcons.chevronRight,
                size: 18, color: DP.muted),
            onTap: () => setState(() => _expanded = _expanded == i ? null : i),
          ),
          if (_expanded == i)
            Padding(
              padding: const EdgeInsets.fromLTRB(54, 0, 4, 10),
              child: Text(faqs[i].answer, style: DPText.bodyMuted),
            ),
        ],
        const SizedBox(height: 10),
        const DPNotice(
          'Our team will never ask for your password, OTP or payment PIN. Report any suspicious request.',
        ),
        Center(
          child: DPLinkButton(
            label: 'Report a payment problem',
            onPressed: () => Navigator.pushNamed(context, '/transaction-validation'),
          ),
        ),
      ],
    );
  }
}
