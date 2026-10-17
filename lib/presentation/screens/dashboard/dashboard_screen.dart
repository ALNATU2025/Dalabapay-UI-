// lib/presentation/screens/dashboard/dashboard_screen.dart
// lib/presentation/screens/dashboard/dashboard_screen.dart
import 'dart:async';
import 'dart:async' show unawaited;
import 'dart:convert';
import 'package:dalabapay/core/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../kyc/kyc_screen.dart';
import '../../../core/services/socket_service.dart' hide debugPrint;
import '../../../core/services/notification_service.dart';
import '../../../ui/ui.dart';

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
  // Everyday essentials shown on Home (all backed by live backend endpoints)
  final List<Map<String, dynamic>> _quickServices = [
    {'icon': DPIcons.phone, 'name': 'Airtime', 'route': '/airtime'},
    {'icon': DPIcons.wifi, 'name': 'Data', 'route': '/data'},
    {'icon': DPIcons.zap, 'name': 'Electricity', 'route': '/electricity'},
    {'icon': DPIcons.tv, 'name': 'TV', 'route': '/cable'},
    {'icon': DPIcons.router, 'name': 'Internet', 'route': '/internet'},
    {'icon': DPIcons.globe, 'name': 'International', 'route': '/international-airtime'},
    {'icon': DPIcons.graduationCap, 'name': 'Education', 'route': '/education'},
  ];

  // Other Services
  // Additional services listed in the Pay bills hub
  final List<Map<String, dynamic>> _otherServices = [
    {'icon': DPIcons.umbrella, 'name': 'Insurance', 'route': '/insurance'},
    {'icon': DPIcons.badgePercent, 'name': 'Earnings', 'route': '/commission'},
    {'icon': DPIcons.users, 'name': 'Referrals', 'route': '/referral'},
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
      margin: const EdgeInsets.symmetric(vertical: 6),
      height: 48,
      decoration: BoxDecoration(
        color: DP.surface,
        borderRadius: BorderRadius.circular(DP.rMd),
      ),
    );
  }

  // Add KYC Modal Widget
  Widget _buildKYCModal() {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DPIconBadge(icon: DPIcons.landmark, bg: DP.greenSoft, fg: DP.green, size: 60, radius: 30),
            const SizedBox(height: 16),
            Text('Get your funding account',
                textAlign: TextAlign.center,
                style: DPText.title.copyWith(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(
              'Verify your identity to get a personal account number. Any bank transfer to it tops up your wallet automatically.',
              textAlign: TextAlign.center,
              style: DPText.bodyMuted,
            ),
            const SizedBox(height: 16),
            const DPNotice('Your details are secure and private.', margin: EdgeInsets.zero),
            const SizedBox(height: 20),
            DPButton(
              label: 'Verify my identity',
              onPressed: () {
                Navigator.pop(context);
                _navigateToKYC();
              },
            ),
            const SizedBox(height: 6),
            DPLinkButton(
              label: 'Remind me later',
              color: DP.muted,
              onPressed: () => Navigator.pop(context),
            ),
          ],
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

  Future<bool?> _showLogoutConfirmationDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DPIconBadge(icon: DPIcons.logOut, bg: DP.dangerSoft, fg: DP.danger, size: 60, radius: 30),
              const SizedBox(height: 16),
              Text('Log out?', style: DPText.title.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Text(
                'You can log back in with your PIN or biometrics.',
                textAlign: TextAlign.center,
                style: DPText.bodyMuted,
              ),
              const SizedBox(height: 22),
              DPButton(
                label: 'Log out',
                kind: DPButtonKind.danger,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
              const SizedBox(height: 10),
              DPButton.secondary(
                label: 'Cancel',
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Performs the actual logout WITHOUT clearing the session data
  /// needed for PIN / Biometric re-login.
  Future<void> _performLogout() async {
    if (mounted) {
      dpSnack(context, 'Logging out...');
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
        dpSnack(context, 'Logged out successfully', success: true);

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
        dpSnack(context, 'Logged out', error: true);
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DPIconBadge(
                icon: iconData,
                bg: iconColor.withValues(alpha: 0.12),
                fg: iconColor,
                size: 60,
                radius: 30,
              ),
              const SizedBox(height: 14),
              DPStatusPill(typeLabel),
              const SizedBox(height: 12),
              Text(
                title,
                style: DPText.title.copyWith(fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(message, style: DPText.bodyMuted, textAlign: TextAlign.center),
              const SizedBox(height: 22),
              DPButton(
                label: 'View',
                onPressed: () {
                  if (notificationId.isNotEmpty) {
                    _markNotificationAsRead(notificationId);
                  }
                  Navigator.of(context, rootNavigator: true).pop();
                  _navigateFromNotification(screen, data);
                },
              ),
              const SizedBox(height: 10),
              DPButton.secondary(
                label: 'Dismiss',
                onPressed: () {
                  if (notificationId.isNotEmpty) {
                    _markNotificationAsRead(notificationId);
                  }
                  Navigator.of(context, rootNavigator: true).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  DPIconData _getAlertIcon(String type) {
    switch (type.toLowerCase()) {
      case 'transaction':
      case 'payment_success':
        return DPIcons.circleCheck;
      case 'payment_failed':
        return DPIcons.circleX;
      case 'commission_earned':
        return DPIcons.sparkles;
      case 'wallet_credit':
      case 'wallet_funded':
        return DPIcons.wallet;
      case 'transfer_sent':
        return DPIcons.arrowUpRight;
      case 'transfer_received':
        return DPIcons.arrowDownLeft;
      case 'referral_bonus':
        return DPIcons.userPlus;
      case 'announcement':
        return DPIcons.bellRing;
      case 'alert':
        return DPIcons.triangleAlert;
      default:
        return DPIcons.bell;
    }
  }

  Color _getAlertColor(String type) {
    switch (type.toLowerCase()) {
      case 'transaction':
      case 'payment_success':
      case 'wallet_credit':
      case 'wallet_funded':
      case 'transfer_received':
      case 'commission_earned':
      case 'referral_bonus':
        return DP.green;
      case 'payment_failed':
      case 'alert':
        return DP.danger;
      default:
        return DP.blue;
    }
  }

  String _getAlertTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'transaction':
      case 'payment_success':
        return 'Successful';
      case 'payment_failed':
        return 'Failed';
      case 'commission_earned':
        return 'Commission';
      case 'wallet_credit':
      case 'wallet_funded':
        return 'Wallet';
      case 'transfer_sent':
        return 'Sent';
      case 'transfer_received':
        return 'Received';
      case 'referral_bonus':
        return 'Referral';
      case 'announcement':
        return 'Announcement';
      case 'alert':
        return 'Alert';
      default:
        return 'Notification';
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
    showDPDialog(
      context,
      tone: DPDialogTone.info,
      icon: DPIcons.hourglass,
      title: 'Not available yet',
      message: '$serviceName isn’t available right now. Please try again later.',
    );
  }

  void _showSuccessMessage(String message) {
    if (mounted) dpSnack(context, message, success: true);
  }

  void _showPendingApprovalSnackBar() {
    if (!mounted) return;
    dpSnack(
      context,
      'Your account is awaiting approval. We’ll notify you as soon as it’s approved.',
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

  DPIconData _getTransactionIcon(String type) {
    final typeLower = type.toLowerCase();
    if (typeLower.contains('international')) return DPIcons.globe;
    if (typeLower.contains('airtime')) return DPIcons.phone;
    if (typeLower.contains('data')) return DPIcons.wifi;
    if (typeLower.contains('electricity')) return DPIcons.zap;
    if (typeLower.contains('cable') || typeLower.contains('tv')) return DPIcons.tv;
    if (typeLower.contains('education')) return DPIcons.graduationCap;
    if (typeLower.contains('insurance')) return DPIcons.umbrella;
    if (typeLower.contains('internet')) return DPIcons.router;
    if (typeLower.contains('transfer received')) return DPIcons.arrowDownLeft;
    if (typeLower.contains('transfer')) return DPIcons.arrowUpRight;
    if (typeLower.contains('commission')) return DPIcons.sparkles;
    if (typeLower.contains('refund')) return DPIcons.rotateCcw;
    if (typeLower.contains('fund') || typeLower.contains('wallet')) {
      return DPIcons.arrowDownLeft;
    }
    return DPIcons.receipt;
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
            primaryColor: DP.navy,
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
    final hour = DateTime.now().hour;
    final greetingIcon = (hour >= 6 && hour < 18) ? DPIcons.sun : DPIcons.moonStar;
    return Padding(
      padding: const EdgeInsets.fromLTRB(DP.gutter, 10, DP.gutter, 6),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            child: const DPLogoMark(size: 46, tile: true),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    'Hello, ${_fullName.isNotEmpty ? _fullName : 'there'}',
                    style: DPText.title.copyWith(fontSize: 18),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                DPIcon(greetingIcon, size: 18, color: DP.ink),
              ],
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: _navigateToNotifications,
                icon: const DPIcon(DPIcons.bell, size: 22, color: DP.ink),
                tooltip: 'Notifications',
              ),
              if (_unreadNotificationCount > 0)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: DP.green, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
          DPLinkButton(label: 'Help', onPressed: () => Navigator.pushNamed(context, '/support')),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isSmallScreen) {
    return DPSectionHeader(
      title,
      actionLabel: 'View all',
      onAction: () => _showAllServices(isSmallScreen),
      padding: const EdgeInsets.fromLTRB(DP.gutter, 28, DP.gutter, 14),
    );
  }

  // ==================== APPROVAL STATUS BANNER ====================

  Widget _buildApprovalBanner(bool isSmallScreen) {
    if (_isApproved) return const SizedBox.shrink();

    final isPending = _isPending;
    final message = isPending
        ? 'You can browse and add money, but payments are paused until your account is approved. This usually takes a few minutes.'
        : (_rejectionReason?.isNotEmpty == true
            ? _rejectionReason!
            : 'Your account was not approved. Please contact support for more details.');

    return Padding(
      padding: const EdgeInsets.fromLTRB(DP.gutter, 8, DP.gutter, 6),
      child: DPNotice(
        message,
        title: isPending ? 'Account awaiting approval' : 'Account not approved',
        kind: isPending ? DPNoticeKind.warn : DPNoticeKind.danger,
        icon: isPending ? DPIcons.hourglass : DPIcons.circleX,
        margin: EdgeInsets.zero,
        action: isPending
            ? GestureDetector(
                onTap: () async {
                  if (mounted) _showSuccessMessage('Checking status…');
                  await _refreshApprovalStatus();
                  if (!mounted) return;
                  if (!_approvalSystemEnabled) {
                    _showSuccessMessage('You can make payments now.');
                  } else if (_isApproved) {
                    _showSuccessMessage('Your account has been approved!');
                  } else if (_isPending) {
                    _showErrorMessage('Still awaiting approval. Please check back in a few minutes.');
                  } else if (_isRejected) {
                    _showErrorMessage('Your account was not approved. Please contact support.');
                  }
                },
                child: Text(
                  'Check status',
                  style: DPText.link.copyWith(color: DP.warn, decoration: TextDecoration.underline),
                ),
              )
            : null,
      ),
    );
  }


  Widget _buildModernBalanceCard(bool isSmallScreen) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(DP.gutter, 14, DP.gutter, 0),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: DP.navy,
            borderRadius: BorderRadius.circular(DP.rXl),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -70,
                top: -50,
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF1E3D78), width: 26),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Available wallet balance',
                          style: DPText.body.copyWith(color: const Color(0xFFC4CFE6), fontSize: 14),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _isBalanceVisible = !_isBalanceVisible);
                          },
                          child: DPIcon(
                            _isBalanceVisible ? DPIcons.eye : DPIcons.eyeOff,
                            size: 18,
                            color: const Color(0xFFC4CFE6),
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _silentBackgroundRefresh();
                          },
                          child: const DPIcon(DPIcons.refreshCw, size: 16, color: Color(0xFF8FA2C9)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _isBalanceReady
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _isBalanceVisible ? dpNaira(_walletBalance) : '₦ ••••••',
                              style: DPText.amount.copyWith(color: Colors.white, fontSize: 34),
                            ),
                          )
                        : _buildBalanceLoadingPlaceholder(isSmallScreen),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: DPButton(
                            label: 'Add money',
                            leadingIcon: DPIcons.plus,
                            kind: DPButtonKind.soft,
                            height: 48,
                            onPressed: _navigateToAddMoney,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DPButton(
                            label: 'Send money',
                            leadingIcon: DPIcons.arrowUpRight,
                            kind: DPButtonKind.navy,
                            height: 48,
                            onPressed: _navigateToSendMoney,
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

  Widget _buildCommissionStrip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DP.gutter, 14, DP.gutter, 0),
      child: Material(
        color: DP.greenSoft,
        borderRadius: BorderRadius.circular(DP.rLg + 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(DP.rLg + 2),
          onTap: _navigateToCommission,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Row(
              children: [
                const DPIcon(DPIcons.sparkles, size: 24, color: DP.green),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Commission earned · separate from wallet',
                          style: DPText.small.copyWith(color: DP.green, fontSize: 12.5)),
                      const SizedBox(height: 4),
                      Text(
                        _isBalanceVisible ? dpNaira(_commissionBalance) : '₦ ••••',
                        style: DPText.title.copyWith(color: DP.green, fontSize: 19),
                      ),
                    ],
                  ),
                ),
                const DPIcon(DPIcons.arrowUpRight, size: 20, color: DP.green),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFundingAccountPrompt() {
    if (_isCheckingAccount || _hasDedicatedAccount) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(DP.gutter, 12, DP.gutter, 0),
      child: DPCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        onTap: _navigateToKYC,
        child: Row(
          children: [
            const DPIconBadge(icon: DPIcons.landmark, size: 40, radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Get your funding account',
                      style: DPText.body.copyWith(fontWeight: FontWeight.w500)),
                  Text('Verify your identity to receive bank transfers',
                      style: DPText.small),
                ],
              ),
            ),
            const DPIcon(DPIcons.chevronRight, size: 18, color: DP.muted),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceLoadingPlaceholder(bool isSmallScreen) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF223F7A),
      highlightColor: const Color(0xFF34558F),
      child: Container(
        width: 210,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }




  Widget _buildServicesGrid(
    List<Map<String, dynamic>> services,
    bool isSmallScreen, {
    bool withMore = true,
  }) {
    final shown = withMore && services.length > 7 ? services.take(7).toList() : services;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DP.gutter - 4),
      child: DPServiceGrid(
        tiles: [
          for (final service in shown)
            DPServiceTile(
              icon: service['icon'] as DPIconData,
              label: service['name'] as String,
              onTap: () {
                HapticFeedback.lightImpact();
                final route = service['route']?.toString() ?? '';
                if (route.isNotEmpty) {
                  _navigateToService(route);
                } else {
                  _showComingSoon(service['name']);
                }
              },
            ),
          if (withMore)
            DPServiceTile(
              icon: DPIcons.layoutGrid,
              label: 'More',
              onTap: () => _showAllServices(isSmallScreen),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentTransactions(bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DPSectionHeader(
          'Recent activity',
          actionLabel: 'See all',
          onAction: _navigateToTransactions,
          padding: const EdgeInsets.fromLTRB(DP.gutter, 18, DP.gutter, 6),
        ),
        if (_isLoadingTransactions)
          _buildShimmerTransactions(isSmallScreen)
        else if (_recentTransactions.isEmpty)
          _buildEmptyTransactions(isSmallScreen)
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DP.gutter),
            child: Column(
              children: [
                for (final t in _recentTransactions.take(5))
                  _buildTransactionItem(t as Map<String, dynamic>, isSmallScreen),
              ],
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
    final status = (transaction['status'] ?? 'completed').toString();
    final date = transaction['createdAt'] != null
        ? DateTime.tryParse(transaction['createdAt'].toString()) ?? DateTime.now()
        : DateTime.now();
    final description = (transaction['description'] ?? 'Transaction').toString();
    final type = (transaction['type'] ?? 'Transaction').toString();
    final failed = status.toLowerCase().contains('fail');
    final statusLabel = failed
        ? 'Failed'
        : (status.toLowerCase().contains('pend') ? 'Pending' : 'Successful');

    return DPTransactionTile(
      icon: _getTransactionIcon(type),
      title: description,
      subtitle: '${_activityDate(date)} · $statusLabel',
      amount: '${isCredit ? '+' : '−'}${dpNaira(amount, decimals: amount % 1 != 0)}',
      credit: isCredit,
      failed: failed,
      onTap: () => _showTransactionReceipt(transaction),
    );
  }

  String _activityDate(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(local.year, local.month, local.day);
    final time = DateFormat('h:mm a').format(local);
    if (d == today) return 'Today, $time';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday, $time';
    return DateFormat('d MMM, h:mm a').format(local);
  }

  Widget _buildShimmerTransactions(bool isSmallScreen) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DP.gutter),
      child: Shimmer.fromColors(
        baseColor: const Color(0xFFEDEFEA),
        highlightColor: const Color(0xFFF8F9F5),
        child: Column(
          children: List.generate(
            3,
            (index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyTransactions(bool isSmallScreen) {
    return const DPEmptyState(
      icon: DPIcons.receipt,
      title: 'No activity yet',
      message: 'Your payments and top-ups will show up here.',
    );
  }

  Widget _buildCustomBottomNavBar(bool isSmallScreen) {
    return DPBottomNav(
      currentIndex: _selectedIndex,
      items: const [
        DPNavItem(DPIcons.house, 'Home'),
        DPNavItem(DPIcons.arrowLeftRight, 'Activity'),
        DPNavItem(DPIcons.wallet, 'Wallet'),
        DPNavItem(DPIcons.user, 'Profile'),
      ],
      onTap: (index) {
        HapticFeedback.lightImpact();
        if (_selectedIndex != index) {
          setState(() => _selectedIndex = index);
        }
        switch (index) {
          case 0:
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
    );
  }

  Widget _buildDrawerTile(
    IconData icon,
    String title,
    VoidCallback onTap, {
    bool isLogout = false,
  }) {
    return ListTile(
      leading: Icon(icon, color: isLogout ? DP.danger : DP.ink2),
      title: Text(title, style: DPText.body.copyWith(color: isLogout ? DP.danger : DP.ink)),
      onTap: onTap,
    );
  }

  void _showAllServices(bool isSmallScreen) {
    final payAgain = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final raw in _recentTransactions) {
      if (raw is! Map) continue;
      final t = Map<String, dynamic>.from(raw);
      final type = (t['type'] ?? '').toString().toLowerCase();
      String? route;
      if (type.contains('electricity')) {
        route = '/electricity';
      } else if (type.contains('cable') || type.contains('tv')) {
        route = '/cable';
      } else if (type.contains('data')) {
        route = '/data';
      } else if (type.contains('international')) {
        route = '/international-airtime';
      } else if (type.contains('airtime')) {
        route = '/airtime';
      }
      if (route == null || seen.contains(route)) continue;
      seen.add(route);
      payAgain.add({
        'route': route,
        'icon': _getTransactionIcon(type),
        'title': (t['description'] ?? 'Payment').toString(),
        'subtitle': '${dpNaira((t['amount'] ?? 0).toDouble(), decimals: false)} · ${_formatDate(DateTime.tryParse(t['createdAt']?.toString() ?? '') ?? DateTime.now())}',
      });
      if (payAgain.length == 3) break;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _BillsHubPage(
          services: [..._quickServices, ..._otherServices],
          payAgain: payAgain,
          onOpen: (route) {
            Navigator.of(context).pop();
            _navigateToService(route);
          },
        ),
      ),
    );
  }

  // ==================== CUSTOM DRAWER METHODS ====================

  Widget _buildDrawerHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 22),
      color: DP.bg,
      child: Row(
        children: [
          DPAvatar(name: _fullName.isNotEmpty ? _fullName : 'User', size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fullName.isNotEmpty ? _fullName : 'User',
                  style: DPText.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _email,
                  style: DPText.small,
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
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: DPTheme.overlay,
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: DP.bg,
          drawer: _isLoading
              ? Drawer(
                  backgroundColor: DP.bg,
                  child: Column(
                    children: [
                      _buildDrawerHeader(),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: List.generate(8, (_) => _buildSkeletonTile()),
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
            child: Column(
              children: [
                _buildAppBar(isSmallScreen),
                Expanded(
                  child: RefreshIndicator(
                    color: DP.green,
                    onRefresh: () async {
                      await _refreshAllData();
                      await _refreshApprovalStatus();
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: const EdgeInsets.only(bottom: 28),
                      children: [
                        _buildApprovalBanner(isSmallScreen),
                        _buildModernBalanceCard(isSmallScreen),
                        _buildCommissionStrip(),
                        _buildFundingAccountPrompt(),
                        _buildSectionHeader('Your everyday essentials', isSmallScreen),
                        _buildServicesGrid(_quickServices, isSmallScreen),
                        _buildRecentTransactions(isSmallScreen),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _buildCustomBottomNavBar(isSmallScreen),
        ),
      ),
    );
  }
}

/// "Pay bills" hub — every service in one place, plus quick repeat payments.
class _BillsHubPage extends StatefulWidget {
  final List<Map<String, dynamic>> services;
  final List<Map<String, dynamic>> payAgain;
  final ValueChanged<String> onOpen;

  const _BillsHubPage({
    required this.services,
    required this.payAgain,
    required this.onOpen,
  });

  @override
  State<_BillsHubPage> createState() => _BillsHubPageState();
}

class _BillsHubPageState extends State<_BillsHubPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.services
        : widget.services
            .where((s) => s['name'].toString().toLowerCase().contains(q))
            .toList();
    return DPPage(
      title: 'Pay bills',
      children: [
        const DPHeadline('Life admin, sorted.',
            subtitle: 'One place for your everyday payments.'),
        DPField(
          label: 'What would you like to pay?',
          controller: _search,
          hint: 'Search bills and services',
          suffixIcon: DPIcons.search,
          onChanged: (_) => setState(() {}),
        ),
        DPSectionHeader('Everyday payments', padding: const EdgeInsets.only(top: 6, bottom: 14)),
        if (filtered.isEmpty)
          const DPEmptyState(icon: DPIcons.search, title: 'No matching service')
        else
          DPServiceGrid(
            tiles: [
              for (final s in filtered)
                DPServiceTile(
                  icon: s['icon'] as DPIconData,
                  label: s['name'] as String,
                  onTap: () => widget.onOpen(s['route'].toString()),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 18, 20),
          decoration: BoxDecoration(
            color: DP.navy,
            borderRadius: BorderRadius.circular(DP.rLg + 2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your bills can give back.',
                        style: DPText.title.copyWith(color: Colors.white, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    Text('See the commission on eligible payments before you pay.',
                        style: DPText.small.copyWith(color: const Color(0xFFC4CFE6), fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const DPIcon(DPIcons.gift, size: 30, color: Colors.white, strokeWidth: 1.5),
            ],
          ),
        ),
        if (widget.payAgain.isNotEmpty) ...[
          const DPSectionHeader('Pay again'),
          for (final p in widget.payAgain)
            DPMenuRow(
              icon: p['icon'] as DPIconData,
              iconBg: DP.surface,
              iconColor: DP.ink2,
              title: p['title'].toString(),
              subtitle: p['subtitle'].toString(),
              onTap: () => widget.onOpen(p['route'].toString()),
            ),
        ],
        const SizedBox(height: 22),
        Center(
          child: Text('Can’t find a service? Let us know in Help.',
              style: DPText.small, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}
