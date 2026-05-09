// =============================================================================
// ResultScreen.dart  — v2.0
// Complete Result Prediction Module for College App
// Theme: Red/Rose accent with full dark/light mode toggle via ThemeProvider
//
// NEW in v2.0:
//  • Configurable marking scheme — student picks their university preset
//    (MU 20/80, VTU 30/70, Default 40/60, 50/50, 25/75, or Custom)
//  • Editable internal-max / end-sem-max / pass mark
//  • Grading-config card in Prediction tab with live grade-scale editor
//  • Backlog-risk chip per subject
//  • Credit-load progress bar in summary banner
//  • Attendance warning toggle per subject
//  • Semester selector (Sem 1–8) drives completed-credits hint
//  • Pass-mark line on end-sem slider
// =============================================================================

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 0 — UNIVERSITY PRESETS
// Real Indian university marking schemes
// ─────────────────────────────────────────────────────────────────────────────

class UniversityPreset {
  final String id;
  final String name;
  final String shortName;
  final double internalMax;
  final double endSemMax;
  final double passMarkInternal;   // minimum to pass internal component
  final double passMarkEndSem;     // minimum to pass end-sem component
  final double passMarkTotal;      // minimum total to pass
  final List<GradeScale> gradeScales;

  const UniversityPreset({
    required this.id,
    required this.name,
    required this.shortName,
    required this.internalMax,
    required this.endSemMax,
    required this.passMarkInternal,
    required this.passMarkEndSem,
    required this.passMarkTotal,
    required this.gradeScales,
  });

  double get totalMax => internalMax + endSemMax;
  double get internalWeight => internalMax;
  double get endSemWeight => endSemMax;

  // Normalise to 100 for grade lookup
  double normalise(double internal, double endSem) {
    return ((internal / internalMax) * internalMax +
        (endSem / endSemMax) * endSemMax)
        .clamp(0.0, totalMax);
  }

  // Returns total marks out of totalMax (not 100)
  double computeTotal(double internal, double endSem) =>
      (internal + endSem).clamp(0.0, totalMax);
}

class UniversityPresets {
  // ── Mumbai University — 20 Internal + 80 End-Sem = 100 ──────────────────
  static const UniversityPreset mumbaiUniversity = UniversityPreset(
    id: 'mu',
    name: 'Mumbai University',
    shortName: 'MU (20+80)',
    internalMax: 20,
    endSemMax: 80,
    passMarkInternal: 0,   // MU: no separate internal pass condition
    passMarkEndSem: 32,    // 40% of 80
    passMarkTotal: 40,
    gradeScales: [
      GradeScale(label: 'O',  minMarks: 80, maxMarks: 100, gradePoints: 10),
      GradeScale(label: 'A+', minMarks: 70, maxMarks: 79,  gradePoints: 9),
      GradeScale(label: 'A',  minMarks: 60, maxMarks: 69,  gradePoints: 8),
      GradeScale(label: 'B+', minMarks: 55, maxMarks: 59,  gradePoints: 7),
      GradeScale(label: 'B',  minMarks: 50, maxMarks: 54,  gradePoints: 6),
      GradeScale(label: 'C',  minMarks: 45, maxMarks: 49,  gradePoints: 5),
      GradeScale(label: 'P',  minMarks: 40, maxMarks: 44,  gradePoints: 4),
      GradeScale(label: 'F',  minMarks: 0,  maxMarks: 39,  gradePoints: 0),
    ],
  );

  // ── VTU — 30 Internal + 70 End-Sem = 100 ────────────────────────────────
  static const UniversityPreset vtu = UniversityPreset(
    id: 'vtu',
    name: 'VTU (Visvesvaraya Technological University)',
    shortName: 'VTU (30+70)',
    internalMax: 30,
    endSemMax: 70,
    passMarkInternal: 12,  // 40% of 30
    passMarkEndSem: 28,    // 40% of 70
    passMarkTotal: 40,
    gradeScales: [
      GradeScale(label: 'O',  minMarks: 90, maxMarks: 100, gradePoints: 10),
      GradeScale(label: 'A+', minMarks: 80, maxMarks: 89,  gradePoints: 9),
      GradeScale(label: 'A',  minMarks: 70, maxMarks: 79,  gradePoints: 8),
      GradeScale(label: 'B+', minMarks: 60, maxMarks: 69,  gradePoints: 7),
      GradeScale(label: 'B',  minMarks: 55, maxMarks: 59,  gradePoints: 6),
      GradeScale(label: 'C',  minMarks: 50, maxMarks: 54,  gradePoints: 5),
      GradeScale(label: 'P',  minMarks: 40, maxMarks: 49,  gradePoints: 4),
      GradeScale(label: 'F',  minMarks: 0,  maxMarks: 39,  gradePoints: 0),
    ],
  );

  // ── Anna University — 20 Internal + 80 End-Sem = 100 ─────────────────────
  static const UniversityPreset annaUniversity = UniversityPreset(
    id: 'au',
    name: 'Anna University',
    shortName: 'Anna (20+80)',
    internalMax: 20,
    endSemMax: 80,
    passMarkInternal: 0,
    passMarkEndSem: 32,
    passMarkTotal: 50,
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

  // ── RTM Nagpur University — 40 Internal + 60 End-Sem = 100 ──────────────
  static const UniversityPreset nagpurUniversity = UniversityPreset(
    id: 'rtmnu',
    name: 'RTM Nagpur University',
    shortName: 'RTMNU (40+60)',
    internalMax: 40,
    endSemMax: 60,
    passMarkInternal: 16,
    passMarkEndSem: 24,
    passMarkTotal: 40,
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

  // ── SPPU (Savitribai Phule Pune University) — 30 Internal + 70 End-Sem ───
  static const UniversityPreset sppu = UniversityPreset(
    id: 'sppu',
    name: 'SPPU Pune University',
    shortName: 'SPPU (30+70)',
    internalMax: 30,
    endSemMax: 70,
    passMarkInternal: 0,
    passMarkEndSem: 28,
    passMarkTotal: 40,
    gradeScales: [
      GradeScale(label: 'O',  minMarks: 75, maxMarks: 100, gradePoints: 10),
      GradeScale(label: 'A+', minMarks: 65, maxMarks: 74,  gradePoints: 9),
      GradeScale(label: 'A',  minMarks: 55, maxMarks: 64,  gradePoints: 8),
      GradeScale(label: 'B+', minMarks: 50, maxMarks: 54,  gradePoints: 7),
      GradeScale(label: 'B',  minMarks: 45, maxMarks: 49,  gradePoints: 6),
      GradeScale(label: 'C',  minMarks: 40, maxMarks: 44,  gradePoints: 5),
      GradeScale(label: 'F',  minMarks: 0,  maxMarks: 39,  gradePoints: 0),
    ],
  );

  // ── JNTU — 30 Internal + 70 End-Sem = 100 ────────────────────────────────
  static const UniversityPreset jntu = UniversityPreset(
    id: 'jntu',
    name: 'JNTU',
    shortName: 'JNTU (30+70)',
    internalMax: 30,
    endSemMax: 70,
    passMarkInternal: 12,
    passMarkEndSem: 28,
    passMarkTotal: 40,
    gradeScales: [
      GradeScale(label: 'O',  minMarks: 90, maxMarks: 100, gradePoints: 10),
      GradeScale(label: 'A+', minMarks: 80, maxMarks: 89,  gradePoints: 9),
      GradeScale(label: 'A',  minMarks: 70, maxMarks: 79,  gradePoints: 8),
      GradeScale(label: 'B+', minMarks: 60, maxMarks: 69,  gradePoints: 7),
      GradeScale(label: 'B',  minMarks: 50, maxMarks: 59,  gradePoints: 6),
      GradeScale(label: 'C',  minMarks: 40, maxMarks: 49,  gradePoints: 5),
      GradeScale(label: 'F',  minMarks: 0,  maxMarks: 39,  gradePoints: 0),
    ],
  );

  // ── Custom — fully editable ───────────────────────────────────────────────
  static UniversityPreset custom({
    double internalMax = 40,
    double endSemMax = 60,
    double passMarkTotal = 40,
  }) =>
      UniversityPreset(
        id: 'custom',
        name: 'Custom',
        shortName: 'Custom',
        internalMax: internalMax,
        endSemMax: endSemMax,
        passMarkInternal: 0,
        passMarkEndSem: 0,
        passMarkTotal: passMarkTotal,
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

  static List<UniversityPreset> get all => [
    mumbaiUniversity,
    vtu,
    annaUniversity,
    nagpurUniversity,
    sppu,
    jntu,
    custom(),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1 — MODELS
// ─────────────────────────────────────────────────────────────────────────────

class GradeScale {
  final String label;
  final double minMarks;
  final double maxMarks;
  final double gradePoints;

  const GradeScale({
    required this.label,
    required this.minMarks,
    required this.maxMarks,
    required this.gradePoints,
  });

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

class Subject {
  final String id;
  String name;
  double credits;
  double? internalMarks;
  double? endSemMarks;
  double? expectedInternalMarks;
  double? expectedEndSemMarks;
  bool useExpected;
  bool hasAttendanceShortage; // NEW: attendance warning flag

  Subject({
    required this.id,
    required this.name,
    required this.credits,
    this.internalMarks,
    this.endSemMarks,
    this.expectedInternalMarks,
    this.expectedEndSemMarks,
    this.useExpected = false,
    this.hasAttendanceShortage = false,
  });

  Subject copyWith({
    String? name,
    double? credits,
    double? internalMarks,
    double? endSemMarks,
    double? expectedInternalMarks,
    double? expectedEndSemMarks,
    bool? useExpected,
    bool? hasAttendanceShortage,
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
        hasAttendanceShortage:
        hasAttendanceShortage ?? this.hasAttendanceShortage,
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
    'hasAttendanceShortage': hasAttendanceShortage,
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
    hasAttendanceShortage: json['hasAttendanceShortage'] as bool? ?? false,
  );
}

// GradingConfig is now derived from UniversityPreset
class GradingConfig {
  final double internalMax;
  final double endSemMax;
  final double passMarkTotal;
  final double passMarkInternal;
  final double passMarkEndSem;
  final List<GradeScale> gradeScales;

  const GradingConfig({
    required this.internalMax,
    required this.endSemMax,
    required this.passMarkTotal,
    required this.passMarkInternal,
    required this.passMarkEndSem,
    required this.gradeScales,
  });

  double get totalMax => internalMax + endSemMax;

  factory GradingConfig.fromPreset(UniversityPreset p) => GradingConfig(
    internalMax: p.internalMax,
    endSemMax: p.endSemMax,
    passMarkTotal: p.passMarkTotal,
    passMarkInternal: p.passMarkInternal,
    passMarkEndSem: p.passMarkEndSem,
    gradeScales: List.unmodifiable(p.gradeScales),
  );

  static GradingConfig get defaultConfig =>
      GradingConfig.fromPreset(UniversityPresets.nagpurUniversity);

  Map<String, dynamic> toJson() => {
    'internalMax': internalMax,
    'endSemMax': endSemMax,
    'passMarkTotal': passMarkTotal,
    'passMarkInternal': passMarkInternal,
    'passMarkEndSem': passMarkEndSem,
    'gradeScales': gradeScales.map((g) => g.toJson()).toList(),
  };

  factory GradingConfig.fromJson(Map<String, dynamic> json) => GradingConfig(
    internalMax: (json['internalMax'] as num).toDouble(),
    endSemMax: (json['endSemMax'] as num).toDouble(),
    passMarkTotal: (json['passMarkTotal'] as num? ?? 40).toDouble(),
    passMarkInternal: (json['passMarkInternal'] as num? ?? 0).toDouble(),
    passMarkEndSem: (json['passMarkEndSem'] as num? ?? 0).toDouble(),
    gradeScales: (json['gradeScales'] as List)
        .map((e) => GradeScale.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  GradingConfig copyWithCustomMax({
    double? internalMax,
    double? endSemMax,
    double? passMarkTotal,
    double? passMarkInternal,
    double? passMarkEndSem,
  }) =>
      GradingConfig(
        internalMax: internalMax ?? this.internalMax,
        endSemMax: endSemMax ?? this.endSemMax,
        passMarkTotal: passMarkTotal ?? this.passMarkTotal,
        passMarkInternal: passMarkInternal ?? this.passMarkInternal,
        passMarkEndSem: passMarkEndSem ?? this.passMarkEndSem,
        gradeScales: gradeScales,
      );
}

class SubjectResult {
  final Subject subject;
  final double totalMarks;    // out of totalMax (not always 100)
  final double totalPct;      // 0–100 percentage
  final String grade;
  final double gradePoints;
  final double weightedPoints;
  final bool isPassing;
  final bool isAtRisk;        // NEW: close to fail but not failed
  final bool hasBacklog;      // NEW: failed in previous sem

  const SubjectResult({
    required this.subject,
    required this.totalMarks,
    required this.totalPct,
    required this.grade,
    required this.gradePoints,
    required this.weightedPoints,
    required this.isPassing,
    required this.isAtRisk,
    required this.hasBacklog,
  });
}

class SubjectPrediction {
  final Subject subject;
  final String targetGrade;
  final double requiredEndSemMarks;
  final bool isAchievable;
  final String insight;
  final double difficultyPct; // 0–1 how hard it is

  const SubjectPrediction({
    required this.subject,
    required this.targetGrade,
    required this.requiredEndSemMarks,
    required this.isAchievable,
    required this.insight,
    required this.difficultyPct,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2 — CALCULATION ENGINE
// ─────────────────────────────────────────────────────────────────────────────

class SGPACalculator {
  final GradingConfig config;
  const SGPACalculator(this.config);

  /// Total marks out of config.totalMax
  double computeTotalMarks(double internal, double endSem) =>
      (internal + endSem).clamp(0.0, config.totalMax);

  /// Percentage 0–100
  double computeTotalPct(double internal, double endSem) =>
      (computeTotalMarks(internal, endSem) / config.totalMax) * 100.0;

  GradeScale resolveGrade(double totalPct) {
    for (final scale in config.gradeScales) {
      if (scale.matches(totalPct)) return scale;
    }
    return config.gradeScales.last;
  }

  bool _checkPass(double internal, double endSem) {
    final total = computeTotalMarks(internal, endSem);
    final pct = (total / config.totalMax) * 100.0;
    if (config.passMarkInternal > 0 && internal < config.passMarkInternal) {
      return false;
    }
    if (config.passMarkEndSem > 0 && endSem < config.passMarkEndSem) {
      return false;
    }
    return pct >= config.passMarkTotal;
  }

  SubjectResult? computeSubjectResult(Subject subject) {
    final internal =
    subject.useExpected ? subject.expectedInternalMarks : subject.internalMarks;
    final endSem =
    subject.useExpected ? subject.expectedEndSemMarks : subject.endSemMarks;
    if (internal == null || endSem == null) return null;

    final total = computeTotalMarks(internal, endSem);
    final pct = computeTotalPct(internal, endSem);
    final scale = resolveGrade(pct);
    final passing = _checkPass(internal, endSem);
    final atRisk = passing && pct < (config.passMarkTotal + 8);

    return SubjectResult(
      subject: subject,
      totalMarks: total,
      totalPct: pct,
      grade: scale.label,
      gradePoints: scale.gradePoints,
      weightedPoints: subject.credits * scale.gradePoints,
      isPassing: passing,
      isAtRisk: atRisk,
      hasBacklog: false,
    );
  }

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
        currentSubjects.fold(0.0, (s, sub) => s + sub.credits)
        ),
    ];
    if (allSemesters.isEmpty) return null;
    final totalWeighted =
    allSemesters.fold(0.0, (sum, sem) => sum + (sem.$1 * sem.$2));
    final totalCredits = allSemesters.fold(0.0, (sum, sem) => sum + sem.$2);
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

  SubjectPrediction predictForTargetGrade(Subject subject, String targetGradeLabel) {
    final targetScale = config.gradeScales.firstWhere(
          (s) => s.label == targetGradeLabel,
      orElse: () => config.gradeScales.last,
    );
    final internal =
        subject.internalMarks ?? subject.expectedInternalMarks ?? 0.0;

    // Total needed (out of totalMax) = (targetMinPct / 100) * totalMax
    final totalNeeded = (targetScale.minMarks / 100.0) * config.totalMax;
    final requiredEndSem = totalNeeded - internal;
    final clamped = requiredEndSem.clamp(0.0, config.endSemMax);
    final isAchievable = requiredEndSem <= config.endSemMax;
    final difficultyPct = (clamped / config.endSemMax).clamp(0.0, 1.0);

    return SubjectPrediction(
      subject: subject,
      targetGrade: targetGradeLabel,
      requiredEndSemMarks: clamped,
      isAchievable: isAchievable,
      difficultyPct: difficultyPct,
      insight: _buildInsight(
        subject.name,
        targetGradeLabel,
        clamped,
        isAchievable,
        internal,
      ),
    );
  }

  String _buildInsight(
      String subjectName,
      String grade,
      double required,
      bool achievable,
      double internal,
      ) {
    if (!achievable) {
      return '❌ $subjectName: $grade not achievable (internal ${internal.toStringAsFixed(1)}/${config.internalMax.toStringAsFixed(0)} too low).';
    }
    final pct = required / config.endSemMax;
    if (pct >= 0.95) {
      return '🔴 $subjectName: Need ${required.toStringAsFixed(1)}/${config.endSemMax.toStringAsFixed(0)} — very tough for $grade.';
    }
    if (pct >= 0.75) {
      return '🟡 $subjectName: Need ${required.toStringAsFixed(1)}/${config.endSemMax.toStringAsFixed(0)} — moderate effort for $grade.';
    }
    return '✅ $subjectName: Need ${required.toStringAsFixed(1)}/${config.endSemMax.toStringAsFixed(0)} — achievable for $grade.';
  }

  double requiredSGPAForTargetCGPA({
    required double currentCGPA,
    required double completedCredits,
    required double targetCGPA,
    required double currentSemesterCredits,
  }) {
    final total = completedCredits + currentSemesterCredits;
    final required =
        (targetCGPA * total - currentCGPA * completedCredits) /
            currentSemesterCredits;
    return required.clamp(0.0, 10.0);
  }

  List<SubjectPrediction> suggestMarksForTargetSGPA({
    required List<Subject> subjects,
    required double targetSGPA,
  }) {
    GradeScale targetScale = config.gradeScales.last;
    for (final scale in config.gradeScales) {
      if (scale.gradePoints >= targetSGPA) {
        targetScale = scale;
        break;
      }
    }
    return subjects.map((s) => predictForTargetGrade(s, targetScale.label)).toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 4 — STATE MANAGEMENT
// ─────────────────────────────────────────────────────────────────────────────

class ResultPredictionProvider extends ChangeNotifier {
  // ── Grading config ────────────────────────────────────────────────────────
  GradingConfig _gradingConfig = GradingConfig.defaultConfig;
  GradingConfig get gradingConfig => _gradingConfig;

  String _selectedPresetId = 'rtmnu';
  String get selectedPresetId => _selectedPresetId;

  // Custom fields (only used when preset == 'custom')
  double _customInternalMax = 40;
  double _customEndSemMax = 60;
  double _customPassMark = 40;
  double get customInternalMax => _customInternalMax;
  double get customEndSemMax => _customEndSemMax;
  double get customPassMark => _customPassMark;

  // ── Subjects ──────────────────────────────────────────────────────────────
  List<Subject> _subjects = [];
  List<Subject> get subjects => List.unmodifiable(_subjects);

  // ── Semester context ─────────────────────────────────────────────────────
  int _currentSemester = 3;
  double _previousCGPA = 0.0;
  double _completedCredits = 0.0;
  int get currentSemester => _currentSemester;
  double get previousCGPA => _previousCGPA;
  double get completedCredits => _completedCredits;

  // ── Targets ───────────────────────────────────────────────────────────────
  String _targetGradeLabel = 'A+';
  double _targetCGPA = 8.5;
  String get targetGradeLabel => _targetGradeLabel;
  double get targetCGPA => _targetCGPA;

  late SGPACalculator _sgpaCalculator;
  late PredictionEngine _predictionEngine;

  ResultPredictionProvider() {
    _rebuild();
    _loadFromPrefs();
    _initDefaultSubjects();
  }

  void _rebuild() {
    _sgpaCalculator = SGPACalculator(_gradingConfig);
    _predictionEngine = PredictionEngine(_gradingConfig);
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

  // ── Preset / config setters ───────────────────────────────────────────────

  void applyPreset(String presetId) {
    _selectedPresetId = presetId;
    if (presetId == 'custom') {
      _gradingConfig = UniversityPresets.custom(
        internalMax: _customInternalMax,
        endSemMax: _customEndSemMax,
        passMarkTotal: _customPassMark,
      ).toGradingConfig();
    } else {
      final preset = UniversityPresets.all.firstWhere(
            (p) => p.id == presetId,
        orElse: () => UniversityPresets.nagpurUniversity,
      );
      _gradingConfig = GradingConfig.fromPreset(preset);
    }
    _rebuild();
    _save();
    notifyListeners();
  }

  void setCustomInternalMax(double val) {
    _customInternalMax = val.clamp(10, 100);
    if (_selectedPresetId == 'custom') applyPreset('custom');
  }

  void setCustomEndSemMax(double val) {
    _customEndSemMax = val.clamp(10, 100);
    if (_selectedPresetId == 'custom') applyPreset('custom');
  }

  void setCustomPassMark(double val) {
    _customPassMark = val.clamp(20, 60);
    if (_selectedPresetId == 'custom') applyPreset('custom');
  }

  // ── Computed getters ──────────────────────────────────────────────────────

  List<SubjectResult?> get subjectResults =>
      _subjects.map(_sgpaCalculator.computeSubjectResult).toList();

  double? get currentSGPA => _sgpaCalculator.calculateSGPA(_subjects);

  double? get predictedCGPA {
    final semCredits = _subjects.fold(0.0, (s, sub) => s + sub.credits);
    final prevSemesters = _completedCredits > 0
        ? [(_previousCGPA, _completedCredits)]
        : <(double, double)>[];
    return _sgpaCalculator.calculateCGPA(prevSemesters, _subjects);
  }

  double get totalCreditLoad =>
      _subjects.fold(0.0, (s, sub) => s + sub.credits);

  double get avgCreditLoad => _subjects.isEmpty ? 0.0 : totalCreditLoad / _subjects.length;

  Subject? get mostImpactfulSubject {
    if (_subjects.isEmpty) return null;
    return _subjects.reduce((a, b) => a.credits > b.credits ? a : b);
  }

  int get subjectsAtRisk =>
      subjectResults.whereType<SubjectResult>().where((r) => r.isAtRisk || !r.isPassing).length;

  int get attendanceShortageCount =>
      _subjects.where((s) => s.hasAttendanceShortage).length;

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

  // ── Subject mutators ──────────────────────────────────────────────────────

  void addSubject() {
    _subjects.add(
        Subject(id: _uid(), name: 'Subject ${_subjects.length + 1}', credits: 3));
    _save();
    notifyListeners();
  }

  void removeSubject(String id) {
    _subjects.removeWhere((s) => s.id == id);
    _save();
    notifyListeners();
  }

  void updateSubjectName(String id, String name) =>
      _mutate(id, (s) => s.copyWith(name: name));
  void updateSubjectCredits(String id, double credits) =>
      _mutate(id, (s) => s.copyWith(credits: credits));
  void updateInternalMarks(String id, double? marks) =>
      _mutate(id, (s) => s.copyWith(internalMarks: marks));
  void updateEndSemMarks(String id, double? marks) =>
      _mutate(id, (s) => s.copyWith(endSemMarks: marks));
  void updateExpectedInternalMarks(String id, double? marks) =>
      _mutate(id, (s) => s.copyWith(expectedInternalMarks: marks));
  void updateExpectedEndSemMarks(String id, double? marks) =>
      _mutate(id, (s) => s.copyWith(expectedEndSemMarks: marks));
  void toggleUseExpected(String id, bool value) =>
      _mutate(id, (s) => s.copyWith(useExpected: value));
  void toggleAttendanceShortage(String id, bool value) =>
      _mutate(id, (s) => s.copyWith(hasAttendanceShortage: value));

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

  void setCurrentSemester(int sem) {
    _currentSemester = sem.clamp(1, 8);
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

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'subjects': _subjects.map((s) => s.toJson()).toList(),
        'previousCGPA': _previousCGPA,
        'completedCredits': _completedCredits,
        'currentSemester': _currentSemester,
        'selectedPresetId': _selectedPresetId,
        'customInternalMax': _customInternalMax,
        'customEndSemMax': _customEndSemMax,
        'customPassMark': _customPassMark,
        'gradingConfig': _gradingConfig.toJson(),
      };
      await prefs.setString('result_prediction_data_v2', jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('result_prediction_data_v2');
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _subjects = (data['subjects'] as List)
          .map((e) => Subject.fromJson(e as Map<String, dynamic>))
          .toList();
      _previousCGPA = (data['previousCGPA'] as num?)?.toDouble() ?? 0.0;
      _completedCredits = (data['completedCredits'] as num?)?.toDouble() ?? 0.0;
      _currentSemester = (data['currentSemester'] as int?) ?? 3;
      _selectedPresetId = (data['selectedPresetId'] as String?) ?? 'rtmnu';
      _customInternalMax = (data['customInternalMax'] as num?)?.toDouble() ?? 40;
      _customEndSemMax = (data['customEndSemMax'] as num?)?.toDouble() ?? 60;
      _customPassMark = (data['customPassMark'] as num?)?.toDouble() ?? 40;

      if (data['gradingConfig'] != null) {
        _gradingConfig = GradingConfig.fromJson(
            data['gradingConfig'] as Map<String, dynamic>);
      }
      _rebuild();
      notifyListeners();
    } catch (_) {}
  }

  void clearAll() {
    _subjects.clear();
    _previousCGPA = 0.0;
    _completedCredits = 0.0;
    _currentSemester = 3;
    _initDefaultSubjects();
    _save();
    notifyListeners();
  }
}

// helper extension
extension _PresetToConfig on UniversityPreset {
  GradingConfig toGradingConfig() => GradingConfig.fromPreset(this);
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 5 — THEME & DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────

class _AppTheme {
  static const Color accent      = Color(0xFFE53935);
  static const Color accentLight = Color(0xFFFF6B6B);
  static const Color accentDark  = Color(0xFFB71C1C);

  static const Color green  = Color(0xFF29D6A4);
  static const Color yellow = Color(0xFFFFBB38);
  static const Color red    = Color(0xFFFF5C7A);
  static const Color blue   = Color(0xFF5DADE2);

  static const Color _darkBg              = Color(0xFF0F0E17);
  static const Color _darkSurface         = Color(0xFF1A1520);
  static const Color _darkSurfaceElevated = Color(0xFF241D2B);
  static const Color _darkTextPrimary     = Color(0xFFF5F0FF);
  static const Color _darkTextSecondary   = Color(0xFF9A8FAA);
  static const Color _darkBorder          = Color(0xFF2E2538);

  static const Color _lightBg              = Color(0xFFFFF5F5);
  static const Color _lightSurface         = Color(0xFFFFFFFF);
  static const Color _lightSurfaceElevated = Color(0xFFFFF0F0);
  static const Color _lightTextPrimary     = Color(0xFF1A0A0A);
  static const Color _lightTextSecondary   = Color(0xFF7A5A5A);
  static const Color _lightBorder          = Color(0xFFFFD6D6);

  static Color bg(bool isDark) => isDark ? _darkBg : _lightBg;
  static Color surface(bool isDark) => isDark ? _darkSurface : _lightSurface;
  static Color surfaceElevated(bool isDark) =>
      isDark ? _darkSurfaceElevated : _lightSurfaceElevated;
  static Color textPrimary(bool isDark) =>
      isDark ? _darkTextPrimary : _lightTextPrimary;
  static Color textSecondary(bool isDark) =>
      isDark ? _darkTextSecondary : _lightTextSecondary;
  static Color border(bool isDark) =>
      isDark ? _darkBorder : _lightBorder;

  static List<Color> bannerGradient(bool isDark) => isDark
      ? [const Color(0xFF2A0A0A), const Color(0xFF1A1520)]
      : [const Color(0xFFFFE5E5), const Color(0xFFFFF0F0)];

  static Color statusColor(double pct) {
    if (pct >= 0.75) return green;
    if (pct >= 0.55) return yellow;
    return red;
  }

  static Color gradeColor(String grade) {
    switch (grade) {
      case 'O':          return green;
      case 'A+':
      case 'A':          return blue;
      case 'B+':
      case 'B':          return yellow;
      case 'P':          return const Color(0xFFAD8CFF);
      default:           return red;
    }
  }

  static ThemeData buildTheme(bool isDark) => ThemeData(
    brightness: isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: bg(isDark),
    colorScheme: isDark
        ? ColorScheme.dark(
      surface: surface(isDark),
      primary: accent,
      secondary: accentLight,
    )
        : ColorScheme.light(
      surface: surface(isDark),
      primary: accent,
      secondary: accentLight,
    ),
    cardTheme: CardThemeData(
      color: surface(isDark),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border(isDark), width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceElevated(isDark),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: border(isDark)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: border(isDark)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
      labelStyle: TextStyle(color: textSecondary(isDark), fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    fontFamily: 'Roboto',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 6 — MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

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
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    return ChangeNotifierProvider(
      create: (_) => ResultPredictionProvider(),
      child: Theme(
        data: _AppTheme.buildTheme(isDark),
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: _AppTheme.bg(isDark),
            appBar: _buildAppBar(context, themeProvider, isDark),
            body: Column(
              children: [
                _SummaryBanner(isDark: isDark),
                _buildTabBar(isDark),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _SubjectsTab(isDark: isDark),
                      _PredictionTab(isDark: isDark),
                      _InsightsTab(isDark: isDark),
                    ],
                  ),
                ),
              ],
            ),
            floatingActionButton: _buildFAB(isDark),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
      BuildContext context,
      ThemeProvider themeProvider,
      bool isDark,
      ) {
    return AppBar(
      backgroundColor: _AppTheme.bg(isDark),
      elevation: 0,
      leading: BackButton(color: _AppTheme.textPrimary(isDark)),
      title: Text(
        'Result Prediction',
        style: TextStyle(
          color: _AppTheme.textPrimary(isDark),
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      actions: [
        // GestureDetector(
        //   onTap: () => themeProvider.toggleTheme(),
        //   child: AnimatedContainer(
        //     duration: const Duration(milliseconds: 300),
        //     width: 52,
        //     height: 28,
        //     margin: const EdgeInsets.only(right: 8),
        //     padding: const EdgeInsets.all(3),
        //     decoration: BoxDecoration(
        //       borderRadius: BorderRadius.circular(20),
        //       gradient: isDark
        //           ? const LinearGradient(
        //         colors: [Color(0xFFE53935), Color(0xFFB71C1C)],
        //       )
        //           : LinearGradient(
        //         colors: [Colors.grey.shade300, Colors.grey.shade200],
        //       ),
        //       boxShadow: [
        //         BoxShadow(
        //           color: isDark
        //               ? const Color(0xFFE53935).withOpacity(0.4)
        //               : Colors.black.withOpacity(0.1),
        //           blurRadius: 8,
        //           offset: const Offset(0, 2),
        //         ),
        //       ],
        //     ),
        //     child: AnimatedAlign(
        //       duration: const Duration(milliseconds: 300),
        //       curve: Curves.easeInOut,
        //       alignment:
        //       isDark ? Alignment.centerRight : Alignment.centerLeft,
        //       child: Container(
        //         width: 22,
        //         height: 22,
        //         decoration: const BoxDecoration(
        //           color: Colors.white,
        //           shape: BoxShape.circle,
        //         ),
        //         child: Center(
        //           child: Icon(
        //             isDark ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded,
        //             color: isDark ? const Color(0xFFE53935) : Colors.amber,
        //             size: 13,
        //           ),
        //         ),
        //       ),
        //     ),
        //   ),
        // ),
        Consumer<ResultPredictionProvider>(
          builder: (context, provider, _) => IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: _AppTheme.textSecondary(isDark)),
            tooltip: 'Reset all data',
            onPressed: () => _confirmReset(context, provider, isDark),
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: _AppTheme.surface(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _AppTheme.border(isDark)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE53935), Color(0xFFFF6B6B)],
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: _AppTheme.textSecondary(isDark),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: 'Subjects'),
          Tab(text: 'Predict'),
          Tab(text: 'Insights'),
        ],
      ),
    );
  }

  Widget _buildFAB(bool isDark) {
    return Consumer<ResultPredictionProvider>(
      builder: (context, provider, _) => FloatingActionButton.extended(
        onPressed: provider.addSubject,
        backgroundColor: Colors.transparent,
        elevation: 0,
        extendedPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        label: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE53935), Color(0xFFFF6B6B)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE53935).withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Add Subject',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmReset(BuildContext context, ResultPredictionProvider provider,
      bool isDark) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _AppTheme.surfaceElevated(isDark),
        title: Text('Reset All Data?',
            style: TextStyle(color: _AppTheme.textPrimary(isDark))),
        content: Text(
          'This will clear all subjects and marks. Cannot be undone.',
          style: TextStyle(color: _AppTheme.textSecondary(isDark)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: _AppTheme.textSecondary(isDark))),
          ),
          TextButton(
            onPressed: () {
              provider.clearAll();
              Navigator.pop(context);
            },
            child: const Text('Reset',
                style: TextStyle(color: Color(0xFFE53935))),
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
  final bool isDark;
  const _SummaryBanner({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Consumer<ResultPredictionProvider>(
      builder: (context, provider, _) {
        final sgpa = provider.currentSGPA;
        final cgpa = provider.predictedCGPA;
        final creditLoad = provider.totalCreditLoad;
        final atRisk = provider.subjectsAtRisk;
        final attnShortage = provider.attendanceShortageCount;
        final config = provider.gradingConfig;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _AppTheme.bannerGradient(isDark),
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _AppTheme.accent.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _StatPill(
                    label: 'SGPA',
                    value: sgpa != null ? sgpa.toStringAsFixed(2) : '--',
                    color: sgpa != null
                        ? _sgpaColor(sgpa)
                        : _AppTheme.textSecondary(isDark),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 12),
                  Container(
                      width: 1,
                      height: 40,
                      color: _AppTheme.border(isDark)),
                  const SizedBox(width: 12),
                  _StatPill(
                    label: 'Pred. CGPA',
                    value: cgpa != null ? cgpa.toStringAsFixed(2) : '--',
                    color: cgpa != null
                        ? _sgpaColor(cgpa)
                        : _AppTheme.textSecondary(isDark),
                    isDark: isDark,
                  ),
                  const Spacer(),
                  // Scheme badge
                  _SchemeBadge(config: config, isDark: isDark),
                ],
              ),
              const SizedBox(height: 10),
              // Credit load bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Credit Load: ',
                          style: TextStyle(
                              color: _AppTheme.textSecondary(isDark),
                              fontSize: 11)),
                      Text('${creditLoad.toStringAsFixed(0)} credits',
                          style: TextStyle(
                              color: _AppTheme.textPrimary(isDark),
                              fontWeight: FontWeight.w600,
                              fontSize: 11)),
                      const Spacer(),
                      if (atRisk > 0)
                        _StatusChip(
                            label: '⚠ $atRisk at risk',
                            color: _AppTheme.yellow),
                      if (attnShortage > 0) ...[
                        const SizedBox(width: 6),
                        _StatusChip(
                            label: '📵 $attnShortage attendance',
                            color: _AppTheme.red),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (creditLoad / 30.0).clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: _AppTheme.border(isDark),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        creditLoad > 24
                            ? _AppTheme.red
                            : creditLoad > 18
                            ? _AppTheme.yellow
                            : _AppTheme.green,
                      ),
                    ),
                  ),
                ],
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

class _SchemeBadge extends StatelessWidget {
  final GradingConfig config;
  final bool isDark;
  const _SchemeBadge({required this.config, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _AppTheme.accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _AppTheme.accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '${config.internalMax.toStringAsFixed(0)}+${config.endSemMax.toStringAsFixed(0)}',
            style: const TextStyle(
                color: _AppTheme.accentLight,
                fontSize: 12,
                fontWeight: FontWeight.w800),
          ),
          Text('scheme',
              style: TextStyle(
                  color: _AppTheme.textSecondary(isDark), fontSize: 9)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: _AppTheme.textSecondary(isDark), fontSize: 11)),
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

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 8 — SUBJECTS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _SubjectsTab extends StatelessWidget {
  final bool isDark;
  const _SubjectsTab({required this.isDark});

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
              isDark: isDark,
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
  final bool isDark;

  const _SubjectCard({
    required this.subject,
    required this.result,
    required this.isMostImpactful,
    required this.config,
    required this.provider,
    required this.isDark,
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
    _internalCtrl = TextEditingController(
        text: s.internalMarks?.toStringAsFixed(1) ?? '');
    _endSemCtrl = TextEditingController(
        text: s.endSemMarks?.toStringAsFixed(1) ?? '');
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
    final isDark = widget.isDark;
    final config = widget.config;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _AppTheme.surface(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: s.hasAttendanceShortage
              ? _AppTheme.red.withOpacity(0.5)
              : isMost
              ? _AppTheme.accent.withOpacity(0.5)
              : _AppTheme.border(isDark),
          width: (isMost || s.hasAttendanceShortage) ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius:
            const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  if (isMost)
                    _MiniChip(
                        label: '⭐ Top',
                        bg: _AppTheme.accent.withOpacity(0.15),
                        text: _AppTheme.accentLight),
                  if (s.hasAttendanceShortage) ...[
                    if (isMost) const SizedBox(width: 4),
                    _MiniChip(
                        label: '📵 Attn',
                        bg: _AppTheme.red.withOpacity(0.12),
                        text: _AppTheme.red),
                  ],
                  if (isMost || s.hasAttendanceShortage)
                    const SizedBox(width: 6),
                  Expanded(
                    child: Text(s.name,
                        style: TextStyle(
                            color: _AppTheme.textPrimary(isDark),
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ),
                  if (r != null) ...[
                    // Risk badge
                    if (!r.isPassing)
                      _MiniChip(
                          label: 'FAIL',
                          bg: _AppTheme.red.withOpacity(0.15),
                          text: _AppTheme.red),
                    if (r.isAtRisk && r.isPassing)
                      _MiniChip(
                          label: 'AT RISK',
                          bg: _AppTheme.yellow.withOpacity(0.15),
                          text: _AppTheme.yellow),
                    const SizedBox(width: 6),
                    _GradeBadge(grade: r.grade),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${r.totalMarks.toStringAsFixed(1)}/${config.totalMax.toStringAsFixed(0)}',
                          style: TextStyle(
                              color: _AppTheme.statusColor(r.totalPct / 100),
                              fontWeight: FontWeight.w700,
                              fontSize: 13),
                        ),
                        Text(
                          '${r.totalPct.toStringAsFixed(1)}%',
                          style: TextStyle(
                              color: _AppTheme.textSecondary(isDark),
                              fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: _AppTheme.textSecondary(isDark),
                    size: 20,
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        color: _AppTheme.textSecondary(isDark), size: 18),
                    onPressed: () => p.removeSubject(s.id),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(left: 4),
                  ),
                ],
              ),
            ),
          ),

          if (_expanded) ...[
            Divider(color: _AppTheme.border(isDark), height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _MarkInput(
                          label: 'Subject Name',
                          controller: _nameCtrl,
                          isText: true,
                          isDark: isDark,
                          onChanged: (v) => p.updateSubjectName(s.id, v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MarkInput(
                          label: 'Credits',
                          controller: _creditsCtrl,
                          maxVal: 6,
                          isDark: isDark,
                          onChanged: (v) {
                            final d = double.tryParse(v);
                            if (d != null) p.updateSubjectCredits(s.id, d);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Attendance toggle row
                  _ToggleRow(
                    label: '📵 Attendance shortage (<75%)',
                    sublabel: 'Flags this subject for attendance risk',
                    value: s.hasAttendanceShortage,
                    activeColor: _AppTheme.red,
                    isDark: isDark,
                    onChanged: (v) => p.toggleAttendanceShortage(s.id, v),
                  ),
                  const SizedBox(height: 8),
                  _ToggleRow(
                    label: '🔮 Use Expected Marks (What-If)',
                    sublabel: 'Simulate future marks',
                    value: s.useExpected,
                    activeColor: _AppTheme.accent,
                    isDark: isDark,
                    onChanged: (v) => p.toggleUseExpected(s.id, v),
                  ),
                  const SizedBox(height: 12),
                  // Pass mark info banner
                  _PassMarkBanner(config: config, isDark: isDark),
                  const SizedBox(height: 12),
                  _SectionLabel(
                      '📝 Actual Marks',
                      active: !s.useExpected,
                      isDark: isDark),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _MarkInput(
                          label: 'Internal (/${config.internalMax.toStringAsFixed(0)})',
                          controller: _internalCtrl,
                          maxVal: config.internalMax,
                          enabled: !s.useExpected,
                          isDark: isDark,
                          onChanged: (v) =>
                              p.updateInternalMarks(s.id, double.tryParse(v)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MarkInput(
                          label: 'End-Sem (/${config.endSemMax.toStringAsFixed(0)})',
                          controller: _endSemCtrl,
                          maxVal: config.endSemMax,
                          enabled: !s.useExpected,
                          isDark: isDark,
                          onChanged: (v) =>
                              p.updateEndSemMarks(s.id, double.tryParse(v)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SectionLabel(
                      '🔮 Expected Marks (Simulation)',
                      active: s.useExpected,
                      isDark: isDark),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _MarkInput(
                          label: 'Exp. Internal (/${config.internalMax.toStringAsFixed(0)})',
                          controller: _expInternalCtrl,
                          maxVal: config.internalMax,
                          enabled: s.useExpected,
                          isDark: isDark,
                          onChanged: (v) =>
                              p.updateExpectedInternalMarks(s.id, double.tryParse(v)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MarkInput(
                          label: 'Exp. End-Sem (/${config.endSemMax.toStringAsFixed(0)})',
                          controller: _expEndSemCtrl,
                          maxVal: config.endSemMax,
                          enabled: s.useExpected,
                          isDark: isDark,
                          onChanged: (v) =>
                              p.updateExpectedEndSemMarks(s.id, double.tryParse(v)),
                        ),
                      ),
                    ],
                  ),
                  if (s.useExpected) ...[
                    const SizedBox(height: 12),
                    _EndSemSlider(
                      subject: s,
                      config: config,
                      provider: p,
                      endSemController: _expEndSemCtrl,
                      isDark: isDark,
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
  final bool isDark;
  const _PredictionTab({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Consumer<ResultPredictionProvider>(
      builder: (context, provider, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            // ── NEW: University / Marking Scheme Selector ────────────────
            _UniversitySchemeCard(provider: provider, isDark: isDark),
            const SizedBox(height: 16),
            _PreviousSemesterCard(provider: provider, isDark: isDark),
            const SizedBox(height: 16),
            _TargetGradeCard(provider: provider, isDark: isDark),
            const SizedBox(height: 16),
            _TargetCGPACard(provider: provider, isDark: isDark),
          ],
        );
      },
    );
  }
}

// ── NEW: University Scheme Card ────────────────────────────────────────────

class _UniversitySchemeCard extends StatefulWidget {
  final ResultPredictionProvider provider;
  final bool isDark;
  const _UniversitySchemeCard(
      {required this.provider, required this.isDark});

  @override
  State<_UniversitySchemeCard> createState() => _UniversitySchemeCardState();
}

class _UniversitySchemeCardState extends State<_UniversitySchemeCard> {
  late TextEditingController _internalCtrl;
  late TextEditingController _endSemCtrl;
  late TextEditingController _passMarkCtrl;

  @override
  void initState() {
    super.initState();
    final p = widget.provider;
    _internalCtrl =
        TextEditingController(text: p.customInternalMax.toStringAsFixed(0));
    _endSemCtrl =
        TextEditingController(text: p.customEndSemMax.toStringAsFixed(0));
    _passMarkCtrl =
        TextEditingController(text: p.customPassMark.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _internalCtrl.dispose();
    _endSemCtrl.dispose();
    _passMarkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    final isDark = widget.isDark;
    final config = p.gradingConfig;
    final isCustom = p.selectedPresetId == 'custom';

    return _SectionCard(
      title: '🏫 University Marking Scheme',
      subtitle: 'Select your college system or enter custom marks',
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Preset chips — scrollable row
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: UniversityPresets.all.map((preset) {
                final selected = p.selectedPresetId == preset.id;
                return GestureDetector(
                  onTap: () => p.applyPreset(preset.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 0),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: selected
                          ? const LinearGradient(
                        colors: [Color(0xFFE53935), Color(0xFFFF6B6B)],
                      )
                          : null,
                      color: selected
                          ? null
                          : _AppTheme.surfaceElevated(isDark),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? Colors.transparent
                            : _AppTheme.border(isDark),
                      ),
                      boxShadow: selected
                          ? [
                        BoxShadow(
                          color: const Color(0xFFE53935)
                              .withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ]
                          : null,
                    ),
                    child: Text(
                      preset.shortName,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : _AppTheme.textSecondary(isDark),
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 14),

          // Active scheme info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _AppTheme.surfaceElevated(isDark),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _AppTheme.accent.withOpacity(0.25)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _SchemeInfoItem(
                      label: 'Internal Max',
                      value: config.internalMax.toStringAsFixed(0),
                      color: _AppTheme.blue,
                    ),
                    _SchemeDivider(),
                    _SchemeInfoItem(
                      label: 'End-Sem Max',
                      value: config.endSemMax.toStringAsFixed(0),
                      color: _AppTheme.accentLight,
                    ),
                    _SchemeDivider(),
                    _SchemeInfoItem(
                      label: 'Total',
                      value: config.totalMax.toStringAsFixed(0),
                      color: _AppTheme.green,
                    ),
                    _SchemeDivider(),
                    _SchemeInfoItem(
                      label: 'Pass Mark',
                      value: '${config.passMarkTotal.toStringAsFixed(0)}%',
                      color: _AppTheme.yellow,
                    ),
                  ],
                ),
                if (config.passMarkInternal > 0 ||
                    config.passMarkEndSem > 0) ...[
                  Divider(
                      color: _AppTheme.border(isDark), height: 14),
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 13,
                          color: _AppTheme.textSecondary(isDark)),
                      const SizedBox(width: 6),
                      Text(
                        'Separate pass conditions: '
                            'Internal ≥ ${config.passMarkInternal.toStringAsFixed(0)}, '
                            'End-Sem ≥ ${config.passMarkEndSem.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: _AppTheme.textSecondary(isDark),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Custom fields (visible only when 'custom' is selected)
          if (isCustom) ...[
            const SizedBox(height: 14),
            _SectionLabel('⚙️ Custom Configuration',
                active: true, isDark: isDark),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MarkInput(
                    label: 'Internal Max',
                    controller: _internalCtrl,
                    maxVal: 100,
                    isDark: isDark,
                    onChanged: (v) {
                      final d = double.tryParse(v);
                      if (d != null) p.setCustomInternalMax(d);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MarkInput(
                    label: 'End-Sem Max',
                    controller: _endSemCtrl,
                    maxVal: 100,
                    isDark: isDark,
                    onChanged: (v) {
                      final d = double.tryParse(v);
                      if (d != null) p.setCustomEndSemMax(d);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MarkInput(
                    label: 'Pass % (e.g. 40)',
                    controller: _passMarkCtrl,
                    maxVal: 60,
                    isDark: isDark,
                    onChanged: (v) {
                      final d = double.tryParse(v);
                      if (d != null) p.setCustomPassMark(d);
                    },
                  ),
                ),
              ],
            ),
          ],

          // Grade scale preview
          const SizedBox(height: 14),
          _GradeScalePreview(
              scales: config.gradeScales, isDark: isDark),
        ],
      ),
    );
  }
}

class _SchemeInfoItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SchemeInfoItem(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF9A8FAA), fontSize: 10)),
        ],
      ),
    );
  }
}

class _SchemeDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
        width: 1, height: 30, color: const Color(0xFF2E2538));
  }
}

class _GradeScalePreview extends StatelessWidget {
  final List<GradeScale> scales;
  final bool isDark;
  const _GradeScalePreview(
      {required this.scales, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Grade Scale',
            style: TextStyle(
                color: _AppTheme.textSecondary(isDark),
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: scales.map((g) {
            final color = _AppTheme.gradeColor(g.label);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withOpacity(0.35)),
              ),
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: g.label,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 12),
                    ),
                    TextSpan(
                      text: ' ${g.minMarks.toStringAsFixed(0)}'
                          '–${g.maxMarks.toStringAsFixed(0)}%'
                          ' · ${g.gradePoints.toStringAsFixed(0)}pts',
                      style: TextStyle(
                          color: _AppTheme.textSecondary(isDark),
                          fontSize: 10),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _PreviousSemesterCard extends StatefulWidget {
  final ResultPredictionProvider provider;
  final bool isDark;
  const _PreviousSemesterCard(
      {required this.provider, required this.isDark});

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
    final isDark = widget.isDark;

    return _SectionCard(
      title: '📊 Previous Semester Data',
      subtitle: 'Required for CGPA calculation',
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Semester selector chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...List.generate(8, (index) {
                  final sem = index + 1;
                  final selected = p.currentSemester == sem;

                  return GestureDetector(
                    onTap: () => p.setCurrentSemester(sem),

                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),

                      width: 28,
                      height: 28,

                      margin: const EdgeInsets.only(right: 4),

                      alignment: Alignment.center,

                      decoration: BoxDecoration(
                        gradient: selected
                            ? const LinearGradient(
                          colors: [
                            Color(0xFFE53935),
                            Color(0xFFFF6B6B),
                          ],
                        )
                            : null,

                        color: selected
                            ? null
                            : _AppTheme.surfaceElevated(isDark),

                        borderRadius: BorderRadius.circular(6),

                        border: Border.all(
                          color: selected
                              ? Colors.transparent
                              : _AppTheme.border(isDark),
                        ),
                      ),

                      child: Text(
                        '$sem',
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : _AppTheme.textSecondary(isDark),

                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.normal,

                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MarkInput(
                  label: 'CGPA so far (0–10)',
                  controller: _cgpaCtrl,
                  maxVal: 10,
                  isDark: isDark,
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
                  isDark: isDark,
                  onChanged: (v) {
                    final d = double.tryParse(v);
                    if (d != null) p.setCompletedCredits(d);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TargetGradeCard extends StatelessWidget {
  final ResultPredictionProvider provider;
  final bool isDark;
  const _TargetGradeCard({required this.provider, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final grades = provider.gradingConfig.gradeScales
        .where((s) => s.gradePoints > 0)
        .toList();
    final predictions = provider.targetGradePredictions;

    return _SectionCard(
      title: '🎯 Target Grade Prediction',
      subtitle: 'Required end-sem marks per subject',
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    gradient: selected
                        ? const LinearGradient(
                      colors: [Color(0xFFE53935), Color(0xFFFF6B6B)],
                    )
                        : null,
                    color: selected
                        ? null
                        : _AppTheme.surfaceElevated(isDark),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? Colors.transparent
                          : _AppTheme.border(isDark),
                    ),
                    boxShadow: selected
                        ? [
                      BoxShadow(
                        color:
                        const Color(0xFFE53935).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ]
                        : null,
                  ),
                  child: Text(
                    '${g.label} (${g.gradePoints.toStringAsFixed(0)})',
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : _AppTheme.textSecondary(isDark),
                      fontWeight:
                      selected ? FontWeight.w700 : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          ...predictions.map((pred) => _PredictionRow(
              prediction: pred,
              config: provider.gradingConfig,
              isDark: isDark)),
        ],
      ),
    );
  }
}

class _TargetCGPACard extends StatefulWidget {
  final ResultPredictionProvider provider;
  final bool isDark;
  const _TargetCGPACard({required this.provider, required this.isDark});

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
    final isDark = widget.isDark;
    final reqSGPA = p.requiredSGPAForTarget;
    final cgpaPreds = p.cgpaTargetPredictions;

    return _SectionCard(
      title: '🚀 Target CGPA Calculator',
      subtitle: 'Find required SGPA and marks',
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Target CGPA: ',
                  style: TextStyle(
                      color: _AppTheme.textSecondary(isDark),
                      fontSize: 13)),
              Text(_sliderVal.toStringAsFixed(1),
                  style: const TextStyle(
                      color: _AppTheme.accentLight,
                      fontWeight: FontWeight.w800,
                      fontSize: 18)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: _AppTheme.accent,
              inactiveTrackColor: _AppTheme.border(isDark),
              thumbColor: _AppTheme.accent,
              overlayColor: _AppTheme.accent.withOpacity(0.2),
            ),
            child: Slider(
              value: _sliderVal,
              min: 5.0,
              max: 10.0,
              divisions: 50,
              onChanged: (v) {
                setState(() => _sliderVal = v);
                p.setTargetCGPA(v);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _AppTheme.surfaceElevated(isDark),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: reqSGPA > 10
                    ? _AppTheme.red.withOpacity(0.4)
                    : _AppTheme.green.withOpacity(0.3),
              ),
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
                          style: TextStyle(
                              color: _AppTheme.textSecondary(isDark),
                              fontSize: 11)),
                      Text(
                        reqSGPA > 10
                            ? 'Not achievable (need ${reqSGPA.toStringAsFixed(2)} > 10)'
                            : reqSGPA.toStringAsFixed(2),
                        style: TextStyle(
                          color:
                          reqSGPA > 10 ? _AppTheme.red : _AppTheme.green,
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
            Text('Suggested Marks to Achieve Target',
                style: TextStyle(
                    color: _AppTheme.textSecondary(isDark), fontSize: 12)),
            const SizedBox(height: 8),
            ...cgpaPreds.map((pred) => _PredictionRow(
                prediction: pred,
                config: p.gradingConfig,
                isDark: isDark)),
          ],
        ],
      ),
    );
  }
}

class _PredictionRow extends StatelessWidget {
  final SubjectPrediction prediction;
  final GradingConfig config;
  final bool isDark;
  const _PredictionRow(
      {required this.prediction,
        required this.config,
        required this.isDark});

  @override
  Widget build(BuildContext context) {
    final p = prediction;
    final color = p.isAchievable
        ? _AppTheme.statusColor(p.difficultyPct)
        : _AppTheme.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _AppTheme.surfaceElevated(isDark),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: p.isAchievable
              ? _AppTheme.border(isDark)
              : _AppTheme.red.withOpacity(0.4),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.subject.name,
                    style: TextStyle(
                        color: _AppTheme.textPrimary(isDark),
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Text(p.insight,
                    style: TextStyle(
                        color: _AppTheme.textSecondary(isDark),
                        fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Text(
                p.isAchievable
                    ? p.requiredEndSemMarks.toStringAsFixed(1)
                    : 'N/A',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 18),
              ),
              Text('/${config.endSemMax.toStringAsFixed(0)}',
                  style: TextStyle(
                      color: _AppTheme.textSecondary(isDark),
                      fontSize: 10)),
            ],
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              value: p.isAchievable
                  ? p.difficultyPct.clamp(0.0, 1.0)
                  : 1.0,
              backgroundColor: _AppTheme.border(isDark),
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
  final bool isDark;
  const _InsightsTab({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Consumer<ResultPredictionProvider>(
      builder: (context, provider, _) {
        final insights = _generateInsights(provider);
        final results =
        provider.subjectResults.whereType<SubjectResult>().toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            if (results.isNotEmpty) ...[
              _GradeDistributionCard(results: results, isDark: isDark),
              const SizedBox(height: 16),
              _CreditWeightChart(
                  subjects: provider.subjects,
                  results: results,
                  isDark: isDark),
              const SizedBox(height: 16),
            ],
            _SectionCard(
              title: '💡 Smart Suggestions',
              subtitle: 'Personalised insights based on your marks',
              isDark: isDark,
              child: Column(
                children: insights.isEmpty
                    ? [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Enter marks to see personalised insights.',
                      style: TextStyle(
                          color: _AppTheme.textSecondary(isDark)),
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

    // SGPA insight
    if (sgpa != null) {
      if (sgpa >= 9.0) {
        insights.add(_Insight(
            icon: '🏆',
            text:
            'Outstanding! SGPA ${sgpa.toStringAsFixed(2)} puts you in top tier.',
            color: _AppTheme.green));
      } else if (sgpa >= 7.5) {
        insights.add(_Insight(
            icon: '👍',
            text:
            'Good SGPA ${sgpa.toStringAsFixed(2)}. Push for ${(sgpa + 0.5).toStringAsFixed(1)} next semester.',
            color: _AppTheme.yellow));
      } else {
        insights.add(_Insight(
            icon: '⚠️',
            text:
            'SGPA ${sgpa.toStringAsFixed(2)} is below 7.5. Focus to avoid backlog risk.',
            color: _AppTheme.red));
      }
    }

    // Failing subjects
    for (final r in results.where((r) => !r.isPassing)) {
      insights.add(_Insight(
          icon: '🔴',
          text:
          '${r.subject.name}: ${r.totalMarks.toStringAsFixed(1)}/${config.totalMax.toStringAsFixed(0)} — below pass mark (${config.passMarkTotal.toStringAsFixed(0)}%). Backlog risk!',
          color: _AppTheme.red));
    }

    // Attendance warnings
    for (final s in provider.subjects.where((s) => s.hasAttendanceShortage)) {
      insights.add(_Insight(
          icon: '📵',
          text:
          '${s.name}: Attendance shortage detected. You may be barred from the exam!',
          color: _AppTheme.red));
    }

    // At-risk subjects
    for (final r in results.where((r) => r.isAtRisk && r.isPassing)) {
      insights.add(_Insight(
          icon: '🟠',
          text:
          '${r.subject.name}: Only ${r.totalPct.toStringAsFixed(1)}% — just above pass mark. Do not relax!',
          color: _AppTheme.yellow));
    }

    // Best subject
    if (results.length > 1) {
      final best = results
          .reduce((a, b) => a.totalPct > b.totalPct ? a : b);
      insights.add(_Insight(
          icon: '⭐',
          text:
          '${best.subject.name} is your strongest at ${best.totalPct.toStringAsFixed(1)}% (${best.grade} grade).',
          color: _AppTheme.green));
    }

    // High-credit subjects below A
    for (final s in provider.subjects.where((s) => s.credits >= 4)) {
      final r = results.firstWhere((r) => r.subject.id == s.id,
          orElse: () => results.first);
      if (r.subject.id == s.id && r.gradePoints < 8) {
        insights.add(_Insight(
            icon: '📌',
            text:
            'Focus on ${s.name} (${s.credits}-credit) — improving this maximises your SGPA.',
            color: _AppTheme.yellow));
      }
    }

    // Close to next grade
    for (final r in results) {
      final currentBand = config.gradeScales
          .firstWhere((g) => g.label == r.grade,
          orElse: () => config.gradeScales.last);
      final nextBandIdx = config.gradeScales.indexOf(currentBand) - 1;
      if (nextBandIdx >= 0) {
        final nextBand = config.gradeScales[nextBandIdx];
        final gap = nextBand.minMarks - r.totalPct;
        if (gap > 0 && gap <= 5) {
          insights.add(_Insight(
              icon: '📈',
              text:
              '${r.subject.name} is ${gap.toStringAsFixed(1)}% away from ${nextBand.label} grade!',
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
  const _Insight(
      {required this.icon, required this.text, required this.color});
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
  final bool isDark;
  const _GradeDistributionCard(
      {required this.results, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final Map<String, int> dist = {};
    for (final r in results) {
      dist[r.grade] = (dist[r.grade] ?? 0) + 1;
    }

    return _SectionCard(
      title: '📊 Grade Distribution',
      subtitle: 'Current semester overview',
      isDark: isDark,
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
                  color:
                  _AppTheme.gradeColor(e.key).withOpacity(0.15),
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
                  style: TextStyle(
                      color: _AppTheme.textSecondary(isDark),
                      fontSize: 10)),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// NEW: Credit-weighted performance chart
class _CreditWeightChart extends StatelessWidget {
  final List<Subject> subjects;
  final List<SubjectResult> results;
  final bool isDark;
  const _CreditWeightChart(
      {required this.subjects,
        required this.results,
        required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '⚖️ Credit-Weighted Performance',
      subtitle: 'Bigger bar = heavier subject',
      isDark: isDark,
      child: Column(
        children: results.map((r) {
          final pct = r.totalPct / 100.0;
          final creditPct = r.subject.credits / 6.0; // max 6 credits
          final color = _AppTheme.statusColor(pct);

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    r.subject.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: _AppTheme.textSecondary(isDark),
                        fontSize: 10),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct.clamp(0.0, 1.0),
                          minHeight: (creditPct * 12 + 4)
                              .clamp(4, 14)
                              .toDouble(),
                          backgroundColor: _AppTheme.border(isDark),
                          valueColor:
                          AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${r.totalPct.toStringAsFixed(1)}% ${r.grade}',
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
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
  final bool isDark;

  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.child,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _AppTheme.surface(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _AppTheme.border(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE53935), Color(0xFFFF6B6B)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(title,
                  style: TextStyle(
                      color: _AppTheme.textPrimary(isDark),
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 11),
              child: Text(subtitle!,
                  style: TextStyle(
                      color: _AppTheme.textSecondary(isDark),
                      fontSize: 12)),
            ),
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
  final bool isDark;
  final ValueChanged<String> onChanged;

  const _MarkInput({
    required this.label,
    required this.controller,
    this.maxVal = 100,
    this.isText = false,
    this.enabled = true,
    required this.isDark,
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
          : [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
      style: TextStyle(
          color: _AppTheme.textPrimary(isDark),
          fontSize: 13,
          fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: _AppTheme.border(isDark).withOpacity(0.4)),
        ),
      ),
      onChanged: onChanged,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool active;
  final bool isDark;
  const _SectionLabel(this.text,
      {required this.active, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: active
            ? _AppTheme.accentLight
            : _AppTheme.textSecondary(isDark),
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

class _MiniChip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color text;
  const _MiniChip(
      {required this.label, required this.bg, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              color: text, fontSize: 9, fontWeight: FontWeight.w700)),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool value;
  final Color activeColor;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.sublabel,
    required this.value,
    required this.activeColor,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: value
            ? activeColor.withOpacity(0.07)
            : _AppTheme.surfaceElevated(isDark),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: value
              ? activeColor.withOpacity(0.3)
              : _AppTheme.border(isDark),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: value
                            ? activeColor
                            : _AppTheme.textSecondary(isDark),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                Text(sublabel,
                    style: TextStyle(
                        color: _AppTheme.textSecondary(isDark),
                        fontSize: 10)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: activeColor,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

/// Shows pass-mark context for current scheme
class _PassMarkBanner extends StatelessWidget {
  final GradingConfig config;
  final bool isDark;
  const _PassMarkBanner({required this.config, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _AppTheme.yellow.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _AppTheme.yellow.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Text('📋', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Scheme: ${config.internalMax.toStringAsFixed(0)} Internal + '
                  '${config.endSemMax.toStringAsFixed(0)} End-Sem = '
                  '${config.totalMax.toStringAsFixed(0)} total. '
                  'Pass: ${config.passMarkTotal.toStringAsFixed(0)}%'
                  '${config.passMarkEndSem > 0 ? ' (End-Sem ≥${config.passMarkEndSem.toStringAsFixed(0)})' : ''}.',
              style: TextStyle(
                  color: _AppTheme.yellow.withOpacity(0.9), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _EndSemSlider extends StatefulWidget {
  final Subject subject;
  final GradingConfig config;
  final ResultPredictionProvider provider;
  final TextEditingController endSemController;
  final bool isDark;

  const _EndSemSlider({
    required this.subject,
    required this.config,
    required this.provider,
    required this.endSemController,
    required this.isDark,
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
    final isDark = widget.isDark;
    final config = widget.config;
    // Pass mark line position 0–1
    final passLinePct =
    (config.passMarkEndSem / config.endSemMax).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('🎚 Quick End-Sem Adjuster',
                style: TextStyle(
                    color: _AppTheme.textSecondary(isDark), fontSize: 11)),
            const Spacer(),
            Text(
              '${_val.toStringAsFixed(1)} / ${config.endSemMax.toStringAsFixed(0)}',
              style: const TextStyle(
                  color: _AppTheme.accentLight,
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
          ],
        ),
        if (config.passMarkEndSem > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              'Pass threshold: ≥${config.passMarkEndSem.toStringAsFixed(0)}',
              style: TextStyle(
                  color: _val < config.passMarkEndSem
                      ? _AppTheme.red
                      : _AppTheme.green,
                  fontSize: 10),
            ),
          ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: _AppTheme.accent,
            inactiveTrackColor: _AppTheme.border(isDark),
            thumbColor: _AppTheme.accent,
            overlayColor: _AppTheme.accent.withOpacity(0.2),
          ),
          child: Slider(
            value: _val,
            min: 0,
            max: config.endSemMax,
            divisions: (config.endSemMax * 2).toInt(),
            onChanged: (v) {
              setState(() => _val = v);
              widget.endSemController.text = v.toStringAsFixed(1);
              widget.provider
                  .updateExpectedEndSemMarks(widget.subject.id, v);
            },
          ),
        ),
      ],
    );
  }
}
