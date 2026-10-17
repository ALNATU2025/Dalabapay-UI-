// lib/presentation/screens/wallet/send_money_screen.dart
// "Send Money" — Dalabapay wallet to Dalabapay wallet, by phone number or
// email. Uses PaymentService.transferToUser (POST /api/transfer) and the
// recipient name check POST /api/transfer/lookup.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/payment_service.dart';
import '../../../ui/ui.dart';

class SendMoneyView extends StatefulWidget {
  final String userId;
  final void Function(double newBalance) onBalanceUpdate;
  const SendMoneyView({
    super.key,
    required this.userId,
    required this.onBalanceUpdate,
  });

  @override
  State<SendMoneyView> createState() => _SendMoneyViewState();
}

class _SendMoneyViewState extends State<SendMoneyView> {
  final _emailController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _pinController = TextEditingController();

  double _balance = 0;
  bool _balanceLoading = true;
  bool _pinSet = false;
  bool _biometricEnabled = false;

  bool _lookingUp = false;
  String? _recipientName;
  String? _lookupError;
  String _lookedUpEmail = '';

  /// 0 = phone number, 1 = email
  int _mode = 0;
  final _phoneController = TextEditingController();
  String _lookedUpPhone = '';

  bool _reviewing = false;
  bool _sending = false;
  String? _pinError;
  Map<String, dynamic>? _result;

  static final _emailRe = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bal = await ApiService.getBalance();
      if (!mounted) return;
      setState(() {
        _balance = bal;
        _pinSet = prefs.getBool('transactionPinSet') ?? false;
        _biometricEnabled = prefs.getBool('biometricEnabled') ?? false;
        _balanceLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _balanceLoading = false);
    }
  }

  double get _amount => double.tryParse(_amountController.text.trim()) ?? 0;
  String get _email => _emailController.text.trim().toLowerCase();

  String get _phone => _phoneController.text.replaceAll(RegExp(r'\D'), '');
  static final _phoneRe = RegExp(r'^(0|234)[789][01]\d{8}$');

  /// The recipient identifier currently typed.
  String get _identifier => _mode == 0 ? _phone : _email;

  /// The identifier that was successfully looked up (for this mode).
  String get _verifiedIdentifier => _mode == 0 ? _lookedUpPhone : _lookedUpEmail;

  bool get _recipientVerified =>
      _recipientName != null &&
      _identifier.isNotEmpty &&
      _verifiedIdentifier == _identifier;

  bool get _identifierValid =>
      _mode == 0 ? _phoneRe.hasMatch(_phone) : _emailRe.hasMatch(_email);

  bool get _canContinue =>
      _identifierValid && _amount > 0 && _amount <= _balance && !_lookingUp;

  bool get _canReview => _recipientVerified && _amount > 0 && _amount <= _balance;

  String get _recipientLabel => _mode == 0 ? _lookedUpPhone : _lookedUpEmail;

  void _setMode(int m) {
    setState(() {
      _mode = m;
      _recipientName = null;
      _lookupError = null;
      _lookedUpEmail = '';
      _lookedUpPhone = '';
    });
  }

  /// Continue: check the recipient first if needed, then open the review.
  Future<void> _continue() async {
    FocusScope.of(context).unfocus();
    if (!_recipientVerified) {
      await _lookup();
      if (!mounted || !_recipientVerified) return;
    }
    _openReview();
  }

  Future<void> _lookup() async {
    final byPhone = _mode == 0;
    final id = _identifier;
    if (!_identifierValid) {
      setState(
        () => _lookupError = byPhone
            ? 'Enter the recipient\'s 11-digit phone number'
            : 'Enter the recipient\'s Dalabapay email',
      );
      return;
    }
    setState(() {
      _lookingUp = true;
      _lookupError = null;
      _recipientName = null;
    });
    try {
      final res = await ApiService.authenticatedPost(
        '/api/transfer/lookup',
        byPhone ? {'phone': id} : {'email': id},
      );
      if (!mounted) return;
      if (res['success'] == true && res['recipient'] is Map) {
        setState(() {
          _recipientName = (res['recipient']['fullName'] ?? id).toString();
          if (byPhone) {
            _lookedUpPhone = id;
          } else {
            _lookedUpEmail = id;
          }
        });
      } else {
        setState(
          () => _lookupError = (res['message'] ??
                  'We couldn\'t find a Dalabapay account with that ${byPhone ? 'phone number' : 'email'}.')
              .toString(),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      final lower = msg.toLowerCase();
      setState(
        () => _lookupError = lower.contains('not found') ||
                lower.contains('couldn')
            ? 'We couldn\'t find a Dalabapay account with that ${byPhone ? 'phone number' : 'email'}.'
            : (lower.contains('more than one')
                ? msg
                : 'Couldn\'t check this recipient. Please try again.'),
      );
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  void _openReview() {
    FocusScope.of(context).unfocus();
    if (!_canReview) return;
    setState(() {
      _pinController.clear();
      _pinError = null;
      _reviewing = true;
    });
  }

  Future<void> _send({bool biometric = false}) async {
    if (_sending) return;
    final pin = _pinController.text.trim();
    if (!biometric && _pinSet && pin.length != 6) {
      setState(() => _pinError = 'Enter your 6-digit payment PIN');
      return;
    }
    if (!_pinSet && !biometric) {
      dpDialog(
        context,
        title: 'Set your payment PIN',
        message: 'Create a transaction PIN in Profile → Password & payment PIN before sending money.',
        tone: DPTone.warning,
      );
      return;
    }
    setState(() {
      _sending = true;
      _pinError = null;
    });
    HapticFeedback.mediumImpact();
    try {
      final note = _noteController.text.trim();
      final res = await PaymentService.transferToUser(
        receiverEmail: _mode == 0 ? '' : _lookedUpEmail,
        receiverPhone: _mode == 0 ? _lookedUpPhone : null,
        amount: _amount,
        transactionPin: biometric ? null : pin,
        useBiometric: biometric,
        description: note.isEmpty ? null : note,
      );
      if (!mounted) return;
      final newBalance = (res['newBalance'] as num?)?.toDouble();
      if (newBalance != null) {
        widget.onBalanceUpdate(newBalance);
        _balance = newBalance;
      }
      setState(() {
        _result = res;
        _reviewing = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '').replaceAll('Transfer failed: ', '');
      final lower = msg.toLowerCase();
      if (lower.contains('pin')) {
        setState(() => _pinError = msg);
        _pinController.clear();
      } else {
        dpDialog(context, title: 'Transfer not sent', message: msg, tone: DPTone.error);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_result != null) {
      return DPSuccessPanel(
        title: 'Money sent',
        subtitle: 'Your transfer is on its way.',
        serviceLabel: 'Wallet transfer',
        amount: _amount,
        rows: [
          DPReviewRow('Recipient', _recipientName ?? _recipientLabel),
          DPReviewRow(_mode == 0 ? 'Phone number' : 'Email', _recipientLabel),
          const DPReviewRow('Transfer fee', '₦0.00'),
          DPReviewRow('Date & time', DateTime.now().toString().substring(0, 16)),
          if (_result!['transactionId'] != null)
            DPReviewRow('Reference', _result!['transactionId'].toString()),
        ],
        onDone: () => Navigator.of(context).maybePop(),
      );
    }

    final biometricOk =
        !kIsWeb && (Platform.isAndroid || Platform.isIOS) && _biometricEnabled;

    return PopScope(
      canPop: !_reviewing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _reviewing && !_sending) {
          setState(() => _reviewing = false);
        }
      },
      child: Scaffold(
        backgroundColor: DP.bg,
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  const DPTopBar(title: 'Send Money'),
                  Expanded(child: _form()),
                ],
              ),
            ),
            if (_reviewing)
              Positioned.fill(
                child: DPReviewPanel(
                  icon: DPIcons.upRight,
                  title: 'To ${_recipientName ?? _recipientLabel}',
                  amount: _amount,
                  rows: [
                    DPReviewRow('Recipient', _recipientName ?? ''),
                    DPReviewRow(
                      _mode == 0 ? 'Phone number' : 'Email',
                      _recipientLabel,
                    ),
                    if (_noteController.text.trim().isNotEmpty)
                      DPReviewRow('Note', _noteController.text.trim()),
                    const DPReviewRow('Transfer fee', '₦0.00'),
                    DPReviewRow('Total to pay', DP.naira(_amount), strong: true),
                  ],
                  walletBalance: _balance,
                  totalDebit: _amount,
                  pinController: _pinController,
                  pinRequired: _pinSet,
                  pinError: _pinError,
                  processing: _sending,
                  payLabel: 'Send ${DP.naira(_amount)}',
                  onPay: () => _send(),
                  onClose: () => setState(() => _reviewing = false),
                  biometricAvailable: biometricOk,
                  onBiometric: () => _send(biometric: true),
                  footnote: 'Transfers to the wrong person may not be recoverable.',
                ),
              ),
          ],
        ),
        bottomNavigationBar: _reviewing
            ? null
            : DPBottomAction(
                footnote: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(DPIcons.shieldCheck, size: 16, color: DP.navyIcon),
                    SizedBox(width: 6),
                    Text(
                      'Your money is safe and secure with Dalabapay',
                      style: DP.caption,
                    ),
                  ],
                ),
                child: DPButton(
                  label: 'Continue',
                  loading: _lookingUp,
                  onPressed: _canContinue ? _continue : null,
                ),
              ),
      ),
    );
  }

  Widget _form() {
    final amount = _amount;
    final over = amount > _balance && !_balanceLoading;
    final byPhone = _mode == 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DPSegmented(
            options: const ['Phone Number', 'Email'],
            index: _mode,
            onChanged: _setMode,
          ),
          const SizedBox(height: 20),
          DPLabel(byPhone ? 'Recipient Phone Number' : 'Recipient Email'),
          if (byPhone)
            DPField(
              key: const ValueKey('phone'),
              controller: _phoneController,
              hint: 'e.g. 08012345678',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(13),
              ],
              prefix: const Icon(DPIcons.user, size: 20),
              onChanged: (_) {
                setState(() => _lookupError = null);
                // Look the name up as soon as a full number is typed
                if (_identifierValid && !_recipientVerified && !_lookingUp) {
                  _lookup();
                }
              },
              errorText: _lookupError,
              suffix: _lookingUp
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            )
          else
            DPField(
              key: const ValueKey('email'),
              controller: _emailController,
              hint: 'name@email.com',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              prefix: const Icon(DPIcons.mail, size: 20),
              onChanged: (_) => setState(() => _lookupError = null),
              onSubmitted: (_) => _lookup(),
              errorText: _lookupError,
              suffix: _lookingUp
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: 'Find recipient',
                      icon: const Icon(DPIcons.search),
                      onPressed: _lookup,
                    ),
            ),
          AnimatedSize(
            duration: DPMotion.base,
            curve: DPMotion.curve,
            child: _recipientVerified
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: DPAppear(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: DP.mint,
                          borderRadius: BorderRadius.circular(DP.rMd),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              DPIcons.checkCircle,
                              color: DP.green,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _recipientName!.toUpperCase(),
                                style: const TextStyle(
                                  color: DP.green,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 18),
          const DPLabel('Amount'),
          DPField(
            controller: _amountController,
            hint: '0.00',
            prefixText: '₦  ',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            onChanged: (_) => setState(() {}),
            errorText: over ? 'This is more than your wallet balance' : null,
            style: const TextStyle(
              fontSize: 16,
              color: DP.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          DPHelper(
            _balanceLoading
                ? 'Checking your balance…'
                : 'Wallet balance: ${DP.naira(_balance)}  ·  No transfer fee',
          ),
          const SizedBox(height: 18),
          const DPLabel('Add Note (Optional)'),
          DPField(
            controller: _noteController,
            hint: 'Enter a note...',
            maxLength: 60,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

}
