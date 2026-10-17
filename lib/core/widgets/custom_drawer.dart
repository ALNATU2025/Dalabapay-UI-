// lib/core/widgets/custom_drawer.dart

import 'package:dalabapay/core/services/api_service.dart' show ApiService;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dalabapay/core/services/update_service.dart';
import 'package:hugeicons/hugeicons.dart';
import 'drawer_item.dart';

class CustomDrawer extends StatefulWidget {
  final Widget header;
  final List<DrawerItem> items;
  final DrawerItem selectedItem;
  final Function(DrawerItem) onItemSelected;
  final bool isAdmin;

  const CustomDrawer({
    super.key,
    required this.header,
    required this.items,
    required this.selectedItem,
    required this.onItemSelected,
    this.isAdmin = false,
  });

  @override
  State<CustomDrawer> createState() => _CustomDrawerState();
}

class _CustomDrawerState extends State<CustomDrawer> {
  String _appVersion = 'Loading...';
  String? _latestVersion;
  bool _hasUpdate = false;
  bool _isLoadingVersion = false;
  bool _isDisposed = false;

  // Map drawer titles to Hugeicons
  final Map<String, dynamic> _iconMap = {
    'Admin Dashboard': HugeIcons.strokeRoundedDashboardSquare01,
    'All Services': HugeIcons.strokeRoundedMenuSquare,
    'Manage Users': HugeIcons.strokeRoundedUserGroup,
    'Transactions': HugeIcons.strokeRoundedReceiptText,
    'Status Update': HugeIcons.strokeRoundedShare06,
    'Refund System': HugeIcons.strokeRoundedMoneyExchange01,
    'Fund Wallet': HugeIcons.strokeRoundedWallet01,
    'VTpass Settings': HugeIcons.strokeRoundedApi,
    'Self Fund': HugeIcons.strokeRoundedMoneyAdd01,
    'Verify Payments': HugeIcons.strokeRoundedAward05,
    'Notifications': HugeIcons.strokeRoundedNotification01,
    'Admin Control': HugeIcons.strokeRoundedSettings01,
    'Service Commission': HugeIcons.strokeRoundedAnalyticsUp,
    'App Update': HugeIcons.strokeRoundedSystemUpdate01,
    'Transaction Validation': HugeIcons.strokeRoundedAward05,
    'My Disputes': HugeIcons.strokeRoundedLegal01,
    'App Settings': HugeIcons.strokeRoundedSetting06,
    'Logout': HugeIcons.strokeRoundedLogout01,
    // ✅ ADD TRANSACTION LIMITS
    'Transaction Limits': HugeIcons.strokeRoundedDashboardSpeed01, // Changed to speedometer for limits
  };

  // Define vibrant colors for different icons
  final Map<String, Color> _iconColors = {
    'Admin Dashboard': const Color(0xFF4F46E5), // Indigo
    'All Services': const Color(0xFF0891B2), // Cyan
    'Manage Users': const Color(0xFF059669), // Emerald
    'Transactions': const Color(0xFF2563EB), // Blue
    'Status Update': const Color(0xFF7C3AED), // Purple
    'Refund System': const Color(0xFFDC2626), // Red
    'Fund Wallet': const Color(0xFF16A34A), // Green
    'VTpass Settings': const Color(0xFFF59E0B), // Amber
    'Self Fund': const Color(0xFFD97706), // Orange
    'Verify Payments': const Color(0xFF0D9488), // Teal
    'Notifications': const Color(0xFFEC4899), // Pink
    'Admin Control': const Color(0xFF6366F1), // Indigo
    'App Update': const Color(0xFF8B5CF6), // Violet
    'Transaction Validation': const Color(0xFF0891B2), // Cyan
    'My Disputes': const Color(0xFFEF4444), // Red
    'App Settings': const Color(0xFF6B7280), // Gray
    'Service Commission': const Color(0xFF7C3AED), // Purple
    // ✅ ADD TRANSACTION LIMITS COLOR
    'Transaction Limits': const Color(0xFFF59E0B), // Amber/Yellow for limits
    'Logout': const Color(0xFFEF4444), // Red
  };

  @override
  void initState() {
    super.initState();
    _loadLocalVersionOnly();
    _checkForUpdateSilently();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  // ... (rest of the methods remain the same)
  
  Future<void> _loadLocalVersionOnly() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!_isDisposed) {
        setState(() {
          _appVersion = packageInfo.version;
        });
        debugPrint('✅ Local app version loaded: ${packageInfo.version}');
        return;
      }
    } catch (e) {
      debugPrint('Error loading version from PackageInfo: $e');
    }

    try {
      String version = await ApiService.getAppVersion();
      if (!_isDisposed) {
        setState(() {
          _appVersion = version;
        });
        debugPrint('✅ App version from API: $version');
        return;
      }
    } catch (e) {
      debugPrint('Error getting version from API: $e');
    }

    if (!_isDisposed) {
      setState(() {
        _appVersion = '1.4.0+1';
      });
    }
  }

  Future<void> _checkForUpdateSilently() async {
    try {
      if (_isDisposed) return;
      setState(() => _isLoadingVersion = true);

      final versionInfo = await UpdateService.checkForUpdate().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⏰ Update check timed out');
          return null;
        },
      );

      if (!_isDisposed) {
        if (versionInfo != null) {
          final needsUpdate = versionInfo['needsUpdate'] ?? false;
          final latestVersion = versionInfo['latestVersion'] ?? '1.0.0';

          setState(() {
            _latestVersion = latestVersion;
            _hasUpdate = needsUpdate;
            _isLoadingVersion = false;

            if (versionInfo['currentVersion'] != null) {
              _appVersion = versionInfo['currentVersion'];
            }
          });

          debugPrint(
            '📊 Update check result: needsUpdate=$needsUpdate, latest=$latestVersion',
          );
        } else {
          setState(() => _isLoadingVersion = false);
          debugPrint('ℹ️ No update information received');
        }
      }
    } catch (e) {
      debugPrint('❌ Update check error: $e');
      if (!_isDisposed) {
        setState(() => _isLoadingVersion = false);
      }
    }
  }

  void _showUpdateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.system_update_alt, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text('Update Available'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A new version ($_latestVersion) is available.',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  'Current version: $_appVersion',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Please update to get the latest features and improvements.',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Later'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await UpdateService.openPlayStore(
                    'https://play.google.com/store/apps/details?id=com.dalabapay.official',
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Update Now'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          widget.header,
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 12),
              itemCount: widget.items.length,
              itemBuilder: (context, index) {
                final item = widget.items[index];
                final isSelected = item.title == widget.selectedItem.title;

                if (item.isAdminOnly && !widget.isAdmin) {
                  return const SizedBox.shrink();
                }
                if (item.isUserOnly && widget.isAdmin) {
                  return const SizedBox.shrink();
                }

                final iconData =
                    _iconMap[item.title] ?? HugeIcons.strokeRoundedCircle;
                final iconColor =
                    isSelected
                        ? const Color(0xFF243889)
                        : (_iconColors[item.title] ?? Colors.grey.shade600);

                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => widget.onItemSelected(item),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isSelected
                                ? const Color(
                                  0xFF243889,
                                ).withValues(alpha: 0.08)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border:
                            isSelected
                                ? Border.all(
                                  color: const Color(0xFF243889),
                                  width: 1.5,
                                )
                                : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color:
                                  isSelected
                                      ? const Color(
                                        0xFF243889,
                                      ).withValues(alpha: 0.1)
                                      : iconColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: HugeIcon(
                              icon: iconData,
                              color:
                                  isSelected
                                      ? const Color(0xFF243889)
                                      : iconColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                color:
                                    isSelected
                                        ? const Color(0xFF243889)
                                        : Colors.grey.shade700,
                                fontWeight:
                                    isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (item.badge != null && item.badge!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF219C7E),
                                    const Color(
                                      0xFF219C7E,
                                    ).withValues(alpha: 0.7),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                item.badge!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Version Footer (same as before)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Colors.grey.shade200.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Version $_appVersion',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                    if (_isLoadingVersion)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: const Color(0xFF243889),
                          ),
                        ),
                      ),
                    if (!_isLoadingVersion && _hasUpdate)
                      GestureDetector(
                        onTap: () => _showUpdateDialog(context),
                        child: Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.system_update_alt,
                                size: 10,
                                color: Colors.orange.shade700,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                'v$_latestVersion',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                if (_hasUpdate && !_isLoadingVersion)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: InkWell(
                      onTap: () => _showUpdateDialog(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.orange.shade400,
                              Colors.orange.shade600,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.download, size: 14, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              'Update Available',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}