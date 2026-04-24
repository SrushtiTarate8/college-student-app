import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'theme_provider.dart';
import 'package:provider/provider.dart';

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

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _confirmController = TextEditingController();
  final _branchController = TextEditingController();

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _slideController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));

    _fadeAnim =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _fadeController.forward();
    _slideController.forward();
  }

  void _switchMode() {
    _fadeController.reset();
    _slideController.reset();
    setState(() => isLogin = !isLogin);
    _fadeController.forward();
    _slideController.forward();
  }

  void _handleAuth() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => HomeScreen(
          studentName: isLogin
              ? "Student"
              : (_nameController.text.isEmpty
              ? "Student"
              : _nameController.text),
          studentBranch:
          isLogin ? "Computer Engineering" : _branchController.text,
          studentEmail: _emailController.text,
        ),
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
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
    _branchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final size = MediaQuery.of(context).size;

    // Themed colors
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
          // Background gradient orbs
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFF6C63FF).withOpacity(isDark ? 0.35 : 0.12),
                  Colors.transparent,
                ]),
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
                gradient: RadialGradient(colors: [
                  const Color(0xFF43E97B).withOpacity(isDark ? 0.25 : 0.1),
                  Colors.transparent,
                ]),
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

                        // ── Top Row: Logo + Theme Toggle ──
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF6C63FF),
                                    Color(0xFF43E97B)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF6C63FF)
                                        .withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.school_rounded,
                                  color: Colors.white, size: 26),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              "CampusMate",
                              style: TextStyle(
                                color: primaryText,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const Spacer(),
                            // Dark Mode Toggle
                            GestureDetector(
                              onTap: () => themeProvider.toggleTheme(),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: 52,
                                height: 28,
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: isDark
                                      ? const LinearGradient(
                                    colors: [
                                      Color(0xFF6C63FF),
                                      Color(0xFF9B59B6)
                                    ],
                                  )
                                      : LinearGradient(
                                    colors: [
                                      Colors.grey.shade300,
                                      Colors.grey.shade200,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isDark
                                          ? const Color(0xFF6C63FF)
                                          .withOpacity(0.35)
                                          : Colors.black.withOpacity(0.1),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: AnimatedAlign(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                  alignment: isDark
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Icon(
                                        isDark
                                            ? Icons.dark_mode_rounded
                                            : Icons.wb_sunny_rounded,
                                        color: isDark
                                            ? const Color(0xFF6C63FF)
                                            : Colors.amber,
                                        size: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: size.height * 0.055),

                        // Heading
                        Text(
                          isLogin ? "Welcome\nBack 👋" : "Create\nAccount ✨",
                          style: TextStyle(
                            color: primaryText,
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            letterSpacing: -0.5,
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

                        // Form card
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: borderColor, width: 1),
                            boxShadow: [
                              if (!isDark)
                                BoxShadow(
                                  color: const Color(0xFF6C63FF)
                                      .withOpacity(0.06),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                            ],
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
                                _buildField(
                                  controller: _branchController,
                                  label: "Branch",
                                  icon: Icons.account_balance_outlined,
                                  fieldFill: fieldFill,
                                  fieldBorder: fieldBorder,
                                  labelColor: labelColor,
                                  inputTextColor: inputTextColor,
                                ),
                                const SizedBox(height: 16),
                              ],
                              _buildField(
                                controller: _emailController,
                                label: "Email",
                                icon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
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
                                toggleObscure: () => setState(() =>
                                _obscurePassword = !_obscurePassword),
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
                                  toggleObscure: () => setState(() =>
                                  _obscureConfirm = !_obscureConfirm),
                                ),
                              ],
                              if (isLogin) ...[
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    "Forgot Password?",
                                    style: TextStyle(
                                      color: const Color(0xFF6C63FF)
                                          .withOpacity(0.9),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 28),

                        // CTA button
                        GestureDetector(
                          onTap: _handleAuth,
                          child: Container(
                            width: double.infinity,
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6C63FF), Color(0xFF9B59B6)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6C63FF).withOpacity(0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                isLogin ? "Sign In" : "Create Account",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 30),

                        // Switch mode
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              isLogin
                                  ? "Don't have an account? "
                                  : "Already have an account? ",
                              style: TextStyle(
                                color: secondaryText,
                                fontSize: 14,
                              ),
                            ),
                            GestureDetector(
                              onTap: _switchMode,
                              child: const Text(
                                "Register",
                                style: TextStyle(
                                  color: Color(0xFF6C63FF),
                                  fontSize: 14,
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
    TextInputType? keyboardType,
    bool obscure = false,
    VoidCallback? toggleObscure,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: TextStyle(color: inputTextColor, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: labelColor, fontSize: 14),
        prefixIcon:
        Icon(icon, color: const Color(0xFF6C63FF), size: 20),
        suffixIcon: toggleObscure != null
            ? IconButton(
          icon: Icon(
            obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: labelColor,
            size: 20,
          ),
          onPressed: toggleObscure,
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
          borderSide: BorderSide(color: fieldBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
        ),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}