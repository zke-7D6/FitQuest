import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'main.dart';
import 'profile_screen.dart';
import 'health_screen.dart';
import 'steps_screen.dart';
import 'quest_screen.dart';
import 'analytics_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  final List<Widget> _screens = const [
    ProfileScreen(),
    StepsScreen(),
    HealthScreen(),
    QuestScreen(),
    AnalyticsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: _buildNav(),
    );
  }

  Widget _buildNav() {
    final items = [
      _NavItem(Icons.home_rounded, Icons.home_outlined, 'Home'),
      _NavItem(Icons.directions_walk_rounded, Icons.directions_walk_outlined, 'Steps'),
      _NavItem(Icons.favorite_rounded, Icons.favorite_border_rounded, 'Health'),
      _NavItem(Icons.explore_rounded, Icons.explore_outlined, 'Quests'),
      _NavItem(Icons.insights_rounded, Icons.insights_outlined, 'Stats'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.98),
        border: Border(top: BorderSide(color: AppColors.border.withOpacity(0.9))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: items.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              final selected = _index == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _index = i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.accent.withOpacity(0.14) : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: selected
                          ? Border.all(color: AppColors.accent.withOpacity(0.24))
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: selected ? 36 : 28,
                          height: selected ? 36 : 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected
                                ? AppColors.accent.withOpacity(0.15)
                                : Colors.transparent,
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: AppColors.accent.withOpacity(0.22),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : [],
                          ),
                          child: Icon(
                            selected ? item.active : item.inactive,
                            size: selected ? 20 : 18,
                            color: selected ? AppColors.accent : AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: GoogleFonts.dmSans(
                            fontSize: 9,
                            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                            color: selected ? AppColors.accent : AppColors.textMuted,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData active;
  final IconData inactive;
  final String label;
  const _NavItem(this.active, this.inactive, this.label);
}
