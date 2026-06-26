import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:raaste/config/routes.dart';
import 'package:raaste/core/constants/app_constants.dart';
import 'package:raaste/core/di/injection.dart';
import 'package:raaste/features/destination/data/repositories/destination_guide_store.dart';
import 'package:raaste/features/destination/data/services/destination_research_service.dart';
import 'package:raaste/features/destination/data/services/open_ai_destination_service.dart';
import 'package:raaste/features/destination/data/services/overpass_service.dart';
import 'package:raaste/features/destination/domain/models/destination_guide.dart';
import 'package:raaste/features/destination/domain/models/osm_place.dart';
import 'package:raaste/features/destination/domain/models/trip_intake.dart';
import 'package:raaste/features/trip/data/repositories/saved_trip_repository.dart';
import 'package:raaste/shared/widgets/raaste_nav_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum _IntakeStep {
  dates,
  landingTime,
  departureTime,
  people,
  interests,
  dietary,
  generating,
}

class DestinationChatScreen extends StatefulWidget {
  final String destinationName;
  final String sourceId;
  final String displayAddress;
  final double? lat;
  final double? lon;
  final String? guideId;
  final String? tripId;

  const DestinationChatScreen({
    super.key,
    required this.destinationName,
    required this.sourceId,
    required this.displayAddress,
    required this.lat,
    required this.lon,
    this.guideId,
    this.tripId,
  });

  bool get isEditMode =>
      (guideId != null && guideId!.trim().isNotEmpty) ||
      (tripId != null && tripId!.trim().isNotEmpty);

  @override
  State<DestinationChatScreen> createState() => _DestinationChatScreenState();
}

class _DestinationChatScreenState extends State<DestinationChatScreen> {
  final _messages = <_ChatMessage>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _guideStore = getIt<DestinationGuideStore>();
  final _openAi = getIt<OpenAiDestinationService>();
  final _research = getIt<DestinationResearchService>();
  final _overpass = getIt<OverpassService>();
  final _savedTrips = getIt<SavedTripRepository>();

  _IntakeStep _step = _IntakeStep.dates;
  DestinationGuide? _editingGuide;
  String? _editingTripId;
  bool _isLoading = false;
  String? _dates;
  String? _landingTime;
  String? _departureTime;
  int? _peopleCount;
  final Set<String> _selectedInterests = {};
  String? _dietaryPreference;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialState() async {
    if (widget.isEditMode) {
      DestinationGuide? guide;
      final tripId = widget.tripId?.trim();
      if (tripId != null && tripId.isNotEmpty) {
        final trip = await _savedTrips.getTrip(tripId);
        guide = trip?.guide;
        _editingTripId = trip?.id;
        if (guide != null) await _guideStore.saveGuide(guide);
      }

      if (guide == null && widget.guideId?.trim().isNotEmpty == true) {
        guide = await _guideStore.getGuide(widget.guideId!.trim());
      }

      if (!mounted) return;
      setState(() {
        _editingGuide = guide;
        _messages.add(
          _ChatMessage.assistant(
            guide == null
                ? 'I could not find that saved guide. Go back and try again.'
                : 'Tell me what you want to change in your ${guide.destinationName} guide.',
          ),
        );
      });
      return;
    }

    _dietaryPreference = _metadataValue([
      'dietary_preference',
      'dietaryPreference',
      'diet',
    ]);

    setState(() {
      _messages.add(
        _ChatMessage.assistant(
          'Great, let\'s plan ${widget.destinationName}. What are your travel dates?',
        ),
      );
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (_isLoading) return;
    if (text.isEmpty && _step == _IntakeStep.interests) {
      _continueWithSelectedInterests();
      return;
    }
    if (text.isEmpty) return;
    _controller.clear();

    setState(() => _messages.add(_ChatMessage.user(text)));
    _scrollToEnd();

    if (widget.isEditMode) {
      await _reviseGuide(text);
      return;
    }

    _handleIntakeText(text);
  }

  void _handleIntakeText(String text) {
    switch (_step) {
      case _IntakeStep.dates:
        _dates = text;
        _step = _IntakeStep.landingTime;
        _addAssistant('What time do you land or arrive there?');
        return;
      case _IntakeStep.landingTime:
        _landingTime = text;
        _step = _IntakeStep.departureTime;
        _addAssistant(
          'What time do you plan to depart or leave on the last day?',
        );
        return;
      case _IntakeStep.departureTime:
        _departureTime = text;
        _step = _IntakeStep.people;
        _addAssistant('How many people are travelling?');
        return;
      case _IntakeStep.people:
        final count = int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), ''));
        if (count == null || count < 1) {
          _addAssistant('Please send the number of travellers, like 2 or 4.');
          return;
        }
        _peopleCount = count;
        _step = _IntakeStep.interests;
        _addAssistant(
          'Pick a few interests or type your own. What should this trip focus on?',
        );
        return;
      case _IntakeStep.interests:
        final typed = text
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty);
        _selectedInterests.addAll(typed);
        _advanceAfterInterests();
        return;
      case _IntakeStep.dietary:
        _dietaryPreference = text;
        _generateGuide();
        return;
      case _IntakeStep.generating:
        return;
    }
  }

  void _continueWithSelectedInterests() {
    if (_selectedInterests.isEmpty) {
      _addAssistant('Tap at least one interest, then press send to continue.');
      return;
    }

    setState(() {
      _messages.add(_ChatMessage.user(_selectedInterests.join(', ')));
    });
    _advanceAfterInterests();
  }

  void _advanceAfterInterests() {
    if (_selectedInterests.isEmpty) {
      _addAssistant('Choose at least one interest so I can filter the guide.');
      return;
    }

    if (_dietaryPreference?.trim().isNotEmpty == true) {
      _generateGuide();
      return;
    }

    _step = _IntakeStep.dietary;
    _addAssistant('Any dietary preference I should respect?');
  }

  Future<void> _generateGuide() async {
    final intake = TripIntake(
      destination: widget.destinationName,
      sourceId: widget.sourceId,
      displayAddress: widget.displayAddress,
      lat: widget.lat,
      lon: widget.lon,
      dates: _dates ?? '',
      landingTime: _landingTime ?? '',
      departureTime: _departureTime ?? '',
      peopleCount: _peopleCount ?? 1,
      interests: _selectedInterests.toList(),
      dietaryPreference: _dietaryPreference ?? 'No specific preference',
    );

    setState(() {
      _step = _IntakeStep.generating;
      _isLoading = true;
      _messages.add(
        _ChatMessage.assistant(
          'I\'m checking curated research and map places to build your itinerary now.',
        ),
      );
    });
    _scrollToEnd();

    try {
      final research = await _research.loadForIntake(intake);
      DestinationGuide guide;

      if (research != null) {
        if (mounted) {
          setState(
            () => _messages.add(
              _ChatMessage.assistant(
                'Using Raaste\'s curated Hyderabad research for a richer itinerary.',
              ),
            ),
          );
          _scrollToEnd();
        }

        try {
          guide = await _openAi.generateGuideFromResearch(intake, research);
        } on OpenAiGuideException {
          if (mounted) {
            setState(
              () => _messages.add(
                _ChatMessage.assistant(
                  'Curated research generation did not complete, so I\'m falling back to OpenStreetMap places.',
                ),
              ),
            );
            _scrollToEnd();
          }
          final places = await _fetchOverpassPlaces(intake);
          guide = await _openAi.generateGuide(intake, places);
        }
      } else {
        final places = await _fetchOverpassPlaces(intake);
        guide = await _openAi.generateGuide(intake, places);
      }

      final guideId = await _guideStore.saveGuide(guide);
      if (mounted) context.go('${AppRoutes.destination}?id=$guideId');
    } on OpenAiGuideException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _step = _IntakeStep.dietary;
        _messages.add(_ChatMessage.assistant(e.message));
      });
    }
  }

  Future<OsmPlaceBundle> _fetchOverpassPlaces(TripIntake intake) async {
    final lat = intake.lat;
    final lon = intake.lon;
    if (lat == null || lon == null) {
      return const OsmPlaceBundle(attractions: [], food: [], radiusMeters: 0);
    }

    try {
      return await _overpass.fetchNearbyPlaces(lat: lat, lon: lon);
    } on OverpassException catch (e) {
      if (mounted) {
        setState(() => _messages.add(_ChatMessage.assistant(e.message)));
      }
      return const OsmPlaceBundle(attractions: [], food: [], radiusMeters: 0);
    }
  }

  Future<void> _reviseGuide(String editRequest) async {
    final guide = _editingGuide;
    if (guide == null) return;

    setState(() {
      _isLoading = true;
      _messages.add(_ChatMessage.assistant('Updating your guide...'));
    });
    _scrollToEnd();

    try {
      final updated = await _openAi.reviseGuide(
        currentGuide: guide,
        editRequest: editRequest,
      );
      final guideId = await _guideStore.saveGuide(updated);
      final saved = updated.copyWith(id: guideId);
      final tripId = _editingTripId ?? widget.tripId?.trim();
      if (tripId != null && tripId.isNotEmpty) {
        await _savedTrips.updateTripGuide(tripId: tripId, guide: saved);
        if (mounted) context.go('${AppRoutes.destination}?tripId=$tripId');
        return;
      }
      if (mounted) context.go('${AppRoutes.destination}?id=$guideId');
    } on OpenAiGuideException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _messages.add(_ChatMessage.assistant(e.message));
      });
    } on SavedTripException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _messages.add(_ChatMessage.assistant(e.message));
      });
    }
  }

  void _toggleInterest(String interest) {
    if (_isLoading) return;
    setState(() {
      if (_selectedInterests.contains(interest)) {
        _selectedInterests.remove(interest);
      } else {
        _selectedInterests.add(interest);
      }
    });
  }

  void _selectDietary(String value) {
    if (_isLoading) return;
    setState(() {
      _dietaryPreference = value;
      _messages.add(_ChatMessage.user(value));
    });
    _generateGuide();
  }

  void _addAssistant(String text) {
    setState(() => _messages.add(_ChatMessage.assistant(text)));
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String? _metadataValue(List<String> keys) {
    final metadata = Supabase.instance.client.auth.currentUser?.userMetadata;
    if (metadata == null) return null;
    for (final key in keys) {
      final value = metadata[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: RaasteShellColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _ChatHeader(
              title: widget.isEditMode ? 'Edit Guide' : widget.destinationName,
              subtitle:
                  widget.isEditMode
                      ? 'Ask Raaste to refine the plan'
                      : 'Raaste AI trip intake',
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                itemCount: _messages.length,
                itemBuilder:
                    (context, index) =>
                        _MessageBubble(message: _messages[index]),
              ),
            ),
            if (_step == _IntakeStep.interests && !widget.isEditMode)
              _ChoiceChips(
                values: AppConstants.interests,
                selected: _selectedInterests,
                onTap: _toggleInterest,
              ),
            if (_step == _IntakeStep.dietary && !widget.isEditMode)
              _ChoiceChips(
                values: AppConstants.dietaryPreferences,
                selected: {if (_dietaryPreference != null) _dietaryPreference!},
                onTap: _selectDietary,
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(18, 10, 18, bottomPadding + 14),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled:
                          !_isLoading &&
                          (!widget.isEditMode || _editingGuide != null),
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: _hintText,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(
                            color: RaasteShellColors.outline,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(
                            color: RaasteShellColors.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: RaasteShellColors.clay,
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: _isLoading ? null : _sendMessage,
                      icon:
                          _isLoading
                              ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                              ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _hintText {
    if (widget.isEditMode) return 'Ask for a change...';
    switch (_step) {
      case _IntakeStep.dates:
        return 'Example: 12-16 August';
      case _IntakeStep.landingTime:
        return 'Example: 10:30 AM';
      case _IntakeStep.departureTime:
        return 'Example: 6:00 PM';
      case _IntakeStep.people:
        return 'Example: 2';
      case _IntakeStep.interests:
        return 'Tap chips, then press send';
      case _IntakeStep.dietary:
        return 'Example: Vegetarian, Jain, Halal';
      case _IntakeStep.generating:
        return 'Generating guide...';
    }
  }
}

class _ChatHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _ChatHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 18, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: RaasteShellColors.ink,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? 'Plan a destination' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: RaasteShellColors.ink,
                    fontFamily: 'serif',
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: RaasteShellColors.muted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceChips extends StatelessWidget {
  final List<String> values;
  final Set<String> selected;
  final ValueChanged<String> onTap;

  const _ChoiceChips({
    required this.values,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              values.map((value) {
                final active = selected.contains(value);
                return ChoiceChip(
                  selected: active,
                  label: Text(value),
                  selectedColor: const Color(0xFFE8D9C8),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color:
                        active
                            ? RaasteShellColors.ink
                            : RaasteShellColors.muted,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                  side: const BorderSide(color: RaasteShellColors.outline),
                  onSelected: (_) => onTap(value),
                );
              }).toList(),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser ? RaasteShellColors.ink : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: isUser ? null : Border.all(color: RaasteShellColors.outline),
          boxShadow: const [
            BoxShadow(
              color: RaasteShellColors.shadow,
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser ? Colors.white : RaasteShellColors.ink,
            fontSize: 14,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;

  const _ChatMessage({required this.text, required this.isUser});

  factory _ChatMessage.user(String text) =>
      _ChatMessage(text: text, isUser: true);

  factory _ChatMessage.assistant(String text) =>
      _ChatMessage(text: text, isUser: false);
}
