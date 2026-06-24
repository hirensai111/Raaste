class AppConstants {
  AppConstants._();

  // Dietary preferences
  static const List<String> dietaryPreferences = [
    'Vegetarian',
    'Non-Vegetarian',
    'Jain',
    'Halal',
    'Vegan',
    'Eggetarian',
  ];

  // Travel styles
  static const List<String> travelStyles = [
    'Budget Backpacker',
    'Mid-Range Explorer',
    'Comfort Traveller',
    'Luxury Seeker',
  ];

  // Travel companions
  static const List<String> travelCompanions = [
    'Solo',
    'Couple',
    'Family',
    'Friends',
    'Group',
  ];

  // Interests
  static const List<String> interests = [
    'Nature',
    'Food',
    'History',
    'Adventure',
    'Nightlife',
    'Spiritual',
    'Shopping',
    'Photography',
    'Wildlife',
    'Beaches',
    'Mountains',
    'Road Trips',
  ];

  // Budget ranges (INR)
  static const Map<String, BudgetRange> budgetRanges = {
    'Shoestring': BudgetRange(0, 3000),
    'Budget': BudgetRange(3000, 8000),
    'Mid-Range': BudgetRange(8000, 20000),
    'Premium': BudgetRange(20000, 50000),
    'Luxury': BudgetRange(50000, double.infinity),
  };
}

class BudgetRange {
  final double min;
  final double max;

  const BudgetRange(this.min, this.max);
}
