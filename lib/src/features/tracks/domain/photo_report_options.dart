class PhotoReportOption {
  final bool enabled;
  final String priceUsd;

  const PhotoReportOption({required this.enabled, required this.priceUsd});

  factory PhotoReportOption.fromJson(Map<String, dynamic> json) =>
      PhotoReportOption(
        enabled: json['enabled'] == true,
        priceUsd: '${json['priceUsd'] ?? '0'}',
      );

  double get price => double.tryParse(priceUsd) ?? 0;
}

class PhotoReportOptions {
  final PhotoReportOption standard;
  final PhotoReportOption custom;

  const PhotoReportOptions({required this.standard, required this.custom});

  factory PhotoReportOptions.fromJson(Map<String, dynamic> json) =>
      PhotoReportOptions(
        standard: PhotoReportOption.fromJson(
          Map<String, dynamic>.from(json['standard'] as Map? ?? {}),
        ),
        custom: PhotoReportOption.fromJson(
          Map<String, dynamic>.from(json['custom'] as Map? ?? {}),
        ),
      );

  PhotoReportOption option(String type) => type == 'custom' ? custom : standard;
}

class PhotoReportSelection {
  final String reportType;
  final String? wish;
  final String expectedPriceUsd;
  final String? loyaltyRewardType;

  const PhotoReportSelection(
    this.reportType,
    this.wish,
    this.expectedPriceUsd, {
    this.loyaltyRewardType,
  });
}
