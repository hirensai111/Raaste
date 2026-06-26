import 'package:raaste/features/destination/domain/models/destination_guide.dart';

class SavedTrip {
  final String id;
  final String userId;
  final String guideId;
  final String destinationName;
  final String destinationAddress;
  final String dates;
  final int peopleCount;
  final String imageUrl;
  final DestinationGuide guide;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SavedTrip({
    required this.id,
    required this.userId,
    required this.guideId,
    required this.destinationName,
    required this.destinationAddress,
    required this.dates,
    required this.peopleCount,
    required this.imageUrl,
    required this.guide,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasRemoteImage => imageUrl.trim().startsWith('http');

  factory SavedTrip.fromSupabase(Map<String, dynamic> json) {
    final guideJson =
        json['guide_json'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return SavedTrip(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      guideId: json['guide_id'] as String? ?? '',
      destinationName: json['destination_name'] as String? ?? '',
      destinationAddress: json['destination_address'] as String? ?? '',
      dates: json['dates'] as String? ?? '',
      peopleCount: (json['people_count'] as num?)?.toInt() ?? 1,
      imageUrl: json['image_url'] as String? ?? '',
      guide: DestinationGuide.fromJson(guideJson),
      status: json['status'] as String? ?? 'planned',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
