// lib/presentation/screens/dashboard/dashboard_screen.dart
// lib/presentation/screens/dashboard/dashboard_screen.dart
import 'dart:async';
import 'dart:async' show unawaited;
import 'dart:convert';
import 'package:dalabapay/core/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../../../core/services/api_service.dart';
import '../../../core/services/payment_service.dart';
import '../../../core/widgets/receipt_widget.dart';
import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';
import '../settings/settings_screen.dart';
import '../user_disputes_page.dart';
import '../transaction_validation_page.dart';
import 'package:hugeicons/hugeicons.dart';
import '../kyc/kyc_screen.dart';
import '../../../core/services/socket_service.dart' hide debugPrint;
import '../../../core/services/notification_service.dart';

// Admin Pages
import '../admin/admin_dashboard_screen.dart';
import '../admin/admin_users_page.dart';
import '../admin/admin_all_transactions_page.dart';
import '../admin/admin_transaction_status_page.dart';
import '../admin/admin_refund_system_page.dart';
import '../admin/admin_fund_wallet_page.dart';
import '../admin/admin_verify_payment_page.dart'; // ✅ FIXED: Hide duplicate
import '../admin/admin_send_notification_page.dart';
import '../admin/admin_control_page.dart';
import '../admin/vtpass_settings_dashboard.dart';
import '../admin/admin_self_fund_page.dart';
import '../admin/admin_service_commission_page.dart';
// Add this import with the other admin imports (around line 30)
import '../admin/admin_transaction_limits_page.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  bool _isBalanceVisible = true;
  bool _hasDedicatedAccount = false;
  String? _dedicatedAccountNumber;
  String? _dedicatedAccountName;
  String? _dedicatedBankName;
  bool _isCheckingAccount = false;
  String _referralCode = 'Loading...';
  String _fullName = '';
  String _email = '';
  String? _userId;
  double _walletBalance = 0.0;
  double _commissionBalance = 0.0;

  // ✅ NEW: Tracks whether we've resolved a real balance yet.
  // Prevents "₦0.00" from flashing when cache is empty and API is slow.
  bool _isBalanceReady = false;

  bool _isLoading = true;
  bool _isAdmin = false;
  bool _isLoadingTransactions = true;
  List<dynamic> _recentTransactions = [];
  int _unreadNotificationCount = 0;
  late NotificationService _notificationService;

  // ✅ NEW: Approval status
  // ✅ Approval status
  String _approvalStatus = 'approved'; // default: approved (for old users)
  String? _rejectionReason;

  // ✅ Global toggle state — when OFF, no banner is ever shown
  bool _approvalSystemEnabled = true;

  // Show pending banner ONLY if:
  //   - approval system is ON globally
  //   - AND user's status is pending
  bool get _isPending => _approvalSystemEnabled && _approvalStatus == 'pending';

  // Show rejected banner ONLY if:
  //   - approval system is ON globally
  //   - AND user's status is rejected
  bool get _isRejected =>
      _approvalSystemEnabled && _approvalStatus == 'rejected';

  bool get _isApproved => !_isPending && !_isRejected;

  static const Color _successColor = Color(0xFF219C7E);
  static const Color _warningColor = Color(0xFFF39C12);

  // Transaction state management
  bool _isTransactionInProgress = false;
  DateTime? _lastUserActivity;
  Timer? _idleLogoutTimer;
  Timer? _silentRefreshTimer;
  Timer? _notificationTimer;
  bool _isAppInBackground = false;

  late AnimationController _animationController;

  // Quick Services
  final List<Map<String, dynamic>> _quickServices = [
    {
      'icon': HugeIcons.strokeRoundedSmartPhone01,
      'name': 'Airtime',
      'route': '/airtime',
      'isHugeIcon': true,
      'iconColor': const Color(0xFF4A90E2),
    },
    {
      'icon': HugeIcons.strokeRoundedWifi01,
      'name': 'Data',
      'route': '/data',
      'isHugeIcon': true,
      'iconColor': const Color(0xFF9B59B6),
    },
    {
      'icon': HugeIcons.strokeRoundedBulb,
      'name': 'Electricity',
      'route': '/electricity',
      'isHugeIcon': true,
      'iconColor': const Color(0xFFF39C12),
    },
    {
      'icon': HugeIcons.strokeRoundedTv01,
      'name': 'Cable TV',
      'route': '/cable',
      'isHugeIcon': true,
      'iconColor': const Color(0xFFE74C3C),
    },
    {
      'icon': HugeIcons.strokeRoundedMortarboard01,
      'name': 'Education',
      'route': '/education',
      'isHugeIcon': true,
      'iconColor': const Color(0xFF2ECC71),
    },
    {
      'icon': HugeIcons.strokeRoundedTelephone,
      'name': 'Intl Airtime',
      'route': '/international-airtime',
      'isHugeIcon': true,
      'iconColor': const Color(0xFF9013FE),
    },
    {
      'icon': HugeIcons.strokeRoundedTicket01,
      'name': 'Tickets',
      'route': '/ticket',
      'isHugeIcon': true,
      'iconColor': const Color(0xFFE67E22),
    },
    {
      'icon': HugeIcons.strokeRoundedPercent,
      'name': 'Commission',
      'route': '/commission',
      'isHugeIcon': true,
      'iconColor': const Color(0xFF219C7E),
    },
  ];

  // Other Services
  final List<Map<String, dynamic>> _otherServices = [
    {
      'icon': HugeIcons.strokeRoundedGlobe,
      'name': 'Internet',
      'route': '/internet',
      'isHugeIcon': true,
      'iconColor': const Color(0xFF3498DB),
    },
    {
      'icon': HugeIcons.strokeRoundedDice,
      'name': 'Betting',
      'route': '/betting',
      'isHugeIcon': true,
      'iconColor': const Color(0xFFE74C3C),
    },
    {
      'icon': HugeIcons.strokeRoundedShield01,
      'name': 'Insurance',
      'route': '/insurance',
      'isHugeIcon': true,
      'iconColor': const Color(0xFF1ABC9C),
    },
    {
      'icon': HugeIcons.strokeRoundedGift,
      'name': 'Donations',
      'route': '/donation',
      'isHugeIcon': true,
      'iconColor': const Color(0xFF417505),
    },
    {
      'icon': HugeIcons.strokeRoundedCash01,
      'name': 'Airtime Cash',
      'route': null,
      'isHugeIcon': true,
      'iconColor': const Color(0xFF4A90E2),
      'comingSoon': true,
    },
    {
      'icon': HugeIcons.strokeRoundedTelegram,
      'name': 'Wallet Transfer',
      'route': null,
      'isHugeIcon': true,
      'iconColor': const Color(0xFFF39C12),
      'comingSoon': true,
    },
    {
      'icon': HugeIcons.strokeRoundedMore01,
      'name': 'More',
      'route': null,
      'isHugeIcon': true,
      'iconColor': const Color(0xFF7F8C8D),
    },
  ];

  @override
  void initState() {
    super.initState();
    _notificationService = NotificationService();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animationController.forward();
    _lastUserActivity = DateTime.now();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // ============================================================
      // ⚡ FAST PATH — Show cached data INSTANTLY (before any await)
      // ============================================================
      await _initializeSession(); // reads prefs only, ~5ms

      // 🔥 Kick off balance load FIRST, do not await it yet
      final balanceFuture = _loadBalances();

      // ✅ Instantly flip loading off so UI renders with cached balance
      if (mounted) {
        setState(() => _isLoading = false);
      }

      // ============================================================
      // 🚀 BACKGROUND TASKS — fire & forget, don't block the UI
      // ============================================================

      // Non-critical, run in parallel and don't await
      unawaited(_notificationService.initialize());

      unawaited(_loadReferralCode());
      unawaited(_loadRecentTransactions());
      unawaited(_checkDedicatedAccount());

      unawaited(
        ApiService.isUserAdmin()
            .then((isAdmin) {
              if (mounted) setState(() => _isAdmin = isAdmin);
            })
            .catchError((_) {}),
      );

      // Listen to notification streams when ready (non-blocking)
      unawaited(
        _notificationService
            .initialize()
            .then((_) {
              if (!mounted) return;

              if (_notificationService.isInitialized) {
                _notificationService.unreadStream.listen((count) {
                  if (mounted) setState(() => _unreadNotificationCount = count);
                });

                _notificationService.notificationStream.listen((notifications) {
                  if (mounted && notifications.isNotEmpty) {
                    _showNotificationAlert(notifications[0]);
                  }
                });

                // Fetch initial unread count in background
                _notificationService
                    .getUnreadCount()
                    .then((count) {
                      if (mounted) {
                        setState(() => _unreadNotificationCount = count);
                      }
                    })
                    .catchError((_) {});
              } else {
                ApiService.getUnreadNotificationCount()
                    .then((count) {
                      if (mounted) {
                        setState(() => _unreadNotificationCount = count);
                      }
                    })
                    .catchError((_) {});
              }
            })
            .catchError((_) {}),
      );

      // Setup sockets + timers immediately (no awaits needed)
      _setupSocketListeners();
      _startSilentRefreshTimer();
      _startNotificationPolling();
      _startIdleTimer();

      // ✅ Wait for balance to finish in the background (optional — UI already rendered)
      unawaited(balanceFuture);
    });
  } // ✅ END of initState — THIS BRACE WAS MISSING

  @override
  void dispose() {
    _animationController.dispose();
    _idleLogoutTimer?.cancel();
    _silentRefreshTimer?.cancel();
    _notificationTimer?.cancel();
    _notificationService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _isAppInBackground = false;
        if (!_isTransactionInProgress) {
          _resetIdleTimer();
          _silentBackgroundRefresh();
          PaymentService.pollPendingVerifications();
          _refreshNotifications();
          // ✅ Refresh approval status + toggle when user returns
          _refreshApprovalStatus();
        }
        break;
      case AppLifecycleState.paused:
        _isAppInBackground = true;
        if (!_isTransactionInProgress) {
          _handleAppBackgrounded();
        }
        break;
      default:
        break;
    }
  }

  // ==================== INITIALIZATION ====================

  Future<void> _initializeSession() async {
    final prefs = await SharedPreferences.getInstance();

    final token = prefs.getString('token');
    if (token == null || token.isEmpty) {
      _redirectToLogin();
      return;
    }

    final userString = prefs.getString('user');
    if (userString != null) {
      try {
        final userMap = jsonDecode(userString);
        _userId = userMap['_id']?.toString();
        _fullName = userMap['fullName']?.toString().split(' ').first ?? 'User';
        _email = userMap['email']?.toString() ?? '';

        // ✅ NEW: Load approval status from cache
        final cachedStatus = userMap['approvalStatus']?.toString();
        if (cachedStatus != null && cachedStatus.isNotEmpty) {
          _approvalStatus = cachedStatus;
        } else {
          _approvalStatus = 'approved'; // Grandfather old users
        }
        _rejectionReason = userMap['rejectionReason']?.toString();
      } catch (e) {
        debugPrint('Error parsing user data: $e');
      }
    }

    if (_userId == null || _userId!.isEmpty) {
      _redirectToLogin();
      return;
    }

    // ✅ Refresh approval status AND toggle state from backend
    await _refreshApprovalStatus();

    _lastUserActivity = DateTime.now();
  } // ✅ END of _initializeSession — this brace was MISSING

  // ==================== APPROVAL STATUS ====================

  /// Fetch the GLOBAL toggle state (from backend) — no auth needed
  Future<void> _refreshApprovalSystemToggle() async {
    try {
      final enabled = await ApiService.isApprovalSystemEnabled();
      if (mounted && enabled != _approvalSystemEnabled) {
        setState(() {
          _approvalSystemEnabled = enabled;
        });
        debugPrint('📋 Approval system toggled to: $enabled');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to refresh approval toggle: $e');
    }
  }

  /// Fetch fresh approval status from backend
  Future<void> _refreshApprovalStatus() async {
    try {
      if (_userId == null || _userId!.isEmpty) return;

      // ✅ Refresh BOTH the global toggle and this user's status
      await _refreshApprovalSystemToggle();

      final response = await ApiService.getCurrentUser(forceRefresh: true);

      // Handle both response shapes: { approvalStatus } or { user: { approvalStatus } }
      final status =
          (response['approvalStatus'] ?? response['user']?['approvalStatus'])
              ?.toString();
      final reason =
          (response['rejectionReason'] ?? response['user']?['rejectionReason'])
              ?.toString();

      // ✅ Existing users with no status = approved
      final normalizedStatus =
          (status == null || status.isEmpty) ? 'approved' : status;

      if (mounted) {
        setState(() {
          _approvalStatus = normalizedStatus;
          _rejectionReason = reason;
        });

        debugPrint(
          '📊 User approval status: $_approvalStatus (toggle: $_approvalSystemEnabled)',
        );

        // Update local cache
        final prefs = await SharedPreferences.getInstance();
        final userString = prefs.getString('user');
        if (userString != null) {
          try {
            final userMap = jsonDecode(userString);
            userMap['approvalStatus'] = _approvalStatus;
            userMap['rejectionReason'] = _rejectionReason;
            await prefs.setString('user', jsonEncode(userMap));
          } catch (e) {
            debugPrint('Error updating cached approval status: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to refresh approval status: $e');
    }
  }

  Future<void> _loadReferralCode() async {
    try {
      if (_userId != null && _userId!.isNotEmpty) {
        final code = await ApiService.getStoredReferralCode(_userId!);
        if (code.isNotEmpty && code != 'N/A') {
          setState(() => _referralCode = code);
        } else {
          final prefs = await SharedPreferences.getInstance();
          final userString = prefs.getString('user');
          if (userString != null) {
            final userMap = jsonDecode(userString);
            final storedCode = userMap['referralCode']?.toString();
            if (storedCode != null &&
                storedCode.isNotEmpty &&
                storedCode != 'N/A') {
              setState(() => _referralCode = storedCode);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading referral code: $e');
      setState(() => _referralCode = 'N/A');
    }
  }

  Future<void> _loadBalances() async {
    final prefs = await SharedPreferences.getInstance();

    // ============================================
    // STEP 1: Show cached balance IMMEDIATELY (0ms)
    // ============================================
    final cachedBalance = prefs.getDouble('walletBalance');
    final cachedCommission = prefs.getDouble('commissionBalance');

    if (cachedBalance != null && mounted) {
      setState(() {
        _walletBalance = cachedBalance;
        _isBalanceReady = true;
      });
    }
    if (cachedCommission != null && mounted) {
      setState(() => _commissionBalance = cachedCommission);
    }

    // ============================================
    // STEP 2: Fetch fresh values from backend (background)
    // ============================================
    try {
      final results = await Future.wait([
        ApiService.getBalance(),
        ApiService.getCommissionBalance(),
      ]).timeout(const Duration(seconds: 10));

      final freshBalance = (results[0] as num).toDouble();
      final freshCommission = (results[1] as num).toDouble();

      if (!mounted) return;

      setState(() {
        _walletBalance = freshBalance;
        _commissionBalance = freshCommission;
        _isBalanceReady = true;
      });

      await prefs.setDouble('walletBalance', freshBalance);
      await prefs.setDouble('commissionBalance', freshCommission);
    } catch (e) {
      debugPrint('Balance fetch error: $e');
      if (mounted && !_isBalanceReady) {
        setState(() => _isBalanceReady = true);
      }
    }
  }

  Future<void> _checkDedicatedAccount() async {
    if (_userId == null) return;

    setState(() => _isCheckingAccount = true);

    try {
      // 🔥 FIX: CLEAR CACHE FIRST
      final prefs = await SharedPreferences.getInstance();

      // Remove specific cache for this user
      await prefs.remove('cashwyre_reserve_account_$_userId');

      // Also clear from user object
      final userString = prefs.getString('user');
      if (userString != null) {
        try {
          final userMap = jsonDecode(userString);
          if (userMap['virtualAccount'] != null) {
            userMap['virtualAccount'] = null;
            await prefs.setString('user', jsonEncode(userMap));
          }
        } catch (e) {
          debugPrint('Error clearing user cache: $e');
        }
      }

      // Now fetch fresh from backend
      final result = await PaymentService.checkDedicatedAccount(
        userId: _userId!,
      );

      debugPrint('📦 Dedicated account check result: $result');

      if (mounted) {
        if (result['hasAccount'] == true) {
          // Get account details from response
          final accountNumber = result['accountNumber'];
          final accountName = result['accountName'];
          final bankName = result['bankName'];

          debugPrint('📝 Account Number from backend: $accountNumber');
          debugPrint('📝 Account Name from backend: $accountName');
          debugPrint('📝 Bank Name from backend: $bankName');

          setState(() {
            _hasDedicatedAccount = true;
            _dedicatedAccountNumber = accountNumber ?? 'N/A';
            _dedicatedAccountName = accountName ?? _fullName;
            _dedicatedBankName = bankName ?? 'Moniepoint MFB';
            _isCheckingAccount = false;
          });

          // Cache the CORRECT account details
          if (userString != null) {
            try {
              final userMap = jsonDecode(userString);
              userMap['virtualAccount'] = {
                'assigned': true,
                'accountNumber': _dedicatedAccountNumber,
                'accountName': _dedicatedAccountName,
                'bankName': _dedicatedBankName,
              };
              userMap['kycVerified'] = true;
              await prefs.setString('user', jsonEncode(userMap));
            } catch (e) {
              debugPrint('Error caching account data: $e');
            }
          }

          // Also store in separate cache
          await prefs.setString(
            'cashwyre_reserve_account_$_userId',
            jsonEncode({
              'accountNumber': _dedicatedAccountNumber,
              'accountName': _dedicatedAccountName,
              'bankName': _dedicatedBankName,
            }),
          );

          debugPrint('✅ Dedicated account loaded: $_dedicatedAccountNumber');
          debugPrint('✅ Account Name: $_dedicatedAccountName');
        } else {
          setState(() {
            _hasDedicatedAccount = false;
            _isCheckingAccount = false;
          });
          debugPrint('ℹ️ No dedicated account found for user');
        }
      }
    } catch (e) {
      debugPrint('❌ Error checking dedicated account: $e');
      setState(() => _isCheckingAccount = false);
    }
  }

  // Add KYC Modal method
  Future<void> _showKYCModal() async {
    // Only show if user doesn't have an account and we haven't shown it before
    final prefs = await SharedPreferences.getInstance();
    final modalShown = prefs.getBool('kyc_modal_shown') ?? false;

    if (_hasDedicatedAccount || modalShown) return;

    // Mark as shown to prevent spamming
    await prefs.setBool('kyc_modal_shown', true);

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildKYCModal(),
    );
  }

  Widget _buildSkeletonTile() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              height: 16,
              decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 40,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  // Add KYC Modal Widget
  Widget _buildKYCModal() {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 400,
          minWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success/Check Icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [Color(0xFF92D394), Color(0xFF1E377E)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Get Your Dedicated Account',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF243889),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'You don\'t have a dedicated account yet. '
                'Complete your KYC to get your personal virtual account for seamless transactions.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: const Color(0xFF64748B),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF243889).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF243889).withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.security,
                      color: const Color(0xFF219C7E),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your account details are secure and private.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF219C7E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
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
                        _navigateToKYC();
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF243889)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Complete KYC',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF243889),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
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
                        _navigateToKYC();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF243889),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Get Started',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Remind Me Later',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF64748B),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setupSocketListeners() {
    try {
      final socketService = SocketService();

      // Listen for new notifications - DIRECT INSTANT ALERT
      socketService.onNotification = (notification) {
        debugPrint('🔔 Socket: New notification received!');
        debugPrint('📦 Notification data: $notification');

        if (mounted) {
          // Show alert immediately - NO DELAY
          _showNotificationAlert(notification);
          // Update count
          _fetchUnreadNotificationCount();
        }
      };

      // Listen for badge updates - TRIGGER IMMEDIATE FETCH
      socketService.onBadgeUpdate = (count) {
        debugPrint('🔄 Socket: Badge update: $count');
        if (mounted) {
          final previousCount = _unreadNotificationCount;

          setState(() {
            _unreadNotificationCount = count;
          });

          // If count increased, fetch and show the new notification IMMEDIATELY
          if (count > previousCount) {
            debugPrint(
              '🔔 Badge count increased! Fetching notification NOW...',
            );
            // Fetch immediately - NO DELAY
            _fetchAndShowNewNotifications();
          }
        }
      };

      // Listen for unread count updates
      socketService.onUnreadCount = (count) {
        debugPrint('🔄 Socket: Unread count: $count');
        if (mounted) {
          final previousCount = _unreadNotificationCount;
          setState(() {
            _unreadNotificationCount = count;
          });
          if (count > previousCount) {
            debugPrint(
              '🔔 Unread count increased! Fetching notification NOW...',
            );
            _fetchAndShowNewNotifications();
          }
        }
      };

      // Listen for errors
      socketService.onError = (error) {
        debugPrint('❌ Socket error: $error');
        _startNotificationPolling();
      };

      // Initialize socket connection if not already initialized
      if (!socketService.isInitialized) {
        socketService
            .initialize()
            .then((_) {
              debugPrint('✅ Socket initialized successfully');
              _fetchUnreadNotificationCountOnStartup();
            })
            .catchError((e) {
              debugPrint('⚠️ Socket init failed, using API polling: $e');
              _startNotificationPolling();
            });
      } else {
        debugPrint('✅ Socket already initialized');
        _fetchUnreadNotificationCountOnStartup();
      }
    } catch (e) {
      debugPrint('⚠️ Socket setup error: $e');
      _startNotificationPolling();
    }
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('DASHBOARD: $message');
    }
  }

  void _navigateToKYC() {
    // Navigate to KYC screen
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const KYCScreen()),
    ).then((result) {
      // Refresh account status after returning
      _checkDedicatedAccount();
    });
  }

  Future<void> _saveBalanceToStorage(double balance) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('walletBalance', balance);

    final userString = prefs.getString('user');
    if (userString != null) {
      try {
        final userMap = jsonDecode(userString);
        userMap['walletBalance'] = balance;
        await prefs.setString('user', jsonEncode(userMap));
      } catch (e) {
        debugPrint('Error updating user object: $e');
      }
    }
  }

  // ==================== TRANSACTIONS ====================

  Future<void> _loadRecentTransactions() async {
    if (!mounted) return; // ✅ ADD THIS CHECK

    setState(() => _isLoadingTransactions = true);
    try {
      final transactions = await ApiService.getTransactions();
      if (!mounted) return; // ✅ ADD THIS CHECK

      if (transactions.isNotEmpty) {
        setState(() {
          _recentTransactions = transactions.take(6).toList();
        });
      } else {
        setState(() => _recentTransactions = []);
      }
    } catch (e) {
      debugPrint('Error loading transactions: $e');
      if (!mounted) return; // ✅ ADD THIS CHECK
      setState(() => _recentTransactions = []);
    } finally {
      if (mounted) {
        setState(() => _isLoadingTransactions = false);
      }
    }
  }

  // ==================== NOTIFICATIONS ====================

  Future<void> _startNotificationPolling() async {
    // Only start polling if socket is not connected
    final socketService = SocketService();
    if (socketService.isConnected) {
      debugPrint('ℹ️ Socket is connected, using socket for notifications');
      return;
    }

    debugPrint('⚠️ Socket not connected, using API polling fallback');

    // Initial fetch - this will show alerts for existing unread notifications
    await _fetchUnreadNotificationCountOnStartup();

    // Check for new notifications every 30 seconds (reduced to prevent backend rate limiting)
    _notificationTimer?.cancel();
    _notificationTimer = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      try {
        final currentCount = _unreadNotificationCount;
        await _fetchUnreadNotificationCount();
        if (_unreadNotificationCount > currentCount && mounted) {
          debugPrint(
            '🔔 New notification detected via polling! Showing alert...',
          );
          await _fetchAndShowNewNotifications();
        }
      } catch (e) {
        debugPrint('⚠️ Polling error: $e');
      }
    });
  }

  /// Force refresh dedicated account from backend
  Future<void> _forceRefreshDedicatedAccount() async {
    if (_userId == null) {
      _showErrorMessage('User ID not found');
      return;
    }

    setState(() => _isCheckingAccount = true);

    try {
      // Clear all cached data
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cashwyre_reserve_account_$_userId');

      final userString = prefs.getString('user');
      if (userString != null) {
        try {
          final userMap = jsonDecode(userString);
          userMap['virtualAccount'] = null;
          await prefs.setString('user', jsonEncode(userMap));
        } catch (e) {}
      }

      // Force fresh fetch
      await _checkDedicatedAccount();

      if (_hasDedicatedAccount) {
        _showSuccessMessage(
          '✅ Account refreshed: $_dedicatedAccountNumber\nName: $_dedicatedAccountName',
        );
      } else {
        _showErrorMessage('No dedicated account found');
      }
    } catch (e) {
      debugPrint('❌ Force refresh error: $e');
      _showErrorMessage('Failed to refresh account');
    } finally {
      setState(() => _isCheckingAccount = false);
    }
  }

  Future<void> _fetchReserveAccount() async {
    try {
      final result = await PaymentService.getReserveAccount(
        userId: _userId!,
        accountReference: _email,
      );

      if (result['success'] == true && result['accountNumber'] != null) {
        setState(() {
          _hasDedicatedAccount = true;
          _dedicatedAccountNumber = result['accountNumber'];
          _dedicatedAccountName = result['accountName'] ?? _fullName;
          _dedicatedBankName = result['bankName'] ?? 'Moniepoint MFB';
          _isCheckingAccount = false;
        });

        // Cache the account
        final prefs = await SharedPreferences.getInstance();
        final userString = prefs.getString('user');
        if (userString != null) {
          try {
            final userMap = jsonDecode(userString);
            userMap['virtualAccount'] = {
              'assigned': true,
              'accountNumber': _dedicatedAccountNumber,
              'accountName': _dedicatedAccountName,
              'bankName': _dedicatedBankName,
            };
            userMap['kycVerified'] = true;
            await prefs.setString('user', jsonEncode(userMap));
          } catch (e) {
            debugPrint('Error caching account: $e');
          }
        }

        debugPrint('✅ Reserve account fetched: $_dedicatedAccountNumber');
      }
    } catch (e) {
      debugPrint('❌ Error fetching reserve account: $e');
    }
  }

  /// Fetch unread count on startup and show alerts for existing unread notifications
  /// Fetch unread count on startup and show alerts for existing unread notifications
  /// Fetch unread count on startup and show alerts for existing unread notifications
  Future<void> _fetchUnreadNotificationCountOnStartup() async {
    try {
      final count = await ApiService.getUnreadNotificationCount();
      if (mounted) {
        debugPrint('📊 Initial unread notification count: $count');

        setState(() {
          _unreadNotificationCount = count;
        });

        // Show alerts for existing unread notifications on startup - IMMEDIATE
        if (count > 0 && mounted) {
          debugPrint('🔔 Showing $count existing unread notifications');
          // Removed the 500ms delay - show immediately
          _fetchAndShowNewNotifications();
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch notification count: $e');
    }
  }

  Future<void> _fetchUnreadNotificationCount() async {
    try {
      final count = await ApiService.getUnreadNotificationCount();
      if (mounted) {
        final previousCount = _unreadNotificationCount;
        debugPrint('📊 Unread notification count: $count (was $previousCount)');

        setState(() {
          _unreadNotificationCount = count;
        });

        // If count increased, show alerts (even if previousCount was 0)
        if (count > previousCount && mounted) {
          debugPrint('🔔 New notification detected! Showing alert...');
          await _fetchAndShowNewNotifications();
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch notification count: $e');
    }
  }

  /// Fetch and show new notifications with alert dialog
  Future<void> _fetchAndShowNewNotifications() async {
    try {
      debugPrint('🔔 Fetching new notifications...');

      final response = await ApiService.getNotifications();

      if (response.isEmpty) {
        debugPrint('⚠️ No notifications found');
        return;
      }

      List<Map<String, dynamic>> notifications = [];
      for (var item in response) {
        try {
          final map = Map<String, dynamic>.from(item as Map);
          notifications.add(map);
        } catch (e) {
          debugPrint('⚠️ Error converting notification: $e');
        }
      }

      final unreadNotifications =
          notifications
              .where((n) => (n['isRead'] == false || n['read'] == false))
              .toList();

      debugPrint('📬 Found ${unreadNotifications.length} unread notifications');

      if (unreadNotifications.isNotEmpty && mounted) {
        if (ModalRoute.of(context)?.isCurrent == true) {
          // ✅ FIX: Use index [0] instead of .first
          final latest = unreadNotifications[0];
          debugPrint('📢 Showing alert for: "${latest['title']}"');
          _showNotificationAlert(latest);
        }
      }
    } catch (e) {
      debugPrint('❌ Failed to fetch new notifications: $e');
    }
  }

  // ==================== REFERRAL ACTIONS ====================

  void _copyReferralCode() {
    Clipboard.setData(ClipboardData(text: _referralCode));
    _showSuccessMessage('Referral code copied to clipboard!');
  }

  void _shareReferralCode() {
    Share.share(
      'Join Dalabapay and earn rewards! 🎉\n\n'
      'Use my referral code: $_referralCode\n\n'
      'Download the app and start earning today!',
    );
    _showSuccessMessage('Share dialog opened!');
  }

  // ✅ NEW: Refresh notifications
  Future<void> _refreshNotifications() async {
    try {
      await _notificationService.getUnreadCount();
      if (_notificationService.notifications.isEmpty) {
        await _notificationService.loadNotifications();
      }
    } catch (e) {
      debugPrint('⚠️ Notification refresh error: $e');
    }
  }

  // ==================== BALANCE REFRESH - SILENT ====================

  /// Refresh dedicated account details
  Future<void> _refreshDedicatedAccount() async {
    if (_userId == null) return;

    setState(() => _isCheckingAccount = true);

    try {
      // Clear cache first
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString('user');
      if (userString != null) {
        try {
          final userMap = jsonDecode(userString);
          if (userMap['virtualAccount'] != null) {
            userMap['virtualAccount'] = null;
            await prefs.setString('user', jsonEncode(userMap));
          }
        } catch (e) {}
      }

      // Re-fetch
      await _checkDedicatedAccount();

      _showSuccessMessage('Account details refreshed');
    } catch (e) {
      debugPrint('Error refreshing account: $e');
      _showErrorMessage('Failed to refresh account');
    } finally {
      setState(() => _isCheckingAccount = false);
    }
  }

  Future<void> _refreshAllData() async {
    try {
      final results = await Future.wait([
        ApiService.getBalance(),
        ApiService.getCommissionBalance(),
        ApiService.getTransactions(),
      ]);

      final balance = results[0] as double;
      final commission = results[1] as double;
      final transactions = results[2] as List<dynamic>?;

      if (mounted) {
        setState(() {
          _walletBalance = balance;
          _commissionBalance = commission;
          if (transactions != null && transactions.isNotEmpty) {
            _recentTransactions = transactions.take(5).toList();
          }
        });
        await _saveBalanceToStorage(balance);
      }
    } catch (e) {
      debugPrint('Refresh error: $e');
    }
  }

  Future<void> _silentBackgroundRefresh() async {
    try {
      final freshBalance = await ApiService.getBalance().timeout(
        const Duration(seconds: 5),
      );
      if (!mounted) return;

      // ✅ Update whenever the value changed (even from non-zero to zero)
      if (freshBalance != _walletBalance) {
        setState(() {
          _walletBalance = freshBalance;
          _isBalanceReady = true; // safety
        });
        await _saveBalanceToStorage(freshBalance);
      }
    } catch (e) {
      // Silent fail - keep cached balance
    }
  }

  void _startSilentRefreshTimer() {
    _silentRefreshTimer?.cancel();
    _silentRefreshTimer = Timer.periodic(const Duration(minutes: 3), (timer) {
      if (!_isTransactionInProgress && mounted) {
        _silentBackgroundRefresh();
        _loadRecentTransactions();
      }
    });
  }

  // ==================== IDLE TIMER & LOGOUT ====================

  // In dashboard_screen.dart - Update the _startIdleTimer method

  void _startIdleTimer() {
    _idleLogoutTimer?.cancel();
    if (_isTransactionInProgress) return;

    _lastUserActivity = DateTime.now();
    // 🕐 20 MINUTES idle timeout (1200 seconds)
    // This gives users enough time to step away without being logged out
    const timeoutSeconds = 20 * 60; // 20 minutes (1200 seconds)
    // For testing, you can use: const timeoutSeconds = 5 * 60; // 5 minutes

    _idleLogoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_isTransactionInProgress) return;

      final idleSeconds =
          DateTime.now().difference(_lastUserActivity!).inSeconds;
      if (idleSeconds >= timeoutSeconds) {
        timer.cancel();
        _performAutoLogout();
      }
    });
  }

  void _resetIdleTimer() {
    _lastUserActivity = DateTime.now();
    if (!_isAppInBackground && !_isTransactionInProgress) {
      _idleLogoutTimer?.cancel();
      _startIdleTimer();
    }
    AuthService.updateLastActivity();
  }

  // Also update the background timer in _handleAppBackgrounded
  void _handleAppBackgrounded() {
    _idleLogoutTimer?.cancel();
    Timer? backgroundTimer;
    backgroundTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isAppInBackground && _lastUserActivity != null) {
        // 30 minutes background timeout (1800 seconds)
        if (DateTime.now().difference(_lastUserActivity!).inSeconds >=
            30 * 60) {
          timer.cancel();
          _performAutoLogout();
        }
      }
    });
  }

  // In dashboard_screen.dart - Fix _performAutoLogout
  Future<void> _performAutoLogout() async {
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();

    // ✅ PRESERVE ALL user data before clearing token
    if (_userId != null && _userId!.isNotEmpty) {
      await prefs.setString('userId', _userId!);
      await prefs.setString('fullName', _fullName);
      await prefs.setString('email', _email);

      final hasPin = prefs.getBool('transactionPinSet') ?? false;
      if (hasPin) {
        await prefs.setBool('transactionPinSet', true);
      }

      final bioEnabled = prefs.getBool('biometricEnabled') ?? false;
      if (bioEnabled) {
        await prefs.setBool('biometricEnabled', true);
      }
    }

    await prefs.setBool('autoLogout', true);
    await prefs.reload();

    if (!mounted) return;

    final hasPin = prefs.getBool('transactionPinSet') ?? false;

    if (hasPin && _userId != null && _userId!.isNotEmpty) {
      debugPrint('🔄 Auto-logout: Navigating to PIN login');
      // ✅ Use pushReplacementNamed
      Navigator.pushReplacementNamed(context, '/pin-login');
    } else {
      debugPrint('🔄 Auto-logout: No PIN set, navigating to login');
      // ✅ Use pushReplacementNamed
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  // ==================== LOGOUT (with confirmation) ====================

  /// Show a confirmation dialog before logging out.
  /// If the user confirms, `_performLogout()` is called.
  Future<void> _logout() async {
    final confirmed = await _showLogoutConfirmationDialog();
    if (confirmed == true) {
      await _performLogout();
    }
  }

  /// Beautiful confirmation dialog styled to match DalabaPay branding
  Future<bool?> _showLogoutConfirmationDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon with gradient circle
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.red.shade400.withValues(alpha: 0.15),
                        Colors.red.shade400.withValues(alpha: 0.05),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.logout_rounded,
                    color: Colors.red.shade400,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  'Logout?',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1C2D5A),
                  ),
                ),
                const SizedBox(height: 10),

                // Message
                Text(
                  'Are you sure you want to logout?\nYou can log back in with your PIN or Biometric.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF64748B),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),

                // Buttons
                Row(
                  children: [
                    // Cancel
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Logout
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        child: Text(
                          'Logout',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Performs the actual logout WITHOUT clearing the session data
  /// needed for PIN / Biometric re-login.
  Future<void> _performLogout() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logging out...', style: GoogleFonts.poppins()),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    try {
      // ✅ ApiService.logoutUser() now PRESERVES token, userId, user,
      //    biometric flag etc. — so PIN/Biometric re-login keeps working.
      await ApiService.logoutUser();

      // Cancel any running timers so they don't fire after navigation
      _idleLogoutTimer?.cancel();
      _silentRefreshTimer?.cancel();
      _notificationTimer?.cancel();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Logged out successfully',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: _successColor,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Small delay so the user sees the snackbar before we navigate
        await Future.delayed(const Duration(milliseconds: 350));
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (route) => false,
          );
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Logout error: $e');
      await ApiService.reportError(e, stackTrace);

      // ⚠️ IMPORTANT: DO NOT call prefs.clear() here.
      // That would wipe token/userId and break PIN/Biometric re-login.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logged out', style: GoogleFonts.poppins()),
            backgroundColor: _warningColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }

  void _redirectToLogin() {
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  // ==================== TRANSACTION STATE ====================

  void _startTransaction() {
    setState(() => _isTransactionInProgress = true);
    _idleLogoutTimer?.cancel();
  }

  void _endTransaction() {
    setState(() => _isTransactionInProgress = false);
    _startIdleTimer();
  }

  // ==================== NAVIGATION ====================

  void _navigateToService(String route) async {
    if (route.isEmpty) {
      _showComingSoon('This service');
      return;
    }

    // ✅ NEW: Block transactions if user is not approved
    if (_isPending) {
      _showPendingApprovalSnackBar();
      return;
    }

    if (_isRejected) {
      _showErrorMessage(
        'Your account has been rejected. Please contact support.',
      );
      return;
    }

    _startTransaction();
    try {
      final userId = _userId ?? '';

      // ✅ List of services that need userId and onBalanceUpdate
      if (route == '/data' ||
          route == '/internet' ||
          route == '/airtime' ||
          route == '/electricity' ||
          route == '/cable' ||
          route == '/cabletv' ||
          route == '/education' ||
          route == '/international-airtime' ||
          route == '/ticket' ||
          route == '/betting' ||
          route == '/insurance' ||
          route == '/donation') {
        await Navigator.pushNamed(
          context,
          route,
          arguments: {
            'userId': userId,
            'onBalanceUpdate': (double newBalance) {
              setState(() => _walletBalance = newBalance);
              _saveBalanceToStorage(newBalance);
            },
          },
        );
      } else {
        await Navigator.pushNamed(context, route);
      }
      await _silentBackgroundRefresh();
    } catch (e) {
      _showComingSoon(route.replaceFirst('/', ''));
    } finally {
      _endTransaction();
    }
    _resetIdleTimer();
  }

  void _navigateToAddMoney() {
    _startTransaction();
    Navigator.pushNamed(
      context,
      '/wallet',
      arguments: {
        'userId': _userId ?? '',
        'onBalanceUpdate': (double newBalance) {
          setState(() => _walletBalance = newBalance);
          _saveBalanceToStorage(newBalance);
        },
        'initialTab': 'add_money',
      },
    ).then((_) {
      // ✅ Reset to Home tab when returning
      if (mounted) setState(() => _selectedIndex = 0);
      _endTransaction();
      _silentBackgroundRefresh();
    });
    _resetIdleTimer();
  }

  void _navigateToCommission() {
    _startTransaction();
    Navigator.pushNamed(
      context,
      '/commission',
      arguments: {
        'userId': _userId ?? '',
        'onBalanceUpdate': (double newBalance) {
          setState(() => _walletBalance = newBalance);
          _saveBalanceToStorage(newBalance);
        },
      },
    ).then((_) {
      _endTransaction();
      _silentBackgroundRefresh();
    });
    _resetIdleTimer();
  }

  void _navigateToTransactions() {
    Navigator.pushNamed(context, '/transactions').then((_) {
      // ✅ Reset to Home tab when returning
      if (mounted) setState(() => _selectedIndex = 0);
      _silentBackgroundRefresh();
      _loadRecentTransactions();
    });
    _resetIdleTimer();
  }

  void _navigateToSettings() {
    Navigator.pushNamed(context, '/settings').then((_) {
      // ✅ Reset to Home tab when returning
      if (mounted) setState(() => _selectedIndex = 0);
      _silentBackgroundRefresh();
    });
    _resetIdleTimer();
  }

  void _navigateToNotifications() {
    Navigator.pushNamed(context, '/notifications').then((_) {
      _fetchUnreadNotificationCount();
    });
    _resetIdleTimer();
  }

  // ==================== NOTIFICATION ALERT DIALOG ====================

  /// Show a beautiful alert dialog for new notifications
  void _showNotificationAlert(Map<String, dynamic> notification) {
    if (!mounted) {
      debugPrint('⚠️ Widget not mounted, cannot show dialog');
      return;
    }

    final title = notification['title']?.toString() ?? 'New Notification';
    final message = notification['message']?.toString() ?? '';
    final type = notification['type']?.toString() ?? 'general';
    final notificationId =
        notification['_id']?.toString() ?? notification['id']?.toString() ?? '';
    final screen = notification['screen']?.toString() ?? 'notifications';
    final data = notification['data'] as Map<String, dynamic>? ?? {};

    debugPrint('📢 Showing alert dialog: "$title"');

    // Check if dialog is already showing
    if (ModalRoute.of(context)?.isCurrent != true) {
      debugPrint('⚠️ Another dialog is already showing, skipping');
      return;
    }

    showDialog(
          context: context,
          barrierDismissible: true, // ✅ CHANGED to true
          barrierColor: Colors.black.withOpacity(0.4), // ✅ Lighter overlay
          useRootNavigator: true, // ✅ Added
          builder:
              (BuildContext dialogContext) => _buildAlertDialog(
                title: title,
                message: message,
                type: type,
                notificationId: notificationId,
                screen: screen,
                data: data,
              ),
        )
        .then((_) {
          debugPrint('✅ Alert dialog dismissed');
          if (mounted) {
            _fetchUnreadNotificationCount();
          }
        })
        .catchError((e) {
          debugPrint('❌ Error showing dialog: $e');
        });
  }

  /// Build the alert dialog widget
  /// Build the alert dialog widget
  Widget _buildAlertDialog({
    required String title,
    required String message,
    required String type,
    required String notificationId,
    required String screen,
    required Map<String, dynamic> data,
  }) {
    final iconData = _getAlertIcon(type);
    final iconColor = _getAlertColor(type);
    final typeLabel = _getAlertTypeLabel(type);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: IntrinsicWidth(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400, minWidth: 280),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon with gradient background
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      iconColor.withOpacity(0.2),
                      iconColor.withOpacity(0.05),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: HugeIcon(icon: iconData, color: iconColor, size: 32),
                ),
              ),
              const SizedBox(height: 16),

              // Type badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: iconColor.withOpacity(0.2)),
                ),
                child: Text(
                  typeLabel,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: iconColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Title
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1C2D5A),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // Message
              Text(
                message,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: const Color(0xFF64748B),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Divider
              Divider(color: Colors.grey.shade100, thickness: 1),
              const SizedBox(height: 16),

              // Action buttons
              Row(
                children: [
                  // Dismiss button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        if (notificationId.isNotEmpty) {
                          _markNotificationAsRead(notificationId);
                        }
                        // ✅ Use Navigator.of(context, rootNavigator: true)
                        Navigator.of(context, rootNavigator: true).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Dismiss',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // View button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (notificationId.isNotEmpty) {
                          _markNotificationAsRead(notificationId);
                        }
                        // ✅ Use Navigator.of(context, rootNavigator: true)
                        Navigator.of(context, rootNavigator: true).pop();
                        _navigateFromNotification(screen, data);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF243889),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'View',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // ✅ Add a tap outside to dismiss (optional but helpful)
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  if (notificationId.isNotEmpty) {
                    _markNotificationAsRead(notificationId);
                  }
                  Navigator.of(context, rootNavigator: true).pop();
                },
                child: Text(
                  'Tap outside to dismiss',
                  style: GoogleFonts.inter(
                    color: Colors.grey.shade400,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Get icon based on notification type
  /// Get icon based on notification type
  /// Get icon based on notification type
  dynamic _getAlertIcon(String type) {
    switch (type.toLowerCase()) {
      case 'transaction':
      case 'payment_success':
        return HugeIcons.strokeRoundedCheckmarkCircle01;
      case 'payment_failed':
        return HugeIcons.strokeRoundedCancelCircle;
      case 'commission_earned':
        return HugeIcons.strokeRoundedMoney01;
      case 'wallet_credit':
      case 'wallet_funded':
        return HugeIcons.strokeRoundedWallet01;
      case 'transfer_sent':
        return HugeIcons.strokeRoundedSent02;
      case 'transfer_received':
        return HugeIcons.strokeRoundedDownload03;
      case 'referral_bonus':
        return HugeIcons.strokeRoundedUserAdd01;
      case 'announcement':
        return HugeIcons.strokeRoundedMegaphone01;
      case 'alert':
        return HugeIcons.strokeRoundedAlert02;
      default:
        return HugeIcons.strokeRoundedNotification01;
    }
  }

  /// Get color based on notification type
  Color _getAlertColor(String type) {
    switch (type.toLowerCase()) {
      case 'transaction':
      case 'payment_success':
      case 'wallet_credit':
      case 'wallet_funded':
      case 'transfer_received':
        return const Color(0xFF219C7E); // Green
      case 'payment_failed':
      case 'alert':
        return Colors.red.shade600;
      case 'commission_earned':
      case 'referral_bonus':
        return const Color(0xFFF59E0B); // Amber
      case 'transfer_sent':
        return const Color(0xFF3B82F6); // Blue
      case 'announcement':
        return const Color(0xFF8B5CF6); // Purple
      default:
        return const Color(0xFF243889); // Primary
    }
  }

  /// Get label for notification type
  String _getAlertTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'transaction':
      case 'payment_success':
        return 'SUCCESS';
      case 'payment_failed':
        return '❌ FAILED';
      case 'commission_earned':
        return '💰 COMMISSION';
      case 'wallet_credit':
      case 'wallet_funded':
        return '💳 WALLET';
      case 'transfer_sent':
        return '📤 SENT';
      case 'transfer_received':
        return '📥 RECEIVED';
      case 'referral_bonus':
        return '🎁 REFERRAL';
      case 'announcement':
        return '📢 ANNOUNCEMENT';
      case 'alert':
        return '⚠️ ALERT';
      default:
        return '📬 NOTIFICATION';
    }
  }

  void _markNotificationAsRead(String notificationId) {
    try {
      final socketService = SocketService();
      // Use socket if available
      if (socketService.isConnected) {
        socketService.markAsRead(notificationId);
        debugPrint('✅ Notification marked as read via socket: $notificationId');
      } else {
        // Fallback to API
        ApiService.markNotificationAsRead(notificationId);
        debugPrint('✅ Notification marked as read via API: $notificationId');
      }
    } catch (e) {
      debugPrint('❌ Error marking notification as read: $e');
    }
  }

  /// Navigate based on notification screen/data
  void _navigateFromNotification(String screen, Map<String, dynamic> data) {
    switch (screen) {
      case 'transactions':
        _navigateToTransactions();
        break;
      case 'wallet':
        _navigateToAddMoney();
        break;
      case 'commission':
        _navigateToCommission();
        break;
      case 'settings':
        _navigateToSettings();
        break;
      case 'kyc':
        _navigateToKYC();
        break;
      case 'service':
        final route = data['route'] ?? '/';
        _navigateToService(route);
        break;
      default:
        // Just go to notifications
        _navigateToNotifications();
        break;
    }
  }

  // ✅ Updated Coming Soon dialog with better UI
  void _showComingSoon(String serviceName) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Icon(
                  Icons.construction_outlined,
                  color: const Color(0xFF243889),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Coming Soon',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF243889),
                    fontSize: 20,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$serviceName will be available soon!',
                  style: GoogleFonts.inter(fontSize: 16, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF219C7E).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF219C7E).withOpacity(0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: const Color(0xFF219C7E),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'We\'re working hard to bring you this feature. Stay tuned!',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: const Color(0xFF219C7E),
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
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'OK',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF219C7E),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _showSuccessMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.inter()),
          backgroundColor: const Color(0xFF219C7E),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showPendingApprovalSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.hourglass_top_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Your account is under approval. You will be notified once an admin approves your account.',
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: _warningColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.inter()),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) return 'Just now';
        return '${difference.inMinutes} min ago';
      }
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return DateFormat('dd/MM/yyyy').format(date);
    }
  }

  // ==================== TRANSACTION ICON HELPERS ====================

  dynamic _getTransactionIcon(String type) {
    final typeLower = type.toLowerCase();

    // Airtime - matches dashboard "Airtime" service icon
    if (typeLower.contains('airtime')) {
      return HugeIcons.strokeRoundedSmartPhone01;
    }
    // Data - matches dashboard "Data" service icon
    if (typeLower.contains('data')) {
      return HugeIcons.strokeRoundedWifi01;
    }
    // Electricity - matches dashboard "Electricity" service icon
    if (typeLower.contains('electricity')) {
      return HugeIcons.strokeRoundedBulb;
    }
    // Cable TV - matches dashboard "Cable TV" service icon
    if (typeLower.contains('cable') || typeLower.contains('tv')) {
      return HugeIcons.strokeRoundedTv01;
    }
    // Education - matches dashboard "Education" service icon
    if (typeLower.contains('education')) {
      return HugeIcons.strokeRoundedMortarboard01;
    }
    // Insurance - matches dashboard "Insurance" service icon
    if (typeLower.contains('insurance')) {
      return HugeIcons.strokeRoundedShield01;
    }
    // Transfer - matches transactions screen
    if (typeLower.contains('transfer sent')) {
      return HugeIcons.strokeRoundedTelegram;
    }
    if (typeLower.contains('transfer received')) {
      return HugeIcons.strokeRoundedDownload03;
    }
    if (typeLower.contains('transfer')) {
      return HugeIcons.strokeRoundedSquareArrowDataTransferHorizontal;
    }
    // ✅ Fund Wallet - Use wallet/purse icon (same as transactions screen)
    if (typeLower.contains('fund') ||
        typeLower.contains('wallet') ||
        typeLower.contains('wallet funding') ||
        typeLower.contains('wallet top-up')) {
      return HugeIcons.strokeRoundedWallet01;
    }
    // Commission - matches dashboard "Commission" service icon
    if (typeLower.contains('commission')) {
      return HugeIcons.strokeRoundedPercent;
    }
    // Refund
    if (typeLower.contains('refund')) {
      return HugeIcons.strokeRoundedCash01;
    }
    // Betting
    if (typeLower.contains('betting')) {
      return HugeIcons.strokeRoundedDice;
    }
    // Internet
    if (typeLower.contains('internet')) {
      return HugeIcons.strokeRoundedGlobe;
    }
    // Tickets
    if (typeLower.contains('ticket')) {
      return HugeIcons.strokeRoundedTicket01;
    }
    // Donations
    if (typeLower.contains('donation')) {
      return HugeIcons.strokeRoundedGift;
    }
    // Default - matches dashboard receipt icon
    return HugeIcons.strokeRoundedReceiptText;
  }

  Color _getTransactionIconColor(String type) {
    final typeLower = type.toLowerCase();

    if (typeLower.contains('commission')) {
      return const Color(0xFF219C7E);
    }
    if (typeLower.contains('fund wallet') ||
        typeLower.contains('wallet funding')) {
      return const Color(0xFF219C7E);
    }
    if (typeLower.contains('transfer received')) return const Color(0xFF219C7E);
    if (typeLower.contains('refund')) return const Color(0xFF219C7E);
    if (typeLower.contains('airtime')) return const Color(0xFF4A90E2);
    if (typeLower.contains('data')) return const Color(0xFF9B59B6);
    if (typeLower.contains('electricity')) return const Color(0xFFF39C12);
    if (typeLower.contains('cable') || typeLower.contains('tv')) {
      return const Color(0xFFE74C3C);
    }
    if (typeLower.contains('education')) return const Color(0xFF2ECC71);
    if (typeLower.contains('insurance')) return const Color(0xFF1ABC9C);
    if (typeLower.contains('betting')) return const Color(0xFFE74C3C);
    if (typeLower.contains('internet')) return const Color(0xFF3498DB);
    if (typeLower.contains('transfer sent')) return Colors.orange;
    if (typeLower.contains('transfer')) return Colors.orange;
    if (typeLower.contains('failed')) return Colors.red;

    return const Color(0xFF243889);
  }

  Color _getAmountColor(String type, bool isCredit) {
    if (isCredit) return const Color(0xFF219C7E);

    final typeLower = type.toLowerCase();
    if (typeLower.contains('commission')) return const Color(0xFF219C7E);
    if (typeLower.contains('fund') || typeLower.contains('wallet')) {
      return const Color(0xFF219C7E);
    }
    if (typeLower.contains('withdraw')) return Colors.red;
    if (typeLower.contains('transfer')) return Colors.red;

    return Colors.red;
  }

  bool _isCreditTransaction(Map<String, dynamic> transaction) {
    final type = transaction['type']?.toString().toLowerCase() ?? '';
    final isCommission = transaction['isCommission'] == true;

    if (isCommission) return true;
    // ✅ Fund Wallet should always be credit
    if (type.contains('fund') ||
        type.contains('wallet') ||
        type.contains('wallet funding') ||
        type.contains('wallet top-up')) {
      return true;
    }
    if (type.contains('received')) return true;
    if (type.contains('credit')) return true;
    if (type.contains('commission')) return true;

    final description =
        transaction['description']?.toString().toLowerCase() ?? '';
    if (description.contains('credit') ||
        description.contains('received') ||
        description.contains('bonus') ||
        description.contains('fund') ||
        description.contains('wallet')) {
      return true;
    }

    return false;
  }

  String _formatBalance(double balance) {
    return balance.toStringAsFixed(2);
  }

  // ==================== SHOW RECEIPT ====================

  void _showTransactionReceipt(Map<String, dynamic> transaction) {
    final transactionType = transaction['type'] ?? 'Transaction';
    final amount = (transaction['amount'] ?? 0.0).toDouble();
    final status = transaction['status'] ?? 'completed';
    final transactionId =
        transaction['_id'] ?? transaction['transactionId'] ?? 'N/A';
    final reference =
        transaction['reference'] ?? transaction['transactionId'] ?? 'N/A';
    final date =
        transaction['createdAt'] != null
            ? DateTime.parse(transaction['createdAt'].toString())
            : DateTime.now();
    final description = transaction['description'] ?? '';
    final phoneNumber =
        transaction['phone']?.toString() ??
        transaction['phoneNumber']?.toString();
    final isCommission = transaction['isCommission'] == true;
    final gateway = 'Dalabapay App';

    String? balanceBefore;
    String? balanceAfter;

    final beforeRaw =
        transaction['balanceBefore'] ??
        transaction['previousBalance'] ??
        transaction['oldBalance'] ??
        transaction['metadata']?['previousBalance'];

    if (beforeRaw != null) {
      try {
        final numValue =
            beforeRaw is num ? beforeRaw : double.parse(beforeRaw.toString());
        balanceBefore = numValue.toStringAsFixed(2);
      } catch (e) {
        balanceBefore = beforeRaw.toString();
      }
    }

    final afterRaw =
        transaction['newBalance'] ??
        transaction['balanceAfter'] ??
        transaction['metadata']?['newBalance'];

    if (afterRaw != null) {
      try {
        final numValue =
            afterRaw is num ? afterRaw : double.parse(afterRaw.toString());
        balanceAfter = numValue.toStringAsFixed(2);
      } catch (e) {
        balanceAfter = afterRaw.toString();
      }
    }

    String? customerName;
    String? customerEmail;
    String? customerPhone;
    String? customerUserId;

    if (transaction['user'] != null) {
      final user = transaction['user'];
      customerName = user['fullName']?.toString();
      customerEmail = user['email']?.toString();
      customerPhone = user['phone']?.toString();
      customerUserId = user['_id']?.toString();
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => ReceiptWidget(
            transactionType: _getDisplayType(transactionType, description),
            amount: amount.toString(),
            status: status,
            transactionId: transactionId,
            reference: reference,
            date: date,
            phoneNumber: phoneNumber,
            description: description,
            balanceBefore: balanceBefore,
            balanceAfter: balanceAfter,
            gateway: gateway,
            isCommission: isCommission,
            commissionSource:
                isCommission ? _getCommissionSource(description) : null,
            primaryColor: const Color(0xFF243889),
            showWatermark: true,
            customerName: customerName,
            customerAddress: customerEmail,
            customerPhone: customerPhone,
            customerUserId: customerUserId,
            isAdminTransaction: _isAdminTransaction(transaction),
            isUserAdmin: false,
          ),
    );
    _resetIdleTimer();
  }

  String _getDisplayType(String type, String description) {
    final descLower = description.toLowerCase();

    if (type.contains('Airtime') || descLower.contains('airtime')) {
      return 'Airtime Purchase';
    }
    if (type.contains('Data') || descLower.contains('data')) {
      return 'Data Purchase';
    }
    if (type.contains('Electricity') || descLower.contains('electricity')) {
      return 'Electricity Purchase';
    }
    if (type.contains('Cable') ||
        descLower.contains('cable') ||
        descLower.contains('tv')) {
      return 'Cable TV Purchase';
    }
    if (type.contains('Commission') || descLower.contains('commission')) {
      return 'Commission';
    }
    if (type.contains('Transfer')) return 'Transfer';
    // ✅ FIX: Better detection for Fund Wallet
    if (type.contains('Wallet') ||
        type.contains('Fund') ||
        descLower.contains('fund') ||
        descLower.contains('wallet funding') ||
        descLower.contains('wallet top-up') ||
        descLower.contains('wallet funding')) {
      return 'Fund Wallet';
    }
    if (type.contains('Withdraw')) return 'Withdrawal';

    return type.isNotEmpty ? type : 'Transaction';
  }

  String _getCommissionSource(String description) {
    final descLower = description.toLowerCase();
    if (descLower.contains('airtime')) return 'Airtime';
    if (descLower.contains('data')) return 'Data';
    if (descLower.contains('electricity')) return 'Electricity';
    if (descLower.contains('cable') || descLower.contains('tv')) {
      return 'Cable TV';
    }
    if (descLower.contains('education')) return 'Education';
    if (descLower.contains('insurance')) return 'Insurance';
    if (descLower.contains('transfer')) return 'Transfer';
    if (descLower.contains('referral')) return 'Referral';
    if (descLower.contains('welcome')) return 'Welcome Bonus';
    if (descLower.contains('first deposit')) return 'First Deposit';
    return 'Service';
  }

  bool _isAdminTransaction(Map<String, dynamic> transaction) {
    return transaction['user'] != null ||
        transaction['isAdmin'] == true ||
        transaction['adminNote'] != null;
  }

  // ==================== BUILD METHODS ====================

  Widget _buildAppBar(bool isSmallScreen) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(Icons.menu, color: const Color(0xFF243889), size: 22),
              onPressed: () {
                _scaffoldKey.currentState?.openDrawer();
              },
              padding: EdgeInsets.zero,
            ),
          ),
          Image.asset('assets/dalabapay2.png', height: 40, fit: BoxFit.contain),
          Row(
            children: [
              // ✅ Manual refresh button
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.refresh,
                    color: const Color(0xFF243889),
                    size: 22,
                  ),
                  onPressed: () async {
                    debugPrint('🔄 Manual refresh triggered');
                    await _fetchUnreadNotificationCount();
                    await _fetchAndShowNewNotifications();
                  },
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 8),
              Stack(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.notifications_none,
                        color: const Color(0xFF243889),
                        size: 22,
                      ),
                      onPressed: _navigateToNotifications,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  if (_unreadNotificationCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF219C7E),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isSmallScreen) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: isSmallScreen ? 14 : 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF243889),
            ),
          ),
          GestureDetector(
            onTap: () => _showAllServices(isSmallScreen),
            child: Row(
              children: [
                Text(
                  'See all',
                  style: GoogleFonts.inter(
                    fontSize: isSmallScreen ? 10 : 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF219C7E),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_ios,
                  size: isSmallScreen ? 8 : 10,
                  color: const Color(0xFF219C7E),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== APPROVAL STATUS BANNER ====================

  Widget _buildApprovalBanner(bool isSmallScreen) {
    // Don't show banner for approved users
    if (_isApproved) return const SizedBox.shrink();

    final isPending = _isPending;
    final bannerColor = isPending ? _warningColor : Colors.red;
    final bgColor =
        isPending
            ? _warningColor.withValues(alpha: 0.10)
            : Colors.red.withValues(alpha: 0.08);
    final borderColor =
        isPending
            ? _warningColor.withValues(alpha: 0.30)
            : Colors.red.withValues(alpha: 0.25);

    final icon = isPending ? Icons.hourglass_top_rounded : Icons.cancel_rounded;

    final title = isPending ? 'Account Under Approval' : 'Account Rejected';

    final message =
        isPending
            ? 'You can browse and add funds, but transactions are disabled until an admin approves your account. This usually takes a few minutes.'
            : (_rejectionReason?.isNotEmpty == true
                ? _rejectionReason!
                : 'Your account has been rejected. Please contact support for more details.');

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 24 : 24,
        vertical: 12,
      ),
      padding: EdgeInsets.all(isSmallScreen ? 14 : 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bannerColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: bannerColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: isSmallScreen ? 14 : 15,
                    fontWeight: FontWeight.w700,
                    color: bannerColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: GoogleFonts.inter(
                    fontSize: isSmallScreen ? 12 : 13,
                    color: const Color(0xFF1C2D5A),
                    height: 1.4,
                  ),
                ),
                if (isPending) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      debugPrint('🔄 [DASHBOARD] Checking approval status...');

                      // Show quick loading toast
                      if (mounted) {
                        _showSuccessMessage('🔄 Checking status...');
                      }

                      // ✅ Re-fetch BOTH toggle and user status
                      await _refreshApprovalStatus();

                      if (!mounted) return;

                      // Evaluate what changed
                      if (!_approvalSystemEnabled) {
                        _showSuccessMessage(
                          '✅ Approval system is OFF — you can transact now.',
                        );
                      } else if (_isApproved) {
                        _showSuccessMessage(
                          '🎉 Your account has been approved!',
                        );
                      } else if (_isPending) {
                        _showErrorMessage(
                          '⏳ Still waiting for admin approval. Please check back in a few minutes.',
                        );
                      } else if (_isRejected) {
                        _showErrorMessage(
                          '❌ Your account has been rejected. Please contact support.',
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: bannerColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            color: bannerColor,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Check Status',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: bannerColor,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildBalanceCard(bool isSmallScreen) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF92D394), Color(0xFF1E377E)],
          stops: [0.06, 0.41],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF219C7E).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Main Wallet',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: isSmallScreen ? 10 : 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _silentBackgroundRefresh,
                      child: Icon(
                        Icons.refresh,
                        color: Colors.white,
                        size: isSmallScreen ? 16 : 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap:
                          () => setState(
                            () => _isBalanceVisible = !_isBalanceVisible,
                          ),
                      child: Icon(
                        _isBalanceVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.white,
                        size: isSmallScreen ? 16 : 18,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _isBalanceVisible
                  ? '₦${_formatBalance(_walletBalance)}'
                  : '••••••••',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Available Balance',
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: isSmallScreen ? 10 : 12,
              ),
            ),

            // ============================================================
            // ✅ DEDICATED ACCOUNT SECTION - FIXED RESPONSIVE
            // ============================================================
            const SizedBox(height: 16),

            // ── Checking State ──────────────────────────────────────────
            if (_isCheckingAccount) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Checking dedicated account...',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: isSmallScreen ? 11 : 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // ── Has Account ─────────────────────────────────────────────
            if (_hasDedicatedAccount) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Label + Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.account_balance,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Dedicated Account',
                              style: GoogleFonts.inter(
                                color: Colors.white70,
                                fontSize: isSmallScreen ? 9 : 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            // Copy button
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(
                                    text: _dedicatedAccountNumber ?? '',
                                  ),
                                );
                                _showSuccessMessage('Account number copied!');
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.copy,
                                  color: Colors.white70,
                                  size: isSmallScreen ? 12 : 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Refresh button
                            GestureDetector(
                              onTap: _refreshDedicatedAccount,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.refresh,
                                  color: Colors.white70,
                                  size: isSmallScreen ? 12 : 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Row 2: Account Number (LEFT ALIGNED - NO CENTER)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          // ✅ Account Number - LEFT ALIGNED
                          Expanded(
                            child: SelectableText(
                              _dedicatedAccountNumber ?? 'N/A',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: isSmallScreen ? 16 : 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                              textAlign: TextAlign.left, // ✅ LEFT ALIGNED
                            ),
                          ),
                          // Status Badge - Right side of account number row
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Active',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: isSmallScreen ? 8 : 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Row 3: Bank Name (Left aligned)
                    if (_dedicatedBankName != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _dedicatedBankName!,
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontSize: isSmallScreen ? 9 : 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                    // Row 4: Account Name (if available)
                    if (_dedicatedAccountName != null &&
                        _dedicatedAccountName!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        child: Text(
                          _dedicatedAccountName!,
                          style: GoogleFonts.inter(
                            color: Colors.white70,
                            fontSize: isSmallScreen ? 10 : 11,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.left,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            // ── No Account ──────────────────────────────────────────────
            if (!_isCheckingAccount && !_hasDedicatedAccount) ...[
              GestureDetector(
                onTap: _navigateToKYC,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Get Your Dedicated Account',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: isSmallScreen ? 11 : 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white70,
                        size: isSmallScreen ? 12 : 14,
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    'Add Money',
                    Icons.add,
                    const Color(0xFF219C7E),
                    Colors.white,
                    _navigateToAddMoney,
                    isSmallScreen,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    'Commission',
                    Icons.percent,
                    Colors.white,
                    Colors.white,
                    _navigateToCommission,
                    isSmallScreen,
                    outlined: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernBalanceCard(bool isSmallScreen) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF243889), Color(0xFF1E377E), Color(0xFF92D394)],
            stops: [0.0, 0.5, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF243889).withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // Decorative circles
              Positioned(
                top: -40,
                right: -40,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
              Positioned(
                bottom: -60,
                left: -30,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.account_balance_wallet,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Main Wallet',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: isSmallScreen ? 11 : 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                _silentBackgroundRefresh();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.refresh,
                                  color: Colors.white,
                                  size: isSmallScreen ? 14 : 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                setState(
                                  () => _isBalanceVisible = !_isBalanceVisible,
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  _isBalanceVisible
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: Colors.white,
                                  size: isSmallScreen ? 14 : 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Balance — shows shimmer until we have a real value
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder:
                          (child, animation) => FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.2),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                      child:
                          // ✅ While balance not yet ready → show animated shimmer pill
                          !_isBalanceReady
                              ? _buildBalanceLoadingPlaceholder(isSmallScreen)
                              : Text(
                                _isBalanceVisible
                                    ? '₦${_formatBalance(_walletBalance)}'
                                    : '••••••••',
                                key: ValueKey(
                                  'bal_${_isBalanceVisible}_$_walletBalance',
                                ),
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: isSmallScreen ? 26 : 30,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Available Balance',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: isSmallScreen ? 10 : 12,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Dedicated Account Section
                    _buildDedicatedAccountSection(isSmallScreen),

                    const SizedBox(height: 20),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: _buildModernActionButton(
                            'Add Money',
                            Icons.add_rounded,
                            true,
                            _navigateToAddMoney,
                            isSmallScreen,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildModernActionButton(
                            'Commission',
                            Icons.percent_rounded,
                            false,
                            _navigateToCommission,
                            isSmallScreen,
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
  }

  /// Small animated shimmer pill shown while balance is loading.
  /// Matches the text height so nothing jumps when the real number arrives.
  Widget _buildBalanceLoadingPlaceholder(bool isSmallScreen) {
    return Container(
      height: isSmallScreen ? 34 : 40,
      width: isSmallScreen ? 160 : 190,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 12),
          SizedBox(
            width: isSmallScreen ? 16 : 18,
            height: isSmallScreen ? 16 : 18,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Loading...',
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: isSmallScreen ? 12 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDedicatedAccountSection(bool isSmallScreen) {
    if (_isCheckingAccount) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Checking account...',
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: isSmallScreen ? 11 : 13,
              ),
            ),
          ],
        ),
      );
    }

    if (_hasDedicatedAccount) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.account_balance,
                        color: Colors.white,
                        size: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Dedicated Account',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: isSmallScreen ? 9 : 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Clipboard.setData(
                          ClipboardData(text: _dedicatedAccountNumber ?? ''),
                        );
                        _showSuccessMessage('Account number copied!');
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.copy_rounded,
                          color: Colors.white70,
                          size: isSmallScreen ? 12 : 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _refreshDedicatedAccount();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.refresh_rounded,
                          color: Colors.white70,
                          size: isSmallScreen ? 12 : 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Account Number - LEFT ALIGNED
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _dedicatedAccountNumber ?? 'N/A',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: isSmallScreen ? 16 : 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Active',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: isSmallScreen ? 8 : 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // Bank Name - LEFT ALIGNED
            if (_dedicatedBankName != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Text(
                  _dedicatedBankName!,
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: isSmallScreen ? 10 : 11,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.left,
                ),
              ),
            // Account Name - LEFT ALIGNED
            if (_dedicatedAccountName != null &&
                _dedicatedAccountName!.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                child: Text(
                  _dedicatedAccountName!,
                  style: GoogleFonts.inter(
                    color: Colors.white60,
                    fontSize: isSmallScreen ? 10 : 11,
                  ),
                  textAlign: TextAlign.left,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      );
    }

    // No account
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _navigateToKYC();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Get Your Dedicated Account',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: isSmallScreen ? 11 : 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.white70,
              size: isSmallScreen ? 12 : 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernActionButton(
    String title,
    IconData icon,
    bool isPrimary,
    VoidCallback onTap,
    bool isSmallScreen,
  ) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 11 : 13),
        decoration: BoxDecoration(
          color: isPrimary ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border:
              isPrimary
                  ? null
                  : Border.all(color: Colors.white.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isPrimary ? const Color(0xFF243889) : Colors.white,
              size: isSmallScreen ? 15 : 17,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: isSmallScreen ? 11 : 13,
                fontWeight: FontWeight.w600,
                color: isPrimary ? const Color(0xFF243889) : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    String title,
    IconData icon,
    Color textColor,
    Color borderColor,
    VoidCallback onTap,
    bool isSmallScreen, {
    bool outlined = false,
  }) {
    if (outlined) {
      return InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 10 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: borderColor, size: isSmallScreen ? 14 : 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: isSmallScreen ? 10 : 12,
                  fontWeight: FontWeight.w600,
                  color: borderColor,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 10 : 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor, size: isSmallScreen ? 14 : 16),
            const SizedBox(width: 6),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: isSmallScreen ? 10 : 12,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServicesGrid(
    List<Map<String, dynamic>> services,
    bool isSmallScreen,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;

    // Mobile-first responsive sizing
    final double iconSize;
    final double fontSize;
    final int crossAxisCount;
    final double childAspectRatio;
    final double crossAxisSpacing;
    final double mainAxisSpacing;
    final double horizontalPadding;

    if (screenWidth < 360) {
      // Very small phones
      iconSize = 26.0;
      fontSize = 8.0;
      crossAxisCount = 4;
      childAspectRatio = 0.70;
      crossAxisSpacing = 4.0;
      mainAxisSpacing = 4.0;
      horizontalPadding = 0.0;
    } else if (screenWidth < 400) {
      // Small phones
      iconSize = 30.0;
      fontSize = 9.0;
      crossAxisCount = 4;
      childAspectRatio = 0.75;
      crossAxisSpacing = 6.0;
      mainAxisSpacing = 6.0;
      horizontalPadding = 0.0;
    } else if (screenWidth < 600) {
      // Medium phones
      iconSize = 34.0;
      fontSize = 10.0;
      crossAxisCount = 4;
      childAspectRatio = 0.80;
      crossAxisSpacing = 8.0;
      mainAxisSpacing = 8.0;
      horizontalPadding = 0.0;
    } else if (screenWidth < 900) {
      // Tablets
      iconSize = 40.0;
      fontSize = 11.0;
      crossAxisCount = 6;
      childAspectRatio = 0.85;
      crossAxisSpacing = 12.0;
      mainAxisSpacing = 12.0;
      horizontalPadding = 4.0;
    } else {
      // Large screens
      iconSize = 44.0;
      fontSize = 12.0;
      crossAxisCount = 8;
      childAspectRatio = 0.90;
      crossAxisSpacing = 16.0;
      mainAxisSpacing = 16.0;
      horizontalPadding = 8.0;
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: crossAxisSpacing,
          mainAxisSpacing: mainAxisSpacing,
          childAspectRatio: childAspectRatio,
        ),
        itemCount: services.length,
        itemBuilder: (context, index) {
          final service = services[index];
          final isHugeIcon = service['isHugeIcon'] ?? false;
          final iconColor = service['iconColor'] ?? const Color(0xFF243889);
          final isComingSoon = service['comingSoon'] ?? false;

          return InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              if (isComingSoon) {
                _showComingSoon(service['name']);
                return;
              }
              if (service['route'] != null &&
                  service['route'].toString().isNotEmpty) {
                _navigateToService(service['route']);
              } else {
                _showComingSoon(service['name']);
              }
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isComingSoon ? Colors.grey.shade50 : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: EdgeInsets.symmetric(
                vertical: screenWidth < 400 ? 6 : 10,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.all(screenWidth < 400 ? 6 : 8),
                    decoration: BoxDecoration(
                      color:
                          isComingSoon
                              ? Colors.grey.shade200
                              : iconColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child:
                        isHugeIcon
                            ? HugeIcon(
                              icon: service['icon'],
                              size: iconSize,
                              color:
                                  isComingSoon
                                      ? Colors.grey.shade400
                                      : iconColor,
                            )
                            : ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                service['iconUrl'],
                                width: iconSize,
                                height: iconSize,
                                fit: BoxFit.contain,
                                color:
                                    isComingSoon ? Colors.grey.shade400 : null,
                                errorBuilder:
                                    (context, error, stackTrace) => Container(
                                      width: iconSize,
                                      height: iconSize,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.image_not_supported,
                                        size: iconSize - 8,
                                        color:
                                            isComingSoon
                                                ? Colors.grey.shade400
                                                : Colors.grey[400],
                                      ),
                                    ),
                              ),
                            ),
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: Text(
                      service['name'],
                      style: GoogleFonts.inter(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        color:
                            isComingSoon
                                ? Colors.grey.shade500
                                : const Color(0xFF243889),
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentTransactions(bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Transactions',
                style: GoogleFonts.poppins(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF243889),
                ),
              ),
              GestureDetector(
                onTap: _navigateToTransactions,
                child: Row(
                  children: [
                    Text(
                      'View all',
                      style: GoogleFonts.inter(
                        fontSize: isSmallScreen ? 10 : 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF219C7E),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: isSmallScreen ? 8 : 10,
                      color: const Color(0xFF219C7E),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (_isLoadingTransactions)
          _buildShimmerTransactions(isSmallScreen)
        else if (_recentTransactions.isEmpty)
          _buildEmptyTransactions(isSmallScreen)
        else
          RepaintBoundary(
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount:
                  _recentTransactions.length > 5
                      ? 5
                      : _recentTransactions.length,
              itemBuilder:
                  (context, index) => _buildTransactionItem(
                    _recentTransactions[index],
                    isSmallScreen,
                  ),
            ),
          ),
      ],
    );
  }

  Widget _buildTransactionItem(
    Map<String, dynamic> transaction,
    bool isSmallScreen,
  ) {
    final isCredit = _isCreditTransaction(transaction);
    final amount = (transaction['amount'] ?? 0.0).toDouble();
    final status = transaction['status'] ?? 'completed';
    final date =
        transaction['createdAt'] != null
            ? DateTime.parse(transaction['createdAt'].toString())
            : DateTime.now();
    final description = transaction['description'] ?? 'Transaction';
    final type = transaction['type'] ?? 'Transaction';
    final isCommission = transaction['isCommission'] == true;

    // ✅ Get the HugeIcon
    final icon = _getTransactionIcon(type);
    final iconColor = _getTransactionIconColor(type);
    final amountColor = _getAmountColor(type, isCredit);

    return GestureDetector(
      onTap: () => _showTransactionReceipt(transaction),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // ✅ Use HugeIcon instead of Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: HugeIcon(icon: icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    description,
                    style: GoogleFonts.inter(
                      fontSize: isSmallScreen ? 13 : 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1C2D5A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(date),
                    style: GoogleFonts.inter(
                      fontSize: isSmallScreen ? 10 : 11,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${isCredit ? '+' : '-'}₦${_formatBalance(amount)}',
                  style: GoogleFonts.inter(
                    fontSize: isSmallScreen ? 13 : 14,
                    fontWeight: FontWeight.w700,
                    color: amountColor,
                  ),
                ),
                const SizedBox(height: 2),
                if (isCommission)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF219C7E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'COMMISSION',
                      style: GoogleFonts.inter(
                        fontSize: isSmallScreen ? 7 : 8,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF219C7E),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color:
                          status == 'completed'
                              ? const Color(0xFF219C7E).withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status == 'completed' ? 'Success' : status,
                      style: GoogleFonts.inter(
                        fontSize: isSmallScreen ? 7 : 8,
                        fontWeight: FontWeight.w600,
                        color:
                            status == 'completed'
                                ? const Color(0xFF219C7E)
                                : Colors.orange,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerTransactions(bool isSmallScreen) {
    return Column(
      children: List.generate(
        3,
        (index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              height: isSmallScreen ? 60 : 72,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyTransactions(bool isSmallScreen) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: EdgeInsets.all(isSmallScreen ? 20 : 32),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long,
            size: isSmallScreen ? 36 : 48,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 12),
          Text(
            'No transactions yet',
            style: GoogleFonts.inter(
              fontSize: isSmallScreen ? 12 : 14,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your transactions will appear here',
            style: GoogleFonts.inter(
              fontSize: isSmallScreen ? 10 : 12,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomBottomNavBar(bool isSmallScreen) {
    final List<Map<String, dynamic>> navItems = [
      {
        'icon': HugeIcons.strokeRoundedHome01,
        'label': 'Home',
        'index': 0,
        'isHugeIcon': true,
      },
      {
        'icon': HugeIcons.strokeRoundedReceiptText,
        'label': 'Transactions',
        'index': 1,
        'isHugeIcon': true,
      },
      {
        'icon': HugeIcons.strokeRoundedWallet01,
        'label': 'Wallets',
        'index': 2,
        'isHugeIcon': true,
      },
      {
        'icon': HugeIcons.strokeRoundedSettings01,
        'label': 'Settings',
        'index': 3,
        'isHugeIcon': true,
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
        left: 12,
        right: 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children:
            navItems.map((item) {
              final isSelected = _selectedIndex == item['index'];
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    // ✅ Haptic feedback
                    HapticFeedback.lightImpact();

                    // ✅ Fix double-click: update index immediately
                    if (_selectedIndex != item['index']) {
                      setState(() => _selectedIndex = item['index']);
                    }

                    // ✅ Navigate based on index
                    switch (item['index']) {
                      case 0:
                        // Home - do nothing, already here
                        break;
                      case 1:
                        _navigateToTransactions();
                        break;
                      case 2:
                        _navigateToAddMoney();
                        break;
                      case 3:
                        _navigateToSettings();
                        break;
                    }
                    _resetIdleTimer();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubic,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      // ✅ Active pill background
                      color:
                          isSelected
                              ? const Color(0xFF243889).withValues(alpha: 0.08)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedScale(
                          scale: isSelected ? 1.15 : 1.0,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutBack,
                          child: HugeIcon(
                            icon: item['icon'],
                            size: 22,
                            color:
                                isSelected
                                    ? const Color(0xFF243889)
                                    : const Color(0xFF9AA0A6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 250),
                          style: TextStyle(
                            color:
                                isSelected
                                    ? const Color(0xFF243889)
                                    : const Color(0xFF9AA0A6),
                            fontSize: 11,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            fontFamily: GoogleFonts.inter().fontFamily,
                          ),
                          child: Text(item['label']),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildDrawerTile(
    IconData icon,
    String title,
    VoidCallback onTap, {
    bool isLogout = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isLogout ? Colors.red : const Color(0xFF243889),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          color: isLogout ? Colors.red : const Color(0xFF243889),
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }

  void _showAllServices(bool isSmallScreen) {
    final allServices = [..._quickServices, ..._otherServices];
    final iconSize = 36.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.8,
            maxChildSize: 0.9,
            minChildSize: 0.5,
            expand: false,
            builder: (context, scrollController) {
              return Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'All Services',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF243889),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: GridView.builder(
                        controller: scrollController,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: isSmallScreen ? 8 : 12,
                          mainAxisSpacing: isSmallScreen ? 8 : 12,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: allServices.length,
                        itemBuilder: (context, index) {
                          final service = allServices[index];
                          final isHugeIcon = service['isHugeIcon'] ?? false;
                          final iconColor =
                              service['iconColor'] ?? const Color(0xFF243889);
                          final isComingSoon = service['comingSoon'] ?? false;

                          return InkWell(
                            onTap: () {
                              if (Navigator.canPop(context)) {
                                if (Navigator.canPop(context)) {
                                  Navigator.pop(context);
                                } else {
                                  // Navigate to a fallback screen
                                  Navigator.pushReplacementNamed(
                                    context,
                                    '/home',
                                  );
                                }
                              } else {
                                // Navigate to a fallback screen
                                Navigator.pushReplacementNamed(
                                  context,
                                  '/home',
                                );
                              }
                              if (isComingSoon) {
                                _showComingSoon(service['name']);
                                return;
                              }
                              if (service['route'] != null &&
                                  service['route'].toString().isNotEmpty) {
                                _navigateToService(service['route']);
                              } else {
                                _showComingSoon(service['name']);
                              }
                            },
                            child: Stack(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color:
                                        isComingSoon
                                            ? Colors.grey.shade50
                                            : Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.03),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    vertical: isSmallScreen ? 10 : 12,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      isHugeIcon
                                          ? HugeIcon(
                                            icon: service['icon'],
                                            size: iconSize,
                                            color:
                                                isComingSoon
                                                    ? Colors.grey.shade400
                                                    : iconColor,
                                          )
                                          : ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: Image.network(
                                              service['iconUrl'],
                                              width: iconSize,
                                              height: iconSize,
                                              fit: BoxFit.contain,
                                              color:
                                                  isComingSoon
                                                      ? Colors.grey.shade400
                                                      : null,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => Container(
                                                    width: iconSize,
                                                    height: iconSize,
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey[100],
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    child: Icon(
                                                      Icons.image_not_supported,
                                                      size: iconSize - 8,
                                                      color:
                                                          isComingSoon
                                                              ? Colors
                                                                  .grey
                                                                  .shade400
                                                              : Colors
                                                                  .grey[400],
                                                    ),
                                                  ),
                                            ),
                                          ),
                                      const SizedBox(height: 8),
                                      Text(
                                        service['name'],
                                        style: GoogleFonts.inter(
                                          fontSize: isSmallScreen ? 9 : 10,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              isComingSoon
                                                  ? Colors.grey.shade500
                                                  : const Color(0xFF243889),
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (isComingSoon)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF219C7E),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'Soon',
                                        style: GoogleFonts.inter(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
    );
  }

  // ==================== CUSTOM DRAWER METHODS ====================

  Widget _buildDrawerHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            const Color(0xFF243889),
            const Color(0xFF243889).withValues(alpha: 0.8),
          ],
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
                  _fullName.isNotEmpty ? _fullName[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF243889),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fullName.isNotEmpty ? _fullName : 'User',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _email.isNotEmpty ? _email : 'user@example.com',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  List<DrawerItem> _getUserDrawerItems() {
    final bool isAdmin = _isAdmin;

    final items = <DrawerItem>[];

    // All Services - everyone
    items.add(
      const DrawerItem(
        title: "All Services",
        icon: Icons.apps,
        page: DashboardScreen(),
      ),
    );

    // Admin items - only show if user is admin
    if (isAdmin) {
      items.addAll([
        const DrawerItem(
          title: "Admin Dashboard",
          icon: Icons.dashboard,
          badge: "ADMIN",
          page: AdminDashboardScreen(),
          isAdminOnly: true,
        ),
        const DrawerItem(
          title: "Manage Users",
          icon: Icons.people_alt,
          page: AdminUsersPage(),
          isAdminOnly: true,
        ),
        // ✅ ADD TRANSACTION LIMITS HERE
        const DrawerItem(
          title: "Transaction Limits",
          icon: Icons.speed,
          page: AdminTransactionLimitsPage(),
          isAdminOnly: true,
        ),
        const DrawerItem(
          title: "Transactions",
          icon: Icons.receipt,
          page: AdminAllTransactionsPage(),
          isAdminOnly: true,
        ),
        const DrawerItem(
          title: "Status Update",
          icon: Icons.update,
          page: AdminTransactionStatusPage(),
          isAdminOnly: true,
        ),
        const DrawerItem(
          title: "Refund System",
          icon: Icons.currency_exchange,
          page: AdminRefundSystemPage(),
          isAdminOnly: true,
        ),
        const DrawerItem(
          title: "Fund Wallet",
          icon: Icons.account_balance_wallet,
          page: AdminFundWalletPage(),
          isAdminOnly: true,
        ),
        const DrawerItem(
          title: "VTpass Settings",
          icon: Icons.api,
          page: VtpassSettingsDashboard(),
          isAdminOnly: true,
        ),
        const DrawerItem(
          title: "Self Fund",
          icon: Icons.attach_money,
          page: AdminSelfFundPage(),
          isAdminOnly: true,
        ),
        const DrawerItem(
          title: "Verify Payments",
          icon: Icons.verified,
          page: AdminVerifyPaymentPage(),
          isAdminOnly: true,
        ),
        const DrawerItem(
          title: "Notifications",
          icon: Icons.notifications_active,
          page: AdminSendNotificationPage(),
          isAdminOnly: true,
        ),
        const DrawerItem(
          title: "Admin Control",
          icon: Icons.settings_applications,
          page: AdminControlPage(),
          isAdminOnly: true,
        ),
        const DrawerItem(
          title: "Service Commission",
          icon: Icons.trending_up,
          badge: "ADMIN",
          page: AdminServiceCommissionPage(),
          isAdminOnly: true,
        ),
      ]);
    }

    // User items - everyone
    items.addAll([
      const DrawerItem(
        title: "Transaction Validation",
        icon: Icons.verified_user,
        page: TransactionValidationPage(),
      ),
      const DrawerItem(
        title: "My Disputes",
        icon: Icons.gavel,
        page: UserDisputesPage(),
      ),
      const DrawerItem(
        title: "App Settings",
        icon: Icons.settings,
        page: SettingsScreen(),
      ),
      const DrawerItem(
        title: "Logout",
        icon: Icons.logout,
        page: SizedBox.shrink(),
      ),
    ]);

    return items;
  }

  DrawerItem _getSelectedDrawerItem() {
    return _getUserDrawerItems().first;
  }

  void _onDrawerItemSelected(DrawerItem item) {
    if (item.title == "Logout") {
      _logout();
      return;
    }
    if (item.title == "App Settings" || item.title == "Settings") {
      Navigator.pushNamed(context, '/settings');
      return;
    }
    if (item.title == "All Services") {
      if (Navigator.canPop(context)) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
      return;
    }
    if (item.title == "Admin Dashboard") {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AdminDashboardScreen()),
      );
      return;
    }
    // ✅ ADD TRANSACTION LIMITS NAVIGATION
    if (item.title == "Transaction Limits") {
      if (Navigator.canPop(context)) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const AdminTransactionLimitsPage(),
        ),
      );
      return;
    }
    if (item.title == "Service Commission") {
      if (Navigator.canPop(context)) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const AdminServiceCommissionPage(),
        ),
      );
      return;
    }
    if (item.title == "Transaction Validation") {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const TransactionValidationPage(),
        ),
      );
      return;
    }
    if (item.title == "My Disputes") {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const UserDisputesPage()),
      );
      return;
    }
    // Navigate to admin pages
    if (item.page is! SizedBox) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => item.page),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;

    return GestureDetector(
      onTap: _resetIdleTimer,
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        key: _scaffoldKey, // ✅ ADD THIS LINE
        backgroundColor: Colors.white,
        drawer:
            _isLoading
                ? Drawer(
                  child: Column(
                    children: [
                      _buildDrawerHeader(),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Shimmer.fromColors(
                          baseColor: Colors.grey[300]!,
                          highlightColor: Colors.grey[100]!,
                          child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: [
                              _buildSkeletonTile(),
                              _buildSkeletonTile(),
                              _buildSkeletonTile(),
                              _buildSkeletonTile(),
                              _buildSkeletonTile(),
                              _buildSkeletonTile(),
                              _buildSkeletonTile(),
                              _buildSkeletonTile(),
                              _buildSkeletonTile(),
                              _buildSkeletonTile(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                : CustomDrawer(
                  header: _buildDrawerHeader(),
                  items: _getUserDrawerItems(),
                  selectedItem: _getSelectedDrawerItem(),
                  onItemSelected: _onDrawerItemSelected,
                  isAdmin: _isAdmin,
                ),
        body: SafeArea(
          child: Column(
            children: [
              _buildAppBar(isSmallScreen),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ✅ NEW: Approval status banner (only shows for pending/rejected)
                      _buildApprovalBanner(isSmallScreen),

                      _buildModernBalanceCard(isSmallScreen),
                      const SizedBox(height: 24),
                      _buildSectionHeader('Quick Services', isSmallScreen),
                      const SizedBox(height: 16),
                      _buildServicesGrid(_quickServices, isSmallScreen),
                      const SizedBox(height: 32),
                      _buildSectionHeader('Other Services', isSmallScreen),
                      const SizedBox(height: 16),
                      _buildServicesGrid(_otherServices, isSmallScreen),
                      const SizedBox(height: 32),
                      _buildRecentTransactions(isSmallScreen),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildCustomBottomNavBar(isSmallScreen),
      ),
    );
  }
}
