import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'main.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _loading = true;

  // Aggregated data
  List<Map<String, dynamic>> _checkins = [];
  List<Map<String, dynamic>> _stepDays = [];
  List<Map<String, dynamic>> _weightLog = [];
  int _totalXp = 0;
  int _completedQuests = 0;
  List<String> _completedQuestIds = [];

  // Computed metrics
  int _currentStreak = 0;
  int _longestStreak = 0;
  int _consistencyScore = 0;
  int _weekSteps = 0;
  int _lastWeekSteps = 0;
  int _weekCalories = 0;
  int _weekQuests = 0;
  int _highestStepsDay = 0;
  int _bestWeekXp = 0;
  double _dietAdherence = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final fs = FirebaseFirestore.instance;
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));

      final results = await Future.wait([
        fs.collection('users').doc(uid).collection('checkins')
            .orderBy(FieldPath.documentId, descending: true).limit(30).get(),
        fs.collection('users').doc(uid).collection('dailySteps')
            .orderBy('date', descending: true).limit(30).get(),
        fs.collection('users').doc(uid).collection('weightLog')
            .orderBy('date', descending: true).limit(8).get(),
        fs.collection('users').doc(uid).collection('quests').doc('status').get(),
      ]);

      final checkinSnap = results[0] as QuerySnapshot;
      final stepsSnap = results[1] as QuerySnapshot;
      final weightSnap = results[2] as QuerySnapshot;
      final questDoc = results[3] as DocumentSnapshot;

      _checkins = checkinSnap.docs.map((d) => {...d.data() as Map<String, dynamic>, 'docId': d.id}).toList();
      _stepDays = stepsSnap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
      _weightLog = weightSnap.docs.map((d) => d.data() as Map<String, dynamic>).toList();

      if (questDoc.exists && questDoc.data() != null) {
        final qd = questDoc.data() as Map<String, dynamic>;
        _totalXp = (qd['totalXp'] as num?)?.toInt() ?? 0;
        _completedQuestIds = List<String>.from(qd['completedIds'] ?? []);
        _completedQuests = _completedQuestIds.length;
      }

      _computeMetrics(now);
    } catch (e) {
      debugPrint('Analytics load: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _computeMetrics(DateTime now) {
    // --- Streaks ---
    _currentStreak = 0;
    _longestStreak = 0;
    int tempStreak = 0;
    for (int i = 0; i < 30; i++) {
      final d = now.subtract(Duration(days: i));
      final key = '${d.year}-${d.month}-${d.day}';
      final hasCheckin = _checkins.any((c) => c['docId'] == key);
      if (hasCheckin) {
        tempStreak++;
        if (i == _currentStreak) _currentStreak = tempStreak;
        if (tempStreak > _longestStreak) _longestStreak = tempStreak;
      } else {
        tempStreak = 0;
      }
    }

    // --- Week steps & last week ---
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final lastWeekStart = weekStart.subtract(const Duration(days: 7));
    _weekSteps = 0;
    _lastWeekSteps = 0;
    _weekCalories = 0;
    _highestStepsDay = 0;

    for (final s in _stepDays) {
      final steps = (s['steps'] as num?)?.toInt() ?? 0;
      final kcal = (s['kcal'] as num?)?.toInt() ?? 0;
      if (steps > _highestStepsDay) _highestStepsDay = steps;

      final ts = s['date'];
      DateTime? entryDate;
      if (ts is Timestamp) entryDate = ts.toDate();
      if (entryDate != null) {
        if (!entryDate.isBefore(weekStart)) {
          _weekSteps += steps;
          _weekCalories += kcal;
        } else if (!entryDate.isBefore(lastWeekStart)) {
          _lastWeekSteps += steps;
        }
      }
    }

    // --- Diet adherence ---
    int dietDays = 0;
    for (final c in _checkins) {
      if (c['ateDiet'] == true) dietDays++;
    }
    _dietAdherence = _checkins.isEmpty ? 0 : (dietDays / _checkins.length * 100);

    // --- Consistency score ---
    int goalMetDays = 0;
    for (final s in _stepDays) {
      final steps = (s['steps'] as num?)?.toInt() ?? 0;
      final goal = (s['goal'] as num?)?.toInt() ?? 8000;
      if (steps >= goal) goalMetDays++;
    }
    final checkinRate = _checkins.length / 30.0;
    final goalRate = _stepDays.isEmpty ? 0.0 : goalMetDays / _stepDays.length;
    final dietRate = _dietAdherence / 100;
    _consistencyScore = ((checkinRate * 40 + goalRate * 40 + dietRate * 20)).round().clamp(0, 100);

    // --- Week quests (approximate from total) ---
    _weekQuests = _completedQuests; // simplified
    _bestWeekXp = _totalXp; // simplified
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _loading
          ? Center(child: Text('LOADING...', style: GoogleFonts.pressStart2p(
              fontSize: 10, color: AppColors.accent)))
          : SafeArea(child: CustomScrollView(slivers: [
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('ANALYTICS', style: GoogleFonts.pressStart2p(
                    fontSize: 13, color: AppColors.accent,
                    shadows: [Shadow(color: AppColors.accent, blurRadius: 8)])),
                  const SizedBox(height: 4),
                  Text('YOUR FITNESS JOURNEY IN NUMBERS',
                    style: GoogleFonts.pressStart2p(fontSize: 6, color: AppColors.textSecondary)),
                  const SizedBox(height: 20),

                  // Weekly Summary
                  _weeklySummary(),
                  const SizedBox(height: 16),

                  // Consistency Score
                  _consistencyCard(),
                  const SizedBox(height: 16),

                  // Mood Timeline
                  _sectionLabel('MOOD TRACKER'),
                  const SizedBox(height: 10),
                  _moodTimeline(),
                  const SizedBox(height: 16),

                  // Activity Heatmap
                  _sectionLabel('30-DAY ACTIVITY'),
                  const SizedBox(height: 10),
                  _activityHeatmap(),
                  const SizedBox(height: 16),

                  // Weight Trend
                  if (_weightLog.isNotEmpty) ...[
                    _sectionLabel('WEIGHT TREND'),
                    const SizedBox(height: 10),
                    _weightTrend(),
                    const SizedBox(height: 16),
                  ],

                  // Personal Records
                  _sectionLabel('PERSONAL RECORDS'),
                  const SizedBox(height: 10),
                  _personalRecords(),
                  const SizedBox(height: 30),
                ]),
              )),
            ])),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
    style: GoogleFonts.pressStart2p(fontSize: 8, color: AppColors.accent));

  Widget _weeklySummary() {
    final stepsDiff = _weekSteps - _lastWeekSteps;
    final stepsUp = stepsDiff >= 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.accentDim, AppColors.accent.withOpacity(0.08)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: AppColors.accent.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.calendar_today_rounded, color: AppColors.accent, size: 14),
          const SizedBox(width: 8),
          Text('THIS WEEK', style: GoogleFonts.pressStart2p(
            fontSize: 8, color: AppColors.accent)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _summaryTile('STEPS', _formatNum(_weekSteps),
            '${stepsUp ? '↑' : '↓'} ${_formatNum(stepsDiff.abs())}',
            stepsUp ? AppColors.success : AppColors.danger)),
          const SizedBox(width: 8),
          Expanded(child: _summaryTile('CALORIES', '${_weekCalories}', 'kcal burned', AppColors.warning)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _summaryTile('QUESTS', '$_completedQuests', 'total done', AppColors.neon2)),
          const SizedBox(width: 8),
          Expanded(child: _summaryTile('STREAK', '$_currentStreak', 'day${_currentStreak == 1 ? '' : 's'}', AppColors.neon3)),
        ]),
      ]),
    );
  }

  Widget _summaryTile(String label, String val, String sub, Color col) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.card, border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.pressStart2p(fontSize: 6, color: AppColors.textMuted)),
      const SizedBox(height: 6),
      Text(val, style: GoogleFonts.pressStart2p(fontSize: 16, color: col,
        shadows: [Shadow(color: col.withOpacity(0.5), blurRadius: 6)])),
      const SizedBox(height: 2),
      Text(sub, style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.textMuted)),
    ]));

  Widget _consistencyCard() {
    final col = _consistencyScore >= 80 ? AppColors.success
        : _consistencyScore >= 50 ? AppColors.warning : AppColors.danger;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: col.withOpacity(0.06),
        border: Border.all(color: col.withOpacity(0.3))),
      child: Row(children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: col.withOpacity(0.1),
            border: Border.all(color: col, width: 3)),
          child: Center(child: Text('$_consistencyScore',
            style: GoogleFonts.pressStart2p(fontSize: 18, color: col)))),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CONSISTENCY SCORE', style: GoogleFonts.pressStart2p(
            fontSize: 8, color: col)),
          const SizedBox(height: 6),
          Text(
            _consistencyScore >= 80 ? 'Outstanding! You\'re crushing it.'
            : _consistencyScore >= 50 ? 'Good progress. Keep pushing!'
            : 'Getting started. Every day counts.',
            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
          const SizedBox(height: 6),
          Row(children: [
            _miniStat('Check-ins', '${_checkins.length}/30'),
            const SizedBox(width: 12),
            _miniStat('Diet', '${_dietAdherence.toStringAsFixed(0)}%'),
            const SizedBox(width: 12),
            _miniStat('Streak', '$_longestStreak best'),
          ]),
        ])),
      ]),
    );
  }

  Widget _miniStat(String label, String val) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(val, style: GoogleFonts.dmSans(fontSize: 12,
        fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      Text(label, style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.textMuted)),
    ]);

  Widget _moodTimeline() {
    final now = DateTime.now();
    final last7 = <Map<String, dynamic>?>[];
    for (int i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = '${d.year}-${d.month}-${d.day}';
      final match = _checkins.where((c) => c['docId'] == key);
      last7.add(match.isNotEmpty ? match.first : null);
    }

    // Simple insight
    int workoutMoodUp = 0, workoutMoodDown = 0;
    for (final c in _checkins) {
      final mood = c['mood'] as String? ?? '';
      final worked = c['workedOut'] == true;
      final good = mood == '🔥' || mood == '🙂';
      if (worked && good) workoutMoodUp++;
      if (!worked && !good) workoutMoodDown++;
    }

    String insight = '';
    if (workoutMoodUp > workoutMoodDown && workoutMoodUp > 2) {
      insight = '💡 You feel better on days you work out!';
    } else if (_checkins.isNotEmpty) {
      insight = '💡 Keep checking in to see mood patterns.';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card, border: Border.all(color: AppColors.border)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(7, (i) {
            final d = now.subtract(Duration(days: 6 - i));
            final dayLabel = ['M','T','W','T','F','S','S'][d.weekday - 1];
            final entry = last7[i];
            final mood = entry?['mood'] as String? ?? '·';
            return Column(children: [
              Text(dayLabel, style: GoogleFonts.pressStart2p(
                fontSize: 7, color: AppColors.textMuted)),
              const SizedBox(height: 6),
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: entry != null ? AppColors.accentDim : AppColors.bg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: entry != null ? AppColors.accent.withOpacity(0.4) : AppColors.border)),
                child: Center(child: Text(mood, style: TextStyle(
                  fontSize: entry != null ? 18 : 12,
                  color: AppColors.textMuted)))),
            ]);
          })),
        if (insight.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: AppColors.bg,
            child: Text(insight, style: GoogleFonts.dmSans(
              fontSize: 12, color: AppColors.textSecondary, fontStyle: FontStyle.italic))),
        ],
      ]),
    );
  }

  Widget _activityHeatmap() {
    final now = DateTime.now();
    final cells = <Widget>[];
    for (int i = 29; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final dateStr = '${d.day}/${d.month}/${d.year}';
      final stepEntry = _stepDays.where((s) => s['dateStr'] == dateStr);
      double intensity = 0;
      if (stepEntry.isNotEmpty) {
        final steps = (stepEntry.first['steps'] as num?)?.toInt() ?? 0;
        final goal = (stepEntry.first['goal'] as num?)?.toInt() ?? 8000;
        intensity = goal > 0 ? (steps / goal).clamp(0.0, 1.5) : 0;
      }
      final checkinKey = '${d.year}-${d.month}-${d.day}';
      final hasCheckin = _checkins.any((c) => c['docId'] == checkinKey);
      if (hasCheckin && intensity < 0.3) intensity = 0.3;

      Color cellColor;
      if (intensity <= 0) {
        cellColor = AppColors.bg;
      } else if (intensity < 0.5) {
        cellColor = AppColors.accent.withOpacity(0.15);
      } else if (intensity < 0.8) {
        cellColor = AppColors.accent.withOpacity(0.35);
      } else if (intensity < 1.0) {
        cellColor = AppColors.accent.withOpacity(0.55);
      } else {
        cellColor = AppColors.accent.withOpacity(0.8);
      }

      cells.add(Tooltip(
        message: '${d.day}/${d.month}: ${stepEntry.isNotEmpty ? stepEntry.first['steps'] : 0} steps',
        child: Container(
          decoration: BoxDecoration(
            color: cellColor,
            border: Border.all(color: AppColors.border, width: 0.5)),
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card, border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GridView.count(
          crossAxisCount: 10, shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 3, crossAxisSpacing: 3,
          children: cells),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text('Less', style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.textMuted)),
          const SizedBox(width: 6),
          ...List.generate(5, (i) => Container(
            width: 12, height: 12,
            margin: const EdgeInsets.only(right: 3),
            color: i == 0 ? AppColors.bg
                : AppColors.accent.withOpacity(0.15 + i * 0.18))),
          Text('More', style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.textMuted)),
        ]),
      ]),
    );
  }

  Widget _weightTrend() {
    final entries = _weightLog.reversed.toList();
    if (entries.isEmpty) return const SizedBox();
    final weights = entries.map((e) => (e['weight'] as num).toDouble()).toList();
    final minW = weights.reduce(min) - 1;
    final maxW = weights.reduce(max) + 1;
    final range = maxW - minW;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card, border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 100,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end,
            children: entries.asMap().entries.map((e) {
              final w = (e.value['weight'] as num).toDouble();
              final h = range > 0 ? ((w - minW) / range * 80).clamp(8.0, 80.0) : 40.0;
              final isLast = e.key == entries.length - 1;
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('${w.toStringAsFixed(1)}',
                    style: GoogleFonts.dmSans(fontSize: 8, color: AppColors.textMuted)),
                  const SizedBox(height: 2),
                  Container(
                    height: h,
                    decoration: BoxDecoration(
                      color: isLast ? AppColors.accent : AppColors.accent.withOpacity(0.4),
                      border: Border.all(color: AppColors.accent.withOpacity(0.6), width: 0.5))),
                ])));
            }).toList()),
        ),
        const SizedBox(height: 8),
        if (weights.length >= 2) ...[
          Builder(builder: (_) {
            final diff = weights.last - weights.first;
            return Container(
            padding: const EdgeInsets.all(10),
            color: AppColors.bg,
            child: Row(children: [
              Icon(diff <= 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                color: diff <= 0 ? AppColors.success : AppColors.warning, size: 16),
              const SizedBox(width: 8),
              Text('${diff > 0 ? '+' : ''}${diff.toStringAsFixed(1)} kg overall',
                style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary)),
            ]));
          }),
        ],
      ]),
    );
  }

  Widget _personalRecords() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card, border: Border.all(color: AppColors.border)),
      child: Column(children: [
        _recordRow('🏃', 'Highest Steps', _formatNum(_highestStepsDay), AppColors.neon2),
        _divider(),
        _recordRow('🔥', 'Longest Streak', '$_longestStreak days', AppColors.neon3),
        _divider(),
        _recordRow('⚡', 'Total XP', '$_totalXp pts', AppColors.accent),
        _divider(),
        _recordRow('🏆', 'Quests Done', '$_completedQuests', AppColors.success),
      ]),
    );
  }

  Widget _recordRow(String emoji, String label, String val, Color col) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 20)),
      const SizedBox(width: 12),
      Expanded(child: Text(label, style: GoogleFonts.dmSans(
        fontSize: 14, color: AppColors.textSecondary))),
      Text(val, style: GoogleFonts.pressStart2p(fontSize: 10, color: col)),
    ]));

  Widget _divider() => Container(height: 1, color: AppColors.border);

  String _formatNum(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}
