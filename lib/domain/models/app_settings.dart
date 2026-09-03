enum Appearance { dark, light, system }

class AppSettings {
  const AppSettings({
    this.appearance = Appearance.dark,
    this.showGrid = true,
    this.agentReadOnly = false,
  });
  final Appearance appearance;
  final bool showGrid;
  final bool agentReadOnly;
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      appearance: Appearance.values.byName(json['appearance'] as String),
      showGrid: json['showGrid'] as bool,
      agentReadOnly: json['agentReadOnly'] as bool,
    );
  }
  Map<String, dynamic> toJson() => {
    'appearance': appearance.name,
    'showGrid': showGrid,
    'agentReadOnly': agentReadOnly,
  };
  AppSettings copyWith({
    Appearance? appearance,
    bool? showGrid,
    bool? agentReadOnly,
  }) => AppSettings(
    appearance: appearance ?? this.appearance,
    showGrid: showGrid ?? this.showGrid,
    agentReadOnly: agentReadOnly ?? this.agentReadOnly,
  );
}
