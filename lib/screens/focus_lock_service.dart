// =============================================================================
// focus_lock_service.dart
//
// Focus Lock + Sound System for Pomodoro
// Updated for flutter_foreground_task v8.x API
// =============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1 — SOUND MANAGER
// ─────────────────────────────────────────────────────────────────────────────

class FocusSoundManager {
  static final FocusSoundManager _instance = FocusSoundManager._();
  factory FocusSoundManager() => _instance;
  FocusSoundManager._();

  final AudioPlayer _player = AudioPlayer();
  bool _soundEnabled = true;
  double _volume = 0.8;

  bool get soundEnabled => _soundEnabled;
  double get volume => _volume;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _soundEnabled = prefs.getBool('focus_sound_enabled') ?? true;
    _volume       = prefs.getDouble('focus_sound_volume') ?? 0.8;
    await _player.setVolume(_volume);
  }

  Future<void> setSoundEnabled(bool val) async {
    _soundEnabled = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('focus_sound_enabled', val);
  }

  Future<void> setVolume(double val) async {
    _volume = val.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('focus_sound_volume', _volume);
  }

  Future<void> playFocusStart() async {
    if (!_soundEnabled) return;
    await _playAsset('sounds/focus_start.mp3');
  }

  Future<void> playFocusComplete() async {
    if (!_soundEnabled) return;
    await _playAsset('sounds/focus_complete.mp3');
  }

  Future<void> playBreakStart() async {
    if (!_soundEnabled) return;
    await _playAsset('sounds/break_start.mp3');
  }

  Future<void> playBreakComplete() async {
    if (!_soundEnabled) return;
    await _playAsset('sounds/break_complete.mp3');
  }

  Future<void> playLevelUp() async {
    if (!_soundEnabled) return;
    await _playAsset('sounds/level_up.mp3');
  }

  Future<void> playBadgeUnlocked() async {
    if (!_soundEnabled) return;
    await _playAsset('sounds/badge_unlocked.mp3');
  }

  Future<void> _playAsset(String path) async {
    try {
      await _player.stop();
      await _player.play(AssetSource(path));
    } catch (e) {
      await HapticFeedback.mediumImpact();
    }
  }

  Future<void> playBeep({int frequency = 440, int durationMs = 300}) async {
    if (!_soundEnabled) return;
    try {
      final bytes = _generateSineWave(
          frequency: frequency, durationMs: durationMs);
      await _player.stop();
      await _player.play(BytesSource(bytes));
    } catch (_) {
      await HapticFeedback.heavyImpact();
    }
  }

  Uint8List _generateSineWave({
    int frequency = 440,
    int durationMs = 500,
    int sampleRate = 44100,
  }) {
    final numSamples = (sampleRate * durationMs / 1000).round();
    final data = ByteData(44 + numSamples * 2);

    final header = <int>[
      0x52, 0x49, 0x46, 0x46,
      0, 0, 0, 0,
      0x57, 0x41, 0x56, 0x45,
      0x66, 0x6D, 0x74, 0x20,
      16, 0, 0, 0,
      1, 0,
      1, 0,
      0, 0, 0, 0,
      0, 0, 0, 0,
      2, 0,
      16, 0,
      0x64, 0x61, 0x74, 0x61,
      0, 0, 0, 0,
    ];

    for (int i = 0; i < header.length; i++) {
      data.setUint8(i, header[i]);
    }

    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint32(40, numSamples * 2, Endian.little);
    data.setUint32(4, 36 + numSamples * 2, Endian.little);

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      double sample = math.sin(2 * math.pi * frequency * t);

      final fadeLen = (sampleRate * 0.01).round();
      if (i < fadeLen) sample *= i / fadeLen;
      if (i > numSamples - fadeLen) sample *= (numSamples - i) / fadeLen;

      final value = (sample * 32767 * _volume).round().clamp(-32768, 32767);
      data.setInt16(44 + i * 2, value, Endian.little);
    }

    return data.buffer.asUint8List();
  }

  void dispose() {
    _player.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2 — FOCUS LOCK MANAGER
// ─────────────────────────────────────────────────────────────────────────────

class FocusLockManager extends ChangeNotifier {
  static final FocusLockManager _instance = FocusLockManager._();
  factory FocusLockManager() => _instance;
  FocusLockManager._();

  bool _isLocked = false;
  bool _dndEnabled = false;
  bool _overlayEnabled = true;
  List<String> _whitelistedContacts = [];

  bool get isLocked => _isLocked;
  bool get dndEnabled => _dndEnabled;
  bool get overlayEnabled => _overlayEnabled;
  List<String> get whitelistedContacts =>
      List.unmodifiable(_whitelistedContacts);

  static const _platform = MethodChannel('com.campusmate/focus_lock');

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _dndEnabled      = prefs.getBool('focus_dnd_enabled') ?? false;
    _overlayEnabled  = prefs.getBool('focus_overlay_enabled') ?? true;
    _whitelistedContacts = prefs.getStringList('focus_whitelist') ?? [];
  }

  Future<bool> requestDNDPermission() async {
    final status = await Permission.accessNotificationPolicy.request();
    return status.isGranted;
  }

  Future<bool> hasDNDPermission() async {
    return await Permission.accessNotificationPolicy.isGranted;
  }

  Future<bool> requestOverlayPermission() async {
    final status = await Permission.systemAlertWindow.request();
    return status.isGranted;
  }
  Future<void> activateFocusLock() async {
    _isLocked = true;

    // Enable DND if allowed
    if (_dndEnabled && await hasDNDPermission()) {
      try {
        await _enableDND();
      } catch (e) {
        debugPrint('DND failed: $e');
      }
    }

    // Start overlay safely
    if (_overlayEnabled) {
      try {
        await _startOverlayService();
      } catch (e) {
        debugPrint('Overlay skipped: $e');
      }
    }

    notifyListeners();
  }
  Future<void> deactivateFocusLock() async {
    _isLocked = false;
    if (_dndEnabled) await _disableDND();
    await _stopOverlayService();
    notifyListeners();
  }

  Future<void> _enableDND() async {
    try {
      await _platform.invokeMethod('enableDND', {
        'whitelistedNumbers': _whitelistedContacts,
      });
    } catch (e) {
      debugPrint('DND enable failed: $e');
    }
  }
  Future<void> _disableDND() async {
    try {
      await _platform.invokeMethod('disableDND');
    } catch (e) {
      debugPrint('DND disable failed: $e');
    }
  }

  Future<void> _startOverlayService() async {
    try {
      await _platform.invokeMethod('startOverlay', {
        'message': 'Focus session in progress...',
        'allowEmergency': true,
      });
    } catch (e) {
      debugPrint('Overlay not implemented yet: $e');
    }
  }

  Future<void> _stopOverlayService() async {
    try {
      await _platform.invokeMethod('stopOverlay');
    } catch (e) {
      debugPrint('Overlay stop failed: $e');
    }
  }
  Future<void> setDNDEnabled(bool val) async {
    _dndEnabled = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('focus_dnd_enabled', val);
    notifyListeners();
  }

  Future<void> setOverlayEnabled(bool val) async {
    _overlayEnabled = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('focus_overlay_enabled', val);
    notifyListeners();
  }

  Future<void> addWhitelistedContact(String phoneNumber) async {
    if (!_whitelistedContacts.contains(phoneNumber)) {
      _whitelistedContacts.add(phoneNumber);
      await _saveWhitelist();
      notifyListeners();
    }
  }

  Future<void> removeWhitelistedContact(String phoneNumber) async {
    _whitelistedContacts.remove(phoneNumber);
    await _saveWhitelist();
    notifyListeners();
  }

  Future<void> _saveWhitelist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('focus_whitelist', _whitelistedContacts);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3 — FOREGROUND SERVICE
// FIX: Updated TaskHandler signatures for flutter_foreground_task v8.x
// - onStart:       (DateTime, TaskStarter) -> Future<void>   ← was SendPort?
// - onRepeatEvent: (DateTime) -> void                        ← was Future<void> + SendPort?
// - onDestroy:     (DateTime) -> Future<void>                ← was Future<void> + SendPort?
// - receivePort:   accessed via FlutterForegroundTask.receivePort (private API removed)
// - AndroidNotificationOptions: removed iconData, buttons, interval, isOnceEvent params
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_FocusTaskHandler());
}

class _FocusTaskHandler extends TaskHandler {
  int _remainingSeconds = 0;
  String _phaseName = 'Focus';
  Timer? _timer;

  // FIX: Signature updated — was (DateTime, SendPort?), now (DateTime, TaskStarter)
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final prefs = await SharedPreferences.getInstance();
    _remainingSeconds = prefs.getInt('fg_remaining_seconds') ?? 1500;
    _phaseName = prefs.getString('fg_phase_name') ?? 'Focus';
    _startTick();
  }

  void _startTick() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        _updateNotification();
        // FIX: Use FlutterForegroundTask.sendDataToMain() instead of SendPort
        FlutterForegroundTask.sendDataToMain(
            {'type': 'tick', 'remaining': _remainingSeconds});
      } else {
        FlutterForegroundTask.sendDataToMain({'type': 'complete'});
        _timer?.cancel();
      }
    });
  }

  void _updateNotification() {
    final mins = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_remainingSeconds % 60).toString().padLeft(2, '0');
    FlutterForegroundTask.updateService(
      notificationTitle: '🎯 $_phaseName — $mins:$secs',
      notificationText: _remainingSeconds > 0
          ? 'Stay focused! Tap to return to app.'
          : 'Session complete! 🎉',
    );
  }

  // FIX: Signature updated — was (DateTime, SendPort?) -> Future<void>,
  // now (DateTime) -> void  (no async, no SendPort)
  @override
  void onRepeatEvent(DateTime timestamp) {
    // Intentionally empty — tick is driven by our own Timer above
  }

  // FIX: Signature updated — was (DateTime, SendPort?) -> Future<void>,
  // now (DateTime) -> Future<void>  (no SendPort)
  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _timer?.cancel();
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/pomodoro');
  }
}

class ForegroundServiceManager {
  static final ForegroundServiceManager _i = ForegroundServiceManager._();
  factory ForegroundServiceManager() => _i;
  ForegroundServiceManager._();

  Function(int remaining)? onTick;
  VoidCallback? onComplete;

  void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'focus_timer_channel',
        channelName: 'Focus Timer',
        channelDescription: 'Shows timer countdown during focus sessions.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        // FIX: 'iconData' param removed in v8 — icon is set via app's
        // notification icon in AndroidManifest.xml instead.
        // FIX: 'buttons' param removed in v8 — use onNotificationPressed instead.
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // FIX: 'interval' and 'isOnceEvent' removed in v8.
        // Use eventAction instead: ForegroundTaskEventAction.repeat(ms)
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<bool> requestPermissions() async {
    final notif = await Permission.notification.request();
    return notif.isGranted;
  }

  Future<void> startService({
    required int remainingSeconds,
    required String phaseName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('fg_remaining_seconds', remainingSeconds);
    await prefs.setString('fg_phase_name', phaseName);

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        notificationTitle: '🎯 $phaseName',
        notificationText: 'Focus session starting...',
        callback: startCallback,
      );
    }

    // FIX: receivePort is a private API only accessible inside the task
    // package itself. In v8 use FlutterForegroundTask.addTaskDataCallback()
    // to receive data sent via FlutterForegroundTask.sendDataToMain().
    FlutterForegroundTask.addTaskDataCallback(_onReceiveData);
  }

  void _onReceiveData(Object data) {
    if (data is Map) {
      if (data['type'] == 'tick') {
        onTick?.call(data['remaining'] as int);
      } else if (data['type'] == 'complete') {
        onComplete?.call();
      }
    }
  }

  Future<void> stopService() async {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveData);
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  Future<void> updateRemaining(int seconds, String phase) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('fg_remaining_seconds', seconds);
    await prefs.setString('fg_phase_name', phase);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 4 — FOCUS LOCK OVERLAY WIDGET
// FIX: WillPopScope → PopScope (deprecated after Flutter 3.12)
// ─────────────────────────────────────────────────────────────────────────────

class FocusLockOverlay extends StatefulWidget {
  final int remainingSeconds;
  final String subjectName;
  final String subjectEmoji;
  final Color subjectColor;
  final bool isDark;
  final VoidCallback onEmergencyExit;
  final VoidCallback onDismiss;

  const FocusLockOverlay({
    super.key,
    required this.remainingSeconds,
    required this.subjectName,
    required this.subjectEmoji,
    required this.subjectColor,
    required this.isDark,
    required this.onEmergencyExit,
    required this.onDismiss,
  });

  @override
  State<FocusLockOverlay> createState() => _FocusLockOverlayState();
}

class _FocusLockOverlayState extends State<FocusLockOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _holdCtrl;
  Timer? _holdTimer;
  bool _holding = false;
  int _holdSeconds = 0;
  static const _holdRequired = 3;

  @override
  void initState() {
    super.initState();
    _holdCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _holdRequired),
    );
  }

  @override
  void dispose() {
    _holdCtrl.dispose();
    _holdTimer?.cancel();
    super.dispose();
  }

  String _fmt(int totalSeconds) {
    final m   = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final sec = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  void _startHold() {
    setState(() {
      _holding = true;
      _holdSeconds = 0;
    });
    _holdCtrl.forward(from: 0);
    _holdTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _holdSeconds++);
      if (_holdSeconds >= _holdRequired) {
        t.cancel();
        widget.onDismiss();
      }
    });
  }

  void _cancelHold() {
    setState(() {
      _holding = false;
      _holdSeconds = 0;
    });
    _holdCtrl.reset();
    _holdTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final color  = widget.subjectColor;

    // FIX: WillPopScope is deprecated. Use PopScope with canPop: false.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF0A0F0A)
            : const Color(0xFFF0F7F0),
        body: Stack(children: [
          Center(
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  color.withValues(alpha: 0.15),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(
                              color: Colors.red, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text('FOCUS LOCKED',
                            style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2)),
                      ]),
                    ),
                    TextButton(
                      onPressed: () => _showEmergencyDialog(context),
                      child: Text('Emergency',
                          style: TextStyle(
                              color: Colors.red.withValues(alpha: 0.6),
                              fontSize: 11)),
                    ),
                  ],
                ),
                const Spacer(),
                Text(widget.subjectEmoji,
                    style: const TextStyle(fontSize: 80)),
                const SizedBox(height: 16),
                Text(widget.subjectName,
                    style: TextStyle(
                        color: isDark
                            ? Colors.white
                            : const Color(0xFF1B2E1C),
                        fontSize: 28,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('Focus session in progress',
                    style: TextStyle(
                        color: isDark
                            ? Colors.white60
                            : const Color(0xFF5A7A5C),
                        fontSize: 15)),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 20),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _fmt(widget.remainingSeconds),
                    style: TextStyle(
                        color: color,
                        fontSize: 52,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
                const SizedBox(height: 12),
                Text('remaining',
                    style: TextStyle(
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontSize: 13)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _motivationalQuote(widget.remainingSeconds),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 14,
                        fontStyle: FontStyle.italic),
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onLongPressStart: (_) => _startHold(),
                  onLongPressEnd: (_) => _cancelHold(),
                  onLongPressCancel: _cancelHold,
                  child: AnimatedBuilder(
                    animation: _holdCtrl,
                    builder: (_, __) => Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Colors.black.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: _holding
                                ? Colors.red.withValues(alpha: 0.5)
                                : Colors.transparent),
                      ),
                      child: Stack(children: [
                        if (_holding)
                          FractionallySizedBox(
                            widthFactor: _holdCtrl.value,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        Center(
                          child: Text(
                            _holding
                                ? 'Hold ${_holdRequired - _holdSeconds}s more to exit...'
                                : '🔒  Hold to exit focus mode',
                            style: TextStyle(
                                color: _holding
                                    ? Colors.red
                                    : (isDark
                                    ? Colors.white38
                                    : Colors.black38),
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Phone calls from emergency contacts still work',
                  style: TextStyle(
                      color: isDark ? Colors.white24 : Colors.black26,
                      fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  String _motivationalQuote(int remaining) {
    if (remaining > 1200) {
      return '"The secret of getting ahead is getting started." — Mark Twain';
    }
    if (remaining > 900) {
      return '"Focus on being productive instead of busy." — Tim Ferriss';
    }
    if (remaining > 600) {
      return '"You can do anything, but not everything." — David Allen';
    }
    if (remaining > 300) {
      return '"Almost there! Deep work creates deep results." 💪';
    }
    return '"Last stretch! You\'re crushing it! 🔥"';
  }

  void _showEmergencyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor:
        widget.isDark ? const Color(0xFF1E2630) : Colors.white,
        title: const Text('Emergency Exit?',
            style: TextStyle(
                fontWeight: FontWeight.w800, color: Colors.red)),
        content: Text(
          'This will end your focus session and break your streak. '
              'Only use this for genuine emergencies.',
          style: TextStyle(
              color: widget.isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Stay Focused',
                style: TextStyle(
                    color: Color(0xFF43A047),
                    fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onEmergencyExit();
            },
            child: const Text('Exit Anyway',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 5 — FOCUS LOCK SETTINGS WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class FocusLockSettingsCard extends StatefulWidget {
  final bool isDark;
  const FocusLockSettingsCard({super.key, required this.isDark});

  @override
  State<FocusLockSettingsCard> createState() =>
      _FocusLockSettingsCardState();
}

class _FocusLockSettingsCardState extends State<FocusLockSettingsCard> {
  final _lock        = FocusLockManager();
  final _sound       = FocusSoundManager();
  final _numberCtrl  = TextEditingController();

  @override
  void initState() {
    super.initState();
    _lock.init();
    _sound.init();
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    super.dispose();
  }

  bool get isDark => widget.isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('🔊 Sound Settings', isDark),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161C20) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isDark
                    ? const Color(0xFF2A3C2B)
                    : const Color(0xFFD0E8D0)),
          ),
          child: Column(children: [
            _ToggleRow(
              label: 'Session sounds',
              subtitle: 'Chimes on start, complete, break',
              value: _sound.soundEnabled,
              isDark: isDark,
              activeColor: const Color(0xFF43A047),
              onChanged: (v) async {
                await _sound.setSoundEnabled(v);
                setState(() {});
              },
            ),
            const SizedBox(height: 16),
            if (_sound.soundEnabled) ...[
              Row(children: [
                const Text('🔈', style: TextStyle(fontSize: 16)),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: const Color(0xFF43A047),
                      inactiveTrackColor: isDark
                          ? const Color(0xFF2A3C2B)
                          : const Color(0xFFD0E8D0),
                      thumbColor: const Color(0xFF43A047),
                      overlayColor:
                      const Color(0xFF43A047).withValues(alpha: 0.15),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: _sound.volume,
                      min: 0, max: 1, divisions: 10,
                      onChanged: (v) async {
                        await _sound.setVolume(v);
                        setState(() {});
                      },
                    ),
                  ),
                ),
                const Text('🔊', style: TextStyle(fontSize: 16)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: _SoundTestBtn(
                        '▶ Focus', () => _sound.playFocusStart(), isDark)),
                const SizedBox(width: 8),
                Expanded(
                    child: _SoundTestBtn(
                        '✅ Done', () => _sound.playFocusComplete(), isDark)),
                const SizedBox(width: 8),
                Expanded(
                    child: _SoundTestBtn(
                        '☕ Break', () => _sound.playBreakStart(), isDark)),
              ]),
            ],
          ]),
        ),

        const SizedBox(height: 24),
        _SectionHeader('🔒 Focus Lock', isDark),
        const SizedBox(height: 8),
        Text(
          'During focus sessions, block all distractions. '
              'Calls/messages from whitelisted contacts still work.',
          style: TextStyle(
              color: isDark
                  ? const Color(0xFF7A9A7C)
                  : const Color(0xFF5A7A5C),
              fontSize: 12),
        ),
        const SizedBox(height: 12),

        ListenableBuilder(
          listenable: _lock,
          builder: (_, __) => Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161C20) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isDark
                      ? const Color(0xFF2A3C2B)
                      : const Color(0xFFD0E8D0)),
            ),
            child: Column(children: [
              _ToggleRow(
                label: 'Do Not Disturb',
                subtitle: 'Silence all notifications during focus',
                value: _lock.dndEnabled,
                isDark: isDark,
                activeColor: const Color(0xFF43A047),
                onChanged: (v) async {
                  if (v) {
                    final granted = await _lock.requestDNDPermission();
                    if (!granted && context.mounted) {
                      _showPermissionDialog(context,
                          'Do Not Disturb Permission',
                          'Please allow DND access in Settings → Apps → Special App Access.');
                      return;
                    }
                  }
                  await _lock.setDNDEnabled(v);
                  setState(() {});
                },
              ),
              const Divider(height: 24, color: Color(0xFF2A3C2B)),
              _ToggleRow(
                label: 'Focus Overlay',
                subtitle: 'Show lock screen when leaving app',
                value: _lock.overlayEnabled,
                isDark: isDark,
                activeColor: const Color(0xFF43A047),
                onChanged: (v) async {
                  if (v) {
                    final granted =
                    await _lock.requestOverlayPermission();
                    if (!granted && context.mounted) {
                      _showPermissionDialog(context,
                          'Overlay Permission',
                          'Please allow "Display over other apps" in Settings.');
                      return;
                    }
                  }
                  await _lock.setOverlayEnabled(v);
                  setState(() {});
                },
              ),
              const Divider(height: 24, color: Color(0xFF2A3C2B)),
              Row(children: [
                Text('📞 Allowed Contacts',
                    style: TextStyle(
                        color: isDark
                            ? Colors.white
                            : const Color(0xFF1B2E1C),
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const Spacer(),
                Text('${_lock.whitelistedContacts.length} contacts',
                    style: TextStyle(
                        color: isDark
                            ? const Color(0xFF7A9A7C)
                            : const Color(0xFF5A7A5C),
                        fontSize: 11)),
              ]),
              const SizedBox(height: 8),
              Text(
                'Calls and messages from these numbers will bypass DND during focus.',
                style: TextStyle(
                    color: isDark
                        ? const Color(0xFF7A9A7C)
                        : const Color(0xFF5A7A5C),
                    fontSize: 11),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _numberCtrl,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(
                        color: isDark
                            ? Colors.white
                            : const Color(0xFF1B2E1C),
                        fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '+91 98765 43210',
                      hintStyle: TextStyle(
                          color: isDark
                              ? const Color(0xFF7A9A7C)
                              : const Color(0xFF5A7A5C)),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1E2630)
                          : const Color(0xFFEFF7EE),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      prefixIcon: const Icon(Icons.phone_rounded,
                          size: 16, color: Color(0xFF43A047)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () async {
                    final num = _numberCtrl.text.trim();
                    if (num.isNotEmpty) {
                      await _lock.addWhitelistedContact(num);
                      _numberCtrl.clear();
                      setState(() {});
                    }
                  },
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [
                        Color(0xFF43A047),
                        Color(0xFF81C784)
                      ]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                    const Icon(Icons.add, color: Colors.white, size: 20),
                  ),
                ),
              ]),
              if (_lock.whitelistedContacts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _lock.whitelistedContacts
                      .map((num) => _ContactChip(
                    number: num,
                    isDark: isDark,
                    onRemove: () async {
                      await _lock.removeWhitelistedContact(num);
                      setState(() {});
                    },
                  ))
                      .toList(),
                ),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  void _showPermissionDialog(
      BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E2630) : Colors.white,
        title: Text(title,
            style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF1B2E1C),
                fontWeight: FontWeight.w700)),
        content: Text(message,
            style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK',
                style: TextStyle(
                    color: Color(0xFF43A047),
                    fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings',
                style: TextStyle(color: Color(0xFF43A047))),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 6 — REUSABLE SMALL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  final bool isDark;
  const _SectionHeader(this.text, this.isDark);

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 3, height: 16,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF43A047), Color(0xFF81C784)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
    Text(text,
        style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1B2E1C),
            fontWeight: FontWeight.w700,
            fontSize: 15)),
  ]);
}

class _ToggleRow extends StatelessWidget {
  final String label, subtitle;
  final bool value, isDark;
  final Color activeColor;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.isDark,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: isDark
                        ? Colors.white
                        : const Color(0xFF1B2E1C),
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(
                    color: isDark
                        ? const Color(0xFF7A9A7C)
                        : const Color(0xFF5A7A5C),
                    fontSize: 11)),
          ]),
    ),
    Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: activeColor,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  ]);
}

class _SoundTestBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isDark;
  const _SoundTestBtn(this.label, this.onTap, this.isDark);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 36,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E2630)
            : const Color(0xFFEFF7EE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFF43A047).withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Text(label,
            style: const TextStyle(
                color: Color(0xFF43A047),
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ),
    ),
  );
}

class _ContactChip extends StatelessWidget {
  final String number;
  final bool isDark;
  final VoidCallback onRemove;
  const _ContactChip(
      {required this.number,
        required this.isDark,
        required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFF43A047).withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
          color: const Color(0xFF43A047).withValues(alpha: 0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.phone_rounded,
          size: 12, color: Color(0xFF43A047)),
      const SizedBox(width: 5),
      Text(number,
          style: const TextStyle(
              color: Color(0xFF43A047),
              fontSize: 12,
              fontWeight: FontWeight.w600)),
      const SizedBox(width: 6),
      GestureDetector(
        onTap: onRemove,
        child: const Icon(Icons.close_rounded,
            size: 14, color: Color(0xFF43A047)),
      ),
    ]),
  );
}