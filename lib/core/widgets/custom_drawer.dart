// lib/core/widgets/custom_drawer.dart

import 'package:dalabapay/core/services/api_service.dart' show ApiService;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dalabapay/core/services/update_service.dart';
import '../../ui/ui.dart';
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
  // Map drawer titles to design-system icons
  final Map<String, DPIconData> _iconMap = {
    'Admin Dashboard': DPIcons.layoutGrid,
    'All Services': DPIcons.house,
    'Manage Users': DPIcons.users,
    'Transactions': DPIcons.receipt,
    'Status Update': DPIcons.refreshCw,
    'Refund System': DPIcons.rotateCcw,
    'Fund Wallet': DPIcons.wallet,
    'VTpass Settings': DPIcons.slidersHorizontal,
    'Self Fund': DPIcons.handCoins,
    'Verify Payments': DPIcons.badgeCheck,
    'Notifications': DPIcons.bellRing,
    'Admin Control': DPIcons.settings,
    'Service Commission': DPIcons.chartColumn,
    'App Update': DPIcons.download,
    'Transaction Validation': DPIcons.shieldCheck,
    'My Disputes': DPIcons.messagesSquare,
    'App Settings': DPIcons.settings,
    'Logout': DPIcons.logOut,
    'Transaction Limits': DPIcons.slidersHorizontal,
  };
;

  // Define vibrant colors for different icons
;

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
    showDPDialog(
      context,
      tone: DPDialogTone.info,
      icon: DPIcons.download,
      title: 'Update available',
      message: 'Version $_latestVersion is ready. You’re on $_appVersion. Update to get the latest improvements.',
      primaryLabel: 'Update now',
      onPrimary: () async {
        Navigator.pop(context);
        await UpdateService.openPlayStore(
          'https://play.google.com/store/apps/details?id=com.dalabapay.official',
        );
      },
      secondaryLabel: 'Later',
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.items.where((item) {
      if (item.isAdminOnly && !widget.isAdmin) return false;
      if (item.isUserOnly && widget.isAdmin) return false;
      return true;
    }).toList();

    return Drawer(
      width: 300,
      backgroundColor: DP.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(DP.rXl)),
      ),
      child: Column(
        children: [
          widget.header,
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final item = visible[index];
                final isSelected = item.title == widget.selectedItem.title;
                final isLogout = item.title == 'Logout';
                final iconData = _iconMap[item.title] ?? DPIcons.circleUser;
                final fg = isLogout ? DP.danger : (isSelected ? DP.green : DP.ink2);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: isSelected ? DP.greenSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(DP.rMd),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(DP.rMd),
                      onTap: () => widget.onItemSelected(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Row(
                          children: [
                            DPIcon(iconData, size: 20, color: fg),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                isLogout ? 'Log out' : item.title,
                                style: DPText.body.copyWith(
                                  color: isLogout ? DP.danger : (isSelected ? DP.green : DP.ink),
                                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                                ),
                              ),
                            ),
                            if (item.badge != null && item.badge!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: DP.navy,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  item.badge!,
                                  style: DPText.small.copyWith(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Row(
                children: [
                  Text('Dalabapay · Version $_appVersion', style: DPText.small),
                  if (_isLoadingVersion) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ],
                  const Spacer(),
                  if (!_isLoadingVersion && _hasUpdate)
                    DPLinkButton(label: 'Update', onPressed: () => _showUpdateDialog(context)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}