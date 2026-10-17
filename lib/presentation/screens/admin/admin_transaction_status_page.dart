// lib/presentation/screens/admin/admin_transaction_status_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/receipt_widget.dart';
import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';
import '../dashboard/dashboard_screen.dart';

class AdminTransactionStatusPage extends StatefulWidget {
  const AdminTransactionStatusPage({super.key});

  @override
  State<AdminTransactionStatusPage> createState() =>
      _AdminTransactionStatusPageState();
}

class _AdminTransactionStatusPageState extends State<AdminTransactionStatusPage>
    with SingleTickerProviderStateMixin {
  // ==================== BRAND COLORS ====================
  static const Color primaryColor = Color(0xFF243889);
  static const Color secondaryColor = Color(0xFF219C7E);
  static const Color successColor = Color(0xFF219C7E);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color textPrimary = Color(0xFF1C2D5A);
  static const Color textSecondary = Color(0xFF64748B);
  // ignore: unused_field
  static const Color backgroundLight = Color(0xFFF8FAFC);

  // ==================== STATE ====================
  List<dynamic> _transactions = [];
  List<dynamic> _filteredTransactions = [];
  Map<String, dynamic>? _selectedTransaction;
  List<dynamic> _disputes = [];
  List<dynamic> _receipts = [];
  bool _isLoading = true;
  bool _isDetailsLoading = false;
  bool _isAdmin = false;
  bool _isInitialLoad = true;
  static const Duration _cacheDuration = Duration(minutes: 5);

  String? _errorMessage;
  String _selectedFilter = 'all';
  String _searchQuery = '';
  String _selectedNewStatus = 'Successful';

  // Stats
  int _pendingCount = 0;
  int _failedCount = 0;
  int _successfulCount = 0;
  int _refundedCount = 0;
  int _disputedCount = 0;
  double _totalPendingAmount = 0;

  // Controllers
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _adminNoteController = TextEditingController();
  final TextEditingController _fundAmountController = TextEditingController();
  final TextEditingController _fundNoteController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  // Animation
  // Animation
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadInitialData();

    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          _searchQuery = _searchController.text;
          _applyFilters();
        }
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _adminNoteController.dispose();
    _fundAmountController.dispose();
    _fundNoteController.dispose();
    _animationController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _showUnlockInstructions(Map<String, dynamic> transaction) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final hasDispute = _disputes.any(
      (d) => d['status'] == 'pending' || d['status'] == 'under_review',
    );
    final hasPendingRefund = transaction['hasPendingRefund'] == true;

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedLock,
                  color: Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  'Transaction Locked',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This transaction is locked and cannot be updated until the following issues are resolved:',
                  style: GoogleFonts.inter(fontSize: 14, color: textPrimary),
                ),
                const SizedBox(height: 16),

                // Dispute Status
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        hasDispute
                            ? errorColor.withValues(alpha: 0.08)
                            : successColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color:
                          hasDispute
                              ? errorColor.withValues(alpha: 0.2)
                              : successColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      HugeIcon(
                        icon:
                            hasDispute
                                ? HugeIcons.strokeRoundedAlert02
                                : HugeIcons.strokeRoundedCheckmarkCircle01,
                        color: hasDispute ? errorColor : successColor,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          hasDispute
                              ? '⚠️ Active Dispute(s) Found - Must be resolved first'
                              : '✅ No active disputes',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: hasDispute ? errorColor : successColor,
                            fontWeight:
                                hasDispute ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Refund Status
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        hasPendingRefund
                            ? errorColor.withValues(alpha: 0.08)
                            : successColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color:
                          hasPendingRefund
                              ? errorColor.withValues(alpha: 0.2)
                              : successColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      HugeIcon(
                        icon:
                            hasPendingRefund
                                ? HugeIcons.strokeRoundedAlert02
                                : HugeIcons.strokeRoundedCheckmarkCircle01,
                        color: hasPendingRefund ? errorColor : successColor,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          hasPendingRefund
                              ? '⚠️ Pending Refund Request - Must be completed first'
                              : '✅ No pending refunds',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: hasPendingRefund ? errorColor : successColor,
                            fontWeight:
                                hasPendingRefund
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Instructions
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📋 How to Unlock:',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (hasDispute)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '• ',
                                style: GoogleFonts.inter(color: textSecondary),
                              ),
                              Expanded(
                                child: Text(
                                  'Go to Refund System → Disputes → Resolve the dispute',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (hasPendingRefund)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '• ',
                                style: GoogleFonts.inter(color: textSecondary),
                              ),
                              Expanded(
                                child: Text(
                                  'Go to Refund System → Process/Complete the refund',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (!hasDispute && !hasPendingRefund)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '• ',
                                style: GoogleFonts.inter(color: textSecondary),
                              ),
                              Expanded(
                                child: Text(
                                  'No issues found. If still locked, contact backend support.',
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
                ),

                const SizedBox(height: 16),

                // Transaction Reference
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedReceiptText,
                        color: textSecondary,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'TX: ${transaction['reference']?.toString() ?? 'N/A'}',
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
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Close',
                  style: GoogleFonts.inter(
                    color: textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hasDispute || hasPendingRefund)
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    // Navigate to Refund System
                    _navigateToRefundSystem();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Go to Refund System',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
    );
  }

  void _navigateToRefundSystem() {
    // Navigate to Refund System page
    // Replace with your actual navigation
    Navigator.pushNamed(context, '/admin/refund-system');
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
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
  }

  // ==================== DATA LOADING ====================

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      final cachedData = prefs.getString('cached_transaction_status');
      if (cachedData != null && _isInitialLoad) {
        try {
          final cached = jsonDecode(cachedData);
          final cacheTime = DateTime.parse(cached['timestamp']);
          if (DateTime.now().difference(cacheTime) < _cacheDuration) {
            setState(() {
              _transactions = cached['transactions'];
              _pendingCount = cached['pendingCount'] ?? 0;
              _failedCount = cached['failedCount'] ?? 0;
              _totalPendingAmount = cached['totalPendingAmount'] ?? 0;
              _applyFilters();
              _isLoading = false;
            });
            debugPrint(
              '📦 Loaded ${_transactions.length} transactions from cache',
            );
          }
        } catch (e) {
          debugPrint('Cache read error: $e');
        }
      }

      final userDataString = prefs.getString('user');

      if (userDataString != null) {
        final userData = jsonDecode(userDataString);
        final bool isAdmin = userData['isAdmin'] == true;
        final String? userId = userData['_id'];
        const String specificAdminUserId = "690088325ca99bed6ab8d4a5";
        final bool isAdminById = userId == specificAdminUserId;

        setState(() {
          _isAdmin = isAdmin || isAdminById;
        });

        if (_isAdmin) {
          await _fetchTransactions();
          _animationController.forward();
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = "You don't have permission to access this page.";
          });
        }
      } else {
        setState(() {
          _isAdmin = false;
          _isLoading = false;
          _errorMessage = "User data not found. Please log in again.";
        });
      }
    } catch (e) {
      debugPrint("Error loading initial data: $e");
      setState(() {
        _isAdmin = false;
        _isLoading = false;
        _errorMessage = "Error checking permissions: ${e.toString()}";
      });
    }
  }

  Future<void> _fetchTransactions() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _isInitialLoad = false;
      });
    }

    try {
      String backendStatus = 'all';
      switch (_selectedFilter) {
        case 'successful':
          backendStatus = 'successful';
          break;
        case 'pending':
          backendStatus = 'pending';
          break;
        case 'failed':
          backendStatus = 'failed';
          break;
        case 'refunded':
          backendStatus = 'refunded';
          break;
        case 'disputed':
          backendStatus = 'disputed';
          break;
        default:
          backendStatus = 'all';
      }

      final response = await ApiService.getAllTransactionsForAdmin(
        status: backendStatus,
        search: _searchQuery,
        page: 1,
        limit: 500,
      );

      if (response['success'] == true) {
        final stats = response['stats'] as Map<String, dynamic>? ?? {};
        final newTransactions = List<dynamic>.from(
          response['transactions'] ?? [],
        );

        debugPrint('📊 [FETCH] Loaded ${newTransactions.length} transactions');

        if (mounted) {
          setState(() {
            _transactions = newTransactions;
            _pendingCount = (stats['pending'] ?? 0) as int;
            _failedCount = (stats['failed'] ?? 0) as int;
            _successfulCount = (stats['successful'] ?? 0) as int;
            _refundedCount = (stats['refunded'] ?? 0) as int;
            _disputedCount = (stats['disputed'] ?? 0) as int;
            _totalPendingAmount =
                ((stats['totalAmount'] ?? 0) as num).toDouble();
          });
          _applyFilters();

          // ✅ Refresh the currently selected transaction if it exists in the new list
          if (_selectedTransaction != null) {
            final selectedId = _selectedTransaction!['_id']?.toString();
            final found = newTransactions.firstWhere(
              (t) => t['_id']?.toString() == selectedId,
              orElse: () => null,
            );
            if (found != null) {
              setState(() {
                _selectedTransaction = Map<String, dynamic>.from(found);
              });
            }
          }
        }
      } else {
        throw Exception(response['message'] ?? 'Failed to load transactions');
      }
    } catch (e) {
      debugPrint("❌ Error fetching transactions: $e");
      if (mounted) {
        setState(() {
          _errorMessage =
              e.toString().contains('Admin')
                  ? "You don't have permission to access admin features."
                  : "Failed to load transactions: ${e.toString()}";
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadTransactionDetails(String transactionId) async {
    debugPrint('🔍 Loading transaction details for ID: $transactionId');

    setState(() {
      _isDetailsLoading = true;
    });

    try {
      final response = await ApiService.getTransactionDetails(transactionId);
      debugPrint(
        '📦 [LOAD-DETAILS] Response: success=${response['success']} - ${response['message'] ?? 'No message'}',
      );

      if (response['success'] == true && response['transaction'] != null) {
        final txData = Map<String, dynamic>.from(response['transaction']);

        debugPrint(
          '✅ [LOAD-DETAILS] Loaded: ${txData['_id']} | Status: ${txData['status']}',
        );

        if (mounted) {
          setState(() {
            _selectedTransaction = txData;
            _disputes = List<dynamic>.from(response['disputes'] ?? []);
            _receipts = List<dynamic>.from(response['receipts'] ?? []);
          });

          // Also update the list item so the UI reflects new status
          final listIndex = _transactions.indexWhere(
            (t) => t['_id']?.toString() == txData['_id']?.toString(),
          );
          if (listIndex != -1) {
            setState(() {
              _transactions[listIndex] = txData;
            });
            _applyFilters();
          }
        }
      } else {
        debugPrint('❌ [LOAD-DETAILS] Failed: ${response['message']}');
        if (mounted) {
          _showSnackBar(
            response['message'] ?? 'Failed to load transaction details',
            true,
          );
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [LOAD-DETAILS] Error: $e');
      debugPrint('   Stack: $stackTrace');
      if (mounted) {
        _showSnackBar('Error loading details: $e', true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDetailsLoading = false;
        });
      }
    }
  }

  void _applyFilters() {
    List<dynamic> filtered = List.from(_transactions);

    if (_selectedFilter != 'all') {
      filtered =
          filtered.where((tx) {
            final status = tx['status']?.toString().toLowerCase() ?? '';

            switch (_selectedFilter) {
              case 'successful':
                return status == 'successful' ||
                    status == 'success' ||
                    status == 'completed';
              case 'pending':
                return status == 'pending';
              case 'failed':
                return status == 'failed';
              case 'refunded':
                return status == 'refunded';
              case 'disputed':
                return tx['hasActiveDispute'] == true;
              default:
                return true;
            }
          }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered =
          filtered.where((tx) {
            final user = tx['user'] as Map<String, dynamic>?;
            return (tx['reference']?.toString().toLowerCase().contains(query) ??
                    false) ||
                (user?['fullName']?.toString().toLowerCase().contains(query) ??
                    false) ||
                (user?['email']?.toString().toLowerCase().contains(query) ??
                    false) ||
                (tx['type']?.toString().toLowerCase().contains(query) ?? false);
          }).toList();
    }

    setState(() {
      _filteredTransactions = filtered;
    });
  }

  // ==================== HELPERS ====================

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) return 'Just now';
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('dd/MM/yyyy').format(date);
    }
  }

  Color _getStatusColor(String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus == 'successful' || lowerStatus == 'completed') {
      return successColor;
    }
    if (lowerStatus == 'pending' || lowerStatus == 'processing') {
      return warningColor;
    }
    if (lowerStatus == 'failed') return errorColor;
    if (lowerStatus == 'refunded') return const Color(0xFF8B5CF6);
    return Colors.grey;
  }

  String _getStatusText(String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus == 'successful' || lowerStatus == 'completed') {
      return 'Successful';
    }
    if (lowerStatus == 'pending' || lowerStatus == 'processing') {
      return 'Pending';
    }
    if (lowerStatus == 'failed') return 'Failed';
    if (lowerStatus == 'refunded') return 'Refunded';
    return status.toUpperCase();
  }

  dynamic _getStatusIcon(String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus == 'successful' || lowerStatus == 'completed') {
      return HugeIcons.strokeRoundedCheckmarkCircle01;
    }
    if (lowerStatus == 'pending' || lowerStatus == 'processing') {
      return HugeIcons.strokeRoundedClock02;
    }
    if (lowerStatus == 'failed') return HugeIcons.strokeRoundedAlert01;
    if (lowerStatus == 'refunded') return HugeIcons.strokeRoundedMoney02;
    return HugeIcons.strokeRoundedCircle;
  }

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
        backgroundColor: isError ? errorColor : successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ==================== DRAWER ====================

  Widget _buildDrawerHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Dalaba',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.09,
                ),
              ),
              Text(
                'pay',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: secondaryColor,
                  letterSpacing: 0.09,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: secondaryColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: secondaryColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              'ADMIN PANEL',
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
      title: "Admin Dashboard",
      icon: Icons.dashboard,
      badge: "ADMIN",
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "All Services",
      icon: Icons.apps,
      page: DashboardScreen(),
      isUserOnly: false,
    ),
    const DrawerItem(
      title: "Manage Users",
      icon: Icons.people_alt,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Transactions",
      icon: Icons.receipt,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Status Update",
      icon: Icons.update,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Refund System",
      icon: Icons.currency_exchange,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Fund Wallet",
      icon: Icons.account_balance_wallet,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "VTpass Settings",
      icon: Icons.api,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Self Fund",
      icon: Icons.attach_money,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Verify Payments",
      icon: Icons.verified,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Notifications",
      icon: Icons.notifications_active,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    const DrawerItem(
      title: "Admin Control",
      icon: Icons.settings_applications,
      page: SizedBox.shrink(),
      isAdminOnly: true,
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

  // ==================== ADMIN HEADER ====================

  Widget _buildAdminHeader() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 16 : 20,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [const Color(0xFF92D394), const Color(0xFF1E377E)],
          stops: const [0.06, 0.41],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: secondaryColor.withValues(alpha: 0.3),
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
                    color: Colors.white.withValues(alpha: 0.15),
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
                  'Admin / Status Update',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: isMobile ? 12 : 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 10 : 14,
                  vertical: isMobile ? 4 : 6,
                ),
                decoration: BoxDecoration(
                  color: secondaryColor,
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
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.update_rounded,
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
                      'Transaction Status',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: isMobile ? 20 : 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: isMobile ? 4 : 6),
                    Text(
                      '${_filteredTransactions.length} pending/failed • ${_pendingCount + _failedCount} total',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: isMobile ? 12 : 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _fetchTransactions,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.refresh_rounded,
                    color: Colors.white,
                    size: isMobile ? 22 : 26,
                  ),
                ),
                tooltip: 'Refresh',
              ),
            ],
          ),
          SizedBox(height: isMobile ? 16 : 20),

          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 18,
              vertical: isMobile ? 4 : 6,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedSearch01,
                  color: primaryColor.withValues(alpha: 0.5),
                  size: isMobile ? 18 : 22,
                ),
                SizedBox(width: isMobile ? 10 : 14),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText:
                          isMobile
                              ? 'Search transactions...'
                              : 'Search by reference, customer, type...',
                      hintStyle: GoogleFonts.inter(
                        color: primaryColor.withValues(alpha: 0.4),
                        fontSize: isMobile ? 13 : 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: isMobile ? 10 : 14,
                      ),
                    ),
                    style: GoogleFonts.inter(
                      color: primaryColor,
                      fontSize: isMobile ? 14 : 15,
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _searchQuery = '';
                      _applyFilters();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        color: primaryColor.withValues(alpha: 0.5),
                        size: isMobile ? 16 : 18,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== STATS CARD ====================

  Widget _buildStatsCard() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: 16,
      ),
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100, width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  value: _successfulCount.toString(),
                  label: 'Successful',
                  icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                  color: successColor,
                  isMobile: isMobile,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  value: _pendingCount.toString(),
                  label: 'Pending',
                  icon: HugeIcons.strokeRoundedClock02,
                  color: warningColor,
                  isMobile: isMobile,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  value: _failedCount.toString(),
                  label: 'Failed',
                  icon: HugeIcons.strokeRoundedAlert01,
                  color: errorColor,
                  isMobile: isMobile,
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 10 : 14),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  value: _refundedCount.toString(),
                  label: 'Refunded',
                  icon: HugeIcons.strokeRoundedMoney02,
                  color: const Color(0xFF8B5CF6),
                  isMobile: isMobile,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  value: _disputedCount.toString(),
                  label: 'Disputed',
                  icon: HugeIcons.strokeRoundedAlert02,
                  color: Colors.orange,
                  isMobile: isMobile,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  value: _transactions.length.toString(),
                  label: 'Total',
                  icon: HugeIcons.strokeRoundedReceiptText,
                  color: Colors.grey.shade700,
                  isMobile: isMobile,
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 12 : 16),
          _buildFilterChips(isMobile),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required String value,
    required String label,
    required dynamic icon,
    required Color color,
    required bool isMobile,
  }) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(isMobile ? 6 : 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: HugeIcon(icon: icon, color: color, size: isMobile ? 18 : 22),
        ),
        SizedBox(height: isMobile ? 4 : 6),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: isMobile ? 14 : 16,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        SizedBox(height: isMobile ? 2 : 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: isMobile ? 9 : 11,
            color: textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips(bool isMobile) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _buildFilterChip('All', 'all', isMobile),
        _buildFilterChip('Successful', 'successful', isMobile),
        _buildFilterChip('Pending', 'pending', isMobile),
        _buildFilterChip('Failed', 'failed', isMobile),
        _buildFilterChip('Refunded', 'refunded', isMobile),
        _buildFilterChip('Disputed', 'disputed', isMobile),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value, bool isMobile) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: isMobile ? 11 : 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? primaryColor : textSecondary,
        ),
      ),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _selectedFilter = value;
          _applyFilters();
        });
      },
      backgroundColor: Colors.white,
      selectedColor: primaryColor.withValues(alpha: 0.08),
      showCheckmark: false,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 12,
        vertical: isMobile ? 4 : 6,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? primaryColor : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
      ),
    );
  }

  // ==================== TRANSACTION LIST ====================

  Widget _buildTransactionList() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (_isLoading) {
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildShimmerCard(isMobile),
            childCount: 6,
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return SliverFillRemaining(child: _buildErrorState());
    }

    if (_filteredTransactions.isEmpty) {
      return SliverFillRemaining(child: _buildEmptyState());
    }

    return SliverPadding(
      padding: EdgeInsets.only(
        left: isMobile ? 16 : 24,
        right: isMobile ? 16 : 24,
        bottom: 24,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final tx = _filteredTransactions[index];
          final isSelected =
              _selectedTransaction != null &&
              _selectedTransaction!['_id'] == tx['_id'];
          return _buildTransactionCard(tx, isSelected, index);
        }, childCount: _filteredTransactions.length),
      ),
    );
  }

  Widget _buildShimmerCard(bool isMobile) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        height: isMobile ? 120 : 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(
    Map<String, dynamic> transaction,
    bool isSelected,
    int index,
  ) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final status = transaction['status']?.toString().toLowerCase() ?? '';
    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0;
    final user = transaction['user'] as Map<String, dynamic>?;
    final reference = transaction['reference']?.toString() ?? 'N/A';
    final createdAt =
        transaction['createdAt'] != null
            ? DateTime.tryParse(transaction['createdAt'].toString())
            : null;
    final canUpdate = transaction['canUpdate'] == true;
    final hasDispute = _disputes.any(
      (d) => d['status'] == 'pending' || d['status'] == 'under_review',
    );
    final statusColor = _getStatusColor(status);

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(position: _slideAnimation, child: child),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color:
              isSelected ? primaryColor.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: isSelected ? primaryColor : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
            onTap: () {
              debugPrint('👆 Tapped transaction: ${transaction['_id']}');
              _openTransactionDialog(transaction);
            },
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 14 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(isMobile ? 8 : 10),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: HugeIcon(
                          icon: _getStatusIcon(status),
                          color: statusColor,
                          size: isMobile ? 18 : 22,
                        ),
                      ),
                      SizedBox(width: isMobile ? 12 : 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              transaction['type']?.toString() ?? 'Transaction',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 14 : 15,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              children: [
                                Text(
                                  'Ref: ${reference.length > 16 ? '${reference.substring(0, 16)}...' : reference}',
                                  style: GoogleFonts.inter(
                                    fontSize: isMobile ? 10 : 11,
                                    color: textSecondary,
                                  ),
                                ),
                                if (hasDispute) ...[
                                  SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'DISPUTE',
                                      style: GoogleFonts.inter(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₦${amount.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 14 : 16,
                              fontWeight: FontWeight.w700,
                              color:
                                  status == 'failed' ? errorColor : textPrimary,
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 6 : 8,
                              vertical: isMobile ? 1 : 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _getStatusText(status),
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 8 : 10,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: isMobile ? 8 : 10),
                  if (user != null)
                    Row(
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedUser,
                          color: textSecondary,
                          size: isMobile ? 12 : 14,
                        ),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            user['fullName']?.toString() ?? 'Unknown User',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 11 : 12,
                              color: textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (createdAt != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(createdAt),
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 10 : 11,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== DETAILS PANEL ====================

  Widget _buildDetailsPanel() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (_selectedTransaction == null) {
      return Container(
        color: Colors.white,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedReceiptText,
                  color: primaryColor,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select a Transaction',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap on a transaction to view details',
                style: GoogleFonts.inter(fontSize: 14, color: textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    if (_isDetailsLoading) {
      return Container(
        color: Colors.white,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading Details...',
                style: GoogleFonts.inter(fontSize: 14, color: textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildDetailsHeader(),
          // ✅ FIX: Remove Expanded, use Flexible instead
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 16 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTransactionInfo(),
                  const SizedBox(height: 16),
                  if (_disputes.isNotEmpty) ...[
                    _buildDisputeSection(),
                    const SizedBox(height: 16),
                  ],
                  if (_receipts.isNotEmpty) ...[
                    _buildReceiptSection(),
                    const SizedBox(height: 16),
                  ],
                  _buildActionButtons(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsHeader() {
    final status = _selectedTransaction?['status']?.toString() ?? 'N/A';
    final statusColor = _getStatusColor(status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => setState(() => _selectedTransaction = null),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Transaction Details',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _selectedTransaction?['reference']?.toString() ?? 'N/A',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HugeIcon(
                  icon: _getStatusIcon(status),
                  color: statusColor,
                  size: 14,
                ),
                SizedBox(width: 4),
                Text(
                  _getStatusText(status),
                  style: GoogleFonts.inter(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionInfo() {
    final tx = _selectedTransaction!;
    final user = tx['user'] as Map<String, dynamic>?;
    final canUpdate = tx['canUpdate'] == true;
    final hasDispute = _disputes.any(
      (d) => d['status'] == 'pending' || d['status'] == 'under_review',
    );
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade100, width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedInformationCircle,
                  color: primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Transaction Information',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              'Type',
              tx['type']?.toString() ?? 'N/A',
              HugeIcons.strokeRoundedTag01,
            ),
            _buildInfoRow(
              'Amount',
              '₦${(tx['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
              HugeIcons.strokeRoundedMoney02,
            ),
            _buildInfoRow(
              'Reference',
              tx['reference']?.toString() ?? 'N/A',
              HugeIcons.strokeRoundedReceiptText,
            ),
            _buildInfoRow(
              'Date',
              tx['createdAt'] != null
                  ? DateFormat(
                    'MMM dd, yyyy HH:mm:ss',
                  ).format(DateTime.parse(tx['createdAt'].toString()))
                  : 'N/A',
              HugeIcons.strokeRoundedCalendar01,
            ),
            _buildInfoRow(
              'Description',
              tx['description']?.toString() ?? 'N/A',
              HugeIcons.strokeRoundedFile01,
            ),
            const Divider(height: 24),
            Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedUser,
                  color: primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Customer Information',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              'Name',
              user?['fullName']?.toString() ?? 'N/A',
              HugeIcons.strokeRoundedUser,
            ),
            _buildInfoRow(
              'Email',
              user?['email']?.toString() ?? 'N/A',
              HugeIcons.strokeRoundedMail01,
            ),
            _buildInfoRow(
              'Phone',
              user?['phone']?.toString() ?? 'N/A',
              HugeIcons.strokeRoundedCall,
            ),
            _buildInfoRow(
              'Wallet Balance',
              user?['walletBalance'] != null
                  ? '₦${(user!['walletBalance'] as num).toStringAsFixed(2)}'
                  : 'N/A',
              HugeIcons.strokeRoundedWallet01,
            ),
            if (hasDispute) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: errorColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: errorColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedAlert02,
                      color: errorColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '⚠️ This transaction has unresolved disputes. Status cannot be updated until disputes are resolved.',
                        style: GoogleFonts.inter(
                          color: errorColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!canUpdate)
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedLock,
                          color: Colors.orange,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            hasDispute
                                ? '🔒 Transaction Locked - Active Dispute'
                                : '🔒 Transaction Locked - Pending Refund',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasDispute
                          ? 'This transaction has unresolved disputes. Please resolve the dispute in the Refund System before updating status.'
                          : 'This transaction has a pending refund request. Complete or reject the refund before updating status.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: isMobile ? double.infinity : 200,
                          child: ElevatedButton.icon(
                            onPressed:
                                () => _showUnlockInstructions(
                                  _selectedTransaction!,
                                ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: HugeIcon(
                              icon: HugeIcons.strokeRoundedInformationCircle,
                              color: Colors.white,
                              size: 18,
                            ),
                            label: Text(
                              'View Unlock Instructions',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: isMobile ? double.infinity : 200,
                          child: OutlinedButton.icon(
                            onPressed: () => _navigateToRefundSystem(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primaryColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              side: BorderSide(color: primaryColor),
                            ),
                            icon: HugeIcon(
                              icon: HugeIcons.strokeRoundedArrowRight01,
                              color: primaryColor,
                              size: 18,
                            ),
                            label: Text(
                              'Go to Refund System',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, dynamic icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HugeIcon(icon: icon, color: textSecondary, size: 16),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(color: textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== DISPUTE SECTION ====================

  Widget _buildDisputeSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade100, width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedAuction,
                  color: Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Disputes',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_disputes.length}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._disputes.map((dispute) => _buildDisputeItem(dispute)),
          ],
        ),
      ),
    );
  }

  Widget _buildDisputeItem(Map<String, dynamic> dispute) {
    final status = dispute['status']?.toString() ?? 'pending';
    final isMobile = MediaQuery.of(context).size.width < 600;

    Color statusColor;
    String statusText;
    dynamic statusIcon;

    switch (status) {
      case 'resolved':
        statusColor = successColor;
        statusText = 'Resolved ✓';
        statusIcon = HugeIcons.strokeRoundedCheckmarkCircle01;
        break;
      case 'rejected':
        statusColor = errorColor;
        statusText = 'Rejected ✗';
        statusIcon = HugeIcons.strokeRoundedCancelCircle;
        break;
      case 'pending':
        statusColor = warningColor;
        statusText = 'Pending Review';
        statusIcon = HugeIcons.strokeRoundedClock02;
        break;
      case 'under_review':
        statusColor = Colors.orange;
        statusText = 'Under Review';
        statusIcon = HugeIcons.strokeRoundedSearch01;
        break;
      default:
        statusColor = Colors.grey;
        statusText = status.toUpperCase();
        statusIcon = HugeIcons.strokeRoundedCircle;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: HugeIcon(icon: statusIcon, color: statusColor, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dispute['type']?.toString() ?? 'Dispute',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  statusText,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Reason: ${dispute['reason']?.toString() ?? 'N/A'}',
            style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
          ),
          if (dispute['resolution'] != null &&
              dispute['resolution'].toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Resolution: ${dispute['resolution']}',
              style: GoogleFonts.inter(fontSize: 12, color: successColor),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== RECEIPT SECTION ====================

  Widget _buildReceiptSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade100, width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedReceiptText,
                  color: primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Receipts',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_receipts.length}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._receipts.map((receipt) => _buildReceiptItem(receipt)),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptItem(Map<String, dynamic> receipt) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(isMobile ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedReceiptText,
              color: primaryColor,
              size: isMobile ? 16 : 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  receipt['type']?.toString() ?? 'Receipt',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                Text(
                  'ID: ${receipt['receiptId']?.toString() ?? 'N/A'}',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 10 : 11,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => _showReceiptDialog(receipt),
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedEye,
              color: primaryColor,
              size: isMobile ? 16 : 18,
            ),
            label: Text(
              'View',
              style: GoogleFonts.inter(
                color: primaryColor,
                fontSize: isMobile ? 11 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 8 : 12,
                vertical: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== ACTION BUTTONS ====================

  Widget _buildActionButtons() {
    final tx = _selectedTransaction;
    if (tx == null) return const SizedBox();

    final canUpdate = tx['canUpdate'] == true;
    final hasDispute = _disputes.any(
      (d) => d['status'] == 'pending' || d['status'] == 'under_review',
    );
    final currentStatus = tx['status']?.toString().toLowerCase() ?? '';
    final user = tx['user'] as Map<String, dynamic>?;
    final userId = user?['_id']?.toString();
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (currentStatus == 'successful' || currentStatus == 'completed') {
      return Card(
        color: successColor.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: successColor.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16 : 20),
          child: Column(
            children: [
              Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                    color: successColor,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This transaction is already successful/completed.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      () => _showFundUserDialog(userId, user?['fullName']),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: successColor,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedWallet01,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: Text(
                    'Fund User Wallet',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade100, width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        child: Column(
          children: [
            // Status Update Section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primaryColor.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedSystemUpdate01,
                        color: primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Update Status',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedNewStatus,
                    decoration: InputDecoration(
                      labelText: 'New Status',
                      labelStyle: GoogleFonts.inter(
                        fontSize: 13,
                        color: textSecondary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: isMobile ? 8 : 12,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Successful',
                        child: Text('✅ Successful'),
                      ),
                      DropdownMenuItem(
                        value: 'Failed',
                        child: Text('❌ Failed'),
                      ),
                      DropdownMenuItem(
                        value: 'Pending',
                        child: Text('⏳ Pending'),
                      ),
                      DropdownMenuItem(
                        value: 'Processing',
                        child: Text('🔄 Processing'),
                      ),
                    ],
                    onChanged:
                        (value) => setState(() => _selectedNewStatus = value!),
                    isExpanded: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _adminNoteController,
                    decoration: InputDecoration(
                      labelText: 'Admin Note (Optional)',
                      hintText:
                          'Add a note explaining why status is being changed',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: isMobile ? 8 : 12,
                      ),
                    ),
                    maxLines: 2,
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton(
                      onPressed: _updateTransactionStatus,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        disabledBackgroundColor: Colors.grey.shade300,
                      ),
                      child: Text(
                        'Update Status',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Fund User Section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: successColor.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: successColor.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedWallet01,
                        color: successColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Fund User Wallet',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _fundAmountController,
                    decoration: InputDecoration(
                      labelText: 'Amount (₦)',
                      prefixText: '₦',
                      hintText: 'Enter amount to fund',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: isMobile ? 8 : 12,
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _fundNoteController,
                    decoration: InputDecoration(
                      labelText: 'Note (Optional)',
                      hintText: 'Reason for funding',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: isMobile ? 8 : 12,
                      ),
                    ),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton.icon(
                      onPressed:
                          () => _showFundUserDialog(userId, user?['fullName']),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: successColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedMoneyAdd01,
                        color: Colors.white,
                        size: 18,
                      ),
                      label: Text(
                        'Fund Wallet',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
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
    );
  }

  // ==================== OPEN TRANSACTION DIALOG ====================
  // ==================== OPEN TRANSACTION DIALOG ====================
  Future<void> _openTransactionDialog(Map<String, dynamic> tx) async {
    final isMobile = MediaQuery.of(context).size.width < 600;

    // Reset the admin note controller text for this dialog
    _adminNoteController.clear();

    // Local state inside the dialog
    String localSelectedStatus = _normalizeStatus(
      tx['status']?.toString() ?? '',
    );
    bool localIsUpdating = false;
    bool dialogClosed = false;

    // Fetch full details first (disputes, receipts)
    setState(() {
      _isDetailsLoading = true;
    });

    try {
      final response = await ApiService.getTransactionDetails(
        tx['_id'].toString(),
      );
      if (response['success'] == true) {
        _disputes = response['disputes'] ?? [];
        _receipts = response['receipts'] ?? [];
      }
    } catch (e) {
      debugPrint('⚠️ Details fetch failed: $e');
    } finally {
      if (mounted) setState(() => _isDetailsLoading = false);
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              insetPadding: EdgeInsets.all(isMobile ? 12 : 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.92,
                  maxWidth: isMobile ? double.infinity : 500,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ============ EXISTING RECEIPT WIDGET ============
                      ReceiptWidget(
                        transactionType:
                            tx['type']?.toString() ?? 'Transaction',
                        amount:
                            (tx['amount'] as num?)?.toStringAsFixed(2) ??
                            '0.00',
                        status: tx['status']?.toString() ?? 'N/A',
                        transactionId:
                            (tx['transactionId'] ?? tx['_id'] ?? 'N/A')
                                .toString(),
                        reference: tx['reference']?.toString() ?? 'N/A',
                        date:
                            tx['createdAt'] != null
                                ? DateTime.tryParse(
                                      tx['createdAt'].toString(),
                                    ) ??
                                    DateTime.now()
                                : DateTime.now(),
                        phoneNumber: tx['phone'] as String?,
                        mobileOperator: null,
                        isCommission: tx['isCommission'] == true,
                        commissionSource: tx['commissionSource'] as String?,
                        isService: tx['serviceFee'] != null,
                        description:
                            tx['description']?.toString() ?? 'No description',
                        balanceBefore: (tx['balanceBefore'] as num?)
                            ?.toStringAsFixed(2),
                        balanceAfter: (tx['balanceAfter'] as num?)
                            ?.toStringAsFixed(2),
                        gateway: tx['gateway'] as String?,
                        primaryColor: primaryColor,
                        showWatermark: false,
                        packageVariationCode:
                            (tx['metadata']
                                    as Map<String, dynamic>?)?['variation_code']
                                as String?,
                        electricityToken:
                            (tx['metadata'] as Map<String, dynamic>?)?['token']
                                as String?,
                        customerName:
                            (tx['user'] as Map<String, dynamic>?)?['fullName']
                                as String? ??
                            'Unknown User',
                        customerAddress:
                            (tx['user'] as Map<String, dynamic>?)?['email']
                                as String? ??
                            'No email',
                        customerPhone:
                            (tx['user'] as Map<String, dynamic>?)?['phone']
                                as String? ??
                            'N/A',
                        customerUserId:
                            (tx['user'] as Map<String, dynamic>?)?['_id']
                                ?.toString() ??
                            'N/A',
                        isAdminTransaction: tx['isAdminPerformed'] == true,
                        adminNote:
                            tx['isAdminPerformed'] == true
                                ? '🔧 ADMIN TRANSACTION'
                                : null,
                        isUserAdmin:
                            (tx['user'] as Map<String, dynamic>?)?['isAdmin'] ==
                            true,
                      ),

                      // ============ STATUS UPDATE SECTION ============
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(20),
                            bottomRight: Radius.circular(20),
                          ),
                          border: Border(
                            top: BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: HugeIcon(
                                    icon: HugeIcons.strokeRoundedSystemUpdate01,
                                    color: primaryColor,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Update Transaction Status',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Current status
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    'Current: ',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: textSecondary,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(
                                        tx['status']?.toString() ?? '',
                                      ).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      tx['status']?.toString() ?? 'N/A',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: _getStatusColor(
                                          tx['status']?.toString() ?? '',
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // New status dropdown
                            Text(
                              'Change to:',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: DropdownButton<String>(
                                value: localSelectedStatus,
                                isExpanded: true,
                                underline: const SizedBox(),
                                icon: HugeIcon(
                                  icon: HugeIcons.strokeRoundedArrowDown01,
                                  color: primaryColor,
                                  size: 18,
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'Successful',
                                    child: Text('✅  Successful'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Completed',
                                    child: Text('✔️  Completed'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Pending',
                                    child: Text('⏳  Pending'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Processing',
                                    child: Text('🔄  Processing'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Failed',
                                    child: Text('❌  Failed'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Refunded',
                                    child: Text('💰  Refunded'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Resolved',
                                    child: Text('✔️  Resolved'),
                                  ),
                                ],
                                onChanged:
                                    dialogClosed
                                        ? null
                                        : (v) {
                                          if (v != null) {
                                            setDialogState(() {
                                              localSelectedStatus = v;
                                            });
                                          }
                                        },
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Admin note
                            TextField(
                              controller: _adminNoteController,
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText: 'Admin Note (Optional)',
                                hintText: 'Reason for status change',
                                hintStyle: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: textSecondary.withValues(alpha: 0.6),
                                ),
                                labelStyle: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: textSecondary,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                              ),
                              style: GoogleFonts.inter(fontSize: 13),
                            ),
                            const SizedBox(height: 16),

                            // Action buttons
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed:
                                        localIsUpdating
                                            ? null
                                            : () {
                                              dialogClosed = true;
                                              Navigator.pop(dialogContext);
                                            },
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      side: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Text(
                                      'Close',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 2,
                                  child: ElevatedButton(
                                    onPressed:
                                        localIsUpdating
                                            ? null
                                            : () async {
                                              // Skip if same
                                              final originalStatus =
                                                  tx['status']?.toString() ??
                                                  '';
                                              if (originalStatus
                                                      .toLowerCase() ==
                                                  localSelectedStatus
                                                      .toLowerCase()) {
                                                if (mounted) {
                                                  _showSnackBar(
                                                    'Status is already "$localSelectedStatus".',
                                                    true,
                                                  );
                                                }
                                                return;
                                              }

                                              // Yes/No confirmation
                                              final confirmed = await showDialog<
                                                bool
                                              >(
                                                context: dialogContext,
                                                barrierDismissible: false,
                                                builder:
                                                    (
                                                      ctx,
                                                    ) => _buildStatusChangeConfirmDialog(
                                                      ctx: ctx,
                                                      userName:
                                                          (tx['user']
                                                                  as Map<
                                                                    String,
                                                                    dynamic
                                                                  >?)?['fullName']
                                                              ?.toString() ??
                                                          'Unknown User',
                                                      reference:
                                                          tx['reference']
                                                              ?.toString() ??
                                                          'N/A',
                                                      amount:
                                                          (tx['amount'] as num?)
                                                              ?.toStringAsFixed(
                                                                2,
                                                              ) ??
                                                          '0.00',
                                                      oldStatus: originalStatus,
                                                      newStatus:
                                                          localSelectedStatus,
                                                      adminNote:
                                                          _adminNoteController
                                                              .text
                                                              .trim(),
                                                    ),
                                              );

                                              if (confirmed != true) return;
                                              if (dialogClosed) return;

                                              // Set loading
                                              setDialogState(() {
                                                localIsUpdating = true;
                                              });

                                              try {
                                                debugPrint(
                                                  '📡 Calling updateTransactionStatus for ${tx['_id']} → $localSelectedStatus',
                                                );
                                                final response =
                                                    await ApiService.updateTransactionStatus(
                                                      transactionId:
                                                          tx['_id'].toString(),
                                                      newStatus:
                                                          localSelectedStatus,
                                                      adminNote:
                                                          _adminNoteController
                                                                  .text
                                                                  .trim()
                                                                  .isNotEmpty
                                                              ? _adminNoteController
                                                                  .text
                                                                  .trim()
                                                              : null,
                                                      resolutionReference: null,
                                                    );
                                                debugPrint(
                                                  '📡 Response received: success=${response['success']}, message=${response['message']}',
                                                );

                                                if (response['success'] ==
                                                    true) {
                                                  dialogClosed = true;
                                                  if (Navigator.canPop(
                                                    dialogContext,
                                                  )) {
                                                    Navigator.pop(
                                                      dialogContext,
                                                    );
                                                  }

                                                  // ✅ CRITICAL FIX: Update local state with fresh data from backend
                                                  if (mounted) {
                                                    setState(() {
                                                      // Update the selected transaction with fresh data
                                                      if (response['transaction'] !=
                                                          null) {
                                                        _selectedTransaction = Map<
                                                          String,
                                                          dynamic
                                                        >.from(
                                                          response['transaction'],
                                                        );
                                                      }
                                                      // Update disputes if returned
                                                      if (response['disputes'] !=
                                                          null) {
                                                        _disputes = List<
                                                          dynamic
                                                        >.from(
                                                          response['disputes'],
                                                        );
                                                      }
                                                      // Update receipts if returned
                                                      if (response['receipts'] !=
                                                          null) {
                                                        _receipts = List<
                                                          dynamic
                                                        >.from(
                                                          response['receipts'],
                                                        );
                                                      }
                                                    });

                                                    _showSnackBar(
                                                      '✅ Status changed from "$originalStatus" to "$localSelectedStatus"',
                                                      false,
                                                    );
                                                    _adminNoteController
                                                        .clear();

                                                    // ✅ Refresh the transaction LIST (stats + filtered list)
                                                    await _fetchTransactions();

                                                    // ✅ Re-fetch transaction details to get complete fresh data
                                                    await _loadTransactionDetails(
                                                      tx['_id'].toString(),
                                                    );
                                                  }
                                                } else {
                                                  if (mounted) {
                                                    setDialogState(() {
                                                      localIsUpdating = false;
                                                    });
                                                    _showSnackBar(
                                                      response['message'] ??
                                                          'Update failed',
                                                      true,
                                                    );
                                                  }
                                                }
                                              } catch (e) {
                                                debugPrint(
                                                  '❌ Update error: $e',
                                                );
                                                if (mounted && !dialogClosed) {
                                                  setDialogState(() {
                                                    localIsUpdating = false;
                                                  });
                                                  _showSnackBar(
                                                    'Error: ${e.toString()}',
                                                    true,
                                                  );
                                                }
                                              }
                                            },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _getStatusColor(
                                        localSelectedStatus,
                                      ),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      elevation: 0,
                                    ),
                                    child:
                                        localIsUpdating
                                            ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            )
                                            : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  Icons.save_rounded,
                                                  size: 18,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Update Status',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==================== NORMALIZE STATUS ====================
  String _normalizeStatus(String status) {
    final s = status.toLowerCase().trim();
    if (s == 'successful' || s == 'success') return 'Successful';
    if (s == 'completed') return 'Completed';
    if (s == 'pending') return 'Pending';
    if (s == 'processing') return 'Processing';
    if (s == 'failed') return 'Failed';
    if (s == 'refunded') return 'Refunded';
    if (s == 'resolved') return 'Resolved';
    return 'Successful';
  }

  // ==================== YES/NO CONFIRMATION DIALOG ====================
  Widget _buildStatusChangeConfirmDialog({
    required BuildContext ctx,
    required String userName,
    required String reference,
    required String amount,
    required String oldStatus,
    required String newStatus,
    required String adminNote,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final oldColor = _getStatusColor(oldStatus);
    final newColor = _getStatusColor(newStatus);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: EdgeInsets.zero,
      content: Container(
        width: isMobile ? double.infinity : 440,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFF92D394), Color(0xFF1E377E)],
                  stops: [0.06, 0.41],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Confirm Status Change',
                          style: GoogleFonts.poppins(
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'This will update the user\'s transaction',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildConfirmInfoRow('User', userName),
                        const SizedBox(height: 6),
                        _buildConfirmInfoRow('Amount', '₦$amount'),
                        const SizedBox(height: 6),
                        _buildConfirmInfoRow('Reference', reference),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: oldColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: oldColor.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CURRENT',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: textSecondary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                oldStatus,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: oldColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: primaryColor.withValues(alpha: 0.6),
                          size: 22,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: newColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: newColor.withValues(alpha: 0.35),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'NEW',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: textSecondary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                newStatus,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: newColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (adminNote.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: primaryColor.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ADMIN NOTE',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: primaryColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            adminNote,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: warningColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: warningColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedAlert02,
                          color: warningColor,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'The user will see this change immediately.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Yes/No buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        'No, Cancel',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: newColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Yes, Change Status',
                            style: GoogleFonts.inter(
                              fontSize: 14,
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
          ],
        ),
      ),
    );
  }

  // ==================== CONFIRM INFO ROW ====================
  Widget _buildConfirmInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            '$label:',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ==================== DIALOGS ====================

  Future<void> _showFundUserDialog(String? userId, String? userName) async {
    if (userId == null) {
      _showSnackBar('User ID not found', true);
      return;
    }

    final amountStr = _fundAmountController.text.trim();
    if (amountStr.isEmpty) {
      _showSnackBar('Please enter an amount', true);
      return;
    }

    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      _showSnackBar('Please enter a valid positive amount', true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedWalletAdd01,
                  color: primaryColor,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  'Confirm Wallet Funding',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDialogInfoRow('User', userName ?? 'Unknown User'),
                const SizedBox(height: 8),
                _buildDialogInfoRow('Amount', '₦${amount.toStringAsFixed(2)}'),
                if (_fundNoteController.text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildDialogInfoRow('Note', _fundNoteController.text),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: warningColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: warningColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedAlertCircle,
                        color: warningColor,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This action will credit the user\'s wallet balance immediately.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
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
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    color: textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: successColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Confirm Funding',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await _processWalletFunding(userId, amount);
    }
  }

  Future<void> _processWalletFunding(String userId, double amount) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) =>
              Center(child: CircularProgressIndicator(color: primaryColor)),
    );

    try {
      final result = await ApiService.fundUserWallet(
        userId: userId,
        amount: amount,
        note:
            _fundNoteController.text.isNotEmpty
                ? _fundNoteController.text
                : 'Admin wallet funding',
      );

      if (result['success'] == true) {
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

        await showDialog(
          context: context,
          builder:
              (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Row(
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                      color: successColor,
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Funding Successful!',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDialogInfoRow(
                      'Amount',
                      '₦${amount.toStringAsFixed(2)}',
                    ),
                    _buildDialogInfoRow(
                      'New Balance',
                      '₦${(result['newBalance'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                    ),
                    if (_fundNoteController.text.isNotEmpty)
                      _buildDialogInfoRow('Note', _fundNoteController.text),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _fundAmountController.clear();
                      _fundNoteController.clear();
                    },
                    child: Text(
                      'Close',
                      style: GoogleFonts.inter(
                        color: textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
        );

        if (_selectedTransaction != null) {
          await _loadTransactionDetails(
            _selectedTransaction!['_id'].toString(),
          );
        }
        await _fetchTransactions();
      } else {
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
        throw Exception(result['message'] ?? 'Funding failed');
      }
    } catch (e) {
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
      _showSnackBar('Error: $e', true);
    }
  }

  // ==================== CONFIRMATION + STATUS UPDATE ====================
  Future<void> _updateTransactionStatus() async {
    if (_selectedTransaction == null) return;

    final tx = _selectedTransaction!;
    final currentStatus = tx['status']?.toString() ?? 'N/A';
    final newStatus = _selectedNewStatus;
    final reference = tx['reference']?.toString() ?? 'N/A';
    final amount = (tx['amount'] as num?)?.toStringAsFixed(2) ?? '0.00';
    final user = tx['user'] as Map<String, dynamic>?;
    final userName = user?['fullName']?.toString() ?? 'Unknown User';
    final adminNote = _adminNoteController.text.trim();

    // ⛔ If nothing is changing, warn the user
    if (currentStatus.toLowerCase() == newStatus.toLowerCase()) {
      _showSnackBar('Status is already "$newStatus". Nothing to change.', true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => _buildStatusChangeConfirmDialog(
            ctx: ctx,
            userName: userName,
            reference: reference,
            amount: amount,
            oldStatus: currentStatus,
            newStatus: newStatus,
            adminNote: adminNote,
          ),
    );

    if (confirmed != true) return;

    // Show loading spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) =>
              Center(child: CircularProgressIndicator(color: primaryColor)),
    );

    try {
      final result = await ApiService.updateTransactionStatus(
        transactionId: tx['_id'].toString(),
        newStatus: newStatus,
        adminNote: adminNote.isNotEmpty ? adminNote : null,
        resolutionReference: null,
      );

      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (result['success'] == true) {
        await _showSuccessDialog(result);
        await _fetchTransactions();
        await _loadTransactionDetails(tx['_id'].toString());
        _adminNoteController.clear();
      } else {
        throw Exception(result['message'] ?? 'Update failed');
      }
    } catch (e) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      _showSnackBar('Error: $e', true);
    }
  }

  Future<void> _showSuccessDialog(Map<String, dynamic> result) async {
    final receipt = result['receipt'];

    await showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                  color: successColor,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  'Status Updated!',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Transaction status has been updated to $_selectedNewStatus.',
                  style: GoogleFonts.inter(fontSize: 14, color: textPrimary),
                ),
                const SizedBox(height: 12),
                if (receipt != null) ...[
                  const Divider(),
                  Text(
                    'Receipt Generated:',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildDialogInfoRow(
                    'Receipt ID',
                    receipt['receiptId'] ?? 'N/A',
                  ),
                  _buildDialogInfoRow(
                    'Old Status',
                    receipt['oldStatus'] ?? 'N/A',
                  ),
                  _buildDialogInfoRow(
                    'New Status',
                    receipt['newStatus'] ?? 'N/A',
                  ),
                  if (receipt['adminNote'] != null &&
                      receipt['adminNote'].toString().isNotEmpty)
                    _buildDialogInfoRow('Note', receipt['adminNote']),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Close',
                  style: GoogleFonts.inter(
                    color: textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (receipt != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showReceiptDialog(receipt);
                  },
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedReceiptText,
                    color: primaryColor,
                    size: 18,
                  ),
                  label: Text(
                    'View Receipt',
                    style: GoogleFonts.inter(
                      color: primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
    );
  }

  void _showReceiptDialog(Map<String, dynamic> receipt) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      builder:
          (ctx) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: isMobile ? double.infinity : 420,
              padding: EdgeInsets.all(isMobile ? 20 : 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedReceiptText,
                    color: primaryColor,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Transaction Receipt',
                    style: GoogleFonts.poppins(
                      fontSize: isMobile ? 18 : 20,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                  const Divider(),
                  _buildDialogInfoRow(
                    'Receipt ID',
                    receipt['receiptId'] ?? 'N/A',
                  ),
                  _buildDialogInfoRow(
                    'Type',
                    receipt['type'] ?? 'status_update',
                  ),
                  _buildDialogInfoRow(
                    'Amount',
                    '₦${(receipt['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                  ),
                  _buildDialogInfoRow(
                    'Old Status',
                    receipt['oldStatus'] ?? 'N/A',
                  ),
                  _buildDialogInfoRow(
                    'New Status',
                    receipt['newStatus'] ?? 'N/A',
                  ),
                  if (receipt['adminNote'] != null &&
                      receipt['adminNote'].toString().isNotEmpty)
                    _buildDialogInfoRow('Admin Note', receipt['adminNote']),
                  _buildDialogInfoRow(
                    'Updated At',
                    receipt['updatedAt'] != null
                        ? DateFormat('MMM dd, yyyy HH:mm:ss').format(
                          DateTime.parse(receipt['updatedAt'].toString()),
                        )
                        : 'N/A',
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Close',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildDialogInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(fontSize: 12, color: textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== STATE WIDGETS ====================

  Widget _buildErrorState() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 20 : 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: isMobile ? 80 : 100,
              height: isMobile ? 80 : 100,
              decoration: BoxDecoration(
                color: errorColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedAlert02,
                color: errorColor,
                size: isMobile ? 40 : 50,
              ),
            ),
            SizedBox(height: isMobile ? 16 : 24),
            Text(
              'Error Loading Transactions',
              style: GoogleFonts.poppins(
                fontSize: isMobile ? 22 : 28,
                fontWeight: FontWeight.w700,
                color: errorColor,
              ),
            ),
            SizedBox(height: isMobile ? 8 : 12),
            Text(
              _errorMessage!,
              style: GoogleFonts.inter(
                fontSize: isMobile ? 14 : 16,
                color: textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isMobile ? 24 : 32),
            SizedBox(
              width: isMobile ? 180 : 200,
              child: ElevatedButton(
                onPressed: _fetchTransactions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh_rounded, size: isMobile ? 18 : 20),
                    SizedBox(width: isMobile ? 6 : 8),
                    Text(
                      'Try Again',
                      style: GoogleFonts.inter(
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

  Widget _buildEmptyState() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 20 : 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: isMobile ? 80 : 100,
              height: isMobile ? 80 : 100,
              decoration: BoxDecoration(
                color: successColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                color: successColor,
                size: isMobile ? 40 : 50,
              ),
            ),
            SizedBox(height: isMobile ? 16 : 24),
            Text(
              'No Transactions Found',
              style: GoogleFonts.poppins(
                fontSize: isMobile ? 20 : 24,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            SizedBox(height: isMobile ? 8 : 12),
            Text(
              'Try adjusting your filters or search',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 14 : 16,
                color: textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
          (item) => item.title == "Status Update",
          orElse: () => _drawerItems.first,
        ),
        onItemSelected: _onDrawerItemSelected,
        isAdmin: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          key: _refreshIndicatorKey,
          onRefresh: _fetchTransactions,
          color: primaryColor,
          backgroundColor: Colors.white,
          child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return RefreshIndicator(
      onRefresh: _fetchTransactions,
      color: primaryColor,
      backgroundColor: Colors.white,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(children: [_buildAdminHeader(), _buildStatsCard()]),
          ),
          _buildTransactionList(),
          // ✅ FIX: Always show details panel if there's a selected transaction
          SliverToBoxAdapter(
            child:
                _selectedTransaction != null
                    ? Container(
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _selectedTransaction = null;
                                  });
                                },
                                icon: Icon(Icons.close, color: textSecondary),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Transaction Details',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: textPrimary,
                                ),
                              ),
                              const Spacer(),
                              if (_selectedTransaction != null)
                                Text(
                                  _selectedTransaction!['reference']
                                          ?.toString() ??
                                      'N/A',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: textSecondary,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            constraints: BoxConstraints(
                              minHeight: 200,
                              maxHeight:
                                  MediaQuery.of(context).size.height * 0.7,
                            ),
                            child: _buildDetailsPanel(),
                          ),
                        ],
                      ),
                    )
                    : const SizedBox(),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left Panel - Transaction List
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _buildAdminHeader(),
              _buildStatsCard(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _fetchTransactions,
                  color: primaryColor,
                  backgroundColor: Colors.white,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      _buildTransactionList(),
                      SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Right Panel - Transaction Details
        Expanded(
          flex: 2,
          child:
              _selectedTransaction != null
                  ? _buildDetailsPanel()
                  : Container(
                    color: Colors.white,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedReceiptText,
                              color: primaryColor,
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Select a Transaction',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Click on a transaction to view details',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
        ),
      ],
    );
  }
}
