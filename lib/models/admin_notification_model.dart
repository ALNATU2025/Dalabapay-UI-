// lib/models/admin_notification_model.dart

class AdminNotificationModel {
  final String id;
  final String type;
  final String title;
  final String message;
  final String severity;
  final String? userId;
  final String? userName;
  final String? userEmail;
  final String? userPhone;
  final String? transactionId;
  final String? transactionReference;
  final String? transactionType;
  final double? amount;
  final String? status;
  final bool isRead;
  final DateTime createdAt;

  AdminNotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.severity,
    this.userId,
    this.userName,
    this.userEmail,
    this.userPhone,
    this.transactionId,
    this.transactionReference,
    this.transactionType,
    this.amount,
    this.status,
    required this.isRead,
    required this.createdAt,
  });

  factory AdminNotificationModel.fromJson(Map<String, dynamic> json) {
    return AdminNotificationModel(
      id: json['_id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'unknown',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      severity: json['severity']?.toString() ?? 'info',
      userId: json['userId']?.toString(),
      userName: json['userName']?.toString(),
      userEmail: json['userEmail']?.toString(),
      userPhone: json['userPhone']?.toString(),
      transactionId: json['transactionId']?.toString(),
      transactionReference: json['transactionReference']?.toString(),
      transactionType: json['transactionType']?.toString(),
      amount: json['amount'] != null
          ? (json['amount'] as num).toDouble()
          : null,
      status: json['status']?.toString(),
      isRead: json['isRead'] == true,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'].toString())
          : DateTime.now(),
    );
  }
}