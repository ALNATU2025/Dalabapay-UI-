// lib/presentation/screens/admin/vtpass_settings_dashboard.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';
import '../dashboard/dashboard_screen.dart';

class VtpassSettingsDashboard extends StatefulWidget {
  const VtpassSettingsDashboard({super.key});

  @override
  State<VtpassSettingsDashboard> createState() =>
      _VtpassSettingsDashboardState();
}

class _VtpassSettingsDashboardState extends State<VtpassSettingsDashboard>
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

  // ==================== STATE ====================
  bool _useSandbox = true;
  bool _isLoading = true;
  bool _isAdmin = false;
  bool _isSpecificAdmin = false;
  bool _isInitialLoad = true;
  bool _maintenanceMode = false;
  String _maintenanceMessage = '';
  bool _isTogglingMaintenance = false;
  static const Duration _cacheDuration = Duration(minutes: 5);

  String? _errorMessage;

  bool _isCheckingHealth = false;
  Map<String, dynamic> _serverHealth = {};

  bool _isTestingCredentials = false;
  Map<String, dynamic> _credentialsTestResult = {};

  bool _isFetchingBalance = false;
  double _vtpassBalance = 0.0;
  DateTime? _balanceLastChecked;
  String _balanceError = '';

  bool _isFetchingAlerts = false;
  List<dynamic> _alerts = [];
  String _alertsError = '';

  int _totalUsers = 0;
  int _activeUsers = 0;
  double _totalBalance = 0;

  // ==================== SERVICE CONTROLS ====================
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

  final Map<String, String> _serviceLabels = {
    'airtime': 'Airtime',
    'data': 'Data',
    'electricity': 'Electricity',
    'cable': 'Cable TV',
    'transfer': 'Money Transfer',
    'international_airtime': 'Int\'l Airtime',
    'education': 'Education',
    'insurance': 'Insurance',
  };

  final Map<String, IconData> _serviceIcons = {
    'airtime': Icons.phone_android,
    'data': Icons.wifi,
    'electricity': Icons.flash_on,
    'cable': Icons.tv,
    'transfer': Icons.swap_horiz,
    'international_airtime': Icons.public,
    'education': Icons.school,
    'insurance': Icons.shield,
  };

  // Controllers
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  final TextEditingController _maintenanceMessageController =
      TextEditingController();

  // Animation
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Flag to prevent multiple data loads
  bool _dataLoaded = false;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _maintenanceMessageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

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
            _maintenanceMessage = serverMessage;
            _maintenanceMessageController.text = serverMessage;
          }
        });
        _showSnackBar(
          value ? '🔧 Maintenance mode enabled' : '✅ Maintenance mode disabled',
          false,
        );
        await _fetchMaintenanceStatus();
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
        setState(() {
          _maintenanceMessage = _maintenanceMessageController.text.trim();
        });
        _showSnackBar('✅ Maintenance message updated', false);
        await _fetchMaintenanceStatus();
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

  // ==================== DATA LOADING ====================

  Future<void> _loadInitialData() async {
    if (_dataLoaded) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      final cachedData = prefs.getString('cached_vtpass_settings');
      if (cachedData != null && _isInitialLoad) {
        try {
          final cached = jsonDecode(cachedData);
          final cacheTime = DateTime.parse(cached['timestamp']);
          if (DateTime.now().difference(cacheTime) < _cacheDuration) {
            setState(() {
              _useSandbox = cached['useSandbox'] ?? true;
              _vtpassBalance = cached['vtpassBalance'] ?? 0;
              _balanceLastChecked =
                  cached['balanceLastChecked'] != null
                      ? DateTime.parse(cached['balanceLastChecked'])
                      : null;
              _alerts = cached['alerts'] ?? [];
              _serverHealth = cached['serverHealth'] ?? {};
              _totalUsers = cached['totalUsers'] ?? 0;
              _activeUsers = cached['activeUsers'] ?? 0;
              _totalBalance = cached['totalBalance'] ?? 0;
              _isLoading = false;
            });
            debugPrint('📦 Loaded VTpass settings from cache');
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
          await _fetchAllData();
          _dataLoaded = true;
          if (mounted) {
            _animationController.forward();
          }
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

  Future<void> _toggleService(String service) async {
    final currentStatus = _serviceStatus[service] ?? true;
    final newStatus = !currentStatus;

    setState(() {
      _serviceStatus[service] = newStatus;
    });

    try {
      final response = await ApiService.authenticatedPost(
        '/api/admin/service-toggle',
        {'service': service, 'enabled': newStatus},
      );

      if (response['success'] != true) {
        setState(() {
          _serviceStatus[service] = currentStatus;
        });
        _showSnackBar(response['message'] ?? 'Failed to toggle service', true);
      } else {
        _showSnackBar(
          '${_serviceLabels[service] ?? service} ${newStatus ? 'enabled' : 'disabled'}',
          false,
        );
        await _fetchServiceStatus();
      }
    } catch (e) {
      setState(() {
        _serviceStatus[service] = currentStatus;
      });
      _showSnackBar('Error: ${e.toString()}', true);
    }
  }

  Widget _buildServiceControlsCard() {
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
          mainAxisSize: MainAxisSize.min,
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
                    mainAxisSize: MainAxisSize.min,
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
            Wrap(
              spacing: isMobile ? 6 : 8,
              runSpacing: isMobile ? 6 : 8,
              children:
                  serviceKeys.map((service) {
                    final isEnabled = _serviceStatus[service] ?? true;
                    final label = _serviceLabels[service] ?? service;
                    final icon = _serviceIcons[service] ?? Icons.help_outline;

                    return Container(
                      width:
                          isMobile
                              ? (MediaQuery.of(context).size.width - 60) / 2
                              : 160,
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 8 : 12,
                        vertical: isMobile ? 6 : 10,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isEnabled
                                ? successColor.withOpacity(0.08)
                                : errorColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
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
                          Icon(
                            icon,
                            color: isEnabled ? successColor : errorColor,
                            size: isMobile ? 14 : 18,
                          ),
                          SizedBox(width: isMobile ? 4 : 8),
                          Expanded(
                            child: Text(
                              label,
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 10 : 12,
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

  Future<void> _fetchAllData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isInitialLoad = false;
    });

    try {
      await Future.wait([
        _fetchUsersStats(),
        _fetchVtpassBalance(),
        _fetchVtpassAlerts(),
        _checkServerHealth(),
        _fetchMaintenanceStatus(),
        _fetchServiceStatus(),
      ]);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'cached_vtpass_settings',
        jsonEncode({
          'useSandbox': _useSandbox,
          'vtpassBalance': _vtpassBalance,
          'balanceLastChecked': _balanceLastChecked?.toIso8601String(),
          'alerts': _alerts,
          'serverHealth': _serverHealth,
          'totalUsers': _totalUsers,
          'activeUsers': _activeUsers,
          'totalBalance': _totalBalance,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint("❌ Error fetching data: $e");
      if (e.toString().contains('Admin access required')) {
        setState(() {
          _errorMessage = "You don't have permission to access admin features.";
          _isAdmin = false;
        });
      } else {
        setState(() {
          _errorMessage = "Failed to load data: ${e.toString()}";
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

  Future<void> _fetchMaintenanceStatus() async {
    try {
      final response = await ApiService.checkMaintenanceStatus();

      debugPrint('🔧 Maintenance Status Response: $response');

      if (response['maintenanceMode'] != null) {
        setState(() {
          _maintenanceMode = response['maintenanceMode'] == true;
          _maintenanceMessage = response['message']?.toString() ?? '';
          _maintenanceMessageController.text = _maintenanceMessage;

          final readOnlyAllowed = response['readOnlyAllowed'] ?? false;
          if (readOnlyAllowed) {
            debugPrint(
              '📖 Read-only mode active - Users can view balance & transactions',
            );
          }

          if (response['isAdmin'] == true) {
            debugPrint('👑 Admin maintenance info:');
            debugPrint(
              '   Maintenance Enabled: ${response['maintenanceEnabled']}',
            );
            debugPrint('   Message: ${response['maintenanceMessage']}');
            debugPrint('   Note: ${response['adminNote']}');
            debugPrint('   Allowed Endpoints: ${response['allowedEndpoints']}');
          }
        });
      } else {
        setState(() {
          _maintenanceMode = false;
          _maintenanceMessage = '';
          _maintenanceMessageController.text = '';
        });
      }
    } catch (e) {
      debugPrint('❌ Error fetching maintenance status: $e');
      setState(() {
        _maintenanceMode = false;
        _maintenanceMessage = '';
        _maintenanceMessageController.text = '';
      });
    }
  }

  Future<void> _fetchUsersStats() async {
    try {
      final users = await ApiService.getAllUsersForAdmin();
      final activeUsers = users.where((u) => u['isActive'] == true).length;
      final totalBalance = users.fold<double>(
        0,
        (sum, user) => sum + ((user['walletBalance'] as num?)?.toDouble() ?? 0),
      );

      setState(() {
        _totalUsers = users.length;
        _activeUsers = activeUsers;
        _totalBalance = totalBalance;
      });
    } catch (e) {
      debugPrint('Error fetching users for stats: $e');
    }
  }

  Future<void> _fetchVtpassBalance() async {
    setState(() {
      _isFetchingBalance = true;
      _balanceError = '';
    });

    try {
      final balanceData = await ApiService.getVtpassBalance();

      if (balanceData['success'] == true) {
        setState(() {
          _vtpassBalance = (balanceData['balance'] as num).toDouble();
          _balanceLastChecked = DateTime.now();
        });
      } else {
        setState(() {
          _balanceError = balanceData['message'] ?? 'Failed to fetch balance';
        });
      }
    } catch (e) {
      setState(() {
        _balanceError = 'Error: $e';
      });
      debugPrint('Error fetching VTpass balance: $e');
    } finally {
      setState(() {
        _isFetchingBalance = false;
      });
    }
  }

  Future<void> _fetchVtpassAlerts() async {
    setState(() {
      _isFetchingAlerts = true;
      _alertsError = '';
    });

    try {
      final alertsData = await ApiService.getVtpassAlerts();

      if (alertsData['success'] == true) {
        setState(() {
          _alerts = alertsData['alerts'] ?? [];
          if (alertsData['currentBalance'] != null) {
            _vtpassBalance = (alertsData['currentBalance'] as num).toDouble();
          }
        });
      } else {
        setState(() {
          _alertsError = alertsData['message'] ?? 'Failed to fetch alerts';
        });
      }
    } catch (e) {
      setState(() {
        _alertsError = 'Error: $e';
      });
      debugPrint('Error fetching VTpass alerts: $e');
    } finally {
      setState(() {
        _isFetchingAlerts = false;
      });
    }
  }

  Future<void> _checkServerHealth() async {
    setState(() {
      _isCheckingHealth = true;
    });

    try {
      final response = await ApiService.checkServerHealth();

      if (response['success'] == true) {
        setState(() {
          _serverHealth = {
            'success': true,
            'status': response['status'] ?? 'OK',
            'timestamp': response['timestamp'],
            'uptime': response['uptime'],
            'message': 'Server is healthy',
          };
        });
      } else {
        setState(() {
          _serverHealth = {
            'success': false,
            'message': response['message'] ?? 'Server health check failed',
          };
        });
      }
    } catch (e) {
      setState(() {
        _serverHealth = {
          'success': false,
          'message': 'Failed to check server health: $e',
        };
      });
    } finally {
      setState(() {
        _isCheckingHealth = false;
      });
    }
  }

  Future<void> _toggleEnvironment() async {
    setState(() {
      _useSandbox = !_useSandbox;
    });

    await ApiService.toggleEnvironment(useSandbox: _useSandbox);

    setState(() {
      _credentialsTestResult = {};
    });

    _showSnackBar(
      '✅ Switched to ${_useSandbox ? "Sandbox" : "Live"} mode',
      false,
    );

    await _fetchVtpassBalance();
  }

  Future<void> _testVtpassCredentials() async {
    setState(() {
      _isTestingCredentials = true;
      _credentialsTestResult = {};
    });

    try {
      final testResult = await ApiService.verifyVtpassCredentials();
      setState(() {
        _credentialsTestResult = testResult;
      });

      if (testResult['success'] == true) {
        _showSnackBar('✅ ${testResult['message']}', false);
      } else {
        _showSnackBar('❌ ${testResult['message']}', true);
      }
    } catch (e) {
      setState(() {
        _credentialsTestResult = {
          'success': false,
          'message': 'Test failed: $e',
        };
      });
      _showSnackBar('❌ Credentials test failed', true);
    } finally {
      setState(() {
        _isTestingCredentials = false;
      });
    }
  }

  Future<void> _refreshData() async {
    await _fetchAllData();
    _showSnackBar('✅ Data refreshed successfully', false);
  }

  void _openDocumentation() async {
    final url = 'https://www.vtpass.com/documentation/';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
      } else {
        _showSnackBar('Could not open documentation', true);
      }
    } catch (e) {
      _showSnackBar('Error opening documentation: $e', true);
    }
  }

  void _showSnackBar(String message, bool isError) {
    if (!mounted) return;
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
    final isSmall = MediaQuery.of(context).size.width < 380;

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
                  'Admin / VTpass Settings',
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
                  Icons.api_rounded,
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
                      'VTpass Settings',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: isSmall ? 16 : (isMobile ? 20 : 28),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: isMobile ? 4 : 6),
                    Text(
                      '${_useSandbox ? "Sandbox" : "Live"} Mode • ₦${_vtpassBalance.toStringAsFixed(2)} balance',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: isSmall ? 10 : (isMobile ? 12 : 14),
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
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: (_useSandbox ? warningColor : successColor)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: HugeIcon(
                    icon:
                        _useSandbox
                            ? HugeIcons.strokeRoundedDeveloper
                            : HugeIcons.strokeRoundedCloud,
                    color: _useSandbox ? warningColor : successColor,
                    size: isMobile ? 16 : 20,
                  ),
                ),
                SizedBox(width: isMobile ? 10 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _useSandbox ? 'Sandbox Mode' : 'Live Mode',
                        style: GoogleFonts.inter(
                          color: primaryColor,
                          fontSize: isSmall ? 11 : (isMobile ? 13 : 14),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _useSandbox
                            ? 'Testing environment - No real transactions'
                            : 'Production environment - Real transactions',
                        style: GoogleFonts.inter(
                          color: textSecondary,
                          fontSize: isSmall ? 8 : (isMobile ? 10 : 11),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _useSandbox,
                  onChanged: (value) => _toggleEnvironment(),
                  activeThumbColor: primaryColor,
                  inactiveThumbColor: Colors.grey[400],
                  activeTrackColor: primaryColor.withValues(alpha: 0.3),
                  inactiveTrackColor: Colors.grey[300],
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
    final isSmall = MediaQuery.of(context).size.width < 380;

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
        'value': '₦${_totalBalance.toStringAsFixed(0)}',
        'label': 'User Balance',
        'icon': HugeIcons.strokeRoundedWallet01,
        'color': secondaryColor,
      },
      {
        'value':
            _isFetchingBalance
                ? '...'
                : '₦${_vtpassBalance.toStringAsFixed(0)}',
        'label': 'VTpass Balance',
        'icon': HugeIcons.strokeRoundedMoney02,
        'color': _vtpassBalance < 5000 ? errorColor : successColor,
      },
    ];

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
      child:
          isSmall
              ? Wrap(
                spacing: 4,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children:
                    stats.map((stat) {
                      return SizedBox(
                        width: (MediaQuery.of(context).size.width - 40) / 2,
                        child: _buildStatItem(
                          value: stat['value'] as String,
                          label: stat['label'] as String,
                          icon: stat['icon'] as dynamic,
                          color: stat['color'] as Color,
                          isMobile: true,
                        ),
                      );
                    }).toList(),
              )
              : Row(
                children:
                    stats.map((stat) {
                      return Expanded(
                        child: _buildStatItem(
                          value: stat['value'] as String,
                          label: stat['label'] as String,
                          icon: stat['icon'] as dynamic,
                          color: stat['color'] as Color,
                          isMobile: isMobile,
                        ),
                      );
                    }).toList(),
              ),
    );
  }

  Widget _buildMaintenanceControlCard() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isSmall = MediaQuery.of(context).size.width < 380;

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
        border: Border.all(
          color:
              _maintenanceMode
                  ? errorColor.withOpacity(0.3)
                  : Colors.grey.shade200,
          width: _maintenanceMode ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (_maintenanceMode ? errorColor : secondaryColor)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: HugeIcon(
                    icon:
                        _maintenanceMode
                            ? HugeIcons.strokeRoundedAlert02
                            : HugeIcons.strokeRoundedCheckmarkCircle01,
                    color: _maintenanceMode ? errorColor : secondaryColor,
                    size: isMobile ? 20 : 24,
                  ),
                ),
                SizedBox(width: isMobile ? 12 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Maintenance Control',
                        style: GoogleFonts.inter(
                          fontSize: isSmall ? 13 : (isMobile ? 15 : 17),
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        _maintenanceMode
                            ? '⚠️ System is in maintenance mode'
                            : '✅ All services are active',
                        style: GoogleFonts.inter(
                          fontSize: isSmall ? 10 : (isMobile ? 12 : 13),
                          color: _maintenanceMode ? errorColor : secondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: isSmall ? 60 : (isMobile ? 70 : 80),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: _maintenanceMode,
                        onChanged:
                            _isTogglingMaintenance ? null : _toggleMaintenance,
                        activeThumbColor: primaryColor,
                        inactiveThumbColor: Colors.grey[400],
                        activeTrackColor: primaryColor.withOpacity(0.3),
                        inactiveTrackColor: Colors.grey[300],
                      ),
                      Text(
                        _maintenanceMode ? 'ON' : 'OFF',
                        style: GoogleFonts.inter(
                          fontSize: isSmall ? 8 : (isMobile ? 9 : 10),
                          fontWeight: FontWeight.w700,
                          color: _maintenanceMode ? errorColor : textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_maintenanceMode) ...[
              const SizedBox(height: 10),
              Container(
                padding: EdgeInsets.all(isMobile ? 10 : 12),
                decoration: BoxDecoration(
                  color: errorColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: errorColor.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: errorColor,
                          size: isMobile ? 18 : 20,
                        ),
                        SizedBox(width: isMobile ? 8 : 10),
                        Expanded(
                          child: Text(
                            '🔴 SYSTEM IS IN MAINTENANCE MODE',
                            style: GoogleFonts.inter(
                              fontSize: isSmall ? 9 : (isMobile ? 11 : 12),
                              color: errorColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: EdgeInsets.only(left: isMobile ? 28 : 30),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                color: secondaryColor,
                                size: isMobile ? 14 : 16,
                              ),
                              SizedBox(width: isMobile ? 6 : 8),
                              Expanded(
                                child: Text(
                                  '✅ View Balance & Transactions (Read-Only)',
                                  style: GoogleFonts.inter(
                                    fontSize:
                                        isSmall ? 8 : (isMobile ? 10 : 11),
                                    color: secondaryColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.block_rounded,
                                color: errorColor,
                                size: isMobile ? 14 : 16,
                              ),
                              SizedBox(width: isMobile ? 6 : 8),
                              Expanded(
                                child: Text(
                                  '❌ New Transactions Disabled',
                                  style: GoogleFonts.inter(
                                    fontSize:
                                        isSmall ? 8 : (isMobile ? 10 : 11),
                                    color: errorColor,
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
              ),
            ],
            if (_maintenanceMode) ...[
              const SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(isMobile ? 10 : 12),
                decoration: BoxDecoration(
                  color: backgroundLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📝 Maintenance Message:',
                      style: GoogleFonts.inter(
                        fontSize: isSmall ? 10 : (isMobile ? 12 : 13),
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _maintenanceMessage.isNotEmpty
                          ? _maintenanceMessage
                          : 'System is under maintenance. Transactions are disabled.',
                      style: GoogleFonts.inter(
                        fontSize: isSmall ? 10 : (isMobile ? 11 : 12),
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // FIX: Use Column for all screens to avoid infinite width
              Column(
                children: [
                  TextField(
                    controller: _maintenanceMessageController,
                    decoration: InputDecoration(
                      hintText: 'Update maintenance message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 12 : 14,
                        vertical: isSmall ? 8 : (isMobile ? 10 : 12),
                      ),
                    ),
                    style: GoogleFonts.inter(
                      fontSize: isSmall ? 11 : (isMobile ? 13 : 14),
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          _isTogglingMaintenance
                              ? null
                              : _updateMaintenanceMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmall ? 10 : (isMobile ? 16 : 20),
                          vertical: isSmall ? 8 : (isMobile ? 10 : 12),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child:
                          _isTogglingMaintenance
                              ? SizedBox(
                                width: isSmall ? 16 : 20,
                                height: isSmall ? 16 : 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                              : Text(
                                'Update',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: isSmall ? 10 : (isMobile ? 12 : 13),
                                ),
                              ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(isMobile ? 8 : 10),
              decoration: BoxDecoration(
                color: infoColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: infoColor.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.admin_panel_settings,
                    color: infoColor,
                    size: isMobile ? 14 : 16,
                  ),
                  SizedBox(width: isMobile ? 6 : 8),
                  Expanded(
                    child: Text(
                      _maintenanceMode
                          ? 'Admin: Full access. Users: Read-only.'
                          : 'Admin access is always available.',
                      style: GoogleFonts.inter(
                        fontSize: isSmall ? 8 : (isMobile ? 10 : 11),
                        color: textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
    final isSmall = MediaQuery.of(context).size.width < 380;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(isSmall ? 4 : (isMobile ? 6 : 8)),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: HugeIcon(
            icon: icon,
            color: color,
            size: isSmall ? 14 : (isMobile ? 18 : 22),
          ),
        ),
        SizedBox(height: isSmall ? 1 : (isMobile ? 2 : 4)),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: isSmall ? 11 : (isMobile ? 14 : 16),
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: isSmall ? 0 : (isMobile ? 1 : 2)),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: isSmall ? 7 : (isMobile ? 9 : 11),
            color: textSecondary,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // ==================== SETTINGS CARDS ====================

  Widget _buildServerHealthCard() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isSmall = MediaQuery.of(context).size.width < 380;
    final isHealthy = _serverHealth['success'] == true;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 8),
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
                    color: (isHealthy ? successColor : errorColor).withValues(
                      alpha: 0.1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedActivity03,
                    color: isHealthy ? successColor : errorColor,
                    size: isMobile ? 20 : 24,
                  ),
                ),
                SizedBox(width: isMobile ? 12 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Server Health',
                        style: GoogleFonts.inter(
                          fontSize: isSmall ? 13 : (isMobile ? 15 : 17),
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        isHealthy
                            ? '✅ Server is running normally'
                            : '⚠️ Server health check failed',
                        style: GoogleFonts.inter(
                          fontSize: isSmall ? 10 : (isMobile ? 12 : 13),
                          color: isHealthy ? successColor : errorColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isHealthy && _serverHealth['uptime'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: successColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _formatUptime(_serverHealth['uptime'].toString()),
                      style: GoogleFonts.inter(
                        fontSize: isSmall ? 8 : (isMobile ? 10 : 11),
                        fontWeight: FontWeight.w600,
                        color: successColor,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_serverHealth.isNotEmpty) ...[
              Container(
                padding: EdgeInsets.all(isMobile ? 10 : 12),
                decoration: BoxDecoration(
                  color: backgroundLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    _buildInfoRow(
                      'Status',
                      _serverHealth['status'] ?? 'Unknown',
                      isMobile,
                    ),
                    _buildInfoRow(
                      'Uptime',
                      _formatUptime(_serverHealth['uptime']?.toString() ?? '0'),
                      isMobile,
                    ),
                    if (_serverHealth['timestamp'] != null)
                      _buildInfoRow(
                        'Last Checked',
                        _formatTimestamp(_serverHealth['timestamp']),
                        isMobile,
                      ),
                  ],
                ),
              ),
              SizedBox(height: isMobile ? 12 : 16),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isCheckingHealth ? null : _checkServerHealth,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon:
                    _isCheckingHealth
                        ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                        : HugeIcon(
                          icon: HugeIcons.strokeRoundedHealth,
                          color: Colors.white,
                          size: isMobile ? 18 : 20,
                        ),
                label: Text(
                  _isCheckingHealth ? 'Checking...' : 'Check Server Health',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: isSmall ? 11 : (isMobile ? 13 : 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCredentialsTestCard() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isSmall = MediaQuery.of(context).size.width < 380;
    final isSuccess = _credentialsTestResult['success'] == true;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 8),
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
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedSecurityLock,
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
                        'Credentials Test',
                        style: GoogleFonts.inter(
                          fontSize: isSmall ? 13 : (isMobile ? 15 : 17),
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        'Test VTpass API credentials',
                        style: GoogleFonts.inter(
                          fontSize: isSmall ? 10 : (isMobile ? 12 : 13),
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_credentialsTestResult.isNotEmpty) ...[
              Container(
                padding: EdgeInsets.all(isMobile ? 10 : 12),
                decoration: BoxDecoration(
                  color: (isSuccess ? successColor : errorColor).withValues(
                    alpha: 0.08,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (isSuccess ? successColor : errorColor).withValues(
                      alpha: 0.2,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    HugeIcon(
                      icon:
                          isSuccess
                              ? HugeIcons.strokeRoundedCheckmarkCircle01
                              : HugeIcons.strokeRoundedCancelCircle,
                      color: isSuccess ? successColor : errorColor,
                      size: isMobile ? 20 : 24,
                    ),
                    SizedBox(width: isMobile ? 10 : 12),
                    Expanded(
                      child: Text(
                        _credentialsTestResult['message'] ?? 'Test completed',
                        style: GoogleFonts.inter(
                          fontSize: isSmall ? 11 : (isMobile ? 13 : 14),
                          fontWeight: FontWeight.w500,
                          color: isSuccess ? successColor : errorColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_credentialsTestResult['environment'] != null) ...[
                SizedBox(height: isMobile ? 8 : 10),
                _buildInfoRow(
                  'Environment',
                  (_credentialsTestResult['environment'] as String)
                      .toUpperCase(),
                  isMobile,
                ),
              ],
              SizedBox(height: isMobile ? 12 : 16),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    _isTestingCredentials ? null : _testVtpassCredentials,
                style: ElevatedButton.styleFrom(
                  backgroundColor: secondaryColor,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon:
                    _isTestingCredentials
                        ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                        : HugeIcon(
                          icon: HugeIcons.strokeRoundedAward04,
                          color: Colors.white,
                          size: isMobile ? 18 : 20,
                        ),
                label: Text(
                  _isTestingCredentials ? 'Testing...' : 'Test Credentials',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: isSmall ? 11 : (isMobile ? 13 : 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentationCard() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isSmall = MediaQuery.of(context).size.width < 380;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 8),
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
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedBookOpen01,
                    color: Colors.blue,
                    size: isMobile ? 20 : 24,
                  ),
                ),
                SizedBox(width: isMobile ? 12 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Documentation & Info',
                        style: GoogleFonts.inter(
                          fontSize: isSmall ? 13 : (isMobile ? 15 : 17),
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        'Access VTpass API documentation',
                        style: GoogleFonts.inter(
                          fontSize: isSmall ? 10 : (isMobile ? 12 : 13),
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(isMobile ? 12 : 16),
              decoration: BoxDecoration(
                color: backgroundLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📌 Important Notes:',
                    style: GoogleFonts.inter(
                      fontSize: isSmall ? 11 : (isMobile ? 13 : 14),
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildBulletPoint(
                    'Sandbox Mode: Use test numbers for testing',
                    isMobile,
                  ),
                  _buildBulletPoint(
                    'Live Mode: Real transactions with real money',
                    isMobile,
                  ),
                  _buildBulletPoint(
                    'Always test credentials before switching to live',
                    isMobile,
                  ),
                  _buildBulletPoint(
                    'Contact VTpass support for live credentials',
                    isMobile,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openDocumentation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedOpenSource,
                  color: Colors.white,
                  size: isMobile ? 18 : 20,
                ),
                label: Text(
                  'Open Documentation',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: isSmall ? 11 : (isMobile ? 13 : 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVtpassBalanceCard() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isSmall = MediaQuery.of(context).size.width < 380;
    final isLow = _vtpassBalance < 5000;
    final isWarning = _vtpassBalance < 10000 && _vtpassBalance >= 5000;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 8),
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
                    color: (isLow
                            ? errorColor
                            : isWarning
                            ? warningColor
                            : successColor)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedWallet01,
                    color:
                        isLow
                            ? errorColor
                            : isWarning
                            ? warningColor
                            : successColor,
                    size: isMobile ? 20 : 24,
                  ),
                ),
                SizedBox(width: isMobile ? 12 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VTpass Balance',
                        style: GoogleFonts.inter(
                          fontSize: isSmall ? 13 : (isMobile ? 15 : 17),
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            _isFetchingBalance
                                ? 'Fetching...'
                                : '₦${_vtpassBalance.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: isSmall ? 16 : (isMobile ? 20 : 24),
                              fontWeight: FontWeight.bold,
                              color:
                                  isLow
                                      ? errorColor
                                      : isWarning
                                      ? warningColor
                                      : successColor,
                            ),
                          ),
                          if (_balanceLastChecked != null) ...[
                            SizedBox(width: isMobile ? 8 : 12),
                            Text(
                              '• ${_formatTimeAgo(_balanceLastChecked!)}',
                              style: GoogleFonts.inter(
                                fontSize: isSmall ? 8 : (isMobile ? 10 : 11),
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _fetchVtpassBalance,
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedRefresh,
                    color: textSecondary,
                    size: isMobile ? 18 : 20,
                  ),
                  tooltip: 'Refresh balance',
                ),
              ],
            ),
            if (_alerts.isNotEmpty) ...[
              SizedBox(height: isMobile ? 12 : 16),
              Text(
                'Low Balance Alerts',
                style: GoogleFonts.inter(
                  fontSize: isSmall ? 11 : (isMobile ? 13 : 14),
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              ..._alerts.take(3).map((alert) => _buildAlertItem(alert)),
              if (_alerts.length > 3)
                TextButton(
                  onPressed: _showAllAlertsDialog,
                  child: Text(
                    'View all ${_alerts.length} alerts',
                    style: GoogleFonts.inter(
                      color: primaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: isSmall ? 11 : (isMobile ? 13 : 14),
                    ),
                  ),
                ),
              SizedBox(height: isMobile ? 8 : 12),
            ] else if (_isFetchingAlerts) ...[
              const SizedBox(height: 8),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
            ] else if (_alertsError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: errorColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '⚠️ $_alertsError',
                  style: GoogleFonts.inter(
                    fontSize: isSmall ? 10 : (isMobile ? 12 : 13),
                    color: errorColor,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  launchUrl(Uri.parse('https://vtpass.com/wallet'));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: secondaryColor,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedMoneyAdd01,
                  color: Colors.white,
                  size: isMobile ? 18 : 20,
                ),
                label: Text(
                  'Add Funds to VTpass',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: isSmall ? 11 : (isMobile ? 13 : 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertItem(Map<String, dynamic> alert) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final isSmall = MediaQuery.of(context).size.width < 380;
    final Color alertColor =
        alert['severity'] == 'CRITICAL'
            ? errorColor
            : alert['severity'] == 'WARNING'
            ? warningColor
            : primaryColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.all(isSmall ? 8 : (isMobile ? 10 : 12)),
      decoration: BoxDecoration(
        color: alertColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: alertColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HugeIcon(
            icon:
                alert['severity'] == 'CRITICAL'
                    ? HugeIcons.strokeRoundedAlert01
                    : HugeIcons.strokeRoundedAlert02,
            color: alertColor,
            size: isSmall ? 14 : (isMobile ? 16 : 18),
          ),
          SizedBox(width: isMobile ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert['title'] ?? 'Low Balance Alert',
                  style: GoogleFonts.inter(
                    fontSize: isSmall ? 10 : (isMobile ? 12 : 13),
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                Text(
                  alert['message'] ?? 'VTpass wallet balance is low',
                  style: GoogleFonts.inter(
                    fontSize: isSmall ? 9 : (isMobile ? 11 : 12),
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (alert['acknowledged'] == false)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: alertColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'NEW',
                style: GoogleFonts.inter(
                  fontSize: isSmall ? 7 : (isMobile ? 8 : 9),
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showAllAlertsDialog() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'All VTpass Alerts',
              style: GoogleFonts.inter(
                fontSize: isMobile ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            content: SizedBox(
              width: isMobile ? double.infinity : 400,
              height: 400,
              child: ListView.builder(
                itemCount: _alerts.length,
                itemBuilder:
                    (context, index) => _buildAlertItem(_alerts[index]),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Close',
                  style: GoogleFonts.inter(
                    color: textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  // ==================== HELPERS ====================

  Widget _buildInfoRow(String label, String value, bool isMobile) {
    final isSmall = MediaQuery.of(context).size.width < 380;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: isSmall ? 60 : (isMobile ? 80 : 100),
            child: Text(
              '$label:',
              style: GoogleFonts.inter(
                fontSize: isSmall ? 10 : (isMobile ? 12 : 13),
                fontWeight: FontWeight.w500,
                color: textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: isSmall ? 10 : (isMobile ? 12 : 13),
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text, bool isMobile) {
    final isSmall = MediaQuery.of(context).size.width < 380;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: GoogleFonts.inter(
              fontSize: isSmall ? 10 : (isMobile ? 12 : 13),
              color: textSecondary,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: isSmall ? 10 : (isMobile ? 12 : 13),
                color: textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    try {
      if (timestamp is String) {
        final dateTime = DateTime.parse(timestamp);
        return DateFormat('HH:mm:ss').format(dateTime);
      }
      return timestamp?.toString() ?? 'N/A';
    } catch (e) {
      return timestamp?.toString() ?? 'N/A';
    }
  }

  String _formatUptime(String uptime) {
    try {
      final seconds = double.parse(uptime);
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      final remainingSeconds = (seconds % 60).toInt();

      if (hours > 0) {
        return '${hours}h ${minutes}m';
      } else if (minutes > 0) {
        return '${minutes}m ${remainingSeconds}s';
      } else {
        return '${remainingSeconds}s';
      }
    } catch (e) {
      return uptime;
    }
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  // ==================== STATE WIDGETS ====================

  Widget _buildErrorState() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
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
                  child: Icon(
                    Icons.error_outline_rounded,
                    color: errorColor,
                    size: isMobile ? 40 : 50,
                  ),
                ),
                SizedBox(height: isMobile ? 16 : 24),
                Text(
                  'Access Denied',
                  style: GoogleFonts.inter(
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
                      onPressed: _fetchAllData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        padding: EdgeInsets.symmetric(
                          vertical: isMobile ? 12 : 16,
                        ),
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
        ),
      ),
    );
  }

  // ==================== MAIN BUILD ====================

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (_isLoading && _errorMessage == null) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: SafeArea(
          child: Center(
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
                  'Loading VTpass Settings...',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 14 : 16,
                    fontWeight: FontWeight.w500,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.grey.shade50,
      drawer: CustomDrawer(
        header: _buildDrawerHeader(),
        items: _drawerItems,
        selectedItem: _drawerItems.firstWhere(
          (item) => item.title == "VTpass Settings",
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
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
                      _buildAdminHeader(),
                      _buildStatsCard(),
                      _buildServerHealthCard(),
                      _buildCredentialsTestCard(),
                      _buildDocumentationCard(),
                      _buildVtpassBalanceCard(),
                      _buildMaintenanceControlCard(),
                      _buildServiceControlsCard(),
                      SizedBox(height: isMobile ? 80 : 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
