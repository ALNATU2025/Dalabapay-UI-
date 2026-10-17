// lib/presentation/screens/admin/admin_dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';
import 'admin_dashboard_home.dart';
import 'admin_wrapper.dart';

// Admin Pages
import 'admin_users_page.dart';
import 'admin_all_transactions_page.dart';
import 'admin_transaction_status_page.dart';
import 'admin_refund_system_page.dart';
import 'admin_fund_wallet_page.dart';
import 'admin_verify_payment_page.dart';
import 'admin_send_notification_page.dart';
import 'admin_control_page.dart';
import 'vtpass_settings_dashboard.dart';
import 'admin_self_fund_page.dart';
import 'admin_service_commission_page.dart';
import 'admin_transaction_limits_page.dart'; // ✅ ADD THIS IMPORT

// User Pages (shared)
import '../dashboard/dashboard_screen.dart';
import '../settings/settings_screen.dart';
import '../user_disputes_page.dart';
import '../transaction_validation_page.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;

  // Track current page for body
  Widget _currentPage = const AdminDashboardHome();

  // Define vibrant colors for different icons (used by CustomDrawer)
  final Map<String, Color> _iconColors = {
    'Admin Dashboard': const Color(0xFF4F46E5), // Indigo
    'All Services': const Color(0xFF0891B2), // Cyan
    'Manage Users': const Color(0xFF059669), // Emerald
    'Transactions': const Color(0xFF2563EB), // Blue
    'Status Update': const Color(0xFF7C3AED), // Purple
    'Refund System': const Color(0xFFDC2626), // Red
    'Fund Wallet': const Color(0xFF16A34A), // Green
    'VTpass Settings': const Color(0xFFF59E0B), // Amber
    'Self Fund': const Color(0xFFD97706), // Orange
    'Verify Payments': const Color(0xFF0D9488), // Teal
    'Notifications': const Color(0xFFEC4899), // Pink
    'Admin Control': const Color(0xFF6366F1), // Indigo
    'Transaction Validation': const Color(0xFF0891B2), // Cyan
    'My Disputes': const Color(0xFFEF4444), // Red
    'App Settings': const Color(0xFF6B7280), // Gray
    'Logout': const Color(0xFFEF4444), // Red
    'Service Commission': const Color(0xFF7C3AED), // Purple
    'Transaction Limits': const Color(0xFFF59E0B), // ✅ ADD THIS - Amber/Yellow
  };

  List<DrawerItem> get _drawerItems => [
    // Admin Dashboard - with ADMIN badge
    const DrawerItem(
      title: "Admin Dashboard",
      icon: Icons.dashboard,
      badge: "ADMIN",
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    // All Services - links to user dashboard
    const DrawerItem(
      title: "All Services",
      icon: Icons.apps,
      page: DashboardScreen(),
      isUserOnly: false,
    ),
    // Admin Items
    const DrawerItem(
      title: "Manage Users",
      icon: Icons.people_alt,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    // ✅ ADD TRANSACTION LIMITS
    const DrawerItem(
      title: "Transaction Limits",
      icon: Icons.speed,
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
    // Service Commission - Super Admin Only
    const DrawerItem(
      title: "Service Commission",
      icon: Icons.trending_up,
      page: SizedBox.shrink(),
      isAdminOnly: true,
    ),
    // User Items
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
    // Settings - everyone
    const DrawerItem(
      title: "App Settings",
      icon: Icons.settings,
      page: SizedBox.shrink(),
    ),
    // Logout - everyone
    const DrawerItem(
      title: "Logout",
      icon: Icons.logout,
      page: SizedBox.shrink(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _currentPage = const AdminDashboardHome();
  }

  void _onItemSelected(DrawerItem item) {
    if (item.title == "Logout") {
      _showLogoutConfirmation();
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
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const AdminWrapper(child: DashboardScreen()),
        ),
      );
      return;
    }

    // Update selected index
    final index = _drawerItems.indexOf(item);
    setState(() {
      _selectedIndex = index;
    });

    // Close drawer
    if (Navigator.canPop(context)) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } else {
      Navigator.pushReplacementNamed(context, '/home');
    }

    // Navigate to the appropriate page
    switch (item.title) {
      case 'Admin Dashboard':
        _navigateToPage(const AdminDashboardHome());
        break;
      case 'Manage Users':
        _navigateToPage(const AdminUsersPage());
        break;
      case 'Transaction Limits': // ✅ ADD THIS CASE
        _navigateToPage(const AdminTransactionLimitsPage());
        break;
      case 'Transactions':
        _navigateToPage(const AdminAllTransactionsPage());
        break;
      case 'Status Update':
        _navigateToPage(const AdminTransactionStatusPage());
        break;
      case 'Refund System':
        _navigateToPage(const AdminRefundSystemPage());
        break;
      case 'Fund Wallet':
        _navigateToPage(const AdminFundWalletPage());
        break;
      case 'VTpass Settings':
        _navigateToPage(const VtpassSettingsDashboard());
        break;
      case 'Self Fund':
        _navigateToPage(const AdminSelfFundPage());
        break;
      case 'Verify Payments':
        _navigateToPage(const AdminVerifyPaymentPage());
        break;
      case 'Notifications':
        _navigateToPage(const AdminSendNotificationPage());
        break;
      case 'Admin Control':
        _navigateToPage(const AdminControlPage());
        break;
      case 'Service Commission':
        _navigateToPage(const AdminServiceCommissionPage());
        break;
      case 'Transaction Validation':
        _navigateToPage(const TransactionValidationPage());
        break;
      case 'My Disputes':
        _navigateToPage(const UserDisputesPage());
        break;
      case 'App Settings':
        _navigateToPage(const SettingsScreen());
        break;
      default:
        break;
    }
  }

  void _navigateToPage(Widget page) {
    setState(() {
      _currentPage = page;
    });
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
        backgroundColor:
            isError ? Colors.red.shade700 : const Color(0xFF219C7E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(16),
      ),
    );
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
                      Navigator.pushReplacementNamed(context, '/home');
                    }
                  } else {
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
                  color: const Color(0xFF219C7E),
                  letterSpacing: 0.09,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF219C7E).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF219C7E).withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              'ADMIN PANEL',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF219C7E),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build drawer item with Hugeicon and vibrant colors
  Widget _buildDrawerItem(DrawerItem item, bool isSelected) {
    final Map<String, dynamic> iconMap = {
      'Admin Dashboard': HugeIcons.strokeRoundedDashboardSquare01,
      'All Services': HugeIcons.strokeRoundedMenuSquare,
      'Manage Users': HugeIcons.strokeRoundedUserGroup,
      'Transactions': HugeIcons.strokeRoundedReceiptText,
      'Status Update': HugeIcons.strokeRoundedShare06,
      'Refund System': HugeIcons.strokeRoundedMoneyExchange01,
      'Fund Wallet': HugeIcons.strokeRoundedWallet01,
      'VTpass Settings': HugeIcons.strokeRoundedApi,
      'Self Fund': HugeIcons.strokeRoundedMoneyAdd01,
      'Verify Payments': HugeIcons.strokeRoundedAward05,
      'Notifications': HugeIcons.strokeRoundedNotification01,
      'Admin Control': HugeIcons.strokeRoundedSettings01,
      'Transaction Validation': HugeIcons.strokeRoundedAward05,
      'My Disputes': HugeIcons.strokeRoundedLegal01,
      'App Settings': HugeIcons.strokeRoundedSetting06,
      'Service Commission': HugeIcons.strokeRoundedAnalyticsUp,
      'Transaction Limits': HugeIcons.strokeRoundedDashboardSpeed01, // ✅ ADD THIS
      'Logout': HugeIcons.strokeRoundedLogout01,
    };

    final iconData = iconMap[item.title] ?? HugeIcons.strokeRoundedCircle;
    final iconColor =
        isSelected
            ? const Color(0xFF243889)
            : (_iconColors[item.title] ?? Colors.grey.shade600);

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? const Color(0xFF243889).withValues(alpha: 0.1)
                  : iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: HugeIcon(
          icon: iconData,
          color: isSelected ? const Color(0xFF243889) : iconColor,
          size: 22,
        ),
      ),
      title: Text(
        item.title,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          color: isSelected ? const Color(0xFF243889) : Colors.grey.shade800,
        ),
      ),
      trailing:
          item.badge != null
              ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF219C7E),
                      const Color(0xFF219C7E).withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  item.badge!,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              )
              : null,
      selected: isSelected,
      selectedTileColor: const Color(0xFF243889).withValues(alpha: 0.06),
      onTap: () => _onItemSelected(item),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.menu, color: const Color(0xFF243889)),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Dalaba',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF243889),
                letterSpacing: 0.09,
              ),
            ),
            Text(
              'pay',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF219C7E),
                letterSpacing: 0.09,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF243889)),
            onPressed: () {
              if (_currentPage is AdminDashboardHome) {
                setState(() {
                  _currentPage = const AdminDashboardHome();
                });
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: CustomDrawer(
        header: _buildDrawerHeader(),
        items: _drawerItems,
        selectedItem: _drawerItems.firstWhere(
          (item) => item.title == "Admin Dashboard",
          orElse: () => _drawerItems.first,
        ),
        onItemSelected: _onItemSelected,
        isAdmin: true,
      ),
      body: _currentPage,
    );
  }
}