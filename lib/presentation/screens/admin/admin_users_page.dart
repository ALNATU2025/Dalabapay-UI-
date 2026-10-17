// lib/presentation/screens/admin/admin_users_page.dart

import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';
import '../dashboard/dashboard_screen.dart';
import 'admin_user_transactions_page.dart';
import 'admin_edit_user_page.dart';
import 'admin_notifications_page.dart';
import 'admin_user_history_page.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage>
    with SingleTickerProviderStateMixin {
  // ==================== BRAND COLORS ====================
  static const Color primaryColor = Color(0xFF102C68);
  static const Color secondaryColor = Color(0xFF168566);
  static const Color successColor = Color(0xFF168566);
  static const Color warningColor = Color(0xFFA76B1D);
  static const Color errorColor = Color(0xFFC0392B);
  static const Color infoColor = Color(0xFF173D88);
  static const Color textPrimary = Color(0xFF14263D);
  static const Color textSecondary = Color(0xFF728078);
  static const Color backgroundLight = Color(0xFFF8F9F5);
  static const String _superAdminId = "690088325ca99bed6ab8d4a5";

  // ==================== STATE VARIABLES ====================

  List<dynamic> users = [];
  List<dynamic> filteredUsers = [];
  List<dynamic> todayUsers = [];
  bool isLoading = true;
  bool _isAdmin = false;
  bool _isSuperAdmin = false;
  String? errorMessage;
  final TextEditingController searchController = TextEditingController();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  String _searchQuery = '';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Timer? _searchDebounce;
  final int _selectedIndex = 0;
  String _currentUserId = '';
  String _currentUserRole = 'user';

  // ✅ NEW: Auto-refresh timer for user list + bell badge
  Timer? _autoRefreshTimer;

  // Helper method to check if user is super admin
  bool _isUserSuperAdmin({
    String? userId,
    String? userEmail,
    Map<String, dynamic>? userData,
  }) {
    // Check by ID
    if (userId != null && _superAdminIds.contains(userId)) {
      return true;
    }

    // Check by email
    if (userEmail != null) {
      final emailLower = userEmail.toLowerCase();
      if (_superAdminEmails.contains(emailLower)) {
        return true;
      }
    }

    // Check from userData map
    if (userData != null) {
      final dataId = userData['_id']?.toString();
      final dataEmail = userData['email']?.toString().toLowerCase();

      if (dataId != null && _superAdminIds.contains(dataId)) {
        return true;
      }
      if (dataEmail != null && _superAdminEmails.contains(dataEmail)) {
        return true;
      }
    }

    return false;
  }

  // ==================== SUPER ADMIN IDENTIFIERS ====================
  // Multiple super admin IDs - Both Adam and Alusine are super admins
  static const List<String> _superAdminIds = [
    "690088325ca99bed6ab8d4a5", // Adam (adam@gmail.com) - Original super admin
    "6917abd88d1943c6ecebfc5f", // Alusine Jalloh (dalabapays@gmail.com) - Super admin
  ];

  // ✅ Also add email-based detection for extra safety
  static const List<String> _superAdminEmails = [
    "adam@gmail.com", // Adam
    "dalabapays@gmail.com", // Alusine Jalloh
  ];

  // ==================== STATISTICS ====================
  Map<String, dynamic> statistics = {
    'daily': 0,
    'weekly': 0,
    'monthly': 0,
    'yearly': 0,
    'totalUsers': 0,
    'activeUsers': 0,
    'adminUsers': 0,
  };
  bool isLoadingStats = false;

  // Filter options
  String _selectedFilter = 'All Users';

  // Roles list (from RBAC)
  List<Map<String, dynamic>> _rolesList = [];

  // ✅ NEW: Approval system toggle
  bool _approvalSystemEnabled = true;
  bool _isLoadingApprovalSetting = true;
  bool _isSavingApprovalSetting = false;

  @override
  void initState() {
    super.initState();
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

    _loadInitialData();

    // ✅ Auto-refresh user list + bell badge every 15s
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _isAdmin && !isLoading) {
        fetchUsers();
        setState(() {}); // refreshes FutureBuilder<int> for the badge
      }
    });

    searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          _searchQuery = searchController.text;
          _filterUsers(searchController.text);
        }
      });
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    _animationController.dispose();
    _searchDebounce?.cancel();
    _autoRefreshTimer?.cancel(); // ✅ NEW
    super.dispose();
  }

  // ==================== DATA LOADING ====================

  Future<void> _loadInitialData() async {
    setState(() {
      isLoading = true;
      isLoadingStats = true;
      errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user');

      if (userDataString != null) {
        final userData = jsonDecode(userDataString);
        debugPrint("User Data from SharedPreferences: $userData");

        // Get current user's ID and email
        final currentUserId = userData['_id']?.toString() ?? '';
        final currentUserEmail = userData['email']?.toString() ?? '';

        // ✅ Check if current user is in the super admin list
        final bool isSuperAdminByIdOrEmail = _isUserSuperAdmin(
          userId: currentUserId,
          userEmail: currentUserEmail,
          userData: userData,
        );

        debugPrint('👤 Current User ID: $currentUserId');
        debugPrint('👤 Current User Email: $currentUserEmail');
        debugPrint('⭐ Is Super Admin (by ID/Email): $isSuperAdminByIdOrEmail');

        // Get fresh user role from RBAC API
        try {
          final roleResult = await ApiService.getUserRole();
          debugPrint('🔍 Role API Response: $roleResult');

          if (roleResult['success'] == true) {
            final data = roleResult['data'];
            final userRole = data?['role'] ?? 'user';

            // ✅ Check multiple conditions for super admin
            final bool isSuperAdmin =
                data?['isSuperAdmin'] == true ||
                userRole == 'super_admin' ||
                userRole == 'superadmin' ||
                isSuperAdminByIdOrEmail;

            final bool isAdmin =
                data?['isAdmin'] == true ||
                userRole == 'admin' ||
                userRole == 'super_admin' ||
                userRole == 'superadmin' ||
                isSuperAdmin;

            debugPrint('👤 User Role from API: $userRole');
            debugPrint('⭐ Final Super Admin: $isSuperAdmin');
            debugPrint('🔑 Final Admin: $isAdmin');

            setState(() {
              _currentUserId = currentUserId;
              _currentUserRole = isSuperAdmin ? 'super_admin' : userRole;
              _isAdmin = isAdmin;
              _isSuperAdmin = isSuperAdmin;
            });

            // Update SharedPreferences
            await prefs.setString(
              'role',
              isSuperAdmin ? 'super_admin' : userRole,
            );
            await prefs.setBool('isAdmin', isAdmin);
            await prefs.setBool('isSuperAdmin', isSuperAdmin);
          } else {
            // Fallback to stored data
            final bool isSuperAdminFallback = _isUserSuperAdmin(
              userId: currentUserId,
              userEmail: currentUserEmail,
            );

            setState(() {
              _currentUserId = currentUserId;
              _isAdmin = userData['isAdmin'] == true || isSuperAdminFallback;
              _isSuperAdmin = isSuperAdminFallback;
              _currentUserRole =
                  isSuperAdminFallback
                      ? 'super_admin'
                      : (userData['isAdmin'] == true ? 'admin' : 'user');
            });
          }
        } catch (e) {
          debugPrint('⚠️ Could not fetch role from backend: $e');
          // Fallback
          final bool isSuperAdminFallback = _isUserSuperAdmin(
            userId: currentUserId,
            userEmail: currentUserEmail,
          );

          setState(() {
            _currentUserId = currentUserId;
            _isAdmin = userData['isAdmin'] == true || isSuperAdminFallback;
            _isSuperAdmin = isSuperAdminFallback;
            _currentUserRole =
                isSuperAdminFallback
                    ? 'super_admin'
                    : (userData['isAdmin'] == true ? 'admin' : 'user');
          });
        }

        if (_isAdmin) {
          await _loadRolesAndPermissions();
          await Future.wait([
            fetchUsers(),
            fetchStatistics(),
            _loadApprovalSetting(), // ✅ NEW: load toggle state
          ]);
          _animationController.forward();
        } else {
          setState(() {
            isLoading = false;
            isLoadingStats = false;
            errorMessage =
                "You don't have permission to access this page. Contact Super Admin.";
          });
        }
      } else {
        setState(() {
          _isAdmin = false;
          _isSuperAdmin = false;
          isLoading = false;
          isLoadingStats = false;
          errorMessage = "User data not found. Please log in again.";
        });
      }
    } catch (e) {
      debugPrint("Error checking admin status: $e");
      setState(() {
        _isAdmin = false;
        _isSuperAdmin = false;
        isLoading = false;
        isLoadingStats = false;
        errorMessage = "Error checking permissions: ${e.toString()}";
      });
    }
  }

  void _loadCurrentUserFromCache(Map<String, dynamic> userData) {
    final String? userId = userData['_id']?.toString();
    final bool isSuperAdmin = userId == _superAdminId;
    final bool isAdmin = userData['isAdmin'] == true || isSuperAdmin;

    debugPrint('⭐ Fallback - Is Super Admin: $isSuperAdmin');

    setState(() {
      _currentUserId = userId ?? '';
      _isAdmin = isAdmin;
      _isSuperAdmin = isSuperAdmin;
      _currentUserRole =
          isSuperAdmin ? 'super_admin' : (isAdmin ? 'admin' : 'user');
    });
  }

  Future<void> _loadApprovalSetting() async {
    setState(() => _isLoadingApprovalSetting = true);
    try {
      final enabled = await ApiService.getApprovalSetting();
      if (mounted) {
        setState(() {
          _approvalSystemEnabled = enabled;
          _isLoadingApprovalSetting = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Failed to load approval setting: $e');
      if (mounted) {
        setState(() => _isLoadingApprovalSetting = false);
      }
    }
  }

  Future<void> _toggleApprovalSystem(bool newValue) async {
    final confirm = await _showConfirmDialog(
      title: newValue ? 'Enable Approval System?' : 'Disable Approval System?',
      message:
          newValue
              ? 'New users will start as PENDING and require admin approval before they can transact.'
              : 'New users will be AUTO-APPROVED immediately after registration. No approval needed.',
      confirmText: newValue ? 'Enable' : 'Disable',
      confirmColor: newValue ? successColor : warningColor,
    );
    if (confirm != true) return;

    setState(() => _isSavingApprovalSetting = true);
    try {
      final response = await ApiService.updateApprovalSetting(newValue);
      if (mounted) {
        if (response['success'] == true) {
          setState(() {
            _approvalSystemEnabled = newValue;
            _isSavingApprovalSetting = false;
          });
          _showSnackBar(
            newValue
                ? '✅ Approval system enabled — new users will be pending.'
                : '⚠️ Approval system disabled — new users auto-approved.',
            false,
          );
        } else {
          setState(() => _isSavingApprovalSetting = false);
          _showSnackBar(
            response['message'] ?? 'Failed to update approval setting',
            true,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingApprovalSetting = false);
        _showSnackBar('Error: ${e.toString()}', true);
      }
    }
  }

  Future<void> _loadRolesAndPermissions() async {
    try {
      try {
        final response = await ApiService.getAllRoles();
        if (response['success'] == true) {
          final roles = response['data']?['roles'] ?? [];
          _rolesList = List<Map<String, dynamic>>.from(roles);
          debugPrint('✅ Loaded ${_rolesList.length} roles from backend');
          return;
        }
      } catch (e) {
        debugPrint('⚠️ Could not fetch roles from backend: $e');
      }

      // Fallback roles
      _rolesList = [
        {
          'role': 'super_admin',
          'label': 'Super Administrator',
          'level': 5,
          'color': warningColor.value,
        },
        {
          'role': 'admin',
          'label': 'Administrator',
          'level': 4,
          'color': primaryColor.value,
        },
        {
          'role': 'finance',
          'label': 'Finance Officer',
          'level': 3,
          'color': successColor.value,
        },
        {
          'role': 'support',
          'label': 'Support Agent',
          'level': 2,
          'color': infoColor.value,
        },
        {
          'role': 'user',
          'label': 'User',
          'level': 0,
          'color': Colors.grey.value,
        },
      ];
      debugPrint('✅ Loaded ${_rolesList.length} roles (fallback)');
    } catch (e) {
      debugPrint('❌ Error loading roles: $e');
      _rolesList = [
        {
          'role': 'user',
          'label': 'User',
          'level': 0,
          'color': Colors.grey.value,
        },
        {
          'role': 'admin',
          'label': 'Admin',
          'level': 4,
          'color': primaryColor.value,
        },
        {
          'role': 'super_admin',
          'label': 'Super Admin',
          'level': 5,
          'color': warningColor.value,
        },
      ];
    }
  }

  Future<void> fetchUsers() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final fetchedUsersList = await ApiService.getAllUsersForAdmin();

      // ✅ SAFETY: Ensure approvalStatus is always present as a String
      // so the "Pending" filter and approval buttons always work.
      final normalizedUsers =
          fetchedUsersList.map((u) {
            if (u is Map<String, dynamic>) {
              final map = Map<String, dynamic>.from(u);
              final rawStatus = map['approvalStatus']?.toString().toLowerCase();
              if (rawStatus == null || rawStatus.isEmpty) {
                // Existing user without status → grandfathered as approved
                map['approvalStatus'] = 'approved';
              } else {
                map['approvalStatus'] = rawStatus;
              }
              return map;
            }
            return u;
          }).toList();

      setState(() {
        users = normalizedUsers;
        _filterUsers(_searchQuery);
        todayUsers = _filterTodayUsers(users);
      });
    } catch (e) {
      debugPrint("❌ Error fetching users: $e");
      if (e.toString().contains('Admin access required')) {
        setState(() {
          errorMessage =
              "You don't have permission to access admin features. Contact Super Admin.";
          _isAdmin = false;
          _isSuperAdmin = false;
        });
      } else {
        setState(() {
          errorMessage = "Failed to fetch users: ${e.toString()}";
        });
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> fetchStatistics() async {
    setState(() => isLoadingStats = true);
    try {
      final statsData = await ApiService.getUserStatistics();
      setState(() {
        statistics = {
          'daily': statsData['statistics']?['daily'] ?? 0,
          'weekly': statsData['statistics']?['weekly'] ?? 0,
          'monthly': statsData['statistics']?['monthly'] ?? 0,
          'yearly': statsData['statistics']?['yearly'] ?? 0,
          'totalUsers': statsData['totalUsers'] ?? 0,
          'activeUsers': statsData['activeUsers'] ?? 0,
          'adminUsers': statsData['adminUsers'] ?? 0,
        };
        // ✅ Only update todayUsers — DO NOT overwrite `users` here.
        // `fetchUsers()` is the single source of truth for the main list.
        if (statsData['todayUsers'] != null) {
          todayUsers = statsData['todayUsers'];
        }
      });
    } catch (e) {
      debugPrint("❌ Error fetching statistics: $e");
    } finally {
      setState(() => isLoadingStats = false);
    }
  }

  List<dynamic> _filterTodayUsers(List<dynamic> allUsers) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return allUsers.where((user) {
      if (user is Map<String, dynamic>) {
        final createdAt = user['createdAt'];
        if (createdAt != null) {
          try {
            final date = DateTime.parse(createdAt.toString());
            return date.isAfter(today) || date.isAtSameMomentAs(today);
          } catch (e) {
            return false;
          }
        }
      }
      return false;
    }).toList();
  }

  void _filterUsers(String query) {
    final lowerCaseQuery = query.toLowerCase();
    List<dynamic> sourceList = [];

    switch (_selectedFilter) {
      case 'Pending':
        sourceList =
            users.where((u) {
              final status =
                  (u['approvalStatus'] ?? 'approved').toString().toLowerCase();
              return status == 'pending';
            }).toList();
        break;
      case 'Today':
        sourceList = todayUsers;
        break;
      case 'Weekly':
        sourceList = _filterWeeklyUsers(users);
        break;
      case 'Monthly':
        sourceList = _filterMonthlyUsers(users);
        break;
      case 'Yearly':
        sourceList = _filterYearlyUsers(users);
        break;
      default:
        sourceList = users;
        break;
    }

    final filtered =
        sourceList.where((user) {
          if (user is Map<String, dynamic>) {
            final name = user['fullName']?.toLowerCase() ?? '';
            final email = user['email']?.toLowerCase() ?? '';
            final userId = user['_id']?.toLowerCase() ?? '';
            final phone = user['phone']?.toLowerCase() ?? '';
            return name.contains(lowerCaseQuery) ||
                email.contains(lowerCaseQuery) ||
                userId.contains(lowerCaseQuery) ||
                phone.contains(lowerCaseQuery);
          }
          return false;
        }).toList();

    setState(() => filteredUsers = filtered);
  }

  List<dynamic> _filterWeeklyUsers(List<dynamic> allUsers) {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    return allUsers.where((user) {
      if (user is Map<String, dynamic>) {
        final createdAt = user['createdAt'];
        if (createdAt != null) {
          try {
            final date = DateTime.parse(createdAt.toString());
            return date.isAfter(weekAgo) || date.isAtSameMomentAs(weekAgo);
          } catch (e) {
            return false;
          }
        }
      }
      return false;
    }).toList();
  }

  List<dynamic> _filterMonthlyUsers(List<dynamic> allUsers) {
    final now = DateTime.now();
    final monthAgo = DateTime(now.year, now.month - 1, now.day);
    return allUsers.where((user) {
      if (user is Map<String, dynamic>) {
        final createdAt = user['createdAt'];
        if (createdAt != null) {
          try {
            final date = DateTime.parse(createdAt.toString());
            return date.isAfter(monthAgo) || date.isAtSameMomentAs(monthAgo);
          } catch (e) {
            return false;
          }
        }
      }
      return false;
    }).toList();
  }

  List<dynamic> _filterYearlyUsers(List<dynamic> allUsers) {
    final now = DateTime.now();
    final yearAgo = DateTime(now.year - 1, now.month, now.day);
    return allUsers.where((user) {
      if (user is Map<String, dynamic>) {
        final createdAt = user['createdAt'];
        if (createdAt != null) {
          try {
            final date = DateTime.parse(createdAt.toString());
            return date.isAfter(yearAgo) || date.isAtSameMomentAs(yearAgo);
          } catch (e) {
            return false;
          }
        }
      }
      return false;
    }).toList();
  }

  String _getRoleLabel(String role) {
    for (var r in _rolesList) {
      if (r['role'] == role) {
        return r['label'] ?? role.toUpperCase();
      }
    }
    switch (role) {
      case 'super_admin':
        return 'Super Administrator ⭐';
      case 'admin':
        return 'Administrator';
      case 'finance':
        return 'Finance Officer';
      case 'support':
        return 'Support Agent';
      default:
        return 'User';
    }
  }

  Color _getRoleColor(String role) {
    for (var r in _rolesList) {
      if (r['role'] == role) {
        dynamic roleColor = r['color'];
        if (roleColor is int) {
          return Color(roleColor);
        } else if (roleColor is Color) {
          return roleColor;
        }
      }
    }
    switch (role) {
      case 'super_admin':
        return warningColor;
      case 'admin':
        return primaryColor;
      case 'finance':
        return successColor;
      case 'support':
        return infoColor;
      default:
        return Colors.grey;
    }
  }

  // ==================== UI BUILDERS ====================

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
    if (item.title == "Manage Users") {
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

  // ==================== APPROVAL SYSTEM TOGGLE CARD ====================

  Widget _buildApprovalToggleCard() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isEnabled = _approvalSystemEnabled;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 8),
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors:
              isEnabled
                  ? [
                    successColor.withValues(alpha: 0.08),
                    successColor.withValues(alpha: 0.02),
                  ]
                  : [
                    warningColor.withValues(alpha: 0.08),
                    warningColor.withValues(alpha: 0.02),
                  ],
        ),
        borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
        border: Border.all(
          color:
              isEnabled
                  ? successColor.withValues(alpha: 0.25)
                  : warningColor.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 10 : 12),
            decoration: BoxDecoration(
              color:
                  isEnabled
                      ? successColor.withValues(alpha: 0.15)
                      : warningColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isEnabled ? Icons.verified_user_rounded : Icons.lock_open_rounded,
              color: isEnabled ? successColor : warningColor,
              size: isMobile ? 20 : 24,
            ),
          ),
          SizedBox(width: isMobile ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pending Approval System',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 13 : 15,
                    fontWeight: FontWeight.w700,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isEnabled
                      ? 'New users start as pending. Admin must approve them.'
                      : 'New users are auto-approved. No approval needed.',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 10 : 12,
                    color: Colors.grey.shade600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isEnabled
                            ? successColor.withValues(alpha: 0.12)
                            : warningColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isEnabled ? '● ENABLED' : '○ DISABLED',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 8 : 9,
                      fontWeight: FontWeight.w700,
                      color: isEnabled ? successColor : warningColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: isMobile ? 8 : 12),
          // Toggle switch
          if (_isLoadingApprovalSetting || _isSavingApprovalSetting)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Transform.scale(
              scale: isMobile ? 0.9 : 1.0,
              child: Switch(
                value: isEnabled,
                onChanged:
                    _isSuperAdmin
                        ? (value) => _toggleApprovalSystem(value)
                        : null, // only super admin can toggle
                activeThumbColor: Colors.white,
                activeTrackColor: successColor,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: Colors.grey.shade400,
              ),
            ),
        ],
      ),
    );
  }

  // ==================== STATISTICS SECTION ====================

  Widget _buildStatisticsSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isLoadingStats) {
      return _buildStatisticsLoadingShimmer(isMobile);
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics_rounded,
                color: primaryColor,
                size: isMobile ? 20 : 24,
              ),
              SizedBox(width: 8),
              Text(
                'Registration Statistics',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 16 : 20,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => fetchStatistics(),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.refresh_rounded,
                    size: isMobile ? 16 : 20,
                    color: primaryColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 12 : 16),
          Container(
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
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
                      child: _buildStatCard(
                        title: 'Today',
                        count: statistics['daily'] ?? 0,
                        icon: Icons.today_rounded,
                        color: primaryColor,
                        isMobile: isMobile,
                      ),
                    ),
                    SizedBox(width: isMobile ? 8 : 12),
                    Expanded(
                      child: _buildStatCard(
                        title: 'This Week',
                        count: statistics['weekly'] ?? 0,
                        icon: Icons.calendar_view_week_rounded,
                        color: secondaryColor,
                        isMobile: isMobile,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isMobile ? 8 : 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        title: 'This Month',
                        count: statistics['monthly'] ?? 0,
                        icon: Icons.calendar_view_month_rounded,
                        color: Colors.orange.shade700,
                        isMobile: isMobile,
                      ),
                    ),
                    SizedBox(width: isMobile ? 8 : 12),
                    Expanded(
                      child: _buildStatCard(
                        title: 'This Year',
                        count: statistics['yearly'] ?? 0,
                        icon: Icons.calendar_today_rounded,
                        color: Colors.purple.shade700,
                        isMobile: isMobile,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isMobile ? 8 : 12),
                Container(
                  padding: EdgeInsets.all(isMobile ? 8 : 12),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(isMobile ? 8 : 12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryItem(
                        label: 'Total',
                        value: statistics['totalUsers']?.toString() ?? '0',
                        icon: Icons.people_alt_rounded,
                        color: primaryColor,
                        isMobile: isMobile,
                      ),
                      _buildSummaryItem(
                        label: 'Active',
                        value: statistics['activeUsers']?.toString() ?? '0',
                        icon: Icons.check_circle_rounded,
                        color: secondaryColor,
                        isMobile: isMobile,
                      ),
                      _buildSummaryItem(
                        label: 'Admins',
                        value: statistics['adminUsers']?.toString() ?? '0',
                        icon: Icons.admin_panel_settings_rounded,
                        color: Colors.amber.shade700,
                        isMobile: isMobile,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required bool isMobile,
  }) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 10 : 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(isMobile ? 10 : 14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: isMobile ? 14 : 18),
              SizedBox(width: 4),
              Text(
                count.toString(),
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 18 : 24,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          SizedBox(height: 2),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: isMobile ? 10 : 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool isMobile,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: isMobile ? 14 : 18),
        SizedBox(width: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: isMobile ? 14 : 18,
            fontWeight: FontWeight.w700,
            color: primaryColor,
          ),
        ),
        Text(
          ' $label',
          style: GoogleFonts.inter(
            fontSize: isMobile ? 10 : 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildStatisticsLoadingShimmer(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_rounded, color: primaryColor, size: 20),
              SizedBox(width: 8),
              Text(
                'Registration Statistics',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 16 : 20,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 12 : 16),
          Shimmer.fromColors(
            baseColor: Colors.grey.shade300,
            highlightColor: Colors.grey.shade100,
            child: Container(
              padding: EdgeInsets.all(isMobile ? 12 : 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildShimmerCard(isMobile)),
                      SizedBox(width: isMobile ? 8 : 12),
                      Expanded(child: _buildShimmerCard(isMobile)),
                    ],
                  ),
                  SizedBox(height: isMobile ? 8 : 12),
                  Row(
                    children: [
                      Expanded(child: _buildShimmerCard(isMobile)),
                      SizedBox(width: isMobile ? 8 : 12),
                      Expanded(child: _buildShimmerCard(isMobile)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerCard(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(isMobile ? 10 : 14),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: isMobile ? 18 : 24,
            color: Colors.grey.shade300,
          ),
          SizedBox(height: 4),
          Container(
            width: 50,
            height: isMobile ? 10 : 12,
            color: Colors.grey.shade300,
          ),
        ],
      ),
    );
  }

  // ==================== FILTER BUTTONS ====================

  Widget _buildFilterButtons() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final filters = [
      'All Users',
      'Pending',
      'Today',
      'Weekly',
      'Monthly',
      'Yearly',
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: 8,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children:
              filters.map((filter) {
                final isSelected = _selectedFilter == filter;
                return Padding(
                  padding: EdgeInsets.only(right: isMobile ? 6 : 10),
                  child: FilterChip(
                    label: Text(
                      filter,
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 12 : 14,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? Colors.white : primaryColor,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedFilter = filter;
                        _filterUsers(_searchQuery);
                      });
                    },
                    backgroundColor: Colors.grey.shade100,
                    selectedColor: primaryColor,
                    showCheckmark: false,
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 10 : 14,
                      vertical: isMobile ? 6 : 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                );
              }).toList(),
        ),
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
          colors: [const Color(0xFF5BB592), const Color(0xFF102C68)],
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
                  'Admin / Users',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: isMobile ? 12 : 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // 🔔 Notification Bell
              FutureBuilder<int>(
                future: ApiService.getAdminUnreadCount(),
                builder: (context, snapshot) {
                  final unread = snapshot.data ?? 0;
                  return GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminNotificationsPage(),
                        ),
                      );
                      setState(() {});
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.notifications_active_rounded,
                            color: Colors.white,
                            size: isMobile ? 20 : 22,
                          ),
                        ),
                        if (unread > 0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                unread > 99 ? '99+' : '$unread',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),

              // Existing Super Admin badge
              if (_isSuperAdmin) ...[
                const SizedBox(width: 8),
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
                  Icons.people_alt_rounded,
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
                      'Manage Users',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: isMobile ? 20 : 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: isMobile ? 4 : 6),
                    Text(
                      '${users.length} Total • ${users.where((u) => u['isActive'] == true).length} Active',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: isMobile ? 12 : 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => fetchUsers(),
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
                tooltip: 'Refresh Users',
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
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText:
                          isMobile
                              ? 'Search users...'
                              : 'Search by name, email, phone or ID...',
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
                      searchController.clear();
                      _filterUsers('');
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

  // ==================== USER CARD ====================

  Widget _buildUserCard(Map<String, dynamic> user, int index) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final bool isActive = user['isActive'] ?? false;
    final bool isThisUserAdmin = user['isAdmin'] ?? false;
    final String userId = user['_id'] ?? 'N/A';
    final String userEmail = user['email'] ?? 'No Email';
    final String userName = user['fullName'] ?? 'No Name';
    final String userPhone = user['phone'] ?? 'No Phone';
    final double walletBalance =
        (user['walletBalance'] as num?)?.toDouble() ?? 0.0;
    final createdAt =
        user['createdAt'] != null
            ? DateTime.parse(user['createdAt'].toString())
            : DateTime.now();
    final bool isCurrentUser = userId == _currentUserId;
    final bool isSuperAdminUser = _isUserSuperAdmin(
      userId: userId,
      userEmail: userEmail,
    );
    final String userRole =
        user['role'] ??
        (isSuperAdminUser
            ? 'super_admin'
            : isThisUserAdmin
            ? 'admin'
            : 'user');
    final roleColor = _getRoleColor(userRole);

    // ✅ FIX: Super Admin can edit all users including their own account
    // Only prevent editing the master super admin account if it's NOT the current user
    final bool canEdit =
        _isSuperAdmin && (userId != _superAdminId || userId == _currentUserId);

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(position: _slideAnimation, child: child),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: isMobile ? 12 : 16),
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap:
                  canEdit
                      ? () => _editUser(user)
                      : () => _showAccessDeniedMessage(),
              splashColor:
                  canEdit
                      ? primaryColor.withValues(alpha: 0.05)
                      : Colors.transparent,
              highlightColor:
                  canEdit
                      ? primaryColor.withValues(alpha: 0.03)
                      : Colors.transparent,
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 14 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with avatar and user info
                    Row(
                      children: [
                        Container(
                          width: isMobile ? 44 : 52,
                          height: isMobile ? 44 : 52,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                roleColor,
                                roleColor.withValues(alpha: 0.7),
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
                        SizedBox(width: isMobile ? 14 : 18),
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
                                        color: primaryColor,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isSuperAdminUser)
                                    Container(
                                      margin: EdgeInsets.only(left: 6),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isMobile ? 6 : 10,
                                        vertical: isMobile ? 2 : 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: warningColor.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.star,
                                            color: warningColor,
                                            size: isMobile ? 10 : 12,
                                          ),
                                          SizedBox(width: 2),
                                          Text(
                                            'Super Admin',
                                            style: GoogleFonts.inter(
                                              color: warningColor,
                                              fontSize: isMobile ? 7 : 9,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else if (isThisUserAdmin)
                                    Container(
                                      margin: EdgeInsets.only(left: 6),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isMobile ? 6 : 10,
                                        vertical: isMobile ? 2 : 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: primaryColor.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.admin_panel_settings_rounded,
                                            color: primaryColor,
                                            size: isMobile ? 10 : 12,
                                          ),
                                          SizedBox(width: 2),
                                          Text(
                                            'Admin',
                                            style: GoogleFonts.inter(
                                              color: primaryColor,
                                              fontSize: isMobile ? 7 : 9,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (isCurrentUser)
                                    Container(
                                      margin: EdgeInsets.only(left: 6),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isMobile ? 6 : 10,
                                        vertical: isMobile ? 2 : 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: infoColor.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'You',
                                        style: GoogleFonts.inter(
                                          color: infoColor,
                                          fontSize: isMobile ? 7 : 9,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),

                                  // ✅ NEW: Pending approval badge
                                  if ((user['approvalStatus'] ?? 'approved') ==
                                      'pending')
                                    Container(
                                      margin: EdgeInsets.only(left: 6),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isMobile ? 6 : 10,
                                        vertical: isMobile ? 2 : 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: warningColor.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: warningColor.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.pending_actions_rounded,
                                            color: warningColor,
                                            size: isMobile ? 10 : 12,
                                          ),
                                          SizedBox(width: 3),
                                          Text(
                                            'Pending',
                                            style: GoogleFonts.inter(
                                              color: warningColor,
                                              fontSize: isMobile ? 7 : 9,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                  // ✅ NEW: Rejected badge
                                  if ((user['approvalStatus'] ?? 'approved') ==
                                      'rejected')
                                    Container(
                                      margin: EdgeInsets.only(left: 6),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isMobile ? 6 : 10,
                                        vertical: isMobile ? 2 : 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.red.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.cancel_rounded,
                                            color: Colors.red.shade700,
                                            size: isMobile ? 10 : 12,
                                          ),
                                          SizedBox(width: 3),
                                          Text(
                                            'Rejected',
                                            style: GoogleFonts.inter(
                                              color: Colors.red.shade700,
                                              fontSize: isMobile ? 7 : 9,
                                              fontWeight: FontWeight.w700,
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
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isMobile ? 14 : 18),
                    // Stats row
                    Container(
                      padding: EdgeInsets.all(isMobile ? 12 : 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
                      ),
                      child: Row(
                        children: [
                          _buildStatItem(
                            label: 'Balance',
                            value: '₦${walletBalance.toStringAsFixed(2)}',
                            icon: Icons.account_balance_wallet_rounded,
                            color: primaryColor,
                            isMobile: isMobile,
                          ),
                          Container(
                            width: 1,
                            height: isMobile ? 30 : 36,
                            color: Colors.grey.shade200,
                          ),
                          _buildStatItem(
                            label: 'Status',
                            value: isActive ? 'Active' : 'Inactive',
                            icon:
                                isActive
                                    ? Icons.check_circle_rounded
                                    : Icons.cancel_rounded,
                            color: isActive ? secondaryColor : Colors.red,
                            isMobile: isMobile,
                          ),
                          Container(
                            width: 1,
                            height: isMobile ? 30 : 36,
                            color: Colors.grey.shade200,
                          ),
                          _buildStatItem(
                            label: 'Role',
                            value: _getRoleLabel(userRole),
                            icon: Icons.badge_rounded,
                            color: roleColor,
                            isMobile: isMobile,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: isMobile ? 12 : 16),

                    // ==================== APPROVAL BUTTONS ====================
                    if ((user['approvalStatus'] ?? 'approved') == 'pending' &&
                        _isSuperAdmin)
                      Padding(
                        padding: EdgeInsets.only(bottom: isMobile ? 10 : 12),
                        child: Container(
                          padding: EdgeInsets.all(isMobile ? 10 : 12),
                          decoration: BoxDecoration(
                            color: warningColor.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: warningColor.withValues(alpha: 0.25),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.pending_actions_rounded,
                                    color: warningColor,
                                    size: isMobile ? 16 : 18,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Awaiting Approval',
                                    style: GoogleFonts.inter(
                                      fontSize: isMobile ? 12 : 13,
                                      fontWeight: FontWeight.w700,
                                      color: warningColor,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed:
                                          () => _approveUser(userId, userName),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: successColor,
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(
                                          vertical: isMobile ? 10 : 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        elevation: 0,
                                      ),
                                      icon: Icon(
                                        Icons.check_circle_rounded,
                                        size: isMobile ? 16 : 18,
                                      ),
                                      label: Text(
                                        'Approve',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w700,
                                          fontSize: isMobile ? 12 : 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: isMobile ? 8 : 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed:
                                          () => _rejectUser(userId, userName),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red.shade700,
                                        padding: EdgeInsets.symmetric(
                                          vertical: isMobile ? 10 : 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        side: BorderSide(
                                          color: Colors.red.shade200,
                                          width: 1.5,
                                        ),
                                      ),
                                      icon: Icon(
                                        Icons.cancel_rounded,
                                        size: isMobile ? 16 : 18,
                                      ),
                                      label: Text(
                                        'Reject',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w700,
                                          fontSize: isMobile ? 12 : 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    // ==================== END APPROVAL BUTTONS ====================

                    // Action buttons row (4 main actions)
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            icon: HugeIcons.strokeRoundedReceiptText,
                            label: 'History',
                            color: Colors.teal.shade700,
                            onTap: () => _openUserHistory(user),
                            isMobile: isMobile,
                          ),
                        ),
                        SizedBox(width: isMobile ? 6 : 8),
                        Expanded(
                          child: _buildActionButton(
                            icon: HugeIcons.strokeRoundedEdit01,
                            label: 'Edit',
                            color:
                                canEdit
                                    ? Colors.orange.shade700
                                    : Colors.grey.shade500,
                            onTap:
                                canEdit
                                    ? () => _editUser(user)
                                    : _showAccessDeniedMessage,
                            isMobile: isMobile,
                          ),
                        ),
                        SizedBox(width: isMobile ? 6 : 8),
                        Expanded(
                          child: _buildActionButton(
                            icon: HugeIcons.strokeRoundedLock,
                            label: 'PIN',
                            color:
                                canEdit
                                    ? Colors.purple.shade700
                                    : Colors.grey.shade500,
                            onTap:
                                canEdit
                                    ? () => _showPinManagementDialog(user)
                                    : _showAccessDeniedMessage,
                            isMobile: isMobile,
                          ),
                        ),
                        SizedBox(width: isMobile ? 6 : 8),
                        Expanded(
                          child: _buildActionButton(
                            icon: HugeIcons.strokeRoundedWallet01,
                            label: 'Fund',
                            color: secondaryColor,
                            onTap:
                                canEdit
                                    ? () =>
                                        _showFundWalletDialog(userId, userName)
                                    : _showAccessDeniedMessage,
                            isMobile: isMobile,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isMobile ? 8 : 10),
                    // NEW: Credit/Debit + View History row
                    // Credit/Debit button (full width, since History is now merged into top row)
                    SizedBox(
                      width: double.infinity,
                      child: _buildActionButton(
                        icon: HugeIcons.strokeRoundedMoneyAdd01,
                        label: 'Credit / Debit Wallet',
                        color: canEdit ? secondaryColor : Colors.grey.shade500,
                        onTap:
                            canEdit
                                ? () => _showCreditDebitDialog(user)
                                : _showAccessDeniedMessage,
                        isMobile: isMobile,
                      ),
                    ),
                    SizedBox(height: isMobile ? 10 : 12),
                    // Activate/Deactivate button - Only Super Admin
                    if (canEdit)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed:
                              () => _toggleUserStatus(userId, isActive, index),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                isActive
                                    ? Colors.red.shade50
                                    : secondaryColor.withValues(alpha: 0.08),
                            foregroundColor:
                                isActive ? Colors.red.shade700 : secondaryColor,
                            padding: EdgeInsets.symmetric(
                              vertical: isMobile ? 10 : 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color:
                                    isActive
                                        ? Colors.red.shade200
                                        : secondaryColor.withValues(alpha: 0.2),
                                width: 1.5,
                              ),
                            ),
                            elevation: 0,
                          ),
                          icon: Icon(
                            isActive
                                ? Icons.person_remove_rounded
                                : Icons.person_add_rounded,
                            size: isMobile ? 18 : 20,
                          ),
                          label: Text(
                            isActive ? 'Deactivate User' : 'Activate User',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: isMobile ? 12 : 14,
                            ),
                          ),
                        ),
                      )
                    else if (_isAdmin && !_isSuperAdmin)
                      // Show message for normal admins
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          vertical: isMobile ? 10 : 12,
                        ),
                        decoration: BoxDecoration(
                          color: warningColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: warningColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              color: warningColor,
                              size: isMobile ? 16 : 18,
                            ),
                            SizedBox(width: isMobile ? 6 : 8),
                            Text(
                              'Contact Super Admin for user management',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w500,
                                fontSize: isMobile ? 10 : 12,
                                color: warningColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool isMobile,
  }) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: isMobile ? 14 : 16, color: color),
              SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 10 : 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: isMobile ? 13 : 15,
              fontWeight: FontWeight.w700,
              color: primaryColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required dynamic icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool isMobile,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: isMobile ? 6 : 8,
            horizontal: 4,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(icon: icon, color: color, size: isMobile ? 16 : 20),
              SizedBox(height: isMobile ? 2 : 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: color,
                  fontSize: isMobile ? 8 : 10,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }


  // ==================== OPEN USER HISTORY (SHARED) ====================
/// Opens the rich AdminUserHistoryPage for a given user.
/// Used by the "History" button on each user card.
void _openUserHistory(Map<String, dynamic> user) {
  final userId = user['_id']?.toString() ?? '';
  final userName = user['fullName']?.toString() ?? 'User';
  final userEmail = user['email']?.toString() ?? '';
  final walletBalance = (user['walletBalance'] as num?)?.toDouble() ?? 0.0;
  final commissionBalance =
      (user['commissionBalance'] as num?)?.toDouble() ?? 0.0;

  if (userId.isEmpty) {
    _showSnackBar('User ID is missing', true);
    return;
  }

  Navigator.push(
    context,
    MaterialPageRoute(
      builder:
          (_) => AdminUserHistoryPage(
            userId: userId,
            userName: userName,
            userEmail: userEmail,
            currentBalance: walletBalance,
            commissionBalance: commissionBalance,
          ),
    ),
  ).then((_) {
    // Refresh the user list when returning (wallet may have changed)
    fetchUsers();
  });
}

  // ==================== ACCESS DENIED MESSAGE ====================

  void _showAccessDeniedMessage() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.lock_outline_rounded, color: warningColor, size: 28),
                SizedBox(width: 12),
                Text(
                  'Access Restricted',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: isMobile ? 18 : 20,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.admin_panel_settings_rounded,
                  color: primaryColor.withValues(alpha: 0.3),
                  size: 64,
                ),
                SizedBox(height: 16),
                Text(
                  'Only Super Administrators can perform this action.',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 14 : 16,
                    color: textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: warningColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: warningColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: warningColor,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Please contact the Super Administrator to request access to this feature.',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 12 : 13,
                            color: warningColor,
                            fontWeight: FontWeight.w500,
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
                style: TextButton.styleFrom(foregroundColor: primaryColor),
                child: Text(
                  'Got it',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
    );
  }

  // ==================== CREDIT/DEBIT QUICK TEMPLATES ====================
  // Predefined reasons admin can pick with one tap.
  // Admin can still type a custom reason.
  static final List<Map<String, String>> _creditDebitTemplates = [
    {
      'label': 'Refund — Failed Transaction',
      'reason': 'Refund for failed transaction',
      'icon': '↩️',
      'applyTo': 'credit', // only shows when Credit is selected
    },
    {
      'label': 'Service Recovery',
      'reason': 'Service recovery — compensation for downtime',
      'icon': '🔧',
      'applyTo': 'credit',
    },
    {
      'label': 'Bonus / Goodwill',
      'reason': 'Goodwill bonus credited by admin',
      'icon': '🎁',
      'applyTo': 'credit',
    },
    {
      'label': 'Correction — Overcharged',
      'reason': 'Correcting overcharged amount',
      'icon': '📝',
      'applyTo': 'credit',
    },
    {
      'label': 'Manual Deposit',
      'reason': 'Manual deposit by admin',
      'icon': '💵',
      'applyTo': 'credit',
    },
    {
      'label': 'Reversal — Incorrect Credit',
      'reason': 'Reversal of incorrect credit',
      'icon': '🔁',
      'applyTo': 'debit',
    },
    {
      'label': 'Correction — Undercharged',
      'reason': 'Correcting undercharged amount',
      'icon': '🛠️',
      'applyTo': 'debit',
    },
    {
      'label': 'Fraud / Suspicious Activity',
      'reason': 'Debit due to fraud/suspicious activity',
      'icon': '🚨',
      'applyTo': 'debit',
    },
    {
      'label': 'Settlement Adjustment',
      'reason': 'Settlement adjustment debit',
      'icon': '⚖️',
      'applyTo': 'debit',
    },
    {'label': 'Custom Reason', 'reason': '', 'icon': '✏️', 'applyTo': 'both'},
  ];

  /// Filter templates based on the selected operation.
  List<Map<String, String>> _getTemplatesFor(String operation) {
    return _creditDebitTemplates
        .where((t) => t['applyTo'] == 'both' || t['applyTo'] == operation)
        .toList();
  }

  // ==================== CREDIT / DEBIT DIALOG ====================

  void _showCreditDebitDialog(Map<String, dynamic> user) {
    final String userId = user['_id']?.toString() ?? '';
    final String userName = user['fullName']?.toString() ?? 'User';
    final String userEmail = user['email']?.toString() ?? '';
    final double currentBalance =
        (user['walletBalance'] as num?)?.toDouble() ?? 0.0;

    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    final referenceController = TextEditingController();
    final noteController = TextEditingController();

    String operation = 'credit'; // 'credit' | 'debit'
    bool isSaving = false;

    final isMobile = MediaQuery.of(context).size.width < 600;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final templates = _getTemplatesFor(operation);

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isMobile ? 20 : 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // ============ TITLE ============
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (operation == 'credit'
                                    ? secondaryColor
                                    : Colors.red)
                                .withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            operation == 'credit'
                                ? Icons.add_rounded
                                : Icons.remove_rounded,
                            color:
                                operation == 'credit'
                                    ? secondaryColor
                                    : Colors.red,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Wallet Adjustment',
                                style: GoogleFonts.inter(
                                  fontSize: isMobile ? 16 : 18,
                                  fontWeight: FontWeight.w700,
                                  color: primaryColor,
                                ),
                              ),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      userName,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: primaryColor.withValues(
                                        alpha: 0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Balance: ₦${currentBalance.toStringAsFixed(2)}',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: primaryColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(modalContext),
                          icon: const Icon(Icons.close_rounded),
                          color: textSecondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ============ CREDIT / DEBIT TOGGLE ============
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  operation = 'credit';
                                  // Clear reason when switching — user picks new template
                                  reasonController.clear();
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      operation == 'credit'
                                          ? secondaryColor
                                          : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_circle_outline_rounded,
                                      size: 16,
                                      color:
                                          operation == 'credit'
                                              ? Colors.white
                                              : textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Credit',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            operation == 'credit'
                                                ? Colors.white
                                                : textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  operation = 'debit';
                                  reasonController.clear();
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      operation == 'debit'
                                          ? Colors.red
                                          : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.remove_circle_outline_rounded,
                                      size: 16,
                                      color:
                                          operation == 'debit'
                                              ? Colors.white
                                              : textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Debit',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            operation == 'debit'
                                                ? Colors.white
                                                : textSecondary,
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
                    const SizedBox(height: 16),

                    // ============ AMOUNT ============
                    _buildDialogField(
                      label: 'Amount (₦)',
                      controller: amountController,
                      hint: '0.00',
                      icon: Icons.attach_money_rounded,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ============ QUICK TEMPLATES ============
                    Row(
                      children: [
                        Icon(
                          Icons.bolt_rounded,
                          size: 16,
                          color: primaryColor.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Quick Templates',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '— tap one to auto-fill the reason',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 140),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              templates.map((t) {
                                final isCustom = t['reason']!.isEmpty;
                                return GestureDetector(
                                  onTap: () {
                                    setModalState(() {
                                      if (isCustom) {
                                        // Just focus — leave text blank
                                        reasonController.text = '';
                                      } else {
                                        reasonController.text =
                                            t['reason'] ?? '';
                                      }
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          isCustom
                                              ? Colors.grey.shade100
                                              : (operation == 'credit'
                                                      ? secondaryColor
                                                      : Colors.red)
                                                  .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color:
                                            isCustom
                                                ? Colors.grey.shade300
                                                : (operation == 'credit'
                                                        ? secondaryColor
                                                        : Colors.red)
                                                    .withValues(alpha: 0.25),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          t['icon'] ?? '',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          t['label'] ?? '',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                isCustom
                                                    ? textPrimary
                                                    : (operation == 'credit'
                                                        ? secondaryColor
                                                        : Colors.red.shade700),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ============ REASON (Editable) ============
                    _buildDialogField(
                      label: 'Reason * (min 3 characters)',
                      controller: reasonController,
                      hint: 'Type reason or pick a template above',
                      icon: Icons.notes_rounded,
                    ),
                    const SizedBox(height: 12),

                    // ============ REFERENCE (Optional) ============
                    _buildDialogField(
                      label: 'Reference (optional)',
                      controller: referenceController,
                      hint: 'e.g. TICKET-12345',
                      icon: Icons.confirmation_number_outlined,
                    ),
                    const SizedBox(height: 12),

                    // ============ NOTE (Optional) ============
                    _buildDialogField(
                      label: 'Note (optional)',
                      controller: noteController,
                      hint: 'Additional details...',
                      icon: Icons.description_outlined,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 20),

                    // ============ CONFIRM BUTTON ============
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            isSaving
                                ? null
                                : () async {
                                  final amountText =
                                      amountController.text.trim();
                                  final reasonText =
                                      reasonController.text.trim();

                                  if (amountText.isEmpty) {
                                    _showSnackBar(
                                      'Please enter an amount',
                                      true,
                                    );
                                    return;
                                  }
                                  final amt = double.tryParse(amountText);
                                  if (amt == null || amt <= 0) {
                                    _showSnackBar(
                                      'Please enter a valid amount',
                                      true,
                                    );
                                    return;
                                  }
                                  if (reasonText.length < 3) {
                                    _showSnackBar(
                                      'Reason is required (min 3 characters)',
                                      true,
                                    );
                                    return;
                                  }

                                  setModalState(() => isSaving = true);

                                  try {
                                    final Map<String, dynamic> res;
                                    if (operation == 'credit') {
                                      res = await ApiService.adminCreditWallet(
                                        userId: userId,
                                        amount: amt,
                                        reason: reasonText,
                                        reference:
                                            referenceController.text
                                                    .trim()
                                                    .isEmpty
                                                ? null
                                                : referenceController.text
                                                    .trim(),
                                        note:
                                            noteController.text.trim().isEmpty
                                                ? null
                                                : noteController.text.trim(),
                                      );
                                    } else {
                                      res = await ApiService.adminDebitWallet(
                                        userId: userId,
                                        amount: amt,
                                        reason: reasonText,
                                        reference:
                                            referenceController.text
                                                    .trim()
                                                    .isEmpty
                                                ? null
                                                : referenceController.text
                                                    .trim(),
                                        note:
                                            noteController.text.trim().isEmpty
                                                ? null
                                                : noteController.text.trim(),
                                      );
                                    }

                                    if (mounted) {
                                      Navigator.pop(modalContext);
                                      _showSnackBar(
                                        res['message']?.toString() ??
                                            'Wallet updated successfully',
                                        false,
                                      );
                                      // Refresh list to show new balance
                                      fetchUsers();
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      setModalState(() => isSaving = false);
                                      _showSnackBar(
                                        e.toString().replaceFirst(
                                          'Exception: ',
                                          '',
                                        ),
                                        true,
                                      );
                                    }
                                  }
                                },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              operation == 'credit'
                                  ? secondaryColor
                                  : Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child:
                            isSaving
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      operation == 'credit'
                                          ? Icons.add_rounded
                                          : Icons.remove_rounded,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      operation == 'credit'
                                          ? 'Credit Wallet'
                                          : 'Debit Wallet',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        'ℹ️ This action will be logged in the audit trail',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==================== USER HISTORY DIALOG (AUDIT TRAIL) ====================

  void _showUserHistoryDialog(Map<String, dynamic> user) {
    final userId = user['_id']?.toString() ?? '';
    final userName = user['fullName']?.toString() ?? 'User';
    final userEmail = user['email']?.toString() ?? '';
    final walletBalance = (user['walletBalance'] as num?)?.toDouble() ?? 0.0;
    final commissionBalance =
        (user['commissionBalance'] as num?)?.toDouble() ?? 0.0;

    if (userId.isEmpty) {
      _showSnackBar('User ID is missing', true);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => AdminUserHistoryPage(
              userId: userId,
              userName: userName,
              userEmail: userEmail,
              currentBalance: walletBalance,
              commissionBalance: commissionBalance,
            ),
      ),
    ).then((_) {
      // Refresh the user list when returning, in case wallet changed
      fetchUsers();
    });
  }

  Widget _buildHistoryBody({
    required Map<String, dynamic> data,
    required String selectedTab,
    required bool isMobile,
  }) {
    if (selectedTab == 'audit') {
      final logs = (data['auditLogs'] as List?) ?? [];
      if (logs.isEmpty) {
        return Center(
          child: Text(
            'No admin activity yet',
            style: GoogleFonts.inter(color: textSecondary),
          ),
        );
      }
      return ListView.builder(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 20,
          vertical: 8,
        ),
        itemCount: logs.length,
        itemBuilder: (context, i) {
          final log = logs[i] as Map<String, dynamic>;
          return _buildAuditLogTile(log);
        },
      );
    } else {
      final txs = (data['transactions'] as List?) ?? [];
      if (txs.isEmpty) {
        return Center(
          child: Text(
            'No transactions found',
            style: GoogleFonts.inter(color: textSecondary),
          ),
        );
      }
      return ListView.builder(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 20,
          vertical: 8,
        ),
        itemCount: txs.length,
        itemBuilder: (context, i) {
          final tx = txs[i] as Map<String, dynamic>;
          return _buildTransactionTile(tx);
        },
      );
    }
  }

  Widget _buildAuditLogTile(Map<String, dynamic> log) {
    final action = (log['action'] ?? '').toString();
    final color = _getAuditColor(action);
    final icon = _getAuditIcon(action);
    final amount = (log['amount'] as num?)?.toDouble() ?? 0;
    final before = (log['balanceBefore'] as num?)?.toDouble() ?? 0;
    final after = (log['balanceAfter'] as num?)?.toDouble() ?? 0;
    final admin = (log['adminName'] ?? 'Admin').toString();
    final createdAt = log['createdAt']?.toString() ?? '';
    final reason = (log['reason'] ?? '').toString();
    final reference = (log['reference'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 14),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _humanizeAction(action),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: primaryColor,
                  ),
                ),
              ),
              if (createdAt.isNotEmpty)
                Text(
                  _formatDate(DateTime.tryParse(createdAt) ?? DateTime.now()),
                  style: GoogleFonts.inter(fontSize: 10, color: textSecondary),
                ),
            ],
          ),
          if (amount > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(
                    '₦${amount.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '₦${before.toStringAsFixed(2)} → ₦${after.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Reason: $reason',
              style: GoogleFonts.inter(fontSize: 11, color: textSecondary),
            ),
          ],
          if (reference.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Ref: $reference',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'By: $admin',
            style: GoogleFonts.inter(
              fontSize: 10,
              color: primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(Map<String, dynamic> tx) {
    final status = (tx['status'] ?? '').toString();
    final isSuccess = status.toLowerCase().contains('success');
    final isFailed = status.toLowerCase().contains('fail');
    final color =
        isSuccess
            ? successColor
            : isFailed
            ? errorColor
            : warningColor;
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final type = (tx['type'] ?? 'Transaction').toString();
    final desc = (tx['description'] ?? '').toString();
    final createdAt = tx['createdAt']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSuccess
                  ? Icons.check_circle_rounded
                  : isFailed
                  ? Icons.cancel_rounded
                  : Icons.schedule_rounded,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: primaryColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (desc.isNotEmpty)
                  Text(
                    desc,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (createdAt.isNotEmpty)
                  Text(
                    _formatDate(DateTime.tryParse(createdAt) ?? DateTime.now()),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '₦${amount.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _getAuditColor(String action) {
    if (action.contains('CREDIT')) return successColor;
    if (action.contains('DEBIT')) return errorColor;
    if (action.contains('ACTIVATED')) return successColor;
    if (action.contains('DEACTIVATED')) return errorColor;
    if (action.contains('SUSPENDED')) return warningColor;
    if (action.contains('APPROVED')) return successColor;
    if (action.contains('REJECTED')) return errorColor;
    if (action.contains('PIN')) return warningColor;
    return infoColor;
  }

  IconData _getAuditIcon(String action) {
    if (action.contains('CREDIT')) return Icons.add_rounded;
    if (action.contains('DEBIT')) return Icons.remove_rounded;
    if (action.contains('ACTIVATED')) return Icons.check_circle_rounded;
    if (action.contains('DEACTIVATED')) return Icons.cancel_rounded;
    if (action.contains('SUSPENDED')) return Icons.block_rounded;
    if (action.contains('APPROVED')) return Icons.verified_rounded;
    if (action.contains('REJECTED')) return Icons.cancel_rounded;
    if (action.contains('PIN')) return Icons.lock_rounded;
    if (action.contains('EDITED')) return Icons.edit_rounded;
    if (action.contains('ROLE')) return Icons.admin_panel_settings_rounded;
    return Icons.history_rounded;
  }

  String _humanizeAction(String action) {
    return action
        .split('_')
        .map(
          (w) =>
              w.isEmpty
                  ? w
                  : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  // ==================== REUSABLE DIALOG FIELD ====================

  Widget _buildDialogField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: textPrimary,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.grey.shade400,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  icon,
                  color: primaryColor.withValues(alpha: 0.5),
                  size: 18,
                ),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== DIALOGS ====================

  void _showFundWalletDialog(String userId, String userName) {
    final TextEditingController amountController = TextEditingController();
    final isMobile = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            insetPadding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: isMobile ? 24 : 32,
            ),
            child: Container(
              padding: EdgeInsets.all(isMobile ? 20 : 28),
              constraints: BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(isMobile ? 14 : 18),
                    decoration: BoxDecoration(
                      color: secondaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      color: secondaryColor,
                      size: isMobile ? 32 : 40,
                    ),
                  ),
                  SizedBox(height: isMobile ? 16 : 20),
                  Text(
                    'Fund Wallet',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 20 : 24,
                      fontWeight: FontWeight.w700,
                      color: primaryColor,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Add funds to $userName\'s wallet',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 14 : 16,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: isMobile ? 20 : 24),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'),
                        ),
                      ],
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 18 : 20,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                      decoration: InputDecoration(
                        hintText: "0.00",
                        hintStyle: GoogleFonts.inter(
                          color: Colors.grey.shade400,
                        ),
                        prefixIcon: Padding(
                          padding: EdgeInsets.all(isMobile ? 12 : 16),
                          child: Text(
                            '₦',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 18 : 20,
                              fontWeight: FontWeight.w700,
                              color: primaryColor,
                            ),
                          ),
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: isMobile ? 14 : 18,
                          horizontal: 12,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isMobile ? 20 : 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
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
                        child: ElevatedButton(
                          onPressed: () async {
                            final amount = double.tryParse(
                              amountController.text.trim(),
                            );
                            if (amount != null && amount > 0) {
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
                              await _fundWallet(userId, amount);
                            } else {
                              _showSnackBar(
                                'Please enter a valid amount.',
                                true,
                              );
                            }
                          },
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
                            'Add Funds',
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
          ),
    );
  }

  void _showPinManagementDialog(Map<String, dynamic> user) {
    final String userId = user['_id'] ?? '';
    final String userName = user['fullName'] ?? 'User';
    final String userEmail = user['email'] ?? '';
    bool isLoading = false;

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => Dialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    constraints: BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.lock_rounded,
                            color: Colors.purple.shade700,
                            size: 32,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'PIN Management',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: primaryColor,
                          ),
                        ),
                        SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Text(
                                userName,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: primaryColor,
                                ),
                              ),
                              Text(
                                userEmail,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 20),
                        if (isLoading)
                          Center(
                            child: CircularProgressIndicator(
                              color: primaryColor,
                            ),
                          )
                        else
                          Column(
                            children: [
                              _buildPinActionButton(
                                icon: Icons.search_rounded,
                                label: 'Check PIN Status',
                                color: Colors.blue.shade700,
                                onTap: () async {
                                  setState(() => isLoading = true);
                                  try {
                                    final response =
                                        await ApiService.adminCheckPinStatus(
                                          userId: userId,
                                        );
                                    if (response['success'] == true) {
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
                                      _showPinStatusDetails(response);
                                    } else {
                                      _showSnackBar(
                                        response['message'] ??
                                            'Failed to check PIN status',
                                        true,
                                      );
                                    }
                                  } catch (e) {
                                    _showSnackBar(
                                      'Error: ${e.toString().replaceAll("Exception: ", "")}',
                                      true,
                                    );
                                  } finally {
                                    setState(() => isLoading = false);
                                  }
                                },
                              ),
                              SizedBox(height: 10),
                              _buildPinActionButton(
                                icon: Icons.lock_open_rounded,
                                label: 'Unlock PIN',
                                color: Colors.orange.shade700,
                                onTap: () async {
                                  final confirm = await _showConfirmDialog(
                                    title: 'Unlock PIN?',
                                    message:
                                        'This will reset failed attempts and unlock the PIN for $userName.',
                                    confirmText: 'Unlock',
                                    confirmColor: Colors.orange,
                                  );
                                  if (confirm != true) return;

                                  setState(() => isLoading = true);
                                  try {
                                    final response =
                                        await ApiService.adminUnlockPin(
                                          userId: userId,
                                        );
                                    if (response['success'] == true) {
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
                                      _showSnackBar(
                                        '✅ PIN unlocked for $userName',
                                        false,
                                      );
                                    } else {
                                      _showSnackBar(
                                        response['message'] ??
                                            'Failed to unlock PIN',
                                        true,
                                      );
                                    }
                                  } catch (e) {
                                    _showSnackBar(
                                      'Error: ${e.toString().replaceAll("Exception: ", "")}',
                                      true,
                                    );
                                  } finally {
                                    setState(() => isLoading = false);
                                  }
                                },
                              ),
                              SizedBox(height: 10),
                              _buildPinActionButton(
                                icon: Icons.restart_alt_rounded,
                                label: 'Reset PIN to Default',
                                color: Colors.red.shade700,
                                onTap: () async {
                                  final confirm = await _showConfirmDialog(
                                    title: 'Reset PIN?',
                                    message:
                                        'This will reset the PIN to default (123456). User will need to change it on next login.',
                                    confirmText: 'Reset',
                                    confirmColor: Colors.red,
                                  );
                                  if (confirm != true) return;

                                  setState(() => isLoading = true);
                                  try {
                                    final response =
                                        await ApiService.adminResetPin(
                                          userId: userId,
                                        );
                                    if (response['success'] == true) {
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
                                      _showSnackBar(
                                        '✅ PIN reset to 123456 for $userName',
                                        false,
                                      );
                                    } else {
                                      _showSnackBar(
                                        response['message'] ??
                                            'Failed to reset PIN',
                                        true,
                                      );
                                    }
                                  } catch (e) {
                                    _showSnackBar(
                                      'Error: ${e.toString().replaceAll("Exception: ", "")}',
                                      true,
                                    );
                                  } finally {
                                    setState(() => isLoading = false);
                                  }
                                },
                              ),
                            ],
                          ),
                        SizedBox(height: 16),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Close',
                            style: GoogleFonts.inter(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }

  Widget _buildPinActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.08),
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color.withValues(alpha: 0.2)),
          ),
          elevation: 0,
        ),
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    );
  }

  void _showPinStatusDetails(Map<String, dynamic> response) {
    final user = response['user'];
    final pinStatus = response['pinStatus'];
    final isMobile = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              padding: EdgeInsets.all(isMobile ? 20 : 24),
              constraints: BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.security_rounded,
                      color: primaryColor,
                      size: 32,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'PIN Status Details',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 18 : 20,
                      fontWeight: FontWeight.w700,
                      color: primaryColor,
                    ),
                  ),
                  SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          user['fullName'] ?? 'User',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: primaryColor,
                          ),
                        ),
                        Text(
                          user['email'] ?? '',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  _buildStatusCard(
                    title: 'Lock Status',
                    value:
                        (pinStatus['isPinLocked'] ?? false)
                            ? 'LOCKED'
                            : 'UNLOCKED',
                    color:
                        (pinStatus['isPinLocked'] ?? false)
                            ? Colors.red
                            : secondaryColor,
                    icon:
                        (pinStatus['isPinLocked'] ?? false)
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                  ),
                  SizedBox(height: 10),
                  _buildStatusCard(
                    title: 'Failed Attempts',
                    value: '${pinStatus['failedAttempts'] ?? 0}',
                    color:
                        (pinStatus['failedAttempts'] ?? 0) > 0
                            ? Colors.orange
                            : secondaryColor,
                    icon: Icons.warning_rounded,
                  ),
                  if ((pinStatus['isPinLocked'] ?? false))
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _buildStatusCard(
                        title: 'Lock Remaining',
                        value: '${pinStatus['lockRemainingMinutes'] ?? 0} min',
                        color: Colors.red,
                        icon: Icons.timer_rounded,
                      ),
                    ),
                  SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Close',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildStatusCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                color: primaryColor,
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
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  confirmText,
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

  // ==================== ACTIONS ====================

  Future<void> _toggleUserStatus(
    String userId,
    bool currentStatus,
    int index,
  ) async {
    final confirm = await _showConfirmDialog(
      title: currentStatus ? 'Deactivate User?' : 'Activate User?',
      message:
          'Are you sure you want to ${currentStatus ? 'deactivate' : 'activate'} this user\'s account?',
      confirmText: currentStatus ? 'Deactivate' : 'Activate',
      confirmColor: currentStatus ? Colors.red : secondaryColor,
    );
    if (confirm != true) return;

    setState(() => isLoading = true);
    try {
      final response = await ApiService.toggleUserStatus(
        userIdToToggle: userId,
        isActive: !currentStatus,
      );
      if (response['success'] == true) {
        _showSnackBar(response['message'] ?? "User status updated.", false);
        setState(() {
          final userIndexInOriginal = users.indexWhere(
            (u) => u['_id'] == userId,
          );
          if (userIndexInOriginal != -1) {
            users[userIndexInOriginal]['isActive'] = !currentStatus;
          }
          _filterUsers(searchController.text);
        });
      } else {
        _showSnackBar(
          response['message'] ?? "Failed to update user status.",
          true,
        );
      }
    } catch (e) {
      if (e.toString().contains('Admin access required')) {
        _showSnackBar(
          "You no longer have admin privileges. Contact Super Admin.",
          true,
        );
        setState(() {
          _isAdmin = false;
          _isSuperAdmin = false;
          errorMessage = "You don't have permission to access admin features.";
        });
      } else {
        _showSnackBar("Error: ${e.toString()}", true);
      }
      debugPrint("Error toggling user status: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ==================== USER APPROVAL ACTIONS ====================

  Future<void> _approveUser(String userId, String userName) async {
    final confirm = await _showConfirmDialog(
      title: 'Approve User?',
      message:
          'Approve $userName? They will be able to perform transactions immediately.',
      confirmText: 'Approve',
      confirmColor: successColor,
    );
    if (confirm != true) return;

    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final response = await ApiService.approveUser(userId);
      if (!mounted) return;
      if (response['success'] == true) {
        _showSnackBar('✅ $userName approved successfully', false);
        await fetchUsers();
      } else {
        _showSnackBar(response['message'] ?? 'Failed to approve user', true);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error: ${e.toString()}', true);
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _rejectUser(String userId, String userName) async {
    // Ask for reason
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.cancel_rounded,
                  color: Colors.red.shade700,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Text(
                  'Reject User?',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reject $userName? They will not be able to perform transactions.',
                  style: GoogleFonts.inter(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  style: GoogleFonts.inter(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Reason (optional)',
                    hintText: 'e.g. Suspicious activity',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Reject',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
    );

    if (confirmed != true) return;

    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final response = await ApiService.rejectUser(
        userId,
        reason:
            reasonController.text.trim().isEmpty
                ? 'Rejected by admin'
                : reasonController.text.trim(),
      );
      if (!mounted) return;
      if (response['success'] == true) {
        _showSnackBar('❌ $userName rejected', false);
        await fetchUsers();
      } else {
        _showSnackBar(response['message'] ?? 'Failed to reject user', true);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error: ${e.toString()}', true);
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _fundWallet(String userId, double amount) async {
    setState(() => isLoading = true);
    try {
      final response = await ApiService.fundWallet(
        userId: userId,
        amount: amount,
        type: 'credit',
      );
      if (response['success'] == true) {
        _showSnackBar("✅ Wallet funded successfully", false);
        await fetchUsers();
      } else {
        throw Exception(response['message'] ?? "Failed to fund wallet");
      }
    } catch (e) {
      debugPrint("❌ Fund wallet error: $e");
      if (e.toString().contains('Admin access required')) {
        _showSnackBar(
          "You no longer have admin privileges. Contact Super Admin.",
          true,
        );
        setState(() {
          _isAdmin = false;
          _isSuperAdmin = false;
          errorMessage = "You don't have permission to access admin features.";
        });
      } else {
        _showSnackBar(e.toString(), true);
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _viewTransactions(String userId, String userEmail, String userName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) =>
                AdminUserTransactionPage(userId: userId, userEmail: userEmail),
      ),
    );
  }

  void _editUser(Map<String, dynamic> userToEdit) async {
    // Only Super Admin can edit users
    if (!_isSuperAdmin) {
      _showAccessDeniedMessage();
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) =>
                AdminEditUserPage(user: userToEdit, onUserUpdated: fetchUsers),
      ),
    );
    await fetchUsers();
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnackBar("📋 User ID copied", false);
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
        backgroundColor: isError ? Colors.red.shade700 : secondaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

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
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  // ==================== LOADING STATES ====================

  Widget _buildLoadingState() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: isMobile ? 60 : 80,
            height: isMobile ? 60 : 80,
            child: CircularProgressIndicator(
              strokeWidth: isMobile ? 4 : 6,
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              backgroundColor: primaryColor.withValues(alpha: 0.1),
            ),
          ),
          SizedBox(height: isMobile ? 16 : 20),
          Text(
            'Loading Users...',
            style: GoogleFonts.inter(
              fontSize: isMobile ? 16 : 18,
              fontWeight: FontWeight.w600,
              color: primaryColor,
            ),
          ),
          SizedBox(height: isMobile ? 8 : 12),
          Text(
            'Please wait while we fetch user data',
            style: GoogleFonts.inter(
              fontSize: isMobile ? 12 : 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState({String? message}) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final displayMessage = message ?? errorMessage ?? 'Something went wrong.';

    return Center(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 20 : 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: isMobile ? 80 : 120,
              height: isMobile ? 80 : 120,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                color: Colors.red.shade700,
                size: isMobile ? 40 : 60,
              ),
            ),
            SizedBox(height: isMobile ? 16 : 24),
            Text(
              'Access Denied',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 22 : 28,
                fontWeight: FontWeight.w700,
                color: Colors.red.shade700,
              ),
            ),
            SizedBox(height: isMobile ? 8 : 12),
            Text(
              displayMessage,
              style: GoogleFonts.inter(
                fontSize: isMobile ? 14 : 16,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isMobile ? 24 : 32),
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

  Widget _buildEmptyState() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: isMobile ? 80 : 120,
              height: isMobile ? 80 : 120,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_search_rounded,
                color: primaryColor,
                size: isMobile ? 40 : 60,
              ),
            ),
            SizedBox(height: isMobile ? 16 : 24),
            Text(
              'No Users Found',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 20 : 24,
                fontWeight: FontWeight.w700,
                color: primaryColor,
              ),
            ),
            SizedBox(height: isMobile ? 8 : 12),
            Text(
              'Try adjusting your search criteria',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 14 : 16,
                color: Colors.grey.shade600,
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
          (item) => item.title == "Manage Users",
          orElse: () => _drawerItems.first,
        ),
        onItemSelected: _onDrawerItemSelected,
        isAdmin: true,
      ),
      body: SafeArea(
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
            Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    color: primaryColor,
                    onRefresh: () async {
                      await Future.wait([
                        fetchUsers(),
                        fetchStatistics(),
                        _loadApprovalSetting(),
                      ]);
                      if (mounted) setState(() {});
                    },
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            children: [
                              _buildAdminHeader(),
                              // ✅ NEW: Approval toggle card
                              _buildApprovalToggleCard(),
                              _buildStatisticsSection(),
                              SizedBox(height: isMobile ? 8 : 12),
                              _buildFilterButtons(),
                              if (isLoading)
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.3,
                                  child: _buildLoadingState(),
                                )
                              else if (errorMessage != null)
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.4,
                                  child: _buildErrorState(),
                                )
                              else if (filteredUsers.isEmpty)
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.4,
                                  child: _buildEmptyState(),
                                ),
                            ],
                          ),
                        ),
                        if (!isLoading &&
                            errorMessage == null &&
                            filteredUsers.isNotEmpty)
                          SliverPadding(
                            padding: EdgeInsets.only(
                              left: isMobile ? 16 : 24,
                              right: isMobile ? 16 : 24,
                              bottom: isMobile ? 100 : 24,
                            ),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(((
                                context,
                                index,
                              ) {
                                final user =
                                    filteredUsers[index]
                                        as Map<String, dynamic>;
                                return _buildUserCard(user, index);
                              }), childCount: filteredUsers.length),
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
    );
  }
}
