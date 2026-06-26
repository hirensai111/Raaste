class DestinationResearch {
  final String destinationName;
  final String assetPath;
  final Map<String, dynamic> data;

  const DestinationResearch({
    required this.destinationName,
    required this.assetPath,
    required this.data,
  });

  Map<String, dynamic> toPromptJson() => {
    'destinationName': destinationName,
    'assetPath': assetPath,
    'research': data,
  };
}
