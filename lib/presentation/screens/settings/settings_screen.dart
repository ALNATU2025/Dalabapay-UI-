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
import '../../../ui/ui.dart';

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
  static const Color _primaryColor = Color(0xFF102C68);
  static const Color _secondaryColor = Color(0xFF168566);
  static const Color _successColor = Color(0xFF168566);
  static const Color _warningColor = Color(0xFFA76B1D);
  static const Color _errorColor = Color(0xFFC0392B);
  static const Color _textPrimary = Color(0xFF14263D);
  static const Color _textSecondary = Color(0xFF728078);
  static const Color _backgroundLight = Color(0xFFF8F9F5);

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
                style: GoogleFonts.inter(fontWeight: FontWeight.bold),
              ),
              content: Text(
                "You'll need to use PIN for all future logins.",
                style: GoogleFonts.inter(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Cancel', style: GoogleFonts.inter()),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    'Disable',
                    style: GoogleFonts.inter(color: _errorColor),
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
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
            content: Text(
              "To use biometric login, you must first set up a screen lock (PIN, Pattern, or Password) on your device.\n\n"
              "Go to Settings → Security → Screen Lock",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Later', style: GoogleFonts.inter()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: Text('Open Settings', style: GoogleFonts.inter()),
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
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
            content: Text(
              "No fingerprint or face ID is set up on this device.\n\n"
              "Go to Settings → Security → Fingerprint / Face Unlock",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Later', style: GoogleFonts.inter()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: Text('Open Settings', style: GoogleFonts.inter()),
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
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You can now use fingerprint or face recognition',
                    style: GoogleFonts.inter(
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
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
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
                  style: GoogleFonts.inter(
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
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your privacy and financial security are our top priorities. '
                    'DalabaPay employs bank-level encryption and security measures to protect your data.',
                    style: GoogleFonts.inter(
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
                    style: GoogleFonts.inter(
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
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
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
                  style: GoogleFonts.inter(
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
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'By using DalabaPay, you agree to our terms governing financial transactions, bill payments, and account usage.',
                    style: GoogleFonts.inter(
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
                    style: GoogleFonts.inter(
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
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
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
          style: GoogleFonts.inter(fontWeight: FontWeight.w500),
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
        content: Text('Logging out...', style: GoogleFonts.inter()),
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
            style: GoogleFonts.inter(),
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
          content: Text('Logged out', style: GoogleFonts.inter()),
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
    dpDialog(
      context,
      title: 'Log out?',
      message: 'You\'ll need your password, PIN or biometrics to get back in.',
      confirmLabel: 'Log out',
      cancelLabel: 'Stay logged in',
      tone: DPTone.warning,
      icon: DPIcons.logout,
      destructive: true,
    ).then((ok) {
      if (ok == true) _logout();
    });
  }

  // ==================== UI HELPERS ====================
  void _showSnackBar(String message, {Color? color}) {
    if (!mounted) return;
    dpSnack(
      context,
      message,
      success: color == _successColor,
      error: color == _errorColor,
    );
  }

  // ==================== BUILD METHODS ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DP.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const DPTopBar(title: 'Your profile'),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      bottomNavigationBar: DPBottomNav(
        index: 3,
        items: const [
          DPNavItem(DPIcons.home, 'Home', activeIcon: DPIcons.homeFilled),
          DPNavItem(DPIcons.activity, 'Activity'),
          DPNavItem(DPIcons.earnings, 'Earnings'),
          DPNavItem(DPIcons.user, 'Profile', activeIcon: DPIcons.userFilled),
        ],
        onTap: (i) {
          final uid = (userData['_id'] ?? '').toString();
          switch (i) {
            case 0:
              Navigator.of(context).maybePop();
              break;
            case 1:
              Navigator.pushReplacementNamed(
                context,
                '/transactions',
                arguments: {'userId': uid},
              );
              break;
            case 2:
              Navigator.pushReplacementNamed(
                context,
                '/commission',
                arguments: {'userId': uid},
              );
              break;
          }
        },
      ),
    );
  }

  void _showPersonalInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DPSheetHandle(),
              const SizedBox(height: 8),
              const Text('Personal information', style: DP.title),
              const SizedBox(height: 16),
              DPCard(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    DPSummaryRow('Full name', fullName.isEmpty ? '—' : fullName),
                    DPSummaryRow('Email', email.isEmpty ? '—' : email),
                    DPSummaryRow('Phone', phone.isEmpty ? '—' : phone),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DPOutlineButton(
                label: 'Change profile photo',
                icon: DPIcons.edit,
                onPressed: () {
                  Navigator.pop(ctx);
                  _pickProfileImage();
                },
              ),
              const SizedBox(height: 10),
              const Text(
                'To change your name, email or phone number, contact support from Help.',
                style: DP.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildBody() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _initializeSettings,
      color: DP.green,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          children: [
            _buildProfileSection(),
            const SizedBox(height: 22),
            _buildSectionHeader('Account'),
            _buildSecuritySettingsCard(),
            const SizedBox(height: 18),
            _buildSectionHeader('Preferences & security'),
            _buildPreferencesCard(),
            const SizedBox(height: 18),
            _buildSectionHeader('About'),
            _buildSupportCard(),
            const SizedBox(height: 24),
            _buildLogoutButton(),
            const SizedBox(height: 14),
            _buildAppVersion(),
          ],
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
    return DPAvatar(name: fullName.isEmpty ? 'D' : fullName, size: 64);
  }

  // ==================== PROFILE SECTION ====================
  Widget _buildProfileSection() {
    final hasImage = (profileImageUrl != null && profileImageUrl!.isNotEmpty) ||
        (userData['profileImage'] != null &&
            userData['profileImage'].toString().isNotEmpty);
    final isAdmin = userData['isAdmin'] == true;
    return DPCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: hasImage ? _viewProfileImage : _pickProfileImage,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: hasImage
                        ? _buildProfileImageContent()
                        : _buildDefaultAvatar(),
                  ),
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: GestureDetector(
                    onTap: isUpdating ? null : _pickProfileImage,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: DP.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: DP.surface, width: 2),
                      ),
                      child: isUpdating
                          ? const Padding(
                              padding: EdgeInsets.all(4),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              DPIcons.edit,
                              size: 12,
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
                  fullName.isNotEmpty ? fullName : 'Dalabapay user',
                  style: DP.title.copyWith(fontSize: 19),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  phone.isNotEmpty ? phone : email,
                  style: DP.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  isAdmin ? 'Admin account' : 'Personal account',
                  style: const TextStyle(
                    color: DP.green,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ==================== SECTION HEADER ====================
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(title, style: DP.section),
    );
  }

  // ==================== SECURITY CARD ====================
  /// "Account" group.
  Widget _buildSecuritySettingsCard() {
    final kycStatus = _isCheckingAccount
        ? 'Checking…'
        : (_hasDedicatedAccount ? 'Verified' : 'Pending');
    return Column(
      children: [
        _buildSettingsTile(
          icon: DPIcons.user,
          title: 'Personal information',
          subtitle: 'Name, email and phone number',
          onTap: _showPersonalInfo,
        ),
        _buildSettingsTile(
          icon: DPIcons.shieldCheck,
          title: 'Identity & limits',
          subtitle: _hasDedicatedAccount
              ? 'Verified · ${_dedicatedAccountNumber ?? ''}'
              : 'Verify to get your funding account',
          status: kycStatus,
          statusColor: _hasDedicatedAccount ? _successColor : _warningColor,
          onTap: _navigateToKYC,
          showRefresh: true,
          refreshCallback: _checkDedicatedAccount,
        ),
        _buildSettingsTile(
          icon: DPIcons.referral,
          title: 'Referrals',
          subtitle: 'Invite friends and earn bonuses',
          onTap: () => Navigator.pushNamed(
            context,
            '/referral',
            arguments: {'userId': (userData['_id'] ?? '').toString()},
          ),
        ),
      ],
    );
  }

  Widget _buildBiometricTile() {
    final busy = _isCheckingBiometric || _isTogglingBiometric;
    return DPMenuRow(
      icon: DPIcons.fingerprint,
      title: 'Biometric login',
      subtitle: busy
          ? (_isTogglingBiometric ? 'Updating…' : 'Checking…')
          : biometricEnabled
              ? 'On for login and payments'
              : (biometricAvailable
                  ? 'Use your fingerprint or face'
                  : 'Set up a screen lock on your phone first'),
      onTap: biometricAvailable || busy ? null : _showSetupLockScreenDialog,
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Switch(
              value: biometricEnabled,
              onChanged: biometricAvailable ? _handleBiometricToggle : null,
            ),
    );
  }

  // ==================== PREFERENCES CARD ====================
  /// "Preferences & security" group.
  Widget _buildPreferencesCard() {
    return Column(
      children: [
        _buildSettingsTile(
          icon: DPIcons.lock,
          title: 'Payment PIN',
          subtitle: transactionPinSet
              ? 'Change your 6-digit payment PIN'
              : 'Set up your payment PIN',
          status: transactionPinSet ? null : 'Not set',
          statusColor: _warningColor,
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChangePinScreen(
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
                  transactionPinSet ? 'PIN changed' : 'PIN set',
                  color: _successColor,
                );
              }
            }
          },
        ),
        _buildSettingsTile(
          icon: DPIcons.key,
          title: 'Password',
          subtitle: 'Keep your account protected',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ChangePasswordScreen()),
          ),
        ),
        _buildBiometricTile(),
        _buildSettingsTile(
          icon: DPIcons.bell,
          title: 'Notifications',
          subtitle: 'Payments, reminders and updates',
          onTap: () => Navigator.pushNamed(context, '/notifications'),
        ),
        _buildSwitchTile(
          icon: DPIcons.sms,
          title: 'Push notifications',
          subtitle: 'Alerts on this phone',
          value: notificationsEnabled,
          onChanged: _toggleNotifications,
        ),
        _buildSettingsTile(
          icon: DPIcons.help,
          title: 'Help & support',
          subtitle: 'We\'re here when you need us',
          onTap: () => Navigator.pushNamed(context, '/help'),
        ),
      ],
    );
  }

  // ==================== SUPPORT CARD ====================
  /// "About" group.
  Widget _buildSupportCard() {
    return Column(
      children: [
        _buildSettingsTile(
          icon: Icons.privacy_tip_outlined,
          title: 'Privacy policy',
          subtitle: 'How we protect your data',
          onTap: _showPrivacyPolicyDialog,
        ),
        _buildSettingsTile(
          icon: Icons.description_outlined,
          title: 'Terms of use',
          subtitle: 'The rules for using Dalabapay',
          onTap: _showTermsDialog,
        ),
      ],
    );
  }

  // ==================== LOGOUT BUTTON ====================
  Widget _buildLogoutButton() {
    return DPOutlineButton(
      label: 'Log out',
      onPressed: isUpdating ? null : _showLogoutConfirmation,
    );
  }

  // ==================== APP VERSION ====================
  // ==================== APP VERSION ====================
  Widget _buildAppVersion() {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _checkForUpdate(),
      builder: (context, snapshot) {
        final hasUpdate = snapshot.data?['needsUpdate'] ?? false;
        final latestVersion = snapshot.data?['latestVersion'] ?? '';
        final currentVersion = snapshot.data?['currentVersion'] ?? '';
        return Column(
          children: [
            Text(
              currentVersion.toString().isEmpty
                  ? 'Dalabapay'
                  : 'Dalabapay · Version $currentVersion',
              style: DP.caption.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 2),
            DPTextLink(
              label: hasUpdate == true
                  ? 'Update to v$latestVersion'
                  : 'Check for updates',
              fontSize: 12.5,
              color: hasUpdate == true ? DP.amber : DP.green,
              onTap: _checkForUpdateManually,
            ),
          ],
        );
      },
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
                  style: GoogleFonts.inter(
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
                  style: GoogleFonts.inter(fontSize: 16, color: _textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Current version: $currentVersion',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: _textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Please update to get the latest features and improvements.',
                  style: GoogleFonts.inter(
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
                child: Text('Later', style: GoogleFonts.inter()),
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
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
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
            style: GoogleFonts.inter(color: Colors.grey.shade600),
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
    return DPMenuRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status != null)
            _buildStatusChip(status, statusColor ?? DP.green),
          if (showRefresh && refreshCallback != null)
            IconButton(
              tooltip: 'Refresh',
              visualDensity: VisualDensity.compact,
              onPressed: refreshCallback,
              icon: const Icon(DPIcons.refresh, size: 18, color: DP.muted),
            ),
          const Icon(DPIcons.chevronRight, color: DP.muted, size: 22),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    ValueChanged<bool>? onChanged,
  }) {
    return DPMenuRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }

  Widget _buildDivider() {
    return const SizedBox(height: 2);
  }
}
