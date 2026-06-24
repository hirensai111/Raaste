import 'package:equatable/equatable.dart';

class Destination extends Equatable {
  final String id;
  final String name;
  final String state;
  final String tagline;
  final String description;
  final List<String> tags;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;

  const Destination({
    required this.id,
    required this.name,
    required this.state,
    required this.tagline,
    required this.description,
    required this.tags,
    this.imageUrl,
    this.latitude,
    this.longitude,
  });

  @override
  List<Object?> get props => [
        id,
        name,
        state,
        tagline,
        description,
        tags,
        imageUrl,
        latitude,
        longitude,
      ];
}
