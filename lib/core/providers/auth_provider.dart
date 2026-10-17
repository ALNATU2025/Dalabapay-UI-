// lib/core/providers/auth_provider.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  Map<String, dynamic>? _user;
  bool _isLoading = false;
  bool _isAuthenticated = false;

  Map<String, dynamic>? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;

  Future<Map<String, dynamic>> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await ApiService.loginUser(email: email, password: password);
      
      if (result['success'] == true) {
        _user = result['user'];
        _isAuthenticated = true;
        notifyListeners();
      }
      
      return result;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    String? referralCode,
    required String otp,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await ApiService.registerUserWithVirtualAccount(
        fullName: fullName,
        email: email,
        phone: phone,
        password: password,
        referralCode: referralCode,
        otp: otp,
      );
      
      if (result['success'] == true) {
        _user = result['user'];
        _isAuthenticated = true;
        notifyListeners();
      }
      
      return result;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      await ApiService.logoutUser();
      _user = null;
      _isAuthenticated = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshUser() async {
    try {
      final userData = await ApiService.getCurrentUser(forceRefresh: true);
      _user = userData;
      _isAuthenticated = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error refreshing user: $e');
    }
  }
}