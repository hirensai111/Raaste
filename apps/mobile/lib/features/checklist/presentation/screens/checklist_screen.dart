import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:raaste/config/routes.dart';
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
  final _repository = TripChecklistRepository();
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 104),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _ChecklistHeader(),
              const SizedBox(height: 18),
              Expanded(
                child:
                    user == null
                        ? const _SignedOutState()
                        : FutureBuilder<List<TripChecklist>>(
                          future: _checklistsFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: RaasteShellColors.clay,
                                ),
                              );
                            }

                            if (snapshot.hasError) {
                              return _StatePanel(
                                icon: Icons.error_outline_rounded,
                                title: 'Checklists could not load',
                                body: snapshot.error.toString().replaceFirst(
                                  'Exception: ',
                                  '',
                                ),
                                actionLabel: 'Try Again',
                                onAction: _refresh,
                              );
                            }

                            final checklists = snapshot.data ?? const [];
                            if (checklists.isEmpty) {
                              return const _EmptyChecklistState();
                            }

                            return RefreshIndicator(
                              color: RaasteShellColors.clay,
                              onRefresh: () async => _refresh(),
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                itemCount: checklists.length,
                                separatorBuilder:
                                    (_, __) => const SizedBox(height: 14),
                                itemBuilder:
                                    (context, index) => _ChecklistCard(
                                      checklist: checklists[index],
                                    ),
                              ),
                            );
                          },
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChecklistHeader extends StatelessWidget {
  const _ChecklistHeader();

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
                  fontSize: 36,
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

class _ChecklistCard extends StatelessWidget {
  final TripChecklist checklist;

  const _ChecklistCard({required this.checklist});

  @override
  Widget build(BuildContext context) {
    final sections = _sectionsFromContent(checklist.content);

    return Material(
      color: const Color(0xFFFFFCF7),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _openDetail(context),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: RaasteShellColors.outline),
            borderRadius: BorderRadius.circular(22),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 52,
                    width: 52,
                    decoration: BoxDecoration(
                      color: _colorFor(checklist.checklistType),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      _iconFor(checklist.checklistType),
                      color: Colors.white,
                      size: 27,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          checklist.typeLabel,
                          style: const TextStyle(
                            color: RaasteShellColors.clay,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          checklist.destinationName.isEmpty
                              ? 'Trip checklist'
                              : '${checklist.destinationName} Checklist',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: RaasteShellColors.ink,
                            fontFamily: 'serif',
                            fontSize: 25,
                            fontWeight: FontWeight.w700,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          checklist.typeSubtitle,
                          style: const TextStyle(
                            color: RaasteShellColors.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: RaasteShellColors.clay,
                    size: 26,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniChip(
                    icon: Icons.calendar_month_outlined,
                    label: _formatDate(checklist.checklistDate),
                  ),
                  if (checklist.tripDates.trim().isNotEmpty)
                    _MiniChip(
                      icon: Icons.route_outlined,
                      label: checklist.tripDates,
                    ),
                  _MiniChip(
                    icon: Icons.checklist_rounded,
                    label:
                        '${sections.length} section${sections.length == 1 ? '' : 's'}',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: RaasteShellColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _ChecklistDetailSheet(checklist: checklist),
    );
  }
}

class _ChecklistDetailSheet extends StatelessWidget {
  final TripChecklist checklist;

  const _ChecklistDetailSheet({required this.checklist});

  @override
  Widget build(BuildContext context) {
    final sections = _sectionsFromContent(checklist.content);
    final intro = _introText(checklist.content);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder:
          (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 48,
                  decoration: BoxDecoration(
                    color: RaasteShellColors.outline,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                checklist.typeLabel,
                style: const TextStyle(
                  color: RaasteShellColors.clay,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                checklist.destinationName.isEmpty
                    ? 'Trip checklist'
                    : checklist.destinationName,
                style: const TextStyle(
                  color: RaasteShellColors.ink,
                  fontFamily: 'serif',
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                ),
              ),
              if (intro.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  intro,
                  style: const TextStyle(
                    color: RaasteShellColors.muted,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              ...sections.map(
                (section) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _ChecklistSection(section: section),
                ),
              ),
            ],
          ),
    );
  }
}

class _ChecklistSection extends StatelessWidget {
  final _DisplaySection section;

  const _ChecklistSection({required this.section});

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
          ...section.items.map((item) => _ChecklistItem(item: item)),
        ],
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  final _DisplayItem item;

  const _ChecklistItem({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: RaasteShellColors.sage,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.text,
                  style: const TextStyle(
                    color: RaasteShellColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                if (item.detail.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.detail,
                    style: const TextStyle(
                      color: RaasteShellColors.muted,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E8D8),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: RaasteShellColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: RaasteShellColors.ink),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: RaasteShellColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
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
    return _StatePanel(
      icon: Icons.lock_outline_rounded,
      title: 'Sign in for checklists',
      body: 'Your trip prep and daily guides will appear here after sign in.',
      actionLabel: 'Sign In',
      onAction: () => context.go(AppRoutes.signIn),
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
                fontSize: 28,
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

class _DisplaySection {
  final String name;
  final String emoji;
  final String context;
  final List<_DisplayItem> items;

  const _DisplaySection({
    required this.name,
    required this.emoji,
    required this.context,
    required this.items,
  });
}

class _DisplayItem {
  final String text;
  final String detail;

  const _DisplayItem({required this.text, required this.detail});
}

List<_DisplaySection> _sectionsFromContent(Map<String, dynamic> content) {
  final rawSections =
      (content['categories'] as List<dynamic>?) ??
      (content['sections'] as List<dynamic>?) ??
      const [];
  return rawSections.whereType<Map>().map((raw) {
    final items =
        (raw['items'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map(_itemFromRaw)
            .where((item) => item.text.trim().isNotEmpty)
            .toList();
    return _DisplaySection(
      name: raw['name'] as String? ?? 'Checklist',
      emoji: raw['emoji'] as String? ?? '-',
      context: raw['time_context'] as String? ?? '',
      items: items,
    );
  }).toList();
}

_DisplayItem _itemFromRaw(Map raw) {
  final text = raw['text'] as String? ?? '';
  final details =
      <String>[
        if ((raw['time'] as String?)?.trim().isNotEmpty == true) raw['time'],
        if ((raw['priority'] as String?)?.trim().isNotEmpty == true)
          '${raw['priority']} priority',
        if ((raw['tip'] as String?)?.trim().isNotEmpty == true) raw['tip'],
      ].whereType<String>().toList();

  return _DisplayItem(text: text, detail: details.join(' | '));
}

String _introText(Map<String, dynamic> content) {
  for (final key in [
    'morning_greeting',
    'weather_heads_up',
    'season_note',
    'wrap_up_message',
    'end_of_day_note',
  ]) {
    final value = content[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

IconData _iconFor(String type) {
  switch (type) {
    case 'pre_trip':
      return Icons.luggage_rounded;
    case 'in_trip_daily':
      return Icons.today_rounded;
    case 'post_trip':
      return Icons.rate_review_outlined;
    default:
      return Icons.checklist_rounded;
  }
}

Color _colorFor(String type) {
  switch (type) {
    case 'pre_trip':
      return RaasteShellColors.sage;
    case 'in_trip_daily':
      return RaasteShellColors.clay;
    case 'post_trip':
      return const Color(0xFF6C668E);
    default:
      return RaasteShellColors.ink;
  }
}

String _formatDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}
