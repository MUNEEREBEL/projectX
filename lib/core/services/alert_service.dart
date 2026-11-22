import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';
import '../../models/document_model.dart';
import '../../models/expiry_alert.dart';
import '../database/database_service.dart';

class AlertService {
  static final AlertService instance = AlertService._internal();
  AlertService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  static const _uuid = Uuid();

  Future<void> init() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification click
      },
    );

    _isInitialized = true;
  }

  /// Schedules notifications for a document's expiry date at 60, 30, 7, and 1 day before.
  Future<void> scheduleDocumentExpiryAlerts(DocumentModel doc, String personName) async {
    if (doc.expiryDate == null) return;
    await init();

    final db = DatabaseService.instance;
    final now = DateTime.now();
    final expiry = doc.expiryDate!;

    final milestones = [60, 30, 7, 1];
    List<ExpiryAlert> alertsToSave = [];

    for (final days in milestones) {
      final scheduledDate = expiry.subtract(Duration(days: days));

      // Only schedule if scheduledDate is in the future
      if (scheduledDate.isAfter(now)) {
        final alertId = _uuid.v4();
        final notificationId = alertId.hashCode.abs() % 100000;

        alertsToSave.add(
          ExpiryAlert(
            id: alertId,
            documentId: doc.id,
            personName: personName,
            documentTitle: doc.title,
            expiryDate: expiry,
            daysBefore: days,
            scheduledAt: scheduledDate,
          ),
        );

        if (Platform.isAndroid) {
          try {
            await _notifications.zonedSchedule(
              notificationId,
              '⚠️ Renewal Alert: ${doc.title}',
              'Expiring in $days days on ${_formatDate(expiry)} for $personName. Tap to review.',
              tz.TZDateTime.from(scheduledDate, tz.local),
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'expiry_alerts_channel',
                  'Document Expiry Alerts',
                  channelDescription: 'Notifications for document renewals and validity',
                  importance: Importance.high,
                  priority: Priority.high,
                ),
              ),
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
          } catch (e) {
            // In case exact alarm permission is restricted
          }
        }
      }
    }

    if (alertsToSave.isNotEmpty) {
      await db.saveAlerts(alertsToSave);
    }
  }

  Future<void> showQuickNotification({required String title, required String body}) async {
    await init();
    const androidDetails = AndroidNotificationDetails(
      'general_alerts_channel',
      'PrivDoc Notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      const NotificationDetails(android: androidDetails),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}
