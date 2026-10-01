/// A maximum-elevation filter option, e.g. "do 1500 m" matches every peak up
/// to (and including) 1500 m.
class ElevationBracket {
  final String label;
  final int maxM;

  const ElevationBracket({required this.label, required this.maxM});

  bool matches(int? elevationM) => elevationM != null && elevationM <= maxM;

  static const List<ElevationBracket> all = [
    ElevationBracket(label: 'do 1000 m', maxM: 1000),
    ElevationBracket(label: 'do 1500 m', maxM: 1500),
    ElevationBracket(label: 'do 2000 m', maxM: 2000),
  ];
}
