// lib/presentation/screens/send_money/send_money_screen.dart
//
// "Send money" from the redesign: to a bank account (Paystack payouts via the
// backend's /api/bank-transfer endpoints) or to another Dalabapay wallet (the
// existing /api/transfer endpoint through PaymentService.transferWithRetry).
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/bank_transfer_service.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/services/payment_service.dart';
import '../../../core/widgets/receipt_widget.dart';
import '../../../ui/ui.dart';

class SendMoneyScreen extends StatefulWidget {
  final String userId;
  final void Function(double newBalance)? onBalanceUpdate;
  final bool startWithWallet;

  const SendMoneyScreen({
    super.key,
    required this.userId,
    this.onBalanceUpdate,
    this.startWithWallet = false,
  });

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen>
    with SingleTickerProviderStateMixin {
  // 0 = bank account, 1 = Dalabapay wallet
  late int _mode = widget.startWithWallet ? 1 : 0;

  final _accountController = TextEditingController();
  final _emailController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _pinController = TextEditingController();

  late final AnimationController _sheetController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _sheet =
      CurvedAnimation(parent: _sheetController, curve: Curves.easeOutCubic);

  double _walletBalance = 0;
  bool _transactionPinSet = false;
  bool _biometricEnabled = false;

  BankTransferConfig _config = BankTransferConfig.disabled;
  bool _loadingConfig = true;
  List<BankInfo> _banks = const [];
  bool _loadingBanks = false;
  BankInfo? _bank;
  String? _accountName;
  bool _resolving = false;
  String? _resolveError;

  String? _walletRecipientName;
  bool _lookingUpRecipient = false;

  bool _showSheet = false;
  bool _processing = false;
  bool _processingBiometric = false;
  String? _pinError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _accountController.dispose();
    _emailController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _pinController.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bio = await biometricService.getBiometricEnabledStatus(userId: widget.userId);
      if (mounted) {
        setState(() {
          _transactionPinSet = prefs.getBool('transactionPinSet') ?? false;
          _biometricEnabled = bio;
        });
      }
    } catch (_) {}
    try {
      final b = await ApiService.getBalance();
      if (mounted) setState(() => _walletBalance = b);
    } catch (_) {}
    final cfg = await BankTransferService.getConfig();
    if (!mounted) return;
    setState(() {
      _config = cfg;
      _loadingConfig = false;
      if (!cfg.enabled && !widget.startWithWallet) _mode = 1;
    });
    if (cfg.enabled) _loadBanks();
  }

  Future<void> _loadBanks() async {
    setState(() => _loadingBanks = true);
    try {
      final banks = await BankTransferService.getBanks();
      if (mounted) setState(() => _banks = banks);
    } catch (e) {
      if (mounted) dpSnack(context, 'Couldn’t load banks. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _loadingBanks = false);
    }
  }

  Future<void> _resolve() async {
    final acct = _accountController.text.trim();
    if (_bank == null || acct.length != 10) return;
    setState(() {
      _resolving = true;
      _resolveError = null;
      _accountName = null;
    });
    try {
      final name = await BankTransferService.resolveAccount(
        accountNumber: acct,
        bankCode: _bank!.code,
      );
      if (!mounted) return;
      setState(() {
        _accountName = name;
        if (name == null) _resolveError = 'We couldn’t find this account. Check the number and bank.';
      });
    } catch (e) {
      if (mounted) {
        setState(() => _resolveError = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _lookupRecipient() async {
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return;
    setState(() {
      _lookingUpRecipient = true;
      _walletRecipientName = null;
    });
    final name = await BankTransferService.lookupWalletRecipient(email);
    if (mounted) {
      setState(() {
        _walletRecipientName = name;
        _lookingUpRecipient = false;
      });
    }
  }

  double get _amount => double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0;
  double get _fee => _mode == 0 ? _config.fee : 0;
  double get _total => _amount + _fee;

  String? _validate() {
    if (_mode == 0) {
      if (!_config.enabled) return 'Bank transfers aren’t available yet.';
      if (_bank == null) return 'Choose the recipient’s bank.';
      if (_accountController.text.trim().length != 10) return 'Enter a 10-digit account number.';
      if (_accountName == null) return 'We need to confirm the account name first.';
      if (_amount < _config.minAmount) {
        return 'The minimum transfer is ${dpNaira(_config.minAmount, decimals: false)}.';
      }
      if (_config.maxAmount > 0 && _amount > _config.maxAmount) {
        return 'The maximum transfer is ${dpNaira(_config.maxAmount, decimals: false)}.';
      }
    } else {
      final email = _emailController.text.trim();
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
        return 'Enter the recipient’s Dalabapay email address.';
      }
      if (_amount <= 0) return 'Enter an amount.';
    }
    if (_total > _walletBalance) return 'Your wallet balance is too low for this transfer.';
    return null;
  }

  void _openReview() {
    FocusScope.of(context).unfocus();
    final err = _validate();
    if (err != null) {
      dpSnack(context, err, error: true);
      return;
    }
    setState(() {
      _pinController.clear();
      _pinError = null;
      _showSheet = true;
    });
    _sheetController.forward(from: 0);
  }

  void _closeReview() {
    _sheetController.reverse().then((_) {
      if (mounted) setState(() => _showSheet = false);
    });
  }

  Future<void> _pay({required bool biometric}) async {
    if (!biometric) {
      final pin = _pinController.text.trim();
      if (pin.length != 6) {
        setState(() => _pinError = 'Enter your 6-digit PIN');
        return;
      }
    }
    setState(() {
      _processing = true;
      _processingBiometric = biometric;
      _pinError = null;
    });
    try {
      if (_mode == 1) {
        final res = await PaymentService.transferWithRetry(
          receiverEmail: _emailController.text.trim().toLowerCase(),
          amount: _amount,
          transactionPin: biometric ? null : _pinController.text.trim(),
          useBiometric: biometric ? true : null,
        );
        final newBalance = (res['newBalance'] as num?)?.toDouble();
        if (newBalance != null) {
          _walletBalance = newBalance;
          widget.onBalanceUpdate?.call(newBalance);
        }
        _closeReview();
        _showReceipt(
          type: 'Wallet Transfer',
          status: 'Successful',
          reference: (res['transactionId'] ?? '').toString(),
          recipient: _walletRecipientName ?? _emailController.text.trim(),
          description: 'Transfer to ${_emailController.text.trim()}',
        );
      } else {
        final ref = 'DPB_${DateTime.now().millisecondsSinceEpoch}';
        final res = await BankTransferService.send(
          accountNumber: _accountController.text.trim(),
          bankCode: _bank!.code,
          bankName: _bank!.name,
          accountName: _accountName!,
          amount: _amount,
          narration: _noteController.text,
          transactionPin: biometric ? null : _pinController.text.trim(),
          useBiometric: biometric,
          clientReference: ref,
        );
        if (res['success'] != true) {
          throw Exception(res['message'] ?? 'Transfer failed');
        }
        final newBalance = (res['newBalance'] as num?)?.toDouble();
        if (newBalance != null) {
          _walletBalance = newBalance;
          widget.onBalanceUpdate?.call(newBalance);
        }
        _closeReview();
        _showReceipt(
          type: 'Bank Transfer',
          status: (res['status'] ?? 'Pending').toString(),
          reference: (res['reference'] ?? ref).toString(),
          recipient: '$_accountName · ${_bank!.name}',
          description: '${_accountController.text.trim()} · ${_bank!.name}',
        );
      }
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '').replaceAll('Transfer failed: ', '');
      if (msg.toLowerCase().contains('pin')) {
        setState(() => _pinError = msg);
        _pinController.clear();
      } else {
        showDPDialog(context, tone: DPDialogTone.error, title: 'Transfer not sent', message: msg);
      }
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
          _processingBiometric = false;
        });
      }
    }
  }

  void _showReceipt({
    required String type,
    required String status,
    required String reference,
    required String recipient,
    required String description,
  }) {
    final amount = _total;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReceiptWidget(
        transactionType: type,
        amount: amount.toStringAsFixed(2),
        status: status,
        transactionId: reference,
        reference: reference,
        date: DateTime.now(),
        recipientName: recipient,
        description: description,
        primaryColor: DP.navy,
        customMessage: status.toLowerCase().contains('pend')
            ? 'Your bank transfer is on its way. Most arrive within minutes.'
            : null,
      ),
    ).then((_) {
      if (!mounted) return;
      setState(() {
        _amountController.clear();
        _noteController.clear();
        _accountController.clear();
        _emailController.clear();
        _accountName = null;
        _walletRecipientName = null;
      });
    });
  }

  void _pickBank() {
    if (_loadingBanks) return;
    if (_banks.isEmpty) {
      _loadBanks();
      return;
    }
    final search = TextEditingController();
    showDPSheet(
      context,
      title: 'Choose bank',
      scrollable: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final q = search.text.trim().toLowerCase();
          final list = q.isEmpty ? _banks : _banks.where((b) => b.name.toLowerCase().contains(q)).toList();
          return Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DPField(
                  controller: search,
                  hint: 'Search banks',
                  suffixIcon: DPIcons.search,
                  onChanged: (_) => setSheet(() {}),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (_, i) => DPOptionRow(
                      title: list[i].name,
                      selected: _bank?.code == list[i].code,
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _bank = list[i];
                          _accountName = null;
                          _resolveError = null;
                        });
                        _resolve();
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool get _canBiometric =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS) && _biometricEnabled;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        DPPage(
          title: 'Send money',
          bottom: DPButton(
            label: 'Review transfer',
            icon: DPIcons.arrowRight,
            onPressed: _loadingConfig ? null : _openReview,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 18),
              child: Text('For the people and things that matter.', style: DPText.bodyMuted),
            ),
            DPChipGrid(
              labels: const ['Bank account', 'Dalabapay wallet'],
              columns: 2,
              selectedIndex: _mode,
              onSelected: (i) => setState(() => _mode = i),
            ),
            if (_loadingConfig)
              const DPLoader()
            else if (_mode == 0)
              ..._bankForm()
            else
              ..._walletForm(),
            DPField(
              label: 'Amount',
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              prefixText: '₦ ',
              hint: '0',
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              onChanged: (_) => setState(() {}),
            ),
            DPField(
              label: 'Note (optional)',
              controller: _noteController,
              hint: 'For the weekend',
              suffixIcon: DPIcons.pencil,
              maxLength: 60,
            ),
            DPSummaryCard(rows: [
              DPSummaryRow('Wallet balance', dpNaira(_walletBalance)),
              DPSummaryRow('Transfer fee', dpNaira(_fee)),
              DPSummaryRow('Total to pay', dpNaira(_total), emphasize: true),
            ]),
            DPNotice(
              _mode == 0
                  ? 'Check the recipient’s name. Transfers to the wrong account may not be recoverable.'
                  : 'Wallet transfers are instant and can’t be reversed. Check the email address.',
              kind: DPNoticeKind.warn,
              margin: EdgeInsets.zero,
            ),
          ],
        ),
        if (_showSheet)
          DPSheetOverlay(
            animation: _sheet,
            onDismiss: _processing ? null : _closeReview,
            child: DPPaymentReview(
              icon: _mode == 0 ? DPIcons.landmark : DPIcons.wallet,
              serviceLabel: _mode == 0 ? 'Bank transfer' : 'Wallet transfer',
              amount: _amount,
              totalToPay: _total,
              rows: [
                if (_mode == 0) ...[
                  DPSummaryRow('Recipient', _accountName ?? ''),
                  DPSummaryRow('Bank', _bank?.name ?? ''),
                  DPSummaryRow('Account number', _accountController.text.trim()),
                ] else ...[
                  DPSummaryRow('Recipient', _walletRecipientName ?? _emailController.text.trim()),
                  DPSummaryRow('Email', _emailController.text.trim()),
                ],
                DPSummaryRow('Amount', dpNaira(_amount)),
                DPSummaryRow('Transfer fee', dpNaira(_fee)),
                DPSummaryRow('Total to pay', dpNaira(_total), emphasize: true),
              ],
              walletBalance: _walletBalance,
              showPin: _transactionPinSet,
              pinController: _pinController,
              pinError: _pinError,
              onPinChanged: (_) {
                if (_pinError != null) setState(() => _pinError = null);
              },
              processing: _processing,
              processingBiometric: _processingBiometric,
              onPayWithPin: () => _pay(biometric: false),
              onPayWithBiometric: _canBiometric ? () => _pay(biometric: true) : null,
              payLabel: 'Send ${dpNaira(_total)}',
              onClose: _closeReview,
              footnote: 'Check the details above. Sent transfers can’t be reversed.',
            ),
          ),
      ],
    );
  }

  List<Widget> _bankForm() {
    if (!_config.enabled) {
      return [
        DPNotice(
          _config.message ??
              'Sending to bank accounts is coming soon. You can send to any Dalabapay wallet right now.',
          title: 'Bank transfers aren’t available yet',
          kind: DPNoticeKind.info,
          action: GestureDetector(
            onTap: () => setState(() => _mode = 1),
            child: Text('Send to a Dalabapay wallet', style: DPText.link.copyWith(color: DP.blue)),
          ),
        ),
      ];
    }
    return [
      DPSelectField(
        label: 'Choose bank',
        value: _bank?.name,
        hint: 'Select bank',
        loading: _loadingBanks,
        onTap: _pickBank,
      ),
      DPField(
        label: 'Account number',
        controller: _accountController,
        keyboardType: TextInputType.number,
        hint: '0123456789',
        maxLength: 10,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        margin: EdgeInsets.only(bottom: _accountName != null || _resolving || _resolveError != null ? 10 : 18),
        suffix: _resolving
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : null,
        suffixIcon: DPIcons.scanLine,
        onChanged: (v) {
          setState(() {
            _accountName = null;
            _resolveError = null;
          });
          if (v.length == 10) _resolve();
        },
      ),
      if (_accountName != null) DPVerifiedName(name: _accountName!),
      if (_resolveError != null) DPNotice(_resolveError!, kind: DPNoticeKind.danger),
    ];
  }

  List<Widget> _walletForm() {
    return [
      DPField(
        label: 'Recipient’s email',
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        hint: 'name@email.com',
        suffixIcon: DPIcons.mail,
        margin: EdgeInsets.only(bottom: _walletRecipientName != null ? 10 : 18),
        helper: _lookingUpRecipient ? 'Looking up recipient…' : null,
        onChanged: (_) {
          if (_walletRecipientName != null) setState(() => _walletRecipientName = null);
        },
        onSubmitted: (_) => _lookupRecipient(),
      ),
      if (_walletRecipientName != null)
        DPVerifiedName(name: _walletRecipientName!, detail: 'Dalabapay wallet')
      else
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DPLinkButton(label: 'Check recipient', onPressed: _lookupRecipient),
          ),
        ),
    ];
  }
}
