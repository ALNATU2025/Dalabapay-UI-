// lib/presentation/screens/settings/change_pin_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferences;
import '../../../core/services/api_service.dart';

class ChangePinScreen extends StatefulWidget {
  final String userId;
  final bool hasExistingPin;
  final String userEmail;

  const ChangePinScreen({
    super.key,
    required this.userId,
    required this.hasExistingPin,
    required this.userEmail,
  });

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final TextEditingController _currentPinController = TextEditingController();
  final TextEditingController _newPinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  bool _isLoading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _errorMessage;

  final Color _primaryColor = const Color(0xFF243889);
  final Color _secondaryColor = const Color(0xFF219C7E);
  final Color _textColor = const Color(0xFF1C2D5A);
  final Color _hintColor = const Color(0xFF94A3B8);
  final Color _successColor = const Color(0xFF219C7E);
  final Color _errorColor = const Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
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
        title: Text(
          widget.hasExistingPin ? 'Change PIN' : 'Set Transaction PIN',
          style: GoogleFonts.poppins(
            color: _primaryColor,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: _primaryColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.hasExistingPin
                          ? 'Enter your current PIN to change it. New PIN must be 6 digits.'
                          : 'Set a 6-digit PIN for secure transactions.',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: _textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            if (widget.hasExistingPin) ...[
              _buildPinField(
                controller: _currentPinController,
                label: 'Current PIN',
                hint: 'Enter current 6-digit PIN',
                obscure: _obscureCurrent,
                onToggle:
                    () => setState(() => _obscureCurrent = !_obscureCurrent),
              ),
              const SizedBox(height: 16),
            ],

            _buildPinField(
              controller: _newPinController,
              label: 'New PIN',
              hint: 'Enter new 6-digit PIN',
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
            ),
            const SizedBox(height: 16),

            _buildPinField(
              controller: _confirmPinController,
              label: 'Confirm PIN',
              hint: 'Confirm your new PIN',
              obscure: _obscureConfirm,
              onToggle:
                  () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            const SizedBox(height: 8),

            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _errorColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _errorColor.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: _errorColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: _errorColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _savePin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child:
                    _isLoading
                        ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                        : Text(
                          widget.hasExistingPin ? 'Change PIN' : 'Set PIN',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _textColor,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(fontSize: 14, color: _hintColor),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _primaryColor, width: 2),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            suffixIcon: IconButton(
              icon: Icon(
                obscure ? Icons.visibility_off : Icons.visibility,
                color: _hintColor,
              ),
              onPressed: onToggle,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          style: GoogleFonts.poppins(
            fontSize: 16,
            color: _textColor,
            letterSpacing: 4,
          ),
          onChanged: (_) {
            if (_errorMessage != null) {
              setState(() => _errorMessage = null);
            }
          },
        ),
      ],
    );
  }

  Future<void> _savePin() async {
    final newPin = _newPinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (widget.hasExistingPin) {
      final currentPin = _currentPinController.text.trim();
      if (currentPin.isEmpty) {
        setState(() => _errorMessage = 'Please enter your current PIN');
        return;
      }
      if (currentPin.length != 6) {
        setState(() => _errorMessage = 'Current PIN must be 6 digits');
        return;
      }
    }

    if (newPin.isEmpty) {
      setState(() => _errorMessage = 'Please enter a new PIN');
      return;
    }

    if (newPin.length != 6) {
      setState(() => _errorMessage = 'PIN must be exactly 6 digits');
      return;
    }

    if (newPin != confirmPin) {
      setState(() => _errorMessage = 'PINs do not match');
      return;
    }

    // Check for common PINs
    final commonPins = [
      '123456',
      '111111',
      '000000',
      '121212',
      '777777',
      '100400',
      '200000',
      '444444',
      '222222',
      '333333',
    ];
    if (commonPins.contains(newPin)) {
      setState(
        () =>
            _errorMessage =
                'PIN is too common. Please choose a more secure PIN',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      Map<String, dynamic> result;

      if (widget.hasExistingPin) {
        result = await ApiService.changeTransactionPin(
          userId: widget.userId,
          currentPin: _currentPinController.text,
          newPin: newPin,
        );
      } else {
        result = await ApiService.setTransactionPin(
          userId: widget.userId,
          pin: newPin,
        );
      }

      if (result['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('transactionPinSet', true);
        await prefs.setBool('hasTransactionPin_${widget.userId}', true);

        _showSuccess(
          widget.hasExistingPin
              ? 'PIN changed successfully!'
              : 'PIN set successfully!',
        );

        _currentPinController.clear();
        _newPinController.clear();
        _confirmPinController.clear();

        Future.delayed(const Duration(seconds: 1), () {
          Navigator.pop(context, {'success': true});
        });
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Failed to save PIN';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: _successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _currentPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }
}
