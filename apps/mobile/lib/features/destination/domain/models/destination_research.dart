class DestinationResearch {
  final String destinationName;
  final String sourceId;
  final String assetPath;
  final Map<String, dynamic> data;

  const DestinationResearch({
    required this.destinationName,
    required this.sourceId,
    required this.assetPath,
    required this.data,
  });

  Map<String, dynamic> toPromptJson() => {
    'destinationName': destinationName,
    'sourceId': sourceId,
    'assetPath': assetPath,
    'research': data,
  };
}
