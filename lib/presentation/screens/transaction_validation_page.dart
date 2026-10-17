// lib/presentation/screens/transaction_validation/transaction_validation_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:dalabapay/presentation/screens/dashboard/dashboard_screen.dart'
    show DashboardScreen;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../../../core/services/api_service.dart';
import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';
import '../../ui/ui.dart';

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
  static const Color primaryColor = Color(0xFF102C68);
  static const Color secondaryColor = Color(0xFF168566);
  static const Color successColor = Color(0xFF168566);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color infoColor = Color(0xFF3B82F6);
  static const Color textPrimary = Color(0xFF14263D);
  static const Color textSecondary = Color(0xFF728078);
  static const Color backgroundLight = Color(0xFFF8F9F5);

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
                    style: TextStyle(
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
                          style: TextStyle(
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
                  style: TextStyle(
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
                  style: TextStyle(
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
                    style: TextStyle(
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
                              style: TextStyle(
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
                        style: TextStyle(
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
                  style: TextStyle(
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
                  style: TextStyle(
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
                    style: TextStyle(
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
                  style: TextStyle(fontSize: 14, color: textSecondary),
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
                        style: TextStyle(
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
                        style: TextStyle(
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
                  style: TextStyle(
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
                  style: TextStyle(
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
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
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
    if (!mounted) return;
    dpSnack(context, message, error: isError, success: !isError);
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
                      style: TextStyle(
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
                      style: TextStyle(
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
              style: TextStyle(
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(DP.gutter, 8, DP.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DPHeader(
            title: 'Check a payment',
            actionLabel: 'Refresh',
            onAction: _loadRecentTransactions,
          ),
          const SizedBox(height: 4),
          Text('Made a transfer that hasn’t shown up? Enter its reference and we’ll check it.',
              style: DPText.bodyMuted),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    Widget stat(String t, int v, Color c) => Expanded(
          child: DPCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t, style: DPText.small),
                const SizedBox(height: 4),
                Text('$v', style: DPText.title.copyWith(color: c)),
              ],
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(DP.gutter, 16, DP.gutter, 0),
      child: Row(children: [
        stat('Verified', _totalVerified, DP.green),
        const SizedBox(width: 10),
        stat('Pending', _totalPending, DP.warn),
        const SizedBox(width: 10),
        stat('Total', _totalVerified + _totalPending + _totalFailed, DP.ink),
      ]),
    );
  }


  Widget _buildInputSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DP.gutter, 18, DP.gutter, 0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DPFieldLabel('Payment reference'),
            TextFormField(
              controller: _referenceController,
              validator: _validateReference,
              style: DPText.body.copyWith(fontSize: 16),
              decoration: InputDecoration(
                hintText: 'e.g. MNFY|82|20260807224750|016416',
                suffixIcon: _referenceController.text.isNotEmpty
                    ? IconButton(
                        icon: DPIcon(_isCopied ? DPIcons.check : DPIcons.copy, size: 18, color: DP.green),
                        onPressed: _copyReference,
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text('You’ll find it on your bank’s transfer receipt or SMS.', style: DPText.small),
            const SizedBox(height: 16),
            DPButton(
              label: 'Check payment',
              leadingIcon: DPIcons.search,
              loading: _isLoading,
              onPressed: _isLoading ? null : _validateTransaction,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationStatus() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DP.gutter, 16, DP.gutter, 0),
      child: DPCard(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: DP.green),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(_currentStatus, style: DPText.body.copyWith(fontWeight: FontWeight.w500))),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_verificationAttempts / 20).clamp(0.0, 1.0),
                backgroundColor: DP.border,
                color: DP.green,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 8),
            Text('${_verificationAttempts * 3}s · checking with the bank', style: DPText.small),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentTransactions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DP.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DPSectionHeader(
            'Recent top-ups',
            actionLabel: _recentTransactions.isNotEmpty ? 'View all' : null,
            onAction: _recentTransactions.isNotEmpty
                ? () {
                    _loadRecentTransactions();
                    Navigator.pushNamed(context, '/transactions');
                  }
                : null,
          ),
          if (_isLoadingHistory)
            const DPLoader()
          else if (_recentTransactions.isEmpty)
            const DPEmptyState(icon: DPIcons.receipt, title: 'No recent top-ups')
          else
            for (final tx in _recentTransactions)
              Builder(builder: (_) {
                final ok = tx['status'] == 'Successful';
                final amount = ((tx['amount'] ?? 0) as num).toDouble();
                final d = DateTime.tryParse(tx['createdAt']?.toString() ?? '');
                return DPTransactionTile(
                  icon: ok ? DPIcons.arrowDownLeft : DPIcons.hourglass,
                  title: (tx['type'] ?? 'Transaction').toString(),
                  subtitle: [
                    if (d != null) DateFormat('d MMM, h:mm a').format(d.toLocal()),
                    (tx['status'] ?? 'Unknown').toString(),
                  ].join(' · '),
                  amount: dpNaira(amount),
                  credit: ok,
                );
              }),
        ],
      ),
    );
  }

  Widget _buildHelpSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DP.gutter, 8, DP.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DPSectionHeader('Good to know'),
          DPCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final t in const [
                  'Your reference is on the transfer receipt from your bank.',
                  'Each payment can only be checked and credited once.',
                  'If it’s still pending, give it a few minutes before contacting us.',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: DPIcon(DPIcons.check, size: 15, color: DP.green),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(t, style: DPText.bodyMuted.copyWith(fontSize: 13.5))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          DPMenuRow(
            icon: DPIcons.headset,
            title: 'Contact support',
            subtitle: 'We’ll check it for you',
            onTap: () => _contactSupport(_referenceController.text.trim()),
          ),
        ],
      ),
    );
  }

  // ==================== MAIN BUILD ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: DP.bg,
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
            if (_isLoading && !_isVerifying) const DPBusyOverlay(message: 'Checking…'),
          ],
        ),
      ),
    );
  }
}
