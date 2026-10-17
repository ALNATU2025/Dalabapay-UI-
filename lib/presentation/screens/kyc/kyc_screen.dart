// lib/presentation/screens/kyc/kyc_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/payment_service.dart';

class KYCScreen extends StatefulWidget {
  const KYCScreen({super.key});

  @override
  State<KYCScreen> createState() => _KYCScreenState();
}

class _KYCScreenState extends State<KYCScreen>
    with SingleTickerProviderStateMixin {
  // ==================== STATE ====================
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isSuccess = false;

  // User data (auto-populated, non-editable)
  String _fullName = '';
  String _email = '';
  String _phone = '';
  String _userId = '';

  // KYC Form Fields
  final TextEditingController _bvnController = TextEditingController();
  final TextEditingController _ninController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _dateOfBirthController = TextEditingController();
  final TextEditingController _genderController = TextEditingController();

  // Validation
  bool _bvnValid = false;
  bool _ninValid = false;
  bool _dateOfBirthValid = false;
  bool _genderValid = false;
  bool _addressValid = false;
  bool _termsAccepted = false;

  String? _bvnError;
  String? _ninError;
  String? _dateOfBirthError;
  String? _genderError;
  String? _addressError;

  // Track which identification method is being used
  bool _isUsingBVN = false;
  bool _isUsingNIN = false;

  // Animation
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // ==================== BRAND COLORS ====================
  static const Color _primaryColor = Color(0xFF243889);
  static const Color _secondaryColor = Color(0xFF219C7E);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _textPrimary = Color(0xFF1C2D5A);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _backgroundLight = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadUserData();
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
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _bvnController.dispose();
    _ninController.dispose();
    _addressController.dispose();
    _dateOfBirthController.dispose();
    _genderController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ==================== LOAD USER DATA ====================
  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString('user');

      if (userString != null) {
        final userData = jsonDecode(userString);
        setState(() {
          _fullName = userData['fullName'] ?? '';
          _email = userData['email'] ?? '';
          _phone = userData['phone'] ?? '';
          _userId = userData['_id'] ?? '';

          if (userData['dateOfBirth'] != null &&
              userData['dateOfBirth'].toString().isNotEmpty) {
            _dateOfBirthController.text = userData['dateOfBirth'];
            _dateOfBirthValid = true;
          }

          if (userData['gender'] != null &&
              userData['gender'].toString().isNotEmpty) {
            _genderController.text = userData['gender'];
            _genderValid = true;
          }

          if (userData['address'] != null &&
              userData['address'].toString().isNotEmpty) {
            _addressController.text = userData['address'];
            _addressValid = true;
          }
        });
      }

      final kycStatus = await PaymentService.getUserKYCStatus(_userId);
      if (kycStatus['success'] == true) {
        if (kycStatus['hasBvn'] == true) {
          _bvnController.text = '••••••••••';
          _bvnValid = true;
          _isUsingBVN = true;
        }
        if (kycStatus['hasNin'] == true) {
          _ninController.text = '••••••••••••';
          _ninValid = true;
          _isUsingNIN = true;
        }
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ==================== VALIDATION ====================
  void _validateBVN(String value) {
    setState(() {
      if (value.isEmpty) {
        _bvnError = null;
        _bvnValid = false;
        _isUsingBVN = false;
      } else if (value.length != 11 || !RegExp(r'^[0-9]+$').hasMatch(value)) {
        _bvnError = 'BVN must be exactly 11 digits';
        _bvnValid = false;
        _isUsingBVN = true;
      } else {
        _bvnError = null;
        _bvnValid = true;
        _isUsingBVN = true;
      }
    });
  }

  void _validateNIN(String value) {
    setState(() {
      if (value.isEmpty) {
        _ninError = null;
        _ninValid = false;
        _isUsingNIN = false;
      } else if (value.length < 11 || !RegExp(r'^[0-9]+$').hasMatch(value)) {
        _ninError = 'NIN must be at least 11 digits';
        _ninValid = false;
        _isUsingNIN = true;
      } else {
        _ninError = null;
        _ninValid = true;
        _isUsingNIN = true;
      }
    });
  }

  void _validateDateOfBirth(String value) {
    setState(() {
      if (value.isEmpty) {
        _dateOfBirthError = 'Date of birth is required';
        _dateOfBirthValid = false;
      } else {
        final parts = value.split('/');
        if (parts.length != 3) {
          _dateOfBirthError = 'Invalid format. Use DD/MM/YYYY';
          _dateOfBirthValid = false;
          return;
        }

        final day = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        final year = int.tryParse(parts[2]);

        if (day == null || month == null || year == null) {
          _dateOfBirthError = 'Invalid date. Use DD/MM/YYYY';
          _dateOfBirthValid = false;
          return;
        }

        if (day < 1 ||
            day > 31 ||
            month < 1 ||
            month > 12 ||
            year < 1900 ||
            year > 2010) {
          _dateOfBirthError = 'Please enter a valid date (1900-2010)';
          _dateOfBirthValid = false;
          return;
        }

        _dateOfBirthError = null;
        _dateOfBirthValid = true;
      }
    });
  }

  void _validateGender(String value) {
    setState(() {
      if (value.isEmpty) {
        _genderError = 'Gender is required';
        _genderValid = false;
      } else {
        _genderError = null;
        _genderValid = true;
      }
    });
  }

  void _validateAddress(String value) {
    setState(() {
      if (value.trim().isEmpty) {
        _addressError = 'Address is required';
        _addressValid = false;
      } else {
        _addressError = null;
        _addressValid = true;
      }
    });
  }

  bool _hasValidIdentification() {
    return (_bvnValid || _ninValid);
  }

  bool _isFormValid() {
    return _hasValidIdentification() &&
        _addressValid &&
        _dateOfBirthValid &&
        _genderValid &&
        _termsAccepted;
  }

  String? _getFormError() {
    if (!_hasValidIdentification()) {
      return 'Please provide either a valid BVN or NIN';
    }
    if (!_addressValid) {
      return 'Please enter your residential address';
    }
    if (!_dateOfBirthValid) {
      return 'Please select your date of birth';
    }
    if (!_genderValid) {
      return 'Please select your gender';
    }
    if (!_termsAccepted) {
      return 'Please accept the Terms of Service';
    }
    return null;
  }

  // ============================================================
  // 🎯 PROFESSIONAL DIALOGS
  // ============================================================

  /// Show loading dialog while submitting
  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(
                      color: _primaryColor,
                      strokeWidth: 4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Creating Your Account...',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please wait while we set up your dedicated account',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: _textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  /// Show Sweet Alert-style Success Dialog
  void _showSweetSuccessDialog(Map<String, dynamic> result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: TweenAnimationBuilder(
              duration: const Duration(milliseconds: 600),
              tween: Tween<double>(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(
                    opacity: value,
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Animated Success Icon
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  _secondaryColor,
                                  _secondaryColor.withValues(alpha: 0.7),
                                ],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 50,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '🎉 Account Created!',
                            style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: _textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your dedicated account has been set up successfully',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              color: _textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          // Account Details Card
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  _primaryColor.withValues(alpha: 0.05),
                                  _secondaryColor.withValues(alpha: 0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _primaryColor.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Column(
                              children: [
                                _buildAccountDetailRow(
                                  'Account Number',
                                  result['accountNumber'] ?? 'N/A',
                                  Icons.account_balance_wallet,
                                ),
                                const Divider(height: 16),
                                _buildAccountDetailRow(
                                  'Account Name',
                                  result['accountName'] ?? _fullName,
                                  Icons.person,
                                ),
                                const Divider(height: 16),
                                _buildAccountDetailRow(
                                  'Bank',
                                  result['bankName'] ?? 'Moniepoint MFB',
                                  Icons.business,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.green.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: _secondaryColor,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Your account tier has been upgraded. You can now receive payments!',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: _secondaryColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          // 🔥 FIX: Go to Dashboard with refresh flag
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                // Close the dialog
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
                                // Close KYC screen with refresh flag
                                Navigator.pop(context, true);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryColor,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.home_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Go to Dashboard',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
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
              },
            ),
          ),
    );
  }

  /// Show Sweet Alert-style Error Dialog
  void _showSweetErrorDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: TweenAnimationBuilder(
              duration: const Duration(milliseconds: 400),
              tween: Tween<double>(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(
                    opacity: value,
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 25,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: _errorColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.error_outline_rounded,
                              color: _errorColor,
                              size: 45,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Something Went Wrong',
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            message,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: _textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
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
                                    setState(() => _isSubmitting = false);
                                  },
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    'Try Again',
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: _textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
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
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _primaryColor,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    'Go Back',
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
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
              },
            ),
          ),
    );
  }

  /// Show Sweet Alert-style Info Dialog
  void _showSweetInfoDialog(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: TweenAnimationBuilder(
              duration: const Duration(milliseconds: 400),
              tween: Tween<double>(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(
                    opacity: value,
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 25,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.info_outline_rounded,
                              color: Colors.blue.shade600,
                              size: 45,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            title,
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            message,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: _textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryColor,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Got It',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
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
              },
            ),
          ),
    );
  }

  Widget _buildAccountDetailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: _primaryColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: _textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: value));
                      _showSweetInfoDialog(
                        'Copied!',
                        'Account details copied to clipboard',
                      );
                    },
                    icon: Icon(Icons.copy, size: 16, color: _primaryColor),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== SUBMIT ====================
  Future<void> _submitKYC() async {
    final formError = _getFormError();
    if (formError != null) {
      _showSweetInfoDialog('Incomplete Form', formError);
      return;
    }

    setState(() => _isSubmitting = true);

    // Show loading dialog
    _showLoadingDialog();

    try {
      final bvn = _bvnController.text.trim();
      final nin = _ninController.text.trim();

      final result = await PaymentService.createReserveAccount(
        userId: _userId,
        fullName: _fullName,
        email: _email,
        phone: _phone,
        bvn: bvn.isNotEmpty ? bvn : '',
        nin: nin.isNotEmpty ? nin : '',
        accountReference: _email,
        address: _addressController.text.trim(),
        dateOfBirth: _dateOfBirthController.text,
        gender: _genderController.text,
      );

      // Close loading dialog
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

      if (result['success'] == true) {
        setState(() {
          _isSubmitting = false;
          _isSuccess = true;
        });

        // Show Sweet Success Dialog
        _showSweetSuccessDialog(result);
      } else {
        throw Exception(result['message'] ?? 'Failed to create account');
      }
    } catch (e) {
      // Close loading dialog
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
      setState(() => _isSubmitting = false);

      // Show Sweet Error Dialog
      _showSweetErrorDialog(e.toString().replaceAll('Exception: ', ''));
    }
  }

  // ==================== UI HELPERS ====================
  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter()),
        backgroundColor: _primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
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
                'Loading your information...',
                style: GoogleFonts.inter(color: _textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: _buildForm(),
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
    );
  }

  Widget _buildForm() {
    final formError = _getFormError();
    final bool isValid = _isFormValid();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Complete Your KYC',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Provide your identification details to create your dedicated account',
                style: GoogleFonts.inter(fontSize: 14, color: _textSecondary),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.amber.shade700,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You only need to provide either BVN or NIN, not both.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Auto-populated User Info
              _buildReadOnlySection(),
              const SizedBox(height: 20),

              // BVN FIELD
              _buildTextField(
                controller: _bvnController,
                label: 'Bank Verification Number (BVN)',
                hint: 'Enter 11-digit BVN (optional if providing NIN)',
                icon: Icons.credit_card,
                errorText: _bvnError,
                onChanged: _validateBVN,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                isOptional: true,
                isValid: _bvnValid,
                isUsing: _isUsingBVN,
              ),

              const SizedBox(height: 8),

              // "OR" Divider
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OR',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: _textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                ],
              ),

              const SizedBox(height: 8),

              // NIN FIELD
              _buildTextField(
                controller: _ninController,
                label: 'National Identification Number (NIN)',
                hint: 'Enter 11-digit NIN (optional if providing BVN)',
                icon: Icons.credit_card_outlined,
                errorText: _ninError,
                onChanged: _validateNIN,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                isOptional: true,
                isValid: _ninValid,
                isUsing: _isUsingNIN,
              ),

              // Validation status
              if (!_hasValidIdentification() &&
                  (_bvnController.text.isNotEmpty ||
                      _ninController.text.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Please enter a valid BVN (11 digits) or NIN (11+ digits)',
                    style: GoogleFonts.inter(fontSize: 12, color: _errorColor),
                  ),
                )
              else if (_hasValidIdentification())
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: _secondaryColor,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isUsingBVN ? '✓ BVN verified' : '✓ NIN verified',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _secondaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // DATE OF BIRTH
              _buildTextField(
                controller: _dateOfBirthController,
                label: 'Date of Birth',
                hint: 'DD/MM/YYYY',
                icon: Icons.calendar_today,
                errorText: _dateOfBirthError,
                onChanged: _validateDateOfBirth,
                readOnly: true,
                onTap: () => _selectDate(),
                isRequired: true,
                isValid: _dateOfBirthValid,
                isUsing: _dateOfBirthController.text.isNotEmpty,
              ),

              const SizedBox(height: 16),

              // GENDER
              _buildTextField(
                controller: _genderController,
                label: 'Gender',
                hint: 'Select your gender',
                icon: Icons.person_outline,
                errorText: _genderError,
                onChanged: _validateGender,
                readOnly: true,
                onTap: () => _selectGender(),
                isRequired: true,
                isValid: _genderValid,
                isUsing: _genderController.text.isNotEmpty,
              ),

              const SizedBox(height: 16),

              // ADDRESS
              _buildTextField(
                controller: _addressController,
                label: 'Residential Address',
                hint: 'Enter your residential address',
                icon: Icons.home_outlined,
                errorText: _addressError,
                onChanged: _validateAddress,
                maxLines: 2,
                isRequired: true,
                isValid: _addressValid,
                isUsing: _addressController.text.trim().isNotEmpty,
              ),

              const SizedBox(height: 24),

              // Terms and Conditions
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _termsAccepted,
                      onChanged: (value) {
                        setState(() => _termsAccepted = value ?? false);
                      },
                      activeColor: _primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'I agree to the ',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: _textSecondary,
                            ),
                          ),
                          TextSpan(
                            text: 'Terms of Service',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _primaryColor,
                            ),
                          ),
                          TextSpan(
                            text:
                                ' and confirm that the information provided is accurate.',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: _textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Error Message
              if (formError != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _errorColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _errorColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: _errorColor, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          formError,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: _errorColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting || !isValid ? null : _submitKYC,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    disabledBackgroundColor: _primaryColor.withValues(
                      alpha: 0.4,
                    ),
                  ),
                  child:
                      _isSubmitting
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
                          : Text(
                            isValid
                                ? 'Create Dedicated Account'
                                : 'Fill Required Fields',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                ),
              ),

              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Your information is secure and encrypted',
                  style: GoogleFonts.inter(fontSize: 12, color: _textSecondary),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadOnlySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _backgroundLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF243889).withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Information',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          _buildReadOnlyRow('Full Name', _fullName),
          const Divider(height: 16),
          _buildReadOnlyRow('Email', _email),
          const Divider(height: 16),
          _buildReadOnlyRow('Phone', _phone),
        ],
      ),
    );
  }

  Widget _buildReadOnlyRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: GoogleFonts.inter(fontSize: 13, color: _textSecondary),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value.isNotEmpty ? value : 'Not set',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _textPrimary,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? errorText,
    Function(String)? onChanged,
    VoidCallback? onTap,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    bool readOnly = false,
    bool isRequired = false,
    bool isOptional = false,
    bool isValid = false,
    bool isUsing = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _textPrimary,
              ),
            ),
            if (isRequired) ...[
              const SizedBox(width: 4),
              Text(
                '*',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: _errorColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            if (isOptional) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Optional',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: _textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            if (isValid && isUsing) ...[
              const Spacer(),
              Icon(Icons.check_circle, color: _secondaryColor, size: 16),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: onChanged,
          onTap: onTap,
          readOnly: readOnly,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
              fontSize: 14,
              color: const Color(0xFF94A3B8),
            ),
            prefixIcon: Icon(icon, color: _primaryColor, size: 20),
            prefixIconConstraints: const BoxConstraints(minWidth: 48),
            errorText: errorText,
            errorStyle: GoogleFonts.inter(fontSize: 12, color: _errorColor),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _primaryColor, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _errorColor, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _errorColor, width: 2),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          style: GoogleFonts.inter(fontSize: 14, color: _textPrimary),
        ),
      ],
    );
  }

  // ==================== DATE & GENDER SELECTORS ====================
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),
      firstDate: DateTime(1950, 1, 1),
      lastDate: DateTime(2010, 12, 31),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: _primaryColor),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dateOfBirthController.text =
            '${picked.day.toString().padLeft(2, '0')}/'
            '${picked.month.toString().padLeft(2, '0')}/'
            '${picked.year}';
        _validateDateOfBirth(_dateOfBirthController.text);
      });
    }
  }

  Future<void> _selectGender() async {
    final String? gender = await showDialog<String>(
      context: context,
      builder:
          (context) => SimpleDialog(
            title: Text(
              'Select Gender',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
            children:
                ['Male', 'Female', 'Other'].map((g) {
                  return SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, g),
                    child: Text(g, style: GoogleFonts.inter()),
                  );
                }).toList(),
          ),
    );
    if (gender != null) {
      setState(() {
        _genderController.text = gender;
        _validateGender(gender);
      });
    }
  }
}
