// lib/presentation/screens/admin/admin_send_notification_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart' hide debugPrint;
import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';
import '../dashboard/dashboard_screen.dart';

class AdminSendNotificationPage extends StatefulWidget {
  const AdminSendNotificationPage({super.key});

  @override
  State<AdminSendNotificationPage> createState() =>
      _AdminSendNotificationPageState();
}

class _AdminSendNotificationPageState extends State<AdminSendNotificationPage>
    with SingleTickerProviderStateMixin {
  // ==================== BRAND COLORS ====================
  static const Color primaryColor = Color(0xFF243889);
  static const Color secondaryColor = Color(0xFF219C7E);
  static const Color successColor = Color(0xFF219C7E);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color textPrimary = Color(0xFF1C2D5A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color backgroundLight = Color(0xFFF8FAFC);

  // ==================== CONTROLLERS ====================
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  // ==================== STATE ====================
  bool _isLoading = true;
  bool _isSending = false;
  bool _isAdmin = false;
  bool _isSpecificAdmin = false;
  String? _errorMessage;

  // Notification Settings
  bool _sendToAll = true;
  String _selectedTemplate = 'custom';
  String _selectedTemplateType = '';

  // User Selection - MULTI SELECT
  List<dynamic> _users = [];
  List<dynamic> _filteredUsers = [];
  List<Map<String, dynamic>> _selectedUsers = [];
  String _searchQuery = '';
  final bool _isSelectingAll = false;

  // Statistics
  int _totalUsers = 0;
  int _activeUsers = 0;
  int _sentNotifications = 0;
  double _successRate = 100.0;

  // ==================== MESSAGE TEMPLATES ====================
  final List<Map<String, dynamic>> _templates = [
    {
      'id': 'custom',
      'name': '✏️ Custom Message',
      'title': '',
      'message': '',
      'type': 'custom',
      'icon': HugeIcons.strokeRoundedKite,
    },
    {
      'id': 'welcome',
      'name': '👋 Welcome New User',
      'title': 'Welcome to DalabaPay! 🎉',
      'message':
          'Dear [User],\n\nWelcome to DalabaPay! We\'re excited to have you on board. Start transacting with ease and earn rewards on every transaction.\n\nNeed help? Contact our support team anytime.\n\nRegards,\nDalabaPay Team',
      'type': 'onboarding',
      'icon': HugeIcons.strokeRoundedUserAdd01,
    },
    {
      'id': 'promotion',
      'name': '🎁 Promotional Offer',
      'title': '🎉 Exclusive Offer Just for You!',
      'message':
          'Dear [User],\n\nEnjoy 10% cashback on all airtime and data purchases this weekend! Use promo code: DALA10 at checkout.\n\nHurry, offer ends soon!\n\nRegards,\nDalabaPay Team',
      'type': 'promotion',
      'icon': HugeIcons.strokeRoundedPercent,
    },
    {
      'id': 'maintenance',
      'name': '🔧 Maintenance Alert',
      'title': '⏰ Scheduled Maintenance',
      'message':
          'Dear [User],\n\nWe will be performing system maintenance on [Date] from [Time] to [Time]. Services may be temporarily unavailable.\n\nWe apologize for any inconvenience.\n\nRegards,\nDalabaPay Team',
      'type': 'alert',
      'icon': HugeIcons.strokeRoundedAlert02,
    },
    {
      'id': 'security',
      'name': '🔒 Security Update',
      'title': '🔐 Security Alert: Account Protection',
      'message':
          'Dear [User],\n\nWe detected a login attempt from a new device. If this wasn\'t you, please secure your account immediately.\n\nAlways use strong passwords and enable 2FA.\n\nStay safe,\nDalabaPay Team',
      'type': 'alert',
      'icon': HugeIcons.strokeRoundedShield01,
    },
    {
      'id': 'transaction',
      'name': '💳 Transaction Update',
      'title': '💰 Transaction Successful',
      'message':
          'Dear [User],\n\nYour transaction of ₦[Amount] has been processed successfully.\n\nReference: [Reference]\nDate: [Date]\n\nThank you for using DalabaPay!\n\nRegards,\nDalabaPay Team',
      'type': 'transaction',
      'icon': HugeIcons.strokeRoundedReceiptText,
    },
    {
      'id': 'commission',
      'name': '💰 Commission Earned',
      'title': '🎊 Commission Alert!',
      'message':
          'Dear [User],\n\nYou\'ve earned ₦[Amount] in commission from [Service] transactions this week!\n\nKeep transacting to earn more rewards.\n\nRegards,\nDalabaPay Team',
      'type': 'commission',
      'icon': HugeIcons.strokeRoundedMoney01,
    },
    {
      'id': 'referral',
      'name': '👥 Referral Bonus',
      'title': '🎁 Referral Bonus Earned!',
      'message':
          'Dear [User],\n\nCongratulations! [Friend\'s Name] just joined DalabaPay using your referral code. You\'ve earned ₦[Amount] as a referral bonus!\n\nShare your code with more friends and earn unlimited rewards.\n\nRegards,\nDalabaPay Team',
      'type': 'referral',
      'icon': HugeIcons.strokeRoundedUserGroup,
    },
    {
      'id': 'kyc',
      'name': '📋 KYC Reminder',
      'title': '📋 Complete Your KYC',
      'message':
          'Dear [User],\n\nComplete your KYC verification to unlock full account features including higher transaction limits and dedicated account access.\n\nIt takes just 5 minutes!\n\nRegards,\nDalabaPay Team',
      'type': 'kyc',
      'icon': HugeIcons.strokeRoundedIdVerified,
    },
    {
      'id': 'wallet_funded',
      'name': '💳 Wallet Funded',
      'title': '💳 Wallet Funded Successfully!',
      'message':
          'Dear [User],\n\nYour wallet has been funded with ₦[Amount].\n\nNew Balance: ₦[Balance]\nTransaction ID: [TransactionID]\n\nThank you for using DalabaPay!\n\nRegards,\nDalabaPay Team',
      'type': 'transaction',
      'icon': HugeIcons.strokeRoundedWallet01,
    },
    {
      'id': 'announcement',
      'name': '📢 General Announcement',
      'title': '📢 Important Update from DalabaPay',
      'message':
          'Dear [User],\n\nWe\'re excited to announce new features and improvements to make your experience better!\n\nCheck out the latest updates in the app.\n\nRegards,\nDalabaPay Team',
      'type': 'announcement',
      'icon': HugeIcons.strokeRoundedMegaphone01,
    },
  ];

  // ==================== ANIMATION ====================
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadAdminData();

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
    _titleController.dispose();
    _messageController.dispose();
    _searchController.dispose();
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

  Future<void> _loadAdminData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
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
          await _loadStatistics();
          _animationController.forward();
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage =
                "You don't have permission to access admin features.";
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
        _errorMessage = "Error loading admin data: ${e.toString()}";
      });
    }
  }

  Future<void> _fetchUsers() async {
    try {
      final fetchedUsers = await ApiService.getAllUsersForAdmin();
      setState(() {
        _users = fetchedUsers;
        _applyFilters();
        _isLoading = false;
      });
      debugPrint('✅ Fetched ${_users.length} users');
    } catch (e) {
      debugPrint('❌ Error fetching users: $e');
      setState(() {
        _errorMessage = "Error fetching users: ${e.toString()}";
        _isLoading = false;
      });
    }
  }

  Future<void> _loadStatistics() async {
    setState(() {
      _totalUsers = _users.length;
      _activeUsers = _users.where((u) => u['isActive'] == true).length;
      _sentNotifications = 125;
      _successRate = 98.5;
    });
  }

  void _applyFilters() {
    setState(() {
      _filteredUsers =
          _users.where((user) {
            final matchesSearch =
                _searchQuery.isEmpty ||
                (user['fullName']?.toLowerCase().contains(_searchQuery) ??
                    false) ||
                (user['email']?.toLowerCase().contains(_searchQuery) ??
                    false) ||
                (user['phone']?.toString().contains(_searchQuery) ?? false);

            final isActive = user['isActive'] ?? true;
            return matchesSearch && isActive;
          }).toList();
    });
  }

  // ==================== TEMPLATE METHODS ====================

  void _applyTemplate(String templateId) {
    final template = _templates.firstWhere((t) => t['id'] == templateId);
    setState(() {
      _selectedTemplate = templateId;
      _selectedTemplateType = template['type'] ?? '';
      _titleController.text = template['title'] ?? '';
      _messageController.text = template['message'] ?? '';
    });
    debugPrint('📋 Applied template: $templateId');
  }

  String _getTemplateEmoji(String type) {
    switch (type) {
      case 'onboarding':
        return '👋';
      case 'promotion':
        return '🎉';
      case 'alert':
        return '⚠️';
      case 'transaction':
        return '💳';
      case 'commission':
        return '💰';
      case 'referral':
        return '👥';
      case 'kyc':
        return '📋';
      case 'announcement':
        return '📢';
      default:
        return '✏️';
    }
  }

  Color _getTemplateColor(String type) {
    switch (type) {
      case 'onboarding':
        return const Color(0xFF4A90E2);
      case 'promotion':
        return const Color(0xFFF59E0B);
      case 'alert':
        return const Color(0xFFEF4444);
      case 'transaction':
        return const Color(0xFF219C7E);
      case 'commission':
        return const Color(0xFF8B5CF6);
      case 'referral':
        return const Color(0xFFEC4899);
      case 'kyc':
        return const Color(0xFF3B82F6);
      case 'announcement':
        return const Color(0xFFF97316);
      default:
        return primaryColor;
    }
  }

  // ==================== USER SELECTION METHODS ====================

  void _toggleUserSelection(Map<String, dynamic> user) {
    setState(() {
      final isSelected = _selectedUsers.any((u) => u['_id'] == user['_id']);
      if (isSelected) {
        _selectedUsers.removeWhere((u) => u['_id'] == user['_id']);
      } else {
        _selectedUsers.add(user);
      }
      debugPrint('👤 Selected users: ${_selectedUsers.length}');
    });
  }

  void _clearSelectedUsers() {
    setState(() {
      _selectedUsers.clear();
    });
    debugPrint('🗑️ Cleared all selected users');
  }

  void _selectAllUsers() {
    setState(() {
      _selectedUsers = List<Map<String, dynamic>>.from(_users);
      debugPrint('✅ Selected all ${_selectedUsers.length} users');
    });
  }

  String _getRecipientDisplay() {
    if (_sendToAll) return 'All Active Users';
    if (_selectedUsers.isEmpty) return 'No users selected';
    if (_selectedUsers.length == 1) {
      return _selectedUsers.first['fullName'] ?? 'User';
    }
    return '${_selectedUsers.length} users selected';
  }

  // ==================== SEND NOTIFICATION ====================

  Future<void> _sendNotification() async {
    if (!_formKey.currentState!.validate()) {
      _showSnackBar("Please fill in all required fields", true);
      return;
    }

    // Check if users are selected when not sending to all
    if (!_sendToAll && _selectedUsers.isEmpty) {
      _showSnackBar("Please select at least one user", true);
      return;
    }

    setState(() => _isSending = true);

    try {
      final title = _titleController.text.trim();
      final messageTemplate = _messageController.text.trim();

      // Get recipient IDs and user names
      List<String> recipientIds = [];
      List<Map<String, String>> userNames = [];

      if (_sendToAll) {
        // Send to all - no personalization needed
        recipientIds = [];
        userNames = [];
      } else {
        // ✅ Build user names list from selected users
        for (var user in _selectedUsers) {
          final userId = user['_id']?.toString() ?? '';
          final fullName = user['fullName']?.toString() ?? 'User';
          final firstName = fullName.split(' ').first;

          if (userId.isNotEmpty) {
            recipientIds.add(userId);
            userNames.add({
              'id': userId,
              'name': fullName,
              'firstName': firstName,
            });
          }
        }

        // ✅ DEBUG: Log the user names for verification
        debugPrint('📋 User names for personalization: $userNames');
      }

      debugPrint(
        '📨 Sending notification to ${_sendToAll ? "ALL" : "${recipientIds.length} users"}',
      );
      debugPrint('📝 Title: $title');
      debugPrint('📝 Template: $messageTemplate');

      // 1. Send via API to save to database
      String apiMessage = messageTemplate;
      if (!_sendToAll && userNames.isNotEmpty) {
        // Personalize for the first user (API only sends to one user at a time)
        final firstName = userNames.first['firstName'] ?? 'User';
        apiMessage = _personalizeMessage(messageTemplate, firstName);
      }

      final response = await ApiService.sendNotification(
        title: title,
        message: apiMessage,
        recipientId: _sendToAll ? null : recipientIds.first,
        sendToAll: _sendToAll,
      );

      if (response['success'] == true) {
        // 2. Send via WebSocket for real-time delivery - personalized per user
        await _sendViaWebSocket(
          title: title,
          messageTemplate: messageTemplate,
          recipientIds: recipientIds,
          userNames: userNames,
          sendToAll: _sendToAll,
        );

        _showSuccessModal(
          title: '✅ Notification Sent!',
          message: response['message'] ?? 'Notification sent successfully!',
          recipient:
              _sendToAll
                  ? 'All Active Users'
                  : '${_selectedUsers.length} user(s)',
          sentCount: response['sentCount'] ?? recipientIds.length,
          templateType: _selectedTemplateType,
        );

        // Reset form
        _titleController.clear();
        _messageController.clear();
        setState(() {
          _sendToAll = true;
          _selectedUsers.clear();
          _selectedTemplate = 'custom';
          _sentNotifications++;
        });

        await _fetchUsers();
      } else {
        throw Exception(response['message'] ?? "Failed to send notification");
      }
    } catch (e) {
      debugPrint('❌ Send notification error: $e');
      _showSnackBar("❌ Error: ${e.toString()}", true);
    } finally {
      setState(() => _isSending = false);
    }
  }

  /// Personalize the message for each user
  /// Personalize the message for each user
  String _personalizeMessage(String template, String userName) {
    if (template.isEmpty) return template;

    // ✅ Debug the input
    debugPrint('🔧 Personalizing: "$template" with "$userName"');

    // Replace all variations of user placeholders
    String personalized = template;

    // Replace [User] with the user's first name
    personalized = personalized.replaceAll('[User]', userName);
    // Also handle [user] (lowercase)
    personalized = personalized.replaceAll('[user]', userName);
    // Handle [Customer] as alternative
    personalized = personalized.replaceAll('[Customer]', userName);
    // Handle [Name] as alternative
    personalized = personalized.replaceAll('[Name]', userName);
    // Handle [First Name]
    personalized = personalized.replaceAll('[FirstName]', userName);

    // ✅ Debug the output
    debugPrint('🔧 Result: "$personalized"');

    return personalized;
  }

  Future<void> _sendViaWebSocket({
    required String title,
    required String messageTemplate,
    List<String>? recipientIds,
    List<Map<String, String>>? userNames,
    bool sendToAll = true,
  }) async {
    try {
      final socketService = SocketService();

      if (socketService.isConnected) {
        if (!sendToAll && recipientIds != null && recipientIds.isNotEmpty) {
          debugPrint(
            '📤 Sending personalized notifications to ${recipientIds.length} users',
          );

          // Send personalized message to each recipient
          for (int i = 0; i < recipientIds.length; i++) {
            final userId = recipientIds[i];

            // Get the user's first name
            String firstName = 'User';
            if (userNames != null && i < userNames.length) {
              firstName = userNames[i]['firstName'] ?? 'User';
            }

            // ✅ DEBUG: Log the personalization
            debugPrint('📝 Personalizing for user $i: "$firstName"');

            // Personalize the message for this user
            final personalizedMessage = _personalizeMessage(
              messageTemplate,
              firstName,
            );

            // ✅ DEBUG: Log the personalized message
            debugPrint('📝 Personalized message: "$personalizedMessage"');

            socketService.emit('admin_notification', {
              'title': title,
              'message': personalizedMessage,
              'recipientId': userId,
              'sendToAll': false,
              'type':
                  _selectedTemplateType.isNotEmpty
                      ? _selectedTemplateType
                      : 'general',
              'screen': 'notifications',
            });

            final userName =
                (userNames != null && i < userNames.length)
                    ? userNames[i]['name'] ?? 'User'
                    : 'User';
            debugPrint('📤 Sent to $userName: "$title"');
          }
          debugPrint(
            '✅ Sent ${recipientIds.length} personalized notifications via SocketService',
          );
        } else {
          // Send to all - no personalization needed
          socketService.emit('admin_notification', {
            'title': title,
            'message': messageTemplate,
            'sendToAll': true,
            'type':
                _selectedTemplateType.isNotEmpty
                    ? _selectedTemplateType
                    : 'general',
            'screen': 'notifications',
          });
          debugPrint('✅ Notification sent to ALL via SocketService');
        }
      } else {
        debugPrint('⚠️ Socket not connected, notification saved to database');
      }
    } catch (e) {
      debugPrint('⚠️ WebSocket send error: $e');
    }
  }

  void _showSuccessModal({
    required String title,
    required String message,
    required String recipient,
    required int sentCount,
    String templateType = '',
  }) {
    final emoji = _getTemplateEmoji(templateType);
    final color = _getTemplateColor(templateType);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            title: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: successColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 32)),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: GoogleFonts.inter(fontSize: 14, color: textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: backgroundLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person_rounded,
                        color: primaryColor,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sent to: $recipient',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      if (sentCount > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '+$sentCount',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: primaryColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (templateType.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _getTemplateEmoji(templateType),
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Template: ${_getTemplateTypeLabel(templateType)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: backgroundLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        color: primaryColor,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sent: ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'OK',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
    );
  }

  String _getTemplateTypeLabel(String type) {
    switch (type) {
      case 'onboarding':
        return 'Welcome/Onboarding';
      case 'promotion':
        return 'Promotional';
      case 'alert':
        return 'Alert';
      case 'transaction':
        return 'Transaction';
      case 'commission':
        return 'Commission';
      case 'referral':
        return 'Referral';
      case 'kyc':
        return 'KYC';
      case 'announcement':
        return 'Announcement';
      default:
        return 'Custom';
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

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 16 : 20,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF92D394), Color(0xFF1E377E)],
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
                  'Admin / Notifications',
                  style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.7),
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
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.notifications_active_rounded,
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
                      'Send Notification',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: isMobile ? 20 : 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: isMobile ? 4 : 6),
                    Text(
                      'Send messages to users',
                      style: GoogleFonts.inter(
                        color: Colors.white.withOpacity(0.8),
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
            value: _totalUsers.toString(),
            icon: HugeIcons.strokeRoundedUser,
            color: primaryColor,
            isMobile: isMobile,
          ),
          _buildStatCard(
            title: 'Active Users',
            value: _activeUsers.toString(),
            icon: HugeIcons.strokeRoundedUserCheck01,
            color: successColor,
            isMobile: isMobile,
          ),
          _buildStatCard(
            title: 'Sent',
            value: _sentNotifications.toString(),
            icon: HugeIcons.strokeRoundedSent02,
            color: const Color(0xFF3B82F6),
            isMobile: isMobile,
          ),
          _buildStatCard(
            title: 'Success Rate',
            value: '${_successRate.toStringAsFixed(1)}%',
            icon: HugeIcons.strokeRoundedAutoConversations,
            color: const Color(0xFFF59E0B),
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
                    style: GoogleFonts.poppins(
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

  // ==================== TEMPLATE GRID BUILDER ====================

  Widget _buildTemplateGrid() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📋 Quick Templates',
            style: GoogleFonts.inter(
              fontSize: isMobile ? 13 : 14,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: isMobile ? 130 : 160,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _templates.length,
              itemBuilder: (context, index) {
                final template = _templates[index];
                final isSelected = _selectedTemplate == template['id'];
                final color = _getTemplateColor(template['type'] ?? '');

                return GestureDetector(
                  onTap: () => _applyTemplate(template['id']),
                  child: Container(
                    width: isMobile ? 110 : 140,
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? color.withOpacity(0.1) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? color : Colors.grey.shade200,
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: HugeIcon(
                            icon: template['icon'],
                            color: color,
                            size: isMobile ? 18 : 22,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          template['name'],
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 8 : 10,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? color : textSecondary,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isSelected)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: Color(0xFF219C7E),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==================== RECIPIENT SELECTION UI ====================

  Widget _buildRecipientChip({
    required String label,
    required dynamic icon,
    required bool selected,
    required VoidCallback onTap,
    required bool isMobile,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 10 : 12,
          vertical: isMobile ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: selected ? primaryColor.withOpacity(0.1) : backgroundLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? primaryColor : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(
              icon: icon,
              color: selected ? primaryColor : textSecondary,
              size: isMobile ? 16 : 18,
            ),
            SizedBox(width: isMobile ? 6 : 8),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  color: selected ? primaryColor : textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: isMobile ? 12 : 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle_rounded,
                color: primaryColor,
                size: isMobile ? 16 : 18,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedUsersChips() {
    if (_selectedUsers.isEmpty) return const SizedBox.shrink();

    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedUserGroup,
                    color: primaryColor,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_selectedUsers.length} user${_selectedUsers.length > 1 ? 's' : ''} selected',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 12 : 13,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (_selectedUsers.length > 1)
                    GestureDetector(
                      onTap: _clearSelectedUsers,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: errorColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: errorColor.withOpacity(0.2),
                          ),
                        ),
                        child: Text(
                          'Clear All',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 10 : 11,
                            fontWeight: FontWeight.w600,
                            color: errorColor,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children:
                _selectedUsers.map((user) {
                  final name = user['fullName'] ?? 'Unknown';
                  final email = user['email'] ?? '';
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: primaryColor.withOpacity(0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: isMobile ? 10 : 12,
                          backgroundColor: primaryColor.withOpacity(0.1),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: GoogleFonts.inter(
                              color: primaryColor,
                              fontSize: isMobile ? 8 : 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 10 : 11,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (email.isNotEmpty)
                              Text(
                                email,
                                style: GoogleFonts.inter(
                                  fontSize: isMobile ? 8 : 9,
                                  color: textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                        GestureDetector(
                          onTap: () => _toggleUserSelection(user),
                          child: Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.close_rounded,
                              color: errorColor,
                              size: isMobile ? 12 : 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildUserSelection(bool isMobile) {
    return Container(
      constraints: BoxConstraints(maxHeight: isMobile ? 280 : 220),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          // Search bar with select all
          Padding(
            padding: EdgeInsets.all(isMobile ? 8 : 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search users...',
                      hintStyle: GoogleFonts.inter(
                        fontSize: isMobile ? 12 : 13,
                        color: Colors.grey.shade400,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: primaryColor,
                        size: isMobile ? 18 : 20,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: primaryColor, width: 1.5),
                      ),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 8 : 10,
                        vertical: isMobile ? 8 : 10,
                      ),
                    ),
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 13 : 14,
                      color: textPrimary,
                    ),
                  ),
                ),
                if (_filteredUsers.isNotEmpty && !_sendToAll)
                  GestureDetector(
                    onTap: () {
                      final allSelected = _filteredUsers.every(
                        (user) =>
                            _selectedUsers.any((u) => u['_id'] == user['_id']),
                      );
                      if (allSelected) {
                        // Remove all filtered users from selection
                        final ids =
                            _filteredUsers.map((u) => u['_id']).toList();
                        setState(() {
                          _selectedUsers.removeWhere(
                            (u) => ids.contains(u['_id']),
                          );
                        });
                      } else {
                        // Add all filtered users to selection
                        for (var user in _filteredUsers) {
                          if (!_selectedUsers.any(
                            (u) => u['_id'] == user['_id'],
                          )) {
                            setState(() {
                              _selectedUsers.add(user);
                            });
                          }
                        }
                      }
                      debugPrint('👤 Selected users: ${_selectedUsers.length}');
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 8 : 10,
                        vertical: isMobile ? 6 : 8,
                      ),
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: primaryColor.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedUser,
                            color: primaryColor,
                            size: isMobile ? 14 : 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Select All',
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 10 : 11,
                              fontWeight: FontWeight.w600,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Selected users chips
          _buildSelectedUsersChips(),

          // User list with search results
          Expanded(
            child:
                _filteredUsers.isEmpty
                    ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(isMobile ? 16 : 20),
                        child: Text(
                          _users.isEmpty
                              ? 'No users found'
                              : 'No matching users',
                          style: GoogleFonts.inter(
                            color: textSecondary,
                            fontSize: isMobile ? 13 : 14,
                          ),
                        ),
                      ),
                    )
                    : ListView.builder(
                      padding: EdgeInsets.all(isMobile ? 4 : 8),
                      itemCount: _filteredUsers.length,
                      itemBuilder: (context, index) {
                        final user = _filteredUsers[index];
                        final userName = user['fullName'] ?? 'Unknown';
                        final userEmail = user['email'] ?? 'No email';
                        final isSelected = _selectedUsers.any(
                          (u) => u['_id'] == user['_id'],
                        );

                        return ListTile(
                          leading: CircleAvatar(
                            radius: isMobile ? 16 : 18,
                            backgroundColor: primaryColor.withOpacity(0.1),
                            child: Text(
                              userName.isNotEmpty
                                  ? userName[0].toUpperCase()
                                  : '?',
                              style: GoogleFonts.inter(
                                color: primaryColor,
                                fontSize: isMobile ? 12 : 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text(
                            userName,
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 13 : 14,
                              fontWeight: FontWeight.w500,
                              color: isSelected ? primaryColor : textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                          trailing:
                              isSelected
                                  ? Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF219C7E),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  )
                                  : null,
                          onTap: () => _toggleUserSelection(user),
                          dense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 8 : 12,
                            vertical: 2,
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipientSection(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recipient',
          style: GoogleFonts.inter(
            fontSize: isMobile ? 14 : 16,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Select users to receive this notification',
          style: GoogleFonts.inter(
            fontSize: isMobile ? 11 : 12,
            color: textSecondary,
          ),
        ),
        SizedBox(height: isMobile ? 8 : 12),

        // Toggle buttons
        Row(
          children: [
            Expanded(
              child: _buildRecipientChip(
                label: 'All Active Users',
                icon: HugeIcons.strokeRoundedUser,
                selected: _sendToAll,
                onTap: () {
                  setState(() {
                    _sendToAll = true;
                    _selectedUsers.clear();
                  });
                },
                isMobile: isMobile,
              ),
            ),
            SizedBox(width: isMobile ? 8 : 12),
            Expanded(
              child: _buildRecipientChip(
                label: 'Select Users',
                icon: HugeIcons.strokeRoundedUserCheck01,
                selected: !_sendToAll,
                onTap: () {
                  setState(() {
                    _sendToAll = false;
                  });
                },
                isMobile: isMobile,
              ),
            ),
          ],
        ),

        // Specific user selection
        if (!_sendToAll) ...[
          SizedBox(height: isMobile ? 12 : 16),
          _buildUserSelection(isMobile),
        ],
      ],
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required dynamic icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
    required bool isMobile,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: GoogleFonts.inter(
          fontSize: isMobile ? 14 : 15,
          color: textPrimary,
        ),
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: GoogleFonts.inter(
            color: textSecondary,
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
              color: primaryColor.withOpacity(0.5),
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

  Widget _buildNotificationForm() {
    final isMobile = MediaQuery.of(context).size.width < 600;

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
              color: Colors.black.withOpacity(0.04),
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
                      color: primaryColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedSent02,
                      color: primaryColor,
                      size: isMobile ? 20 : 24,
                    ),
                  ),
                  SizedBox(width: isMobile ? 10 : 14),
                  Text(
                    'Compose Notification',
                    style: GoogleFonts.poppins(
                      fontSize: isMobile ? 16 : 18,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: isMobile ? 16 : 20),

              // Template Grid
              _buildTemplateGrid(),
              const Divider(),
              const SizedBox(height: 12),

              // Recipient Section
              _buildRecipientSection(isMobile),
              SizedBox(height: isMobile ? 16 : 20),

              // Title Field
              _buildFormField(
                controller: _titleController,
                label: 'Notification Title *',
                hint: 'Enter a clear, descriptive title',
                icon: HugeIcons.strokeRoundedKite,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
                isMobile: isMobile,
              ),
              SizedBox(height: isMobile ? 12 : 14),

              // Message Field - Updated with personalization hint
              _buildFormField(
                controller: _messageController,
                label: 'Message Content *',
                hint:
                    'Write your message here... Use [User] for personalization',
                icon: HugeIcons.strokeRoundedMessage01,
                maxLines: isMobile ? 4 : 5,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a message';
                  }
                  return null;
                },
                isMobile: isMobile,
              ),

              // ============================================================
              // ✅ STEP 5: ADD THIS PERSONALIZATION INFO INDICATOR
              // ============================================================
              if (!_sendToAll && _selectedUsers.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: primaryColor.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedUser,
                        color: primaryColor,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '💡 [User] will be replaced with each user\'s name (${_selectedUsers.length} users)',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 10 : 11,
                            color: primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // ============================================================

              // Character count
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${_messageController.text.length} characters',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color:
                          _messageController.text.length > 500
                              ? errorColor
                              : textSecondary,
                    ),
                  ),
                ),
              ),
              SizedBox(height: isMobile ? 16 : 20),

              // Send Button
              SizedBox(
                width: double.infinity,
                height: isMobile ? 48 : 50,
                child: ElevatedButton(
                  onPressed: _isSending ? null : _sendNotification,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child:
                      _isSending
                          ? const SizedBox(
                            width: 20,
                            height: 20,
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
                                icon: HugeIcons.strokeRoundedSent02,
                                color: Colors.white,
                                size: isMobile ? 18 : 20,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Send Notification',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: isMobile ? 14 : 16,
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
    );
  }

  Widget _buildLoadingState() {
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
              'Loading notification admin panel...',
              style: GoogleFonts.inter(fontSize: 14, color: textSecondary),
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
                  color: errorColor.withOpacity(0.08),
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
    if (_isLoading) {
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
          (item) => item.title == "Notifications",
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
                  _buildStatsSection(),
                  _buildNotificationForm(),
                  const SizedBox(height: 40),
                ],
              ),
            ),

            // Loading Overlay
            if (_isSending)
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
                          'Sending notification...',
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
