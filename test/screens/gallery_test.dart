import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dalabapay/ui/ui.dart';
import 'harness.dart';

void main() {
  setUpAll(() async {
    mockPlatform();
    await loadFonts();
  });

  testWidgets('component gallery', (tester) async {
    await shoot(
      tester,
      '00_gallery',
      DPPage(
        title: 'Buy airtime',
        actionLabel: 'History',
        onAction: () {},
        children: [
          const DPHeadline('Keep the conversation going.',
              subtitle: 'Top up any Nigerian number in moments.'),
          const DPFieldLabel('Choose network'),
          DPChipGrid(
              labels: const ['MTN', 'Airtel', 'Glo', '9mobile'],
              selectedIndex: 0,
              columns: 4,
              onSelected: (_) {}),
          const DPField(label: 'Phone number', hint: '0803 456 7890', suffixIcon: DPIcons.contactRound,
              helper: 'Your number · MTN Nigeria'),
          const DPSummaryCard(rows: [
            DPSummaryRow('Wallet balance', '₦126,850.00'),
            DPSummaryRow('Estimated commission', '₦20.00', valueColor: DP.green),
          ]),
          const DPNotice('Commission goes to your earnings, not your wallet balance.'),
          DPButton(label: 'Continue to review', icon: DPIcons.arrowRight, onPressed: () {}),
          const SizedBox(height: 16),
          DPServiceGrid(tiles: [
            for (final i in [DPIcons.phone, DPIcons.wifi, DPIcons.zap, DPIcons.tv])
              DPServiceTile(icon: i, label: 'Service', onTap: () {}),
          ]),
          const DPTransactionTile(icon: DPIcons.phone, title: 'MTN airtime',
              subtitle: 'Today, 10:42 AM · Successful', amount: '-₦2,000'),
          const DPTransactionTile(icon: DPIcons.arrowDownLeft, title: 'Wallet top-up',
              subtitle: 'Today, 9:15 AM · Successful', amount: '+₦50,000', credit: true),
          const DPLogo(height: 30),
        ],
      ),
      height: 1500,
    );
  });
}
