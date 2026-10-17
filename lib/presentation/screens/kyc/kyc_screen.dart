// lib/presentation/screens/kyc/kyc_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/payment_service.dart';
import '../../../ui/ui.dart';

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
  static const Color _primaryColor = Color(0xFF102C68);
  static const Color _secondaryColor = Color(0xFF168566);
  static const Color _errorColor = Color(0xFFEF4444);
  static const Color _textPrimary = Color(0xFF14263D);
  static const Color _textSecondary = Color(0xFF728078);
  static const Color _backgroundLight = Color(0xFFF8F9F5);

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

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Dialog(
        insetPadding: EdgeInsets.symmetric(horizontal: 60),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 30, horizontal: 20),
          child: DPLoader(message: 'Setting up your account…'),
        ),
      ),
    );
  }

  void _showSweetSuccessDialog(Map<String, dynamic> result) {
    final accountNumber = (result['accountNumber'] ?? 'N/A').toString();
    showDPDialog(
      context,
      title: 'Your account is ready',
      message: 'Send money to this account number to add money to your Dalabapay wallet.',
      tone: DPDialogTone.success,
      barrierDismissible: false,
      body: Column(
        children: [
          DPSummaryCard(rows: [
            DPSummaryRow('Account number', accountNumber, emphasize: true),
            DPSummaryRow('Account name', (result['accountName'] ?? _fullName).toString()),
            DPSummaryRow('Bank', (result['bankName'] ?? 'Moniepoint MFB').toString()),
          ]),
          DPLinkButton(
            label: 'Copy account number',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: accountNumber));
              dpSnack(context, 'Account number copied', success: true);
            },
          ),
        ],
      ),
      primaryLabel: 'Go to home',
      onPrimary: () {
        Navigator.of(context).pop(); // close dialog
        Navigator.pop(context, true); // close KYC with refresh flag
      },
    );
  }

  void _showSweetErrorDialog(String message) {
    showDPDialog(
      context,
      title: 'We couldn’t verify you',
      message: message,
      tone: DPDialogTone.error,
      primaryLabel: 'Try again',
    );
  }

  void _showSweetInfoDialog(String title, String message) {
    showDPDialog(context, title: title, message: message, tone: DPDialogTone.info);
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
    dpSnack(context, message);
  }

  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    final isValid = _isFormValid();
    return DPPage(
      title: 'Identity & limits',
      bottom: _isLoading
          ? null
          : DPButton(
              label: isValid ? 'Create my account' : 'Fill the required fields',
              loading: _isSubmitting,
              onPressed: _isSubmitting || !isValid ? null : _submitKYC,
            ),
      children: [
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: DPLoader(message: 'Loading your information…'),
          )
        else
          _buildForm(),
      ],
    );
  }


  Widget _buildForm() {
    final formError = _getFormError();
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DPHeadline(
            'Verify it’s you.',
            subtitle: 'We’ll create your personal funding account so you can add money by bank transfer.',
          ),
          const DPNotice(
            'You only need one: your BVN or your NIN.',
            kind: DPNoticeKind.info,
          ),
          _buildReadOnlySection(),
          _buildTextField(
            controller: _bvnController,
            label: 'BVN',
            hint: '11-digit Bank Verification Number',
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
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                const Expanded(child: Divider(color: DP.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('OR', style: DPText.overline),
                ),
                const Expanded(child: Divider(color: DP.border)),
              ],
            ),
          ),
          _buildTextField(
            controller: _ninController,
            label: 'NIN',
            hint: '11-digit National Identification Number',
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
          _buildTextField(
            controller: _dateOfBirthController,
            label: 'Date of birth',
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
          _buildTextField(
            controller: _addressController,
            label: 'Residential address',
            hint: 'House number, street, city',
            icon: Icons.home_outlined,
            errorText: _addressError,
            onChanged: _validateAddress,
            maxLines: 2,
            isRequired: true,
            isValid: _addressValid,
            isUsing: _addressController.text.trim().isNotEmpty,
          ),
          GestureDetector(
            onTap: () => setState(() => _termsAccepted = !_termsAccepted),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _termsAccepted,
                      onChanged: (value) => setState(() => _termsAccepted = value ?? false),
                      activeColor: DP.green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'I agree to the Terms of Service and confirm the information I’ve given is accurate.',
                      style: DPText.bodyMuted.copyWith(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (formError != null && (_bvnController.text.isNotEmpty || _ninController.text.isNotEmpty))
            DPNotice(formError, kind: DPNoticeKind.warn),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const DPIcon(DPIcons.lock, size: 14, color: DP.muted),
              const SizedBox(width: 6),
              Text('Your details are encrypted and only used to verify you.', style: DPText.small),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlySection() {
    return DPSummaryCard(rows: [
      DPSummaryRow('Full name', _fullName.isNotEmpty ? _fullName : 'Not set'),
      DPSummaryRow('Email', _email.isNotEmpty ? _email : 'Not set'),
      DPSummaryRow('Phone', _phone.isNotEmpty ? _phone : 'Not set'),
    ]);
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
    return DPField(
      label: label,
      labelTrailing: isValid && isUsing
          ? const DPIcon(DPIcons.circleCheck, size: 16, color: DP.green)
          : (isOptional ? Text('Optional', style: DPText.small) : null),
      controller: controller,
      hint: hint,
      errorText: errorText,
      onChanged: onChanged,
      onTap: onTap,
      readOnly: readOnly,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      suffixIcon: readOnly ? DPIcons.chevronDown : null,
      onSuffixTap: readOnly ? onTap : null,
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
    final String? gender = await showDPSheet<String>(
      context,
      title: 'Gender',
      builder: (ctx) => Column(
        children: [
          for (final g in const ['Male', 'Female', 'Other'])
            DPOptionRow(
              title: g,
              selected: _genderController.text == g,
              onTap: () => Navigator.pop(ctx, g),
            ),
        ],
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
