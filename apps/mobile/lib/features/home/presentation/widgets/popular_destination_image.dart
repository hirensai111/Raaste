import 'package:flutter/material.dart';
import 'package:raaste/core/di/injection.dart';
import 'package:raaste/features/home/domain/models/popular_attraction.dart';
import 'package:raaste/features/trip/data/services/place_image_service.dart';

class PopularDestinationImage extends StatefulWidget {
  final PopularAttraction attraction;
  final double height;
  final BorderRadius borderRadius;
  final List<Widget> foreground;

  const PopularDestinationImage({
    super.key,
    required this.attraction,
    required this.height,
    required this.borderRadius,
    this.foreground = const [],
  });

  @override
  State<PopularDestinationImage> createState() =>
      _PopularDestinationImageState();
}

class _PopularDestinationImageState extends State<PopularDestinationImage> {
  late Future<String> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = _loadImage();
  }

  @override
  void didUpdateWidget(covariant PopularDestinationImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attraction.planningDestination !=
        widget.attraction.planningDestination) {
      _imageFuture = _loadImage();
    }
  }

  Future<String> _loadImage() {
    return getIt<PlaceImageService>().imageForDestination(
      widget.attraction.planningDestination,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: FutureBuilder<String>(
          future: _imageFuture,
          builder: (context, snapshot) {
            final resolved = snapshot.data?.trim();
            final imagePath =
                _isRemoteImage(resolved) ? resolved! : widget.attraction.image;

            return Stack(
              fit: StackFit.expand,
              children: [
                _DestinationImageLayer(
                  imagePath: imagePath,
                  localFallback: widget.attraction.image,
                ),
                ...widget.foreground,
              ],
            );
          },
        ),
      ),
    );
  }

  bool _isRemoteImage(String? value) {
    return value != null &&
        (value.startsWith('https://') || value.startsWith('http://'));
  }
}

class _DestinationImageLayer extends StatelessWidget {
  final String imagePath;
  final String localFallback;

  const _DestinationImageLayer({
    required this.imagePath,
    required this.localFallback,
  });

  @override
  Widget build(BuildContext context) {
    final isRemote =
        imagePath.startsWith('https://') || imagePath.startsWith('http://');

    if (isRemote) {
      return Image.network(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _LocalFallbackImage(path: localFallback),
      );
    }

    return _LocalFallbackImage(path: imagePath);
  }
}

class _LocalFallbackImage extends StatelessWidget {
  final String path;

  const _LocalFallbackImage({required this.path});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      path,
      fit: BoxFit.cover,
      errorBuilder:
          (_, __, ___) =>
              Image.asset(PlaceImageService.fallbackAsset, fit: BoxFit.cover),
    );
  }
}
