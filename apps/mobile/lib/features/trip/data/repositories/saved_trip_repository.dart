import 'package:raaste/features/destination/domain/models/destination_guide.dart';
import 'package:raaste/features/trip/data/services/place_image_service.dart';
import 'package:raaste/features/trip/domain/models/saved_trip.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SavedTripException implements Exception {
  final String message;

  const SavedTripException(this.message);

  @override
  String toString() => message;
}

class SavedTripRepository {
  final SupabaseClient _client;
  final PlaceImageService _imageService;

  SavedTripRepository({SupabaseClient? client, PlaceImageService? imageService})
    : _client = client ?? Supabase.instance.client,
      _imageService = imageService ?? PlaceImageService();

  Future<List<SavedTrip>> listTrips() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];

    try {
      final rows = await _client
          .from('saved_trips')
          .select()
          .eq('user_id', user.id)
          .order('updated_at', ascending: false);
      return rows
          .whereType<Map<String, dynamic>>()
          .map(SavedTrip.fromSupabase)
          .toList();
    } on PostgrestException catch (e) {
      throw SavedTripException(_friendlyDatabaseMessage(e));
    } catch (_) {
      throw const SavedTripException('Could not load your trips right now.');
    }
  }

  Future<SavedTrip?> getTrip(String tripId) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final row =
          await _client
              .from('saved_trips')
              .select()
              .eq('id', tripId)
              .eq('user_id', user.id)
              .maybeSingle();
      if (row == null) return null;
      return SavedTrip.fromSupabase(row);
    } on PostgrestException catch (e) {
      throw SavedTripException(_friendlyDatabaseMessage(e));
    } catch (_) {
      throw const SavedTripException('Could not open this trip right now.');
    }
  }

  Future<SavedTrip> saveGuide(DestinationGuide guide) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const SavedTripException('Please sign in to save trips.');
    }

    final imageUrl = await _imageService.imageForDestination(
      guide.destinationName,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final payload = {
      'user_id': user.id,
      'guide_id': guide.id,
      'destination_name': guide.destinationName,
      'destination_address': guide.intake.displayAddress,
      'dates': guide.intake.dates,
      'people_count': guide.intake.peopleCount,
      'image_url': imageUrl,
      'guide_json': guide.toJson(),
      'status': 'planned',
      'updated_at': now,
    };

    try {
      final existing =
          await _client
              .from('saved_trips')
              .select('id, image_url, created_at')
              .eq('user_id', user.id)
              .eq('guide_id', guide.id)
              .maybeSingle();

      final row =
          await _client
              .from('saved_trips')
              .upsert({
                ...payload,
                if (existing != null) 'id': existing['id'],
                if (existing != null) 'image_url': existing['image_url'],
                if (existing == null) 'created_at': now,
              }, onConflict: 'id')
              .select()
              .single();
      return SavedTrip.fromSupabase(row);
    } on PostgrestException catch (e) {
      throw SavedTripException(_friendlyDatabaseMessage(e));
    } catch (_) {
      throw const SavedTripException('Could not save this trip right now.');
    }
  }

  Future<SavedTrip> updateTripGuide({
    required String tripId,
    required DestinationGuide guide,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const SavedTripException('Please sign in to update trips.');
    }

    try {
      final row =
          await _client
              .from('saved_trips')
              .update({
                'guide_id': guide.id,
                'destination_name': guide.destinationName,
                'destination_address': guide.intake.displayAddress,
                'dates': guide.intake.dates,
                'people_count': guide.intake.peopleCount,
                'guide_json': guide.toJson(),
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('id', tripId)
              .eq('user_id', user.id)
              .select()
              .single();
      return SavedTrip.fromSupabase(row);
    } on PostgrestException catch (e) {
      throw SavedTripException(_friendlyDatabaseMessage(e));
    } catch (_) {
      throw const SavedTripException('Could not update this trip right now.');
    }
  }

  String _friendlyDatabaseMessage(PostgrestException e) {
    if (e.code == '42P01' || e.code == 'PGRST205') {
      return 'The saved trips table has not been created yet. Run the saved_trips SQL migration in Supabase first.';
    }
    return e.message.isNotEmpty ? e.message : 'Trip database request failed.';
  }
}
