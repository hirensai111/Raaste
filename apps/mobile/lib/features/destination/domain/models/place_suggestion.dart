class PlaceSuggestion {
  final String sourceId;
  final String name;
  final String description;
  final String displayAddress;
  final double? lat;
  final double? lon;

  const PlaceSuggestion({
    required this.sourceId,
    required this.name,
    required this.description,
    required this.displayAddress,
    required this.lat,
    required this.lon,
  });

  factory PlaceSuggestion.curated({
    required String sourceId,
    required String name,
    required String state,
    required String tagline,
    required double lat,
    required double lon,
  }) {
    return PlaceSuggestion(
      sourceId: sourceId,
      name: name,
      description: tagline.isNotEmpty ? tagline : '$state, India',
      displayAddress: '$name, $state, India',
      lat: lat,
      lon: lon,
    );
  }
}
