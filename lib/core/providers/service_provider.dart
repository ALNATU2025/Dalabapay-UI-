// lib/core/providers/service_provider.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ServiceProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = false;
  String? _selectedService;

  List<Map<String, dynamic>> get services => _services;
  List<Map<String, dynamic>> get transactions => _transactions;
  bool get isLoading => _isLoading;
  String? get selectedService => _selectedService;

  ServiceProvider() {
    loadServices();
  }

  void loadServices() {
    _services = [
      {'id': 'airtime', 'name': 'Airtime', 'icon': '📱', 'route': '/airtime'},
      {'id': 'data', 'name': 'Data', 'icon': '📊', 'route': '/data'},
      {
        'id': 'electricity',
        'name': 'Electricity',
        'icon': '💡',
        'route': '/electricity',
      },
      {'id': 'cable', 'name': 'Cable TV', 'icon': '📺', 'route': '/cable'},
      {
        'id': 'education',
        'name': 'Education',
        'icon': '🎓',
        'route': '/education',
      },
      {
        'id': 'insurance',
        'name': 'Insurance',
        'icon': '🛡️',
        'route': '/insurance',
      },
      {
        'id': 'commission',
        'name': 'Commission',
        'icon': '💰',
        'route': '/commission',
      },
      {
        'id': 'referral',
        'name': 'Referral',
        'icon': '👥',
        'route': '/referral',
      },
    ];
    notifyListeners();
  }

  Future<void> loadTransactions() async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await ApiService.getTransactions();
      _transactions = result.cast<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('Error loading transactions: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectService(String serviceId) {
    _selectedService = serviceId;
    notifyListeners();
  }
}
