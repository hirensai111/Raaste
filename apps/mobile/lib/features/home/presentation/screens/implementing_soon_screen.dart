import 'package:flutter/material.dart';
import 'package:raaste/shared/widgets/raaste_nav_shell.dart';

class ImplementingSoonScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final RaasteNavTab tab;

  const ImplementingSoonScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.tab,
  });

  @override
  Widget build(BuildContext context) {
    return RaasteNavScaffold(
      currentTab: tab,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 116),
          child: Center(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: RaasteShellColors.surface,
                border: Border.all(color: RaasteShellColors.outline),
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: RaasteShellColors.shadow,
                    blurRadius: 26,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 72,
                    width: 72,
                    decoration: BoxDecoration(
                      color: RaasteShellColors.sage,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(icon, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: RaasteShellColors.ink,
                      fontFamily: 'serif',
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Implementing soon',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: RaasteShellColors.muted,
                      fontSize: 18,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
