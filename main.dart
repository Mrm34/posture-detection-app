import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'login_page.dart';
import 'home_page.dart';

// ─────────────────────────────────────────────
//  THEME NOTIFIER  (global dark/light toggle)
// ─────────────────────────────────────────────
class ThemeNotifier extends ChangeNotifier {
  bool _isDark = true;
  bool get isDark => _isDark;

  void toggle() {
    _isDark = !_isDark;
    notifyListeners();
  }
}

final themeNotifier = ThemeNotifier();

// ─────────────────────────────────────────────
//  MAIN
// ─────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    themeNotifier.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF0F2F5),
        colorScheme: ColorScheme.light(primary: const Color(0xFF6C63FF)),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        colorScheme: ColorScheme.dark(primary: const Color(0xFF6C63FF)),
      ),
      themeMode: themeNotifier.isDark ? ThemeMode.dark : ThemeMode.light,
      home: const SplashScreen(),
    );
  }
}

// ─────────────────────────────────────────────
//  SPLASH SCREEN
// ─────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();

    // Navigate after 2.5s
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      final user = FirebaseAuth.instance.currentUser;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, __, ___) =>
              user != null ? const HomePage() : const LoginPage(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo
              ScaleTransition(
                scale: _scale,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C63FF).withOpacity(0.5),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.accessibility_new_rounded,
                    color: Colors.white,
                    size: 52,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // App name
              ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
                ).createShader(rect),
                child: const Text(
                  'Posture AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Your posture, perfected.',
                style: TextStyle(
                  color: Color(0xFF8B8FA8),
                  fontSize: 14,
                  letterSpacing: 0.3,
                ),
              ),

              const SizedBox(height: 48),

              // Loading dots
              _LoadingDots(),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with TickerProviderStateMixin {
  late List<AnimationController> _ctrls;
  late List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      ),
    );
    _anims = _ctrls
        .map(
          (c) => Tween<double>(
            begin: 0.4,
            end: 1.0,
          ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
        )
        .toList();

    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) {
          _ctrls[i].repeat(reverse: true);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return FadeTransition(
          opacity: _anims[i],
          child: Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
              ),
            ),
          ),
        );
      }),
    );
  }
}
