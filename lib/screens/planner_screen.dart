import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

// ══════════════════════════════════════════════════════════════════════════════
//  NOTIFICATION SERVICE
// ══════════════════════════════════════════════════════════════════════════════

final FlutterLocalNotificationsPlugin _notifPlugin =
FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  tzdata.initializeTimeZones();

  const androidSettings =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'planner_channel',
    'Study Planner',
    description: 'Study task reminders',
    importance: Importance.max,
  );

  const initSettings =
  InitializationSettings(android: androidSettings, iOS: iosSettings);

  await _notifPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (details) {},
  );

  await _notifPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  await _notifPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

Future<void> scheduleTaskNotification(Task task, DateTime taskDate) async {
  if (!task.reminderOn) return;

  final scheduledDate = tz.TZDateTime(
    tz.local,
    taskDate.year,
    taskDate.month,
    taskDate.day,
    task.hour,
    task.minute,
  );

  if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) return;

  const androidDetails = AndroidNotificationDetails(
    'planner_channel',
    'Study Planner',
    channelDescription: 'Study task reminders',
    importance: Importance.max,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
    color: Color(0xFF00897B),
    enableVibration: true,
    playSound: true,
  );
  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );
  const details =
  NotificationDetails(android: androidDetails, iOS: iosDetails);

  final notifId = task.id.hashCode.abs() % 100000;

  await _notifPlugin.zonedSchedule(
    notifId,
    '📚 ${task.subject}',
    task.note.isNotEmpty ? task.note : 'Time to study!',
    scheduledDate,
    details,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
    UILocalNotificationDateInterpretation.absoluteTime,
  );
}

Future<void> cancelTaskNotification(String taskId) async {
  final notifId = taskId.hashCode.abs() % 100000;
  await _notifPlugin.cancel(notifId);
}

// ══════════════════════════════════════════════════════════════════════════════
//  CONSTANTS
// ══════════════════════════════════════════════════════════════════════════════

const kTeal = Color(0xFF00897B);
const kTealLight = Color(0xFFE0F2F1);
const kTealDark = Color(0xFF00695C);
const kAccentOrange = Color(0xFFFF7043);
const kAccentPurple = Color(0xFF7C4DFF);
const kCardWhite = Color(0xFFFFFFFF);
const kTextDark = Color(0xFF1A2332);
const kTextMuted = Color(0xFF8A9BB0);
const kBgGrey = Color(0xFFF0F4F8);

const List<String> kSubjectColors = [
  '#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4',
  '#FFEAA7', '#DDA0DD', '#98D8C8', '#F7DC6F',
  '#BB8FCE', '#85C1E9',
];

// ══════════════════════════════════════════════════════════════════════════════
//  TASK MODEL
// ══════════════════════════════════════════════════════════════════════════════

class Task {
  final String id;
  String subject;
  String note;
  int hour;
  int minute;
  bool isDone;
  bool reminderOn;
  String colorHex;
  String priority;
  String dateKey;

  Task({
    required this.id,
    required this.subject,
    required this.note,
    required this.hour,
    required this.minute,
    this.isDone = false,
    this.reminderOn = false,
    required this.colorHex,
    this.priority = 'medium',
    required this.dateKey,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'subject': subject,
    'note': note,
    'hour': hour,
    'minute': minute,
    'isDone': isDone,
    'reminderOn': reminderOn,
    'colorHex': colorHex,
    'priority': priority,
    'dateKey': dateKey,
  };

  factory Task.fromMap(Map<String, dynamic> m) => Task(
    id: m['id'] ?? UniqueKey().toString(),
    subject: m['subject'] ?? '',
    note: m['note'] ?? '',
    hour: m['hour'] ?? 8,
    minute: m['minute'] ?? 0,
    isDone: m['isDone'] ?? false,
    reminderOn: m['reminderOn'] ?? false,
    colorHex: m['colorHex'] ?? '#4ECDC4',
    priority: m['priority'] ?? 'medium',
    dateKey: m['dateKey'] ?? _todayKey(),
  );

  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static String keyFromDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get timeLabel {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  Color get color {
    try {
      return Color(int.parse(colorHex.replaceAll('#', '0xFF')));
    } catch (_) {
      return kTeal;
    }
  }

  Color get priorityColor {
    switch (priority) {
      case 'high':
        return const Color(0xFFEF5350);
      case 'medium':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF66BB6A);
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  HOME SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class PlannerHomeScreen extends StatefulWidget {
  const PlannerHomeScreen({super.key});
  @override
  State<PlannerHomeScreen> createState() => _PlannerHomeScreenState();
}

class _PlannerHomeScreenState extends State<PlannerHomeScreen>
    with TickerProviderStateMixin {
  late Box<List> _box;
  List<Task> _allTasks = [];
  String _filter = 'all';
  late AnimationController _fabAnimCtrl;
  late Animation<double> _fabAnim;

  late DateTime _selectedDate;
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _weekStart = _selectedDate.subtract(Duration(days: now.weekday - 1));

    _box = Hive.box<List>('plannerBox');
    _loadTasks();

    _fabAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fabAnim =
        CurvedAnimation(parent: _fabAnimCtrl, curve: Curves.easeOut);
    Future.delayed(const Duration(milliseconds: 400), _fabAnimCtrl.forward);
  }

  @override
  void dispose() {
    _fabAnimCtrl.dispose();
    super.dispose();
  }

  void _loadTasks() {
    final raw = _box.get('tasks', defaultValue: []) ?? [];
    setState(() {
      _allTasks = raw
          .map((e) => Task.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      _sortTasks();
    });
  }

  void _saveTasks() {
    _box.put('tasks', _allTasks.map((t) => t.toMap()).toList());
  }

  void _sortTasks() {
    _allTasks.sort((a, b) {
      final dateCmp = a.dateKey.compareTo(b.dateKey);
      if (dateCmp != 0) return dateCmp;
      return (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute);
    });
  }

  void _addTask(Task t) async {
    setState(() => _allTasks.add(t));
    _sortTasks();
    _saveTasks();
    if (t.reminderOn) {
      final date = DateTime.parse(t.dateKey);
      await scheduleTaskNotification(t, date);
    }
  }

  void _updateTask(Task t) async {
    await cancelTaskNotification(t.id);
    final idx = _allTasks.indexWhere((e) => e.id == t.id);
    if (idx != -1) {
      setState(() => _allTasks[idx] = t);
      _sortTasks();
      _saveTasks();
    }
    if (t.reminderOn) {
      final date = DateTime.parse(t.dateKey);
      await scheduleTaskNotification(t, date);
    }
  }

  void _deleteTask(String id) async {
    await cancelTaskNotification(id);
    setState(() => _allTasks.removeWhere((t) => t.id == id));
    _saveTasks();
  }

  void _toggleDone(String id) {
    final idx = _allTasks.indexWhere((t) => t.id == id);
    if (idx != -1) {
      setState(() => _allTasks[idx].isDone = !_allTasks[idx].isDone);
      _saveTasks();
    }
  }

  void _toggleReminder(String id) async {
    final idx = _allTasks.indexWhere((t) => t.id == id);
    if (idx != -1) {
      final task = _allTasks[idx];
      task.reminderOn = !task.reminderOn;
      setState(() {});
      _saveTasks();
      if (task.reminderOn) {
        final date = DateTime.parse(task.dateKey);
        await scheduleTaskNotification(task, date);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '🔔 Reminder set for ${task.subject} at ${task.timeLabel}'),
              backgroundColor: kAccentPurple,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        await cancelTaskNotification(id);
      }
    }
  }

  String get _selectedKey => Task.keyFromDate(_selectedDate);

  List<Task> get _dayTasks =>
      _allTasks.where((t) => t.dateKey == _selectedKey).toList();

  List<Task> get _filteredTasks {
    switch (_filter) {
      case 'done':
        return _dayTasks.where((t) => t.isDone).toList();
      case 'pending':
        return _dayTasks.where((t) => !t.isDone).toList();
      default:
        return _dayTasks;
    }
  }

  int get _completedCount => _dayTasks.where((t) => t.isDone).length;
  double get _progress =>
      _dayTasks.isEmpty ? 0 : _completedCount / _dayTasks.length;

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  bool _isSelected(DateTime d) =>
      d.year == _selectedDate.year &&
          d.month == _selectedDate.month &&
          d.day == _selectedDate.day;

  int _taskCountForDay(DateTime d) {
    final key = Task.keyFromDate(d);
    return _allTasks.where((t) => t.dateKey == key).length;
  }

  void _prevWeek() =>
      setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)));

  void _nextWeek() =>
      setState(() => _weekStart = _weekStart.add(const Duration(days: 7)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgGrey,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildProgressCard(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildFilterRow(),
            ),
          ),
          _filteredTasks.isEmpty
              ? SliverToBoxAdapter(child: _buildEmptyState())
              : SliverList(
            delegate: SliverChildBuilderDelegate(
                  (ctx, i) => Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 5),
                child: _TaskCard(
                  task: _filteredTasks[i],
                  onToggleDone: () =>
                      _toggleDone(_filteredTasks[i].id),
                  onToggleReminder: () =>
                      _toggleReminder(_filteredTasks[i].id),
                  onDelete: () => _deleteTask(_filteredTasks[i].id),
                  onEdit: () => _showTaskSheet(context,
                      task: _filteredTasks[i]),
                ),
              ),
              childCount: _filteredTasks.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabAnim,
        child: FloatingActionButton.extended(
          onPressed: () => _showTaskSheet(context),
          backgroundColor: kTeal,
          foregroundColor: Colors.white,
          elevation: 6,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Task',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

    final weekDates = List.generate(7, (i) => _weekStart.add(Duration(days: i)));

    final firstMonth = months[weekDates.first.month - 1];
    final lastMonth  = months[weekDates.last.month - 1];
    final monthLabel = firstMonth == lastMonth
        ? '$firstMonth ${weekDates.first.year}'
        : '$firstMonth – $lastMonth ${weekDates.last.year}';

    final selLabel = _isToday(_selectedDate)
        ? 'Today'
        : '${days[_selectedDate.weekday - 1]}, '
        '${_selectedDate.day} ${months[_selectedDate.month - 1]}';

    final canPop = Navigator.of(context).canPop(); // ← for back button

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [kTeal, kTealDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius:
        BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 14, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row ───────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  // ✅ BACK BUTTON — only shows when there is a previous screen
                  if (canPop)
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 36,
                        height: 36,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white30),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Good ${_greeting()}! 👋',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Study Planner',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5),
                      ),
                    ],
                  ),
                ],
              ),
              // Selected day badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white30),
                ),
                child: Text(
                  selLabel,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Week navigation row
          Row(
            children: [
              GestureDetector(
                onTap: _prevWeek,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.chevron_left_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  monthLabel,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _nextWeek,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.chevron_right_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Day tiles
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final date = weekDates[i];
              final isSelected = _isSelected(date);
              final isToday = _isToday(date);
              final count = _taskCountForDay(date);

              return GestureDetector(
                onTap: () => setState(() => _selectedDate = date),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 42,
                  height: 70,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white
                        : isToday
                        ? Colors.white.withOpacity(0.3)
                        : Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: isToday && !isSelected
                        ? Border.all(color: Colors.white54, width: 1.5)
                        : null,
                    boxShadow: isSelected
                        ? [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 3))
                    ]
                        : [],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        days[i][0],
                        style: TextStyle(
                          color: isSelected ? kTeal : Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          color: isSelected ? kTealDark : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      count > 0
                          ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? kTeal
                              : Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                          : Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kCardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: kTeal.withOpacity(0.10),
              blurRadius: 16,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isToday(_selectedDate)
                        ? "Today's Progress"
                        : "${_dayLabel()} Progress",
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kTextDark),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$_completedCount of ${_dayTasks.length} tasks done',
                    style: const TextStyle(fontSize: 12, color: kTextMuted),
                  ),
                ],
              ),
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: kTealLight),
                child: Center(
                  child: Text(
                    '${(_progress * 100).toInt()}%',
                    style: const TextStyle(
                        color: kTeal,
                        fontWeight: FontWeight.w800,
                        fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 8,
              backgroundColor: kBgGrey,
              valueColor: const AlwaysStoppedAnimation<Color>(kTeal),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatPill(
                  icon: Icons.pending_actions_rounded,
                  label:
                  '${_dayTasks.where((t) => !t.isDone).length} Pending',
                  color: kAccentOrange),
              const SizedBox(width: 8),
              _StatPill(
                  icon: Icons.check_circle_outline_rounded,
                  label: '$_completedCount Done',
                  color: kTeal),
              const SizedBox(width: 8),
              _StatPill(
                  icon: Icons.notifications_active_outlined,
                  label:
                  '${_dayTasks.where((t) => t.reminderOn).length} Reminders',
                  color: kAccentPurple),
            ],
          ),
        ],
      ),
    );
  }

  String _dayLabel() {
    final months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${days[_selectedDate.weekday - 1]} ${_selectedDate.day} ${months[_selectedDate.month - 1]}';
  }

  Widget _buildFilterRow() {
    final filters = [
      ('all', 'All', Icons.apps_rounded),
      ('pending', 'Pending', Icons.hourglass_empty_rounded),
      ('done', 'Done', Icons.check_circle_rounded),
    ];
    return Row(
      children: filters.map((f) {
        final isActive = _filter == f.$1;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => setState(() => _filter = f.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isActive ? kTeal : kCardWhite,
                borderRadius: BorderRadius.circular(20),
                boxShadow: isActive
                    ? [
                  BoxShadow(
                      color: kTeal.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ]
                    : [],
              ),
              child: Row(
                children: [
                  Icon(f.$3,
                      size: 14,
                      color: isActive ? Colors.white : kTextMuted),
                  const SizedBox(width: 5),
                  Text(f.$2,
                      style: TextStyle(
                          color: isActive ? Colors.white : kTextMuted,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: const BoxDecoration(
                color: kTealLight, shape: BoxShape.circle),
            child: const Icon(Icons.menu_book_rounded,
                size: 44, color: kTeal),
          ),
          const SizedBox(height: 16),
          const Text('No tasks yet!',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: kTextDark)),
          const SizedBox(height: 6),
          Text(
            'Tap + to plan ${_isToday(_selectedDate) ? "today" : _dayLabel()}',
            style: const TextStyle(color: kTextMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  void _showTaskSheet(BuildContext context, {Task? task}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddEditTaskSheet(
        existingTask: task,
        defaultDate: _selectedDate,
        onSave: (t) {
          if (task == null) {
            _addTask(t);
          } else {
            _updateTask(t);
          }
        },
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Morning';
    if (h < 17) return 'Afternoon';
    return 'Evening';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  TASK CARD
// ══════════════════════════════════════════════════════════════════════════════

class _TaskCard extends StatefulWidget {
  final Task task;
  final VoidCallback onToggleDone;
  final VoidCallback onToggleReminder;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _TaskCard({
    required this.task,
    required this.onToggleDone,
    required this.onToggleReminder,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _scaleAnim = Tween<double>(begin: 0.95, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTap: widget.onEdit,
        child: Container(
          decoration: BoxDecoration(
            color: kCardWhite,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: t.isDone
                  ? Colors.grey.withOpacity(0.2)
                  : t.color.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Color strip
                Container(
                  width: 54,
                  decoration: BoxDecoration(
                    color: t.isDone
                        ? Colors.grey.withOpacity(0.08)
                        : t.color.withOpacity(0.12),
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(18)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: widget.onToggleDone,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: t.isDone ? kTeal : Colors.transparent,
                            border: Border.all(
                                color: t.isDone ? kTeal : t.color,
                                width: 2),
                          ),
                          child: t.isDone
                              ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 16)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: t.priorityColor),
                      ),
                    ],
                  ),
                ),
                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.subject,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: t.isDone ? kTextMuted : kTextDark,
                                  decoration: t.isDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: t.priorityColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                t.priority.toUpperCase(),
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: t.priorityColor),
                              ),
                            ),
                          ],
                        ),
                        if (t.note.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(t.note,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: kTextMuted)),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.access_time_rounded,
                                size: 13, color: kTextMuted),
                            const SizedBox(width: 4),
                            Text(t.timeLabel,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: kTextMuted,
                                    fontWeight: FontWeight.w600)),
                            const Spacer(),
                            GestureDetector(
                              onTap: widget.onToggleReminder,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: t.reminderOn
                                      ? kAccentPurple.withOpacity(0.12)
                                      : kBgGrey,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  t.reminderOn
                                      ? Icons.notifications_active_rounded
                                      : Icons.notifications_off_outlined,
                                  size: 14,
                                  color: t.reminderOn
                                      ? kAccentPurple
                                      : kTextMuted,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onDelete();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 14,
                                    color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  STAT PILL
// ══════════════════════════════════════════════════════════════════════════════

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatPill(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  ADD / EDIT TASK SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _AddEditTaskSheet extends StatefulWidget {
  final Task? existingTask;
  final DateTime defaultDate;
  final void Function(Task) onSave;

  const _AddEditTaskSheet({
    this.existingTask,
    required this.defaultDate,
    required this.onSave,
  });

  @override
  State<_AddEditTaskSheet> createState() => _AddEditTaskSheetState();
}

class _AddEditTaskSheetState extends State<_AddEditTaskSheet> {
  final _subjectCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  TimeOfDay _time = TimeOfDay.now();
  late DateTime _taskDate;
  bool _reminderOn = false;
  String _priority = 'medium';
  String _colorHex = '#4ECDC4';

  @override
  void initState() {
    super.initState();
    final t = widget.existingTask;
    _taskDate = t != null ? DateTime.parse(t.dateKey) : widget.defaultDate;
    if (t != null) {
      _subjectCtrl.text = t.subject;
      _noteCtrl.text = t.note;
      _time = TimeOfDay(hour: t.hour, minute: t.minute);
      _reminderOn = t.reminderOn;
      _priority = t.priority;
      _colorHex = t.colorHex;
    }
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (ctx, child) => Theme(
        data: ThemeData.light()
            .copyWith(colorScheme: const ColorScheme.light(primary: kTeal)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _time = picked);
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _taskDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.light()
            .copyWith(colorScheme: const ColorScheme.light(primary: kTeal)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _taskDate = picked);
  }

  String get _dateLabel {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final d = DateTime(_taskDate.year, _taskDate.month, _taskDate.day);
    if (d == today) return 'Today';
    if (d == tomorrow) return 'Tomorrow';
    final months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${_taskDate.day} ${months[_taskDate.month - 1]} ${_taskDate.year}';
  }

  void _submit() {
    if (_subjectCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please enter a subject name!'),
        backgroundColor: kAccentOrange,
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    if (_reminderOn) {
      final scheduled = DateTime(
          _taskDate.year, _taskDate.month, _taskDate.day,
          _time.hour, _time.minute);
      if (scheduled.isBefore(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              '⚠️ Reminder time is in the past — notification won\'t fire.'),
          backgroundColor: kAccentOrange,
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }

    final task = Task(
      id: widget.existingTask?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      subject: _subjectCtrl.text.trim(),
      note: _noteCtrl.text.trim(),
      hour: _time.hour,
      minute: _time.minute,
      isDone: widget.existingTask?.isDone ?? false,
      reminderOn: _reminderOn,
      colorHex: _colorHex,
      priority: _priority,
      dateKey: Task.keyFromDate(_taskDate),
    );
    widget.onSave(task);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingTask != null;
    return Container(
      decoration: const BoxDecoration(
        color: kCardWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Handle + close button ─────────────────────────────────
            Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                // ✅ CLOSE button (top-right of sheet)
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: kBgGrey,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 18, color: kTextMuted),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Title row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: kTealLight,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.edit_note_rounded,
                      color: kTeal, size: 22),
                ),
                const SizedBox(width: 10),
                Text(
                  isEdit ? 'Edit Task' : 'New Task',
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: kTextDark),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _SheetLabel('Subject / Course'),
            const SizedBox(height: 6),
            _SheetTextField(
                controller: _subjectCtrl,
                hint: 'e.g. Mathematics, Physics...',
                icon: Icons.book_outlined),
            const SizedBox(height: 14),

            _SheetLabel('Notes (optional)'),
            const SizedBox(height: 6),
            _SheetTextField(
                controller: _noteCtrl,
                hint: 'Add a quick note...',
                icon: Icons.notes_rounded,
                maxLines: 3),
            const SizedBox(height: 14),

            _SheetLabel('Date'),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: kBgGrey,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        color: kTeal, size: 18),
                    const SizedBox(width: 10),
                    Text(_dateLabel,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: kTextDark)),
                    const Spacer(),
                    const Text('Change',
                        style: TextStyle(color: kTeal, fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            _SheetLabel('Time'),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickTime,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: kBgGrey,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        color: kTeal, size: 18),
                    const SizedBox(width: 10),
                    Text(_time.format(context),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: kTextDark)),
                    const Spacer(),
                    const Text('Change',
                        style: TextStyle(color: kTeal, fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            _SheetLabel('Priority'),
            const SizedBox(height: 8),
            Row(
              children: [
                _PriorityChip(
                    label: 'Low',
                    color: const Color(0xFF66BB6A),
                    selected: _priority == 'low',
                    onTap: () => setState(() => _priority = 'low')),
                const SizedBox(width: 8),
                _PriorityChip(
                    label: 'Medium',
                    color: const Color(0xFFFF9800),
                    selected: _priority == 'medium',
                    onTap: () => setState(() => _priority = 'medium')),
                const SizedBox(width: 8),
                _PriorityChip(
                    label: 'High',
                    color: const Color(0xFFEF5350),
                    selected: _priority == 'high',
                    onTap: () => setState(() => _priority = 'high')),
              ],
            ),
            const SizedBox(height: 14),

            _SheetLabel('Color Tag'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kSubjectColors.map((hex) {
                final c =
                Color(int.parse(hex.replaceAll('#', '0xFF')));
                final selected = _colorHex == hex;
                return GestureDetector(
                  onTap: () => setState(() => _colorHex = hex),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: kTextDark, width: 2.5)
                          : null,
                      boxShadow: selected
                          ? [
                        BoxShadow(
                            color: c.withOpacity(0.5), blurRadius: 6)
                      ]
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 16)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _reminderOn
                    ? kAccentPurple.withOpacity(0.08)
                    : kBgGrey,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _reminderOn
                      ? kAccentPurple.withOpacity(0.3)
                      : Colors.grey[200]!,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _reminderOn
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_off_outlined,
                    color: _reminderOn ? kAccentPurple : kTextMuted,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Set Reminder',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: kTextDark,
                                fontSize: 14)),
                        if (_reminderOn)
                          Text(
                            'Notification on $_dateLabel at ${_time.format(context)}',
                            style: const TextStyle(
                                fontSize: 11, color: kTextMuted),
                          ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: _reminderOn,
                    activeColor: kAccentPurple,
                    onChanged: (v) => setState(() => _reminderOn = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kTeal,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  isEdit ? 'Save Changes' : 'Add Task',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SHEET HELPERS
// ══════════════════════════════════════════════════════════════════════════════

class _SheetLabel extends StatelessWidget {
  final String text;
  const _SheetLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: kTextMuted,
          letterSpacing: 0.3));
}

class _SheetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final int maxLines;

  const _SheetTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 14, color: kTextDark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: kTextMuted, fontSize: 13),
        prefixIcon: Icon(icon, color: kTextMuted, size: 18),
        filled: true,
        fillColor: kBgGrey,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey[200]!)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey[200]!)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kTeal, width: 1.5)),
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _PriorityChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? color : color.withOpacity(0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : color)),
      ),
    );
  }
}