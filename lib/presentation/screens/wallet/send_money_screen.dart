// lib/presentation/screens/wallet/send_money_screen.dart
// "Send money" from the redesign — Dalabapay wallet to Dalabapay wallet.
// Uses the existing PaymentService.transferToUser (POST /api/transfer) and the
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

  bool get _canReview =>
      _recipientName != null &&
      _lookedUpEmail == _email &&
      _amount > 0 &&
      _amount <= _balance;

  Future<void> _lookup() async {
    final email = _email;
    if (!_emailRe.hasMatch(email)) {
      setState(() => _lookupError = 'Enter the recipient\'s Dalabapay email');
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
        {'email': email},
      );
      if (!mounted) return;
      if (res['success'] == true && res['recipient'] is Map) {
        setState(() {
          _recipientName = (res['recipient']['fullName'] ?? email).toString();
          _lookedUpEmail = email;
        });
      } else {
        setState(
          () => _lookupError =
              (res['message'] ?? 'We couldn\'t find a Dalabapay account with that email.')
                  .toString(),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      setState(
        () => _lookupError = msg.toLowerCase().contains('not found')
            ? 'We couldn\'t find a Dalabapay account with that email.'
            : 'Couldn\'t check this recipient. Please try again.',
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
        receiverEmail: _lookedUpEmail,
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
          DPReviewRow('Recipient', _recipientName ?? _lookedUpEmail),
          DPReviewRow('Email', _lookedUpEmail),
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
                  const DPTopBar(title: 'Send money'),
                  Expanded(child: _form()),
                ],
              ),
            ),
            if (_reviewing)
              Positioned.fill(
                child: DPReviewPanel(
                  icon: DPIcons.upRight,
                  title: 'To ${_recipientName ?? _lookedUpEmail}',
                  amount: _amount,
                  rows: [
                    DPReviewRow('Recipient', _recipientName ?? ''),
                    DPReviewRow('Email', _lookedUpEmail),
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
                child: DPButton(
                  label: 'Review transfer',
                  icon: DPIcons.forward,
                  onPressed: _canReview ? _openReview : null,
                ),
              ),
      ),
    );
  }

  Widget _form() {
    final amount = _amount;
    final over = amount > _balance && !_balanceLoading;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'For the people and things that matter.',
            style: DP.body.copyWith(color: DP.muted),
          ),
          const SizedBox(height: 18),
          const DPChipRow(
            options: ['Dalabapay wallet'],
            selected: 'Dalabapay wallet',
            onSelect: _noop,
          ),
          const SizedBox(height: 20),
          const DPLabel('Recipient\'s email'),
          DPField(
            controller: _emailController,
            hint: 'name@email.com',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {
              if (_lookedUpEmail != _email) {
                _recipientName = null;
                _lookupError = null;
              }
            }),
            onSubmitted: (_) => _lookup(),
            errorText: _lookupError,
            suffix: _lookingUp
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: 'Find recipient',
                    icon: const Icon(DPIcons.search),
                    onPressed: _lookup,
                  ),
          ),
          if (_recipientName == null && _lookupError == null && !_lookingUp)
            Align(
              alignment: Alignment.centerRight,
              child: DPTextLink(label: 'Find recipient', onTap: _lookup),
            ),
          if (_recipientName != null && _lookedUpEmail == _email) ...[
            const SizedBox(height: 12),
            DPCard(
              color: DP.mint,
              borderColor: null,
              radius: DP.rLg,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  const Icon(DPIcons.checkCircle, color: DP.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _recipientName!.toUpperCase(),
                      style: const TextStyle(
                        color: DP.green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          const DPLabel('Amount'),
          DPField(
            controller: _amountController,
            hint: '0.00',
            prefixText: '₦',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            onChanged: (_) => setState(() {}),
            errorText: over ? 'This is more than your wallet balance' : null,
            style: const TextStyle(fontSize: 17, color: DP.ink),
          ),
          const SizedBox(height: 20),
          const DPLabel('Note (optional)'),
          DPField(
            controller: _noteController,
            hint: 'For the weekend',
            maxLength: 60,
            suffix: const Icon(DPIcons.edit, color: DP.muted),
          ),
          const SizedBox(height: 20),
          DPCard(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
            child: Column(
              children: [
                DPSummaryRow(
                  'Wallet balance',
                  _balanceLoading ? '…' : DP.naira(_balance),
                ),
                const DPSummaryRow('Transfer fee', '₦0.00'),
                DPSummaryRow('Total to pay', DP.naira(amount), strong: true),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const DPBanner(
            'Check the recipient\'s name. Transfers to the wrong account may not be recoverable.',
            tone: DPTone.warning,
          ),
        ],
      ),
    );
  }

  static void _noop(String _) {}
}
