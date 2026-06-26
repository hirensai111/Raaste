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

  factory PlaceSuggestion.fromNominatim(Map<String, dynamic> json) {
    final displayName = (json['display_name'] as String?)?.trim() ?? '';
    final namedetails = json['namedetails'] as Map<String, dynamic>? ?? {};
    final address = json['address'] as Map<String, dynamic>? ?? {};

    final name = ((json['name'] as String?) ??
            (namedetails['name'] as String?) ??
            _firstDisplayPart(displayName))
        .trim();
    final description = _descriptionFor(displayName, address);
    final osmType = (json['osm_type'] as String?)?.trim() ?? 'osm';
    final osmId = json['osm_id']?.toString() ?? '';

    return PlaceSuggestion(
      sourceId: '$osmType:$osmId',
      name: name.isNotEmpty ? name : 'Destination',
      description: description.isNotEmpty ? description : displayName,
      displayAddress: displayName,
      lat: double.tryParse(json['lat']?.toString() ?? ''),
      lon: double.tryParse(json['lon']?.toString() ?? ''),
    );
  }

  static String _firstDisplayPart(String displayName) {
    return displayName.split(',').first.trim();
  }

  static String _descriptionFor(
    String displayName,
    Map<String, dynamic> address,
  ) {
    final city = address['city'] ??
        address['town'] ??
        address['village'] ??
        address['municipality'];
    final state = address['state'];
    final country = address['country'];
    final parts = [city, state, country]
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    if (parts.isNotEmpty) return parts.join(', ');
    return displayName;
  }
}
