import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:raaste/features/destination/domain/models/destination_research.dart';
import 'package:raaste/features/destination/domain/models/trip_intake.dart';

class DestinationResearchService {
  static const _assets = <_ResearchAsset>[
    _ResearchAsset(
      sourceId: 'hyderabad',
      assetPath: 'assets/research/hyderabad_raaste_research.json',
      matchTerms: ['hyderabad', 'secunderabad'],
    ),
    _ResearchAsset(
      sourceId: 'lonavala',
      assetPath: 'assets/research/lonavala_raaste_research.json',
      matchTerms: ['lonavala', 'khandala', 'pawna', 'karla'],
    ),
    _ResearchAsset(
      sourceId: 'varanasi',
      assetPath: 'assets/research/varanasi_raaste_research.json',
      matchTerms: ['varanasi', 'banaras', 'benares', 'kashi'],
    ),
  ];

  final AssetBundle _bundle;

  DestinationResearchService({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  Future<DestinationResearch?> loadForIntake(TripIntake intake) async {
    final destinationText =
        [intake.destination, intake.displayAddress].join(' ').toLowerCase();

    for (final asset in _assets) {
      if (!_matches(asset, destinationText)) continue;

      final research = await _load(asset);
      if (research != null) return research;
    }

    return null;
  }

  bool _matches(_ResearchAsset asset, String text) {
    return asset.matchTerms.any(text.contains);
  }

  Future<DestinationResearch?> _load(_ResearchAsset asset) async {
    try {
      final raw = await _bundle.loadString(asset.assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final destination = decoded['destination'];
      final destinationName =
          destination is Map<String, dynamic>
              ? destination['name'] as String? ?? asset.sourceId
              : asset.sourceId;

      return DestinationResearch(
        destinationName: destinationName,
        sourceId: asset.sourceId,
        assetPath: asset.assetPath,
        data: decoded,
      );
    } catch (_) {
      return null;
    }
  }
}

class _ResearchAsset {
  final String sourceId;
  final String assetPath;
  final List<String> matchTerms;

  const _ResearchAsset({
    required this.sourceId,
    required this.assetPath,
    required this.matchTerms,
  });
}
