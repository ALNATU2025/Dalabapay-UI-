// lib/ui/dp_review.dart
// "Review payment" panel from the redesign, shared by every bill screen.
// It only draws: the owning screen passes its own PIN controller, error
// state and the handlers that already verify the PIN and run the payment.
import 'package:flutter/material.dart';

import 'dp_logo.dart';
import 'dp_motion.dart';
import 'dp_tokens.dart';
import 'dp_widgets.dart';

class DPReviewRow {
  final String label;
  final String value;
  final bool strong;
  const DPReviewRow(this.label, this.value, {this.strong = false});
}

class DPReviewPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final double amount;
  final List<DPReviewRow> rows;

  /// Current wallet balance and the total that will be debited.
  final double? walletBalance;
  final double? totalDebit;

  /// Estimated commission (null hides the note).
  final double? commission;

  final TextEditingController pinController;
  final FocusNode? pinFocusNode;
  final bool pinRequired;
  final String? pinError;
  final bool processing;
  final VoidCallback onPay;
  final VoidCallback onClose;

  final bool biometricAvailable;
  final String biometricLabel;
  final VoidCallback? onBiometric;

  final String? footnote;
  final String payLabel;
  final Widget? extra;

  const DPReviewPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.amount,
    required this.rows,
    required this.pinController,
    required this.onPay,
    required this.onClose,
    this.walletBalance,
    this.totalDebit,
    this.commission,
    this.pinFocusNode,
    this.pinRequired = true,
    this.pinError,
    this.processing = false,
    this.biometricAvailable = false,
    this.biometricLabel = 'biometrics',
    this.onBiometric,
    this.footnote,
    this.payLabel = '',
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final total = totalDebit ?? amount;
    final label = payLabel.isNotEmpty ? payLabel : 'Pay ${DP.naira(total)}';
    return Material(
      color: DP.bg,
      child: SafeArea(
        child: Column(
          children: [
            DPTopBar(
              title: 'Review payment',
              onBack: processing ? () {} : onClose,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                children: [
                  Center(
                    child: DPAppear(
                      scaleFrom: 0.7,
                      offsetY: 0,
                      child: DPIconBadge(icon, size: 64, iconSize: 30),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: DP.body.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      DP.naira(amount),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w500,
                        color: DP.ink,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  DPCard(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(
                      children: [
                        for (final r in rows)
                          DPSummaryRow(r.label, r.value, strong: r.strong),
                      ],
                    ),
                  ),
                  if (walletBalance != null) ...[
                    const SizedBox(height: 12),
                    DPCard(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Row(
                        children: [
                          const Icon(DPIcons.wallet, color: DP.navyIcon),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Dalabapay wallet',
                                  style: DP.bodyStrong,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  walletBalance! >= total
                                      ? '${DP.naira(walletBalance)} → ${DP.naira(walletBalance! - total)} after payment'
                                      : 'Balance ${DP.naira(walletBalance)} · not enough for this payment',
                                  style: DP.caption.copyWith(
                                    color: walletBalance! >= total
                                        ? DP.muted
                                        : DP.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            walletBalance! >= total
                                ? DPIcons.checkCircle
                                : DPIcons.alert,
                            color:
                                walletBalance! >= total ? DP.green : DP.red,
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (commission != null && commission! > 0) ...[
                    const SizedBox(height: 12),
                    DPBanner(
                      'You\'ll earn about ${DP.naira(commission)} commission. It goes to your separate earnings balance after payment.',
                    ),
                  ],
                  if (extra != null) ...[const SizedBox(height: 12), extra!],
                  if (pinRequired) ...[
                    const SizedBox(height: 24),
                    const Text('Enter your payment PIN', style: DP.section),
                    const SizedBox(height: 12),
                    DPCodeInput(
                      controller: pinController,
                      focusNode: pinFocusNode,
                      length: 6,
                      error: pinError != null,
                    ),
                    if (pinError != null)
                      DPHelper(pinError!, color: DP.red, icon: DPIcons.alert),
                  ],
                  if (biometricAvailable && onBiometric != null) ...[
                    const SizedBox(height: 14),
                    Center(
                      child: TextButton.icon(
                        onPressed: processing ? null : onBiometric,
                        icon: const Icon(DPIcons.fingerprint, color: DP.green),
                        label: Text(
                          'Pay with $biometricLabel',
                          style: const TextStyle(
                            color: DP.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            DPBottomAction(
              footnote: footnote == null
                  ? null
                  : Text(
                      footnote!,
                      textAlign: TextAlign.center,
                      style: DP.caption,
                    ),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: pinController,
                builder: (context, v, _) {
                  final ready = !pinRequired || v.text.trim().length >= 4;
                  return DPButton(
                    label: label,
                    icon: DPIcons.lock,
                    loading: processing,
                    onPressed: ready ? onPay : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen success state ("Payment successful") used after a purchase.
class DPSuccessPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final String serviceLabel;
  final double amount;
  final List<DPReviewRow> rows;
  final double? commission;
  final VoidCallback onDone;
  final VoidCallback? onShare;
  final VoidCallback? onViewReceipt;
  final bool pending;

  const DPSuccessPanel({
    super.key,
    this.title = 'Payment Successful!',
    this.subtitle = 'Your transaction has been completed successfully.',
    required this.serviceLabel,
    required this.amount,
    required this.rows,
    required this.onDone,
    this.commission,
    this.onShare,
    this.onViewReceipt,
    this.pending = false,
  });

  @override
  Widget build(BuildContext context) {
    final kind = pending ? DPStatusKind.pending : DPStatusKind.success;
    Duration d(int ms) => Duration(milliseconds: ms);
    return Material(
      color: DP.bg,
      child: SafeArea(
        child: Column(
          children: [
            DPLogoBar(
              onLeading: onDone,
              actionLabel: 'Help',
              onAction: () => Navigator.pushNamed(context, '/help'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                children: [
                  Center(child: DPStatusHero(kind: kind, size: 92)),
                  DPAppear(
                    delay: d(380),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        color: DP.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  DPAppear(
                    delay: d(460),
                    child: Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: DP.body.copyWith(color: DP.muted),
                    ),
                  ),
                  const SizedBox(height: 22),
                  DPAppear(
                    delay: d(540),
                    offsetY: 24,
                    child: _ReceiptCard(
                      serviceLabel: serviceLabel,
                      amount: amount,
                      pending: pending,
                      rows: rows,
                      commission: commission,
                      rowDelay: d(640),
                    ),
                  ),
                ],
              ),
            ),
            DPBottomAction(
              footnote: const Text(
                'Need help? Quote your payment reference.',
                style: DP.caption,
              ),
              child: Column(
                children: [
                  DPButton(label: 'Done', onPressed: onDone),
                  if (onShare != null) ...[
                    const SizedBox(height: 10),
                    DPOutlineButton(
                      label: 'Share Receipt',
                      icon: DPIcons.share,
                      onPressed: onShare,
                    ),
                  ] else if (onViewReceipt != null) ...[
                    const SizedBox(height: 10),
                    DPOutlineButton(
                      label: 'View Full Receipt',
                      icon: DPIcons.receipt,
                      onPressed: onViewReceipt,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White receipt card: service label, counting amount, status pill, rows
/// that cascade in, and the perforated "ticket" edge.
class _ReceiptCard extends StatelessWidget {
  final String serviceLabel;
  final double amount;
  final bool pending;
  final List<DPReviewRow> rows;
  final double? commission;
  final Duration rowDelay;

  const _ReceiptCard({
    required this.serviceLabel,
    required this.amount,
    required this.pending,
    required this.rows,
    required this.commission,
    required this.rowDelay,
  });

  @override
  Widget build(BuildContext context) {
    final all = [
      DPReviewRow('Amount', DP.naira(amount), strong: true),
      DPReviewRow('Service', serviceLabel),
      if (pending) const DPReviewRow('Status', 'Processing'),
      ...rows,
    ];
    return Container(
      decoration: BoxDecoration(
        color: DP.surface,
        borderRadius: BorderRadius.circular(DP.rLg),
        border: Border.all(color: DP.border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          for (var i = 0; i < all.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: DP.borderSoft),
            DPAppear(
              delay: rowDelay + DPMotion.stagger(i, stepMs: 50),
              offsetY: 8,
              child: DPSummaryRow(
                all[i].label,
                all[i].value,
                strong: all[i].strong,
                valueColor: i == 0 ? DP.ink : null,
              ),
            ),
          ],
          if (commission != null && commission! > 0) ...[
            const SizedBox(height: 8),
            DPAppear(
              delay: rowDelay + DPMotion.stagger(all.length, stepMs: 50),
              scaleFrom: 0.95,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: DP.mint,
                  borderRadius: BorderRadius.circular(DP.rSm),
                ),
                child: Row(
                  children: [
                    const Icon(DPIcons.sparkle, color: DP.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${DP.naira(commission)} added to your earnings',
                        style: const TextStyle(color: DP.green, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// Dashed hairline, like the tear line on a paper receipt.
class DPDashedDivider extends StatelessWidget {
  final Color color;
  const DPDashedDivider({super.key, this.color = DP.border});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const dash = 6.0, gap = 4.0;
        final n = (c.maxWidth / (dash + gap)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            n,
            (_) => SizedBox(
              width: dash,
              height: 1.2,
              child: DecoratedBox(decoration: BoxDecoration(color: color)),
            ),
          ),
        );
      },
    );
  }
}
