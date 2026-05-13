import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/core/network/api_client.dart';
import 'package:little_signals/core/storage/secure_token_storage.dart';
import 'package:little_signals/features/events/data/events_api.dart';
import 'package:little_signals/features/events/events_provider.dart';
import 'package:little_signals/features/events/models/stress_event.dart';

void main() {
  test('createEvent forwards selected category id', () async {
    final api = _CaptureEventsApi();
    final provider = EventsProvider(eventsApi: api);

    final event = await provider.createEvent(
      stressScore: 64,
      trigger: 'Work',
      categoryId: 'category-work',
    );

    expect(api.createdEvent?.categoryId, 'category-work');
    expect(event?.categoryId, 'category-work');
  });

  test('updateEvent patches selected category id', () async {
    final api = _CaptureEventsApi();
    final provider = EventsProvider(eventsApi: api);
    final existing = StressEvent(
      id: 'event-1',
      detectedAt: DateTime.utc(2026, 5, 8, 12),
      stressScore: 50,
      trigger: 'Family',
      note: null,
      categoryId: 'category-family',
    );

    final event = await provider.updateEvent(
      event: existing,
      stressScore: 72,
      trigger: 'Work',
      categoryId: 'category-work',
    );

    expect(api.updatedChanges?['category_id'], 'category-work');
    expect(event?.categoryId, 'category-work');
  });
}

class _CaptureEventsApi extends EventsApi {
  StressEvent? createdEvent;
  Map<String, dynamic>? updatedChanges;

  _CaptureEventsApi()
    : super(apiClient: ApiClient(tokenStorage: SecureTokenStorage()));

  @override
  Future<StressEvent> createEvent(StressEvent event) async {
    createdEvent = event;
    return event.copyWith(id: 'created-event');
  }

  @override
  Future<StressEvent> updateEvent(
    String id,
    Map<String, dynamic> changes,
  ) async {
    updatedChanges = changes;
    return StressEvent(
      id: id,
      detectedAt: DateTime.utc(2026, 5, 8, 12),
      stressScore: (changes['user_stress_level'] as num?)?.round(),
      trigger: _firstChip(changes['log_chips']),
      note: changes['log_text'] as String?,
      logChips:
          (changes['log_chips'] as List?)?.map((item) => '$item').toList() ??
          const <String>[],
      categoryId: changes['category_id'] as String?,
    );
  }

  String _firstChip(Object? value) {
    if (value is! List || value.isEmpty) return '';
    return '${value.first}';
  }
}
