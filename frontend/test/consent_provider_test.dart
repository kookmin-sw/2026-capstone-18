import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/core/network/api_client.dart';
import 'package:little_signals/core/storage/secure_token_storage.dart';
import 'package:little_signals/features/consent/consent_provider.dart';
import 'package:little_signals/features/consent/data/consent_api.dart';

void main() {
  group('ConsentProvider', () {
    test('clears stale consent while loading a new session', () async {
      final api = _FakeConsentApi();
      final provider = ConsentProvider(consentApi: api);

      final firstLoad = provider.loadConsent();
      api.completeNextGet(_consent(raw: true));
      await firstLoad;

      expect(provider.consent?.rawBiosignalConsent, isTrue);

      final secondLoad = provider.loadConsent();

      expect(provider.consent, isNull);
      expect(provider.isLoading, isTrue);

      api.completeNextGet(_consent(raw: false));
      await secondLoad;

      expect(provider.consent?.rawBiosignalConsent, isFalse);
      expect(provider.isLoading, isFalse);
    });

    test(
      'ignores a consent response that completes after session clear',
      () async {
        final api = _FakeConsentApi();
        final provider = ConsentProvider(consentApi: api);

        final load = provider.loadConsent();
        provider.clearSessionData();
        api.completeNextGet(_consent(raw: true));
        await load;

        expect(provider.consent, isNull);
        expect(provider.isLoading, isFalse);
      },
    );
  });
}

ConsentState _consent({required bool raw}) {
  return ConsentState(
    rawBiosignalConsent: raw,
    auditLoggingConsent: false,
    privacyPolicyVersion: '2026.05',
  );
}

class _FakeConsentApi extends ConsentApi {
  final List<Completer<ConsentState>> _getCompleters = [];

  _FakeConsentApi()
    : super(apiClient: ApiClient(tokenStorage: SecureTokenStorage()));

  @override
  Future<ConsentState> getConsent() {
    final completer = Completer<ConsentState>();
    _getCompleters.add(completer);
    return completer.future;
  }

  void completeNextGet(ConsentState value) {
    _getCompleters.removeAt(0).complete(value);
  }
}
