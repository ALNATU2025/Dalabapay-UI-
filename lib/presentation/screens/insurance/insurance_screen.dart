// lib/presentation/screens/insurance/insurance_screen.dart

import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

import '../../../core/services/api_service.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/widgets/receipt_widget.dart';
import '../../../core/widgets/request_limit_increase_dialog.dart';
import '../../../ui/ui.dart';

class InsuranceScreen extends StatefulWidget {
  final void Function(double newBalance) onBalanceUpdate;
  final String userId;

  const InsuranceScreen({
    super.key,
    required this.onBalanceUpdate,
    required this.userId,
  });

  @override
  State<InsuranceScreen> createState() => _InsuranceScreenState();
}

class _InsuranceScreenState extends State<InsuranceScreen>
    with TickerProviderStateMixin {
  // Controllers
  final TextEditingController _plateController = TextEditingController();
  final TextEditingController _chasisController = TextEditingController();
  final TextEditingController _insuredNameController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  // Focus Nodes
  final FocusNode _plateFocusNode = FocusNode();
  final FocusNode _chasisFocusNode = FocusNode();
  final FocusNode _insuredNameFocusNode = FocusNode();
  final FocusNode _yearFocusNode = FocusNode();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _pinFocusNode = FocusNode();

  // State Variables
  String? _selectedInsuranceType;
  String? _selectedPlan;
  String? _selectedVehicleMake;
  String? _selectedVehicleModel;
  String? _selectedVehicleColor;
  String? _selectedEngineCapacity;
  String? _selectedState;
  String? _selectedLGA;
  bool _isLoading = false;
  bool _isLoadingData = true;
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
  final bool _insuranceServiceEnabled = true;
  bool _isUserActive = true;

  // Animation
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController _sheetController;
  late Animation<double> _sheetAnimation;

  // Shake Animation for Wrong PIN
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  // Insurance Types
  final List<Map<String, dynamic>> _insuranceTypes = [
    {
      'name': 'Private',
      'code': 'private',
      'icon': HugeIcons.strokeRoundedUser,
      'amount': 3000,
      'color': const Color(0xFF4CAF50),
    },
    {
      'name': 'Commercial',
      'code': 'commercial',
      'icon': HugeIcons.strokeRoundedDeliveryTruck01,
      'amount': 5000,
      'color': const Color(0xFF2196F3),
    },
    {
      'name': 'Tricycle',
      'code': 'tricycle',
      'icon': HugeIcons.strokeRoundedMotorbike02,
      'amount': 1500,
      'color': const Color(0xFFFF9800),
    },
    {
      'name': 'Motorcycle',
      'code': 'motorcycle',
      'icon': HugeIcons.strokeRoundedCar05,
      'amount': 3000,
      'color': const Color(0xFF9C27B0),
    },
  ];

  // API Data
  List<dynamic> _vehicleMakes = [];
  List<dynamic> _vehicleModels = [];
  List<dynamic> _vehicleColors = [];
  List<dynamic> _engineCapacities = [];
  List<dynamic> _states = [];
  List<dynamic> _lgas = [];

  // Payment Sheet State
  bool _showPaymentSheet = false;
  bool _isProcessingPayment = false;

  // Complete Nigeria States and LGAs mapping (Fallback)
  final Map<String, List<String>> _statesLGAs = {
    'Abia': ['Aba North', 'Aba South', 'Arochukwu', 'Bende', 'Ikwuano'],
    'Adamawa': ['Demsa', 'Fufore', 'Ganaye', 'Gireri', 'Gombi'],
    'Akwa Ibom': ['Abak', 'Eastern Obolo', 'Eket', 'Esit Eket', 'Essien Udim'],
    'Anambra': [
      'Aguata',
      'Anambra East',
      'Anambra West',
      'Anaocha',
      'Awka North',
    ],
    'Bauchi': ['Alkaleri', 'Bauchi', 'Bogoro', 'Damban', 'Darazo'],
    'Bayelsa': ['Brass', 'Ekeremor', 'Kolokuma/Opokuma', 'Nembe', 'Ogbia'],
    'Benue': ['Ado', 'Agatu', 'Apa', 'Buruku', 'Gboko'],
    'Borno': ['Abadam', 'Askira/Uba', 'Bama', 'Bayo', 'Biu'],
    'Cross River': ['Akpabuyo', 'Odukpani', 'Akamkpa', 'Biase', 'Abi'],
    'Delta': [
      'Oshimili',
      'Aniocha',
      'Aniocha South',
      'Ika South',
      'Ika North-East',
    ],
    'Ebonyi': ['Edda', 'Afikpo', 'Onicha', 'Ohaozara', 'Abakaliki'],
    'Edo': ['Esan North-East', 'Esan Central', 'Esan West', 'Egor', 'Ukpoba'],
    'Ekiti': [
      'Ado',
      'Ekiti-East',
      'Ekiti-West',
      'Emure/Ise/Orun',
      'Ekiti South-West',
    ],
    'Enugu': [
      'Enugu South',
      'Igbo-Eze South',
      'Enugu North',
      'Nkanu',
      'Udi Agwu',
    ],
    'FCT': ['Abaji', 'Abuja Municipal', 'Bwari', 'Gwagwalada', 'Kuje', 'Kwali'],
    'Gombe': ['Akko', 'Balanga', 'Billiri', 'Dukku', 'Kaltungo'],
    'Imo': [
      'Aboh-Mbaise',
      'Ahiazu-Mbaise',
      'Ehime-Mbano',
      'Ezinihitte',
      'Ideato North',
    ],
    'Jigawa': ['Auyo', 'Babura', 'Birni Kudu', 'Biriniwa', 'Buji'],
    'Kaduna': ['Birni-Gwari', 'Chikun', 'Giwa', 'Igabi', 'Ikara'],
    'Kano': ['Ajingi', 'Albasu', 'Bagwai', 'Bebeji', 'Bichi'],
    'Katsina': ['Bakori', 'Batagarawa', 'Batsari', 'Baure', 'Bindawa'],
    'Kebbi': ['Aleiro', 'Arewa-Dandi', 'Argungu', 'Augie', 'Bagudo'],
    'Kogi': ['Adavi', 'Ajaokuta', 'Ankpa', 'Bassa', 'Dekina'],
    'Kwara': ['Asa', 'Baruten', 'Edu', 'Ekiti', 'Ifelodun'],
    'Lagos': ['Agege', 'Ajeromi-Ifelodun', 'Alimosho', 'Amuwo-Odofin', 'Apapa'],
    'Nasarawa': ['Akwanga', 'Awe', 'Doma', 'Karu', 'Keana'],
    'Niger': ['Agaie', 'Agwara', 'Bida', 'Borgu', 'Bosso'],
    'Ogun': [
      'Abeokuta North',
      'Abeokuta South',
      'Ado-Odo/Ota',
      'Yewa North',
      'Yewa South',
    ],
    'Ondo': [
      'Akoko North East',
      'Akoko North West',
      'Akoko South Akure East',
      'Akoko South West',
      'Akure North',
    ],
    'Osun': [
      'Aiyedade',
      'Aiyedire',
      'Atakumosa East',
      'Atakumosa West',
      'Boluwaduro',
    ],
    'Oyo': ['Afijio', 'Akinyele', 'Atiba', 'Atisbo', 'Egbeda'],
    'Plateau': ['Barikin Ladi', 'Bassa', 'Bokkos', 'Jos East', 'Jos North'],
    'Rivers': [
      'Abua/Odual',
      'Ahoada East',
      'Ahoada West',
      'Akuku Toru',
      'Andoni',
    ],
    'Sokoto': ['Binji', 'Bodinga', 'Dange-shnsi', 'Gada', 'Goronyo'],
    'Taraba': ['Ardo-kola', 'Bali', 'Donga', 'Gashaka', 'Cassol'],
    'Yobe': ['Bade', 'Bursari', 'Damaturu', 'Fika', 'Fune'],
    'Zamfara': ['Anka', 'Bakura', 'Birnin Magaji', 'Bukkuyum', 'Bungudu'],
  };

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeData();
    _fetchSecuritySettings();
    _loadWalletBalance();
    _loadInsuranceData();
    _checkBiometricSupport();
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _fadeController.forward();

    _sheetController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _sheetAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _sheetController, curve: Curves.easeOutCubic),
    );

    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: 0.0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _sheetController.dispose();
    _shakeController.dispose();
    _plateController.dispose();
    _chasisController.dispose();
    _insuredNameController.dispose();
    _yearController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    _plateFocusNode.dispose();
    _chasisFocusNode.dispose();
    _insuredNameFocusNode.dispose();
    _yearFocusNode.dispose();
    _emailFocusNode.dispose();
    _phoneFocusNode.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('🛡️ INSURANCE: $message');
    }
  }

  void _showPinErrorSnackBar({
    required String message,
    int? attemptsRemaining,
  }) {
    if (!mounted) return;
    final displayMsg = attemptsRemaining != null
        ? '$message ($attemptsRemaining ${attemptsRemaining == 1 ? 'attempt' : 'attempts'} remaining)'
        : message;
    dpSnack(context, displayMsg, error: true);
  }

  Future<void> _checkBiometricSupport() async {
    if (kIsWeb) return;
    try {
      final isAvailable = await biometricService.isBiometricAvailable();
      final isEnabled = await biometricService.getBiometricEnabledStatus(
        userId: widget.userId,
      );

      if (isAvailable) {
        final name = await biometricService.getBiometricName();
        if (mounted) {
          setState(() {
            _biometricName = name;
            _biometricEnabled = isEnabled;
          });
        }
      }
    } catch (e) {
      debugPrint('Biometric check error: $e');
    }
  }

  Future<void> _initializeData() async {
    try {
      final user = await ApiService.getCurrentUser();
      if (mounted) {
        setState(() {
          _isUserActive = user['isActive'] ?? true;
          _insuredNameController.text = user['fullName'] ?? '';
          _emailController.text = user['email'] ?? '';
          _phoneController.text = user['phone'] ?? '';
          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingData = false);
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
      final isEnabled =
          kIsWeb
              ? false
              : await biometricService.getBiometricEnabledStatus(
                userId: widget.userId,
              );

      final userString = prefs.getString('user');
      bool pinSet = prefs.getBool('transactionPinSet') ?? false;

      if (userString != null) {
        final user = jsonDecode(userString);
        pinSet =
            pinSet ||
            (user['transactionPinSet'] ?? false) ||
            (user['hasTransactionPin'] ?? false) ||
            (user['pinSet'] ?? false) ||
            (user['transactionPin'] != null &&
                user['transactionPin'].toString().isNotEmpty &&
                user['transactionPin'].toString() != 'null');
      }

      if (mounted) {
        setState(() {
          _transactionPinSet = pinSet;
          _biometricEnabled = isEnabled;
        });
      }

      final globalSettings = await ApiService.getGlobalSecuritySettings();
      if (mounted) {
        setState(() {
          _pinRequired = globalSettings['pinRequired'] ?? true;
          _biometricAllowed = globalSettings['biometricAllowed'] ?? true;
        });
      }

      final securitySettings = await ApiService.getSecuritySettings();
      if (mounted && securitySettings['securitySettings'] != null) {
        setState(() {
          _pinLocked =
              securitySettings['securitySettings']['pinLocked'] ?? false;
          _lockTimeRemaining =
              securitySettings['securitySettings']['lockTimeRemaining'] ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error fetching security settings: $e');
    }
  }

  Future<void> _loadInsuranceData() async {
    try {
      await Future.wait([
        _loadVehicleMakes(),
        _loadVehicleColors(),
        _loadEngineCapacities(),
        _loadStates(),
      ]);
    } catch (e) {
      debugPrint('Error loading insurance data: $e');
      _loadFallbackData();
    }
  }

  Future<void> _loadVehicleMakes() async {
    try {
      final makes = await ApiService.getVehicleMakes();
      setState(() => _vehicleMakes = makes);
    } catch (e) {
      debugPrint('Error loading vehicle makes: $e');
      setState(() {
        _vehicleMakes = [
          {'id': '1', 'name': 'Toyota'},
          {'id': '2', 'name': 'Honda'},
          {'id': '3', 'name': 'Ford'},
          {'id': '4', 'name': 'BMW'},
          {'id': '5', 'name': 'Mercedes'},
          {'id': '6', 'name': 'Audi'},
          {'id': '7', 'name': 'Nissan'},
          {'id': '8', 'name': 'Hyundai'},
          {'id': '9', 'name': 'Kia'},
          {'id': '10', 'name': 'Chevrolet'},
          {'id': '11', 'name': 'Lexus'},
          {'id': '12', 'name': 'Mazda'},
          {'id': '13', 'name': 'Subaru'},
          {'id': '14', 'name': 'Volkswagen'},
          {'id': '15', 'name': 'Jeep'},
          {'id': '16', 'name': 'Land Rover'},
          {'id': '17', 'name': 'Volvo'},
        ];
      });
    }
  }

  Future<void> _loadVehicleModels(String makeName) async {
    try {
      final models = await ApiService.getVehicleModels(makeName);
      setState(() => _vehicleModels = models);
    } catch (e) {
      debugPrint('Error loading vehicle models: $e');
      setState(() {
        _vehicleModels = [
          {'code': 'corolla', 'name': 'Corolla'},
          {'code': 'camry', 'name': 'Camry'},
          {'code': 'civic', 'name': 'Civic'},
          {'code': 'accord', 'name': 'Accord'},
          {'code': 'f150', 'name': 'F-150'},
          {'code': 'mustang', 'name': 'Mustang'},
          {'code': '3series', 'name': '3 Series'},
          {'code': '5series', 'name': '5 Series'},
          {'code': 'cclass', 'name': 'C-Class'},
          {'code': 'eclass', 'name': 'E-Class'},
          {'code': 'a4', 'name': 'A4'},
          {'code': 'q5', 'name': 'Q5'},
        ];
      });
    }
  }

  Future<void> _loadVehicleColors() async {
    try {
      final colors = await ApiService.getVehicleColors();
      setState(() => _vehicleColors = colors);
    } catch (e) {
      debugPrint('Error loading vehicle colors: $e');
      setState(() {
        _vehicleColors = [
          {'code': '20', 'name': 'Ash'},
          {'code': '1004', 'name': 'Black'},
          {'code': '1005', 'name': 'White'},
          {'code': '1006', 'name': 'Red'},
          {'code': '1007', 'name': 'Blue'},
          {'code': '1008', 'name': 'Silver'},
          {'code': '1009', 'name': 'Gold'},
          {'code': '1010', 'name': 'Green'},
          {'code': '1011', 'name': 'Yellow'},
          {'code': '1012', 'name': 'Brown'},
          {'code': '1013', 'name': 'Grey'},
          {'code': '1014', 'name': 'Maroon'},
          {'code': '1015', 'name': 'Navy'},
          {'code': '1016', 'name': 'Purple'},
          {'code': '1017', 'name': 'Orange'},
        ];
      });
    }
  }

  Future<void> _loadEngineCapacities() async {
    try {
      final capacities = await ApiService.getEngineCapacities();
      setState(() => _engineCapacities = capacities);
    } catch (e) {
      debugPrint('Error loading engine capacities: $e');
      setState(() {
        _engineCapacities = [
          {'code': '1', 'value': '0.1 - 1.59'},
          {'code': '2', 'value': '1.6 - 2.0'},
          {'code': '3', 'value': '2.1 - 3.0'},
          {'code': '4', 'value': '3.1 - 4.0'},
          {'code': '5', 'value': '4.1 - 5.0'},
          {'code': '6', 'value': '5.1 - 6.0'},
        ];
      });
    }
  }

  Future<void> _loadStates() async {
    try {
      _log('📍 Loading states...');
      final states = await ApiService.getStates();
      _log('📦 States response: $states');

      setState(() {
        _states = states;

        // Auto-select first state and load its LGAs
        if (_states.isNotEmpty && _states[0] is Map) {
          final firstState = _states[0] as Map;
          final stateCode = firstState['code']?.toString();
          if (stateCode != null && stateCode.isNotEmpty) {
            _selectedState = stateCode;
            _log(
              '✅ Auto-selected state: ${firstState['name']} (code: $stateCode)',
            );
            // Load LGAs for this state
            _loadLGAs(stateCode);
          }
        }
      });
    } catch (e) {
      _log('❌ Error loading states: $e');
      _loadFallbackStates();
    }
  }

  // The state list could not be loaded. Made-up codes would be rejected by
  // the insurer, so we show a reload option instead.
  void _loadFallbackStates() {
    if (!mounted) return;
    setState(() => _states = []);
  }

  void _loadFallbackData() {
    if (!mounted) return;
    setState(() {});
  }

  DPIconData _typeIcon(String code) {
    switch (code) {
      case 'commercial':
        return DPIcons.package;
      case 'tricycle':
      case 'motorcycle':
        return DPIcons.mapPin;
      default:
        return DPIcons.shieldCheck;
    }
  }

  Future<void> _loadLGAs(String stateCode) async {
    try {
      _log('📍 Loading LGAs for state code: $stateCode');

      final lgas = await ApiService.getLGAs(stateCode);

      _log('📦 Raw LGAs response: $lgas');

      // ✅ Process the response properly
      List<Map<String, dynamic>> processedLgas = [];

      for (var item in lgas) {
        if (item is Map) {
          final code = item['code']?.toString() ?? '';
          final name = item['name']?.toString() ?? '';

          _log('   📍 Processing: code=$code, name=$name');

          if (code.isNotEmpty &&
              name.isNotEmpty &&
              name != '[object Object]') {
            processedLgas.add({
              'code': code,
              'name': name,
              'stateCode': item['stateCode']?.toString() ?? stateCode,
            });
          }
        }
      }
    
      _log('✅ Processed ${processedLgas.length} LGAs');

      setState(() {
        _lgas = processedLgas;

        if (_lgas.isNotEmpty) {
          final firstLGA = _lgas[0];
          final lgaCode = firstLGA['code']?.toString();
          if (lgaCode != null && lgaCode.isNotEmpty) {
            _selectedLGA = lgaCode;
            _log('✅ Auto-selected LGA: ${firstLGA['name']} (code: $lgaCode)');
          }
        }
      });
    } catch (e) {
      _log('❌ Error loading LGAs: $e');
      // Fallback logic...
    }
  }

  String? _validateForm() {
    if (_selectedInsuranceType == null) {
      return 'Please select an insurance type';
    }

    if (_selectedPlan == null) {
      return 'Please select a plan';
    }

    if (_plateController.text.trim().isEmpty) {
      return 'Please enter plate number';
    }

    if (_chasisController.text.trim().isEmpty) {
      return 'Please enter chasis number';
    }

    if (_insuredNameController.text.trim().isEmpty) {
      return 'Please enter insured name';
    }

    if (_yearController.text.trim().isEmpty) {
      return 'Please enter year of make';
    }
    if (_yearController.text.trim().length != 4) {
      return 'Please enter a valid year';
    }

    if (_selectedVehicleMake == null) {
      return 'Please select vehicle make';
    }

    if (_selectedVehicleModel == null) {
      return 'Please select vehicle model';
    }

    if (_selectedVehicleColor == null) {
      return 'Please select vehicle color';
    }

    if (_selectedEngineCapacity == null) {
      return 'Please select engine capacity';
    }

    if (_selectedState == null) {
      return 'Please select state';
    }

    if (_selectedLGA == null) {
      return 'Please select LGA';
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
      if (mounted) {
        setState(() {
          _showPaymentSheet = false;
          _isProcessingPayment = false;
          _pinValidationError = null;
        });
      }
    });
  }

  // ==================== PROCESS PAYMENT ====================

  Future<void> _processPaymentWithPIN() async {
    HapticFeedback.mediumImpact();

    if (!_transactionPinSet) {
      _showErrorDialog(
        'PIN Required',
        'Please set up a transaction PIN in Settings.',
      );
      return;
    }

    if (_pinLocked && _lockTimeRemaining > 0) {
      _showErrorDialog(
        'PIN Locked',
        'Your PIN is locked due to too many failed attempts. Try again in $_lockTimeRemaining minutes.',
      );
      return;
    }

    if (!_pinRequired) {
      await _executePurchase();
      return;
    }

    final pin = _pinController.text.trim();
    if (pin.isEmpty || pin.length < 4 || pin.length > 6) {
      setState(() {
        _pinValidationError = 'Please enter a valid 4-6 digit PIN';
      });
      _shakeController.forward(from: 0.0);
      return;
    }

    setState(() {
      _pinValidationError = null;
      _isProcessingPayment = true;
    });

    // ✅ STEP 1: PRE-VERIFY PIN BEFORE TRANSACTION (Like Airtime)
    try {
      final verifyResult = await ApiService.verifyTransactionPin(
        userId: widget.userId,
        transactionPin: pin,
      );

      if (verifyResult['success'] != true) {
        final message = verifyResult['message'] ?? 'Incorrect transaction PIN';
        final attemptsRemaining = verifyResult['attemptsRemaining'];

        setState(() {
          _isProcessingPayment = false;
          _pinValidationError =
              attemptsRemaining != null
                  ? '$message ($attemptsRemaining ${attemptsRemaining == 1 ? 'attempt' : 'attempts'} left)'
                  : message;
        });

        _pinController.clear();
        _shakeController.forward(from: 0.0);
        _showPinErrorSnackBar(
          message: message,
          attemptsRemaining: attemptsRemaining,
        );
        return;
      }
    } catch (e) {
      setState(() => _isProcessingPayment = false);
      _showErrorDialog('PIN Verification Error', _mapExceptionToUserMessage(e));
      return;
    }

    // ✅ STEP 2: PIN VERIFIED SUCCESSFULLY -> EXECUTE
    await _executePurchase(pin: pin);
  }

  Future<void> _processPaymentWithBiometric() async {
    HapticFeedback.mediumImpact();

    setState(() {
      _isProcessingPayment = true;
      _isAuthenticating = true;
      _pinValidationError = null;
      _useBiometric = true;
    });

    try {
      final isAvailable = await biometricService.isBiometricAvailable();
      if (!isAvailable) {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
        _showErrorDialog(
          'Biometric Not Available',
          'Biometric authentication is not available on this device.',
        );
        return;
      }

      final isEnabled = await biometricService.getBiometricEnabledStatus(
        userId: widget.userId,
      );
      if (!isEnabled) {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
        _showErrorDialog(
          'Biometric Not Enabled',
          'Biometric authentication is not enabled. Please enable it in Settings.',
        );
        return;
      }

      final bool biometricSuccess = await biometricService.authenticate(
        reason: 'Authenticate to purchase Insurance',
        biometricOnly: false,
        stickyAuth: true,
      );

      if (!biometricSuccess) {
        setState(() {
          _isProcessingPayment = false;
          _isAuthenticating = false;
        });
        _showErrorDialog(
          'Authentication Cancelled',
          'Biometric authentication was cancelled.',
        );
        return;
      }

      await _executePurchase(useBiometric: true);
    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
        _isAuthenticating = false;
      });
      _showErrorDialog('Authentication Error', _mapExceptionToUserMessage(e));
    }
  }

  // ==================== EXECUTE PURCHASE ====================

  Future<void> _executePurchase({
    String? pin,
    bool useBiometric = false,
  }) async {
    try {
      setState(() {
        _isLoading = true;
        _isAuthenticating = true;
      });

      final selectedType = _insuranceTypes.firstWhere(
        (t) => t['code'] == _selectedInsuranceType,
      );
      final amount = (selectedType['amount'] ?? 0).toDouble();

      // Get current balance
      final currentBalance = await ApiService.getBalance();

      // Check if user has enough balance
      if (currentBalance < amount) {
        setState(() {
          _isProcessingPayment = false;
          _isLoading = false;
          _isAuthenticating = false;
        });
        _showErrorDialog(
          'Insufficient Balance',
          'Your wallet balance (₦${currentBalance.toStringAsFixed(2)}) is insufficient.\n\n'
              'Insurance cost: ₦${amount.toStringAsFixed(2)}\n'
              'Please fund your wallet and try again.',
        );
        _closePaymentSheet();
        return;
      }

      // Make API call to purchase insurance
      final result = await ApiService.purchaseInsurance(
        userId: widget.userId,
        phone: _phoneController.text.trim(),
        insuredName: _insuredNameController.text.trim(),
        engineCapacity: _selectedEngineCapacity!,
        chasisNumber: _chasisController.text.trim(),
        plateNumber: _plateController.text.trim().toUpperCase(),
        vehicleMake: _getMakeName(),
        vehicleModel: _getModelName(),
        vehicleColor: _getColorName(),
        yearOfMake: _yearController.text.trim(),
        state: _getStateName(),
        lga: _getLGAName(),
        email: _emailController.text.trim(),
        variationCode: selectedType['code'] ?? 'private',
        transactionPin: useBiometric ? null : pin,
        useBiometric: useBiometric,
      );

      if (result['success'] == true) {
        final newBalance = result['newBalance'] ?? currentBalance - amount;

        widget.onBalanceUpdate(newBalance);
        setState(() {
          _walletBalance = newBalance;
        });

        // Store the new balance
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('walletBalance', newBalance);

        _closePaymentSheet();
        _showSuccessDialog(selectedType['name'], amount, result);
        _clearForm();
      } else {
        setState(() {
          _isProcessingPayment = false;
        });

        // ✅ CHECK FOR LIMIT ERRORS
        // ✅ CHECK FOR LIMIT ERRORS
        final errorCode = result['code']?.toString() ?? '';
        final errorMsg = result['message'] ?? '';

        // Robust detection: code OR message patterns
        final isLimitError =
            errorCode == 'PER_TRANSACTION_LIMIT_EXCEEDED' ||
            errorCode == 'DAILY_LIMIT_EXCEEDED' ||
            errorMsg.contains('PER_TRANSACTION_LIMIT_EXCEEDED') ||
            errorMsg.contains('DAILY_LIMIT_EXCEEDED') ||
            errorMsg.contains('per transaction is') ||
            errorMsg.contains('limit of') ||
            errorMsg.contains('Maximum insurance');

        if (isLimitError) {
          // Extract limit info from error
          final limitValue = result['limit'] ?? 0;
          final requestedValue = result['requested'] ?? amount;

          double limit = 0.0;
          if (limitValue is double) {
            limit = limitValue;
          } else if (limitValue is int) {
            limit = limitValue.toDouble();
          } else if (limitValue is num) {
            limit = limitValue.toDouble();
          } else if (limitValue is String) {
            limit = double.tryParse(limitValue) ?? 0.0;
          }

          double requested = 0.0;
          if (requestedValue is double) {
            requested = requestedValue;
          } else if (requestedValue is int) {
            requested = requestedValue.toDouble();
          } else if (requestedValue is num) {
            requested = requestedValue.toDouble();
          } else if (requestedValue is String) {
            requested = double.tryParse(requestedValue) ?? amount;
          } else {
            requested = amount;
          }

          final isDaily =
              errorMsg.contains('DAILY_LIMIT_EXCEEDED') ||
              errorCode == 'DAILY_LIMIT_EXCEEDED';
          final service = 'insurance';

          _showLimitIncreaseDialog(
            service: service,
            limitType: isDaily ? 'dailyCap' : 'perTransaction',
            currentLimit: limit,
            requestedAmount: requested,
          );
          return;
        }

        _showErrorDialog(
          'Purchase Failed',
          result['message'] ?? 'Transaction failed. Please try again.',
        );
      }
    } catch (e) {
      setState(() {
        _isProcessingPayment = false;
      });
      _showErrorDialog('Purchase Failed', _mapExceptionToUserMessage(e));
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

  String _getMakeName() {
    if (_selectedVehicleMake == null) return 'Unknown Make';
    final make = _vehicleMakes.firstWhere(
      (m) => (m['id'] ?? m['code'] ?? '').toString() == _selectedVehicleMake,
      orElse: () => {'name': 'Unknown Make'},
    );
    return make['name']?.toString() ?? 'Unknown Make';
  }

  String _getModelName() {
    if (_selectedVehicleModel == null) return 'Unknown Model';
    final model = _vehicleModels.firstWhere(
      (m) => (m['code'] ?? m['id'] ?? '').toString() == _selectedVehicleModel,
      orElse: () => {'name': 'Unknown Model'},
    );
    return model['name']?.toString() ?? 'Unknown Model';
  }

  String _getColorName() {
    if (_selectedVehicleColor == null) return 'Unknown';
    final color = _vehicleColors.firstWhere(
      (c) => (c['code'] ?? '').toString() == _selectedVehicleColor,
      orElse: () => {'name': 'Unknown'},
    );
    return color['name']?.toString() ?? 'Unknown';
  }

  String _getStateName() {
    if (_selectedState == null) return 'Unknown State';
    final state = _states.firstWhere(
      (s) => (s['code'] ?? '').toString() == _selectedState,
      orElse: () => {'name': 'Unknown State'},
    );
    return state['name']?.toString() ?? 'Unknown State';
  }

  String _getLGAName() {
    if (_selectedLGA == null) return 'Unknown LGA';
    final lga = _lgas.firstWhere(
      (l) => (l['code'] ?? '').toString() == _selectedLGA,
      orElse: () => {'name': 'Unknown LGA'},
    );
    return lga['name']?.toString() ?? 'Unknown LGA';
  }

  // ==================== LIMIT INCREASE DIALOG ====================
  void _showLimitIncreaseDialog({
    required String service,
    required String limitType,
    required double currentLimit,
    required double requestedAmount,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (context) => RequestLimitIncreaseDialog(
            service: service,
            limitType: limitType,
            currentLimit: currentLimit,
            requestedAmount: requestedAmount,
          ),
    );
  }

  void _showSuccessDialog(
    String plan,
    double amount,
    Map<String, dynamic> result,
  ) {
    final transactionId =
        result['transactionId'] ??
        'TXN_${DateTime.now().millisecondsSinceEpoch}';
    final reference = result['requestId'] ?? transactionId;
    final certificateUrl =
        result['certificateUrl'] ?? result['certUrl']; // ✅ GET CERTIFICATE URL

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ReceiptWidget(
              transactionType: 'Insurance',
              amount: amount.toStringAsFixed(2),
              status: 'completed',
              transactionId: transactionId,
              reference: reference.toString(),
              date: DateTime.now(),
              phoneNumber: _phoneController.text.trim(),
              description: '$plan Insurance - ${_plateController.text.trim()}',
              customMessage: '✓ Insurance policy activated successfully!',
              primaryColor: const Color(0xFF102C68),
              showWatermark: true,
              isAdminTransaction: false,
              isUserAdmin: false,
              certificateUrl: certificateUrl, // ✅ PASS CERTIFICATE URL
              customerName: _insuredNameController.text.trim(),
              packageVariationCode: plan,
              balanceAfter: result['newBalance']?.toString(),
            ),
          ),
    );
    _clearForm();
  }

  void _showErrorDialog(String title, String message) {
    showDPDialog(context, tone: DPDialogTone.error, title: title, message: message);
  }

  void _clearForm() {
    _plateController.clear();
    _chasisController.clear();
    _yearController.clear();
    _pinController.clear();
    setState(() {
      _selectedInsuranceType = null;
      _selectedPlan = null;
      _selectedVehicleMake = null;
      _selectedVehicleModel = null;
      _selectedVehicleColor = null;
      _selectedEngineCapacity = null;
      _selectedState = null;
      _selectedLGA = null;
      _useBiometric = false;
      _pinValidationError = null;
    });
  }

  // ==================== UI BUILDERS ====================

  Widget _buildInsuranceTypeCard(Map<String, dynamic> type, bool isSelected) {
    final amount = (type['amount'] ?? 0).toDouble();
    return DPOptionRow(
      leading: DPIconBadge(icon: _typeIcon(type['code'].toString()), size: 38, radius: 12),
      title: '${type['name']} vehicle',
      subtitle: 'Third-party motor insurance · 1 year',
      trailingText: dpNaira(amount, decimals: false),
      selected: isSelected,
      onTap: () => setState(() {
        _selectedInsuranceType = type['code'];
        _selectedPlan = type['name'];
      }),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<dynamic> items,
    required String displayKey,
    required String valueKey,
    required Function(String?) onChanged,
    required dynamic icon,
  }) {
    final seenValues = <String>{};
    final uniqueItems = <Map<String, dynamic>>[];
    for (var item in items) {
      if (item is! Map) continue;
      String? itemValue;
      if (item[valueKey] != null) {
        itemValue = item[valueKey].toString();
      } else if (item['code'] != null) {
        itemValue = item['code'].toString();
      } else if (item['id'] != null) {
        itemValue = item['id'].toString();
      }
      if (itemValue != null && !seenValues.contains(itemValue)) {
        seenValues.add(itemValue);
        String displayValue = 'Unknown';
        if (item[displayKey] != null) {
          displayValue = item[displayKey].toString();
        } else if (item['name'] != null) {
          displayValue = item['name'].toString();
        } else if (item['value'] != null) {
          displayValue = item['value'].toString();
        }
        uniqueItems.add({'_v': itemValue, '_d': displayValue});
      }
    }
    String? display;
    for (final i in uniqueItems) {
      if (i['_v'] == value) display = i['_d'];
    }
    return DPSelectField(
      label: label,
      value: display,
      hint: uniqueItems.isEmpty ? 'Not available' : 'Select',
      onTap: uniqueItems.isEmpty
          ? null
          : () {
              var query = '';
              showDPSheet(
                context,
                title: label,
                scrollable: false,
                builder: (ctx) => StatefulBuilder(
                  builder: (ctx, setSheet) {
                    final shown = query.isEmpty
                        ? uniqueItems
                        : uniqueItems
                            .where((i) => i['_d'].toString().toLowerCase().contains(query))
                            .toList();
                    return Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (uniqueItems.length > 8)
                            DPField(
                              hint: 'Search',
                              suffixIcon: DPIcons.search,
                              onChanged: (q) => setSheet(() => query = q.trim().toLowerCase()),
                            ),
                          Flexible(
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: shown.length,
                              itemBuilder: (_, i) => DPOptionRow(
                                title: shown[i]['_d'].toString(),
                                selected: shown[i]['_v'] == value,
                                onTap: () {
                                  Navigator.pop(ctx);
                                  onChanged(shown[i]['_v'].toString());
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
            },
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required dynamic icon,
    required TextInputType keyboardType,
    int? maxLength,
  }) {
    return DPField(
      label: label,
      controller: controller,
      focusNode: focusNode,
      hint: hint,
      keyboardType: keyboardType,
      maxLength: maxLength,
      suffixIcon: icon is DPIconData ? icon : null,
      inputFormatters: keyboardType == TextInputType.number || keyboardType == TextInputType.phone
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
    );
  }

  // ==================== PAYMENT SHEET OVERLAY ====================

  Widget _buildPaymentSheetOverlay() {
    final selectedType = _insuranceTypes.firstWhere(
      (t) => t['code'] == _selectedInsuranceType,
      orElse: () => _insuranceTypes[0],
    );
    final amount = (selectedType['amount'] ?? 0).toDouble();
    final bool isBiometricSupported = Platform.isAndroid || Platform.isIOS;
    final canBiometric = isBiometricSupported && _biometricEnabled && _biometricAllowed;
    return DPSheetOverlay(
      animation: _sheetAnimation,
      onDismiss: _isProcessingPayment ? null : _closePaymentSheet,
      child: DPPaymentReview(
        icon: DPIcons.umbrella,
        serviceLabel: 'Third-party insurance · ${selectedType['name']}',
        amount: amount,
        rows: [
          DPSummaryRow('Insured name', _insuredNameController.text.trim()),
          DPSummaryRow('Plate number', _plateController.text.trim().toUpperCase()),
          DPSummaryRow('Year', _yearController.text.trim()),
          DPSummaryRow('Phone', _phoneController.text.trim()),
          const DPSummaryRow('Service fee', '₦0.00'),
          DPSummaryRow('Total to pay', dpNaira(amount), emphasize: true),
        ],
        walletBalance: _walletBalance,
        showPin: _transactionPinSet,
        pinController: _pinController,
        pinFocusNode: _pinFocusNode,
        pinError: _pinValidationError,
        shake: _shakeAnimation,
        onPinChanged: (_) {
          if (_pinValidationError != null) setState(() => _pinValidationError = null);
        },
        processing: _isProcessingPayment,
        processingBiometric: _useBiometric,
        onPayWithPin: _processPaymentWithPIN,
        onPayWithBiometric: canBiometric ? _processPaymentWithBiometric : null,
        biometricName: _biometricName,
        onClose: _closePaymentSheet,
        footnote: 'Your certificate details will be on the receipt and sent to your email.',
      ),
    );
  }

  // ==================== PAYMENT SHEET DETAILS ====================



  // ==================== PIN OPTION WITH SHAKE ====================


  // ==================== BIOMETRIC OPTION ====================


  // ==================== MAIN BUILD ====================

  @override
  Widget build(BuildContext context) {
    final available = !_isLoadingData && _isUserActive && _insuranceServiceEnabled;
    return Stack(
      children: [
        DPPage(
          title: 'Insurance',
          actionLabel: 'History',
          onAction: () => Navigator.pushNamed(context, '/transactions'),
          bottom: available ? _buildPurchaseButton() : null,
          children: [_buildBody()],
        ),
        if (_showPaymentSheet) _buildPaymentSheetOverlay(),
      ],
    );
  }



  Widget _buildBody() {
    if (_isLoadingData) {
      return const Padding(padding: EdgeInsets.only(top: 80), child: DPLoader(message: 'Loading…'));
    }
    if (!_isUserActive || !_insuranceServiceEnabled) {
      return _buildServiceUnavailable();
    }
    final lookupsMissing =
        _vehicleMakes.isEmpty || _vehicleColors.isEmpty || _engineCapacities.isEmpty || _states.isEmpty;
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 18),
              child: Text('Third-party motor insurance in minutes.', style: DPText.bodyMuted),
            ),
            if (lookupsMissing)
              DPNotice(
                'Some vehicle or location lists didn’t load. Reload to continue.',
                kind: DPNoticeKind.warn,
                action: DPLinkButton(label: 'Reload', onPressed: _loadInsuranceData),
              ),
            _buildInsuranceTypeSection(),
            _buildVehicleSection(),
            _buildLocationSection(),
            _buildPersonalSection(),
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }


  Widget _buildInsuranceTypeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DPFieldLabel('Vehicle type'),
        for (final type in _insuranceTypes)
          _buildInsuranceTypeCard(type, _selectedInsuranceType == type['code']),
      ],
    );
  }


  Widget _buildVehicleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DPSectionHeader('Vehicle details'),
        _buildTextField(
          label: 'Plate number',
          controller: _plateController,
          focusNode: _plateFocusNode,
          hint: 'e.g. ABC123XY',
          icon: DPIcons.idCard,
          keyboardType: TextInputType.text,
        ),
        _buildTextField(
          label: 'Chassis number',
          controller: _chasisController,
          focusNode: _chasisFocusNode,
          hint: 'Enter chassis number',
          icon: DPIcons.fileText,
          keyboardType: TextInputType.text,
        ),
        _buildTextField(
          label: 'Year of make',
          controller: _yearController,
          focusNode: _yearFocusNode,
          hint: 'e.g. 2020',
          icon: DPIcons.calendar,
          keyboardType: TextInputType.number,
          maxLength: 4,
        ),
        _buildDropdownField(
          label: 'Vehicle make',
          value: _selectedVehicleMake,
          items: _vehicleMakes,
          displayKey: 'name',
          valueKey: 'id',
          onChanged: (value) {
            setState(() {
              _selectedVehicleMake = value;
              _selectedVehicleModel = null;
              _vehicleModels = [];
              if (value != null) _loadVehicleModels(value);
            });
          },
          icon: null,
        ),
        if (_selectedVehicleMake != null)
          _buildDropdownField(
            label: 'Vehicle model',
            value: _selectedVehicleModel,
            items: _vehicleModels,
            displayKey: 'name',
            valueKey: 'code',
            onChanged: (value) => setState(() => _selectedVehicleModel = value),
            icon: null,
          ),
        _buildDropdownField(
          label: 'Vehicle colour',
          value: _selectedVehicleColor,
          items: _vehicleColors,
          displayKey: 'name',
          valueKey: 'code',
          onChanged: (value) => setState(() => _selectedVehicleColor = value),
          icon: null,
        ),
        _buildDropdownField(
          label: 'Engine capacity',
          value: _selectedEngineCapacity,
          items: _engineCapacities,
          displayKey: 'value',
          valueKey: 'code',
          onChanged: (value) => setState(() => _selectedEngineCapacity = value),
          icon: null,
        ),
      ],
    );
  }

  Widget _buildLocationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DPSectionHeader('Location'),
        _buildDropdownField(
          label: 'State',
          value: _selectedState,
          items: _states,
          displayKey: 'name',
          valueKey: 'code',
          onChanged: (value) {
            setState(() {
              _selectedState = value;
              _selectedLGA = null;
              _lgas = [];
              if (value != null) _loadLGAs(value);
            });
          },
          icon: null,
        ),
        if (_selectedState != null)
          _buildDropdownField(
            label: 'Local government area',
            value: _selectedLGA,
            items: _lgas,
            displayKey: 'name',
            valueKey: 'code',
            onChanged: (value) => setState(() => _selectedLGA = value),
            icon: null,
          ),
      ],
    );
  }

  Widget _buildPersonalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DPSectionHeader('Policy holder'),
        _buildTextField(
          label: 'Insured name',
          controller: _insuredNameController,
          focusNode: _insuredNameFocusNode,
          hint: 'Full name',
          icon: DPIcons.user,
          keyboardType: TextInputType.text,
        ),
        _buildTextField(
          label: 'Email address',
          controller: _emailController,
          focusNode: _emailFocusNode,
          hint: 'name@email.com',
          icon: DPIcons.mail,
          keyboardType: TextInputType.emailAddress,
        ),
        _buildTextField(
          label: 'Phone number',
          controller: _phoneController,
          focusNode: _phoneFocusNode,
          hint: '0803 456 7890',
          icon: DPIcons.phone,
          keyboardType: TextInputType.phone,
          maxLength: 11,
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return const DPNotice(
      'Terms apply. Your certificate details are issued by the insurer after payment.',
      kind: DPNoticeKind.info,
      margin: EdgeInsets.zero,
    );
  }

  Widget _buildPurchaseButton() {
    final busy = _isLoading || _isAuthenticating || _isProcessingPayment;
    final type = _insuranceTypes.where((t) => t['code'] == _selectedInsuranceType).toList();
    return DPButton(
      label: type.isEmpty ? 'Review insurance' : 'Review · ${dpNaira((type.first['amount'] ?? 0).toDouble(), decimals: false)}',
      icon: DPIcons.arrowRight,
      loading: busy,
      onPressed: busy ? null : _openPaymentSheet,
    );
  }

  Widget _buildServiceUnavailable() {
    return DPServiceUnavailable(
      message: !_isUserActive
          ? 'Your account has been deactivated. Please contact support.'
          : 'Insurance is currently unavailable. Please try again later.',
    );
  }
}
