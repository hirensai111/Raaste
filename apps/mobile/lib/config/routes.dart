import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:raaste/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:raaste/features/checklist/presentation/screens/checklist_screen.dart';
import 'package:raaste/features/companion/presentation/screens/companion_screen.dart';
import 'package:raaste/features/destination/presentation/screens/destination_chat_screen.dart';
import 'package:raaste/features/destination/presentation/screens/destination_detail_screen.dart';
import 'package:raaste/features/food/presentation/screens/food_screen.dart';
import 'package:raaste/features/home/presentation/screens/home_screen.dart';
import 'package:raaste/features/home/presentation/screens/popular_attractions_screen.dart';
import 'package:raaste/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:raaste/features/onboarding/presentation/screens/profile_setup_screen.dart';
import 'package:raaste/features/profile/presentation/screens/personal_information_screen.dart';
import 'package:raaste/features/profile/presentation/screens/profile_screen.dart';
import 'package:raaste/features/splash/presentation/screens/splash_screen.dart';
import 'package:raaste/features/trip/presentation/screens/itinerary_screen.dart';
import 'package:raaste/features/trip/presentation/screens/my_trips_screen.dart';
import 'package:raaste/features/trip/presentation/screens/trip_planning_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String profileSetup = '/profile-setup';
  static const String signIn = '/sign-in';
  static const String home = '/home';
  static const String trips = '/trips';
  static const String explore = '/explore';
  static const String food = '/food';
  static const String saved = '/saved';
  static const String destination = '/destination';
  static const String destinationChat = '/destination-chat';
  static const String popularAttractions = '/popular-attractions';
  static const String tripPlanning = '/trip-planning';
  static const String itinerary = '/itinerary';
  static const String companion = '/companion';
  static const String profile = '/profile';
  static const String personalInformation = '/profile/personal-information';
  static const String changePassword = '/profile/change-password';
}

class AppRouter {
  AppRouter._();

  static final _rootNavigatorKey = GlobalKey<NavigatorState>();

  static GoRouter get router => GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (_, state) => _fadePage(state, const SplashScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (_, state) => _fadePage(state, const OnboardingScreen()),
      ),
      GoRoute(
        path: AppRoutes.profileSetup,
        pageBuilder: (_, state) => _fadePage(state, const ProfileSetupScreen()),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        pageBuilder: (_, state) => _fadePage(state, const SignInScreen()),
      ),
      GoRoute(
        path: AppRoutes.home,
        pageBuilder: (_, state) => _fadePage(state, const HomeScreen()),
      ),
      GoRoute(
        path: AppRoutes.popularAttractions,
        builder: (_, __) => const PopularAttractionsScreen(),
      ),
      GoRoute(path: AppRoutes.trips, builder: (_, __) => const MyTripsScreen()),
      GoRoute(path: AppRoutes.food, builder: (_, __) => const FoodScreen()),
      GoRoute(path: AppRoutes.explore, builder: (_, __) => const FoodScreen()),
      GoRoute(
        path: AppRoutes.saved,
        builder: (_, __) => const ChecklistScreen(),
      ),
      GoRoute(
        path: AppRoutes.destination,
        builder:
            (_, state) => DestinationDetailScreen(
              destinationId: state.uri.queryParameters['id'] ?? '',
              tripId: state.uri.queryParameters['tripId'],
            ),
      ),
      GoRoute(
        path: AppRoutes.destinationChat,
        builder:
            (_, state) => DestinationChatScreen(
              destinationName: state.uri.queryParameters['destination'] ?? '',
              sourceId:
                  state.uri.queryParameters['sourceId'] ??
                  state.uri.queryParameters['placeId'] ??
                  '',
              displayAddress: state.uri.queryParameters['displayAddress'] ?? '',
              lat: double.tryParse(state.uri.queryParameters['lat'] ?? ''),
              lon: double.tryParse(state.uri.queryParameters['lon'] ?? ''),
              guideId: state.uri.queryParameters['guideId'],
              tripId: state.uri.queryParameters['tripId'],
            ),
      ),
      GoRoute(
        path: AppRoutes.tripPlanning,
        builder:
            (_, state) => TripPlanningScreen(
              destinationId: state.uri.queryParameters['destinationId'] ?? '',
            ),
      ),
      GoRoute(
        path: AppRoutes.itinerary,
        builder:
            (_, state) => ItineraryScreen(
              tripId: state.uri.queryParameters['tripId'] ?? '',
            ),
      ),
      GoRoute(
        path: AppRoutes.companion,
        builder:
            (_, state) => CompanionScreen(
              tripId: state.uri.queryParameters['tripId'] ?? '',
            ),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (_, __) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.personalInformation,
        builder: (_, __) => const PersonalInformationScreen(),
      ),
      GoRoute(
        path: AppRoutes.changePassword,
        builder: (_, __) => const ChangePasswordScreen(),
      ),
    ],
  );
}

CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
      child: child,
    ),
  );
}
