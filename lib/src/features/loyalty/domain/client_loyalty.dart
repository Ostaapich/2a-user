class LoyaltyReward {
  final int cost;
  final bool enabled;

  const LoyaltyReward({required this.cost, required this.enabled});
}

class LoyaltyThreshold {
  final String tier;
  final double kg;
  final int shipments;

  const LoyaltyThreshold(this.tier, this.kg, this.shipments);
}

class LoyaltyGift {
  final String id;
  final String tier;
  final String status;

  const LoyaltyGift(this.id, this.tier, this.status);
}

/// Optional v1 capability. Unknown versions or incomplete money-like balances
/// are rejected, so an older backend never changes the ordinary paid flow.
class ClientLoyalty {
  static const tiers = ['base', 'silver', 'gold', 'platinum'];
  final int balance;
  final String tier;
  final double shippedKg;
  final int shipments;
  final int shippingDays;
  final int windowDays;
  final int pendingTracksMissingProductInfo;
  final int assembliesMissingDelivery;
  final List<LoyaltyThreshold> thresholds;
  final LoyaltyReward photo;
  final LoyaltyReward video;
  final List<LoyaltyGift> gifts;

  const ClientLoyalty({
    required this.balance,
    required this.tier,
    required this.shippedKg,
    required this.shipments,
    required this.shippingDays,
    required this.windowDays,
    this.pendingTracksMissingProductInfo = 0,
    this.assembliesMissingDelivery = 0,
    required this.thresholds,
    required this.photo,
    required this.video,
    required this.gifts,
  });

  LoyaltyReward reward(String type) => type == 'video' ? video : photo;

  bool canRedeem(String type) =>
      const ['photo', 'video'].contains(type) &&
      reward(type).enabled &&
      balance >= reward(type).cost;

  bool canClaim(String giftTier) =>
      tiers.contains(giftTier) &&
      giftTier != 'base' &&
      tiers.indexOf(tier) >= tiers.indexOf(giftTier) &&
      !gifts.any((gift) => gift.tier == giftTier);

  static ClientLoyalty? tryParse(dynamic value) {
    if (value is! Map || value['enabled'] != true || value['version'] != 1) {
      return null;
    }
    try {
      final balance = _integer(value['balance']);
      final tier = value['tier'];
      if (!tiers.contains(tier)) return null;
      final metrics = value['metrics'] as Map;
      final rewards = value['rewards'] as Map;
      final quality = value['quality'] == null
          ? const <String, dynamic>{}
          : value['quality'] as Map;
      LoyaltyReward parseReward(String type, int expected) {
        final reward = rewards[type] as Map;
        if (_integer(reward['cost']) != expected ||
            reward['enabled'] is! bool) {
          throw const FormatException('Unsupported reward');
        }
        return LoyaltyReward(
          cost: expected,
          enabled: reward['enabled'] == true,
        );
      }

      final thresholds = (value['thresholds'] as List).map((item) {
        final row = item as Map;
        if (!tiers.skip(1).contains(row['tier'])) {
          throw const FormatException('Unsupported tier');
        }
        return LoyaltyThreshold(
          row['tier'] as String,
          _number(row['kg']),
          _integer(row['shipments']),
        );
      }).toList();
      if (thresholds.length != 3 ||
          thresholds.map((t) => t.tier).toSet().length != 3) {
        return null;
      }
      final gifts = (value['gifts'] as List).map((item) {
        final row = item as Map;
        if (row['id'] is! String ||
            !tiers.skip(1).contains(row['tier']) ||
            !const ['requested', 'fulfilled'].contains(row['status'])) {
          throw const FormatException('Invalid gift');
        }
        return LoyaltyGift(
          row['id'] as String,
          row['tier'] as String,
          row['status'] as String,
        );
      }).toList();
      return ClientLoyalty(
        balance: balance,
        tier: tier as String,
        shippedKg: _number(metrics['shippedKg']),
        shipments: _integer(metrics['shipments']),
        shippingDays: _integer(metrics['shippingDays']),
        windowDays: _integer(metrics['windowDays']),
        pendingTracksMissingProductInfo: _integer(
          quality['pendingTracksMissingProductInfo'] ?? 0,
        ),
        assembliesMissingDelivery: _integer(
          quality['assembliesMissingDelivery'] ?? 0,
        ),
        thresholds: List.unmodifiable(thresholds),
        photo: parseReward('photo', 5),
        video: parseReward('video', 10),
        gifts: List.unmodifiable(gifts),
      );
    } catch (_) {
      return null;
    }
  }

  static int _integer(dynamic value) {
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        value != value.roundToDouble()) {
      throw const FormatException('Invalid integer');
    }
    return value.toInt();
  }

  static double _number(dynamic value) {
    if (value is! num || !value.isFinite || value < 0) {
      throw const FormatException('Invalid number');
    }
    return value.toDouble();
  }
}
