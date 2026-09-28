import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CancellationRequestsScreen extends StatelessWidget {
  const CancellationRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('طلبات إلغاء المواعيد'),
          centerTitle: true,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('appointments')
              .where(
                'status',
                isEqualTo: 'cancellationRequested',
              )
              .orderBy('date')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState ==
                ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'تعذر تحميل طلبات الإلغاء:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final requests = snapshot.data?.docs ?? [];

            if (requests.isEmpty) {
              return const Center(
                child: Text(
                  'لا توجد طلبات إلغاء حاليًا',
                  style: TextStyle(fontSize: 17),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              itemBuilder: (context, index) {
                final doc = requests[index];
                final data =
                    doc.data() as Map<String, dynamic>;

                final name = data['name'] ?? 'بدون اسم';
                final phone = data['phone'] ?? '';
                final notes = data['notes'] ?? '';
                final date = data['date'] as Timestamp?;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              child: Icon(Icons.person),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                name.toString(),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        if (date != null)
                          _InfoRow(
                            icon: Icons.calendar_month,
                            text: _formatDate(date.toDate()),
                          ),

                        if (phone.toString().isNotEmpty)
                          _InfoRow(
                            icon: Icons.phone,
                            text: phone.toString(),
                          ),

                        if (notes.toString().trim().isNotEmpty)
                          _InfoRow(
                            icon: Icons.notes,
                            text: notes.toString(),
                          ),

                        const SizedBox(height: 14),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius:
                                BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.warning_amber,
                                color: Colors.orange,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'طلب إلغاء بانتظار الموافقة',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  _approveCancellation(
                                    context,
                                    doc.id,
                                    data,
                                  );
                                },
                                icon: const Icon(
                                  Icons.check,
                                ),
                                label: const Text(
                                  'موافقة',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  _rejectCancellation(
                                    context,
                                    doc.id,
                                  );
                                },
                                icon: const Icon(
                                  Icons.close,
                                ),
                                label: const Text(
                                  'رفض الطلب',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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

  Future<void> _approveCancellation(
    BuildContext context,
    String appointmentId,
    Map<String, dynamic> data,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تأكيد إلغاء الموعد'),
          content: const Text(
            'هل أنت متأكد من الموافقة على إلغاء هذا الموعد؟',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('موافقة'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final userId = data['userId'];

      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(appointmentId)
          .update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('notifications')
          .add({
        'userId': userId,
        'title': 'تم إلغاء الموعد',
        'message':
            'تمت الموافقة على طلب إلغاء موعد الحجامة الخاص بك.',
        'appointmentId': appointmentId,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم إلغاء الموعد وإبلاغ العميل',
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

  Future<void> _rejectCancellation(
    BuildContext context,
    String appointmentId,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(appointmentId)
          .update({
        'status': 'approved',
        'cancellationRequestedAt': FieldValue.delete(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم رفض طلب الإلغاء وإبقاء الموعد',
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

  static String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} - '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text),
          ),
        ],
      ),
    );
  }
}