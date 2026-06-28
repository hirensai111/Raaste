import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:raaste/config/routes.dart';
import 'package:raaste/core/constants/app_constants.dart';
import 'package:raaste/core/di/injection.dart';
import 'package:raaste/features/destination/data/repositories/destination_guide_store.dart';
import 'package:raaste/features/destination/data/services/destination_research_service.dart';
import 'package:raaste/features/destination/data/services/google_route_matrix_service.dart';
import 'package:raaste/features/destination/data/services/open_ai_destination_service.dart';
import 'package:raaste/features/destination/domain/models/destination_guide.dart';
import 'package:raaste/features/destination/domain/models/trip_intake.dart';
import 'package:raaste/features/trip/data/repositories/saved_trip_repository.dart';
import 'package:raaste/shared/widgets/raaste_nav_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum _IntakeStep {
  dates,
  landingTime,
  departureTime,
  travelMode,
  stay,
  people,
  pace,
  interests,
  dietary,
  generating,
}

enum _EditFollowUpStep { none, landingTime, endDate, departureTime, stay }

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
  final _routeTiming = getIt<GoogleRouteMatrixService>();
  final _savedTrips = getIt<SavedTripRepository>();

  _IntakeStep _step = _IntakeStep.dates;
  _EditFollowUpStep _editFollowUpStep = _EditFollowUpStep.none;
  DestinationGuide? _editingGuide;
  String? _editingTripId;
  bool _isLoading = false;

  String? _dates;
  String? _landingTime;
  String? _departureTime;
  String? _travelMode;
  String? _stayNameOrAddress;
  int? _peopleCount;
  String? _pacePreference;
  final Set<String> _selectedInterests = {};
  String? _dietaryPreference;

  String? _pendingEditRequest;
  String? _pendingEditLandingTime;
  String? _pendingEditEndDateAnswer;
  String? _pendingEditDepartureTime;
  String? _pendingEditStayNameOrAddress;
  bool _pendingEditStartedWithStartDate = false;

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
    if (!widget.isEditMode && text.isEmpty && _step == _IntakeStep.interests) {
      _continueWithSelectedInterests();
      return;
    }
    if (text.isEmpty) return;
    _controller.clear();

    setState(() => _messages.add(_ChatMessage.user(text)));
    _scrollToEnd();

    if (widget.isEditMode) {
      await _handleEditText(text);
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
        _step = _IntakeStep.travelMode;
        _addAssistant(
          'How are you travelling there: car, bus, train, aeroplane, or some other way?',
        );
        return;
      case _IntakeStep.travelMode:
        _travelMode = text;
        _step = _IntakeStep.stay;
        _addAssistant(
          'Where are you staying? Hotel name, area, or address is fine.',
        );
        return;
      case _IntakeStep.stay:
        _stayNameOrAddress = text;
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
        _step = _IntakeStep.pace;
        _addAssistant(
          'Do you want this to be a leisure, balanced, or packed trip? You can also say things like: leisure on day 1, packed on day 2.',
        );
        return;
      case _IntakeStep.pace:
        _pacePreference = text;
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
      stayNameOrAddress: _stayNameOrAddress ?? '',
      peopleCount: _peopleCount ?? 1,
      travelMode: _travelMode ?? 'Not specified',
      pacePreference: _pacePreference ?? 'Balanced',
      interests: _selectedInterests.toList(),
      dietaryPreference: _dietaryPreference ?? 'No specific preference',
    );

    setState(() {
      _step = _IntakeStep.generating;
      _isLoading = true;
      _messages.add(
        _ChatMessage.assistant(
          'I\'m checking Raaste\'s curated destination research to build your itinerary now.',
        ),
      );
    });
    _scrollToEnd();

    try {
      final research = await _research.loadForIntake(intake);
      if (research == null) {
        throw const OpenAiGuideException(
          'Raaste can only plan trips for Hyderabad, Lonavala, and Varanasi right now.',
        );
      }

      if (mounted) {
        setState(
          () => _messages.add(
            _ChatMessage.assistant(
              'Using Raaste\'s curated ${research.destinationName} research for your itinerary.',
            ),
          ),
        );
        _scrollToEnd();
      }

      if (mounted) {
        setState(
          () => _messages.add(
            _ChatMessage.assistant(
              'Checking Google route times from your stay so the schedule is realistic.',
            ),
          ),
        );
        _scrollToEnd();
      }

      final timingContext = await _routeTiming.buildTimingContext(
        intake,
        research,
      );
      final guide = await _openAi.generateGuideFromResearch(
        intake,
        research,
        timingContext: timingContext,
      );
      final guideId = await _guideStore.saveGuide(guide);
      if (mounted) context.go('${AppRoutes.destination}?id=$guideId');
    } on RouteTimingException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _step = _IntakeStep.stay;
        _messages.add(_ChatMessage.assistant(e.message));
      });
    } on OpenAiGuideException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _step = _IntakeStep.dietary;
        _messages.add(_ChatMessage.assistant(e.message));
      });
    }
  }

  Future<void> _handleEditText(String text) async {
    switch (_editFollowUpStep) {
      case _EditFollowUpStep.none:
        if (_shouldAskStayEditFollowUp(text) ||
            (_editingGuide?.intake.stayNameOrAddress.trim().isEmpty == true &&
                _editNeedsRouteTiming(text))) {
          _pendingEditRequest = text;
          _editFollowUpStep = _EditFollowUpStep.stay;
          _addAssistant(
            'What hotel, area, or address should I use as your stay base for retiming?',
          );
          return;
        }
        if (_shouldAskDateEditFollowUps(text)) {
          _pendingEditRequest = text;
          _pendingEditStartedWithStartDate = !_isEndDateOnlyEdit(text);

          if (_pendingEditStartedWithStartDate) {
            _editFollowUpStep = _EditFollowUpStep.landingTime;
            _addAssistant(
              'Got it. What time will you land or arrive on the revised start date?',
            );
          } else {
            _pendingEditEndDateAnswer = text;
            _editFollowUpStep = _EditFollowUpStep.departureTime;
            _addAssistant(
              'Got it. What time do you plan to depart or leave on the revised end date?',
            );
          }
          return;
        }
        await _reviseGuide(text);
        return;
      case _EditFollowUpStep.landingTime:
        _pendingEditLandingTime = text;
        _editFollowUpStep = _EditFollowUpStep.endDate;
        final currentDates = _editingGuide?.intake.dates.trim();
        _addAssistant(
          currentDates?.isNotEmpty == true
              ? 'Your trip is currently saved as $currentDates. Is the current end date still correct, or do you want to change it too? Send "same" or the new end date.'
              : 'Is the current end date still correct, or do you want to change it too? Send "same" or the new end date.',
        );
        return;
      case _EditFollowUpStep.endDate:
        _pendingEditEndDateAnswer = text;
        if (_keepsCurrentEndDate(text)) {
          final request = _buildDateEditRequest();
          _clearPendingDateEdit();
          await _reviseGuide(request);
          return;
        }
        _editFollowUpStep = _EditFollowUpStep.departureTime;
        _addAssistant(
          'What time do you plan to depart or leave on the revised end date?',
        );
        return;
      case _EditFollowUpStep.departureTime:
        _pendingEditDepartureTime = text;
        final request = _buildDateEditRequest();
        _clearPendingDateEdit();
        await _reviseGuide(request);
        return;
      case _EditFollowUpStep.stay:
        _pendingEditStayNameOrAddress = text;
        final request = _buildStayEditRequest();
        _clearPendingStayEdit();
        await _reviseGuide(request);
        return;
    }
  }

  bool _shouldAskStayEditFollowUp(String text) {
    final lower = text.toLowerCase();
    return lower.contains('hotel') ||
        lower.contains('stay') ||
        lower.contains('staying') ||
        lower.contains('accommodation') ||
        lower.contains('base') ||
        lower.contains('check in') ||
        lower.contains('check-in');
  }

  bool _editNeedsRouteTiming(String text) {
    final lower = text.toLowerCase();
    return _shouldAskDateEditFollowUps(text) ||
        _shouldAskStayEditFollowUp(text) ||
        lower.contains('arrival') ||
        lower.contains('landing') ||
        lower.contains('departure') ||
        lower.contains('flight') ||
        lower.contains('aeroplane') ||
        lower.contains('airplane') ||
        lower.contains('train') ||
        lower.contains('bus') ||
        lower.contains('car') ||
        lower.contains('drive');
  }

  bool _shouldAskDateEditFollowUps(String text) {
    final lower = text.toLowerCase();
    final directDateChange =
        lower.contains('date') ||
        lower.contains('start') ||
        lower.contains('begin') ||
        lower.contains('arrival date') ||
        lower.contains('end date') ||
        lower.contains('last day') ||
        lower.contains('departure date') ||
        lower.contains('return date') ||
        lower.contains('extend') ||
        lower.contains('shorten') ||
        lower.contains('night');
    if (directDateChange) return true;

    final hasOrdinal = RegExp(r'\b\d{1,2}(?:st|nd|rd|th)\b').hasMatch(lower);
    final hasMonth = RegExp(
      r'\b(?:jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\b',
    ).hasMatch(lower);
    final hasChangeWord = RegExp(
      r'\b(?:change|move|shift|instead|from|to|make)\b',
    ).hasMatch(lower);
    return hasChangeWord && (hasOrdinal || hasMonth);
  }

  bool _isEndDateOnlyEdit(String text) {
    final lower = text.toLowerCase();
    final mentionsEndDate =
        lower.contains('end date') ||
        lower.contains('last day') ||
        lower.contains('departure date') ||
        lower.contains('return date') ||
        lower.contains('checkout date') ||
        lower.contains('check-out date');
    final mentionsStartDate =
        lower.contains('start date') ||
        lower.contains('start') ||
        lower.contains('begin') ||
        lower.contains('arrival date') ||
        lower.contains('landing date') ||
        lower.contains('first day');
    return mentionsEndDate && !mentionsStartDate;
  }

  String _buildDateEditRequest() {
    final original = _pendingEditRequest?.trim() ?? '';
    final landing = _pendingEditLandingTime?.trim() ?? '';
    final departure = _pendingEditDepartureTime?.trim() ?? '';
    final endDateAnswer = _pendingEditEndDateAnswer?.trim() ?? '';
    final currentDates = _editingGuide?.intake.dates.trim() ?? '';
    final keepsEnd =
        endDateAnswer.isNotEmpty && _keepsCurrentEndDate(endDateAnswer);

    final startInstruction =
        _pendingEditStartedWithStartDate
            ? 'Update the start date from the original request and set intake.landingTime to: $landing.'
            : 'Keep the existing start date and existing intake.landingTime unchanged.';
    final endInstruction =
        keepsEnd
            ? 'Keep the current end date from the existing itinerary ($currentDates).'
            : _pendingEditStartedWithStartDate
            ? 'Change the end date to: $endDateAnswer.'
            : 'Apply the end-date change from the original request.';
    final departureInstruction =
        departure.isEmpty
            ? 'Keep the existing intake.departureTime unless the revised end date requires a sensible adjustment.'
            : 'Set intake.departureTime to: $departure.';

    return '''
Original user edit request:
$original

Follow-up answers:
- Start date handling: $startInstruction
- End date handling: $endInstruction
- Departure time handling: $departureInstruction

Apply these changes to the trip intake. Update intake.dates to the full revised date range, preserving unchanged start/end dates where instructed. Regenerate itineraryDays for every day in the revised date range. Retime Day 1 only if the start date or landing time changed, and retime the final day around the revised departure time when provided.
''';
  }

  String _buildStayEditRequest() {
    final original = _pendingEditRequest?.trim() ?? '';
    final stay = _pendingEditStayNameOrAddress?.trim() ?? '';

    return '''
Original user edit request:
$original

Follow-up answers:
- Set intake.stayNameOrAddress to: $stay.

Apply these changes to the trip intake. Regenerate route-aware itinerary timings around the revised stay/base, arrival/departure transfers, and daily movement.
''';
  }

  void _clearPendingStayEdit() {
    _pendingEditRequest = null;
    _pendingEditStayNameOrAddress = null;
    _editFollowUpStep = _EditFollowUpStep.none;
  }

  void _clearPendingDateEdit() {
    _pendingEditRequest = null;
    _pendingEditLandingTime = null;
    _pendingEditEndDateAnswer = null;
    _pendingEditDepartureTime = null;
    _pendingEditStayNameOrAddress = null;
    _pendingEditStartedWithStartDate = false;
    _editFollowUpStep = _EditFollowUpStep.none;
  }

  bool _keepsCurrentEndDate(String answer) {
    final lower = answer.trim().toLowerCase();
    return lower == 'same' ||
        lower == 'yes' ||
        lower == 'correct' ||
        lower.contains('same') ||
        lower.contains('current') ||
        lower.contains('keep') ||
        lower.contains('no change');
  }

  TripIntake _intakeForRouteTimingEdit(TripIntake current, String editRequest) {
    final stay =
        _extractPromptValue(editRequest, 'stayNameOrAddress') ??
        _extractStayFromPlainText(editRequest) ??
        current.stayNameOrAddress;
    final landing =
        _extractPromptValue(editRequest, 'landingTime') ?? current.landingTime;
    final departure =
        _extractPromptValue(editRequest, 'departureTime') ??
        current.departureTime;
    final travelMode = _extractTravelMode(editRequest) ?? current.travelMode;

    return current.copyWith(
      stayNameOrAddress: stay,
      landingTime: landing,
      departureTime: departure,
      travelMode: travelMode,
    );
  }

  String? _extractPromptValue(String text, String fieldName) {
    final pattern = RegExp(
      'intake\\.$fieldName\\s+to:\\s*([^\\.\\n]+)',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(text);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? _extractStayFromPlainText(String text) {
    final patterns = [
      RegExp(
        r'(?:hotel|stay|staying|accommodation|base)\s+(?:to|at|in|is|as)\s+([^\.\n]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:change|move|switch)\s+(?:to|into)\s+([^\.\n]+)',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      final value = match?.group(1)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String? _extractTravelMode(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('flight') ||
        lower.contains('aeroplane') ||
        lower.contains('airplane') ||
        lower.contains('plane')) {
      return 'Aeroplane';
    }
    if (lower.contains('train') || lower.contains('rail')) return 'Train';
    if (lower.contains('bus') || lower.contains('coach')) return 'Bus';
    if (lower.contains('car') ||
        lower.contains('drive') ||
        lower.contains('cab')) {
      return 'Car';
    }
    return null;
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
      final timingIntake = _intakeForRouteTimingEdit(guide.intake, editRequest);
      final research = await _research.loadForIntake(timingIntake);
      if (research == null) {
        throw const OpenAiGuideException(
          'Raaste can only retime trips for Hyderabad, Lonavala, and Varanasi right now.',
        );
      }
      final timingContext = await _routeTiming.buildTimingContext(
        timingIntake,
        research,
      );
      final updated = await _openAi.reviseGuide(
        currentGuide: guide,
        editRequest: editRequest,
        timingContext: timingContext,
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
    } on RouteTimingException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _messages.add(_ChatMessage.assistant(e.message));
      });
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

  void _selectTravelMode(String value) {
    if (_isLoading) return;
    setState(() {
      _travelMode = value;
      _step = _IntakeStep.stay;
      _messages.add(_ChatMessage.user(value));
    });
    _addAssistant(
      'Where are you staying? Hotel name, area, or address is fine.',
    );
  }

  void _selectPace(String value) {
    if (_isLoading) return;
    setState(() {
      _pacePreference = value;
      _step = _IntakeStep.interests;
      _messages.add(_ChatMessage.user(value));
    });
    _addAssistant(
      'Pick a few interests or type your own. What should this trip focus on?',
    );
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

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    if (widget.isEditMode) {
      final tripId = _editingTripId ?? widget.tripId?.trim();
      if (tripId != null && tripId.isNotEmpty) {
        context.go('${AppRoutes.destination}?tripId=$tripId');
        return;
      }

      final guideId = widget.guideId?.trim();
      if (guideId != null && guideId.isNotEmpty) {
        context.go('${AppRoutes.destination}?id=$guideId');
        return;
      }

      context.go(AppRoutes.trips);
      return;
    }

    context.go(AppRoutes.home);
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
              onBack: _handleBack,
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
            if (_step == _IntakeStep.travelMode && !widget.isEditMode)
              _ChoiceChips(
                values: const ['Car', 'Bus', 'Train', 'Aeroplane', 'Other'],
                selected: {if (_travelMode != null) _travelMode!},
                onTap: _selectTravelMode,
              ),
            if (_step == _IntakeStep.pace && !widget.isEditMode)
              _ChoiceChips(
                values: const ['Leisure', 'Balanced', 'Packed'],
                selected: {if (_pacePreference != null) _pacePreference!},
                onTap: _selectPace,
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
    if (widget.isEditMode) {
      switch (_editFollowUpStep) {
        case _EditFollowUpStep.landingTime:
          return 'Example: 10:30 AM';
        case _EditFollowUpStep.endDate:
          return 'Example: Same, or 30 August';
        case _EditFollowUpStep.departureTime:
          return 'Example: 6:00 PM';
        case _EditFollowUpStep.stay:
          return 'Example: Taj Deccan, Banjara Hills';
        case _EditFollowUpStep.none:
          return 'Ask for a change...';
      }
    }

    switch (_step) {
      case _IntakeStep.dates:
        return 'Example: 12-16 August';
      case _IntakeStep.landingTime:
        return 'Example: 10:30 AM';
      case _IntakeStep.departureTime:
        return 'Example: 6:00 PM';
      case _IntakeStep.travelMode:
        return 'Example: Train, car, bus, or flight';
      case _IntakeStep.stay:
        return 'Example: Taj Deccan, Banjara Hills';
      case _IntakeStep.people:
        return 'Example: 2';
      case _IntakeStep.pace:
        return 'Example: Leisure, Packed, or Packed on day 2';
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
  final VoidCallback onBack;

  const _ChatHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 18, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
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
