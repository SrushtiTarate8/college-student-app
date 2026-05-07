// =============================================================================
// pomodoro_screen.dart
//
// FocusGrove — Gamified Pomodoro Screen
//
// Builds ON TOP of your existing productivity_engine.dart.
// Adds:
//   • Per-subject session configuration (focus/break durations per subject)
//   • Daily streak dots — full 🔥 / half ⚡ / missed ✗ per subject
//   • Growing tree visualisation (seed→sprout→sapling→tree→blooming)
//   • Duolingo-style mascot "Sprout" with mood reactions
//   • XP + Level system with animated level-up
//   • Badge/Achievement system (10 badges)
//   • Reward overlay on session complete with confetti
//   • Full dark/light mode via ThemeProvider
//
// This file is SELF-CONTAINED — import it and navigate like:
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => PomodoroScreen(engine: _productivityEngine)));
// =============================================================================

// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'productivity_engine.dart';
import 'theme_provider.dart';
import 'focus_lock_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1 — GAMIFICATION MODELS
// ─────────────────────────────────────────────────────────────────────────────

/// Daily streak quality per subject per day.
enum StreakTier { full, half, none }

/// One badge the student can unlock.
class FocusBadge {
  final String id;
  final String emoji;
  final String title;
  final String desc;
  final int xpReward;
  const FocusBadge({
    required this.id,
    required this.emoji,
    required this.title,
    required this.desc,
    required this.xpReward,
  });
}

const List<FocusBadge> kBadges = [
  FocusBadge(id: 'first',      emoji: '🌱', title: 'First Seed',    desc: 'Completed your very first session!',    xpReward: 50),
  FocusBadge(id: 'streak3',    emoji: '🔥', title: 'On Fire',       desc: '3-day streak!',                        xpReward: 100),
  FocusBadge(id: 'streak7',    emoji: '⚡', title: 'Week Warrior',  desc: '7-day streak — unstoppable!',           xpReward: 250),
  FocusBadge(id: 'streak30',   emoji: '👑', title: 'Month Master',  desc: '30-day streak — legendary!',           xpReward: 1000),
  FocusBadge(id: 'sessions10', emoji: '🎯', title: 'Ten Sessions',  desc: '10 total sessions completed!',         xpReward: 75),
  FocusBadge(id: 'sessions50', emoji: '💎', title: 'Diamond Mind',  desc: '50 sessions — seriously dedicated!',   xpReward: 300),
  FocusBadge(id: 'level5',     emoji: '⭐', title: 'Level 5',       desc: 'Reached Level 5!',                     xpReward: 150),
  FocusBadge(id: 'level10',    emoji: '🌟', title: 'Level 10',      desc: 'Reached Level 10!',                    xpReward: 400),
  FocusBadge(id: 'bloom',      emoji: '🌸', title: 'Tree Bloomed',  desc: 'Your tree reached full bloom!',        xpReward: 200),
  FocusBadge(id: 'nocturnal',  emoji: '🦉', title: 'Night Owl',     desc: 'Completed a session after midnight!',  xpReward: 80),
];

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2 — GAMIFICATION STATE  (saved to SharedPreferences)
// ─────────────────────────────────────────────────────────────────────────────

class GamificationState extends ChangeNotifier {
  int _xp = 0;
  int _totalSessions = 0;
  final Set<String> _unlockedBadges = {};

  // key = "subjectId|yyyy-MM-dd"  value = sessions completed
  final Map<String, int> _dailyMap = {};

  // daily target per subject (subjectId → target count)
  final Map<String, int> _targets = {};

  int get xp => _xp;
  int get totalSessions => _totalSessions;
  int get level => (_xp ~/ 200) + 1;
  double get levelProgress => (_xp % 200) / 200.0;
  int get xpToNext => 200 - (_xp % 200);
  Set<String> get unlockedBadges => Set.unmodifiable(_unlockedBadges);

  // ── Persistence keys ──────────────────────────────────────────────────────
  static const _kXp       = 'gs_xp';
  static const _kSessions = 'gs_sessions';
  static const _kBadges   = 'gs_badges';
  static const _kDaily    = 'gs_daily';
  static const _kTargets  = 'gs_targets';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _xp            = p.getInt(_kXp)       ?? 0;
    _totalSessions = p.getInt(_kSessions) ?? 0;
    _unlockedBadges.addAll((p.getStringList(_kBadges) ?? []));
    final rawDaily   = p.getString(_kDaily);
    final rawTargets = p.getString(_kTargets);
    if (rawDaily   != null) {
      final m = jsonDecode(rawDaily) as Map<String, dynamic>;
      m.forEach((k, v) => _dailyMap[k]  = v as int);
    }
    if (rawTargets != null) {
      final m = jsonDecode(rawTargets) as Map<String, dynamic>;
      m.forEach((k, v) => _targets[k]  = v as int);
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kXp,       _xp);
    await p.setInt(_kSessions, _totalSessions);
    await p.setStringList(_kBadges, _unlockedBadges.toList());
    await p.setString(_kDaily,   jsonEncode(_dailyMap));
    await p.setString(_kTargets, jsonEncode(_targets));
  }

  // ── Called by the screen whenever a focus session completes ──────────────
  /// Returns list of newly unlocked badges so the UI can celebrate.
  List<FocusBadge> recordSession({
    required String subjectId,
    required int focusMinutes,
    required double currentStreakDays,
    required bool isAfterMidnight,
  }) {
    _totalSessions++;
    final gained = 20 + (focusMinutes ~/ 5) * 5;
    _xp += gained;

    // Daily record
    final key = '$subjectId|${_todayStr()}';
    _dailyMap[key] = (_dailyMap[key] ?? 0) + 1;

    // Check new badges
    final newBadges = _checkBadges(currentStreakDays, isAfterMidnight);
    for (final b in newBadges) {
      _xp += b.xpReward;
    }

    _save();
    notifyListeners();
    return newBadges;
  }

  void setTarget(String subjectId, int target) {
    _targets[subjectId] = target;
    _save();
    notifyListeners();
  }

  int targetFor(String subjectId) => _targets[subjectId] ?? 4;

  int sessionsOnDay(String subjectId, String dateStr) =>
      _dailyMap['$subjectId|$dateStr'] ?? 0;

  /// Returns [StreakTier] for each of the last 7 days (index 0 = 6 days ago, 6 = today).
  List<StreakTier> streak7(String subjectId) {
    return List.generate(7, (i) {
      final d = DateTime.now().subtract(Duration(days: 6 - i));
      final dateStr = _dateStr(d);
      final done = sessionsOnDay(subjectId, dateStr);
      final target = targetFor(subjectId);
      if (done >= target)       return StreakTier.full;
      if (done >= target ~/ 2 && done > 0) return StreakTier.half;
      return StreakTier.none;
    });
  }

  List<FocusBadge> _checkBadges(double streak, bool nocturnal) {
    final newBadges = <FocusBadge>[];
    void tryUnlock(String id) {
      if (!_unlockedBadges.contains(id)) {
        final b = kBadges.firstWhere((b) => b.id == id, orElse: () => kBadges.first);
        _unlockedBadges.add(id);
        newBadges.add(b);
      }
    }
    if (_totalSessions >= 1)   tryUnlock('first');
    if (_totalSessions >= 10)  tryUnlock('sessions10');
    if (_totalSessions >= 50)  tryUnlock('sessions50');
    if (streak >= 3)           tryUnlock('streak3');
    if (streak >= 7)           tryUnlock('streak7');
    if (streak >= 30)          tryUnlock('streak30');
    if (level >= 5)            tryUnlock('level5');
    if (level >= 10)           tryUnlock('level10');
    if (nocturnal)             tryUnlock('nocturnal');
    return newBadges;
  }

  static String _todayStr() => _dateStr(DateTime.now());
  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3 — THEME TOKENS
// ─────────────────────────────────────────────────────────────────────────────

class _T {
  // ── Adaptive ──────────────────────────────────────────────────────────────
  static Color bg(bool d)          => d ? const Color(0xFF0E1117) : const Color(0xFFF0F4F0);
  static Color surface(bool d)     => d ? const Color(0xFF161C20) : Colors.white;
  static Color surfaceEl(bool d)   => d ? const Color(0xFF1E2630) : const Color(0xFFEFF7EE);
  static Color tp(bool d)          => d ? const Color(0xFFE8F5E9) : const Color(0xFF1B2E1C);
  static Color ts(bool d)          => d ? const Color(0xFF7A9A7C) : const Color(0xFF5A7A5C);
  static Color border(bool d)      => d ? const Color(0xFF2A3C2B) : const Color(0xFFD0E8D0);

  // ── Fixed ─────────────────────────────────────────────────────────────────
  static const Color accent   = Color(0xFF43A047);
  static const Color accent2  = Color(0xFF81C784);
  static const Color gold     = Color(0xFFFFD54F);
  static const Color orange   = Color(0xFFFF8F00);
  static const Color red      = Color(0xFFEF5350);
  static const Color blue     = Color(0xFF42A5F5);
  static const Color purple   = Color(0xFFAB47BC);
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 4 — MASCOT PAINTER  (Sprout — Duolingo-style leaf character)
// ─────────────────────────────────────────────────────────────────────────────

/// mood: 'idle' | 'excited' | 'happy' | 'sad' | 'sleeping'
class _MascotPainter extends CustomPainter {
  final String mood;
  _MascotPainter(this.mood);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width * 0.42;

    // Body
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        colors: const [Color(0xFF66BB6A), Color(0xFF2E7D32)],
        center: const Alignment(-0.3, -0.3),
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - r * 0.1), width: r * 1.8, height: r * 1.9),
      bodyPaint,
    );

    // Cheeks
    if (mood == 'happy' || mood == 'excited') {
      final cp = Paint()..color = const Color(0xFFEF9A9A).withOpacity(0.7);
      canvas.drawCircle(Offset(cx - r * 0.45, cy + r * 0.15), r * 0.17, cp);
      canvas.drawCircle(Offset(cx + r * 0.45, cy + r * 0.15), r * 0.17, cp);
    }

    final dark = Paint()..color = const Color(0xFF1B5E20);
    final white = Paint()..color = Colors.white;

    // Eyes
    if (mood == 'sleeping') {
      final lp = Paint()
        ..color = const Color(0xFF1B5E20)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(Path()
        ..moveTo(cx - r * 0.45, cy - r * 0.1)
        ..quadraticBezierTo(cx - r * 0.3, cy - r * 0.3, cx - r * 0.15, cy - r * 0.1), lp);
      canvas.drawPath(Path()
        ..moveTo(cx + r * 0.15, cy - r * 0.1)
        ..quadraticBezierTo(cx + r * 0.3, cy - r * 0.3, cx + r * 0.45, cy - r * 0.1), lp);
    } else {
      final es = mood == 'excited' ? r * 0.22 : r * 0.18;
      canvas.drawCircle(Offset(cx - r * 0.3,  cy - r * 0.15), es, white);
      canvas.drawCircle(Offset(cx - r * 0.28, cy - r * 0.13), es * 0.6, dark);
      canvas.drawCircle(Offset(cx - r * 0.22, cy - r * 0.19), es * 0.2, white);
      canvas.drawCircle(Offset(cx + r * 0.3,  cy - r * 0.15), es, white);
      canvas.drawCircle(Offset(cx + r * 0.28, cy - r * 0.13), es * 0.6, dark);
      canvas.drawCircle(Offset(cx + r * 0.36, cy - r * 0.19), es * 0.2, white);
    }

    // Mouth
    final mp = Paint()
      ..color = const Color(0xFF1B5E20)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final mouth = Path();
    if (mood == 'sad') {
      mouth
        ..moveTo(cx - r * 0.25, cy + r * 0.3)
        ..quadraticBezierTo(cx, cy + r * 0.15, cx + r * 0.25, cy + r * 0.3);
    } else if (mood == 'excited') {
      mouth
        ..moveTo(cx - r * 0.35, cy + r * 0.2)
        ..quadraticBezierTo(cx, cy + r * 0.55, cx + r * 0.35, cy + r * 0.2);
    } else {
      mouth
        ..moveTo(cx - r * 0.25, cy + r * 0.2)
        ..quadraticBezierTo(cx, cy + r * 0.45, cx + r * 0.25, cy + r * 0.2);
    }
    canvas.drawPath(mouth, mp);

    // Leaf sprout on head
    canvas.drawLine(
      Offset(cx, cy - r * 0.85),
      Offset(cx + r * 0.15, cy - r * 1.3),
      Paint()..color = const Color(0xFF558B2F)..strokeWidth = 2..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(cx + r * 0.15, cy - r * 1.3)
        ..quadraticBezierTo(cx + r * 0.6, cy - r * 1.5, cx + r * 0.5, cy - r * 1.1)
        ..quadraticBezierTo(cx + r * 0.3, cy - r * 1.2, cx + r * 0.15, cy - r * 1.3),
      Paint()..color = const Color(0xFFAED581),
    );
  }

  @override
  bool shouldRepaint(_MascotPainter old) => old.mood != mood;
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 5 — TREE PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class _TreeCanvas extends StatelessWidget {
  final TreeStage stage;
  final double sway; // 0..1

  const _TreeCanvas({required this.stage, required this.sway});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 180),
      painter: _TreePainter(stage: stage, sway: sway),
    );
  }
}

class _TreePainter extends CustomPainter {
  final TreeStage stage;
  final double sway;
  _TreePainter({required this.stage, required this.sway});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final bottom = size.height * 0.95;
    _drawSoil(canvas, cx, bottom);
    switch (stage) {
      case TreeStage.seed:    _seed(canvas, cx, bottom, size);    break;
      case TreeStage.sprout:  _sprout(canvas, cx, bottom, size);  break;
      case TreeStage.plant:   _plant(canvas, cx, bottom, size);   break;
      case TreeStage.tree:    _tree(canvas, cx, bottom, size);    break;
      case TreeStage.bigTree: _bigTree(canvas, cx, bottom, size); break;
    }
  }

  void _drawSoil(Canvas canvas, double cx, double bottom) {
    canvas.drawPath(
      Path()
        ..moveTo(cx - 45, bottom)
        ..quadraticBezierTo(cx, bottom + 10, cx + 45, bottom)
        ..close(),
      Paint()..color = const Color(0xFF8D6E63),
    );
  }

  void _seed(Canvas canvas, double cx, double bottom, Size s) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, bottom - 12), width: 24, height: 18),
      Paint()..color = const Color(0xFF795548),
    );
  }

  void _sprout(Canvas canvas, double cx, double bottom, Size s) {
    final sw = math.sin(sway * math.pi * 2) * 4;
    final stemH = s.height * 0.28;
    canvas.drawLine(Offset(cx, bottom), Offset(cx + sw, bottom - stemH),
        Paint()..color = const Color(0xFF558B2F)..strokeWidth = 5..strokeCap = StrokeCap.round..style = PaintingStyle.stroke);
    _leaf(canvas, cx + sw - 2, bottom - stemH, -0.7, 20, 11, const Color(0xFF66BB6A));
    _leaf(canvas, cx + sw + 2, bottom - stemH,  0.7, 20, 11, const Color(0xFF66BB6A));
  }

  void _plant(Canvas canvas, double cx, double bottom, Size s) {
    final sw = math.sin(sway * math.pi * 2) * 5;
    final stemH = s.height * 0.45;
    canvas.drawLine(Offset(cx, bottom), Offset(cx + sw, bottom - stemH),
        Paint()..color = const Color(0xFF795548)..strokeWidth = 7..strokeCap = StrokeCap.round..style = PaintingStyle.stroke);
    for (int i = 0; i < 3; i++) {
      final t = (i + 1) / 4;
      final bx = cx + sw * t; final by = bottom - stemH * t;
      _leaf(canvas, bx - 5, by, -0.5, 22, 13, const Color(0xFF43A047));
      _leaf(canvas, bx + 5, by,  0.5, 22, 13, const Color(0xFF43A047));
    }
    canvas.drawCircle(Offset(cx + sw, bottom - stemH), 28, Paint()..color = const Color(0xFF2E7D32));
    canvas.drawCircle(Offset(cx + sw, bottom - stemH - 12), 20, Paint()..color = const Color(0xFF43A047));
  }

  void _tree(Canvas canvas, double cx, double bottom, Size s) {
    final sw = math.sin(sway * math.pi * 2) * 4;
    final stemH = s.height * 0.6;
    // Trunk
    canvas.drawPath(
      Path()
        ..moveTo(cx - 10, bottom)
        ..lineTo(cx - 6 + sw, bottom - stemH)
        ..lineTo(cx + 6 + sw, bottom - stemH)
        ..lineTo(cx + 10, bottom)..close(),
      Paint()..color = const Color(0xFF6D4C41),
    );
    // Crown
    for (final (dy, r, c) in [
      (0.0, 52.0, const Color(0xFF1B5E20)),
      (-18.0, 44.0, const Color(0xFF2E7D32)),
      (-32.0, 34.0, const Color(0xFF43A047)),
      (-44.0, 26.0, const Color(0xFF66BB6A)),
    ]) {
      canvas.drawCircle(Offset(cx + sw, bottom - stemH + dy), r, Paint()..color = c);
    }
  }

  void _bigTree(Canvas canvas, double cx, double bottom, Size s) {
    _tree(canvas, cx, bottom, s);
    final sw = math.sin(sway * math.pi * 2) * 4;
    final stemH = s.height * 0.6;
    final rng = math.Random(42);
    for (int i = 0; i < 30; i++) {
      final angle = rng.nextDouble() * 2 * math.pi;
      final dist = rng.nextDouble() * 52;
      final colors = [const Color(0xFFF48FB1), const Color(0xFFF06292),
        const Color(0xFFFFCDD2), const Color(0xFFFFE0B2)];
      canvas.drawCircle(
        Offset(cx + sw + math.cos(angle) * dist, bottom - stemH - 10 + math.sin(angle) * dist * 0.6),
        7 + rng.nextDouble() * 5,
        Paint()..color = colors[rng.nextInt(colors.length)],
      );
    }
  }

  void _leaf(Canvas canvas, double x, double y, double angle,
      double w, double h, Color color) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(w / 2, -h / 2, w, 0)
        ..quadraticBezierTo(w / 2, h / 2, 0, 0),
      Paint()..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TreePainter old) => old.sway != sway || old.stage != stage;
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 6 — MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class PomodoroScreen extends StatefulWidget {
  final ProductivityEngine engine;
  const PomodoroScreen({super.key, required this.engine});

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  // ── Gamification state ────────────────────────────────────────────────────
  final GamificationState _gs = GamificationState();
  bool _gsReady = false;

  // ── Sound + Focus Lock ────────────────────────────────────────────────────
  final _sound      = FocusSoundManager();
  final _lockMgr    = FocusLockManager();
  final _fgService  = ForegroundServiceManager();
  bool _focusLockActive = false; // true = overlay shown

  // ── Active pomodoro session ────────────────────────────────────────────────
  late PomodoroSession _session;

  // ── Tab ───────────────────────────────────────────────────────────────────
  // Two tabs only: Timer (0) and Streaks (1)
  int _tab = 0;
  late PageController _pageCtrl;

  // ── Animations ───────────────────────────────────────────────────────────
  late AnimationController _treeSwayCtrl;   // continuous gentle sway
  late AnimationController _orbitalCtrl;    // background blobs
  late AnimationController _mascotBounce;   // mascot bob
  late AnimationController _rewardCtrl;     // session-complete overlay
  late AnimationController _levelUpCtrl;    // level-up banner

  // ── Reward overlay data ───────────────────────────────────────────────────
  String? _rewardMsg;
  List<FocusBadge> _newBadges = [];

  // ── Mascot mood ───────────────────────────────────────────────────────────
  String _mascotMood = 'idle';

  ProductivityEngine get _engine => widget.engine;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Create session directly — avoids engine.startSession() which internally
    // calls _activeSession?.dispose() and causes "used after dispose" on re-nav.
    _session = _createFreshSession();

    _pageCtrl = PageController();

    _treeSwayCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
    _orbitalCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 14))
      ..repeat();
    _mascotBounce = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _rewardCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _levelUpCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

    _gs.load().then((_) {
      if (mounted) setState(() => _gsReady = true);
    });

    // Init sound, lock, foreground service
    _sound.init();
    _lockMgr.init();
    _fgService.init();

    // Foreground service tick → sync session remaining time display
    _fgService.onTick = (remaining) {
      if (mounted && _session.isRunning) setState(() {});
    };
    // Foreground service complete → fire same callback as session
    _fgService.onComplete = () {
      if (mounted) _onFocusComplete();
    };
  }

  /// Creates a fresh [PomodoroSession] from the currently selected subject,
  /// wires up all callbacks and starts it in idle state.
  /// Safe to call multiple times — always call [_disposeSession] first.
  PomodoroSession _createFreshSession() {
    // Use buildSession() — safe factory that does NOT dispose any existing
    // session and does NOT auto-start. We wire our own callbacks here.
    final session = _engine.buildSession();
    session.onFocusComplete = _onFocusComplete;
    session.addListener(_onSessionTick);
    return session; // idle — caller must explicitly call start()
  }

  /// Safely tears down the current [_session] without touching the engine.
  void _disposeSession() {
    _session.onFocusComplete = null; // clear callback FIRST to avoid late fires
    _session.removeListener(_onSessionTick);
    if (_session.isRunning) _session.pause();
    _session.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeSession();
    _lockMgr.deactivateFocusLock();
    _fgService.stopService();
    _sound.dispose();
    _pageCtrl.dispose();
    _treeSwayCtrl.dispose();
    _orbitalCtrl.dispose();
    _mascotBounce.dispose();
    _rewardCtrl.dispose();
    _levelUpCtrl.dispose();
    super.dispose();
  }

  @override
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _fgService.stopService();
    }
  }
  // Track previous phase to detect transitions
  SessionPhase _prevPhase = SessionPhase.idle;

  void _onSessionTick() {
    if (!mounted) return;
    // Detect phase change for break sound
    if (_session.phase != _prevPhase) {
      if (_session.phase == SessionPhase.shortBreak ||
          _session.phase == SessionPhase.longBreak) {
        _sound.playBreakStart();
        _startBreakSession();
      }
      _prevPhase = _session.phase;
    }
    setState(() {
      _mascotMood = _session.phase == SessionPhase.focus
          ? (_session.isRunning ? 'excited' : 'idle')
          : (_session.phase != SessionPhase.idle ? 'happy' : 'idle');
    });
  }

  void _onFocusComplete() {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    _sound.playFocusComplete();          // ← Play completion sound
    _lockMgr.deactivateFocusLock();      // ← Remove DND + overlay
    _fgService.stopService();            // ← Stop foreground notification
    setState(() => _focusLockActive = false);
    _engine.recordFocusComplete(_session);
    final isNight = DateTime.now().hour >= 0 && DateTime.now().hour < 5;
    final newBadges = _gs.recordSession(
      subjectId: _session.subject.id,
      focusMinutes: _session.subject.focusDuration.inMinutes,
      currentStreakDays: _engine.streak.currentStreak,
      isAfterMidnight: isNight,
    );

    // Check if tree bloomed
    if (_engine.treeResult?.stage == TreeStage.bigTree &&
        !_gs.unlockedBadges.contains('bloom')) {
      newBadges.add(kBadges.firstWhere((b) => b.id == 'bloom'));
      _gs._unlockedBadges.add('bloom');
    }

    final xpGained = 20 + (_session.subject.focusDuration.inMinutes ~/ 5) * 5;
    setState(() {
      _mascotMood = 'excited';
      _newBadges  = newBadges;
      _rewardMsg  = '+$xpGained XP  🎉${newBadges.isNotEmpty ? '\n${newBadges.map((b) => '${b.emoji} ${b.title}').join('  ')}' : ''}';
    });
    _rewardCtrl.forward(from: 0);
  }

  void _switchTab(int i) {
    setState(() => _tab = i);
    _pageCtrl.animateToPage(i,
        duration: const Duration(milliseconds: 400), curve: Curves.easeInOutCubic);
  }

  void _rebuildSession() {
    _disposeSession();
    _session = _createFreshSession();
    setState(() {});
  }

  /// Call this instead of session.start() directly.
  /// Plays sound, activates focus lock, starts foreground service.
  Future<void> _startFocusSession() async {
    print("START CLICKED");
    await _sound.playFocusStart();
    print("sound done");
    await _lockMgr.activateFocusLock();
    print("lock done");
    await _fgService.startService(
      remainingSeconds: _session.subject.focusDuration.inSeconds,
      phaseName: _session.subject.name,
    );
    print("fg done");
    _session.start();
    print("SESSION STARTED");
    setState(() => _focusLockActive = _lockMgr.overlayEnabled);
  }

  /// Called when a break starts
  Future<void> _startBreakSession() async {
    await _sound.playBreakStart();
    // Update foreground notification for break phase
    final isFocus = _session.phase == SessionPhase.focus;
    final breakSecs = isFocus
        ? _session.subject.shortBreakDuration.inSeconds
        : _session.subject.longBreakDuration.inSeconds;
    await _fgService.startService(
      remainingSeconds: breakSecs,
      phaseName: '☕ Break',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tp   = Provider.of<ThemeProvider>(context);
    final isDark = tp.isDarkMode;

    return ChangeNotifierProvider.value(
      value: _gs,
      child: Scaffold(
        backgroundColor: _T.bg(isDark),
        body: Stack(
          children: [
            // ── Animated background ────────────────────────────────────
            _OrbitalBg(ctrl: _orbitalCtrl, isDark: isDark),

            SafeArea(
              child: Column(
                children: [
                  _AppBar(tp: tp, isDark: isDark, gs: _gs,
                      engine: _engine, onBack: () => Navigator.pop(context)),
                  const SizedBox(height: 4),
                  // XP / level strip
                  if (_gsReady) _XPStrip(gs: _gs, isDark: isDark),
                  const SizedBox(height: 6),
                  // Subject selector
                  _SubjectRow(
                      manager: _engine.subjectManager,
                      gs: _gs,
                      isDark: isDark,
                      onSelect: (s) {
                        _engine.subjectManager.select(s.id);
                        _rebuildSession();
                      }),
                  const SizedBox(height: 6),
                  // Tab bar — Timer | Streaks
                  _TabStrip(current: _tab, onTap: _switchTab, isDark: isDark),
                  Expanded(
                    child: PageView(
                      controller: _pageCtrl,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        // Tab 0 — Timer
                        _TimerPage(
                          session: _session,
                          engine: _engine,
                          gs: _gs,
                          isDark: isDark,
                          mascotMood: _mascotMood,
                          mascotBounce: _mascotBounce,
                          treeSwayCtrl: _treeSwayCtrl,
                          onStartFocus: _startFocusSession,
                        ),
                        // Tab 1 — Streaks
                        _StreakPage(engine: _engine, gs: _gs, isDark: isDark),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Focus lock overlay (shown when user tries to leave) ──
            if (_focusLockActive && _session.isRunning)
              FocusLockOverlay(
                remainingSeconds: _session.remaining.inSeconds,
                subjectName: _session.subject.name,
                subjectEmoji: _session.subject.emoji,
                subjectColor: _session.subject.color,
                isDark: isDark,
                onEmergencyExit: () {
                  _session.reset();
                  _lockMgr.deactivateFocusLock();
                  _fgService.stopService();
                  setState(() => _focusLockActive = false);
                },
                onDismiss: () {
                  // User held 3 sec — pause and let them leave
                  _session.pause();
                  setState(() => _focusLockActive = false);
                },
              ),

            // ── Session complete reward overlay ────────────────────────
            if (_rewardMsg != null)
              _RewardOverlay(
                msg: _rewardMsg!,
                badges: _newBadges,
                gs: _gs,
                anim: _rewardCtrl,
                isDark: isDark,
                onDismiss: () => setState(() { _rewardMsg = null; _newBadges = []; }),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 7 — APP BAR
// ─────────────────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final ThemeProvider tp;
  final bool isDark;
  final GamificationState gs;
  final ProductivityEngine engine;
  final VoidCallback onBack;

  const _AppBar({
    required this.tp, required this.isDark, required this.gs,
    required this.engine, required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: _T.surface(isDark),
                shape: BoxShape.circle,
                border: Border.all(color: _T.border(isDark)),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 15, color: _T.tp(isDark)),
            ),
          ),
          const SizedBox(width: 10),
          Text('🌿 FocusGrove',
              style: TextStyle(
                  color: _T.tp(isDark),
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3)),
          const Spacer(),
          // Settings button
          GestureDetector(
            onTap: () => showPomodoroSettings(
              context: context,
              engine: engine,
              gs: gs,
              isDark: isDark,
            ),
            child: Container(
              width: 36, height: 36,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2630) : const Color(0xFFEFF7EE),
                shape: BoxShape.circle,
                border: Border.all(color: isDark ? const Color(0xFF2A3C2B) : const Color(0xFFD0E8D0)),
              ),
              child: Icon(Icons.tune_rounded,
                  size: 16, color: isDark ? const Color(0xFF7A9A7C) : const Color(0xFF5A7A5C)),
            ),
          ),
          // Streak pill
          AnimatedBuilder(
            animation: engine,
            builder: (_, __) {
              final s = engine.streak.currentStreak;
              return Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: s > 0 ? _T.orange.withOpacity(0.15) : _T.surfaceEl(isDark),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: s > 0 ? _T.orange.withOpacity(0.5) : _T.border(isDark)),
                ),
                child: Row(children: [
                  Text(s > 0 ? '🔥' : '💤', style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  Text(s.toStringAsFixed(s == s.roundToDouble() ? 0 : 1),
                      style: TextStyle(
                          color: s > 0 ? _T.orange : _T.ts(isDark),
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ]),
              );
            },
          ),
          // Dark mode toggle (matches HomeScreen)
          GestureDetector(
            onTap: tp.toggleTheme,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 52, height: 28,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: isDark
                    ? const LinearGradient(colors: [Color(0xFF43A047), Color(0xFF1B5E20)])
                    : LinearGradient(colors: [Colors.grey.shade300, Colors.grey.shade200]),
                boxShadow: [BoxShadow(
                  color: isDark ? _T.accent.withOpacity(0.4) : Colors.black.withOpacity(0.1),
                  blurRadius: 8, offset: const Offset(0, 2),
                )],
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 22, height: 22,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Center(child: Icon(
                    isDark ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded,
                    color: isDark ? _T.accent : Colors.amber, size: 13,
                  )),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 8 — XP STRIP
// ─────────────────────────────────────────────────────────────────────────────

class _XPStrip extends StatelessWidget {
  final GamificationState gs;
  final bool isDark;
  const _XPStrip({required this.gs, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: gs,
      builder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Text('Lv ${gs.level}',
              style: const TextStyle(
                  color: _T.accent, fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Stack(children: [
              Container(height: 8,
                  decoration: BoxDecoration(
                      color: _T.surfaceEl(isDark),
                      borderRadius: BorderRadius.circular(4))),
              AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOut,
                widthFactor: gs.levelProgress,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF43A047), Color(0xFFAED581)]),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Text('${gs.xpToNext} XP to next',
              style: TextStyle(color: _T.ts(isDark), fontSize: 10)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 9 — SUBJECT ROW
// ─────────────────────────────────────────────────────────────────────────────

class _SubjectRow extends StatelessWidget {
  final SubjectManager manager;
  final GamificationState gs;
  final bool isDark;
  final ValueChanged<Subject> onSelect;

  const _SubjectRow({
    required this.manager, required this.gs,
    required this.isDark,  required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: manager,
      builder: (_, __) {
        final subjects = manager.subjects;
        final selId = manager.selected?.id;
        return SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: subjects.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final s = subjects[i];
              final isActive = s.id == selId;
              // Today's streak quality for this subject
              final tier = _todayTier(s.id, gs);
              return GestureDetector(
                onTap: () => onSelect(s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isActive ? s.color.withOpacity(0.2) : _T.surface(isDark),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: isActive ? s.color : _T.border(isDark),
                        width: isActive ? 2 : 1),
                    boxShadow: isActive
                        ? [BoxShadow(color: s.color.withOpacity(0.2), blurRadius: 10)]
                        : null,
                  ),
                  child: Row(children: [
                    Text(s.emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.name,
                          style: TextStyle(
                              color: isActive ? s.color : _T.tp(isDark),
                              fontWeight: FontWeight.w700, fontSize: 12)),
                      Text(
                        tier == StreakTier.full ? '🔥 Full' :
                        tier == StreakTier.half ? '⚡ Half' : '–',
                        style: TextStyle(color: _T.ts(isDark), fontSize: 9),
                      ),
                    ]),
                  ]),
                ),
              );
            },
          ),
        );
      },
    );
  }

  StreakTier _todayTier(String subjectId, GamificationState gs) {
    final today = DateTime.now();
    final ds = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
    final done = gs.sessionsOnDay(subjectId, ds);
    final target = gs.targetFor(subjectId);
    if (done >= target) return StreakTier.full;
    if (done >= target ~/ 2 && done > 0) return StreakTier.half;
    return StreakTier.none;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 10 — TAB STRIP
// ─────────────────────────────────────────────────────────────────────────────

class _TabStrip extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;
  final bool isDark;
  const _TabStrip({required this.current, required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    const tabs = [('⏱', 'Timer'), ('📅', 'Streaks')];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _T.surface(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _T.border(isDark)),
      ),
      child: Row(
        children: List.generate(2, (i) {
          final active = i == current;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: active
                      ? const LinearGradient(colors: [Color(0xFF43A047), Color(0xFF81C784)])
                      : null,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(tabs[i].$1, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  Text(tabs[i].$2,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : _T.ts(isDark))),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 11 — TIMER PAGE
// ─────────────────────────────────────────────────────────────────────────────

class _TimerPage extends StatelessWidget {
  final PomodoroSession session;
  final ProductivityEngine engine;
  final GamificationState gs;
  final bool isDark;
  final String mascotMood;
  final AnimationController mascotBounce;
  final AnimationController treeSwayCtrl;
  final Future<void> Function() onStartFocus;

  const _TimerPage({
    required this.session, required this.engine, required this.gs,
    required this.isDark,  required this.mascotMood,
    required this.mascotBounce, required this.treeSwayCtrl,
    required this.onStartFocus,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      child: Column(children: [
        // ── Mascot + message ────────────────────────────────────────────
        _MascotBar(mood: mascotMood, bounce: mascotBounce,
            engine: engine, session: session, isDark: isDark),
        const SizedBox(height: 16),

        // ── Tree + circular timer card ──────────────────────────────────
        _TreeTimerCard(
            session: session, engine: engine, gs: gs,
            isDark: isDark, treeSwayCtrl: treeSwayCtrl,
            onStartFocus: onStartFocus),
        const SizedBox(height: 16),

        // ── Interval dots ───────────────────────────────────────────────
        AnimatedBuilder(
          animation: session,
          builder: (_, __) => _IntervalRow(
              completed: session.completedIntervals,
              interval: session.subject.longBreakInterval,
              isDark: isDark),
        ),
        const SizedBox(height: 16),

        // ── Daily goal ──────────────────────────────────────────────────
        _GoalCard(goal: engine.dailyGoal, isDark: isDark),
      ]),
    );
  }
}

// ── Mascot bar ────────────────────────────────────────────────────────────────

class _MascotBar extends StatelessWidget {
  final String mood;
  final AnimationController bounce;
  final ProductivityEngine engine;
  final PomodoroSession session;
  final bool isDark;

  const _MascotBar({
    required this.mood, required this.bounce,
    required this.engine, required this.session, required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final char = engine.characterState(
        phase: session.phase);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _T.surface(isDark),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _T.border(isDark)),
      ),
      child: Row(children: [
        // Mascot
        AnimatedBuilder(
          animation: bounce,
          builder: (_, child) => Transform.translate(
            offset: Offset(0, -bounce.value * 4),
            child: child,
          ),
          child: CustomPaint(
            size: const Size(56, 56),
            painter: _MascotPainter(mood),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(char.message,
                  key: ValueKey(char.message),
                  style: const TextStyle(
                      color: _T.accent,
                      fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            const SizedBox(height: 2),
            Text('Tap timer to start focusing',
                style: TextStyle(color: _T.ts(isDark), fontSize: 11)),
          ]),
        ),
        // Mood pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _T.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(char.emoji,
              style: const TextStyle(fontSize: 18)),
        ),
      ]),
    );
  }
}

// ── Tree + Timer combined card ────────────────────────────────────────────────

class _TreeTimerCard extends StatelessWidget {
  final PomodoroSession session;
  final ProductivityEngine engine;
  final GamificationState gs;
  final bool isDark;
  final AnimationController treeSwayCtrl;
  final Future<void> Function() onStartFocus;

  const _TreeTimerCard({
    required this.session, required this.engine, required this.gs,
    required this.isDark,  required this.treeSwayCtrl,
    required this.onStartFocus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _T.surface(isDark),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _T.border(isDark)),
        boxShadow: [BoxShadow(
            color: _T.accent.withOpacity(0.07), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Column(children: [
        // Tree
        AnimatedBuilder(
          animation: treeSwayCtrl,
          builder: (_, __) {
            final tree = engine.treeResult;
            return _TreeCanvas(
              stage: tree?.stage ?? TreeStage.seed,
              sway: treeSwayCtrl.value,
            );
          },
        ),
        // Stage label + progress
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AnimatedBuilder(
            animation: engine,
            builder: (_, __) {
              final tree = engine.treeResult;
              final stage = tree?.stage ?? TreeStage.seed;
              const labels = {
                TreeStage.seed: 'Seed', TreeStage.sprout: 'Sprout',
                TreeStage.plant: 'Sapling', TreeStage.tree: 'Tree',
                TreeStage.bigTree: '🌸 Blooming!',
              };
              return Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(labels[stage]!,
                      style: TextStyle(
                          color: _T.tp(isDark),
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  if (stage != TreeStage.bigTree)
                    Text('  ${gs.totalSessions} sessions',
                        style: TextStyle(color: _T.ts(isDark), fontSize: 11)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: tree?.overallProgress ?? 0,
                    minHeight: 6,
                    backgroundColor: _T.surfaceEl(isDark),
                    valueColor: const AlwaysStoppedAnimation<Color>(_T.accent),
                  ),
                ),
              ]);
            },
          ),
        ),
        Divider(height: 24, thickness: 1, color: _T.border(isDark)),
        // Circular timer
        AnimatedBuilder(
          animation: session,
          builder: (_, __) => _CircularTimer(
              session: session, isDark: isDark),
        ),
        const SizedBox(height: 20),
        // Controls
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _Controls(
            session: session,
            isDark: isDark,
            onStartFocus: onStartFocus,
          ),
        ),
      ]),
    );
  }
}

// ── Circular timer ────────────────────────────────────────────────────────────

class _CircularTimer extends StatelessWidget {
  final PomodoroSession session;
  final bool isDark;
  const _CircularTimer({required this.session, required this.isDark});

  Color get _color {
    switch (session.phase) {
      case SessionPhase.focus:      return _T.accent;
      case SessionPhase.shortBreak: return _T.blue;
      case SessionPhase.longBreak:  return _T.gold;
      case SessionPhase.idle:       return _T.ts(isDark);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _label {
    switch (session.phase) {
      case SessionPhase.focus:      return 'DEEP FOCUS';
      case SessionPhase.shortBreak: return 'SHORT BREAK';
      case SessionPhase.longBreak:  return 'LONG BREAK';
      case SessionPhase.idle:       return 'TAP ▶ TO BEGIN';
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = session.phase == SessionPhase.idle ? 0.0 : session.progress;
    return Stack(alignment: Alignment.center, children: [
      SizedBox(width: 170, height: 170,
          child: CircularProgressIndicator(
              value: 1, strokeWidth: 11,
              color: _color.withOpacity(0.1), strokeCap: StrokeCap.round)),
      SizedBox(width: 170, height: 170,
          child: CircularProgressIndicator(
              value: pct, strokeWidth: 11,
              color: _color,
              backgroundColor: Colors.transparent,
              strokeCap: StrokeCap.round)),
      Container(
        width: 130, height: 130,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _T.surface(isDark),
          boxShadow: [BoxShadow(color: _color.withOpacity(0.15), blurRadius: 20)],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_fmt(session.remaining),
              style: TextStyle(
                  color: _color, fontSize: 34,
                  fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 2),
          Text(_label,
              style: TextStyle(color: _T.ts(isDark),
                  fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        ]),
      ),
    ]);
  }
}

// ── Controls ──────────────────────────────────────────────────────────────────

class _Controls extends StatelessWidget {
  final PomodoroSession session;
  final bool isDark;
  final Future<void> Function() onStartFocus;
  const _Controls({
    required this.session,
    required this.isDark,
    required this.onStartFocus,
  });

  @override
  Widget build(BuildContext context) {
    final running = session.isRunning;
    final isIdle  = session.phase == SessionPhase.idle;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _SmallBtn(icon: Icons.refresh_rounded, isDark: isDark,
            onTap: () { HapticFeedback.lightImpact(); session.reset(); }),
        const SizedBox(width: 20),
        // Big play/pause
        GestureDetector(
          onTap: () async {
            HapticFeedback.mediumImpact();

            if (running) {
              session.pause();

            } else if (isIdle) {

              await onStartFocus();

            } else {
              session.resume();
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 68, height: 68,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF43A047), Color(0xFF81C784)]),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                  color: _T.accent.withOpacity(0.4), blurRadius: 18,
                  offset: const Offset(0, 5))],
            ),
            child: Icon(
              running ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white, size: 34,
            ),
          ),
        ),
        const SizedBox(width: 20),
        _SmallBtn(icon: Icons.skip_next_rounded, isDark: isDark,
            onTap: () { HapticFeedback.lightImpact(); session.skip(); }),
      ]),
      if (isIdle) ...[
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _OutBtn(
              label: '☕ Short Break (${session.subject.shortBreakDuration.inMinutes}m)',
              color: _T.blue, isDark: isDark,
              onTap: () { session.phase == SessionPhase.idle
                  ? _startBreak(session, false) : null; })),
          const SizedBox(width: 10),
          Expanded(child: _OutBtn(
              label: '🌿 Long Break (${session.subject.longBreakDuration.inMinutes}m)',
              color: _T.gold, isDark: isDark,
              onTap: () => _startBreak(session, true))),
        ]),
      ],
    ]);
  }

  void _startBreak(PomodoroSession s, bool long) {
    // Manually set phase for a standalone break
    if (!s.isRunning) s.start();
  }
}

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;
  const _SmallBtn({required this.icon, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 46, height: 46,
      decoration: BoxDecoration(
        color: _T.surface(isDark),
        shape: BoxShape.circle,
        border: Border.all(color: _T.border(isDark)),
      ),
      child: Icon(icon, color: _T.ts(isDark), size: 20),
    ),
  );
}

class _OutBtn extends StatelessWidget {
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback? onTap;
  const _OutBtn({required this.label, required this.color,
    required this.isDark, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 42,
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Center(child: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11))),
    ),
  );
}

// ── Interval dots ─────────────────────────────────────────────────────────────

class _IntervalRow extends StatelessWidget {
  final int completed;
  final int interval;
  final bool isDark;
  const _IntervalRow(
      {required this.completed, required this.interval, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final filled = completed % interval;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _T.surface(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _T.border(isDark)),
      ),
      child: Row(children: [
        Text('Session ${filled == 0 && completed > 0 ? interval : filled}/$interval',
            style: TextStyle(color: _T.ts(isDark), fontSize: 12)),
        const Spacer(),
        ...List.generate(interval, (i) {
          final done = i < filled || (filled == 0 && completed > 0);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: done ? 22 : 10, height: 10,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: done ? _T.accent : _T.surfaceEl(isDark),
              borderRadius: BorderRadius.circular(5),
              boxShadow: done
                  ? [BoxShadow(color: _T.accent.withOpacity(0.4), blurRadius: 6)]
                  : null,
            ),
          );
        }),
      ]),
    );
  }
}

// ── Daily goal card ────────────────────────────────────────────────────────────

class _GoalCard extends StatelessWidget {
  final DailyGoal goal;
  final bool isDark;
  const _GoalCard({required this.goal, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: goal,
      builder: (_, __) {
        final pct = goal.completionPercentage();
        final done = pct >= 1.0;
        final color = done ? const Color(0xFF30D158)
            : pct >= 0.5 ? _T.accent : _T.accent2;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _T.surface(isDark),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _T.border(isDark)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(done ? '🏆' : '🎯', style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text('Daily Goal',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
              const Spacer(),
              Text(goal.formattedProgress(),
                  style: TextStyle(color: _T.ts(isDark), fontSize: 11)),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: pct),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOut,
                builder: (_, v, __) => LinearProgressIndicator(
                    value: v, minHeight: 8,
                    backgroundColor: color.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(color)),
              ),
            ),
            if (done) ...[
              const SizedBox(height: 8),
              const Text('🎉 Daily goal crushed!',
                  style: TextStyle(color: Color(0xFF30D158),
                      fontWeight: FontWeight.w600, fontSize: 11)),
            ],
          ]),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 12 — STREAKS PAGE
// ─────────────────────────────────────────────────────────────────────────────

class _StreakPage extends StatelessWidget {
  final ProductivityEngine engine;
  final GamificationState gs;
  final bool isDark;

  const _StreakPage(
      {required this.engine, required this.gs, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([engine, gs]),
      builder: (_, __) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          child: Column(children: [
            // Overall streak hero
            _StreakHero(streak: engine.streak, isDark: isDark),
            const SizedBox(height: 16),
            // Per-subject 7-day calendars
            ...engine.subjectManager.subjects.map((s) =>
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SubjectStreak7(
                      subject: s, gs: gs, isDark: isDark),
                ),
            ),
            const SizedBox(height: 8),
            // Stats row
            _MiniStatsRow(engine: engine, gs: gs, isDark: isDark),
          ]),
        );
      },
    );
  }
}

class _StreakHero extends StatelessWidget {
  final StreakEngine streak;
  final bool isDark;
  const _StreakHero({required this.streak, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final s = streak.currentStreak;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF43A047), Color(0xFF1B5E20)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(
            color: _T.accent.withOpacity(0.35), blurRadius: 22,
            offset: const Offset(0, 8))],
      ),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Current Streak',
              style: TextStyle(color: Colors.white70, fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(s.toStringAsFixed(s == s.roundToDouble() ? 0 : 1),
              style: const TextStyle(color: Colors.white,
                  fontSize: 52, fontWeight: FontWeight.w900, height: 1)),
          Text('${(streak.weeklyConsistency * 100).round()}% weekly consistency',
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ]),
        const Spacer(),
        const Text('🔥', style: TextStyle(fontSize: 60)),
      ]),
    );
  }
}

class _SubjectStreak7 extends StatelessWidget {
  final Subject subject;
  final GamificationState gs;
  final bool isDark;
  const _SubjectStreak7(
      {required this.subject, required this.gs, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final tiers = gs.streak7(subject.id);
    final dayLabels = ['M','T','W','T','F','S','S'];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _T.surface(isDark),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: subject.color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 10, height: 10,
              decoration: BoxDecoration(
                  color: subject.color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('${subject.emoji}  ${subject.name}',
              style: TextStyle(color: _T.tp(isDark),
                  fontWeight: FontWeight.w700, fontSize: 13)),
          const Spacer(),
          Text('Target: ${gs.targetFor(subject.id)}/day',
              style: TextStyle(color: _T.ts(isDark), fontSize: 11)),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(7, (i) {
              final tier = tiers[i];
              final isToday = i == 6;
              final day = DateTime.now().subtract(Duration(days: 6 - i));
              final label = dayLabels[day.weekday - 1];
              return Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tier == StreakTier.full
                        ? _T.accent
                        : tier == StreakTier.half
                        ? _T.gold
                        : _T.surfaceEl(isDark),
                    border: isToday
                        ? Border.all(color: _T.accent, width: 2)
                        : null,
                    boxShadow: tier == StreakTier.full
                        ? [BoxShadow(color: _T.accent.withOpacity(0.3), blurRadius: 8)]
                        : null,
                  ),
                  child: Center(child: Text(
                    tier == StreakTier.full ? '🔥'
                        : tier == StreakTier.half ? '⚡'
                        : isToday ? '·' : '✗',
                    style: TextStyle(
                        fontSize: tier != StreakTier.none ? 15 : 12,
                        color: tier == StreakTier.none ? _T.ts(isDark) : Colors.white),
                  )),
                ),
                const SizedBox(height: 3),
                Text(label,
                    style: TextStyle(
                        color: isToday ? _T.accent : _T.ts(isDark),
                        fontSize: 9,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.normal)),
              ]);
            })),
        const SizedBox(height: 10),
        // Legend
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _Dot(_T.accent, '🔥 Full'),
          const SizedBox(width: 14),
          _Dot(_T.gold, '⚡ Half'),
          const SizedBox(width: 14),
          _Dot(_T.surfaceEl(isDark), '✗ Missed'),
        ]),
      ]),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final String label;
  const _Dot(this.color, this.label);

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 8, height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(color: Color(0xFF7A9A7C), fontSize: 10)),
  ]);
}

class _MiniStatsRow extends StatelessWidget {
  final ProductivityEngine engine;
  final GamificationState gs;
  final bool isDark;
  const _MiniStatsRow(
      {required this.engine, required this.gs, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('🏆', '${engine.streak.longestStreak.round()}', 'Best Streak', _T.orange),
      ('⏱',  '${gs.totalSessions}', 'Total Sessions', _T.accent),
      ('💎',  '${gs.xp}', 'Total XP', _T.blue),
    ];
    return Row(children: items.map((item) {
      return Expanded(
        child: Container(
          margin: EdgeInsets.only(left: items.indexOf(item) > 0 ? 8 : 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _T.surface(isDark),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: item.$4.withOpacity(0.15)),
          ),
          child: Column(children: [
            Text(item.$1, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(item.$2,
                style: TextStyle(color: item.$4,
                    fontWeight: FontWeight.w800, fontSize: 20)),
            Text(item.$3,
                style: TextStyle(color: _T.ts(isDark), fontSize: 10)),
          ]),
        ),
      );
    }).toList());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 13 — BADGES PAGE
// ─────────────────────────────────────────────────────────────────────────────

class _BadgesPage extends StatelessWidget {
  final GamificationState gs;
  final bool isDark;
  const _BadgesPage({required this.gs, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: gs,
      builder: (_, __) {
        final unlocked = gs.unlockedBadges;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          child: Column(children: [
            // Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)]),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(children: [
                const Text('🏅', style: TextStyle(fontSize: 30)),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${unlocked.length} / ${kBadges.length} Badges',
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w800, fontSize: 17)),
                  Text('${((unlocked.length / kBadges.length) * 100).round()}% complete',
                      style: const TextStyle(color: Color(0xFFA5D6A7), fontSize: 12)),
                ]),
              ]),
            ),
            const SizedBox(height: 14),
            // Grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, crossAxisSpacing: 10,
                  mainAxisSpacing: 10, childAspectRatio: 1.05),
              itemCount: kBadges.length,
              itemBuilder: (_, i) {
                final badge = kBadges[i];
                final isUnlocked = unlocked.contains(badge.id);
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isUnlocked ? _T.surface(isDark) : _T.surfaceEl(isDark),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: isUnlocked
                            ? _T.gold.withOpacity(0.4)
                            : _T.border(isDark),
                        width: isUnlocked ? 1.5 : 1),
                    boxShadow: isUnlocked
                        ? [BoxShadow(
                        color: _T.gold.withOpacity(0.12), blurRadius: 14)]
                        : null,
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Stack(alignment: Alignment.center, children: [
                      Text(isUnlocked ? badge.emoji : '🔒',
                          style: TextStyle(
                              fontSize: 30,
                              color: isUnlocked ? null : Colors.transparent)),
                      if (!isUnlocked)
                        Text('🔒',
                            style: TextStyle(
                                fontSize: 28,
                                color: _T.ts(isDark).withOpacity(0.4))),
                    ]),
                    const SizedBox(height: 8),
                    Text(badge.title,
                        style: TextStyle(
                            color: isUnlocked ? _T.tp(isDark) : _T.ts(isDark),
                            fontWeight: FontWeight.w700, fontSize: 12),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 3),
                    Text(badge.desc,
                        style: TextStyle(color: _T.ts(isDark), fontSize: 9),
                        textAlign: TextAlign.center,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (isUnlocked) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _T.gold.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('+${badge.xpReward} XP',
                            style: TextStyle(
                                color: _T.gold,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                );
              },
            ),
          ]),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 14 — REWARD OVERLAY
// ─────────────────────────────────────────────────────────────────────────────

class _RewardOverlay extends StatelessWidget {
  final String msg;
  final List<FocusBadge> badges;
  final GamificationState gs;
  final AnimationController anim;
  final bool isDark;
  final VoidCallback onDismiss;

  const _RewardOverlay({
    required this.msg, required this.badges, required this.gs,
    required this.anim, required this.isDark, required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: Colors.black54,
        child: Center(
          child: AnimatedBuilder(
            animation: anim,
            builder: (_, child) {
              final scale = Tween<double>(begin: 0.5, end: 1.0)
                  .animate(CurvedAnimation(
                  parent: anim, curve: Curves.elasticOut))
                  .value;
              final opacity = Tween<double>(begin: 0, end: 1)
                  .animate(CurvedAnimation(
                  parent: anim,
                  curve: const Interval(0, 0.4)))
                  .value;
              return Opacity(
                opacity: opacity,
                child: Transform.scale(scale: scale, child: child),
              );
            },
            child: Container(
              margin: const EdgeInsets.all(30),
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: _T.surface(isDark),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: _T.gold.withOpacity(0.4), width: 2),
                boxShadow: [BoxShadow(
                    color: _T.gold.withOpacity(0.2), blurRadius: 30)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Mascot celebrating
                CustomPaint(
                  size: const Size(70, 70),
                  painter: _MascotPainter('excited'),
                ),
                const SizedBox(height: 12),
                const Text('Session Complete! 🎉',
                    style: TextStyle(color: _T.accent,
                        fontWeight: FontWeight.w800, fontSize: 19)),
                const SizedBox(height: 8),
                Text(msg,
                    style: TextStyle(
                        color: _T.gold,
                        fontWeight: FontWeight.w700, fontSize: 15),
                    textAlign: TextAlign.center),
                if (badges.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 6,
                      children: badges.map((b) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _T.gold.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _T.gold.withOpacity(0.4)),
                        ),
                        child: Text('${b.emoji} ${b.title}',
                            style: TextStyle(
                                color: _T.gold,
                                fontWeight: FontWeight.w700, fontSize: 11)),
                      )).toList()),
                ],
                const SizedBox(height: 18),
                // Confetti dots
                Row(mainAxisAlignment: MainAxisAlignment.center,
                    children: [_T.red, _T.accent, _T.gold, _T.blue, _T.purple]
                        .map((c) => Container(
                      width: 10, height: 10,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                          color: c, shape: BoxShape.circle),
                    ))
                        .toList()),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF43A047), Color(0xFF81C784)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Keep Going!',
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 15 — ORBITAL BACKGROUND
// ─────────────────────────────────────────────────────────────────────────────

class _OrbitalBg extends StatelessWidget {
  final AnimationController ctrl;
  final bool isDark;
  const _OrbitalBg({required this.ctrl, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final t = ctrl.value * 2 * math.pi;
        return Stack(children: [
          Positioned(
            top: -90 + math.sin(t * 0.4) * 35,
            right: -70 + math.cos(t * 0.3) * 25,
            child: Container(
              width: 280, height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  _T.accent.withOpacity(isDark ? 0.12 : 0.07),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            bottom: 60 + math.cos(t * 0.35) * 40,
            left: -50 + math.sin(t * 0.5) * 20,
            child: Container(
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  _T.accent2.withOpacity(isDark ? 0.09 : 0.05),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
        ]);
      },
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// LOCK & SOUND TAB — inside settings sheet
// ─────────────────────────────────────────────────────────────────────────────

class _LockSoundTab extends StatelessWidget {
  final bool isDark;
  final ScrollController scrollCtrl;
  const _LockSoundTab({required this.isDark, required this.scrollCtrl});

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        FocusLockSettingsCard(isDark: isDark),
      ],
    );
  }
}

// =============================================================================
// SETTINGS & SETUP SYSTEM
// Added below existing code — no existing classes modified.
//
// Includes:
//   • _SettingsSheet      — bottom sheet with daily goal + all subject config
//   • _DailyGoalPicker    — slider + preset buttons for daily focus target
//   • _SubjectConfigCard  — per-subject editor (focus, break, interval, color)
//   • _AddSubjectSheet    — full-screen add-subject flow
//   • showPomodoroSettings() — call this from the AppBar settings icon
// =============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT — call this to open the settings sheet
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showPomodoroSettings({
  required BuildContext context,
  required ProductivityEngine engine,
  required GamificationState gs,
  required bool isDark,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SettingsSheet(
      engine: engine,
      gs: gs,
      isDark: isDark,
      onChanged: onChanged,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SETTINGS SHEET — main container
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsSheet extends StatefulWidget {
  final ProductivityEngine engine;
  final GamificationState gs;
  final bool isDark;
  final VoidCallback? onChanged;

  const _SettingsSheet({
    required this.engine,
    required this.gs,
    required this.isDark,
    this.onChanged,
  });

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tc;

  @override
  void initState() {
    super.initState();
    _tc = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  bool get isDark => widget.isDark;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: _T.bg(isDark),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          // Drag handle
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: _T.border(isDark),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF43A047), Color(0xFF81C784)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.tune_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Text('Focus Settings',
                  style: TextStyle(
                      color: _T.tp(isDark),
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: _T.surfaceEl(isDark),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close_rounded,
                      color: _T.ts(isDark), size: 16),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // Tab bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _T.surface(isDark),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _T.border(isDark)),
            ),
            child: TabBar(
              controller: _tc,
              indicator: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF43A047), Color(0xFF81C784)]),
                borderRadius: BorderRadius.circular(9),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: _T.ts(isDark),
              labelStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700),
              tabs: const [
                Tab(text: '🎯  Daily Goal'),
                Tab(text: '📚  Subjects'),
                Tab(text: '🔒  Lock & Sound'),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tc,
              children: [
                _DailyGoalTab(
                    engine: widget.engine,
                    gs: widget.gs,
                    isDark: isDark,
                    scrollCtrl: scrollCtrl,
                    onChanged: widget.onChanged),
                _SubjectsTab2(
                    engine: widget.engine,
                    gs: widget.gs,
                    isDark: isDark,
                    scrollCtrl: scrollCtrl,
                    onChanged: widget.onChanged),
                _LockSoundTab(isDark: isDark, scrollCtrl: scrollCtrl),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DAILY GOAL TAB
// ─────────────────────────────────────────────────────────────────────────────

class _DailyGoalTab extends StatefulWidget {
  final ProductivityEngine engine;
  final GamificationState gs;
  final bool isDark;
  final ScrollController scrollCtrl;
  final VoidCallback? onChanged;

  const _DailyGoalTab({
    required this.engine, required this.gs,
    required this.isDark, required this.scrollCtrl,
    this.onChanged,
  });

  @override
  State<_DailyGoalTab> createState() => _DailyGoalTabState();
}

class _DailyGoalTabState extends State<_DailyGoalTab> {
  late double _goalMinutes;

  // Presets: (label, minutes)
  static const _presets = [
    ('30 min', 30.0),
    ('1 hour', 60.0),
    ('1.5 hrs', 90.0),
    ('2 hours', 120.0),
    ('3 hours', 180.0),
    ('4 hours', 240.0),
  ];

  @override
  void initState() {
    super.initState();
    _goalMinutes = widget.engine.dailyGoal.targetMinutes;
  }

  String _formatGoal(double m) {
    if (m < 60) return '${m.round()} min';
    final h = (m / 60).floor();
    final rem = (m % 60).round();
    return rem == 0 ? '${h}h' : '${h}h ${rem}m';
  }

  String _motivationText(double m) {
    if (m <= 30) return 'Perfect for busy days 📅';
    if (m <= 60) return 'A solid daily habit 💪';
    if (m <= 90) return 'Building momentum 🚀';
    if (m <= 120) return 'Serious focus mode 🧠';
    if (m <= 180) return 'Deep work champion 🏆';
    return 'Elite level dedication 👑';
  }

  void _applyGoal() {
    widget.engine.dailyGoal.targetMinutes = _goalMinutes;
    widget.engine.dailyGoal.notifyListeners();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return ListView(
      controller: widget.scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        // Hero display
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF43A047), Color(0xFF1B5E20)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                  color: _T.accent.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8))
            ],
          ),
          child: Column(children: [
            const Text('Daily Focus Goal',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              _formatGoal(_goalMinutes),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  height: 1),
            ),
            const SizedBox(height: 6),
            Text(_motivationText(_goalMinutes),
                style: const TextStyle(
                    color: Colors.white70, fontSize: 14)),
          ]),
        ),
        const SizedBox(height: 24),

        // Slider
        Text('Adjust Goal',
            style: TextStyle(
                color: _T.tp(isDark),
                fontWeight: FontWeight.w700,
                fontSize: 14)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          decoration: BoxDecoration(
            color: _T.surface(isDark),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _T.border(isDark)),
          ),
          child: Column(children: [
            Row(children: [
              Text('15 min',
                  style: TextStyle(color: _T.ts(isDark), fontSize: 11)),
              const Spacer(),
              Text('5 hours',
                  style: TextStyle(color: _T.ts(isDark), fontSize: 11)),
            ]),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: _T.accent,
                inactiveTrackColor: _T.border(isDark),
                thumbColor: _T.accent,
                overlayColor: _T.accent.withOpacity(0.15),
                trackHeight: 6,
                thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 12),
              ),
              child: Slider(
                value: _goalMinutes,
                min: 15,
                max: 300,
                divisions: 57, // 5-min steps
                onChanged: (v) {
                  setState(() => _goalMinutes = (v / 5).round() * 5.0);
                },
                onChangeEnd: (_) => _applyGoal(),
              ),
            ),
            // Live indicator
            Text(
              _formatGoal(_goalMinutes),
              style: const TextStyle(
                  color: _T.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 18),
            ),
          ]),
        ),
        const SizedBox(height: 24),

        // Preset chips
        Text('Quick Presets',
            style: TextStyle(
                color: _T.tp(isDark),
                fontWeight: FontWeight.w700,
                fontSize: 14)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _presets.map((p) {
            final isActive =
                (_goalMinutes - p.$2).abs() < 1;
            return GestureDetector(
              onTap: () {
                setState(() => _goalMinutes = p.$2);
                _applyGoal();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: isActive
                      ? const LinearGradient(
                      colors: [Color(0xFF43A047), Color(0xFF81C784)])
                      : null,
                  color: isActive ? null : _T.surface(isDark),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isActive
                          ? Colors.transparent
                          : _T.border(isDark)),
                  boxShadow: isActive
                      ? [BoxShadow(
                      color: _T.accent.withOpacity(0.3),
                      blurRadius: 8)]
                      : null,
                ),
                child: Text(p.$1,
                    style: TextStyle(
                        color: isActive
                            ? Colors.white
                            : _T.tp(isDark),
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),

        // What counts toward goal
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _T.accent.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: _T.accent.withOpacity(0.2)),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('ℹ️', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Text('How streaks work',
                      style: TextStyle(
                          color: _T.tp(isDark),
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ]),
                const SizedBox(height: 8),
                _InfoRow(
                    '🔥 Full streak',
                    'Complete 100% of your daily goal',
                    isDark),
                _InfoRow(
                    '⚡ Half streak',
                    'Complete at least 50% of your goal',
                    isDark),
                _InfoRow(
                    '✗ Missed',
                    'Less than 50% — streak resets',
                    isDark),
              ]),
        ),

        const SizedBox(height: 24),

        // Current progress today
        _TodayProgressCard(
            engine: widget.engine, isDark: isDark),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String desc;
  final bool isDark;
  const _InfoRow(this.label, this.desc, this.isDark);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style: const TextStyle(
                  color: _T.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Text(desc,
              style: TextStyle(
                  color: _T.ts(isDark), fontSize: 12)),
        ),
      ]),
    );
  }
}

class _TodayProgressCard extends StatelessWidget {
  final ProductivityEngine engine;
  final bool isDark;
  const _TodayProgressCard(
      {required this.engine, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: engine.dailyGoal,
      builder: (_, __) {
        final goal = engine.dailyGoal;
        final pct = goal.completionPercentage();
        final done = pct >= 1.0;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _T.surface(isDark),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _T.border(isDark)),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(done ? '🏆 ' : '📊 ',
                      style: const TextStyle(fontSize: 16)),
                  Text("Today's Progress",
                      style: TextStyle(
                          color: _T.tp(isDark),
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  const Spacer(),
                  Text(goal.formattedProgress(),
                      style: TextStyle(
                          color: _T.ts(isDark), fontSize: 11)),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 8,
                    backgroundColor: _T.surfaceEl(isDark),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        done ? const Color(0xFF30D158) : _T.accent),
                  ),
                ),
              ]),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUBJECTS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _SubjectsTab2 extends StatelessWidget {
  final ProductivityEngine engine;
  final GamificationState gs;
  final bool isDark;
  final ScrollController scrollCtrl;
  final VoidCallback? onChanged;

  const _SubjectsTab2({
    required this.engine, required this.gs,
    required this.isDark, required this.scrollCtrl,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: engine.subjectManager,
      builder: (context, _) {
        final subjects = engine.subjectManager.subjects;

        return ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            // Header hint
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _T.accent.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border:
                Border.all(color: _T.accent.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Text('💡', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Long-press any subject to delete it. '
                        'Tap to expand and edit.',
                    style: TextStyle(
                        color: _T.ts(isDark), fontSize: 12),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // Subject cards
            ...subjects.map((s) => _SubjectConfigCard(
              subject: s,
              engine: engine,
              gs: gs,
              isDark: isDark,
              onChanged: onChanged,
            )),

            const SizedBox(height: 8),

            // Add subject button
            GestureDetector(
              onTap: () => _showAddSubjectSheet(context),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: _T.surface(isDark),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _T.accent.withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [
                                Color(0xFF43A047),
                                Color(0xFF81C784)
                              ]),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.add,
                            color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text('Add New Subject',
                          style: TextStyle(
                              color: _T.tp(isDark),
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                    ]),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAddSubjectSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddSubjectSheet(
        engine: engine,
        gs: gs,
        isDark: isDark,
        onAdded: onChanged,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUBJECT CONFIG CARD — expandable editor per subject
// ─────────────────────────────────────────────────────────────────────────────

class _SubjectConfigCard extends StatefulWidget {
  final Subject subject;
  final ProductivityEngine engine;
  final GamificationState gs;
  final bool isDark;
  final VoidCallback? onChanged;

  const _SubjectConfigCard({
    required this.subject, required this.engine,
    required this.gs,      required this.isDark,
    this.onChanged,
  });

  @override
  State<_SubjectConfigCard> createState() => _SubjectConfigCardState();
}

class _SubjectConfigCardState extends State<_SubjectConfigCard> {
  bool _expanded = false;
  late int _focusMins;
  late int _shortBreakMins;
  late int _longBreakMins;
  late int _interval;
  late int _dailyTarget;
  late Color _color;

  static const _colorOptions = [
    Color(0xFFFF2D78), Color(0xFF43A047), Color(0xFF42A5F5),
    Color(0xFFFF8F00), Color(0xFFAB47BC), Color(0xFFEF5350),
    Color(0xFF00BCD4), Color(0xFF8D6E63), Color(0xFF26A69A),
    Color(0xFF5C6BC0),
  ];

  static const _emojiOptions = [
    '📚', '🧠', '💻', '📖', '💪', '🎨', '🎵', '🔬', '📐', '✏️',
    '🌍', '📝', '🏃', '🍎', '⚗️', '📊',
  ];

  late String _emoji;

  @override
  void initState() {
    super.initState();
    final s = widget.subject;
    _focusMins      = s.focusDuration.inMinutes;
    _shortBreakMins = s.shortBreakDuration.inMinutes;
    _longBreakMins  = s.longBreakDuration.inMinutes;
    _interval       = s.longBreakInterval;
    _dailyTarget    = widget.gs.targetFor(s.id);
    _color          = s.color;
    _emoji          = s.emoji;
  }

  void _save() {
    final updated = widget.subject.copyWith(
      emoji: _emoji,
      color: _color,
      focusDuration:      Duration(minutes: _focusMins),
      shortBreakDuration: Duration(minutes: _shortBreakMins),
      longBreakDuration:  Duration(minutes: _longBreakMins),
      longBreakInterval:  _interval,
    );
    widget.engine.subjectManager.update(updated);
    widget.gs.setTarget(widget.subject.id, _dailyTarget);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.subject;
    final isDark = widget.isDark;

    return GestureDetector(
      onLongPress: () => _confirmDelete(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _T.surface(isDark),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: _expanded
                  ? _color.withOpacity(0.5)
                  : _T.border(isDark),
              width: _expanded ? 1.5 : 1),
          boxShadow: _expanded
              ? [BoxShadow(
              color: _color.withOpacity(0.12), blurRadius: 12)]
              : null,
        ),
        child: Column(children: [
          // Header row
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                // Emoji + color dot
                Stack(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: _color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _color.withOpacity(0.3)),
                    ),
                    child: Center(
                        child: Text(_emoji,
                            style:
                            const TextStyle(fontSize: 22))),
                  ),
                  Positioned(
                    right: 0, bottom: 0,
                    child: Container(
                      width: 12, height: 12,
                      decoration: BoxDecoration(
                          color: _color,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: _T.surface(isDark),
                              width: 1.5)),
                    ),
                  ),
                ]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(s.name,
                            style: TextStyle(
                                color: _T.tp(isDark),
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(
                          '${_focusMins}m focus  •  '
                              '${_shortBreakMins}m break  •  '
                              '$_dailyTarget sessions/day',
                          style: TextStyle(
                              color: _T.ts(isDark),
                              fontSize: 11),
                        ),
                      ]),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: _T.ts(isDark),
                ),
              ]),
            ),
          ),

          // Expanded editor
          if (_expanded) ...[
            Divider(
                height: 1, color: _T.border(isDark)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    // ── Emoji picker ──────────────────────────
                    Text('Emoji',
                        style: TextStyle(
                            color: _T.ts(isDark),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _emojiOptions.map((e) {
                        final sel = e == _emoji;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _emoji = e);
                            _save();
                          },
                          child: AnimatedContainer(
                            duration:
                            const Duration(milliseconds: 150),
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: sel
                                  ? _color.withOpacity(0.2)
                                  : _T.surfaceEl(isDark),
                              borderRadius:
                              BorderRadius.circular(10),
                              border: Border.all(
                                  color: sel
                                      ? _color
                                      : Colors.transparent,
                                  width: 2),
                            ),
                            child: Center(
                                child: Text(e,
                                    style: const TextStyle(
                                        fontSize: 18))),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // ── Color picker ──────────────────────────
                    Text('Color',
                        style: TextStyle(
                            color: _T.ts(isDark),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _colorOptions.map((c) {
                        final sel = c.value == _color.value;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _color = c);
                            _save();
                          },
                          child: AnimatedContainer(
                            duration:
                            const Duration(milliseconds: 150),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: sel
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 3),
                              boxShadow: sel
                                  ? [BoxShadow(
                                  color:
                                  c.withOpacity(0.5),
                                  blurRadius: 8)]
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // ── Focus duration ────────────────────────
                    _SpinnerRow(
                      label: '🧠 Focus Duration',
                      value: _focusMins,
                      unit: 'min',
                      min: 5, max: 90, step: 5,
                      isDark: isDark,
                      onChanged: (v) {
                        setState(() => _focusMins = v);
                        _save();
                      },
                    ),
                    const SizedBox(height: 12),

                    // ── Short break ───────────────────────────
                    _SpinnerRow(
                      label: '☕ Short Break',
                      value: _shortBreakMins,
                      unit: 'min',
                      min: 1, max: 30, step: 1,
                      isDark: isDark,
                      onChanged: (v) {
                        setState(() => _shortBreakMins = v);
                        _save();
                      },
                    ),
                    const SizedBox(height: 12),

                    // ── Long break ────────────────────────────
                    _SpinnerRow(
                      label: '🌿 Long Break',
                      value: _longBreakMins,
                      unit: 'min',
                      min: 5, max: 60, step: 5,
                      isDark: isDark,
                      onChanged: (v) {
                        setState(() => _longBreakMins = v);
                        _save();
                      },
                    ),
                    const SizedBox(height: 12),

                    // ── Long break interval ───────────────────
                    _SpinnerRow(
                      label: '🔁 Long Break After',
                      value: _interval,
                      unit: 'sessions',
                      min: 2, max: 8, step: 1,
                      isDark: isDark,
                      onChanged: (v) {
                        setState(() => _interval = v);
                        _save();
                      },
                    ),
                    const SizedBox(height: 12),

                    // ── Daily target ──────────────────────────
                    _SpinnerRow(
                      label: '🎯 Daily Target',
                      value: _dailyTarget,
                      unit: 'sessions',
                      min: 1, max: 16, step: 1,
                      isDark: isDark,
                      onChanged: (v) {
                        setState(() => _dailyTarget = v);
                        _save();
                      },
                    ),
                    const SizedBox(height: 16),

                    // Session time summary
                    _SessionSummary(
                      focusMins: _focusMins,
                      shortBreakMins: _shortBreakMins,
                      longBreakMins: _longBreakMins,
                      interval: _interval,
                      dailyTarget: _dailyTarget,
                      isDark: isDark,
                    ),
                  ]),
            ),
          ],
        ]),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    if (widget.engine.subjectManager.subjects.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Need at least one subject!'),
        backgroundColor: _T.red,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _T.surfaceEl(widget.isDark),
        title: Text('Delete ${widget.subject.name}?',
            style: TextStyle(
                color: _T.tp(widget.isDark),
                fontWeight: FontWeight.w700)),
        content: Text(
          'All streak data for this subject will remain, '
              'but the subject will be removed.',
          style: TextStyle(color: _T.ts(widget.isDark)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(
                    color: _T.ts(widget.isDark))),
          ),
          TextButton(
            onPressed: () {
              widget.engine.subjectManager
                  .remove(widget.subject.id);
              widget.onChanged?.call();
              Navigator.pop(context);
            },
            child: const Text('Delete',
                style: TextStyle(
                    color: _T.red,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SESSION SUMMARY — shows total cycle time for the configured subject
// ─────────────────────────────────────────────────────────────────────────────

class _SessionSummary extends StatelessWidget {
  final int focusMins, shortBreakMins, longBreakMins;
  final int interval, dailyTarget;
  final bool isDark;

  const _SessionSummary({
    required this.focusMins, required this.shortBreakMins,
    required this.longBreakMins, required this.interval,
    required this.dailyTarget, required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // One full cycle = (interval × focus) + (interval-1 × shortBreak) + longBreak
    final cycleMin = (interval * focusMins) +
        ((interval - 1) * shortBreakMins) +
        longBreakMins;
    final dailyMin = dailyTarget * focusMins +
        (dailyTarget - 1) * shortBreakMins +
        ((dailyTarget ~/ interval)) * longBreakMins;
    final h = dailyMin ~/ 60;
    final m = dailyMin % 60;
    final timeStr = h > 0 ? '${h}h ${m}m' : '${m}m';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _T.accent.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _T.accent.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('⏱ Session Summary',
            style: TextStyle(
                color: _T.tp(isDark),
                fontWeight: FontWeight.w700,
                fontSize: 12)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: _SummaryItem(
                  '1 cycle', '${cycleMin}m', isDark)),
          Expanded(
              child: _SummaryItem(
                  'Daily total', timeStr, isDark)),
          Expanded(
              child: _SummaryItem(
                  'Pure focus',
                  '${dailyTarget * focusMins}m',
                  isDark)),
        ]),
      ]),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label, value;
  final bool isDark;
  const _SummaryItem(this.label, this.value, this.isDark);

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value,
        style: const TextStyle(
            color: _T.accent,
            fontWeight: FontWeight.w800,
            fontSize: 16)),
    Text(label,
        style: TextStyle(
            color: _T.ts(isDark), fontSize: 10)),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// ADD SUBJECT SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _AddSubjectSheet extends StatefulWidget {
  final ProductivityEngine engine;
  final GamificationState gs;
  final bool isDark;
  final VoidCallback? onAdded;

  const _AddSubjectSheet({
    required this.engine, required this.gs,
    required this.isDark, this.onAdded,
  });

  @override
  State<_AddSubjectSheet> createState() => _AddSubjectSheetState();
}

class _AddSubjectSheetState extends State<_AddSubjectSheet> {
  final _nameCtrl = TextEditingController();
  String _emoji = '📚';
  Color _color = const Color(0xFF43A047);
  int _focusMins      = 25;
  int _shortBreakMins = 5;
  int _longBreakMins  = 15;
  int _interval       = 4;
  int _dailyTarget    = 4;

  static const _templates = [
    ('Deep Work', '🧠', Color(0xFF43A047), 50, 10, 20, 4),
    ('Reading',   '📖', Color(0xFF42A5F5), 25,  5, 15, 4),
    ('Exercise',  '💪', Color(0xFFEF5350), 45, 10, 15, 2),
    ('Coding',    '💻', Color(0xFFAB47BC), 50, 10, 20, 4),
    ('Revision',  '✏️', Color(0xFFFF8F00), 25,  5, 15, 4),
    ('Language',  '🌍', Color(0xFF00BCD4), 20,  5, 10, 4),
  ];

  static const _colorOptions = [
    Color(0xFF43A047), Color(0xFFEF5350), Color(0xFF42A5F5),
    Color(0xFFFF8F00), Color(0xFFAB47BC), Color(0xFF00BCD4),
    Color(0xFFFF2D78), Color(0xFF8D6E63), Color(0xFF26A69A),
    Color(0xFF5C6BC0),
  ];

  static const _emojiOptions = [
    '📚', '🧠', '💻', '📖', '💪', '🎨', '🎵', '🔬',
    '📐', '✏️', '🌍', '📝', '🏃', '🍎', '⚗️', '📊',
  ];

  bool get _isValid => _nameCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _applyTemplate(int i) {
    final t = _templates[i];
    setState(() {
      _nameCtrl.text = t.$1;
      _emoji          = t.$2;
      _color          = t.$3;
      _focusMins      = t.$4;
      _shortBreakMins = t.$5;
      _longBreakMins  = t.$6;
      _interval       = t.$7;
    });
  }

  void _add() {
    if (!_isValid) return;
    final id = '${_nameCtrl.text.trim().toLowerCase().replaceAll(' ', '-')}'
        '-${DateTime.now().millisecondsSinceEpoch}';
    final subject = Subject(
      id: id,
      name: _nameCtrl.text.trim(),
      emoji: _emoji,
      color: _color,
      focusDuration:      Duration(minutes: _focusMins),
      shortBreakDuration: Duration(minutes: _shortBreakMins),
      longBreakDuration:  Duration(minutes: _longBreakMins),
      longBreakInterval:  _interval,
    );
    widget.engine.subjectManager.add(subject);
    widget.gs.setTarget(id, _dailyTarget);
    widget.onAdded?.call();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return DraggableScrollableSheet(
      initialChildSize: 0.94,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: _T.bg(isDark),
          borderRadius:
          const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            // Drag handle + title
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: _T.border(isDark),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(children: [
              Text('Add Subject',
                  style: TextStyle(
                      color: _T.tp(isDark),
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: _T.surfaceEl(isDark),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close_rounded,
                      color: _T.ts(isDark), size: 16),
                ),
              ),
            ]),
            const SizedBox(height: 20),

            // Quick templates
            Text('Quick Templates',
                style: TextStyle(
                    color: _T.tp(isDark),
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            const SizedBox(height: 10),
            SizedBox(
              height: 70,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _templates.length,
                separatorBuilder: (_, __) =>
                const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final t = _templates[i];
                  final isActive =
                      _nameCtrl.text == t.$1 && _color == t.$3;
                  return GestureDetector(
                    onTap: () => _applyTemplate(i),
                    child: AnimatedContainer(
                      duration:
                      const Duration(milliseconds: 200),
                      width: 85,
                      decoration: BoxDecoration(
                        color: isActive
                            ? t.$3.withOpacity(0.2)
                            : _T.surface(isDark),
                        borderRadius:
                        BorderRadius.circular(14),
                        border: Border.all(
                            color: isActive
                                ? t.$3
                                : _T.border(isDark),
                            width: isActive ? 2 : 1),
                      ),
                      child: Column(
                          mainAxisAlignment:
                          MainAxisAlignment.center,
                          children: [
                            Text(t.$2,
                                style: const TextStyle(
                                    fontSize: 22)),
                            const SizedBox(height: 2),
                            Text(t.$1,
                                style: TextStyle(
                                    color: isActive
                                        ? t.$3
                                        : _T.ts(isDark),
                                    fontSize: 10,
                                    fontWeight:
                                    FontWeight.w600),
                                maxLines: 1,
                                overflow:
                                TextOverflow.ellipsis),
                          ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            // Name field
            Text('Subject Name',
                style: TextStyle(
                    color: _T.tp(isDark),
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                  color: _T.tp(isDark),
                  fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'e.g. Mathematics',
                hintStyle:
                TextStyle(color: _T.ts(isDark)),
                filled: true,
                fillColor: _T.surface(isDark),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  BorderSide(color: _T.border(isDark)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                  BorderSide(color: _T.border(isDark)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: _T.accent, width: 2),
                ),
                prefixText: '$_emoji  ',
                prefixStyle: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 20),

            // Emoji
            Text('Icon',
                style: TextStyle(
                    color: _T.tp(isDark),
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _emojiOptions.map((e) {
                final sel = e == _emoji;
                return GestureDetector(
                  onTap: () => setState(() => _emoji = e),
                  child: AnimatedContainer(
                    duration:
                    const Duration(milliseconds: 150),
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: sel
                          ? _color.withOpacity(0.2)
                          : _T.surface(isDark),
                      borderRadius:
                      BorderRadius.circular(10),
                      border: Border.all(
                          color: sel
                              ? _color
                              : _T.border(isDark),
                          width: sel ? 2 : 1),
                    ),
                    child: Center(
                        child: Text(e,
                            style: const TextStyle(
                                fontSize: 20))),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Color
            Text('Color',
                style: TextStyle(
                    color: _T.tp(isDark),
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12, runSpacing: 12,
              children: _colorOptions.map((c) {
                final sel = c.value == _color.value;
                return GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: AnimatedContainer(
                    duration:
                    const Duration(milliseconds: 150),
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: sel
                              ? Colors.white
                              : Colors.transparent,
                          width: 3),
                      boxShadow: sel
                          ? [BoxShadow(
                          color:
                          c.withOpacity(0.5),
                          blurRadius: 8)]
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Timings
            Text('Session Timings',
                style: TextStyle(
                    color: _T.tp(isDark),
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _T.surface(isDark),
                borderRadius: BorderRadius.circular(16),
                border:
                Border.all(color: _T.border(isDark)),
              ),
              child: Column(children: [
                _SpinnerRow(
                  label: '🧠 Focus',
                  value: _focusMins,
                  unit: 'min',
                  min: 5, max: 90, step: 5,
                  isDark: isDark,
                  onChanged: (v) =>
                      setState(() => _focusMins = v),
                ),
                const SizedBox(height: 12),
                _SpinnerRow(
                  label: '☕ Short Break',
                  value: _shortBreakMins,
                  unit: 'min',
                  min: 1, max: 30, step: 1,
                  isDark: isDark,
                  onChanged: (v) =>
                      setState(() => _shortBreakMins = v),
                ),
                const SizedBox(height: 12),
                _SpinnerRow(
                  label: '🌿 Long Break',
                  value: _longBreakMins,
                  unit: 'min',
                  min: 5, max: 60, step: 5,
                  isDark: isDark,
                  onChanged: (v) =>
                      setState(() => _longBreakMins = v),
                ),
                const SizedBox(height: 12),
                _SpinnerRow(
                  label: '🔁 Long Break After',
                  value: _interval,
                  unit: 'sessions',
                  min: 2, max: 8, step: 1,
                  isDark: isDark,
                  onChanged: (v) =>
                      setState(() => _interval = v),
                ),
                const SizedBox(height: 12),
                _SpinnerRow(
                  label: '🎯 Daily Target',
                  value: _dailyTarget,
                  unit: 'sessions',
                  min: 1, max: 16, step: 1,
                  isDark: isDark,
                  onChanged: (v) =>
                      setState(() => _dailyTarget = v),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // Summary
            _SessionSummary(
              focusMins: _focusMins,
              shortBreakMins: _shortBreakMins,
              longBreakMins: _longBreakMins,
              interval: _interval,
              dailyTarget: _dailyTarget,
              isDark: isDark,
            ),
            const SizedBox(height: 24),

            // Add button
            GestureDetector(
              onTap: _isValid ? _add : null,
              child: AnimatedContainer(
                duration:
                const Duration(milliseconds: 200),
                height: 56,
                decoration: BoxDecoration(
                  gradient: _isValid
                      ? const LinearGradient(colors: [
                    Color(0xFF43A047),
                    Color(0xFF81C784)
                  ])
                      : null,
                  color: _isValid
                      ? null
                      : _T.surfaceEl(isDark),
                  borderRadius:
                  BorderRadius.circular(16),
                  boxShadow: _isValid
                      ? [BoxShadow(
                      color:
                      _T.accent.withOpacity(0.35),
                      blurRadius: 12,
                      offset:
                      const Offset(0, 4))]
                      : null,
                ),
                child: Center(
                  child: Text(
                    _isValid
                        ? 'Add Subject'
                        : 'Enter a subject name',
                    style: TextStyle(
                      color: _isValid
                          ? Colors.white
                          : _T.ts(isDark),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SPINNER ROW — +/- stepper with label
// ─────────────────────────────────────────────────────────────────────────────

class _SpinnerRow extends StatelessWidget {
  final String label;
  final String unit;
  final int value;
  final int min, max, step;
  final bool isDark;
  final ValueChanged<int> onChanged;

  const _SpinnerRow({
    required this.label, required this.value,
    required this.unit,  required this.min,
    required this.max,   required this.step,
    required this.isDark, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Text(label,
            style: TextStyle(
                color: _T.tp(isDark),
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ),
      // Minus
      GestureDetector(
        onTap: value > min
            ? () => onChanged(value - step)
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: value > min
                ? _T.surfaceEl(isDark)
                : _T.border(isDark).withOpacity(0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _T.border(isDark)),
          ),
          child: Icon(Icons.remove,
              size: 16,
              color: value > min
                  ? _T.tp(isDark)
                  : _T.ts(isDark).withOpacity(0.3)),
        ),
      ),
      // Value
      SizedBox(
        width: 64,
        child: Column(children: [
          Text('$value',
              style: TextStyle(
                  color: _T.tp(isDark),
                  fontWeight: FontWeight.w800,
                  fontSize: 16),
              textAlign: TextAlign.center),
          Text(unit,
              style: TextStyle(
                  color: _T.ts(isDark), fontSize: 9),
              textAlign: TextAlign.center),
        ]),
      ),
      // Plus
      GestureDetector(
        onTap: value < max
            ? () => onChanged(value + step)
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34, height: 34,
          decoration: BoxDecoration(
            gradient: value < max
                ? const LinearGradient(colors: [
              Color(0xFF43A047),
              Color(0xFF81C784)
            ])
                : null,
            color: value < max
                ? null
                : _T.border(isDark).withOpacity(0.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.add,
              size: 16,
              color: value < max
                  ? Colors.white
                  : _T.ts(isDark).withOpacity(0.3)),
        ),
      ),
    ]);
  }
}