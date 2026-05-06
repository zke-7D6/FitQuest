import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'main.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});
  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  final _ageCtrl    = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  String _activity = 'Moderately Active';
  String _gender   = 'Male';
  String _dietType = 'Vegetarian';
  bool _saved      = false;
  bool _loadingData = true;
  Map<String, dynamic>? _result;
  int _tab = 0; // 0=overview 1=diet 2=workout
  int _planSeed = _todaySeed();

  static int _todaySeed() {
    final now = DateTime.now();
    return now.year * 10000 + now.month * 100 + now.day;
  }

  int _seedFor(String key) {
    var h = _planSeed;
    for (final code in key.codeUnits) {
      h = (h * 31 + code) & 0x7fffffff;
    }
    return h;
  }

  T _pick<T>(String key, List<T> list) {
    if (list.isEmpty) throw StateError('Cannot pick from an empty list');
    return list[Random(_seedFor(key)).nextInt(list.length)];
  }

  final _activities = ['Sedentary', 'Lightly Active', 'Moderately Active', 'Very Active'];

  @override
  void initState() { super.initState(); _loadSavedData(); }

  @override
  void dispose() {
    _ageCtrl.dispose(); _weightCtrl.dispose(); _heightCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { if (mounted) setState(() => _loadingData = false); return; }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!mounted) return;
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        setState(() {
          _ageCtrl.text    = data['age']?.toString() ?? '';
          _weightCtrl.text = data['weight']?.toString() ?? '';
          _heightCtrl.text = data['height']?.toString() ?? '';
          _gender   = data['gender'] ?? 'Male';
          _activity = data['activity'] ?? 'Moderately Active';
          _dietType = data['dietType'] ?? 'Vegetarian';
          _saved    = true;
        });
        _analyse(silent: true);
      }
    } catch (e) { debugPrint('Health load: $e'); }
    if (mounted) setState(() => _loadingData = false);
  }

  int _safeCalorieFloor() => _gender == 'Male' ? 1500 : 1300;

  int _safeFatLossDeficit(int tdee) {
    if (tdee < 1800) return 200;
    if (tdee < 2200) return 300;
    if (tdee < 2700) return 400;
    return 500;
  }

  int _safeWeightGainSurplus(int tdee) {
    if (tdee < 1800) return 200;
    if (tdee < 2400) return 300;
    return 400;
  }

  int _calorieAdjustment(String type, int tdee) {
    if (type == 'underweight') return _safeWeightGainSurplus(tdee);
    if (type == 'healthy') return 0;
    return -_safeFatLossDeficit(tdee);
  }

  String _targetLabel(String type, int adjustment) {
    if (adjustment > 0) return 'Safe surplus +$adjustment kcal — gain weight';
    if (adjustment < 0) return 'Safe deficit $adjustment kcal — lose fat';
    return 'Maintenance calories';
  }

  Future<void> _saveData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'age': int.tryParse(_ageCtrl.text),
      'weight': double.tryParse(_weightCtrl.text),
      'height': double.tryParse(_heightCtrl.text),
      'gender': _gender, 'activity': _activity, 'dietType': _dietType,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) setState(() => _saved = true);
  }

  void _analyse({bool silent = false}) {
    final age    = int.tryParse(_ageCtrl.text);
    final weight = double.tryParse(_weightCtrl.text);
    final height = double.tryParse(_heightCtrl.text);
    if (age == null || weight == null || height == null || age <= 0 || weight <= 0 || height <= 0) {
      if (!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fill in all fields', style: GoogleFonts.dmSans()),
        backgroundColor: AppColors.card));
      return;
    }
    final h = height / 100;
    final bmi = weight / (h * h);
    final bmr = _gender == 'Male'
        ? 10 * weight + 6.25 * height - 5 * age + 5
        : 10 * weight + 6.25 * height - 5 * age - 161;
    final multipliers = {
      'Sedentary': 1.2, 'Lightly Active': 1.375,
      'Moderately Active': 1.55, 'Very Active': 1.725
    };
    final tdee = bmr * multipliers[_activity]!;
    String cat; Color col; String type;
    if (bmi < 18.5) { cat = 'Underweight'; col = AppColors.neon2; type = 'underweight'; }
    else if (bmi < 25) { cat = 'Healthy'; col = AppColors.success; type = 'healthy'; }
    else if (bmi < 30) { cat = 'Overweight'; col = AppColors.warning; type = 'overweight'; }
    else { cat = 'Obese'; col = AppColors.danger; type = 'obese'; }
    if (mounted) setState(() {
      final tdeeInt = tdee.round();
      final adjustment = _calorieAdjustment(type, tdeeInt);
      final targetCal = (tdeeInt + adjustment).clamp(_safeCalorieFloor(), 6000).toInt();

      _result = {
        'bmi': bmi,
        'cat': cat,
        'col': col,
        'tdee': tdeeInt,
        'type': type,
        'adjustment': adjustment,
        'targetCal': targetCal,
        // Kept for compatibility with older UI logic.
        'deficit': targetCal,
        'surplus': targetCal,
      };
    });
    if (!silent) _saveData();
  }

  @override
  Widget build(BuildContext context) {
    final name = FirebaseAuth.instance.currentUser?.displayName?.split(' ').first ?? 'Athlete';
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _loadingData
        ? Center(child: Text('LOADING...', style: GoogleFonts.pressStart2p(
            fontSize: 10, color: AppColors.accent)))
        : SafeArea(child: CustomScrollView(slivers: [
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Header
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Hey, $name 👋', style: GoogleFonts.dmSans(
                      fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text('HEALTH STATS', style: GoogleFonts.pressStart2p(
                      fontSize: 12, color: AppColors.accent,
                      shadows: [Shadow(color: AppColors.accent.withOpacity(0.5), blurRadius: 8)])),
                  ]),
                  if (_saved) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      border: Border.all(color: AppColors.success.withOpacity(0.4))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.cloud_done_outlined, color: AppColors.success, size: 13),
                      const SizedBox(width: 5),
                      Text('SAVED', style: GoogleFonts.pressStart2p(
                        fontSize: 6, color: AppColors.success)),
                    ])),
                ]),
                const SizedBox(height: 20),

                // Input card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    border: Border.all(color: AppColors.accent.withOpacity(0.3))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('YOUR STATS', style: GoogleFonts.pressStart2p(
                      fontSize: 8, color: AppColors.accent)),
                    const SizedBox(height: 14),

                    // Diet toggle
                    Row(children: ['Vegetarian', 'Non-Vegetarian'].map((d) {
                      final sel = _dietType == d;
                      return Expanded(child: GestureDetector(
                        onTap: () => setState(() => _dietType = d),
                        child: Container(
                          margin: EdgeInsets.only(right: d == 'Vegetarian' ? 8 : 0),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: sel ? AppColors.accentDim : Colors.transparent,
                            border: Border.all(color: sel ? AppColors.accent : AppColors.border,
                              width: sel ? 2 : 1)),
                          child: Center(child: Text(
                            d == 'Vegetarian' ? '🥦 Veg' : '🍗 Non-Veg',
                            style: GoogleFonts.dmSans(
                              color: sel ? AppColors.accent : AppColors.textSecondary,
                              fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                              fontSize: 13))))));
                    }).toList()),
                    const SizedBox(height: 10),

                    // Gender toggle
                    Row(children: ['Male', 'Female'].map((g) {
                      final sel = _gender == g;
                      return Expanded(child: GestureDetector(
                        onTap: () => setState(() => _gender = g),
                        child: Container(
                          margin: EdgeInsets.only(right: g == 'Male' ? 8 : 0),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: sel ? AppColors.accentDim : Colors.transparent,
                            border: Border.all(color: sel ? AppColors.accent : AppColors.border,
                              width: sel ? 2 : 1)),
                          child: Center(child: Text(
                            g == 'Male' ? '♂  Male' : '♀  Female',
                            style: GoogleFonts.dmSans(
                              color: sel ? AppColors.accent : AppColors.textSecondary,
                              fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                              fontSize: 13))))));
                    }).toList()),
                    const SizedBox(height: 10),

                    // Stat inputs
                    Row(children: [
                      Expanded(child: _statBox(_ageCtrl, 'Age', 'yrs',
                        action: TextInputAction.next)),
                      const SizedBox(width: 8),
                      Expanded(child: _statBox(_weightCtrl, 'Weight', 'kg',
                        action: TextInputAction.next)),
                      const SizedBox(width: 8),
                      Expanded(child: _statBox(_heightCtrl, 'Height', 'cm',
                        action: TextInputAction.done, onDone: _analyse)),
                    ]),
                    const SizedBox(height: 10),

                    // Activity dropdown
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        border: Border.all(color: AppColors.border)),
                      child: DropdownButtonFormField<String>(
                        value: _activity, dropdownColor: AppColors.card,
                        style: GoogleFonts.dmSans(color: AppColors.textPrimary, fontSize: 14),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          prefixIcon: Icon(Icons.bolt_rounded, color: AppColors.accent, size: 18)),
                        items: _activities.map((a) => DropdownMenuItem(
                          value: a, child: Text(a))).toList(),
                        onChanged: (v) => setState(() => _activity = v!),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Analyse button
                    GestureDetector(
                      onTap: _analyse,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          boxShadow: [BoxShadow(
                            color: AppColors.accent.withOpacity(0.3), blurRadius: 10)]),
                        child: Center(child: Text('ANALYSE + SAVE',
                          style: GoogleFonts.pressStart2p(
                            fontSize: 9, color: AppColors.bg, letterSpacing: 1))),
                      ),
                    ),
                  ]),
                ),

                // Results
                if (_result != null) ...[
                  const SizedBox(height: 20),
                  _resultsSection(),
                ],
                const SizedBox(height: 30),
              ]),
            )),
          ])),
    );
  }

  Widget _statBox(TextEditingController ctrl, String label, String unit,
      {TextInputAction action = TextInputAction.next, VoidCallback? onDone}) =>
    Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg, border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.pressStart2p(fontSize: 7, color: AppColors.textMuted)),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: TextField(
            controller: ctrl, keyboardType: TextInputType.number,
            textInputAction: action,
            onSubmitted: onDone != null ? (_) => onDone() : null,
            style: GoogleFonts.dmSans(color: AppColors.textPrimary,
              fontSize: 22, fontWeight: FontWeight.w700),
            cursorColor: AppColors.accent,
            decoration: InputDecoration(
              border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
              hintText: '—', hintStyle: GoogleFonts.dmSans(
                color: AppColors.textMuted, fontSize: 22, fontWeight: FontWeight.w700)))),
          Text(unit, style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textMuted)),
        ]),
      ]));

  Widget _resultsSection() {
    final bmi  = _result!['bmi'] as double;
    final cat  = _result!['cat'] as String;
    final col  = _result!['col'] as Color;
    final tdee = _result!['tdee'] as int;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Metric cards
      Row(children: [
        Expanded(child: _metricCard('BMI', bmi.toStringAsFixed(1), cat, col)),
        const SizedBox(width: 10),
        Expanded(child: _metricCard('CALORIES', '$tdee', 'kcal/day', AppColors.neon2)),
      ]),
      const SizedBox(height: 16),

      // Tab switcher
      Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border)),
        child: Row(children: ['Overview', 'Diet', 'Workout'].asMap().entries.map((e) {
          final sel = _tab == e.key;
          return Expanded(child: GestureDetector(
            onTap: () => setState(() => _tab = e.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 10),
              color: sel ? AppColors.accent : Colors.transparent,
              child: Center(child: Text(e.value,
                style: GoogleFonts.pressStart2p(
                  fontSize: 7,
                  color: sel ? AppColors.bg : AppColors.textSecondary))))));
        }).toList()),
      ),
      const SizedBox(height: 14),

      if (_tab == 0) _overviewTab(),
      if (_tab == 1) _dietTab(),
      if (_tab == 2) _workoutTab(),
    ]);
  }

  Widget _metricCard(String title, String val, String sub, Color col) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: col.withOpacity(0.07),
      border: Border.all(color: col.withOpacity(0.3))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: GoogleFonts.pressStart2p(fontSize: 7, color: AppColors.textSecondary)),
      const SizedBox(height: 6),
      Text(val, style: GoogleFonts.pressStart2p(fontSize: 22, color: col,
        shadows: [Shadow(color: col.withOpacity(0.6), blurRadius: 8)])),
      const SizedBox(height: 2),
      Text(sub, style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textMuted)),
    ]));

  Widget _overviewTab() {
    final type = _result!['type'] as String;
    final tips = <Map<String, String>>[
      if (type == 'underweight') ...[
        {'e': '🥜', 't': 'Add healthy fats to every meal — nuts, avocado, ghee, peanut butter.'},
        {'e': '🏋️', 't': 'Focus on strength training 3x/week to build muscle, not just eat more.'},
        {'e': '😴', 't': 'Sleep 8 hours — your body builds muscle during sleep, not during workouts.'},
        {'e': '🥛', 't': 'Protein at every meal: eggs, paneer, dal, chicken, or Greek yogurt.'},
        {'e': '📈', 't': 'Track your weight weekly. Aim to gain 0.5 kg per week maximum.'},
      ] else if (type == 'healthy') ...[
        {'e': '✅', 't': 'You\'re in a great range. Focus on performance, not just weight.'},
        {'e': '🏃', 't': '150 min of moderate cardio per week is the gold standard for heart health.'},
        {'e': '💧', 't': 'Drink 35 ml of water per kg of bodyweight daily.'},
        {'e': '🧘', 't': 'Add one flexibility session per week to prevent injury.'},
        {'e': '📊', 't': 'Weigh yourself weekly at the same time — morning, after bathroom.'},
      ] else if (type == 'overweight') ...[
        {'e': '🔥', 't': 'A 300–500 calorie daily deficit leads to safe fat loss of 0.5 kg/week.'},
        {'e': '🚶', 't': '45 min brisk walks 5x/week burns more calories than most people think.'},
        {'e': '🥦', 't': 'Cut sugar, maida, and packaged food first — these are the biggest culprits.'},
        {'e': '⏰', 't': 'Eat dinner before 7:30 PM. Late eating stores more fat.'},
        {'e': '📉', 't': 'Don\'t aim to lose more than 1 kg/week — slow loss is permanent loss.'},
      ] else ...[
        {'e': '🩺', 't': 'Talk to a doctor before starting any exercise program.'},
        {'e': '🚶', 't': 'Start with 15–20 min walks daily. Add 5 min every week.'},
        {'e': '🍎', 't': 'Replace all drinks with water. No soda, no juice, no sugar in chai.'},
        {'e': '🛌', 't': 'Poor sleep causes weight gain — fix your sleep before your diet.'},
        {'e': '🧠', 't': 'Mental health matters as much as physical. Be kind to yourself.'},
      ],
    ];
    return Column(children: tips.map((t) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card, border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Text(t['e']!, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Expanded(child: Text(t['t']!, style: GoogleFonts.dmSans(
          fontSize: 13, color: AppColors.textSecondary, height: 1.45))),
      ]))).toList());
  }

  Widget _dietTab() {
    final type = _result!['type'] as String;
    final tdee = _result!['tdee'] as int;
    final targetCal = _result!['targetCal'] as int;
    final adjustment = _result!['adjustment'] as int;
    final targetLabel = _targetLabel(type, adjustment);
    final meals = _getMeals(type, _dietType, targetCal);
    final totalMealCalories = meals.fold<int>(0, (sum, m) {
      final raw = m['kcal'];
      final value = raw is int ? raw : int.tryParse(raw.toString()) ?? 0;
      return sum + value;
    });

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Calorie target banner
      Container(
        width: double.infinity, padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.accentDim,
          border: Border.all(color: AppColors.accent.withOpacity(0.4))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TODAY\'S DIET PLAN', style: GoogleFonts.pressStart2p(
              fontSize: 7, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Text('~$totalMealCalories kcal', style: GoogleFonts.pressStart2p(
              fontSize: 20, color: AppColors.accent,
              shadows: [Shadow(color: AppColors.accent, blurRadius: 10)])),
            const SizedBox(height: 2),
            Text('$targetLabel • Target: $targetCal kcal • Maintenance: $tdee kcal', style: GoogleFonts.dmSans(
              fontSize: 11, color: AppColors.textSecondary)),
          ])),
          GestureDetector(
            onTap: () => setState(() => _planSeed = DateTime.now().millisecondsSinceEpoch),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.bg,
                border: Border.all(color: AppColors.accent.withOpacity(0.5))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.shuffle_rounded, color: AppColors.accent, size: 16),
                const SizedBox(width: 6),
                Text('SHUFFLE', style: GoogleFonts.pressStart2p(
                  fontSize: 6, color: AppColors.accent)),
              ]),
            ),
          ),
        ])),
      ...meals.map((m) => _mealCard(m)),
    ]);
  }

  Widget _mealCard(Map<String, dynamic> meal) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: AppColors.card, border: Border.all(color: AppColors.border)),
    child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(meal['meal'], style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
            Text(meal['time'], style: GoogleFonts.dmSans(
              fontSize: 11, color: AppColors.textMuted)),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: AppColors.accentDim,
            child: Text('~${meal['kcal']} kcal', style: GoogleFonts.pressStart2p(
              fontSize: 7, color: AppColors.accent))),
        ])),
      Container(height: 1, color: AppColors.border),
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ...(meal['items'] as List<String>).map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Container(width: 4, height: 4, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(child: Text(item, style: GoogleFonts.dmSans(
                fontSize: 13, color: AppColors.textSecondary))),
            ]))),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            color: AppColors.bg,
            child: Row(children: [
              const Icon(Icons.lightbulb_outline_rounded, color: AppColors.accent, size: 14),
              const SizedBox(width: 8),
              Expanded(child: Text(meal['tip'], style: GoogleFonts.dmSans(
                fontSize: 12, color: AppColors.textMuted, fontStyle: FontStyle.italic))),
            ])),
        ])),
    ]));

  Widget _workoutTab() {
    final type = _result!['type'] as String;
    final stages = _getWorkoutStages(type);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.card, border: Border.all(color: AppColors.border)),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.textMuted, size: 16),
          const SizedBox(width: 10),
          Expanded(child: Text(
            'Start at Beginner and progress as you get stronger.',
            style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted, height: 1.4))),
        ])),
      ...stages.asMap().entries.map((e) => _workoutStage(e.value, e.key == stages.length - 1)),
    ]);
  }

  Widget _workoutStage(Map<String, dynamic> stage, bool isLast) {
    final col = stage['col'] as Color;
    final exercises = stage['exercises'] as List<Map<String, String>>;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: col.withOpacity(0.12), shape: BoxShape.circle,
            border: Border.all(color: col, width: 2)),
          child: Center(child: Text(stage['icon'], style: const TextStyle(fontSize: 16)))),
        if (!isLast) Container(width: 2, height: 24, color: AppColors.border,
          margin: const EdgeInsets.symmetric(vertical: 4)),
      ]),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(stage['level'], style: GoogleFonts.dmSans(
            fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            color: col.withOpacity(0.1),
            child: Text(stage['weeks'], style: GoogleFonts.pressStart2p(
              fontSize: 7, color: col))),
        ]),
        const SizedBox(height: 2),
        Text(stage['focus'], style: GoogleFonts.dmSans(
          fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 4),
        Text('${stage['days']}  ·  ${stage['cardio']}',
          style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.accent,
            fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card, border: Border.all(color: AppColors.border)),
          child: Column(children: exercises.asMap().entries.map((ex) {
            final last = ex.key == exercises.length - 1;
            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(child: Text(ex.value['name']!, style: GoogleFonts.dmSans(
                    fontSize: 13, color: AppColors.textSecondary))),
                  Text(ex.value['sets']!, style: GoogleFonts.dmSans(
                    fontSize: 12, color: col, fontWeight: FontWeight.w600)),
                ])),
              if (!last) Container(height: 1, color: AppColors.border),
            ]);
          }).toList()),
        ),
        SizedBox(height: isLast ? 0 : 18),
      ])),
    ]);
  }

  List<Map<String, dynamic>> _getMeals(String type, String diet, int targetCal) {
    final isVeg = diet == 'Vegetarian';

    Map<String, dynamic> meal(
      String meal,
      String time,
      int kcal,
      List<String> items,
      String tip,
    ) => {
      'meal': meal,
      'time': time,
      'kcal': '$kcal',
      'items': items,
      'tip': tip,
    };

    List<Map<String, dynamic>> pool(String slot) {
      final key = '${type}_${isVeg ? 'veg' : 'nonveg'}_$slot';

      if (type == 'underweight') {
        if (slot == 'breakfast') return [
          meal('Breakfast', '7:00 AM', 650, isVeg
              ? ['Peanut butter banana smoothie', 'Oats with honey, milk & nuts', 'Paneer bhurji']
              : ['Peanut butter banana smoothie', 'Oats with honey & nuts', '3 scrambled eggs with butter'],
              'Never skip breakfast — this meal sets your metabolic tone for the whole day.'),
          meal('Breakfast', '7:30 AM', 620, isVeg
              ? ['Stuffed paneer paratha with curd', 'Banana', 'Glass of whole milk']
              : ['Egg paratha', 'Banana', 'Glass of whole milk'],
              'A high-calorie breakfast helps you gain weight without forcing huge dinners.'),
          meal('Breakfast', '8:00 AM', 700, isVeg
              ? ['Masala oats cooked in milk', 'Peanut butter toast', 'Dates and almonds']
              : ['Chicken sandwich', 'Masala oats in milk', 'Dates and almonds'],
              'Add calorie-dense foods like nuts, dates, milk and peanut butter.'),
          meal('Breakfast', '7:00 AM', 680, isVeg
              ? ['Poha with peanuts', 'Paneer cubes', 'Mango or banana shake']
              : ['Poha with peanuts', 'Boiled eggs', 'Mango or banana shake'],
              'Liquid calories like shakes are useful when appetite is low.'),
        ];
        if (slot == 'snack1') return [
          meal('Mid-Morning', '10:30 AM', 300, isVeg
              ? ['Full-fat Greek yogurt with granola', 'Mixed nuts & dried fruit', '1 banana']
              : ['Chicken or tuna sandwich on whole wheat', 'Full-fat yogurt', '1 banana'],
              'Calorie-dense snacks between meals are key to reaching your daily surplus.'),
          meal('Mid-Morning', '11:00 AM', 320, isVeg
              ? ['Peanut chikki', 'Lassi', 'Roasted makhana']
              : ['Boiled eggs', 'Lassi', 'Roasted makhana'],
              'Small snacks make weight gain easier than depending only on big meals.'),
          meal('Mid-Morning', '10:00 AM', 280, isVeg
              ? ['Cheese sandwich', 'Coconut water', 'Handful of cashews']
              : ['Chicken cheese sandwich', 'Coconut water', 'Handful of cashews'],
              'Use snacks to add protein and healthy fats, not just sugar.'),
        ];
        if (slot == 'lunch') return [
          meal('Lunch', '1:00 PM', 800, isVeg
              ? ['Rice or 2–3 chapati', 'Dal makhani with ghee', 'Paneer curry', 'Salad with olive oil']
              : ['Rice or 2–3 chapati', 'Dal with ghee', 'Chicken or mutton curry', 'Salad with olive oil'],
              'Add ghee or olive oil freely — healthy fats have double the calories of carbs.'),
          meal('Lunch', '1:30 PM', 760, isVeg
              ? ['Rajma rice', 'Paneer tikka', 'Curd', 'Salad']
              : ['Chicken biryani style rice', 'Curd', 'Salad', 'Dal'],
              'Pair carbs with protein so the weight you gain supports muscle.'),
          meal('Lunch', '12:45 PM', 820, isVeg
              ? ['Chole with rice', 'Aloo sabzi', 'Curd', 'Ghee on rice']
              : ['Fish curry with rice', 'Dal', 'Curd', 'Vegetables'],
              'Your lunch should be your strongest meal if you struggle to gain weight.'),
        ];
        if (slot == 'snack2') return [
          meal('Evening Snack', '4:30 PM', 350, isVeg
              ? ['Avocado toast or peanut butter on whole wheat', 'Mango or banana', 'Full-fat milk']
              : ['Egg sandwich or chicken wrap', 'Mango or banana', 'Protein shake with milk'],
              'Avocado and nut butter are packed with calorie-dense healthy fats.'),
          meal('Evening Snack', '5:00 PM', 360, isVeg
              ? ['Paneer roll', 'Banana shake', 'Walnuts']
              : ['Chicken roll', 'Banana shake', 'Walnuts'],
              'A strong evening snack prevents late-night junk cravings.'),
          meal('Evening Snack', '4:00 PM', 330, isVeg
              ? ['Sprouts with paneer', 'Dates', 'Milk coffee']
              : ['Sprouts with eggs', 'Dates', 'Milk coffee'],
              'Protein plus carbs before training improves workout performance.'),
        ];
        return [
          meal('Dinner', '8:00 PM', 700, isVeg
              ? ['Rajma or chole with rice', 'Sabzi with ghee', 'Curd (full fat)', 'Glass of whole milk']
              : ['Grilled chicken (200g)', 'Rice or roti', 'Mixed sabzi', 'Glass of whole milk'],
              'Milk before bed provides slow-release protein while you sleep and recover.'),
          meal('Dinner', '8:30 PM', 680, isVeg
              ? ['Paneer pulao', 'Dal soup', 'Curd', 'Mixed vegetables']
              : ['Chicken pulao', 'Dal soup', 'Curd', 'Mixed vegetables'],
              'Dinner should support recovery, not just fill calories.'),
          meal('Dinner', '7:45 PM', 720, isVeg
              ? ['2–3 chapati', 'Paneer butter masala', 'Dal', 'Salad']
              : ['2–3 chapati', 'Egg curry or chicken curry', 'Dal', 'Salad'],
              'A balanced dinner helps you wake up energetic instead of bloated.'),
        ];
      }

      if (type == 'healthy') {
        if (slot == 'breakfast') return [
          meal('Breakfast', '7:30 AM', 450, isVeg
              ? ['Oats with berries, flaxseeds & almonds', 'Paneer or tofu scramble', 'Black coffee or green tea']
              : ['Oats with berries & seeds', '2–3 eggs any style', 'Black coffee or green tea'],
              'A high-protein breakfast reduces hunger and prevents overeating all day.'),
          meal('Breakfast', '8:00 AM', 430, isVeg
              ? ['Moong dal cheela', 'Curd', 'Fruit']
              : ['Egg bhurji', 'Toast', 'Fruit'],
              'Start with protein to keep energy stable through college or work.'),
          meal('Breakfast', '7:00 AM', 470, isVeg
              ? ['Vegetable upma', 'Sprouts salad', 'Green tea']
              : ['Vegetable upma', 'Boiled eggs', 'Green tea'],
              'Keep breakfast filling but not heavy — performance matters more than scale weight.'),
          meal('Breakfast', '7:45 AM', 440, isVeg
              ? ['Paneer sandwich', 'Apple', 'Unsweetened tea']
              : ['Chicken sandwich', 'Apple', 'Unsweetened tea'],
              'Avoid sugary drinks; they add calories without keeping you full.'),
        ];
        if (slot == 'snack1') return [
          meal('Mid-Morning', '10:30 AM', 180, isVeg
              ? ['1 seasonal fruit', 'Handful of almonds & walnuts']
              : ['1 seasonal fruit', '1–2 boiled eggs or nuts'],
              'Eat whole fruit — never juice. Fibre slows sugar absorption significantly.'),
          meal('Mid-Morning', '11:00 AM', 170, isVeg
              ? ['Roasted chana', 'Coconut water']
              : ['Boiled egg', 'Coconut water'],
              'Light snacks prevent overeating at lunch.'),
          meal('Mid-Morning', '10:00 AM', 190, isVeg
              ? ['Curd with chia seeds', 'Small fruit']
              : ['Greek yogurt', 'Small fruit'],
              'Choose snacks that give protein or fibre, not empty calories.'),
        ];
        if (slot == 'lunch') return [
          meal('Lunch', '1:00 PM', 600, isVeg
              ? ['1–2 chapati or brown rice', 'Dal or rajma', 'Paneer sabzi', 'Salad']
              : ['1–2 chapati or rice', 'Dal', 'Grilled chicken (150g) or fish', 'Salad'],
              'Half your plate should be vegetables — not a side dish, literally half the plate.'),
          meal('Lunch', '1:30 PM', 580, isVeg
              ? ['Brown rice', 'Chole', 'Curd', 'Cucumber salad']
              : ['Brown rice', 'Fish curry', 'Curd', 'Cucumber salad'],
              'Build lunch around protein + vegetables, then add carbs.'),
          meal('Lunch', '12:45 PM', 620, isVeg
              ? ['2 chapati', 'Dal tadka', 'Tofu/paneer sabzi', 'Salad']
              : ['2 chapati', 'Chicken curry', 'Dal', 'Salad'],
              'A good lunch should leave you satisfied, not sleepy.'),
        ];
        if (slot == 'snack2') return [
          meal('Evening', '5:00 PM', 150, isVeg
              ? ['Roasted chana or sprouts', 'Coconut water or lemon water']
              : ['Boiled egg or grilled chicken strips', 'Coconut water or black coffee'],
              'Light protein snack before your evening workout if you have one.'),
          meal('Evening', '4:30 PM', 160, isVeg
              ? ['Makhana', 'Lemon water']
              : ['Egg whites', 'Lemon water'],
              'The evening snack should stop cravings, not become a mini dinner.'),
          meal('Evening', '5:30 PM', 180, isVeg
              ? ['Sprouts chaat', 'Buttermilk']
              : ['Chicken salad cup', 'Buttermilk'],
              'Choose crunchy, high-fibre snacks instead of packaged food.'),
        ];
        return [
          meal('Dinner', '7:30 PM', 500, isVeg
              ? ['Moong dal or vegetable soup', '1–2 chapati', 'Stir-fried vegetables', 'Curd']
              : ['Grilled fish or chicken (150g)', '1–2 chapati', 'Stir-fried vegetables', 'Buttermilk'],
              'Lighter dinners improve sleep quality and morning energy levels significantly.'),
          meal('Dinner', '8:00 PM', 520, isVeg
              ? ['Vegetable khichdi', 'Curd', 'Salad']
              : ['Chicken soup', '1–2 chapati', 'Salad'],
              'A simple dinner is easier to repeat consistently than a complicated one.'),
          meal('Dinner', '7:00 PM', 480, isVeg
              ? ['Paneer/tofu stir fry', '1 chapati', 'Soup']
              : ['Egg curry or fish', '1 chapati', 'Soup'],
              'Keep dinner protein-rich and moderately light.'),
        ];
      }

      if (type == 'overweight') {
        if (slot == 'breakfast') return [
          meal('Breakfast', '7:00 AM', 350, isVeg
              ? ['Moong dal cheela (2) with chutney', 'Plain curd (small)', 'Green tea (no sugar)']
              : ['2 boiled eggs (1 yolk)', 'Vegetable upma (small)', 'Green tea (no sugar)'],
              'Cut all morning sugar completely — no biscuits, no chai with sugar.'),
          meal('Breakfast', '7:30 AM', 330, isVeg
              ? ['Sprouts chaat', 'Curd', 'Black coffee']
              : ['Egg white omelette', 'Toast', 'Black coffee'],
              'High protein breakfast reduces cravings later in the day.'),
          meal('Breakfast', '8:00 AM', 360, isVeg
              ? ['Besan cheela', 'Mint chutney', 'Lemon water']
              : ['Chicken/egg sandwich', 'Lemon water'],
              'Avoid liquid sugar — it is one of the easiest fat-loss wins.'),
          meal('Breakfast', '7:15 AM', 340, isVeg
              ? ['Vegetable oats', 'Paneer cubes', 'Green tea']
              : ['Vegetable oats', 'Boiled eggs', 'Green tea'],
              'A controlled breakfast keeps the day under control.'),
        ];
        if (slot == 'snack1') return [
          meal('Mid-Morning', '10:30 AM', 100, isVeg
              ? ['1 guava or pear (not banana)', '5–6 almonds']
              : ['1 seasonal fruit (not banana/mango)', '1 boiled egg or 5 almonds'],
              'Always choose lower sugar fruits. Avoid mango, banana, grapes in this phase.'),
          meal('Mid-Morning', '11:00 AM', 90, isVeg
              ? ['Cucumber sticks', 'Green tea']
              : ['Egg whites', 'Green tea'],
              'Keep snacks light — they should not erase your calorie deficit.'),
          meal('Mid-Morning', '10:00 AM', 120, isVeg
              ? ['Roasted chana', 'Water']
              : ['Boiled egg', 'Water'],
              'Protein snacks help you stay full with fewer calories.'),
        ];
        if (slot == 'lunch') return [
          meal('Lunch', '1:00 PM', 500, isVeg
              ? ['Big salad FIRST', '1–2 small chapati (no butter)', 'Dal (1 bowl)', 'Curd (small)']
              : ['Big salad FIRST', 'Grilled chicken (100g) or fish', '1 chapati', 'Dal (small)'],
              'Eat your salad FIRST before anything else — fills you up on almost zero calories.'),
          meal('Lunch', '1:30 PM', 480, isVeg
              ? ['Vegetable bowl', 'Dal', '1 chapati', 'Curd']
              : ['Grilled chicken bowl', 'Vegetables', '1 chapati', 'Curd'],
              'Use vegetables for volume and protein for fullness.'),
          meal('Lunch', '12:45 PM', 520, isVeg
              ? ['Rajma small bowl', '1 chapati', 'Large salad', 'Buttermilk']
              : ['Fish/chicken curry', '1 chapati', 'Large salad', 'Buttermilk'],
              'Do not remove carbs completely; control portions instead.'),
        ];
        if (slot == 'snack2') return [
          meal('Evening', '5:00 PM', 80, isVeg
              ? ['Cucumber and carrot sticks', 'Lemon water or plain chaas']
              : ['Boiled egg whites (1–2) or vegetables', 'Black coffee or lemon water'],
              'Evening is the danger zone. Avoid anything fried or packaged completely.'),
          meal('Evening', '4:30 PM', 100, isVeg
              ? ['Sprouts small bowl', 'Mint water']
              : ['Chicken soup cup', 'Mint water'],
              'Plan your evening snack before cravings hit.'),
          meal('Evening', '5:30 PM', 90, isVeg
              ? ['Roasted makhana', 'Green tea']
              : ['Egg whites', 'Green tea'],
              'Avoid fried snacks; they are calorie dense and easy to overeat.'),
        ];
        return [
          meal('Dinner', '7:00 PM', 380, isVeg
              ? ['Clear vegetable or tomato soup', '1 small chapati', 'Stir-fried vegetables']
              : ['Grilled fish or chicken soup', '1 small chapati or skip', 'Stir-fried vegetables'],
              'Eat before 7:30 PM maximum. Every hour earlier improves fat loss.'),
          meal('Dinner', '7:30 PM', 400, isVeg
              ? ['Moong dal soup', 'Vegetable sabzi', 'Small curd']
              : ['Chicken clear soup', 'Vegetable sabzi', 'Small curd'],
              'Dinner should be the lightest meal during fat loss.'),
          meal('Dinner', '6:45 PM', 360, isVeg
              ? ['Paneer/tofu salad', 'Soup', 'No sugar drink']
              : ['Grilled chicken salad', 'Soup', 'No sugar drink'],
              'A protein-rich light dinner supports fat loss and recovery.'),
        ];
      }

      // obese
      if (slot == 'breakfast') return [
        meal('Breakfast', '8:00 AM', 280, isVeg
            ? ['Moong dal cheela (2 small)', 'Plain curd (no sugar)', 'Warm lemon water']
            : ['2 boiled egg whites + 1 whole', 'Small vegetable upma', 'Warm lemon water'],
            'Low glycemic foods prevent blood sugar spikes essential for weight loss.'),
        meal('Breakfast', '7:30 AM', 300, isVeg
            ? ['Besan chilla', 'Mint chutney', 'Green tea']
            : ['Egg white omelette', 'Small toast', 'Green tea'],
            'Start simple. The goal is consistency, not perfection.'),
        meal('Breakfast', '8:30 AM', 290, isVeg
            ? ['Vegetable dalia', 'Curd', 'Water']
            : ['Chicken soup bowl', 'Small toast', 'Water'],
            'Choose warm, filling foods that are easy on digestion.'),
      ];
      if (slot == 'snack1') return [
        meal('Mid-Morning', '11:00 AM', 70, isVeg
            ? ['1 small guava or pear', 'Herbal tea — no sugar']
            : ['1 small fruit (guava or pear)', 'Plain water or herbal tea'],
            'Drink 3+ litres of water daily. Most hunger is actually dehydration.'),
        meal('Mid-Morning', '10:30 AM', 80, isVeg
            ? ['Cucumber sticks', 'Lemon water']
            : ['Boiled egg white', 'Lemon water'],
            'Keep snacks very light until consistency improves.'),
        meal('Mid-Morning', '11:30 AM', 90, isVeg
            ? ['Roasted chana small handful', 'Water']
            : ['Chicken soup small cup', 'Water'],
            'Small planned snacks prevent large unplanned meals.'),
      ];
      if (slot == 'lunch') return [
        meal('Lunch', '1:00 PM', 420, isVeg
            ? ['Unlimited salad first', 'Dal (1 bowl)', 'Steamed vegetables', '1 small chapati']
            : ['Unlimited salad first', 'Grilled chicken (100g) or fish', 'Steamed vegetables', '1 chapati (optional)'],
            'Eat in this order always: salad → protein → vegetables → chapati.'),
        meal('Lunch', '1:30 PM', 440, isVeg
            ? ['Vegetable soup', 'Dal', '1 chapati', 'Curd']
            : ['Fish/chicken soup', 'Vegetables', '1 chapati', 'Curd'],
            'Your lunch should be controlled but filling.'),
        meal('Lunch', '12:45 PM', 410, isVeg
            ? ['Large salad', 'Moong dal', 'Steamed sabzi', 'Buttermilk']
            : ['Large salad', 'Grilled chicken', 'Steamed sabzi', 'Buttermilk'],
            'Vegetables first makes portion control much easier.'),
      ];
      if (slot == 'snack2') return [
        meal('Evening', '4:30 PM', 60, isVeg
            ? ['Cucumber, carrot sticks', 'Buttermilk (no sugar or salt)']
            : ['Cucumber, carrot sticks', 'Buttermilk or plain water'],
            'Your evening habits drive your weight more than anything else. Stay disciplined.'),
        meal('Evening', '5:00 PM', 70, isVeg
            ? ['Clear soup', 'Water']
            : ['Egg white or clear soup', 'Water'],
            'Do not let evening hunger turn into fried snacks.'),
        meal('Evening', '4:00 PM', 80, isVeg
            ? ['Makhana small bowl', 'Green tea']
            : ['Chicken broth', 'Green tea'],
            'Keep it light, warm, and planned.'),
      ];
      return [
        meal('Dinner', '6:30 PM', 300, isVeg
            ? ['Clear vegetable soup', 'Steamed vegetables (unlimited)', '1 small chapati (optional)']
            : ['Clear chicken or vegetable soup', 'Grilled fish (80g) or egg whites (2)', 'Steamed vegetables'],
            'Eat by 6:30–7 PM. This single change has the biggest impact on your journey.'),
        meal('Dinner', '7:00 PM', 320, isVeg
            ? ['Moong soup', 'Vegetable bowl', 'Curd small']
            : ['Chicken soup', 'Vegetable bowl', 'Curd small'],
            'Early, light dinners improve sleep and reduce cravings.'),
        meal('Dinner', '6:45 PM', 310, isVeg
            ? ['Tofu/paneer small salad', 'Clear soup', 'Water']
            : ['Egg white/chicken salad', 'Clear soup', 'Water'],
            'Stop eating before you are stuffed. Consistency beats intensity.'),
      ];
    }

    final selected = <Map<String, dynamic>>[
      Map<String, dynamic>.from(_pick('${type}_${diet}_breakfast', pool('breakfast'))),
      Map<String, dynamic>.from(_pick('${type}_${diet}_snack1', pool('snack1'))),
      Map<String, dynamic>.from(_pick('${type}_${diet}_lunch', pool('lunch'))),
      Map<String, dynamic>.from(_pick('${type}_${diet}_snack2', pool('snack2'))),
      Map<String, dynamic>.from(_pick('${type}_${diet}_dinner', pool('dinner'))),
    ];

    return _balanceMealsToTarget(selected, targetCal, type, isVeg);
  }

  List<Map<String, dynamic>> _balanceMealsToTarget(
    List<Map<String, dynamic>> meals,
    int targetCal,
    String type,
    bool isVeg,
  ) {
    int kcalOf(Map<String, dynamic> m) => int.tryParse(m['kcal'].toString()) ?? 0;
    void setKcal(Map<String, dynamic> m, int v) => m['kcal'] = '$v';
    void addItem(Map<String, dynamic> m, String item) {
      final items = List<String>.from(m['items'] as List);
      items.add(item);
      m['items'] = items;
    }

    int total() => meals.fold<int>(0, (sum, m) => sum + kcalOf(m));

    // Keep food calories realistic. Do NOT force a 350 kcal meal to show as 650 kcal.
    // If the safe target is higher, add visible realistic portions or an add-on card.
    var gap = targetCal - total();
    if (gap > 150) {
      final boosts = <Map<String, dynamic>>[
        {
          'idx': 2,
          'max': 350,
          'veg': 'Extra rice/chapati + dal/paneer/tofu portion',
          'nonveg': 'Extra rice/chapati + chicken/fish/egg portion',
        },
        {
          'idx': 4,
          'max': 300,
          'veg': 'Extra dal/protein serving or 1 chapati',
          'nonveg': 'Extra egg/chicken/fish serving or 1 chapati',
        },
        {
          'idx': 0,
          'max': 150,
          'veg': 'Extra curd/paneer or 1 small cheela',
          'nonveg': 'Extra egg/curd or 1 small cheela',
        },
        {
          'idx': 3,
          'max': 150,
          'veg': 'Protein snack add-on: sprouts/curd/paneer',
          'nonveg': 'Protein snack add-on: eggs/chicken soup',
        },
        {
          'idx': 1,
          'max': 100,
          'veg': 'Extra fruit or curd add-on',
          'nonveg': 'Extra egg or fruit add-on',
        },
      ];

      for (final b in boosts) {
        if (gap <= 150) break;
        final add = gap.clamp(0, b['max'] as int).toInt();
        if (add <= 0) continue;
        final idx = b['idx'] as int;
        setKcal(meals[idx], kcalOf(meals[idx]) + add);
        addItem(meals[idx], '${isVeg ? b['veg'] : b['nonveg']} (+$add kcal)');
        gap -= add;
      }

      if (gap > 180) {
        final add = gap.clamp(200, 450).toInt();
        meals.add({
          'meal': 'Target Add-on',
          'time': 'Any time',
          'kcal': '$add',
          'items': isVeg
              ? ['Choose one: paneer/tofu bowl, curd + oats, or dal-rice mini bowl']
              : ['Choose one: egg/chicken bowl, curd + oats, or dal-rice mini bowl'],
          'tip': 'This add-on keeps the plan close to your safe calorie target without making small meals look unrealistically high.',
        });
      }
    }

    // If the selected plan is slightly over/under the target, that is normal.
    // Real diet plans should be approximate, not fake-perfect.
    return meals;
  }

  List<Map<String, dynamic>> _getWorkoutStages(String type) {
    final isLoss = type == 'overweight' || type == 'obese';
    final isGain = type == 'underweight';
    final isFemale = _gender == 'Female';
    final isSedentary = _activity == 'Sedentary';
    final isVeryActive = _activity == 'Very Active';

    List<Map<String, String>> choose(String key, List<List<Map<String, String>>> options) =>
        _pick('${type}_${_gender}_${_activity}_$key', options);

    final beginnerLoss = choose('beginnerLoss', isFemale ? [
      [
        {'name': 'Brisk Walking', 'sets': isSedentary ? '20–30 min' : '30 min'},
        {'name': 'Wall Push-ups', 'sets': '3 × 8–10'},
        {'name': 'Chair Squats', 'sets': '3 × 10'},
        {'name': 'Seated Leg Raises', 'sets': '3 × 12'},
      ],
      [
        {'name': 'Low-Impact Step Touches', 'sets': '3 × 2 min'},
        {'name': 'Glute Bridges', 'sets': '3 × 12'},
        {'name': 'Incline Push-ups', 'sets': '3 × 8'},
        {'name': 'Dead Bug Core', 'sets': '3 × 10/side'},
      ],
      [
        {'name': 'Easy Walk Intervals', 'sets': '25 min'},
        {'name': 'Box Squats', 'sets': '3 × 10'},
        {'name': 'Standing Side Leg Raises', 'sets': '3 × 12/side'},
        {'name': 'Bird Dog', 'sets': '3 × 10/side'},
      ],
    ] : [
      [
        {'name': 'Brisk Walking', 'sets': isSedentary ? '20–30 min' : '30 min'},
        {'name': 'Wall Push-ups', 'sets': '3 × 10'},
        {'name': 'Chair Squats', 'sets': '3 × 10'},
        {'name': 'Seated Leg Raises', 'sets': '3 × 12'},
      ],
      [
        {'name': 'Incline Push-ups', 'sets': '3 × 8–12'},
        {'name': 'Bodyweight Squats', 'sets': '3 × 12'},
        {'name': 'Marching in Place', 'sets': '4 × 2 min'},
        {'name': 'Plank Hold', 'sets': '3 × 15s'},
      ],
      [
        {'name': 'Walk + Stair Combo', 'sets': '25 min'},
        {'name': 'Assisted Lunges', 'sets': '3 × 8/leg'},
        {'name': 'Knee Push-ups', 'sets': '3 × 8'},
        {'name': 'Mountain Climbers Slow', 'sets': '3 × 12'},
      ],
    ]);

    final beginnerGain = choose('beginnerGain', isFemale ? [
      [
        {'name': 'Bodyweight Squats', 'sets': '3 × 12'},
        {'name': 'Glute Bridges', 'sets': '3 × 15'},
        {'name': 'Knee Push-ups', 'sets': '3 × 8'},
        {'name': 'Plank Hold', 'sets': '3 × 20s'},
      ],
      [
        {'name': 'Goblet Squats', 'sets': '3 × 10'},
        {'name': 'Dumbbell Romanian Deadlift', 'sets': '3 × 12'},
        {'name': 'Dumbbell Rows', 'sets': '3 × 12'},
        {'name': 'Side Plank', 'sets': '2 × 20s/side'},
      ],
    ] : [
      [
        {'name': 'Bodyweight Squats', 'sets': '3 × 15'},
        {'name': 'Push-ups (knees OK)', 'sets': '3 × 10'},
        {'name': 'Dumbbell Rows', 'sets': '3 × 12'},
        {'name': 'Plank Hold', 'sets': '3 × 20s'},
      ],
      [
        {'name': 'Goblet Squats', 'sets': '3 × 10'},
        {'name': 'Incline Push-ups', 'sets': '3 × 12'},
        {'name': 'Dumbbell Shoulder Press', 'sets': '3 × 10'},
        {'name': 'Farmer Carry', 'sets': '3 × 20m'},
      ],
    ]);

    final intermediateLoss = choose('intermediateLoss', isFemale ? [
      [
        {'name': 'Step-ups', 'sets': '3 × 12/leg'},
        {'name': 'Dumbbell Squats', 'sets': '3 × 15'},
        {'name': 'Glute Kickbacks', 'sets': '3 × 15/side'},
        {'name': 'Mountain Climbers', 'sets': '3 × 20'},
      ],
      [
        {'name': 'Low-Impact HIIT', 'sets': '5 × 40s'},
        {'name': 'Reverse Lunges', 'sets': '3 × 10/leg'},
        {'name': 'Push-ups', 'sets': '3 × 8–12'},
        {'name': 'Bicycle Crunches', 'sets': '3 × 20'},
      ],
    ] : [
      [
        {'name': 'Jump Rope', 'sets': '3 × 3 min'},
        {'name': 'Dumbbell Squats', 'sets': '3 × 15'},
        {'name': 'Push-ups (full)', 'sets': '3 × 12'},
        {'name': 'Mountain Climbers', 'sets': '3 × 20'},
      ],
      [
        {'name': 'Jog-Walk Intervals', 'sets': '25 min'},
        {'name': 'Dumbbell Lunges', 'sets': '3 × 10/leg'},
        {'name': 'Burpees Low Impact', 'sets': '3 × 8'},
        {'name': 'Plank Shoulder Taps', 'sets': '3 × 20'},
      ],
    ]);

    final intermediateGain = choose('intermediateGain', isFemale ? [
      [
        {'name': 'Goblet Squats', 'sets': '4 × 10'},
        {'name': 'Hip Thrusts', 'sets': '4 × 12'},
        {'name': 'Lat Pulldowns', 'sets': '4 × 12'},
        {'name': 'Overhead Press', 'sets': '3 × 10'},
      ],
      [
        {'name': 'Romanian Deadlifts', 'sets': '4 × 10'},
        {'name': 'Walking Lunges', 'sets': '3 × 12/leg'},
        {'name': 'Seated Rows', 'sets': '4 × 12'},
        {'name': 'Core Dead Bug', 'sets': '3 × 12/side'},
      ],
    ] : [
      [
        {'name': 'Barbell / Goblet Squats', 'sets': '4 × 10'},
        {'name': 'Push-ups (full)', 'sets': '4 × 15'},
        {'name': 'Lat Pulldowns', 'sets': '4 × 12'},
        {'name': 'Overhead Press', 'sets': '3 × 10'},
      ],
      [
        {'name': 'Romanian Deadlifts', 'sets': '4 × 10'},
        {'name': 'Dumbbell Bench Press', 'sets': '4 × 10'},
        {'name': 'One-arm Rows', 'sets': '4 × 12'},
        {'name': 'Hammer Curls', 'sets': '3 × 12'},
      ],
    ]);

    final advancedLoss = choose('advancedLoss', isFemale ? [
      [
        {'name': 'HIIT Intervals', 'sets': '8 × 20s on / 10s off'},
        {'name': 'Kettlebell Swings', 'sets': '4 × 15'},
        {'name': 'Box Step-ups', 'sets': '4 × 12'},
        {'name': 'Dumbbell Deadlifts', 'sets': '4 × 10'},
      ],
      [
        {'name': 'Cycle/Sprint Intervals', 'sets': '10 × 30s'},
        {'name': 'Bulgarian Split Squats', 'sets': '3 × 10/leg'},
        {'name': 'Push Press', 'sets': '4 × 8'},
        {'name': 'Hollow Hold', 'sets': '3 × 30s'},
      ],
    ] : [
      [
        {'name': 'HIIT Intervals', 'sets': '8 × 20s on / 10s off'},
        {'name': 'Kettlebell Swings', 'sets': '4 × 15'},
        {'name': 'Box Jumps', 'sets': '4 × 10'},
        {'name': 'Barbell Deadlifts', 'sets': '4 × 10'},
      ],
      [
        {'name': 'Sprint Intervals', 'sets': '8 × 100m'},
        {'name': 'Burpees', 'sets': '4 × 10'},
        {'name': 'Barbell Squats', 'sets': '4 × 8'},
        {'name': 'Battle Ropes', 'sets': '5 × 30s'},
      ],
    ]);

    final advancedGain = choose('advancedGain', isFemale ? [
      [
        {'name': 'Deadlifts', 'sets': '5 × 5'},
        {'name': 'Hip Thrusts', 'sets': '5 × 8'},
        {'name': 'Pull-ups / Assisted', 'sets': '4 × 8'},
        {'name': 'Farmer Carry', 'sets': '3 × 30m'},
      ],
      [
        {'name': 'Front Squats', 'sets': '4 × 6'},
        {'name': 'Romanian Deadlifts', 'sets': '4 × 8'},
        {'name': 'Dumbbell Bench Press', 'sets': '4 × 8'},
        {'name': 'Cable Core Rotations', 'sets': '3 × 12/side'},
      ],
    ] : [
      [
        {'name': 'Deadlifts', 'sets': '5 × 5'},
        {'name': 'Bench Press', 'sets': '5 × 5'},
        {'name': 'Pull-ups', 'sets': '4 × 8'},
        {'name': 'Farmer\'s Carry', 'sets': '3 × 30m'},
      ],
      [
        {'name': 'Front Squats', 'sets': '4 × 6'},
        {'name': 'Weighted Push-ups', 'sets': '4 × 8'},
        {'name': 'Barbell Rows', 'sets': '4 × 8'},
        {'name': 'Dips', 'sets': '3 × 10'},
      ],
    ]);

    final masterLoss = choose('masterLoss', isFemale ? [
      [
        {'name': 'Sprint / Cycle Intervals', 'sets': '10 × 30s'},
        {'name': 'Full-body Circuit', 'sets': '5 rounds'},
        {'name': 'Heavy Hip Hinge', 'sets': '5 × 5'},
        {'name': 'Mobility Cooldown', 'sets': '15 min'},
      ],
      [
        {'name': 'Metabolic Conditioning', 'sets': '20 min'},
        {'name': 'Kettlebell Complex', 'sets': '5 rounds'},
        {'name': 'Walking Lunges', 'sets': '4 × 20'},
        {'name': 'Core Finisher', 'sets': '8 min'},
      ],
    ] : [
      [
        {'name': 'Sprint Intervals', 'sets': '10 × 100m'},
        {'name': 'Circuit Training', 'sets': '5 rounds'},
        {'name': 'Heavy Compound Lifts', 'sets': '5 × 5'},
        {'name': 'Metabolic Conditioning', 'sets': '20 min'},
      ],
      [
        {'name': 'Prowler / Hill Sprints', 'sets': '8 rounds'},
        {'name': 'Barbell Complex', 'sets': '5 rounds'},
        {'name': 'Pull-ups', 'sets': '5 × max'},
        {'name': 'Core Finisher', 'sets': '10 min'},
      ],
    ]);

    final masterGain = choose('masterGain', isFemale ? [
      [
        {'name': 'Front Squats', 'sets': '5 × 3'},
        {'name': 'Hip Thrusts Heavy', 'sets': '5 × 5'},
        {'name': 'Weighted Pull-ups / Assisted', 'sets': '4 × 6'},
        {'name': 'Battle Ropes', 'sets': '5 × 30s'},
      ],
      [
        {'name': 'Olympic Lift Practice', 'sets': '5 × 3'},
        {'name': 'Romanian Deadlift Heavy', 'sets': '5 × 5'},
        {'name': 'Push Press', 'sets': '4 × 6'},
        {'name': 'Loaded Carries', 'sets': '4 × 30m'},
      ],
    ] : [
      [
        {'name': 'Olympic Lifts', 'sets': '5 × 3'},
        {'name': 'Weighted Pull-ups', 'sets': '4 × 6'},
        {'name': 'Front Squats', 'sets': '4 × 6'},
        {'name': 'Battle Ropes', 'sets': '5 × 30s'},
      ],
      [
        {'name': 'Power Cleans', 'sets': '5 × 3'},
        {'name': 'Weighted Dips', 'sets': '4 × 6'},
        {'name': 'Heavy Rows', 'sets': '4 × 6'},
        {'name': 'Sled Push / Farmer Carry', 'sets': '5 rounds'},
      ],
    ]);

    return [
      {
        'level': 'Beginner', 'weeks': 'Week 1–4',
        'icon': '🌱', 'col': AppColors.success,
        'focus': isLoss ? 'Build the habit. Low impact only.'
            : isGain ? 'Learn form, build your base.'
            : 'Establish consistency and control.',
        'days': isSedentary ? '3 days/week' : '3–4 days/week',
        'cardio': isLoss ? (isSedentary ? '20–30 min walk daily' : '30 min walk daily') : '15–20 min light cardio',
        'exercises': isLoss ? beginnerLoss : beginnerGain,
      },
      {
        'level': 'Intermediate', 'weeks': 'Week 5–10',
        'icon': '🔥', 'col': AppColors.warning,
        'focus': isLoss ? 'Cardio + resistance combo.' : 'Progressive overload begins.',
        'days': isVeryActive ? '4–5 days/week' : '4 days/week',
        'cardio': isLoss ? '40–45 min cardio 3x/week' : '20 min jog or cycle',
        'exercises': isLoss ? intermediateLoss : intermediateGain,
      },
      {
        'level': 'Advanced', 'weeks': 'Week 11–16',
        'icon': '⚡', 'col': AppColors.neon2,
        'focus': isLoss ? 'HIIT + strength. Real fat burning.' : 'Max strength & muscle.',
        'days': isVeryActive ? '5–6 days/week' : '5 days/week',
        'cardio': isLoss ? '20 min HIIT × 3/week' : '30 min mixed cardio',
        'exercises': isLoss ? advancedLoss : advancedGain,
      },
      {
        'level': 'Master', 'weeks': 'Week 17+',
        'icon': '👑', 'col': AppColors.accent,
        'focus': isLoss ? 'Lean, athletic, sustainable.' : 'Athletic performance.',
        'days': isVeryActive ? '6 days/week' : '5–6 days/week',
        'cardio': isLoss ? 'Daily activity + 2 HIIT' : 'Sport-specific training',
        'exercises': isLoss ? masterLoss : masterGain,
      },
    ];
  }

}
