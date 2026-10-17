// lib/core/widgets/drawer_item.dart
import 'package:flutter/material.dart';

class DrawerItem {
  final String title;
  final IconData icon;
  final String? badge;
  final Widget page;
  final bool isAdminOnly;
  final bool isUserOnly;

  const DrawerItem({
    required this.title,
    required this.icon,
    this.badge,
    required this.page,
    this.isAdminOnly = false,
    this.isUserOnly = false,
  });
}
