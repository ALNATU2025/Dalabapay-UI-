// lib/presentation/screens/bills/pay_bills_screen.dart
// "Pay bills" hub from the redesign. UI only: it lists the services the
// dashboard already supports and hands the chosen route back via [onSelect].
import 'package:flutter/material.dart';

import '../../../ui/ui.dart';

class PayBillsScreen extends StatefulWidget {
  /// Each entry: {'icon': IconData, 'name': String, 'route': String}
  final List<Map<String, dynamic>> services;

  /// Recent transactions (same shape as the dashboard list) used for
  /// "Pay again" shortcuts.
  final List<dynamic> recentTransactions;
  final ValueChanged<String> onSelect;

  const PayBillsScreen({
    super.key,
    required this.services,
    required this.recentTransactions,
    required this.onSelect,
  });

  @override
  State<PayBillsScreen> createState() => _PayBillsScreenState();
}

class _PayBillsScreenState extends State<PayBillsScreen> {
  String _query = '';

  String? _routeForType(String text) {
    final t = text.toLowerCase();
    if (t.contains('international')) return '/international-airtime';
    if (t.contains('airtime')) return '/airtime';
    if (t.contains('data') || t.contains('internet')) return '/data';
    if (t.contains('electric')) return '/electricity';
    if (t.contains('cable') || t.contains('tv') || t.contains('dstv') ||
        t.contains('gotv') || t.contains('startimes')) {
      return '/cable';
    }
    if (t.contains('education') || t.contains('waec') || t.contains('jamb')) {
      return '/education';
    }
    if (t.contains('insurance')) return '/insurance';
    return null;
  }

  IconData _iconForRoute(String route) {
    for (final s in widget.services) {
      if (s['route'] == route) return s['icon'] as IconData;
    }
    return DPIcons.receipt;
  }

  /// Distinct recent bill payments (max 4) for "Pay again".
  List<Map<String, dynamic>> _payAgain() {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final raw in widget.recentTransactions) {
      if (raw is! Map) continue;
      final t = Map<String, dynamic>.from(raw);
      final type = t['type']?.toString() ?? '';
      final desc = t['description']?.toString() ?? '';
      final route = _routeForType('$type $desc');
      if (route == null) continue;
      final target = (t['phone'] ??
              t['phoneNumber'] ??
              t['meterNumber'] ??
              t['smartcardNumber'] ??
              t['billersCode'] ??
              t['metadata']?['phone'] ??
              t['metadata']?['meterNumber'] ??
              t['metadata']?['smartcardNumber'] ??
              '')
          .toString();
      final key = '$route|${target.isEmpty ? desc : target}';
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add({
        'route': route,
        'title': desc.isNotEmpty ? desc : type,
        'subtitle': target,
      });
      if (out.length == 4) break;
    }
    return out;
  }

  String _mask(String v) {
    if (v.length <= 6) return v;
    return '${v.substring(0, 4)}•••${v.substring(v.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final services = q.isEmpty
        ? widget.services
        : widget.services
            .where((s) => (s['name'] as String).toLowerCase().contains(q))
            .toList();
    final again = _payAgain();

    return Scaffold(
      backgroundColor: DP.bg,
      body: SafeArea(
        child: Column(
          children: [
            const DPTopBar(title: 'Pay bills'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                children: [
                  const DPHeadline(
                    'Life admin, sorted.',
                    subtitle: 'One place for your everyday payments.',
                    bottom: 20,
                  ),
                  const DPLabel('What would you like to pay?'),
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    decoration: DPField.decoration(
                      hint: 'Search bills and services',
                      suffix: const Icon(DPIcons.search),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const DPSectionHeader('Everyday payments'),
                  if (services.isEmpty)
                    const DPEmptyState(
                      icon: DPIcons.search,
                      title: 'No matching service',
                      message: 'Try another word, like "data" or "TV".',
                    )
                  else
                    DPServiceGrid(
                      tiles: [
                        for (final s in services)
                          DPServiceTile(
                            icon: s['icon'] as IconData,
                            label: s['name'] as String,
                            onTap: () => widget.onSelect(s['route'] as String),
                          ),
                      ],
                    ),
                  const SizedBox(height: 22),
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
                                'Your bills can give back.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'See the commission on eligible payments before you pay.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.78),
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          DPIcons.gift,
                          color: Colors.white.withValues(alpha: 0.9),
                          size: 30,
                        ),
                      ],
                    ),
                  ),
                  if (again.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const DPSectionHeader('Pay again'),
                    for (final a in again)
                      DPListRow(
                        onTap: () => widget.onSelect(a['route'] as String),
                        leading: DPIconBadge.blue(
                          _iconForRoute(a['route'] as String),
                          size: 40,
                          iconSize: 20,
                        ),
                        title: a['title'] as String,
                        subtitle: _mask(a['subtitle'] as String),
                        trailing: const Icon(
                          DPIcons.chevronRight,
                          color: DP.muted,
                        ),
                      ),
                  ],
                  const SizedBox(height: 24),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/help'),
                      child: const Text(
                        'Can\'t find a service? Let us know in Help.',
                        style: DP.caption,
                      ),
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
