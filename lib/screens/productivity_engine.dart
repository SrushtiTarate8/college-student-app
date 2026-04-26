// productivity_engine.dart
//
// Pure logic layer — no UI widgets.
// The PomodoroScreen UI lives in pomodoro_screen.dart.

// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// THEME CONSTANTS  (used by engine-owned widgets only)
// ═══════════════════════════════════════════════════════════════════════════

class _K {
  static const rose      = Color(0xFFFF2D78);
  static const roseDark  = Color(0xFFD4005F);
  static const roseMid   = Color(0xFFFF6FA3);
  static const roseLight = Color(0xFFFFD6E7);
  static const roseFaint = Color(0xFFFFF0F5);
  static const blush     = Color(0xFFFF8FB1);
  static const magenta   = Color(0xFFE91E8C);
  static const plum      = Color(0xFF8B1A4A);
  static const bg        = Color(0xFFFDF5F8);
  static const surface   = Color(0xFFFFFFFF);
  static const surfaceAlt= Color(0xFFFFF0F5);
  static const border    = Color(0xFFFFD6E7);
  static const divider   = Color(0xFFFFC8DC);
  static const textPrimary = Color(0xFF1A0510);
  static const textSecond  = Color(0xFF7A2A50);
  static const textHint    = Color(0xFFBF8FA5);
  static const success   = Color(0xFF2ECC71);
  static const warning   = Color(0xFFFF9500);
  static const info      = Color(0xFF5856D6);
  static const gradPrimary = LinearGradient(
    colors: [rose, magenta],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const gradSoft = LinearGradient(
    colors: [Color(0xFFFF6FA3), Color(0xFFFF2D78)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  static const gradBreak = LinearGradient(
    colors: [Color(0xFF5856D6), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const fast   = Duration(milliseconds: 200);
  static const medium = Duration(milliseconds: 450);
  static const slow   = Duration(milliseconds: 800);
}

// ═══════════════════════════════════════════════════════════════════════════
// 1. DOMAIN MODELS
// ═══════════════════════════════════════════════════════════════════════════

enum SessionPhase { idle, focus, shortBreak, longBreak }

class SessionRecord {
  final String subjectId;
  final DateTime startedAt;
  final Duration focusDuration;
  final bool completed;

  const SessionRecord({
    required this.subjectId,
    required this.startedAt,
    required this.focusDuration,
    required this.completed,
  });

  Map<String, dynamic> toJson() => {
    'subjectId': subjectId,
    'startedAt': startedAt.toIso8601String(),
    'focusMinutes': focusDuration.inSeconds / 60.0,
    'completed': completed,
  };

  factory SessionRecord.fromJson(Map<String, dynamic> j) => SessionRecord(
    subjectId: j['subjectId'] as String,
    startedAt: DateTime.parse(j['startedAt'] as String),
    focusDuration: Duration(seconds: ((j['focusMinutes'] as num) * 60).round()),
    completed: j['completed'] as bool,
  );
}

class Subject {
  final String id;
  final String name;
  final String emoji;
  final Duration focusDuration;
  final Duration shortBreakDuration;
  final Duration longBreakDuration;
  final int longBreakInterval;
  final Color color;

  const Subject({
    required this.id,
    required this.name,
    this.emoji = '📚',
    this.focusDuration = const Duration(minutes: 25),
    this.shortBreakDuration = const Duration(minutes: 5),
    this.longBreakDuration = const Duration(minutes: 15),
    this.longBreakInterval = 4,
    this.color = _K.rose,
  });

  Subject copyWith({
    String? name, String? emoji,
    Duration? focusDuration, Duration? shortBreakDuration,
    Duration? longBreakDuration, int? longBreakInterval, Color? color,
  }) => Subject(
    id: id,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    focusDuration: focusDuration ?? this.focusDuration,
    shortBreakDuration: shortBreakDuration ?? this.shortBreakDuration,
    longBreakDuration: longBreakDuration ?? this.longBreakDuration,
    longBreakInterval: longBreakInterval ?? this.longBreakInterval,
    color: color ?? this.color,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'emoji': emoji,
    'focusSeconds': focusDuration.inSeconds,
    'shortBreakSeconds': shortBreakDuration.inSeconds,
    'longBreakSeconds': longBreakDuration.inSeconds,
    'longBreakInterval': longBreakInterval,
    'colorValue': color.value,
  };

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
    id: j['id'] as String,
    name: j['name'] as String,
    emoji: j['emoji'] as String? ?? '📚',
    focusDuration: Duration(seconds: j['focusSeconds'] as int),
    shortBreakDuration: Duration(seconds: j['shortBreakSeconds'] as int),
    longBreakDuration: Duration(seconds: j['longBreakSeconds'] as int),
    longBreakInterval: j['longBreakInterval'] as int,
    color: Color(j['colorValue'] as int),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// 2. PERSISTENCE
// ═══════════════════════════════════════════════════════════════════════════

abstract class StorageService {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
  Future<void> clear();
}

class InMemoryStorage implements StorageService {
  final _store = <String, String>{};
  @override Future<String?> getString(String key) async => _store[key];
  @override Future<void> setString(String key, String value) async => _store[key] = value;
  @override Future<void> remove(String key) async => _store.remove(key);
  @override Future<void> clear() async => _store.clear();
}

// ═══════════════════════════════════════════════════════════════════════════
// 3a. POMODORO SESSION  (drift-free stopwatch timing)
// ═══════════════════════════════════════════════════════════════════════════

class PomodoroSession extends ChangeNotifier {
  Subject _subject;
  Subject get subject => _subject;

  SessionPhase _phase = SessionPhase.idle;
  SessionPhase get phase => _phase;

  int _completedIntervals = 0;
  int get completedIntervals => _completedIntervals;

  Duration get elapsed => _stopwatch.elapsed + _pauseOffset;

  Duration get remaining {
    final r = _durationFor(_phase) - elapsed;
    return r.isNegative ? Duration.zero : r;
  }

  double get progress {
    final total = _durationFor(_phase);
    if (total.inMilliseconds == 0) return 0;
    return (elapsed.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  bool get isRunning => _timer != null;

  final Stopwatch _stopwatch = Stopwatch();
  Duration _pauseOffset = Duration.zero;
  Timer? _timer;

  VoidCallback? onFocusComplete;
  VoidCallback? onBreakComplete;
  VoidCallback? onTick;

  PomodoroSession({required Subject subject}) : _subject = subject;

  void changeSubject(Subject s) { _subject = s; reset(); }

  void start() {
    _phase = SessionPhase.focus;
    _startTimer();
  }

  void pause() {
    if (!isRunning) return;
    _pauseOffset = elapsed;
    _stopwatch..stop()..reset();
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  void resume() {
    if (isRunning || _phase == SessionPhase.idle) return;
    _startTimer();
  }

  void reset() {
    _timer?.cancel(); _timer = null;
    _stopwatch..stop()..reset();
    _pauseOffset = Duration.zero;
    _phase = SessionPhase.idle;
    _completedIntervals = 0;
    notifyListeners();
  }

  void skip() => _advancePhase();

  @override
  void dispose() {
    _timer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  void _startTimer() {
    _stopwatch..reset()..start();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), _onTick);
    notifyListeners();
  }

  void _onTick(Timer _) {
    onTick?.call();
    if (elapsed >= _durationFor(_phase)) {
      _advancePhase();
    } else {
      notifyListeners();
    }
  }

  void _advancePhase() {
    _stopwatch..stop()..reset();
    _pauseOffset = Duration.zero;
    _timer?.cancel(); _timer = null;

    if (_phase == SessionPhase.focus) {
      _completedIntervals++;
      onFocusComplete?.call();
      _phase = (_completedIntervals % _subject.longBreakInterval == 0)
          ? SessionPhase.longBreak
          : SessionPhase.shortBreak;
    } else {
      onBreakComplete?.call();
      _phase = SessionPhase.idle;
    }
    notifyListeners();
  }

  Duration _durationFor(SessionPhase p) {
    switch (p) {
      case SessionPhase.focus:      return _subject.focusDuration;
      case SessionPhase.shortBreak: return _subject.shortBreakDuration;
      case SessionPhase.longBreak:  return _subject.longBreakDuration;
      case SessionPhase.idle:       return Duration.zero;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 3b. SUBJECT MANAGER
// ═══════════════════════════════════════════════════════════════════════════

class SubjectManager extends ChangeNotifier {
  final StorageService _storage;
  static const _kSubjects = 'subjects_v1';
  static const _kSelected = 'selected_subject_id';

  final List<Subject> _subjects = [];
  List<Subject> get subjects => List.unmodifiable(_subjects);

  Subject? _selected;
  Subject? get selected => _selected;

  SubjectManager(this._storage);

  Future<void> load() async {
    final raw = await _storage.getString(_kSubjects);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _subjects..clear()
          ..addAll(list.map((e) => Subject.fromJson(e as Map<String, dynamic>)));
      } catch (_) { _subjects.clear(); }
    }
    if (_subjects.isEmpty) _seedDefaults();

    final selId = await _storage.getString(_kSelected);
    _selected = _subjects.firstWhere((s) => s.id == selId, orElse: () => _subjects.first);
    notifyListeners();
  }

  void add(Subject subject) { _subjects.add(subject); _persist(); notifyListeners(); }

  void remove(String id) {
    _subjects.removeWhere((s) => s.id == id);
    if (_selected?.id == id) _selected = _subjects.isNotEmpty ? _subjects.first : null;
    _persist(); notifyListeners();
  }

  void update(Subject updated) {
    final idx = _subjects.indexWhere((s) => s.id == updated.id);
    if (idx == -1) return;
    _subjects[idx] = updated;
    if (_selected?.id == updated.id) _selected = updated;
    _persist(); notifyListeners();
  }

  void select(String id) {
    _selected = _subjects.firstWhere((s) => s.id == id, orElse: () => _subjects.first);
    _storage.setString(_kSelected, _selected!.id);
    notifyListeners();
  }

  void _seedDefaults() {
    _subjects.addAll([
      const Subject(id: 'deep-work', name: 'Deep Work', emoji: '🧠', color: Color(0xFFFF2D78)),
      const Subject(id: 'reading',   name: 'Reading',   emoji: '📖', color: Color(0xFFE91E8C)),
      const Subject(id: 'exercise',  name: 'Exercise',  emoji: '💪',
          focusDuration: Duration(minutes: 45),
          shortBreakDuration: Duration(minutes: 10),
          color: Color(0xFFFF6FA3)),
      const Subject(id: 'coding',    name: 'Coding',    emoji: '💻', color: Color(0xFF8B1A4A)),
    ]);
  }

  Future<void> _persist() async {
    await _storage.setString(
        _kSubjects, jsonEncode(_subjects.map((s) => s.toJson()).toList()));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 3c. STREAK ENGINE
// ═══════════════════════════════════════════════════════════════════════════

enum DayResult { fullGoal, halfGoal, belowHalf, missed }

class StreakEngine {
  final double currentStreak;
  final double longestStreak;
  final double weeklyConsistency;

  const StreakEngine({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.weeklyConsistency = 0,
  });

  StreakEngine recompute({
    required List<SessionRecord> history,
    required double targetMinutes,
    DateTime? today,
  }) {
    final now = _utcDay(today ?? DateTime.now());
    final Map<DateTime, double> byDay = {};
    for (final r in history) {
      if (!r.completed) continue;
      final day = _utcDay(r.startedAt);
      byDay[day] = (byDay[day] ?? 0) + r.focusDuration.inSeconds / 60.0;
    }

    double streak = 0, longest = longestStreak;
    for (int i = 0; i <= 365; i++) {
      final day = now.subtract(Duration(days: i));
      final result = _evaluate(byDay[day] ?? 0, targetMinutes);
      if (result == DayResult.missed && day != now) break;
      switch (result) {
        case DayResult.fullGoal: streak += 1.0; break;
        case DayResult.halfGoal: streak += 0.5; break;
        default: break;
      }
    }
    if (streak > longest) longest = streak;

    int consistent = 0;
    for (int i = 0; i < 7; i++) {
      if ((byDay[now.subtract(Duration(days: i))] ?? 0) >= targetMinutes * 0.5) consistent++;
    }
    return StreakEngine(
        currentStreak: streak,
        longestStreak: longest,
        weeklyConsistency: consistent / 7);
  }

  static DayResult _evaluate(double m, double t) {
    if (t <= 0) return DayResult.fullGoal;
    if (m == 0) return DayResult.missed;
    final r = m / t;
    if (r >= 1.0) return DayResult.fullGoal;
    if (r >= 0.5) return DayResult.halfGoal;
    return DayResult.belowHalf;
  }

  static DateTime _utcDay(DateTime dt) => DateTime.utc(dt.year, dt.month, dt.day);
}

// ═══════════════════════════════════════════════════════════════════════════
// 3d. TREE GROWTH ENGINE
// ═══════════════════════════════════════════════════════════════════════════

enum TreeStage { seed, sprout, plant, tree, bigTree }

class TreeGrowthResult {
  final TreeStage stage;
  final double stageProgress;
  final double overallProgress;
  const TreeGrowthResult({
    required this.stage,
    required this.stageProgress,
    required this.overallProgress,
  });
}

class TreeGrowthEngine {
  final double maxFocusMinutes;
  const TreeGrowthEngine({this.maxFocusMinutes = 300});

  TreeGrowthResult compute({
    required double totalFocusMinutes,
    required double streakMultiplier,
  }) {
    final raw = (totalFocusMinutes / maxFocusMinutes).clamp(0.0, 1.0);
    final boosted = (raw * streakMultiplier).clamp(0.0, 1.0);
    final stage = _stageFor(boosted);
    final (lo, hi) = _rangeFor(stage);
    return TreeGrowthResult(
      stage: stage,
      stageProgress: hi == lo ? 1.0 : ((boosted - lo) / (hi - lo)).clamp(0.0, 1.0),
      overallProgress: boosted,
    );
  }

  String stageLabel(TreeStage s) {
    switch (s) {
      case TreeStage.seed:    return 'Seed';
      case TreeStage.sprout:  return 'Sprout';
      case TreeStage.plant:   return 'Sapling';
      case TreeStage.tree:    return 'Tree';
      case TreeStage.bigTree: return 'Ancient';
    }
  }

  static TreeStage _stageFor(double p) {
    if (p < 0.20) return TreeStage.seed;
    if (p < 0.40) return TreeStage.sprout;
    if (p < 0.60) return TreeStage.plant;
    if (p < 0.80) return TreeStage.tree;
    return TreeStage.bigTree;
  }

  static (double, double) _rangeFor(TreeStage s) {
    switch (s) {
      case TreeStage.seed:    return (0.00, 0.20);
      case TreeStage.sprout:  return (0.20, 0.40);
      case TreeStage.plant:   return (0.40, 0.60);
      case TreeStage.tree:    return (0.60, 0.80);
      case TreeStage.bigTree: return (0.80, 1.00);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 3e. REWARD ENGINE
// ═══════════════════════════════════════════════════════════════════════════

class UnlockableItem {
  final String id;
  final String name;
  final String emoji;
  final int costCoins;
  bool unlocked;
  UnlockableItem({
    required this.id, required this.name,
    required this.emoji, required this.costCoins,
    this.unlocked = false,
  });
}

class RewardEngine extends ChangeNotifier {
  int _coins = 0;
  int get coins => _coins;

  final List<UnlockableItem> catalogue;

  RewardEngine({List<UnlockableItem>? catalogue})
      : catalogue = catalogue ?? [
    UnlockableItem(id: 'dark-theme',  name: 'Dark Theme',       emoji: '🌙', costCoins: 50),
    UnlockableItem(id: 'forest-bg',   name: 'Forest Background', emoji: '🌲', costCoins: 100),
    UnlockableItem(id: 'zen-sounds',  name: 'Zen Sounds',        emoji: '🎵', costCoins: 150),
    UnlockableItem(id: 'petal-theme', name: 'Petal Theme',       emoji: '🌸', costCoins: 200),
  ];

  void awardSession({required Duration focusDuration, required double currentStreak}) {
    _coins += (focusDuration.inMinutes / 25.0 * 10).round() + _streakBonus(currentStreak);
    notifyListeners();
  }

  bool purchase(String itemId) {
    final idx = catalogue.indexWhere((i) => i.id == itemId);
    if (idx == -1) return false;
    final item = catalogue[idx];
    if (item.unlocked || _coins < item.costCoins) return false;
    _coins -= item.costCoins;
    item.unlocked = true;
    notifyListeners();
    return true;
  }

  bool isUnlocked(String itemId) => catalogue.any((i) => i.id == itemId && i.unlocked);

  static int _streakBonus(double s) {
    if (s >= 30) return 25;
    if (s >= 14) return 15;
    if (s >= 7)  return 10;
    if (s >= 3)  return 5;
    return 0;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 3f. MOTIVATION CHARACTER
// ═══════════════════════════════════════════════════════════════════════════

enum CharacterMood { ecstatic, happy, neutral, struggling, sad }

class CharacterState {
  final CharacterMood mood;
  final String message;
  final String emoji;
  const CharacterState({required this.mood, required this.message, required this.emoji});
}

class MotivationCharacter {
  static CharacterState evaluate({
    required double streakDays,
    required double completionPercent,
    required int sessionsToday,
    required SessionPhase phase,
  }) {
    if (phase == SessionPhase.focus) {
      if (completionPercent >= 0.8)
        return const CharacterState(mood: CharacterMood.ecstatic, emoji: '🔥', message: 'Almost there! Keep pushing!');
      return const CharacterState(mood: CharacterMood.happy, emoji: '💪', message: "Deep focus mode — you're crushing it!");
    }
    if (phase == SessionPhase.shortBreak)
      return const CharacterState(mood: CharacterMood.happy, emoji: '☕', message: 'Great session! Take a breather.');
    if (phase == SessionPhase.longBreak)
      return const CharacterState(mood: CharacterMood.ecstatic, emoji: '🎉', message: 'Incredible work! You earned this rest.');

    if (completionPercent >= 1.0 && streakDays >= 14)
      return const CharacterState(mood: CharacterMood.ecstatic, emoji: '🏆', message: 'Legend! 14-day streak maintained!');
    if (completionPercent >= 1.0 && streakDays >= 7)
      return const CharacterState(mood: CharacterMood.ecstatic, emoji: '🦁', message: 'Unstoppable! Week streak on fire!');
    if (completionPercent >= 1.0)
      return const CharacterState(mood: CharacterMood.happy, emoji: '🎯', message: 'Daily goal smashed! Outstanding!');
    if (completionPercent >= 0.75)
      return const CharacterState(mood: CharacterMood.happy, emoji: '⚡', message: "Almost done with today's goal!");
    if (completionPercent >= 0.5)
      return const CharacterState(mood: CharacterMood.neutral, emoji: '🌿', message: 'Halfway there — keep the flow!');
    if (sessionsToday > 0)
      return const CharacterState(mood: CharacterMood.neutral, emoji: '🐢', message: 'Good start — a few more sessions!');
    if (streakDays > 3)
      return const CharacterState(mood: CharacterMood.struggling, emoji: '😬', message: 'Your streak needs you today!');
    return const CharacterState(mood: CharacterMood.sad, emoji: '🌧', message: "Let's start — even 5 minutes counts!");
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 3g. DAILY GOAL
// ═══════════════════════════════════════════════════════════════════════════

class DailyGoal extends ChangeNotifier {
  double targetMinutes;
  double _completedMinutes = 0;
  double get completedMinutes => _completedMinutes;

  DailyGoal({this.targetMinutes = 120});

  double completionPercentage() =>
      targetMinutes == 0 ? 0 : (_completedMinutes / targetMinutes).clamp(0.0, 1.0);

  void addMinutes(double m) { _completedMinutes += m; notifyListeners(); }
  void resetDay() { _completedMinutes = 0; notifyListeners(); }

  String formattedProgress() {
    final pct = (completionPercentage() * 100).round();
    return '${_completedMinutes.round()} / ${targetMinutes.round()} min  ($pct%)';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 4. PRODUCTIVITY ENGINE — coordinator
// ═══════════════════════════════════════════════════════════════════════════

class ProductivityEngine extends ChangeNotifier {
  final StorageService storage;
  late final SubjectManager subjectManager;
  late final RewardEngine rewardEngine;
  late final DailyGoal dailyGoal;
  static const _treeEngine = TreeGrowthEngine();

  StreakEngine _streak = const StreakEngine();
  StreakEngine get streak => _streak;

  TreeGrowthResult? _treeResult;
  TreeGrowthResult? get treeResult => _treeResult;

  final List<SessionRecord> _history = [];
  List<SessionRecord> get history => List.unmodifiable(_history);

  int get sessionsToday {
    final t = DateTime.now();
    return _history.where((r) =>
    r.completed &&
        r.startedAt.year  == t.year &&
        r.startedAt.month == t.month &&
        r.startedAt.day   == t.day).length;
  }

  ProductivityEngine({StorageService? storage})
      : storage = storage ?? InMemoryStorage() {
    subjectManager = SubjectManager(this.storage);
    rewardEngine   = RewardEngine();
    dailyGoal      = DailyGoal();
  }

  Future<void> initialize() async {
    await subjectManager.load();
    await _loadHistory();
    _recomputeDerived();
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FIXED: buildSession() replaces the old startSession().
  //
  // Old startSession() had two critical bugs:
  //   1. It called _activeSession?.dispose() which disposed the session
  //      the UI was still holding — causing "used after dispose" on re-nav.
  //   2. It auto-called session.start() — the UI couldn't show an idle state.
  //
  // buildSession() just CREATES and returns a session; the caller owns it
  // entirely and decides when to start/stop/dispose it.
  // ─────────────────────────────────────────────────────────────────────────
  PomodoroSession buildSession() {
    final subject = subjectManager.selected
        ?? const Subject(id: 'default', name: 'Focus');
    return PomodoroSession(subject: subject);
    // NOTE: caller must set onFocusComplete, addListener, and start() themselves.
  }

  // Called by the UI when a focus interval completes.
  void recordFocusComplete(PomodoroSession session) {
    final record = SessionRecord(
      subjectId: session.subject.id,
      startedAt: DateTime.now(),
      focusDuration: session.subject.focusDuration,
      completed: true,
    );
    _history.add(record);
    _persistHistory();
    dailyGoal.addMinutes(record.focusDuration.inSeconds / 60.0);
    rewardEngine.awardSession(
        focusDuration: record.focusDuration,
        currentStreak: _streak.currentStreak);
    _recomputeDerived();
    notifyListeners();
  }

  CharacterState characterState({SessionPhase phase = SessionPhase.idle}) =>
      MotivationCharacter.evaluate(
        streakDays: _streak.currentStreak,
        completionPercent: dailyGoal.completionPercentage(),
        sessionsToday: sessionsToday,
        phase: phase,
      );

  void rolloverDay() {
    dailyGoal.resetDay();
    _recomputeDerived();
    notifyListeners();
  }

  void _recomputeDerived() {
    _streak = _streak.recompute(
        history: _history, targetMinutes: dailyGoal.targetMinutes);
    final multiplier = 1.0 + _streak.currentStreak * 0.05;
    final totalMins = _history
        .where((r) => r.completed)
        .fold(0.0, (acc, r) => acc + r.focusDuration.inSeconds / 60.0);
    _treeResult = _treeEngine.compute(
        totalFocusMinutes: totalMins, streakMultiplier: multiplier);
  }

  static const _kHistory = 'session_history_v1';

  Future<void> _loadHistory() async {
    final raw = await storage.getString(_kHistory);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _history.addAll(
          list.map((e) => SessionRecord.fromJson(e as Map<String, dynamic>)));
    } catch (_) {}
  }

  Future<void> _persistHistory() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    _history.removeWhere((r) => r.startedAt.isBefore(cutoff));
    await storage.setString(
        _kHistory, jsonEncode(_history.map((r) => r.toJson()).toList()));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 5. APP LIFECYCLE MIXIN
// ═══════════════════════════════════════════════════════════════════════════

mixin PomodoroLifecycleMixin<T extends StatefulWidget>
on State<T>, WidgetsBindingObserver {
  PomodoroSession? get watchedSession;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = watchedSession;
    if (s == null) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        if (s.isRunning) s.pause();
        break;
      default:
        break;
    }
  }
}