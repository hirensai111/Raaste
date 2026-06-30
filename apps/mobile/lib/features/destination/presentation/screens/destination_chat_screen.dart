import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:raaste/config/routes.dart';
import 'package:raaste/core/constants/app_constants.dart';
import 'package:raaste/core/di/injection.dart';
import 'package:raaste/features/destination/data/repositories/destination_guide_store.dart';
import 'package:raaste/features/destination/data/services/destination_research_service.dart';
import 'package:raaste/features/destination/data/services/google_route_matrix_service.dart';
import 'package:raaste/features/destination/data/services/open_ai_destination_service.dart';
import 'package:raaste/features/destination/data/services/stay_search_service.dart';
import 'package:raaste/features/destination/domain/models/destination_guide.dart';
import 'package:raaste/features/destination/domain/models/place_suggestion.dart';
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
  final _staySearch = getIt<StaySearchService>();
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
  double? _stayLat;
  double? _stayLon;
  int? _peopleCount;
  String? _pacePreference;
  final Set<String> _selectedInterests = {};
  String? _dietaryPreference;

  String? _pendingEditRequest;
  String? _pendingEditLandingTime;
  String? _pendingEditEndDateAnswer;
  String? _pendingEditDepartureTime;
  String? _pendingEditStayNameOrAddress;
  double? _pendingEditStayLat;
  double? _pendingEditStayLon;
  bool _pendingEditStartedWithStartDate = false;

  Timer? _staySearchDebounce;
  List<PlaceSuggestion> _staySuggestions = const [];
  bool _isSearchingStay = false;
  String? _staySearchError;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleComposerChanged);
    _loadInitialState();
  }

  @override
  void dispose() {
    _staySearchDebounce?.cancel();
    _controller.removeListener(_handleComposerChanged);
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
    if (_isDatePromptActive) {
      _addAssistant(
        'Use the date selector below so I can keep the trip dates valid.',
      );
      return;
    }
    if (_isStaySelectionActive) {
      await _handleStaySearchSubmit(text);
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
        _addAssistant(
          'Use the date selector below so I can keep the trip dates valid.',
        );
        return;
      case _IntakeStep.landingTime:
        final time = _normalizeTimeInput(text);
        if (time == null) {
          _addAssistant(_timeValidationMessage);
          return;
        }
        _landingTime = time;
        _step = _IntakeStep.departureTime;
        _addAssistant(
          'What time do you plan to depart or leave on the last day?',
        );
        return;
      case _IntakeStep.departureTime:
        final time = _normalizeTimeInput(text);
        if (time == null) {
          _addAssistant(_timeValidationMessage);
          return;
        }
        _departureTime = time;
        _step = _IntakeStep.travelMode;
        _addAssistant(
          'How are you travelling there: car, bus, train, aeroplane, or some other way?',
        );
        return;
      case _IntakeStep.travelMode:
        _travelMode = text;
        _step = _IntakeStep.stay;
        _clearStaySearch();
        _addAssistant(
          'Search for your hotel, stay, or area and choose one of the map results.',
        );
        return;
      case _IntakeStep.stay:
        _addAssistant(
          'Search for your hotel, stay, or area and choose one of the map results.',
        );
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
      stayLat: _stayLat,
      stayLon: _stayLon,
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
          _clearStaySearch();
          _addAssistant(
            'Search for the hotel, stay, or area I should use as your new base, then choose a map result.',
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
            _editFollowUpStep = _EditFollowUpStep.endDate;
            _addAssistant(
              'Choose the revised end date from the date selector below.',
            );
          }
          return;
        }
        await _reviseGuide(text);
        return;
      case _EditFollowUpStep.landingTime:
        final time = _normalizeTimeInput(text);
        if (time == null) {
          _addAssistant(_timeValidationMessage);
          return;
        }
        _pendingEditLandingTime = time;
        _editFollowUpStep = _EditFollowUpStep.endDate;
        final currentDates = _editingGuide?.intake.dates.trim();
        _addAssistant(
          currentDates?.isNotEmpty == true
              ? 'Your trip is currently saved as $currentDates. Keep that end date or choose a new one below.'
              : 'Keep the current end date or choose a new one below.',
        );
        return;
      case _EditFollowUpStep.endDate:
        _addAssistant(
          'Use the date selector below so I can keep the trip dates valid.',
        );
        return;
      case _EditFollowUpStep.departureTime:
        final time = _normalizeTimeInput(text);
        if (time == null) {
          _addAssistant(_timeValidationMessage);
          return;
        }
        _pendingEditDepartureTime = time;
        final request = _buildDateEditRequest();
        _clearPendingDateEdit();
        await _reviseGuide(request);
        return;
      case _EditFollowUpStep.stay:
        _addAssistant(
          'Search for the updated hotel, stay, or area and choose one of the map results.',
        );
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
            : endDateAnswer.isNotEmpty
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

    final lat = _pendingEditStayLat;
    final lon = _pendingEditStayLon;
    final coordinateInstructions =
        lat != null && lon != null
            ? '- Set intake.stayLat to: $lat.\n- Set intake.stayLon to: $lon.'
            : '- Keep existing stay coordinates only if they still match the selected stay.';

    return '''
Original user edit request:
$original

Follow-up answers:
- Set intake.stayNameOrAddress to: $stay.
$coordinateInstructions

Apply these changes to the trip intake. Regenerate route-aware itinerary timings around the revised stay/base, arrival/departure transfers, and daily movement.
''';
  }

  void _clearPendingStayEdit() {
    _pendingEditRequest = null;
    _pendingEditStayNameOrAddress = null;
    _pendingEditStayLat = null;
    _pendingEditStayLon = null;
    _editFollowUpStep = _EditFollowUpStep.none;
  }

  void _clearPendingDateEdit() {
    _pendingEditRequest = null;
    _pendingEditLandingTime = null;
    _pendingEditEndDateAnswer = null;
    _pendingEditDepartureTime = null;
    _pendingEditStayNameOrAddress = null;
    _pendingEditStayLat = null;
    _pendingEditStayLon = null;
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
    final stayLat =
        _extractPromptDouble(editRequest, 'stayLat') ?? current.stayLat;
    final stayLon =
        _extractPromptDouble(editRequest, 'stayLon') ?? current.stayLon;
    final landing =
        _extractPromptValue(editRequest, 'landingTime') ?? current.landingTime;
    final departure =
        _extractPromptValue(editRequest, 'departureTime') ??
        current.departureTime;
    final travelMode = _extractTravelMode(editRequest) ?? current.travelMode;

    return current.copyWith(
      stayNameOrAddress: stay,
      stayLat: stayLat,
      stayLon: stayLon,
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

  double? _extractPromptDouble(String text, String fieldName) {
    final value = _extractPromptValue(text, fieldName);
    return value == null ? null : double.tryParse(value);
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
        research: research,
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
    _clearStaySearch();
    _addAssistant(
      'Search for your hotel, stay, or area and choose one of the map results.',
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

  bool get _isTripDatePromptActive {
    return !_isLoading && !widget.isEditMode && _step == _IntakeStep.dates;
  }

  bool get _isEndDatePromptActive {
    return !_isLoading &&
        widget.isEditMode &&
        _editFollowUpStep == _EditFollowUpStep.endDate;
  }

  bool get _isDatePromptActive =>
      _isTripDatePromptActive || _isEndDatePromptActive;

  bool get _hidesComposer => _isTimePromptActive || _isDatePromptActive;
  bool get _isStaySelectionActive {
    if (_isLoading) return false;
    if (widget.isEditMode) return _editFollowUpStep == _EditFollowUpStep.stay;
    return _step == _IntakeStep.stay;
  }

  bool get _isTimePromptActive {
    if (_isLoading) return false;
    if (widget.isEditMode) {
      return _editFollowUpStep == _EditFollowUpStep.landingTime ||
          _editFollowUpStep == _EditFollowUpStep.departureTime;
    }
    return _step == _IntakeStep.landingTime ||
        _step == _IntakeStep.departureTime;
  }

  void _submitSelectedDateRange(DateTimeRange range) {
    final label = _formatDateRange(range);
    setState(() {
      _dates = label;
      _step = _IntakeStep.landingTime;
      _messages.add(_ChatMessage.user(label));
    });
    _scrollToEnd();
    _addAssistant('What time do you land or arrive there?');
  }

  Future<void> _keepCurrentEndDate() async {
    if (!_isEndDatePromptActive || _isLoading) return;
    final label = 'Keep current end date';
    setState(() => _messages.add(_ChatMessage.user(label)));
    _scrollToEnd();

    _pendingEditEndDateAnswer = label;
    final request = _buildDateEditRequest();
    _clearPendingDateEdit();
    await _reviseGuide(request);
  }

  void _submitSelectedEndDate(DateTime date) {
    if (!_isEndDatePromptActive || _isLoading) return;
    final label = _formatDate(date);
    setState(() {
      _pendingEditEndDateAnswer = label;
      _editFollowUpStep = _EditFollowUpStep.departureTime;
      _messages.add(_ChatMessage.user(label));
    });
    _scrollToEnd();
    _addAssistant(
      'What time do you plan to depart or leave on the revised end date?',
    );
  }

  String _formatDateRange(DateTimeRange range) {
    final start = range.start;
    final end = range.end;
    if (_isSameDate(start, end)) return _formatDate(start);
    if (start.year == end.year && start.month == end.month) {
      return '${start.day}-${end.day} ${_monthName(start.month)} ${start.year}';
    }
    if (start.year == end.year) {
      return '${start.day} ${_monthName(start.month)} - ${end.day} ${_monthName(end.month)} ${start.year}';
    }
    return '${_formatDate(start)} - ${_formatDate(end)}';
  }

  String _formatDate(DateTime date) {
    return '${date.day} ${_monthName(date.month)} ${date.year}';
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  bool get _isDepartureTimePrompt {
    return widget.isEditMode
        ? _editFollowUpStep == _EditFollowUpStep.departureTime
        : _step == _IntakeStep.departureTime;
  }

  String get _timePickerLabel {
    return _isDepartureTimePrompt ? 'Departure time' : 'Arrival time';
  }

  String get _activeDestinationName {
    if (widget.destinationName.trim().isNotEmpty) return widget.destinationName;
    return _editingGuide?.destinationName ??
        _editingGuide?.intake.destination ??
        '';
  }

  double? get _activeDestinationLat => widget.lat ?? _editingGuide?.intake.lat;
  double? get _activeDestinationLon => widget.lon ?? _editingGuide?.intake.lon;

  String get _timeValidationMessage =>
      'Please choose a valid time like 10:30 AM, 6 PM, or 18:30. Times such as 25 PM are not valid.';

  void _handleComposerChanged() {
    if (!_isStaySelectionActive) return;
    _scheduleStaySearch(_controller.text);
  }

  void _scheduleStaySearch(String query) {
    _staySearchDebounce?.cancel();
    final clean = query.trim();
    if (clean.length < 2) {
      if (_staySuggestions.isNotEmpty ||
          _staySearchError != null ||
          _isSearchingStay) {
        setState(() {
          _staySuggestions = const [];
          _staySearchError = null;
          _isSearchingStay = false;
        });
      }
      return;
    }

    _staySearchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _runStaySearch(clean),
    );
  }

  Future<void> _runStaySearch(String query) async {
    if (!_isStaySelectionActive || query.trim().length < 2) return;
    final destination = _activeDestinationName;
    if (destination.trim().isEmpty) return;

    setState(() {
      _isSearchingStay = true;
      _staySearchError = null;
    });

    try {
      final results = await _staySearch.search(
        query: query,
        destinationName: destination,
        destinationLat: _activeDestinationLat,
        destinationLon: _activeDestinationLon,
      );
      if (!mounted || !_isStaySelectionActive) return;
      if (_controller.text.trim() != query.trim()) return;
      setState(() {
        _staySuggestions = results;
        _isSearchingStay = false;
        _staySearchError =
            results.isEmpty
                ? 'No map results yet. Try a more specific hotel or area.'
                : null;
      });
    } on StaySearchException catch (e) {
      if (!mounted) return;
      setState(() {
        _staySuggestions = const [];
        _isSearchingStay = false;
        _staySearchError = e.message;
      });
    }
  }

  Future<void> _handleStaySearchSubmit(String text) async {
    final query = text.trim();
    if (query.isEmpty) {
      _addAssistant(
        'Start typing your hotel, stay, or area, then choose one of the map results.',
      );
      return;
    }

    final match = _matchingStaySuggestion(query);
    if (match != null) {
      await _selectStaySuggestion(match);
      return;
    }

    await _runStaySearch(query);
    _addAssistant(
      'Choose the matching hotel or area from the map results below. If it is not listed, type a more specific name.',
    );
  }

  PlaceSuggestion? _matchingStaySuggestion(String query) {
    final normalized = query.trim().toLowerCase();
    for (final suggestion in _staySuggestions) {
      if (suggestion.name.trim().toLowerCase() == normalized ||
          suggestion.displayAddress.trim().toLowerCase() == normalized) {
        return suggestion;
      }
    }
    return null;
  }

  Future<void> _selectStaySuggestion(PlaceSuggestion suggestion) async {
    final label = _stayLabel(suggestion);
    _staySearchDebounce?.cancel();
    _controller.clear();

    setState(() {
      _staySuggestions = const [];
      _staySearchError = null;
      _isSearchingStay = false;
      _messages.add(_ChatMessage.user(label));
    });
    _scrollToEnd();

    if (widget.isEditMode) {
      _pendingEditStayNameOrAddress = label;
      _pendingEditStayLat = suggestion.lat;
      _pendingEditStayLon = suggestion.lon;
      final request = _buildStayEditRequest();
      _clearPendingStayEdit();
      await _reviseGuide(request);
      return;
    }

    setState(() {
      _stayNameOrAddress = label;
      _stayLat = suggestion.lat;
      _stayLon = suggestion.lon;
      _step = _IntakeStep.people;
      _messages.add(_ChatMessage.assistant('How many people are travelling?'));
    });
    _scrollToEnd();
  }

  String _stayLabel(PlaceSuggestion suggestion) {
    final address = suggestion.displayAddress.trim();
    if (address.isEmpty || address == suggestion.name) return suggestion.name;
    return '${suggestion.name} - $address';
  }

  void _clearStaySearch() {
    _staySearchDebounce?.cancel();
    _staySuggestions = const [];
    _staySearchError = null;
    _isSearchingStay = false;
  }

  Future<void> _submitSelectedTime(String normalized) async {
    if (_isLoading) return;
    setState(() => _messages.add(_ChatMessage.user(normalized)));
    _scrollToEnd();

    if (widget.isEditMode) {
      await _handleEditText(normalized);
      return;
    }
    _handleIntakeText(normalized);
  }

  String? _normalizeTimeInput(String input) {
    final text = input
        .trim()
        .toUpperCase()
        .replaceAll('.', '')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (text == 'NOON') return '12:00 PM';
    if (text == 'MIDNIGHT') return '12:00 AM';

    final twelveHour = RegExp(
      r'^(\d{1,2})(?::(\d{1,2}))?\s*([AP]M)$',
    ).firstMatch(text);
    if (twelveHour != null) {
      final rawHour = int.tryParse(twelveHour.group(1)!);
      final rawMinute = int.tryParse(twelveHour.group(2) ?? '0');
      final marker = twelveHour.group(3)!;
      if (rawHour == null || rawMinute == null) return null;
      if (rawHour < 1 || rawHour > 12 || rawMinute < 0 || rawMinute > 59) {
        return null;
      }
      var hour = rawHour % 12;
      if (marker == 'PM') hour += 12;
      return _formatClockTime(hour, rawMinute);
    }

    final twentyFourHour = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
    if (twentyFourHour != null) {
      final hour = int.tryParse(twentyFourHour.group(1)!);
      final minute = int.tryParse(twentyFourHour.group(2)!);
      if (hour == null || minute == null) return null;
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
      return _formatClockTime(hour, minute);
    }

    return null;
  }

  String _formatClockTime(int hour24, int minute) {
    final marker = hour24 >= 12 ? 'PM' : 'AM';
    var hour = hour24 % 12;
    if (hour == 0) hour = 12;
    return '$hour:${minute.toString().padLeft(2, '0')} $marker';
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
            if (_isTripDatePromptActive)
              _DateRangeSelectorPanel(onSubmit: _submitSelectedDateRange),
            if (_isEndDatePromptActive)
              _EndDateSelectorPanel(
                currentDates: _editingGuide?.intake.dates,
                onKeepCurrent: _keepCurrentEndDate,
                onSubmit: _submitSelectedEndDate,
              ),
            if (_isTimePromptActive)
              _TimeSelectorPanel(
                key: ValueKey(_timePickerLabel),
                label: _timePickerLabel,
                initialPm: _isDepartureTimePrompt,
                onSubmit: _submitSelectedTime,
              ),
            if (_isStaySelectionActive)
              _StaySearchPanel(
                isSearching: _isSearchingStay,
                suggestions: _staySuggestions,
                errorText: _staySearchError,
                onSelect: _selectStaySuggestion,
              ),
            if (!_hidesComposer)
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
          return 'Search hotel or area';
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
        return 'Search hotel or area';
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

class _DateRangeSelectorPanel extends StatefulWidget {
  final ValueChanged<DateTimeRange> onSubmit;

  const _DateRangeSelectorPanel({required this.onSubmit});

  @override
  State<_DateRangeSelectorPanel> createState() =>
      _DateRangeSelectorPanelState();
}

class _DateRangeSelectorPanelState extends State<_DateRangeSelectorPanel> {
  DateTimeRange? _range;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: RaasteShellColors.outline),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: RaasteShellColors.shadow,
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.calendar_month_rounded,
                  color: RaasteShellColors.clay,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _range == null ? 'Travel dates' : _rangeLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RaasteShellColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range_rounded, size: 18),
              label: Text(
                _range == null ? 'Choose travel dates' : 'Change dates',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: RaasteShellColors.ink,
                side: const BorderSide(color: RaasteShellColors.outline),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    _range == null ? null : () => widget.onSubmit(_range!),
                style: FilledButton.styleFrom(
                  backgroundColor: RaasteShellColors.clay,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: RaasteShellColors.outline,
                  disabledForegroundColor: RaasteShellColors.muted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(today.year + 2, today.month, today.day),
      initialDateRange: _range,
      helpText: 'Select travel dates',
      saveText: 'Done',
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
  }

  String get _rangeLabel {
    final range = _range!;
    final start = range.start;
    final end = range.end;
    if (_sameDate(start, end)) return _dateLabel(start);
    if (start.year == end.year && start.month == end.month) {
      return '${start.day}-${end.day} ${_monthName(start.month)} ${start.year}';
    }
    if (start.year == end.year) {
      return '${start.day} ${_monthName(start.month)} - ${end.day} ${_monthName(end.month)} ${start.year}';
    }
    return '${_dateLabel(start)} - ${_dateLabel(end)}';
  }
}

class _EndDateSelectorPanel extends StatelessWidget {
  final String? currentDates;
  final Future<void> Function() onKeepCurrent;
  final ValueChanged<DateTime> onSubmit;

  const _EndDateSelectorPanel({
    required this.currentDates,
    required this.onKeepCurrent,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = currentDates?.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: RaasteShellColors.outline),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: RaasteShellColors.shadow,
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.event_available_rounded,
                  color: RaasteShellColors.clay,
                  size: 20,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'End date',
                    style: TextStyle(
                      color: RaasteShellColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Current: $subtitle',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: RaasteShellColors.muted),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onKeepCurrent,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Keep current'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: RaasteShellColors.ink,
                      side: const BorderSide(color: RaasteShellColors.outline),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _pickEndDate(context),
                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: const Text('Choose date'),
                    style: FilledButton.styleFrom(
                      backgroundColor: RaasteShellColors.clay,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickEndDate(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(today.year + 2, today.month, today.day),
      initialDate: today,
      helpText: 'Select end date',
    );
    if (picked != null) onSubmit(picked);
  }
}

bool _sameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _dateLabel(DateTime date) {
  return '${date.day} ${_monthName(date.month)} ${date.year}';
}

String _monthName(int month) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return months[month - 1];
}

class _TimeSelectorPanel extends StatefulWidget {
  final String label;
  final bool initialPm;
  final ValueChanged<String> onSubmit;

  const _TimeSelectorPanel({
    super.key,
    required this.label,
    required this.initialPm,
    required this.onSubmit,
  });

  @override
  State<_TimeSelectorPanel> createState() => _TimeSelectorPanelState();
}

class _TimeSelectorPanelState extends State<_TimeSelectorPanel> {
  late int _hour;
  late int _minute;
  late String _period;

  @override
  void initState() {
    super.initState();
    _hour = widget.initialPm ? 6 : 10;
    _minute = 0;
    _period = widget.initialPm ? 'PM' : 'AM';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: RaasteShellColors.outline),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: RaasteShellColors.shadow,
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  color: RaasteShellColors.clay,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      color: RaasteShellColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  _formattedTime,
                  style: const TextStyle(
                    color: RaasteShellColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _TimeDropdown<int>(
                    label: 'Hour',
                    value: _hour,
                    values: List<int>.generate(12, (index) => index + 1),
                    display: (value) => value.toString(),
                    onChanged: (value) => setState(() => _hour = value),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimeDropdown<int>(
                    label: 'Minute',
                    value: _minute,
                    values: List<int>.generate(12, (index) => index * 5),
                    display: (value) => value.toString().padLeft(2, '0'),
                    onChanged: (value) => setState(() => _minute = value),
                  ),
                ),
                const SizedBox(width: 10),
                _PeriodToggle(
                  period: _period,
                  onChanged: (value) => setState(() => _period = value),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => widget.onSubmit(_formattedTime),
                style: FilledButton.styleFrom(
                  backgroundColor: RaasteShellColors.clay,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _formattedTime =>
      '$_hour:${_minute.toString().padLeft(2, '0')} $_period';
}

class _TimeDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> values;
  final String Function(T value) display;
  final ValueChanged<T> onChanged;

  const _TimeDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F2EC),
        border: Border.all(color: RaasteShellColors.outline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: RaasteShellColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              items:
                  values
                      .map(
                        (item) => DropdownMenuItem<T>(
                          value: item,
                          child: Text(
                            display(item),
                            style: const TextStyle(
                              color: RaasteShellColors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                      .toList(),
              onChanged: (value) {
                if (value != null) onChanged(value);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodToggle extends StatelessWidget {
  final String period;
  final ValueChanged<String> onChanged;

  const _PeriodToggle({required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F2EC),
        border: Border.all(color: RaasteShellColors.outline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PeriodButton(
            label: 'AM',
            active: period == 'AM',
            onTap: () => onChanged('AM'),
          ),
          _PeriodButton(
            label: 'PM',
            active: period == 'PM',
            onTap: () => onChanged('PM'),
          ),
        ],
      ),
    );
  }
}

class _PeriodButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PeriodButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 54,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? RaasteShellColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : RaasteShellColors.muted,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _StaySearchPanel extends StatelessWidget {
  final bool isSearching;
  final List<PlaceSuggestion> suggestions;
  final String? errorText;
  final ValueChanged<PlaceSuggestion> onSelect;

  const _StaySearchPanel({
    required this.isSearching,
    required this.suggestions,
    required this.errorText,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (!isSearching && suggestions.isEmpty && errorText == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 260),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: RaasteShellColors.outline),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: RaasteShellColors.shadow,
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (isSearching && suggestions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: RaasteShellColors.clay,
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Searching map results...',
              style: TextStyle(color: RaasteShellColors.muted),
            ),
          ],
        ),
      );
    }

    if (suggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          errorText ?? 'No results found.',
          style: const TextStyle(color: RaasteShellColors.muted),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: suggestions.length,
      separatorBuilder:
          (_, __) => const Divider(height: 1, color: RaasteShellColors.outline),
      itemBuilder: (context, index) {
        final suggestion = suggestions[index];
        return ListTile(
          dense: true,
          leading: const Icon(
            Icons.location_on_outlined,
            color: RaasteShellColors.clay,
          ),
          title: Text(
            suggestion.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: RaasteShellColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            suggestion.displayAddress,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: RaasteShellColors.muted),
          ),
          onTap: () => onSelect(suggestion),
        );
      },
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
