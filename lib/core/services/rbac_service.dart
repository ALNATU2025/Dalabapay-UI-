// lib/core/services/rbac_service.dart
// COMPLETE RBAC SERVICE - COPY AND PASTE THIS ENTIRE FILE

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RbacService {
  static const String baseUrl = 'https://vtpass-backend.onrender.com';

  // ==================== SINGLE RBAC ENDPOINT ====================

  static Future<Map<String, dynamic>> callRbac({
    required String operation,
    String? targetUserId,
    String? role,
    List<String>? permissions,
    String? resource,
    String? action,
    String? checkPermission,
    String? resourceId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        return {
          'success': false,
          'message': 'Authentication required',
          'code': 'AUTH_REQUIRED',
        };
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/rbac'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'operation': operation,
          'targetUserId': targetUserId,
          'role': role,
          'permissions': permissions,
          'resource': resource,
          'action': action,
          'checkPermission': checkPermission,
          'resourceId': resourceId,
        }),
      );

      final data = jsonDecode(response.body);
      return data;
    } catch (e) {
      return {
        'success': false,
        'message': 'Error calling RBAC API: ${e.toString()}',
        'code': 'RBAC_ERROR',
      };
    }
  }

  // ==================== HELPER METHODS ====================

  /// Get all roles and their permissions (Admin+)
  static Future<Map<String, dynamic>> getRoles() async {
    return await callRbac(operation: 'get_roles');
  }

  /// Get specific role details (Admin+)
  static Future<Map<String, dynamic>> getRole(String role) async {
    return await callRbac(operation: 'get_role', role: role);
  }

  /// Assign role to user (Super Admin only)
  static Future<Map<String, dynamic>> assignRole(
    String userId,
    String role,
  ) async {
    return await callRbac(
      operation: 'assign_role',
      targetUserId: userId,
      role: role,
    );
  }

  /// Remove role from user (Super Admin only)
  static Future<Map<String, dynamic>> removeRole(String userId) async {
    return await callRbac(operation: 'remove_role', targetUserId: userId);
  }

  /// Get user's role and permissions (Self/Admin)
  static Future<Map<String, dynamic>> getUserRole([String? userId]) async {
    return await callRbac(operation: 'get_user_role', targetUserId: userId);
  }

  /// Check if user has permission (Self/Admin)
  static Future<Map<String, dynamic>> checkPermission(
    String permission, [
    String? userId,
  ]) async {
    return await callRbac(
      operation: 'check_permission',
      checkPermission: permission,
      targetUserId: userId,
    );
  }

  /// Get users by role (Admin+)
  static Future<Map<String, dynamic>> getUsersByRole([String? role]) async {
    return await callRbac(operation: 'get_users_by_role', role: role);
  }

  /// Update user permissions (Super Admin only)
  static Future<Map<String, dynamic>> updatePermissions(
    String userId,
    List<String> permissions,
  ) async {
    return await callRbac(
      operation: 'update_permissions',
      targetUserId: userId,
      permissions: permissions,
    );
  }

  /// Get all available permissions (Admin+)
  static Future<Map<String, dynamic>> getAvailablePermissions() async {
    return await callRbac(operation: 'get_available_permissions');
  }

  /// Get role statistics (Admin+)
  static Future<Map<String, dynamic>> getRoleStats() async {
    return await callRbac(operation: 'get_role_stats');
  }

  /// Check if user can access resource (Self/Admin)
  static Future<Map<String, dynamic>> canAccess(
    String resource,
    String action, [
    String? userId,
  ]) async {
    return await callRbac(
      operation: 'can_access',
      resource: resource,
      action: action,
      targetUserId: userId,
    );
  }
}
