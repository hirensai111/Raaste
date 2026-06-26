class OsmPlaceBundle {
  final List<OsmPlace> attractions;
  final List<OsmPlace> food;
  final int radiusMeters;

  const OsmPlaceBundle({
    required this.attractions,
    required this.food,
    required this.radiusMeters,
  });

  bool get isSparse => attractions.length < 3 || food.length < 2;

  Map<String, dynamic> toJson() => {
        'radiusMeters': radiusMeters,
        'attractions': attractions.map((place) => place.toJson()).toList(),
        'food': food.map((place) => place.toJson()).toList(),
      };
}

class OsmPlace {
  final String sourceId;
  final String name;
  final String category;
  final String type;
  final double lat;
  final double lon;
  final Map<String, String> tags;

  const OsmPlace({
    required this.sourceId,
    required this.name,
    required this.category,
    required this.type,
    required this.lat,
    required this.lon,
    required this.tags,
  });

  factory OsmPlace.fromOverpass(Map<String, dynamic> json) {
    final tags = (json['tags'] as Map<String, dynamic>? ?? const {})
        .map((key, value) => MapEntry(key, value.toString()));
    final center = json['center'] as Map<String, dynamic>? ?? const {};
    final lat = (json['lat'] as num?)?.toDouble() ??
        (center['lat'] as num?)?.toDouble() ??
        0;
    final lon = (json['lon'] as num?)?.toDouble() ??
        (center['lon'] as num?)?.toDouble() ??
        0;
    final elementType = json['type']?.toString() ?? 'osm';
    final id = json['id']?.toString() ?? '';

    return OsmPlace(
      sourceId: '$elementType:$id',
      name: _nameFromTags(tags),
      category: _categoryFromTags(tags),
      type: _typeFromTags(tags),
      lat: lat,
      lon: lon,
      tags: tags,
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'name': name,
        'category': category,
        'type': type,
        'lat': lat,
        'lon': lon,
        'tags': tags,
      };

  static String _nameFromTags(Map<String, String> tags) {
    return tags['name'] ?? tags['name:en'] ?? tags['brand'] ?? 'Unnamed place';
  }

  static String _categoryFromTags(Map<String, String> tags) {
    if (tags.containsKey('amenity')) return 'food';
    return 'attraction';
  }

  static String _typeFromTags(Map<String, String> tags) {
    return tags['tourism'] ??
        tags['amenity'] ??
        tags['historic'] ??
        tags['leisure'] ??
        'place';
  }
}
