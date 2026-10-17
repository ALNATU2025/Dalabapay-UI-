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
  static const Color _brandPrimary = Color(0xFF243889);
  static const Color _brandSecondary = Color(0xFF219C7E);
  static const Color _brandLight = Color(0xFF92D394);
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
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        url.length > 80 ? '${url.substring(0, 80)}...' : url,
                        style: GoogleFonts.poppins(
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _brandSecondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showCopySuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _brandSecondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade600,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildStatusBadge() {
    final status = widget.status;
    final statusColor = _statusColor;
    final statusIcon =
        status.toLowerCase().contains('success') ||
                status.toLowerCase().contains('completed')
            ? Icons.check_circle
            : status.toLowerCase().contains('pending') ||
                status.toLowerCase().contains('processing')
            ? Icons.pending
            : status.toLowerCase().contains('failed') ||
                status.toLowerCase().contains('cancelled')
            ? Icons.error
            : Icons.info;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, color: statusColor, size: 16),
          const SizedBox(width: 8),
          Text(
            status.toUpperCase(),
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: statusColor,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    bool highlight = false,
    bool isAmount = false,
    bool showCopyIcon = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight:
                          highlight || isAmount
                              ? FontWeight.bold
                              : FontWeight.normal,
                      color:
                          highlight
                              ? _brandPrimary
                              : isAmount
                              ? _brandSecondary
                              : Colors.grey.shade900,
                    ),
                  ),
                ),
                if (showCopyIcon &&
                    value.isNotEmpty &&
                    value != 'N/A' &&
                    value != 'Check SMS') ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _copyTokenToClipboard(value),
                    child: Icon(
                      Icons.content_copy_rounded,
                      size: 14,
                      color: _brandPrimary.withOpacity(0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(color: Colors.grey.shade200, height: 8, thickness: 0.5);
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
                  color: Color(0xFFB45309),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'ADMIN ACTION DETAILS',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFB45309),
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
          child: Icon(icon, size: 14, color: const Color(0xFFB45309)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFB45309),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: GoogleFonts.poppins(
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
                          color: Color(0xFFB45309),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isMobile = screenWidth < 600;
    final operator = _detectedOperator;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(isMobile ? 8 : 12),
      child: RepaintBoundary(
        key: _receiptKey,
        child: Container(
          width: screenWidth * (isMobile ? 0.92 : 0.8),
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: screenHeight * 0.85,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                spreadRadius: 1,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with gradient
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_brandPrimary, Color(0xFF1A2E6E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.asset(
                                  'assets/dalabapay2.png',
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.receipt_long,
                                      color: _brandPrimary,
                                      size: 30,
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Dalabapay',
                                  style: GoogleFonts.poppins(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  'Transaction Receipt',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: Colors.white.withOpacity(0.85),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            _buildStatusBadge(),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 12,
                              color: Colors.white.withOpacity(0.7),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _formattedDate,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.85),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                            ),
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Scrollable Content
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Amount Section
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _brandSecondary.withOpacity(0.08),
                              _brandLight.withOpacity(0.05),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _brandSecondary.withOpacity(0.15),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Amount',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formattedAmount,
                              style: GoogleFonts.poppins(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: _brandSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              alignment: WrapAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _brandPrimary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: _brandPrimary.withOpacity(0.15),
                                    ),
                                  ),
                                  child: Text(
                                    widget.transactionType.toUpperCase(),
                                    style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _brandPrimary,
                                    ),
                                  ),
                                ),
                                if (operator != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _operatorColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: _operatorColor.withOpacity(0.2),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.sim_card,
                                          size: 12,
                                          color: _operatorColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          operator,
                                          style: GoogleFonts.poppins(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: _operatorColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Transaction Details
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            _buildDetailRow(
                              'Transaction ID',
                              widget.transactionId,
                              highlight: true,
                              showCopyIcon: true,
                            ),
                            _buildDivider(),
                            _buildDetailRow(
                              'Reference',
                              widget.reference,
                              showCopyIcon: true,
                            ),
                            _buildDivider(),
                            if (widget.gateway != null &&
                                widget.gateway!.isNotEmpty) ...[
                              _buildDetailRow('Gateway', widget.gateway!),
                              _buildDivider(),
                            ],
                            if (widget.description != null &&
                                widget.description!.isNotEmpty) ...[
                              _buildDetailRow(
                                'Description',
                                widget.description!,
                              ),
                              _buildDivider(),
                            ],
                            if (widget.phoneNumber != null &&
                                widget.phoneNumber!.isNotEmpty) ...[
                              _buildDetailRow(
                                'Phone Number',
                                widget.phoneNumber!,
                                showCopyIcon: true,
                              ),
                              _buildDivider(),
                            ],
                            if (widget.smartcardNumber != null &&
                                widget.smartcardNumber!.isNotEmpty) ...[
                              _buildDetailRow(
                                'Smartcard Number',
                                widget.smartcardNumber!,
                                showCopyIcon: true,
                              ),
                              _buildDivider(),
                            ],
                            if (widget.meterNumber != null &&
                                widget.meterNumber!.isNotEmpty) ...[
                              _buildDetailRow(
                                'Meter Number',
                                widget.meterNumber!,
                                showCopyIcon: true,
                              ),
                              _buildDivider(),
                            ],

                            // Electricity Token
                            if (widget.electricityToken != null &&
                                widget.electricityToken!.isNotEmpty &&
                                widget.electricityToken != 'Check SMS' &&
                                widget.electricityToken != 'N/A' &&
                                widget.transactionType.toLowerCase().contains(
                                  'electricity',
                                )) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.orange.shade200,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '⚡ ELECTRICITY TOKEN',
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange.shade800,
                                          ),
                                        ),
                                        InkWell(
                                          onTap:
                                              _isCopyingToken
                                                  ? null
                                                  : () => _copyTokenToClipboard(
                                                    widget.electricityToken!,
                                                  ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: Colors.orange.shade300,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                _isCopyingToken
                                                    ? SizedBox(
                                                      width: 12,
                                                      height: 12,
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        valueColor:
                                                            AlwaysStoppedAnimation<
                                                              Color
                                                            >(
                                                              Colors
                                                                  .orange
                                                                  .shade700,
                                                            ),
                                                      ),
                                                    )
                                                    : Icon(
                                                      Icons
                                                          .content_copy_rounded,
                                                      size: 14,
                                                      color:
                                                          Colors
                                                              .orange
                                                              .shade700,
                                                    ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _isCopyingToken
                                                      ? 'Copying...'
                                                      : 'Copy',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        Colors.orange.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    GestureDetector(
                                      onTap:
                                          () => _copyTokenToClipboard(
                                            widget.electricityToken!,
                                          ),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.orange.shade200,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                widget.electricityToken!,
                                                style: GoogleFonts.poppins(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.grey.shade900,
                                                  letterSpacing: 1.5,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                            Icon(
                                              Icons.content_copy_rounded,
                                              size: 18,
                                              color: Colors.orange.shade600,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Tap token to copy • Also sent via SMS',
                                      style: GoogleFonts.poppins(
                                        fontSize: 9,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _buildDivider(),
                            ],

                            if (widget.customerName != null &&
                                widget.customerName!.isNotEmpty &&
                                widget.customerName != 'N/A' &&
                                widget.transactionType.toLowerCase().contains(
                                  'electricity',
                                )) ...[
                              _buildDetailRow(
                                'Customer Name',
                                widget.customerName!,
                                showCopyIcon: true,
                              ),
                              _buildDivider(),
                            ],

                            if (widget.customerAddress != null &&
                                widget.customerAddress!.isNotEmpty &&
                                widget.customerAddress != 'N/A' &&
                                widget.transactionType.toLowerCase().contains(
                                  'electricity',
                                )) ...[
                              _buildDetailRow(
                                'Customer Address',
                                widget.customerAddress!,
                                showCopyIcon: true,
                              ),
                              _buildDivider(),
                            ],

                            if (widget.packageVariationCode != null &&
                                widget.packageVariationCode!.isNotEmpty &&
                                widget.packageVariationCode != 'N/A') ...[
                              _buildDetailRow(
                                'Package',
                                widget.packageVariationCode!,
                                showCopyIcon: true,
                              ),
                              _buildDivider(),
                            ],

                            if (widget.isCommission &&
                                widget.commissionSource != null &&
                                widget.commissionSource!.isNotEmpty) ...[
                              _buildDetailRow(
                                'Commission Source',
                                widget.commissionSource!,
                              ),
                              _buildDivider(),
                            ],

                            // Balance Before
                            if ((widget.transactionType == 'Fund Wallet' ||
                                    widget.transactionType ==
                                        'Wallet Funding') &&
                                widget.balanceBefore != null &&
                                widget.balanceBefore!.isNotEmpty &&
                                widget.balanceBefore != 'N/A' &&
                                double.tryParse(widget.balanceBefore!) !=
                                    null) ...[
                              _buildDetailRow(
                                'Previous Balance',
                                '₦${double.parse(widget.balanceBefore!).toStringAsFixed(2)}',
                              ),
                              _buildDivider(),
                            ] else if (widget.balanceBefore != null &&
                                widget.balanceBefore!.isNotEmpty &&
                                widget.balanceBefore != 'N/A') ...[
                              _buildDetailRow(
                                'Previous Balance',
                                '₦${widget.balanceBefore}',
                              ),
                              _buildDivider(),
                            ],

                            _buildDetailRow(
                              'Transaction Amount',
                              _formattedAmount,
                              isAmount: true,
                            ),

                            // New Balance
                            if ((widget.transactionType == 'Fund Wallet' ||
                                    widget.transactionType ==
                                        'Wallet Funding') &&
                                widget.balanceAfter != null &&
                                widget.balanceAfter!.isNotEmpty &&
                                widget.balanceAfter != 'N/A' &&
                                double.tryParse(widget.balanceAfter!) !=
                                    null) ...[
                              _buildDivider(),
                              _buildDetailRow(
                                'New Balance',
                                '₦${double.parse(widget.balanceAfter!).toStringAsFixed(2)}',
                                isAmount: true,
                              ),
                            ] else if (widget.balanceAfter != null &&
                                widget.balanceAfter!.isNotEmpty &&
                                widget.balanceAfter != 'N/A') ...[
                              _buildDivider(),
                              _buildDetailRow(
                                'New Balance',
                                '₦${widget.balanceAfter}',
                                isAmount: true,
                              ),
                            ],

                            // Admin Section — ONLY shown to confirmed admin viewers
                            if ((widget.isUserAdmin ||
                                    widget.isAdminTransaction) &&
                                _isViewerAdminLoaded &&
                                _isViewerAdmin) ...[
                              _buildDivider(),
                              if (widget.customerName != null &&
                                  widget.customerName!.isNotEmpty &&
                                  widget.customerName != 'Unknown User' &&
                                  widget.customerName != 'N/A')
                                _buildDetailRow(
                                  'User Name',
                                  widget.customerName!,
                                  highlight: true,
                                  showCopyIcon: true,
                                ),
                              if (widget.customerAddress != null &&
                                  widget.customerAddress!.isNotEmpty &&
                                  widget.customerAddress != 'No Email' &&
                                  widget.customerAddress != 'N/A')
                                _buildDetailRow(
                                  'User Email',
                                  widget.customerAddress!,
                                  showCopyIcon: true,
                                ),
                              if (widget.customerPhone != null &&
                                  widget.customerPhone!.isNotEmpty &&
                                  widget.customerPhone != 'No Phone' &&
                                  widget.customerPhone != 'N/A')
                                _buildDetailRow(
                                  'User Phone',
                                  widget.customerPhone!,
                                  showCopyIcon: true,
                                ),
                              if (widget.customerUserId != null &&
                                  widget.customerUserId!.isNotEmpty &&
                                  widget.customerUserId != 'No ID' &&
                                  widget.customerUserId != 'N/A')
                                _buildDetailRow(
                                  'User ID',
                                  widget.customerUserId!,
                                  showCopyIcon: true,
                                ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Admin Badge — ONLY shown to confirmed admin viewers
                      if ((widget.isAdminTransaction || widget.isUserAdmin) &&
                          _isViewerAdminLoaded &&
                          _isViewerAdmin)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                widget.isAdminTransaction
                                    ? Icons.shield
                                    : Icons.verified_user,
                                color: Colors.amber.shade700,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.isAdminTransaction
                                          ? (widget.adminNote ??
                                              '🔧 ADMIN TRANSACTION')
                                          : '👑 ADMIN USER',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade800,
                                      ),
                                    ),
                                    if (widget.isAdminTransaction &&
                                        widget.adminNote != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        widget.adminNote!,
                                        style: GoogleFonts.poppins(
                                          fontSize: 10,
                                          color: Colors.amber.shade700,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Commission Badge
                      if (widget.isCommission) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _brandSecondary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _brandSecondary.withOpacity(0.15),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.attach_money,
                                color: _brandSecondary,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Commission Transaction',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: _brandSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Service Fee Badge
                      if (widget.isService) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.design_services,
                                color: Colors.blue.shade700,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Service Fee',
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: Colors.blue.shade800,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // ✅ Admin action details — ONLY shown to confirmed admin viewers
                      if (widget.isAdminTransaction &&
                          _isViewerAdminLoaded &&
                          _isViewerAdmin)
                        _buildAdminActionSection(),

                      // Custom Message - REMOVED "Verified by VTpass" message
                      if (widget.customMessage != null &&
                          !widget.customMessage!.contains('VTpass')) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _statusColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _statusColor.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                widget.status.toLowerCase().contains('success')
                                    ? Icons.check_circle
                                    : Icons.info,
                                size: 16,
                                color: _statusColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.customMessage!,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: _statusColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 8),

                      // Footer
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _brandPrimary.withOpacity(0.05),
                              _brandSecondary.withOpacity(0.05),
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Image.asset(
                              'assets/dalabapay2.png',
                              height: 24,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.receipt_long,
                                  color: _brandPrimary,
                                  size: 24,
                                );
                              },
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Thank you for choosing Dalabapay!',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              '💚 Secure • Fast • Reliable',
                              style: GoogleFonts.poppins(
                                fontSize: 9,
                                color: Colors.grey.shade400,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Action Buttons
              // Action Buttons
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                ),
                child: Column(
                  children: [
                    // ✅ DOWNLOAD CERTIFICATE BUTTON (only for insurance with certificate)
                    if (widget.certificateUrl != null &&
                        widget.certificateUrl!.isNotEmpty &&
                        widget.transactionType.toLowerCase().contains(
                          'insurance',
                        )) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed:
                              _isDownloadingCertificate
                                  ? null
                                  : _downloadCertificate,
                          icon:
                              _isDownloadingCertificate
                                  ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(Icons.picture_as_pdf, size: 18),
                          label: Text(
                            _isDownloadingCertificate
                                ? 'Loading...'
                                : '📄 Download Certificate',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isSaving ? null : _saveReceipt,
                            icon: Icon(
                              _isSaving ? Icons.downloading : Icons.download,
                              size: 16,
                            ),
                            label: Text(
                              _isSaving ? 'Saving...' : 'Save',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _brandSecondary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isSharing ? null : _shareReceipt,
                            icon: Icon(
                              _isSharing ? Icons.share : Icons.share_outlined,
                              size: 16,
                            ),
                            label: Text(
                              _isSharing ? 'Sharing...' : 'Share',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _brandPrimary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          backgroundColor: Colors.grey.shade100,
                        ),
                        child: Text(
                          'Close Receipt',
                          style: GoogleFonts.poppins(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
