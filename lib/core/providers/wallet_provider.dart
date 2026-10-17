// lib/core/providers/wallet_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class WalletProvider extends ChangeNotifier {
  double _walletBalance = 0.0;
  double _commissionBalance = 0.0;
  List<Map<String, dynamic>> _recentTransactions = [];
  bool _isLoading = false;
  String? _userId;

  double get walletBalance => _walletBalance;
  double get commissionBalance => _commissionBalance;
  List<Map<String, dynamic>> get recentTransactions => _recentTransactions;
  bool get isLoading => _isLoading;
  String? get userId => _userId;

  Future<void> loadBalances() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _userId = prefs.getString('userId');

      _walletBalance = await ApiService.getBalance();
      _commissionBalance = await ApiService.getCommissionBalance();
    } catch (e) {
      debugPrint('Error loading balances: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadTransactions({int limit = 10}) async {
    try {
      final transactions = await ApiService.getTransactions();
      _recentTransactions =
          transactions.take(limit).cast<Map<String, dynamic>>().toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading transactions: $e');
    }
  }

  Future<void> refresh() async {
    await Future.wait([loadBalances(), loadTransactions()]);
  }

  void updateWalletBalance(double newBalance) {
    _walletBalance = newBalance;
    notifyListeners();
  }

  void updateCommissionBalance(double newBalance) {
    _commissionBalance = newBalance;
    notifyListeners();
  }
}
