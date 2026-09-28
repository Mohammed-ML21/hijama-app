import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notifications_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'users_management_screen.dart';
import 'upcoming_appointments_screen.dart';
import 'cancellation_requests_screen.dart';
import 'pending_appointments_screen.dart';
import 'notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
Future<void> scheduleApprovedAppointmentReminders() async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) return;

  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('appointments')
        .where('userId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'approved')
        .get();
    print('عدد المواعيد المقبولة: ${snapshot.docs.length}');
    for (final doc in snapshot.docs) {
      final data = doc.data();

      final timestamp = data['date'] as Timestamp?;

      if (timestamp == null) continue;
      print('جدولة تذكير للموعد: ${doc.id}');
      await NotificationService.scheduleAppointmentReminder(
        appointmentId: doc.id,
        appointmentDate: timestamp.toDate(),
      );
    }
  } catch (e) {
    debugPrint(
      'خطأ في جدولة تذكيرات المواعيد: $e',
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  await NotificationService.initialize();

  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final notification = message.notification;

    if (notification != null) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Row(
            children: [
              const Icon(
                Icons.notifications_active,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title ?? 'إشعار جديد',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (notification.body != null) Text(notification.body!),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  });

  runApp(const HijamaApp());
}

class HijamaApp extends StatelessWidget {
  const HijamaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'حجامة',

      // ✅ دعم التعريب
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar', 'AE'), Locale('ar'), Locale('en')],
      locale: const Locale('ar'),

      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Arial',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB71C1C)),
      ),
      home: const AuthGate(),
    );
  }
}
// ======================================================
// بوابة تسجيل الدخول
// ======================================================

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Future<void> saveFcmToken(User user) async {
    final token = await FirebaseMessaging.instance.getToken();

    if (token == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'fcmToken': token,
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        print('AUTH STATE: ${snapshot.data?.email}');

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasData) {
          final user = snapshot.data!;

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .snapshots(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (userSnapshot.hasError) {
                return const Scaffold(
                  body: Center(
                    child: Text(
                      'تعذر التحقق من حالة الحساب',
                    ),
                  ),
                );
              }

              final data = userSnapshot.data?.data() as Map<String, dynamic>?;

              final isBlocked = data?['isBlocked'] == true;

              if (isBlocked) {
                return const BlockedAccountScreen();
              }

              saveFcmToken(user);
              scheduleApprovedAppointmentReminders();
              return const HomeScreen();
            },
          );
        }

        return const LoginScreen();
      },
    );
  }
}

class BlockedAccountScreen extends StatelessWidget {
  const BlockedAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const LoginScreen();
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final data = snapshot.data?.data() as Map<String, dynamic>?;

        final isBlocked = data?['isBlocked'] == true;

        // إذا رفع الكوتش الحظر
        // نرجع للـ AuthGate حتى يدخل المستخدم للتطبيق
        if (!isBlocked) {
          return const AuthGate();
        }

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.block,
                      size: 90,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'تم حظر حسابك',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'لا يمكنك استخدام التطبيق حاليًا.\n'
                      'يرجى التواصل مع الكوتش عبود لمزيد من المعلومات.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('تسجيل الخروج'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;
  bool obscurePassword = true;

  Future<void> login() async {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال البريد الإلكتروني وكلمة المرور'),
        ),
      );
      return;
    }

    setState(() => loading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      // لا نستخدم Navigator هنا.
      // AuthGate سينقل المستخدم تلقائيًا إلى الواجهة الرئيسية.
    } on FirebaseAuthException catch (e) {
      String message = 'حدث خطأ أثناء تسجيل الدخول';

      if (e.code == 'user-not-found') {
        message = 'لا يوجد حساب بهذا البريد الإلكتروني';
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'البريد الإلكتروني أو كلمة المرور غير صحيحة';
      } else if (e.code == 'invalid-email') {
        message = 'البريد الإلكتروني غير صحيح';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(
                    Icons.health_and_safety,
                    size: 80,
                    color: Color(0xFFB71C1C),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'حجامة',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB71C1C),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'تسجيل الدخول',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 35),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      prefixIcon: const Icon(Icons.email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: loading ? null : login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB71C1C),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: loading
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                            )
                          : const Text(
                              'تسجيل الدخول',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RegisterScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      'ليس لديك حساب؟ إنشاء حساب جديد',
                      style: TextStyle(
                        color: Color(0xFFB71C1C),
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool loading = false;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;

  Future<void> register() async {
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final phone = phoneController.text.trim();
    final password = passwordController.text;
    final confirmPassword = confirmPasswordController.text;

    if (name.isEmpty ||
        email.isEmpty ||
        phone.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تعبئة جميع الحقول'),
        ),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('كلمة المرور يجب أن تكون 6 أحرف على الأقل'),
        ),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('كلمتا المرور غير متطابقتين'),
        ),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      await credential.user?.updateDisplayName(name);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
        'name': name,
        'email': email,
        'phone': phone,
        'role': 'client',
        'isBlocked': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إنشاء الحساب بنجاح'),
        ),
      );

      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      String message = 'حدث خطأ أثناء إنشاء الحساب';

      if (e.code == 'email-already-in-use') {
        message = 'هذا البريد الإلكتروني مستخدم مسبقًا';
      } else if (e.code == 'invalid-email') {
        message = 'البريد الإلكتروني غير صحيح';
      } else if (e.code == 'weak-password') {
        message = 'كلمة المرور ضعيفة';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إنشاء حساب'),
          backgroundColor: const Color(0xFFB71C1C),
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(
                  Icons.person_add_alt_1,
                  size: 70,
                  color: Color(0xFFB71C1C),
                ),
                const SizedBox(height: 15),
                const Text(
                  'إنشاء حساب جديد',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 25),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'الاسم الكامل',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'البريد الإلكتروني',
                    prefixIcon: const Icon(Icons.email),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'رقم الهاتف للتواصل',
                    prefixIcon: const Icon(Icons.phone),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'تأكيد كلمة المرور',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureConfirmPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          obscureConfirmPassword = !obscureConfirmPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: loading ? null : register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB71C1C),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: loading
                        ? const CircularProgressIndicator(
                            color: Colors.white,
                          )
                        : const Text(
                            'إنشاء الحساب',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
// ======================================================
// شاشة البداية
// ======================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _scaleAnimation = Tween<double>(
      begin: 0.75,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: const Color(0xFFB71C1C),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.25),
                        blurRadius: 25,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.water_drop,
                    color: Colors.white,
                    size: 65,
                  ),
                ),
                const SizedBox(height: 25),
                const Text(
                  'حجامة',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB71C1C),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'مع الكوتش عبود',
                  style: TextStyle(
                    fontSize: 20,
                    color: Color(0xFF333333),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 15),
                const Text(
                  'حجامة • لياقة بدنية • علاج تكميلي',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================
// الصفحة الرئيسية
// ======================================================

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<bool> isAdmin() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return false;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    return doc.exists && doc.data()?['role'] == 'admin';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        drawer: const AppDrawer(),
        backgroundColor: const Color(0xFFF8F8F8),
        appBar: AppBar(
          leading: Builder(
            builder: (context) {
              return IconButton(
                icon: const Icon(
                  Icons.menu,
                  color: Color(0xFFB71C1C),
                  size: 30,
                ),
                onPressed: () {
                  Scaffold.of(context).openDrawer();
                },
              );
            },
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'حجامة',
            style: TextStyle(
              color: Color(0xFFB71C1C),
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            FutureBuilder<bool>(
              future: isAdmin(),
              builder: (context, snapshot) {
                if (snapshot.data != true) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('notifications')
                        .where(
                          'userId',
                          isEqualTo: FirebaseAuth.instance.currentUser?.uid,
                        )
                        .where('isRead', isEqualTo: false)
                        .snapshots(),
                    builder: (context, notificationSnapshot) {
                      final unreadCount =
                          notificationSnapshot.data?.docs.length ?? 0;

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const NotificationsScreen(),
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.notifications_none,
                              color: Color(0xFFB71C1C),
                              size: 28,
                            ),
                          ),
                          if (unreadCount > 0)
                            Positioned(
                              right: 5,
                              top: 2,
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  unreadCount > 9 ? '9+' : '$unreadCount',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  );
                }

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'لوحة التحكم',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminDashboardScreen(),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.dashboard_outlined,
                        color: Color(0xFFB71C1C),
                        size: 28,
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(
                        Icons.notifications_none,
                        color: Color(0xFFB71C1C),
                        size: 28,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 310,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(25),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/images/coach.jpg',
                          fit: BoxFit.cover,
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.75),
                              ],
                            ),
                          ),
                        ),
                        const Positioned(
                          bottom: 20,
                          right: 20,
                          left: 20,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'الكوتش عبود',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                'مدرب لياقة بدنية ومتخصص في الحجامة',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 25),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'أهلاً بك 👋',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF222222),
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'اهتم بصحتك، وابدأ رحلتك معنا',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 65,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BookingScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB71C1C),
                      foregroundColor: Colors.white,
                      elevation: 5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_month, size: 27),
                        SizedBox(width: 12),
                        Text(
                          'احجز موعدك الآن',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 25),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'اكتشف خدماتنا',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF222222),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _HomeButton(
                icon: Icons.person_outline,
                title: 'عن الكوتش عبود',
                subtitle: 'تعرف على خبرتي وشهاداتي',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AboutScreen(),
                    ),
                  );
                },
              ),
              _HomeButton(
                icon: Icons.water_drop_outlined,
                title: 'فوائد الحجامة',
                subtitle: 'معلومات وإرشادات مهمة',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BenefitsScreen(),
                    ),
                  );
                },
              ),
              _HomeButton(
                icon: Icons.health_and_safety,
                title: 'الحالات التي قد تساعد الحجامة فيها',
                subtitle: 'معلومات عامة حول الحالات التي قد تستفيد من الحجامة',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ConditionsScreen(),
                    ),
                  );
                },
              ),
              _HomeButton(
                icon: Icons.health_and_safety_outlined,
                title: 'قبل وبعد الجلسة',
                subtitle: 'إرشادات تساعدك على الاستعداد',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BeforeAfterScreen(),
                    ),
                  );
                },
              ),
              _HomeButton(
                icon: Icons.event_note,
                title: 'مواعيدي',
                subtitle: 'الموعد القادم',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MyAppointmentsScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 25),
              const Text(
                'حجامة مع الكوتش عبود',
                style: TextStyle(
                  color: Color(0xFFB71C1C),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'حجامة • لياقة بدنية • علاج تكميلي',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  Future<bool> isAdmin() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return false;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    return doc.exists && doc.data()?['role'] == 'admin';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 25,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFFB71C1C),
              ),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 38,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.person,
                      size: 45,
                      color: Color(0xFFB71C1C),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.displayName?.isNotEmpty == true
                        ? user!.displayName!
                        : 'المستخدم',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    user?.email ?? '',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.calendar_month,
                color: Color(0xFFB71C1C),
              ),
              title: const Text('مواعيدي'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MyAppointmentsScreen(),
                  ),
                );
              },
            ),
            FutureBuilder<bool>(
              future: isAdmin(),
              builder: (context, snapshot) {
                if (snapshot.data != true) {
                  return const SizedBox.shrink();
                }

                return ListTile(
                  leading: const Icon(
                    Icons.dashboard_outlined,
                    color: Color(0xFFB71C1C),
                  ),
                  title: const Text('لوحة التحكم'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminDashboardScreen(),
                      ),
                    );
                  },
                );
              },
            ),
            const Divider(),
            const Spacer(),
            ListTile(
              leading: const Icon(
                Icons.logout,
                color: Colors.red,
              ),
              title: const Text(
                'تسجيل الخروج',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () async {
                final shouldLogout = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) {
                    return AlertDialog(
                      title: const Text('تسجيل الخروج'),
                      content: const Text(
                        'هل أنت متأكد أنك تريد تسجيل الخروج؟',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(dialogContext, false);
                          },
                          child: const Text('إلغاء'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(dialogContext, true);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFB71C1C),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('تسجيل الخروج'),
                        ),
                      ],
                    );
                  },
                );

                if (shouldLogout == true) {
                  await FirebaseAuth.instance.signOut();
                }
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  Future<void> updateAppointment(
    String appointmentId,
    String status,
  ) async {
    final appointmentRef = FirebaseFirestore.instance
        .collection('appointments')
        .doc(appointmentId);

    final appointment = await appointmentRef.get();

    if (!appointment.exists) {
      return;
    }

    final data = appointment.data();

    if (data == null) {
      return;
    }

    final userId = data['userId'];

    await appointmentRef.update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance.collection('notifications').add({
      'userId': userId,
      'title': status == 'approved' ? 'تم قبول موعدك ✅' : 'تم رفض موعدك',
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
          title: const Text('لوحة تحكم الكوتش'),
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.0,
            children: [
              _AdminButton(
                icon: Icons.pending_actions,
                title: 'الطلبات قيد الانتظار',
                color: Colors.orange,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PendingAppointmentsScreen(),
                    ),
                  );
                },
              ),
              _AdminButton(
                icon: Icons.event_available,
                title: 'المواعيد القادمة',
                color: Colors.green,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const UpcomingAppointmentsScreen(),
                    ),
                  );
                },
              ),
              _AdminButton(
                icon: Icons.event_busy,
                title: 'طلبات الإلغاء',
                color: Colors.red,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CancellationRequestsScreen(),
                    ),
                  );
                },
              ),
              _AdminButton(
                icon: Icons.people,
                title: 'إدارة الحسابات',
                color: Colors.blue,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const UsersManagementScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _AdminButton({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: color.withOpacity(0.12),
                child: Icon(
                  icon,
                  size: 32,
                  color: color,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ======================================================
// أزرار الصفحة الرئيسية
// ======================================================

class _HomeButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                // الأيقونة
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: const Color(0xFFB71C1C), size: 28),
                ),

                const SizedBox(width: 15),

                // النص
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF222222),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),

                // السهم
                const Icon(
                  Icons.arrow_back_ios_new,
                  color: Color(0xFFB71C1C),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F8F8),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'عن الكوتش عبود',
            style: TextStyle(
              color: Color(0xFFB71C1C),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 20),

              // الصورة
              Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFB71C1C), width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/coach.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),

              const SizedBox(height: 18),

              const Text(
                'الكوتش عبود',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB71C1C),
                ),
              ),

              const SizedBox(height: 5),

              const Text(
                'مدرب لياقة بدنية ومتخصص في الحجامة والعلاج التكميلي',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),

              const SizedBox(height: 25),

              // النبذة
              _InfoCard(
                title: 'نبذة عني',
                icon: Icons.person,
                child: const Text(
                  'أنا الكوتش عبود، مدرب لياقة بدنية ومتخصص في مجال الحجامة والعلاج التكميلي، حاصل على بكالوريوس في علوم الرياضة، بالإضافة إلى دورات وشهادات متخصصة في التدريب الشخصي، الحجامة، الوخز بالإبر والتغذية الرياضية.\n\n'
                  'أهتم بتقديم جلسات الحجامة بأسلوب منظم يعتمد على تقييم حالة الشخص واحتياجاته، مع التركيز على السلامة والنظافة واختيار المناطق المناسبة للجلسة.\n\n'
                  'من خلال هذا التطبيق، أسعى إلى تقديم تجربة أكثر تنظيمًا واحترافية في متابعة العملاء، وتوثيق الجلسات، وتقديم المعلومات والإرشادات المتعلقة بالحجامة والعناية قبل وبعد الجلسة.',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.9,
                    color: Color(0xFF333333),
                  ),
                ),
              ),

              const SizedBox(height: 15),

              // المؤهلات
              _InfoCard(
                title: 'المؤهلات والتخصصات',
                icon: Icons.school,
                child: Column(
                  children: const [
                    _QualificationItem(
                      icon: Icons.fitness_center,
                      text: 'بكالوريوس في علوم الرياضة',
                    ),
                    _QualificationItem(
                      icon: Icons.person,
                      text: 'تدريب شخصي ولياقة بدنية',
                    ),
                    _QualificationItem(icon: Icons.water_drop, text: 'الحجامة'),
                    _QualificationItem(
                      icon: Icons.medical_services_outlined,
                      text: 'الوخز بالإبر',
                    ),
                    _QualificationItem(
                      icon: Icons.restaurant,
                      text: 'التغذية الرياضية',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 15),

              // الشهادات
              _InfoCard(
                title: 'الشهادات والدورات',
                icon: Icons.workspace_premium,
                child: Column(
                  children: [
                    _CertificateImage(
                      image: 'assets/images/certificate1.jpg',
                      title: 'شهادة 1',
                    ),
                    _CertificateImage(
                      image: 'assets/images/certificate2.jpg',
                      title: 'شهادة 2',
                    ),
                    _CertificateImage(
                      image: 'assets/images/certificate3.jpg',
                      title: 'شهادة 3',
                    ),
                    _CertificateImage(
                      image: 'assets/images/certificate4.jpg',
                      title: 'شهادة 4',
                    ),
                    _CertificateImage(
                      image: 'assets/images/certificate5.jpg',
                      title: 'شهادة 5',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: const Color(0xFFB71C1C)),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB71C1C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _QualificationItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _QualificationItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFB71C1C), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CertificateImage extends StatelessWidget {
  final String image;
  final String title;

  const _CertificateImage({required this.image, required this.title});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CertificateViewer(image: image, title: title),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        height: 190,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(image, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class CertificateViewer extends StatelessWidget {
  final String image;
  final String title;

  const CertificateViewer({
    super.key,
    required this.image,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.asset(image, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class BenefitsScreen extends StatelessWidget {
  const BenefitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F8F8),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'فوائد الحجامة',
            style: TextStyle(
              color: Color(0xFFB71C1C),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _InfoCard(
              title: 'ما هي الحجامة؟',
              icon: Icons.water_drop,
              child: const Text(
                'الحجامة ممارسة من ممارسات الطب التكميلي، يتم خلالها استخدام كؤوس خاصة على الجلد. وفي الحجامة الرطبة يتم إجراء وخزات سطحية للجلد قبل وضع الكؤوس.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.8,
                  color: Color(0xFF333333),
                ),
              ),
            ),
            const SizedBox(height: 15),
            _BenefitCard(
              icon: Icons.self_improvement,
              title: 'الاسترخاء',
              text:
                  'قد يجد بعض الأشخاص أن جلسة الحجامة تساعدهم على الشعور بالاسترخاء والراحة.',
            ),
            _BenefitCard(
              icon: Icons.accessibility_new,
              title: 'الشعور بالراحة العضلية',
              text:
                  'قد يشعر بعض الأشخاص بتحسن مؤقت في الإحساس بالشد أو الانزعاج العضلي بعد الجلسة.',
            ),
            _BenefitCard(
              icon: Icons.favorite_outline,
              title: 'العناية والعافية',
              text:
                  'يمكن أن تكون الحجامة جزءًا من روتين العناية بالصحة والعافية لدى بعض الأشخاص، مع مراعاة الحالة الصحية لكل شخص.',
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3F3),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFFFCDD2)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFB71C1C)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'ملاحظة: الحجامة علاج تكميلي وليست بديلًا عن التشخيص أو العلاج الطبي. تختلف الاستجابة من شخص لآخر، ولا ينبغي اعتبارها علاجًا مؤكدًا لأي مرض.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.7,
                        color: Color(0xFF555555),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),
          ],
        ),
      ),
    );
  }
}

class _BenefitCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _BenefitCard({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFFB71C1C), size: 27),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF222222),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.7,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BeforeAfterScreen extends StatelessWidget {
  const BeforeAfterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F8F8),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'قبل وبعد الجلسة',
            style: TextStyle(
              color: Color(0xFFB71C1C),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _InfoCard(
              title: 'قبل الجلسة',
              icon: Icons.event_available,
              child: Column(
                children: const [
                  _InstructionItem(
                    text: 'احرص على الحصول على قسط كافٍ من الراحة.',
                  ),
                  _InstructionItem(
                    text:
                        'تناول وجبة مناسبة قبل الجلسة، وتجنب الوصول وأنت مرهق أو جائع جدًا.',
                  ),
                  _InstructionItem(
                    text: 'احرص على شرب كمية مناسبة من السوائل.',
                  ),
                  _InstructionItem(
                    text:
                        'أخبر مقدم الجلسة عن أي أدوية أو حالات صحية أو أمور قد تؤثر على ملاءمة الجلسة.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            _InfoCard(
              title: 'بعد الجلسة',
              icon: Icons.health_and_safety,
              child: Column(
                children: const [
                  _InstructionItem(text: 'خذ وقتًا للراحة بعد الجلسة.'),
                  _InstructionItem(
                      text:
                          'عدم تناول مشتقات الالبان والاجبان والحليب واللحوم الحمراء.'),
                  _InstructionItem(
                      text: 'يمنع الاستحمام بعد الحجامة لمدة 12 ساعة '),
                  _InstructionItem(
                    text:
                        'حافظ على نظافة مواضع الحجامة واتبع تعليمات العناية التي يقدمها لك المختص.',
                  ),
                  _InstructionItem(text: 'اشرب كمية مناسبة من السوائل.'),
                  _InstructionItem(
                    text:
                        'تجنب المجهود الشديد مباشرة بعد الجلسة إذا شعرت بالتعب أو الدوخة.',
                  ),
                  _InstructionItem(
                    text:
                        'من الطبيعي أن تظهر علامات مؤقتة على الجلد في مواضع الكؤوس.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'متى تطلب المساعدة؟',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB71C1C),
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'إذا ظهرت أعراض شديدة أو غير معتادة مثل نزيف مستمر، ألم شديد، تورم متزايد، علامات التهاب أو دوخة شديدة، يجب طلب التقييم الطبي المناسب.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.8,
                      color: Color(0xFF444444),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),
          ],
        ),
      ),
    );
  }
}

class _InstructionItem extends StatelessWidget {
  final String text;

  const _InstructionItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Color(0xFFB71C1C), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                height: 1.7,
                color: Color(0xFF333333),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  DateTime? selectedDate;
  TimeOfDay? selectedTime;

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final notesController = TextEditingController();

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> selectDate() async {
    final now = DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 90)),
      locale: const Locale('ar'),
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child!);
      },
    );

    if (date != null && mounted) {
      setState(() {
        selectedDate = date;
      });
    }
  }

  Future<void> selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: selectedTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child!);
      },
    );

    if (time != null && mounted) {
      setState(() {
        selectedTime = time;
      });
    }
  }

  Future<void> confirmBooking() async {
    if (nameController.text.trim().isEmpty ||
        phoneController.text.trim().isEmpty ||
        selectedDate == null ||
        selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تعبئة الاسم ورقم الهاتف واختيار الموعد'),
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب تسجيل الدخول أولًا'),
        ),
      );
      return;
    }

    try {
      final appointmentDateTime = DateTime(
        selectedDate!.year,
        selectedDate!.month,
        selectedDate!.day,
        selectedTime!.hour,
        selectedTime!.minute,
      );

      await FirebaseFirestore.instance.collection('appointments').add({
        'userId': user.uid,
        'name': nameController.text.trim(),
        'phone': phoneController.text.trim(),
        'email': user.email ?? '',
        'date': Timestamp.fromDate(appointmentDateTime),
        'notes': notesController.text.trim(),
        'durationMinutes': 15,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'reminderSent': false,
      });

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('تم إرسال طلب الحجز ✅'),
            content: const Text(
              'تم إرسال طلب موعدك بنجاح.\n'
              'سيتم مراجعة الطلب من الكوتش عبود وتأكيد الموعد.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                child: const Text('موافق'),
              ),
            ],
          );
        },
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر حفظ الحجز: ${e.message ?? 'حدث خطأ غير معروف'}',
          ),
        ),
      );
    }
  }

  String formatDate() {
    if (selectedDate == null) return 'اختر اليوم';

    return '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}';
  }

  String formatTime() {
    if (selectedTime == null) return 'اختر الوقت';

    return selectedTime!.format(context);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F8F8),
        appBar: AppBar(
          title: const Text(
            'حجز جلسة',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFFB71C1C),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'احجز موعدك مع الكوتش عبود',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'مدة الجلسة: 15 دقيقة',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 25),
              TextField(
                controller: nameController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'اسم العميل',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'رقم الهاتف',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'اختيار الموعد',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: selectDate,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_month,
                        color: Color(0xFFB71C1C),
                      ),
                      const SizedBox(width: 12),
                      Text(formatDate(), style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: selectTime,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, color: Color(0xFFB71C1C)),
                      const SizedBox(width: 12),
                      Text(formatTime(), style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'ملاحظات إضافية (اختياري)',
                  alignLabelWithHint: true,
                  prefixIcon: const Icon(Icons.note),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 25),
              ElevatedButton(
                onPressed: confirmBooking,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB71C1C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'تأكيد الحجز',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ConditionInfo {
  final String title;
  final String description;
  final String area;
  final bool medicalWarning;

  const ConditionInfo({
    required this.title,
    required this.description,
    required this.area,
    this.medicalWarning = false,
  });
}

class ConditionsScreen extends StatelessWidget {
  const ConditionsScreen({super.key});

  static const List<ConditionInfo> conditions = [
    ConditionInfo(
      title: 'خشونة الركبة ومشاكل الأربطة والغضاريف',
      description:
          'قد تُستخدم الحجامة كوسيلة تكميلية للمساعدة في تخفيف بعض الآلام العضلية والمفصلية وتحسين الشعور بالراحة.',
      area:
          'حول منطقة الركبة والعضلات المحيطة بها، ويحدد الموضع المناسب حسب التقييم.',
    ),
    ConditionInfo(
      title: 'عرق النسا وآلام أسفل الظهر',
      description:
          'قد تساعد الجلسة التكميلية في تخفيف بعض آلام أسفل الظهر والعضلات المحيطة.',
      area: 'أسفل الظهر ومناطق العضلات المحيطة، حسب تقييم الحالة.',
    ),
    ConditionInfo(
      title: 'مشاكل الرقبة والغضاريف العنقية',
      description:
          'قد تُستخدم للمساعدة في تخفيف بعض التوتر والآلام العضلية في منطقة الرقبة والكتفين.',
      area:
          'منطقة أعلى الظهر والكتفين والعضلات المحيطة بالرقبة، مع تجنب المواضع الخطرة.',
      medicalWarning: true,
    ),
    ConditionInfo(
      title: 'الربو وبعض مشاكل الجهاز التنفسي',
      description:
          'قد تُستخدم الحجامة كعلاج تكميلي لتحسين الاسترخاء والشعور العام، لكنها لا تستبدل أدوية الربو أو خطة الطبيب.',
      area: 'أعلى الظهر ومناطق الصدر المناسبة حسب التقييم.',
      medicalWarning: true,
    ),
    ConditionInfo(
      title: 'بعض مشاكل الجلد',
      description:
          'يمكن تقييم الحالة بشكل فردي، مع تجنب إجراء الحجامة على الجلد الملتهب أو المصاب أو المتضرر.',
      area: 'تُحدد حسب الحالة، ولا تُجرى مباشرة على المناطق الجلدية المصابة.',
      medicalWarning: true,
    ),
    ConditionInfo(
      title: 'ارتفاع ضغط الدم',
      description:
          'قد تكون الحجامة ممارسة تكميلية لدى بعض الأشخاص، لكنها ليست بديلًا عن علاج ضغط الدم ومتابعته.',
      area: 'تُحدد مواضع الجلسة بعد تقييم الحالة.',
      medicalWarning: true,
    ),
    ConditionInfo(
      title: 'البواسير والناسور',
      description:
          'تحتاج هذه الحالات إلى تشخيص طبي، ويمكن التفكير في الحجامة فقط كإجراء تكميلي بعيدًا عن المنطقة المصابة.',
      area: 'مناطق عامة بعيدة عن موضع الإصابة، حسب التقييم الطبي والمهني.',
      medicalWarning: true,
    ),
    ConditionInfo(
      title: 'بعض الحالات المرتبطة بالمناعة',
      description:
          'قد تُستخدم الحجامة ضمن ممارسات تكميلية لتحسين الاسترخاء والراحة، ولا تعتبر علاجًا لأمراض المناعة.',
      area: 'تُحدد حسب حالة الشخص وتاريخه الصحي.',
      medicalWarning: true,
    ),
    ConditionInfo(
      title: 'مرض السكري',
      description:
          'الحجامة لا تغني عن علاج السكري أو قياس السكر والمتابعة الطبية.',
      area:
          'تُحدد بعد تقييم الحالة، مع الانتباه إلى سلامة الجلد والتئام الجروح.',
      medicalWarning: true,
    ),
    ConditionInfo(
      title: 'مشاكل الكبد والمرارة',
      description:
          'قد تُناقش الحجامة كإجراء تكميلي، لكن أمراض الكبد والمرارة تحتاج أولًا إلى تشخيص ومتابعة طبية.',
      area: 'تُحدد المواضع المناسبة حسب التقييم.',
      medicalWarning: true,
    ),
    ConditionInfo(
      title: 'بعض آلام والتهابات الأعصاب',
      description:
          'قد تساعد في تخفيف بعض الآلام العضلية المصاحبة، لكن سبب ألم الأعصاب يجب تقييمه طبيًا.',
      area: 'على المناطق العضلية المرتبطة بالألم، حسب الحالة.',
      medicalWarning: true,
    ),
    ConditionInfo(
      title: 'آلام العضلات والتشنجات',
      description:
          'قد تساعد الحجامة بعض الأشخاص في الشعور بالراحة وتخفيف التوتر العضلي.',
      area: 'على العضلات المتأثرة أو المناطق المحيطة بها حسب التقييم.',
    ),
    ConditionInfo(
      title: 'مشاكل المعدة والهضم',
      description:
          'يمكن استخدام الحجامة كإجراء تكميلي لدى بعض الأشخاص، مع ضرورة معرفة سبب الأعراض المستمرة.',
      area:
          'مناطق عامة مناسبة حسب التقييم، وليس على المناطق التي تحتوي على جروح أو التهابات.',
      medicalWarning: true,
    ),
    ConditionInfo(
      title: 'القولون العصبي',
      description:
          'قد تساعد بعض الأشخاص على الاسترخاء وتخفيف بعض الأعراض المرتبطة بالتوتر، والاستجابة تختلف من شخص لآخر.',
      area: 'الظهر والمناطق العضلية المحيطة، حسب التقييم.',
    ),
    ConditionInfo(
      title: 'تأخر الإنجاب',
      description:
          'تأخر الإنجاب له أسباب متعددة ويحتاج إلى تقييم طبي للزوجين. الحجامة لا تُعد علاجًا مثبتًا للعقم.',
      area: 'تُحدد فقط كإجراء تكميلي وبعد تقييم الحالة.',
      medicalWarning: true,
    ),
    ConditionInfo(
      title: 'مشاكل الجيوب الأنفية',
      description:
          'قد تُستخدم الحجامة كوسيلة تكميلية للمساعدة في الشعور بالراحة، لكنها لا تستبدل علاج التهاب أو مشاكل الجيوب.',
      area: 'أعلى الظهر ومناطق عامة مناسبة حسب التقييم، وليس مباشرة على الوجه.',
      medicalWarning: true,
    ),
    ConditionInfo(
      title: 'العصب السابع والخامس',
      description:
          'هذه الحالات تحتاج إلى تشخيص السبب أولًا. يمكن مناقشة الحجامة كإجراء تكميلي فقط بعد التقييم المناسب.',
      area:
          'مناطق عضلية مناسبة حول الرأس والرقبة حسب الحالة، مع تجنب المناطق الحساسة.',
      medicalWarning: true,
    ),
    ConditionInfo(
      title: 'مشاكل القلب والدورة الدموية',
      description:
          'أمراض القلب تحتاج إلى متابعة طبية. لا تعتبر الحجامة بديلًا عن الأدوية أو العلاج الموصوف.',
      area: 'تُحدد فقط بعد تقييم الحالة والتأكد من ملاءمة الجلسة.',
      medicalWarning: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F8F8),
        appBar: AppBar(
          title: const Text(
            'الحالات التي قد تساعد الحجامة فيها',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFFB71C1C),
        ),
        body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: conditions.length,
          itemBuilder: (context, index) {
            final item = conditions[index];

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.health_and_safety,
                        color: Color(0xFFB71C1C),
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    item.description,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.7,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF5F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: Color(0xFFB71C1C),
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'المناطق العامة: ${item.area}',
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.6,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item.medicalWarning) ...[
                    const SizedBox(height: 12),
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.orange,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'تنبيه: هذه الحالة تحتاج تقييمًا طبيًا، والحجامة لا تُغني عن العلاج الموصوف.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class MyAppointmentsScreen extends StatefulWidget {
  const MyAppointmentsScreen({super.key});

  @override
  State<MyAppointmentsScreen> createState() => _MyAppointmentsScreenState();
}

class _MyAppointmentsScreenState extends State<MyAppointmentsScreen> {
  Set<String> _hiddenAppointmentIds = {};

Future<void> _loadHiddenAppointments() async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) return;

  final prefs = await SharedPreferences.getInstance();

  final hiddenIds =
      prefs.getStringList('hidden_appointments_${user.uid}') ?? [];

  if (!mounted) return;

  setState(() {
    _hiddenAppointmentIds = hiddenIds.toSet();
  });
}

@override
void initState() {
  super.initState();
  _loadHiddenAppointments();
}
  String getStatusText(String status) {
    switch (status) {
      case 'approved':
        return 'تم قبول الموعد';
      case 'rejected':
        return 'تم رفض الموعد';
      case 'cancellationRequested':
        return 'طلب الإلغاء بانتظار موافقة الكوتش';
      case 'cancelled':
        return 'تم إلغاء الموعد';
      default:
        return 'قيد المراجعة';
    }
  }

  Color getStatusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'cancellationRequested':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Future<void> _requestCancellation(
    BuildContext context,
    String appointmentId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('طلب إلغاء الموعد'),
          content: const Text(
            'سيتم إرسال طلب إلغاء للكوتش، ولن يتم إلغاء الموعد إلا بعد موافقته.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('رجوع'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('إرسال الطلب'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(appointmentId)
          .update({
        'status': 'cancellationRequested',
        'cancellationRequestedAt': FieldValue.serverTimestamp(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال طلب الإلغاء للكوتش'),
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
    final user = FirebaseAuth.instance.currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F8F8),
        appBar: AppBar(
  title: const Text(
    'مواعيدي',
    style: TextStyle(fontWeight: FontWeight.bold),
  ),
  centerTitle: true,
  backgroundColor: Colors.white,
  foregroundColor: const Color(0xFFB71C1C),
  actions: [
    IconButton(
      tooltip: 'إخفاء المواعيد القديمة',
      icon: const Icon(Icons.delete_sweep_outlined),
      onPressed: () async {
        final user = FirebaseAuth.instance.currentUser;

        if (user == null) return;

        final snapshot = await FirebaseFirestore.instance
            .collection('appointments')
            .where('userId', isEqualTo: user.uid)
            .get();

        final now = DateTime.now();

        final oldAppointmentIds = snapshot.docs.where((doc) {
          final data = doc.data();
          final timestamp = data['date'] as Timestamp?;

          if (timestamp == null) return false;

          return timestamp.toDate().isBefore(now);
        }).map((doc) => doc.id).toList();

        if (oldAppointmentIds.isEmpty) {
          if (!context.mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا توجد مواعيد قديمة لإخفائها'),
            ),
          );

          return;
        }

        final prefs = await SharedPreferences.getInstance();

        final hiddenIds =
            prefs.getStringList('hidden_appointments_${user.uid}') ?? [];

        final updatedIds = {
          ...hiddenIds,
          ...oldAppointmentIds,
        }.toList();

        await prefs.setStringList(
          'hidden_appointments_${user.uid}',
          updatedIds,
        );

        if (!context.mounted) return;

        setState(() {
          _hiddenAppointmentIds.addAll(oldAppointmentIds);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إخفاء ${oldAppointmentIds.length} موعد قديم من جهازك',
            ),
          ),
        );
      },
    ),
  ],
),
        body: user == null
            ? const Center(
                child: Text('يجب تسجيل الدخول أولًا'),
              )
            : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('appointments')
                    .where('userId', isEqualTo: user.uid)
                    .orderBy('date', descending: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFB71C1C),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'حدث خطأ أثناء تحميل المواعيد:\n${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                 final allAppointments = snapshot.data?.docs ?? [];

final appointments = allAppointments.where((doc) {
  return !_hiddenAppointmentIds.contains(doc.id);
}).toList();

                  if (appointments.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.event_available,
                              size: 80,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'لا توجد مواعيد حاليًا',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'عند حجز جلسة جديدة سيظهر موعدك هنا.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 25),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const BookingScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.calendar_month),
                              label: const Text('احجز موعدًا جديدًا'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFB71C1C),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: appointments.length,
                    itemBuilder: (context, index) {
                      final appointment =
                          appointments[index].data() as Map<String, dynamic>;

                      final Timestamp? timestamp =
                          appointment['date'] as Timestamp?;

                      final date = timestamp?.toDate();

                      final status =
                          appointment['status']?.toString() ?? 'pending';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFDECEC),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.calendar_month,
                                      color: Color(0xFFB71C1C),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'موعد الحجامة',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              if (date != null) ...[
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.event,
                                      size: 21,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${date.day}/${date.month}/${date.year}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.access_time,
                                      size: 21,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 14),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: getStatusColor(status)
                                      .withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      status == 'approved'
                                          ? Icons.check_circle
                                          : status == 'rejected'
                                              ? Icons.cancel
                                              : Icons.hourglass_top,
                                      color: getStatusColor(status),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      getStatusText(status),
                                      style: TextStyle(
                                        color: getStatusColor(status),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (appointment['notes'] != null &&
                                  appointment['notes']
                                      .toString()
                                      .trim()
                                      .isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Text(
                                  'ملاحظات: ${appointment['notes']}',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                              if (status == 'approved') ...[
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      _requestCancellation(
                                        context,
                                        appointments[index].id,
                                      );
                                    },
                                    icon: const Icon(Icons.cancel_outlined),
                                    label: const Text('طلب إلغاء الموعد'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(
                                        color: Colors.red,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
