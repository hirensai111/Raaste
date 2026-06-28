import 'package:raaste/features/destination/data/services/destination_research_service.dart';
import 'package:raaste/features/destination/domain/models/place_suggestion.dart';

class DestinationSearchException implements Exception {
  final String message;
  const DestinationSearchException(this.message);

  @override
  String toString() => message;
}

class DestinationSearchService {
  final DestinationResearchService _researchService;

  DestinationSearchService({DestinationResearchService? researchService})
    : _researchService = researchService ?? DestinationResearchService();

  Future<List<PlaceSuggestion>> autocomplete(String input) async {
    final query = input.trim().toLowerCase();
    if (query.length < 2) return const [];

    final destinations = _researchService.availableDestinations();
    final results = <PlaceSuggestion>[];

    for (final destination in destinations) {
      final searchable =
          [
            destination.name,
            destination.description,
            destination.displayAddress,
            ..._researchService.matchTermsFor(destination.sourceId),
          ].join(' ').toLowerCase();

      if (searchable.contains(query)) results.add(destination);
    }

    return results;
  }

  PlaceSuggestion? findCuratedDestination(String input) {
    final query = input.trim().toLowerCase();
    if (query.isEmpty) return null;

    for (final destination in _researchService.availableDestinations()) {
      final terms = [
        destination.name,
        destination.displayAddress,
        ..._researchService.matchTermsFor(destination.sourceId),
      ].map((item) => item.trim().toLowerCase());

      if (terms.any((term) => term == query)) return destination;
    }

    return null;
  }
}
