import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'main.dart';

class Quest {
  final String id;
  final String title;
  final String desc;
  final String detail;
  final String type;
  final String category;
  final int xp;
  final String difficulty;
  final Color diffCol;
  final String icon;
  final List<String> tags;
  final String time;
  final int kcal;
  final int steps;
  final String physicalGain;
  final String achievement;
  final double radiusMeters;
  final String verifyLabel;

  const Quest({
    required this.id, required this.title, required this.desc,
    required this.detail, required this.type, required this.category,
    required this.xp, required this.difficulty, required this.diffCol,
    required this.icon, required this.tags, required this.time,
    required this.kcal, required this.steps, required this.physicalGain,
    required this.achievement, required this.radiusMeters,
    required this.verifyLabel,
  });

  String get distanceLabel => radiusMeters >= 1000
      ? '${(radiusMeters / 1000).toStringAsFixed(1)} km'
      : '${radiusMeters.toStringAsFixed(0)} m';
}

String _readable(double m) =>
    m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.toStringAsFixed(0)} m';

final List<Quest> allQuests = [
  Quest(
    id: 'metro_bound', title: 'Metro Bound', category: 'Walk',
    icon: '🚇', difficulty: 'Easy', diffCol: AppColors.success,
    xp: 150, kcal: 180, steps: 3500, time: '~20–40 min',
    radiusMeters: 1500,
    verifyLabel: 'Walk 1.5 km from your starting point',
    tags: ['Outdoor', 'Walking', 'GPS'], type: 'gps',
    desc: 'Walk at least 1.5 km — ideally towards a metro station near you.',
    detail: 'Head out and walk at least 1.5 km from where you started. '
        'Try to walk towards the nearest metro station. '
        'When you\'ve covered the distance, tap "Check My Location" to verify.',
    physicalGain: 'A 1.5 km brisk walk burns ~180 kcal and strengthens your heart.',
    achievement: 'You walked to the metro and back. That\'s real city fitness!',
  ),
  Quest(
    id: 'park_spotter', title: 'Park Spotter', category: 'Find',
    icon: '🌳', difficulty: 'Easy', diffCol: AppColors.success,
    xp: 120, kcal: 120, steps: 2500, time: '~20–30 min',
    radiusMeters: 1000,
    verifyLabel: 'Walk 1 km from your starting point',
    tags: ['Outdoor', 'Discovery', 'GPS'], type: 'gps',
    desc: 'Walk 1 km to find a park or garden you\'ve never visited.',
    detail: 'Head out and walk at least 1 km from where you started. '
        'Find a park, garden, or any green space you haven\'t been to before. '
        'Walk around it at least once then tap "Check My Location".',
    physicalGain: 'Walking in green spaces reduces stress hormones by up to 16%.',
    achievement: 'You found a new park. Nature is the best gym!',
  ),
  Quest(
    id: 'red_object', title: 'The Red Object Hunt', category: 'Find',
    icon: '🔴', difficulty: 'Easy', diffCol: AppColors.success,
    xp: 80, kcal: 90, steps: 1500, time: '~15–25 min',
    radiusMeters: 800,
    verifyLabel: 'Walk 800 m from your starting point',
    tags: ['Observation', 'Creative', 'Walking'], type: 'honour',
    desc: 'Walk 800 m and find something red you\'d normally walk past.',
    detail: 'Walk at least 800 m from where you started. Along the way, find something '
        'red that is NOT a vehicle, traffic light, or clothing. '
        'Think — a red door, postbox, flower, or sign. '
        'Once you\'ve walked the distance and found your object, tap "I Found It!"',
    physicalGain: 'Mindful observation walks improve focus and reduce anxiety.',
    achievement: 'You trained your eyes to see what others miss. That\'s mindfulness!',
  ),
  Quest(
    id: 'floor_climb', title: '10-Floor Climb', category: 'Challenge',
    icon: '🏢', difficulty: 'Medium', diffCol: AppColors.warning,
    xp: 200, kcal: 150, steps: 800, time: '~15–25 min',
    radiusMeters: 300,
    verifyLabel: 'Leave your building (300 m movement)',
    tags: ['Cardio', 'Strength', 'Legs'], type: 'honour',
    desc: 'Find a building and climb 10 floors using only the stairs.',
    detail: 'Walk to any building with at least 10 floors — your college, an apartment, '
        'or office building. No elevator allowed. Climb all 10 floors in one go. '
        'GPS will verify you left home. Tap "I Completed This" when done.',
    physicalGain: 'Stair climbing burns 3x more calories than flat walking per minute.',
    achievement: 'You climbed 10 floors. Your legs and lungs earned this!',
  ),
  Quest(
    id: 'water_body', title: 'Water Body Walk', category: 'Walk',
    icon: '💧', difficulty: 'Medium', diffCol: AppColors.warning,
    xp: 180, kcal: 280, steps: 5500, time: '~35–50 min',
    radiusMeters: 2000,
    verifyLabel: 'Walk 2 km from your starting point',
    tags: ['Outdoor', 'Mindful', 'GPS'], type: 'gps',
    desc: 'Walk 2 km to find any lake, pond, river, or fountain.',
    detail: 'Head out and walk at least 2 km from where you started. '
        'Find any body of water — a lake, pond, river, canal, or decorative fountain. '
        'Sit near it for at least 5 minutes, then tap "Check My Location".',
    physicalGain: 'Long walks improve endurance and completely clear mental fog.',
    achievement: 'You found water in the city. A peaceful warrior move!',
  ),
  Quest(
    id: 'ancient_spotter', title: 'Spot Something Ancient', category: 'Find',
    icon: '🏛️', difficulty: 'Medium', diffCol: AppColors.warning,
    xp: 130, kcal: 160, steps: 2800, time: '~25–40 min',
    radiusMeters: 1200,
    verifyLabel: 'Walk 1.2 km from your starting point',
    tags: ['Discovery', 'Culture', 'Walking'], type: 'honour',
    desc: 'Walk 1.2 km and find something over 50 years old.',
    detail: 'Walk at least 1.2 km from where you started. Look for heritage buildings, '
        'ancient trees, old temples, colonial-era structures, or any monument. '
        'When you find something old and interesting, tap "I Found It!"',
    physicalGain: 'Walking + curiosity is a proven mood booster combination.',
    achievement: 'You connected with history on foot. Culture AND fitness!',
  ),
  Quest(
    id: 'morning_5k', title: '5K Morning Run', category: 'Challenge',
    icon: '🏃', difficulty: 'Hard', diffCol: AppColors.danger,
    xp: 300, kcal: 320, steps: 6500, time: '~25–40 min',
    radiusMeters: 4500,
    verifyLabel: 'Cover 4.5 km from your starting point',
    tags: ['Running', 'Morning', 'Cardio'], type: 'honour',
    desc: 'Run or walk 4.5 km before 8 AM — your hardest quest yet.',
    detail: 'Before 8:00 AM, head out and cover at least 4.5 km from where you started. '
        'You can walk portions but keep moving. '
        'GPS will verify your distance. Tap "I Completed This" when done.',
    physicalGain: 'Morning runs boost your metabolism for the entire rest of the day.',
    achievement: 'A 4.5K before 8 AM. Most people are still asleep. You\'re not!',
  ),
  Quest(
    id: 'colour_quest', title: 'The Colour Quest', category: 'Find',
    icon: '🎨', difficulty: 'Hard', diffCol: AppColors.danger,
    xp: 160, kcal: 200, steps: 3800, time: '~30–50 min',
    radiusMeters: 1500,
    verifyLabel: 'Walk 1.5 km from your starting point',
    tags: ['Creative', 'Walking', 'Observation'], type: 'honour',
    desc: 'Walk 1.5 km and find red, yellow, blue, and green objects.',
    detail: 'Walk at least 1.5 km from where you started. Along the way find one fixed '
        'object (NOT clothing or vehicles) in each colour: red, yellow, blue, green. '
        'All four must be found in one outing. Tap "I Completed This" when done.',
    physicalGain: 'Observation walks build mental sharpness and burn steady calories.',
    achievement: 'Four colours, one walk. You saw the world differently today!',
  ),
  Quest(
    id: 'sunrise_walk', title: 'Sunrise Walk', category: 'Walk',
    icon: '🌅', difficulty: 'Medium', diffCol: AppColors.warning,
    xp: 200, kcal: 220, steps: 4000, time: '~30–45 min',
    radiusMeters: 2000,
    verifyLabel: 'Walk 2 km before 7 AM',
    tags: ['Morning', 'Mindful', 'GPS'], type: 'gps',
    desc: 'Walk 2 km before 7 AM and catch the morning air.',
    detail: 'Before 7:00 AM, head outside and walk at least 2 km from where you started. '
        'No earphones — just you, the morning air, and your thoughts. '
        'Tap "Check My Location" when you\'ve covered the distance.',
    physicalGain: 'Morning light resets your circadian rhythm and improves sleep quality.',
    achievement: 'You owned the morning before the world woke up!',
  ),
  Quest(
    id: 'market_run', title: 'Local Market Run', category: 'Walk',
    icon: '🛒', difficulty: 'Easy', diffCol: AppColors.success,
    xp: 100, kcal: 130, steps: 2200, time: '~20–30 min',
    radiusMeters: 1000,
    verifyLabel: 'Walk 1 km from your starting point',
    tags: ['Outdoor', 'Daily Life', 'GPS'], type: 'gps',
    desc: 'Walk 1 km to your nearest local market or shop.',
    detail: 'Head to any local market, sabzi mandi, or shop that is at least 1 km away. '
        'Walk there — no auto or bike. Buy something if you like. '
        'Tap "Check My Location" when you\'ve reached the distance.',
    physicalGain: 'Replacing short vehicle trips with walks adds thousands of steps weekly.',
    achievement: 'You turned an errand into a workout. That\'s lifestyle fitness!',
  ),
  Quest(
    id: 'shadow_trace', title: 'Shadow Tracer', category: 'Find',
    icon: '☀️', difficulty: 'Easy', diffCol: AppColors.success,
    xp: 90, kcal: 80, steps: 1400, time: '~15–20 min',
    radiusMeters: 700,
    verifyLabel: 'Walk 700 m from your starting point',
    tags: ['Outdoor', 'Creative', 'Mindful'], type: 'honour',
    desc: 'Walk 700 m and find the longest shadow you can see.',
    detail: 'Walk at least 700 m from where you started during daylight hours. '
        'Look for the longest shadow cast by a tree, building, or structure. '
        'Stand in it for a moment and notice how it feels. '
        'Tap "I Found It!" when done.',
    physicalGain: 'Short mindful walks reduce cortisol and improve mood within minutes.',
    achievement: 'You noticed something most people walk past every day. Eyes open!',
  ),
  Quest(
    id: 'hill_hunt', title: 'Find the High Ground', category: 'Challenge',
    icon: '⛰️', difficulty: 'Hard', diffCol: AppColors.danger,
    xp: 250, kcal: 300, steps: 5800, time: '~40–60 min',
    radiusMeters: 2500,
    verifyLabel: 'Walk 2.5 km from your starting point',
    tags: ['Outdoor', 'Cardio', 'Elevation'], type: 'gps',
    desc: 'Walk 2.5 km and find the highest point you can reach on foot.',
    detail: 'Head out and walk at least 2.5 km from where you started. '
        'Find the highest point accessible on foot — a rooftop terrace, overpass, '
        'hill, or elevated park. Stand at the top and look around. '
        'Tap "Check My Location" when you\'ve covered the distance.',
    physicalGain: 'Uphill walking activates your glutes and burns 50% more than flat walks.',
    achievement: 'You found high ground. A warrior always scouts the terrain!',
  ),
];

class QuestScreen extends StatefulWidget {
  const QuestScreen({super.key});
  @override
  State<QuestScreen> createState() => _QuestScreenState();
}

class _QuestScreenState extends State<QuestScreen> {
  int _filter = 0;
  Quest? _activeQuest;
  bool _loadingQuest = true;
  int _totalXp = 0;
  List<String> _completedIds = [];
  Map<String, int> _abandonCounts = {};
  List<String> get _abandonedIds => _abandonCounts.keys.toList();

  final _filters = ['All', 'Walk', 'Find', 'Challenge'];

  @override
  void initState() {
    super.initState();
    _loadActiveQuest();
  }

  Future<void> _loadActiveQuest() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loadingQuest = false); return; }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('quests').doc('status').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final activeId = data['activeQuestId'] as String?;
        _totalXp = (data['totalXp'] as num?)?.toInt() ?? 0;
        _completedIds = List<String>.from(data['completedIds'] ?? []);
        final rawAbandoned = data['abandonCounts'];
        if (rawAbandoned is Map) {
          _abandonCounts = rawAbandoned.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
        }
        if (activeId != null) {
          try {
            _activeQuest = allQuests.firstWhere((q) => q.id == activeId);
          } catch (_) {}
        }
      }
    } catch (e) { debugPrint('Quest load: $e'); }
    if (mounted) setState(() => _loadingQuest = false);
  }

  Future<void> _acceptQuest(Quest quest) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users').doc(uid).collection('quests').doc('status')
        .set({'activeQuestId': quest.id, 'totalXp': _totalXp,
              'completedIds': _completedIds, 'abandonCounts': _abandonCounts},
            SetOptions(merge: true));
    if (mounted) setState(() => _activeQuest = quest);
  }

  Future<void> _completeQuest(Quest quest) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final newXp = _totalXp + quest.xp;
    final newCompleted = [..._completedIds, quest.id];
    await FirebaseFirestore.instance
        .collection('users').doc(uid).collection('quests').doc('status')
        .set({'activeQuestId': null, 'totalXp': newXp,
              'completedIds': newCompleted, 'abandonCounts': _abandonCounts},
            SetOptions(merge: true));
    await FirebaseFirestore.instance
        .collection('users').doc(uid).collection('quests').doc(quest.id)
        .set({'completedAt': FieldValue.serverTimestamp(), 'xpEarned': quest.xp});
    if (mounted) setState(() {
      _activeQuest = null;
      _totalXp = newXp;
      _completedIds = newCompleted;
    });
  }

  Future<void> _abandonQuest(Quest quest) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final newCounts = {..._abandonCounts, quest.id: (_abandonCounts[quest.id] ?? 0) + 1};
    await FirebaseFirestore.instance
        .collection('users').doc(uid).collection('quests').doc('status')
        .set({'activeQuestId': null, 'abandonCounts': newCounts},
            SetOptions(merge: true));
    if (mounted) setState(() {
      _activeQuest = null;
      _abandonCounts = newCounts;
    });
  }

  int _abandonCount(String id) => _abandonCounts[id] ?? 0;

  List<Quest> get _filtered {
    if (_filter == 0) return allQuests;
    return allQuests.where((q) => q.category == _filters[_filter]).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _loadingQuest
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : SafeArea(child: CustomScrollView(slivers: [
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('SIDE QUESTS', style: GoogleFonts.pressStart2p(
                    fontSize: 13, color: AppColors.accent,
                    shadows: [Shadow(color: AppColors.accent, blurRadius: 8)])),
                  const SizedBox(height: 6),
                  Text('GET OUTSIDE. DO SOMETHING REAL.',
                    style: GoogleFonts.pressStart2p(fontSize: 6, color: AppColors.textSecondary)),
                  const SizedBox(height: 16),

                  // XP Banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        AppColors.accentDim, AppColors.accent.withOpacity(0.12)]),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: AppColors.accent.withOpacity(0.25))),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Text('TOTAL XP', style: GoogleFonts.pressStart2p(
                          fontSize: 7, color: AppColors.textSecondary)),
                        const SizedBox(height: 6),
                        Text('$_totalXp PTS', style: GoogleFonts.pressStart2p(
                          fontSize: 18, color: AppColors.accent,
                          shadows: [Shadow(color: AppColors.accent, blurRadius: 12)])),
                        Row(children: [
                          Text('${_completedIds.length} completed',
                            style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.success)),
                          if (_abandonCounts.isNotEmpty) ...[
                            Text('  ·  ', style: GoogleFonts.dmSans(
                              fontSize: 11, color: AppColors.textMuted)),
                            Text('${_abandonCounts.length} abandoned',
                              style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.danger.withOpacity(0.8))),
                          ],
                        ]),
                      ])),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.15), shape: BoxShape.circle),
                        child: const Icon(Icons.emoji_events_rounded,
                          color: AppColors.neon2, size: 28)),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  if (_activeQuest != null) ...[
                    _activeQuestBanner(),
                    const SizedBox(height: 16),
                  ],

                  // Filters
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: _filters.asMap().entries.map((e) {
                      final sel = _filter == e.key;
                      return GestureDetector(
                        onTap: () => setState(() => _filter = e.key),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: sel ? AppColors.accent : AppColors.card,
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(color: sel ? AppColors.accent : AppColors.border)),
                          child: Text(e.value, style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: sel ? Colors.white : AppColors.textSecondary,
                            fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
                        ),
                      );
                    }).toList()),
                  ),
                  const SizedBox(height: 20),
                ]),
              )),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                sliver: SliverList(delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _questCard(_filtered[i]),
                  childCount: _filtered.length,
                )),
              ),
            ])),
    );
  }

  Widget _activeQuestBanner() {
    final q = _activeQuest!;
    return GestureDetector(
      onTap: () => _openActiveQuest(q),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.warning.withOpacity(0.08),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: AppColors.warning.withOpacity(0.4))),
        child: Row(children: [
          Text(q.icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2)),
              child: Text('ACTIVE QUEST', style: GoogleFonts.dmSans(
                fontSize: 10, color: AppColors.warning,
                fontWeight: FontWeight.w700, letterSpacing: 1))),
            const SizedBox(height: 5),
            Text(q.title, style: GoogleFonts.dmSans(
              fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            Text(q.verifyLabel, style: GoogleFonts.dmSans(
              fontSize: 12, color: AppColors.textMuted)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ]),
      ),
    );
  }

  Widget _questCard(Quest q) {
    final isActive = _activeQuest?.id == q.id;
    final isCompleted = _completedIds.contains(q.id);
    final isAbandoned = _abandonCounts.containsKey(q.id);
    final isLocked = _activeQuest != null && !isActive;

    Color borderCol = AppColors.border;
    Color bgCol = AppColors.card;
    if (isActive) { borderCol = AppColors.warning.withOpacity(0.4); bgCol = AppColors.warning.withOpacity(0.05); }
    if (isCompleted) { borderCol = AppColors.success.withOpacity(0.3); bgCol = AppColors.success.withOpacity(0.04); }
    if (isAbandoned) { borderCol = AppColors.border; bgCol = AppColors.bg; }

    return GestureDetector(
      onTap: () {
        if (isLocked) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Finish your active quest first!', style: GoogleFonts.dmSans()),
            backgroundColor: AppColors.card));
          return;
        }
        if (isActive) { _openActiveQuest(q); return; }
        if (!isCompleted) _showQuestDetail(q);
      },
      child: Opacity(
        opacity: isAbandoned ? 0.5 : isLocked ? 0.45 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: bgCol, borderRadius: BorderRadius.circular(2),
            border: Border.all(color: borderCol, width: 0.5)),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.bg, borderRadius: BorderRadius.circular(2)),
                  child: Center(child: Text(q.icon, style: const TextStyle(fontSize: 26)))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Expanded(child: Text(q.title.toUpperCase(), style: GoogleFonts.pressStart2p(
                      fontSize: 8,
                      color: AppColors.textPrimary))),
                    if (isCompleted)
                      const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20)
                    else if (isAbandoned)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: AppColors.danger.withOpacity(0.3))),
                        child: Text('Tried ${_abandonCount(q.id)}×', style: GoogleFonts.dmSans(
                          fontSize: 11, color: AppColors.danger,
                          fontWeight: FontWeight.w600)))
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: q.diffCol.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: q.diffCol.withOpacity(0.3))),
                        child: Text(q.difficulty, style: GoogleFonts.dmSans(
                          fontSize: 11, color: q.diffCol, fontWeight: FontWeight.w600))),
                  ]),
                  const SizedBox(height: 5),
                  Text(q.desc, style: GoogleFonts.dmSans(
                    fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    _chip(Icons.straighten_rounded, q.distanceLabel),
                    _chip(Icons.timer_outlined, q.time),
                    _chip(Icons.star_outline_rounded, '+${q.xp} XP'),
                    _chip(Icons.local_fire_department_outlined, '~${q.kcal} kcal'),
                  ]),
                ])),
              ]),
            ),
            Container(height: 0.5, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: q.tags.take(2).map((t) => Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.bg, borderRadius: BorderRadius.circular(6)),
                  child: Text(t, style: GoogleFonts.dmSans(
                    fontSize: 11, color: AppColors.textMuted)))).toList()),
                Text(
                  isActive ? '▶ In Progress'
                    : isCompleted ? '✓ Completed'
                    : isAbandoned ? '↩ Try Again'
                    : isLocked ? '🔒 Locked'
                    : 'View Quest →',
                  style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w500,
                    color: isActive ? AppColors.warning
                      : isCompleted ? AppColors.success
                      : isAbandoned ? AppColors.danger
                      : isLocked ? AppColors.textMuted
                      : AppColors.neon2)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(2)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: AppColors.textMuted),
      const SizedBox(width: 4),
      Text(label, style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textMuted)),
    ]));

  void _showQuestDetail(Quest q) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75, minChildSize: 0.5, maxChildSize: 0.95,
        expand: false,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.border,
                borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Row(children: [
              Text(q.icon, style: const TextStyle(fontSize: 40)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(q.title, style: GoogleFonts.dmSans(
                  fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Row(children: [
                  _badge(q.difficulty, q.diffCol),
                  const SizedBox(width: 8),
                  _badge(q.type == 'gps' ? '📍 GPS verified' : '📍 GPS + self-confirm',
                    AppColors.accent),
                ]),
              ])),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: _detailStat('Verify', q.distanceLabel, AppColors.neon2)),
              const SizedBox(width: 8),
              Expanded(child: _detailStat('XP', '+${q.xp}', AppColors.neon2)),
              const SizedBox(width: 8),
              Expanded(child: _detailStat('Calories', '~${q.kcal}', AppColors.warning)),
              const SizedBox(width: 8),
              Expanded(child: _detailStat('Steps', '~${q.steps}', AppColors.success)),
            ]),
            const SizedBox(height: 20),
            Text('What to do', style: GoogleFonts.dmSans(
              fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card, borderRadius: BorderRadius.circular(2),
                border: Border.all(color: AppColors.border, width: 0.5)),
              child: Text(q.detail, style: GoogleFonts.dmSans(
                fontSize: 14, color: AppColors.textSecondary, height: 1.6))),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.06),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: AppColors.success.withOpacity(0.2))),
              child: Row(children: [
                const Icon(Icons.favorite_rounded, color: AppColors.success, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(q.physicalGain, style: GoogleFonts.dmSans(
                  fontSize: 13, color: AppColors.success, height: 1.4))),
              ])),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity, height: 54,
              child: ElevatedButton(
                onPressed: () { Navigator.pop(context); _acceptQuest(q); },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                  elevation: 0),
                child: Text('ACCEPT QUEST', style: GoogleFonts.pressStart2p(fontSize: 9, color: AppColors.bg)),
              ),
            ),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  void _openActiveQuest(Quest q) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ActiveQuestScreen(
        quest: q,
        onComplete: () async {
          await _completeQuest(q);
          if (mounted) _showCompletionScreen(q);
        },
        onAbandon: () => _abandonQuest(q),
      ),
    ));
  }

  void _showCompletionScreen(Quest q) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => QuestCompleteScreen(quest: q, totalXp: _totalXp)));
  }

  Widget _badge(String label, Color col) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: col.withOpacity(0.1), borderRadius: BorderRadius.circular(2),
      border: Border.all(color: col.withOpacity(0.3))),
    child: Text(label, style: GoogleFonts.dmSans(
      fontSize: 11, color: col, fontWeight: FontWeight.w500)));

  Widget _detailStat(String label, String val, Color col) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.card, borderRadius: BorderRadius.circular(2),
      border: Border.all(color: AppColors.border, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.textMuted)),
      const SizedBox(height: 4),
      Text(val, style: GoogleFonts.dmSans(
        fontSize: 14, fontWeight: FontWeight.w700, color: col)),
    ]));
}

// ─── ACTIVE QUEST SCREEN ────────────────────────────────────────────────────
class ActiveQuestScreen extends StatefulWidget {
  final Quest quest;
  final VoidCallback onComplete;
  final VoidCallback onAbandon;
  const ActiveQuestScreen({super.key, required this.quest,
    required this.onComplete, required this.onAbandon});
  @override
  State<ActiveQuestScreen> createState() => _ActiveQuestScreenState();
}

class _ActiveQuestScreenState extends State<ActiveQuestScreen> {
  bool _checking = false;
  String _statusMsg = '';
  bool _verified = false;
  Position? _startPosition;

  @override
  void initState() {
    super.initState();
    _getStart();
  }

  Future<void> _getStart() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best));
      if (mounted) setState(() => _startPosition = pos);
    } catch (e) { debugPrint('Start pos: $e'); }
  }

  String _readable(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.toStringAsFixed(0)} m';

  Future<void> _check() async {
    setState(() { _checking = true; _statusMsg = 'Getting your location...'; });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        setState(() { _statusMsg = 'Location blocked. Enable it in browser settings.'; _checking = false; });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));

      // Wait for accurate reading — retry if accuracy > 15m
      Position accurate = pos;
      if (pos.accuracy > 15) {
        await Future.delayed(const Duration(seconds: 2));
        try {
          accurate = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.best));
        } catch (_) {}
      }

      double moved = 0;
      if (_startPosition != null) {
        moved = Geolocator.distanceBetween(
          _startPosition!.latitude, _startPosition!.longitude,
          accurate.latitude, accurate.longitude);
        // Sanity check — cap at realistic walking distance
        final elapsed = DateTime.now().difference(DateTime.now()).inSeconds;
        if (moved > 50000) moved = 0; // GPS glitch protection
      }

      final required = widget.quest.radiusMeters;
      if (moved >= required) {
        setState(() {
          _verified = true;
          _statusMsg = 'GPS verified ✅ — You\'ve moved ${_readable(moved)} from your start. Quest complete!';
          _checking = false;
        });
      } else {
        final need = required - moved;
        setState(() {
          _statusMsg = 'You\'ve moved ${_readable(moved)} so far. Walk ${_readable(need)} more to complete this quest.';
          _checking = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMsg = 'Could not get location. Make sure location is allowed in your browser.';
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.quest;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context)),
        title: Text('Active Quest', style: GoogleFonts.dmSans(
          fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        actions: [
          TextButton(
            onPressed: () => showDialog(context: context, builder: (_) => AlertDialog(
              backgroundColor: AppColors.card,
              title: Text('Abandon Quest?', style: GoogleFonts.dmSans(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              content: Text('You\'ll lose progress. The quest will be marked as abandoned.',
                style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.dmSans(color: AppColors.textSecondary))),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                    widget.onAbandon();
                  },
                  child: Text('Abandon', style: GoogleFonts.dmSans(
                    color: AppColors.danger, fontWeight: FontWeight.w600))),
              ],
            )),
            child: Text('Abandon', style: GoogleFonts.dmSans(
              color: AppColors.danger, fontSize: 13)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.card, borderRadius: BorderRadius.circular(2),
                border: Border.all(color: AppColors.warning.withOpacity(0.3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(q.icon, style: const TextStyle(fontSize: 36)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(2)),
                      child: Text('IN PROGRESS', style: GoogleFonts.dmSans(
                        fontSize: 10, color: AppColors.warning,
                        fontWeight: FontWeight.w700, letterSpacing: 1))),
                    const SizedBox(height: 6),
                    Text(q.title, style: GoogleFonts.dmSans(
                      fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ])),
                ]),
                const SizedBox(height: 14),
                Text(q.detail, style: GoogleFonts.dmSans(
                  fontSize: 14, color: AppColors.textSecondary, height: 1.6)),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bg, borderRadius: BorderRadius.circular(2)),
                  child: Row(children: [
                    const Icon(Icons.straighten_rounded, color: AppColors.accent, size: 16),
                    const SizedBox(width: 8),
                    Text('Required distance: ${q.distanceLabel}',
                      style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.neon2,
                        fontWeight: FontWeight.w500)),
                  ])),
              ]),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.accentDim, borderRadius: BorderRadius.circular(2),
                border: Border.all(color: AppColors.accent.withOpacity(0.3))),
              child: Row(children: [
                const Icon(Icons.emoji_events_rounded, color: AppColors.neon2, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('Complete to earn +${q.xp} XP · ~${q.kcal} kcal · ~${q.steps} steps',
                  style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.neon2,
                    fontWeight: FontWeight.w500))),
              ]),
            ),
            const SizedBox(height: 20),

            if (_statusMsg.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _verified
                    ? AppColors.success.withOpacity(0.08) : AppColors.card,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: _verified ? AppColors.success.withOpacity(0.3) : AppColors.border,
                    width: 0.5)),
                child: Row(children: [
                  Icon(_verified ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                    color: _verified ? AppColors.success : AppColors.textSecondary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_statusMsg, style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: _verified ? AppColors.success : AppColors.textSecondary,
                    height: 1.4))),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            if (!_verified) ...[
              SizedBox(width: double.infinity, height: 54,
                child: ElevatedButton(
                  onPressed: _checking ? null : _check,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                    elevation: 0),
                  child: _checking
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        q.type == 'gps' ? '[ CHECK LOCATION ]' : '[ VERIFY GPS ]',
                        style: GoogleFonts.pressStart2p(fontSize: 8, color: AppColors.bg)),
                ),
              ),
              if (_statusMsg.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, height: 48,
                  child: OutlinedButton(
                    onPressed: _checking ? null : _check,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2))),
                    child: Text('Check Again', style: GoogleFonts.dmSans(fontSize: 15)),
                  ),
                ),
              ],
            ] else ...[
              SizedBox(width: double.infinity, height: 54,
                child: ElevatedButton(
                  onPressed: () { Navigator.pop(context); widget.onComplete(); },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                    elevation: 0),
                  child: Text('>> COMPLETE QUEST', style: GoogleFonts.pressStart2p(fontSize: 9, color: AppColors.bg)),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ─── QUEST COMPLETE SCREEN ───────────────────────────────────────────────────
class QuestCompleteScreen extends StatelessWidget {
  final Quest quest;
  final int totalXp;
  const QuestCompleteScreen({super.key, required this.quest, required this.totalXp});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),
            Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1), shape: BoxShape.circle,
                border: Border.all(color: AppColors.success.withOpacity(0.3), width: 2)),
              child: const Center(child: Text('🏆', style: TextStyle(fontSize: 56)))),
            const SizedBox(height: 24),
            Text('QUEST\nCOMPLETE!',
              textAlign: TextAlign.center,
              style: GoogleFonts.pressStart2p(
              fontSize: 20, color: AppColors.accent, height: 1.8,
              shadows: [Shadow(color: AppColors.accent, blurRadius: 16)])),
            const SizedBox(height: 8),
            Text(quest.achievement,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 15, color: AppColors.textSecondary, height: 1.5)),
            const SizedBox(height: 32),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.card, borderRadius: BorderRadius.circular(2),
                border: Border.all(color: AppColors.success.withOpacity(0.3))),
              child: Column(children: [
                Text('What you gained', style: GoogleFonts.dmSans(
                  fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _gain('⚡', '+${quest.xp}', 'XP', AppColors.neon2),
                  _gain('🔥', '~${quest.kcal}', 'kcal', AppColors.warning),
                  _gain('👣', '~${quest.steps}', 'steps', AppColors.success),
                ]),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.bg, borderRadius: BorderRadius.circular(2)),
                  child: Row(children: [
                    const Icon(Icons.favorite_rounded, color: AppColors.success, size: 16),
                    const SizedBox(width: 10),
                    Expanded(child: Text(quest.physicalGain, style: GoogleFonts.dmSans(
                      fontSize: 13, color: AppColors.textSecondary, height: 1.4))),
                  ])),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.accentDim, borderRadius: BorderRadius.circular(2)),
                  child: Text('Total XP: $totalXp pts', style: GoogleFonts.dmSans(
                    fontSize: 14, color: AppColors.neon2, fontWeight: FontWeight.w600))),
              ]),
            ),
            const Spacer(),
            SizedBox(width: double.infinity, height: 54,
              child: ElevatedButton(
                onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                  elevation: 0),
                child: Text('>> BACK TO QUESTS', style: GoogleFonts.pressStart2p(fontSize: 9, color: AppColors.bg)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _gain(String emoji, String val, String label, Color col) => Column(children: [
    Text(emoji, style: const TextStyle(fontSize: 28)),
    const SizedBox(height: 6),
    Text(val, style: GoogleFonts.dmSans(fontSize: 22, fontWeight: FontWeight.w700, color: col)),
    Text(label, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted)),
  ]);
}
