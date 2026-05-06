import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'main.dart';
import 'auth_screen.dart';
import 'notification_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userData;
  bool _loading = true;
  bool _firstTime = false;
  bool _savingOnboarding = false;
  List<Map<String, dynamic>> _weightLog = [];
  Map<String, dynamic>? _todayCheckin;
  DateTime? _lastWeighIn;

  // Onboarding
  final _nameCtrl   = TextEditingController();
  final _ageCtrl    = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  String _gender   = 'Male';
  String _activity = 'Moderately Active';
  String _dietType = 'Vegetarian';
  int _onboardStep = 0;

  final _activities = ['Sedentary', 'Lightly Active', 'Moderately Active', 'Very Active'];

  final _quotes = [
    'Mental health is as important as physical health.',
    'Don\'t starve yourself. Nourish yourself to feel your best.',
    'Consistency beats intensity. Show up every day.',
    'Progress is not always visible. Trust the process.',
    'Your body is a vehicle to be maintained, not a problem.',
    'Sleep is the most underrated fitness tool.',
    'You don\'t need to be perfect. Just consistent.',
    'Stay active — but rest too. Recovery is progress.',
  ];

  String get _quote => _quotes[DateTime.now().weekday % _quotes.length];
  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _nameCtrl.dispose(); _ageCtrl.dispose();
    _weightCtrl.dispose(); _heightCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { if (mounted) setState(() => _loading = false); return; }
    try {
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month}-${today.day}';
      final fs = FirebaseFirestore.instance;
      final results = await Future.wait([
        fs.collection('users').doc(uid).get(),
        fs.collection('users').doc(uid).collection('weightLog')
            .orderBy('date', descending: true).limit(8).get(),
        fs.collection('users').doc(uid).collection('checkins').doc(todayStr).get(),
      ]);
      if (!mounted) return;
      final userDoc    = results[0] as DocumentSnapshot;
      final weightSnap = results[1] as QuerySnapshot;
      final checkinDoc = results[2] as DocumentSnapshot;
      final data = userDoc.data() as Map<String, dynamic>?;
      if (!userDoc.exists || data == null || data['age'] == null) {
        _nameCtrl.text = FirebaseAuth.instance.currentUser?.displayName ?? '';
        if (mounted) setState(() { _firstTime = true; _loading = false; });
        return;
      }
      final wLog = weightSnap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
      DateTime? lastWeigh;
      if (wLog.isNotEmpty) {
        final ts = wLog.first['date'];
        if (ts is Timestamp) lastWeigh = ts.toDate();
      }
      if (mounted) setState(() {
        _userData    = data;
        _weightLog   = wLog;
        _lastWeighIn = lastWeigh;
        _todayCheckin = checkinDoc.exists ? checkinDoc.data() as Map<String, dynamic>? : null;
        _loading     = false;
      });
    } catch (e) {
      debugPrint('Profile load: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveOnboarding() async {
    if (_savingOnboarding) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Session expired. Please sign in again.', style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.danger,
        ));
      }
      return;
    }

    final name = _nameCtrl.text.trim().isEmpty
        ? (FirebaseAuth.instance.currentUser?.displayName ?? '').trim()
        : _nameCtrl.text.trim();
    final age = int.tryParse(_ageCtrl.text.trim());
    final weight = double.tryParse(_weightCtrl.text.trim());
    final height = double.tryParse(_heightCtrl.text.trim());

    if (name.isEmpty || age == null || weight == null || height == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Please fill all fields correctly', style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.card,
        ));
      }
      return;
    }

    if (age <= 0 || age > 120 || weight <= 0 || height <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Enter realistic age, weight and height values', style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.card,
        ));
      }
      return;
    }

    if (mounted) setState(() => _savingOnboarding = true);

    try {
      await FirebaseAuth.instance.currentUser?.updateDisplayName(name);

      final data = {
        'name': name,
        'age': age,
        'weight': weight,
        'height': height,
        'gender': _gender,
        'activity': _activity,
        'dietType': _dietType,
        'email': FirebaseAuth.instance.currentUser?.email,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(data, SetOptions(merge: true));

      // Notifications can fail on Android if permission/exact-alarm settings are blocked.
      // Do not let that break profile creation.
      try {
        await NotificationService.scheduleAllReminders();
      } catch (e) {
        debugPrint('Notification scheduling failed: $e');
      }

      if (!mounted) return;

      FocusScope.of(context).unfocus();

      setState(() {
        _userData = data;
        _weightLog = [];
        _todayCheckin = null;
        _lastWeighIn = null;
        _firstTime = false;
        _loading = false;
        _savingOnboarding = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Profile created successfully ✓', style: GoogleFonts.dmSans()),
        backgroundColor: AppColors.success.withOpacity(0.9),
        duration: const Duration(seconds: 2),
      ));
    } on FirebaseException catch (e) {
      debugPrint('Onboarding Firebase error: ${e.code} ${e.message}');
      if (mounted) {
        setState(() => _savingOnboarding = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save profile: ${e.message ?? e.code}', style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.danger,
        ));
      }
    } catch (e) {
      debugPrint('Onboarding save error: $e');
      if (mounted) {
        setState(() => _savingOnboarding = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Something went wrong. Try again.', style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.danger,
        ));
      }
    }
  }

  Future<void> _logWeight(double w) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final now = DateTime.now();
    final entry = {
      'weight': w, 'date': Timestamp.fromDate(now),
      'dateStr': '${now.day}/${now.month}/${now.year}',
    };
    await FirebaseFirestore.instance
        .collection('users').doc(uid).collection('weightLog').add(entry);
    await FirebaseFirestore.instance.collection('users').doc(uid)
        .set({'weight': w, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    if (mounted) setState(() {
      _weightLog.insert(0, entry);
      _lastWeighIn = now;
      if (_userData != null) _userData!['weight'] = w;
    });
    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveCheckin(Map<String, dynamic> data) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final today = DateTime.now();
    final key = '${today.year}-${today.month}-${today.day}';
    data['date'] = Timestamp.now();
    await FirebaseFirestore.instance
        .collection('users').doc(uid).collection('checkins').doc(key).set(data);
    if (mounted) setState(() => _todayCheckin = data);
    if (mounted) Navigator.pop(context);
  }

  bool get _canWeighIn {
    if (_lastWeighIn == null) return true;
    return DateTime.now().difference(_lastWeighIn!).inDays >= 7;
  }

  String get _nextWeighIn {
    if (_lastWeighIn == null) return '';
    final diff = (_lastWeighIn!.add(const Duration(days: 7))).difference(DateTime.now()).inDays + 1;
    return 'Next weigh-in in $diff day${diff == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0.04, 0.02),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: _loading
          ? KeyedSubtree(key: const ValueKey('profile_loading'), child: _skeleton())
          : _firstTime
              ? KeyedSubtree(key: const ValueKey('profile_onboarding'), child: _onboarding())
              : KeyedSubtree(key: const ValueKey('profile_main'), child: _profile()),
    );
  }

  // ─── SKELETON ────────────────────────────────────────────────────────
  Widget _skeleton() => Scaffold(
    backgroundColor: AppColors.bg,
    body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _shimmer(120, 12), const SizedBox(height: 6), _shimmer(160, 22)]),
          Row(children: [_shimmer(40, 40), const SizedBox(width: 8), _shimmer(40, 40)]),
        ]),
        const SizedBox(height: 20),
        _shimmer(double.infinity, 90),
        const SizedBox(height: 14),
        Row(children: List.generate(4, (i) => Expanded(child: Container(
          margin: EdgeInsets.only(right: i < 3 ? 10 : 0),
          child: _shimmer(double.infinity, 65))))),
        const SizedBox(height: 16),
        _shimmer(double.infinity, 80),
        const SizedBox(height: 16),
        _shimmer(double.infinity, 70),
      ]),
    )),
  );

  Widget _shimmer(double w, double h) => Container(
    width: w, height: h, margin: const EdgeInsets.only(bottom: 0),
    decoration: BoxDecoration(
      color: AppColors.card,
      border: Border.all(color: AppColors.border, width: 0.5)));

  // ─── ONBOARDING ──────────────────────────────────────────────────────
  Widget _onboarding() => Scaffold(
    backgroundColor: AppColors.bg,
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center,
          children: [0, 1].map((i) => AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: _onboardStep == i ? 24 : 8, height: 4,
            color: _onboardStep == i ? AppColors.accent : AppColors.border,
          )).toList()),
        const SizedBox(height: 40),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.08, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: _onboardStep == 0
                ? KeyedSubtree(key: const ValueKey('name_step'), child: _stepName())
                : KeyedSubtree(key: const ValueKey('stats_step'), child: _stepStats()),
          ),
        ),
      ]),
    )),
  );

  Widget _stepName() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('FITQUEST', style: GoogleFonts.pressStart2p(
      fontSize: 20, color: AppColors.accent,
      shadows: [Shadow(color: AppColors.accent, blurRadius: 16)])),
    const SizedBox(height: 16),
    Text('Welcome!', style: GoogleFonts.dmSans(
      fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
    const SizedBox(height: 8),
    Text('Let\'s set up your profile for personalised fitness advice.',
      style: GoogleFonts.dmSans(fontSize: 15, color: AppColors.textSecondary, height: 1.5)),
    const SizedBox(height: 36),
    _pixelLabel('YOUR NAME'),
    const SizedBox(height: 8),
    _inputBox(_nameCtrl, 'Enter your name', Icons.person_outline,
      action: TextInputAction.done,
      onSubmit: () { if (_nameCtrl.text.trim().isNotEmpty) setState(() => _onboardStep = 1); }),
    const Spacer(),
    _greenBtn('Continue →', () {
      if (_nameCtrl.text.trim().isEmpty) return;
      setState(() => _onboardStep = 1);
    }),
  ]);

  Widget _stepStats() => SingleChildScrollView(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Your baseline', style: GoogleFonts.dmSans(
      fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
    const SizedBox(height: 6),
    Text('Helps us build your personalised plan.',
      style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary)),
    const SizedBox(height: 24),
    _pixelLabel('DIET PREFERENCE'),
    const SizedBox(height: 8),
    _dietRow(_dietType, (v) => setState(() => _dietType = v)),
    const SizedBox(height: 16),
    _pixelLabel('GENDER'),
    const SizedBox(height: 8),
    _genderRow(_gender, (v) => setState(() => _gender = v)),
    const SizedBox(height: 16),
    _pixelLabel('MEASUREMENTS'),
    const SizedBox(height: 8),
    Row(children: [
      Expanded(child: _numBox(_ageCtrl, 'Age', 'yrs')),
      const SizedBox(width: 8),
      Expanded(child: _numBox(_weightCtrl, 'Weight', 'kg')),
      const SizedBox(width: 8),
      Expanded(child: _numBox(_heightCtrl, 'Height', 'cm')),
    ]),
    const SizedBox(height: 16),
    _pixelLabel('ACTIVITY LEVEL'),
    const SizedBox(height: 8),
    _activityDrop(_activity, (v) => setState(() => _activity = v)),
    const SizedBox(height: 28),
    Row(children: [
      OutlinedButton(
        onPressed: () => setState(() => _onboardStep = 0),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          side: const BorderSide(color: AppColors.border),
          shape: const RoundedRectangleBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
        child: Text('Back', style: GoogleFonts.dmSans(fontSize: 15))),
      const SizedBox(width: 12),
      Expanded(
        child: _greenBtn(
          _savingOnboarding ? 'SAVING...' : "Let's go! →",
          _savingOnboarding ? null : _saveOnboarding,
        ),
      ),
    ]),
    const SizedBox(height: 20),
  ]));

  // ─── MAIN PROFILE ────────────────────────────────────────────────────
  Widget _profile() {
    final user = FirebaseAuth.instance.currentUser;
    final name = (_userData?['name'] as String?)?.isNotEmpty == true
        ? _userData!['name'] as String
        : (user?.displayName?.isNotEmpty == true ? user!.displayName! : 'Athlete');
    final firstName = name.split(' ').first;
    final age    = _userData?['age'];
    final weight = (_userData?['weight'] as num?)?.toDouble();
    final height = (_userData?['height'] as num?)?.toDouble();
    final bmi    = (weight != null && height != null)
        ? weight / ((height / 100) * (height / 100)) : null;
    final bmiLabel = bmi == null ? '—'
        : bmi < 18.5 ? 'Underweight' : bmi < 25 ? 'Healthy'
        : bmi < 30 ? 'Overweight' : 'Obese';
    final bmiCol = bmi == null ? AppColors.textMuted
        : bmi < 18.5 ? AppColors.neon2 : bmi < 25 ? AppColors.success
        : bmi < 30 ? AppColors.warning : AppColors.danger;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Header
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Good $_greeting, $firstName 👋',
                style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text('YOUR PROFILE', style: GoogleFonts.pressStart2p(
                fontSize: 12, color: AppColors.accent,
                shadows: [Shadow(color: AppColors.accent.withOpacity(0.5), blurRadius: 8)])),
            ]),
            Row(children: [
              _iconBtn(Icons.edit_outlined, _showEdit),
              const SizedBox(width: 8),
              _iconBtn(Icons.logout_rounded, () async {
                await FirebaseAuth.instance.signOut();
              }),
            ]),
          ]),
          const SizedBox(height: 20),

          // Avatar card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: AppColors.accent.withOpacity(0.4), width: 1),
              boxShadow: [BoxShadow(
                color: AppColors.accent.withOpacity(0.06), blurRadius: 20)]),
            child: Row(children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: AppColors.accentDim,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accent, width: 2)),
                child: Center(child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'A',
                  style: GoogleFonts.pressStart2p(fontSize: 22, color: AppColors.accent)))),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: GoogleFonts.dmSans(
                  fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text(user?.email ?? '', style: GoogleFonts.dmSans(
                  fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                if (bmi != null) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: bmiCol.withOpacity(0.15),
                    border: Border.all(color: bmiCol.withOpacity(0.4))),
                  child: Text('BMI $bmiLabel', style: GoogleFonts.pressStart2p(
                    fontSize: 7, color: bmiCol))),
              ])),
            ]),
          ),
          const SizedBox(height: 14),

          // Stat tiles
          Row(children: [
            Expanded(child: _statTile('AGE', age != null ? '$age' : '—', 'yrs', AppColors.neon2)),
            const SizedBox(width: 8),
            Expanded(child: _statTile('WEIGHT', weight != null ? weight.toStringAsFixed(1) : '—', 'kg', AppColors.accent)),
            const SizedBox(width: 8),
            Expanded(child: _statTile('HEIGHT', height != null ? height.toStringAsFixed(0) : '—', 'cm', AppColors.textSecondary)),
            const SizedBox(width: 8),
            Expanded(child: _statTile('BMI', bmi != null ? bmi.toStringAsFixed(1) : '—', bmiLabel, bmiCol)),
          ]),
          const SizedBox(height: 16),

          // Daily insight
          Container(
            width: double.infinity, padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: AppColors.accent.withOpacity(0.25))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.auto_awesome_rounded, color: AppColors.accent, size: 14),
                const SizedBox(width: 6),
                Text('DAILY INSIGHT', style: GoogleFonts.pressStart2p(
                  fontSize: 7, color: AppColors.accent)),
              ]),
              const SizedBox(height: 10),
              Text('"$_quote"', style: GoogleFonts.dmSans(
                fontSize: 14, color: AppColors.textSecondary,
                height: 1.6, fontStyle: FontStyle.italic)),
            ]),
          ),
          const SizedBox(height: 16),

          // Check-in
          _sectionRow('TODAY\'S CHECK-IN',
            _todayCheckin == null ? _pill('Check in', _showCheckin) : null),
          const SizedBox(height: 10),
          _todayCheckin != null ? _checkinDone() : _checkinPrompt(),
          const SizedBox(height: 16),

          // Weigh-in
          _sectionRow('WEEKLY WEIGH-IN',
            _canWeighIn ? _pill('+ Log', _showWeighIn) : null),
          const SizedBox(height: 10),
          if (!_canWeighIn)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.border)),
              child: Row(children: [
                const Icon(Icons.lock_outline_rounded, color: AppColors.textMuted, size: 18),
                const SizedBox(width: 10),
                Text(_nextWeighIn, style: GoogleFonts.dmSans(
                  fontSize: 13, color: AppColors.textSecondary)),
              ]))
          else
            _weightWidget(),
        ]),
      )),
    );
  }

  // ─── EDIT SHEET ──────────────────────────────────────────────────────
  void _showEdit() {
    final nameC = TextEditingController(text: _userData?['name'] ?? '');
    final ageC  = TextEditingController(text: (_userData?['age'] as num?)?.toString() ?? '');
    final wC    = TextEditingController(text: (_userData?['weight'] as num?)?.toString() ?? '');
    final hC    = TextEditingController(text: (_userData?['height'] as num?)?.toString() ?? '');
    String act  = _userData?['activity'] ?? 'Moderately Active';
    String gen  = _userData?['gender'] ?? 'Male';
    String diet = _userData?['dietType'] ?? 'Vegetarian';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(),
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24,
          MediaQuery.of(context).viewInsets.bottom + 24),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          _handle(),
          const SizedBox(height: 16),
          Text('EDIT PROFILE', style: GoogleFonts.pressStart2p(
            fontSize: 10, color: AppColors.accent)),
          const SizedBox(height: 20),
          _pixelLabel('NAME'),
          const SizedBox(height: 8),
          _inputBox(nameC, 'Your name', Icons.person_outline),
          const SizedBox(height: 14),
          _pixelLabel('DIET'),
          const SizedBox(height: 8),
          _dietRow(diet, (d) => setS(() => diet = d)),
          const SizedBox(height: 14),
          _pixelLabel('GENDER'),
          const SizedBox(height: 8),
          _genderRow(gen, (g) => setS(() => gen = g)),
          const SizedBox(height: 14),
          _pixelLabel('MEASUREMENTS'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _numBox(ageC, 'Age', 'yrs')),
            const SizedBox(width: 8),
            Expanded(child: _numBox(wC, 'Weight', 'kg')),
            const SizedBox(width: 8),
            Expanded(child: _numBox(hC, 'Height', 'cm')),
          ]),
          const SizedBox(height: 14),
          _pixelLabel('ACTIVITY LEVEL'),
          const SizedBox(height: 8),
          _activityDrop(act, (v) => setS(() => act = v)),
          const SizedBox(height: 24),
          _greenBtn('Save Changes', () async {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid == null) return;
            final name   = nameC.text.trim();
            final age    = int.tryParse(ageC.text.trim());
            final weight = double.tryParse(wC.text.trim());
            final height = double.tryParse(hC.text.trim());
            if (name.isEmpty || age == null || weight == null || height == null) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text('Fill all fields', style: GoogleFonts.dmSans()),
                backgroundColor: AppColors.card));
              return;
            }
            await FirebaseAuth.instance.currentUser?.updateDisplayName(name);
            final update = {
              'name': name, 'age': age, 'weight': weight, 'height': height,
              'gender': gen, 'activity': act, 'dietType': diet,
              'updatedAt': FieldValue.serverTimestamp(),
            };
            await FirebaseFirestore.instance.collection('users').doc(uid)
                .set(update, SetOptions(merge: true));
            if (mounted) setState(() => _userData = {...?_userData, ...update});
            if (mounted) Navigator.pop(context);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Profile saved ✓', style: GoogleFonts.dmSans()),
              backgroundColor: AppColors.success.withOpacity(0.8)));
          }),
          const SizedBox(height: 8),
        ])),
      )),
    );
  }

  // ─── CHECK-IN SHEET ──────────────────────────────────────────────────
  void _showCheckin() {
    String mood = '';
    bool ate = false, worked = false, slept = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(),
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          _handle(),
          const SizedBox(height: 16),
          Text('DAILY CHECK-IN', style: GoogleFonts.pressStart2p(
            fontSize: 10, color: AppColors.accent)),
          const SizedBox(height: 4),
          Text('Quick — 3 taps and done.',
            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          Text('How are you feeling today?',
            style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textSecondary,
              fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['😴','😕','😐','🙂','🔥'].map((e) => GestureDetector(
              onTap: () => setS(() => mood = e),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: mood == e ? AppColors.accentDim : AppColors.card,
                  border: Border.all(
                    color: mood == e ? AppColors.accent : AppColors.border,
                    width: mood == e ? 2 : 1)),
                child: Center(child: Text(e, style: const TextStyle(fontSize: 24)))),
            )).toList()),
          const SizedBox(height: 20),
          Text('Today I...', style: GoogleFonts.dmSans(
            fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          _tapTile('🥗', 'Ate according to my diet', ate, (v) => setS(() => ate = v)),
          const SizedBox(height: 8),
          _tapTile('💪', 'Worked out today', worked, (v) => setS(() => worked = v)),
          const SizedBox(height: 8),
          _tapTile('😴', 'Got enough sleep last night', slept, (v) => setS(() => slept = v)),
          const SizedBox(height: 24),
          _greenBtn('Save Check-in', mood.isEmpty ? null : () => _saveCheckin({
            'mood': mood, 'ateDiet': ate, 'workedOut': worked, 'sleptWell': slept,
          })),
          const SizedBox(height: 8),
        ]),
      )),
    );
  }

  // ─── WEIGH-IN SHEET ──────────────────────────────────────────────────
  void _showWeighIn() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24,
          MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          _handle(),
          const SizedBox(height: 16),
          Text('LOG WEIGHT', style: GoogleFonts.pressStart2p(
            fontSize: 10, color: AppColors.accent)),
          const SizedBox(height: 4),
          Text('Weigh yourself at the same time each week.',
            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: AppColors.card, border: Border.all(color: AppColors.border)),
            child: TextField(
              controller: ctrl, autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                final w = double.tryParse(ctrl.text);
                if (w != null && w > 0) _logWeight(w);
              },
              style: GoogleFonts.pressStart2p(color: AppColors.accent, fontSize: 28),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                hintText: '0.0',
                hintStyle: GoogleFonts.pressStart2p(color: AppColors.textMuted, fontSize: 28),
                suffixText: 'kg',
                suffixStyle: GoogleFonts.dmSans(color: AppColors.textSecondary, fontSize: 16),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(20))),
          ),
          const SizedBox(height: 16),
          _greenBtn('Save', () {
            final w = double.tryParse(ctrl.text);
            if (w != null && w > 0) _logWeight(w);
          }),
        ]),
      ),
    );
  }

  // ─── HELPERS ─────────────────────────────────────────────────────────
  Widget _handle() => Center(child: Container(
    width: 36, height: 4, color: AppColors.border));

  Widget _pixelLabel(String t) => Text(t, style: GoogleFonts.pressStart2p(
    fontSize: 8, color: AppColors.textSecondary, letterSpacing: 1));

  Widget _greenBtn(String label, VoidCallback? onTap) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: onTap == null ? AppColors.accentDim : AppColors.accent,
        boxShadow: onTap == null ? [] : [
          BoxShadow(color: AppColors.accent.withOpacity(0.3), blurRadius: 10)]),
      child: Center(
        child: label == 'SAVING...'
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.bg,
                ),
              )
            : Text(label, style: GoogleFonts.pressStart2p(
                fontSize: 9, color: AppColors.bg, letterSpacing: 1)),
      ),
    ),
  );

  Widget _iconBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 1)),
      child: Icon(icon, color: AppColors.textSecondary, size: 18)));

  Widget _pill(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accentDim,
        border: Border.all(color: AppColors.accent.withOpacity(0.5))),
      child: Text(label, style: GoogleFonts.pressStart2p(
        fontSize: 7, color: AppColors.accent))));

  Widget _sectionRow(String title, Widget? action) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(title, style: GoogleFonts.pressStart2p(fontSize: 8, color: AppColors.accent)),
      if (action != null) action,
    ]);

  Widget _statTile(String label, String val, String sub, Color col) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.card, border: Border.all(color: AppColors.border, width: 1)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.pressStart2p(fontSize: 6, color: AppColors.textMuted)),
      const SizedBox(height: 6),
      Text(val, style: GoogleFonts.pressStart2p(fontSize: 13, color: col,
        shadows: [Shadow(color: col.withOpacity(0.6), blurRadius: 6)])),
      const SizedBox(height: 2),
      Text(sub, style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.textMuted)),
    ]));

  Widget _inputBox(TextEditingController ctrl, String hint, IconData icon,
      {TextInputAction action = TextInputAction.next, VoidCallback? onSubmit}) =>
    Container(
      decoration: BoxDecoration(
        color: AppColors.card, border: Border.all(color: AppColors.border)),
      child: TextField(
        controller: ctrl, textInputAction: action,
        onSubmitted: onSubmit != null ? (_) => onSubmit() : null,
        style: GoogleFonts.dmSans(color: AppColors.textPrimary, fontSize: 15),
        cursorColor: AppColors.accent,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 14),
          prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16))));

  Widget _numBox(TextEditingController ctrl, String label, String unit) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.card, border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.pressStart2p(fontSize: 7, color: AppColors.textMuted)),
      const SizedBox(height: 6),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: TextField(
          controller: ctrl, keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
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

  Widget _dietRow(String current, Function(String) onChange) => Row(
    children: ['Vegetarian', 'Non-Vegetarian'].map((d) {
      final sel = current == d;
      return Expanded(child: GestureDetector(
        onTap: () => onChange(d),
        child: Container(
          margin: EdgeInsets.only(right: d == 'Vegetarian' ? 8 : 0),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: sel ? AppColors.accentDim : AppColors.card,
            border: Border.all(color: sel ? AppColors.accent : AppColors.border, width: sel ? 2 : 1)),
          child: Center(child: Text(d == 'Vegetarian' ? '🥦 Veg' : '🍗 Non-Veg',
            style: GoogleFonts.dmSans(
              color: sel ? AppColors.accent : AppColors.textSecondary,
              fontWeight: sel ? FontWeight.w700 : FontWeight.normal, fontSize: 14))))));
    }).toList());

  Widget _genderRow(String current, Function(String) onChange) => Row(
    children: ['Male', 'Female'].map((g) {
      final sel = current == g;
      return Expanded(child: GestureDetector(
        onTap: () => onChange(g),
        child: Container(
          margin: EdgeInsets.only(right: g == 'Male' ? 8 : 0),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: sel ? AppColors.accentDim : AppColors.card,
            border: Border.all(color: sel ? AppColors.accent : AppColors.border, width: sel ? 2 : 1)),
          child: Center(child: Text(g == 'Male' ? '♂  Male' : '♀  Female',
            style: GoogleFonts.dmSans(
              color: sel ? AppColors.accent : AppColors.textSecondary,
              fontWeight: sel ? FontWeight.w700 : FontWeight.normal, fontSize: 14))))));
    }).toList());

  Widget _activityDrop(String current, Function(String) onChange) => Container(
    decoration: BoxDecoration(
      color: AppColors.card, border: Border.all(color: AppColors.border)),
    child: DropdownButtonFormField<String>(
      value: current, dropdownColor: AppColors.card,
      style: GoogleFonts.dmSans(color: AppColors.textPrimary, fontSize: 14),
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        prefixIcon: Icon(Icons.bolt_rounded, color: AppColors.accent, size: 18)),
      items: _activities.map((a) => DropdownMenuItem(
        value: a, child: Text(a))).toList(),
      onChanged: (v) { if (v != null) onChange(v); }));

  Widget _tapTile(String emoji, String label, bool val, Function(bool) onChange) =>
    GestureDetector(
      onTap: () => onChange(!val),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: val ? AppColors.accentDim : AppColors.card,
          border: Border.all(color: val ? AppColors.accent : AppColors.border, width: val ? 2 : 1)),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: GoogleFonts.dmSans(
            fontSize: 14,
            color: val ? AppColors.accent : AppColors.textSecondary,
            fontWeight: val ? FontWeight.w500 : FontWeight.normal))),
          Icon(val ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
            color: val ? AppColors.accent : AppColors.textMuted, size: 20),
        ])));

  Widget _checkinPrompt() => GestureDetector(
    onTap: _showCheckin,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card, border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          color: AppColors.accentDim,
          child: const Text('☀️', style: TextStyle(fontSize: 20))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('How\'s your day?', style: GoogleFonts.dmSans(
            fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          Text('Tap to do your daily check-in',
            style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted)),
        ])),
        const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      ])));

  Widget _checkinDone() {
    final d = _todayCheckin!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.success.withOpacity(0.4))),
      child: Column(children: [
        Row(children: [
          Text(d['mood'] ?? '🙂', style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Check-in done ✓', style: GoogleFonts.dmSans(
              fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.success)),
            Text('See you tomorrow!',
              style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted)),
          ])),
        ]),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _badge('🥗', 'Diet', d['ateDiet'] == true),
          _badge('💪', 'Workout', d['workedOut'] == true),
          _badge('😴', 'Sleep', d['sleptWell'] == true),
        ]),
      ]));
  }

  Widget _badge(String e, String label, bool done) => Column(children: [
    Text(e, style: TextStyle(fontSize: 22,
      color: done ? Colors.white : Colors.white.withOpacity(0.2))),
    const SizedBox(height: 4),
    Text(label, style: GoogleFonts.dmSans(
      fontSize: 11, color: done ? AppColors.textSecondary : AppColors.textMuted)),
    Icon(done ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
      color: done ? AppColors.success : AppColors.textMuted, size: 14),
  ]);

  Widget _weightWidget() {
    if (_weightLog.isEmpty) return GestureDetector(
      onTap: _showWeighIn,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card, border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(10), color: AppColors.accentDim,
            child: const Icon(Icons.monitor_weight_outlined, color: AppColors.accent, size: 20)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('No weigh-ins yet', style: GoogleFonts.dmSans(
              fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Text('Log your first weight to track progress',
              style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ])));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card, border: Border.all(color: AppColors.border)),
      child: Column(children: _weightLog.take(5).toList().asMap().entries.map((e) {
        final isFirst = e.key == 0;
        final entry   = e.value;
        final isLast  = e.key == (_weightLog.length - 1).clamp(0, 4);
        double? diff;
        if (!isLast && e.key + 1 < _weightLog.length) {
          diff = (entry['weight'] as num).toDouble()
               - (_weightLog[e.key + 1]['weight'] as num).toDouble();
        }
        return Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                if (isFirst) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    color: AppColors.accentDim,
                    child: Text('LATEST', style: GoogleFonts.pressStart2p(
                      fontSize: 7, color: AppColors.accent))),
                  const SizedBox(width: 8),
                ],
                Text(entry['dateStr'] ?? '', style: GoogleFonts.dmSans(
                  fontSize: 13, color: AppColors.textSecondary)),
              ]),
              Row(children: [
                if (diff != null) ...[
                  Icon(diff <= 0 ? Icons.south_rounded : Icons.north_rounded,
                    color: diff <= 0 ? AppColors.success : AppColors.danger, size: 13),
                  const SizedBox(width: 3),
                  Text('${diff.abs().toStringAsFixed(1)} kg',
                    style: GoogleFonts.dmSans(fontSize: 12,
                      color: diff <= 0 ? AppColors.success : AppColors.danger)),
                  const SizedBox(width: 10),
                ],
                Text('${entry['weight']} kg', style: GoogleFonts.dmSans(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ]),
            ])),
          if (!isLast) Container(height: 1, color: AppColors.border),
        ]);
      }).toList()));
  }
}
