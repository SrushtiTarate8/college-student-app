// =============================================================================
// ResultScreen.dart
// Complete Result Prediction Module for College App
//
// Architecture:
//   ├── Models         (GradeScale, Subject, Semester)
//   ├── Calculator     (SGPACalculator, PredictionEngine)
//   ├── State Mgmt     (ResultPredictionProvider via ChangeNotifier)
//   └── UI             (ResultScreen + sub-widgets)

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1 — MODELS
// ─────────────────────────────────────────────────────────────────────────────

/// Represents a single grade band in the grading system.
/// e.g.  O grade: minMarks=90, maxMarks=100, gradePoints=10
class GradeScale {
  final String label;       // "O", "A+", "A", "B+", "B", "C", "F"
  final double minMarks;    // inclusive lower bound (out of 100)
  final double maxMarks;    // inclusive upper bound (out of 100)
  final double gradePoints; // grade point awarded for this band

  const GradeScale({
    required this.label,
    required this.minMarks,
    required this.maxMarks,
    required this.gradePoints,
  });

  /// Returns true when [totalMarks] falls in this grade band.
  bool matches(double totalMarks) =>
      totalMarks >= minMarks && totalMarks <= maxMarks;

  Map<String, dynamic> toJson() => {
    'label': label,
    'minMarks': minMarks,
    'maxMarks': maxMarks,
    'gradePoints': gradePoints,
  };

  factory GradeScale.fromJson(Map<String, dynamic> json) => GradeScale(
    label: json['label'] as String,
    minMarks: (json['minMarks'] as num).toDouble(),
    maxMarks: (json['maxMarks'] as num).toDouble(),
    gradePoints: (json['gradePoints'] as num).toDouble(),
  );
}

/// Represents one subject in the current semester.
class Subject {
  final String id;
  String name;
  double credits;

  // Actual marks entered by student (null = not yet entered)
  double? internalMarks;
  double? endSemMarks;

  // Expected / what-if marks (used for simulation)
  double? expectedInternalMarks;
  double? expectedEndSemMarks;

  // Whether to use expected marks for calculation
  bool useExpected;

  Subject({
    required this.id,
    required this.name,
    required this.credits,
    this.internalMarks,
    this.endSemMarks,
    this.expectedInternalMarks,
    this.expectedEndSemMarks,
    this.useExpected = false,
  });

  Subject copyWith({
    String? name,
    double? credits,
    double? internalMarks,
    double? endSemMarks,
    double? expectedInternalMarks,
    double? expectedEndSemMarks,
    bool? useExpected,
  }) =>
      Subject(
        id: id,
        name: name ?? this.name,
        credits: credits ?? this.credits,
        internalMarks: internalMarks ?? this.internalMarks,
        endSemMarks: endSemMarks ?? this.endSemMarks,
        expectedInternalMarks:
        expectedInternalMarks ?? this.expectedInternalMarks,
        expectedEndSemMarks: expectedEndSemMarks ?? this.expectedEndSemMarks,
        useExpected: useExpected ?? this.useExpected,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'credits': credits,
    'internalMarks': internalMarks,
    'endSemMarks': endSemMarks,
    'expectedInternalMarks': expectedInternalMarks,
    'expectedEndSemMarks': expectedEndSemMarks,
    'useExpected': useExpected,
  };

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
    id: json['id'] as String,
    name: json['name'] as String,
    credits: (json['credits'] as num).toDouble(),
    internalMarks: (json['internalMarks'] as num?)?.toDouble(),
    endSemMarks: (json['endSemMarks'] as num?)?.toDouble(),
    expectedInternalMarks:
    (json['expectedInternalMarks'] as num?)?.toDouble(),
    expectedEndSemMarks: (json['expectedEndSemMarks'] as num?)?.toDouble(),
    useExpected: json['useExpected'] as bool? ?? false,
  );
}

/// Stores configuration for the marking scheme.
class GradingConfig {
  final double internalWeight;  // e.g. 40  (marks out of internalMax)
  final double endSemWeight;    // e.g. 60  (marks out of endSemMax)
  final double internalMax;     // max marks for internal (default 40)
  final double endSemMax;       // max marks for end-sem  (default 60)
  final List<GradeScale> gradeScales; // sorted descending by minMarks

  const GradingConfig({
    required this.internalWeight,
    required this.endSemWeight,
    required this.internalMax,
    required this.endSemMax,
    required this.gradeScales,
  });

  /// Default university grading (Anna University style)
  static GradingConfig get defaultConfig => const GradingConfig(
    internalWeight: 40,
    endSemWeight: 60,
    internalMax: 40,
    endSemMax: 60,
    gradeScales: [
      GradeScale(label: 'O',  minMarks: 91, maxMarks: 100, gradePoints: 10),
      GradeScale(label: 'A+', minMarks: 81, maxMarks: 90,  gradePoints: 9),
      GradeScale(label: 'A',  minMarks: 71, maxMarks: 80,  gradePoints: 8),
      GradeScale(label: 'B+', minMarks: 61, maxMarks: 70,  gradePoints: 7),
      GradeScale(label: 'B',  minMarks: 57, maxMarks: 60,  gradePoints: 6),
      GradeScale(label: 'C',  minMarks: 50, maxMarks: 56,  gradePoints: 5),
      GradeScale(label: 'F',  minMarks: 0,  maxMarks: 49,  gradePoints: 0),
    ],
  );
}

/// Holds computed results for a single subject.
class SubjectResult {
  final Subject subject;
  final double totalMarks;        // out of 100
  final String grade;
  final double gradePoints;
  final double weightedPoints;    // credits × gradePoints
  final bool isPassing;

  const SubjectResult({
    required this.subject,
    required this.totalMarks,
    required this.grade,
    required this.gradePoints,
    required this.weightedPoints,
    required this.isPassing,
  });
}

/// Prediction for a single subject given a target grade.
class SubjectPrediction {
  final Subject subject;
  final String targetGrade;
  final double requiredEndSemMarks; // out of endSemMax
  final bool isAchievable;
  final String insight;

  const SubjectPrediction({
    required this.subject,
    required this.targetGrade,
    required this.requiredEndSemMarks,
    required this.isAchievable,
    required this.insight,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2 — CALCULATION ENGINE
// ─────────────────────────────────────────────────────────────────────────────

class SGPACalculator {
  final GradingConfig config;

  const SGPACalculator(this.config);

  /// Converts internal + end-sem raw marks to a combined score out of 100.
  /// Internal  : student scores [internalMarks] out of [config.internalMax]
  /// End-Sem   : student scores [endSemMarks]   out of [config.endSemMax]
  /// Total     = (internalMarks / internalMax * 40) + (endSemMarks / endSemMax * 60)
  double computeTotalMarks(double internal, double endSem) {
    final normalizedInternal =
        (internal / config.internalMax) * config.internalWeight;
    final normalizedEndSem =
        (endSem / config.endSemMax) * config.endSemWeight;
    return (normalizedInternal + normalizedEndSem).clamp(0.0, 100.0);
  }

  /// Returns the GradeScale that matches [totalMarks], or 'F' if none.
  GradeScale resolveGrade(double totalMarks) {
    for (final scale in config.gradeScales) {
      if (scale.matches(totalMarks)) return scale;
    }
    // Fall back to lowest grade
    return config.gradeScales.last;
  }

  /// Computes SubjectResult for a subject using actual or expected marks.
  SubjectResult? computeSubjectResult(Subject subject) {
    final internal = subject.useExpected
        ? subject.expectedInternalMarks
        : subject.internalMarks;
    final endSem = subject.useExpected
        ? subject.expectedEndSemMarks
        : subject.endSemMarks;

    if (internal == null || endSem == null) return null;

    final total = computeTotalMarks(internal, endSem);
    final scale = resolveGrade(total);

    return SubjectResult(
      subject: subject,
      totalMarks: total,
      grade: scale.label,
      gradePoints: scale.gradePoints,
      weightedPoints: subject.credits * scale.gradePoints,
      isPassing: scale.gradePoints > 0,
    );
  }

  /// Calculates SGPA from a list of subjects.
  /// Returns null if no subjects have complete marks.
  double? calculateSGPA(List<Subject> subjects) {
    final results =
    subjects.map(computeSubjectResult).whereType<SubjectResult>().toList();
    if (results.isEmpty) return null;

    final totalWeightedPoints =
    results.fold(0.0, (sum, r) => sum + r.weightedPoints);
    final totalCredits = results.fold(0.0, (sum, r) => sum + r.subject.credits);

    if (totalCredits == 0) return null;
    return totalWeightedPoints / totalCredits;
  }

  /// Calculates CGPA given previous semesters and current semester.
  /// [prevSGPAs] = List of (sgpa, totalCredits) tuples for prior semesters.
  double? calculateCGPA(
      List<(double sgpa, double credits)> prevSemesters,
      List<Subject> currentSubjects,
      ) {
    final currentSGPA = calculateSGPA(currentSubjects);

    final allSemesters = [
      ...prevSemesters,
      if (currentSGPA != null)
        (
        currentSGPA,
        currentSubjects.fold(0.0, (s, sub) => s + sub.credits),
        ),
    ];

    if (allSemesters.isEmpty) return null;

    final totalWeighted = allSemesters.fold(
        0.0, (sum, sem) => sum + (sem.$1 * sem.$2));
    final totalCredits =
    allSemesters.fold(0.0, (sum, sem) => sum + sem.$2);

    if (totalCredits == 0) return null;
    return totalWeighted / totalCredits;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3 — PREDICTION ENGINE
// ─────────────────────────────────────────────────────────────────────────────

class PredictionEngine {
  final GradingConfig config;
  final SGPACalculator calculator;

  PredictionEngine(this.config) : calculator = SGPACalculator(config);

  /// For a subject, given a target grade label (e.g., "O"),
  /// computes the minimum end-sem marks required.
  SubjectPrediction predictForTargetGrade(
      Subject subject, String targetGradeLabel) {
    // Find the target grade scale
    final targetScale = config.gradeScales.firstWhere(
          (s) => s.label == targetGradeLabel,
      orElse: () => config.gradeScales.last,
    );

    // Use actual internal marks if available, else expected, else 0
    final internal = subject.internalMarks ??
        subject.expectedInternalMarks ??
        0.0;

    // Minimum total score needed = targetScale.minMarks
    // total = (internal / internalMax * 40) + (endSem / endSemMax * 60)
    // Solve for endSem:
    // endSem = ((target - internalContribution) / 60) * endSemMax
    final internalContribution =
        (internal / config.internalMax) * config.internalWeight;
    final requiredEndSemNormalized =
        targetScale.minMarks - internalContribution;
    final requiredEndSem =
        (requiredEndSemNormalized / config.endSemWeight) * config.endSemMax;

    final clamped = requiredEndSem.clamp(0.0, config.endSemMax);
    final isAchievable = requiredEndSem <= config.endSemMax;

    final insight = _buildInsight(
      subject.name,
      targetGradeLabel,
      clamped,
      isAchievable,
      internal,
    );

    return SubjectPrediction(
      subject: subject,
      targetGrade: targetGradeLabel,
      requiredEndSemMarks: clamped,
      isAchievable: isAchievable,
      insight: insight,
    );
  }

  String _buildInsight(String subjectName, String grade, double required,
      bool achievable, double internal) {
    if (!achievable) {
      return '❌ $subjectName: $grade grade not achievable with internal $internal/${config.internalMax}.';
    }
    if (required >= config.endSemMax * 0.95) {
      return '⚠️ $subjectName: Need ${required.toStringAsFixed(1)}/${config.endSemMax.toStringAsFixed(0)} — very tough for $grade.';
    }
    if (required >= config.endSemMax * 0.75) {
      return '🟡 $subjectName: Need ${required.toStringAsFixed(1)}/${config.endSemMax.toStringAsFixed(0)} — moderate effort for $grade.';
    }
    return '✅ $subjectName: Need ${required.toStringAsFixed(1)}/${config.endSemMax.toStringAsFixed(0)} — achievable for $grade.';
  }

  /// Given a target CGPA, returns the required SGPA for the current semester.
  double requiredSGPAForTargetCGPA({
    required double currentCGPA,
    required double completedCredits,
    required double targetCGPA,
    required double currentSemesterCredits,
  }) {
    // CGPA = (currentCGPA * completedCredits + SGPA * semCredits)
    //         / (completedCredits + semCredits)
    // Solving for SGPA:
    final total = completedCredits + currentSemesterCredits;
    final required =
        (targetCGPA * total - currentCGPA * completedCredits) /
            currentSemesterCredits;
    return required.clamp(0.0, 10.0);
  }

  /// Suggests marks distribution across subjects to achieve a target SGPA.
  /// Strategy: start from the highest-credit subject and assign optimally.
  List<SubjectPrediction> suggestMarksForTargetSGPA({
    required List<Subject> subjects,
    required double targetSGPA,
    String preferredTargetGrade = 'A+',
  }) {
    // Find the grade needed to achieve targetSGPA across subjects uniformly
    // Simple strategy: find the grade band that gives >= targetSGPA gradePoints
    final neededGradePoints = targetSGPA;
    GradeScale targetScale = config.gradeScales.last;
    for (final scale in config.gradeScales) {
      if (scale.gradePoints >= neededGradePoints) {
        targetScale = scale;
        // Pick the lowest grade that still meets the threshold
        break;
      }
    }

    return subjects
        .map((s) => predictForTargetGrade(s, targetScale.label))
        .toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 4 — STATE MANAGEMENT (Provider / ChangeNotifier)
// ─────────────────────────────────────────────────────────────────────────────

class ResultPredictionProvider extends ChangeNotifier {
  // ── Config ──────────────────────────────────────────────────────────────
  GradingConfig _gradingConfig = GradingConfig.defaultConfig;
  GradingConfig get gradingConfig => _gradingConfig;

  // ── Subjects ─────────────────────────────────────────────────────────────
  List<Subject> _subjects = [];
  List<Subject> get subjects => List.unmodifiable(_subjects);

  // ── Previous Semester Data ────────────────────────────────────────────────
  double _previousCGPA = 0.0;
  double _completedCredits = 0.0;
  double get previousCGPA => _previousCGPA;
  double get completedCredits => _completedCredits;

  // ── Target Inputs ─────────────────────────────────────────────────────────
  String _targetGradeLabel = 'A+';
  double _targetCGPA = 8.5;
  String get targetGradeLabel => _targetGradeLabel;
  double get targetCGPA => _targetCGPA;

  // ── Derived / Computed ────────────────────────────────────────────────────
  late SGPACalculator _sgpaCalculator;
  late PredictionEngine _predictionEngine;

  ResultPredictionProvider() {
    _sgpaCalculator = SGPACalculator(_gradingConfig);
    _predictionEngine = PredictionEngine(_gradingConfig);
    _loadFromPrefs();
    _initDefaultSubjects();
  }

  void _initDefaultSubjects() {
    if (_subjects.isNotEmpty) return;
    _subjects = [
      Subject(id: _uid(), name: 'Mathematics', credits: 4),
      Subject(id: _uid(), name: 'Physics', credits: 3),
      Subject(id: _uid(), name: 'Programming', credits: 4),
      Subject(id: _uid(), name: 'English', credits: 2),
      Subject(id: _uid(), name: 'Electronics', credits: 3),
    ];
  }

  String _uid() =>
      DateTime.now().microsecondsSinceEpoch.toString() +
          Random().nextInt(9999).toString();

  // ── Computed Properties ───────────────────────────────────────────────────

  List<SubjectResult?> get subjectResults =>
      _subjects.map(_sgpaCalculator.computeSubjectResult).toList();

  double? get currentSGPA => _sgpaCalculator.calculateSGPA(_subjects);

  double? get predictedCGPA {
    final sgpa = currentSGPA;
    if (sgpa == null && _completedCredits == 0) return null;

    final semCredits =
    _subjects.fold(0.0, (s, sub) => s + sub.credits);
    final prevSemesters = _completedCredits > 0
        ? [(_previousCGPA, _completedCredits)]
        : <(double, double)>[];

    return _sgpaCalculator.calculateCGPA(prevSemesters, _subjects);
  }

  Subject? get mostImpactfulSubject {
    if (_subjects.isEmpty) return null;
    return _subjects.reduce((a, b) => a.credits > b.credits ? a : b);
  }

  List<SubjectPrediction> get targetGradePredictions => _subjects
      .map((s) => _predictionEngine.predictForTargetGrade(s, _targetGradeLabel))
      .toList();

  double get requiredSGPAForTarget {
    final semCredits = _subjects.fold(0.0, (s, sub) => s + sub.credits);
    if (semCredits == 0 || _completedCredits == 0) return _targetCGPA;
    return _predictionEngine.requiredSGPAForTargetCGPA(
      currentCGPA: _previousCGPA,
      completedCredits: _completedCredits,
      targetCGPA: _targetCGPA,
      currentSemesterCredits: semCredits,
    );
  }

  List<SubjectPrediction> get cgpaTargetPredictions =>
      _predictionEngine.suggestMarksForTargetSGPA(
        subjects: _subjects,
        targetSGPA: requiredSGPAForTarget,
      );

  // ── Mutations ─────────────────────────────────────────────────────────────

  void addSubject() {
    _subjects.add(Subject(
      id: _uid(),
      name: 'Subject ${_subjects.length + 1}',
      credits: 3,
    ));
    _save();
    notifyListeners();
  }

  void removeSubject(String id) {
    _subjects.removeWhere((s) => s.id == id);
    _save();
    notifyListeners();
  }

  void updateSubjectName(String id, String name) {
    _mutate(id, (s) => s.copyWith(name: name));
  }

  void updateSubjectCredits(String id, double credits) {
    _mutate(id, (s) => s.copyWith(credits: credits));
  }

  void updateInternalMarks(String id, double? marks) {
    _mutate(id, (s) => s.copyWith(internalMarks: marks));
  }

  void updateEndSemMarks(String id, double? marks) {
    _mutate(id, (s) => s.copyWith(endSemMarks: marks));
  }

  void updateExpectedInternalMarks(String id, double? marks) {
    _mutate(id, (s) => s.copyWith(expectedInternalMarks: marks));
  }

  void updateExpectedEndSemMarks(String id, double? marks) {
    _mutate(id, (s) => s.copyWith(expectedEndSemMarks: marks));
  }

  void toggleUseExpected(String id, bool value) {
    _mutate(id, (s) => s.copyWith(useExpected: value));
  }

  void setPreviousCGPA(double val) {
    _previousCGPA = val.clamp(0.0, 10.0);
    _save();
    notifyListeners();
  }

  void setCompletedCredits(double val) {
    _completedCredits = val.clamp(0.0, 500.0);
    _save();
    notifyListeners();
  }

  void setTargetGradeLabel(String label) {
    _targetGradeLabel = label;
    notifyListeners();
  }

  void setTargetCGPA(double val) {
    _targetCGPA = val.clamp(0.0, 10.0);
    notifyListeners();
  }

  void _mutate(String id, Subject Function(Subject) updater) {
    final idx = _subjects.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    _subjects[idx] = updater(_subjects[idx]);
    _save();
    notifyListeners();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'subjects': _subjects.map((s) => s.toJson()).toList(),
        'previousCGPA': _previousCGPA,
        'completedCredits': _completedCredits,
      };
      await prefs.setString('result_prediction_data', jsonEncode(data));
    } catch (_) {
      // Silently fail — non-critical persistence
    }
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('result_prediction_data');
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _subjects = (data['subjects'] as List)
          .map((e) => Subject.fromJson(e as Map<String, dynamic>))
          .toList();
      _previousCGPA = (data['previousCGPA'] as num?)?.toDouble() ?? 0.0;
      _completedCredits = (data['completedCredits'] as num?)?.toDouble() ?? 0.0;
      notifyListeners();
    } catch (_) {
      // Corrupted data — start fresh
    }
  }

  void clearAll() {
    _subjects.clear();
    _previousCGPA = 0.0;
    _completedCredits = 0.0;
    _initDefaultSubjects();
    _save();
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 5 — THEME & DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────

class _AppTheme {
  static const Color bg = Color(0xFF0F1117);
  static const Color surface = Color(0xFF1A1D27);
  static const Color surfaceElevated = Color(0xFF222535);
  static const Color accent = Color(0xFF6C63FF);
  static const Color accentLight = Color(0xFF8B85FF);
  static const Color green = Color(0xFF29D6A4);
  static const Color yellow = Color(0xFFFFBB38);
  static const Color red = Color(0xFFFF5C7A);
  static const Color textPrimary = Color(0xFFEEF0FF);
  static const Color textSecondary = Color(0xFF8B8FA8);
  static const Color border = Color(0xFF2E3147);

  static Color statusColor(double marks, double maxMarks) {
    final pct = marks / maxMarks;
    if (pct >= 0.85) return green;
    if (pct >= 0.65) return yellow;
    return red;
  }

  static Color gradeColor(String grade) {
    switch (grade) {
      case 'O':
        return green;
      case 'A+':
      case 'A':
        return const Color(0xFF5DADE2);
      case 'B+':
      case 'B':
        return yellow;
      default:
        return red;
    }
  }

  static ThemeData get theme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      surface: surface,
      primary: accent,
      secondary: accentLight,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: border, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
      labelStyle: const TextStyle(color: textSecondary, fontSize: 12),
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    fontFamily: 'Roboto',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 6 — MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

/// Entry point — wrap in ChangeNotifierProvider before use.
/// Your HomeScreen's navigation call:
///   Navigator.push(context, MaterialPageRoute(
///     builder: (_) => const ResultScreen()));
///
/// Make sure to add the provider higher in your widget tree (e.g. main.dart):
///   ChangeNotifierProvider(create: (_) => ResultPredictionProvider(), ...)
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      // Provide locally so this module is self-contained.
      // Remove this wrapper if you provide it globally in main.dart.
      create: (_) => ResultPredictionProvider(),
      child: Theme(
        data: _AppTheme.theme,
        child: Scaffold(
          backgroundColor: _AppTheme.bg,
          appBar: _buildAppBar(),
          body: Column(
            children: [
              _SummaryBanner(),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: const [
                    _SubjectsTab(),
                    _PredictionTab(),
                    _InsightsTab(),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: _buildFAB(),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _AppTheme.bg,
      elevation: 0,
      leading: BackButton(color: _AppTheme.textPrimary),
      title: const Text(
        'Result Prediction',
        style: TextStyle(
          color: _AppTheme.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      actions: [
        Consumer<ResultPredictionProvider>(
          builder: (context, provider, _) => IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _AppTheme.textSecondary),
            tooltip: 'Reset all data',
            onPressed: () => _confirmReset(context, provider),
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: _AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _AppTheme.border),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: _AppTheme.accent,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: _AppTheme.textSecondary,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: 'Subjects'),
          Tab(text: 'Predict'),
          Tab(text: 'Insights'),
        ],
      ),
    );
  }

  Widget _buildFAB() {
    return Consumer<ResultPredictionProvider>(
      builder: (context, provider, _) => FloatingActionButton.extended(
        onPressed: provider.addSubject,
        backgroundColor: _AppTheme.accent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Subject',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _confirmReset(BuildContext context, ResultPredictionProvider provider) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _AppTheme.surfaceElevated,
        title: const Text('Reset All Data?',
            style: TextStyle(color: _AppTheme.textPrimary)),
        content: const Text(
          'This will clear all subjects and marks. Cannot be undone.',
          style: TextStyle(color: _AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: _AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              provider.clearAll();
              Navigator.pop(context);
            },
            child: const Text('Reset',
                style: TextStyle(color: _AppTheme.red)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 7 — SUMMARY BANNER
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner();

  @override
  Widget build(BuildContext context) {
    return Consumer<ResultPredictionProvider>(
      builder: (context, provider, _) {
        final sgpa = provider.currentSGPA;
        final cgpa = provider.predictedCGPA;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E1B4B), Color(0xFF1A1D27)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _AppTheme.accent.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              _StatPill(
                label: 'SGPA',
                value: sgpa != null ? sgpa.toStringAsFixed(2) : '--',
                color: sgpa != null
                    ? _sgpaColor(sgpa)
                    : _AppTheme.textSecondary,
              ),
              const SizedBox(width: 12),
              Container(width: 1, height: 40, color: _AppTheme.border),
              const SizedBox(width: 12),
              _StatPill(
                label: 'Predicted CGPA',
                value: cgpa != null ? cgpa.toStringAsFixed(2) : '--',
                color: cgpa != null
                    ? _sgpaColor(cgpa)
                    : _AppTheme.textSecondary,
              ),
              const Spacer(),
              if (provider.mostImpactfulSubject != null)
                _HighlightChip(
                  label: '⭐ ${provider.mostImpactfulSubject!.name}',
                  subtitle: '${provider.mostImpactfulSubject!.credits} credits',
                ),
            ],
          ),
        );
      },
    );
  }

  Color _sgpaColor(double val) {
    if (val >= 8.5) return _AppTheme.green;
    if (val >= 7.0) return _AppTheme.yellow;
    return _AppTheme.red;
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatPill(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: _AppTheme.textSecondary, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5)),
      ],
    );
  }
}

class _HighlightChip extends StatelessWidget {
  final String label;
  final String subtitle;
  const _HighlightChip({required this.label, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _AppTheme.accent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _AppTheme.accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: _AppTheme.accentLight,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          Text(subtitle,
              style: const TextStyle(
                  color: _AppTheme.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 8 — SUBJECTS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _SubjectsTab extends StatelessWidget {
  const _SubjectsTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<ResultPredictionProvider>(
      builder: (context, provider, _) {
        final subjects = provider.subjects;
        final results = provider.subjectResults;
        final mostImpactId = provider.mostImpactfulSubject?.id;

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: subjects.length,
          itemBuilder: (context, idx) {
            return _SubjectCard(
              subject: subjects[idx],
              result: results[idx],
              isMostImpactful: subjects[idx].id == mostImpactId,
              config: provider.gradingConfig,
              provider: provider,
            );
          },
        );
      },
    );
  }
}

class _SubjectCard extends StatefulWidget {
  final Subject subject;
  final SubjectResult? result;
  final bool isMostImpactful;
  final GradingConfig config;
  final ResultPredictionProvider provider;

  const _SubjectCard({
    required this.subject,
    required this.result,
    required this.isMostImpactful,
    required this.config,
    required this.provider,
  });

  @override
  State<_SubjectCard> createState() => _SubjectCardState();
}

class _SubjectCardState extends State<_SubjectCard> {
  bool _expanded = true;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _creditsCtrl;
  late final TextEditingController _internalCtrl;
  late final TextEditingController _endSemCtrl;
  late final TextEditingController _expInternalCtrl;
  late final TextEditingController _expEndSemCtrl;

  @override
  void initState() {
    super.initState();
    final s = widget.subject;
    _nameCtrl = TextEditingController(text: s.name);
    _creditsCtrl =
        TextEditingController(text: s.credits.toStringAsFixed(0));
    _internalCtrl =
        TextEditingController(text: s.internalMarks?.toStringAsFixed(1) ?? '');
    _endSemCtrl =
        TextEditingController(text: s.endSemMarks?.toStringAsFixed(1) ?? '');
    _expInternalCtrl = TextEditingController(
        text: s.expectedInternalMarks?.toStringAsFixed(1) ?? '');
    _expEndSemCtrl = TextEditingController(
        text: s.expectedEndSemMarks?.toStringAsFixed(1) ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _creditsCtrl.dispose();
    _internalCtrl.dispose();
    _endSemCtrl.dispose();
    _expInternalCtrl.dispose();
    _expEndSemCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.subject;
    final r = widget.result;
    final isMost = widget.isMostImpactful;
    final p = widget.provider;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMost
              ? _AppTheme.accent.withOpacity(0.5)
              : _AppTheme.border,
          width: isMost ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // ── Header row ────────────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  if (isMost)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _AppTheme.accent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('⭐ Top',
                          style: TextStyle(
                              color: _AppTheme.accentLight, fontSize: 10)),
                    ),
                  Expanded(
                    child: Text(s.name,
                        style: const TextStyle(
                            color: _AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ),
                  if (r != null) ...[
                    _GradeBadge(grade: r.grade),
                    const SizedBox(width: 8),
                    Text(r.totalMarks.toStringAsFixed(1),
                        style: TextStyle(
                            color: _AppTheme.statusColor(
                                r.totalMarks, 100),
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                  ],
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: _AppTheme.textSecondary,
                    size: 20,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: _AppTheme.textSecondary, size: 18),
                    onPressed: () => p.removeSubject(s.id),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(left: 4),
                  ),
                ],
              ),
            ),
          ),

          // ── Credits & name editor ─────────────────────────────────────────
          if (_expanded) ...[
            const Divider(color: _AppTheme.border, height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + Credits row
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _MarkInput(
                          label: 'Subject Name',
                          controller: _nameCtrl,
                          isText: true,
                          onChanged: (v) => p.updateSubjectName(s.id, v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MarkInput(
                          label: 'Credits',
                          controller: _creditsCtrl,
                          maxVal: 6,
                          onChanged: (v) {
                            final d = double.tryParse(v);
                            if (d != null) p.updateSubjectCredits(s.id, d);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Toggle actual vs expected
                  Row(
                    children: [
                      const Text('Use Expected Marks (What-If)',
                          style: TextStyle(
                              color: _AppTheme.textSecondary, fontSize: 12)),
                      const Spacer(),
                      Switch(
                        value: s.useExpected,
                        onChanged: (v) => p.toggleUseExpected(s.id, v),
                        activeColor: _AppTheme.accent,
                        materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Actual marks
                  _SectionLabel(
                      '📝 Actual Marks',
                      active: !s.useExpected),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _MarkInput(
                          label:
                          'Internal (/${widget.config.internalMax.toStringAsFixed(0)})',
                          controller: _internalCtrl,
                          maxVal: widget.config.internalMax,
                          enabled: !s.useExpected,
                          onChanged: (v) {
                            final d = double.tryParse(v);
                            p.updateInternalMarks(s.id, d);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MarkInput(
                          label:
                          'End-Sem (/${widget.config.endSemMax.toStringAsFixed(0)})',
                          controller: _endSemCtrl,
                          maxVal: widget.config.endSemMax,
                          enabled: !s.useExpected,
                          onChanged: (v) {
                            final d = double.tryParse(v);
                            p.updateEndSemMarks(s.id, d);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Expected marks
                  _SectionLabel(
                      '🔮 Expected Marks (Simulation)',
                      active: s.useExpected),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _MarkInput(
                          label:
                          'Exp. Internal (/${widget.config.internalMax.toStringAsFixed(0)})',
                          controller: _expInternalCtrl,
                          maxVal: widget.config.internalMax,
                          enabled: s.useExpected,
                          onChanged: (v) {
                            final d = double.tryParse(v);
                            p.updateExpectedInternalMarks(s.id, d);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MarkInput(
                          label:
                          'Exp. End-Sem (/${widget.config.endSemMax.toStringAsFixed(0)})',
                          controller: _expEndSemCtrl,
                          maxVal: widget.config.endSemMax,
                          enabled: s.useExpected,
                          onChanged: (v) {
                            final d = double.tryParse(v);
                            p.updateExpectedEndSemMarks(s.id, d);
                          },
                        ),
                      ),
                    ],
                  ),

                  // End-Sem slider for quick simulation
                  if (s.useExpected) ...[
                    const SizedBox(height: 12),
                    _EndSemSlider(
                      subject: s,
                      config: widget.config,
                      provider: p,
                      endSemController: _expEndSemCtrl,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 9 — PREDICTION TAB
// ─────────────────────────────────────────────────────────────────────────────

class _PredictionTab extends StatelessWidget {
  const _PredictionTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<ResultPredictionProvider>(
      builder: (context, provider, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            _PreviousSemesterCard(provider: provider),
            const SizedBox(height: 16),
            _TargetGradeCard(provider: provider),
            const SizedBox(height: 16),
            _TargetCGPACard(provider: provider),
          ],
        );
      },
    );
  }
}

class _PreviousSemesterCard extends StatefulWidget {
  final ResultPredictionProvider provider;
  const _PreviousSemesterCard({required this.provider});

  @override
  State<_PreviousSemesterCard> createState() => _PreviousSemesterCardState();
}

class _PreviousSemesterCardState extends State<_PreviousSemesterCard> {
  late final TextEditingController _cgpaCtrl;
  late final TextEditingController _creditsCtrl;

  @override
  void initState() {
    super.initState();
    _cgpaCtrl = TextEditingController(
        text: widget.provider.previousCGPA > 0
            ? widget.provider.previousCGPA.toStringAsFixed(2)
            : '');
    _creditsCtrl = TextEditingController(
        text: widget.provider.completedCredits > 0
            ? widget.provider.completedCredits.toStringAsFixed(0)
            : '');
  }

  @override
  void dispose() {
    _cgpaCtrl.dispose();
    _creditsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    return _SectionCard(
      title: '📊 Previous Semester Data',
      subtitle: 'Required for CGPA calculation',
      child: Row(
        children: [
          Expanded(
            child: _MarkInput(
              label: 'CGPA so far (0–10)',
              controller: _cgpaCtrl,
              maxVal: 10,
              onChanged: (v) {
                final d = double.tryParse(v);
                if (d != null) p.setPreviousCGPA(d);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MarkInput(
              label: 'Completed Credits',
              controller: _creditsCtrl,
              maxVal: 500,
              onChanged: (v) {
                final d = double.tryParse(v);
                if (d != null) p.setCompletedCredits(d);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetGradeCard extends StatelessWidget {
  final ResultPredictionProvider provider;
  const _TargetGradeCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final grades = provider.gradingConfig.gradeScales
        .where((s) => s.gradePoints > 0)
        .toList();
    final predictions = provider.targetGradePredictions;

    return _SectionCard(
      title: '🎯 Target Grade Prediction',
      subtitle: 'Required end-sem marks per subject',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grade selector
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: grades.map((g) {
              final selected = g.label == provider.targetGradeLabel;
              return GestureDetector(
                onTap: () => provider.setTargetGradeLabel(g.label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? _AppTheme.accentLight
                        : _AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: selected
                            ? _AppTheme.accent
                            : _AppTheme.border),
                  ),
                  child: Text(
                    '${g.label} (${g.gradePoints.toStringAsFixed(0)})',
                    style: TextStyle(
                      color:
                      selected ? Colors.white : _AppTheme.textSecondary,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Predictions per subject
          ...predictions.map((pred) => _PredictionRow(prediction: pred,
              config: provider.gradingConfig)),
        ],
      ),
    );
  }
}

class _TargetCGPACard extends StatefulWidget {
  final ResultPredictionProvider provider;
  const _TargetCGPACard({required this.provider});

  @override
  State<_TargetCGPACard> createState() => _TargetCGPACardState();
}

class _TargetCGPACardState extends State<_TargetCGPACard> {
  late double _sliderVal;

  @override
  void initState() {
    super.initState();
    _sliderVal = widget.provider.targetCGPA;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    final reqSGPA = p.requiredSGPAForTarget;
    final cgpaPreds = p.cgpaTargetPredictions;

    return _SectionCard(
      title: '🚀 Target CGPA Calculator',
      subtitle: 'Find required SGPA and marks',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Target CGPA: ',
                  style: const TextStyle(
                      color: _AppTheme.textSecondary, fontSize: 13)),
              Text(_sliderVal.toStringAsFixed(1),
                  style: const TextStyle(
                      color: _AppTheme.accentLight,
                      fontWeight: FontWeight.w800,
                      fontSize: 18)),
            ],
          ),
          Slider(
            value: _sliderVal,
            min: 5.0,
            max: 10.0,
            divisions: 50,
            activeColor: _AppTheme.accent,
            inactiveColor: _AppTheme.border,
            onChanged: (v) {
              setState(() => _sliderVal = v);
              p.setTargetCGPA(v);
            },
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: reqSGPA > 10
                      ? _AppTheme.red.withOpacity(0.4)
                      : _AppTheme.green.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  reqSGPA > 10
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  color: reqSGPA > 10 ? _AppTheme.red : _AppTheme.green,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Required SGPA this semester',
                          style: const TextStyle(
                              color: _AppTheme.textSecondary,
                              fontSize: 11)),
                      Text(
                        reqSGPA > 10
                            ? 'Not achievable (need ${reqSGPA.toStringAsFixed(2)} > 10)'
                            : reqSGPA.toStringAsFixed(2),
                        style: TextStyle(
                          color: reqSGPA > 10
                              ? _AppTheme.red
                              : _AppTheme.green,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (reqSGPA <= 10 && cgpaPreds.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Suggested Marks to Achieve Target',
                style: TextStyle(
                    color: _AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            ...cgpaPreds.map((pred) => _PredictionRow(
                prediction: pred, config: p.gradingConfig)),
          ],
        ],
      ),
    );
  }
}

class _PredictionRow extends StatelessWidget {
  final SubjectPrediction prediction;
  final GradingConfig config;
  const _PredictionRow({required this.prediction, required this.config});

  @override
  Widget build(BuildContext context) {
    final p = prediction;
    final pct = p.requiredEndSemMarks / config.endSemMax;
    final color = _AppTheme.statusColor(p.requiredEndSemMarks, config.endSemMax);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: p.isAchievable
                ? _AppTheme.border
                : _AppTheme.red.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.subject.name,
                    style: const TextStyle(
                        color: _AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Text(p.insight,
                    style: const TextStyle(
                        color: _AppTheme.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Text(
                p.isAchievable
                    ? '${p.requiredEndSemMarks.toStringAsFixed(1)}'
                    : 'N/A',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 18),
              ),
              Text('/${config.endSemMax.toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: _AppTheme.textSecondary, fontSize: 10)),
            ],
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              value: p.isAchievable ? pct.clamp(0.0, 1.0) : 1.0,
              backgroundColor: _AppTheme.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              strokeWidth: 3.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 10 — INSIGHTS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _InsightsTab extends StatelessWidget {
  const _InsightsTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<ResultPredictionProvider>(
      builder: (context, provider, _) {
        final insights = _generateInsights(provider);
        final results = provider.subjectResults.whereType<SubjectResult>().toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            if (results.isNotEmpty) _GradeDistributionCard(results: results),
            const SizedBox(height: 16),
            _SectionCard(
              title: '💡 Smart Suggestions',
              subtitle: 'Personalised insights based on your marks',
              child: Column(
                children: insights.isEmpty
                    ? [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Enter marks to see personalised insights.',
                      style: TextStyle(color: _AppTheme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  )
                ]
                    : insights
                    .map((i) => _InsightTile(insight: i))
                    .toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  List<_Insight> _generateInsights(ResultPredictionProvider provider) {
    final insights = <_Insight>[];
    final results =
    provider.subjectResults.whereType<SubjectResult>().toList();
    final sgpa = provider.currentSGPA;
    final config = provider.gradingConfig;

    if (results.isEmpty) return insights;

    // SGPA overview
    if (sgpa != null) {
      if (sgpa >= 9.0) {
        insights.add(_Insight(
            icon: '🏆',
            text: 'Outstanding! Your SGPA of ${sgpa.toStringAsFixed(2)} puts you in top tier.',
            color: _AppTheme.green));
      } else if (sgpa >= 7.5) {
        insights.add(_Insight(
            icon: '👍',
            text: 'Good SGPA of ${sgpa.toStringAsFixed(2)}. Push for ${(sgpa + 0.5).toStringAsFixed(1)} next semester.',
            color: _AppTheme.yellow));
      } else {
        insights.add(_Insight(
            icon: '⚠️',
            text: 'SGPA ${sgpa.toStringAsFixed(2)} is below 7.5. Focus to avoid backlog risk.',
            color: _AppTheme.red));
      }
    }

    // Failing subjects
    final failing = results.where((r) => !r.isPassing).toList();
    for (final f in failing) {
      insights.add(_Insight(
          icon: '🔴',
          text: '${f.subject.name} is at risk of failing (${f.totalMarks.toStringAsFixed(1)}/100). Needs immediate attention.',
          color: _AppTheme.red));
    }

    // Best subject
    if (results.length > 1) {
      final best = results.reduce((a, b) =>
      a.totalMarks > b.totalMarks ? a : b);
      insights.add(_Insight(
          icon: '⭐',
          text: '${best.subject.name} is your strongest subject at ${best.totalMarks.toStringAsFixed(1)}/100 (${best.grade} grade).',
          color: _AppTheme.green));
    }

    // High credit subjects not at full potential
    final highCredit = provider.subjects
        .where((s) => s.credits >= 4)
        .toList();
    for (final s in highCredit) {
      final r = results.firstWhere((r) => r.subject.id == s.id,
          orElse: () => results.first);
      if (r.subject.id == s.id && r.gradePoints < 8) {
        insights.add(_Insight(
            icon: '📌',
            text: 'Focus on ${s.name} (${s.credits} credits) — improving this maximises your SGPA.',
            color: _AppTheme.yellow));
      }
    }

    // Near-grade boundary subjects
    for (final r in results) {
      final currentBand = config.gradeScales
          .firstWhere((g) => g.label == r.grade, orElse: () => config.gradeScales.last);
      final nextBandIdx = config.gradeScales.indexOf(currentBand) - 1;
      if (nextBandIdx >= 0) {
        final nextBand = config.gradeScales[nextBandIdx];
        final gap = nextBand.minMarks - r.totalMarks;
        if (gap > 0 && gap <= 5) {
          insights.add(_Insight(
              icon: '📈',
              text:
              '${r.subject.name} is ${gap.toStringAsFixed(1)} marks away from ${nextBand.label} grade!',
              color: _AppTheme.accentLight));
        }
      }
    }

    return insights;
  }
}

class _Insight {
  final String icon;
  final String text;
  final Color color;
  const _Insight({required this.icon, required this.text, required this.color});
}

class _InsightTile extends StatelessWidget {
  final _Insight insight;
  const _InsightTile({required this.insight});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: insight.color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: insight.color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(insight.icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(insight.text,
                style: TextStyle(
                    color: insight.color.withOpacity(0.9), fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _GradeDistributionCard extends StatelessWidget {
  final List<SubjectResult> results;
  const _GradeDistributionCard({required this.results});

  @override
  Widget build(BuildContext context) {
    // Count grades
    final Map<String, int> dist = {};
    for (final r in results) {
      dist[r.grade] = (dist[r.grade] ?? 0) + 1;
    }

    return _SectionCard(
      title: '📊 Grade Distribution',
      subtitle: 'Current semester overview',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: dist.entries.map((e) {
          return Column(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _AppTheme.gradeColor(e.key).withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _AppTheme.gradeColor(e.key), width: 2),
                ),
                child: Text(e.key,
                    style: TextStyle(
                        color: _AppTheme.gradeColor(e.key),
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
              ),
              const SizedBox(height: 4),
              Text('${e.value} subj',
                  style: const TextStyle(
                      color: _AppTheme.textSecondary, fontSize: 10)),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 11 — REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SectionCard(
      {required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: _AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!,
                style: const TextStyle(
                    color: _AppTheme.textSecondary, fontSize: 12)),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _MarkInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final double maxVal;
  final bool isText;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _MarkInput({
    required this.label,
    required this.controller,
    this.maxVal = 100,
    this.isText = false,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: isText
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: isText
          ? []
          : [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ],
      style: const TextStyle(
          color: _AppTheme.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _AppTheme.border.withOpacity(0.4)),
        ),
      ),
      onChanged: onChanged,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool active;
  const _SectionLabel(this.text, {required this.active});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: active ? _AppTheme.accentLight : _AppTheme.textSecondary,
        fontSize: 12,
        fontWeight: active ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }
}

class _GradeBadge extends StatelessWidget {
  final String grade;
  const _GradeBadge({required this.grade});

  @override
  Widget build(BuildContext context) {
    final color = _AppTheme.gradeColor(grade);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(grade,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

/// Slider widget for quick end-sem mark simulation.
class _EndSemSlider extends StatefulWidget {
  final Subject subject;
  final GradingConfig config;
  final ResultPredictionProvider provider;
  final TextEditingController endSemController;

  const _EndSemSlider({
    required this.subject,
    required this.config,
    required this.provider,
    required this.endSemController,
  });

  @override
  State<_EndSemSlider> createState() => _EndSemSliderState();
}

class _EndSemSliderState extends State<_EndSemSlider> {
  late double _val;

  @override
  void initState() {
    super.initState();
    _val = widget.subject.expectedEndSemMarks ??
        widget.subject.endSemMarks ??
        0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('🎚 Quick End-Sem Adjuster',
                style: TextStyle(
                    color: _AppTheme.textSecondary, fontSize: 11)),
            const Spacer(),
            Text(
              '${_val.toStringAsFixed(1)} / ${widget.config.endSemMax.toStringAsFixed(0)}',
              style: const TextStyle(
                  color: _AppTheme.accentLight,
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
          ],
        ),
        Slider(
          value: _val,
          min: 0,
          max: widget.config.endSemMax,
          divisions: (widget.config.endSemMax * 2).toInt(),
          activeColor: _AppTheme.accent,
          inactiveColor: _AppTheme.border,
          onChanged: (v) {
            setState(() => _val = v);
            widget.endSemController.text = v.toStringAsFixed(1);
            widget.provider.updateExpectedEndSemMarks(widget.subject.id, v);
          },
        ),
      ],
    );
  }
}

// =============================================================================
// HOW TO USE IN YOUR APP
// =============================================================================
//
// 1. Add to pubspec.yaml:
//    dependencies:
//      provider: ^6.1.2
//      shared_preferences: ^2.2.3
//
// 2. Wrap your MaterialApp or the relevant subtree in main.dart:
//
//    void main() {
//      runApp(
//        MultiProvider(
//          providers: [
//            ChangeNotifierProvider(create: (_) => ResultPredictionProvider()),
//          ],
//          child: const MyApp(),
//        ),
//      );
//    }
//
//    NOTE: If you keep the ChangeNotifierProvider INSIDE ResultScreen
//    (as this file does for self-contained operation), you do NOT need the
//    global provider above. The screen manages its own state.
//
// 3. Navigate from your HomeScreen:
//
//    Navigator.push(
//      context,
//      MaterialPageRoute(builder: (context) => const ResultScreen()),
//    );
//
// =============================================================================