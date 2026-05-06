import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'main.dart';

class MentalHealthScreen extends StatefulWidget {
  const MentalHealthScreen({super.key});
  @override
  State<MentalHealthScreen> createState() => _MentalHealthScreenState();
}

class _MentalHealthScreenState extends State<MentalHealthScreen>
    with SingleTickerProviderStateMixin {
  int _section = 0; // 0=breathe 1=journal 2=sleep 3=gratitude
  bool _loading = true;
  Map<String, dynamic>? _todayData;

  // Breathing
  bool _breathing = false;
  int _breathDuration = 4; // minutes
  String _breathPhase = 'Inhale';
  double _breathScale = 0.4;
  Timer? _breathTimer;
  int _breathSecondsLeft = 0;
  String _breathPattern = '4-7-8';

  // Journal
  final _journalCtrl = TextEditingController();
  int _stressLevel = 3;

  // Gratitude
  final _gratitudeCtrl = TextEditingController();

  // Sleep
  double _sleepHours = 7;

  // Tips
  final _stressTips = [
    {'e': '🧘', 't': 'Take 5 deep breaths before reacting to any stressful situation.'},
    {'e': '🚶', 't': 'A 10-minute walk outdoors can reduce cortisol by up to 25%.'},
    {'e': '📵', 't': 'Put your phone on DND for 30 minutes. Your brain needs silence.'},
    {'e': '💧', 't': 'Dehydration amplifies anxiety. Drink water before worrying.'},
    {'e': '📝', 't': 'Write down what\'s bothering you. Getting it out helps.'},
    {'e': '🎵', 't': 'Listen to calming music for 10 minutes. It lowers heart rate.'},
    {'e': '🤝', 't': 'Talk to someone you trust. Don\'t carry it alone.'},
    {'e': '😴', 't': 'Sleep deprivation makes everything feel worse. Prioritize rest.'},
    {'e': '🌿', 't': 'Spend 5 minutes near a plant or tree. Nature heals.'},
    {'e': '🎯', 't': 'Focus on one thing at a time. Multitasking increases stress.'},
  ];

  String get _dateKey {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  @override
  void initState() {
    super.initState();
    _loadToday();
  }

  @override
  void dispose() {
    _breathTimer?.cancel();
    _journalCtrl.dispose();
    _gratitudeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadToday() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { if (mounted) setState(() => _loading = false); return; }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('mentalHealth').doc(_dateKey).get();
      if (doc.exists && doc.data() != null) {
        _todayData = doc.data();
        _journalCtrl.text = _todayData?['journalEntry'] ?? '';
        _gratitudeCtrl.text = _todayData?['gratitude'] ?? '';
        _stressLevel = (_todayData?['stressLevel'] as num?)?.toInt() ?? 3;
        _sleepHours = (_todayData?['sleepHours'] as num?)?.toDouble() ?? 7;
      }
    } catch (e) { debugPrint('Mental health load: $e'); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final data = {
      'journalEntry': _journalCtrl.text.trim(),
      'gratitude': _gratitudeCtrl.text.trim(),
      'stressLevel': _stressLevel,
      'sleepHours': _sleepHours,
      'breathingMinutes': (_todayData?['breathingMinutes'] as num?)?.toInt() ?? 0,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('mentalHealth').doc(_dateKey)
        .set(data, SetOptions(merge: true));
    _todayData = data;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Saved ✓', style: GoogleFonts.dmSans()),
        backgroundColor: AppColors.success.withOpacity(0.9),
        duration: const Duration(seconds: 1)));
    }
  }

  void _startBreathing() {
    final totalSec = _breathDuration * 60;
    setState(() {
      _breathing = true;
      _breathSecondsLeft = totalSec;
      _breathPhase = 'Inhale';
      _breathScale = 0.4;
    });

    int cyclePos = 0;
    List<int> phaseDurations;
    List<String> phaseNames;

    if (_breathPattern == '4-7-8') {
      phaseDurations = [4, 7, 8];
      phaseNames = ['Inhale', 'Hold', 'Exhale'];
    } else {
      phaseDurations = [4, 4, 4, 4];
      phaseNames = ['Inhale', 'Hold', 'Exhale', 'Hold'];
    }

    int phaseIdx = 0;
    int phaseCounter = 0;

    _breathTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_breathSecondsLeft <= 0) {
        t.cancel();
        _onBreathingComplete();
        return;
      }
      setState(() {
        _breathSecondsLeft--;
        phaseCounter++;
        if (phaseCounter >= phaseDurations[phaseIdx]) {
          phaseCounter = 0;
          phaseIdx = (phaseIdx + 1) % phaseNames.length;
          _breathPhase = phaseNames[phaseIdx];
        }
        // Scale circle based on phase
        if (_breathPhase == 'Inhale') {
          _breathScale = 0.4 + (phaseCounter / phaseDurations[phaseIdx]) * 0.6;
        } else if (_breathPhase == 'Exhale') {
          _breathScale = 1.0 - (phaseCounter / phaseDurations[phaseIdx]) * 0.6;
        }
      });
    });
  }

  void _stopBreathing() {
    _breathTimer?.cancel();
    setState(() { _breathing = false; _breathScale = 0.4; });
  }

  Future<void> _onBreathingComplete() async {
    _breathTimer?.cancel();
    setState(() { _breathing = false; _breathScale = 0.4; });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('mentalHealth').doc(_dateKey)
        .set({
      'breathingMinutes': FieldValue.increment(_breathDuration),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$_breathDuration min breathing done 🧘', style: GoogleFonts.dmSans()),
        backgroundColor: AppColors.success.withOpacity(0.9)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context)),
        title: Text('MIND & WELLNESS', style: GoogleFonts.pressStart2p(
          fontSize: 10, color: AppColors.accent)),
      ),
      body: _loading
          ? Center(child: Text('LOADING...', style: GoogleFonts.pressStart2p(
              fontSize: 10, color: AppColors.accent)))
          : SafeArea(child: Column(children: [
              // Section tabs
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _tabBtn(0, '🧘', 'Breathe'),
                    _tabBtn(1, '📝', 'Journal'),
                    _tabBtn(2, '😴', 'Sleep'),
                    _tabBtn(3, '🙏', 'Gratitude'),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                child: _section == 0 ? _breatheSection()
                    : _section == 1 ? _journalSection()
                    : _section == 2 ? _sleepSection()
                    : _gratitudeSection(),
              )),
            ])),
    );
  }

  Widget _tabBtn(int idx, String emoji, String label) {
    final sel = _section == idx;
    return GestureDetector(
      onTap: () => setState(() => _section = idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? AppColors.accent : AppColors.card,
          border: Border.all(color: sel ? AppColors.accent : AppColors.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.dmSans(
            fontSize: 13, color: sel ? AppColors.bg : AppColors.textSecondary,
            fontWeight: sel ? FontWeight.w700 : FontWeight.normal)),
        ]),
      ),
    );
  }

  // ─── BREATHE ──────────────────────────────────────────────────────────
  Widget _breatheSection() {
    final mins = _breathSecondsLeft ~/ 60;
    final secs = _breathSecondsLeft % 60;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('BREATHING EXERCISE', style: GoogleFonts.pressStart2p(
        fontSize: 8, color: AppColors.accent)),
      const SizedBox(height: 6),
      Text('Focus on the circle. Breathe with it.',
        style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
      const SizedBox(height: 24),

      // Pattern selector
      if (!_breathing) ...[
        Row(children: ['4-7-8', 'Box'].map((p) {
          final sel = _breathPattern == (p == 'Box' ? 'box' : '4-7-8');
          final val = p == 'Box' ? 'box' : '4-7-8';
          return Expanded(child: GestureDetector(
            onTap: () => setState(() => _breathPattern = val),
            child: Container(
              margin: EdgeInsets.only(right: p == '4-7-8' ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _breathPattern == val ? AppColors.accentDim : AppColors.card,
                border: Border.all(
                  color: _breathPattern == val ? AppColors.accent : AppColors.border,
                  width: _breathPattern == val ? 2 : 1)),
              child: Center(child: Text(
                p == 'Box' ? '□ Box (4-4-4-4)' : '🌊 4-7-8',
                style: GoogleFonts.dmSans(fontSize: 13,
                  color: _breathPattern == val ? AppColors.accent : AppColors.textSecondary,
                  fontWeight: _breathPattern == val ? FontWeight.w700 : FontWeight.normal))))));
        }).toList()),
        const SizedBox(height: 12),
        Row(children: [2, 5, 10].map((d) {
          final sel = _breathDuration == d;
          return Expanded(child: GestureDetector(
            onTap: () => setState(() => _breathDuration = d),
            child: Container(
              margin: EdgeInsets.only(right: d != 10 ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: sel ? AppColors.accentDim : AppColors.card,
                border: Border.all(color: sel ? AppColors.accent : AppColors.border)),
              child: Center(child: Text('$d min', style: GoogleFonts.dmSans(
                fontSize: 13, color: sel ? AppColors.accent : AppColors.textSecondary,
                fontWeight: sel ? FontWeight.w700 : FontWeight.normal))))));
        }).toList()),
        const SizedBox(height: 24),
      ],

      // Breathing circle
      Center(child: AnimatedContainer(
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
        width: 180 * _breathScale + 40,
        height: 180 * _breathScale + 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.accent.withOpacity(0.08),
          border: Border.all(color: AppColors.accent.withOpacity(0.5), width: 3),
          boxShadow: [BoxShadow(
            color: AppColors.accent.withOpacity(_breathing ? 0.3 : 0.1),
            blurRadius: _breathing ? 40 : 10, spreadRadius: _breathing ? 8 : 0)]),
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_breathing ? _breathPhase : 'Ready',
            style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w700,
              color: AppColors.accent)),
          if (_breathing) ...[
            const SizedBox(height: 4),
            Text('$mins:${secs.toString().padLeft(2, '0')}',
              style: GoogleFonts.pressStart2p(fontSize: 10, color: AppColors.textMuted)),
          ],
        ])),
      )),
      const SizedBox(height: 24),

      // Start/stop button
      GestureDetector(
        onTap: _breathing ? _stopBreathing : _startBreathing,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _breathing ? AppColors.danger : AppColors.accent,
            boxShadow: [BoxShadow(
              color: (_breathing ? AppColors.danger : AppColors.accent).withOpacity(0.3),
              blurRadius: 10)]),
          child: Center(child: Text(
            _breathing ? 'STOP' : 'START BREATHING',
            style: GoogleFonts.pressStart2p(fontSize: 9, color: AppColors.bg))),
        ),
      ),
      const SizedBox(height: 20),

      // Tips
      Text('STRESS MANAGEMENT', style: GoogleFonts.pressStart2p(
        fontSize: 8, color: AppColors.accent)),
      const SizedBox(height: 10),
      ..._getTodayTips().map((t) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card, border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Text(t['e']!, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(t['t']!, style: GoogleFonts.dmSans(
            fontSize: 13, color: AppColors.textSecondary, height: 1.4))),
        ]))),
    ]);
  }

  List<Map<String, String>> _getTodayTips() {
    final seed = DateTime.now().day + DateTime.now().month * 31;
    final rng = Random(seed);
    final shuffled = List<Map<String, String>>.from(_stressTips)..shuffle(rng);
    return shuffled.take(3).toList();
  }

  // ─── JOURNAL ──────────────────────────────────────────────────────────
  Widget _journalSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('MOOD JOURNAL', style: GoogleFonts.pressStart2p(
      fontSize: 8, color: AppColors.accent)),
    const SizedBox(height: 6),
    Text('How are you feeling right now? No judgement.',
      style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
    const SizedBox(height: 20),
    Text('STRESS LEVEL', style: GoogleFonts.pressStart2p(
      fontSize: 7, color: AppColors.textMuted)),
    const SizedBox(height: 8),
    Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(5, (i) {
        final level = i + 1;
        final labels = ['Very Low', 'Low', 'Moderate', 'High', 'Very High'];
        final colors = [AppColors.success, AppColors.neon3, AppColors.warning,
            AppColors.neon4, AppColors.danger];
        final sel = _stressLevel == level;
        return GestureDetector(
          onTap: () => setState(() => _stressLevel = level),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 54, height: 54,
            decoration: BoxDecoration(
              color: sel ? colors[i].withOpacity(0.15) : AppColors.card,
              border: Border.all(color: sel ? colors[i] : AppColors.border,
                width: sel ? 2 : 1)),
            child: Center(child: Text('$level',
              style: GoogleFonts.pressStart2p(fontSize: 14,
                color: sel ? colors[i] : AppColors.textMuted)))));
      })),
    const SizedBox(height: 20),
    Text('JOURNAL ENTRY', style: GoogleFonts.pressStart2p(
      fontSize: 7, color: AppColors.textMuted)),
    const SizedBox(height: 8),
    Container(
      decoration: BoxDecoration(
        color: AppColors.card, border: Border.all(color: AppColors.border)),
      child: TextField(
        controller: _journalCtrl, maxLines: 5, maxLength: 500,
        style: GoogleFonts.dmSans(color: AppColors.textPrimary, fontSize: 14, height: 1.5),
        cursorColor: AppColors.accent,
        decoration: InputDecoration(
          hintText: 'Write whatever comes to mind...',
          hintStyle: GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
          counterStyle: GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 10)))),
    const SizedBox(height: 20),
    _saveButton(),
  ]);

  // ─── SLEEP ────────────────────────────────────────────────────────────
  Widget _sleepSection() {
    final sleepColor = _sleepHours >= 7 ? AppColors.success
        : _sleepHours >= 5 ? AppColors.warning : AppColors.danger;
    final sleepLabel = _sleepHours >= 8 ? 'Great sleep!'
        : _sleepHours >= 7 ? 'Good enough'
        : _sleepHours >= 5 ? 'Needs improvement'
        : 'Sleep deprived';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('SLEEP TRACKER', style: GoogleFonts.pressStart2p(
        fontSize: 8, color: AppColors.accent)),
      const SizedBox(height: 6),
      Text('How many hours did you sleep last night?',
        style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
      const SizedBox(height: 24),
      Center(child: Column(children: [
        Text('${_sleepHours.toStringAsFixed(1)}', style: GoogleFonts.pressStart2p(
          fontSize: 36, color: sleepColor,
          shadows: [Shadow(color: sleepColor.withOpacity(0.5), blurRadius: 12)])),
        Text('HOURS', style: GoogleFonts.pressStart2p(
          fontSize: 8, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Text(sleepLabel, style: GoogleFonts.dmSans(
          fontSize: 13, color: sleepColor, fontWeight: FontWeight.w600)),
      ])),
      const SizedBox(height: 20),
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor: sleepColor, inactiveTrackColor: AppColors.border,
          thumbColor: sleepColor, overlayColor: sleepColor.withOpacity(0.2),
          trackHeight: 6),
        child: Slider(
          value: _sleepHours, min: 0, max: 12, divisions: 24,
          onChanged: (v) => setState(() => _sleepHours = v))),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('0h', style: GoogleFonts.pressStart2p(fontSize: 7, color: AppColors.textMuted)),
        Text('12h', style: GoogleFonts.pressStart2p(fontSize: 7, color: AppColors.textMuted)),
      ]),
      const SizedBox(height: 20),
      // Sleep tips
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card, border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.lightbulb_outline_rounded, color: AppColors.accent, size: 14),
            const SizedBox(width: 6),
            Text('SLEEP TIPS', style: GoogleFonts.pressStart2p(
              fontSize: 7, color: AppColors.accent)),
          ]),
          const SizedBox(height: 10),
          _tipItem('🌙', 'Go to bed and wake up at the same time daily.'),
          _tipItem('📱', 'No screens 30 minutes before bed.'),
          _tipItem('☕', 'Avoid caffeine after 2 PM.'),
          _tipItem('🛏️', 'Keep your room cool, dark, and quiet.'),
        ])),
      const SizedBox(height: 20),
      _saveButton(),
    ]);
  }

  Widget _tipItem(String emoji, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: GoogleFonts.dmSans(
        fontSize: 12, color: AppColors.textSecondary, height: 1.4))),
    ]));

  // ─── GRATITUDE ────────────────────────────────────────────────────────
  Widget _gratitudeSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('DAILY GRATITUDE', style: GoogleFonts.pressStart2p(
      fontSize: 8, color: AppColors.accent)),
    const SizedBox(height: 6),
    Text('What\'s one good thing about today?',
      style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
    const SizedBox(height: 24),
    Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.accent.withOpacity(0.3))),
      child: Column(children: [
        const Text('🙏', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bg, border: Border.all(color: AppColors.border)),
          child: TextField(
            controller: _gratitudeCtrl, maxLines: 3, maxLength: 200,
            style: GoogleFonts.dmSans(color: AppColors.textPrimary, fontSize: 15, height: 1.5),
            cursorColor: AppColors.accent,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: 'I\'m grateful for...',
              hintStyle: GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 15),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
              counterStyle: GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 10)))),
      ])),
    const SizedBox(height: 20),
    Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.06),
        border: Border.all(color: AppColors.success.withOpacity(0.2))),
      child: Row(children: [
        const Icon(Icons.favorite_rounded, color: AppColors.success, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(
          'Gratitude rewires your brain for positivity. Even 1 line a day makes a difference.',
          style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.success, height: 1.4))),
      ])),
    const SizedBox(height: 20),
    _saveButton(),
  ]);

  Widget _saveButton() => GestureDetector(
    onTap: _saveData,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.accent,
        boxShadow: [BoxShadow(color: AppColors.accent.withOpacity(0.3), blurRadius: 10)]),
      child: Center(child: Text('SAVE', style: GoogleFonts.pressStart2p(
        fontSize: 9, color: AppColors.bg, letterSpacing: 1))),
    ));
}
