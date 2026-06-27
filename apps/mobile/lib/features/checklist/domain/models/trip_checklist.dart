class TripChecklist {
  final String id;
  final String tripId;
  final String checklistType;
  final DateTime checklistDate;
  final int? dayNumber;
  final String destinationName;
  final String tripDates;
  final Map<String, dynamic> content;
  final DateTime generatedAt;

  const TripChecklist({
    required this.id,
    required this.tripId,
    required this.checklistType,
    required this.checklistDate,
    required this.dayNumber,
    required this.destinationName,
    required this.tripDates,
    required this.content,
    required this.generatedAt,
  });

  String get typeLabel {
    switch (checklistType) {
      case 'pre_trip':
        return 'Before Trip';
      case 'in_trip_daily':
        return dayNumber == null ? 'Today' : 'Day $dayNumber';
      case 'post_trip':
        return 'After Trip';
      default:
        return 'Checklist';
    }
  }

  String get typeSubtitle {
    switch (checklistType) {
      case 'pre_trip':
        return 'Personal prep guide';
      case 'in_trip_daily':
        return 'Morning trip plan';
      case 'post_trip':
        return 'Wrap-up checklist';
      default:
        return 'Trip checklist';
    }
  }

  /// A short heading for the whole checklist, falling back to the destination.
  String get title {
    final raw = content['title'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return destinationName.isEmpty ? 'Trip checklist' : destinationName;
  }

  /// One-line intro/context for the checklist.
  String get intro {
    for (final key in [
      'intro',
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

  /// Normalized sections, tolerant of both the AI shape (`sections`) and the
  /// legacy static shape (`categories`).
  List<ChecklistSection> get sections {
    final raw =
        (content['sections'] as List<dynamic>?) ??
        (content['categories'] as List<dynamic>?) ??
        const [];

    final result = <ChecklistSection>[];
    for (var s = 0; s < raw.length; s++) {
      final section = raw[s];
      if (section is! Map) continue;
      final rawItems = (section['items'] as List<dynamic>? ?? const []);
      final items = <ChecklistItem>[];
      for (var i = 0; i < rawItems.length; i++) {
        final item = rawItems[i];
        if (item is! Map) continue;
        final text = (item['text'] as String? ?? '').trim();
        if (text.isEmpty) continue;
        items.add(
          ChecklistItem(
            sectionIndex: s,
            itemIndex: i,
            text: text,
            detail: _itemDetail(item),
            priority: (item['priority'] as String? ?? '').trim().toLowerCase(),
            actionLabel: (item['action_label'] as String? ?? '').trim(),
            done: item['done'] == true,
          ),
        );
      }
      result.add(
        ChecklistSection(
          name: section['name'] as String? ?? 'Checklist',
          emoji: section['emoji'] as String? ?? '📋',
          context: section['context'] as String? ??
              section['time_context'] as String? ??
              '',
          items: items,
        ),
      );
    }
    return result;
  }

  int get totalItems =>
      sections.fold(0, (sum, section) => sum + section.items.length);

  int get completedItems => sections.fold(
        0,
        (sum, section) =>
            sum + section.items.where((item) => item.done).length,
      );

  /// Combines extra context fields from legacy item shapes into one detail line.
  static String _itemDetail(Map item) {
    final explicit = (item['detail'] as String? ?? '').trim();
    if (explicit.isNotEmpty) return explicit;

    final parts = <String>[
      if ((item['time'] as String?)?.trim().isNotEmpty == true)
        (item['time'] as String).trim(),
      if ((item['tip'] as String?)?.trim().isNotEmpty == true)
        (item['tip'] as String).trim(),
    ];
    return parts.join(' · ');
  }

  factory TripChecklist.fromSupabase(Map<String, dynamic> json) {
    final rawContent = json['content'];
    return TripChecklist(
      id: json['id'] as String? ?? '',
      tripId: json['trip_id'] as String? ?? '',
      checklistType: json['checklist_type'] as String? ?? '',
      checklistDate:
          DateTime.tryParse(json['checklist_date'] as String? ?? '') ??
          DateTime.now(),
      dayNumber: (json['day_number'] as num?)?.toInt(),
      destinationName: json['destination_name'] as String? ?? '',
      tripDates: json['trip_dates'] as String? ?? '',
      content:
          rawContent is Map
              ? Map<String, dynamic>.from(rawContent)
              : <String, dynamic>{},
      generatedAt:
          DateTime.tryParse(json['generated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class ChecklistSection {
  final String name;
  final String emoji;
  final String context;
  final List<ChecklistItem> items;

  const ChecklistSection({
    required this.name,
    required this.emoji,
    required this.context,
    required this.items,
  });
}

class ChecklistItem {
  /// Index of the owning section within the checklist content.
  final int sectionIndex;

  /// Index of this item within its section.
  final int itemIndex;
  final String text;
  final String detail;
  final String priority;
  final String actionLabel;
  final bool done;

  const ChecklistItem({
    required this.sectionIndex,
    required this.itemIndex,
    required this.text,
    required this.detail,
    required this.priority,
    required this.actionLabel,
    required this.done,
  });
}
