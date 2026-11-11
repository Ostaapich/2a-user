import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Session-only contact draft. Passwords and verification tokens are never
/// retained. A page reopened after leaving must confirm the phone again.
class RegistrationContactDraft {
  const RegistrationContactDraft({
    this.name = '',
    this.phone = '',
    this.email = '',
    this.agentCode = '',
    this.referralCode = '',
  });
  final String name, phone, email, agentCode, referralCode;
}

class RegistrationDraftStore {
  RegistrationContactDraft? value;
  bool authenticated = false;
  void clear() => value = null;
}

final registrationDraftStoreProvider = Provider(
  (_) => RegistrationDraftStore(),
);
