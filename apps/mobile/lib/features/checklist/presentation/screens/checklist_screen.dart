import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:raaste/config/routes.dart';
import 'package:raaste/core/di/injection.dart';
import 'package:raaste/features/checklist/application/trip_checklist_repository.dart';
import 'package:raaste/features/checklist/domain/models/trip_checklist.dart';
import 'package:raaste/shared/widgets/raaste_nav_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  final _repository = getIt<TripChecklistRepository>();
  late Future<List<TripChecklist>> _checklistsFuture;

  @override
  void initState() {
    super.initState();
    _checklistsFuture = _repository.listChecklists();
  }

  void _refresh() {
    setState(() => _checklistsFuture = _repository.listChecklists());
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return RaasteNavScaffold(
      currentTab: RaasteNavTab.saved,
      body: SafeArea(
        bottom: false,
        child:
            user == null
                ? const Padding(
                  padding: EdgeInsets.fromLTRB(20, 18, 20, 104),
                  child: _SignedOutState(),
                )
                : FutureBuilder<List<TripChecklist>>(
                  future: _checklistsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const _LoadingState();
                    }

                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 104),
                        child: _StatePanel(
                          icon: Icons.error_outline_rounded,
                          title: 'Checklists could not load',
                          body: snapshot.error.toString().replaceFirst(
                            'Exception: ',
                            '',
                          ),
                          actionLabel: 'Try Again',
                          onAction: _refresh,
                        ),
                      );
                    }

                    final checklists = snapshot.data ?? const [];
                    final active = _pickActiveChecklist(checklists);

                    if (active == null) {
                      return const Padding(
                        padding: EdgeInsets.fromLTRB(20, 18, 20, 104),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ScreenHeader(),
                            SizedBox(height: 18),
                            Expanded(child: _EmptyChecklistState()),
                          ],
                        ),
                      );
                    }

                    return _ActiveChecklistView(
                      checklist: active,
                      repository: _repository,
                      onRefresh: _refresh,
                    );
                  },
                ),
      ),
    );
  }

  /// With only one trip active at a time, pick the most relevant checklist:
  /// today's in-trip list first, then pre-trip, then post-trip. The list is
  /// already ordered by checklist_date desc, so the first match wins.
  TripChecklist? _pickActiveChecklist(List<TripChecklist> all) {
    if (all.isEmpty) return null;
    for (final type in ['in_trip_daily', 'pre_trip', 'post_trip']) {
      for (final checklist in all) {
        if (checklist.checklistType == type) return checklist;
      }
    }
    return all.first;
  }
}

/// The full inline, checkable checklist for the active trip phase.
class _ActiveChecklistView extends StatefulWidget {
  final TripChecklist checklist;
  final TripChecklistRepository repository;
  final VoidCallback onRefresh;

  const _ActiveChecklistView({
    required this.checklist,
    required this.repository,
    required this.onRefresh,
  });

  @override
  State<_ActiveChecklistView> createState() => _ActiveChecklistViewState();
}

class _ActiveChecklistViewState extends State<_ActiveChecklistView> {
  late TripChecklist _checklist = widget.checklist;

  // Tracks items currently being saved so we can disable double-taps.
  final _savingKeys = <String>{};

  @override
  void didUpdateWidget(covariant _ActiveChecklistView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checklist.id != widget.checklist.id) {
      _checklist = widget.checklist;
    }
  }

  Future<void> _toggle(ChecklistItem item) async {
    final key = '${item.sectionIndex}:${item.itemIndex}';
    if (_savingKeys.contains(key)) return;

    final newValue = !item.done;
    setState(() => _savingKeys.add(key));

    try {
      final updatedContent = await widget.repository.setItemDone(
        checklistId: _checklist.id,
        content: _checklist.content,
        sectionIndex: item.sectionIndex,
        itemIndex: item.itemIndex,
        done: newValue,
      );
      if (!mounted) return;
      setState(() {
        _checklist = TripChecklist(
          id: _checklist.id,
          tripId: _checklist.tripId,
          checklistType: _checklist.checklistType,
          checklistDate: _checklist.checklistDate,
          dayNumber: _checklist.dayNumber,
          destinationName: _checklist.destinationName,
          tripDates: _checklist.tripDates,
          content: updatedContent,
          generatedAt: _checklist.generatedAt,
        );
        _savingKeys.remove(key);
      });
    } on TripChecklistException catch (e) {
      if (!mounted) return;
      setState(() => _savingKeys.remove(key));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final checklist = _checklist;
    final sections = checklist.sections;
    final total = checklist.totalItems;
    final completed = checklist.completedItems;

    return RefreshIndicator(
      color: RaasteShellColors.clay,
      onRefresh: () async => widget.onRefresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
        children: [
          const _ScreenHeader(),
          const SizedBox(height: 18),
          _ProgressCard(
            checklist: checklist,
            completed: completed,
            total: total,
          ),
          const SizedBox(height: 18),
          for (final section in sections) ...[
            _SectionBlock(
              section: section,
              savingKeys: _savingKeys,
              onToggle: _toggle,
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _ScreenHeader extends StatelessWidget {
  const _ScreenHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Checklist',
                style: TextStyle(
                  color: RaasteShellColors.ink,
                  fontFamily: 'serif',
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Prep, daily plans, and post-trip wrap-ups',
                style: TextStyle(
                  color: RaasteShellColors.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: RaasteShellColors.ink,
            foregroundColor: Colors.white,
          ),
          onPressed: () => context.go(AppRoutes.trips),
          icon: const Icon(Icons.work_outline_rounded),
        ),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final TripChecklist checklist;
  final int completed;
  final int total;

  const _ProgressCard({
    required this.checklist,
    required this.completed,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;
    final intro = checklist.intro;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: RaasteShellColors.outline),
        boxShadow: const [
          BoxShadow(
            color: RaasteShellColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            checklist.typeLabel,
            style: const TextStyle(
              color: RaasteShellColors.clay,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            checklist.title,
            style: const TextStyle(
              color: RaasteShellColors.ink,
              fontFamily: 'serif',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.05,
            ),
          ),
          if (intro.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              intro,
              style: const TextStyle(
                color: RaasteShellColors.muted,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '$completed of $total done',
                style: const TextStyle(
                  color: RaasteShellColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                  color: RaasteShellColors.sage,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress,
              backgroundColor: const Color(0x14000000),
              color: RaasteShellColors.sage,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  final ChecklistSection section;
  final Set<String> savingKeys;
  final ValueChanged<ChecklistItem> onToggle;

  const _SectionBlock({
    required this.section,
    required this.savingKeys,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RaasteShellColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(section.emoji, style: const TextStyle(fontSize: 21)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  section.name,
                  style: const TextStyle(
                    color: RaasteShellColors.ink,
                    fontFamily: 'serif',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (section.context.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              section.context,
              style: const TextStyle(
                color: RaasteShellColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          for (final item in section.items)
            _ChecklistItemTile(
              item: item,
              saving: savingKeys.contains(
                '${item.sectionIndex}:${item.itemIndex}',
              ),
              onToggle: () => onToggle(item),
            ),
        ],
      ),
    );
  }
}

class _ChecklistItemTile extends StatelessWidget {
  final ChecklistItem item;
  final bool saving;
  final VoidCallback onToggle;

  const _ChecklistItemTile({
    required this.item,
    required this.saving,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: saving ? null : onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Checkbox(done: item.done, saving: saving),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(
                          item.text,
                          style: TextStyle(
                            color:
                                item.done
                                    ? RaasteShellColors.muted
                                    : RaasteShellColors.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                            decoration:
                                item.done
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                          ),
                        ),
                      ),
                      if (item.priority.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _PriorityBadge(priority: item.priority),
                      ],
                    ],
                  ),
                  if (item.detail.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.detail,
                      style: const TextStyle(
                        color: RaasteShellColors.muted,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (item.actionLabel.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      item.actionLabel,
                      style: const TextStyle(
                        color: RaasteShellColors.clay,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  final bool done;
  final bool saving;

  const _Checkbox({required this.done, required this.saving});

  @override
  Widget build(BuildContext context) {
    if (saving) {
      return const SizedBox(
        height: 22,
        width: 22,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: RaasteShellColors.sage,
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 22,
      width: 22,
      decoration: BoxDecoration(
        color: done ? RaasteShellColors.sage : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: done ? RaasteShellColors.sage : RaasteShellColors.outline,
          width: 2,
        ),
      ),
      child:
          done
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
              : null,
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final String priority;

  const _PriorityBadge({required this.priority});

  @override
  Widget build(BuildContext context) {
    final (color, bg) = switch (priority) {
      'critical' => (const Color(0xFFC0392B), const Color(0xFFFBE3E0)),
      'high' => (const Color(0xFFB9770E), const Color(0xFFFAEACF)),
      'medium' => (const Color(0xFF5A53A8), const Color(0xFFE6E4F6)),
      _ => (RaasteShellColors.muted, const Color(0xFFEDE7DD)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 104),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ScreenHeader(),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: RaasteShellColors.clay),
                  SizedBox(height: 16),
                  Text(
                    'Building your checklist…',
                    style: TextStyle(
                      color: RaasteShellColors.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignedOutState extends StatelessWidget {
  const _SignedOutState();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ScreenHeader(),
        const SizedBox(height: 18),
        Expanded(
          child: _StatePanel(
            icon: Icons.lock_outline_rounded,
            title: 'Sign in for checklists',
            body:
                'Your trip prep and daily guides will appear here after sign in.',
            actionLabel: 'Sign In',
            onAction: () => context.go(AppRoutes.signIn),
          ),
        ),
      ],
    );
  }
}

class _EmptyChecklistState extends StatelessWidget {
  const _EmptyChecklistState();

  @override
  Widget build(BuildContext context) {
    return _StatePanel(
      icon: Icons.checklist_rounded,
      title: 'No checklists yet',
      body:
          'Saved trips get checklists automatically: 14 days before, each travel morning, and after the trip.',
      actionLabel: 'View Trips',
      onAction: () => context.go(AppRoutes.trips),
    );
  }
}

class _StatePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _StatePanel({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF7),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: RaasteShellColors.outline),
          boxShadow: const [
            BoxShadow(
              color: RaasteShellColors.shadow,
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: RaasteShellColors.sage, size: 48),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: RaasteShellColors.ink,
                fontFamily: 'serif',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: RaasteShellColors.muted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: RaasteShellColors.ink,
                foregroundColor: Colors.white,
              ),
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
