import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const settings = InitializationSettings(
      android: androidSettings,
    );

    await _notifications.initialize(settings);

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> scheduleAppointmentReminder({
    required String appointmentId,
    required DateTime appointmentDate,
  }) async {
    final now = DateTime.now();

    final reminderDate = appointmentDate.subtract(const Duration(hours: 24));

    print('الآن: $now');
    print('موعد الإشعار: $reminderDate');
    print('موعد الحجامة: $appointmentDate');

// تجاهل الموعد إذا انتهى
    if (appointmentDate.isBefore(now)) {
      return;
    }

// تجاهل الموعد إذا كان وقت التذكير قد فات
    if (reminderDate.isBefore(now)) {
      return;
    }

    await _notifications.zonedSchedule(
      appointmentId.hashCode,
      'تذكير بموعد الحجامة ⏰',
      'لديك جلسة حجامة غدًا الساعة ${_formatTime(appointmentDate)}. ننتظرك 🌹',
      tz.TZDateTime.from(reminderDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'appointment_reminders',
          'تذكيرات المواعيد',
          channelDescription: 'تنبيهات تذكير العميل بموعد جلسة الحجامة',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: appointmentId,
    );
    print('تمت جدولة الإشعار بنجاح للساعة: $reminderDate');
  }

  static String _formatTime(DateTime date) {
    final minute = date.minute.toString().padLeft(2, '0');

    final period = date.hour >= 12 ? 'مساءً' : 'صباحًا';

    final displayHour = date.hour == 0
        ? 12
        : date.hour > 12
            ? date.hour - 12
            : date.hour;

    return '$displayHour:$minute $period';
  }
}
