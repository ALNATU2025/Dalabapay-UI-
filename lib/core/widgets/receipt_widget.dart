// lib/core/widgets/receipt_widget.dart
// lib/core/widgets/receipt_widget.dart
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ✅ Same import used by the admin dashboard
import '../services/api_service.dart';
import '../../ui/ui.dart';

class ReceiptWidget extends StatefulWidget {
  final String transactionType;
  final String amount;
  final String status;
  final String transactionId;
  final String reference;
  final DateTime date;
  final String? phoneNumber;
  final String? smartcardNumber;
  final String? meterNumber;
  final String? description;
  final String? balanceBefore;
  final String? balanceAfter;
  final String? customerName;
  final String? customerAddress;
  final String? customerPhone;
  final String? customerUserId;
  final String? gateway;
  final String? recipientName;
  final String? mobileOperator;
  final bool isCommission;
  final String? commissionSource;
  final bool isService;
  final Color primaryColor;
  final String? customMessage;
  final String? vtpassResponse;
  final bool showWatermark;
  final String? packageVariationCode;
  final String? electricityToken;
  final bool isAdminTransaction;
  final String? adminNote;
  final bool isUserAdmin;
  final String? certificateUrl;

  // ✅ NEW: Admin action fields (shown for admin credit/debit / adjustments)
  final String? adminReason;
  final String? adminReference;
  final String? adminTransactionNote;
  final String? adminPerformerName;
  final String? adminPerformerEmail;

  const ReceiptWidget({
    super.key,
    required this.transactionType,
    required this.amount,
    required this.status,
    required this.transactionId,
    required this.reference,
    required this.date,
    this.phoneNumber,
    this.smartcardNumber,
    this.meterNumber,
    this.description,
    this.balanceBefore,
    this.balanceAfter,
    this.customerName,
    this.customerAddress,
    this.customerPhone,
    this.customerUserId,
    this.gateway,
    this.recipientName,
    this.mobileOperator,
    this.isCommission = false,
    this.commissionSource,
    this.isService = false,
    this.primaryColor = const Color(0xFF102C68),
    this.customMessage,
    this.vtpassResponse,
    this.showWatermark = true,
    this.packageVariationCode,
    this.electricityToken,
    this.isAdminTransaction = false,
    this.adminNote,
    this.isUserAdmin = false,
    this.certificateUrl,

    // ✅ NEW: Admin action fields
    this.adminReason,
    this.adminReference,
    this.adminTransactionNote,
    this.adminPerformerName,
    this.adminPerformerEmail,
  });

  @override
  State<ReceiptWidget> createState() => _ReceiptWidgetState();
}

class _ReceiptWidgetState extends State<ReceiptWidget> {
  final GlobalKey _receiptKey = GlobalKey();
  bool _isSaving = false;
  bool _isSharing = false;
  bool _isCopyingToken = false;
  bool _isDownloadingCertificate = false;

  // ✅ Track whether the CURRENT viewer is an admin.
  // This ensures non-admin users NEVER see admin-only UI
  // on their receipts, regardless of what the caller passes.
  bool _isViewerAdmin = false;
  bool _isViewerAdminLoaded = false;

  // Brand Colors
  static const Color _brandPrimary = Color(0xFF102C68);
  static const Color _brandSecondary = Color(0xFF168566);
  static const Color _brandLight = Color(0xFF5BB592);
  static const Color _brandWhite = Color(0xFFFFFFFF);

  @override
  void initState() {
    super.initState();
    _loadViewerAdminStatus();
  }

  /// Reads the caller's admin status from local storage.
  /// Non-admins ALWAYS get `false` — so admin UI never shows for them.
  /// ✅ Determines whether the CURRENT viewer is an admin.
  ///
  /// Uses the SAME method as `AdminDashboardHome._loadCurrentUser()`:
  ///   1. Try `ApiService.getUserRole()` — the authoritative backend source
  ///   2. Fallback to local `SharedPreferences` (role + isAdmin + isSuperAdmin)
  ///   3. Fallback to the hardcoded super-admin ID
  ///
  /// Non-admins ALWAYS get `false` → admin UI NEVER shows for them.
  Future<void> _loadViewerAdminStatus() async {
    const String superAdminId = "690088325ca99bed6ab8d4a5";

    // Start with a safe default (false) — we only flip to true
    // if we can positively confirm the user is an admin.
    bool viewerIsAdmin = false;

    // ─────────────────────────────────────────────────
    // 1) Read local cache (fast + always available)
    // ─────────────────────────────────────────────────
    String? localUserId;
    String localRole = 'user';
    bool localIsAdmin = false;
    bool localIsSuperAdmin = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      localIsAdmin = prefs.getBool('isAdmin') ?? false;
      localIsSuperAdmin = prefs.getBool('isSuperAdmin') ?? false;
      localRole = prefs.getString('role') ?? 'user';

      final userDataString = prefs.getString('user');
      if (userDataString != null) {
        try {
          final userData = jsonDecode(userDataString);
          localUserId = userData['_id']?.toString();
        } catch (_) {
          /* ignore corrupted user blob */
        }
      }
    } catch (_) {
      /* ignore prefs failure */
    }

    // If local cache already confirms admin → trust it
    if (localIsAdmin ||
        localIsSuperAdmin ||
        localRole == 'admin' ||
        localRole == 'super_admin' ||
        localUserId == superAdminId) {
      viewerIsAdmin = true;
    }

    // ─────────────────────────────────────────────────
    // 2) Ask the backend (authoritative source)
    //    Only needed if local cache didn't already say "admin".
    // ─────────────────────────────────────────────────
    if (!viewerIsAdmin) {
      try {
        final roleResult = await ApiService.getUserRole();
        if (roleResult['success'] == true) {
          final data = roleResult['data'];
          final userRole = data?['role']?.toString() ?? 'user';
          final backendIsSuperAdmin =
              data?['isSuperAdmin'] == true ||
              userRole == 'super_admin' ||
              userRole == 'superadmin';
          final backendIsAdmin =
              data?['isAdmin'] == true ||
              userRole == 'admin' ||
              backendIsSuperAdmin;

          // Also check hardcoded super-admin ID if present
          final userIdFromRole = data?['_id']?.toString();
          final matchesSuperAdminId =
              userIdFromRole == superAdminId || localUserId == superAdminId;

          viewerIsAdmin =
              backendIsAdmin || backendIsSuperAdmin || matchesSuperAdminId;
        }
      } catch (_) {
        // Network error — fall through with whatever we decided from local cache
      }
    }

    // ─────────────────────────────────────────────────
    // 3) Publish result to UI
    // ─────────────────────────────────────────────────
    if (mounted) {
      setState(() {
        _isViewerAdmin = viewerIsAdmin;
        _isViewerAdminLoaded = true;
      });
    }
  }

  String get _formattedDate {
    return DateFormat('MMM dd, yyyy - hh:mm a').format(widget.date);
  }

  String get _formattedAmount {
    String cleanAmount =
        widget.amount
            .replaceAll('₦', '')
            .replaceAll('N', '')
            .replaceAll('₩', '')
            .replaceAll('¥', '')
            .replaceAll('#', '')
            .trim();
    double amount = double.tryParse(cleanAmount) ?? 0;
    return '₦${amount.toStringAsFixed(2)}';
  }

  Color get _statusColor {
    final status = widget.status.toLowerCase();
    if (status.contains('success') || status.contains('completed')) {
      return _brandSecondary;
    } else if (status.contains('pending') || status.contains('processing')) {
      return Colors.orange;
    } else if (status.contains('failed') || status.contains('cancelled')) {
      return Colors.red;
    }
    return _brandPrimary;
  }

  String? get _detectedOperator {
    if (widget.mobileOperator != null && widget.mobileOperator!.isNotEmpty) {
      return widget.mobileOperator!.toUpperCase();
    }
    final desc = widget.description?.toLowerCase() ?? '';
    final type = widget.transactionType.toLowerCase();
    if (desc.contains('mtn') || type.contains('mtn')) return 'MTN';
    if (desc.contains('airtel') || type.contains('airtel')) return 'AIRTEL';
    if (desc.contains('glo') || type.contains('glo')) return 'GLO';
    if (desc.contains('9mobile') ||
        desc.contains('etisalat') ||
        type.contains('9mobile') ||
        type.contains('etisalat')) {
      return '9MOBILE';
    }
    return null;
  }

  Color get _operatorColor {
    switch (_detectedOperator?.toUpperCase()) {
      case 'MTN':
        return const Color(0xFFFFCB05);
      case 'AIRTEL':
        return const Color(0xFFEF1C25);
      case 'GLO':
        return const Color(0xFF00843D);
      case '9MOBILE':
        return const Color(0xFF00B4D2);
      default:
        return _brandPrimary;
    }
  }

  Future<Uint8List?> _captureReceipt() async {
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final renderObject = _receiptKey.currentContext?.findRenderObject();
      if (renderObject == null || renderObject is! RenderRepaintBoundary) {
        return null;
      }
      final boundary = renderObject;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return byteData?.buffer.asUint8List();
    } catch (e) {
      return null;
    }
  }

  Future<void> _downloadCertificate() async {
    if (widget.certificateUrl == null || widget.certificateUrl!.isEmpty) {
      _showErrorMessage('No certificate available for download');
      return;
    }

    setState(() => _isDownloadingCertificate = true);

    try {
      final url = widget.certificateUrl!;

      // If it's a web URL
      if (url.startsWith('http')) {
        // Show a dialog with the link
        _showCertificateLinkDialog(url);
      } else {
        // If it's a code, show as text
        _showCertificateCodeDialog(url);
      }
    } catch (e) {
      _showErrorMessage('Failed to access certificate: $e');
    } finally {
      if (mounted) {
        setState(() => _isDownloadingCertificate = false);
      }
    }
  }

  void _showCertificateLinkDialog(String url) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.picture_as_pdf, color: Colors.red, size: 28),
                const SizedBox(width: 10),
                const Text('Certificate Available'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your insurance certificate is ready.'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📄 PDF Certificate',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        url.length > 80 ? '${url.substring(0, 80)}...' : url,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.blue.shade700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Copy URL to clipboard
                  Clipboard.setData(ClipboardData(text: url));
                  _showSuccessMessage(
                    '✅ Certificate link copied to clipboard!',
                  );
                },
                child: const Text('Copy Link'),
              ),
            ],
          ),
    );
  }

  void _showCertificateCodeDialog(String code) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Certificate Code'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your insurance certificate code:'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    code,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  _showSuccessMessage('✅ Certificate code copied!');
                },
                child: const Text('Copy Code'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  Future<void> _saveReceipt() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final imageBytes = await _captureReceipt();
      if (imageBytes != null) {
        _showSuccessMessage('✅ Receipt ready! Take screenshot: Power + Volume');
      } else {
        _showErrorMessage('Failed to capture. Take manual screenshot.');
      }
    } catch (e) {
      _showErrorMessage('Save failed. Take manual screenshot.');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _shareReceipt() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      final imageBytes = await _captureReceipt();
      final operator = _detectedOperator ?? '';
      final operatorText = operator.isNotEmpty ? '📶 Network: $operator' : '';

      final shareText = '''
📄 Dalabapay Transaction Receipt
━━━━━━━━━━━━━━━━━━━━
📋 Type: ${widget.transactionType}
💰 Amount: $_formattedAmount
✅ Status: ${widget.status}
🆔 ID: ${widget.transactionId}
📅 Date: $_formattedDate
$operatorText
${widget.phoneNumber != null ? '📱 Phone: ${widget.phoneNumber}' : ''}
${widget.description != null && widget.description!.isNotEmpty ? '📝 Description: ${widget.description}' : ''}
${widget.gateway != null && widget.gateway!.isNotEmpty ? '🌐 Gateway: ${widget.gateway}' : ''}
━━━━━━━━━━━━━━━━━━━━
Powered by Dalabapay''';

      if (imageBytes != null) {
        try {
          final tempDir = await Directory.systemTemp.createTemp('dalabapay');
          final filePath =
              '${tempDir.path}/receipt_${widget.transactionId}.png';
          final file = File(filePath);
          await file.writeAsBytes(imageBytes);
          await Share.shareXFiles(
            [XFile(filePath)],
            text: shareText,
            subject: 'Dalabapay Receipt - ${widget.transactionType}',
          );
        } catch (_) {
          await Share.share(shareText);
        }
      } else {
        await Share.share(shareText);
      }
      _showSuccessMessage('✅ Receipt shared!');
    } catch (e) {
      _showErrorMessage('Share failed. Try manual screenshot.');
    } finally {
      setState(() => _isSharing = false);
    }
  }

  Future<void> _copyTokenToClipboard(String textToCopy) async {
    if (textToCopy.isEmpty ||
        textToCopy == 'N/A' ||
        textToCopy == 'Check SMS') {
      return;
    }
    setState(() => _isCopyingToken = true);
    try {
      await Clipboard.setData(ClipboardData(text: textToCopy));
      _showCopySuccessMessage('✅ Token copied to clipboard!');
    } catch (e) {
      _showErrorMessage('Failed to copy');
    } finally {
      setState(() => _isCopyingToken = false);
    }
  }

  void _showSuccessMessage(String message) {
    if (mounted) dpSnack(context, message.replaceAll('✅ ', ''), success: true);
  }

  void _showCopySuccessMessage(String message) {
    if (mounted) dpSnack(context, message.replaceAll('✅ ', ''), success: true);
  }

  void _showErrorMessage(String message) {
    if (mounted) dpSnack(context, message, error: true);
  }

  /// Large status mark at the top of the receipt.
  Widget _buildStatusBadge() {
    final s = widget.status.toLowerCase();
    final ok = s.contains('success') ||
        s.contains('completed') ||
        s.contains('delivered') ||
        s.contains('resolved');
    final pending = s.contains('pending') || s.contains('processing');
    final Color c = ok ? DP.green : (pending ? DP.amber : DP.red);
    final Color bg = ok ? DP.mint : (pending ? DP.amberBg : DP.redBg);
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        child: Icon(
          ok ? DPIcons.check : (pending ? DPIcons.pending : DPIcons.close),
          color: Colors.white,
          size: 30,
        ),
      ),
    );
  }

  String get _headline {
    final s = widget.status.toLowerCase();
    if (s.contains('pending') || s.contains('processing')) {
      return 'Payment processing';
    }
    if (s.contains('fail') || s.contains('cancel')) return 'Payment failed';
    if (s.contains('refund')) return 'Payment refunded';
    if (widget.isCommission) return 'Earnings credited';
    return 'Payment successful';
  }

  String get _subline {
    final s = widget.status.toLowerCase();
    if (s.contains('pending') || s.contains('processing')) {
      return 'We\'ll update you as soon as it\'s confirmed.';
    }
    if (s.contains('fail') || s.contains('cancel')) {
      return 'No money left your wallet for this payment.';
    }
    return 'That\'s one less thing on your list.';
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    bool highlight = false,
    bool isAmount = false,
    bool showCopyIcon = false,
  }) {
    final canCopy = showCopyIcon &&
        value.isNotEmpty &&
        value != 'N/A' &&
        value != 'Check SMS';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: DP.muted),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: GestureDetector(
              onTap: canCopy ? () => _copyTokenToClipboard(value) : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: highlight || isAmount
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: DP.ink,
                      ),
                    ),
                  ),
                  if (canCopy) ...[
                    const SizedBox(width: 6),
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(DPIcons.copy, size: 14, color: DP.faint),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const SizedBox.shrink();
  }

  // ==================== ADMIN ACTION SECTION ====================
  /// Shown on the receipt ONLY when an admin performed the transaction
  /// (manual credit/debit, adjustment, etc.).
  ///
  /// Displays: Reason, Reference, Note, and the admin who did it.
  Widget _buildAdminActionSection() {
    final hasReason =
        widget.adminReason != null && widget.adminReason!.trim().isNotEmpty;
    final hasReference =
        widget.adminReference != null &&
        widget.adminReference!.trim().isNotEmpty;
    final hasNote =
        widget.adminTransactionNote != null &&
        widget.adminTransactionNote!.trim().isNotEmpty;
    final hasAdmin =
        widget.adminPerformerName != null &&
        widget.adminPerformerName!.trim().isNotEmpty;

    // If nothing to show, render nothing.
    if (!hasReason && !hasReference && !hasNote && !hasAdmin) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6), // soft amber background
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE0A1), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFE0A1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  size: 14,
                  color: Color(0xFFA76B1D),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'ADMIN ACTION DETAILS',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFA76B1D),
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Reason
          if (hasReason) ...[
            _buildAdminDetailRow(
              icon: Icons.notes_rounded,
              label: 'Reason',
              value: widget.adminReason!,
            ),
            if (hasReference || hasNote || hasAdmin) const SizedBox(height: 8),
          ],

          // Reference
          if (hasReference) ...[
            _buildAdminDetailRow(
              icon: Icons.confirmation_number_outlined,
              label: 'Reference',
              value: widget.adminReference!,
              copyable: true,
            ),
            if (hasNote || hasAdmin) const SizedBox(height: 8),
          ],

          // Note
          if (hasNote) ...[
            _buildAdminDetailRow(
              icon: Icons.description_outlined,
              label: 'Note',
              value: widget.adminTransactionNote!,
            ),
            if (hasAdmin) const SizedBox(height: 8),
          ],

          // Admin who performed the action
          if (hasAdmin)
            _buildAdminDetailRow(
              icon: Icons.verified_user_rounded,
              label: 'Performed By',
              value:
                  widget.adminPerformerEmail != null &&
                          widget.adminPerformerEmail!.isNotEmpty
                      ? '${widget.adminPerformerName} (${widget.adminPerformerEmail})'
                      : widget.adminPerformerName!,
            ),
        ],
      ),
    );
  }

  Widget _buildAdminDetailRow({
    required IconData icon,
    required String label,
    required String value,
    bool copyable = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 14, color: const Color(0xFFA76B1D)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFA76B1D),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade900,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (copyable)
                    GestureDetector(
                      onTap: () => _copyTokenToClipboard(value),
                      child: const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.content_copy_rounded,
                          size: 13,
                          color: Color(0xFFA76B1D),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
  // ==================== END ADMIN ACTION SECTION ====================

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final operator = _detectedOperator;
    final isElectricity =
        widget.transactionType.toLowerCase().contains('electricity');
    final hasToken = widget.electricityToken != null &&
        widget.electricityToken!.isNotEmpty &&
        widget.electricityToken != 'Check SMS' &&
        widget.electricityToken != 'N/A' &&
        isElectricity;
    final isFunding = widget.transactionType == 'Fund Wallet' ||
        widget.transactionType == 'Wallet Funding';
    String? money(String? raw) {
      if (raw == null || raw.isEmpty || raw == 'N/A') return null;
      final d = double.tryParse(raw.replaceAll(RegExp(r'[₦,\s]'), ''));
      return d == null ? '₦$raw' : DP.naira(d);
    }

    final before = money(widget.balanceBefore);
    final after = money(widget.balanceAfter);
    final showAdmin = (widget.isUserAdmin || widget.isAdminTransaction) &&
        _isViewerAdminLoaded &&
        _isViewerAdmin;

    final receiptCard = Container(
      decoration: BoxDecoration(
        color: DP.surface,
        borderRadius: BorderRadius.circular(DP.rXl),
        border: Border.all(color: DP.border),
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        children: [
          Text(
            widget.transactionType.toUpperCase(),
            textAlign: TextAlign.center,
            style: DP.tiny,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _formattedAmount,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w500,
                color: DP.ink,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(),
          const SizedBox(height: 4),
          if (widget.phoneNumber != null && widget.phoneNumber!.isNotEmpty)
            _buildDetailRow('Recipient', widget.phoneNumber!, showCopyIcon: true),
          if (operator != null) _buildDetailRow('Network', operator),
          if (widget.description != null && widget.description!.isNotEmpty)
            _buildDetailRow('Description', widget.description!),
          if (widget.smartcardNumber != null &&
              widget.smartcardNumber!.isNotEmpty)
            _buildDetailRow(
              'Smartcard number',
              widget.smartcardNumber!,
              showCopyIcon: true,
            ),
          if (widget.meterNumber != null && widget.meterNumber!.isNotEmpty)
            _buildDetailRow(
              'Meter number',
              widget.meterNumber!,
              showCopyIcon: true,
            ),
          if (isElectricity &&
              widget.customerName != null &&
              widget.customerName!.isNotEmpty &&
              widget.customerName != 'N/A')
            _buildDetailRow('Customer', widget.customerName!),
          if (isElectricity &&
              widget.customerAddress != null &&
              widget.customerAddress!.isNotEmpty &&
              widget.customerAddress != 'N/A')
            _buildDetailRow('Address', widget.customerAddress!),
          if (widget.packageVariationCode != null &&
              widget.packageVariationCode!.isNotEmpty &&
              widget.packageVariationCode != 'N/A')
            _buildDetailRow('Package', widget.packageVariationCode!),
          if (widget.isCommission &&
              widget.commissionSource != null &&
              widget.commissionSource!.isNotEmpty)
            _buildDetailRow('Earned from', widget.commissionSource!),
          _buildDetailRow(
            'Paid from',
            widget.isCommission || isFunding ? 'Dalabapay earnings' : 'Dalabapay wallet',
          ),
          if (before != null && (isFunding || after != null))
            _buildDetailRow('Previous balance', before),
          _buildDetailRow(
            widget.isCommission || isFunding ? 'Amount' : 'Total paid',
            _formattedAmount,
            isAmount: true,
          ),
          if (after != null) _buildDetailRow('New balance', after),
          _buildDetailRow(
            'Date & time',
            DateFormat('d MMM yyyy, h:mm a').format(widget.date.toLocal()),
          ),
          _buildDetailRow('Reference', widget.reference, showCopyIcon: true),
          if (widget.transactionId != widget.reference)
            _buildDetailRow(
              'Transaction ID',
              widget.transactionId,
              showCopyIcon: true,
            ),
          if (hasToken) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _isCopyingToken
                  ? null
                  : () => _copyTokenToClipboard(widget.electricityToken!),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: DP.amberBg,
                  borderRadius: BorderRadius.circular(DP.rMd),
                  border: Border.all(color: DP.amberLine),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ELECTRICITY TOKEN · TAP TO COPY',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w600,
                        color: DP.amber,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.electricityToken!,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.4,
                              color: DP.ink,
                            ),
                          ),
                        ),
                        const Icon(DPIcons.copy, color: DP.amber, size: 18),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (widget.isCommission) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      '$_formattedAmount added to your earnings',
                      style: const TextStyle(color: DP.green, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (widget.customMessage != null &&
              widget.customMessage!.isNotEmpty &&
              !widget.customMessage!.contains('VTpass')) ...[
            const SizedBox(height: 10),
            Text(
              widget.customMessage!.replaceAll('✓ ', ''),
              textAlign: TextAlign.center,
              style: DP.caption,
            ),
          ],
          if (showAdmin) ...[
            const SizedBox(height: 10),
            const Divider(),
            if (widget.customerName != null &&
                widget.customerName!.isNotEmpty &&
                widget.customerName != 'Unknown User' &&
                widget.customerName != 'N/A')
              _buildDetailRow('User name', widget.customerName!, showCopyIcon: true),
            if (widget.customerAddress != null &&
                widget.customerAddress!.isNotEmpty &&
                widget.customerAddress != 'No Email' &&
                widget.customerAddress != 'N/A')
              _buildDetailRow('User email', widget.customerAddress!, showCopyIcon: true),
            if (widget.customerPhone != null &&
                widget.customerPhone!.isNotEmpty &&
                widget.customerPhone != 'No Phone' &&
                widget.customerPhone != 'N/A')
              _buildDetailRow('User phone', widget.customerPhone!, showCopyIcon: true),
            if (widget.customerUserId != null &&
                widget.customerUserId!.isNotEmpty &&
                widget.customerUserId != 'No ID' &&
                widget.customerUserId != 'N/A')
              _buildDetailRow('User ID', widget.customerUserId!, showCopyIcon: true),
            if (widget.isAdminTransaction) ...[
              const SizedBox(height: 6),
              DPBanner(
                widget.adminNote ?? 'Admin transaction',
                tone: DPTone.warning,
                icon: DPIcons.admin,
              ),
              _buildAdminActionSection(),
            ],
          ],
          const SizedBox(height: 12),
          const DPWordmark(height: 20),
        ],
      ),
    );

    return Dialog(
      backgroundColor: DP.bg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DP.rXl)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: size.height * 0.92),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(DPIcons.close, color: DP.ink),
                  ),
                  const Expanded(
                    child: Text(
                      'Payment receipt',
                      textAlign: TextAlign.center,
                      style: DP.bodyStrong,
                    ),
                  ),
                  DPTextLink(
                    label: 'Help',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/help');
                    },
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                child: RepaintBoundary(
                  key: _receiptKey,
                  child: Container(
                    color: DP.bg,
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Column(
                      children: [
                        _buildStatusBadge(),
                        const SizedBox(height: 12),
                        Text(_headline, style: DP.title.copyWith(fontSize: 21)),
                        const SizedBox(height: 4),
                        Text(
                          _subline,
                          textAlign: TextAlign.center,
                          style: DP.body.copyWith(color: DP.muted, fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        receiptCard,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Column(
                children: [
                  if (widget.certificateUrl != null &&
                      widget.certificateUrl!.isNotEmpty &&
                      widget.transactionType.toLowerCase().contains('insurance')) ...[
                    DPOutlineButton(
                      label: _isDownloadingCertificate
                          ? 'Loading…'
                          : 'Download certificate',
                      icon: DPIcons.download,
                      onPressed:
                          _isDownloadingCertificate ? null : _downloadCertificate,
                    ),
                    const SizedBox(height: 10),
                  ],
                  DPButton(
                    label: 'Share receipt',
                    icon: DPIcons.share,
                    loading: _isSharing,
                    onPressed: _isSharing ? null : _shareReceipt,
                  ),
                  const SizedBox(height: 10),
                  DPOutlineButton(
                    label: 'Done',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Need help? Quote your payment reference.',
                    style: DP.caption,
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
