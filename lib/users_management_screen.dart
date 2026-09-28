import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UsersManagementScreen extends StatefulWidget {
  const UsersManagementScreen({super.key});

  @override
  State<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends State<UsersManagementScreen> {
  String searchText = '';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة الحسابات'),
          centerTitle: true,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                onChanged: (value) {
                  setState(() {
                    searchText = value.trim().toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'بحث بالاسم أو الإيميل أو الهاتف',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .orderBy('name')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'حدث خطأ: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  final users = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;

                    // لا نعرض حسابات الأدمن ضمن العملاء
                    if (data['role'] == 'admin') {
                      return false;
                    }

                    final name = (data['name'] ?? '').toString().toLowerCase();
                    final email =
                        (data['email'] ?? '').toString().toLowerCase();
                    final phone =
                        (data['phone'] ?? '').toString().toLowerCase();

                    if (searchText.isEmpty) {
                      return true;
                    }

                    return name.contains(searchText) ||
                        email.contains(searchText) ||
                        phone.contains(searchText);
                  }).toList();

                  if (users.isEmpty) {
                    return const Center(
                      child: Text(
                        'لا يوجد حسابات',
                        style: TextStyle(fontSize: 16),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final doc = users[index];
                      final data = doc.data() as Map<String, dynamic>;

                      final name = data['name'] ?? 'بدون اسم';
                      final email = data['email'] ?? '';
                      final phone = data['phone'] ?? '';
                      final isBlocked = data['isBlocked'] == true;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            radius: 25,
                            child: Icon(
                              isBlocked ? Icons.block : Icons.person,
                            ),
                          ),
                          title: Text(
                            name.toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (email.toString().isNotEmpty)
                                Text(email.toString()),
                              if (phone.toString().isNotEmpty)
                                Text(phone.toString()),
                              const SizedBox(height: 4),
                              Text(
                                isBlocked ? 'الحساب محظور' : 'الحساب فعال',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isBlocked ? Colors.red : Colors.green,
                                ),
                              ),
                            ],
                          ),
                          trailing: const Icon(
                            Icons.arrow_back_ios_new,
                            size: 18,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UserDetailsScreen(
                                  userId: doc.id,
                                  userData: data,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UserDetailsScreen extends StatelessWidget {
  final String userId;
  final Map<String, dynamic> userData;

  const UserDetailsScreen({
    super.key,
    required this.userId,
    required this.userData,
  });

  Future<void> _changeBlockStatus(
    BuildContext context,
    bool block,
  ) async {
    final action = block ? 'حظر' : 'رفع الحظر';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('$action الحساب؟'),
          content: Text(
            block
                ? 'هل أنت متأكد من حظر هذا الحساب؟'
                : 'هل أنت متأكد من رفع الحظر عن هذا الحساب؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'isBlocked': block,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              block ? 'تم حظر الحساب' : 'تم رفع الحظر عن الحساب',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = userData['name'] ?? 'بدون اسم';
    final email = userData['email'] ?? '';
    final phone = userData['phone'] ?? '';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('بيانات العميل'),
          centerTitle: true,
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .snapshots(),
          builder: (context, userSnapshot) {
            final currentData =
                userSnapshot.data?.data() as Map<String, dynamic>?;

            final currentIsBlocked = currentData?['isBlocked'] == true;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 42,
                          child: Icon(
                            currentIsBlocked ? Icons.block : Icons.person,
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          name.toString(),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _infoRow(
                          Icons.email,
                          'الإيميل',
                          email.toString(),
                        ),
                        _infoRow(
                          Icons.phone,
                          'الهاتف',
                          phone.toString(),
                        ),
                        _infoRow(
                          currentIsBlocked ? Icons.block : Icons.check_circle,
                          'الحالة',
                          currentIsBlocked ? 'محظور' : 'فعال',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _changeBlockStatus(
                        context,
                        !currentIsBlocked,
                      );
                    },
                    icon: Icon(
                      currentIsBlocked ? Icons.lock_open : Icons.block,
                    ),
                    label: Text(
                      currentIsBlocked ? 'رفع الحظر' : 'حظر الحساب',
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'جلسات العميل',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('appointments')
                      .where('userId', isEqualTo: userId)
                      .orderBy('date', descending: true)
                      .snapshots(),
                  builder: (context, appointmentSnapshot) {
                    if (appointmentSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(30),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    if (appointmentSnapshot.hasError) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'تعذر تحميل الجلسات:\n${appointmentSnapshot.error}',
                          ),
                        ),
                      );
                    }

                    final appointments = appointmentSnapshot.data?.docs ?? [];

                    if (appointments.isEmpty) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: Text(
                              'لا توجد جلسات لهذا العميل',
                            ),
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: appointments.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;

                        final date = data['date'] as Timestamp?;
                        final status = data['status'] ?? 'pending';
                        final notes = data['notes'] ?? '';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.calendar_month,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        date == null
                                            ? 'تاريخ غير محدد'
                                            : _formatDate(
                                                date.toDate(),
                                              ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _statusText(status.toString()),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _statusColor(status.toString()),
                                  ),
                                ),
                                if (notes.toString().trim().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'ملاحظات: ${notes.toString()}',
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _infoRow(
    IconData icon,
    String title,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 10),
          Text(
            '$title: ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} - '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  static String _statusText(String status) {
    switch (status) {
      case 'approved':
        return 'تم قبول الموعد';
      case 'rejected':
        return 'تم رفض الموعد';
      default:
        return 'قيد المراجعة';
    }
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }
}
