import 'dart:convert';

import 'package:raaste/core/services/storage_service.dart';
import 'package:raaste/features/destination/domain/models/destination_guide.dart';

class DestinationGuideStore {
  static const _storageKey = 'destination_guides';
  final StorageService _storage;

  const DestinationGuideStore(this._storage);

  Future<String> saveGuide(DestinationGuide guide) async {
    final guides = await _readAll();
    final id = guide.id.trim().isNotEmpty
        ? guide.id
        : 'guide_${DateTime.now().millisecondsSinceEpoch}';
    final saved = guide.copyWith(id: id, updatedAt: DateTime.now());

    guides[id] = saved.toJson();
    await _storage.setString(_storageKey, jsonEncode(guides));
    return id;
  }

  Future<DestinationGuide?> getGuide(String id) async {
    final guides = await _readAll();
    final raw = guides[id];
    if (raw is! Map<String, dynamic>) return null;
    return DestinationGuide.fromJson(raw);
  }

  Future<Map<String, dynamic>> _readAll() async {
    final raw = await _storage.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    return {};
  }
}
