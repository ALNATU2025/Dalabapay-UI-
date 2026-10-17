// lib/presentation/screens/user_disputes_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;

import '../../../core/services/api_service.dart';
import '../../../core/widgets/custom_drawer.dart';
import '../../../core/widgets/drawer_item.dart';
import '../../ui/ui.dart';
import 'package:dalabapay/presentation/screens/dashboard/dashboard_screen.dart'
    show DashboardScreen;

class UserDisputesPage extends StatefulWidget {
  const UserDisputesPage({super.key});

  @override
  State<UserDisputesPage> createState() => _UserDisputesPageState();
}

class _UserDisputesPageState extends State<UserDisputesPage>
    with TickerProviderStateMixin {
  // ==================== BRAND COLORS ====================
  static const Color primaryColor = Color(0xFF102C68);
  static const Color secondaryColor = Color(0xFF168566);
  static const Color successColor = Color(0xFF168566);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color infoColor = Color(0xFF3B82F6);
  static const Color textPrimary = Color(0xFF14263D);
  static const Color textSecondary = Color(0xFF728078);
  static const Color backgroundLight = Color(0xFFF8F9F5);

  // ==================== STATE ====================
  List<dynamic> _disputes = [];
  List<dynamic> _userTransactions = [];
  bool _isLoading = true;
  bool _isCreating = false;
  String? _errorMessage;
  int _pendingCount = 0;
  String _currentUserRole = 'user';
  String _currentUserName = '';
  String _currentUserEmail = '';
  String _currentUserId = '';
  bool _isAdmin = false;
  bool _isSuperAdmin = false;

  // Screenshot - Cross-platform (Unified approach)
  XFile? _selectedImageXFile;
  Uint8List? _imageBytes;
  String? _imageDataUrl;
  bool _hasImage = false;

  // Animation
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Tab controller
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadCurrentUser();
    _loadData();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  // ==================== USER LOADING ====================

  Future<void> _loadCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user');
      if (userDataString != null) {
        final userData = jsonDecode(userDataString);

        try {
          final roleResult = await ApiService.getUserRole();
          if (roleResult['success'] == true) {
            final data = roleResult['data'];
            final userRole = data?['role'] ?? 'user';
            final isAdmin =
                data?['isAdmin'] == true ||
                userRole == 'admin' ||
                userRole == 'super_admin';
            final isSuperAdmin =
                data?['isSuperAdmin'] == true || userRole == 'super_admin';

            setState(() {
              _currentUserId = userData['_id']?.toString() ?? '';
              _currentUserName = userData['fullName'] ?? 'Unknown User';
              _currentUserEmail = userData['email'] ?? 'No Email';
              _currentUserRole = userRole;
              _isAdmin = isAdmin;
              _isSuperAdmin = isSuperAdmin;
            });
          } else {
            _loadCurrentUserFromCache(userData);
          }
        } catch (e) {
          _log('⚠️ Could not fetch role from backend: $e');
          _loadCurrentUserFromCache(userData);
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading current user: $e');
    }
  }

  void _loadCurrentUserFromCache(Map<String, dynamic> userData) {
    setState(() {
      _currentUserId = userData['_id']?.toString() ?? '';
      _currentUserName = userData['fullName'] ?? 'Unknown User';
      _currentUserEmail = userData['email'] ?? 'No Email';
      _isAdmin = userData['isAdmin'] == true;
      _isSuperAdmin = false;
      _currentUserRole = _isAdmin ? 'admin' : 'user';
    });
  }

  // ==================== DATA LOADING ====================

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final disputesResponse = await ApiService.authenticatedGet(
        '/api/disputes/my-disputes',
      );
      if (disputesResponse['success'] == true) {
        setState(() {
          _disputes = disputesResponse['disputes'] ?? [];
          _pendingCount = disputesResponse['pendingCount'] ?? 0;
        });
      }

      final transactions = await ApiService.getTransactions();
      setState(() {
        _userTransactions =
            transactions.where((tx) {
              final status = tx['status']?.toString().toLowerCase() ?? '';
              return status == 'failed' || status == 'pending';
            }).toList();
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('🔍 USER DISPUTES: $message');
    }
  }

  // ==================== DISPUTE ACTIONS ====================

  Future<void> _createDispute({
    required String transactionId,
    required String type,
    required String reason,
    String? description,
    double? amount,
    XFile? screenshot,
  }) async {
    if (_isCreating) {
      _log('⚠️ Already creating a dispute, ignoring duplicate request');
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      // Convert XFile to File for API (works cross-platform)
      File? file;
      if (screenshot != null) {
        if (kIsWeb) {
          // For web, we need to handle differently
          // The ApiService should handle web uploads
          file = File(screenshot.path);
        } else {
          file = File(screenshot.path);
        }
      }

      final response = await ApiService.createDispute(
        transactionId: transactionId,
        type: type,
        reason: reason,
        description: description,
        amount: amount,
        screenshot: file,
      );

      if (response['success'] == true) {
        if (mounted) {
          _showSnackBar(
            response['message'] ?? 'Dispute created successfully!',
            false,
          );
          await _loadData();
        }
      } else {
        throw Exception(response['message'] ?? 'Failed to create dispute');
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString().replaceAll('Exception: ', '');
        if (errorMessage.contains('Failed to fetch') ||
            errorMessage.contains('Cannot connect') ||
            errorMessage.contains('Network')) {
          errorMessage =
              'Network error: Unable to reach server. Please check your internet connection.';
        } else if (errorMessage.contains('timeout')) {
          errorMessage = 'Request timed out. Please try again.';
        } else if (errorMessage.contains('already have an open dispute')) {
          errorMessage =
              'You already have an open dispute for this transaction. Please wait for it to be resolved.';
        }
        _showSnackBar(errorMessage, true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  // ==================== UI HELPERS ====================

  void _showSnackBar(String message, bool isError) {
    if (!mounted) return;
    dpSnack(context, message, error: isError, success: !isError);
  }

  String _getFullImageUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    if (path.startsWith('/uploads')) {
      return '${ApiService.baseUrl}$path';
    }
    return '${ApiService.baseUrl}/uploads/disputes/$path';
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending Review';
      case 'under_review':
        return 'Under Review';
      case 'investigating':
        return 'Investigating';
      case 'resolved':
        return 'Resolved ✓';
      case 'rejected':
        return 'Rejected ✗';
      case 'escalated':
        return 'Escalated';
      default:
        return status.toUpperCase();
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return warningColor;
      case 'under_review':
        return infoColor;
      case 'investigating':
        return Colors.purple;
      case 'resolved':
        return successColor;
      case 'rejected':
        return errorColor;
      case 'escalated':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // ==================== CROSS-PLATFORM IMAGE HELPERS ====================

  /// Pick image from gallery - works on all platforms (Web, Mobile, Desktop)
  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (image != null) {
        // Read bytes for preview (works on all platforms)
        final bytes = await image.readAsBytes();

        setState(() {
          _selectedImageXFile = image;
          _imageBytes = bytes;
          // Create data URL for preview (works everywhere)
          _imageDataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
          _hasImage = true;
        });
        _log(
          '✅ Image selected (${bytes.length} bytes) - Platform: ${kIsWeb ? "Web" : "Native"}',
        );
      }
    } catch (e) {
      _log('❌ Error picking image: $e');
      _showSnackBar('Error selecting image: ${e.toString()}', true);
    }
  }

  /// Get the File object for API upload (works cross-platform)
  File? _getFileForUpload() {
    if (_selectedImageXFile == null) return null;
    return File(_selectedImageXFile!.path);
  }

  /// Build preview image for selected screenshot (unified cross-platform)
  Widget _buildPreviewImage({
    double? height,
    double? width,
    BoxFit fit = BoxFit.cover,
  }) {
    if (!_hasImage || _imageDataUrl == null) {
      return Container(
        height: height ?? 150,
        width: width ?? double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, size: 40, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              'No image selected',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    // Unified approach: Use memory image with data URL (works on all platforms)
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        _imageBytes!,
        height: height ?? 150,
        width: width ?? double.infinity,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: height ?? 150,
            color: Colors.grey[200],
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, size: 40, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text(
                  'Failed to load image',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Build network image from server (with caching and error handling)
  Widget _buildNetworkImage({
    required String imageUrl,
    double? height,
    double? width,
    BoxFit fit = BoxFit.cover,
  }) {
    return Image.network(
      imageUrl,
      height: height,
      width: width,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          height: height ?? 80,
          width: width ?? 80,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value:
                    loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: height ?? 80,
          width: width ?? 80,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image, size: 24, color: Colors.grey[400]),
              const SizedBox(height: 4),
              Text(
                'Error',
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build evidence item (image or file)
  Widget _buildEvidenceItem(
    String evidencePath, {
    double? height,
    double? width,
  }) {
    final isImage =
        evidencePath.toLowerCase().endsWith('.jpg') ||
        evidencePath.toLowerCase().endsWith('.png') ||
        evidencePath.toLowerCase().endsWith('.jpeg') ||
        evidencePath.toLowerCase().endsWith('.gif') ||
        evidencePath.toLowerCase().endsWith('.webp');

    if (!isImage) {
      return Container(
        height: height ?? 80,
        width: width ?? 80,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insert_drive_file, size: 30, color: Colors.grey[600]),
            const SizedBox(height: 4),
            Text(
              'File',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    final imageUrl = _getFullImageUrl(evidencePath);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: _buildNetworkImage(
        imageUrl: imageUrl,
        height: height ?? 80,
        width: width ?? 80,
      ),
    );
  }

  // ==================== DIALOGS ====================

  void _showEvidenceDialog(List<dynamic> evidence) {
    if (evidence.isEmpty) {
      _showSnackBar('No evidence uploaded for this dispute', true);
      return;
    }

    final isMobile = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => Dialog(
            insetPadding: EdgeInsets.all(isMobile ? 8 : 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              width: isMobile ? double.infinity : 600,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
                maxWidth: isMobile ? double.infinity : 600,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [Color(0xFF5BB592), Color(0xFF102C68)],
                        stops: [0.06, 0.41],
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.image, color: Colors.white, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Evidence (${evidence.length} file${evidence.length > 1 ? 's' : ''})',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close, color: Colors.white),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isMobile ? 2 : 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1,
                      ),
                      itemCount: evidence.length,
                      itemBuilder: (context, index) {
                        final evidencePath = evidence[index].toString();
                        final isImage =
                            evidencePath.toLowerCase().endsWith('.jpg') ||
                            evidencePath.toLowerCase().endsWith('.png') ||
                            evidencePath.toLowerCase().endsWith('.jpeg') ||
                            evidencePath.toLowerCase().endsWith('.gif') ||
                            evidencePath.toLowerCase().endsWith('.webp');

                        if (isImage) {
                          return GestureDetector(
                            onTap:
                                () => _showFullScreenImage(
                                  _getFullImageUrl(evidencePath),
                                ),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.grey.shade200,
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _buildNetworkImage(
                                  imageUrl: _getFullImageUrl(evidencePath),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          );
                        } else {
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.grey.shade200,
                                width: 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.insert_drive_file,
                                  size: 40,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'File ${index + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  // Footer
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${evidence.length} file${evidence.length > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 13,
                            color: textSecondary,
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            foregroundColor: primaryColor,
                          ),
                          child: Text(
                            'Close',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  void _showFullScreenImage(String imageUrl) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => Dialog(
            insetPadding: EdgeInsets.zero,
            backgroundColor: Colors.black,
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    panEnabled: true,
                    boundaryMargin: const EdgeInsets.all(20),
                    child: _buildNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                      height: double.infinity,
                      width: double.infinity,
                    ),
                  ),
                ),
                Positioned(
                  top: 40,
                  right: 20,
                  child: IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 30,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.5),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Tap to zoom • Drag to pan',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  void _showCreateDisputeDialog(Map<String, dynamic> transaction) {
    final TextEditingController reasonController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    String selectedType = 'refund_request';

    // Reset image state
    _selectedImageXFile = null;
    _imageBytes = null;
    _imageDataUrl = null;
    _hasImage = false;

    final isMobile = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                backgroundColor: Colors.white,
                titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: warningColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.gavel, color: warningColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'File a Dispute',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: SizedBox(
                    width: isMobile ? double.infinity : 400,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: backgroundLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Transaction Details',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Ref: ${transaction['reference']}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Amount: ₦${(transaction['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Date: ${DateFormat('MMM dd, yyyy').format(DateTime.parse(transaction['createdAt'].toString()))}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: selectedType,
                          decoration: InputDecoration(
                            labelText: 'Dispute Type',
                            labelStyle: TextStyle(color: textSecondary),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: primaryColor,
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          style: TextStyle(color: textPrimary),
                          items: const [
                            DropdownMenuItem(
                              value: 'service_not_delivered',
                              child: Text('📦 Service Not Delivered'),
                            ),
                            DropdownMenuItem(
                              value: 'incorrect_amount',
                              child: Text('💰 Incorrect Amount'),
                            ),
                            DropdownMenuItem(
                              value: 'failed_transaction',
                              child: Text('❌ Failed Transaction'),
                            ),
                            DropdownMenuItem(
                              value: 'pending_transaction',
                              child: Text('⏳ Pending Transaction'),
                            ),
                            DropdownMenuItem(
                              value: 'refund_request',
                              child: Text('💸 Refund Request'),
                            ),
                            DropdownMenuItem(
                              value: 'other',
                              child: Text('📝 Other'),
                            ),
                          ],
                          onChanged:
                              (value) =>
                                  setDialogState(() => selectedType = value!),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: reasonController,
                          style: TextStyle(color: textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Reason *',
                            hintText: 'Brief explanation of the issue',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: primaryColor,
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: descriptionController,
                          style: TextStyle(color: textPrimary),
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Detailed Description',
                            hintText:
                                'Provide more details about what happened',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: primaryColor,
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Screenshot Upload Section - Cross-Platform (Unified)
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.image_outlined,
                                      color: textSecondary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Upload Evidence (Optional)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              // Show preview if image selected
                              if (_hasImage) ...[
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: _buildPreviewImage(
                                          height: 160,
                                          width: double.infinity,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.check_circle_rounded,
                                            color: successColor,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Image ready for upload (${(_imageBytes?.length ?? 0) ~/ 1024} KB)',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: successColor,
                                              ),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              setDialogState(() {
                                                _selectedImageXFile = null;
                                                _imageBytes = null;
                                                _imageDataUrl = null;
                                                _hasImage = false;
                                              });
                                            },
                                            child: Text(
                                              'Change',
                                              style: TextStyle(
                                                color: primaryColor,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                InkWell(
                                  onTap: () async {
                                    await _pickImage();
                                    setDialogState(() {});
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: primaryColor.withOpacity(
                                              0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.upload_file,
                                            color: primaryColor,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Click to upload screenshot',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                  color: textPrimary,
                                                ),
                                              ),
                                              Text(
                                                'PNG, JPG, WEBP • Max 1MB',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.chevron_right,
                                          color: Colors.grey[400],
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Supported formats: PNG, JPG, JPEG, WEBP',
                          style: TextStyle(
                            fontSize: 11,
                            color: textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                actions: [
                  TextButton(
                    onPressed: () {
                      _selectedImageXFile = null;
                      _imageBytes = null;
                      _imageDataUrl = null;
                      _hasImage = false;
                      Navigator.pop(ctx);
                    },
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: textSecondary,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed:
                        _isCreating
                            ? null
                            : () async {
                              if (reasonController.text.isEmpty) {
                                _showSnackBar('Please enter a reason', true);
                                return;
                              }
                              Navigator.pop(ctx);
                              await _createDispute(
                                transactionId: transaction['_id'].toString(),
                                type: selectedType,
                                reason: reasonController.text,
                                description:
                                    descriptionController.text.isNotEmpty
                                        ? descriptionController.text
                                        : null,
                                amount:
                                    (transaction['amount'] as num?)?.toDouble(),
                                screenshot: _selectedImageXFile,
                              );
                              // Reset image state
                              _selectedImageXFile = null;
                              _imageBytes = null;
                              _imageDataUrl = null;
                              _hasImage = false;
                            },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child:
                        _isCreating
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                            : Text(
                              'Submit Dispute',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                  ),
                ],
              );
            },
          ),
    );
  }

  void _showDisputeDetails(Map<String, dynamic> dispute) {
    final status = dispute['status']?.toString() ?? 'pending';
    final transaction = dispute['transactionId'] as Map<String, dynamic>?;
    final evidence = dispute['evidence'] as List<dynamic>?;
    final hasEvidence = evidence != null && evidence.isNotEmpty;
    final statusColor = _getStatusColor(status);
    final statusLabel = _getStatusLabel(status);

    final isMobile = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.gavel, color: statusColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Dispute Details',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: isMobile ? double.infinity : 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Status', statusLabel, statusColor),
                  const Divider(),
                  _buildDetailRow(
                    'Type',
                    dispute['type']
                            ?.toString()
                            .replaceAll('_', ' ')
                            .toUpperCase() ??
                        'N/A',
                  ),
                  _buildDetailRow(
                    'Amount',
                    '₦${(dispute['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                  ),
                  _buildDetailRow(
                    'Reason',
                    dispute['reason']?.toString() ?? 'N/A',
                  ),
                  if (dispute['description'] != null &&
                      dispute['description'].toString().isNotEmpty)
                    _buildDetailRow(
                      'Description',
                      dispute['description'].toString(),
                    ),
                  if (hasEvidence) ...[
                    const Divider(),
                    Text(
                      'Attached Evidence',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Evidence Grid
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          evidence.map((e) {
                            final path = e.toString();
                            return GestureDetector(
                              onTap:
                                  () => _showFullScreenImage(
                                    _getFullImageUrl(path),
                                  ),
                              child: _buildEvidenceItem(
                                path,
                                height: 80,
                                width: 80,
                              ),
                            );
                          }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => _showEvidenceDialog(evidence),
                        icon: const Icon(Icons.fullscreen, size: 18),
                        label: Text(
                          'View All Evidence (${evidence.length})',
                          style: TextStyle(color: primaryColor),
                        ),
                      ),
                    ),
                  ],
                  if (dispute['resolution'] != null &&
                      dispute['resolution'].toString().isNotEmpty) ...[
                    const Divider(),
                    _buildDetailRow(
                      'Resolution',
                      dispute['resolution'].toString(),
                      successColor,
                    ),
                    if (dispute['resolvedAt'] != null)
                      _buildDetailRow(
                        'Resolved On',
                        DateFormat('MMM dd, yyyy HH:mm').format(
                          DateTime.parse(dispute['resolvedAt'].toString()),
                        ),
                      ),
                  ],
                  if (transaction != null) ...[
                    const Divider(),
                    _buildDetailRow(
                      'Transaction Ref',
                      transaction['reference']?.toString() ?? 'N/A',
                    ),
                  ],
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Close',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildDetailRow(String label, String value, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: color ?? textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== DRAWER ====================

  Widget _buildDrawerHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [primaryColor, primaryColor.withOpacity(0.8)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: Colors.white,
                child: Text(
                  _currentUserName.isNotEmpty
                      ? _currentUserName[0].toUpperCase()
                      : 'U',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentUserName.isNotEmpty ? _currentUserName : 'User',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _currentUserEmail.isNotEmpty
                          ? _currentUserEmail
                          : 'user@example.com',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: secondaryColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: secondaryColor.withOpacity(0.3)),
            ),
            child: Text(
              _isSuperAdmin ? 'SUPER ADMIN' : (_isAdmin ? 'ADMIN' : 'USER'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: secondaryColor,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<DrawerItem> get _drawerItems => [
    const DrawerItem(
      title: "All Services",
      icon: Icons.apps,
      page: DashboardScreen(),
      isUserOnly: false,
    ),
    const DrawerItem(
      title: "Transaction Validation",
      icon: Icons.verified_user,
      page: SizedBox.shrink(),
      isUserOnly: true,
    ),
    const DrawerItem(
      title: "My Disputes",
      icon: Icons.gavel,
      page: SizedBox.shrink(),
      isUserOnly: true,
    ),
    const DrawerItem(
      title: "App Settings",
      icon: Icons.settings,
      page: SizedBox.shrink(),
    ),
    const DrawerItem(
      title: "Logout",
      icon: Icons.logout,
      page: SizedBox.shrink(),
    ),
  ];

  void _onDrawerItemSelected(DrawerItem item) {
    if (item.title == "Logout") {
      _showLogoutConfirmation();
      return;
    }
    if (item.title == "All Services") {
      if (Navigator.canPop(context)) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          // Navigate to a fallback screen
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        // Navigate to a fallback screen
        Navigator.pushReplacementNamed(context, '/home');
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
      return;
    }
    if (item.title == "My Disputes") {
      if (Navigator.canPop(context)) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          // Navigate to a fallback screen
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        // Navigate to a fallback screen
        Navigator.pushReplacementNamed(context, '/home');
      }
      return;
    }
    if (item.title == "Transaction Validation") {
      if (Navigator.canPop(context)) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          // Navigate to a fallback screen
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        // Navigate to a fallback screen
        Navigator.pushReplacementNamed(context, '/home');
      }
      Navigator.pushNamed(context, '/transaction-validation');
      return;
    }
    if (item.title == "App Settings") {
      if (Navigator.canPop(context)) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          // Navigate to a fallback screen
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        // Navigate to a fallback screen
        Navigator.pushReplacementNamed(context, '/home');
      }
      Navigator.pushNamed(context, '/settings');
      return;
    }
    if (item.page is! SizedBox) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => item.page),
      );
    }
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Logout'),
            content: const Text('Are you sure you want to logout?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      // Navigate to a fallback screen
                      Navigator.pushReplacementNamed(context, '/home');
                    }
                  } else {
                    // Navigate to a fallback screen
                    Navigator.pushReplacementNamed(context, '/home');
                  }
                  Navigator.pushReplacementNamed(context, '/login');
                },
                child: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  // ==================== UI BUILDERS ====================

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DP.gutter, 8, DP.gutter, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DPHeader(
            title: 'My tickets',
            actionLabel: 'Refresh',
            onAction: _loadData,
          ),
          const SizedBox(height: 4),
          Text('Report a problem with a payment and follow its progress.', style: DPText.bodyMuted),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    final total = _disputes.length;
    final resolved = _disputes.where((d) => d['status'] == 'resolved').length;
    final pending = _disputes
        .where((d) => d['status'] == 'pending' || d['status'] == 'under_review')
        .length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(DP.gutter, 14, DP.gutter, 4),
      child: Row(
        children: [
          Expanded(child: _buildStatCard(title: 'Total', value: '$total', icon: Icons.receipt_long, color: DP.ink, isMobile: true, screenWidth: 0)),
          const SizedBox(width: 10),
          Expanded(child: _buildStatCard(title: 'Open', value: '$pending', icon: Icons.hourglass_top, color: DP.warn, isMobile: true, screenWidth: 0)),
          const SizedBox(width: 10),
          Expanded(child: _buildStatCard(title: 'Resolved', value: '$resolved', icon: Icons.check_circle, color: DP.green, isMobile: true, screenWidth: 0)),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isMobile,
    required double screenWidth,
  }) {
    return DPCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: DPText.small),
          const SizedBox(height: 4),
          Text(value, style: DPText.title.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(DP.gutter, 14, DP.gutter, 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: DP.surface,
        borderRadius: BorderRadius.circular(DP.rMd),
        border: Border.all(color: DP.border),
      ),
      child: TabBar(
        controller: _tabController,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: DP.greenSoft,
          borderRadius: BorderRadius.circular(DP.rSm),
          border: Border.all(color: DP.green),
        ),
        labelColor: DP.green,
        unselectedLabelColor: DP.muted,
        labelStyle: DPText.label,
        tabs: [
          Tab(height: 40, text: 'My tickets (${_disputes.length})'),
          const Tab(height: 40, text: 'Report a payment'),
        ],
      ),
    );
  }

  Widget _buildDisputesList() {
    if (_disputes.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(DP.gutter),
        children: [
          DPEmptyState(
            icon: DPIcons.ticket,
            title: 'No tickets yet',
            message: 'If a payment failed or is stuck, report it and we’ll look into it.',
            actionLabel: 'Report a payment',
            onAction: () => _tabController.animateTo(1),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      color: DP.green,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(DP.gutter, 10, DP.gutter, 24),
        itemCount: _disputes.length,
        itemBuilder: (context, index) => _buildDisputeCard(_disputes[index]),
      ),
    );
  }

  Widget _buildDisputeCard(Map<String, dynamic> dispute) {
    final status = dispute['status']?.toString() ?? 'pending';
    final transaction = dispute['transactionId'] is Map ? dispute['transactionId'] as Map<String, dynamic> : null;
    final date = DateTime.tryParse(dispute['createdAt']?.toString() ?? '');
    final evidence = dispute['evidence'] as List<dynamic>?;
    final hasEvidence = evidence != null && evidence.isNotEmpty;
    final statusLabel = _getStatusLabel(status);
    final type = dispute['type']?.toString().replaceAll('_', ' ') ?? 'Dispute';
    return DPCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () => _showDisputeDetails(dispute),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DPIconBadge(icon: DPIcons.ticket, size: 40, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type[0].toUpperCase() + type.substring(1), style: DPText.body.copyWith(fontWeight: FontWeight.w500)),
                    if (transaction != null)
                      Text(transaction['reference']?.toString() ?? '', style: DPText.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (date != null) Text(DateFormat('d MMM yyyy').format(date.toLocal()), style: DPText.small),
                  ],
                ),
              ),
              DPStatusPill(statusLabel.replaceAll(' ✓', '').replaceAll(' ✗', '')),
            ],
          ),
          const SizedBox(height: 10),
          Text(dispute['reason']?.toString() ?? 'No reason provided',
              style: DPText.bodyMuted.copyWith(fontSize: 13.5), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (hasEvidence) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: evidence.length > 4 ? 4 : evidence.length,
                itemBuilder: (context, index) {
                  final path = evidence[index].toString();
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => _showFullScreenImage(_getFullImageUrl(path)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _buildEvidenceItem(path, height: 64, width: 64),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (evidence.length > 4)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('+${evidence.length - 4} more', style: DPText.small),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildNewDisputeTab() {
    if (_userTransactions.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(DP.gutter),
        children: const [
          DPEmptyState(
            icon: DPIcons.receipt,
            title: 'No transactions yet',
            message: 'Payments you can report will appear here.',
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      color: DP.green,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(DP.gutter, 10, DP.gutter, 24),
        children: [
          const DPNotice(
            'You can report failed or pending payments. Successful payments don’t need a ticket.',
            kind: DPNoticeKind.info,
          ),
          for (final tx in _userTransactions) _buildTransactionCard(tx),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final status = tx['status']?.toString().toLowerCase() ?? '';
    final date = DateTime.tryParse(tx['createdAt']?.toString() ?? '');
    final isSuccessful = status.contains('success') || status.contains('completed');
    final canFileDispute = status.contains('pending') || status.contains('failed');
    return DPCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tx['type']?.toString() ?? 'Transaction', style: DPText.body.copyWith(fontWeight: FontWeight.w500)),
                    Text(
                      [
                        if (date != null) DateFormat('d MMM yyyy').format(date.toLocal()),
                        tx['reference']?.toString() ?? '',
                      ].where((e) => e.isNotEmpty).join(' · '),
                      style: DPText.small,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(dpNaira(amount), style: DPText.value),
                  const SizedBox(height: 4),
                  DPStatusPill(tx['status']?.toString() ?? 'Unknown'),
                ],
              ),
            ],
          ),
          if (canFileDispute) ...[
            const SizedBox(height: 14),
            DPButton(
              label: 'Report this payment',
              kind: DPButtonKind.soft,
              height: 46,
              onPressed: () => _showCreateDisputeDialog(tx),
            ),
          ] else if (isSuccessful) ...[
            const SizedBox(height: 10),
            Text('Completed — nothing to report.', style: DPText.small.copyWith(color: DP.green)),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return ListView(
      padding: const EdgeInsets.all(DP.gutter),
      children: [
        DPEmptyState(
          icon: DPIcons.circleAlert,
          title: 'Couldn’t load your tickets',
          message: _errorMessage ?? 'Something went wrong',
          actionLabel: 'Try again',
          onAction: _loadData,
        ),
      ],
    );
  }

  // ==================== MAIN BUILD ====================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: DP.bg,
        body: Center(child: DPLoader(message: 'Loading your tickets…')),
      );
    }
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: DP.bg,
      drawer: CustomDrawer(
        header: _buildDrawerHeader(),
        items: _drawerItems,
        selectedItem: _drawerItems.firstWhere(
          (item) => item.title == "My Disputes",
          orElse: () => _drawerItems.first,
        ),
        onItemSelected: _onDrawerItemSelected,
        isAdmin: _isAdmin,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                _buildStatsSection(),
                _buildTabBar(),
                Expanded(
                  child: _errorMessage != null
                      ? _buildErrorState()
                      : TabBarView(
                          controller: _tabController,
                          children: [_buildDisputesList(), _buildNewDisputeTab()],
                        ),
                ),
              ],
            ),
            if (_isCreating) const DPBusyOverlay(message: 'Sending your ticket…'),
          ],
        ),
      ),
    );
  }
}
