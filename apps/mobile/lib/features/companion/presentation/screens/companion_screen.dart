import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:raaste/config/routes.dart';
import 'package:raaste/core/di/injection.dart';
import 'package:raaste/features/companion/application/local_itinerary_edit_service.dart';
import 'package:raaste/features/destination/data/repositories/destination_guide_store.dart';
import 'package:raaste/features/destination/data/services/destination_research_service.dart';
import 'package:raaste/features/destination/data/services/google_route_matrix_service.dart';
import 'package:raaste/features/destination/data/services/open_ai_destination_service.dart';
import 'package:raaste/features/destination/domain/models/destination_guide.dart';
import 'package:raaste/features/trip/data/repositories/saved_trip_repository.dart';
import 'package:raaste/features/trip/domain/models/saved_trip.dart';
import 'package:raaste/shared/widgets/raaste_nav_shell.dart';

class CompanionScreen extends StatefulWidget {
  final String tripId;

  const CompanionScreen({super.key, required this.tripId});

  @override
  State<CompanionScreen> createState() => _CompanionScreenState();
}

enum _CompanionMode {
  idle,
  confirmingRegeneration,
  confirmingAiFallback,
  selectingDates,
  selectingArrivalTime,
  selectingDepartureTime,
  showingAlternatives,
  applyingChange,
}

class _CompanionScreenState extends State<CompanionScreen> {
  final _messages = <_ChatMessage>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _savedTrips = getIt<SavedTripRepository>();
  final _guideStore = getIt<DestinationGuideStore>();
  final _research = getIt<DestinationResearchService>();
  final _routeTiming = getIt<GoogleRouteMatrixService>();
  final _openAi = getIt<OpenAiDestinationService>();
  final _localEdits = getIt<LocalItineraryEditService>();

  SavedTrip? _trip;
  Map<String, dynamic>? _researchContext;
  bool _isLoading = false;
  bool _isInitialising = true;
  bool _hasUpdatedTrip = false;
  String? _initError;
  _CompanionMode _mode = _CompanionMode.idle;
  String? _pendingDates;
  String? _pendingArrivalTime;
  String? _pendingDepartureTime;
  String? _pendingAiFallbackRequest;
  bool _pendingAiFallbackAlternatives = false;
  List<LocalTripAlternative> _alternatives = const [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final tripId = widget.tripId.trim();
    if (tripId.isEmpty) {
      setState(() {
        _isInitialising = false;
        _initError = 'No trip selected. Go back and open a saved trip first.';
      });
      return;
    }

    final trip = await _savedTrips.getTrip(tripId);
    if (trip == null) {
      setState(() {
        _isInitialising = false;
        _initError = 'Could not load your trip. Go back and try again.';
      });
      return;
    }

    final research = await _research.loadForIntake(trip.guide.intake);
    setState(() {
      _trip = trip;
      _researchContext = research?.toPromptJson() ?? <String, dynamic>{};
      _isInitialising = false;
      _messages.add(
        _ChatMessage.assistant(
          'Trip Companion can edit this itinerary for ${trip.destinationName}. Ask me to replace a planned stop, show alternatives to a place, or change dates/times. Date and time changes require regenerating the itinerary.',
        ),
      );
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading || _isInitialising || _trip == null) return;
    _controller.clear();
    _addUser(text);

    if (_mode == _CompanionMode.confirmingRegeneration) {
      _handleTypedRegenerationAnswer(text);
      return;
    }
    if (_mode == _CompanionMode.confirmingAiFallback) {
      await _handleTypedAiFallbackAnswer(text);
      return;
    }
    if (_mode == _CompanionMode.showingAlternatives) {
      final index = _alternativeIndexFromText(text);
      if (index == null) {
        _addAssistant(
          'Choose one of the alternatives below so I can update the itinerary.',
        );
        return;
      }
      await _selectAlternative(_alternatives[index], addUserMessage: false);
      return;
    }
    if (_mode != _CompanionMode.idle) return;

    if (_isDateOrTimeEdit(text)) {
      _startRegenerationConfirmation(text);
    } else if (_shouldOfferAlternativesBeforeEditing(text)) {
      await _loadAlternatives(text);
    } else if (_isAlternativesRequest(text)) {
      await _loadAlternatives(text);
    } else if (_isDirectEditRequest(text)) {
      await _applyLocalDirectEdit(text);
    } else if (_isComplexAiEditRequest(text)) {
      _startAiFallbackConfirmation(
        text,
        alternatives: false,
        explanation:
            'That edit needs itinerary reasoning beyond a safe local place swap. Do you want me to use AI for this update?',
      );
    } else {
      _addAssistant(_scopeMessage);
    }
  }

  void _startRegenerationConfirmation(String request) {
    setState(() {
      _alternatives = const [];
      _mode = _CompanionMode.confirmingRegeneration;
      _messages.add(
        _ChatMessage.assistant(
          'Changing dates or times requires regenerating the itinerary. Do you want to regenerate?',
        ),
      );
    });
    _scrollToEnd();
  }

  void _handleTypedRegenerationAnswer(String text) {
    final lower = text.trim().toLowerCase();
    if (_isYes(lower)) {
      _handleRegenerationDecision(true, addUserMessage: false);
    } else if (_isNo(lower)) {
      _handleRegenerationDecision(false, addUserMessage: false);
    } else {
      _addAssistant('Please choose Yes or No.');
    }
  }

  Future<void> _handleTypedAiFallbackAnswer(String text) async {
    final lower = text.trim().toLowerCase();
    if (_isYes(lower)) {
      await _handleAiFallbackDecision(true, addUserMessage: false);
    } else if (_isNo(lower)) {
      await _handleAiFallbackDecision(false, addUserMessage: false);
    } else {
      _addAssistant('Please choose Yes or No.');
    }
  }

  void _startAiFallbackConfirmation(
    String request, {
    required bool alternatives,
    required String explanation,
  }) {
    setState(() {
      _pendingAiFallbackRequest = request;
      _pendingAiFallbackAlternatives = alternatives;
      _alternatives = const [];
      _mode = _CompanionMode.confirmingAiFallback;
      _isLoading = false;
      _messages.add(_ChatMessage.assistant(explanation));
    });
    _scrollToEnd();
  }

  Future<void> _handleAiFallbackDecision(
    bool yes, {
    bool addUserMessage = true,
  }) async {
    if (addUserMessage) _addUser(yes ? 'Yes' : 'No');
    final request = _pendingAiFallbackRequest;
    final useAlternativesFlow = _pendingAiFallbackAlternatives;
    _clearPendingAiFallback();

    if (!yes) {
      setState(() {
        _mode = _CompanionMode.idle;
        _messages.add(
          _ChatMessage.assistant(
            'No changes made. For a free local edit, ask me to replace a planned stop with a named place from the saved research, or ask for researched alternatives to a planned stop.',
          ),
        );
      });
      _scrollToEnd();
      return;
    }

    if (request == null || request.trim().isEmpty) {
      setState(() {
        _mode = _CompanionMode.idle;
        _messages.add(
          _ChatMessage.assistant('I lost the edit request. Please ask again.'),
        );
      });
      _scrollToEnd();
      return;
    }

    setState(() => _mode = _CompanionMode.idle);
    if (useAlternativesFlow) {
      await _loadAiAlternatives(request);
    } else {
      await _reviseTrip(request);
    }
  }

  void _handleRegenerationDecision(bool yes, {bool addUserMessage = true}) {
    if (addUserMessage) _addUser(yes ? 'Yes' : 'No');
    if (!yes) {
      setState(() {
        _mode = _CompanionMode.idle;
        _messages.add(
          _ChatMessage.assistant(
            'To edit dates and times, a new itinerary generation is required.',
          ),
        );
      });
      _scrollToEnd();
      return;
    }
    setState(() {
      _mode = _CompanionMode.selectingDates;
      _messages.add(
        _ChatMessage.assistant(
          'Choose the new travel dates. I will reuse your destination, stay, people, travel mode, pace, interests, and dietary preference.',
        ),
      );
    });
    _scrollToEnd();
  }

  void _submitSelectedDateRange(DateTimeRange range) {
    final label = _dateRangeLabel(range);
    setState(() {
      _pendingDates = label;
      _mode = _CompanionMode.selectingArrivalTime;
      _messages.add(_ChatMessage.user(label));
      _messages.add(_ChatMessage.assistant('What time do you land or arrive?'));
    });
    _scrollToEnd();
  }

  void _submitArrivalTime(String time) {
    setState(() {
      _pendingArrivalTime = time;
      _mode = _CompanionMode.selectingDepartureTime;
      _messages.add(_ChatMessage.user(time));
      _messages.add(
        _ChatMessage.assistant(
          'What time do you depart or leave on the final day?',
        ),
      );
    });
    _scrollToEnd();
  }

  Future<void> _submitDepartureTime(String time) async {
    setState(() {
      _pendingDepartureTime = time;
      _messages.add(_ChatMessage.user(time));
    });
    _scrollToEnd();
    await _regenerateTrip();
  }

  Future<void> _regenerateTrip() async {
    final trip = _trip;
    final dates = _pendingDates;
    final arrival = _pendingArrivalTime;
    final departure = _pendingDepartureTime;
    if (trip == null || dates == null || arrival == null || departure == null) {
      _addAssistant(
        'I need the new dates, arrival time, and departure time before regenerating.',
      );
      return;
    }

    final intake = trip.guide.intake.copyWith(
      dates: dates,
      landingTime: arrival,
      departureTime: departure,
    );
    setState(() {
      _mode = _CompanionMode.applyingChange;
      _isLoading = true;
      _hasUpdatedTrip = false;
      _messages.add(
        _ChatMessage.assistant(
          'Regenerating your itinerary around the new dates and times...',
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
      final timingContext = await _routeTiming.buildTimingContext(
        intake,
        research,
      );
      final guide = await _openAi.generateGuideFromResearch(
        intake,
        research,
        timingContext: timingContext,
      );
      final updatedTrip = await _saveUpdatedGuide(guide);
      if (!mounted) return;
      setState(() {
        _trip = updatedTrip;
        _researchContext = research.toPromptJson();
        _mode = _CompanionMode.idle;
        _isLoading = false;
        _hasUpdatedTrip = true;
        _clearPendingRegeneration();
        _messages.add(
          _ChatMessage.assistant(
            'Done. I regenerated and saved the itinerary with the new dates and times.',
          ),
        );
      });
      _scrollToEnd();
    } on RouteTimingException catch (e) {
      _showOperationError(e.message);
    } on OpenAiGuideException catch (e) {
      _showOperationError(e.message);
    } on SavedTripException catch (e) {
      _showOperationError(e.message);
    } catch (_) {
      _showOperationError(
        'Could not regenerate the itinerary right now. Please try again.',
      );
    }
  }

  Future<void> _loadAlternatives(String request) async {
    final trip = _trip;
    if (trip == null) return;
    setState(() {
      _mode = _CompanionMode.applyingChange;
      _isLoading = true;
      _hasUpdatedTrip = false;
      _alternatives = const [];
      _messages.add(
        _ChatMessage.assistant(
          'Checking the saved trip research for options...',
        ),
      );
    });
    _scrollToEnd();

    try {
      final research = await _research.loadForIntake(trip.guide.intake);
      if (research == null) {
        throw const OpenAiGuideException(
          'Raaste can only edit trips for Hyderabad, Lonavala, and Varanasi right now.',
        );
      }
      final researchContext = research.toPromptJson();
      final alternatives = _localEdits.suggestAlternatives(
        guide: trip.guide,
        researchContext: researchContext,
        request: request,
      );
      if (!mounted) return;
      if (alternatives.isEmpty) {
        _researchContext = researchContext;
        _startAiFallbackConfirmation(
          request,
          alternatives: true,
          explanation:
              'I could not safely find researched local options for that edit. Do you want me to use AI to look for alternatives?',
        );
        return;
      }
      setState(() {
        _researchContext = researchContext;
        _alternatives = alternatives;
        _mode = _CompanionMode.showingAlternatives;
        _isLoading = false;
        _messages.add(
          _ChatMessage.assistant(
            'I found these researched options. Choose one and I will update the itinerary without using AI.',
          ),
        );
      });
      _scrollToEnd();
    } on OpenAiGuideException catch (e) {
      _showOperationError(e.message);
    } catch (_) {
      _showOperationError(
        'Could not find local alternatives right now. Please try again.',
      );
    }
  }

  Future<void> _loadAiAlternatives(String request) async {
    final trip = _trip;
    final researchContext = _researchContext;
    if (trip == null || researchContext == null) return;
    setState(() {
      _mode = _CompanionMode.applyingChange;
      _isLoading = true;
      _hasUpdatedTrip = false;
      _alternatives = const [];
      _messages.add(
        _ChatMessage.assistant(
          'Using AI to find itinerary-safe alternatives...',
        ),
      );
    });
    _scrollToEnd();

    try {
      final suggestions = await _openAi.suggestTripAlternatives(
        guide: trip.guide,
        researchContext: researchContext,
        request: request,
      );
      final alternatives =
          suggestions
              .map(
                (suggestion) => LocalTripAlternative(
                  title: suggestion.title,
                  reason: suggestion.reason,
                  editRequest: suggestion.editRequest,
                  option: null,
                  applyLocally: false,
                ),
              )
              .toList();
      if (!mounted) return;
      setState(() {
        _alternatives = alternatives;
        _mode = _CompanionMode.showingAlternatives;
        _isLoading = false;
        _messages.add(
          _ChatMessage.assistant(
            'Choose one alternative below and I will update the itinerary with AI.',
          ),
        );
      });
      _scrollToEnd();
    } on OpenAiGuideException catch (e) {
      _showOperationError(e.message);
    } catch (_) {
      _showOperationError(
        'Could not find alternatives right now. Please try again.',
      );
    }
  }

  Future<void> _selectAlternative(
    LocalTripAlternative alternative, {
    bool addUserMessage = true,
  }) async {
    if (addUserMessage) _addUser('Use ${alternative.title}');
    if (alternative.applyLocally && alternative.option != null) {
      await _applySelectedLocalAlternative(alternative);
      return;
    }
    await _reviseTrip(
      alternative.editRequest,
      fromAlternative: true,
      selectedAlternativeTitle: alternative.title,
    );
  }

  Future<void> _applySelectedLocalAlternative(
    LocalTripAlternative alternative,
  ) async {
    final trip = _trip;
    final option = alternative.option;
    if (trip == null || option == null) return;
    setState(() {
      _mode = _CompanionMode.applyingChange;
      _isLoading = true;
      _hasUpdatedTrip = false;
      _alternatives = const [];
      _messages.add(
        _ChatMessage.assistant('Applying that researched option locally...'),
      );
    });
    _scrollToEnd();

    try {
      final research = await _research.loadForIntake(trip.guide.intake);
      if (research == null) {
        throw const OpenAiGuideException(
          'Raaste can only edit trips for Hyderabad, Lonavala, and Varanasi right now.',
        );
      }
      final researchContext = research.toPromptJson();
      final result = _localEdits.applySelectedAlternative(
        guide: trip.guide,
        request: alternative.editRequest,
        option: option,
      );
      if (result == null) {
        if (!mounted) return;
        _researchContext = researchContext;
        _startAiFallbackConfirmation(
          alternative.editRequest,
          alternatives: false,
          explanation:
              'I could not safely match the selected option to a planned stop. Do you want me to use AI for this update?',
        );
        return;
      }
      await _finishLocalUpdate(result, researchContext);
    } on OpenAiGuideException catch (e) {
      _showOperationError(e.message);
    } on SavedTripException catch (e) {
      _showOperationError(e.message);
    } catch (_) {
      _showOperationError(
        'Could not update the itinerary locally right now. Please try again.',
      );
    }
  }

  Future<void> _applyLocalDirectEdit(String request) async {
    final trip = _trip;
    if (trip == null) return;
    setState(() {
      _mode = _CompanionMode.applyingChange;
      _isLoading = true;
      _hasUpdatedTrip = false;
      _alternatives = const [];
      _messages.add(
        _ChatMessage.assistant(
          'Checking whether this can be edited locally...',
        ),
      );
    });
    _scrollToEnd();

    try {
      final research = await _research.loadForIntake(trip.guide.intake);
      if (research == null) {
        throw const OpenAiGuideException(
          'Raaste can only edit trips for Hyderabad, Lonavala, and Varanasi right now.',
        );
      }
      final researchContext = research.toPromptJson();
      final result = _localEdits.applyDirectEdit(
        guide: trip.guide,
        researchContext: researchContext,
        request: request,
      );
      if (result == null) {
        final alternatives = _localEdits.suggestAlternatives(
          guide: trip.guide,
          researchContext: researchContext,
          request: request,
        );
        if (!mounted) return;
        if (alternatives.isNotEmpty) {
          setState(() {
            _researchContext = researchContext;
            _alternatives = alternatives;
            _mode = _CompanionMode.showingAlternatives;
            _isLoading = false;
            _messages.add(
              _ChatMessage.assistant(
                'I found researched options that fit that request. Choose one and I will update the itinerary without using AI.',
              ),
            );
          });
          _scrollToEnd();
          return;
        }
        _researchContext = researchContext;
        _startAiFallbackConfirmation(
          request,
          alternatives: false,
          explanation:
              'I could not safely apply that from saved research alone. Do you want me to use AI for this edit?',
        );
        return;
      }
      await _finishLocalUpdate(result, researchContext);
    } on OpenAiGuideException catch (e) {
      _showOperationError(e.message);
    } on SavedTripException catch (e) {
      _showOperationError(e.message);
    } catch (_) {
      _showOperationError(
        'Could not update the itinerary locally right now. Please try again.',
      );
    }
  }

  Future<void> _finishLocalUpdate(
    LocalGuideEditResult result,
    Map<String, dynamic> researchContext,
  ) async {
    final updatedTrip = await _saveUpdatedGuide(result.guide);
    if (!mounted) return;
    setState(() {
      _trip = updatedTrip;
      _researchContext = researchContext;
      _mode = _CompanionMode.idle;
      _isLoading = false;
      _hasUpdatedTrip = true;
      _alternatives = const [];
      _messages.add(_ChatMessage.assistant(result.message));
    });
    _scrollToEnd();
  }

  Future<void> _reviseTrip(
    String editRequest, {
    bool fromAlternative = false,
    String? selectedAlternativeTitle,
  }) async {
    final trip = _trip;
    if (trip == null) return;
    setState(() {
      _mode = _CompanionMode.applyingChange;
      _isLoading = true;
      _hasUpdatedTrip = false;
      _alternatives = const [];
      _messages.add(
        _ChatMessage.assistant(
          fromAlternative
              ? 'Applying that alternative with AI...'
              : 'Updating your itinerary with AI...',
        ),
      );
    });
    _scrollToEnd();

    try {
      final research = await _research.loadForIntake(trip.guide.intake);
      if (research == null) {
        throw const OpenAiGuideException(
          'Raaste can only edit trips for Hyderabad, Lonavala, and Varanasi right now.',
        );
      }
      final timingContext = await _routeTiming.buildTimingContext(
        trip.guide.intake,
        research,
      );
      final updated = await _openAi.reviseGuide(
        currentGuide: trip.guide,
        editRequest: _placeEditRequest(
          editRequest,
          selectedAlternativeTitle: selectedAlternativeTitle,
        ),
        timingContext: timingContext,
        research: research,
      );
      final updatedTrip = await _saveUpdatedGuide(updated);
      if (!mounted) return;
      setState(() {
        _trip = updatedTrip;
        _researchContext = research.toPromptJson();
        _mode = _CompanionMode.idle;
        _isLoading = false;
        _hasUpdatedTrip = true;
        _messages.add(
          _ChatMessage.assistant('Done. I updated and saved the itinerary.'),
        );
      });
      _scrollToEnd();
    } on RouteTimingException catch (e) {
      _showOperationError(e.message);
    } on OpenAiGuideException catch (e) {
      _showOperationError(e.message);
    } on SavedTripException catch (e) {
      _showOperationError(e.message);
    } catch (_) {
      _showOperationError(
        'Could not update the itinerary right now. Please try again.',
      );
    }
  }

  Future<SavedTrip> _saveUpdatedGuide(DestinationGuide guide) async {
    final trip = _trip;
    if (trip == null) {
      throw const SavedTripException('Could not update this trip right now.');
    }
    final guideId = await _guideStore.saveGuide(guide);
    final savedGuide = guide.copyWith(id: guideId, updatedAt: DateTime.now());
    return _savedTrips.updateTripGuide(tripId: trip.id, guide: savedGuide);
  }

  void _showOperationError(String message) {
    if (!mounted) return;
    setState(() {
      _mode = _CompanionMode.idle;
      _isLoading = false;
      _messages.add(_ChatMessage.assistant(message));
    });
    _scrollToEnd();
  }

  String _placeEditRequest(
    String editRequest, {
    String? selectedAlternativeTitle,
  }) {
    final selectedRule =
        selectedAlternativeTitle == null
            ? ''
            : '''
- The user selected this researched option: $selectedAlternativeTitle. Use this exact concrete option as the replacement.
- Visible itinerary text must be polished for a traveller. Use a natural stop title such as "$selectedAlternativeTitle" or "Shopping at $selectedAlternativeTitle". Never use internal/generic wording like "generic mall slot", "mall time", "shopping option", "nearby mall", or "choose a mall".
''';

    return '''
User itinerary edit request:
$editRequest

Trip Companion editing rules:
- This is a place/activity/restaurant itinerary edit, not a date or trip-time regeneration.
- Do not change intake.dates, intake.landingTime, intake.departureTime, stay, people count, travel mode, pace, interests, or dietary preference.
- Keep the same number of itinerary days.
- Retiming nearby stops is allowed only to make the selected replacement fit realistically.
- If the request names a broad category instead of a concrete place, do not apply it directly; this path should only apply already-selected concrete places.
$selectedRule''';
  }

  void _clearPendingRegeneration() {
    _pendingDates = null;
    _pendingArrivalTime = null;
    _pendingDepartureTime = null;
  }

  void _clearPendingAiFallback() {
    _pendingAiFallbackRequest = null;
    _pendingAiFallbackAlternatives = false;
  }

  void _addUser(String text) {
    setState(() => _messages.add(_ChatMessage.user(text)));
    _scrollToEnd();
  }

  void _addAssistant(String text) {
    setState(() => _messages.add(_ChatMessage.assistant(text)));
    _scrollToEnd();
  }

  bool _isDateOrTimeEdit(String text) {
    final lower = text.toLowerCase();
    final mentionsDate =
        lower.contains('date') ||
        lower.contains('dates') ||
        lower.contains('start date') ||
        lower.contains('end date') ||
        lower.contains('extend') ||
        lower.contains('shorten') ||
        lower.contains('postpone') ||
        lower.contains('prepone') ||
        RegExp(
          r'\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\b',
        ).hasMatch(lower);
    final mentionsTripTime =
        lower.contains('arrival') ||
        lower.contains('arrive') ||
        lower.contains('landing') ||
        lower.contains('departure') ||
        lower.contains('depart') ||
        lower.contains('final day time') ||
        lower.contains('flight time') ||
        lower.contains('train time');
    return mentionsDate || mentionsTripTime;
  }

  bool _isAlternativesRequest(String text) {
    final lower = text.toLowerCase();
    final asksForCategory = RegExp(
      r'\b(mall|malls|cafe|cafes|restaurant|restaurants|restraunt|restraunts|resturant|resturants|market|markets|shopping|place|activity|attraction)\b',
    ).hasMatch(lower);
    final asksForSuggestion =
        lower.contains('suggest') ||
        lower.contains('find') ||
        lower.contains('show') ||
        lower.contains('give me') ||
        lower.contains('options');
    return lower.contains('alternative') ||
        lower.contains('alternatives') ||
        lower.contains('show options') ||
        lower.contains('other options') ||
        lower.contains('suggest options') ||
        lower.contains('suggest another') ||
        lower.contains('show another') ||
        (asksForCategory && asksForSuggestion);
  }

  bool _shouldOfferAlternativesBeforeEditing(String text) {
    final lower = text.toLowerCase();
    if (!_isDirectEditRequest(text)) return false;

    final asksForGenericCategory = RegExp(
      r'\b(?:with|to|for|into|instead of)\s+(?:a|an|some|any|one|other|good|nice|nearby|best)?\s*(?:mall|malls|cafe|cafes|restaurant|restaurants|restraunt|restraunts|resturant|resturants|market|markets|shopping|shop|shops|place|activity|attraction|park|museum|temple|pub|bar|club)\b',
    ).hasMatch(lower);
    final categoryReplacement = RegExp(
      r'\b(?:mall|malls|cafe|cafes|restaurant|restaurants|restraunt|restraunts|resturant|resturants|market|markets|shopping|place|activity|attraction)\s+(?:option|options|replacement|instead)\b',
    ).hasMatch(lower);

    return asksForGenericCategory || categoryReplacement;
  }

  bool _isDirectEditRequest(String text) {
    final lower = text.toLowerCase();
    return lower.contains('replace') ||
        lower.contains('swap') ||
        lower.contains('edit') ||
        lower.contains('update') ||
        lower.contains('modify') ||
        lower.contains('switch') ||
        lower.contains('substitute') ||
        lower.contains('turn ') ||
        lower.contains('instead') ||
        lower.contains('remove') ||
        lower.contains('skip') ||
        lower.contains('move') ||
        lower.contains('retime') ||
        lower.contains('add ') ||
        lower.contains('use ') ||
        lower.contains('put ') ||
        lower.contains('change');
  }

  bool _isComplexAiEditRequest(String text) {
    return RegExp(
      r'\b(make|optimi[sz]e|retime|route|rearrange|rebuild|less tiring|easier|slower|faster|kid|family|balance|too packed|too much|entire day|whole day)\b',
      caseSensitive: false,
    ).hasMatch(text);
  }

  bool _isYes(String lower) {
    return lower == 'yes' ||
        lower == 'y' ||
        lower.contains('yes') ||
        lower.contains('regenerate') ||
        lower.contains('go ahead');
  }

  bool _isNo(String lower) {
    return lower == 'no' ||
        lower == 'n' ||
        lower.contains('no') ||
        lower.contains('cancel') ||
        lower.contains('do not') ||
        lower.contains("don't");
  }

  int? _alternativeIndexFromText(String text) {
    final normalized = text.trim().toLowerCase();
    final asNumber = int.tryParse(normalized.replaceAll(RegExp(r'[^0-9]'), ''));
    if (asNumber != null && asNumber >= 1 && asNumber <= _alternatives.length) {
      return asNumber - 1;
    }
    for (var i = 0; i < _alternatives.length; i++) {
      if (normalized.contains(_alternatives[i].title.toLowerCase())) return i;
    }
    return null;
  }

  String get _scopeMessage =>
      'Trip Companion only edits or regenerates your saved itinerary. Try "edit mall time with a mall", "replace the 4 PM stop with Inorbit Mall", "show alternatives to Golconda Fort", or "change my dates".';

  bool get _showComposer =>
      !_isLoading &&
      !_isInitialising &&
      _initError == null &&
      _mode == _CompanionMode.idle;

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

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.trips);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: RaasteShellColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildMessageList()),
            if (_isLoading) _buildTypingIndicator(),
            if (_mode == _CompanionMode.confirmingRegeneration)
              _ConfirmationPanel(
                onYes: () => _handleRegenerationDecision(true),
                onNo: () => _handleRegenerationDecision(false),
              ),
            if (_mode == _CompanionMode.confirmingAiFallback)
              _ConfirmationPanel(
                onYes: () => _handleAiFallbackDecision(true),
                onNo: () => _handleAiFallbackDecision(false),
              ),
            if (_mode == _CompanionMode.selectingDates)
              _DateRangeSelectorPanel(onSubmit: _submitSelectedDateRange),
            if (_mode == _CompanionMode.selectingArrivalTime)
              _TimePickerPanel(
                label: 'Arrival time',
                initialTime: const TimeOfDay(hour: 10, minute: 0),
                onSubmit: _submitArrivalTime,
              ),
            if (_mode == _CompanionMode.selectingDepartureTime)
              _TimePickerPanel(
                label: 'Departure time',
                initialTime: const TimeOfDay(hour: 18, minute: 0),
                onSubmit: _submitDepartureTime,
              ),
            if (_mode == _CompanionMode.showingAlternatives)
              _AlternativesPanel(
                alternatives: _alternatives,
                onSelect: _selectAlternative,
              ),
            if (_hasUpdatedTrip && _mode == _CompanionMode.idle)
              _ViewItineraryPanel(onTap: _openUpdatedItinerary),
            if (_showComposer) _buildInput(bottomPadding),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final name = _trip?.destinationName ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 18, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: _handleBack,
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
                  name.isEmpty ? 'Trip Companion' : name,
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
                const Text(
                  'Edit or regenerate itinerary',
                  style: TextStyle(
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

  Widget _buildMessageList() {
    if (_isInitialising) {
      return const Center(
        child: CircularProgressIndicator(color: RaasteShellColors.clay),
      );
    }
    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _initError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: RaasteShellColors.muted),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      itemCount: _messages.length,
      itemBuilder:
          (context, index) => _MessageBubble(message: _messages[index]),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: RaasteShellColors.outline),
        ),
        child: const SizedBox(width: 36, height: 14, child: _TypingDots()),
      ),
    );
  }

  Widget _buildInput(double bottomPadding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 10, 18, bottomPadding + 14),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText:
                    'Replace a stop, show alternatives, or change dates...',
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
              onPressed: _sendMessage,
              icon: const Icon(Icons.send_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _openUpdatedItinerary() {
    final tripId = _trip?.id.trim();
    if (tripId == null || tripId.isEmpty) return;
    context.go(
      '${AppRoutes.destination}?tripId=${Uri.encodeComponent(tripId)}',
    );
  }
}

class _ConfirmationPanel extends StatelessWidget {
  final VoidCallback onYes;
  final VoidCallback onNo;

  const _ConfirmationPanel({required this.onYes, required this.onNo});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Row(
        children: [
          Expanded(
            child: _PanelButton(
              label: 'No',
              icon: Icons.close_rounded,
              filled: false,
              onTap: onNo,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _PanelButton(
              label: 'Yes',
              icon: Icons.refresh_rounded,
              filled: true,
              onTap: onYes,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlternativesPanel extends StatelessWidget {
  final List<LocalTripAlternative> alternatives;
  final ValueChanged<LocalTripAlternative> onSelect;

  const _AlternativesPanel({
    required this.alternatives,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final maxHeight =
        (MediaQuery.sizeOf(context).height * 0.46)
            .clamp(220.0, 430.0)
            .toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children:
                alternatives.asMap().entries.map((entry) {
                  final index = entry.key + 1;
                  final alternative = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$index. ${alternative.title}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: RaasteShellColors.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (alternative.reason.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              alternative.reason,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: RaasteShellColors.muted,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: () => onSelect(alternative),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text(
                                'Use this',
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2F6F68),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
      ),
    );
  }
}

class _ViewItineraryPanel extends StatelessWidget {
  final VoidCallback onTap;

  const _ViewItineraryPanel({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.map_outlined, size: 18),
          label: const Text('View updated itinerary'),
          style: FilledButton.styleFrom(
            backgroundColor: RaasteShellColors.ink,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _PanelButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final background = filled ? RaasteShellColors.clay : Colors.white;
    final foreground = filled ? Colors.white : RaasteShellColors.ink;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  filled ? RaasteShellColors.clay : RaasteShellColors.outline,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
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
                    _range == null
                        ? 'New travel dates'
                        : _dateRangeLabel(_range!),
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
}

class _TimePickerPanel extends StatefulWidget {
  final String label;
  final TimeOfDay initialTime;
  final ValueChanged<String> onSubmit;

  const _TimePickerPanel({
    required this.label,
    required this.initialTime,
    required this.onSubmit,
  });

  @override
  State<_TimePickerPanel> createState() => _TimePickerPanelState();
}

class _TimePickerPanelState extends State<_TimePickerPanel> {
  TimeOfDay? _time;

  @override
  Widget build(BuildContext context) {
    final label =
        _time == null
            ? 'Choose ${widget.label.toLowerCase()}'
            : _time!.format(context);
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
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: RaasteShellColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.access_time_rounded, size: 18),
              label: Text(_time == null ? 'Choose time' : 'Change time'),
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
                    _time == null
                        ? null
                        : () => widget.onSubmit(_time!.format(context)),
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

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? widget.initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _time = picked);
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

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(3, (i) {
            final delay = i / 3;
            final value = (_ctrl.value - delay).clamp(0.0, 1.0);
            final opacity = (value < 0.5 ? value * 2 : (1 - value) * 2).clamp(
              0.3,
              1.0,
            );
            return Opacity(
              opacity: opacity,
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: RaasteShellColors.muted,
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
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

String _dateRangeLabel(DateTimeRange range) {
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

String _dateLabel(DateTime date) =>
    '${date.day} ${_monthName(date.month)} ${date.year}';

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

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
