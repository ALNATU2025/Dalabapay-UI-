// lib/presentation/widgets/request_limit_increase_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';

class RequestLimitIncreaseDialog extends StatelessWidget {
  final String service;
  final String limitType;
  final double currentLimit;
  final double requestedAmount;

  const RequestLimitIncreaseDialog({
    super.key,
    required this.service,
    required this.limitType,
    required this.currentLimit,
    required this.requestedAmount,
  });

  static const Color primaryColor = Color(0xFF15368A);
  static const Color secondaryColor = Color(0xFF079A68);
  static const Color warningColor = Color(0xFFB7791F);

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final serviceLabel = _getServiceLabel(service);
    final serviceIcon = _getServiceIcon(service);
    final limitLabel =
        limitType == 'perTransaction' ? 'Per Transaction' : 'Daily Cap';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: Container(
        width: isMobile ? double.infinity : 400,
        padding: EdgeInsets.all(isMobile ? 20 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: warningColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedAlert02,
                    color: warningColor,
                    size: isMobile ? 24 : 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Limit Reached',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 16 : 18,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF10255A),
                        ),
                      ),
                      Text(
                        '$serviceLabel - $limitLabel',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 12 : 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Service Icon
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: HugeIcon(
                  icon: serviceIcon,
                  color: primaryColor,
                  size: isMobile ? 32 : 40,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Details
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  _buildInfoRow(
                    'Current Limit',
                    '₦${currentLimit.toStringAsFixed(0)}',
                    Colors.grey.shade700,
                  ),
                  const Divider(height: 12),
                  _buildInfoRow(
                    'Requested Amount',
                    '₦${requestedAmount.toStringAsFixed(0)}',
                    warningColor,
                  ),
                  const Divider(height: 12),
                  _buildInfoRow('Service', serviceLabel, primaryColor),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Message
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedInformationCircle,
                    color: Colors.blue.shade700,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Contact admin to request a limit increase for this service.',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 12 : 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // WhatsApp Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openWhatsApp(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedWhatsapp,
                  color: Colors.white,
                  size: isMobile ? 20 : 24,
                ),
                label: Text(
                  'Chat Admin on WhatsApp',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 14 : 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Close Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Text(
                  'Close',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 13 : 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  String _getServiceLabel(String service) {
    final labels = {
      'airtime': 'Airtime',
      'data': 'Data',
      'electricity': 'Electricity',
      'cable': 'Cable TV',
      'transfer': 'Money Transfer',
      'international_airtime': 'International Airtime',
      'education': 'Education',
      'insurance': 'Insurance',
    };
    return labels[service] ?? service;
  }

  // HugeIcons constants are a List<List<dynamic>> payload, not Flutter IconData.
  dynamic _getServiceIcon(String service) {
    final icons = {
      'airtime': HugeIcons.strokeRoundedSmartPhone01,
      'data': HugeIcons.strokeRoundedWifi01,
      'electricity': HugeIcons.strokeRoundedBulb,
      'cable': HugeIcons.strokeRoundedTv01,
      'transfer': HugeIcons.strokeRoundedSquareArrowDataTransferHorizontal,
      'international_airtime': HugeIcons.strokeRoundedTelephone,
      'education': HugeIcons.strokeRoundedMortarboard01,
      'insurance': HugeIcons.strokeRoundedShield01,
    };
    return icons[service] ?? HugeIcons.strokeRoundedSettings01;
  }

  // ✅ FIXED: Proper async handling with mounted check
  Future<void> _openWhatsApp(BuildContext context) async {
    // Check if context is still valid
    if (!context.mounted) return;

    final serviceLabel = _getServiceLabel(service);
    final limitLabel =
        limitType == 'perTransaction' ? 'Per Transaction' : 'Daily Cap';

    const phoneNumber = '2349163207050'; // Replace with actual admin number

    // ✅ FIXED: Dynamic message with correct service name
    final message = '''
Hello Admin,

I would like to request a limit increase for $serviceLabel service.

Current Limit: ₦${currentLimit.toStringAsFixed(0)}
Requested Amount: ₦${requestedAmount.toStringAsFixed(0)}
Limit Type: $limitLabel

Please review my request and increase my limit as soon as possible.

Thank you.
    ''';

    final whatsappUrl =
        'https://wa.me/$phoneNumber?text=${Uri.encodeComponent(message)}';

    try {
      final uri = Uri.parse(whatsappUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!context.mounted) return;
        _showCopyMessageDialog(context, message);
      }
    } catch (e) {
      if (!context.mounted) return;
      _showCopyMessageDialog(context, message);
    }
  }

  // ✅ FIXED: Proper async handling with mounted check
  void _showCopyMessageDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Copy Message'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Please copy this message and send it to admin:'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    message,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
              ElevatedButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: message));
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Message copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  Navigator.pop(dialogContext);
                },
                child: const Text('Copy Message'),
              ),
            ],
          ),
    );
  }
}
