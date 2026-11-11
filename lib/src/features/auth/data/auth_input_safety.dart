String normalizeAuthEmail(String value) => value.trim().toLowerCase();

bool isValidAuthEmail(String value) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());

/// Uses the deadline, so suspension and delayed timer callbacks do not extend it.
int verificationSecondsLeft(DateTime expiresAt, {DateTime? now}) {
  final millis = expiresAt.difference(now ?? DateTime.now()).inMilliseconds;
  return millis <= 0 ? 0 : (millis / 1000).ceil();
}

/// One in-memory return address. External URLs and authentication screens are
/// never accepted; the router's own destination still validates entity access.
class PendingAuthDestination {
  String? _location;

  void remember(Uri uri) {
    if (uri.hasScheme || uri.hasAuthority || uri.hasFragment) return;
    if (!uri.path.startsWith('/') || uri.path.contains('\\')) return;
    const roots = {
      'photos',
      'tracks',
      'invoices',
      'support',
      'training',
      'calculator',
      'search-nocode',
      'payment-chat',
      'news',
      'profile',
      'rules',
      'referral',
      'partner-program',
      'tariffs',
      'shop',
      'sp-finance',
      'garage',
      'self-buyout',
      'purchase-blanks',
    };
    if (uri.pathSegments.isEmpty || !roots.contains(uri.pathSegments.first)) {
      return;
    }
    _location = uri.toString();
  }

  String? take() {
    final location = _location;
    _location = null;
    return location;
  }
}
