import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'main.dart';

// ─── CHALLENGE MODEL ────────────────────────────────────────────────────────
class Challenge {
  final String id;
  final String title;
  final String description;
  final String type; // 'steps', 'streak', 'quest', 'distance'
  final String icon;
  final int target;
  final String targetUnit;
  final int durationDays;
  final int rewardXp;
  final String difficulty;
  final Color diffCol;

  const Challenge({
    required this.id, required this.title, required this.description,
    required this.type, required this.icon, required this.target,
    required this.targetUnit, required this.durationDays,
    required this.rewardXp, required this.difficulty, required this.diffCol,
  });
}

// Pre-seeded challenges that rotate weekly
final List<Challenge> _allChallenges = [
  const Challenge(
    id: 'step_50k', title: '50K Step Week',
    description: 'Walk 50,000 steps total this week. That\'s about 7,000 a day — very doable!',
    type: 'steps', icon: '👟', target: 50000, targetUnit: 'steps',
    durationDays: 7, rewardXp: 300, difficulty: 'Medium', diffCol: AppColors.warning),
  const Challenge(
    id: 'step_100k', title: 'The Century',
    description: 'Hit 100,000 steps in a week. Elite territory — about 14K daily.',
    type: 'steps', icon: '🏃', target: 100000, targetUnit: 'steps',
    durationDays: 7, rewardXp: 600, difficulty: 'Hard', diffCol: AppColors.danger),
  const Challenge(
    id: 'streak_7', title: '7-Day Warrior',
    description: 'Check in every single day for 7 days straight. No breaks.',
    type: 'streak', icon: '🔥', target: 7, targetUnit: 'days',
    durationDays: 7, rewardXp: 250, difficulty: 'Medium', diffCol: AppColors.warning),
  const Challenge(
    id: 'streak_14', title: 'Fortnight Fighter',
    description: 'Maintain a 14-day check-in streak. True consistency.',
    type: 'streak', icon: '⚡', target: 14, targetUnit: 'days',
    durationDays: 14, rewardXp: 500, difficulty: 'Hard', diffCol: AppColors.danger),
  const Challenge(
    id: 'quest_3', title: 'Quest Hunter',
    description: 'Complete 3 different quests this week. Explore your city!',
    type: 'quest', icon: '🗺️', target: 3, targetUnit: 'quests',
    durationDays: 7, rewardXp: 350, difficulty: 'Medium', diffCol: AppColors.warning),
  const Challenge(
    id: 'quest_5', title: 'Quest Master',
    description: 'Finish 5 quests in a single week. Only the dedicated survive.',
    type: 'quest', icon: '🏆', target: 5, targetUnit: 'quests',
    durationDays: 7, rewardXp: 700, difficulty: 'Hard', diffCol: AppColors.danger),
  const Challenge(
    id: 'dist_10k', title: '10K Walker',
    description: 'Walk a total of 10 km this week. About 1.5 km per day.',
    type: 'distance', icon: '🚶', target: 10, targetUnit: 'km',
    durationDays: 7, rewardXp: 200, difficulty: 'Easy', diffCol: AppColors.success),
  const Challenge(
    id: 'dist_30k', title: 'Marathon Chaser',
    description: 'Cover 30 km total in a week. That\'s almost a marathon distance!',
    type: 'distance', icon: '🥇', target: 30, targetUnit: 'km',
    durationDays: 7, rewardXp: 450, difficulty: 'Hard', diffCol: AppColors.danger),
  const Challenge(
    id: 'step_15k_day', title: 'Daily Beast',
    description: 'Hit 15,000 steps in a single day. One big push!',
    type: 'steps', icon: '💪', target: 15000, targetUnit: 'steps',
    durationDays: 1, rewardXp: 200, difficulty: 'Medium', diffCol: AppColors.warning),
  const Challenge(
    id: 'diet_5', title: 'Clean Eater',
    description: 'Follow your diet plan for 5 out of 7 days this week.',
    type: 'streak', icon: '🥗', target: 5, targetUnit: 'days',
    durationDays: 7, rewardXp: 300, difficulty: 'Medium', diffCol: AppColors.warning),
  const Challenge(
    id: 'step_25k', title: 'Starter Sprint',
    description: 'Walk 25,000 steps this week. Perfect for beginners!',
    type: 'steps', icon: '🌱', target: 25000, targetUnit: 'steps',
    durationDays: 7, rewardXp: 150, difficulty: 'Easy', diffCol: AppColors.success),
  const Challenge(
    id: 'dist_5k', title: 'Neighbourhood Explorer',
    description: 'Walk 5 km total this week. Know your neighbourhood better.',
    type: 'distance', icon: '🏘️', target: 5, targetUnit: 'km',
    durationDays: 7, rewardXp: 120, difficulty: 'Easy', diffCol: AppColors.success),
];

List<Challenge> _getWeeklyChallenges() {
  final now = DateTime.now();
  final weekSeed = now.year * 100 + (now.difference(DateTime(now.year)).inDays ~/ 7);
  final rng = Random(weekSeed);
  final shuffled = List<Challenge>.from(_allChallenges)..shuffle(rng);
  return shuffled.take(6).toList();
}

// ─── SOCIAL SCREEN ──────────────────────────────────────────────────────────
class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});
  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  bool _loading = true;
  int _tab = 0; // 0=challenges, 1=achievements
  List<Challenge> _weeklyChallenges = [];
  Map<String, Map<String, dynamic>> _myProgress = {};
  Set<String> _completedChallengeIds = {};
  int _totalChallengeXp = 0;

  // Leaderboard data
  Map<String, List<Map<String, dynamic>>> _leaderboards = {};

  @override
  void initState() {
    super.initState();
    _weeklyChallenges = _getWeeklyChallenges();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { if (mounted) setState(() => _loading = false); return; }
    try {
      final fs = FirebaseFirestore.instance;
      final historySnap = await fs.collection('users').doc(uid)
          .collection('challengeHistory').get();

      for (final doc in historySnap.docs) {
        final data = doc.data();
        if (data['completed'] == true) _completedChallengeIds.add(doc.id);
        _myProgress[doc.id] = data;
      }

      // Load progress for weekly challenges
      for (final c in _weeklyChallenges) {
        if (!_myProgress.containsKey(c.id)) continue;
        // Load leaderboard
        try {
          final partSnap = await fs.collection('challenges').doc(c.id)
              .collection('participants')
              .orderBy('progress', descending: true).limit(10).get();
          _leaderboards[c.id] = partSnap.docs.map((d) => d.data()).toList();
        } catch (_) {}
      }

      // Total challenge XP
      for (final entry in _myProgress.values) {
        if (entry['completed'] == true) {
          _totalChallengeXp += (entry['rewardXp'] as num?)?.toInt() ?? 0;
        }
      }
    } catch (e) { debugPrint('Social load: $e'); }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _joinChallenge(Challenge c) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final fs = FirebaseFirestore.instance;
    final displayName = FirebaseAuth.instance.currentUser?.displayName ?? 'Athlete';

    final data = {
      'challengeId': c.id,
      'joinedAt': FieldValue.serverTimestamp(),
      'progress': 0,
      'target': c.target,
      'completed': false,
      'rewardXp': c.rewardXp,
    };

    await Future.wait([
      fs.collection('users').doc(uid).collection('challengeHistory').doc(c.id).set(data),
      fs.collection('challenges').doc(c.id).collection('participants').doc(uid).set({
        'displayName': displayName.split(' ').first,
        'progress': 0,
        'joinedAt': FieldValue.serverTimestamp(),
      }),
      fs.collection('challenges').doc(c.id).set({
        'title': c.title,
        'participantCount': FieldValue.increment(1),
      }, SetOptions(merge: true)),
    ]);

    if (mounted) setState(() => _myProgress[c.id] = data);
  }

  Future<void> _updateProgress(Challenge c, int newProgress) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final fs = FirebaseFirestore.instance;
    final completed = newProgress >= c.target;

    await Future.wait([
      fs.collection('users').doc(uid).collection('challengeHistory').doc(c.id).update({
        'progress': newProgress,
        'completed': completed,
        if (completed) 'completedAt': FieldValue.serverTimestamp(),
      }),
      fs.collection('challenges').doc(c.id).collection('participants').doc(uid).update({
        'progress': newProgress,
      }),
    ]);

    if (mounted) setState(() {
      _myProgress[c.id]?['progress'] = newProgress;
      _myProgress[c.id]?['completed'] = completed;
      if (completed) _completedChallengeIds.add(c.id);
    });
  }

  bool _isJoined(String id) => _myProgress.containsKey(id);
  bool _isCompleted(String id) => _completedChallengeIds.contains(id);
  int _getProgress(String id) => (_myProgress[id]?['progress'] as num?)?.toInt() ?? 0;

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
                  Text('COMMUNITY', style: GoogleFonts.pressStart2p(
                    fontSize: 13, color: AppColors.accent,
                    shadows: [Shadow(color: AppColors.accent, blurRadius: 8)])),
                  const SizedBox(height: 4),
                  Text('CHALLENGE YOURSELF. COMPETE WITH OTHERS.',
                    style: GoogleFonts.pressStart2p(fontSize: 6, color: AppColors.textSecondary)),
                  const SizedBox(height: 16),

                  // XP from challenges
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        AppColors.neon3.withOpacity(0.08), AppColors.accent.withOpacity(0.06)]),
                      border: Border.all(color: AppColors.neon3.withOpacity(0.3))),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.neon3.withOpacity(0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.groups_rounded, color: AppColors.neon3, size: 24)),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('CHALLENGE XP', style: GoogleFonts.pressStart2p(
                          fontSize: 7, color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text('$_totalChallengeXp PTS', style: GoogleFonts.pressStart2p(
                          fontSize: 16, color: AppColors.neon3,
                          shadows: [Shadow(color: AppColors.neon3, blurRadius: 10)])),
                        Text('${_completedChallengeIds.length} challenges completed',
                          style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textMuted)),
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Tab switcher
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.card, border: Border.all(color: AppColors.border)),
                    child: Row(children: ['Challenges', 'Achievements'].asMap().entries.map((e) {
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
                  const SizedBox(height: 16),
                ]),
              )),

              if (_tab == 0)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                  sliver: SliverList(delegate: SliverChildBuilderDelegate(
                    (_, i) => _challengeCard(_weeklyChallenges[i]),
                    childCount: _weeklyChallenges.length,
                  )),
                )
              else
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                  child: _achievementsSection(),
                )),
            ])),
    );
  }

  Widget _challengeCard(Challenge c) {
    final joined = _isJoined(c.id);
    final completed = _isCompleted(c.id);
    final progress = _getProgress(c.id);
    final progressPct = c.target > 0 ? (progress / c.target).clamp(0.0, 1.0) : 0.0;

    Color borderCol = AppColors.border;
    Color bgCol = AppColors.card;
    if (joined && !completed) {
      borderCol = AppColors.warning.withOpacity(0.4);
      bgCol = AppColors.warning.withOpacity(0.03);
    }
    if (completed) {
      borderCol = AppColors.success.withOpacity(0.4);
      bgCol = AppColors.success.withOpacity(0.03);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: bgCol, border: Border.all(color: borderCol)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: AppColors.bg, borderRadius: BorderRadius.circular(2)),
              child: Center(child: Text(c.icon, style: const TextStyle(fontSize: 24)))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text(c.title.toUpperCase(), style: GoogleFonts.pressStart2p(
                  fontSize: 8, color: AppColors.textPrimary))),
                if (completed)
                  const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20)
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.diffCol.withOpacity(0.1),
                      border: Border.all(color: c.diffCol.withOpacity(0.3))),
                    child: Text(c.difficulty, style: GoogleFonts.dmSans(
                      fontSize: 11, color: c.diffCol, fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 5),
              Text(c.description, style: GoogleFonts.dmSans(
                fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _infoPill(Icons.star_outline_rounded, '+${c.rewardXp} XP'),
                _infoPill(Icons.flag_outlined, '${c.target} ${c.targetUnit}'),
                _infoPill(Icons.timer_outlined, '${c.durationDays} day${c.durationDays == 1 ? '' : 's'}'),
              ]),
            ])),
          ]),
        ),

        // Progress bar if joined
        if (joined) ...[
          Container(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('$progress / ${c.target} ${c.targetUnit}',
                  style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary)),
                Text('${(progressPct * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.pressStart2p(fontSize: 7,
                    color: completed ? AppColors.success : AppColors.accent)),
              ]),
              const SizedBox(height: 6),
              Container(
                height: 8,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border, width: 0.5)),
                child: Row(children: [
                  Expanded(
                    flex: (progressPct * 100).round().clamp(0, 100),
                    child: Container(color: completed ? AppColors.success : AppColors.accent)),
                  Expanded(
                    flex: (100 - (progressPct * 100).round()).clamp(0, 100),
                    child: Container(color: AppColors.bg)),
                ])),
            ])),
        ],

        // Action button
        Container(height: 1, color: AppColors.border),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              const Icon(Icons.group_outlined, color: AppColors.textMuted, size: 14),
              const SizedBox(width: 4),
              Text('Community Challenge', style: GoogleFonts.dmSans(
                fontSize: 11, color: AppColors.textMuted)),
            ]),
            GestureDetector(
              onTap: () {
                if (completed) return;
                if (!joined) {
                  _joinChallenge(c);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Joined ${c.title}! 🎉', style: GoogleFonts.dmSans()),
                    backgroundColor: AppColors.success.withOpacity(0.9)));
                } else {
                  _showChallengeDetail(c);
                }
              },
              child: Text(
                completed ? '✓ Completed'
                  : joined ? 'View Progress →'
                  : 'Join Challenge →',
                style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600,
                  color: completed ? AppColors.success
                    : joined ? AppColors.warning
                    : AppColors.accent)),
            ),
          ]),
        ),
      ]),
    );
  }

  void _showChallengeDetail(Challenge c) {
    final leaderboard = _leaderboards[c.id] ?? [];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(2))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, minChildSize: 0.4, maxChildSize: 0.85,
        expand: false,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4, color: AppColors.border)),
            const SizedBox(height: 20),
            Row(children: [
              Text(c.icon, style: const TextStyle(fontSize: 36)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.title, style: GoogleFonts.dmSans(
                  fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text('${c.target} ${c.targetUnit} · ${c.durationDays} days · +${c.rewardXp} XP',
                  style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted)),
              ])),
            ]),
            const SizedBox(height: 20),
            Text('LEADERBOARD', style: GoogleFonts.pressStart2p(
              fontSize: 8, color: AppColors.accent)),
            const SizedBox(height: 10),
            if (leaderboard.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                color: AppColors.card,
                child: Center(child: Text('No participants yet. Be the first!',
                  style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted))))
            else
              ...leaderboard.asMap().entries.map((e) {
                final rank = e.key + 1;
                final p = e.value;
                final name = p['displayName'] ?? 'Athlete';
                final prog = (p['progress'] as num?)?.toInt() ?? 0;
                final medal = rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : '#$rank';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: rank <= 3 ? AppColors.accentDim : AppColors.card,
                    border: Border(bottom: BorderSide(color: AppColors.border))),
                  child: Row(children: [
                    SizedBox(width: 30, child: Text(medal,
                      style: rank <= 3
                        ? const TextStyle(fontSize: 18)
                        : GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(name, style: GoogleFonts.dmSans(
                      fontSize: 14, color: AppColors.textPrimary,
                      fontWeight: rank <= 3 ? FontWeight.w700 : FontWeight.normal))),
                    Text('$prog ${c.targetUnit}', style: GoogleFonts.pressStart2p(
                      fontSize: 8, color: rank <= 3 ? AppColors.accent : AppColors.textSecondary)),
                  ]));
              }),
          ]),
        ),
      ),
    );
  }

  Widget _achievementsSection() {
    final completed = _allChallenges.where((c) => _completedChallengeIds.contains(c.id)).toList();
    if (completed.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: AppColors.card, border: Border.all(color: AppColors.border)),
        child: Center(child: Column(children: [
          const Text('🏅', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 14),
          Text('NO ACHIEVEMENTS YET', style: GoogleFonts.pressStart2p(
            fontSize: 9, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Text('Join and complete challenges to earn badges!',
            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
        ])));
    }

    return Column(children: completed.map((c) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.04),
        border: Border.all(color: AppColors.success.withOpacity(0.3))),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.1), shape: BoxShape.circle,
            border: Border.all(color: AppColors.success, width: 2)),
          child: Center(child: Text(c.icon, style: const TextStyle(fontSize: 22)))),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.title, style: GoogleFonts.dmSans(
            fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          Text('+${c.rewardXp} XP earned', style: GoogleFonts.dmSans(
            fontSize: 12, color: AppColors.success)),
        ])),
        const Icon(Icons.verified_rounded, color: AppColors.success, size: 24),
      ]))).toList());
  }

  Widget _infoPill(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(2)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: AppColors.textMuted),
      const SizedBox(width: 4),
      Text(label, style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textMuted)),
    ]));
}
