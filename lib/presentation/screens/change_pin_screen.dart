// lib/presentation/screens/settings/change_pin_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferences;
import '../../../core/services/api_service.dart';
import '../../ui/ui.dart';

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

  final Color _primaryColor = const Color(0xFF102C68);
  final Color _secondaryColor = const Color(0xFF168566);
  final Color _textColor = const Color(0xFF14263D);
  final Color _hintColor = const Color(0xFFA9B2AC);
  final Color _successColor = const Color(0xFF168566);
  final Color _errorColor = const Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    final existing = widget.hasExistingPin;
    return DPPage(
      title: existing ? 'Change payment PIN' : 'Set payment PIN',
      bottom: DPButton(
        label: existing ? 'Change PIN' : 'Set PIN',
        loading: _isLoading,
        onPressed: _isLoading ? null : _savePin,
      ),
      children: [
        DPHeadline(
          existing ? 'Keep your money safe.' : 'Protect every payment.',
          subtitle: existing
              ? 'Enter your current PIN, then choose a new 6-digit PIN.'
              : 'You’ll use this 6-digit PIN to approve payments and transfers.',
        ),
        if (existing)
          _buildPinField(
            controller: _currentPinController,
            label: 'Current PIN',
            hint: '',
            obscure: _obscureCurrent,
            onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
          ),
        _buildPinField(
          controller: _newPinController,
          label: 'New PIN',
          hint: '',
          obscure: _obscureNew,
          onToggle: () => setState(() => _obscureNew = !_obscureNew),
        ),
        _buildPinField(
          controller: _confirmPinController,
          label: 'Confirm new PIN',
          hint: '',
          obscure: _obscureConfirm,
          onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
        ),
        if (_errorMessage != null) DPNotice(_errorMessage!, kind: DPNoticeKind.danger),
        const DPNotice(
          'Avoid easy PINs like 123456 or your birthday. Never share your PIN — Dalabapay staff will never ask for it.',
          kind: DPNoticeKind.info,
          margin: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildPinField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: DPFieldLabel(label)),
              DPLinkButton(label: obscure ? 'Show' : 'Hide', onPressed: onToggle),
            ],
          ),
          DPCodeInput(
            controller: controller,
            length: 6,
            obscure: obscure,
            error: _errorMessage != null,
            onChanged: (_) {
              if (_errorMessage != null) setState(() => _errorMessage = null);
            },
          ),
        ],
      ),
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
    if (!mounted) return;
    dpSnack(context, message, success: true);
  }

  @override
  void dispose() {
    _currentPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }
}
