import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UpcomingAppointmentsScreen extends StatelessWidget {
  const UpcomingAppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final now = Timestamp.now();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المواعيد القادمة'),
          centerTitle: true,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('appointments')
              .where('status', isEqualTo: 'approved')
              .where('date', isGreaterThan: now)
              .orderBy('date')
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
                    'تعذر تحميل المواعيد:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final appointments = snapshot.data?.docs ?? [];

            if (appointments.isEmpty) {
              return const Center(
                child: Text(
                  'لا توجد مواعيد قادمة حاليًا',
                  style: TextStyle(fontSize: 17),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: appointments.length,
              itemBuilder: (context, index) {
                final doc = appointments[index];
                final data = doc.data() as Map<String, dynamic>;

                final name = data['name'] ?? 'بدون اسم';
                final phone = data['phone'] ?? '';
                final notes = data['notes'] ?? '';
                final date = data['date'] as Timestamp?;

                if (date == null) {
                  return const SizedBox.shrink();
                }

                final appointmentDate = date.toDate();

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                        _InfoRow(
                          icon: Icons.calendar_month,
                          text: _formatDate(appointmentDate),
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
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.green.withOpacity(0.1),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'تم تأكيد الموعد',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
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
