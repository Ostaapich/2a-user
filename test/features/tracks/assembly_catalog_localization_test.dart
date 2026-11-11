import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/data/assemblies_provider.dart';

void main() {
  test(
    'catalogs prefer explicit API nameZh in Chinese and retain Russian fallback',
    () {
      final packaging = PackagingType.fromJson({
        'id': 1,
        'name': 'Box',
        'nameRu': 'Картонная коробка',
        'nameZh': '纸箱',
        'baseCost': 7,
      });
      expect(packaging.localizedName(true), '纸箱');
      expect(packaging.localizedName(false), 'Картонная коробка');
      final tariff = Tariff.fromJson({
        'id': 2,
        'name': 'Авто',
        'nameZh': '汽运',
        'baseCost': 3,
      });
      expect(tariff.localizedName(true), '汽运');
      expect(tariff.localizedName(false), 'Авто');
      expect(
        const PackagingType(
          id: 1,
          name: 'Original',
          nameZh: ' ',
        ).localizedName(true),
        'Original',
      );
      expect(
        const Tariff(id: 2, name: 'Original', baseCost: 3).localizedName(true),
        'Original',
      );
    },
  );
}
