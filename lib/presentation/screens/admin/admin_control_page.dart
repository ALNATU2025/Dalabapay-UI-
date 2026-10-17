// lib/presentation/screens/admin/admin_control_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';
import '../dashboard/dashboard_screen.dart';

class AdminControlPage extends StatefulWidget {
  const AdminControlPage({super.key});

  @override
  State<AdminControlPage> createState() => _AdminControlPageState();
}

class _AdminControlPageState extends State<AdminControlPage>
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

  // ==================== CONTROLLERS ====================
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  // ==================== STATE ====================
  bool _isLoading = true;
  bool _isProcessing = false;
  bool _isAdmin = false;
  bool _isSuperAdmin = false;
  String? _errorMessage;
  String _currentUserId = '';
  String _currentUserName = '';
  String _currentUserEmail = '';
  String _currentUserRole = 'user';

  // User Data
  List<dynamic> _users = [];
  List<dynamic> _filteredUsers = [];
  List<dynamic> _adminsList = [];
  List<Map<String, dynamic>> _rolesList = [];
  List<String> _permissionsList = [];
  String _searchQuery = '';

  // Filters
  String _selectedFilter = 'all';
  String _selectedRole = 'all';
  String _selectedStatus = 'all';
  String _selectedSearchBy = 'Name';
  final List<String> _searchOptions = ['Name', 'Email', 'User ID', 'Role'];

  // ==================== ANIMATION ====================
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
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
          _searchQuery = _searchController.text.toLowerCase();
          _applyFilters();
        }
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _emailController.dispose();
    _animationController.dispose();
    _searchDebounce?.cancel();
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
  }

  // ==================== DATA LOADING ====================

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      await _loadCurrentUser();
      await _fetchUsers();
      await _loadAdminsList();
      await _loadRolesAndPermissions();
      _animationController.forward();
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      setState(() {
        _errorMessage = "Error loading data: ${e.toString()}";
        _isLoading = false;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

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
            // ✅ TRUST BACKEND ONLY — no hardcoded ID
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

            // Update SharedPreferences with correct role data
            await prefs.setString('role', userRole);
            await prefs.setBool('isAdmin', isAdmin);
            await prefs.setBool('isSuperAdmin', isSuperAdmin);
          } else {
            // Fallback to stored data
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
    // ✅ Trust stored role from backend, fallback to isAdmin/isSuperAdmin flags
    final storedRole = userData['role']?.toString() ?? 'user';
    final storedIsSuperAdmin =
        userData['isSuperAdmin'] == true || storedRole == 'super_admin';
    final storedIsAdmin =
        userData['isAdmin'] == true ||
        storedRole == 'admin' ||
        storedIsSuperAdmin;

    setState(() {
      _currentUserId = userData['_id']?.toString() ?? '';
      _currentUserName = userData['fullName'] ?? 'Unknown User';
      _currentUserEmail = userData['email'] ?? 'No Email';
      _isAdmin = storedIsAdmin;
      // ✅ No hardcoded ID — trust the backend-stored role
      _isSuperAdmin = storedIsSuperAdmin;
      _currentUserRole =
          storedIsSuperAdmin
              ? 'super_admin'
              : (storedIsAdmin ? 'admin' : 'user');
    });
  }

  Future<void> _fetchUsers() async {
    try {
      debugPrint('🔄 _fetchUsers() called');
      final fetchedUsers = await ApiService.getAllUsersForAdmin();
      debugPrint('📊 _fetchUsers() received ${fetchedUsers.length} users');

      if (fetchedUsers.isEmpty) {
        debugPrint('⚠️ No users returned from API');
        _showSnackBar('No users found in the system', false);
      }

      setState(() {
        _users = fetchedUsers;
        _applyFilters();
      });

      debugPrint('✅ Fetched ${_users.length} users');
      debugPrint('📊 First user: ${_users.isNotEmpty ? _users[0] : 'none'}');
    } catch (e) {
      debugPrint('❌ Error fetching users: $e');
      _showSnackBar('Failed to load users: $e', true);
    }
  }

  Future<void> _loadAdminsList() async {
    try {
      final admins =
          _users.where((user) {
            final role = user['role']?.toString() ?? 'user';
            return user['isAdmin'] == true ||
                user['isSuperAdmin'] == true ||
                role == 'admin' ||
                role == 'super_admin';
          }).toList();
      setState(() {
        _adminsList = admins;
      });
      debugPrint('✅ Loaded ${_adminsList.length} admins');
    } catch (e) {
      debugPrint('❌ Error loading admin list: $e');
    }
  }

  Future<void> _loadRolesAndPermissions() async {
    try {
      // Try to fetch roles from backend
      try {
        final response = await ApiService.getAllRoles();
        if (response['success'] == true) {
          final roles = response['data']?['roles'] ?? [];
          _rolesList = List<Map<String, dynamic>>.from(roles);

          // Build permissions list
          final allPermissions = <String>{};
          for (var role in _rolesList) {
            final perms = role['permissions'] as List<dynamic>? ?? [];
            for (var perm in perms) {
              if (perm != '*') {
                allPermissions.add(perm.toString());
              }
            }
          }
          _permissionsList = allPermissions.toList()..sort();

          debugPrint('✅ Loaded ${_rolesList.length} roles from backend');
          return;
        }
      } catch (e) {
        debugPrint('⚠️ Could not fetch roles from backend: $e');
      }

      // Fallback: Define roles locally
      _rolesList = [
        {
          'role': 'super_admin',
          'label': 'Super Administrator',
          'level': 5,
          'permissions': ['*'],
          'color': warningColor.value,
        },
        {
          'role': 'admin',
          'label': 'Administrator',
          'level': 4,
          'permissions': [
            'view_dashboard',
            'view_users',
            'manage_users',
            'view_transactions',
            'view_all_transactions',
            'update_transaction_status',
            'manage_admins',
            'manage_settings',
            'view_reports',
            'export_data',
            'manage_notifications',
          ],
          'color': primaryColor.value,
        },
        {
          'role': 'finance',
          'label': 'Finance Officer',
          'level': 3,
          'permissions': [
            'view_transactions',
            'view_all_transactions',
            'process_refunds',
            'view_disputes',
            'resolve_disputes',
            'view_reports',
            'view_financial_reports',
            'manage_wallet',
          ],
          'color': successColor.value,
        },
        {
          'role': 'support',
          'label': 'Support Agent',
          'level': 2,
          'permissions': [
            'view_users',
            'view_transactions',
            'view_disputes',
            'create_disputes',
            'resolve_disputes',
            'send_notifications',
            'update_user_status',
          ],
          'color': infoColor.value,
        },
        {
          'role': 'user',
          'label': 'User',
          'level': 0,
          'permissions': [
            'view_profile',
            'update_profile',
            'view_own_transactions',
            'make_transactions',
            'create_own_disputes',
            'view_own_disputes',
            'view_commission',
          ],
          'color': Colors.grey.value,
        },
      ];

      // Build permissions list from roles
      final allPermissions = <String>{};
      for (var role in _rolesList) {
        for (var perm in role['permissions'] as List<dynamic>) {
          if (perm != '*') {
            allPermissions.add(perm.toString());
          }
        }
      }
      _permissionsList = allPermissions.toList()..sort();

      debugPrint(
        '✅ Loaded ${_rolesList.length} roles and ${_permissionsList.length} permissions (fallback)',
      );
    } catch (e) {
      debugPrint('❌ Error loading roles and permissions: $e');
      _rolesList = [
        {
          'role': 'user',
          'label': 'User',
          'level': 0,
          'permissions': [],
          'color': Colors.grey.value,
        },
        {
          'role': 'admin',
          'label': 'Admin',
          'level': 4,
          'permissions': [],
          'color': primaryColor.value,
        },
        {
          'role': 'super_admin',
          'label': 'Super Admin',
          'level': 5,
          'permissions': [],
          'color': warningColor.value,
        },
      ];
      _permissionsList = [];
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredUsers =
          _users.where((user) {
            final matchesSearch =
                _searchQuery.isEmpty ||
                _matchesSearchCriteria(user, _searchQuery, _selectedSearchBy);

            // ✅ Trust backend role — not hardcoded ID
            final userRole = user['role']?.toString() ?? 'user';
            final isSuperAdmin =
                user['isSuperAdmin'] == true || userRole == 'super_admin';
            final isAdmin =
                user['isAdmin'] == true || userRole == 'admin' || isSuperAdmin;
            final isRegular = !isAdmin && !isSuperAdmin;

            bool matchesRole = true;
            switch (_selectedRole) {
              case 'admin':
                matchesRole = isAdmin && !isSuperAdmin;
                break;
              case 'super_admin':
                matchesRole = isSuperAdmin;
                break;
              case 'user':
                matchesRole = isRegular;
                break;
              default:
                matchesRole = true;
            }

            final isActive = user['isActive'] ?? true;
            bool matchesStatus = true;
            switch (_selectedStatus) {
              case 'active':
                matchesStatus = isActive;
                break;
              case 'inactive':
                matchesStatus = !isActive;
                break;
              default:
                matchesStatus = true;
            }

            bool matchesAdditionalFilter = true;
            switch (_selectedFilter) {
              case 'admins':
                matchesAdditionalFilter = isAdmin || isSuperAdmin;
                break;
              case 'regular':
                matchesAdditionalFilter = isRegular;
                break;
              default:
                matchesAdditionalFilter = true;
            }

            return matchesSearch &&
                matchesRole &&
                matchesStatus &&
                matchesAdditionalFilter;
          }).toList();
    });
  }

  bool _matchesSearchCriteria(
    Map<String, dynamic> user,
    String query,
    String searchBy,
  ) {
    switch (searchBy) {
      case 'Name':
        return user['fullName']?.toString().toLowerCase().contains(query) ??
            false;
      case 'Email':
        return user['email']?.toString().toLowerCase().contains(query) ?? false;
      case 'User ID':
        return user['_id']?.toString().toLowerCase().contains(query) ?? false;
      case 'Role':
        // ✅ Trust backend role — not hardcoded ID
        final userRoleRaw = user['role']?.toString() ?? 'user';
        final isSuperAdmin =
            user['isSuperAdmin'] == true || userRoleRaw == 'super_admin';
        final isAdmin =
            user['isAdmin'] == true || userRoleRaw == 'admin' || isSuperAdmin;
        if (query.contains('super')) return isSuperAdmin;
        if (query.contains('admin')) return isAdmin;
        if (query.contains('user')) return !isAdmin;
        return false;
      default:
        return false;
    }
  }

  // ==================== RBAC ACTIONS ====================

  Future<void> _assignRole(String userId, String role) async {
    if (_isProcessing) return;
    if (!_isSuperAdmin) {
      _showSnackBar('❌ Only Super Admin can assign roles', true);
      return;
    }

    setState(() => _isProcessing = true);
    try {
      debugPrint('🔄 Assigning role $role to user: $userId');

      final response = await ApiService.assignRole(userId, role);

      if (response['success'] == true) {
        final userIndex = _users.indexWhere(
          (user) => user['_id']?.toString() == userId,
        );
        if (userIndex != -1) {
          _users[userIndex]['role'] = role;
          _users[userIndex]['isAdmin'] =
              (role == 'admin' || role == 'super_admin');
          _users[userIndex]['isSuperAdmin'] = (role == 'super_admin');
        }

        await _loadAdminsList();
        _applyFilters();

        _showSnackBar('✅ Role assigned successfully', false);
        debugPrint('✅ Role $role assigned to user $userId');
      } else {
        throw Exception(response['message'] ?? 'Failed to assign role');
      }
    } catch (e) {
      debugPrint('❌ Error assigning role: $e');
      _showSnackBar('❌ Error: ${e.toString()}', true);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _removeRole(String userId) async {
    if (_isProcessing) return;
    if (!_isSuperAdmin) {
      _showSnackBar('❌ Only Super Admin can remove roles', true);
      return;
    }

    setState(() => _isProcessing = true);
    try {
      debugPrint('🔄 Removing role from user: $userId');

      final response = await ApiService.removeRole(userId);

      if (response['success'] == true) {
        final userIndex = _users.indexWhere(
          (user) => user['_id']?.toString() == userId,
        );
        if (userIndex != -1) {
          _users[userIndex]['role'] = 'user';
          _users[userIndex]['isAdmin'] = false;
          _users[userIndex]['isSuperAdmin'] = false;
        }

        await _loadAdminsList();
        _applyFilters();

        _showSnackBar('✅ Role removed successfully', false);
        debugPrint('✅ Role removed from user $userId');
      } else {
        throw Exception(response['message'] ?? 'Failed to remove role');
      }
    } catch (e) {
      debugPrint('❌ Error removing role: $e');
      _showSnackBar('❌ Error: ${e.toString()}', true);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _toggleUserActiveStatus(
    String userId,
    bool currentStatus,
  ) async {
    if (_isProcessing) return;
    if (!_isSuperAdmin && !_isAdmin) {
      _showSnackBar('❌ Admin access required', true);
      return;
    }

    setState(() => _isProcessing = true);
    try {
      debugPrint('🔄 Toggling user status: $userId -> ${!currentStatus}');

      await ApiService.toggleUserStatus(
        userIdToToggle: userId,
        isActive: !currentStatus,
      );

      final userIndex = _users.indexWhere(
        (user) => user['_id']?.toString() == userId,
      );
      if (userIndex != -1) {
        _users[userIndex]['isActive'] = !currentStatus;
      }

      _applyFilters();
      _showSnackBar(
        !currentStatus
            ? '✅ User activated successfully'
            : '✅ User deactivated successfully',
        false,
      );
    } catch (e) {
      debugPrint('❌ Error toggling user status: $e');
      String errorMsg = e.toString();
      if (errorMsg.contains('You cannot deactivate your own account')) {
        _showSnackBar('You cannot deactivate your own account', true);
      } else {
        _showSnackBar('❌ Error: $errorMsg', true);
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _addAdminByEmail() async {
    final email = _emailController.text.trim();

    if (!_isSuperAdmin) {
      _showSnackBar('❌ Only Super Admin can add admins', true);
      return;
    }

    if (email.isEmpty) {
      _showSnackBar('Please enter an email address', true);
      return;
    }

    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      _showSnackBar('Please enter a valid email address', true);
      return;
    }

    setState(() => _isProcessing = true);
    try {
      debugPrint('🔍 Searching for user by email: $email');

      final userIndex = _users.indexWhere(
        (user) =>
            user['email']?.toString().toLowerCase() == email.toLowerCase(),
      );

      if (userIndex == -1) {
        _showSnackBar('User with this email not found', true);
        return;
      }

      final user = _users[userIndex];
      final userId = user['_id']?.toString();

      if (userId == _superAdminId) {
        _showSnackBar('This user is already Super Admin', true);
        return;
      }

      if (user['isAdmin'] == true) {
        _showSnackBar('This user is already an admin', true);
        return;
      }

      await _assignRole(userId!, 'admin');
      _emailController.clear();
      FocusScope.of(context).unfocus();
    } catch (e) {
      debugPrint('❌ Error adding admin: $e');
      _showSnackBar('❌ Error: ${e.toString()}', true);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // ==================== UI HELPERS ====================

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
        backgroundColor: isError ? errorColor : secondaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(16),
      ),
    );
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

  String _getRoleLabel(String role) {
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

  void _showUserDetails(Map<String, dynamic> user) {
    final isSuperAdmin = user['_id']?.toString() == _superAdminId;
    final isAdmin = user['isAdmin'] == true;
    final isActive = user['isActive'] ?? true;
    final userId = user['_id']?.toString() ?? '';
    final userRole =
        user['role'] ??
        (isSuperAdmin
            ? 'super_admin'
            : isAdmin
            ? 'admin'
            : 'user');
    final isCurrentUser = userId == _currentUserId;
    final roleColor = _getRoleColor(userRole);

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isSuperAdmin
                        ? Icons.star
                        : isAdmin
                        ? Icons.admin_panel_settings
                        : Icons.person,
                    color: roleColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    user['fullName']?.toString() ?? 'User Details',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
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
                _buildDetailRow('📧 Email', user['email']?.toString() ?? 'N/A'),
                const SizedBox(height: 8),
                _buildDetailRow('🆔 User ID', userId),
                const SizedBox(height: 8),
                _buildDetailRow('👤 Role', _getRoleLabel(userRole)),
                const SizedBox(height: 8),
                _buildDetailRow(
                  '📊 Status',
                  isActive ? 'Active ✅' : 'Inactive ❌',
                ),
                const SizedBox(height: 8),
                _buildDetailRow(
                  '🔑 Permissions',
                  '${(user['permissions'] as List?)?.length ?? 0} permissions',
                ),
                if (user['createdAt'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildDetailRow(
                      '📅 Created',
                      DateFormat(
                        'MMM dd, yyyy HH:mm',
                      ).format(DateTime.parse(user['createdAt'])),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Close',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ),
              if (_isSuperAdmin && !isCurrentUser) ...[
                const SizedBox(width: 4),
                // Role dropdown
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: userRole,
                      icon: const Icon(Icons.arrow_drop_down),
                      items:
                          _rolesList.map((role) {
                            final isSelected = role['role'] == userRole;
                            dynamic roleColor = role['color'];
                            Color color;
                            if (roleColor is int) {
                              color = Color(roleColor);
                            } else if (roleColor is Color) {
                              color = roleColor;
                            } else {
                              color = primaryColor;
                            }
                            return DropdownMenuItem<String>(
                              value: role['role'],
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    role['label'],
                                    style: GoogleFonts.inter(
                                      fontWeight:
                                          isSelected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                      color:
                                          isSelected
                                              ? primaryColor
                                              : textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                      onChanged: (newRole) {
                        if (newRole != null && newRole != userRole) {
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
                          _assignRole(userId, newRole);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Activate/Deactivate
                ElevatedButton(
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
                    _toggleUserActiveStatus(userId, isActive);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isActive ? errorColor : successColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  child: Text(
                    isActive ? 'Deactivate' : 'Activate',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
          ),
        ),
      ],
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
                      style: GoogleFonts.inter(
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
                      style: GoogleFonts.inter(
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

  // ==================== UI BUILDERS ====================

  Widget _buildAdminHeader() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 16 : 20,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF5BB592), Color(0xFF102C68)],
          stops: [0.06, 0.41],
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
                  'Admin / Control',
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
                  Icons.admin_panel_settings_rounded,
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
                      'Admin Control',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: isMobile ? 20 : 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: isMobile ? 4 : 6),
                    Text(
                      'RBAC - Manage roles & permissions',
                      style: GoogleFonts.inter(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: isMobile ? 12 : 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loadInitialData,
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
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    final totalUsers = _users.length;
    // ✅ Trust backend role — not hardcoded ID
    final superAdminCount =
        _users.where((u) {
          final role = u['role']?.toString() ?? 'user';
          return u['isSuperAdmin'] == true || role == 'super_admin';
        }).length;

    final adminUsers =
        _users.where((u) {
          final role = u['role']?.toString() ?? 'user';
          final isSuper = u['isSuperAdmin'] == true || role == 'super_admin';
          final isAdmin = u['isAdmin'] == true || role == 'admin' || isSuper;
          // Regular admin (not super admin)
          return isAdmin && !isSuper;
        }).length;

    final activeUsers = _users.where((u) => u['isActive'] == true).length;
    final regularUsers = totalUsers - adminUsers - superAdminCount;

    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 8 : 12,
      ),
      child: Wrap(
        spacing: isMobile ? 8 : 12,
        runSpacing: isMobile ? 8 : 12,
        children: [
          _buildStatCard(
            title: 'Total Users',
            value: totalUsers.toString(),
            icon: HugeIcons.strokeRoundedUser,
            color: primaryColor,
            isMobile: isMobile,
          ),
          _buildStatCard(
            title: 'Super Admin',
            value: superAdminCount.toString(),
            icon: HugeIcons.strokeRoundedStar,
            color: warningColor,
            isMobile: isMobile,
          ),
          _buildStatCard(
            title: 'Admins',
            value: adminUsers.toString(),
            icon: HugeIcons.strokeRoundedUserCheck01,
            color: successColor,
            isMobile: isMobile,
          ),
          _buildStatCard(
            title: 'Regular Users',
            value: regularUsers.toString(),
            icon: HugeIcons.strokeRoundedUser,
            color: infoColor,
            isMobile: isMobile,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required dynamic icon,
    required Color color,
    required bool isMobile,
  }) {
    final cardWidth =
        isMobile
            ? (MediaQuery.of(context).size.width - 48) / 2
            : (MediaQuery.of(context).size.width - 72) / 4;

    return SizedBox(
      width: cardWidth,
      child: Container(
        padding: EdgeInsets.all(isMobile ? 12 : 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
          border: Border.all(color: color.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 6 : 8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: HugeIcon(
                icon: icon,
                color: color,
                size: isMobile ? 16 : 20,
              ),
            ),
            SizedBox(width: isMobile ? 8 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 16 : 20,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 9 : 11,
                      color: textSecondary,
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
    );
  }

  Widget _buildSearchAndFilters() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 8),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search users...',
              hintStyle: GoogleFonts.inter(
                fontSize: isMobile ? 13 : 14,
                color: Colors.grey.shade400,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: primaryColor,
                size: isMobile ? 20 : 22,
              ),
              suffixIcon:
                  _searchController.text.isNotEmpty
                      ? IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.grey.shade400,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _searchQuery = '';
                          _applyFilters();
                        },
                      )
                      : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: primaryColor, width: 1.5),
              ),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 16,
                vertical: isMobile ? 12 : 14,
              ),
            ),
            style: GoogleFonts.inter(
              fontSize: isMobile ? 14 : 15,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children:
                _searchOptions.map((option) {
                  return FilterChip(
                    label: Text(
                      option,
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 10 : 11,
                        fontWeight:
                            _selectedSearchBy == option
                                ? FontWeight.w600
                                : FontWeight.w500,
                        color:
                            _selectedSearchBy == option
                                ? Colors.white
                                : textSecondary,
                      ),
                    ),
                    selected: _selectedSearchBy == option,
                    onSelected: (selected) {
                      setState(() {
                        _selectedSearchBy = option;
                        _applyFilters();
                      });
                    },
                    backgroundColor: Colors.white,
                    selectedColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color:
                            _selectedSearchBy == option
                                ? primaryColor
                                : Colors.grey.shade300,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterDropdown(
                  value: _selectedRole,
                  options: ['all', 'admin', 'super_admin', 'user'],
                  icon: HugeIcons.strokeRoundedUserAccount,
                  label: 'Role',
                  onChanged: (value) {
                    setState(() {
                      _selectedRole = value!;
                      _applyFilters();
                    });
                  },
                  isMobile: isMobile,
                ),
                const SizedBox(width: 8),
                _buildFilterDropdown(
                  value: _selectedStatus,
                  options: ['all', 'active', 'inactive'],
                  icon: HugeIcons.strokeRoundedStatus,
                  label: 'Status',
                  onChanged: (value) {
                    setState(() {
                      _selectedStatus = value!;
                      _applyFilters();
                    });
                  },
                  isMobile: isMobile,
                ),
                const SizedBox(width: 8),
                _buildFilterChip('All Users', 'all', isMobile),
                const SizedBox(width: 6),
                _buildFilterChip('Admins', 'admins', isMobile),
                const SizedBox(width: 6),
                _buildFilterChip('Regular', 'regular', isMobile),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String value,
    required List<String> options,
    required dynamic icon,
    required String label,
    required ValueChanged<String?> onChanged,
    required bool isMobile,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: Icon(Icons.arrow_drop_down, color: primaryColor),
          items:
              options.map((option) {
                return DropdownMenuItem<String>(
                  value: option,
                  child: Row(
                    children: [
                      HugeIcon(
                        icon: icon,
                        color: primaryColor,
                        size: isMobile ? 14 : 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        option == 'all'
                            ? 'All'
                            : option.replaceAll('_', ' ').toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 10 : 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, bool isMobile) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: isMobile ? 10 : 11,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          color: isSelected ? Colors.white : textSecondary,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = selected ? value : 'all';
          _applyFilters();
        });
      },
      backgroundColor: Colors.white,
      selectedColor: primaryColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? primaryColor : Colors.grey.shade300,
        ),
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildAdminListSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 8),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedUserShield01,
                color: primaryColor,
                size: isMobile ? 18 : 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Admin Users (${_adminsList.length})',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const Spacer(),
              if (_isSuperAdmin)
                Tooltip(
                  message: 'Refresh admins list',
                  child: IconButton(
                    icon: Icon(Icons.refresh_rounded, size: isMobile ? 18 : 20),
                    onPressed: _loadAdminsList,
                    color: textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_adminsList.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedUserShield01,
                      color: Colors.grey.shade300,
                      size: 40,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No Admin Users',
                      style: GoogleFonts.inter(
                        color: textSecondary,
                        fontSize: isMobile ? 13 : 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: isMobile ? 140 : 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _adminsList.length,
                itemBuilder: (context, index) {
                  final admin = _adminsList[index];
                  final isSuperAdmin =
                      admin['_id']?.toString() == _superAdminId;
                  final isActive = admin['isActive'] ?? true;
                  final role =
                      admin['role'] ?? (isSuperAdmin ? 'super_admin' : 'admin');
                  final roleColor = _getRoleColor(role);

                  return Container(
                    width: isMobile ? 170 : 200,
                    margin: EdgeInsets.only(
                      right: index == _adminsList.length - 1 ? 0 : 12,
                    ),
                    padding: EdgeInsets.all(isMobile ? 10 : 12),
                    decoration: BoxDecoration(
                      color: backgroundLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            isSuperAdmin
                                ? warningColor.withOpacity(0.3)
                                : primaryColor.withOpacity(0.15),
                        width: isSuperAdmin ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: isMobile ? 14 : 16,
                              backgroundColor:
                                  isSuperAdmin
                                      ? warningColor.withOpacity(0.1)
                                      : roleColor.withOpacity(0.1),
                              child: Icon(
                                isSuperAdmin
                                    ? Icons.star
                                    : Icons.admin_panel_settings,
                                size: isMobile ? 14 : 16,
                                color: isSuperAdmin ? warningColor : roleColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    admin['fullName']?.toString() ?? 'Unknown',
                                    style: GoogleFonts.inter(
                                      fontSize: isMobile ? 11 : 12,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    _getRoleLabel(role),
                                    style: GoogleFonts.inter(
                                      fontSize: isMobile ? 9 : 10,
                                      color: roleColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    isActive
                                        ? successColor.withOpacity(0.1)
                                        : errorColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isActive ? 'Active' : 'Inactive',
                                style: GoogleFonts.inter(
                                  fontSize: isMobile ? 8 : 9,
                                  color: isActive ? successColor : errorColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              admin['email']?.toString().split('@').first ??
                                  'No email',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 8 : 9,
                                color: textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
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
  }

  Widget _buildAddAdminSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 8),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedUserAdd01,
                color: primaryColor,
                size: isMobile ? 18 : 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Add User as Admin',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'By Email Address',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 11 : 12,
                        fontWeight: FontWeight.w600,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        hintText: 'Enter user email',
                        hintStyle: GoogleFonts.inter(
                          fontSize: isMobile ? 13 : 14,
                          color: Colors.grey.shade400,
                        ),
                        prefixIcon: Icon(
                          Icons.email_outlined,
                          color: primaryColor,
                          size: isMobile ? 18 : 20,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: primaryColor,
                            width: 1.5,
                          ),
                        ),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 12 : 14,
                          vertical: isMobile ? 10 : 12,
                        ),
                      ),
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 14 : 15,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: isMobile ? 60 : 70,
                height: isMobile ? 46 : 50,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _addAdminByEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  child:
                      _isProcessing
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                          : HugeIcon(
                            icon: HugeIcons.strokeRoundedUserAdd01,
                            color: Colors.white,
                            size: isMobile ? 20 : 24,
                          ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserList() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 8),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedUserGroup,
                color: primaryColor,
                size: isMobile ? 18 : 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Users (${_filteredUsers.length})',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_filteredUsers.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    HugeIcon(
                      icon:
                          _users.isEmpty
                              ? HugeIcons.strokeRoundedUserGroup
                              : HugeIcons.strokeRoundedSearch01,
                      color: Colors.grey.shade300,
                      size: 40,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _users.isEmpty ? 'No users found' : 'No matching users',
                      style: GoogleFonts.inter(
                        color: textSecondary,
                        fontSize: isMobile ? 13 : 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _filteredUsers.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final user = _filteredUsers[index];
                final userId = user['_id']?.toString() ?? '';
                final isUserAdmin = user['isAdmin'] == true;
                final isActive = user['isActive'] ?? true;
                final isCurrentUser = userId == _currentUserId;
                // ✅ Trust backend role — not hardcoded ID
                final storedRole = user['role']?.toString() ?? 'user';
                final isSuperAdmin =
                    user['isSuperAdmin'] == true || storedRole == 'super_admin';
                final userRole =
                    isSuperAdmin
                        ? 'super_admin'
                        : (isUserAdmin ? 'admin' : 'user');
                final roleColor = _getRoleColor(userRole);

                return InkWell(
                  onTap: () => _showUserDetails(user),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: isMobile ? 8 : 10),
                    child: Row(
                      children: [
                        Container(
                          width: isMobile ? 36 : 40,
                          height: isMobile ? 36 : 40,
                          decoration: BoxDecoration(
                            color: roleColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isSuperAdmin
                                ? Icons.star
                                : isUserAdmin
                                ? Icons.admin_panel_settings
                                : Icons.person,
                            color: roleColor,
                            size: isMobile ? 16 : 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      user['fullName']?.toString() ?? 'Unknown',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                        fontSize: isMobile ? 13 : 14,
                                        color: textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isCurrentUser)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: infoColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'You',
                                        style: GoogleFonts.inter(
                                          fontSize: isMobile ? 8 : 9,
                                          fontWeight: FontWeight.w600,
                                          color: infoColor,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              Text(
                                user['email']?.toString() ?? 'No email',
                                style: GoogleFonts.inter(
                                  fontSize: isMobile ? 11 : 12,
                                  color: textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Wrap(
                                spacing: 4,
                                runSpacing: 2,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: roleColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: roleColor.withOpacity(0.2),
                                      ),
                                    ),
                                    child: Text(
                                      _getRoleLabel(userRole),
                                      style: GoogleFonts.inter(
                                        fontSize: isMobile ? 8 : 9,
                                        fontWeight: FontWeight.w600,
                                        color: roleColor,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          isActive
                                              ? successColor.withOpacity(0.1)
                                              : errorColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isActive ? 'Active' : 'Inactive',
                                      style: GoogleFonts.inter(
                                        fontSize: isMobile ? 8 : 9,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            isActive
                                                ? successColor
                                                : errorColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (_isSuperAdmin && !isCurrentUser)
                          Row(
                            children: [
                              // Role dropdown
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: userRole,
                                    icon: Icon(
                                      Icons.arrow_drop_down,
                                      color: primaryColor,
                                      size: isMobile ? 18 : 20,
                                    ),
                                    items:
                                        _rolesList.map((role) {
                                          final isSelected =
                                              role['role'] == userRole;
                                          dynamic roleColor = role['color'];
                                          Color color;
                                          if (roleColor is int) {
                                            color = Color(roleColor);
                                          } else if (roleColor is Color) {
                                            color = roleColor;
                                          } else {
                                            color = primaryColor;
                                          }
                                          return DropdownMenuItem<String>(
                                            value: role['role'],
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration: BoxDecoration(
                                                    color: color,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  role['label'],
                                                  style: GoogleFonts.inter(
                                                    fontSize:
                                                        isMobile ? 10 : 11,
                                                    fontWeight:
                                                        isSelected
                                                            ? FontWeight.w600
                                                            : FontWeight.w400,
                                                    color:
                                                        isSelected
                                                            ? primaryColor
                                                            : textPrimary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                    onChanged: (newRole) {
                                      if (newRole != null &&
                                          newRole != userRole) {
                                        _assignRole(userId, newRole);
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Activate/Deactivate
                              IconButton(
                                icon: Icon(
                                  isActive
                                      ? Icons.block_outlined
                                      : Icons.check_circle_outline,
                                  color: isActive ? errorColor : successColor,
                                  size: isMobile ? 18 : 20,
                                ),
                                onPressed:
                                    _isProcessing
                                        ? null
                                        : () => _toggleUserActiveStatus(
                                          userId,
                                          isActive,
                                        ),
                                tooltip: isActive ? 'Deactivate' : 'Activate',
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ==================== MAIN BUILD ====================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading admin control panel...',
                style: GoogleFonts.inter(fontSize: 14, color: textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.grey.shade50,
      drawer: CustomDrawer(
        header: _buildDrawerHeader(),
        items: _drawerItems,
        selectedItem: _drawerItems.firstWhere(
          (item) => item.title == "Admin Control",
          orElse: () => _drawerItems.first,
        ),
        onItemSelected: _onDrawerItemSelected,
        isAdmin: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _buildAdminHeader(),
                  _buildStatsSection(),
                  _buildSearchAndFilters(),
                  _buildAdminListSection(),
                  if (_isSuperAdmin) _buildAddAdminSection(),
                  _buildUserList(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
            if (_isProcessing)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Processing...',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
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
    );
  }
}
