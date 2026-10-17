// lib/presentation/screens/admin/admin_fund_wallet_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';
import '../dashboard/dashboard_screen.dart';

class AdminFundWalletPage extends StatefulWidget {
  const AdminFundWalletPage({super.key});

  @override
  State<AdminFundWalletPage> createState() => _AdminFundWalletPageState();
}

class _AdminFundWalletPageState extends State<AdminFundWalletPage>
    with SingleTickerProviderStateMixin {
  // ==================== BRAND COLORS ====================
  static const Color primaryColor = Color(0xFF243889);
  static const Color secondaryColor = Color(0xFF219C7E);
  static const Color successColor = Color(0xFF219C7E);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color textPrimary = Color(0xFF1C2D5A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color backgroundLight = Color(0xFFF8FAFC);

  // ==================== STATE ====================
  List<dynamic> _users = [];
  List<dynamic> _filteredUsers = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  bool _isSpecificAdmin = false;
  bool _isInitialLoad = true;
  static const Duration _cacheDuration = Duration(minutes: 5);

  String? _errorMessage;
  String _searchQuery = '';
  String _selectedFilter = 'all';

  // Selected user for funding
  Map<String, dynamic>? _selectedUser;
  bool _showFundingPanel = false;

  // Stats
  int _totalUsers = 0;
  int _activeUsers = 0;
  double _totalWalletBalance = 0;
  double _totalCommissionBalance = 0;

  // Controllers
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

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
    _amountController.dispose();
    _noteController.dispose();
    _animationController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
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

      // Check cached data
      final cachedData = prefs.getString('cached_fund_wallet_users');
      if (cachedData != null && _isInitialLoad) {
        try {
          final cached = jsonDecode(cachedData);
          final cacheTime = DateTime.parse(cached['timestamp']);
          if (DateTime.now().difference(cacheTime) < _cacheDuration) {
            setState(() {
              _users = cached['users'] ?? [];
              _totalUsers = cached['totalUsers'] ?? 0;
              _activeUsers = cached['activeUsers'] ?? 0;
              _totalWalletBalance = cached['totalWalletBalance'] ?? 0;
              _totalCommissionBalance = cached['totalCommissionBalance'] ?? 0;
              _applyFilters();
              _isLoading = false;
            });
            debugPrint('📦 Loaded fund wallet data from cache');
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
          _isSpecificAdmin = isAdminById;
        });

        if (_isAdmin) {
          await _fetchUsers();
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

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isInitialLoad = false;
    });

    try {
      final fetchedUsers = await ApiService.getAllUsersForAdmin();

      // Calculate stats
      int total = fetchedUsers.length;
      int active = fetchedUsers.where((u) => u['isActive'] == true).length;
      double walletBalance = fetchedUsers.fold<double>(
        0,
        (sum, user) => sum + ((user['walletBalance'] as num?)?.toDouble() ?? 0),
      );
      double commissionBalance = fetchedUsers.fold<double>(
        0,
        (sum, user) =>
            sum + ((user['commissionBalance'] as num?)?.toDouble() ?? 0),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'cached_fund_wallet_users',
        jsonEncode({
          'users': fetchedUsers,
          'totalUsers': total,
          'activeUsers': active,
          'totalWalletBalance': walletBalance,
          'totalCommissionBalance': commissionBalance,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      setState(() {
        _users = fetchedUsers;
        _totalUsers = total;
        _activeUsers = active;
        _totalWalletBalance = walletBalance;
        _totalCommissionBalance = commissionBalance;
        _applyFilters();
      });
    } catch (e) {
      debugPrint("❌ Error fetching users: $e");
      if (e.toString().contains('Admin access required')) {
        setState(() {
          _errorMessage = "You don't have permission to access admin features.";
          _isAdmin = false;
        });
      } else {
        setState(() {
          _errorMessage = "Failed to load users: ${e.toString()}";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilters() {
    List<dynamic> filtered = List.from(_users);

    // Filter by status
    if (_selectedFilter != 'all') {
      filtered =
          filtered.where((user) {
            final isActive = user['isActive'] ?? true;
            final walletBalance =
                (user['walletBalance'] as num?)?.toDouble() ?? 0;
            final isUserAdmin = user['isAdmin'] == true;

            switch (_selectedFilter) {
              case 'active':
                return isActive;
              case 'inactive':
                return !isActive;
              case 'admin':
                return isUserAdmin;
              case 'lowBalance':
                return walletBalance < 1000;
              default:
                return true;
            }
          }).toList();
    }

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered =
          filtered.where((user) {
            final name = user['fullName']?.toString().toLowerCase() ?? '';
            final email = user['email']?.toString().toLowerCase() ?? '';
            final phone = user['phone']?.toString() ?? '';
            return name.contains(query) ||
                email.contains(query) ||
                phone.contains(query);
          }).toList();
    }

    setState(() {
      _filteredUsers = filtered;
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

  String _formatLargeNumber(double value) {
    if (value >= 1000000) {
      return '₦${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '₦${(value / 1000).toStringAsFixed(1)}K';
    }
    return '₦${value.toStringAsFixed(2)}';
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
                  'Admin / Fund Wallet',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: isMobile ? 12 : 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (_isSpecificAdmin)
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
                    'SUPER ADMIN',
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
                  Icons.account_balance_wallet_rounded,
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
                      'Fund Wallet',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: isMobile ? 20 : 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: isMobile ? 4 : 6),
                    Text(
                      '${_filteredUsers.length} of $_totalUsers users • $_activeUsers active',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: isMobile ? 12 : 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _fetchUsers,
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
                              ? 'Search users...'
                              : 'Search by name, email or phone...',
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
        horizontal: isMobile ? 12 : 16,
        vertical: isMobile ? 8 : 12,
      ),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100, width: 1),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isSmall = constraints.maxWidth < 400;
          final stats = [
            {
              'value': _totalUsers.toString(),
              'label': 'Users',
              'icon': HugeIcons.strokeRoundedUser,
              'color': primaryColor,
            },
            {
              'value': _activeUsers.toString(),
              'label': 'Active',
              'icon': HugeIcons.strokeRoundedCheckmarkCircle01,
              'color': successColor,
            },
            {
              'value': _formatLargeNumber(_totalWalletBalance),
              'label': 'Total Wallet',
              'icon': HugeIcons.strokeRoundedWallet01,
              'color': secondaryColor,
            },
            {
              'value': _formatLargeNumber(_totalCommissionBalance),
              'label': 'Total Commission',
              'icon': HugeIcons.strokeRoundedMoney02,
              'color': Colors.amber.shade700,
            },
          ];

          if (isSmall) {
            return Wrap(
              spacing: 4,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children:
                  stats.map((stat) {
                    return SizedBox(
                      width: constraints.maxWidth / 2 - 12,
                      child: _buildStatItem(
                        value: stat['value'] as String,
                        label: stat['label'] as String,
                        icon: stat['icon'] as dynamic,
                        color: stat['color'] as Color,
                        isMobile: true,
                      ),
                    );
                  }).toList(),
            );
          }

          return Row(
            children:
                stats.map((stat) {
                  return Expanded(
                    child: _buildStatItem(
                      value: stat['value'] as String,
                      label: stat['label'] as String,
                      icon: stat['icon'] as dynamic,
                      color: stat['color'] as Color,
                      isMobile: false,
                    ),
                  );
                }).toList(),
          );
        },
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
        SizedBox(height: isMobile ? 2 : 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: isMobile ? 14 : 16,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: isMobile ? 1 : 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: isMobile ? 9 : 11,
            color: textSecondary,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // ==================== FILTER CHIPS ====================

  Widget _buildFilterChips() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    final filters = [
      {'label': 'All', 'value': 'all'},
      {'label': 'Active', 'value': 'active'},
      {'label': 'Inactive', 'value': 'inactive'},
      {'label': 'Admins', 'value': 'admin'},
      {'label': 'Low Balance', 'value': 'lowBalance'},
    ];

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
      height: isMobile ? 48 : 40,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children:
              filters.map((filter) {
                return Padding(
                  padding: EdgeInsets.only(right: isMobile ? 6 : 8),
                  child: _buildFilterChip(
                    label: filter['label'] as String,
                    value: filter['value'] as String,
                    isMobile: isMobile,
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required String value,
    required bool isMobile,
  }) {
    final isSelected = _selectedFilter == value;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = value;
          _applyFilters();
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 16,
          vertical: isMobile ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primaryColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isSelected ? Colors.white : textSecondary,
            fontSize: isMobile ? 12 : 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ==================== USER LIST ====================

  Widget _buildUserList() {
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

    if (_filteredUsers.isEmpty) {
      return SliverFillRemaining(child: _buildEmptyState());
    }

    return SliverPadding(
      padding: EdgeInsets.only(
        left: isMobile ? 16 : 24,
        right: isMobile ? 16 : 24,
        bottom: 24,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildUserCard(_filteredUsers[index]),
          childCount: _filteredUsers.length,
        ),
      ),
    );
  }

  Widget _buildShimmerCard(bool isMobile) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        height: isMobile ? 140 : 160,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isActive = user['isActive'] ?? true;
    final walletBalance = (user['walletBalance'] as num?)?.toDouble() ?? 0;
    final commissionBalance =
        (user['commissionBalance'] as num?)?.toDouble() ?? 0;
    final isUserAdmin = user['isAdmin'] == true;
    final userName = user['fullName']?.toString() ?? 'Unknown User';
    final userEmail = user['email']?.toString() ?? 'No Email';
    final userPhone = user['phone']?.toString() ?? 'N/A';
    final createdAt =
        user['createdAt'] != null
            ? DateTime.tryParse(user['createdAt'].toString())
            : null;

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
          color: Colors.white,
          borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
            onTap: () => _showFundDialog(user),
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 14 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Avatar
                      Container(
                        width: isMobile ? 44 : 52,
                        height: isMobile ? 44 : 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              primaryColor,
                              primaryColor.withValues(alpha: 0.7),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            userName.isNotEmpty
                                ? userName[0].toUpperCase()
                                : '?',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: isMobile ? 18 : 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: isMobile ? 12 : 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    userName,
                                    style: GoogleFonts.inter(
                                      fontSize: isMobile ? 15 : 17,
                                      fontWeight: FontWeight.w700,
                                      color: textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isUserAdmin)
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isMobile ? 6 : 8,
                                      vertical: isMobile ? 2 : 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: secondaryColor.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.shield_rounded,
                                          color: secondaryColor,
                                          size: isMobile ? 12 : 14,
                                        ),
                                        SizedBox(width: 2),
                                        Text(
                                          'Admin',
                                          style: GoogleFonts.inter(
                                            color: secondaryColor,
                                            fontSize: isMobile ? 8 : 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            SizedBox(height: 2),
                            Text(
                              userEmail,
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 12 : 13,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              children: [
                                Icon(
                                  Icons.phone_rounded,
                                  size: isMobile ? 12 : 14,
                                  color: Colors.grey.shade400,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  userPhone,
                                  style: GoogleFonts.inter(
                                    fontSize: isMobile ? 11 : 12,
                                    color: Colors.grey.shade500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const Spacer(),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isMobile ? 6 : 8,
                                    vertical: isMobile ? 2 : 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        isActive
                                            ? successColor.withValues(
                                              alpha: 0.08,
                                            )
                                            : errorColor.withValues(
                                              alpha: 0.08,
                                            ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    isActive ? 'Active' : 'Inactive',
                                    style: GoogleFonts.inter(
                                      fontSize: isMobile ? 9 : 10,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          isActive ? successColor : errorColor,
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

                  SizedBox(height: isMobile ? 12 : 14),

                  // Balance Row
                  Container(
                    padding: EdgeInsets.all(isMobile ? 10 : 12),
                    decoration: BoxDecoration(
                      color: backgroundLight,
                      borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'Wallet',
                                style: GoogleFonts.inter(
                                  fontSize: isMobile ? 9 : 10,
                                  color: textSecondary,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '₦${walletBalance.toStringAsFixed(2)}',
                                style: GoogleFonts.inter(
                                  fontSize: isMobile ? 13 : 15,
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: isMobile ? 30 : 36,
                          color: Colors.grey.shade200,
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'Commission',
                                style: GoogleFonts.inter(
                                  fontSize: isMobile ? 9 : 10,
                                  color: textSecondary,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '₦${commissionBalance.toStringAsFixed(2)}',
                                style: GoogleFonts.inter(
                                  fontSize: isMobile ? 13 : 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (createdAt != null) ...[
                          Container(
                            width: 1,
                            height: isMobile ? 30 : 36,
                            color: Colors.grey.shade200,
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  'Joined',
                                  style: GoogleFonts.inter(
                                    fontSize: isMobile ? 9 : 10,
                                    color: textSecondary,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  _formatDate(createdAt),
                                  style: GoogleFonts.inter(
                                    fontSize: isMobile ? 11 : 12,
                                    fontWeight: FontWeight.w500,
                                    color: textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  SizedBox(height: isMobile ? 10 : 12),

                  // Action Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showFundDialog(user),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: secondaryColor,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: isMobile ? 10 : 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedMoneyAdd01,
                        color: Colors.white,
                        size: isMobile ? 18 : 20,
                      ),
                      label: Text(
                        'Fund Wallet',
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
          ),
        ),
      ),
    );
  }

  // ==================== FUNDING PANEL ====================

  void _showFundDialog(Map<String, dynamic> user) {
    setState(() {
      _selectedUser = user;
      _showFundingPanel = true;
    });
    _amountController.clear();
    _noteController.clear();
  }

  void _hideFundDialog() {
    setState(() {
      _showFundingPanel = false;
      _selectedUser = null;
    });
    _amountController.clear();
    _noteController.clear();
  }

  Widget _buildFundingPanel() {
    if (_selectedUser == null || !_showFundingPanel) return const SizedBox();

    final isMobile = MediaQuery.of(context).size.width < 600;
    final user = _selectedUser!;
    final currentBalance = (user['walletBalance'] as num?)?.toDouble() ?? 0;
    final userName = user['fullName']?.toString() ?? 'Unknown User';
    final userEmail = user['email']?.toString() ?? 'No Email';

    return Positioned.fill(
      child: GestureDetector(
        onTap: _hideFundDialog,
        child: Container(
          color: Colors.black.withValues(alpha: 0.4),
          child: DraggableScrollableSheet(
            initialChildSize: isMobile ? 0.85 : 0.7,
            minChildSize: isMobile ? 0.3 : 0.4,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: EdgeInsets.all(isMobile ? 16 : 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drag handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Header
                      Row(
                        children: [
                          Container(
                            width: isMobile ? 44 : 52,
                            height: isMobile ? 44 : 52,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  primaryColor,
                                  primaryColor.withValues(alpha: 0.7),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                userName.isNotEmpty
                                    ? userName[0].toUpperCase()
                                    : '?',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: isMobile ? 18 : 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: isMobile ? 12 : 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  userName,
                                  style: GoogleFonts.inter(
                                    fontSize: isMobile ? 16 : 18,
                                    fontWeight: FontWeight.bold,
                                    color: textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  userEmail,
                                  style: GoogleFonts.inter(
                                    fontSize: isMobile ? 12 : 13,
                                    color: textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _hideFundDialog,
                            icon: Icon(
                              Icons.close_rounded,
                              color: textSecondary,
                              size: isMobile ? 22 : 24,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),

                      SizedBox(height: isMobile ? 16 : 20),

                      // Current Balance
                      Container(
                        padding: EdgeInsets.all(isMobile ? 12 : 16),
                        decoration: BoxDecoration(
                          color: successColor.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: successColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: successColor.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: HugeIcon(
                                icon: HugeIcons.strokeRoundedWallet01,
                                color: successColor,
                                size: isMobile ? 20 : 24,
                              ),
                            ),
                            SizedBox(width: isMobile ? 10 : 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Current Balance',
                                    style: GoogleFonts.inter(
                                      fontSize: isMobile ? 11 : 12,
                                      color: textSecondary,
                                    ),
                                  ),
                                  Text(
                                    '₦${currentBalance.toStringAsFixed(2)}',
                                    style: GoogleFonts.inter(
                                      fontSize: isMobile ? 22 : 28,
                                      fontWeight: FontWeight.bold,
                                      color: successColor,
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

                      SizedBox(height: isMobile ? 20 : 24),

                      // Funding Amount
                      Text(
                        'Funding Amount',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 15 : 16,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      SizedBox(height: isMobile ? 8 : 10),
                      TextField(
                        controller: _amountController,
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d{0,2}'),
                          ),
                        ],
                        decoration: InputDecoration(
                          hintText: 'Enter amount (e.g., 1000.00)',
                          hintStyle: GoogleFonts.inter(
                            fontSize: isMobile ? 13 : 14,
                            color: Colors.grey.shade500,
                          ),
                          prefixIcon: Padding(
                            padding: EdgeInsets.all(isMobile ? 12 : 16),
                            child: Text(
                              '₦',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 16 : 18,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                              ),
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: primaryColor,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 12 : 16,
                            vertical: isMobile ? 12 : 16,
                          ),
                        ),
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 16 : 18,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),

                      SizedBox(height: isMobile ? 16 : 20),

                      // Quick Amounts
                      Text(
                        'Quick Amounts',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 14 : 15,
                          fontWeight: FontWeight.w600,
                          color: textSecondary,
                        ),
                      ),
                      SizedBox(height: isMobile ? 8 : 10),
                      Wrap(
                        spacing: isMobile ? 6 : 8,
                        runSpacing: isMobile ? 6 : 8,
                        children:
                            [500, 1000, 2000, 5000, 10000, 20000]
                                .map(
                                  (amount) => ActionChip(
                                    label: Text(
                                      '₦$amount',
                                      style: GoogleFonts.inter(
                                        fontSize: isMobile ? 12 : 13,
                                        color: primaryColor,
                                      ),
                                    ),
                                    onPressed: () {
                                      _amountController.text =
                                          amount.toString();
                                    },
                                    backgroundColor: primaryColor.withValues(
                                      alpha: 0.08,
                                    ),
                                    side: BorderSide(
                                      color: primaryColor.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),

                      SizedBox(height: isMobile ? 16 : 20),

                      // Note (Optional)
                      Text(
                        'Note (Optional)',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 15 : 16,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      SizedBox(height: isMobile ? 8 : 10),
                      TextField(
                        controller: _noteController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Add a note for this transaction...',
                          hintStyle: GoogleFonts.inter(
                            fontSize: isMobile ? 13 : 14,
                            color: Colors.grey.shade500,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: primaryColor,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 12 : 16,
                            vertical: isMobile ? 10 : 12,
                          ),
                        ),
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 13 : 14,
                          color: textPrimary,
                        ),
                      ),

                      SizedBox(height: isMobile ? 24 : 32),

                      // Confirm Button
                      SizedBox(
                        width: double.infinity,
                        height: isMobile ? 48 : 54,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _fundUser,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: secondaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child:
                              _isLoading
                                  ? SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                  : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      HugeIcon(
                                        icon:
                                            HugeIcons
                                                .strokeRoundedCheckmarkCircle01,
                                        color: Colors.white,
                                        size: isMobile ? 18 : 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Confirm Funding',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          fontSize: isMobile ? 15 : 16,
                                        ),
                                      ),
                                    ],
                                  ),
                        ),
                      ),

                      SizedBox(height: MediaQuery.of(context).padding.bottom),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _fundUser() async {
    if (_selectedUser == null) return;

    final amountStr = _amountController.text.trim();
    if (amountStr.isEmpty) {
      _showSnackBar('Please enter an amount', true);
      return;
    }

    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      _showSnackBar('Please enter a valid positive amount', true);
      return;
    }

    final userId = _selectedUser!['_id'].toString();
    final userName = _selectedUser!['fullName']?.toString() ?? 'User';

    // Show confirmation dialog
    final confirmed = await _showConfirmDialog(
      title: 'Confirm Funding',
      message:
          'You are about to fund $userName\'s wallet with ₦${amount.toStringAsFixed(2)}.',
      confirmText: 'Fund',
      confirmColor: secondaryColor,
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final response = await ApiService.fundWallet(
        userId: userId,
        amount: amount,
        note: _noteController.text.isNotEmpty ? _noteController.text : null,
      );

      if (response['success'] == true) {
        _showSnackBar(
          '✅ Successfully funded ₦${amount.toStringAsFixed(2)} to $userName',
          false,
        );
        _hideFundDialog();
        await _fetchUsers();
      } else {
        throw Exception(response['message'] ?? 'Failed to fund wallet');
      }
    } catch (e) {
      _showSnackBar('Error: ${e.toString()}', true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmText,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              title,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            content: Text(
              message,
              style: GoogleFonts.inter(color: Colors.grey.shade700),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    color: textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  confirmText,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
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
                  onPressed: _fetchUsers,
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
                color: primaryColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedUser,
                color: primaryColor,
                size: isMobile ? 40 : 50,
              ),
            ),
            SizedBox(height: isMobile ? 16 : 24),
            Text(
              'No Users Found',
              style: GoogleFonts.poppins(
                fontSize: isMobile ? 20 : 24,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            SizedBox(height: isMobile ? 8 : 12),
            Text(
              _searchQuery.isNotEmpty || _selectedFilter != 'all'
                  ? 'Try adjusting your search or filters'
                  : 'No users have been registered yet',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 14 : 16,
                color: textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (_searchQuery.isNotEmpty || _selectedFilter != 'all') ...[
              SizedBox(height: isMobile ? 20 : 24),
              ElevatedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _selectedFilter = 'all';
                    _applyFilters();
                  });
                },
                icon: Icon(Icons.clear_all_rounded, size: isMobile ? 18 : 20),
                label: Text(
                  'Clear Filters',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
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
          (item) => item.title == "Fund Wallet",
          orElse: () => _drawerItems.first,
        ),
        onItemSelected: _onDrawerItemSelected,
        isAdmin: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              key: _refreshIndicatorKey,
              onRefresh: _fetchUsers,
              color: primaryColor,
              backgroundColor: Colors.white,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        _buildAdminHeader(),
                        _buildFilterChips(),
                        _buildStatsCard(),
                      ],
                    ),
                  ),
                  _buildUserList(),
                  SliverToBoxAdapter(
                    child: SizedBox(height: isMobile ? 80 : 24),
                  ),
                ],
              ),
            ),
            if (_showFundingPanel) _buildFundingPanel(),
          ],
        ),
      ),
    );
  }
}
