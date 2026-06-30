import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get_it/get_it.dart';
import 'package:raaste/core/network/dio_client.dart';
import 'package:raaste/core/network/network_info.dart';
import 'package:raaste/core/services/location_service.dart';
import 'package:raaste/core/services/storage_service.dart';
import 'package:raaste/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:raaste/features/auth/domain/repositories/auth_repository.dart';
import 'package:raaste/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:raaste/features/checklist/application/open_ai_checklist_service.dart';
import 'package:raaste/features/checklist/application/research_checklist_content_service.dart';
import 'package:raaste/features/checklist/application/trip_checklist_repository.dart';
import 'package:raaste/features/companion/application/local_itinerary_edit_service.dart';
import 'package:raaste/features/destination/data/repositories/destination_guide_store.dart';
import 'package:raaste/features/destination/data/services/destination_research_service.dart';
import 'package:raaste/features/destination/data/services/destination_search_service.dart';
import 'package:raaste/features/destination/data/services/google_route_matrix_service.dart';
import 'package:raaste/features/destination/data/services/open_ai_destination_service.dart';
import 'package:raaste/features/destination/data/services/stay_search_service.dart';
import 'package:raaste/features/food/data/repositories/food_repository.dart';
import 'package:raaste/features/trip/data/repositories/saved_trip_repository.dart';
import 'package:raaste/features/trip/data/services/place_image_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GetIt getIt = GetIt.instance;

Future<void> configureDependencies() async {
  // Core
  getIt.registerLazySingleton<DioClient>(() => DioClient());
  getIt.registerLazySingleton<Connectivity>(() => Connectivity());
  getIt.registerLazySingleton<NetworkInfo>(
    () => NetworkInfoImpl(getIt<Connectivity>()),
  );
  getIt.registerLazySingleton<LocationService>(() => LocationService());

  // Storage
  final sharedPrefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(sharedPrefs);
  getIt.registerLazySingleton<StorageService>(
    () => StorageServiceImpl(getIt<SharedPreferences>()),
  );

  // Auth
  getIt.registerLazySingleton<AuthRepository>(() => AuthRepositoryImpl());
  getIt.registerFactory<AuthBloc>(() => AuthBloc(getIt<AuthRepository>()));

  // Destination planning
  getIt.registerLazySingleton<DestinationResearchService>(
    () => DestinationResearchService(),
  );
  getIt.registerLazySingleton<DestinationSearchService>(
    () => DestinationSearchService(
      researchService: getIt<DestinationResearchService>(),
    ),
  );
  getIt.registerLazySingleton<StaySearchService>(() => StaySearchService());
  getIt.registerLazySingleton<GoogleRouteMatrixService>(
    () => GoogleRouteMatrixService(),
  );
  getIt.registerLazySingleton<OpenAiDestinationService>(
    () => OpenAiDestinationService(),
  );
  getIt.registerLazySingleton<DestinationGuideStore>(
    () => DestinationGuideStore(getIt<StorageService>()),
  );
  getIt.registerLazySingleton<LocalItineraryEditService>(
    () => const LocalItineraryEditService(),
  );

  // Checklists
  getIt.registerLazySingleton<OpenAiChecklistService>(
    () => OpenAiChecklistService(),
  );
  getIt.registerLazySingleton<ResearchChecklistContentService>(
    () => const ResearchChecklistContentService(),
  );
  getIt.registerLazySingleton<TripChecklistRepository>(
    () => TripChecklistRepository(
      checklistService: getIt<OpenAiChecklistService>(),
      researchService: getIt<DestinationResearchService>(),
      researchContentService: getIt<ResearchChecklistContentService>(),
    ),
  );

  // Saved trips
  getIt.registerLazySingleton<PlaceImageService>(() => PlaceImageService());
  getIt.registerLazySingleton<SavedTripRepository>(
    () => SavedTripRepository(
      imageService: getIt<PlaceImageService>(),
      checklistRepository: getIt<TripChecklistRepository>(),
    ),
  );

  // Food discovery
  getIt.registerLazySingleton<FoodRepository>(
    () => FoodRepository(savedTrips: getIt<SavedTripRepository>()),
  );
}
