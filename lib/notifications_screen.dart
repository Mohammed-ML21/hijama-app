import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
Set<String> _hiddenNotificationIds = {};

Future<void> _loadHiddenNotifications() async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) return;

  final prefs = await SharedPreferences.getInstance();

  final hiddenIds =
      prefs.getStringList('hidden_notifications_${user.uid}') ?? [];

  if (!mounted) return;

  setState(() {
    _hiddenNotificationIds = hiddenIds.toSet();
  });
}

@override
void initState() {
  super.initState();
  _loadHiddenNotifications();
}
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
       appBar: AppBar(
  title: const Text('الإشعارات'),
  centerTitle: true,
  actions: [
    IconButton(
      tooltip: 'إخفاء الإشعارات القديمة',
      icon: const Icon(Icons.delete_sweep_outlined),
      onPressed: () async {
        final user = FirebaseAuth.instance.currentUser;

        if (user == null) return;

        final snapshot = await FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: user.uid)
            .get();

        final now = DateTime.now();

        final oldNotificationIds = snapshot.docs.where((doc) {
          final data = doc.data();

          final timestamp = data['createdAt'] as Timestamp?;

          if (timestamp == null) return false;

          return timestamp.toDate().isBefore(now);
        }).map((doc) => doc.id).toList();

        if (oldNotificationIds.isEmpty) {
          if (!context.mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا توجد إشعارات قديمة لإخفائها'),
            ),
          );

          return;
        }

        final prefs = await SharedPreferences.getInstance();

        final hiddenIds =
            prefs.getStringList('hidden_notifications_${user.uid}') ?? [];

        final updatedIds = {
          ...hiddenIds,
          ...oldNotificationIds,
        }.toList();

        await prefs.setStringList(
          'hidden_notifications_${user.uid}',
          updatedIds,
        );

        if (!context.mounted) return;

        setState(() {
          _hiddenNotificationIds.addAll(oldNotificationIds);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إخفاء ${oldNotificationIds.length} إشعار قديم من جهازك',
            ),
          ),
        );
      },
    ),
  ],
),
        body: user == null
            ? const Center(
                child: Text('يجب تسجيل الدخول أولاً'),
              )
            : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('notifications')
                    .where('userId', isEqualTo: user.uid)
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'خطأ:\n${snapshot.error}',
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    );
                  }

                  final allNotifications = snapshot.data?.docs ?? [];

final notifications = allNotifications.where((doc) {
  return !_hiddenNotificationIds.contains(doc.id);
}).toList();
                  for (final notification in notifications) {
                    final data = notification.data() as Map<String, dynamic>;

                    if (data['isRead'] == false) {
                      FirebaseFirestore.instance
                          .collection('notifications')
                          .doc(notification.id)
                          .update({
                        'isRead': true,
                      });
                    }
                  }

                  if (notifications.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notifications_none,
                            size: 70,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 15),
                          Text(
                            'لا توجد إشعارات حالياً',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final data =
                          notifications[index].data() as Map<String, dynamic>;

                      final title = data['title'] ?? 'إشعار';
                      final message = data['message'] ?? '';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFB71C1C),
                            child: Icon(
                              Icons.notifications,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(message),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}
