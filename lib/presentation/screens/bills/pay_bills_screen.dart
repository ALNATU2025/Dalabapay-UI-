// lib/presentation/screens/bills/pay_bills_screen.dart
// "All Services" (design screen 8) and "Pay Bills" (design screen 11).
// UI only: the chosen route is handed back via [onSelect]; the dashboard
// opens it with the same logic as before.
import 'package:flutter/material.dart';

import '../../../ui/ui.dart';

/// Pushed "All Services" screen (keeps the old PayBillsScreen API).
class PayBillsScreen extends StatelessWidget {
  /// Kept for compatibility; the catalogue above is used for the grid.
  final List<Map<String, dynamic>> services;
  final List<dynamic> recentTransactions;
  final ValueChanged<String> onSelect;

  const PayBillsScreen({
    super.key,
    required this.services,
    required this.recentTransactions,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DP.bg,
      body: SafeArea(
        child: ServicesView(
          recentTransactions: recentTransactions,
          onSelect: onSelect,
          showBack: true,
        ),
      ),
    );
  }
}

/// "All Services" content — used as the Services tab and as a pushed page.
class ServicesView extends StatefulWidget {
  final List<dynamic> recentTransactions;
  final ValueChanged<String> onSelect;
  final bool showBack;

  const ServicesView({
    super.key,
    required this.recentTransactions,
    required this.onSelect,
    this.showBack = false,
  });

  @override
  State<ServicesView> createState() => _ServicesViewState();
}

class _ServicesViewState extends State<ServicesView> {
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
    for (final s in kDalabapayServices) {
      if (s.route == route) return s.icon;
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
        ? kDalabapayServices
        : kDalabapayServices
            .where((s) => s.name.toLowerCase().contains(q))
            .toList();
    final again = _payAgain();

    return Column(
      children: [
        DPTopBar(title: 'All Services', showBack: widget.showBack),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
            children: [
              TextField(
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 15, color: DP.ink),
                decoration: DPField.decoration(
                  hint: 'Search for a service...',
                  prefix: const Icon(DPIcons.search, size: 20),
                ),
              ),
              const SizedBox(height: 18),
              if (services.isEmpty)
                const DPEmptyState(
                  icon: DPIcons.search,
                  title: 'No matching service',
                  message: 'Try another word, like "data" or "TV".',
                )
              else
                DPServiceGrid(
                  columns: 3,
                  tiles: [
                    for (final s in services)
                      DPServiceTile(
                        icon: s.icon,
                        label: s.name,
                        image: s.image,
                        color: s.color,
                        onTap: () => widget.onSelect(s.route),
                      ),
                  ],
                ),
              if (again.isNotEmpty && q.isEmpty) ...[
                const SizedBox(height: 24),
                const DPSectionHeader('Pay again'),
                DPCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    children: [
                      for (var i = 0; i < again.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, color: DP.borderSoft),
                        DPListRow(
                          onTap: () =>
                              widget.onSelect(again[i]['route'] as String),
                          leading: DPIconBadge.blue(
                            _iconForRoute(again[i]['route'] as String),
                            size: 40,
                            iconSize: 20,
                          ),
                          title: again[i]['title'] as String,
                          subtitle: _mask(again[i]['subtitle'] as String),
                          trailing: const Icon(
                            DPIcons.chevronRight,
                            color: DP.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// "Pay Bills" (design screen 11): provider tiles + promo banner.
class BillsScreen extends StatelessWidget {
  final ValueChanged<String> onSelect;
  const BillsScreen({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    const tiles = <DPService>[
      DPService('Electricity', DPIcons.bolt, '/electricity', DPAssets.svcElectricity, DP.green),
      DPService('DSTV', DPIcons.tv, '/cable', DPAssets.dstv, DP.navyIcon),
      DPService('GOtv', DPIcons.tv, '/cable', DPAssets.gotv, DP.green),
      DPService('StarTimes', DPIcons.tv, '/cable', DPAssets.startimes, DP.amber),
      DPService('WAEC PIN', DPIcons.badge, '/education', DPAssets.waec, DP.amber),
      DPService('Education', DPIcons.school, '/education', DPAssets.svcEducation, DP.navyIcon),
      DPService('Insurance', DPIcons.shield, '/insurance', DPAssets.svcInsurance, DP.green),
      DPService('Data', DPIcons.wifi, '/data', DPAssets.svcData, DP.navyIcon),
      DPService('More', DPIcons.grid, '/services', DPAssets.svcMore, DP.navyIcon),
    ];
    return Scaffold(
      backgroundColor: DP.bg,
      body: SafeArea(
        child: Column(
          children: [
            const DPTopBar(title: 'Pay Bills'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                children: [
                  DPServiceGrid(
                    columns: 3,
                    tiles: [
                      for (final s in tiles)
                        DPServiceTile(
                          icon: s.icon,
                          label: s.name,
                          image: s.image,
                          color: s.color,
                          onTap: () => onSelect(s.route),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const DPAppear(
                    delay: Duration(milliseconds: 250),
                    child: DPPromoBanner(
                      title: 'Quick & Easy\nBill Payments',
                      subtitle:
                          'Keep your services active and never miss a payment.',
                      image: DPAssets.bannerBills,
                      icon: DPIcons.bolt,
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
