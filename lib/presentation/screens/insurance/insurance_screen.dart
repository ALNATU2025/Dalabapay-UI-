// lib/presentation/screens/insurance/insurance_screen.dart

import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

import '../../../core/services/api_service.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/widgets/receipt_widget.dart';
import '../../../core/widgets/request_limit_increase_dialog.dart';
import '../../../ui/ui.dart';
import '../../../core/services/commission_rates_service.dart';

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
      'color': const Color(0xFFA76B1D),
    },
    {
      'name': 'Motorcycle',
      'code': 'motorcycle',
      'icon': HugeIcons.strokeRoundedCar05,
      'amount': 3000,
      'color': const Color(0xFF173D88),
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

    final displayMsg =
        attemptsRemaining != null
            ? '⚠️ $message ($attemptsRemaining ${attemptsRemaining == 1 ? 'attempt' : 'attempts'} remaining)'
            : '⚠️ $message';

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.white24,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_reset_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayMsg,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFC0392B),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
        duration: const Duration(seconds: 4),
      ),
    );
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

  void _loadFallbackStates() {
    final stateNames = _statesLGAs.keys.toList();
    setState(() {
      _states =
          stateNames.map((name) {
            return {'code': name, 'name': name};
          }).toList();
      if (_states.isNotEmpty) {
        final firstState = _states[0] as Map;
        final stateCode = firstState['code']?.toString();
        if (stateCode != null && stateCode.isNotEmpty) {
          _selectedState = stateCode;
          _loadLGAs(stateCode);
        }
      }
    });
  }

  void _loadFallbackData() {
    final stateNames = _statesLGAs.keys.toList();
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
      _engineCapacities = [
        {'code': '1', 'value': '0.1 - 1.59'},
        {'code': '2', 'value': '1.6 - 2.0'},
        {'code': '3', 'value': '2.1 - 3.0'},
        {'code': '4', 'value': '3.1 - 4.0'},
        {'code': '5', 'value': '4.1 - 5.0'},
        {'code': '6', 'value': '5.1 - 6.0'},
      ];
      _states =
          stateNames.map((name) {
            return {'code': name, 'name': name};
          }).toList();
      if (_states.isNotEmpty) {
        final firstState = _states[0] as Map;
        final stateCode = firstState['code']?.toString();
        if (stateCode != null && stateCode.isNotEmpty) {
          _selectedState = stateCode;
          _loadLGAs(stateCode);
        }
      }
    });
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
    dpDialog(
      context,
      title: title,
      message: message,
      confirmLabel: 'OK',
      tone: DPTone.error,
    );
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
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedInsuranceType = type['code'];
          _selectedPlan = type['name'];
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: 100,
        height: 100,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: isSelected ? type['color'] : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? type['color'] : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color:
                  isSelected
                      ? type['color'].withOpacity(0.3)
                      : Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(
              icon: type['icon'] as dynamic,
              size: 32,
              color: isSelected ? Colors.white : type['color'],
            ),
            const SizedBox(height: 6),
            Text(
              type['name'] as String,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '₦${type['amount']}',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color:
                    isSelected
                        ? Colors.white.withOpacity(0.9)
                        : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
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
        uniqueItems.add({
          ...item,
          '_dropdown_value': itemValue,
          '_dropdown_display': displayValue,
        });
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF102C68),
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
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(
              prefixIcon: HugeIcon(
                icon: icon,
                color: const Color(0xFF102C68),
                size: 22,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 12,
              ),
              hintText: 'Select $label',
              hintStyle: GoogleFonts.inter(
                color: Colors.grey.shade400,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF102C68),
            ),
            items: [
              DropdownMenuItem<String>(
                value: null,
                child: Text(
                  'Select $label',
                  style: GoogleFonts.inter(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              ...uniqueItems.map<DropdownMenuItem<String>>((item) {
                final itemValue = item['_dropdown_value']?.toString() ?? '';
                final displayValue =
                    item['_dropdown_display']?.toString() ?? 'Unknown';
                return DropdownMenuItem<String>(
                  value: itemValue,
                  child: Text(
                    displayValue,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF102C68),
                    ),
                  ),
                );
              }),
            ],
            onChanged: onChanged,
            dropdownColor: Colors.white,
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedArrowDown01,
              color: const Color(0xFF102C68),
              size: 20,
            ),
          ),
        ),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF102C68),
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
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            maxLength: maxLength,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(
                color: Colors.grey.shade400,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: HugeIcon(
                icon: icon,
                color: const Color(0xFF102C68),
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
              counterText: '',
            ),
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            inputFormatters:
                keyboardType == TextInputType.number
                    ? [FilteringTextInputFormatter.digitsOnly]
                    : null,
          ),
        ),
      ],
    );
  }

  // ==================== PAYMENT SHEET OVERLAY ====================

  Widget _buildPaymentSheetOverlay() {
    final selectedType = _insuranceTypes.firstWhere(
      (t) => t['code'] == _selectedInsuranceType,
      orElse: () => _insuranceTypes[0],
    );
    final amount = ((selectedType['amount'] ?? 0) as num).toDouble();
    final biometricOk = !kIsWeb &&
        (Platform.isAndroid || Platform.isIOS) &&
        _biometricEnabled &&
        _biometricAllowed;
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _sheetAnimation,
        builder: (context, child) => FractionalTranslation(
          translation: Offset(0, 1 - _sheetAnimation.value),
          child: child,
        ),
        child: AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) => Transform.translate(
            offset: Offset(_shakeAnimation.value, 0),
            child: child,
          ),
          child: DPReviewPanel(
            icon: DPIcons.shield,
            title: (selectedType['name'] ?? 'Insurance').toString(),
            amount: amount,
            rows: [
              if (_selectedPlan != null) DPReviewRow('Plan', _selectedPlan!),
              DPReviewRow('Insured name', _insuredNameController.text.trim()),
              DPReviewRow('Plate number', _plateController.text.trim()),
              if (_selectedVehicleMake != null)
                DPReviewRow(
                  'Vehicle',
                  '${_selectedVehicleMake ?? ''} ${_selectedVehicleModel ?? ''}'.trim(),
                ),
              DPReviewRow('Phone number', _phoneController.text.trim()),
              DPReviewRow('Total to pay', DP.naira(amount), strong: true),
            ],
            walletBalance: _walletBalance,
            totalDebit: amount,
            commission: CommissionRatesService.estimate('insurance', amount),
            pinController: _pinController,
            pinFocusNode: _pinFocusNode,
            pinRequired: _transactionPinSet && _pinRequired,
            pinError: _pinValidationError,
            processing: _isProcessingPayment,
            onPay: _processPaymentWithPIN,
            onClose: _closePaymentSheet,
            biometricAvailable: biometricOk,
            biometricLabel: _biometricName,
            onBiometric: _processPaymentWithBiometric,
            footnote: 'Check the plate number. Policies can\'t be reversed once issued.',
          ),
        ),
      ),
    );
  }

  // ==================== PAYMENT SHEET DETAILS ====================



  // ==================== PIN OPTION WITH SHAKE ====================


  // ==================== BIOMETRIC OPTION ====================


  // ==================== MAIN BUILD ====================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_showPaymentSheet,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _showPaymentSheet && !_isProcessingPayment) {
          _closePaymentSheet();
        }
      },
      child: Scaffold(
        backgroundColor: DP.bg,
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  DPTopBar(
                    title: 'Insurance',
                    actionLabel: 'History',
                    onAction: () => Navigator.pushNamed(
                      context,
                      '/transactions',
                      arguments: {'userId': widget.userId},
                    ),
                  ),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
            if (_showPaymentSheet) _buildPaymentSheetOverlay(),
          ],
        ),
      ),
    );
  }


  Widget _buildWalletBalanceBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF102C68).withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF102C68).withOpacity(0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.account_balance_wallet_rounded,
            color: Color(0xFF102C68),
            size: 15,
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isBalanceVisible = !_isBalanceVisible);
            },
            child: Text(
              _isBalanceVisible
                  ? '₦${_walletBalance.toStringAsFixed(2)}'
                  : '••••••',
              style: GoogleFonts.inter(
                color: const Color(0xFF102C68),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoadingData) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF102C68)),
        ),
      );
    }

    if (!_isUserActive || !_insuranceServiceEnabled) {
      return _buildServiceUnavailable();
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: 100,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCleanBanner(),
              const SizedBox(height: 20),
              _buildInsuranceTypeSection(),
              const SizedBox(height: 24),
              if (_selectedPlan != null) _buildSelectedPlanDisplay(),
              const SizedBox(height: 24),
              _buildVehicleSection(),
              const SizedBox(height: 24),
              _buildLocationSection(),
              const SizedBox(height: 24),
              _buildPersonalSection(),
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

  Widget _buildCleanBanner() {
    return const DPHeadline(
      'Cover that keeps you moving.',
      subtitle: 'Third-party motor insurance with your certificate on the receipt.',
      bottom: 0,
    );
  }

  Widget _buildInsuranceTypeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Insurance Type',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF102C68),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _insuranceTypes.length,
            itemBuilder: (context, index) {
              final type = _insuranceTypes[index];
              return _buildInsuranceTypeCard(
                type,
                _selectedInsuranceType == type['code'],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedPlanDisplay() {
    final selectedPlan = _insuranceTypes.firstWhere(
      (t) => t['name'] == _selectedPlan,
      orElse: () => _insuranceTypes[0],
    );
    final amount = (selectedPlan['amount'] ?? 0).toDouble();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF168566).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF168566).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedCheckmarkCircle01,
            color: const Color(0xFF168566),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Selected: $_selectedPlan',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF102C68),
              ),
            ),
          ),
          Text(
            '₦${amount.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF168566),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vehicle Information',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF102C68),
            ),
          ),
          const SizedBox(height: 16),
          _buildTextField(
            label: 'Plate Number',
            controller: _plateController,
            focusNode: _plateFocusNode,
            hint: 'Enter plate number',
            icon: HugeIcons.strokeRoundedCar01,
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            label: 'Chasis Number',
            controller: _chasisController,
            focusNode: _chasisFocusNode,
            hint: 'Enter chasis number',
            icon: HugeIcons.strokeRoundedLeftToRightListNumber,
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            label: 'Year of Make',
            controller: _yearController,
            focusNode: _yearFocusNode,
            hint: 'e.g., 2020',
            icon: HugeIcons.strokeRoundedCalendar01,
            keyboardType: TextInputType.number,
            maxLength: 4,
          ),
          const SizedBox(height: 12),
          _buildDropdownField(
            label: 'Vehicle Make',
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
            icon: HugeIcons.strokeRoundedCar01,
          ),
          if (_selectedVehicleMake != null) ...[
            const SizedBox(height: 12),
            _buildDropdownField(
              label: 'Vehicle Model',
              value: _selectedVehicleModel,
              items: _vehicleModels,
              displayKey: 'name',
              valueKey: 'code',
              onChanged: (value) {
                setState(() => _selectedVehicleModel = value);
              },
              icon: HugeIcons.strokeRoundedCar01,
            ),
          ],
          const SizedBox(height: 12),
          _buildDropdownField(
            label: 'Vehicle Color',
            value: _selectedVehicleColor,
            items: _vehicleColors,
            displayKey: 'name',
            valueKey: 'code',
            onChanged: (value) {
              setState(() => _selectedVehicleColor = value);
            },
            icon: HugeIcons.strokeRoundedColorPicker,
          ),
          const SizedBox(height: 12),
          _buildDropdownField(
            label: 'Engine Capacity',
            value: _selectedEngineCapacity,
            items: _engineCapacities,
            displayKey: 'value',
            valueKey: 'code',
            onChanged: (value) {
              setState(() => _selectedEngineCapacity = value);
            },
            icon: HugeIcons.strokeRoundedEngine,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Location Information',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF102C68),
            ),
          ),
          const SizedBox(height: 16),
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
            icon: HugeIcons.strokeRoundedLocation01,
          ),
          if (_selectedState != null) ...[
            const SizedBox(height: 12),
            _buildDropdownField(
              label: 'Local Government Area',
              value: _selectedLGA,
              items: _lgas,
              displayKey: 'name',
              valueKey: 'code',
              onChanged: (value) {
                setState(() => _selectedLGA = value);
              },
              icon: HugeIcons.strokeRoundedMapPin,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPersonalSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personal Information',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF102C68),
            ),
          ),
          const SizedBox(height: 16),
          _buildTextField(
            label: 'Insured Name',
            controller: _insuredNameController,
            focusNode: _insuredNameFocusNode,
            hint: 'Enter full name',
            icon: HugeIcons.strokeRoundedUser,
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            label: 'Email Address',
            controller: _emailController,
            focusNode: _emailFocusNode,
            hint: 'Enter email address',
            icon: HugeIcons.strokeRoundedMail01,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            label: 'Phone Number',
            controller: _phoneController,
            focusNode: _phoneFocusNode,
            hint: 'Enter 11-digit phone number',
            icon: HugeIcons.strokeRoundedSmartPhone01,
            keyboardType: TextInputType.phone,
            maxLength: 11,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF102C68).withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF102C68).withOpacity(0.08)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF102C68),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'T&C applies. Coverage details will be shared after payment.',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF102C68),
              ),
            ),
          ),
        ],
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
          backgroundColor: const Color(0xFF168566),
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
                    const Icon(
                      Icons.bolt_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Proceed to Pay',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  Widget _buildServiceUnavailable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DPEmptyState(
          icon: DPIcons.shield,
          title: 'Insurance is unavailable right now',
          message: 'Please try again in a little while.',
          actionLabel: 'Go back',
          onAction: () => Navigator.pop(context),
        ),
      ),
    );
  }
}
