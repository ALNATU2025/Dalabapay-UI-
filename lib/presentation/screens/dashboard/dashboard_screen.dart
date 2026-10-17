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
import '../../../ui/ui.dart';
import '../bills/pay_bills_screen.dart';

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

  static const Color _successColor = Color(0xFF079A68);
  static const Color _warningColor = Color(0xFFB7791F);

  // Transaction state management
  bool _isTransactionInProgress = false;
  DateTime? _lastUserActivity;
  Timer? _idleLogoutTimer;
  Timer? _silentRefreshTimer;
  Timer? _notificationTimer;
  bool _isAppInBackground = false;

  late AnimationController _animationController;

  // Quick Services
  // Everyday essentials shown on Home (design: 4 x 2 grid, last tile = More)
  final List<Map<String, dynamic>> _quickServices = [
    {'icon': DPIcons.phone, 'name': 'Airtime', 'route': '/airtime'},
    {'icon': DPIcons.wifi, 'name': 'Data', 'route': '/data'},
    {'icon': DPIcons.bolt, 'name': 'Electricity', 'route': '/electricity'},
    {'icon': DPIcons.tv, 'name': 'TV', 'route': '/cable'},
    {'icon': DPIcons.school, 'name': 'Education', 'route': '/education'},
    {'icon': DPIcons.shield, 'name': 'Insurance', 'route': '/insurance'},
    {
      'icon': DPIcons.globe,
      'name': 'International',
      'route': '/international-airtime',
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
                    colors: [Color(0xFF35C08E), Color(0xFF15368A)],
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
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF15368A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'You don\'t have a dedicated account yet. '
                'Complete your KYC to get your personal virtual account for seamless transactions.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: const Color(0xFF7B87A1),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF15368A).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF15368A).withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.security,
                      color: const Color(0xFF079A68),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your account details are secure and private.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF079A68),
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
                        side: const BorderSide(color: Color(0xFF15368A)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Complete KYC',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF15368A),
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
                        backgroundColor: const Color(0xFF15368A),
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
                    color: const Color(0xFF7B87A1),
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
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF10255A),
                  ),
                ),
                const SizedBox(height: 10),

                // Message
                Text(
                  'Are you sure you want to logout?\nYou can log back in with your PIN or Biometric.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF7B87A1),
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
                            color: const Color(0xFF7B87A1),
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
          content: Text('Logging out...', style: GoogleFonts.inter()),
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
              style: GoogleFonts.inter(),
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
            content: Text('Logged out', style: GoogleFonts.inter()),
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
    Navigator.pushNamed(
      context,
      '/transactions',
      arguments: {'userId': _userId ?? ''},
    ).then((result) {
      // The pushed tab can ask for another tab when it closes.
      if (mounted) _handleTabResult(result);
      _silentBackgroundRefresh();
      _loadRecentTransactions();
    });
    _resetIdleTimer();
  }

  void _handleTabResult(Object? result) {
    switch (result) {
      case 'services':
        setState(() => _selectedIndex = 2);
        break;
      case 'transactions':
        _onNavTap(1);
        break;
      case 'profile':
        _onNavTap(3);
        break;
      case 'send':
        setState(() => _selectedIndex = 0);
        _navigateToSendMoney();
        break;
      default:
        setState(() => _selectedIndex = 0);
    }
  }

  void _navigateToSettings() {
    Navigator.pushNamed(context, '/settings').then((result) {
      if (mounted) _handleTabResult(result);
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
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF10255A),
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
                  color: const Color(0xFF7B87A1),
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
                          color: const Color(0xFF7B87A1),
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
                        backgroundColor: const Color(0xFF15368A),
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
        return const Color(0xFF079A68); // Green
      case 'payment_failed':
      case 'alert':
        return Colors.red.shade600;
      case 'commission_earned':
      case 'referral_bonus':
        return const Color(0xFFB7791F); // Amber
      case 'transfer_sent':
        return const Color(0xFF2563EB); // Blue
      case 'announcement':
        return const Color(0xFF2563EB); // Purple
      default:
        return const Color(0xFF15368A); // Primary
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
    dpDialog(
      context,
      title: 'Not available yet',
      message:
          '$serviceName isn\'t available right now. We\'ll let you know when it is.',
      confirmLabel: 'OK',
      tone: DPTone.info,
    );
  }

  void _showSuccessMessage(String message) {
    if (mounted) dpSnack(context, message, success: true);
  }

  void _showPendingApprovalSnackBar() {
    if (!mounted) return;
    dpSnack(
      context,
      'Your account is being reviewed. We\'ll notify you once it\'s approved.',
    );
  }

  void _showErrorMessage(String message) {
    if (mounted) dpSnack(context, message, error: true);
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

  IconData _getTransactionIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('international')) return DPIcons.globe;
    if (t.contains('airtime')) return DPIcons.phone;
    if (t.contains('data') || t.contains('internet')) return DPIcons.wifi;
    if (t.contains('electric')) return DPIcons.bolt;
    if (t.contains('cable') || t.contains('tv')) return DPIcons.tv;
    if (t.contains('education')) return DPIcons.school;
    if (t.contains('insurance')) return DPIcons.shield;
    if (t.contains('transfer received')) return DPIcons.downLeft;
    if (t.contains('transfer')) return DPIcons.upRight;
    if (t.contains('commission') || t.contains('bonus')) return DPIcons.sparkle;
    if (t.contains('refund')) return DPIcons.refresh;
    if (t.contains('fund') || t.contains('wallet') || t.contains('deposit')) {
      return DPIcons.downLeft;
    }
    return DPIcons.receipt;
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
    return DP.naira(balance).substring(1);
  }

  void _navigateToSendMoney() {
    if (_isPending) {
      _showPendingApprovalSnackBar();
      return;
    }
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
        'initialTab': 'transfer',
      },
    ).then((_) {
      if (mounted) setState(() => _selectedIndex = 0);
      _endTransaction();
      _silentBackgroundRefresh();
    });
    _resetIdleTimer();
  }

  String _firstName() {
    final n = _fullName.trim();
    if (n.isEmpty) return 'there';
    return n.split(RegExp(r'\s+')).first;
  }

  String _activityTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final time = DateFormat('h:mm a').format(date);
    if (d == today) return 'Today, $time';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday, $time';
    return DateFormat('d MMM, h:mm a').format(date);
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
            primaryColor: const Color(0xFF15368A),
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

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning!';
    if (h < 17) return 'Good afternoon!';
    return 'Good evening!';
  }

  Widget _buildAppBar(bool isSmallScreen) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Open menu',
            child: GestureDetector(
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: DP.blueTint,
                ),
                child: ClipOval(child: DPAvatar(name: _fullName, size: 44)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, ${_firstName()}!',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: DP.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(_greeting(), style: DP.caption.copyWith(fontSize: 13)),
              ],
            ),
          ),
          DPIconSquare(
            icon: DPIcons.bell,
            size: 44,
            color: DP.navy,
            background: Colors.transparent,
            semanticLabel: 'Notifications',
            onTap: _navigateToNotifications,
            badge: _unreadNotificationCount > 0
                ? Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: DP.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: DP.surface, width: 1.5),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  // ==================== APPROVAL STATUS BANNER ====================

  Widget _buildApprovalBanner(bool isSmallScreen) {
    if (_isApproved) return const SizedBox.shrink();
    final isPending = _isPending;
    final message = isPending
        ? 'You can add money and look around. Payments unlock once your account is approved — usually within a few minutes.'
        : (_rejectionReason?.isNotEmpty == true
            ? _rejectionReason!
            : 'Your account was not approved. Please contact support for details.');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: DPBanner(
        message,
        title: isPending ? 'Account under review' : 'Account not approved',
        tone: isPending ? DPTone.warning : DPTone.error,
        icon: isPending ? DPIcons.pending : DPIcons.alert,
        action: isPending
            ? DPTextLink(
                label: 'Check status',
                color: DP.amber,
                onTap: () async {
                  _showSuccessMessage('Checking your status…');
                  await _refreshApprovalStatus();
                  if (!mounted) return;
                  if (!_approvalSystemEnabled || _isApproved) {
                    _showSuccessMessage('You\'re approved — you can pay now.');
                  } else if (_isPending) {
                    _showErrorMessage(
                      'Still under review. Please check back in a few minutes.',
                    );
                  } else if (_isRejected) {
                    _showErrorMessage(
                      'Your account was not approved. Please contact support.',
                    );
                  }
                },
              )
            : DPTextLink(
                label: 'Contact support',
                color: DP.red,
                onTap: () => Navigator.pushNamed(context, '/help'),
              ),
      ),
    );
  }


  Widget _buildModernBalanceCard(bool isSmallScreen) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        gradient: DP.navyGradient,
        borderRadius: BorderRadius.circular(DP.rXl),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3315368A),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Wallet Balance',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              InkResponse(
                radius: 20,
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _isBalanceVisible = !_isBalanceVisible);
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    _isBalanceVisible ? DPIcons.eye : DPIcons.eyeOff,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: !_isBalanceReady
                  ? _buildBalanceLoadingPlaceholder(isSmallScreen)
                  : Align(
                      key: ValueKey('bal_$_isBalanceVisible'),
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _isBalanceVisible
                            ? DPCountUp(
                                value: _walletBalance,
                                format: (v) => DP.naira(v),
                                style: _balanceStyle,
                              )
                            : const Text('₦ ••••••', style: _balanceStyle),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: _navigateToCommission,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(DPIcons.sparkle, size: 14, color: Color(0xFF7FE3BC)),
                const SizedBox(width: 5),
                Text(
                  'Earnings ${_isBalanceVisible ? DP.naira(_commissionBalance) : '₦ ••••'}',
                  style: const TextStyle(
                    color: Color(0xFF7FE3BC),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(
                  DPIcons.chevronRight,
                  size: 16,
                  color: Color(0xFF7FE3BC),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DPButton(
                  label: 'Add Money',
                  leadingIcon: DPIcons.plus,
                  height: 46,
                  background: DP.greenBright,
                  onPressed: _navigateToAddMoney,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DPButton(
                  label: 'Send Money',
                  height: 46,
                  background: DP.blue,
                  onPressed: _navigateToSendMoney,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const TextStyle _balanceStyle = TextStyle(
    color: Colors.white,
    fontSize: 30,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  Widget _buildBalanceLoadingPlaceholder(bool isSmallScreen) {
    return Align(
      key: const ValueKey('bal_loading'),
      alignment: Alignment.centerLeft,
      child: Container(
        height: 30,
        width: 170,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  // Groups behind the three Essential Services tiles.
  static const List<DPService> _payBillGroup = [
    DPService('Electricity', DPIcons.bolt, '/electricity', DPAssets.svcElectricity, DP.green),
    DPService('Airtime', DPIcons.smartphone, '/airtime', DPAssets.svcAirtime, DP.navyIcon),
    DPService('Data', DPIcons.wifi, '/data', DPAssets.svcData, DP.navyIcon),
  ];
  static const List<DPService> _payTvGroup = [
    DPService('DSTV', DPIcons.tv, '/cable', DPAssets.dstv, DP.navyIcon),
    DPService('GOtv', DPIcons.tv, '/cable', DPAssets.gotv, DP.green),
    DPService('StarTimes', DPIcons.tv, '/cable', DPAssets.startimes, DP.amber),
  ];

  /// "Essential Services": Pay Bill · Pay TV · International Airtime.
  /// Everything else lives behind "More" / the Services tab.
  Widget _buildServicesGrid(
    List<Map<String, dynamic>> services,
    bool isSmallScreen,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DPSectionHeader(
            'Essential Services',
            actionLabel: 'More',
            onAction: () => _onNavTap(2),
          ),
          DPServiceGrid(
            columns: 3,
            tiles: [
              DPServiceTile(
                icon: DPIcons.receipt,
                label: 'Pay Bill',
                image: DPAssets.svcBills,
                color: DP.green,
                onTap: () => _showServiceGroup(
                  'Pay Bill',
                  'Electricity, airtime and data',
                  _payBillGroup,
                ),
              ),
              DPServiceTile(
                icon: DPIcons.tv,
                label: 'Pay TV',
                image: DPAssets.svcTv,
                color: DP.navyIcon,
                onTap: () => _showServiceGroup(
                  'Pay TV',
                  'DSTV, GOtv and StarTimes',
                  _payTvGroup,
                ),
              ),
              DPServiceTile(
                icon: DPIcons.globe,
                label: 'International Airtime',
                image: DPAssets.svcInternational,
                color: DP.navyIcon,
                onTap: () => _openServiceRoute('/international-airtime'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Bottom sheet listing the services behind an Essential Services tile.
  void _showServiceGroup(
    String title,
    String subtitle,
    List<DPService> group,
  ) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: DP.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DP.rXl)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DPSheetHandle(),
              const SizedBox(height: 8),
              Text(title, style: DP.title),
              const SizedBox(height: 4),
              Text(subtitle, style: DP.caption),
              const SizedBox(height: 18),
              DPServiceGrid(
                columns: 3,
                tiles: [
                  for (final s in group)
                    DPServiceTile(
                      icon: s.icon,
                      label: s.name,
                      image: s.image,
                      color: s.color,
                      onTap: () {
                        Navigator.pop(ctx);
                        _openServiceRoute(s.route);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sliding banners: International Airtime and Cable TV.
  Widget _buildBanners(bool isSmallScreen) {
    return _HomeBanners(
      banners: [
        _HomeBannerData(
          title: 'International\nAirtime',
          subtitle: 'Top up loved ones\' phones abroad in seconds.',
          image: DPAssets.bannerInternational,
          icon: DPIcons.globe,
          onTap: () => _openServiceRoute('/international-airtime'),
        ),
        _HomeBannerData(
          title: 'Never Miss\nYour Shows',
          subtitle: 'Renew DSTV, GOtv & StarTimes instantly.',
          image: DPAssets.bannerCable,
          icon: DPIcons.tv,
          onTap: () => _openServiceRoute('/cable'),
        ),
      ],
    );
  }

  /// Opens a service route, including the special routes used by the
  /// services catalogue.
  void _openServiceRoute(String route) {
    HapticFeedback.lightImpact();
    switch (route) {
      case '/services':
        _onNavTap(2);
        return;
      case '/bills':
        _openBills();
        return;
      case '/wallet:add':
        _navigateToAddMoney();
        return;
      case '/wallet:send':
        _navigateToSendMoney();
        return;
      case '/commission':
        _navigateToCommission();
        return;
      default:
        _navigateToService(route);
    }
  }

  void _openBills() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BillsScreen(
          onSelect: (route) {
            Navigator.pop(context);
            _openServiceRoute(route);
          },
        ),
      ),
    );
    _resetIdleTimer();
  }

  Widget _buildRecentTransactions(bool isSmallScreen) {
    final list = _recentTransactions.take(5).toList();
    Widget content;
    if (_isLoadingTransactions && list.isEmpty) {
      content = Column(
        children: List.generate(
          3,
          (i) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                DPSkeleton(width: 44, height: 44, radius: 22),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DPSkeleton(width: 140),
                      SizedBox(height: 8),
                      DPSkeleton(width: 90, height: 11),
                    ],
                  ),
                ),
                DPSkeleton(width: 64, height: 14),
              ],
            ),
          ),
        ),
      );
    } else if (list.isEmpty) {
      content = const DPEmptyState(
        icon: DPIcons.receipt,
        title: 'No transactions yet',
        message: 'Your payments and top-ups will show up here.',
      );
    } else {
      content = Column(
        children: [
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: DP.borderSoft),
            _buildTransactionItem(
              Map<String, dynamic>.from(list[i] as Map),
              isSmallScreen,
            ),
          ],
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DPSectionHeader(
            'Transaction History',
            actionLabel: 'See All',
            onAction: _navigateToTransactions,
          ),
          DPCard(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: AnimatedSize(
              duration: DPMotion.base,
              curve: DPMotion.curve,
              alignment: Alignment.topCenter,
              child: content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(
    Map<String, dynamic> transaction,
    bool isSmallScreen,
  ) {
    final isCredit = _isCreditTransaction(transaction);
    final amount = ((transaction['amount'] ?? 0.0) as num).toDouble();
    final status = transaction['status']?.toString() ?? 'completed';
    final date = transaction['createdAt'] != null
        ? (DateTime.tryParse(transaction['createdAt'].toString())?.toLocal() ??
            DateTime.now())
        : DateTime.now();
    final description = transaction['description']?.toString() ?? 'Transaction';
    final type = transaction['type']?.toString() ?? 'Transaction';
    final isCommission = transaction['isCommission'] == true;
    final icon = _getTransactionIcon(type);
    final statusLabel = isCommission ? 'Commission' : DPStatus.labelFor(status);

    return DPListRow(
      onTap: () => _showTransactionReceipt(transaction),
      padding: const EdgeInsets.symmetric(vertical: 12),
      leading: isCredit
          ? DPIconBadge(icon, size: 44, iconSize: 21)
          : DPIconBadge(
              icon,
              size: 44,
              iconSize: 21,
              color: DP.red,
              background: DP.redBg,
            ),
      title: description,
      subtitle: '${_activityTime(date)}  •  $statusLabel',
      trailing: Text(
        '${isCredit ? '+ ' : '- '}${DP.naira(amount)}',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: isCredit ? DP.green : DP.red,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  void _onNavTap(int i) {
    HapticFeedback.lightImpact();
    switch (i) {
      case 0:
      case 2:
        if (_selectedIndex != i) setState(() => _selectedIndex = i);
        break;
      case 1:
        setState(() => _selectedIndex = 1);
        _navigateToTransactions();
        break;
      case 3:
        setState(() => _selectedIndex = 3);
        _navigateToSettings();
        break;
    }
    _resetIdleTimer();
  }

  Widget _buildCustomBottomNavBar(bool isSmallScreen) {
    return DPBottomNav(
      index: _selectedIndex,
      items: kDPTabs,
      onTap: _onNavTap,
      onCenter: _navigateToSendMoney,
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
        color: isLogout ? Colors.red : const Color(0xFF15368A),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          color: isLogout ? Colors.red : const Color(0xFF15368A),
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }

  // ==================== CUSTOM DRAWER METHODS ====================

  Widget _buildDrawerHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
      color: DP.navy,
      child: Row(
        children: [
          DPAvatar(name: _fullName.isNotEmpty ? _fullName : 'User', size: 48),
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
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _email,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
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
        key: _scaffoldKey,
        backgroundColor: DP.bg,
        drawer: _isLoading
            ? Drawer(
                child: Column(
                  children: [
                    _buildDrawerHeader(),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: List.generate(6, (_) => _buildSkeletonTile()),
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
          bottom: false,
          child: PopScope(
            canPop: _selectedIndex != 2,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && _selectedIndex == 2) {
                setState(() => _selectedIndex = 0);
              }
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, a) =>
                  FadeTransition(opacity: a, child: child),
              child: _selectedIndex == 2
                  ? ServicesView(
                      key: const ValueKey('services'),
                      recentTransactions: _recentTransactions,
                      onSelect: _openServiceRoute,
                    )
                  : Column(
                      key: const ValueKey('home'),
                      children: [
                        _buildAppBar(isSmallScreen),
                        Expanded(
                          child: RefreshIndicator(
                            color: DP.green,
                            onRefresh: _refreshAllData,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(top: 6, bottom: 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildApprovalBanner(isSmallScreen),
                                  DPAppear(
                                    scaleFrom: 0.97,
                                    child: _buildModernBalanceCard(isSmallScreen),
                                  ),
                                  const SizedBox(height: 20),
                                  DPAppear(
                                    delay: const Duration(milliseconds: 120),
                                    child: _buildServicesGrid(
                                      _quickServices,
                                      isSmallScreen,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  DPAppear(
                                    delay: const Duration(milliseconds: 260),
                                    child: _buildBanners(isSmallScreen),
                                  ),
                                  const SizedBox(height: 20),
                                  DPAppear(
                                    delay: const Duration(milliseconds: 360),
                                    child: _buildRecentTransactions(
                                      isSmallScreen,
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
          ),
        ),
        bottomNavigationBar: _buildCustomBottomNavBar(isSmallScreen),
      ),
    );
  }
}

class _HomeBannerData {
  final String title;
  final String subtitle;
  final String image;
  final IconData icon;
  final VoidCallback onTap;
  const _HomeBannerData({
    required this.title,
    required this.subtitle,
    required this.image,
    required this.icon,
    required this.onTap,
  });
}

/// Auto-sliding promo banners with page dots.
class _HomeBanners extends StatefulWidget {
  final List<_HomeBannerData> banners;
  const _HomeBanners({required this.banners});

  @override
  State<_HomeBanners> createState() => _HomeBannersState();
}

class _HomeBannersState extends State<_HomeBanners> {
  final PageController _page = PageController(viewportFraction: 0.9);
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_page.hasClients || widget.banners.length < 2) return;
      final next = (_index + 1) % widget.banners.length;
      _page.animateToPage(
        next,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 118,
          child: PageView.builder(
            controller: _page,
            itemCount: widget.banners.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final b = widget.banners[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: DPPromoBanner(
                  title: b.title,
                  subtitle: b.subtitle,
                  image: b.image,
                  icon: b.icon,
                  onTap: b.onTap,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.banners.length, (i) {
            final on = i == _index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: on ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: on ? DP.green : DP.border,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}
