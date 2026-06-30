import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:raaste/config/routes.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  static const _imageWidth = 941.0;
  static const _imageHeight = 1672.0;
  static const _getStartedRect = Rect.fromLTRB(148, 1434, 793, 1528);
  static const _loginRect = Rect.fromLTRB(148, 1554, 793, 1648);

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFFF5EFE0),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5EFE0),
      // Extend behind system bars so the welcome art fills every pixel.
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Use the full display size including system bar areas so the
          // tap-target math stays in sync with the rendered image.
          final media = MediaQuery.of(context);
          final screenSize = Size(
            media.size.width,
            media.size.height,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/images/raaste_welcomescreen.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
              _ImageTapTarget(
                imageRect: _getStartedRect,
                screenSize: screenSize,
                label: 'Get Started',
                onTap: () => context.go(AppRoutes.profileSetup),
              ),
              _ImageTapTarget(
                imageRect: _loginRect,
                screenSize: screenSize,
                label: 'Log In',
                onTap: () => context.go(AppRoutes.signIn),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ImageTapTarget extends StatelessWidget {
  final Rect imageRect;
  final Size screenSize;
  final String label;
  final VoidCallback onTap;

  const _ImageTapTarget({
    required this.imageRect,
    required this.screenSize,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rect = _coverMappedRect(imageRect, screenSize);

    return Positioned.fromRect(
      rect: rect,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: Colors.white.withValues(alpha: 0.12),
            highlightColor: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(rect.height / 2),
          ),
        ),
      ),
    );
  }

  Rect _coverMappedRect(Rect sourceRect, Size screenSize) {
    const imageAspect =
        OnboardingScreen._imageWidth / OnboardingScreen._imageHeight;
    final screenAspect = screenSize.width / screenSize.height;

    final fittedWidth =
        screenAspect > imageAspect
            ? screenSize.width
            : screenSize.height * imageAspect;
    final fittedHeight =
        screenAspect > imageAspect
            ? screenSize.width / imageAspect
            : screenSize.height;
    final dx = (screenSize.width - fittedWidth) / 2;
    final dy = (screenSize.height - fittedHeight) / 2;

    return Rect.fromLTRB(
      dx + (sourceRect.left / OnboardingScreen._imageWidth) * fittedWidth,
      dy + (sourceRect.top / OnboardingScreen._imageHeight) * fittedHeight,
      dx + (sourceRect.right / OnboardingScreen._imageWidth) * fittedWidth,
      dy + (sourceRect.bottom / OnboardingScreen._imageHeight) * fittedHeight,
    );
  }
}
