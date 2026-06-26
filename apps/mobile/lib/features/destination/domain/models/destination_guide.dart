import 'package:raaste/features/destination/domain/models/trip_intake.dart';

class DestinationGuide {
  final String id;
  final String destinationName;
  final TripIntake intake;
  final GuideOverview overview;
  final List<ItineraryDay> itineraryDays;
  final List<String> disclaimers;
  final DateTime updatedAt;

  const DestinationGuide({
    required this.id,
    required this.destinationName,
    required this.intake,
    required this.overview,
    required this.itineraryDays,
    required this.disclaimers,
    required this.updatedAt,
  });

  DestinationGuide copyWith({
    String? id,
    String? destinationName,
    TripIntake? intake,
    GuideOverview? overview,
    List<ItineraryDay>? itineraryDays,
    List<String>? disclaimers,
    DateTime? updatedAt,
  }) {
    return DestinationGuide(
      id: id ?? this.id,
      destinationName: destinationName ?? this.destinationName,
      intake: intake ?? this.intake,
      overview: overview ?? this.overview,
      itineraryDays: itineraryDays ?? this.itineraryDays,
      disclaimers: disclaimers ?? this.disclaimers,
      updatedAt: updatedAt ?? this.updatedAt,
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
      };

  factory DestinationGuide.fromJson(Map<String, dynamic> json) {
    return DestinationGuide(
      id: json['id'] as String? ?? '',
      destinationName: json['destinationName'] as String? ?? '',
      intake: TripIntake.fromJson(
        json['intake'] as Map<String, dynamic>? ?? const {},
      ),
      overview: GuideOverview.fromJson(
        json['overview'] as Map<String, dynamic>? ?? const {},
      ),
      itineraryDays: (json['itineraryDays'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ItineraryDay.fromJson)
          .toList(),
      disclaimers: (json['disclaimers'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
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
        summary: json['summary'] as String? ?? '',
        bestTimeToVisit: json['bestTimeToVisit'] as String? ?? '',
        howToGetThere: json['howToGetThere'] as String? ?? '',
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
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String? ?? '',
        stops: (json['stops'] as List<dynamic>? ?? const [])
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
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        type: json['type'] as String? ?? 'activity',
        sourceId: json['sourceId'] as String? ?? '',
        lat: (json['lat'] as num?)?.toDouble(),
        lon: (json['lon'] as num?)?.toDouble(),
      );
}
