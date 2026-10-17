// lib/core/services/permission_service.dart
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> requestStoragePermission() async {
    if (await Permission.storage.isGranted) {
      return true;
    }

    final status = await Permission.storage.request();
    return status.isGranted;
  }

  static Future<bool> requestCameraPermission() async {
    if (await Permission.camera.isGranted) {
      return true;
    }

    final status = await Permission.camera.request();
    return status.isGranted;
  }

  static Future<bool> requestNotificationPermission() async {
    if (await Permission.notification.isGranted) {
      return true;
    }

    final status = await Permission.notification.request();
    return status.isGranted;
  }

  static Future<Map<String, bool>> checkAllPermissions() async {
    return {
      'storage': await Permission.storage.isGranted,
      'camera': await Permission.camera.isGranted,
      'notifications': await Permission.notification.isGranted,
    };
  }
}
