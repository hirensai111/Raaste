class DestinationResearch {
  final String destinationName;
  final String sourceId;
  final String assetPath;
  final Map<String, dynamic> data;
  final String? restaurantAssetPath;
  final Map<String, dynamic>? restaurantData;

  const DestinationResearch({
    required this.destinationName,
    required this.sourceId,
    required this.assetPath,
    required this.data,
    this.restaurantAssetPath,
    this.restaurantData,
  });

  Map<String, dynamic> toPromptJson() => {
    'destinationName': destinationName,
    'sourceId': sourceId,
    'assetPath': assetPath,
    'research': data,
    if (restaurantAssetPath != null && restaurantData != null)
      'restaurantAssetPath': restaurantAssetPath,
    if (restaurantData != null) 'restaurantResearch': restaurantData,
  };
}
