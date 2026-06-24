import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:raaste/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:raaste/features/companion/presentation/screens/companion_screen.dart';
import 'package:raaste/features/destination/presentation/screens/destination_detail_screen.dart';
import 'package:raaste/features/explore/presentation/screens/explore_screen.dart';
import 'package:raaste/features/home/presentation/screens/home_screen.dart';
import 'package:raaste/features/home/presentation/screens/implementing_soon_screen.dart';
import 'package:raaste/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:raaste/features/onboarding/presentation/screens/profile_setup_screen.dart';
import 'package:raaste/features/profile/presentation/screens/profile_screen.dart';
import 'package:raaste/features/splash/presentation/screens/splash_screen.dart';
import 'package:raaste/features/trip/presentation/screens/itinerary_screen.dart';
import 'package:raaste/features/trip/presentation/screens/trip_planning_screen.dart';
import 'package:raaste/shared/widgets/raaste_nav_shell.dart';

class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String profileSetup = '/profile-setup';
  static const String signIn = '/sign-in';
  static const String home = '/home';
  static const String trips = '/trips';
  static const String explore = '/explore';
  static const String saved = '/saved';
  static const String destination = '/destination';
  static const String tripPlanning = '/trip-planning';
  static const String itinerary = '/itinerary';
  static const String companion = '/companion';
  static const String profile = '/profile';
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
            builder: (_, __) => const SplashScreen(),
          ),
          GoRoute(
            path: AppRoutes.onboarding,
            builder: (_, __) => const OnboardingScreen(),
          ),
          GoRoute(
            path: AppRoutes.profileSetup,
            builder: (_, __) => const ProfileSetupScreen(),
          ),
          GoRoute(
            path: AppRoutes.signIn,
            builder: (_, __) => const SignInScreen(),
          ),
          GoRoute(
            path: AppRoutes.home,
            builder: (_, __) => const HomeScreen(),
          ),
          GoRoute(
            path: AppRoutes.trips,
            builder: (_, __) => const ImplementingSoonScreen(
              title: 'Trips',
              icon: Icons.work_outline_rounded,
              tab: RaasteNavTab.trips,
            ),
          ),
          GoRoute(
            path: AppRoutes.explore,
            builder: (_, __) => const ExploreScreen(),
          ),
          GoRoute(
            path: AppRoutes.saved,
            builder: (_, __) => const ImplementingSoonScreen(
              title: 'Saved',
              icon: Icons.favorite_border_rounded,
              tab: RaasteNavTab.saved,
            ),
          ),
          GoRoute(
            path: AppRoutes.destination,
            builder: (_, state) => DestinationDetailScreen(
              destinationId: state.uri.queryParameters['id'] ?? '',
            ),
          ),
          GoRoute(
            path: AppRoutes.tripPlanning,
            builder: (_, state) => TripPlanningScreen(
              destinationId: state.uri.queryParameters['destinationId'] ?? '',
            ),
          ),
          GoRoute(
            path: AppRoutes.itinerary,
            builder: (_, state) => ItineraryScreen(
              tripId: state.uri.queryParameters['tripId'] ?? '',
            ),
          ),
          GoRoute(
            path: AppRoutes.companion,
            builder: (_, state) => CompanionScreen(
              tripId: state.uri.queryParameters['tripId'] ?? '',
            ),
          ),
          GoRoute(
            path: AppRoutes.profile,
            builder: (_, __) => const ProfileScreen(),
          ),
        ],
      );
}
