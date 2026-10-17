// lib/presentation/screens/admin/admin_transaction_limits_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';
import '../dashboard/dashboard_screen.dart';
import '../../../core/services/secure_storage_service.dart';

class AdminTransactionLimitsPage extends StatefulWidget {
  const AdminTransactionLimitsPage({super.key});

  @override
  State<AdminTransactionLimitsPage> createState() =>
      _AdminTransactionLimitsPageState();
}

class _AdminTransactionLimitsPageState extends State<AdminTransactionLimitsPage>
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

  // ==================== STATE VARIABLES ====================
  bool _isLoading = true;
  bool _isAdmin = false;
  bool _isSuperAdmin = false;
  String? _errorMessage;
  String _currentUserId = '';

  // Users list
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  // Selected user for limit management
  Map<String, dynamic>? _selectedUser;
  bool _isEditingUser = false;

  // Limit configuration
  // Limit configuration
  final Map<String, TextEditingController> _perTransactionControllers = {};
  final Map<String, TextEditingController> _dailyLimitControllers = {};
  final Map<String, bool> _customLimitEnabled = {};
  bool _isSavingLimits = false;

  // ✅ NEW: Default limits editing state (system-wide limits)
  final Map<String, TextEditingController> _defaultPerTxnControllers = {};
  final Map<String, TextEditingController> _defaultDailyControllers = {};
  bool _isSavingDefaults = false;

  // Maintenance mode
  bool _maintenanceMode = false;
  bool _isTogglingMaintenance = false;
  final TextEditingController _maintenanceMessageController =
      TextEditingController();

  // Service enable/disable
  final Map<String, bool> _serviceStatus = {
    'airtime': true,
    'data': true,
    'electricity': true,
    'cable': true,
    'transfer': true,
    'international_airtime': true,
    'education': true,
    'insurance': true,
  };

  // Service labels
  final Map<String, String> _serviceLabels = {
    'airtime': 'Airtime',
    'data': 'Data',
    'electricity': 'Electricity',
    'cable': 'Cable TV',
    'transfer': 'Money Transfer',
    'international_airtime': 'International Airtime',
    'education': 'Education',
    'insurance': 'Insurance',
  };

  // Service icons
  // Service icons
  final Map<String, dynamic> _serviceIcons = {
    'airtime': HugeIcons.strokeRoundedSmartPhone01,
    'data': HugeIcons.strokeRoundedWifi01,
    'electricity': HugeIcons.strokeRoundedBulb,
    'cable': HugeIcons.strokeRoundedTv01,
    'transfer': HugeIcons.strokeRoundedSquareArrowDataTransferHorizontal,
    'international_airtime': HugeIcons.strokeRoundedTelephone,
    'education': HugeIcons.strokeRoundedMortarboard01,
    'insurance': HugeIcons.strokeRoundedShield01,
  };

  // Default limits
  // Default limits - MUST MATCH BACKEND TRANSACTION_LIMITS
  final Map<String, Map<String, double>> _defaultLimits = {
    'airtime': {'perTransaction': 1000, 'dailyCap': 5000},
    'data': {'perTransaction': 10000, 'dailyCap': 10000},
    'electricity': {'perTransaction': 50000, 'dailyCap': 100000},
    'cable': {'perTransaction': 100000, 'dailyCap': 500000}, // ✅ Updated
    'transfer': {'perTransaction': 50000, 'dailyCap': 100000},
    'international_airtime': {'perTransaction': 10000, 'dailyCap': 50000},
    'education': {'perTransaction': 50000, 'dailyCap': 100000},
    'insurance': {'perTransaction': 50000, 'dailyCap': 100000},
  };

  // Animation
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  // ==================== INIT STATE ====================
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
          _filterUsers();
        }
      });
    });

    // Initialize controllers for all services
    // Initialize controllers for all services (per-user custom limits)
    for (final service in _defaultLimits.keys) {
      _perTransactionControllers[service] = TextEditingController();
      _dailyLimitControllers[service] = TextEditingController();
      _customLimitEnabled[service] = false;

      // ✅ NEW: Initialize default limits controllers (system-wide)
      _defaultPerTxnControllers[service] = TextEditingController();
      _defaultDailyControllers[service] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _maintenanceMessageController.dispose();
    for (final controller in _perTransactionControllers.values) {
      controller.dispose();
    }
    for (final controller in _dailyLimitControllers.values) {
      controller.dispose();
    }
    // ✅ NEW: Dispose default limits controllers
    for (final controller in _defaultPerTxnControllers.values) {
      controller.dispose();
    }
    for (final controller in _defaultDailyControllers.values) {
      controller.dispose();
    }
    _searchDebounce?.cancel();
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
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
  }

  void _log(String message) {
    debugPrint(message);
  }

  // ==================== DATA LOADING ====================
  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user');

      if (userDataString != null) {
        final userData = jsonDecode(userDataString);
        _currentUserId = userData['_id']?.toString() ?? '';

        // Check admin status
        _isAdmin = userData['isAdmin'] == true;
        _isSuperAdmin = _isUserSuperAdmin(userData);

        if (_isAdmin) {
          // ✅ Fetch default limits from backend FIRST
          await _fetchDefaultLimitsFromBackend();
          // ✅ Then fetch users
          await _fetchUsers();
          await _fetchMaintenanceStatus();
          await _fetchServiceStatus();
          _animationController.forward();
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = "You don't have permission to access this page.";
          });
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = "User data not found. Please log in again.";
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Error loading data: ${e.toString()}";
      });
    }
  }

  bool _isUserSuperAdmin(Map<String, dynamic> userData) {
    final userId = userData['_id']?.toString() ?? '';
    final email = userData['email']?.toString().toLowerCase() ?? '';

    const superAdminIds = [
      "690088325ca99bed6ab8d4a5",
      "6917abd88d1943c6ecebfc5f",
    ];

    const superAdminEmails = ["adam@gmail.com", "dalabapays@gmail.com"];

    return superAdminIds.contains(userId) || superAdminEmails.contains(email);
  }

  Future<void> _fetchUsers() async {
    try {
      final token = await SecureStorageService.getAccessToken();
      if (token == null || token.isEmpty) {
        debugPrint('⚠️ No token found, cannot fetch users');
        setState(() {
          _isLoading = false;
          _errorMessage = 'Please log in again to access this page.';
        });
        return;
      }

      debugPrint('✅ Token found: ${token.substring(0, 10)}...');

      final users = await ApiService.getAllUsersForAdmin();
      debugPrint('✅ Retrieved ${users.length} users');

      setState(() {
        _users = List<Map<String, dynamic>>.from(users);
        _filteredUsers = _users;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error fetching users: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load users: ${e.toString()}';
      });
    }
  }

  Future<void> _fetchDefaultLimitsFromBackend() async {
    try {
      _log('📊 Fetching default limits from backend...');

      final limits = await ApiService.getDefaultLimits();

      final perTransaction = limits['perTransaction'] as Map<String, dynamic>?;
      final daily = limits['daily'] as Map<String, dynamic>?;

      if (perTransaction != null && daily != null) {
        // ✅ Update the default limits map with backend values
        for (final service in _defaultLimits.keys) {
          final perTxnRaw = perTransaction[service];
          final dailyRaw = daily[service];

          final perTxn =
              perTxnRaw is num
                  ? perTxnRaw.toDouble()
                  : double.tryParse(perTxnRaw?.toString() ?? '') ?? 0;
          final dailyCap =
              dailyRaw is num
                  ? dailyRaw.toDouble()
                  : double.tryParse(dailyRaw?.toString() ?? '') ?? 0;

                    // ✅ Accept 0 too — 0 = UNLIMITED on the backend
          _defaultLimits[service] = {
            'perTransaction': perTxn,
            'dailyCap': dailyCap,
          };

          _log(
            '✅ Updated $service: perTransaction = ${
              perTxn == 0 ? 'UNLIMITED' : '₦$perTxn'
            }, dailyCap = ${
              dailyCap == 0 ? 'UNLIMITED' : '₦$dailyCap'
            }',
          );
        }
      }
    } catch (e) {
      _log('❌ Error fetching default limits: $e');
      // Keep hardcoded defaults as fallback
    }
  }

  Future<void> _fetchMaintenanceStatus() async {
    try {
      final response = await ApiService.authenticatedGet(
        '/api/maintenance-status',
      );
      if (response['maintenanceMode'] != null) {
        setState(() {
          _maintenanceMode = response['maintenanceMode'] == true;
          _maintenanceMessageController.text =
              response['message']?.toString() ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error fetching maintenance status: $e');
    }
  }

  Future<void> _fetchServiceStatus() async {
    try {
      final settings = await ApiService.getAppSettings();
      if (settings['settings'] != null) {
        final data = settings['settings'];
        setState(() {
          _serviceStatus['airtime'] = data['isAirtimeEnabled'] ?? true;
          _serviceStatus['data'] = data['isDataEnabled'] ?? true;
          _serviceStatus['electricity'] = data['isElectricityEnabled'] ?? true;
          _serviceStatus['cable'] = data['isCableTvEnabled'] ?? true;
          _serviceStatus['transfer'] = data['isTransferEnabled'] ?? true;
          _serviceStatus['international_airtime'] =
              data['isInternationalAirtimeEnabled'] ?? true;
          _serviceStatus['education'] = data['isEducationEnabled'] ?? true;
          _serviceStatus['insurance'] = data['isInsuranceEnabled'] ?? true;
        });
      }
    } catch (e) {
      debugPrint('Error fetching service status: $e');
    }
  }

  void _filterUsers() {
    final query = _searchQuery.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() {
        _filteredUsers = _users;
      });
      return;
    }

    setState(() {
      _filteredUsers =
          _users.where((user) {
            final name = user['fullName']?.toString().toLowerCase() ?? '';
            final email = user['email']?.toString().toLowerCase() ?? '';
            final id = user['_id']?.toString().toLowerCase() ?? '';
            final phone = user['phone']?.toString().toLowerCase() ?? '';
            return name.contains(query) ||
                email.contains(query) ||
                id.contains(query) ||
                phone.contains(query);
          }).toList();
    });
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
              color: secondaryColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: secondaryColor.withOpacity(0.3)),
            ),
            child: Text(
              _isSuperAdmin ? 'SUPER ADMIN' : 'ADMIN PANEL',
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
                  'Admin / Transaction Limits',
                  style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: isMobile ? 12 : 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (_isSuperAdmin)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 10 : 14,
                    vertical: isMobile ? 4 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: warningColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star,
                        color: Colors.white,
                        size: isMobile ? 10 : 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'SUPER ADMIN',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: isMobile ? 8 : 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
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
                  Icons.speed_rounded,
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
                      'Transaction Limits',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: isMobile ? 20 : 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: isMobile ? 4 : 6),
                    Text(
                      'Manage user limits & service availability',
                      style: GoogleFonts.inter(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: isMobile ? 12 : 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _refreshData,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
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

          // Search Bar
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
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedSearch01,
                  color: primaryColor.withOpacity(0.5),
                  size: isMobile ? 18 : 22,
                ),
                SizedBox(width: isMobile ? 10 : 14),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText:
                          isMobile
                              ? 'Search users...'
                              : 'Search by name, email, phone or ID...',
                      hintStyle: GoogleFonts.inter(
                        color: primaryColor.withOpacity(0.4),
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
                      _filterUsers();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        color: primaryColor.withOpacity(0.5),
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

  // ==================== MAINTENANCE MODE SECTION ====================
  Widget _buildMaintenanceSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (_maintenanceMode ? errorColor : successColor)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: HugeIcon(
                    icon:
                        _maintenanceMode
                            ? HugeIcons.strokeRoundedAlert01
                            : HugeIcons.strokeRoundedCheckmarkCircle01,
                    color: _maintenanceMode ? errorColor : successColor,
                    size: isMobile ? 20 : 24,
                  ),
                ),
                SizedBox(width: isMobile ? 12 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Maintenance Mode',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 15 : 17,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        _maintenanceMode
                            ? '⚠️ All services are currently disabled'
                            : '✅ All services are active',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 12 : 13,
                          color: _maintenanceMode ? errorColor : successColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _maintenanceMode,
                  onChanged: _isTogglingMaintenance ? null : _toggleMaintenance,
                  activeThumbColor: primaryColor,
                  inactiveThumbColor: Colors.grey[400],
                  activeTrackColor: primaryColor.withOpacity(0.3),
                  inactiveTrackColor: Colors.grey[300],
                ),
              ],
            ),
            if (_maintenanceMode) ...[
              SizedBox(height: isMobile ? 12 : 16),
              Container(
                padding: EdgeInsets.all(isMobile ? 12 : 14),
                decoration: BoxDecoration(
                  color: warningColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: warningColor.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Maintenance Message',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 12 : 13,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    SizedBox(height: isMobile ? 8 : 10),
                    TextField(
                      controller: _maintenanceMessageController,
                      maxLines: 2,
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 13 : 14,
                        color: textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Enter maintenance message...',
                        hintStyle: GoogleFonts.inter(
                          color: Colors.grey.shade400,
                          fontSize: isMobile ? 12 : 13,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: primaryColor, width: 2),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 12 : 14,
                          vertical: isMobile ? 10 : 12,
                        ),
                      ),
                    ),
                    SizedBox(height: isMobile ? 8 : 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            _isTogglingMaintenance
                                ? null
                                : _updateMaintenanceMessage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            vertical: isMobile ? 10 : 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon:
                            _isTogglingMaintenance
                                ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                                : HugeIcon(
                                  icon: HugeIcons.strokeRoundedSave,
                                  color: Colors.white,
                                  size: isMobile ? 16 : 18,
                                ),
                        label: Text(
                          _isTogglingMaintenance
                              ? 'Saving...'
                              : 'Update Message',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: isMobile ? 13 : 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: isMobile ? 8 : 12),
              Container(
                padding: EdgeInsets.all(isMobile ? 10 : 12),
                decoration: BoxDecoration(
                  color: errorColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: errorColor,
                      size: isMobile ? 16 : 18,
                    ),
                    SizedBox(width: isMobile ? 8 : 10),
                    Expanded(
                      child: Text(
                        'Users can still login and view balances, but cannot perform any transactions.',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 11 : 12,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==================== SERVICE TOGGLES SECTION ====================
  Widget _buildServiceTogglesSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final serviceKeys = _serviceStatus.keys.toList();

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: infoColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedSettings01,
                    color: infoColor,
                    size: isMobile ? 20 : 24,
                  ),
                ),
                SizedBox(width: isMobile ? 12 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Service Controls',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 15 : 17,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        'Enable or disable individual services',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 12 : 13,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: isMobile ? 12 : 16),

            // Service toggles in a grid
            Wrap(
              spacing: isMobile ? 8 : 12,
              runSpacing: isMobile ? 8 : 10,
              children:
                  serviceKeys.map((service) {
                    final isEnabled = _serviceStatus[service] ?? true;
                    final label = _serviceLabels[service] ?? service;
                    final icon = _serviceIcons[service] ?? Icons.help_outline;

                    return Container(
                      width:
                          isMobile
                              ? (MediaQuery.of(context).size.width - 60) / 2
                              : 140,
                      padding: EdgeInsets.all(isMobile ? 10 : 12),
                      decoration: BoxDecoration(
                        color:
                            isEnabled
                                ? successColor.withOpacity(0.08)
                                : errorColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              isEnabled
                                  ? successColor.withOpacity(0.2)
                                  : errorColor.withOpacity(0.2),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          HugeIcon(
                            icon: icon,
                            color: isEnabled ? successColor : errorColor,
                            size: isMobile ? 16 : 18,
                          ),
                          SizedBox(width: isMobile ? 6 : 8),
                          Expanded(
                            child: Text(
                              label,
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 11 : 12,
                                fontWeight: FontWeight.w500,
                                color: isEnabled ? successColor : errorColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Switch(
                            value: isEnabled,
                            onChanged: (value) => _toggleService(service),
                            activeThumbColor: successColor,
                            inactiveThumbColor: Colors.grey[400],
                            activeTrackColor: successColor.withOpacity(0.3),
                            inactiveTrackColor: Colors.grey[300],
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== USER SELECTION / LIMIT MANAGEMENT ====================
  Widget _buildUserSelectionSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (_selectedUser == null) {
      return Container(
        margin: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 16,
          vertical: 8,
        ),
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedUser,
                    color: primaryColor,
                    size: isMobile ? 20 : 24,
                  ),
                ),
                SizedBox(width: isMobile ? 12 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select a User',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 15 : 17,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        'Click a user to manage their transaction limits',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 12 : 13,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: isMobile ? 12 : 16),

            // User list
            if (_isLoading)
              _buildUsersLoadingShimmer(isMobile)
            else if (_filteredUsers.isEmpty)
              _buildEmptyState(isMobile)
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _filteredUsers.length,
                itemBuilder: (context, index) {
                  final user = _filteredUsers[index];
                  return _buildUserTile(user, isMobile);
                },
              ),
          ],
        ),
      );
    } else {
      return _buildLimitEditor(isMobile);
    }
  }

  Widget _buildUserTile(Map<String, dynamic> user, bool isMobile) {
    final userId = user['_id']?.toString() ?? '';
    final userName = user['fullName']?.toString() ?? 'Unknown User';
    final userEmail = user['email']?.toString() ?? 'No Email';
    final isAdmin = user['isAdmin'] == true;
    final isCurrentUser = userId == _currentUserId;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: ListTile(
        onTap: () {
          setState(() {
            _selectedUser = user;
            _loadUserLimits(user);
          });
        },
        leading: Container(
          width: isMobile ? 40 : 44,
          height: isMobile ? 40 : 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryColor, primaryColor.withOpacity(0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              userName.isNotEmpty ? userName[0].toUpperCase() : '?',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        title: Text(
          userName,
          style: GoogleFonts.inter(
            fontSize: isMobile ? 14 : 15,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
        ),
        subtitle: Text(
          userEmail,
          style: GoogleFonts.inter(
            fontSize: isMobile ? 11 : 12,
            color: textSecondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isAdmin)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Admin',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 8 : 9,
                    color: primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (isCurrentUser)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: infoColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'You',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 8 : 9,
                    color: infoColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey.shade400,
              size: isMobile ? 20 : 24,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== LIMIT EDITOR ====================
  Widget _buildLimitEditor(bool isMobile) {
    final user = _selectedUser!;
    final userName = user['fullName']?.toString() ?? 'Unknown User';
    final userEmail = user['email']?.toString() ?? '';

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User header with back button
            Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedUser = null;
                      _isEditingUser = false;
                      _resetLimitControllers();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: primaryColor,
                      size: isMobile ? 18 : 20,
                    ),
                  ),
                ),
                SizedBox(width: isMobile ? 12 : 14),
                Container(
                  width: isMobile ? 40 : 44,
                  height: isMobile ? 40 : 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [primaryColor, primaryColor.withOpacity(0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: isMobile ? 16 : 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: isMobile ? 10 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 14 : 16,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        userEmail,
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 11 : 12,
                          color: textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_isSavingLimits)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primaryColor,
                    ),
                  ),
              ],
            ),
            SizedBox(height: isMobile ? 16 : 20),

            // Service limits
            Text(
              'Transaction Limits per Service',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 14 : 16,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            SizedBox(height: isMobile ? 8 : 12),
            Text(
              'Set custom limits for this user. Leave empty to use default values.',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 11 : 12,
                color: textSecondary,
              ),
            ),
            SizedBox(height: isMobile ? 12 : 16),

            // Limit cards
            ..._defaultLimits.keys.map((service) {
              return _buildLimitCard(service, isMobile);
            }),

            SizedBox(height: isMobile ? 16 : 20),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _isSavingLimits
                            ? null
                            : () {
                              setState(() {
                                _selectedUser = null;
                                _isEditingUser = false;
                                _resetLimitControllers();
                              });
                            },
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 12 : 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: isMobile ? 10 : 14),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isSavingLimits ? null : _saveUserLimits,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: secondaryColor,
                      padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 12 : 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _isSavingLimits ? 'Saving...' : 'Save Limits',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
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
  }

  Widget _buildLimitCard(String service, bool isMobile) {
    final label = _serviceLabels[service] ?? service;
    final icon = _serviceIcons[service] ?? Icons.help_outline;
    final defaultPerTxn = _defaultLimits[service]?['perTransaction'] ?? 0;
    final defaultDaily = _defaultLimits[service]?['dailyCap'] ?? 0;

    final isCustom = _customLimitEnabled[service] ?? false;
    final perTxnController = _perTransactionControllers[service]!;
    final dailyController = _dailyLimitControllers[service]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              isCustom ? primaryColor.withOpacity(0.3) : Colors.grey.shade200,
          width: isCustom ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: icon,
                color: primaryColor,
                size: isMobile ? 18 : 20,
              ),
              SizedBox(width: isMobile ? 8 : 10),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 13 : 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
              // ✅ Show system default badge
              if (!isCustom)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'System Default',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 8 : 9,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Custom',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 10 : 11,
                      color: isCustom ? primaryColor : Colors.grey.shade500,
                    ),
                  ),
                  Switch(
                    value: isCustom,
                    onChanged: (value) {
                      setState(() {
                        _customLimitEnabled[service] = value;
                        if (!value) {
                          perTxnController.clear();
                          dailyController.clear();
                        }
                      });
                    },
                    activeThumbColor: primaryColor,
                    inactiveThumbColor: Colors.grey[400],
                    activeTrackColor: primaryColor.withOpacity(0.3),
                    inactiveTrackColor: Colors.grey[300],
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: isMobile ? 8 : 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Per Transaction (₦)',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 10 : 11,
                            color: textSecondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (!isCustom)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: infoColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '₦${defaultPerTxn.toStringAsFixed(0)}',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 8 : 9,
                                color: infoColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              isCustom
                                  ? primaryColor.withOpacity(0.3)
                                  : Colors.grey.shade300,
                        ),
                      ),
                      child: TextField(
                        controller: perTxnController,
                        enabled: isCustom,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d{0,2}'),
                          ),
                        ],
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 13 : 14,
                          color: isCustom ? textPrimary : Colors.grey.shade400,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              isCustom
                                  ? 'Enter amount...'
                                  : 'Use system default',
                          hintStyle: GoogleFonts.inter(
                            fontSize: isMobile ? 11 : 12,
                            color:
                                isCustom
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade300,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 10 : 12,
                            vertical: isMobile ? 8 : 10,
                          ),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              '₦',
                              style: GoogleFonts.inter(
                                color:
                                    isCustom
                                        ? textPrimary
                                        : Colors.grey.shade400,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 0,
                            minHeight: 0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: isMobile ? 10 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Daily Cap (₦)',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 10 : 11,
                            color: textSecondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (!isCustom)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: infoColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '₦${defaultDaily.toStringAsFixed(0)}',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 8 : 9,
                                color: infoColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              isCustom
                                  ? primaryColor.withOpacity(0.3)
                                  : Colors.grey.shade300,
                        ),
                      ),
                      child: TextField(
                        controller: dailyController,
                        enabled: isCustom,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d{0,2}'),
                          ),
                        ],
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 13 : 14,
                          color: isCustom ? textPrimary : Colors.grey.shade400,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              isCustom
                                  ? 'Enter amount...'
                                  : 'Use system default',
                          hintStyle: GoogleFonts.inter(
                            fontSize: isMobile ? 11 : 12,
                            color:
                                isCustom
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade300,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 10 : 12,
                            vertical: isMobile ? 8 : 10,
                          ),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              '₦',
                              style: GoogleFonts.inter(
                                color:
                                    isCustom
                                        ? textPrimary
                                        : Colors.grey.shade400,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 0,
                            minHeight: 0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // ✅ Show a note when custom limits are enabled
          if (isCustom)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: warningColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: warningColor.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedInformationCircle,
                      color: warningColor,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Custom limits override system defaults for this user',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 10 : 11,
                          color: warningColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== LIMIT OPERATIONS ====================
  void _loadUserLimits(Map<String, dynamic>? user) {
    if (user == null) {
      _resetLimitControllers();
      setState(() {
        _isEditingUser = false;
      });
      return;
    }

    // Reset controllers
    _resetLimitControllers();

    // Check if user has custom limits
    final customLimits = user['customLimits'] ?? {};

    _log('📂 Loading custom limits for user: ${user['fullName']}');
    _log('📂 Custom limits data: ${jsonEncode(customLimits)}');

    for (final service in _defaultLimits.keys) {
      final serviceLimits = customLimits[service];
      if (serviceLimits != null) {
        final perTxn = serviceLimits['perTransaction'];
        final daily = serviceLimits['dailyCap'];

        // ✅ Check if either limit is set and > 0
        final hasPerTxn = perTxn != null && perTxn > 0;
        final hasDaily = daily != null && daily > 0;

        if (hasPerTxn || hasDaily) {
          if (hasPerTxn) {
            _perTransactionControllers[service]?.text = perTxn.toString();
          }
          if (hasDaily) {
            _dailyLimitControllers[service]?.text = daily.toString();
          }
          _customLimitEnabled[service] = true;

          _log(
            '✅ Loaded custom limits for $service: perTransaction = $perTxn, dailyCap = $daily',
          );
        }
      }
    }

    setState(() {
      _isEditingUser = true;
    });
  }

  void _resetLimitControllers() {
    for (final service in _defaultLimits.keys) {
      _perTransactionControllers[service]?.clear();
      _dailyLimitControllers[service]?.clear();
      _customLimitEnabled[service] = false;
    }
  }

  Future<void> _saveUserLimits() async {
    if (_selectedUser == null) return;

    setState(() {
      _isSavingLimits = true;
    });

    try {
      final userId = _selectedUser!['_id']?.toString() ?? '';
      final String userName = _selectedUser!['fullName']?.toString() ?? 'User';
      final customLimits = <String, dynamic>{};

      for (final service in _defaultLimits.keys) {
        final isCustom = _customLimitEnabled[service] ?? false;
        if (isCustom) {
          final perTxnText =
              _perTransactionControllers[service]?.text.trim() ?? '';
          final dailyText = _dailyLimitControllers[service]?.text.trim() ?? '';

          final perTxn = double.tryParse(perTxnText);
          final daily = double.tryParse(dailyText);

          // ✅ Accept 0 (unlimited) — only skip if BOTH fields are empty
          final hasPerTxn =
              perTxnText.isNotEmpty && perTxn != null && perTxn >= 0;
          final hasDaily = dailyText.isNotEmpty && daily != null && daily >= 0;

          if (hasPerTxn || hasDaily) {
            customLimits[service] = {
              'perTransaction':
                  hasPerTxn
                      ? perTxn
                      : (_defaultLimits[service]?['perTransaction'] ?? 0),
              'dailyCap':
                  hasDaily
                      ? daily
                      : (_defaultLimits[service]?['dailyCap'] ?? 0),
            };
          }
        }
      }

      _log(
        '📦 Saving custom limits for $userName: ${jsonEncode(customLimits)}',
      );

      final response = await ApiService.adminUpdateUser(
        userId: userId,
        data: {'customLimits': customLimits},
      );

      if (response['success'] == true) {
        _showSnackBar('✅ Limits updated successfully for $userName', false);

        // Update user in local list
        final index = _users.indexWhere((u) => u['_id'] == userId);
        if (index != -1) {
          _users[index]['customLimits'] = customLimits;
          _users[index] = Map<String, dynamic>.from(_users[index]);
        }

        setState(() {
          _selectedUser = null;
          _isEditingUser = false;
          _resetLimitControllers();
        });

        await _fetchUsers();

        // Re-select the updated user
        final updatedUser = _users.firstWhere(
          (u) => u['_id'] == userId,
          orElse: () => {},
        );

        if (updatedUser.isNotEmpty) {
          _log('📂 Re-selecting user with updated limits');
          setState(() {
            _selectedUser = updatedUser;
            _loadUserLimits(updatedUser);
          });
        }
      } else {
        _showSnackBar(response['message'] ?? 'Failed to update limits', true);
      }
    } catch (e) {
      _log('❌ Error saving limits: $e');
      _showSnackBar('Error: ${e.toString()}', true);
    } finally {
      if (mounted) {
        setState(() {
          _isSavingLimits = false;
        });
      }
    }
  }

  // ==================== MAINTENANCE OPERATIONS ====================
  Future<void> _toggleMaintenance(bool value) async {
    setState(() {
      _isTogglingMaintenance = true;
    });

    try {
      final messageText = _maintenanceMessageController.text.trim();
      final defaultMessage =
          value
              ? 'System is currently under maintenance. Please check back shortly.'
              : '';

      final response =
          await ApiService.authenticatedPost('/api/admin/maintenance', {
            'isMaintenanceMode': value,
            'message': messageText.isNotEmpty ? messageText : defaultMessage,
          });

      if (response['success'] == true) {
        setState(() {
          _maintenanceMode = value;
          final serverMessage =
              response['maintenanceMessage']?.toString() ?? '';
          if (serverMessage.isNotEmpty) {
            _maintenanceMessageController.text = serverMessage;
          }
        });
        _showSnackBar(
          value ? '🔧 Maintenance mode enabled' : '✅ Maintenance mode disabled',
          false,
        );
        _fetchMaintenanceStatus();
      } else {
        _showSnackBar(
          response['message'] ?? 'Failed to toggle maintenance mode',
          true,
        );
      }
    } catch (e) {
      _showSnackBar('Error: ${e.toString()}', true);
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingMaintenance = false;
        });
      }
    }
  }

  Future<void> _updateMaintenanceMessage() async {
    setState(() {
      _isTogglingMaintenance = true;
    });

    try {
      final response =
          await ApiService.authenticatedPost('/api/admin/maintenance', {
            'isMaintenanceMode': _maintenanceMode,
            'message': _maintenanceMessageController.text.trim(),
          });

      if (response['success'] == true) {
        _showSnackBar('✅ Maintenance message updated', false);
        _fetchMaintenanceStatus();
      } else {
        _showSnackBar(response['message'] ?? 'Failed to update message', true);
      }
    } catch (e) {
      _showSnackBar('Error: ${e.toString()}', true);
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingMaintenance = false;
        });
      }
    }
  }

  // ==================== SERVICE TOGGLE OPERATIONS ====================
  Future<void> _toggleService(String service) async {
    final currentStatus = _serviceStatus[service] ?? true;
    final newStatus = !currentStatus;

    // Update UI optimistically
    setState(() {
      _serviceStatus[service] = newStatus;
    });

    try {
      final response = await ApiService.authenticatedPost(
        '/api/admin/service-toggle',
        {'service': service, 'enabled': newStatus},
      );

      if (response['success'] != true) {
        // Revert on failure
        setState(() {
          _serviceStatus[service] = currentStatus;
        });
        _showSnackBar(response['message'] ?? 'Failed to toggle service', true);
      } else {
        _showSnackBar(
          '${_serviceLabels[service] ?? service} ${newStatus ? 'enabled' : 'disabled'}',
          false,
        );
        _fetchServiceStatus();
      }
    } catch (e) {
      // Revert on error
      setState(() {
        _serviceStatus[service] = currentStatus;
      });
      _showSnackBar('Error: ${e.toString()}', true);
    }
  }

  // ==================== REFRESH ====================
  Future<void> _refreshData() async {
    // ✅ Check token first
    final token = await SecureStorageService.getAccessToken();
    if (token == null || token.isEmpty) {
      _showSnackBar('Please log in again', true);
      return;
    }

    await Future.wait([
      _fetchUsers(),
      _fetchMaintenanceStatus(),
      _fetchServiceStatus(),
    ]);
    _showSnackBar('✅ Data refreshed successfully', false);
  }

  // ==================== HELPERS ====================
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

  // ==================== LOADING & EMPTY STATES ====================
  Widget _buildUsersLoadingShimmer(bool isMobile) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Column(
        children: List.generate(
          4,
          (index) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 20 : 32),
      child: Center(
        child: Column(
          children: [
            Container(
              width: isMobile ? 60 : 80,
              height: isMobile ? 60 : 80,
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_search_rounded,
                color: primaryColor,
                size: isMobile ? 30 : 40,
              ),
            ),
            SizedBox(height: isMobile ? 12 : 16),
            Text(
              'No Users Found',
              style: GoogleFonts.poppins(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            SizedBox(height: isMobile ? 4 : 6),
            Text(
              'Try adjusting your search criteria',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 12 : 14,
                color: textSecondary,
              ),
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
          (item) => item.title == "Transaction Limits",
          orElse: () => _drawerItems.first,
        ),
        onItemSelected: _onDrawerItemSelected,
        isAdmin: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          key: _refreshIndicatorKey,
          onRefresh: _refreshData,
          color: primaryColor,
          backgroundColor: Colors.white,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.white, Colors.grey.shade50],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              if (_isLoading)
                _buildLoadingState()
              else if (_errorMessage != null)
                _buildErrorState()
              else
                CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          _buildAdminHeader(),
                          _buildMaintenanceSection(),
                          _buildServiceTogglesSection(),
                          _buildDefaultLimitsEditor(),
                          _buildUserSelectionSection(),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== DEFAULT LIMITS EDITOR (NEW) ====================
  Widget _buildDefaultLimitsEditor() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: primaryColor.withOpacity(0.15), width: 1.5),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: warningColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedSetting06,
                    color: warningColor,
                    size: isMobile ? 20 : 24,
                  ),
                ),
                SizedBox(width: isMobile ? 12 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'System Default Limits',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 15 : 17,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        'These are the global fallback limits for all users',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 12 : 13,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isSavingDefaults)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primaryColor,
                    ),
                  ),
              ],
            ),
            SizedBox(height: isMobile ? 12 : 16),

                       // Info banner
            Container(
              padding: EdgeInsets.all(isMobile ? 10 : 12),
              decoration: BoxDecoration(
                color: infoColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: infoColor,
                    size: isMobile ? 16 : 18,
                  ),
                  SizedBox(width: isMobile ? 8 : 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Users without custom limits will be subject to these limits.',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 11 : 12,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '⚡ Enter 0 to make a limit UNLIMITED for that service.',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 11 : 12,
                            fontWeight: FontWeight.w600,
                            color: warningColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: isMobile ? 12 : 16),

            // Per-service editors
            ..._defaultLimits.keys.map((service) {
              return _buildDefaultLimitRow(service, isMobile);
            }),

            SizedBox(height: isMobile ? 14 : 18),

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSavingDefaults ? null : _saveDefaultLimits,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon:
                    _isSavingDefaults
                        ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : HugeIcon(
                          icon: HugeIcons.strokeRoundedSave,
                          color: Colors.white,
                          size: isMobile ? 16 : 18,
                        ),
                label: Text(
                  _isSavingDefaults ? 'Saving Defaults...' : 'Save Defaults',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: isMobile ? 13 : 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultLimitRow(String service, bool isMobile) {
    final label = _serviceLabels[service] ?? service;
    final icon = _serviceIcons[service] ?? Icons.help_outline;
    final currentPerTxn = _defaultLimits[service]?['perTransaction'] ?? 0;
    final currentDaily = _defaultLimits[service]?['dailyCap'] ?? 0;

    final perTxnCtrl = _defaultPerTxnControllers[service]!;
    final dailyCtrl = _defaultDailyControllers[service]!;

    // Populate text only if empty (don't overwrite user typing)
        // Populate text only if empty (don't overwrite user typing)
    // ✅ Show 0 too — 0 = UNLIMITED
    if (perTxnCtrl.text.isEmpty) {
      perTxnCtrl.text = currentPerTxn.toStringAsFixed(0);
    }
    if (dailyCtrl.text.isEmpty) {
      dailyCtrl.text = currentDaily.toStringAsFixed(0);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(isMobile ? 10 : 12),
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
              HugeIcon(
                icon: icon,
                color: primaryColor,
                size: isMobile ? 16 : 18,
              ),
              SizedBox(width: isMobile ? 6 : 8),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 6 : 8),
          Row(
            children: [
              Expanded(
                child: _buildSmallLimitField(
                  controller: perTxnCtrl,
                  label: 'Per Transaction (₦)',
                  isMobile: isMobile,
                ),
              ),
              SizedBox(width: isMobile ? 8 : 10),
              Expanded(
                child: _buildSmallLimitField(
                  controller: dailyCtrl,
                  label: 'Daily Cap (₦)',
                  isMobile: isMobile,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallLimitField({
    required TextEditingController controller,
    required String label,
    required bool isMobile,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: isMobile ? 9 : 10,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: 3),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            style: GoogleFonts.inter(
              fontSize: isMobile ? 12 : 13,
              color: textPrimary,
            ),
            decoration: InputDecoration(
              hintText: '0 = unlimited',
              hintStyle: GoogleFonts.inter(
                fontSize: isMobile ? 10 : 11,
                color: Colors.grey.shade400,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: isMobile ? 8 : 10,
                vertical: isMobile ? 8 : 10,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 8, right: 2),
                child: Text(
                  '₦',
                  style: GoogleFonts.inter(
                    color: textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: isMobile ? 12 : 13,
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveDefaultLimits() async {
    setState(() => _isSavingDefaults = true);

    try {
      final Map<String, dynamic> perTransaction = {};
      final Map<String, dynamic> daily = {};

            for (final service in _defaultLimits.keys) {
        final perTxnText =
            _defaultPerTxnControllers[service]?.text.trim() ?? '';
        final dailyText = _defaultDailyControllers[service]?.text.trim() ?? '';

        final perTxn = double.tryParse(perTxnText);
        final dailyCap = double.tryParse(dailyText);

        // ✅ Send 0 too — it means "unlimited" on the backend.
        // Only skip if the field is empty (null).
        if (perTxn != null && perTxn >= 0) {
          perTransaction[service] = perTxn;
        }
        if (dailyCap != null && dailyCap >= 0) {
          daily[service] = dailyCap;
        }
      }

      if (perTransaction.isEmpty && daily.isEmpty) {
        _showSnackBar('Please enter at least one limit before saving', true);
        return;
      }

      final response = await ApiService.updateDefaultLimits(
        perTransaction: perTransaction,
        daily: daily,
      );

      if (response['success'] == true) {
        _showSnackBar('✅ Default limits updated successfully', false);

        // Refresh from backend to confirm
        await _fetchDefaultLimitsFromBackend();

        // Clear the controllers so they get re-populated with fresh values
        for (final service in _defaultLimits.keys) {
          _defaultPerTxnControllers[service]?.clear();
          _defaultDailyControllers[service]?.clear();
        }

        setState(() {});
      } else {
        _showSnackBar(
          response['message']?.toString() ?? 'Failed to update limits',
          true,
        );
      }
    } catch (e) {
      _log('❌ Error saving default limits: $e');
      _showSnackBar('Error: ${e.toString()}', true);
    } finally {
      if (mounted) {
        setState(() => _isSavingDefaults = false);
      }
    }
  }

  Widget _buildLoadingState() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: isMobile ? 40 : 50,
            height: isMobile ? 40 : 50,
            child: CircularProgressIndicator(
              strokeWidth: isMobile ? 3 : 4,
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading limits...',
            style: GoogleFonts.inter(
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.w500,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }

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
                color: errorColor.withOpacity(0.1),
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
              'Access Denied',
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
            if (_isAdmin)
              SizedBox(
                width: isMobile ? 180 : 200,
                child: ElevatedButton(
                  onPressed: _loadInitialData,
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
}
