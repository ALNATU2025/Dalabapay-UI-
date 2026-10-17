// lib/presentation/screens/ticket/ticket_screen.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/receipt_widget.dart';

class TicketScreen extends StatefulWidget {
  final void Function(double newBalance) onBalanceUpdate;
  final String userId;

  const TicketScreen({
    super.key,
    required this.onBalanceUpdate,
    required this.userId,
  });

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen>
    with TickerProviderStateMixin {
  // Controllers
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _passengerNameController =
      TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  // Focus Nodes
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _fromFocusNode = FocusNode();
  final FocusNode _toFocusNode = FocusNode();
  final FocusNode _dateFocusNode = FocusNode();
  final FocusNode _pinFocusNode = FocusNode();

  // State Variables
  String? _selectedCategory;
  String? _selectedFrom;
  String? _selectedTo;
  DateTime? _selectedDate;
  bool _isLoading = false;
  bool _isAuthenticating = false;
  bool _isBalanceVisible = true;
  double _walletBalance = 0.0;

  // Authentication State
  bool _transactionPinSet = false;
  bool _biometricEnabled = false;
  bool _pinRequired = true;
  bool _biometricAllowed = true;
  bool _useBiometric = false;
  bool _pinLocked = false;
  int _lockTimeRemaining = 0;
  String? _pinValidationError;
  String _biometricName = 'Biometric';

  // Service State
  final bool _ticketServiceEnabled = true;
  bool _isUserActive = true;
  bool _isLoadingUserData = true;

  // Animation
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController _sheetController;
  late Animation<double> _sheetAnimation;

  // Categories
  final List<Map<String, dynamic>> _categories = [
    {'name': 'All', 'icon': HugeIcons.strokeRoundedDashboardSquare01},
    {'name': 'Flight', 'icon': HugeIcons.strokeRoundedAirplane01},
    {'name': 'Bus', 'icon': HugeIcons.strokeRoundedBus01},
    {'name': 'Train', 'icon': HugeIcons.strokeRoundedTrain01},
    {'name': 'Event', 'icon': HugeIcons.strokeRoundedCalendar01},
    {'name': 'Movie', 'icon': HugeIcons.strokeRoundedFlimSlate},
  ];

  // Locations (for demo)
  final List<String> _locations = [
    'Lagos, Nigeria',
    'Abuja, Nigeria',
    'Port Harcourt, Nigeria',
    'Ibadan, Nigeria',
    'Kano, Nigeria',
    'Enugu, Nigeria',
    'Benin City, Nigeria',
    'Warri, Nigeria',
    'Accra, Ghana',
    'Nairobi, Kenya',
    'Cape Town, South Africa',
    'Cairo, Egypt',
  ];

  // Quick Trip Suggestions
  final List<Map<String, String>> _quickTrips = [
    {'from': 'Lagos', 'to': 'Abuja'},
    {'from': 'Lagos', 'to': 'Port Harcourt'},
    {'from': 'Abuja', 'to': 'Kano'},
    {'from': 'Ibadan', 'to': 'Lagos'},
  ];

  // Passenger count
  int _passengerCount = 1;

  // Payment Sheet State
  bool _showPaymentSheet = false;
  bool _isProcessingPayment = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeData();
    _fetchSecuritySettings();
    _loadWalletBalance();
    _checkBiometricSupport();
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _fadeController.forward();

    _sheetController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _sheetAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _sheetController, curve: Curves.easeOutCubic),
    );
  }

  Future<void> _checkBiometricSupport() async {
    try {
      final isAvailable = await ApiService.isBiometricAvailable();
      final prefs = await SharedPreferences.getInstance();
      final isEnabled = prefs.getBool('biometricEnabled') ?? false;

      if (isAvailable && isEnabled) {
        final name = await ApiService.getBiometricName();
        setState(() {
          _biometricName = name;
          _biometricEnabled = true;
        });
      } else if (isAvailable) {
        final name = await ApiService.getBiometricName();
        setState(() {
          _biometricName = name;
          _biometricEnabled = false;
        });
      }
    } catch (e) {
      debugPrint('Biometric check error: $e');
    }
  }

  Future<void> _initializeData() async {
    try {
      final user = await ApiService.getCurrentUser();
      setState(() {
        _isUserActive = user['isActive'] ?? true;
        _isLoadingUserData = false;
      });
    } catch (e) {
      setState(() => _isLoadingUserData = false);
    }
  }

  Future<void> _loadWalletBalance() async {
    try {
      final balance = await ApiService.getBalance();
      if (mounted) {
        setState(() => _walletBalance = balance);
      }
    } catch (e) {
      // Silent fail
    }
  }

  Future<void> _fetchSecuritySettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _transactionPinSet = prefs.getBool('transactionPinSet') ?? false;
        _biometricEnabled = prefs.getBool('biometricEnabled') ?? false;
      });

      final globalSettings = await ApiService.getGlobalSecuritySettings();
      setState(() {
        _pinRequired = globalSettings['pinRequired'] ?? true;
        _biometricAllowed = globalSettings['biometricAllowed'] ?? true;
      });

      final securitySettings = await ApiService.getSecuritySettings();
      setState(() {
        _pinLocked = securitySettings['securitySettings']['pinLocked'] ?? false;
        _lockTimeRemaining =
            securitySettings['securitySettings']['lockTimeRemaining'] ?? 0;
      });
    } catch (e) {
      // Silent fail
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _sheetController.dispose();
    _searchController.dispose();
    _fromController.dispose();
    _toController.dispose();
    _dateController.dispose();
    _passengerNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    _searchFocusNode.dispose();
    _fromFocusNode.dispose();
    _toFocusNode.dispose();
    _dateFocusNode.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  String? _validateForm() {
    if (_selectedCategory == null || _selectedCategory == 'All') {
      return 'Please select a category';
    }

    if (_selectedFrom == null || _selectedFrom!.isEmpty) {
      return 'Please select departure location';
    }

    if (_selectedTo == null || _selectedTo!.isEmpty) {
      return 'Please select destination';
    }

    if (_selectedTo == _selectedFrom) {
      return 'Departure and destination cannot be the same';
    }

    if (_selectedDate == null) {
      return 'Please select a travel date';
    }

    if (_selectedDate!.isBefore(DateTime.now())) {
      return 'Travel date cannot be in the past';
    }

    if (_passengerNameController.text.trim().isEmpty) {
      return 'Please enter passenger name';
    }

    if (_emailController.text.trim().isEmpty) {
      return 'Please enter email address';
    }

    if (!RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(_emailController.text.trim())) {
      return 'Please enter a valid email address';
    }

    if (_phoneController.text.trim().isEmpty) {
      return 'Please enter phone number';
    }

    if (_phoneController.text.trim().length != 11) {
      return 'Phone number must be exactly 11 digits';
    }

    return null;
  }

  String _mapExceptionToUserMessage(dynamic e) {
    final errorStr = e.toString().replaceAll('Exception: ', '');
    if (errorStr.contains('Insufficient wallet balance')) {
      return 'Insufficient wallet balance. Please fund your wallet.';
    } else if (errorStr.contains('service is currently disabled')) {
      return 'Service temporarily unavailable. Please try again later.';
    } else if (errorStr.contains('No internet connection')) {
      return 'No internet connection detected.';
    } else if (errorStr.contains('timeout')) {
      return 'Request timed out. Please check your connection.';
    } else if (errorStr.contains('Authentication token not found')) {
      return 'Session expired. Please log in again.';
    } else if (errorStr.contains('Invalid transaction PIN')) {
      return errorStr;
    } else if (errorStr.contains('Biometric authentication failed')) {
      return 'Biometric authentication failed. Please try again or use your PIN.';
    } else if (errorStr.contains('Biometric not available')) {
      return 'Biometric is not available on this device. Please use your PIN.';
    }
    return errorStr.length > 100 ? 'An unexpected error occurred.' : errorStr;
  }

  // ==================== OPEN PAYMENT SHEET ====================

  void _openPaymentSheet() {
    final validationError = _validateForm();
    if (validationError != null) {
      _showErrorDialog('Validation Error', validationError);
      return;
    }

    setState(() {
      _pinValidationError = null;
      _pinController.clear();
      _showPaymentSheet = true;
      _useBiometric = false;
    });
    _sheetController.forward();
  }

  void _closePaymentSheet() {
    _sheetController.reverse().then((_) {
      setState(() {
        _showPaymentSheet = false;
        _isProcessingPayment = false;
        _pinValidationError = null;
      });
    });
  }

  // ==================== PROCESS PAYMENT ====================

  Future<void> _processPaymentWithPIN() async {
    // Validate PIN
    if (!_transactionPinSet) {
      _showErrorDialog(
        'PIN Required',
        'Please set up a transaction PIN in Settings.',
      );
      return;
    }

    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() {
        _pinValidationError = 'Please enter your transaction PIN';
      });
      return;
    }
    if (pin.length != 6) {
      setState(() {
        _pinValidationError = 'PIN must be exactly 6 digits';
      });
      return;
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(pin)) {
      setState(() {
        _pinValidationError = 'PIN must contain only numbers';
      });
      return;
    }

    setState(() {
      _pinValidationError = null;
      _isProcessingPayment = true;
    });

    await _executeBooking(pin: pin);
  }

  Future<void> _processPaymentWithBiometric() async {
    setState(() {
      _isProcessingPayment = true;
      _isAuthenticating = true;
      _pinValidationError = null;
    });

    try {
      final isAvailable = await ApiService.isBiometricAvailable();
      if (!isAvailable) {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
        _showErrorDialog(
          'Biometric Not Available',
          'Biometric authentication is not available on this device. Please use your PIN.',
        );
        return;
      }

      if (!_biometricEnabled) {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
        _showErrorDialog(
          'Biometric Not Enabled',
          'Biometric authentication is not enabled. Please enable it in Settings or use your PIN.',
        );
        return;
      }

      final biometricSuccess = await ApiService.authenticateWithBiometrics();

      if (!biometricSuccess) {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
        _showErrorDialog(
          'Authentication Failed',
          'Biometric authentication failed. Please try again or use your PIN.',
        );
        return;
      }

      await _executeBooking(useBiometric: true);
    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
        _isAuthenticating = false;
      });
      _showErrorDialog('Authentication Error', _mapExceptionToUserMessage(e));
    }
  }

  // ==================== EXECUTE BOOKING WITH BALANCE CHECK ====================

  Future<void> _executeBooking({String? pin, bool useBiometric = false}) async {
    try {
      setState(() {
        _isLoading = true;
        _isAuthenticating = true;
      });

      // ✅ 1. Calculate the ticket price
      final amount = _calculateTicketPrice();

      // ✅ 2. Get current balance from API
      final currentBalance = await ApiService.getBalance();

      // ✅ 3. Check if user has enough balance
      if (currentBalance < amount) {
        setState(() {
          _isProcessingPayment = false;
          _isLoading = false;
          _isAuthenticating = false;
        });
        _showErrorDialog(
          'Insufficient Balance',
          'Your wallet balance (₦${currentBalance.toStringAsFixed(2)}) is insufficient.\n\n'
              'Ticket cost: ₦${amount.toStringAsFixed(2)}\n'
              'Please fund your wallet and try again.',
        );
        _closePaymentSheet();
        return;
      }

      // ✅ 4. Process the booking with balance deduction
      final result = await _bookTicketWithBalanceCheck(
        amount: amount,
        pin: pin,
        useBiometric: useBiometric,
      );

      if (result['success'] == true) {
        final newBalance = result['newBalance'] ?? 0.0;

        // ✅ 5. Update balance in the app
        widget.onBalanceUpdate(newBalance);
        setState(() {
          _walletBalance = newBalance;
        });

        // ✅ 6. Store the new balance in SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('walletBalance', newBalance);

        _closePaymentSheet();
        _showSuccessDialog(result);
        _clearForm();
      } else {
        setState(() {
          _isProcessingPayment = false;
        });
        _showErrorDialog(
          'Booking Failed',
          result['message'] ?? 'Please try again.',
        );
      }
    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
      });
      _showErrorDialog('Booking Failed', _mapExceptionToUserMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isAuthenticating = false;
          _isProcessingPayment = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _bookTicketWithBalanceCheck({
    required double amount,
    String? pin,
    bool useBiometric = false,
  }) async {
    try {
      // ✅ Get current balance from API (double-check)
      final currentBalance = await ApiService.getBalance();

      // ✅ Double-check balance (redundant but safe)
      if (currentBalance < amount) {
        return {
          'success': false,
          'message': 'Insufficient balance. Please fund your wallet.',
          'currentBalance': currentBalance,
          'requiredAmount': amount,
        };
      }

      // ✅ Calculate new balance
      final newBalance = currentBalance - amount;

      // ✅ Simulate API call for booking
      await Future.delayed(const Duration(seconds: 2));

      return {
        'success': true,
        'newBalance': newBalance,
        'transactionId': 'TXN_${DateTime.now().millisecondsSinceEpoch}',
        'amount': amount,
        'ticket': {
          'category': _selectedCategory,
          'from': _selectedFrom,
          'to': _selectedTo,
          'date': _selectedDate!.toIso8601String(),
          'passengerName': _passengerNameController.text.trim(),
          'email': _emailController.text.trim(),
          'phone': _phoneController.text.trim(),
          'passengerCount': _passengerCount,
          'reference': 'REF_${DateTime.now().millisecondsSinceEpoch}',
        },
      };
    } catch (e) {
      return {'success': false, 'message': _mapExceptionToUserMessage(e)};
    }
  }

  double _calculateTicketPrice() {
    final basePrice = 5000.0;
    final distanceMultiplier = _getDistanceMultiplier();
    final categoryMultiplier = _getCategoryMultiplier();
    return basePrice *
        distanceMultiplier *
        categoryMultiplier *
        _passengerCount;
  }

  double _getDistanceMultiplier() {
    if (_selectedFrom == null || _selectedTo == null) return 1.0;
    final fromIndex = _locations.indexOf(_selectedFrom!);
    final toIndex = _locations.indexOf(_selectedTo!);
    final diff = (fromIndex - toIndex).abs();
    return 1.0 + (diff * 0.1);
  }

  double _getCategoryMultiplier() {
    switch (_selectedCategory) {
      case 'Flight':
        return 3.0;
      case 'Train':
        return 1.5;
      case 'Event':
        return 1.2;
      case 'Movie':
        return 0.8;
      case 'Bus':
      default:
        return 1.0;
    }
  }

  void _showSuccessDialog(Map<String, dynamic> result) {
    final ticket = result['ticket'] as Map<String, dynamic>;
    final amount = result['amount'] as double;
    final transactionId = result['transactionId'] as String;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ReceiptWidget(
              transactionType: 'Ticket Booking',
              amount: amount.toStringAsFixed(2),
              status: 'delivered',
              transactionId: transactionId,
              reference: ticket['reference'] ?? transactionId,
              date: DateTime.now(),
              phoneNumber: ticket['phone'] ?? '',
              description:
                  '${ticket['from']} → ${ticket['to']} (${ticket['category']})',
              customMessage: '✓ Booking confirmed! Enjoy your trip.',
              primaryColor: const Color(0xFF243889),
              showWatermark: true,
              isAdminTransaction: false,
              isUserAdmin: false,
            ),
          ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: Colors.white,
            title: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700, size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            content: Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'OK',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF219C7E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _clearForm() {
    _fromController.clear();
    _toController.clear();
    _dateController.clear();
    _passengerNameController.clear();
    _emailController.clear();
    _phoneController.clear();
    _pinController.clear();
    setState(() {
      _selectedCategory = null;
      _selectedFrom = null;
      _selectedTo = null;
      _selectedDate = null;
      _passengerCount = 1;
      _useBiometric = false;
      _pinValidationError = null;
    });
  }

  void _selectQuickTrip(String from, String to) {
    setState(() {
      _selectedFrom = from;
      _selectedTo = to;
      _fromController.text = from;
      _toController.text = to;
    });
  }

  void _incrementPassengers() {
    setState(() {
      if (_passengerCount < 10) _passengerCount++;
    });
  }

  void _decrementPassengers() {
    setState(() {
      if (_passengerCount > 1) _passengerCount--;
    });
  }

  Widget _buildCategoryChip(Map<String, dynamic> category, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategory = category['name'];
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF243889) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF243889) : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: category['icon'] as dynamic,
              size: 18,
              color: isSelected ? Colors.white : const Color(0xFF243889),
            ),
            const SizedBox(width: 8),
            Text(
              category['name'] as String,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF243889),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required dynamic icon,
    required String? selectedValue,
    required void Function(String) onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hint,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF243889),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          child: DropdownButtonFormField<String>(
            initialValue: selectedValue,
            isExpanded: true,
            decoration: InputDecoration(
              prefixIcon: HugeIcon(
                icon: icon,
                color: const Color(0xFF243889),
                size: 22,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 12,
              ),
              hintText: 'Select $hint',
              hintStyle: GoogleFonts.poppins(
                color: Colors.grey.shade400,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF243889),
            ),
            items:
                _locations.map((location) {
                  return DropdownMenuItem<String>(
                    value: location,
                    child: Text(
                      location,
                      style: GoogleFonts.poppins(fontSize: 14),
                    ),
                  );
                }).toList(),
            onChanged: (value) {
              if (value != null) {
                onSelected(value);
              }
            },
            dropdownColor: Colors.white,
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedArrowDown01,
              color: const Color(0xFF243889),
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Travel Date',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF243889),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: DateTime.now().add(const Duration(days: 1)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              builder: (context, child) {
                return Theme(
                  data: ThemeData.light().copyWith(
                    primaryColor: const Color(0xFF243889),
                    colorScheme: const ColorScheme.light(
                      primary: Color(0xFF243889),
                    ),
                    buttonTheme: const ButtonThemeData(
                      textTheme: ButtonTextTheme.primary,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (date != null) {
              setState(() {
                _selectedDate = date;
                _dateController.text = DateFormat('MMM dd, yyyy').format(date);
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200, width: 1),
            ),
            child: TextField(
              controller: _dateController,
              focusNode: _dateFocusNode,
              enabled: false,
              decoration: InputDecoration(
                hintText: 'Select Date',
                hintStyle: GoogleFonts.poppins(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                prefixIcon: HugeIcon(
                  icon: HugeIcons.strokeRoundedCalendar01,
                  color: const Color(0xFF243889),
                  size: 22,
                ),
                suffixIcon: HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowDown01,
                  color: const Color(0xFF243889),
                  size: 20,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.transparent,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 14,
                ),
              ),
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color:
                    _selectedDate != null
                        ? const Color(0xFF243889)
                        : Colors.grey.shade400,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickTripsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Trips',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF243889),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              _quickTrips.map((trip) {
                final isSelected =
                    _selectedFrom == trip['from'] && _selectedTo == trip['to'];
                return GestureDetector(
                  onTap: () => _selectQuickTrip(trip['from']!, trip['to']!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isSelected
                              ? const Color(0xFF243889).withOpacity(0.1)
                              : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            isSelected
                                ? const Color(0xFF243889)
                                : Colors.grey.shade300,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedArrowRight01,
                          size: 14,
                          color:
                              isSelected
                                  ? const Color(0xFF243889)
                                  : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${trip['from']} → ${trip['to']}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            color:
                                isSelected
                                    ? const Color(0xFF243889)
                                    : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }

  Widget _buildPassengerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Passenger Details',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF243889),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: TextField(
                  controller: _passengerNameController,
                  decoration: InputDecoration(
                    hintText: 'Full Name',
                    hintStyle: GoogleFonts.poppins(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    prefixIcon: HugeIcon(
                      icon: HugeIcons.strokeRoundedUser,
                      color: const Color(0xFF243889),
                      size: 22,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.transparent,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 14,
                    ),
                  ),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200, width: 1),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedMinusSign,
                        size: 20,
                        color: const Color(0xFF243889),
                      ),
                      onPressed: _decrementPassengers,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    Text(
                      '$_passengerCount',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF243889),
                      ),
                    ),
                    IconButton(
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedAdd01,
                        size: 20,
                        color: const Color(0xFF243889),
                      ),
                      onPressed: _incrementPassengers,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContactSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Contact Details',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF243889),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'Email Address',
              hintStyle: GoogleFonts.poppins(
                color: Colors.grey.shade400,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: HugeIcon(
                icon: HugeIcons.strokeRoundedMail01,
                color: const Color(0xFF243889),
                size: 22,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 14,
              ),
            ),
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
            ],
            decoration: InputDecoration(
              hintText: 'Phone Number (11 digits)',
              hintStyle: GoogleFonts.poppins(
                color: Colors.grey.shade400,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: HugeIcon(
                icon: HugeIcons.strokeRoundedSmartPhone01,
                color: const Color(0xFF243889),
                size: 22,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 14,
              ),
            ),
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x05243889),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Container(
            width: 23,
            height: 23,
            decoration: BoxDecoration(
              color: const Color(0xFF243889).withOpacity(0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.info_outline,
              color: Color(0xFF243889),
              size: 16,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              'Book your tickets instantly.\nSecure and reliable.',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF243889),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== PAYMENT SHEET OVERLAY ====================

  Widget _buildPaymentSheetOverlay() {
    return GestureDetector(
      onTap: _isProcessingPayment ? null : _closePaymentSheet,
      child: AnimatedBuilder(
        animation: _sheetAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _sheetAnimation.value,
            child: Container(
              color: Colors.black.withOpacity(0.4 * _sheetAnimation.value),
              child: Stack(
                children: [
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Transform.translate(
                      offset: Offset(
                        0,
                        (1 - _sheetAnimation.value) *
                            MediaQuery.of(context).size.height *
                            0.6,
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        child: SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 12),
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Stack(
                                children: [
                                  Center(
                                    child: Image.asset(
                                      'assets/dalabapay2.png',
                                      height: 40,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  Positioned(
                                    right: 16,
                                    top: 0,
                                    child: GestureDetector(
                                      onTap:
                                          _isProcessingPayment
                                              ? null
                                              : _closePaymentSheet,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 18,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Confirm Booking',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1C2D5A),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildPaymentSheetDetails(),
                              const SizedBox(height: 16),
                              _buildPaymentSheetBalance(),
                              const SizedBox(height: 20),
                              Divider(
                                color: Colors.grey.shade200,
                                thickness: 1,
                              ),
                              const SizedBox(height: 20),
                              // Pay with PIN Option
                              if (_transactionPinSet) ...[
                                _buildPinOption(),
                                const SizedBox(height: 12),
                              ],
                              // Pay with Biometric Option
                              if (_biometricEnabled && _biometricAllowed)
                                _buildBiometricOption(),
                              if (!_transactionPinSet && !_biometricEnabled)
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.orange.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.warning_amber,
                                        color: Colors.orange.shade700,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Set up a transaction PIN or enable biometric in Settings to make payments.',
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.orange.shade800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ==================== PAYMENT SHEET DETAILS ====================

  Widget _buildPaymentSheetDetails() {
    final price = _calculateTicketPrice();
    final formattedDate =
        _selectedDate != null
            ? DateFormat('MMM dd, yyyy').format(_selectedDate!)
            : 'N/A';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          // Category
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF243889).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedTicket01,
                      color: const Color(0xFF243889),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Category',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Flexible(
                child: Text(
                  _selectedCategory ?? 'N/A',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1C2D5A),
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Divider(height: 12, color: Colors.grey.shade200),
          // From
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF243889).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedAirplaneTakeOff01,
                      color: const Color(0xFF243889),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'From',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Flexible(
                child: Text(
                  _selectedFrom ?? 'N/A',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1C2D5A),
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Divider(height: 12, color: Colors.grey.shade200),
          // To
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF243889).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedAirplaneLanding01,
                      color: const Color(0xFF243889),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'To',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Flexible(
                child: Text(
                  _selectedTo ?? 'N/A',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1C2D5A),
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Divider(height: 12, color: Colors.grey.shade200),
          // Date
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF243889).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedCalendar01,
                      color: const Color(0xFF243889),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Date',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Flexible(
                child: Text(
                  formattedDate,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1C2D5A),
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Divider(height: 12, color: Colors.grey.shade200),
          // Passengers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF243889).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedUser,
                      color: const Color(0xFF243889),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Passengers',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Text(
                '$_passengerCount',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1C2D5A),
                ),
              ),
            ],
          ),
          Divider(height: 12, color: Colors.grey.shade200),
          // Amount
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF219C7E).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedMoney01,
                      color: const Color(0xFF219C7E),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Total',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Text(
                '₦${price.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF219C7E),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSheetBalance() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF219C7E).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF219C7E).withOpacity(0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedWallet01,
                  color: const Color(0xFF219C7E),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Available Balance',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '₦${_walletBalance.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF219C7E),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== PIN OPTION ====================

  Widget _buildPinOption() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color:
              _useBiometric
                  ? Colors.grey.shade50
                  : const Color(0xFF243889).withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                _useBiometric ? Colors.grey.shade300 : const Color(0xFF243889),
            width: _useBiometric ? 1 : 2,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _pinController,
                focusNode: _pinFocusNode,
                obscureText: true,
                enabled: !_useBiometric,
                decoration: InputDecoration(
                  hintText: 'Enter 6-digit transaction PIN',
                  hintStyle: GoogleFonts.poppins(
                    color:
                        _useBiometric
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  prefixIcon: Icon(
                    Icons.lock_outline,
                    color:
                        _useBiometric
                            ? Colors.grey.shade400
                            : const Color(0xFF243889),
                    size: 18,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 12,
                  ),
                  errorText: _pinValidationError,
                  errorStyle: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _useBiometric ? Colors.grey.shade400 : Colors.black,
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onChanged: (_) => setState(() => _pinValidationError = null),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed:
                    _isProcessingPayment || _useBiometric
                        ? null
                        : _processPaymentWithPIN,
                style: TextButton.styleFrom(
                  backgroundColor:
                      _useBiometric
                          ? Colors.transparent
                          : const Color(0xFF219C7E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child:
                    _isProcessingPayment && !_useBiometric
                        ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                        : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              color:
                                  _useBiometric
                                      ? Colors.grey.shade400
                                      : Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _useBiometric ? 'Switch to PIN' : 'Pay with PIN',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color:
                                    _useBiometric
                                        ? Colors.grey.shade400
                                        : Colors.white,
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

  // ==================== BIOMETRIC OPTION ====================

  Widget _buildBiometricOption() {
    final bool isBiometricSupported = Platform.isAndroid || Platform.isIOS;

    if (!isBiometricSupported || !_biometricEnabled) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: _isProcessingPayment ? null : _processPaymentWithBiometric,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color:
                _useBiometric
                    ? const Color(0xFF243889).withOpacity(0.08)
                    : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  _useBiometric
                      ? const Color(0xFF243889)
                      : Colors.grey.shade300,
              width: _useBiometric ? 2 : 1,
            ),
          ),
          child:
              _isProcessingPayment && _useBiometric
                  ? Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: const Color(0xFF243889),
                        strokeWidth: 2.5,
                      ),
                    ),
                  )
                  : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.fingerprint,
                        color:
                            _useBiometric
                                ? const Color(0xFF243889)
                                : Colors.grey.shade600,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _useBiometric
                              ? 'Tap to authenticate with $_biometricName'
                              : 'Pay with $_biometricName',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color:
                                _useBiometric
                                    ? const Color(0xFF243889)
                                    : Colors.grey.shade700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_useBiometric)
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF219C7E),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 12,
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          _buildBody(),
          if (_showPaymentSheet) _buildPaymentSheetOverlay(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios,
          color: Color(0xFF243889),
          size: 20,
        ),
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
              color: const Color(0xFF243889),
              letterSpacing: 0.09,
            ),
          ),
          Text(
            'pay',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF219C7E),
              letterSpacing: 0.09,
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0x05243889),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: Color(0xFF243889),
                size: 16,
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap:
                    () =>
                        setState(() => _isBalanceVisible = !_isBalanceVisible),
                child: Text(
                  _isBalanceVisible
                      ? '₦${_walletBalance.toStringAsFixed(2)}'
                      : '••••',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF243889),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoadingUserData) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF243889)),
        ),
      );
    }

    if (!_isUserActive || !_ticketServiceEnabled) {
      return _buildServiceUnavailable();
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBanner(),
              const SizedBox(height: 24),
              _buildCategoriesSection(),
              const SizedBox(height: 20),
              _buildLocationField(
                controller: _fromController,
                focusNode: _fromFocusNode,
                hint: 'Departure',
                icon: HugeIcons.strokeRoundedAirplaneTakeOff01,
                selectedValue: _selectedFrom,
                onSelected: (value) {
                  setState(() => _selectedFrom = value);
                },
              ),
              const SizedBox(height: 16),
              _buildLocationField(
                controller: _toController,
                focusNode: _toFocusNode,
                hint: 'Destination',
                icon: HugeIcons.strokeRoundedAirplaneLanding01,
                selectedValue: _selectedTo,
                onSelected: (value) {
                  setState(() => _selectedTo = value);
                },
              ),
              const SizedBox(height: 16),
              _buildDateField(),
              const SizedBox(height: 16),
              _buildQuickTripsSection(),
              const SizedBox(height: 24),
              _buildPassengerSection(),
              const SizedBox(height: 16),
              _buildContactSection(),
              const SizedBox(height: 24),
              _buildInfoCard(),
              const SizedBox(height: 24),
              _buildPurchaseButton(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPurchaseButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed:
            (_isLoading || _isAuthenticating || _isProcessingPayment)
                ? null
                : _openPaymentSheet,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF219C7E),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          disabledBackgroundColor: Colors.grey.shade300,
        ),
        child:
            _isLoading || _isAuthenticating || _isProcessingPayment
                ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedSearch01,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Book Ticket',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  Widget _buildBanner() {
    return Container(
      width: double.infinity,
      height: 128,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        image: const DecorationImage(
          image: AssetImage('assets/ticket_banner.png'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildCategoriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Category',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF243889),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              _categories.map((category) {
                final isSelected = _selectedCategory == category['name'];
                return _buildCategoryChip(category, isSelected);
              }).toList(),
        ),
      ],
    );
  }

  Widget _buildServiceUnavailable() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              !_isUserActive
                  ? Icons.account_circle
                  : Icons.confirmation_number_outlined,
              color:
                  !_isUserActive ? Colors.red.shade700 : Colors.orange.shade700,
              size: 60,
            ),
            const SizedBox(height: 16),
            Text(
              !_isUserActive ? 'Account Deactivated' : 'Service Unavailable',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color:
                    !_isUserActive
                        ? Colors.red.shade700
                        : Colors.orange.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              !_isUserActive
                  ? 'Your account has been deactivated. Please contact support.'
                  : 'Ticket booking service is currently unavailable. Please try again later.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF243889),
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
                'Go Back',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
