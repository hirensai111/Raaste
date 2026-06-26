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
