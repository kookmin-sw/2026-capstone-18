import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/cycle.dart';

abstract class CycleOngoingStore {
  Future<bool> isOngoing(String cycleId);

  Future<void> setOngoing(String cycleId, bool ongoing);

  Future<Cycle?> applyTo(Cycle? cycle) async {
    if (cycle == null || cycle.id.isEmpty) return cycle;

    if (cycle.periodEndDate != null) {
      await setOngoing(cycle.id, false);
      return cycle.copyWith(periodOngoing: false);
    }

    final ongoing = await isOngoing(cycle.id);
    return cycle.copyWith(periodOngoing: ongoing);
  }
}

class CycleOngoingStorage extends CycleOngoingStore {
  static const _keyPrefix = 'cycle_period_ongoing_';

  final FlutterSecureStorage _storage;

  CycleOngoingStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<bool> isOngoing(String cycleId) async {
    if (cycleId.isEmpty) return false;
    return await _storage.read(key: _key(cycleId)) == 'true';
  }

  @override
  Future<void> setOngoing(String cycleId, bool ongoing) async {
    if (cycleId.isEmpty) return;

    if (ongoing) {
      await _storage.write(key: _key(cycleId), value: 'true');
    } else {
      await _storage.delete(key: _key(cycleId));
    }
  }

  String _key(String cycleId) => '$_keyPrefix$cycleId';
}
