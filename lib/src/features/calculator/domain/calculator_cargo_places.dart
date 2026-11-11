/// One physical cargo place. Dimensions are in centimetres, weight in kilograms.
class CargoPlaceDimensions {
  const CargoPlaceDimensions({
    required this.lengthCm,
    required this.widthCm,
    required this.heightCm,
    required this.weightKg,
  });

  final double lengthCm;
  final double widthCm;
  final double heightCm;
  final double weightKg;
}

class CargoPlacesTotals {
  const CargoPlacesTotals({
    required this.weightKg,
    required this.volumeM3,
    required this.placesCount,
  });

  final double weightKg;
  final double volumeM3;
  final int placesCount;
}

/// Incomplete/invalid places never produce a partial usable aggregate.
CargoPlacesTotals? calculateCargoPlacesTotals(
  List<CargoPlaceDimensions> places,
) {
  if (places.isEmpty) return null;
  var weight = 0.0;
  var volume = 0.0;
  for (final place in places) {
    for (final value in [
      place.lengthCm,
      place.widthCm,
      place.heightCm,
      place.weightKg,
    ]) {
      if (!value.isFinite || value <= 0) return null;
    }
    final placeVolume = place.lengthCm * place.widthCm * place.heightCm / 1e6;
    if (!placeVolume.isFinite || placeVolume <= 0) return null;
    weight += place.weightKg;
    volume += placeVolume;
    if (!weight.isFinite || !volume.isFinite) return null;
  }
  return CargoPlacesTotals(
    weightKg: weight,
    volumeM3: volume,
    placesCount: places.length,
  );
}
