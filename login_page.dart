import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final emailController = TextEditingController();
  final passController = TextEditingController();
  final confirmPassController = TextEditingController();
  final captchaInputController = TextEditingController();

  bool isLogin = true;
  bool isLoading = false;
  bool obscurePass = true;
  bool obscureConfirm = true;

  String currentCaptcha = "";

  // Password rule states
  bool hasUppercase = false;
  bool hasDigit = false;
  bool hasSymbol = false;
  bool hasMinLength = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _generateCaptcha();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _animController.forward();

    passController.addListener(() {
      final v = passController.text;
      setState(() {
        hasUppercase = v.contains(RegExp(r'[A-Z]'));
        hasDigit = v.contains(RegExp(r'[0-9]'));
        hasSymbol = v.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'));
        hasMinLength = v.length >= 8;
      });
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    emailController.dispose();
    passController.dispose();
    confirmPassController.dispose();
    captchaInputController.dispose();
    super.dispose();
  }

  void _generateCaptcha() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ123456789';
    final random = Random();
    setState(() {
      currentCaptcha = List.generate(
        6,
        (i) => chars[random.nextInt(chars.length)],
      ).join();
    });
  }

  void _toggleMode() {
    _animController.reverse().then((_) {
      setState(() {
        isLogin = !isLogin;
        captchaInputController.clear();
        confirmPassController.clear();
        passController.clear();
        emailController.clear();
      });
      _generateCaptcha();
      _animController.forward();
    });
  }

  Future<void> auth() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);
    try {
      if (isLogin) {
        // ── LOGIN ──
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passController.text.trim(),
        );
        // Login এর সময়ও active_user update করো
        final uid = cred.user!.uid;
        await FirebaseDatabase.instance.ref('active_user').set(uid);
      } else {
        // ── SIGNUP ──
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passController.text.trim(),
        );

        final uid = cred.user!.uid;
        final now = DateTime.now().toIso8601String();

        // ✅ নতুন user এর জন্য database এ initial profile তৈরি করো
        await FirebaseDatabase.instance.ref('users/$uid').set({
          'email': emailController.text.trim(),
          'created_at': now,
          'analytics': {
            'last_posture': 'WAITING',
            'last_suggestion': 'Start a posture session',
            'posture_score': 0,
            'sitting_time': 0,
            'good_posture': 0,
            'bad_posture': 0,
            'last_updated': now,
          },
        });

        // ✅ active_user set করো যাতে Python script সঠিক UID পায়
        await FirebaseDatabase.instance.ref('active_user').set(uid);
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomePage()),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? "Auth error"),
          backgroundColor: const Color(0xFFE53E3E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F1117), Color(0xFF1A1D2E), Color(0xFF0D1526)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Logo / Header ──
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6C63FF).withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.accessibility_new_rounded,
                            color: Colors.white,
                            size: 38,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: Text(
                          "Posture AI",
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            foreground: Paint()
                              ..shader =
                                  const LinearGradient(
                                    colors: [
                                      Color(0xFF6C63FF),
                                      Color(0xFF3ECFCF),
                                    ],
                                  ).createShader(
                                    const Rect.fromLTWH(0, 0, 200, 40),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(
                          isLogin ? "Welcome back 👋" : "Create your account",
                          style: const TextStyle(
                            color: Color(0xFF8B8FA8),
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ── Card ──
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2130),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0xFF2E3250),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Email
                            _buildLabel("Email"),
                            const SizedBox(height: 6),
                            _buildTextField(
                              controller: emailController,
                              hint: "you@example.com",
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) {
                                if (v == null || v.isEmpty)
                                  return "Please enter your email address";
                                if (!v.contains('@'))
                                  return "Please enter a valid email address";
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),

                            // Password
                            _buildLabel("Password"),
                            const SizedBox(height: 6),
                            _buildTextField(
                              controller: passController,
                              hint: "••••••••",
                              icon: Icons.lock_outline_rounded,
                              obscure: obscurePass,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  obscurePass
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: const Color(0xFF6C63FF),
                                  size: 20,
                                ),
                                onPressed: () =>
                                    setState(() => obscurePass = !obscurePass),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return "Password";
                                if (!isLogin) {
                                  if (!hasMinLength ||
                                      !hasUppercase ||
                                      !hasDigit ||
                                      !hasSymbol) {
                                    return "Password requirements";
                                  }
                                }
                                return null;
                              },
                            ),

                            // Password requirements (sign up only)
                            if (!isLogin) ...[
                              const SizedBox(height: 12),
                              _buildPasswordRequirements(),
                              const SizedBox(height: 18),

                              // Confirm Password
                              _buildLabel("Confirm Password"),
                              const SizedBox(height: 6),
                              _buildTextField(
                                controller: confirmPassController,
                                hint: "••••••••",
                                icon: Icons.lock_reset_outlined,
                                obscure: obscureConfirm,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    obscureConfirm
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: const Color(0xFF6C63FF),
                                    size: 20,
                                  ),
                                  onPressed: () => setState(
                                    () => obscureConfirm = !obscureConfirm,
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty)
                                    return "Please confirm your password";
                                  if (v != passController.text)
                                    return "Passwords do not match";
                                  return null;
                                },
                              ),
                            ] else
                              const SizedBox(height: 0),

                            const SizedBox(height: 20),

                            // Captcha
                            _buildLabel("Captcha"),
                            const SizedBox(height: 8),
                            _buildCaptchaWidget(),
                            const SizedBox(height: 10),
                            _buildTextField(
                              controller: captchaInputController,
                              hint: "Type Captcha",
                              icon: Icons.security_rounded,
                              validator: (v) {
                                if (v == null || v.isEmpty)
                                  return "Please Enter Captcha";
                                if (v.toUpperCase() != currentCaptcha)
                                  return "Incorrect Captcha";
                                return null;
                              },
                            ),

                            const SizedBox(height: 28),

                            // Submit button
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: isLoading ? null : auth,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    gradient: isLoading
                                        ? null
                                        : const LinearGradient(
                                            colors: [
                                              Color(0xFF6C63FF),
                                              Color(0xFF3ECFCF),
                                            ],
                                          ),
                                    color: isLoading
                                        ? const Color(0xFF2E3250)
                                        : null,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Container(
                                    alignment: Alignment.center,
                                    child: isLoading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: Color(0xFF6C63FF),
                                            ),
                                          )
                                        : Text(
                                            isLogin ? "Login" : "Sign Up",
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Toggle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isLogin
                                ? "Don't have an account? "
                                : "Already have an account? ",
                            style: const TextStyle(
                              color: Color(0xFF8B8FA8),
                              fontSize: 14,
                            ),
                          ),
                          GestureDetector(
                            onTap: _toggleMode,
                            child: Text(
                              isLogin ? "Sign Up" : "Login",
                              style: const TextStyle(
                                color: Color(0xFF6C63FF),
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFFB0B4CC),
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF4A4F6A), fontSize: 14),
        prefixIcon: Icon(icon, color: const Color(0xFF6C63FF), size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFF13151F),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2E3250)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2E3250)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE53E3E)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE53E3E), width: 1.5),
        ),
        errorStyle: const TextStyle(color: Color(0xFFE53E3E), fontSize: 12),
      ),
    );
  }

  Widget _buildPasswordRequirements() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF13151F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E3250)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Password requirements:",
            style: TextStyle(
              color: Color(0xFF8B8FA8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _buildRequirementRow(hasMinLength, "Minimum 8 character"),
          const SizedBox(height: 5),
          _buildRequirementRow(
            hasUppercase,
            "At least 1 uppercase letter (A-Z)",
          ),
          const SizedBox(height: 5),
          _buildRequirementRow(hasDigit, "At least 1 number (0-9)"),
          const SizedBox(height: 5),
          _buildRequirementRow(hasSymbol, "At least 1 symbol (!@#\$%^&*)"),
        ],
      ),
    );
  }

  Widget _buildRequirementRow(bool satisfied, String text) {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: satisfied
                ? const Color(0xFF22C55E).withOpacity(0.15)
                : const Color(0xFF2E3250),
            border: Border.all(
              color: satisfied
                  ? const Color(0xFF22C55E)
                  : const Color(0xFF4A4F6A),
              width: 1.5,
            ),
          ),
          child: satisfied
              ? const Icon(Icons.check, color: Color(0xFF22C55E), size: 11)
              : null,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: satisfied
                  ? const Color(0xFF22C55E)
                  : const Color(0xFF8B8FA8),
              fontSize: 12,
              fontWeight: satisfied ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCaptchaWidget() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1050), Color(0xFF0D2040)],
        ),
        border: Border.all(color: const Color(0xFF2E3250)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: currentCaptcha.split('').map((char) {
                  final rng = Random(char.codeUnitAt(0));
                  final rotAngle = (rng.nextDouble() - 0.5) * 0.5;
                  final colors = [
                    const Color(0xFF6C63FF),
                    const Color(0xFF3ECFCF),
                    const Color(0xFFFF6B9D),
                    const Color(0xFFFFAB4E),
                    const Color(0xFF22C55E),
                  ];
                  final color = colors[rng.nextInt(colors.length)];
                  return Transform.rotate(
                    angle: rotAngle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        char,
                        style: TextStyle(
                          color: color,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          shadows: [
                            Shadow(
                              color: color.withOpacity(0.6),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Container(width: 1, color: const Color(0xFF2E3250)),
          InkWell(
            onTap: () {
              _generateCaptcha();
              captchaInputController.clear();
            },
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(14),
              bottomRight: Radius.circular(14),
            ),
            child: Container(
              width: 52,
              alignment: Alignment.center,
              child: const Icon(
                Icons.refresh_rounded,
                color: Color(0xFF6C63FF),
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
