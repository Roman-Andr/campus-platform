/// Persisted independently from brightness. Names are stable storage IDs.
enum PaletteId {
  lavender,
  sage,
  sky,
  peach;

  static PaletteId parse(String? value) =>
      values.firstWhere((id) => id.name == value, orElse: () => lavender);
}
