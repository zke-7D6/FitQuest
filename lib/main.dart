import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'auth_screen.dart';
import 'home_screen.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.init();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const FitQuestApp());
}

class FitQuestApp extends StatelessWidget {
  const FitQuestApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      title: 'FitQuest',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.dark,
          primary: AppColors.accent,
          surface: AppColors.surface,
        ),
        textTheme: GoogleFonts.dmSansTextTheme(base.textTheme).apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: AppColors.bg,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppColors.textPrimary,
          centerTitle: false,
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _SplashScreen();
          }
          return snapshot.hasData ? const HomeScreen() : const AuthScreen();
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FitQuestLogo(size: 70),
            SizedBox(height: 18),
            Text(
              'FitQuest',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
                color: AppColors.accent,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'your fitness quest begins',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            SizedBox(height: 28),
            SizedBox(
              width: 150,
              child: LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: AppColors.border,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FitQuestLogo extends StatelessWidget {
  final double size;
  const FitQuestLogo({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.card,
        border: Border.all(color: AppColors.accent.withOpacity(0.85), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withOpacity(0.18),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(Icons.explore_rounded, color: AppColors.accent, size: size * 0.54),
    );
  }
}

class AppColors {
  // Modern FitQuest palette: dark fitness app, softer than the previous neon/cyber look.
  static const bg = Color(0xFF061421);
  static const surface = Color(0xFF0B1A29);
  static const card = Color(0xFF102235);
  static const card2 = Color(0xFF132B3E);
  static const border = Color(0xFF24364A);

  static const accent = Color(0xFF5AF2DD);
  static const accentDim = Color(0x223FEBD3);
  static const neon2 = Color(0xFF6EE7FF);
  static const neon3 = Color(0xFFB8FF4D);
  static const neon4 = Color(0xFFFFD166);

  static const textPrimary = Color(0xFFEAF2FF);
  static const textSecondary = Color(0xFFAAB8CC);
  static const textMuted = Color(0xFF6F8197);

  static const success = Color(0xFF65F2A6);
  static const warning = Color(0xFFFFD166);
  static const danger = Color(0xFFFF6B7A);

  static const gradientStart = Color(0xFF11273B);
  static const gradientEnd = Color(0xFF0A1725);
}
