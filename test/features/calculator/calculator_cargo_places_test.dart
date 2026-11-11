import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/calculator/domain/calculator_cargo_places.dart';

CargoPlaceDimensions place({
  double length = 100,
  double width = 40,
  double height = 30,
  double weight = 6,
}) => CargoPlaceDimensions(
  lengthCm: length,
  widthCm: width,
  heightCm: height,
  weightKg: weight,
);
void main() {
  test(
    'mixed cargo sizes aggregate each volume and weight with one row per place',
    () {
      final result = calculateCargoPlacesTotals([
        place(),
        place(length: 20, width: 20, height: 10, weight: 4),
      ])!;
      expect(result.weightKg, 10);
      expect(result.volumeM3, closeTo(.124, 1e-12));
      expect(result.placesCount, 2);
    },
  );
  test('fractional positive dimensions remain valid', () {
    final result = calculateCargoPlacesTotals([
      place(length: .1, width: .2, height: .3, weight: .5),
    ])!;
    expect(result.volumeM3, closeTo(6e-9, 1e-20));
    expect(result.weightKg, .5);
    expect(result.placesCount, 1);
  });
  test('empty cargo is incomplete', () {
    expect(calculateCargoPlacesTotals([]), isNull);
  });
  for (final value in [
    0.0,
    -1.0,
    double.nan,
    double.infinity,
    double.negativeInfinity,
  ]) {
    for (final field in ['length', 'width', 'height', 'weight']) {
      test(
        'invalid $field=$value rejects entire aggregate including valid first row',
        () {
          final invalid = place(
            length: field == 'length' ? value : 1,
            width: field == 'width' ? value : 1,
            height: field == 'height' ? value : 1,
            weight: field == 'weight' ? value : 1,
          );
          expect(calculateCargoPlacesTotals([place(), invalid]), isNull);
        },
      );
    }
  }
  test('dimension multiplication overflow rejects cargo', () {
    expect(
      calculateCargoPlacesTotals([place(length: 1e308, width: 2)]),
      isNull,
    );
  });
  test('total weight overflow rejects otherwise valid individual rows', () {
    expect(
      calculateCargoPlacesTotals([place(weight: 1e308), place(weight: 1e308)]),
      isNull,
    );
  });
  test('volume underflow cannot masquerade as zero-volume valid cargo', () {
    expect(
      calculateCargoPlacesTotals([
        place(length: double.minPositive, width: 1, height: 1),
      ]),
      isNull,
    );
  });
}
