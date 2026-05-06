import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import 'main.dart';
import 'notification_service.dart';

class StepsScreen extends StatefulWidget {
  const StepsScreen({super.key});

  @override
  State<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends State<StepsScreen> with WidgetsBindingObserver {
  int _steps = 0;
  int _goal = 8000;
  int _recommendedGoal = 8000;
  double _distanceMeters = 0;
  int _kcal = 0;

  bool _loading = true;
  bool _sensorReady = false;
  bool _permissionDenied = false;
  bool _goalNotified = false;
  bool _highActivityNotified = false;
  bool _extremeActivityNotified = false;

  String _status = 'INITIALISING SENSOR...';

  int? _todayBaseline;
  int? _lastRawSensorSteps;
  String _todayKey = _dateKey(DateTime.now());
  StreamSubscription<StepCount>? _stepSub;

  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _history = [];

  static String _dateKey(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  static String _dateDisplay(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stepSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDayChange();
      _restartStepStream();
    }
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final fs = FirebaseFirestore.instance;
      final results = await Future.wait([
        fs.collection('users').doc(uid).get(),
        fs.collection('users').doc(uid).collection('dailySteps')
            .orderBy('date', descending: true).limit(7).get(),
        fs.collection('users').doc(uid).collection('stepGoal').doc('current').get(),
        fs.collection('users').doc(uid).collection('dailySteps').doc(_todayKey).get(),
      ]);

      if (!mounted) return;

      final userDoc = results[0] as DocumentSnapshot;
      final historySnap = results[1] as QuerySnapshot;
      final goalDoc = results[2] as DocumentSnapshot;
      final todayDoc = results[3] as DocumentSnapshot;

      if (userDoc.exists) {
        _userData = userDoc.data() as Map<String, dynamic>?;
        _recommendedGoal = _calcGoal(_userData);
      }

      _goal = goalDoc.exists && (goalDoc.data() as Map?)?.containsKey('goal') == true
          ? ((goalDoc.data() as Map)['goal'] as num).toInt()
          : _recommendedGoal;

      _history = historySnap.docs
          .map((d) => d.data() as Map<String, dynamic>)
          .toList();

      // If today's baseline does not exist yet, use the last saved raw sensor
      // value as the best available starting point. This helps after midnight
      // or after reinstalling without losing all sync behaviour.
      if (!todayDoc.exists && _history.isNotEmpty) {
        final previousRaw = (_history.first['rawSensorSteps'] as num?)?.toInt();
        if (previousRaw != null) _todayBaseline = previousRaw;
      }

      if (todayDoc.exists && todayDoc.data() != null) {
        final data = todayDoc.data() as Map<String, dynamic>;
        _todayBaseline = (data['baseline'] as num?)?.toInt();
        _steps = (data['steps'] as num?)?.toInt() ?? 0;
        _goalNotified = data['goalNotified'] == true;
        _highActivityNotified = data['highActivityNotified'] == true;
        _extremeActivityNotified = data['extremeActivityNotified'] == true;
        _recalculateStats();
      }
    } catch (e) {
      debugPrint('Steps load error: $e');
      _status = 'FAILED TO LOAD SAVED STEPS';
    }

    if (mounted) setState(() => _loading = false);
    await _startDailyStepTracking();
  }

  int _calcGoal(Map<String, dynamic>? d) {
    if (d == null) return 8000;

    final w = (d['weight'] as num?)?.toDouble();
    final h = (d['height'] as num?)?.toDouble();
    final bmi = (w != null && h != null && h > 0)
        ? w / ((h / 100) * (h / 100))
        : null;
    final act = d['activity'] ?? 'Moderately Active';

    int base = bmi == null
        ? 8000
        : bmi < 18.5
            ? 7000
            : bmi < 25
                ? 10000
                : bmi < 30
                    ? 9000
                    : 6000;

    if (act == 'Sedentary') base -= 1000;
    if (act == 'Very Active') base += 2000;
    return base.clamp(1000, 50000);
  }

  Future<void> _startDailyStepTracking() async {
    if (kIsWeb) {
      if (!mounted) return;
      setState(() {
        _sensorReady = false;
        _status = 'STEP TRACKING WORKS ON ANDROID APP ONLY';
      });
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      if (!mounted) return;
      setState(() {
        _sensorReady = false;
        _status = 'STEP SENSOR NOT SUPPORTED ON THIS PLATFORM';
      });
      return;
    }

    setState(() {
      _status = 'CHECKING ACTIVITY PERMISSION...';
      _permissionDenied = false;
    });

    if (defaultTargetPlatform == TargetPlatform.android) {
      final permission = await Permission.activityRecognition.request();
      if (!permission.isGranted) {
        if (!mounted) return;
        setState(() {
          _permissionDenied = true;
          _sensorReady = false;
          _status = 'PHYSICAL ACTIVITY PERMISSION REQUIRED';
        });
        return;
      }
    }

    await _restartStepStream();
  }

  Future<void> _restartStepStream() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
         defaultTargetPlatform != TargetPlatform.iOS)) {
      if (!mounted) return;
      setState(() => _status = 'STEP TRACKING WORKS ON ANDROID APP ONLY');
      return;
    }

    await _stepSub?.cancel();

    if (!mounted) return;
    setState(() => _status = 'AUTO-SYNCING WITH PHONE STEP SENSOR...');

    _stepSub = Pedometer.stepCountStream.listen(
      _onStepCount,
      onError: (error) {
        debugPrint('Pedometer error: $error');
        if (!mounted) return;
        setState(() {
          _sensorReady = false;
          _status = 'STEP SENSOR NOT AVAILABLE ON THIS DEVICE';
        });
      },
      cancelOnError: false,
    );
  }

  Future<void> _onStepCount(StepCount event) async {
    await _checkDayChange();

    final raw = event.steps;
    _lastRawSensorSteps = raw;

    // The sensor usually returns cumulative steps since last phone reboot.
    // Today's baseline lets us calculate only today's steps.
    if (_todayBaseline == null) {
      _todayBaseline = raw;
      await _saveToday(force: true);
    }

    // If phone reboots, the raw sensor can reset to a smaller number.
    if (_todayBaseline != null && raw < _todayBaseline!) {
      _todayBaseline = raw;
      _goalNotified = false;
      _highActivityNotified = false;
      _extremeActivityNotified = false;
      await _saveToday(force: true);
    }

    final todaySteps = (raw - (_todayBaseline ?? raw)).clamp(0, 1000000);

    if (!mounted) return;
    setState(() {
      _sensorReady = true;
      _status = 'AUTO TRACKING TODAY';
      _steps = todaySteps;
      _recalculateStats();
    });

    await _handleStepMilestones();
    await _saveToday();
  }

  Future<void> _handleStepMilestones() async {
    final realProgress = _goal > 0 ? _steps / _goal : 0.0;
    final veryHighSteps = _steps >= 25000 || realProgress >= 2.5;
    final extremeSteps = _steps >= 40000 || realProgress >= 4.0;

    if (_steps >= _goal && !_goalNotified) {
      _goalNotified = true;
      await NotificationService.stepGoalReached(_steps);
    }

    // These are sync-based notifications: if the app was closed, they trigger
    // when the app opens/resumes and reads the latest sensor value.
    if (extremeSteps && !_extremeActivityNotified) {
      _extremeActivityNotified = true;
      _highActivityNotified = true;
      await NotificationService.show(
        id: 14,
        title: 'Extreme Activity Alert ⚠️',
        body: 'Your step count is extremely high today. Hydrate, rest, and avoid overtraining.',
      );
    } else if (veryHighSteps && !_highActivityNotified) {
      _highActivityNotified = true;
      await NotificationService.show(
        id: 13,
        title: 'High Activity Warning ⚠️',
        body: 'You are far above your daily goal. Take rest and stop if you feel pain, dizziness, or unusual fatigue.',
      );
    }
  }

  Future<void> _checkDayChange() async {
    final nowKey = _dateKey(DateTime.now());
    if (nowKey == _todayKey) return;

    _todayKey = nowKey;
    _todayBaseline = _lastRawSensorSteps;
    _steps = 0;
    _distanceMeters = 0;
    _kcal = 0;
    _goalNotified = false;
    _highActivityNotified = false;
    _extremeActivityNotified = false;
    await _saveToday(force: true);
    await _reloadHistoryOnly();
  }

  void _recalculateStats() {
    final height = (_userData?['height'] as num?)?.toDouble();
    final weight = (_userData?['weight'] as num?)?.toDouble() ?? 70.0;

    final strideMeters = height != null && height > 0
        ? (height * 0.00415).clamp(0.55, 0.95)
        : 0.762;

    _distanceMeters = _steps * strideMeters;
    _kcal = (_distanceMeters * weight * 0.000539).round();
  }

  Future<void> _saveToday({bool force = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _todayBaseline == null) return;

    final now = DateTime.now();
    final entry = {
      'steps': _steps,
      'goal': _goal,
      'baseline': _todayBaseline,
      'rawSensorSteps': _lastRawSensorSteps,
      'distance': double.parse((_distanceMeters / 1000).toStringAsFixed(3)),
      'kcal': _kcal,
      'date': Timestamp.fromDate(DateTime(now.year, now.month, now.day)),
      'updatedAt': FieldValue.serverTimestamp(),
      'dateStr': _dateDisplay(now),
      'method': 'pedometer',
      'goalNotified': _goalNotified,
      'highActivityNotified': _highActivityNotified,
      'extremeActivityNotified': _extremeActivityNotified,
    };

    await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('dailySteps').doc(_todayKey)
        .set(entry, SetOptions(merge: true));

    final existingIndex = _history.indexWhere((h) => h['dateStr'] == entry['dateStr']);
    if (mounted) {
      setState(() {
        if (existingIndex >= 0) {
          _history[existingIndex] = entry;
        } else {
          _history.insert(0, entry);
        }
      });
    }
  }

  Future<void> _reloadHistoryOnly() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid)
          .collection('dailySteps').orderBy('date', descending: true).limit(7).get();
      if (mounted) {
        setState(() => _history = snap.docs.map((d) => d.data()).toList());
      }
    } catch (e) {
      debugPrint('Step history reload error: $e');
    }
  }

  Future<void> _manualSync() async {
    setState(() => _status = 'REFRESHING SENSOR...');
    await _restartStepStream();
    await _reloadHistoryOnly();
  }

  Future<void> _resetTodayBaseline() async {
    if (_lastRawSensorSteps == null) return;

    setState(() {
      _todayBaseline = _lastRawSensorSteps;
      _steps = 0;
      _distanceMeters = 0;
      _kcal = 0;
      _goalNotified = false;
      _highActivityNotified = false;
      _extremeActivityNotified = false;
      _status = 'TODAY RESET';
    });

    await _saveToday(force: true);
  }

  Future<void> _saveGoal(int g) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('stepGoal').doc('current')
          .set({'goal': g});
    }

    setState(() {
      _goal = g;
      if (_steps < _goal) _goalNotified = false;
      if (_steps < 25000 && (_goal == 0 || _steps / _goal < 2.5)) {
        _highActivityNotified = false;
      }
      if (_steps < 40000 && (_goal == 0 || _steps / _goal < 4.0)) {
        _extremeActivityNotified = false;
      }
    });

    await _handleStepMilestones();
    await _saveToday(force: true);
  }

  void _showGoalPicker() {
    int temp = _goal;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.accent, width: 1)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SET DAILY GOAL', style: GoogleFonts.pressStart2p(
                fontSize: 12, color: AppColors.accent)),
              const SizedBox(height: 6),
              Text('RECOMMENDED: $_recommendedGoal STEPS',
                style: GoogleFonts.pressStart2p(
                  fontSize: 7, color: AppColors.textSecondary)),
              const SizedBox(height: 24),
              Center(child: Text('$temp', style: GoogleFonts.pressStart2p(
                fontSize: 28, color: AppColors.accent,
                shadows: [Shadow(color: AppColors.accent, blurRadius: 12)]))),
              const SizedBox(height: 4),
              Center(child: Text('STEPS', style: GoogleFonts.pressStart2p(
                fontSize: 8, color: AppColors.textSecondary))),
              const SizedBox(height: 16),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: AppColors.accent,
                  inactiveTrackColor: AppColors.border,
                  thumbColor: AppColors.accent,
                  overlayColor: AppColors.accent.withOpacity(0.2),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: temp.toDouble(),
                  min: 1000,
                  max: 50000,
                  divisions: 98,
                  onChanged: (v) => setS(() => temp = v.round()),
                ),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('1K', style: GoogleFonts.pressStart2p(
                  fontSize: 7, color: AppColors.textMuted)),
                Text('50K', style: GoogleFonts.pressStart2p(
                  fontSize: 7, color: AppColors.textMuted)),
              ]),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _recommendedGoal,
                  3000,
                  5000,
                  7500,
                  10000,
                  15000,
                  20000,
                ].toSet().map((v) => GestureDetector(
                  onTap: () => setS(() => temp = v),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: temp == v ? AppColors.accent : AppColors.accentDim,
                      border: Border.all(color: AppColors.accent, width: 1),
                    ),
                    child: Text(
                      v == _recommendedGoal
                          ? 'REC ${_formatCompact(v)}'
                          : _formatCompact(v),
                      style: GoogleFonts.pressStart2p(
                        fontSize: 8,
                        color: temp == v ? AppColors.bg : AppColors.accent,
                      ),
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 24),
              _pixelBtn('SET GOAL', () {
                Navigator.pop(ctx);
                _saveGoal(temp);
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showResetConfirm() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('RESET TODAY?', style: GoogleFonts.pressStart2p(
          fontSize: 10, color: AppColors.accent)),
        content: Text(
          'This sets your current sensor count as today\'s new starting point. Use only if the step count looks wrong.',
          style: GoogleFonts.dmSans(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _resetTodayBaseline();
            },
            child: Text('Reset', style: GoogleFonts.dmSans(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  String _formatCompact(int v) {
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}K';
    }
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final realProgress = _goal > 0 ? _steps / _goal : 0.0;
    final barProgress = realProgress.clamp(0.0, 1.0);
    final pct = (realProgress * 100).toStringAsFixed(0);
    final goalReached = _steps >= _goal;
    final stepsLeft = goalReached ? 0 : _goal - _steps;
    final distKm = _distanceMeters / 1000;

    final veryHighSteps = _steps >= 25000 || realProgress >= 2.5;
    final extremeSteps = _steps >= 40000 || realProgress >= 4.0;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _loading
          ? Center(child: Text('LOADING...', style: GoogleFonts.pressStart2p(
              fontSize: 10, color: AppColors.accent)))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('DAILY STEPS', style: GoogleFonts.pressStart2p(
                              fontSize: 13,
                              color: AppColors.accent,
                              shadows: [Shadow(
                                color: AppColors.accent.withOpacity(0.5),
                                blurRadius: 8,
                              )],
                            )),
                            const SizedBox(height: 4),
                            Text(_status, style: GoogleFonts.pressStart2p(
                              fontSize: 7,
                              color: _permissionDenied ? AppColors.danger : AppColors.textSecondary,
                            )),
                          ],
                        ),
                        GestureDetector(
                          onTap: _showGoalPicker,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.accentDim,
                              border: Border.all(color: AppColors.accent, width: 1),
                            ),
                            child: Column(children: [
                              Text('DAILY GOAL', style: GoogleFonts.pressStart2p(
                                fontSize: 6, color: AppColors.textSecondary)),
                              const SizedBox(height: 4),
                              Text(_formatCompact(_goal), style: GoogleFonts.pressStart2p(
                                fontSize: 11, color: AppColors.accent)),
                            ]),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    Center(child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        border: Border.all(
                          color: extremeSteps
                              ? AppColors.danger
                              : veryHighSteps
                                  ? AppColors.warning
                                  : goalReached
                                      ? AppColors.accent
                                      : AppColors.accent.withOpacity(0.4),
                          width: 2,
                        ),
                        boxShadow: [BoxShadow(
                          color: (goalReached ? AppColors.accent : AppColors.neon2)
                              .withOpacity(goalReached ? 0.25 : 0.08),
                          blurRadius: 20,
                          spreadRadius: 2,
                        )],
                      ),
                      child: Column(children: [
                        Text('STEPS TODAY', style: GoogleFonts.pressStart2p(
                          fontSize: 8,
                          color: AppColors.textSecondary,
                          letterSpacing: 3,
                        )),
                        const SizedBox(height: 12),
                        FittedBox(child: Text('$_steps', style: GoogleFonts.pressStart2p(
                          fontSize: 40,
                          color: goalReached ? AppColors.accent : AppColors.neon2,
                          shadows: [Shadow(
                            color: (goalReached ? AppColors.accent : AppColors.neon2).withOpacity(0.8),
                            blurRadius: 16,
                          )],
                        ))),
                        const SizedBox(height: 8),
                        Text('DAILY GOAL: $_goal STEPS', style: GoogleFonts.pressStart2p(
                          fontSize: 7,
                          color: AppColors.textSecondary,
                        )),
                        const SizedBox(height: 14),
                        Container(
                          height: 16,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.accent.withOpacity(0.4), width: 1),
                          ),
                          child: Row(children: [
                            Expanded(
                              flex: (barProgress * 100).round(),
                              child: Container(color: goalReached ? AppColors.accent : AppColors.neon2),
                            ),
                            Expanded(
                              flex: 100 - (barProgress * 100).round(),
                              child: Container(color: AppColors.accentDim),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('$pct% OF GOAL', style: GoogleFonts.pressStart2p(
                              fontSize: 7, color: AppColors.textSecondary)),
                            Text(_sensorReady ? 'PEDOMETER' : 'WAITING', style: GoogleFonts.pressStart2p(
                              fontSize: 7,
                              color: _sensorReady ? AppColors.neon4 : AppColors.textMuted,
                            )),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _goalStatusPill(goalReached, stepsLeft, veryHighSteps, extremeSteps),
                      ]),
                    )),
                    const SizedBox(height: 16),

                    if (extremeSteps)
                      _activityWarningBox(
                        'EXTREME ACTIVITY ALERT',
                        'Your step count is extremely high today. Prioritize recovery, hydrate, and stop if you feel pain, dizziness, chest discomfort, or unusual fatigue.',
                        AppColors.danger,
                      )
                    else if (veryHighSteps)
                      _activityWarningBox(
                        'HIGH ACTIVITY WARNING',
                        'You are far above your daily goal. Take rest, hydrate, and avoid pushing more if your body feels tired.',
                        AppColors.warning,
                      ),
                    if (veryHighSteps || extremeSteps) const SizedBox(height: 16),

                    Row(children: [
                      Expanded(child: _statBox(
                        'DIST',
                        distKm >= 1 ? distKm.toStringAsFixed(2) : _distanceMeters.toStringAsFixed(0),
                        distKm >= 1 ? 'KM' : 'M',
                        AppColors.neon2,
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: _statBox('KCAL', '$_kcal', 'CAL', AppColors.neon4)),
                      const SizedBox(width: 8),
                      Expanded(child: _statBox('LEFT', '$stepsLeft', 'STEPS', AppColors.neon3)),
                    ]),
                    const SizedBox(height: 16),

                    if (_permissionDenied)
                      _infoBox(
                        'Permission needed',
                        'Enable Physical Activity permission from app settings, then tap refresh.',
                        AppColors.danger,
                      ),
                    if (_permissionDenied) const SizedBox(height: 16),

                    _pixelBtn(
                      '[ RESET TODAY IF WRONG ]',
                      _showResetConfirm,
                      color: AppColors.danger,
                    ),
                    const SizedBox(height: 24),

                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.accentDim,
                        border: Border.all(color: AppColors.accent.withOpacity(0.4), width: 1),
                      ),
                      child: Row(children: [
                        Text('>', style: GoogleFonts.pressStart2p(
                          fontSize: 10, color: AppColors.accent)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(
                          'RECOMMENDED FOR YOU: $_recommendedGoal STEPS/DAY',
                          style: GoogleFonts.pressStart2p(
                            fontSize: 7,
                            color: AppColors.textSecondary,
                            height: 1.8,
                          ),
                        )),
                      ]),
                    ),
                    const SizedBox(height: 24),

                    Text('RECENT DAYS', style: GoogleFonts.pressStart2p(
                      fontSize: 9, color: AppColors.accent)),
                    const SizedBox(height: 12),
                    _history.isEmpty ? _emptyHistory() : _historyWidget(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _goalStatusPill(bool goalReached, int stepsLeft, bool veryHigh, bool extreme) {
    String text;
    Color color;
    IconData icon;

    if (extreme) {
      text = 'EXTREME ACTIVITY — RECOVER NOW';
      color = AppColors.danger;
      icon = Icons.warning_rounded;
    } else if (veryHigh) {
      text = 'WAY ABOVE GOAL — REST + HYDRATE';
      color = AppColors.warning;
      icon = Icons.warning_amber_rounded;
    } else if (goalReached) {
      text = 'GOAL COMPLETE ✅';
      color = AppColors.accent;
      icon = Icons.check_circle_rounded;
    } else {
      text = '$stepsLeft STEPS LEFT';
      color = AppColors.neon2;
      icon = Icons.directions_walk_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Flexible(child: Text(text, textAlign: TextAlign.center, style: GoogleFonts.pressStart2p(
          fontSize: 7,
          color: color,
          height: 1.5,
        ))),
      ]),
    );
  }

  Widget _activityWarningBox(String title, String body, Color color) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      border: Border.all(color: color.withOpacity(0.55), width: 1),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.health_and_safety_outlined, color: color, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.pressStart2p(fontSize: 7, color: color)),
        const SizedBox(height: 8),
        Text(body, style: GoogleFonts.dmSans(
          fontSize: 12,
          color: AppColors.textSecondary,
          height: 1.45,
        )),
      ])),
    ]),
  );

  Widget _infoBox(String title, String body, Color color) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.card,
      border: Border.all(color: color.withOpacity(0.6), width: 1),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.info_outline_rounded, color: color, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(), style: GoogleFonts.pressStart2p(
          fontSize: 7,
          color: color,
        )),
        const SizedBox(height: 6),
        Text(body, style: GoogleFonts.dmSans(
          fontSize: 12,
          color: AppColors.textSecondary,
          height: 1.4,
        )),
      ])),
    ]),
  );

  Widget _statBox(String label, String val, String unit, Color col) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.card,
      border: Border.all(color: col.withOpacity(0.4), width: 1),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.pressStart2p(fontSize: 7, color: AppColors.textMuted)),
      const SizedBox(height: 8),
      FittedBox(child: Text(val, style: GoogleFonts.pressStart2p(
        fontSize: 14,
        color: col,
        shadows: [Shadow(color: col.withOpacity(0.5), blurRadius: 8)],
      ))),
      if (unit.isNotEmpty)
        Text(unit, style: GoogleFonts.pressStart2p(fontSize: 6, color: AppColors.textMuted)),
    ]),
  );

  Widget _emptyHistory() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(border: Border.all(color: AppColors.border, width: 1)),
    child: Center(child: Text(
      'NO DAILY LOGS YET\nWALK AROUND WITH THE APP INSTALLED',
      textAlign: TextAlign.center,
      style: GoogleFonts.pressStart2p(
        fontSize: 9,
        color: AppColors.textMuted,
        height: 2,
      ),
    )),
  );

  Widget _historyWidget() => Container(
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.accent.withOpacity(0.3), width: 1),
    ),
    child: Column(children: _history.take(7).toList().asMap().entries.map((e) {
      final entry = e.value;
      final visibleCount = _history.take(7).length;
      final isLast = e.key == visibleCount - 1;
      final steps = (entry['steps'] as num?)?.toInt() ?? 0;
      final entryGoal = (entry['goal'] as num?)?.toInt() ?? _goal;
      final goalMet = steps >= entryGoal;
      final distance = (entry['distance'] as num?)?.toDouble() ?? 0.0;
      final kcal = (entry['kcal'] as num?)?.toInt() ?? 0;
      final percent = entryGoal > 0 ? ((steps / entryGoal) * 100).round() : 0;

      return Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Text(goalMet ? '★' : '·', style: GoogleFonts.pressStart2p(
              fontSize: 12,
              color: goalMet ? AppColors.accent : AppColors.textMuted,
            )),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry['dateStr'] ?? '', style: GoogleFonts.pressStart2p(
                fontSize: 8,
                color: AppColors.textSecondary,
              )),
              const SizedBox(height: 4),
              Text('$percent%  ·  $kcal CAL  ·  ${distance.toStringAsFixed(2)} KM  ·  GOAL $entryGoal',
                style: GoogleFonts.pressStart2p(fontSize: 6, color: AppColors.textMuted)),
            ])),
            Text('$steps', style: GoogleFonts.pressStart2p(
              fontSize: 13,
              color: goalMet ? AppColors.accent : AppColors.neon2,
            )),
          ]),
        ),
        if (!isLast) Container(height: 1, color: AppColors.border),
      ]);
    }).toList()),
  );

  Widget _pixelBtn(String label, VoidCallback onTap, {Color? color}) {
    final col = color ?? AppColors.accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: col,
          boxShadow: [BoxShadow(
            color: col.withOpacity(0.4),
            blurRadius: 12,
            spreadRadius: 1,
          )],
        ),
        child: Center(child: Text(label, style: GoogleFonts.pressStart2p(
          fontSize: 9,
          color: AppColors.bg,
          letterSpacing: 1,
        ))),
      ),
    );
  }
}
