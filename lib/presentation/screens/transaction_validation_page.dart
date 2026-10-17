// lib/presentation/screens/transaction_validation/transaction_validation_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:dalabapay/presentation/screens/dashboard/dashboard_screen.dart'
    show DashboardScreen;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../../../core/services/api_service.dart';
import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';

class TransactionValidationPage extends StatefulWidget {
  final String? userId;
  final VoidCallback? onBalanceUpdate;
  final bool isAdmin;
  final String? initialReference;

  const TransactionValidationPage({
    super.key,
    this.userId,
    this.onBalanceUpdate,
    this.isAdmin = false,
    this.initialReference,
  });

  @override
  State<TransactionValidationPage> createState() =>
      _TransactionValidationPageState();
}

class _TransactionValidationPageState extends State<TransactionValidationPage>
    with SingleTickerProviderStateMixin {
  // ==================== BRAND COLORS ====================
  static const Color primaryColor = Color(0xFF243889);
  static const Color secondaryColor = Color(0xFF219C7E);
  static const Color successColor = Color(0xFF219C7E);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color infoColor = Color(0xFF3B82F6);
  static const Color textPrimary = Color(0xFF1C2D5A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color backgroundLight = Color(0xFFF8FAFC);

  // ==================== CONTROLLERS ====================
  final TextEditingController _referenceController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // ==================== STATE ====================
  bool _isLoading = false;
  bool _isVerifying = false;
  bool _isAdmin = false;
  bool _isSuperAdmin = false;
  String _currentUserRole = 'user';
  String _currentUserId = '';
  String _currentUserName = '';
  String _currentUserEmail = '';

  int _verificationAttempts = 0;
  Timer? _pollingTimer;
  String _currentStatus = '';
  bool _isCopied = false;

  // Animation
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Transaction History
  List<Map<String, dynamic>> _recentTransactions = [];
  bool _isLoadingHistory = false;

  // Stats
  int _totalVerified = 0;
  int _totalPending = 0;
  int _totalFailed = 0;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadCurrentUser();
    _loadRecentTransactions();

    if (widget.initialReference != null &&
        widget.initialReference!.isNotEmpty) {
      _referenceController.text = widget.initialReference!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _validateTransaction();
      });
    }
  }

  @override
  void dispose() {
    _referenceController.dispose();
    _pollingTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  // ==================== USER LOADING ====================

  Future<void> _loadCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user');
      if (userDataString != null) {
        final userData = jsonDecode(userDataString);

        // Get fresh user role from RBAC API
        try {
          final roleResult = await ApiService.getUserRole();
          if (roleResult['success'] == true) {
            final data = roleResult['data'];
            final userRole = data?['role'] ?? 'user';
            final isAdmin =
                data?['isAdmin'] == true ||
                userRole == 'admin' ||
                userRole == 'super_admin';
            final isSuperAdmin =
                data?['isSuperAdmin'] == true || userRole == 'super_admin';

            setState(() {
              _currentUserId = userData['_id']?.toString() ?? '';
              _currentUserName = userData['fullName'] ?? 'Unknown User';
              _currentUserEmail = userData['email'] ?? 'No Email';
              _currentUserRole = userRole;
              _isAdmin = isAdmin;
              _isSuperAdmin = isSuperAdmin;
            });

            await prefs.setString('role', userRole);
            await prefs.setBool('isAdmin', isAdmin);
            await prefs.setBool('isSuperAdmin', isSuperAdmin);
          } else {
            _loadCurrentUserFromCache(userData);
          }
        } catch (e) {
          debugPrint('⚠️ Could not fetch role from backend: $e');
          _loadCurrentUserFromCache(userData);
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading current user: $e');
    }
  }

  void _loadCurrentUserFromCache(Map<String, dynamic> userData) {
    setState(() {
      _currentUserId = userData['_id']?.toString() ?? '';
      _currentUserName = userData['fullName'] ?? 'Unknown User';
      _currentUserEmail = userData['email'] ?? 'No Email';
      _isAdmin = userData['isAdmin'] == true;
      _isSuperAdmin = false;
      _currentUserRole = _isAdmin ? 'admin' : 'user';
    });
  }

  // ==================== TRANSACTION HISTORY ====================

  Future<void> _loadRecentTransactions() async {
    setState(() => _isLoadingHistory = true);
    try {
      final transactions = await ApiService.getTransactions();
      if (transactions.isNotEmpty) {
        // Count ALL transactions for stats
        final allTransactions =
            transactions.map((tx) {
              final status = tx['status']?.toString() ?? 'Unknown';
              return {
                'reference':
                    tx['reference']?.toString() ??
                    tx['transactionId']?.toString() ??
                    'N/A',
                'amount': tx['amount']?.toDouble() ?? 0.0,
                'status': status,
                'type': tx['type']?.toString() ?? 'Transaction',
                'createdAt':
                    tx['createdAt']?.toString() ??
                    DateTime.now().toIso8601String(),
              };
            }).toList();

        // Calculate stats from ALL transactions
        _totalVerified =
            allTransactions
                .where(
                  (t) =>
                      t['status'] == 'Successful' || t['status'] == 'Completed',
                )
                .length;
        _totalPending =
            allTransactions
                .where(
                  (t) =>
                      t['status'] == 'Pending' || t['status'] == 'Processing',
                )
                .length;
        _totalFailed =
            allTransactions.where((t) => t['status'] == 'Failed').length;

        // Only show last 5 in the list
        setState(() {
          _recentTransactions = allTransactions.take(5).toList();
        });

        _log(
          '📊 Stats updated: Verified: $_totalVerified, Pending: $_totalPending, Failed: $_totalFailed',
        );
      }
    } catch (e) {
      debugPrint('❌ Error loading recent transactions: $e');
    } finally {
      setState(() => _isLoadingHistory = false);
    }
  }

  // ==================== TRANSACTION VALIDATION ====================

  void _copyReference() {
    final reference = _referenceController.text.trim();
    if (reference.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: reference));
      setState(() => _isCopied = true);
      _showSnackBar('Reference copied!', false);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isCopied = false);
      });
    }
  }

  Future<void> _validateTransaction() async {
    if (!_formKey.currentState!.validate()) return;

    final reference = _referenceController.text.trim();

    // Check if user has permission to validate transactions
    if (!_isAdmin && !_isSuperAdmin) {
      final hasPermission = await ApiService.hasPermission('view_transactions');
      if (!hasPermission) {
        _showSnackBar(
          'You don\'t have permission to validate transactions',
          true,
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _isVerifying = true;
      _verificationAttempts = 0;
      _currentStatus = '🔍 Checking transaction status...';
    });

    // Try searching by reference first, then by transaction ID
    await _checkTransactionStatus(reference);
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('🔍 TRANSACTION VALIDATION: $message');
    }
  }

  Future<void> _checkTransactionStatus(String query) async {
    try {
      _log('🔍 Checking transaction: $query');

      // Use PaymentService to check the transaction
      // First, try to get transaction from main backend via ApiService
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      // Try main backend first
      var response = await http
          .get(
            Uri.parse(
              'https://vtpass-backend.onrender.com/api/transactions/check-reference/$query',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 10));

      // If not found, try virtual account backend
      if (response.statusCode != 200 || !json.decode(response.body)['exists']) {
        response = await http
            .get(
              Uri.parse(
                'https://virtual-account-backend.onrender.com/api/transactions/check-status?reference=$query',
              ),
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(const Duration(seconds: 10));
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final exists = data['exists'] == true || data['success'] == true;

        if (exists) {
          final transaction = data['transaction'] ?? data['data'] ?? data;
          final amount = transaction['amount']?.toDouble() ?? 0;
          final status = transaction['status']?.toString() ?? 'Unknown';

          _pollingTimer?.cancel();
          setState(() {
            _isLoading = false;
            _isVerifying = false;
          });

          if (status.toLowerCase() == 'successful' ||
              status.toLowerCase() == 'completed' ||
              status.toLowerCase() == 'delivered') {
            _showAlreadyProcessedDialog(query, amount);
          } else if (status.toLowerCase() == 'pending' ||
              status.toLowerCase() == 'processing') {
            _showPendingTransactionDialog(query, amount);
          } else {
            _showNotFoundDialog(query);
          }
          return;
        }
      }

      _startPolling(query);
    } catch (e) {
      debugPrint('❌ Status check error: $e');
      _startPolling(query);
    }
  }

  Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('token');
    } catch (e) {
      _log('❌ Error getting token: $e');
      return null;
    }
  }

  void _startPolling(String query) {
    _pollingTimer?.cancel();

    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      _verificationAttempts++;

      try {
        // Use ApiService for main backend
        var response = await ApiService.authenticatedGet(
          '/api/transactions/check-reference/$query',
        );

        if (response['success'] == true && response['exists'] == true) {
          timer.cancel();
          _handleTransactionResult(query, response);
          return;
        }

        // Try virtual account backend
        final vaResponse = await http
            .get(
              Uri.parse(
                'https://virtual-account-backend.onrender.com/api/transactions/check-status?reference=$query',
              ),
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(const Duration(seconds: 5));

        if (vaResponse.statusCode == 200) {
          final vaData = json.decode(vaResponse.body);
          if (vaData['success'] == true) {
            timer.cancel();
            _handleTransactionResult(query, vaData);
            return;
          }
        }

        if (_verificationAttempts >= 20) {
          timer.cancel();
          setState(() {
            _isLoading = false;
            _isVerifying = false;
          });
          _showNotFoundDialog(query);
          return;
        }

        setState(() {
          _currentStatus = '⏳ Checking... (${_verificationAttempts * 3}s)';
        });
      } catch (e) {
        if (_verificationAttempts >= 20) {
          timer.cancel();
          setState(() {
            _isLoading = false;
            _isVerifying = false;
          });
          _showNotFoundDialog(query);
        }
      }
    });
  }

  void _handleTransactionResult(String query, Map<String, dynamic> data) {
    _log('📦 Handling transaction result for: $query');

    final transaction = data['transaction'] ?? data['data'] ?? data;
    final amount = transaction['amount']?.toDouble() ?? 0;
    final status = transaction['status']?.toString() ?? 'Unknown';

    _pollingTimer?.cancel();
    setState(() {
      _isLoading = false;
      _isVerifying = false;
    });

    // ✅ Refresh transactions to update stats
    _loadRecentTransactions();

    if (status.toLowerCase() == 'successful' ||
        status.toLowerCase() == 'completed' ||
        status.toLowerCase() == 'delivered') {
      _showAlreadyProcessedDialog(query, amount);
    } else if (status.toLowerCase() == 'pending' ||
        status.toLowerCase() == 'processing') {
      _showPendingTransactionDialog(query, amount);
    } else {
      _showNotFoundDialog(query);
    }
  }

  // ==================== DIALOGS ====================

  void _showAlreadyProcessedDialog(String reference, double amount) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: successColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: successColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Transaction Verified ✅',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDialogDetailRow('Reference', reference),
                const SizedBox(height: 8),
                _buildDialogDetailRow(
                  'Amount',
                  '₦${amount.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 8),
                _buildDialogDetailRow('Status', '✅ Completed'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: successColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: successColor.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: successColor,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This transaction has been verified and credited to your wallet.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx); // ← ONLY CLOSE THE DIALOG, NOT THE PAGE
                  // Clear the reference field for next validation
                  _referenceController.clear();
                  setState(() {
                    _isLoading = false;
                    _isVerifying = false;
                  });
                },
                child: Text(
                  'Verify Another',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx); // ← ONLY CLOSE THE DIALOG
                  // Clear the reference field for next validation
                  _referenceController.clear();
                  setState(() {
                    _isLoading = false;
                    _isVerifying = false;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: successColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'OK',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _showPendingTransactionDialog(String reference, double amount) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: infoColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.pending_rounded,
                    color: infoColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Transaction Pending',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDialogDetailRow('Reference', reference),
                const SizedBox(height: 8),
                _buildDialogDetailRow(
                  'Amount',
                  '₦${amount.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 8),
                _buildDialogDetailRow('Status', '⏳ Pending'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: infoColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: infoColor.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: infoColor,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '⏳ Your payment is still processing.',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No funds have been added to your wallet yet. '
                        'Please wait for the payment to complete.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (Navigator.canPop(context)) {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      // Navigate to a fallback screen
                      Navigator.pushReplacementNamed(context, '/home');
                    }
                  } else {
                    // Navigate to a fallback screen
                    Navigator.pushReplacementNamed(context, '/home');
                  }
                },
                child: Text(
                  'Close',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _contactSupport(reference);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Contact Support',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _showNotFoundDialog(String reference) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: errorColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.error_outline_rounded,
                    color: errorColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Transaction Not Found',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'We could not find this transaction in our system.',
                  style: GoogleFonts.inter(fontSize: 14, color: textSecondary),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: backgroundLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '💡 What to do:',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• Double-check the reference number\n'
                        '• Make sure you completed the payment\n'
                        '• If you just made the payment, wait a few minutes\n'
                        '• Contact support with your transaction receipt',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: textSecondary,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Close',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _contactSupport(reference);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Contact Support',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildDialogDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: textSecondary,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
        ),
      ],
    );
  }

  void _contactSupport(String reference) {
    final message = Uri.encodeComponent(
      'Hello Support,\n\n'
      'I need assistance with transaction validation.\n'
      'Reference: $reference\n'
      'User ID: ${widget.userId ?? _currentUserId}\n\n'
      'Please help me verify this transaction.\n\n'
      'Thank you.',
    );
    final whatsappUrl = 'https://wa.me/2349039781549?text=$message';
    try {
      launchUrl(Uri.parse(whatsappUrl), mode: LaunchMode.externalApplication);
    } catch (e) {
      _showSnackBar('Please contact support at +234 903 978 1549', false);
    }
  }

  // ==================== UI HELPERS ====================

  void _showSnackBar(String message, bool isError) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? errorColor : secondaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String? _validateReference(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a transaction reference';
    }
    if (!RegExp(r'^[a-zA-Z0-9|]+$').hasMatch(value)) {
      return 'Invalid reference format';
    }
    if (value.length < 8) {
      return 'Reference is too short';
    }
    if (value.length > 50) {
      return 'Reference is too long';
    }
    return null;
  }

  // ==================== DRAWER ====================

  Widget _buildDrawerHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [primaryColor, primaryColor.withOpacity(0.8)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: Colors.white,
                child: Text(
                  _currentUserName.isNotEmpty
                      ? _currentUserName[0].toUpperCase()
                      : 'U',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentUserName.isNotEmpty ? _currentUserName : 'User',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _currentUserEmail.isNotEmpty
                          ? _currentUserEmail
                          : 'user@example.com',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: secondaryColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: secondaryColor.withOpacity(0.3)),
            ),
            child: Text(
              _isSuperAdmin ? 'SUPER ADMIN' : (_isAdmin ? 'ADMIN' : 'USER'),
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: secondaryColor,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<DrawerItem> get _drawerItems => [
    const DrawerItem(
      title: "All Services",
      icon: Icons.apps,
      page: DashboardScreen(),
      isUserOnly: false,
    ),
    const DrawerItem(
      title: "Transaction Validation",
      icon: Icons.verified_user,
      page: SizedBox.shrink(),
      isUserOnly: true,
    ),
    const DrawerItem(
      title: "My Disputes",
      icon: Icons.gavel,
      page: SizedBox.shrink(),
      isUserOnly: true,
    ),
    const DrawerItem(
      title: "App Settings",
      icon: Icons.settings,
      page: SizedBox.shrink(),
    ),
    const DrawerItem(
      title: "Logout",
      icon: Icons.logout,
      page: SizedBox.shrink(),
    ),
  ];

  void _onDrawerItemSelected(DrawerItem item) {
    if (item.title == "Logout") {
      _showLogoutConfirmation();
      return;
    }
    if (item.title == "All Services") {
      if (Navigator.canPop(context)) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          // Navigate to a fallback screen
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        // Navigate to a fallback screen
        Navigator.pushReplacementNamed(context, '/home');
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
      return;
    }
    if (item.title == "Transaction Validation") {
      if (Navigator.canPop(context)) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          // Navigate to a fallback screen
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        // Navigate to a fallback screen
        Navigator.pushReplacementNamed(context, '/home');
      }
      return;
    }
    if (item.title == "My Disputes") {
      if (Navigator.canPop(context)) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          // Navigate to a fallback screen
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        // Navigate to a fallback screen
        Navigator.pushReplacementNamed(context, '/home');
      }
      Navigator.pushNamed(context, '/disputes');
      return;
    }
    if (item.title == "App Settings") {
      if (Navigator.canPop(context)) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          // Navigate to a fallback screen
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        // Navigate to a fallback screen
        Navigator.pushReplacementNamed(context, '/home');
      }
      Navigator.pushNamed(context, '/settings');
      return;
    }
    if (item.page is! SizedBox) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => item.page),
      );
    }
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Logout'),
            content: const Text('Are you sure you want to logout?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      // Navigate to a fallback screen
                      Navigator.pushReplacementNamed(context, '/home');
                    }
                  } else {
                    // Navigate to a fallback screen
                    Navigator.pushReplacementNamed(context, '/home');
                  }
                  Navigator.pushReplacementNamed(context, '/login');
                },
                child: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  // ==================== UI BUILDERS ====================

  Widget _buildHeader() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 16 : 20,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF92D394), Color(0xFF1E377E)],
          stops: [0.06, 0.41],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: secondaryColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: isMobile ? 20 : 24,
                  ),
                ),
              ),
              SizedBox(width: isMobile ? 12 : 16),
              Expanded(
                child: Text(
                  'Transaction Validation',
                  style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: isMobile ? 12 : 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (_isAdmin || _isSuperAdmin)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 10 : 14,
                    vertical: isMobile ? 4 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: successColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'ADMIN',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: isMobile ? 8 : 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: isMobile ? 16 : 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: isMobile ? 56 : 64,
                height: isMobile ? 56 : 64,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.verified_rounded,
                  color: primaryColor,
                  size: isMobile ? 28 : 34,
                ),
              ),
              SizedBox(width: isMobile ? 14 : 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verify Payment',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: isMobile ? 20 : 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: isMobile ? 4 : 6),
                    Text(
                      'Check your transaction status instantly',
                      style: GoogleFonts.inter(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: isMobile ? 12 : 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Stats cards - flexible width
          Expanded(
            child: Wrap(
              spacing: isMobile ? 6 : 12,
              runSpacing: isMobile ? 6 : 12,
              children: [
                _buildStatCard(
                  title: 'Verified',
                  value: '$_totalVerified',
                  icon: HugeIcons.strokeRoundedCheckmarkCircle02,
                  color: successColor,
                  isMobile: isMobile,
                  screenWidth: screenWidth, // ✅ ADD THIS
                ),
                _buildStatCard(
                  title: 'Pending',
                  value: '$_totalPending',
                  icon: HugeIcons.strokeRoundedClock01,
                  color: warningColor,
                  isMobile: isMobile,
                  screenWidth: screenWidth, // ✅ ADD THIS
                ),
                _buildStatCard(
                  title: 'Total',
                  value: '${_totalVerified + _totalPending + _totalFailed}',
                  icon: HugeIcons.strokeRoundedTransaction,
                  color: primaryColor,
                  isMobile: isMobile,
                  screenWidth: screenWidth, // ✅ ADD THIS
                ),
              ],
            ),
          ),
          // Refresh button - fixed width
          Container(
            width: isMobile ? 40 : 48,
            height: isMobile ? 40 : 48,
            margin: const EdgeInsets.only(left: 8),
            child: IconButton(
              onPressed: () {
                _loadRecentTransactions();
                _showSnackBar('Refreshing transactions...', false);
              },
              icon: Icon(
                Icons.refresh_rounded,
                color: primaryColor,
                size: isMobile ? 20 : 24,
              ),
              tooltip: 'Refresh stats',
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required dynamic icon,
    required Color color,
    required bool isMobile,
    required double screenWidth, // ← Required parameter
  }) {
    // Calculate card width based on screen size
    double cardWidth;
    if (screenWidth < 360) {
      cardWidth = (screenWidth - 50) / 3;
    } else if (screenWidth < 400) {
      cardWidth = (screenWidth - 55) / 3;
    } else if (screenWidth < 600) {
      cardWidth = (screenWidth - 60) / 3;
    } else if (screenWidth < 900) {
      cardWidth = 120;
    } else {
      cardWidth = 150;
    }

    if (cardWidth < 80) cardWidth = 80;

    return SizedBox(
      width: cardWidth,
      child: Container(
        padding: EdgeInsets.all(isMobile ? 8 : 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
          border: Border.all(color: color.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 4 : 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: HugeIcon(
                icon: icon,
                color: color,
                size: isMobile ? 14 : 16,
              ),
            ),
            SizedBox(width: isMobile ? 6 : 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: GoogleFonts.poppins(
                      fontSize: isMobile ? 14 : 18,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 8 : 10,
                      color: textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 8),
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedReceiptText,
                  color: primaryColor,
                  size: isMobile ? 18 : 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Transaction Reference',
                  style: GoogleFonts.poppins(
                    fontSize: isMobile ? 14 : 16,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                const Spacer(),
                if (_referenceController.text.isNotEmpty)
                  GestureDetector(
                    onTap: _copyReference,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 8 : 12,
                        vertical: isMobile ? 4 : 6,
                      ),
                      decoration: BoxDecoration(
                        color:
                            _isCopied
                                ? successColor.withOpacity(0.1)
                                : primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isCopied
                                ? Icons.check_rounded
                                : Icons.copy_rounded,
                            size: isMobile ? 14 : 16,
                            color: _isCopied ? successColor : primaryColor,
                          ),
                          if (!isMobile) ...[
                            const SizedBox(width: 4),
                            Text(
                              _isCopied ? 'Copied!' : 'Copy',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: _isCopied ? successColor : primaryColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _referenceController,
              validator: _validateReference,
              decoration: InputDecoration(
                hintText: 'Enter transaction reference',
                hintStyle: GoogleFonts.inter(
                  fontSize: isMobile ? 13 : 14,
                  color: Colors.grey.shade400,
                ),
                prefixIcon: Icon(
                  Icons.receipt_long_rounded,
                  color: primaryColor,
                  size: isMobile ? 20 : 22,
                ),
                suffixIcon:
                    _referenceController.text.isNotEmpty
                        ? IconButton(
                          icon: Icon(
                            Icons.clear_rounded,
                            size: isMobile ? 18 : 20,
                            color: Colors.grey.shade400,
                          ),
                          onPressed: () => _referenceController.clear(),
                        )
                        : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: primaryColor, width: 1.5),
                ),
                filled: true,
                fillColor: backgroundLight,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 12 : 16,
                  vertical: isMobile ? 12 : 14,
                ),
              ),
              style: GoogleFonts.inter(
                fontSize: isMobile ? 14 : 15,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(isMobile ? 10 : 12),
              decoration: BoxDecoration(
                color: infoColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: infoColor.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: infoColor,
                    size: isMobile ? 16 : 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Enter your transaction reference code',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 11 : 12,
                            color: textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Examples: 17764011904836a721458 or MNFY|82|20260807224750|016416',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 10 : 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: isMobile ? 48 : 54,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _validateTransaction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child:
                    _isLoading
                        ? SizedBox(
                          width: 22,
                          height: 22,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                        : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.verified_rounded,
                              size: isMobile ? 18 : 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Verify Transaction',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 14 : 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationStatus() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 8),
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: infoColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
        border: Border.all(color: infoColor.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          SizedBox(
            width: isMobile ? 40 : 48,
            height: isMobile ? 40 : 48,
            child: const CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(infoColor),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _currentStatus,
            style: GoogleFonts.inter(
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.w600,
              color: infoColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Checking database for transaction...',
            style: GoogleFonts.inter(
              fontSize: isMobile ? 11 : 12,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_verificationAttempts / 20).clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade200,
              color: infoColor,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_verificationAttempts * 3}s elapsed',
            style: GoogleFonts.inter(
              fontSize: isMobile ? 10 : 11,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTransactions() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 8),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedTransaction,
                color: primaryColor,
                size: isMobile ? 18 : 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Recent Transactions',
                style: GoogleFonts.poppins(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const Spacer(),
              if (_recentTransactions.isNotEmpty)
                TextButton(
                  onPressed: () {
                    // Refresh transactions before navigating
                    _loadRecentTransactions();
                    Navigator.pushNamed(context, '/transactions');
                  },
                  child: Text(
                    'View All',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 11 : 12,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingHistory)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_recentTransactions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedTransaction,
                      color: Colors.grey.shade300,
                      size: 40,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No recent transactions',
                      style: GoogleFonts.inter(
                        color: textSecondary,
                        fontSize: isMobile ? 13 : 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _recentTransactions.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final tx = _recentTransactions[index];
                final isSuccess = tx['status'] == 'Successful';
                final statusColor = isSuccess ? successColor : warningColor;
                final statusIcon =
                    isSuccess
                        ? Icons.check_circle_rounded
                        : Icons.pending_rounded;

                return Padding(
                  padding: EdgeInsets.symmetric(vertical: isMobile ? 8 : 10),
                  child: Row(
                    children: [
                      Container(
                        width: isMobile ? 36 : 40,
                        height: isMobile ? 36 : 40,
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          statusIcon,
                          color: statusColor,
                          size: isMobile ? 18 : 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tx['type'] ?? 'Transaction',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: isMobile ? 13 : 14,
                                color: textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              tx['reference'] ?? 'N/A',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 10 : 11,
                                color: textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    tx['status'] ?? 'Unknown',
                                    style: GoogleFonts.inter(
                                      fontSize: isMobile ? 8 : 9,
                                      fontWeight: FontWeight.w600,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat(
                                    'MMM dd, HH:mm',
                                  ).format(DateTime.parse(tx['createdAt'])),
                                  style: GoogleFonts.inter(
                                    fontSize: isMobile ? 8 : 9,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₦${(tx['amount'] ?? 0).toStringAsFixed(2)}',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: isMobile ? 13 : 14,
                          color: isSuccess ? successColor : textPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHelpSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 8),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedHelpCircle,
                color: primaryColor,
                size: isMobile ? 18 : 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Need Help?',
                style: GoogleFonts.poppins(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '• Your reference can be found in your transaction receipt\n'
            '• Format: Alphanumeric (e.g., 17764011904836a721485)\n'
            '• Each transaction can only be verified once\n'
            '• For pending transactions, wait a few minutes or contact support',
            style: GoogleFonts.inter(
              fontSize: isMobile ? 11 : 12,
              color: textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _contactSupport(_referenceController.text.trim()),
            child: Container(
              padding: EdgeInsets.all(isMobile ? 10 : 12),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: primaryColor.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.support_agent_rounded,
                    color: primaryColor,
                    size: isMobile ? 18 : 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Contact Support',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 12 : 13,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: primaryColor,
                    size: isMobile ? 14 : 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== MAIN BUILD ====================

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.grey.shade50,
      drawer: CustomDrawer(
        header: _buildDrawerHeader(),
        items: _drawerItems,
        selectedItem: _drawerItems.firstWhere(
          (item) => item.title == "Transaction Validation",
          orElse: () => _drawerItems.first,
        ),
        onItemSelected: _onDrawerItemSelected,
        isAdmin: _isAdmin,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _buildHeader(),
                  _buildStatsSection(),
                  _buildInputSection(),
                  if (_isVerifying) _buildVerificationStatus(),
                  _buildRecentTransactions(),
                  _buildHelpSection(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
            if (_isLoading && !_isVerifying)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Processing...',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
