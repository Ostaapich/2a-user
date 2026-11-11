import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_provider.dart';
import '../../clients/application/client_codes_controller.dart';

/// Session-only choices, isolated by authenticated owner and proven client code.
final _invoicePaymentDraftSessionProvider =
    Provider<_InvoicePaymentDraftSession>((ref) {
      final owner = ref.watch(
        authProvider.select(
          (value) => (value.isLoggedIn, value.clientId, value.userDomain),
        ),
      );
      return _InvoicePaymentDraftSession(owner.$1 && (owner.$2 ?? 0) > 0);
    });

final invoicePaymentMethodDraftsProvider = Provider<InvoicePaymentMethodDrafts>(
  (ref) => ref
      .watch(_invoicePaymentDraftSessionProvider)
      .forCode(ref.watch(activeClientCodeProvider)),
);

class _InvoicePaymentDraftSession {
  _InvoicePaymentDraftSession(this.enabled);
  final bool enabled;
  final _unknown = InvoicePaymentMethodDrafts(enabled: false);
  String? _knownCode;
  InvoicePaymentMethodDrafts? _drafts;

  InvoicePaymentMethodDrafts forCode(String? code) {
    // A refresh may briefly hide the code. Keep the known draft in memory, but
    // return a disabled scope until the exact same code is proven again.
    if (code == null || code.isEmpty) return _unknown;
    if (_knownCode != code) {
      _knownCode = code;
      _drafts = InvoicePaymentMethodDrafts(enabled: enabled);
    }
    return _drafts!;
  }
}

class InvoicePaymentMethodDrafts {
  InvoicePaymentMethodDrafts({required this.enabled});

  final bool enabled;
  final _methods = <String, String>{};

  String? selected(String invoiceId) => enabled ? _methods[invoiceId] : null;

  void select(String invoiceId, String method) {
    if (!enabled) return;
    // Bound a long-lived session without storing payment details or credentials.
    if (!_methods.containsKey(invoiceId) && _methods.length >= 128) {
      _methods.remove(_methods.keys.first);
    }
    _methods[invoiceId] = method;
  }
}
