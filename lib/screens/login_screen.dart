import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_screen.dart';
import 'theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  bool isLogin = true;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _selectedBranch;

  final List<String> branches = [
    "Computer Engineering",
    "IT Engineering",
    "ENTC",
    "Mechanical Engineering",
    "Civil Engineering",
    "Electrical Engineering",
    "AI & DS",
  ];

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnim =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOut),
    );

    _fadeController.forward();
    _slideController.forward();
  }

  void _switchMode() {
    _fadeController.reset();
    _slideController.reset();

    setState(() {
      isLogin = !isLogin;
    });

    _fadeController.forward();
    _slideController.forward();
  }

  Future<void> _handleAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnack("Please fill required fields");
      return;
    }

    if (!isLogin) {
      if (name.isEmpty) {
        _showSnack("Enter your full name");
        return;
      }

      if (_selectedBranch == null) {
        _showSnack("Select your branch");
        return;
      }

      if (_confirmController.text.trim() != password) {
        _showSnack("Passwords do not match");
        return;
      }
    }

    try {
      setState(() => _isLoading = true);

      UserCredential userCredential;

      if (isLogin) {
        userCredential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        await userCredential.user?.updateDisplayName(name);

        final uid = userCredential.user!.uid;

        await FirebaseFirestore.instance
            .collection("students")
            .doc(uid)
            .set({
          "name": name,
          "email": email,
          "branch": _selectedBranch,
          "createdAt": FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => HomeScreen(
            studentName: isLogin
                ? (userCredential.user?.displayName ?? "Student")
                : name,
            studentBranch:
            isLogin ? "Computer Engineering" : _selectedBranch!,
            studentEmail: email,
          ),
          transitionDuration: const Duration(milliseconds: 600),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    } on FirebaseAuthException catch (e) {
      print("Firebase code: ${e.code}");
      print("Firebase message: ${e.message}");

      String msg = "${e.code} : ${e.message}";

      if (e.code == "user-not-found") {
        msg = "No user found with this email";
      } else if (e.code == "wrong-password") {
        msg = "Wrong password";
      } else if (e.code == "email-already-in-use") {
        msg = "Email already registered";
      } else if (e.code == "weak-password") {
        msg = "Password should be at least 6 characters";
      } else if (e.code == "invalid-email") {
        msg = "Invalid email address";
      }

      _showSnack(msg);
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
}

void _showSnack(String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

@override
void dispose() {
  _fadeController.dispose();
  _slideController.dispose();
  _emailController.dispose();
  _passwordController.dispose();
  _nameController.dispose();
  _confirmController.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final themeProvider = Provider.of<ThemeProvider>(context);
  final isDark = themeProvider.isDarkMode;
  final size = MediaQuery
      .of(context)
      .size;

  final bgColor = isDark ? const Color(0xFF0F0E17) : const Color(0xFFF5F4FB);
  final cardBg = isDark ? const Color(0xFF1A1A2E) : Colors.white;
  final primaryText = isDark ? Colors.white : const Color(0xFF1A1535);
  final secondaryText = isDark
      ? Colors.white.withOpacity(0.55)
      : const Color(0xFF1A1535).withOpacity(0.5);
  final borderColor = isDark
      ? Colors.white.withOpacity(0.07)
      : const Color(0xFF6C63FF).withOpacity(0.1);
  final fieldFill = isDark
      ? Colors.white.withOpacity(0.05)
      : const Color(0xFF6C63FF).withOpacity(0.04);
  final fieldBorder = isDark
      ? Colors.white.withOpacity(0.08)
      : const Color(0xFF6C63FF).withOpacity(0.12);
  final labelColor = isDark
      ? Colors.white.withOpacity(0.45)
      : const Color(0xFF1A1535).withOpacity(0.4);
  final inputTextColor = isDark ? Colors.white : const Color(0xFF1A1535);

  return Scaffold(
    backgroundColor: bgColor,
    body: Stack(
      children: [
        Positioned(
          top: -80,
          right: -60,
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF6C63FF).withOpacity(isDark ? 0.35 : 0.12),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -60,
          left: -40,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF43E97B).withOpacity(isDark ? 0.25 : 0.1),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: size.height * 0.07),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF6C63FF),
                                  Color(0xFF43E97B),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.school_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            "CampusMate",
                            style: TextStyle(
                              color: primaryText,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: themeProvider.toggleTheme,
                            child: Icon(
                              isDark
                                  ? Icons.dark_mode_rounded
                                  : Icons.wb_sunny_rounded,
                              color: primaryText,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: size.height * 0.055),
                      Text(
                        isLogin ? "Welcome\nBack 👋" : "Create\nAccount ✨",
                        style: TextStyle(
                          color: primaryText,
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isLogin
                            ? "Sign in to continue your journey"
                            : "Join CampusMate and stay organized",
                        style: TextStyle(
                          color: secondaryText,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: size.height * 0.045),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          children: [
                            if (!isLogin) ...[
                              _buildField(
                                controller: _nameController,
                                label: "Full Name",
                                icon: Icons.person_outline_rounded,
                                fieldFill: fieldFill,
                                fieldBorder: fieldBorder,
                                labelColor: labelColor,
                                inputTextColor: inputTextColor,
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                value: _selectedBranch,
                                dropdownColor: cardBg,
                                style: TextStyle(color: inputTextColor),
                                decoration: InputDecoration(
                                  labelText: "Branch",
                                  prefixIcon: const Icon(
                                    Icons.account_balance_outlined,
                                    color: Color(0xFF6C63FF),
                                  ),
                                  filled: true,
                                  fillColor: fieldFill,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                items: branches.map((branch) {
                                  return DropdownMenuItem(
                                    value: branch,
                                    child: Text(branch),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedBranch = value;
                                  });
                                },
                              ),
                              const SizedBox(height: 16),
                            ],
                            _buildField(
                              controller: _emailController,
                              label: "Email",
                              icon: Icons.email_outlined,
                              fieldFill: fieldFill,
                              fieldBorder: fieldBorder,
                              labelColor: labelColor,
                              inputTextColor: inputTextColor,
                            ),
                            const SizedBox(height: 16),
                            _buildField(
                              controller: _passwordController,
                              label: "Password",
                              icon: Icons.lock_outline_rounded,
                              obscure: _obscurePassword,
                              fieldFill: fieldFill,
                              fieldBorder: fieldBorder,
                              labelColor: labelColor,
                              inputTextColor: inputTextColor,
                              toggleObscure: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            if (!isLogin) ...[
                              const SizedBox(height: 16),
                              _buildField(
                                controller: _confirmController,
                                label: "Confirm Password",
                                icon: Icons.lock_reset_rounded,
                                obscure: _obscureConfirm,
                                fieldFill: fieldFill,
                                fieldBorder: fieldBorder,
                                labelColor: labelColor,
                                inputTextColor: inputTextColor,
                                toggleObscure: () {
                                  setState(() {
                                    _obscureConfirm = !_obscureConfirm;
                                  });
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      GestureDetector(
                        onTap: _isLoading ? null : _handleAuth,
                        child: Container(
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF6C63FF),
                                Color(0xFF9B59B6),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: _isLoading
                                ? const CircularProgressIndicator(
                              color: Colors.white,
                            )
                                : Text(
                              isLogin ? "Sign In" : "Create Account",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isLogin
                                ? "Don't have an account? "
                                : "Already have an account? ",
                            style: TextStyle(
                              color: secondaryText,
                            ),
                          ),
                          GestureDetector(
                            onTap: _switchMode,
                            child: Text(
                              isLogin ? "Register" : "Login",
                              style: const TextStyle(
                                color: Color(0xFF6C63FF),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildField({
  required TextEditingController controller,
  required String label,
  required IconData icon,
  required Color fieldFill,
  required Color fieldBorder,
  required Color labelColor,
  required Color inputTextColor,
  bool obscure = false,
  VoidCallback? toggleObscure,
}) {
  return TextField(
    controller: controller,
    obscureText: obscure,
    style: TextStyle(color: inputTextColor),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: labelColor),
      prefixIcon: Icon(
        icon,
        color: const Color(0xFF6C63FF),
      ),
      suffixIcon: toggleObscure != null
          ? IconButton(
        onPressed: toggleObscure,
        icon: Icon(
          obscure
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          color: labelColor,
        ),
      )
          : null,
      filled: true,
      fillColor: fieldFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Color(0xFF6C63FF),
          width: 1.5,
        ),
      ),
    ),
  );
}}
