// ============================================================
//  chatbot_screen.dart
//  CampusMate AI — with persistent chat history
//  Place in: lib/screens/chatbot_screen.dart
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:groq/groq.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// ── API Key ───────────────────────────────────────────────────────────────────
final String _apiKey = dotenv.env['GROQ_API_KEY'] ?? '';// gsk_...

// ── Storage key for chat history ──────────────────────────────────────────────
const String _chatHistoryKey = 'campusmate_chat_history';
const int    _maxStoredMsgs  = 50; // keep last 50 messages

// ── Colors ────────────────────────────────────────────────────────────────────
const Color _bg          = Color(0xFFF0F1F8);
const Color _userBubble  = Color(0xFF6C63FF);
const Color _botBubble   = Color(0xFFFFFFFF);
const Color _headerStart = Color(0xFF6C63FF);
const Color _headerEnd   = Color(0xFF9C59D1);
const Color _textDark    = Color(0xFF1A1A2E);
const Color _textMuted   = Color(0xFF9E9E9E);
const Color _chipBg      = Color(0xFFEEECFF);
const Color _chipText    = Color(0xFF6C63FF);
const Color _dateDividerColor = Color(0xFFB0B8D0);

// ── Message model ─────────────────────────────────────────────────────────────
class _Msg {
  final String   text;
  final bool     isUser;
  final DateTime time;

  const _Msg(this.text, this.isUser, this.time);

  Map<String, dynamic> toJson() => {
    'text'  : text,
    'isUser': isUser,
    'time'  : time.toIso8601String(),
  };

  factory _Msg.fromJson(Map<String, dynamic> j) => _Msg(
    j['text']   as String,
    j['isUser'] as bool,
    DateTime.parse(j['time'] as String),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
//  SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class ChatbotScreen extends StatefulWidget {
  final String studentName;
  final String studentBranch;

  const ChatbotScreen({
    super.key,
    this.studentName   = 'Student',
    this.studentBranch = 'Computer Engineering',
  });

  @override
  State<ChatbotScreen> createState() => _ChatbotState();
}

class _ChatbotState extends State<ChatbotScreen>
    with TickerProviderStateMixin {

  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  final _msgs   = <_Msg>[];
  final _focus  = FocusNode();

  bool _busy        = false;
  bool _ready       = false;
  bool _isFirstOpen = true;

  late Groq _groq;

  // App data
  double _att         = 0;
  String _subjSummary = 'No subject data yet';
  String _taskSummary = 'No tasks today';
  String _notesSummary= 'No notes saved';

  // Typing animation
  late AnimationController _dot;
  late Animation<double>   _dotA;

  // Input field animation
  late AnimationController _sendBtnCtrl;
  late Animation<double>   _sendBtnAnim;

  final _chips = [
    'My attendance 📊',
    'Today tasks 📅',
    'Am I at risk? ⚠️',
    'Study tips 💡',
    'My notes 📝',
    'Make study plan 📖',
  ];

  // ── Init ────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _dot = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _dotA = Tween(begin: 0.3, end: 1.0).animate(_dot);

    _sendBtnCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _sendBtnAnim = Tween(begin: 1.0, end: 0.92).animate(
        CurvedAnimation(parent: _sendBtnCtrl, curve: Curves.easeInOut));

    _ctrl.addListener(() => setState(() {}));

    _initialize();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _dot.dispose();
    _sendBtnCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ── Initialize: load history + data + groq ──────────────────────────────────
  Future<void> _initialize() async {
    await Future.wait([
      _loadChatHistory(),
      _loadAttendance(),
      _loadTasks(),
      _loadNotes(),
    ]);

    final systemPrompt =
        'You are CampusMate AI, a smart and friendly college assistant. '
        'Student: ${widget.studentName}, Branch: ${widget.studentBranch}. '
        'Attendance: ${_att.toStringAsFixed(1)}% (${_att >= 75 ? "safe" : "at risk"}). '
        'Subjects: $_subjSummary. '
        'Todays tasks: $_taskSummary. '
        'Notes: $_notesSummary. '
        'Use this data for personalized answers. '
        'Keep replies SHORT. For simple questions: 1-3 sentences max. '
        'For study topics: brief + bullet points only if needed. '
        'Never over-explain. No filler phrases.';

    _groq = Groq(
      apiKey: _apiKey,
      configuration: Configuration(
        model: 'llama-3.1-8b-instant',
        temperature: 0.7,
      ),
    );

    _groq.startChat();
    _groq.setCustomInstructionsWith(systemPrompt);

    setState(() => _ready = true);

    // Show welcome only on first ever open
    if (_isFirstOpen && _msgs.isEmpty) {
      _addBot(
          'Welcome ${widget.studentName}! ✨\n\n'
              'I\'m CampusMate AI — your personal academic assistant.\n\n'
              'I analyze your attendance, tasks, and notes to give you smart insights and guidance.\n\n'
              'Let’s make your college life more productive 🚀'
      );
    } else {
      // Scroll to bottom to show latest messages
      _scrollToBottom(instant: true);
    }
  }

  // ── Load chat history from SharedPreferences ────────────────────────────────
  Future<void> _loadChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_chatHistoryKey);
      if (raw == null || raw.isEmpty) {
        _isFirstOpen = true;
        return;
      }
      final list = jsonDecode(raw) as List;
      if (list.isEmpty) {
        _isFirstOpen = true;
        return;
      }
      setState(() {
        _msgs.addAll(list.map((e) =>
            _Msg.fromJson(Map<String, dynamic>.from(e as Map))));
        _isFirstOpen = false;
      });
    } catch (_) {
      _isFirstOpen = true;
    }
  }

  // ── Save chat history to SharedPreferences ──────────────────────────────────
  Future<void> _saveChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep only last _maxStoredMsgs messages
      final toSave = _msgs.length > _maxStoredMsgs
          ? _msgs.sublist(_msgs.length - _maxStoredMsgs)
          : _msgs;
      await prefs.setString(
          _chatHistoryKey, jsonEncode(toSave.map((m) => m.toJson()).toList()));
    } catch (_) {}
  }

  // ── Load attendance ──────────────────────────────────────────────────────────
  Future<void> _loadAttendance() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString('att_subjects');
      if (raw == null) return;
      final list  = jsonDecode(raw) as List;
      int tA = 0, tL = 0;
      final parts = <String>[];
      for (final e in list) {
        final name = (e['name']     as String?) ?? 'Subject';
        final att  = (e['attended'] as int?)    ?? 0;
        final miss = (e['missed']   as int?)    ?? 0;
        final tot  = att + miss;
        tA += att; tL += tot;
        if (tot > 0) {
          final pct = (att / tot * 100).toStringAsFixed(0);
          parts.add('$name:$pct%${att / tot * 100 < 75 ? "(low)" : ""}');
        }
      }
      if (tL > 0) _att = tA / tL * 100;
      if (parts.isNotEmpty) _subjSummary = parts.join(', ');
    } catch (_) {}
  }

  // ── Load tasks ───────────────────────────────────────────────────────────────
  Future<void> _loadTasks() async {
    try {
      if (!Hive.isBoxOpen('plannerBox')) {
        await Hive.openBox<List>('plannerBox');
      }
      final box = Hive.box<List>('plannerBox');
      final raw = box.get('tasks', defaultValue: []) ?? [];
      final now = DateTime.now();
      final key =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final today = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((t) => t['dateKey'] == key)
          .toList();
      if (today.isNotEmpty) {
        _taskSummary = today.map((t) {
          final done = t['isDone'] == true ? 'done' : 'pending';
          return '${t['subject']}($done)';
        }).join(', ');
      }
    } catch (_) {}
  }

  // ── Load notes ───────────────────────────────────────────────────────────────
  Future<void> _loadNotes() async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final raw    = prefs.getString('notes_list');
      if (raw == null) return;
      final list   = jsonDecode(raw) as List;
      final titles = list
          .map((e) => (e['title'] as String?) ?? '')
          .where((s) => s.isNotEmpty)
          .take(6)
          .toList();
      if (titles.isNotEmpty) _notesSummary = titles.join(', ');
    } catch (_) {}
  }

  // ── Send message ─────────────────────────────────────────────────────────────
  Future<void> _send(String text) async {
    final msg = text.trim();
    if (msg.isEmpty || _busy || !_ready) return;
    _ctrl.clear();
    HapticFeedback.lightImpact();

    setState(() {
      _msgs.add(_Msg(msg, true, DateTime.now()));
      _busy = true;
    });
    _scrollToBottom();

    try {
      final response = await _groq.sendMessage(msg);
      final reply    = response.choices.first.message.content.trim();
      setState(() => _busy = false);
      _addBot(reply.isNotEmpty ? reply : 'No response. Please try again.');
    } on GroqException catch (e) {
      setState(() => _busy = false);
      _addBot('API error: ${e.message}');
    } catch (e) {
      setState(() => _busy = false);
      _addBot('Something went wrong. Please try again.');
    }
  }

  void _addBot(String t) {
    setState(() => _msgs.add(_Msg(t, false, DateTime.now())));
    _saveChatHistory(); // ← save after every bot reply
    _scrollToBottom();
  }

  void _scrollToBottom({bool instant = false}) {
    Future.delayed(Duration(milliseconds: instant ? 50 : 150), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: Duration(milliseconds: instant ? 1 : 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Date label between messages ──────────────────────────────────────────────
  String _dateLabel(DateTime t) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yest  = today.subtract(const Duration(days: 1));
    final d     = DateTime(t.year, t.month, t.day);
    if (d == today) return 'Today';
    if (d == yest)  return 'Yesterday';
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${t.day} ${months[t.month - 1]} ${t.year}';
  }

  bool _showDateDivider(int i) {
    if (i == 0) return true;
    final prev = _msgs[i - 1].time;
    final curr = _msgs[i].time;
    return prev.year  != curr.year ||
        prev.month != curr.month ||
        prev.day   != curr.day;
  }

  String _formatTime(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? "AM" : "PM"}';
  }

  // ── Clear chat ───────────────────────────────────────────────────────────────
  Future<void> _clearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear Chat',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
            'This will delete all chat history permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _userBubble,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Clear SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chatHistoryKey);

    // Reset Groq session
    _groq.startChat();
    _groq.setCustomInstructionsWith(
      'You are CampusMate AI. Student: ${widget.studentName}. '
          'Attendance: ${_att.toStringAsFixed(1)}%. '
          'Subjects: $_subjSummary. Tasks: $_taskSummary. Notes: $_notesSummary. '
          'Keep replies SHORT. 1-3 sentences for simple questions. No over-explaining.',
    );

    setState(() => _msgs.clear());
    _addBot('Chat cleared! 🧹 How can I help you, ${widget.studentName}?');
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: !_ready
              ? _buildLoadingState()
              : GestureDetector(
            onTap: () => _focus.unfocus(),
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              itemCount: _msgs.length + (_busy ? 1 : 0),
              itemBuilder: (_, i) {
                if (_busy && i == _msgs.length) {
                  return _typingBubble();
                }
                return Column(
                  children: [
                    if (_showDateDivider(i))
                      _dateDivider(_dateLabel(_msgs[i].time)),
                    _bubble(_msgs[i]),
                  ],
                );
              },
            ),
          ),
        ),
        // Chips only on first message
        if (_ready && !_busy && _msgs.length <= 1) _chipsRow(),
        _inputBar(),
      ]),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [_headerStart, _headerEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius:
        BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 12, 16, 18),
      child: Row(children: [
        // Back
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white30),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 16),
          ),
        ),
        const SizedBox(width: 12),

        // Avatar with pulse
        Stack(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white38, width: 2),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 22),
            ),
            Positioned(
              bottom: 1, right: 1,
              child: Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF69F0AE),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),

        // Title
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CampusMate AI',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3)),
              Text(
                _busy ? 'Typing...' : 'Online · Your study assistant',
                style: TextStyle(
                    color: _busy
                        ? const Color(0xFFFFE082)
                        : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),

        // Clear chat button
        GestureDetector(
          onTap: _clearChat,
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete_outline_rounded,
                color: Colors.white, size: 18),
          ),
        ),
      ]),
    );
  }

  // ── Date divider ──────────────────────────────────────────────────────────
  Widget _dateDivider(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Expanded(
            child: Divider(color: _dateDividerColor.withOpacity(0.4),
                thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4)
              ],
            ),
            child: Text(label,
                style: const TextStyle(
                    color: _dateDividerColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
        ),
        Expanded(
            child: Divider(
                color: _dateDividerColor.withOpacity(0.4), thickness: 1)),
      ]),
    );
  }

  // ── Chat bubble ───────────────────────────────────────────────────────────
  Widget _bubble(_Msg m) {
    final u = m.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
        u ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Bot avatar
          if (!u) ...[
            Container(
              width: 32, height: 32,
              margin: const EdgeInsets.only(right: 8, bottom: 2),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [_headerStart, _headerEnd]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 15),
            ),
          ],

          Flexible(
            child: Column(
              crossAxisAlignment: u
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Long press to copy
                GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: m.text));
                    HapticFeedback.mediumImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Message copied!'),
                        duration: const Duration(seconds: 1),
                        backgroundColor: _userBubble,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  },
                  child: Container(
                    constraints: BoxConstraints(
                        maxWidth:
                        MediaQuery.of(context).size.width * 0.75),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: u ? _userBubble : _botBubble,
                      borderRadius: BorderRadius.only(
                        topLeft:     const Radius.circular(18),
                        topRight:    const Radius.circular(18),
                        bottomLeft:  Radius.circular(u ? 18 : 4),
                        bottomRight: Radius.circular(u ? 4 : 18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: u
                              ? _userBubble.withOpacity(0.25)
                              : Colors.black.withOpacity(0.07),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      m.text,
                      style: TextStyle(
                        color: u ? Colors.white : _textDark,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Time + tick for user messages
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_formatTime(m.time),
                        style: const TextStyle(
                            color: _textMuted, fontSize: 10)),
                    if (u) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.done_all_rounded,
                          size: 12, color: _userBubble),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // User avatar
          if (u) ...[
            Container(
              width: 32, height: 32,
              margin: const EdgeInsets.only(left: 8, bottom: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF9C59D1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  widget.studentName.isNotEmpty
                      ? widget.studentName[0].toUpperCase()
                      : 'S',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Typing indicator ──────────────────────────────────────────────────────
  Widget _typingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 32, height: 32,
            margin: const EdgeInsets.only(right: 8, bottom: 2),
            decoration: const BoxDecoration(
              gradient:
              LinearGradient(colors: [_headerStart, _headerEnd]),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 15),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: _botBubble,
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(18),
                topRight:    Radius.circular(18),
                bottomLeft:  Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.07),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                3,
                    (i) => AnimatedBuilder(
                  animation: _dotA,
                  builder: (_, __) {
                    final opacity = i == 0
                        ? _dotA.value
                        : i == 1
                        ? _dotA.value * 0.7
                        : _dotA.value * 0.4;
                    return Container(
                      width: 8, height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: _headerStart.withOpacity(opacity),
                        shape: BoxShape.circle,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick chips ───────────────────────────────────────────────────────────
  Widget _chipsRow() {
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 16, bottom: 8),
            child: Text('Quick actions',
                style: TextStyle(
                    color: _textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _chips.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _send(_chips[i]),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _chipBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _chipText.withOpacity(0.25)),
                    boxShadow: [
                      BoxShadow(
                          color: _chipText.withOpacity(0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: Text(_chips[i],
                      style: const TextStyle(
                          color: _chipText,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // ── Input bar ─────────────────────────────────────────────────────────────
  Widget _inputBar() {
    final hasText = _ctrl.text.trim().isNotEmpty;
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: _bg,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -3))
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Text field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
                border: Border.all(
                  color: hasText
                      ? _userBubble.withOpacity(0.4)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                maxLines: 5,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(
                    fontSize: 14, color: _textDark, height: 1.4),
                decoration: InputDecoration(
                  hintText: _ready
                      ? 'Message CampusMate AI...'
                      : 'Loading your data...',
                  hintStyle: TextStyle(
                      color: Colors.grey[400], fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                ),
                onSubmitted: (v) {
                  if (!_busy) _send(v);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Send button — animates in/out
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: 48, height: 48,
            child: GestureDetector(
              onTapDown: (_) => _sendBtnCtrl.forward(),
              onTapUp: (_) {
                _sendBtnCtrl.reverse();
                _send(_ctrl.text);
              },
              onTapCancel: () => _sendBtnCtrl.reverse(),
              child: ScaleTransition(
                scale: _sendBtnAnim,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: hasText && !_busy
                          ? [_headerStart, _headerEnd]
                          : [Colors.grey.shade300, Colors.grey.shade400],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: hasText && !_busy
                        ? [
                      BoxShadow(
                          color: _userBubble.withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ]
                        : [],
                  ),
                  child: Icon(
                    _busy
                        ? Icons.hourglass_empty_rounded
                        : Icons.send_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Loading state ─────────────────────────────────────────────────────────
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72, height: 72,
            decoration: const BoxDecoration(
              gradient:
              LinearGradient(colors: [_headerStart, _headerEnd]),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 34),
          ),
          const SizedBox(height: 16),
          const Text('Preparing your assistant...',
              style: TextStyle(
                  color: _headerStart,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Loading attendance, tasks & notes',
              style: TextStyle(
                  color: Colors.grey[500], fontSize: 13)),
          const SizedBox(height: 20),
          const SizedBox(
            width: 180,
            child: LinearProgressIndicator(
              color: _headerStart,
              backgroundColor: Color(0xFFDDD9FF),
              minHeight: 3,
            ),
          ),
        ],
      ),
    );
  }
}