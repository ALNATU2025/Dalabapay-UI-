// lib/features/settings/screens/settings_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/biometric_service.dart';
import '../change_password_screen.dart';
import '../change_pin_screen.dart';
import '../kyc/kyc_screen.dart';
import '../../../core/services/payment_service.dart';
import '../../../core/services/update_service.dart';
import '../../../core/utils/image_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  // ==================== STATE VARIABLES ====================
  Map<String, dynamic> userData = {};
  String fullName = '';
  String email = '';
  String phone = '';
  double walletBalance = 0.0;
  double commissionBalance = 0.0;
  bool isLoading = true;
  bool isUpdating = false;
  bool notificationsEnabled = true;
  bool biometricEnabled = false;
  bool darkModeEnabled = false;
  bool twoFactorEnabled = false;
  bool isActive = true;
  bool transactionPinSet = false;
  Map<String, dynamic>? virtualAccount;
  Map<String, dynamic>? securitySettings;
  Map<String, dynamic>? globalSecuritySettings;
  Map<String, dynamic>? appSettings;

  bool _hasDedicatedAccount = false;
  String? _dedicatedAccountNumber;
  String? _dedicatedAccountName;
  String? _dedicatedBankName;
  bool _isCheckingAccount = false;

  // Security fields
  bool pinLocked = false;
  int lockTimeRemaining = 0;
  int failedPinAttempts = 0;
  bool biometricAvailable = false;
  bool biometricAllowed = true;
  bool pinRequired = true;

  // Profile image
  String? profileImageUrl;

  // ✅ Stable cache-buster (regenerated ONLY when image changes)
  String _profileImageCacheBuster =
      DateTime.now().millisecondsSinceEpoch.toString();

  final LocalAuthentication _localAuth = LocalAuthentication();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isCheckingBiometric = true;
  bool _isTogglingBiometric = false;

  // Animation
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // ==================== BRAND COLORS ====================
  static const Color _primaryColor = Color(0xFF243889);
  static const Color _secondaryColor = Color(0xFF219C7E);
  static const Color _successColor = Color(0xFF219C7E);
  static const Color _warningColor = Color(0xFFF59E0B);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _textPrimary = Color(0xFF1C2D5A);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _backgroundLight = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeSettings();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // ==================== INITIALIZATION ====================
  Future<void> _initializeSettings() async {
    await _loadSettings();
    await _loadUserData();
    await _loadSecuritySettings();
    await _loadAppSettings();
    await _checkBiometricAvailabilityAndStatus();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
      darkModeEnabled = prefs.getBool('darkModeEnabled') ?? false;
      twoFactorEnabled = prefs.getBool('twoFactorEnabled') ?? false;
    });
  }

  Future<void> _loadUserData() async {
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString('user');
      if (userString != null) {
        userData = jsonDecode(userString);
        final userId = userData['_id'];

        // ✅ Load profile image from userData
        String? loadedImage = userData['profileImage'];

        // Also check if there's a separate stored profile image
        if (loadedImage == null || loadedImage.isEmpty) {
          final savedImage = prefs.getString('profileImage');
          if (savedImage != null && savedImage.isNotEmpty) {
            loadedImage = savedImage;
          }
        }

        setState(() {
          fullName = userData['fullName'] ?? '';
          email = userData['email'] ?? '';
          phone = userData['phone'] ?? '';
          walletBalance = (userData['walletBalance'] ?? 0.0).toDouble();
          commissionBalance = (userData['commissionBalance'] ?? 0.0).toDouble();
          isActive = userData['isActive'] ?? true;
          profileImageUrl = loadedImage;
        });

        debugPrint('📸 Profile image URL loaded: $profileImageUrl');

        // Check biometric status using the service
        if (userId != null) {
          final biometricEnabledStatus = await biometricService
              .getBiometricEnabledStatus(userId: userId.toString());

          setState(() {
            biometricEnabled = biometricEnabledStatus;
          });
        }

        if (userId != null) {
          try {
            final freshUserData = await ApiService.getUserProfile(userId);
            if (freshUserData['success'] != false) {
              // ✅ Update profile image from fresh data
              String? freshImage = freshUserData['profileImage'];
              if (freshImage != null && freshImage.isNotEmpty) {
                profileImageUrl = freshImage;
                await prefs.setString('profileImage', freshImage);
              }

              setState(() {
                userData = freshUserData;
                fullName = freshUserData['fullName'] ?? '';
                email = freshUserData['email'] ?? '';
                phone = freshUserData['phone'] ?? '';
                walletBalance =
                    (freshUserData['walletBalance'] ?? 0.0).toDouble();
                commissionBalance =
                    (freshUserData['commissionBalance'] ?? 0.0).toDouble();
                isActive = freshUserData['isActive'] ?? true;

                // ✅ Bump cache-buster ONLY if the image path changed
                if (freshImage != null &&
                    freshImage.isNotEmpty &&
                    freshImage != profileImageUrl) {
                  profileImageUrl = freshImage;
                  _profileImageCacheBuster =
                      DateTime.now().millisecondsSinceEpoch.toString();
                } else if (freshImage != null && freshImage.isNotEmpty) {
                  profileImageUrl = freshImage;
                }

                transactionPinSet = _checkTransactionPinStatus(freshUserData);
              });

              await prefs.setString('user', jsonEncode(freshUserData));
              await prefs.setBool('transactionPinSet', transactionPinSet);
            }
          } catch (e) {
            debugPrint('Error fetching fresh user data: $e');
            transactionPinSet = _checkTransactionPinStatus(userData);
          }
        } else {
          transactionPinSet = _checkTransactionPinStatus(userData);
        }

        // Check for dedicated account
        try {
          final virtualAccountDetails =
              await ApiService.getUserVirtualAccount();
          setState(() {
            virtualAccount = virtualAccountDetails;

            if (virtualAccountDetails != null &&
                virtualAccountDetails['accountNumber'] != null) {
              final accNumber = virtualAccountDetails['accountNumber'];
              final accName = virtualAccountDetails['accountName'];
              final bankName = virtualAccountDetails['bankName'];

              if (accNumber != null &&
                  accNumber.isNotEmpty &&
                  accNumber != 'Account Pending' &&
                  accNumber != 'Pending') {
                setState(() {
                  _hasDedicatedAccount = true;
                  _dedicatedAccountNumber = accNumber;
                  _dedicatedAccountName = accName ?? fullName;
                  _dedicatedBankName = bankName ?? 'Moniepoint MFB';
                });

                debugPrint(
                  '✅ Settings - Found dedicated account from virtualAccount: $accNumber',
                );
              }
            }
          });
        } catch (e) {
          debugPrint('Error fetching virtual account: $e');
        }

        await _checkDedicatedAccount();
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      _showSnackBar('Error loading user data. Please try again.');
    } finally {
      setState(() => isLoading = false);
    }
  }

  bool _checkTransactionPinStatus(Map<String, dynamic> userData) {
    return (userData['transactionPinSet'] ?? false) ||
        (userData['hasTransactionPin'] ?? false) ||
        (userData['transactionPin'] != null &&
            userData['transactionPin'].toString().isNotEmpty &&
            userData['transactionPin'].toString() != 'null') ||
        (userData['pinSet'] ?? false) ||
        (userData['isPinSet'] ?? false);
  }

  Future<void> _loadSecuritySettings() async {
    try {
      final settings = await ApiService.getSecuritySettings();
      if (settings['success'] == true) {
        setState(() {
          securitySettings = settings['securitySettings'] ?? {};
          pinLocked = securitySettings?['pinLocked'] ?? false;
          lockTimeRemaining = securitySettings?['lockTimeRemaining'] ?? 0;
          failedPinAttempts = securitySettings?['failedPinAttempts'] ?? 0;
        });
      }

      final globalSettings = await ApiService.getGlobalSecuritySettings();
      setState(() {
        globalSecuritySettings = globalSettings;
        pinRequired = globalSettings['pinRequired'] ?? true;
        biometricAllowed = globalSettings['biometricAllowed'] ?? true;
      });
    } catch (e) {
      debugPrint('Error loading security settings: $e');
    }
  }

  Future<void> _loadAppSettings() async {
    try {
      final settings = await ApiService.getAppSettings();
      if (settings['success'] == true) {
        setState(() {
          appSettings = settings;
        });
      }
    } catch (e) {
      debugPrint('Error loading app settings: $e');
    }
  }

  // ==================== BIOMETRIC ====================
  Future<void> _checkBiometricAvailabilityAndStatus() async {
    setState(() => _isCheckingBiometric = true);

    try {
      final String? userId = userData['_id']?.toString();

      // Use the biometric service to get status
      final bool isAvailable = await biometricService.isBiometricAvailable();
      final bool isEnabled = await biometricService.getBiometricEnabledStatus(
        userId: userId,
      );

      setState(() {
        biometricAvailable = isAvailable;
        biometricEnabled = isEnabled;
        _isCheckingBiometric = false;
      });

      debugPrint(
        'Biometric loaded for user $userId → enabled: $biometricEnabled, available: $biometricAvailable',
      );
    } catch (e) {
      debugPrint('Error checking biometric: $e');
      setState(() => _isCheckingBiometric = false);
    }
  }

  Future<void> _handleBiometricToggle(bool value) async {
    if (_isTogglingBiometric) return;

    // Disabling Biometric
    if (!value && biometricEnabled) {
      final confirm = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Disable Biometric?',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
              ),
              content: Text(
                "You'll need to use PIN for all future logins.",
                style: GoogleFonts.poppins(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Cancel', style: GoogleFonts.poppins()),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    'Disable',
                    style: GoogleFonts.poppins(color: _errorColor),
                  ),
                ),
              ],
            ),
      );

      if (confirm != true) return;

      setState(() => _isTogglingBiometric = true);
      try {
        await _toggleBiometricInApp(false);
        _showSnackBar('Biometric disabled');
      } finally {
        setState(() => _isTogglingBiometric = false);
      }
      return;
    }

    // Check if Transaction PIN is set first
    if (!transactionPinSet) {
      _showSnackBar('Please set Transaction PIN first');
      return;
    }

    setState(() => _isTogglingBiometric = true);

    try {
      final bool didAuthenticate = await biometricService.authenticate(
        reason: 'Enable biometric authentication for DalabaPay',
        biometricOnly: false, // Allow fallback if needed
        stickyAuth: true, // MUST BE TRUE FOR BOTH ANDROID AND IOS
      );

      if (didAuthenticate) {
        final String? userId = userData['_id']?.toString();
        if (userId != null) {
          await biometricService.toggleBiometric(userId: userId, enable: true);
        }

        await _checkBiometricAvailabilityAndStatus();
        _showSnackBar('Biometric enabled successfully!', color: _successColor);
        _showBiometricSuccessAnimation();
      } else {
        _showSnackBar('Authentication cancelled');
      }
    } on PlatformException catch (e) {
      debugPrint('Biometric error: ${e.code} - ${e.message}');

      String message = 'Failed to enable biometric';

      switch (e.code) {
        case 'no_fragment_activity':
          message =
              'Configuration issue: MainActivity must extend FlutterFragmentActivity.';
          break;
        case 'NotAvailable':
        case 'notAvailable':
          message = 'Biometric authentication is not available on this device';
          break;
        case 'PasscodeNotSet':
        case 'passcodeNotSet':
          message =
              'Please set up a screen lock (PIN/Pattern) in device settings first';
          _showSetupLockScreenDialog();
          break;
        case 'NotEnrolled':
        case 'notEnrolled':
          message = 'No fingerprint or face ID registered on this device';
          _showSetupBiometricDialog();
          break;
        case 'LockedOut':
        case 'lockedOut':
          message =
              'Biometric locked due to too many attempts. Try again later.';
          break;
        case 'PermanentlyLockedOut':
        case 'permanentlyLockedOut':
          message =
              'Biometric permanently locked. Please use device PIN/Password.';
          break;
        default:
          if (e.message != null &&
              e.message!.toLowerCase().contains('cancel')) {
            message = 'Authentication cancelled';
          } else {
            message = 'Biometric setup failed: ${e.message ?? e.code}';
          }
      }

      _showSnackBar(message);
    } catch (e) {
      debugPrint('Unexpected biometric error: $e');
      _showSnackBar('Failed to enable biometric');
    } finally {
      setState(() => _isTogglingBiometric = false);
    }
  }

  Future<void> _toggleBiometricInApp(bool enable) async {
    try {
      final String? userId = userData['_id']?.toString();
      if (userId == null || userId.isEmpty) {
        debugPrint('Cannot toggle biometric: No userId found');
        return;
      }

      // Use the biometric service to toggle
      await biometricService.toggleBiometric(userId: userId, enable: enable);

      // Refresh the status
      await _checkBiometricAvailabilityAndStatus();

      debugPrint(
        '✅ Biometric ${enable ? 'enabled' : 'disabled'} for user: $userId',
      );
    } catch (e) {
      debugPrint('❌ Error toggling biometric: $e');
      rethrow;
    }
  }

  void _showSetupLockScreenDialog() {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            icon: Icon(Icons.lock_outline, size: 48, color: _warningColor),
            title: Text(
              'Screen Lock Required',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
            content: Text(
              "To use biometric login, you must first set up a screen lock (PIN, Pattern, or Password) on your device.\n\n"
              "Go to Settings → Security → Screen Lock",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Later', style: GoogleFonts.poppins()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: Text('Open Settings', style: GoogleFonts.poppins()),
              ),
            ],
          ),
    );
  }

  void _showSetupBiometricDialog() {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            icon: Icon(Icons.fingerprint, size: 48, color: _primaryColor),
            title: Text(
              'Setup Biometric',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
            content: Text(
              "No fingerprint or face ID is set up on this device.\n\n"
              "Go to Settings → Security → Fingerprint / Face Unlock",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Later', style: GoogleFonts.poppins()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: Text('Open Settings', style: GoogleFonts.poppins()),
              ),
            ],
          ),
    );
  }

  void _showBiometricSuccessAnimation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _successColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle,
                      size: 48,
                      color: _successColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Biometric Enabled!',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You can now use fingerprint or face recognition',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: _textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Continue',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  void _navigateToKYC() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const KYCScreen()),
    ).then((result) {
      if (result == true) {
        _showSnackBar('✅ KYC completed! Checking your account...');
        _checkDedicatedAccount();
      }
    });
  }

  Future<void> _checkDedicatedAccount() async {
    final userId = userData['_id']?.toString();
    if (userId == null) return;

    setState(() => _isCheckingAccount = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cashwyre_reserve_account_$userId');

      final result = await PaymentService.checkDedicatedAccount(userId: userId);

      debugPrint('📦 Settings - Dedicated account check result: $result');

      if (mounted) {
        final bool hasAccount =
            result['success'] == true && result['hasAccount'] == true;

        setState(() {
          _hasDedicatedAccount = hasAccount;
          _dedicatedAccountNumber = hasAccount ? result['accountNumber'] : null;
          _dedicatedAccountName = hasAccount ? result['accountName'] : null;
          _dedicatedBankName = hasAccount ? result['bankName'] : null;
          _isCheckingAccount = false;
        });

        if (hasAccount && _dedicatedAccountNumber != null) {
          final prefs = await SharedPreferences.getInstance();
          final userString = prefs.getString('user');
          if (userString != null) {
            try {
              final userMap = jsonDecode(userString);
              userMap['kycVerified'] = true;
              userMap['hasDedicatedAccount'] = true;
              userMap['virtualAccount'] = {
                'assigned': true,
                'accountNumber': _dedicatedAccountNumber,
                'accountName': _dedicatedAccountName,
                'bankName': _dedicatedBankName,
              };
              await prefs.setString('user', jsonEncode(userMap));

              setState(() {
                userData = userMap;
              });
            } catch (e) {
              debugPrint('Error updating userData: $e');
            }
          }
        }

        debugPrint('Settings - hasDedicatedAccount: $_hasDedicatedAccount');
      }
    } catch (e) {
      debugPrint('Error checking dedicated account in settings: $e');
      setState(() => _isCheckingAccount = false);
    }
  }

  // ==================== SETTINGS ACTIONS ====================
  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _toggleDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkModeEnabled', value);

    setState(() {
      darkModeEnabled = value;
    });

    _showSnackBar(value ? 'Dark mode enabled' : 'Light mode enabled');
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() {
      notificationsEnabled = value;
    });
    await _saveSetting('notificationsEnabled', value);
    _showSnackBar(value ? 'Notifications enabled' : 'Notifications disabled');
  }

  Future<void> _pickProfileImage() async {
    if (isUpdating) return;

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 500,
        maxHeight: 500,
        imageQuality: 80,
      );

      if (image == null) return;

      // ✅ Check file size uniformly (works on web and mobile)
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) {
        _showSnackBar('Image file is empty');
        return;
      }

      // ~2MB safety cap (backend also enforces 2MB)
      if (bytes.lengthInBytes > 2 * 1024 * 1024) {
        _showSnackBar('Image too large. Please choose an image under 2MB.');
        return;
      }

      setState(() => isUpdating = true);
      _showSnackBar('Uploading image...', color: Colors.blue);

      // ✅ Pass the XFile directly — ApiService handles web vs mobile
      final result = await ApiService.uploadProfileImage(imageFile: image);

      debugPrint('📸 Upload result: $result');

      // Extract new image path (raw from backend, e.g. /uploads/xxx.jpg)
      String? rawPath;
      if (result['success'] == true && result['profileImage'] != null) {
        rawPath = result['profileImage'].toString();
      } else if (result['data'] != null &&
          result['data']['profileImage'] != null) {
        rawPath = result['data']['profileImage'].toString();
      } else {
        throw Exception(result['message'] ?? 'Failed to upload image');
      }

      // ✅ STORE RAW PATH (relative) — ImageHelper will build the full URL at display
      debugPrint('✅ Profile image uploaded. Raw path: $rawPath');

      // ✅ 1. Force-evict ALL cached images from this app
      // This is CRITICAL on Flutter Web where the browser caches images aggressively.
      // We evict the OLD URL (whatever it was) so a fresh fetch happens.
      final oldUrl = profileImageUrl;
      if (oldUrl != null && oldUrl.isNotEmpty) {
        final oldResolved = ImageHelper.buildImageUrl(oldUrl);
        if (oldResolved != null) {
          await NetworkImage(oldResolved).evict();
          debugPrint('🗑️ Evicted old image from cache: $oldResolved');
        }
      }

      // Also evict any previously-cached version of the new URL (in case of retries)
      final newResolved = ImageHelper.buildImageUrl(rawPath);
      if (newResolved != null) {
        await NetworkImage(newResolved).evict();
        debugPrint('🗑️ Evicted new image from cache: $newResolved');
      }

      // ✅ 2. Update local storage with RAW path
      final prefs = await SharedPreferences.getInstance();

      // Preserve the entire userData map but replace profileImage
      final updatedUser = Map<String, dynamic>.from(userData);
      updatedUser['profileImage'] = rawPath;
      // Bump updatedAt so cache buster changes on next render
      updatedUser['updatedAt'] = DateTime.now().toIso8601String();

      await prefs.setString('user', jsonEncode(updatedUser));
      await prefs.setString('profileImage', rawPath);

      // ✅ 3. Update state — forces rebuild with new raw path
      // ✅ 3. Update state — forces rebuild with new raw path AND new cache-buster
      if (!mounted) return;
      setState(() {
        userData = updatedUser;
        profileImageUrl = rawPath; // RAW path only — ImageHelper resolves it
        // ✅ Regenerate cache-buster — this is the ONLY place it should change
        _profileImageCacheBuster =
            DateTime.now().millisecondsSinceEpoch.toString();
        isUpdating = false;
      });

      _showSnackBar('Profile image updated!', color: _successColor);
    } catch (e, stackTrace) {
      final errorMsg = e.toString();
      debugPrint('❌ Upload error: $errorMsg');
      debugPrint('Stack trace: $stackTrace');

      if (errorMsg.contains('Invalid file type') || errorMsg.contains('web')) {
        _showSnackBar('Please select a valid image file (JPEG, PNG, etc.)');
      } else if (errorMsg.contains('multipart') || errorMsg.contains('File')) {
        _showSnackBar('Error uploading file. Please try again.');
      } else {
        _showSnackBar(
          'Error uploading image: ${errorMsg.replaceAll('Exception: ', '')}',
        );
      }
      if (mounted) setState(() => isUpdating = false);
    }
  }

  // ==================== SUPPORT ACTIONS ====================
  void _showHelpCenterDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.help_outline, color: _primaryColor, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Help Center',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Get in touch with our support team:',
                  style: GoogleFonts.poppins(fontSize: 16, color: _textPrimary),
                ),
                const SizedBox(height: 20),
                _buildContactInfoRow(
                  Icons.email,
                  'Email:',
                  'support@dalabapay.com',
                ),
                const SizedBox(height: 16),
                _buildContactInfoRow(
                  Icons.phone,
                  'WhatsApp:',
                  '+234 916 320 7050',
                ),
                const SizedBox(height: 20),
                Text(
                  'We\'re available 24/7 to assist you.',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: _textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: _primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  'Close',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildContactInfoRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: _primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: value));
                    _showSnackBar('Copied to clipboard');
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          value,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _primaryColor,
                          ),
                        ),
                      ),
                      Icon(Icons.content_copy, size: 16, color: _primaryColor),
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

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.language, color: _primaryColor, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Language Settings',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'App Language: English',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Currently, English is the only supported language. '
                  'We are working to add more languages in future updates.',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: _textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: _primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  'OK',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
    );
  }

  void _showPrivacyPolicyDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.privacy_tip, color: _primaryColor, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Privacy Policy',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DalabaPay Privacy Policy',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your privacy and financial security are our top priorities. '
                    'DalabaPay employs bank-level encryption and security measures to protect your data.',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: _textPrimary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• Bank-level 256-bit encryption for all data\n'
                    '• Secure transaction processing\n'
                    '• No sharing of personal data without consent\n'
                    '• Right to data access and deletion\n'
                    '• Regular security audits and compliance',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: _textPrimary,
                      height: 1.8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildCopyButton(
                    text: '''DalabaPay Privacy Policy

Your privacy and financial security are our top priorities. We employ bank-level encryption and security measures to protect your data.

• Bank-level 256-bit encryption for all data
• Secure transaction processing
• No sharing of personal data without consent
• Right to data access and deletion
• Regular security audits and compliance
• GDPR and local regulation compliance''',
                    label: 'Copy Privacy Policy',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: _primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  'Close',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
    );
  }

  void _showTermsDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.description, color: _primaryColor, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Terms & Conditions',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DalabaPay Terms of Service',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'By using DalabaPay, you agree to our terms governing financial transactions, bill payments, and account usage.',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: _textPrimary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• Users must be 18+ years of age\n'
                    '• All financial transactions are final\n'
                    '• Service fees apply as disclosed\n'
                    '• Account suspension for suspicious activity\n'
                    '• Instant bill payment processing\n'
                    '• User responsibility for account security',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: _textPrimary,
                      height: 1.8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildCopyButton(
                    text: '''DalabaPay Terms & Conditions

By using DalabaPay, you agree to our terms governing financial transactions, bill payments, and account usage.

• Users must be 18+ years of age
• All financial transactions are final
• Service fees apply as disclosed
• Account suspension for suspicious activity
• Instant bill payment processing
• User responsibility for account security
• Compliance with financial regulations''',
                    label: 'Copy Terms & Conditions',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: _primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  'Close',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildCopyButton({required String text, required String label}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Clipboard.setData(ClipboardData(text: text));
          _showSnackBar('$label copied to clipboard');
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: _primaryColor,
          side: BorderSide(color: _primaryColor.withValues(alpha: 0.3)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: Icon(Icons.content_copy, size: 18),
        label: Text(
          label,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  // ==================== LOGOUT ====================
  // In settings_screen.dart - Fix _logout method
 Future<void> _logout() async {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Logging out...', style: GoogleFonts.poppins()),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  try {
    await ApiService.logoutUser();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Logged out successfully',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: _successColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // ✅ Clear entire stack and go to login
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    }
  } catch (e, stackTrace) {
    debugPrint('Logout error: $e');
    await ApiService.reportError(e, stackTrace);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logged out', style: GoogleFonts.poppins()),
          backgroundColor: _warningColor,
        ),
      );
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    }
  }
}

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.logout, color: _errorColor),
                const SizedBox(width: 12),
                Text(
                  'Logout',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: Text(
              'Are you sure you want to logout from your account?',
              style: GoogleFonts.poppins(fontSize: 16, color: _textPrimary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: _textSecondary),
                child: Text('Cancel', style: GoogleFonts.poppins()),
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
                  _logout();
                },
                style: TextButton.styleFrom(foregroundColor: _errorColor),
                child: Text('Logout', style: GoogleFonts.poppins()),
              ),
            ],
          ),
    );
  }

  // ==================== UI HELPERS ====================
  void _showSnackBar(String message, {Color? color}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: color ?? _primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ==================== BUILD METHODS ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundLight,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: _primaryColor, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Dalaba',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _primaryColor,
              letterSpacing: 0.09,
            ),
          ),
          Text(
            'pay',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _secondaryColor,
              letterSpacing: 0.09,
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: Icon(Icons.refresh, color: _primaryColor, size: 22),
          onPressed: _initializeSettings,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading settings...',
              style: GoogleFonts.poppins(color: _textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _initializeSettings,
      color: _primaryColor,
      backgroundColor: Colors.white,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            children: [
              _buildProfileSection(),
              const SizedBox(height: 24),
              _buildSectionHeader('Security'),
              const SizedBox(height: 12),
              _buildSecuritySettingsCard(),
              const SizedBox(height: 24),
              _buildSectionHeader('Preferences'),
              const SizedBox(height: 12),
              _buildPreferencesCard(),
              const SizedBox(height: 24),
              _buildSectionHeader('Support'),
              const SizedBox(height: 12),
              _buildSupportCard(),
              const SizedBox(height: 24),
              _buildLogoutButton(),
              const SizedBox(height: 8),
              _buildAppVersion(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileImageContent() {
    // Check multiple sources for profile image
    String? imageUrl;

    if (profileImageUrl != null && profileImageUrl!.isNotEmpty) {
      imageUrl = profileImageUrl;
    } else if (userData['profileImage'] != null &&
        userData['profileImage'].toString().isNotEmpty) {
      imageUrl = userData['profileImage'].toString();
    }

    if (imageUrl == null || imageUrl.isEmpty) {
      return Icon(Icons.person, size: 36, color: Colors.white);
    }

    // ✅ Build full URL using ImageHelper
    // ✅ Cache buster: use updatedAt if present, else generate from URL hash
    // This GUARANTEES a unique cache key per distinct image.
    // ✅ Build full URL using ImageHelper
    // ✅ Use the STABLE cache-buster stored in state.
    //    It only changes when the image is replaced.
    final fullImageUrl = ImageHelper.buildImageUrl(
      imageUrl,
      cacheBuster: _profileImageCacheBuster,
    );
    final fallbackUrl = ImageHelper.buildFallbackUrl(imageUrl);

    ImageHelper.logImageLoad(imageUrl, fullImageUrl);

    if (fullImageUrl == null) {
      return Icon(Icons.person, size: 36, color: Colors.white);
    }

    return Image.network(
      fullImageUrl,
      fit: BoxFit.cover,
      headers: const {'Cache-Control': 'max-age=86400'},
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
              value:
                  loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        debugPrint('❌ Primary image failed: $error');

        if (fallbackUrl != null && fallbackUrl != fullImageUrl) {
          debugPrint('📸 Trying fallback: $fallbackUrl');
          return Image.network(
            fallbackUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('❌ Fallback also failed: $error');
              return _buildDefaultAvatar();
            },
          );
        }

        return _buildDefaultAvatar();
      },
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      color: _primaryColor,
      child: Icon(Icons.person, size: 36, color: Colors.white),
    );
  }

  // ==================== PROFILE SECTION ====================
  Widget _buildProfileSection() {
    // Debug: Log the profile image URL
    debugPrint('📸 Profile Image URL: $profileImageUrl');
    debugPrint('📸 UserData profileImage: ${userData['profileImage']}');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _primaryColor.withValues(alpha: 0.05),
            _secondaryColor.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _primaryColor.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          // Profile image with tap to view
          GestureDetector(
            onTap:
                profileImageUrl != null && profileImageUrl!.isNotEmpty
                    ? _viewProfileImage
                    : null,
            child: Stack(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _primaryColor.withValues(alpha: 0.2),
                      width: 3,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_primaryColor, _secondaryColor],
                    ),
                  ),
                  // ✅ Unique key forces rebuild when URL changes
                  child: ClipOval(
                    key: ValueKey(profileImageUrl ?? 'no-image'),
                    child: _buildProfileImageContent(),
                  ),
                ),
                // Camera button for re-upload
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: isUpdating ? null : _pickProfileImage,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child:
                          isUpdating
                              ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.white,
                                ),
                              )
                              : Icon(
                                Icons.camera_alt,
                                size: 14,
                                color: Colors.white,
                              ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName.isNotEmpty ? fullName : 'User Name',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  email.isNotEmpty ? email : 'user@example.com',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: _textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Phone: ${phone.isNotEmpty ? phone : 'Not set'}',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: _textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildStatusChip(
                      isActive ? 'Active' : 'Inactive',
                      isActive ? _successColor : _errorColor,
                    ),
                    if (userData['isAdmin'] == true) ...[
                      const SizedBox(width: 8),
                      _buildStatusChip('Admin', _warningColor),
                    ],
                  ],
                ),
                // ✅ Add Re-upload button
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (profileImageUrl != null &&
                        profileImageUrl!.isNotEmpty) ...[
                      GestureDetector(
                        onTap: _viewProfileImage,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _primaryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _primaryColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.visibility,
                                size: 12,
                                color: _primaryColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'View',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: _primaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _pickProfileImage,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _secondaryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _secondaryColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.refresh,
                                size: 12,
                                color: _secondaryColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Change',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: _secondaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      GestureDetector(
                        onTap: _pickProfileImage,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _primaryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _primaryColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, size: 12, color: _primaryColor),
                              const SizedBox(width: 4),
                              Text(
                                'Add Photo',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: _primaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  // ==================== SECTION HEADER ====================
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: _textPrimary,
        ),
      ),
    );
  }

  // ==================== SECURITY CARD ====================
  Widget _buildSecuritySettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildSettingsTile(
            icon: Icons.lock_outline,
            title: 'Transaction PIN',
            subtitle:
                transactionPinSet
                    ? 'PIN is set - Tap to change'
                    : 'Set up transaction PIN',
            status: transactionPinSet ? 'Set' : 'Not Set',
            statusColor: transactionPinSet ? _successColor : _warningColor,
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => ChangePinScreen(
                        userId: userData['_id'] ?? '',
                        hasExistingPin: transactionPinSet,
                        userEmail: email,
                      ),
                ),
              );
              if (result != null && mounted) {
                await _loadUserData();
                if (result['success'] == true) {
                  _showSnackBar(
                    transactionPinSet
                        ? 'PIN changed!'
                        : 'PIN set successfully!',
                    color: _successColor,
                  );
                }
              }
            },
          ),
          _buildDivider(),
          _buildBiometricTile(),
          _buildDivider(),
          _buildSettingsTile(
            icon: Icons.password_outlined,
            title: 'Change Password',
            subtitle: 'Update your account password',
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChangePasswordScreen(),
                  ),
                ),
          ),
          _buildDivider(),
          _buildSettingsTile(
            icon: Icons.verified_user,
            title: 'KYC Verification',
            subtitle:
                _isCheckingAccount
                    ? 'Checking account status...'
                    : _hasDedicatedAccount
                    ? 'Account verified - ${_dedicatedAccountNumber ?? ""}'
                    : 'Complete KYC to get your dedicated account',
            status:
                _isCheckingAccount
                    ? 'Checking...'
                    : _hasDedicatedAccount
                    ? 'Verified'
                    : 'Pending',
            statusColor:
                _isCheckingAccount
                    ? Colors.blue
                    : _hasDedicatedAccount
                    ? _successColor
                    : _warningColor,
            onTap: _navigateToKYC,
            showRefresh: true,
            refreshCallback: _checkDedicatedAccount,
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricTile() {
    if (_isCheckingBiometric || _isTogglingBiometric) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _primaryColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.fingerprint, size: 22, color: _primaryColor),
        ),
        title: Text(
          'Biometric Authentication',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _textPrimary,
          ),
        ),
        subtitle: Text(
          _isTogglingBiometric ? 'Processing...' : 'Checking...',
          style: GoogleFonts.poppins(fontSize: 14, color: _textSecondary),
        ),
        trailing: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _primaryColor.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.fingerprint, size: 22, color: _primaryColor),
      ),
      title: Text(
        'Biometric Authentication',
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: _textPrimary,
        ),
      ),
      subtitle: Text(
        biometricEnabled
            ? 'Use fingerprint or face for login & payments'
            : biometricAvailable
            ? 'Enable fingerprint or face recognition'
            : 'Tap for setup instructions',
        style: GoogleFonts.poppins(fontSize: 14, color: _textSecondary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!biometricAvailable)
            IconButton(
              icon: Icon(Icons.help_outline, color: _textSecondary, size: 20),
              onPressed: _showSetupLockScreenDialog,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          Switch(
            value: biometricEnabled,
            onChanged: biometricAvailable ? _handleBiometricToggle : null,
            activeThumbColor: _secondaryColor,
            activeTrackColor: _secondaryColor.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  // ==================== PREFERENCES CARD ====================
  Widget _buildPreferencesCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildSwitchTile(
            icon: Icons.notifications_none,
            title: 'Push Notifications',
            subtitle: 'Receive mobile notifications',
            value: notificationsEnabled,
            onChanged: _toggleNotifications,
          ),
          _buildDivider(),
          _buildSwitchTile(
            icon: Icons.dark_mode_outlined,
            title: 'Dark Mode',
            subtitle: 'Switch between light and dark theme',
            value: darkModeEnabled,
            onChanged: _toggleDarkMode,
          ),
          _buildDivider(),
          _buildSettingsTile(
            icon: Icons.language,
            title: 'Language',
            subtitle: 'App language settings',
            onTap: _showLanguageDialog,
          ),
        ],
      ),
    );
  }

  // ==================== SUPPORT CARD ====================
  Widget _buildSupportCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildSettingsTile(
            icon: Icons.help_outline,
            title: 'Help Center',
            subtitle: 'Get support and assistance',
            onTap: _showHelpCenterDialog,
          ),
          _buildDivider(),
          _buildSettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'How we protect your data',
            onTap: _showPrivacyPolicyDialog,
          ),
          _buildDivider(),
          _buildSettingsTile(
            icon: Icons.description_outlined,
            title: 'Terms & Conditions',
            subtitle: 'App usage terms',
            onTap: _showTermsDialog,
          ),
        ],
      ),
    );
  }

  // ==================== LOGOUT BUTTON ====================
  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isUpdating ? null : _showLogoutConfirmation,
        style: ElevatedButton.styleFrom(
          backgroundColor: _errorColor.withValues(alpha: 0.05),
          foregroundColor: _errorColor,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: _errorColor.withValues(alpha: 0.2)),
          ),
          elevation: 0,
        ),
        child:
            isUpdating
                ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_errorColor),
                  ),
                )
                : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout, size: 20, color: _errorColor),
                    const SizedBox(width: 8),
                    Text(
                      'Logout',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _errorColor,
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  // ==================== APP VERSION ====================
  // ==================== APP VERSION ====================
  Widget _buildAppVersion() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _checkForUpdate(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Text(
                'Loading version...',
                style: GoogleFonts.poppins(fontSize: 12, color: _textSecondary),
              );
            }

            final hasUpdate = snapshot.data?['needsUpdate'] ?? false;
            final latestVersion = snapshot.data?['latestVersion'] ?? '';
            final currentVersion = snapshot.data?['currentVersion'] ?? '1.0.0';

            return Column(
              children: [
                Text(
                  'Version $currentVersion',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: _textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                // Check for updates button
                GestureDetector(
                  onTap: _checkForUpdateManually,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.system_update_alt,
                          size: 12,
                          color: _primaryColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          hasUpdate ? 'Update available!' : 'Check for updates',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: hasUpdate ? _warningColor : _primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (hasUpdate) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _warningColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'v$latestVersion available',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: _warningColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // Add this helper method to check for updates
  Future<Map<String, dynamic>?> _checkForUpdate() async {
    try {
      // Use the UpdateService
      final versionInfo = await UpdateService.checkForUpdate().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⏰ Update check timed out');
          return null;
        },
      );

      if (versionInfo != null) {
        // Cache the version info
        final prefs = await SharedPreferences.getInstance();
        if (versionInfo['currentVersion'] != null) {
          await prefs.setString('appVersion', versionInfo['currentVersion']);
        }
      }

      return versionInfo;
    } catch (e) {
      debugPrint('❌ Update check error: $e');
      return null;
    }
  }

  void _viewProfileImage() {
    if (profileImageUrl == null || profileImageUrl!.isEmpty) {
      _showSnackBar('No profile image set');
      return;
    }

    final fullImageUrl = ImageHelper.buildImageUrl(
      profileImageUrl,
      cacheBuster: _profileImageCacheBuster,
    );
    final fallbackUrl = ImageHelper.buildFallbackUrl(profileImageUrl);

    if (fullImageUrl == null) {
      _showSnackBar('Invalid image URL');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        fullImageUrl,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return SizedBox(
                            height: 300,
                            child: Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _primaryColor,
                                ),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          if (fallbackUrl != null &&
                              fallbackUrl != fullImageUrl) {
                            return Image.network(
                              fallbackUrl,
                              fit: BoxFit.contain,
                              errorBuilder:
                                  (ctx, err, st) =>
                                      _buildImageErrorPlaceholder(),
                            );
                          }
                          return _buildImageErrorPlaceholder();
                        },
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
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

  // Add this method to manually check for updates
  void _checkForUpdateManually() async {
    try {
      _showSnackBar('Checking for updates...', color: Colors.blue);

      final versionInfo = await _checkForUpdate();

      if (versionInfo == null) {
        _showSnackBar('Unable to check for updates. Please try again.');
        return;
      }

      final needsUpdate = versionInfo['needsUpdate'] ?? false;
      final latestVersion = versionInfo['latestVersion'] ?? '';
      final currentVersion = versionInfo['currentVersion'] ?? '1.0.0';

      if (needsUpdate) {
        _showUpdateAvailableDialog(latestVersion, currentVersion);
      } else {
        _showSnackBar(
          '✅ You have the latest version ($currentVersion)!',
          color: _successColor,
        );
      }
    } catch (e) {
      _showSnackBar('Failed to check for updates: $e');
    }
  }

  // Add this method to show update dialog
  void _showUpdateAvailableDialog(String newVersion, String currentVersion) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.system_update_alt, color: _primaryColor, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Update Available',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A new version ($newVersion) is available.',
                  style: GoogleFonts.poppins(fontSize: 16, color: _textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Current version: $currentVersion',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: _textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Please update to get the latest features and improvements.',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: _textSecondary,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(foregroundColor: _textSecondary),
                child: Text('Later', style: GoogleFonts.poppins()),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await UpdateService.openPlayStore(
                    'https://play.google.com/store/apps/details?id=com.dalabapay.official',
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Update Now',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildImageErrorPlaceholder() {
    return Container(
      height: 300,
      color: Colors.grey.shade100,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 8),
          Text(
            'Failed to load image',
            style: GoogleFonts.poppins(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // ==================== TILE BUILDERS ====================
  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    String? status,
    Color? statusColor,
    VoidCallback? onTap,
    bool showRefresh = false,
    VoidCallback? refreshCallback,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _primaryColor.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 22, color: _primaryColor),
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: _textPrimary,
        ),
      ),
      subtitle:
          subtitle != null
              ? Text(
                subtitle,
                style: GoogleFonts.poppins(fontSize: 14, color: _textSecondary),
              )
              : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showRefresh && refreshCallback != null)
            IconButton(
              icon: Icon(Icons.refresh, color: _primaryColor, size: 18),
              onPressed: refreshCallback,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          if (status != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (statusColor ?? _primaryColor).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (statusColor ?? _primaryColor).withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                status,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: statusColor ?? _primaryColor,
                ),
              ),
            )
          else
            Icon(Icons.chevron_right, color: _textSecondary, size: 20),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    ValueChanged<bool>? onChanged,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _primaryColor.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 22, color: _primaryColor),
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: _textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.poppins(fontSize: 14, color: _textSecondary),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: _secondaryColor,
        activeTrackColor: _secondaryColor.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Divider(height: 1, thickness: 0.5, color: Colors.grey.shade200),
    );
  }
}
