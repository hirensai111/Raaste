class PopularAttraction {
  final String title;
  final String location;
  final String planningDestination;
  final String image;
  final List<String> tags;
  final double lat;
  final double lon;

  const PopularAttraction({
    required this.title,
    required this.location,
    required this.planningDestination,
    required this.image,
    required this.tags,
    required this.lat,
    required this.lon,
  });

  String get address => '$planningDestination, India - $title: $location';

  String get sourceId =>
      planningDestination.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}

const popularAttractions = [
  PopularAttraction(
    title: 'Hyderabad',
    location: 'Telangana',
    planningDestination: 'Hyderabad',
    image: 'assets/images/home_current_trip.png',
    tags: ['Heritage', 'Biryani', 'Old City'],
    lat: 17.3850,
    lon: 78.4867,
  ),
  PopularAttraction(
    title: 'Varanasi',
    location: 'Uttar Pradesh',
    planningDestination: 'Varanasi',
    image: 'assets/images/home_tip_art.png',
    tags: ['Ghats', 'Spiritual', 'Food walks'],
    lat: 25.3176,
    lon: 82.9739,
  ),
  PopularAttraction(
    title: 'Lonavala',
    location: 'Maharashtra',
    planningDestination: 'Lonavala',
    image: 'assets/images/home_popular_coorg_light.png',
    tags: ['Monsoon', 'Viewpoints', 'Forts'],
    lat: 18.7546,
    lon: 73.4062,
  ),
  PopularAttraction(
    title: 'Jaipur',
    location: 'Rajasthan',
    planningDestination: 'Jaipur',
    image: 'assets/images/explore_trending_jaipur.png',
    tags: ['Palaces', 'Heritage', 'Shopping'],
    lat: 26.9124,
    lon: 75.7873,
  ),
  PopularAttraction(
    title: 'Goa',
    location: 'Goa',
    planningDestination: 'Goa',
    image: 'assets/images/explore_trending_goa.png',
    tags: ['Beaches', 'Food', 'Nightlife'],
    lat: 15.2993,
    lon: 74.1240,
  ),
  PopularAttraction(
    title: 'Manali',
    location: 'Himachal Pradesh',
    planningDestination: 'Manali',
    image: 'assets/images/explore_trending_manali.png',
    tags: ['Mountains', 'Adventure', 'Snow'],
    lat: 32.2396,
    lon: 77.1887,
  ),
  PopularAttraction(
    title: 'Munnar',
    location: 'Kerala',
    planningDestination: 'Munnar',
    image: 'assets/images/home_destination_munnar.png',
    tags: ['Tea gardens', 'Nature', 'Views'],
    lat: 10.0889,
    lon: 77.0595,
  ),
  PopularAttraction(
    title: 'Alleppey',
    location: 'Kerala',
    planningDestination: 'Alleppey',
    image: 'assets/images/explore_region_south.png',
    tags: ['Backwaters', 'Houseboats', 'Seafood'],
    lat: 9.4981,
    lon: 76.3388,
  ),
  PopularAttraction(
    title: 'Jaisalmer',
    location: 'Rajasthan',
    planningDestination: 'Jaisalmer',
    image: 'assets/images/explore_region_west.png',
    tags: ['Desert', 'Forts', 'Culture'],
    lat: 26.9157,
    lon: 70.9083,
  ),
  PopularAttraction(
    title: 'Hampi',
    location: 'Karnataka',
    planningDestination: 'Hampi',
    image: 'assets/images/home_trip_art.png',
    tags: ['Ruins', 'History', 'Photography'],
    lat: 15.3350,
    lon: 76.4600,
  ),
];
