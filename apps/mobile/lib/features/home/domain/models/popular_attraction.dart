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
      'place_type:${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
}

const popularAttractions = [
  PopularAttraction(
    title: 'Hill Stations',
    location: 'Manali, Munnar, Ooty',
    planningDestination: 'Manali',
    image: 'assets/images/explore_trending_manali.png',
    tags: ['Mountains', 'Nature', 'Cool weather'],
    lat: 32.2396,
    lon: 77.1887,
  ),
  PopularAttraction(
    title: 'Beach Escapes',
    location: 'Goa, Gokarna, Varkala',
    planningDestination: 'Goa',
    image: 'assets/images/explore_trending_goa.png',
    tags: ['Beach', 'Food', 'Nightlife'],
    lat: 15.2993,
    lon: 74.124,
  ),
  PopularAttraction(
    title: 'Royal Cities',
    location: 'Jaipur, Udaipur, Jodhpur',
    planningDestination: 'Jaipur',
    image: 'assets/images/explore_trending_jaipur.png',
    tags: ['Palaces', 'Heritage', 'Shopping'],
    lat: 26.9124,
    lon: 75.7873,
  ),
  PopularAttraction(
    title: 'Tea Gardens',
    location: 'Munnar, Coorg, Chikmagalur',
    planningDestination: 'Munnar',
    image: 'assets/images/home_destination_munnar.png',
    tags: ['Tea', 'Slow travel', 'Views'],
    lat: 10.0889,
    lon: 77.0595,
  ),
  PopularAttraction(
    title: 'Backwaters',
    location: 'Alleppey, Kumarakom, Kochi',
    planningDestination: 'Alleppey',
    image: 'assets/images/explore_region_south.png',
    tags: ['Houseboats', 'Food', 'Calm'],
    lat: 9.4981,
    lon: 76.3388,
  ),
  PopularAttraction(
    title: 'Desert Trails',
    location: 'Jaisalmer, Bikaner, Kutch',
    planningDestination: 'Jaisalmer',
    image: 'assets/images/explore_region_west.png',
    tags: ['Desert', 'Forts', 'Culture'],
    lat: 26.9157,
    lon: 70.9083,
  ),
  PopularAttraction(
    title: 'Spiritual Cities',
    location: 'Varanasi, Rishikesh, Amritsar',
    planningDestination: 'Varanasi',
    image: 'assets/images/home_tip_art.png',
    tags: ['Spiritual', 'Rivers', 'Local food'],
    lat: 25.3176,
    lon: 82.9739,
  ),
  PopularAttraction(
    title: 'Wildlife Breaks',
    location: 'Ranthambore, Jim Corbett, Kaziranga',
    planningDestination: 'Ranthambore National Park',
    image: 'assets/images/explore_region_himalayas.png',
    tags: ['Wildlife', 'Safari', 'Nature'],
    lat: 26.0173,
    lon: 76.5026,
  ),
  PopularAttraction(
    title: 'Ancient Ruins',
    location: 'Hampi, Khajuraho, Ajanta',
    planningDestination: 'Hampi',
    image: 'assets/images/home_trip_art.png',
    tags: ['UNESCO', 'History', 'Photography'],
    lat: 15.335,
    lon: 76.46,
  ),
  PopularAttraction(
    title: 'City Weekends',
    location: 'Mumbai, Delhi, Bengaluru',
    planningDestination: 'Mumbai',
    image: 'assets/images/home_current_trip.png',
    tags: ['City', 'Food', 'Short trip'],
    lat: 19.076,
    lon: 72.8777,
  ),
];
