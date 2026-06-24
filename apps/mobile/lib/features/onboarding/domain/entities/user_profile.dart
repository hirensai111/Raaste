import 'package:equatable/equatable.dart';

class UserProfile extends Equatable {
  final String? id;
  final String? name;
  final String dietaryPreference;
  final String travelStyle;
  final String travelCompanion;
  final List<String> interests;
  final double budgetMin;
  final double budgetMax;

  const UserProfile({
    this.id,
    this.name,
    required this.dietaryPreference,
    required this.travelStyle,
    required this.travelCompanion,
    required this.interests,
    required this.budgetMin,
    required this.budgetMax,
  });

  UserProfile copyWith({
    String? id,
    String? name,
    String? dietaryPreference,
    String? travelStyle,
    String? travelCompanion,
    List<String>? interests,
    double? budgetMin,
    double? budgetMax,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      dietaryPreference: dietaryPreference ?? this.dietaryPreference,
      travelStyle: travelStyle ?? this.travelStyle,
      travelCompanion: travelCompanion ?? this.travelCompanion,
      interests: interests ?? this.interests,
      budgetMin: budgetMin ?? this.budgetMin,
      budgetMax: budgetMax ?? this.budgetMax,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        dietaryPreference,
        travelStyle,
        travelCompanion,
        interests,
        budgetMin,
        budgetMax,
      ];
}
