import 'package:raaste/features/destination/domain/models/itinerary_timing_context.dart';
import 'package:raaste/features/destination/domain/models/trip_intake.dart';

class DestinationGuide {
  final String id;
  final String destinationName;
  final TripIntake intake;
  final GuideOverview overview;
  final List<ItineraryDay> itineraryDays;
  final List<String> disclaimers;
  final DateTime updatedAt;
  final ItineraryTimingContext? timingContext;

  const DestinationGuide({
    required this.id,
    required this.destinationName,
    required this.intake,
    required this.overview,
    required this.itineraryDays,
    required this.disclaimers,
    required this.updatedAt,
    this.timingContext,
  });

  DestinationGuide copyWith({
    String? id,
    String? destinationName,
    TripIntake? intake,
    GuideOverview? overview,
    List<ItineraryDay>? itineraryDays,
    List<String>? disclaimers,
    DateTime? updatedAt,
    ItineraryTimingContext? timingContext,
  }) {
    return DestinationGuide(
      id: id ?? this.id,
      destinationName: destinationName ?? this.destinationName,
      intake: intake ?? this.intake,
      overview: overview ?? this.overview,
      itineraryDays: itineraryDays ?? this.itineraryDays,
      disclaimers: disclaimers ?? this.disclaimers,
      updatedAt: updatedAt ?? this.updatedAt,
      timingContext: timingContext ?? this.timingContext,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'destinationName': destinationName,
    'intake': intake.toJson(),
    'overview': overview.toJson(),
    'itineraryDays': itineraryDays.map((item) => item.toJson()).toList(),
    'disclaimers': disclaimers,
    'updatedAt': updatedAt.toIso8601String(),
    if (timingContext != null) 'timingContext': timingContext!.toJson(),
  };

  factory DestinationGuide.fromJson(Map<String, dynamic> json) {
    final days =
        (json['itineraryDays'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ItineraryDay.fromJson)
            .toList();

    return DestinationGuide(
      id: json['id'] as String? ?? '',
      destinationName: _cleanVisibleText(
        json['destinationName'] as String? ?? '',
      ),
      intake: TripIntake.fromJson(
        json['intake'] as Map<String, dynamic>? ?? const {},
      ),
      overview: GuideOverview.fromJson(
        json['overview'] as Map<String, dynamic>? ?? const {},
      ),
      itineraryDays: _sanitizeItineraryDays(days),
      disclaimers:
          (json['disclaimers'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .map(_cleanVisibleText)
              .where((text) => text.isNotEmpty)
              .toList(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      timingContext:
          json['timingContext'] is Map<String, dynamic>
              ? ItineraryTimingContext.fromJson(
                json['timingContext'] as Map<String, dynamic>,
              )
              : null,
    );
  }
}

class GuideOverview {
  final String summary;
  final String bestTimeToVisit;
  final String howToGetThere;

  const GuideOverview({
    required this.summary,
    required this.bestTimeToVisit,
    required this.howToGetThere,
  });

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'bestTimeToVisit': bestTimeToVisit,
    'howToGetThere': howToGetThere,
  };

  factory GuideOverview.fromJson(Map<String, dynamic> json) => GuideOverview(
    summary: _cleanVisibleText(json['summary'] as String? ?? ''),
    bestTimeToVisit: _cleanVisibleText(
      json['bestTimeToVisit'] as String? ?? '',
    ),
    howToGetThere: _cleanVisibleText(json['howToGetThere'] as String? ?? ''),
  );
}

class ItineraryDay {
  final int dayNumber;
  final String title;
  final String subtitle;
  final List<ItineraryStop> stops;

  const ItineraryDay({
    required this.dayNumber,
    required this.title,
    required this.subtitle,
    required this.stops,
  });

  Map<String, dynamic> toJson() => {
    'dayNumber': dayNumber,
    'title': title,
    'subtitle': subtitle,
    'stops': stops.map((stop) => stop.toJson()).toList(),
  };

  factory ItineraryDay.fromJson(Map<String, dynamic> json) => ItineraryDay(
    dayNumber: (json['dayNumber'] as num?)?.toInt() ?? 1,
    title: _cleanVisibleText(json['title'] as String? ?? ''),
    subtitle: _cleanVisibleText(json['subtitle'] as String? ?? ''),
    stops:
        (json['stops'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ItineraryStop.fromJson)
            .toList(),
  );
}

class ItineraryStop {
  final String time;
  final String title;
  final String description;
  final String type;
  final String sourceId;
  final double? lat;
  final double? lon;

  const ItineraryStop({
    required this.time,
    required this.title,
    required this.description,
    required this.type,
    required this.sourceId,
    required this.lat,
    required this.lon,
  });

  Map<String, dynamic> toJson() => {
    'time': time,
    'title': title,
    'description': description,
    'type': type,
    'sourceId': sourceId,
    'lat': lat,
    'lon': lon,
  };

  factory ItineraryStop.fromJson(Map<String, dynamic> json) => ItineraryStop(
    time: json['time'] as String? ?? '',
    title: _cleanVisibleText(json['title'] as String? ?? ''),
    description: _cleanVisibleText(json['description'] as String? ?? ''),
    type: json['type'] as String? ?? 'activity',
    sourceId: json['sourceId'] as String? ?? '',
    lat: (json['lat'] as num?)?.toDouble(),
    lon: (json['lon'] as num?)?.toDouble(),
  );
}

List<ItineraryDay> _sanitizeItineraryDays(List<ItineraryDay> days) {
  final seen = <String>{};
  final cleanedDays = <ItineraryDay>[];

  for (final day in days) {
    final cleanedStops = <ItineraryStop>[];
    for (final stop in day.stops) {
      if (_isPlaceholderMealStop(stop)) continue;

      final key = _dedupeKeyForStop(stop);
      if (key != null && seen.contains(key)) continue;
      if (key != null) seen.add(key);
      cleanedStops.add(stop);
    }

    cleanedDays.add(
      ItineraryDay(
        dayNumber: day.dayNumber,
        title: day.title,
        subtitle: day.subtitle,
        stops: _sortStopsChronologically(cleanedStops),
      ),
    );
  }

  return cleanedDays;
}

List<ItineraryStop> _sortStopsChronologically(List<ItineraryStop> stops) {
  final indexed = stops.asMap().entries.toList();
  indexed.sort((a, b) {
    final aTime = _startMinuteOfDay(a.value.time);
    final bTime = _startMinuteOfDay(b.value.time);
    if (aTime == null && bTime == null) return a.key.compareTo(b.key);
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    final comparison = aTime.compareTo(bTime);
    return comparison == 0 ? a.key.compareTo(b.key) : comparison;
  });
  return indexed.map((entry) => entry.value).toList();
}

int? _startMinuteOfDay(String value) {
  final text = value.toUpperCase().replaceAll('.', '').trim();
  if (text.isEmpty) return null;

  final matches =
      RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?').allMatches(text).toList();
  if (matches.isEmpty) return null;

  final first = matches.first;
  final hour = int.tryParse(first.group(1) ?? '');
  final minute = int.tryParse(first.group(2) ?? '0') ?? 0;
  if (hour == null || hour < 1 || hour > 12 || minute < 0 || minute > 59) {
    return null;
  }

  var marker = first.group(3);
  if (marker == null) {
    for (final match in matches.skip(1)) {
      marker = match.group(3);
      if (marker != null) break;
    }
  }
  if (marker == null) return null;

  var normalizedHour = hour % 12;
  if (marker == 'PM') normalizedHour += 12;
  return normalizedHour * 60 + minute;
}

bool _isPlaceholderMealStop(ItineraryStop stop) {
  final text = '${stop.title} ${stop.description}'.toLowerCase();
  return text.contains('ask your hotel for dietary-appropriate options') ||
      text.contains('ask your hotel for dietary appropriate options') ||
      text.contains('no matching restaurant') ||
      text.contains('database for this area is growing') ||
      text.contains('doesn\'t provide a reliable') ||
      text.contains('does not provide a reliable');
}

String? _dedupeKeyForStop(ItineraryStop stop) {
  final type = stop.type.toLowerCase();
  final title = stop.title.toLowerCase();
  final generic =
      type.contains('travel') ||
      type.contains('transfer') ||
      type.contains('checkin') ||
      type.contains('check-in') ||
      type.contains('checkout') ||
      type.contains('rest') ||
      type.contains('buffer') ||
      title.contains('arrive') ||
      title.contains('check-in') ||
      title.contains('check in') ||
      title.contains('transfer') ||
      title.contains('luggage') ||
      title.contains('rest');
  if (generic) return null;

  final source = stop.sourceId.trim().toLowerCase();
  if (source.isNotEmpty && source.startsWith('research:')) {
    return 'source:$source';
  }

  final normalizedTitle = _normalizeStopTitle(stop.title);
  if (normalizedTitle.length < 4) return null;
  return 'title:$normalizedTitle';
}

String _normalizeStopTitle(String value) {
  return value
      .toLowerCase()
      .replaceFirst(RegExp(r'^(breakfast|lunch|dinner|snack)\s+at\s+'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

String _cleanVisibleText(String value) {
  var text = value.trim();
  if (text.isEmpty) return text;

  text = text.replaceAll(
    RegExp(
      r'\s*(?:Source IDs?|source IDs?|sourceIds?)\s*:\s*.*$',
      caseSensitive: false,
    ),
    '',
  );
  text = text.replaceAll(
    RegExp(r'\s*\(?\s*sourceId\s*:\s*.*$', caseSensitive: false),
    '',
  );
  text = text.replaceAll(
    RegExp(
      r'\s*research:[a-z0-9_:\-]+(?:\s*,\s*research:[a-z0-9_:\-]+)*\.?',
      caseSensitive: false,
    ),
    '',
  );
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  text = text.replaceAllMapped(
    RegExp(r'\s+([,.;:])'),
    (match) => match.group(1)!,
  );
  text = text.replaceAll(RegExp(r'\(\s*\)'), '').trim();
  return text;
}
