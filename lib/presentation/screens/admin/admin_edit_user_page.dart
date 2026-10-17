// lib/presentation/screens/admin/admin_edit_user_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';
import '../dashboard/dashboard_screen.dart';

class AdminEditUserPage extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback onUserUpdated;

  const AdminEditUserPage({
    super.key,
    required this.user,
    required this.onUserUpdated,
  });

  @override
  State<AdminEditUserPage> createState() => _AdminEditUserPageState();
}

class _AdminEditUserPageState extends State<AdminEditUserPage>
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
  static const String _superAdminId = "690088325ca99bed6ab8d4a5";

  // ==================== CONTROLLERS ====================
  late TextEditingController _fullNameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _walletBalanceController;

  // ==================== STATE ====================
  bool _isLoading = false;
  bool _isAdmin = false;
  bool _isSuperAdmin = false;
  bool _isCheckingAdmin = true;
  bool _isActive = true;
  bool _isAdminUser = false;
  bool _isCurrentUser = false;
  String? _errorMessage;
  String _adminName = '';
  String _userId = '';
  bool _isReadOnly =
      false; // Default to editable (will be set after role check)

  // PIN Management State
  bool _showPinManagement = false;
  bool _isPinLoading = false;
  Map<String, dynamic>? _pinStatusData;

  // ==================== ANIMATION ====================
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeControllers();
    _loadAdminData();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _walletBalanceController.dispose();
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
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
  }

  void _initializeControllers() {
    _fullNameController = TextEditingController(
      text: widget.user['fullName'] ?? '',
    );
    _emailController = TextEditingController(text: widget.user['email'] ?? '');
    _phoneController = TextEditingController(text: widget.user['phone'] ?? '');
    _walletBalanceController = TextEditingController(
      text: (widget.user['walletBalance'] ?? 0.0).toStringAsFixed(2),
    );

    _isActive = widget.user['isActive'] ?? true;
    _isAdminUser = widget.user['isAdmin'] ?? false;
    _userId = widget.user['_id'] ?? '';
  }

  // ==================== DATA LOADING ====================

  Future<void> _loadAdminData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user');

      if (userDataString != null) {
        final userData = jsonDecode(userDataString);

        // Get fresh user role from RBAC API
        try {
          final roleResult = await ApiService.getUserRole();
          debugPrint('🔍 Role API Response: $roleResult');

          if (roleResult['success'] == true) {
            final data = roleResult['data'];
            final userRole = data?['role'] ?? 'user';

            // CRITICAL FIX: Properly check for Super Admin
            // ✅ Trust backend only — no hardcoded ID
            final bool isSuperAdmin =
                data?['isSuperAdmin'] == true ||
                userRole == 'super_admin' ||
                userRole == 'superadmin';

            final bool isAdmin =
                data?['isAdmin'] == true ||
                userRole == 'admin' ||
                userRole == 'super_admin' ||
                userRole == 'superadmin' ||
                isSuperAdmin;

            final bool isCurrentUser = userData['_id'] == _userId;

            debugPrint('👤 User Role: $userRole');
            debugPrint('⭐ Is Super Admin: $isSuperAdmin');
            debugPrint('🔑 Is Admin: $isAdmin');

            setState(() {
              _isAdmin = isAdmin;
              _isSuperAdmin = isSuperAdmin;
              _adminName = userData['fullName'] ?? 'Admin';
              _isCurrentUser = isCurrentUser;
              _isCheckingAdmin = false;
              // SUPER ADMIN CAN EDIT - only Super Admin gets edit access
              _isReadOnly = !isSuperAdmin;
            });

            if (_isAdmin) {
              _animationController.forward();
            } else {
              setState(() {
                _errorMessage =
                    "You don't have permission to access this page.";
              });
            }
            return;
          }
        } catch (e) {
          debugPrint('⚠️ Could not fetch role from backend: $e');
        }

        // ✅ Fallback to stored role — no hardcoded ID
        final String? userId = userData['_id'];
        final storedRole = userData['role']?.toString() ?? 'user';
        final bool isSuperAdmin =
            userData['isSuperAdmin'] == true || storedRole == 'super_admin';
        final bool isAdmin =
            userData['isAdmin'] == true ||
            storedRole == 'admin' ||
            isSuperAdmin;
        final bool isCurrentUser = userId == _userId;

        debugPrint('⭐ Fallback - Is Super Admin: $isSuperAdmin');

        setState(() {
          _isAdmin = isAdmin;
          _isSuperAdmin = isSuperAdmin;
          _adminName = userData['fullName'] ?? 'Admin';
          _isCurrentUser = isCurrentUser;
          _isCheckingAdmin = false;
          // SUPER ADMIN CAN EDIT
          _isReadOnly = !isSuperAdmin;
        });

        if (_isAdmin) {
          _animationController.forward();
        } else {
          setState(() {
            _errorMessage = "You don't have permission to access this page.";
          });
        }
      } else {
        setState(() {
          _isCheckingAdmin = false;
          _errorMessage = "User data not found. Please log in again.";
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading admin data: $e');
      setState(() {
        _isCheckingAdmin = false;
        _errorMessage = "Error loading admin data: ${e.toString()}";
      });
    }
  }

  // ==================== UPDATE USER ====================

  Future<void> _updateUser() async {
    // Double-check: Only Super Admin can update
    if (!_isSuperAdmin) {
      _showAccessDeniedMessage();
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService.updateUserProfile(
        userId: _userId,
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        walletBalance:
            double.tryParse(_walletBalanceController.text.trim()) ?? 0.0,
        isActive: _isActive,
        isAdminStatus: _isAdminUser,
        isAdmin: _isAdmin,
      );

      if (response['success'] == true) {
        _showSnackBar("✅ User updated successfully!", false);
        widget.onUserUpdated();

        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
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
        }
      } else {
        _showSnackBar(response['message'] ?? "Failed to update user.", true);
      }
    } catch (e) {
      if (e.toString().contains('Admin access required')) {
        _showSnackBar(
          "You don't have permission to perform this action.",
          true,
        );
        setState(() {
          _isAdmin = false;
          _isSuperAdmin = false;
        });
      } else {
        _showSnackBar("Error: ${e.toString()}", true);
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ==================== ACCESS DENIED ====================

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
                  style: GoogleFonts.poppins(
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
                  'Only Super Administrators can edit user details.',
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
                          'This page is in read-only mode for normal admins. Please contact the Super Administrator for edit access.',
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

  // ==================== PIN MANAGEMENT ====================

  Future<void> _checkPinStatus() async {
    if (!_isSuperAdmin) {
      _showAccessDeniedMessage();
      return;
    }

    setState(() {
      _isPinLoading = true;
      _pinStatusData = null;
    });

    try {
      final response = await ApiService.adminCheckPinStatus(userId: _userId);

      if (response['success'] == true) {
        setState(() {
          _pinStatusData = response;
        });
        _showSnackBar("✅ PIN status retrieved successfully", false);
      } else {
        _showSnackBar(
          response['message'] ?? "Failed to check PIN status",
          true,
        );
      }
    } catch (e) {
      _showSnackBar("Error: ${e.toString()}", true);
    } finally {
      setState(() {
        _isPinLoading = false;
      });
    }
  }

  Future<void> _unlockPin() async {
    if (!_isSuperAdmin) {
      _showAccessDeniedMessage();
      return;
    }

    final confirm = await _showConfirmDialog(
      title: 'Unlock PIN?',
      message:
          'This will reset failed attempts and unlock the PIN for ${widget.user['fullName'] ?? 'this user'}.',
      confirmText: 'Unlock',
      confirmColor: Colors.orange,
    );

    if (confirm != true) return;

    setState(() {
      _isPinLoading = true;
    });

    try {
      final response = await ApiService.adminUnlockPin(userId: _userId);

      if (response['success'] == true) {
        _showSnackBar("✅ PIN unlocked successfully!", false);
        await _checkPinStatus();
      } else {
        _showSnackBar(response['message'] ?? "Failed to unlock PIN", true);
      }
    } catch (e) {
      _showSnackBar("Error: ${e.toString()}", true);
    } finally {
      setState(() {
        _isPinLoading = false;
      });
    }
  }

  Future<void> _resetPin() async {
    if (!_isSuperAdmin) {
      _showAccessDeniedMessage();
      return;
    }

    final confirm = await _showConfirmDialog(
      title: 'Reset PIN to Default?',
      message:
          'This will reset the PIN to default (123456) for ${widget.user['fullName'] ?? 'this user'}. They will need to change it on next login.',
      confirmText: 'Reset',
      confirmColor: Colors.red,
    );

    if (confirm != true) return;

    setState(() {
      _isPinLoading = true;
    });

    try {
      final response = await ApiService.adminResetPin(userId: _userId);

      if (response['success'] == true) {
        _showSnackBar("✅ PIN reset to default (123456) successfully!", false);
        await _checkPinStatus();
      } else {
        _showSnackBar(response['message'] ?? "Failed to reset PIN", true);
      }
    } catch (e) {
      _showSnackBar("Error: ${e.toString()}", true);
    } finally {
      setState(() {
        _isPinLoading = false;
      });
    }
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
        backgroundColor: isError ? errorColor : secondaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(16),
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
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
            content: Text(
              message,
              style: GoogleFonts.inter(color: textSecondary),
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
      return DateFormat('MMM dd, yyyy').format(date);
    }
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

  // ==================== UI BUILDERS ====================

  Widget _buildAdminHeader() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final userName = widget.user['fullName'] ?? 'User';

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
                  _isSuperAdmin
                      ? 'Admin / Users / Edit'
                      : 'Admin / Users / View',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.7),
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
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                    style: GoogleFonts.poppins(
                      color: primaryColor,
                      fontSize: isMobile ? 24 : 30,
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
                    Text(
                      _isSuperAdmin
                          ? 'Edit User Profile'
                          : 'User Profile (Read-Only)',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: isMobile ? 20 : 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: isMobile ? 4 : 6),
                    Text(
                      userName,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: isMobile ? 14 : 16,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (_isCurrentUser)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 8 : 12,
                    vertical: isMobile ? 4 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: warningColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: warningColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_rounded,
                        color: warningColor,
                        size: isMobile ? 12 : 14,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'You',
                        style: GoogleFonts.inter(
                          color: warningColor,
                          fontSize: isMobile ? 9 : 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: isMobile ? 16 : 20),
          Container(
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoItem(
                  icon: Icons.email_rounded,
                  label: 'Email',
                  value: widget.user['email']?.toString() ?? 'N/A',
                  isMobile: isMobile,
                ),
                _buildInfoItem(
                  icon: Icons.phone_rounded,
                  label: 'Phone',
                  value: widget.user['phone']?.toString() ?? 'N/A',
                  isMobile: isMobile,
                ),
                _buildInfoItem(
                  icon: Icons.calendar_today_rounded,
                  label: 'Joined',
                  value:
                      widget.user['createdAt'] != null
                          ? _formatDate(
                            DateTime.parse(widget.user['createdAt'].toString()),
                          )
                          : 'N/A',
                  isMobile: isMobile,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
    required bool isMobile,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.8),
          size: isMobile ? 16 : 18,
        ),
        SizedBox(height: isMobile ? 2 : 4),
        Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: isMobile ? 8 : 10,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: isMobile ? 10 : 12,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildAdminStatusCard() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (_isSuperAdmin) {
      return Container(
        margin: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 24,
          vertical: 8,
        ),
        padding: EdgeInsets.all(isMobile ? 14 : 18),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
          border: Border.all(color: Colors.amber.shade200, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 8 : 10),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.admin_panel_settings_rounded,
                color: Colors.amber.shade700,
                size: isMobile ? 20 : 24,
              ),
            ),
            SizedBox(width: isMobile ? 12 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Super Admin Mode - Full Edit Access',
                    style: GoogleFonts.inter(
                      color: Colors.amber.shade800,
                      fontSize: isMobile ? 14 : 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'You have full edit permissions for this user',
                    style: GoogleFonts.inter(
                      color: Colors.amber.shade700,
                      fontSize: isMobile ? 11 : 13,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 8 : 12,
                vertical: isMobile ? 4 : 6,
              ),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '✅ EDIT',
                style: GoogleFonts.inter(
                  color: Colors.amber.shade700,
                  fontSize: isMobile ? 8 : 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Read-only mode card for normal admins
      return Container(
        margin: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 24,
          vertical: 8,
        ),
        padding: EdgeInsets.all(isMobile ? 14 : 18),
        decoration: BoxDecoration(
          color: warningColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(isMobile ? 14 : 16),
          border: Border.all(
            color: warningColor.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 8 : 10),
              decoration: BoxDecoration(
                color: warningColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                color: warningColor,
                size: isMobile ? 20 : 24,
              ),
            ),
            SizedBox(width: isMobile ? 12 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Read-Only Mode',
                    style: GoogleFonts.inter(
                      color: warningColor,
                      fontSize: isMobile ? 14 : 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'You are viewing this profile in read-only mode. Contact Super Admin to edit.',
                    style: GoogleFonts.inter(
                      color: warningColor.withValues(alpha: 0.8),
                      fontSize: isMobile ? 11 : 13,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 8 : 12,
                vertical: isMobile ? 4 : 6,
              ),
              decoration: BoxDecoration(
                color: warningColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '🔒 VIEW ONLY',
                style: GoogleFonts.inter(
                  color: warningColor,
                  fontSize: isMobile ? 8 : 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildEditForm() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final bool isEditable = _isSuperAdmin;

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(position: _slideAnimation, child: child),
        );
      },
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 24,
          vertical: 8,
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
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(isMobile ? 8 : 10),
                    decoration: BoxDecoration(
                      color:
                          isEditable
                              ? primaryColor.withValues(alpha: 0.08)
                              : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: HugeIcon(
                      icon:
                          isEditable
                              ? HugeIcons.strokeRoundedUserEdit01
                              : HugeIcons.strokeRoundedUser,
                      color: isEditable ? primaryColor : Colors.grey.shade500,
                      size: isMobile ? 20 : 24,
                    ),
                  ),
                  SizedBox(width: isMobile ? 10 : 14),
                  Text(
                    isEditable
                        ? 'User Information'
                        : 'User Information (Read-Only)',
                    style: GoogleFonts.poppins(
                      fontSize: isMobile ? 16 : 18,
                      fontWeight: FontWeight.w600,
                      color: isEditable ? textPrimary : Colors.grey.shade600,
                    ),
                  ),
                  if (!isEditable)
                    Container(
                      margin: EdgeInsets.only(left: 10),
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 6 : 10,
                        vertical: isMobile ? 2 : 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '🔒 Locked',
                        style: GoogleFonts.inter(
                          fontSize: isMobile ? 8 : 10,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: isMobile ? 16 : 20),

              // ==================== READ-ONLY INFO MESSAGE ====================
              if (!isEditable)
                Container(
                  padding: EdgeInsets.all(isMobile ? 12 : 14),
                  margin: EdgeInsets.only(bottom: isMobile ? 16 : 20),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Colors.blue.shade700,
                        size: isMobile ? 20 : 24,
                      ),
                      SizedBox(width: isMobile ? 10 : 14),
                      Expanded(
                        child: Text(
                          'This profile is in read-only mode. Contact the Super Administrator to make changes.',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 12 : 14,
                            color: Colors.blue.shade700,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              _buildFormField(
                controller: _fullNameController,
                label: 'Full Name',
                hint: 'Enter user\'s full name',
                icon: HugeIcons.strokeRoundedUser,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Full name is required';
                  }
                  return null;
                },
                isMobile: isMobile,
                readOnly: !isEditable,
              ),
              SizedBox(height: isMobile ? 12 : 14),
              _buildFormField(
                controller: _emailController,
                label: 'Email Address',
                hint: 'Enter user\'s email',
                icon: HugeIcons.strokeRoundedMail01,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Email is required';
                  }
                  if (!value.contains('@') || !value.contains('.')) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
                isMobile: isMobile,
                readOnly: !isEditable,
              ),
              SizedBox(height: isMobile ? 12 : 14),
              _buildFormField(
                controller: _phoneController,
                label: 'Phone Number',
                hint: 'Enter user\'s phone number',
                icon: HugeIcons.strokeRoundedCall,
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Phone number is required';
                  }
                  return null;
                },
                isMobile: isMobile,
                readOnly: !isEditable,
              ),
              SizedBox(height: isMobile ? 12 : 14),
              _buildFormField(
                controller: _walletBalanceController,
                label: 'Wallet Balance (₦)',
                hint: 'Enter wallet balance',
                icon: HugeIcons.strokeRoundedWallet01,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Balance is required';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Enter a valid amount';
                  }
                  return null;
                },
                isMobile: isMobile,
                readOnly: !isEditable,
              ),
              SizedBox(height: isMobile ? 20 : 24),

              // Account Controls
              Container(
                padding: EdgeInsets.all(isMobile ? 14 : 18),
                decoration: BoxDecoration(
                  color: backgroundLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        isEditable
                            ? Colors.grey.shade200
                            : Colors.grey.shade300,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isEditable
                              ? Icons.settings_outlined
                              : Icons.settings_outlined,
                          color:
                              isEditable ? primaryColor : Colors.grey.shade500,
                          size: isMobile ? 18 : 20,
                        ),
                        SizedBox(width: isMobile ? 8 : 10),
                        Text(
                          'Account Controls',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 14 : 16,
                            fontWeight: FontWeight.w600,
                            color:
                                isEditable ? textPrimary : Colors.grey.shade600,
                          ),
                        ),
                        if (!isEditable)
                          Container(
                            margin: EdgeInsets.only(left: 8),
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 6 : 10,
                              vertical: isMobile ? 2 : 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'LOCKED',
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 8 : 10,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: isMobile ? 12 : 14),

                    _buildToggleSwitch(
                      title: 'Account Status',
                      subtitle:
                          _isActive
                              ? 'User can access the system'
                              : 'User account is disabled',
                      value: _isActive,
                      onChanged:
                          isEditable
                              ? (value) {
                                setState(() {
                                  _isActive = value;
                                });
                              }
                              : null,
                      activeColor: successColor,
                      icon: Icons.check_circle_rounded,
                      isMobile: isMobile,
                      readOnly: !isEditable,
                    ),
                    Divider(
                      height: isMobile ? 24 : 30,
                      thickness: 1,
                      color: Colors.grey.shade200,
                    ),
                    _buildToggleSwitch(
                      title: 'Admin Privileges',
                      subtitle:
                          _isAdminUser
                              ? 'User has admin access'
                              : 'User has regular access',
                      value: _isAdminUser,
                      onChanged:
                          isEditable
                              ? (value) {
                                if (_isCurrentUser && !value) {
                                  _showSnackBar(
                                    "You cannot remove your own admin status.",
                                    true,
                                  );
                                  return;
                                }
                                // ✅ Prevent removing the LAST super admin
                                // (check the user being edited, not hardcoded ID)
                                final targetIsSuperAdmin =
                                    widget.user['isSuperAdmin'] == true ||
                                    widget.user['role']?.toString() ==
                                        'super_admin';
                                if (targetIsSuperAdmin && !value) {
                                  _showSnackBar(
                                    "This user's super admin status cannot be revoked.",
                                    true,
                                  );
                                  return;
                                }
                                setState(() {
                                  _isAdminUser = value;
                                });
                              }
                              : null,
                      activeColor: primaryColor,
                      icon: Icons.admin_panel_settings_rounded,
                      isMobile: isMobile,
                      readOnly: !isEditable,
                    ),
                  ],
                ),
              ),
              SizedBox(height: isMobile ? 16 : 20),

              // ==================== PIN MANAGEMENT SECTION ====================
              if (isEditable)
                _buildPinManagementSection(isMobile)
              else
                _buildReadOnlyPinSection(isMobile),

              SizedBox(height: isMobile ? 16 : 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: Text(
                        'Close',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          vertical: isMobile ? 10 : 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: BorderSide(
                          color:
                              isEditable ? Colors.grey.shade300 : primaryColor,
                        ),
                      ),
                    ),
                  ),
                  if (isEditable) ...[
                    SizedBox(width: isMobile ? 8 : 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _updateUser,
                        icon:
                            _isLoading
                                ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Icon(Icons.save_rounded, size: 18),
                        label: Text(
                          _isLoading ? 'Saving...' : 'Save Changes',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: EdgeInsets.symmetric(
                            vertical: isMobile ? 10 : 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== READ-ONLY PIN SECTION ====================

  Widget _buildReadOnlyPinSection(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: Colors.grey.shade500,
                size: isMobile ? 18 : 20,
              ),
              SizedBox(width: isMobile ? 8 : 10),
              Text(
                'PIN Management',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 6 : 10,
                  vertical: isMobile ? 2 : 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '🔒 LOCKED',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 8 : 10,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 12 : 14),
          Container(
            padding: EdgeInsets.all(isMobile ? 12 : 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Colors.grey.shade600,
                  size: isMobile ? 20 : 24,
                ),
                SizedBox(width: isMobile ? 10 : 14),
                Expanded(
                  child: Text(
                    'PIN management is locked in read-only mode. Contact Super Admin for PIN operations.',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 12 : 13,
                      color: Colors.grey.shade600,
                      height: 1.4,
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

  // ==================== PIN MANAGEMENT SECTION ====================

  Widget _buildPinManagementSection(bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: backgroundLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: Colors.purple.shade700,
                size: isMobile ? 18 : 20,
              ),
              SizedBox(width: isMobile ? 8 : 10),
              Text(
                'PIN Management',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showPinManagement = !_showPinManagement;
                    if (_showPinManagement && _pinStatusData == null) {
                      _checkPinStatus();
                    }
                  });
                },
                icon: Icon(
                  _showPinManagement
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: isMobile ? 18 : 20,
                ),
                label: Text(
                  _showPinManagement ? 'Hide' : 'Manage PIN',
                  style: GoogleFonts.inter(
                    color: primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          if (_showPinManagement) ...[
            SizedBox(height: isMobile ? 12 : 14),
            if (_isPinLoading)
              Center(
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 16 : 20),
                  child: CircularProgressIndicator(color: primaryColor),
                ),
              )
            else if (_pinStatusData != null)
              _buildPinStatusDisplay(isMobile)
            else
              Center(
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 16 : 20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.security_rounded,
                        color: Colors.grey.shade400,
                        size: isMobile ? 40 : 48,
                      ),
                      SizedBox(height: isMobile ? 8 : 12),
                      Text(
                        'No PIN data available',
                        style: GoogleFonts.inter(
                          color: textSecondary,
                          fontSize: isMobile ? 13 : 14,
                        ),
                      ),
                      SizedBox(height: isMobile ? 10 : 12),
                      ElevatedButton.icon(
                        onPressed: _checkPinStatus,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Check PIN Status'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPinStatusDisplay(bool isMobile) {
    final pinStatus = _pinStatusData?['pinStatus'];
    final isLocked = pinStatus?['isPinLocked'] ?? false;
    final failedAttempts = pinStatus?['failedAttempts'] ?? 0;
    final lockRemaining = pinStatus?['lockRemainingMinutes'] ?? 0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildPinStatusCard(
                title: 'Lock Status',
                value: isLocked ? 'LOCKED' : 'UNLOCKED',
                color: isLocked ? errorColor : successColor,
                icon: isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                isMobile: isMobile,
              ),
            ),
            SizedBox(width: isMobile ? 8 : 12),
            Expanded(
              child: _buildPinStatusCard(
                title: 'Failed Attempts',
                value: '$failedAttempts',
                color: failedAttempts > 0 ? warningColor : successColor,
                icon: Icons.warning_rounded,
                isMobile: isMobile,
              ),
            ),
          ],
        ),
        if (isLocked) ...[
          SizedBox(height: isMobile ? 8 : 10),
          _buildPinStatusCard(
            title: 'Lock Remaining',
            value: '$lockRemaining min',
            color: errorColor,
            icon: Icons.timer_rounded,
            isMobile: isMobile,
          ),
        ],
        SizedBox(height: isMobile ? 12 : 14),
        Row(
          children: [
            Expanded(
              child: _buildPinActionButton(
                icon: Icons.refresh_rounded,
                label: 'Check Status',
                color: infoColor,
                onTap: _checkPinStatus,
                isMobile: isMobile,
              ),
            ),
            SizedBox(width: isMobile ? 6 : 8),
            Expanded(
              child: _buildPinActionButton(
                icon: Icons.lock_open_rounded,
                label: 'Unlock PIN',
                color: Colors.orange.shade700,
                onTap: _unlockPin,
                isMobile: isMobile,
              ),
            ),
          ],
        ),
        SizedBox(height: isMobile ? 8 : 10),
        SizedBox(
          width: double.infinity,
          child: _buildPinActionButton(
            icon: Icons.restart_alt_rounded,
            label: 'Reset PIN to Default (123456)',
            color: Colors.red.shade700,
            onTap: _resetPin,
            isMobile: isMobile,
          ),
        ),
      ],
    );
  }

  Widget _buildPinStatusCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
    required bool isMobile,
  }) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 10 : 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: isMobile ? 18 : 22),
          SizedBox(height: isMobile ? 4 : 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: isMobile ? 9 : 11,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool isMobile,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: isMobile ? 16 : 18),
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: isMobile ? 11 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.08),
        foregroundColor: color,
        padding: EdgeInsets.symmetric(
          vertical: isMobile ? 8 : 10,
          horizontal: isMobile ? 8 : 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
        elevation: 0,
      ),
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required dynamic icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    required bool isMobile,
    bool readOnly = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: readOnly ? Colors.grey.shade100 : backgroundLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: readOnly ? Colors.grey.shade300 : Colors.grey.shade200,
        ),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        style: GoogleFonts.inter(
          fontSize: isMobile ? 14 : 15,
          color: readOnly ? Colors.grey.shade700 : textPrimary,
        ),
        validator: readOnly ? null : validator,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          hintText: readOnly ? '' : hint,
          labelStyle: GoogleFonts.inter(
            color: readOnly ? Colors.grey.shade500 : textSecondary,
            fontSize: isMobile ? 12 : 13,
          ),
          hintStyle: GoogleFonts.inter(
            color: Colors.grey.shade400,
            fontSize: isMobile ? 13 : 14,
          ),
          prefixIcon: Padding(
            padding: EdgeInsets.all(isMobile ? 10 : 12),
            child: HugeIcon(
              icon: icon,
              color:
                  readOnly
                      ? Colors.grey.shade400
                      : primaryColor.withValues(alpha: 0.5),
              size: isMobile ? 18 : 20,
            ),
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 14,
            vertical: isMobile ? 14 : 16,
          ),
        ),
      ),
    );
  }

  Widget _buildToggleSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    required Color activeColor,
    required IconData icon,
    required bool isMobile,
    bool readOnly = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Icon(
                icon,
                color: readOnly ? Colors.grey.shade400 : activeColor,
                size: isMobile ? 18 : 20,
              ),
              SizedBox(width: isMobile ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 13 : 14,
                        fontWeight: FontWeight.w600,
                        color: readOnly ? Colors.grey.shade600 : textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 11 : 12,
                        color: readOnly ? Colors.grey.shade500 : textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: readOnly ? null : onChanged,
          activeThumbColor: activeColor,
          inactiveThumbColor: Colors.grey.shade400,
          inactiveTrackColor: Colors.grey.shade300,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Loading user data...',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 20 : 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: isMobile ? 80 : 100,
                height: isMobile ? 80 : 100,
                decoration: BoxDecoration(
                  color: errorColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  color: errorColor,
                  size: isMobile ? 40 : 50,
                ),
              ),
              SizedBox(height: isMobile ? 16 : 20),
              Text(
                'Access Denied',
                style: GoogleFonts.poppins(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.w700,
                  color: errorColor,
                ),
              ),
              SizedBox(height: isMobile ? 8 : 12),
              Text(
                _errorMessage ??
                    'You don\'t have permission to access this page.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 14 : 16,
                  color: textSecondary,
                ),
              ),
              SizedBox(height: isMobile ? 20 : 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(
                  'Go Back',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 20 : 24,
                    vertical: isMobile ? 12 : 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== MAIN BUILD ====================

  @override
  Widget build(BuildContext context) {
    if (_isCheckingAdmin) {
      return _buildLoadingState();
    }

    if (!_isAdmin) {
      return _buildErrorState();
    }

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
            // Main Content
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _buildAdminHeader(),
                  _buildAdminStatusCard(),
                  _buildEditForm(),
                  SizedBox(height: 40),
                ],
              ),
            ),
            // Loading Overlay
            if (_isLoading)
              Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
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
                        SizedBox(height: 12),
                        Text(
                          'Updating user...',
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
