import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'theme_provider.dart';
import 'package:provider/provider.dart';

class ProfileScreen extends StatelessWidget {
  final String studentName;
  final String studentBranch;
  final String studentEmail;

  const ProfileScreen({
    super.key,
    this.studentName = "Student",
    this.studentBranch = "Computer Engineering",
    this.studentEmail = "student@college.edu",
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    final bgColor = isDark ? const Color(0xFF0F0E17) : const Color(0xFFF5F4FB);
    final cardBg = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final primaryText = isDark ? Colors.white : const Color(0xFF1A1535);
    final secondaryText = isDark
        ? Colors.white.withOpacity(0.45)
        : const Color(0xFF1A1535).withOpacity(0.4);
    final borderColor = isDark
        ? Colors.white.withOpacity(0.06)
        : const Color(0xFF6C63FF).withOpacity(0.08);
    final backBtnBg = isDark
        ? Colors.white.withOpacity(0.07)
        : const Color(0xFF6C63FF).withOpacity(0.07);

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // Decorative blobs
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFF6C63FF)
                      .withOpacity(isDark ? 0.25 : 0.1),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            bottom: -40,
            left: -30,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFF43E97B)
                      .withOpacity(isDark ? 0.15 : 0.08),
                  Colors.transparent,
                ]),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // ─── Header ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: backBtnBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: primaryText,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        "Profile",
                        style: TextStyle(
                          color: primaryText,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
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
                                    ? const Color(0xFF6C63FF).withOpacity(0.35)
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
                ),

                const SizedBox(height: 36),

                // ─── Avatar ───────────────────────────────────────
                Container(
                  width: 94,
                  height: 94,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF9B59B6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C63FF).withOpacity(0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      studentName.isNotEmpty
                          ? studentName[0].toUpperCase()
                          : "S",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                Text(
                  studentName,
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  studentEmail,
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 8),

                // Branch badge
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF6C63FF).withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    studentBranch,
                    style: const TextStyle(
                      color: Color(0xFF6C63FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ─── Info tiles ───────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          _infoTile(
                            icon: Icons.grade_rounded,
                            label: "Year",
                            value: "3rd Year",
                            cardBg: cardBg,
                            borderColor: borderColor,
                            primaryText: primaryText,
                            secondaryText: secondaryText,
                          ),
                          const SizedBox(height: 12),
                          _infoTile(
                            icon: Icons.badge_rounded,
                            label: "Roll No.",
                            value: "CS-2024-031",
                            cardBg: cardBg,
                            borderColor: borderColor,
                            primaryText: primaryText,
                            secondaryText: secondaryText,
                          ),
                          const SizedBox(height: 12),
                          _infoTile(
                            icon: Icons.star_rounded,
                            label: "CGPA",
                            value: "8.4 / 10",
                            cardBg: cardBg,
                            borderColor: borderColor,
                            primaryText: primaryText,
                            secondaryText: secondaryText,
                          ),
                          const SizedBox(height: 12),
                          _infoTile(
                            icon: Icons.bar_chart_rounded,
                            label: "Attendance",
                            value: "85%",
                            cardBg: cardBg,
                            borderColor: borderColor,
                            primaryText: primaryText,
                            secondaryText: secondaryText,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ─── Logout ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
                  child: GestureDetector(
                    onTap: () => _confirmLogout(context),
                    child: Container(
                      width: double.infinity,
                      height: 54,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.05)
                            : const Color(0xFFFF6B6B).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFFF6B6B).withOpacity(0.4),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.logout_rounded,
                              color: Color(0xFFFF6B6B), size: 20),
                          SizedBox(width: 10),
                          Text(
                            "Logout",
                            style: TextStyle(
                              color: Color(0xFFFF6B6B),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
    required Color cardBg,
    required Color borderColor,
    required Color primaryText,
    required Color secondaryText,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF6C63FF), size: 18),
          ),
          const SizedBox(width: 14),
          Text(
            label,
            style: TextStyle(
              color: secondaryText,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: primaryText,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    final themeProvider =
    Provider.of<ThemeProvider>(context, listen: false);
    final isDark = themeProvider.isDarkMode;
    final cardBg = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final primaryText = isDark ? Colors.white : const Color(0xFF1A1535);
    final secondaryText = isDark
        ? Colors.white.withOpacity(0.6)
        : const Color(0xFF1A1535).withOpacity(0.5);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cardBg,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "Logout",
          style: TextStyle(
              color: primaryText, fontWeight: FontWeight.w700),
        ),
        content: Text(
          "Are you sure you want to logout?",
          style: TextStyle(color: secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel",
                style: TextStyle(color: secondaryText)),
          ),
          GestureDetector(
            onTap: () {
              Navigator.pushAndRemoveUntil(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const LoginScreen(),
                  transitionDuration: const Duration(milliseconds: 500),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                ),
                    (route) => false,
              );
            },
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                "Logout",
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}