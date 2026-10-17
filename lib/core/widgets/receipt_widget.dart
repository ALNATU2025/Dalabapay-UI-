// lib/core/widgets/receipt_widget.dart
// lib/core/widgets/receipt_widget.dart
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    this.primaryColor = const Color(0xFF243889),
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
  // Brand colours (from the design system)
  static const Color _brandPrimary = DP.navy;
  static const Color _brandSecondary = DP.green;

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
    return DateFormat('d MMM yyyy, h:mm a').format(widget.date.toLocal());
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
    if (status.contains('success') ||
        status.contains('completed') ||
        status.contains('deliver')) {
      return DP.green;
    } else if (status.contains('pending') || status.contains('processing')) {
      return DP.warn;
    } else if (status.contains('failed') || status.contains('cancelled')) {
      return DP.danger;
    }
    return DP.blue;
  }

  bool get _isFailed {
    final s = widget.status.toLowerCase();
    return s.contains('fail') || s.contains('cancel');
  }

  bool get _isPending {
    final s = widget.status.toLowerCase();
    return s.contains('pend') || s.contains('process');
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
    showDPDialog(
      context,
      tone: DPDialogTone.success,
      icon: DPIcons.fileText,
      title: 'Your certificate is ready',
      message: url.length > 80 ? '${url.substring(0, 80)}…' : url,
      primaryLabel: 'Copy link',
      onPrimary: () {
        Navigator.pop(context);
        Clipboard.setData(ClipboardData(text: url));
        _showSuccessMessage('Certificate link copied');
      },
      secondaryLabel: 'Close',
    );
  }

  void _showCertificateCodeDialog(String code) {
    showDPDialog(
      context,
      tone: DPDialogTone.success,
      icon: DPIcons.fileText,
      title: 'Certificate code',
      body: SelectableText(code, style: DPText.title, textAlign: TextAlign.center),
      primaryLabel: 'Copy code',
      onPrimary: () {
        Clipboard.setData(ClipboardData(text: code));
        _showSuccessMessage('Certificate code copied');
      },
      secondaryLabel: 'Close',
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
    dpSnack(context, message.replaceAll('✅ ', ''), success: true);
  }

  void _showCopySuccessMessage(String message) {
    dpSnack(context, message.replaceAll('✅ ', ''), success: true);
  }

  void _showErrorMessage(String message) {
    dpSnack(context, message, error: true);
  }

  Widget _buildStatusBadge() => DPStatusPill(widget.status);

  Widget _buildDetailRow(
    String label,
    String value, {
    bool highlight = false,
    bool isAmount = false,
    bool showCopyIcon = false,
  }) {
    final canCopy = showCopyIcon && value.isNotEmpty && value != 'N/A' && value != 'Check SMS';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: DPText.bodyMuted.copyWith(fontSize: 13.5)),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: canCopy ? () => _copyTokenToClipboard(value) : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      style: DPText.value.copyWith(
                        fontSize: 13.5,
                        color: isAmount ? DP.green : DP.ink,
                        fontWeight: highlight || isAmount ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (canCopy) ...[
                    const SizedBox(width: 6),
                    const DPIcon(DPIcons.copy, size: 14, color: DP.muted),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() => const SizedBox.shrink();

  // ==================== ADMIN ACTION SECTION ====================
  Widget _buildAdminActionSection() {
    final hasReason = widget.adminReason != null && widget.adminReason!.trim().isNotEmpty;
    final hasReference =
        widget.adminReference != null && widget.adminReference!.trim().isNotEmpty;
    final hasNote =
        widget.adminTransactionNote != null && widget.adminTransactionNote!.trim().isNotEmpty;
    final hasAdmin =
        widget.adminPerformerName != null && widget.adminPerformerName!.trim().isNotEmpty;

    if (!hasReason && !hasReference && !hasNote && !hasAdmin) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DP.warnSoft,
        borderRadius: BorderRadius.circular(DP.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ADMIN ACTION DETAILS', style: DPText.overline.copyWith(color: DP.warn)),
          const SizedBox(height: 10),
          if (hasReason)
            _buildAdminDetailRow(icon: Icons.notes_rounded, label: 'Reason', value: widget.adminReason!),
          if (hasReference)
            _buildAdminDetailRow(
              icon: Icons.confirmation_number_outlined,
              label: 'Reference',
              value: widget.adminReference!,
              copyable: true,
            ),
          if (hasNote)
            _buildAdminDetailRow(
              icon: Icons.description_outlined,
              label: 'Note',
              value: widget.adminTransactionNote!,
            ),
          if (hasAdmin)
            _buildAdminDetailRow(
              icon: Icons.verified_user_outlined,
              label: 'Performed by',
              value: widget.adminPerformerEmail != null && widget.adminPerformerEmail!.isNotEmpty
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: DP.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: DPText.small.copyWith(color: DP.warn)),
                const SizedBox(height: 2),
                Text(value, style: DPText.value.copyWith(fontSize: 13)),
              ],
            ),
          ),
          if (copyable)
            GestureDetector(
              onTap: () => _copyTokenToClipboard(value),
              child: const DPIcon(DPIcons.copy, size: 14, color: DP.warn),
            ),
        ],
      ),
    );
  }
  // ==================== END ADMIN ACTION SECTION ====================

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final operator = _detectedOperator;
    final title = _isFailed
        ? 'Payment failed'
        : (_isPending ? 'Payment processing' : 'Payment successful');
    final subtitle = _isFailed
        ? 'No money was taken for this payment.'
        : (_isPending
            ? 'We’ll update you as soon as it’s confirmed.'
            : 'That’s one less thing on your list.');
    final isViewerAdmin = _isViewerAdminLoaded && _isViewerAdmin;
    final hasToken = widget.electricityToken != null &&
        widget.electricityToken!.isNotEmpty &&
        widget.electricityToken != 'Check SMS' &&
        widget.electricityToken != 'N/A' &&
        widget.transactionType.toLowerCase().contains('electricity');
    final isElectricity = widget.transactionType.toLowerCase().contains('electricity');

    String? money(String? raw) {
      if (raw == null || raw.isEmpty || raw == 'N/A') return null;
      final v = double.tryParse(raw.replaceAll(',', ''));
      return v == null ? '₦$raw' : dpNaira(v);
    }

    final rows = <Widget>[
      if (widget.phoneNumber != null && widget.phoneNumber!.isNotEmpty)
        _buildDetailRow('Recipient', widget.phoneNumber!, showCopyIcon: true),
      if (widget.recipientName != null && widget.recipientName!.isNotEmpty)
        _buildDetailRow('Recipient name', widget.recipientName!),
      if (operator != null) _buildDetailRow('Network', '$operator Nigeria'),
      if (widget.smartcardNumber != null && widget.smartcardNumber!.isNotEmpty)
        _buildDetailRow('Smartcard number', widget.smartcardNumber!, showCopyIcon: true),
      if (widget.meterNumber != null && widget.meterNumber!.isNotEmpty)
        _buildDetailRow('Meter number', widget.meterNumber!, showCopyIcon: true),
      if (isElectricity &&
          widget.customerName != null &&
          widget.customerName!.isNotEmpty &&
          widget.customerName != 'N/A')
        _buildDetailRow('Customer name', widget.customerName!),
      if (isElectricity &&
          widget.customerAddress != null &&
          widget.customerAddress!.isNotEmpty &&
          widget.customerAddress != 'N/A')
        _buildDetailRow('Customer address', widget.customerAddress!),
      if (widget.packageVariationCode != null &&
          widget.packageVariationCode!.isNotEmpty &&
          widget.packageVariationCode != 'N/A')
        _buildDetailRow('Package', widget.packageVariationCode!),
      if (widget.description != null && widget.description!.isNotEmpty)
        _buildDetailRow('Description', widget.description!),
      if (widget.isCommission &&
          widget.commissionSource != null &&
          widget.commissionSource!.isNotEmpty)
        _buildDetailRow('Commission source', widget.commissionSource!),
      _buildDetailRow('Paid from', widget.isCommission ? 'Commission earnings' : 'Dalabapay wallet'),
      if (money(widget.balanceBefore) != null)
        _buildDetailRow('Previous balance', money(widget.balanceBefore)!),
      _buildDetailRow('Total paid', _formattedAmount, highlight: true),
      if (money(widget.balanceAfter) != null)
        _buildDetailRow('New balance', money(widget.balanceAfter)!, isAmount: true),
      _buildDetailRow('Date & time', _formattedDate),
      _buildDetailRow('Reference', widget.reference, showCopyIcon: true),
      if (widget.transactionId != widget.reference)
        _buildDetailRow('Transaction ID', widget.transactionId, showCopyIcon: true),
      if ((widget.isUserAdmin || widget.isAdminTransaction) && isViewerAdmin) ...[
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
      ],
    ];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: screenHeight * 0.9),
        child: Material(
          color: DP.bg,
          borderRadius: BorderRadius.circular(DP.rXl),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const DPIcon(DPIcons.x, size: 20, color: DP.muted),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                  child: RepaintBoundary(
                    key: _receiptKey,
                    child: Container(
                      color: DP.bg,
                      child: Column(
                        children: [
                          DPSuccessMark(size: 72, failed: _isFailed),
                          const SizedBox(height: 14),
                          Text(title, style: DPText.title.copyWith(fontSize: 20)),
                          const SizedBox(height: 4),
                          Text(subtitle, style: DPText.bodyMuted, textAlign: TextAlign.center),
                          const SizedBox(height: 18),
                          DPCard(
                            margin: EdgeInsets.zero,
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                            child: Column(
                              children: [
                                Text(widget.transactionType.toUpperCase(),
                                    style: DPText.overline.copyWith(color: DP.muted, letterSpacing: 0.8)),
                                const SizedBox(height: 6),
                                Text(_formattedAmount, style: DPText.amount.copyWith(fontSize: 30)),
                                const SizedBox(height: 4),
                                _buildStatusBadge(),
                                const SizedBox(height: 10),
                                if (hasToken) _buildTokenBlock(),
                                ...rows,
                                if (widget.isCommission)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 6, bottom: 8),
                                    child: DPNotice(
                                      'Commission transaction',
                                      icon: DPIcons.sparkles,
                                      margin: EdgeInsets.zero,
                                    ),
                                  ),
                                if (widget.isService)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 6, bottom: 8),
                                    child: DPNotice('Service fee',
                                        kind: DPNoticeKind.info, margin: EdgeInsets.zero),
                                  ),
                              ],
                            ),
                          ),
                          if ((widget.isAdminTransaction || widget.isUserAdmin) && isViewerAdmin)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: DPNotice(
                                widget.isAdminTransaction
                                    ? (widget.adminNote ?? 'Admin transaction')
                                    : 'Admin user',
                                kind: DPNoticeKind.warn,
                                icon: DPIcons.shield,
                                margin: EdgeInsets.zero,
                              ),
                            ),
                          if (widget.isAdminTransaction && isViewerAdmin) _buildAdminActionSection(),
                          if (widget.customMessage != null &&
                              !widget.customMessage!.contains('VTpass'))
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: DPNotice(
                                widget.customMessage!,
                                kind: _isFailed
                                    ? DPNoticeKind.danger
                                    : (_isPending ? DPNoticeKind.warn : DPNoticeKind.success),
                                margin: EdgeInsets.zero,
                              ),
                            ),
                          const SizedBox(height: 14),
                          const DPLogo(height: 18),
                          const SizedBox(height: 6),
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
                      DPButton(
                        label: 'Download certificate',
                        leadingIcon: DPIcons.fileText,
                        kind: DPButtonKind.soft,
                        loading: _isDownloadingCertificate,
                        onPressed: _isDownloadingCertificate ? null : _downloadCertificate,
                      ),
                      const SizedBox(height: 10),
                    ],
                    DPButton(
                      label: 'Share receipt',
                      icon: DPIcons.share2,
                      loading: _isSharing,
                      onPressed: _isSharing ? null : _shareReceipt,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DPButton.secondary(
                            label: _isSaving ? 'Saving…' : 'Save',
                            leadingIcon: DPIcons.download,
                            onPressed: _isSaving ? null : _saveReceipt,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DPButton.secondary(
                            label: 'Done',
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('Need help? Quote your payment reference.', style: DPText.small),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTokenBlock() {
    final token = widget.electricityToken!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DP.greenSoft,
        borderRadius: BorderRadius.circular(DP.rMd),
      ),
      child: Column(
        children: [
          Text('ELECTRICITY TOKEN', style: DPText.overline),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _isCopyingToken ? null : () => _copyTokenToClipboard(token),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    token,
                    textAlign: TextAlign.center,
                    style: DPText.title.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.4,
                      color: DP.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const DPIcon(DPIcons.copy, size: 16, color: DP.green),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('Tap to copy · Also sent by SMS', style: DPText.small.copyWith(color: DP.green)),
        ],
      ),
    );
  }
}
