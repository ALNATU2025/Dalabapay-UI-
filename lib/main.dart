// lib/main.dart - Fully Updated with Session Management & PIN Lock
import 'dart:async';

import 'package:dalabapay/core/services/auth_service.dart' show AuthService;
import 'package:dalabapay/presentation/screens/auth/change_pin_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kReleaseMode, kDebugMode, kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:developer' as developer;
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dalabapay/core/services/secure_storage_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'core/theme/app_theme.dart';
import 'ui/ui.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/wallet_provider.dart';
import 'core/providers/service_provider.dart';
import 'core/services/api_service.dart';
import 'presentation/screens/splash/splash_screen.dart';
import 'core/services/notification_service.dart';
import 'presentation/screens/onboarding/onboarding_screen.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/auth/register_screen.dart';
import 'presentation/screens/auth/forgot_password_screen.dart';
import 'presentation/screens/auth/otp_verification_screen.dart';
import 'presentation/screens/auth/reset_password_screen.dart';
// ✅ PIN Screens
import 'presentation/screens/auth/pin_setup_screen.dart';
import 'presentation/screens/auth/pin_login_screen.dart';
import 'presentation/screens/auth/pin_lock_screen.dart';
import 'presentation/screens/dashboard/dashboard_screen.dart';
import 'presentation/screens/admin/admin_wrapper.dart';
import 'presentation/screens/admin/admin_dashboard_screen.dart';
import 'presentation/screens/admin/admin_users_page.dart';
import 'presentation/screens/admin/admin_all_transactions_page.dart';
import 'presentation/screens/admin/admin_transaction_status_page.dart';
import 'presentation/screens/admin/admin_refund_system_page.dart';
import 'presentation/screens/admin/admin_fund_wallet_page.dart';
import 'presentation/screens/admin/admin_verify_payment_page.dart';
import 'presentation/screens/admin/admin_send_notification_page.dart';
import 'presentation/screens/admin/admin_control_page.dart';
import 'presentation/screens/admin/vtpass_settings_dashboard.dart';
import 'presentation/screens/admin/admin_self_fund_page.dart';
// ✅ NEW: Service Commission Page
import 'presentation/screens/admin/admin_service_commission_page.dart';
// Services
import 'presentation/screens/airtime/airtime_screen.dart';
import 'presentation/screens/electricity/electricity_screen.dart';
import 'presentation/screens/cabletv/cabletv_screen.dart';
import 'presentation/screens/education/education_screen.dart';
import 'presentation/screens/international_airtime/international_airtime_screen.dart';
import 'presentation/screens/ticket/ticket_screen.dart';
import 'presentation/screens/commission/commission_screen.dart';
import 'presentation/screens/referral/referral_screen.dart';
import 'presentation/screens/internet/internet_screen.dart';
import 'presentation/screens/betting/betting_screen.dart';
import 'presentation/screens/insurance/insurance_screen.dart';
import 'presentation/screens/donation/donation_screen.dart';
import 'presentation/screens/transactions/transactions_screen.dart';
import 'presentation/screens/wallet/wallet_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/screens/kyc/kyc_screen.dart';
import 'presentation/screens/user_disputes_page.dart';
import 'presentation/screens/transaction_validation_page.dart';
import 'presentation/screens/notifications/notifications_screen.dart';

// lib/main.dart - Add this at the top after imports
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 💡 Fully Configured Web Credentials for DalabaPay
FirebaseOptions _getWebFirebaseOptions() {
  return const FirebaseOptions(
    apiKey: "AIzaSyD_dlIje_6MFSVoOnOi4Ap0otMahH8VV6Q",
    authDomain: "dalabapay-937de.firebaseapp.com",
    projectId: "dalabapay-937de",
    storageBucket: "dalabapay-937de.firebasestorage.app",
    messagingSenderId: "320938451256",
    appId: "1:320938451256:web:493f82f7fd7ac4bdd661cd",
    measurementId: "G-DNEPPNG6E2",
  );
}

// Background handler - MUST be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase with web options if on web
  if (kIsWeb) {
    await Firebase.initializeApp(options: _getWebFirebaseOptions());
  } else {
    await Firebase.initializeApp();
  }
  debugPrint('🔔 Handling background message: ${message.messageId}');
}

// ==================== ERROR HANDLING ====================
void _setupErrorHandling() {
  // ✅ Handle Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    if (kReleaseMode) {
      developer.log(
        details.exceptionAsString(),
        name: 'FlutterError',
        error: details.exception,
        stackTrace: details.stack,
      );
    } else {
      FlutterError.presentError(details);
    }
    _reportError(details.exception, details.stack);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    developer.log(
      error.toString(),
      name: 'PlatformError',
      error: error,
      stackTrace: stack,
    );
    _reportError(error, stack);
    return true;
  };

  runZonedGuarded(() {}, (Object error, StackTrace stack) {
    developer.log(
      error.toString(),
      name: 'ZoneError',
      error: error,
      stackTrace: stack,
    );
    _reportError(error, stack);
  });
}

void _reportError(Object error, StackTrace? stack) {
  if (kDebugMode) {
    debugPrint('❌ Error: $error');
    debugPrint('📚 Stack: $stack');
  }
}

// ==================== MAIN ====================
Future<void> main() async {
  _setupErrorHandling();
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Initialize Firebase with web options if on web
  if (kIsWeb) {
    await Firebase.initializeApp(options: _getWebFirebaseOptions());
  } else {
    await Firebase.initializeApp();
  }

  // Register background handler
  // Register background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  try {
    await ApiService.initializeSecurity();
    await AuthService.initialize();

    // ✅ Initialize NotificationService (handles foreground FCM internally)
    await NotificationService().initialize();

    final isLoggedIn = await SecureStorageService.isLoggedIn();
    debugPrint('🔐 Logged In: $isLoggedIn');
  } catch (e) {
    debugPrint('⚠️ Init error: $e');
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const DalabaPayApp());
}

// ==================== MAIN APP WITH LIFECYCLE MANAGEMENT ====================
class DalabaPayApp extends StatefulWidget {
  const DalabaPayApp({super.key});

  @override
  State<DalabaPayApp> createState() => _DalabaPayAppState();
}

class _DalabaPayAppState extends State<DalabaPayApp>
    with WidgetsBindingObserver {
  Timer? _lockTimer;
  bool _isAppInBackground = false;
  bool _pinLockShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateActivity();

    // ✅ Flush any notification tap that arrived during cold-start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().flushPendingNavigation();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockTimer?.cancel();
    super.dispose();
  }

  // ==================== LIFECYCLE MANAGEMENT ====================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _isAppInBackground = true;
        _pinLockShown = false;
        _lockTimer?.cancel();
        // ✅ 30-MINUTE background lock (matches AuthService session timeout)
        _lockTimer = Timer(const Duration(minutes: 30), () {
          if (_isAppInBackground && !_pinLockShown) {
            _showPinLock();
          }
        });
        break;

      case AppLifecycleState.resumed:
        _isAppInBackground = false;
        _lockTimer?.cancel();
        _updateActivity();
        _checkIfNeedsPinLock();
        break;

      case AppLifecycleState.inactive:
        break;

      default:
        break;
    }
  }

  // ==================== PIN LOCK METHODS ====================

  void _showPinLock() {
    if (_pinLockShown) return;
    _pinLockShown = true;

    try {
      final navigator = navigatorKey.currentState;
      if (navigator != null && navigator.mounted) {
        final currentRoute = ModalRoute.of(navigator.context)?.settings.name;
        if (currentRoute != '/pin-lock' &&
            currentRoute != '/login' &&
            currentRoute != '/register') {
          navigator.pushNamed('/pin-lock');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Show PIN lock error: $e');
    }
  }

  Future<void> _checkIfNeedsPinLock() async {
    try {
      final userId = await SecureStorageService.getUserId();
      final prefs = await SharedPreferences.getInstance();

      if (userId != null && userId.isNotEmpty) {
        // ✅ Match the key used by AuthService ('lastActivity')
        final lastActivity = prefs.getInt('lastActivity') ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        final inactiveMinutes = (now - lastActivity) / (1000 * 60);

        // ✅ 30-MINUTE idle threshold (matches AuthService session timeout)
        if (inactiveMinutes >= 30 && !_pinLockShown) {
          _showPinLock();
        }
      }
    } catch (e) {
      debugPrint('⚠️ Check PIN lock error: $e');
    }
  }

  Future<void> _updateActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // ✅ Match the key used by AuthService ('lastActivity')
      await prefs.setInt('lastActivity', DateTime.now().millisecondsSinceEpoch);
      await prefs.reload();
    } catch (e) {
      // Silent fail
    }
  }

  // ==================== BUILD ====================

  Widget _buildErrorWidget() {
    return Material(
      color: Colors.white,
      child: Builder(
        builder:
            (context) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Something went wrong',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1C2D5A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      kReleaseMode
                          ? 'Please restart the app'
                          : 'An error occurred during build',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (!kReleaseMode) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Check the console for details',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        try {
                          // ✅ Navigate safely to role-based dashboard
                          final nav = navigatorKey.currentState;
                          if (nav != null && nav.mounted) {
                            nav.pushNamedAndRemoveUntil(
                              '/dashboard',
                              (route) => false,
                            );
                          } else {
                            Navigator.of(context).pushNamedAndRemoveUntil(
                              '/dashboard',
                              (route) => false,
                            );
                          }
                        } catch (e) {
                          debugPrint('Failed to navigate to dashboard: $e');
                        }
                      },
                      child: const Text('Go to Dashboard'),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ChangeNotifierProvider<WalletProvider>(create: (_) => WalletProvider()),
        ChangeNotifierProvider<ServiceProvider>(
          create: (_) => ServiceProvider(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'DalabaPay',
        debugShowCheckedModeBanner: false,
        theme: DPTheme.light(),
        darkTheme: DPTheme.light(),
        themeMode: ThemeMode.light,
        initialRoute: '/',

        builder: (context, child) {
          ErrorWidget.builder = (errorDetails) => _buildErrorWidget();
          return child ?? const SizedBox.shrink();
        },

        onGenerateRoute: (settings) {
          switch (settings.name) {
            // ==================== AUTH ROUTES ====================
            case '/':
              return MaterialPageRoute(builder: (_) => const SplashScreen());
            case '/onboarding':
              return MaterialPageRoute(
                builder: (_) => const OnboardingScreen(),
              );
            case '/login':
              return MaterialPageRoute(builder: (_) => const LoginScreen());
            case '/register':
              return MaterialPageRoute(builder: (_) => const RegisterScreen());
            case '/forgot-password':
              return MaterialPageRoute(
                builder: (_) => const ForgotPasswordScreen(),
              );
            case '/otp-verification':
              final args = settings.arguments as Map<String, dynamic>?;
              final email = args?['email'] ?? '';
              return MaterialPageRoute(
                builder: (_) => OTPVerificationScreen(email: email),
              );
            case '/reset-password':
              final args = settings.arguments as Map<String, dynamic>?;
              final resetToken = args?['resetToken'] ?? '';
              return MaterialPageRoute(
                builder: (_) => ResetPasswordScreen(resetToken: resetToken),
              );

            // ==================== PIN ROUTES ====================
            case '/pin-setup':
              final args = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute(
                builder:
                    (_) => PinSetupScreen(
                      userId: args?['userId'] ?? '',
                      fullName: args?['fullName'] ?? '',
                      email: args?['email'] ?? '',
                      isFirstTime: args?['isFirstTime'] ?? true,
                      currentPin: args?['currentPin'],
                    ),
              );
            case '/pin-login':
              return MaterialPageRoute(builder: (_) => const PinLoginScreen());
            case '/pin-lock':
              return MaterialPageRoute(builder: (_) => const PinLockScreen());

            // ==================== CHANGE PIN ROUTE ====================
            case '/change-pin':
              final args = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute(
                builder:
                    (_) => ChangePinScreen(
                      userId: args?['userId'] ?? '',
                      userEmail: args?['userEmail'] ?? '',
                      fullName: args?['fullName'] ?? '',
                    ),
              );

            // ==================== MAIN DASHBOARD ====================
            case '/dashboard':
              return MaterialPageRoute(
                builder: (_) => const RoleBasedDashboard(),
              );

            // ==================== ADMIN ROUTES ====================
            case '/admin-dashboard':
              return MaterialPageRoute(
                builder:
                    (_) => const AdminWrapper(child: AdminDashboardScreen()),
              );
            case '/admin-users':
              return MaterialPageRoute(
                builder: (_) => const AdminWrapper(child: AdminUsersPage()),
              );
            case '/admin-transactions':
              return MaterialPageRoute(
                builder:
                    (_) =>
                        const AdminWrapper(child: AdminAllTransactionsPage()),
              );
            case '/admin-status-update':
              return MaterialPageRoute(
                builder:
                    (_) =>
                        const AdminWrapper(child: AdminTransactionStatusPage()),
              );
            case '/admin-refund':
              return MaterialPageRoute(
                builder:
                    (_) => const AdminWrapper(child: AdminRefundSystemPage()),
              );
            case '/admin-fund-wallet':
              return MaterialPageRoute(
                builder:
                    (_) => const AdminWrapper(child: AdminFundWalletPage()),
              );
            case '/admin-verify-payment':
              return MaterialPageRoute(
                builder:
                    (_) => const AdminWrapper(child: AdminVerifyPaymentPage()),
              );
            case '/admin-notifications':
              return MaterialPageRoute(
                builder:
                    (_) =>
                        const AdminWrapper(child: AdminSendNotificationPage()),
              );
            case '/admin-control':
              return MaterialPageRoute(
                builder: (_) => const AdminWrapper(child: AdminControlPage()),
              );
            case '/admin-vtpass':
              return MaterialPageRoute(
                builder:
                    (_) => const AdminWrapper(child: VtpassSettingsDashboard()),
              );
            case '/admin-self-fund':
              return MaterialPageRoute(
                builder: (_) => const AdminWrapper(child: AdminSelfFundPage()),
              );
            case '/admin-service-commission':
              return MaterialPageRoute(
                builder:
                    (_) =>
                        const AdminWrapper(child: AdminServiceCommissionPage()),
              );

            // ==================== USER ROUTES ====================
            case '/settings':
              return MaterialPageRoute(builder: (_) => const SettingsScreen());
            case '/kyc':
              return MaterialPageRoute(builder: (_) => const KYCScreen());
            case '/notifications':
              return MaterialPageRoute(
                builder: (_) => const NotificationsScreen(),
              );
            case '/transactions':
              return MaterialPageRoute(
                builder: (_) {
                  final args = settings.arguments as Map<String, dynamic>?;
                  final userId = args?['userId'] ?? '';
                  return TransactionsScreen(
                    userId: userId,
                    highlightReference: args?['highlightReference'],
                  );
                },
              );
            case '/user-disputes':
              return MaterialPageRoute(
                builder: (_) => const UserDisputesPage(),
              );
            case '/transaction-validation':
              return MaterialPageRoute(
                builder: (_) => const TransactionValidationPage(),
              );

            // ==================== SERVICE ROUTES ====================
            case '/airtime':
              return MaterialPageRoute(
                builder: (_) {
                  final args = settings.arguments as Map<String, dynamic>?;
                  final userId = args?['userId'] ?? '';
                  final onBalanceUpdate =
                      args?['onBalanceUpdate'] as void Function(double)?;
                  return AirtimeScreen(
                    userId: userId,
                    onBalanceUpdate: onBalanceUpdate ?? (_) {},
                  );
                },
              );
            case '/data':
            case '/internet':
              return MaterialPageRoute(
                builder: (_) {
                  final args = settings.arguments as Map<String, dynamic>?;
                  final userId = args?['userId'] ?? '';
                  final onBalanceUpdate =
                      args?['onBalanceUpdate'] as void Function(double)?;
                  return InternetScreen(
                    userId: userId,
                    onBalanceUpdate: onBalanceUpdate ?? (_) {},
                  );
                },
              );
            case '/electricity':
              return MaterialPageRoute(
                builder: (_) {
                  final args = settings.arguments as Map<String, dynamic>?;
                  final userId = args?['userId'] ?? '';
                  final onBalanceUpdate =
                      args?['onBalanceUpdate'] as void Function(double)?;
                  return ElectricityScreen(
                    userId: userId,
                    onBalanceUpdate: onBalanceUpdate ?? (_) {},
                  );
                },
              );
            case '/cabletv':
            case '/cable':
              return MaterialPageRoute(
                builder: (_) {
                  final args = settings.arguments as Map<String, dynamic>?;
                  final userId = args?['userId'] ?? '';
                  final onBalanceUpdate =
                      args?['onBalanceUpdate'] as void Function(double)?;
                  return CableTVScreen(
                    userId: userId,
                    onBalanceUpdate: onBalanceUpdate ?? (_) {},
                  );
                },
              );
            case '/education':
              return MaterialPageRoute(
                builder: (_) {
                  final args = settings.arguments as Map<String, dynamic>?;
                  final userId = args?['userId'] ?? '';
                  final onBalanceUpdate =
                      args?['onBalanceUpdate'] as void Function(double)?;
                  return EducationScreen(
                    userId: userId,
                    onBalanceUpdate: onBalanceUpdate ?? (_) {},
                  );
                },
              );
            case '/international-airtime':
              return MaterialPageRoute(
                builder: (_) {
                  final args = settings.arguments as Map<String, dynamic>?;
                  final userId = args?['userId'] ?? '';
                  final onBalanceUpdate =
                      args?['onBalanceUpdate'] as void Function(double)?;
                  return IntlAirtimeScreen(
                    userId: userId,
                    onBalanceUpdate: onBalanceUpdate ?? (_) {},
                  );
                },
              );
            case '/ticket':
              return MaterialPageRoute(
                builder: (_) {
                  final args = settings.arguments as Map<String, dynamic>?;
                  final userId = args?['userId'] ?? '';
                  final onBalanceUpdate =
                      args?['onBalanceUpdate'] as void Function(double)?;
                  return TicketScreen(
                    userId: userId,
                    onBalanceUpdate: onBalanceUpdate ?? (_) {},
                  );
                },
              );
            case '/commission':
              return MaterialPageRoute(
                builder: (_) {
                  final args = settings.arguments as Map<String, dynamic>?;
                  final userId = args?['userId'] ?? '';
                  final onBalanceUpdate =
                      args?['onBalanceUpdate'] as void Function(double)?;
                  return CommissionScreen(
                    userId: userId,
                    onBalanceUpdate: onBalanceUpdate ?? (_) {},
                  );
                },
              );
            case '/referral':
            case '/referral-earnings':
              return MaterialPageRoute(
                builder: (_) {
                  final args = settings.arguments as Map<String, dynamic>?;
                  final userId = args?['userId'] ?? '';
                  return ReferralEarningsPage(userId: userId);
                },
              );
            case '/betting':
              return MaterialPageRoute(
                builder: (_) {
                  final args = settings.arguments as Map<String, dynamic>?;
                  final userId = args?['userId'] ?? '';
                  final onBalanceUpdate =
                      args?['onBalanceUpdate'] as void Function(double)?;
                  return BettingScreen(
                    userId: userId,
                    onBalanceUpdate: onBalanceUpdate ?? (_) {},
                  );
                },
              );
            case '/insurance':
              return MaterialPageRoute(
                builder: (_) {
                  final args = settings.arguments as Map<String, dynamic>?;
                  final userId = args?['userId'] ?? '';
                  final onBalanceUpdate =
                      args?['onBalanceUpdate'] as void Function(double)?;
                  return InsuranceScreen(
                    userId: userId,
                    onBalanceUpdate: onBalanceUpdate ?? (_) {},
                  );
                },
              );
            case '/donation':
              return MaterialPageRoute(
                builder: (_) {
                  final args = settings.arguments as Map<String, dynamic>?;
                  final userId = args?['userId'] ?? '';
                  final onBalanceUpdate =
                      args?['onBalanceUpdate'] as void Function(double)?;
                  return DonationScreen(
                    userId: userId,
                    onBalanceUpdate: onBalanceUpdate ?? (_) {},
                  );
                },
              );
            case '/wallet':
              return MaterialPageRoute(
                builder: (_) {
                  final args = settings.arguments as Map<String, dynamic>?;
                  final userId = args?['userId'] ?? '';
                  final onBalanceUpdate =
                      args?['onBalanceUpdate'] as void Function(double)?;
                  final initialTab = args?['initialTab'] as String?;
                  return WalletTopUpScreen(
                    userId: userId,
                    onBalanceUpdate: onBalanceUpdate ?? (_) {},
                    initialTab: initialTab,
                  );
                },
              );

            default:
              // ✅ Unknown route → go to role-based dashboard
              return MaterialPageRoute(
                builder: (_) => const RoleBasedDashboard(),
                settings: const RouteSettings(name: '/dashboard'),
              );
          }
        },

        onUnknownRoute: (settings) {
          // ✅ Unknown route → go to role-based dashboard (admin or user)
          return MaterialPageRoute(
            builder: (context) => const RoleBasedDashboard(),
            settings: const RouteSettings(name: '/dashboard'),
          );
        },
      ),
    );
  }
}

// ==================== ROLE BASED DASHBOARD ====================
class RoleBasedDashboard extends StatelessWidget {
  const RoleBasedDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: ApiService.isUserAdmin(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF243889)),
              ),
            ),
          );
        }

        if (snapshot.data == true) {
          return const AdminWrapper(child: AdminDashboardScreen());
        } else {
          return const DashboardScreen();
        }
      },
    );
  }
}

// ==================== NOT FOUND SCREEN ====================
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.screen_search_desktop,
                  size: 80,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  'Page Not Found',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1C2D5A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'The page you are looking for does not exist.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacementNamed(context, '/');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF219C7E),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Go to Home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== SAFE NAVIGATION EXTENSION ====================
extension SafeNavigator on BuildContext {
  Future<T?> safePushNamed<T>(String routeName, {Object? arguments}) async {
    try {
      return await Navigator.pushNamed<T>(
        this,
        routeName,
        arguments: arguments,
      );
    } catch (e) {
      debugPrint('Navigation error to $routeName: $e');
      return null;
    }
  }

  void safePop() {
    try {
      if (Navigator.canPop(this)) {
        Navigator.pop(this);
      }
    } catch (e) {
      debugPrint('Pop error: $e');
    }
  }

  void safePopUntil(String routeName) {
    try {
      Navigator.popUntil(this, (route) => route.settings.name == routeName);
    } catch (e) {
      debugPrint('PopUntil error: $e');
      Navigator.pushReplacementNamed(this, routeName);
    }
  }
}
