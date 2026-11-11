/// Device-session draft of one client/code/track selection. Never persisted
/// with credentials, and never shared between account scopes.
class AssemblyFormDraft {
  AssemblyFormDraft({
    this.tariffId,
    Set<int> packagingIds = const {},
    this.fragile = false,
    this.placePreference,
    this.insured = false,
    this.insuranceAmount = '',
    this.goodsDescription = '',
    this.step = 0,
  }) : packagingIds = Set.unmodifiable(packagingIds);

  final int? tariffId;
  final Set<int> packagingIds;
  final bool fragile;
  final String? placePreference;
  final bool insured;
  final String insuranceAmount;
  final String goodsDescription;
  final int step;
}
