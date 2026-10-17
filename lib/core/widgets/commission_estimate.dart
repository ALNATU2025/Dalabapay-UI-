// lib/core/widgets/commission_estimate.dart
import 'package:flutter/material.dart';

import '../../ui/ui.dart';
import '../services/commission_rates_service.dart';

/// Summary card with wallet balance and (when the backend exposes rates)
/// the estimated commission for this payment. Loads rates on first build,
/// so screens don't need any extra state.
class WalletCommissionCard extends StatefulWidget {
  final double walletBalance;
  final double amount;

  /// airtime, data, electricity, cable, education, insurance, international
  final String service;
  final bool balanceVisible;

  const WalletCommissionCard({
    super.key,
    required this.walletBalance,
    required this.amount,
    required this.service,
    this.balanceVisible = true,
  });

  @override
  State<WalletCommissionCard> createState() => _WalletCommissionCardState();
}

class _WalletCommissionCardState extends State<WalletCommissionCard> {
  @override
  void initState() {
    super.initState();
    CommissionRatesService.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final est = CommissionRatesService.estimate(widget.service, widget.amount);
    return DPCard(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      child: Column(
        children: [
          DPSummaryRow(
            'Wallet balance',
            widget.balanceVisible ? DP.naira(widget.walletBalance) : '₦ ••••',
          ),
          if (est != null)
            DPSummaryRow(
              'Estimated commission',
              DP.naira(est),
              valueColor: DP.green,
            ),
        ],
      ),
    );
  }
}
