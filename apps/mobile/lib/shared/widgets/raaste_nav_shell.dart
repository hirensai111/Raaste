import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:raaste/config/routes.dart';

class RaasteShellColors {
  const RaasteShellColors._();

  static const background = Color(0xFFFBF4E9);
  static const surface = Color(0xFFFAF4EA);
  static const surfaceAlt = Color(0xFFF3EDE2);
  static const ink = Color(0xFF254632);
  static const muted = Color(0xFF72685E);
  static const sage = Color(0xFF647A55);
  static const clay = Color(0xFFC96F3D);
  static const outline = Color(0xFFE3D9CB);
  static const shadow = Color(0x1F4B3A28);
}

enum RaasteNavTab { home, trips, explore, saved, profile }

class RaasteNavScaffold extends StatelessWidget {
  final Widget body;
  final RaasteNavTab currentTab;

  const RaasteNavScaffold({
    super.key,
    required this.body,
    required this.currentTab,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RaasteShellColors.background,
      extendBody: true,
      body: body,
      bottomNavigationBar: RaasteBottomNav(currentTab: currentTab),
    );
  }
}

class RaasteBottomNav extends StatelessWidget {
  final RaasteNavTab currentTab;

  const RaasteBottomNav({super.key, required this.currentTab});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            color: const Color(0xF7FFFBF4),
            border: Border.all(color: RaasteShellColors.outline),
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                color: RaasteShellColors.shadow,
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                tab: RaasteNavTab.home,
                currentTab: currentTab,
              ),
              _NavItem(
                icon: Icons.explore_outlined,
                label: 'Explore',
                tab: RaasteNavTab.explore,
                currentTab: currentTab,
              ),
              _NavItem(
                icon: Icons.work_outline_rounded,
                label: 'My Trips',
                tab: RaasteNavTab.trips,
                currentTab: currentTab,
              ),
              _NavItem(
                icon: Icons.checklist_rounded,
                label: 'Checklist',
                tab: RaasteNavTab.saved,
                currentTab: currentTab,
              ),
              _NavItem(
                icon: Icons.person_outline_rounded,
                label: 'Profile',
                tab: RaasteNavTab.profile,
                currentTab: currentTab,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final RaasteNavTab tab;
  final RaasteNavTab currentTab;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.tab,
    required this.currentTab,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = tab == currentTab;
    final color = isActive ? RaasteShellColors.ink : Colors.grey.shade600;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _goToTab(context, tab),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    height: 1,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(top: 7),
                height: 3,
                width: isActive ? 34 : 0,
                decoration: BoxDecoration(
                  color: RaasteShellColors.ink,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _goToTab(BuildContext context, RaasteNavTab tab) {
    switch (tab) {
      case RaasteNavTab.home:
        context.go(AppRoutes.home);
        return;
      case RaasteNavTab.trips:
        context.go(AppRoutes.trips);
        return;
      case RaasteNavTab.explore:
        context.go(AppRoutes.explore);
        return;
      case RaasteNavTab.saved:
        context.go(AppRoutes.saved);
        return;
      case RaasteNavTab.profile:
        context.go(AppRoutes.profile);
        return;
    }
  }
}

void showImplementingSoon(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Implementing soon')));
}
