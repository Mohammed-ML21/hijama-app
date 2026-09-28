import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PendingAppointmentsScreen extends StatelessWidget {
  const PendingAppointmentsScreen({super.key});

  Future<void> updateAppointment(
    String appointmentId,
    String status,
  ) async {
    final appointmentRef = FirebaseFirestore.instance
        .collection('appointments')
        .doc(appointmentId);

    final appointment = await appointmentRef.get();

    if (!appointment.exists) return;

    final data = appointment.data();

    if (data == null) return;

    final userId = data['userId'];

    await appointmentRef.update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance
        .collection('notifications')
        .add({
      'userId': userId,
      'title': status == 'approved'
          ? 'تم قبول موعدك ✅'
          : 'تم رفض موعدك',
      'message': status == 'approved'
          ? 'تم قبول موعد الحجامة الخاص بك. ننتظرك في الموعد المحدد.'
          : 'نعتذر، تم رفض موعد الحجامة الخاص بك.',
      'appointmentId': appointmentId,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الطلبات قيد الانتظار'),
          centerTitle: true,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('appointments')
              .where('status', isEqualTo: 'pending')
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
                    'حدث خطأ أثناء تحميل الطلبات:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final appointments = snapshot.data?.docs ?? [];

            if (appointments.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.event_available,
                      size: 70,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 15),
                    Text(
                      'لا توجد طلبات حجز معلقة',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: appointments.length,
              itemBuilder: (context, index) {
                final doc = appointments[index];

                final data =
                    doc.data() as Map<String, dynamic>;

                final name = data['name'] ?? '';
                final phone = data['phone'] ?? '';
                final notes = data['notes'] ?? '';

                final timestamp =
                    data['date'] as Timestamp?;

                final appointmentDate =
                    timestamp?.toDate();

                String dateText = 'غير محدد';
                String timeText = '';

                if (appointmentDate != null) {
                  dateText =
                      '${appointmentDate.day}/${appointmentDate.month}/${appointmentDate.year}';

                  timeText =
                      '${appointmentDate.hour.toString().padLeft(2, '0')}:${appointmentDate.minute.toString().padLeft(2, '0')}';
                }

                return Card(
                  margin:
                      const EdgeInsets.only(bottom: 15),
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(18),
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
                              backgroundColor:
                                  Color(0xFFFFEBEE),
                              child: Icon(
                                Icons.person,
                                color: Color(0xFFB71C1C),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                name.toString(),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 15),

                        Text(
                          '📞 الهاتف: $phone',
                          style:
                              const TextStyle(fontSize: 16),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          '📅 التاريخ: $dateText',
                          style:
                              const TextStyle(fontSize: 16),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          '⏰ الوقت: $timeText',
                          style:
                              const TextStyle(fontSize: 16),
                        ),

                        if (notes
                            .toString()
                            .isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            '📝 الملاحظات: $notes',
                            style: const TextStyle(
                              fontSize: 16,
                            ),
                          ),
                        ],

                        const SizedBox(height: 18),

                        Row(
                          children: [
                            Expanded(
                              child:
                                  ElevatedButton.icon(
                                onPressed: () async {
                                  try {
                                    await updateAppointment(
                                      doc.id,
                                      'approved',
                                    );

                                    if (!context.mounted) {
                                      return;
                                    }

                                    ScaffoldMessenger.of(
                                            context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'تم قبول الموعد بنجاح ✅',
                                        ),
                                      ),
                                    );
                                  } catch (e) {
                                    if (!context.mounted) {
                                      return;
                                    }

                                    ScaffoldMessenger.of(
                                            context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'تعذر قبول الموعد: $e',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                icon:
                                    const Icon(Icons.check),
                                label:
                                    const Text('قبول'),
                                style:
                                    ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Colors.green,
                                  foregroundColor:
                                      Colors.white,
                                ),
                              ),
                            ),

                            const SizedBox(width: 10),

                            Expanded(
                              child:
                                  ElevatedButton.icon(
                                onPressed: () async {
                                  try {
                                    await updateAppointment(
                                      doc.id,
                                      'rejected',
                                    );

                                    if (!context.mounted) {
                                      return;
                                    }

                                    ScaffoldMessenger.of(
                                            context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'تم رفض الموعد',
                                        ),
                                      ),
                                    );
                                  } catch (e) {
                                    if (!context.mounted) {
                                      return;
                                    }

                                    ScaffoldMessenger.of(
                                            context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'تعذر رفض الموعد: $e',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                icon:
                                    const Icon(Icons.close),
                                label:
                                    const Text('رفض'),
                                style:
                                    ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Colors.red,
                                  foregroundColor:
                                      Colors.white,
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
}