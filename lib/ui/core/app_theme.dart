import 'package:flutter/material.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.line,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentDark,
    required this.edge,
    required this.edgeMuted,
    required this.danger,
    required this.warning,
    required this.onWarning,
  });
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color line;
  final Color text;
  final Color muted;
  final Color accent;
  final Color accentDark;
  final Color edge;
  final Color edgeMuted;
  final Color danger;
  final Color warning;
  final Color onWarning;
  static const dark = AppPalette(
    background: Color(0xFF111310),
    surface: Color(0xFF181B17),
    surfaceHigh: Color(0xFF20231E),
    line: Color(0xFF30342D),
    text: Color(0xFFF2F4EE),
    muted: Color(0xFF90968A),
    accent: Color(0xFFB6F36B),
    accentDark: Color(0xFF26351B),
    edge: Color(0xFF8B947C),
    edgeMuted: Color(0xFF40453D),
    danger: Color(0xFFE38A86),
    warning: Color(0xFF483028),
    onWarning: Color(0xFFFFE1CC),
  );
  // Light keeps the same confidence of line as dark: card borders and idle
  // arrows sit several steps below the ground colour, not one.
  static const light = AppPalette(
    background: Color(0xFFF5F7F2),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEAF0E3),
    line: Color(0xFFB7C2AB),
    text: Color(0xFF20261B),
    muted: Color(0xFF5F6A55),
    accent: Color(0xFF476B16),
    accentDark: Color(0xFFE1EED0),
    edge: Color(0xFF64744F),
    edgeMuted: Color(0xFF97A587),
    danger: Color(0xFFB3261E),
    warning: Color(0xFFFFE4CA),
    onWarning: Color(0xFF4B2B13),
  );
  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceHigh,
    Color? line,
    Color? text,
    Color? muted,
    Color? accent,
    Color? accentDark,
    Color? edge,
    Color? edgeMuted,
    Color? danger,
    Color? warning,
    Color? onWarning,
  }) => AppPalette(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceHigh: surfaceHigh ?? this.surfaceHigh,
    line: line ?? this.line,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    accent: accent ?? this.accent,
    accentDark: accentDark ?? this.accentDark,
    edge: edge ?? this.edge,
    edgeMuted: edgeMuted ?? this.edgeMuted,
    danger: danger ?? this.danger,
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
  );
  @override
  AppPalette lerp(covariant AppPalette? other, double t) => other == null
      ? this
      : AppPalette(
          background: Color.lerp(background, other.background, t)!,
          surface: Color.lerp(surface, other.surface, t)!,
          surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
          line: Color.lerp(line, other.line, t)!,
          text: Color.lerp(text, other.text, t)!,
          muted: Color.lerp(muted, other.muted, t)!,
          accent: Color.lerp(accent, other.accent, t)!,
          accentDark: Color.lerp(accentDark, other.accentDark, t)!,
          edge: Color.lerp(edge, other.edge, t)!,
          edgeMuted: Color.lerp(edgeMuted, other.edgeMuted, t)!,
          danger: Color.lerp(danger, other.danger, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
          onWarning: Color.lerp(onWarning, other.onWarning, t)!,
        );
}

extension AppThemeContext on BuildContext {
  AppPalette get colors =>
      Theme.of(this).extension<AppPalette>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? AppPalette.dark
          : AppPalette.light);
  TextTheme get type => Theme.of(this).textTheme;
}

abstract final class AppTheme {
  static const portalTransition = Duration(milliseconds: 420);
  static const portalHover = Duration(milliseconds: 260);
  // Navigation starts at rest, accelerates, then settles without overshoot.
  static const portalCurve = Cubic(.2, 0, .2, 1);
  static const portalHoverCurve = Cubic(.22, .8, .18, 1);
  static const portalExitVeil = Interval(.4, .65, curve: Curves.easeInOutCubic);
  static const portalExitReveal = Interval(
    .65,
    .95,
    curve: Curves.easeOutCubic,
  );
  static const arrowStroke = 1.7;
  static const edgeIgnition = Duration(milliseconds: 480);
  static const edgeIgnitionCurve = Curves.easeInOutCubic;
  static const arrowSelectedStroke = 2.3;
  static const arrowHeadLength = 9.0;
  static const arrowHeadHalfWidth = 4.5;
  static const radiusSmall = 5.0;
  static const radiusControl = 8.0;
  static const radiusCard = 10.0;
  static const radiusProcessCard = 24.0;
  static const mirrorInset = 12.0;
  static const mirrorMinRadius = 2.0;
  static const referencePortalExtent = 20.0;
  static BoxDecoration referenceCard(
    BuildContext context, {
    required bool active,
  }) {
    final p = context.colors;
    return BoxDecoration(
      color: p.surface,
      borderRadius: BorderRadius.circular(radiusCard),
      border: Border.all(
        color: active
            ? p.accent
            : Color.alphaBlend(p.accent.withValues(alpha: .38), p.line),
        width: active ? 1.5 : 1,
      ),
    );
  }

  static const radiusDialog = 12.0;
  static const radiusFloating = 12.0;
  static const panelEnter = Duration(milliseconds: 280);
  static const panelExit = Duration(milliseconds: 200);
  static const panelSwap = Duration(milliseconds: 320);
  static const inspectorTitle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -.7,
    height: 1.2,
  );

  static BoxDecoration inspectorSheet(BuildContext context) {
    final p = context.colors;
    return BoxDecoration(
      gradient: RadialGradient(
        center: Alignment.topRight,
        radius: 1.1,
        colors: [
          Color.alphaBlend(p.accent.withValues(alpha: .07), p.surface),
          p.surface,
        ],
        stops: const [0, .75],
      ),
    );
  }

  static InputDecoration inspectorInput(
    BuildContext context, {
    required bool title,
  }) {
    final p = context.colors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusDialog),
      borderSide: BorderSide(color: p.line.withValues(alpha: .65)),
    );
    return InputDecoration(
      filled: true,
      fillColor: p.background.withValues(alpha: title ? .45 : .7),
      isDense: true,
      contentPadding: title
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
          : const EdgeInsets.all(16),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: p.accent, width: 1.5),
      ),
    );
  }

  static BoxDecoration floatingPanel(BuildContext context) {
    final p = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cast = dark ? p.background : p.text;
    // Two tight shadows read as a lifted surface; one wide blur reads as a
    // Material elevation overlay.
    return BoxDecoration(
      color: p.surface,
      borderRadius: BorderRadius.circular(radiusFloating),
      border: Border.all(color: p.line.withValues(alpha: .8)),
      boxShadow: [
        BoxShadow(
          color: cast.withValues(alpha: dark ? .40 : .05),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: cast.withValues(alpha: dark ? .34 : .07),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  static const canvasLabel = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
  );
  static const zoomLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const searchStyle = TextStyle(fontSize: 11);
  static ThemeData get dark => _build(Brightness.dark, AppPalette.dark);
  static ThemeData get light => _build(Brightness.light, AppPalette.light);

  static ButtonStyle _button(
    AppPalette p,
    OutlinedBorder shape,
    TextTheme text, {
    required Color foreground,
    Color? background,
    Color? disabledBackground,
    BorderSide? border,
  }) => ButtonStyle(
    splashFactory: NoSplash.splashFactory,
    elevation: const WidgetStatePropertyAll(0),
    shape: WidgetStatePropertyAll(shape),
    textStyle: WidgetStatePropertyAll(text.labelLarge),
    iconSize: const WidgetStatePropertyAll(17),
    minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 13)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? disabledBackground
          : background,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? p.muted.withValues(alpha: .55)
          : foreground,
    ),
    overlayColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.pressed)
          ? foreground.withValues(alpha: .16)
          : states.contains(WidgetState.hovered)
          ? foreground.withValues(alpha: .09)
          : null,
    ),
    // A visible ring, not a tint: this board is driven from the keyboard.
    side: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: p.accent, width: 2)
          : border,
    ),
  );

  static ThemeData _build(Brightness brightness, AppPalette p) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: p.accent,
          brightness: brightness,
        ).copyWith(
          primary: p.accent,
          onPrimary: brightness == Brightness.dark ? p.background : p.surface,
          primaryContainer: p.accentDark,
          onPrimaryContainer: p.text,
          surface: p.surface,
          onSurface: p.text,
          onSurfaceVariant: p.muted,
          surfaceContainer: p.surfaceHigh,
          surfaceContainerHigh: p.surfaceHigh,
          outline: p.line,
          outlineVariant: p.line,
          error: p.danger,
          errorContainer: p.warning,
          onErrorContainer: p.onWarning,
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusControl),
    );
    // Only 400/600/700 are bundled; nothing here may ask for another weight or
    // CanvasKit will synthesise it. Tracking tightens as size grows, which is
    // what keeps Inter from reading like a UI toolkit default.
    final text = const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        letterSpacing: -.8,
        height: 1.15,
      ),
      titleLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -.35,
        height: 1.25,
      ),
      titleMedium: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        letterSpacing: -.15,
      ),
      bodyLarge: TextStyle(fontSize: 13.5, height: 1.45, letterSpacing: -.05),
      bodyMedium: TextStyle(fontSize: 13, height: 1.45, letterSpacing: -.05),
      bodySmall: TextStyle(fontSize: 12.5, height: 1.5),
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: -.1,
      ),
      labelMedium: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: .35,
      ),
      labelSmall: TextStyle(fontSize: 11.5, height: 1.4),
    ).apply(bodyColor: p.text, displayColor: p.text);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [p],
      scaffoldBackgroundColor: p.background,
      // DropdownButton menus paint on canvasColor; without this they fall back
      // to the Material grey and ignore the palette.
      canvasColor: p.surfaceHigh,
      fontFamily: 'Inter',
      // The expanding ink ripple is the loudest Material tell. Flat hover and
      // pressed tints read as a web app; every component inherits this.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: p.text.withValues(alpha: .045),
      focusColor: p.accent.withValues(alpha: .12),
      textTheme: text,
      iconTheme: IconThemeData(color: p.muted, size: 19),
      dividerColor: p.line,
      dividerTheme: DividerThemeData(color: p.line, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: p.line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusDialog),
          side: BorderSide(color: p.line),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
        titleTextStyle: text.titleLarge!.copyWith(color: p.text),
        contentTextStyle: text.bodySmall!.copyWith(color: p.muted),
      ),
      popupMenuTheme: PopupMenuThemeData(color: p.surfaceHigh, shape: shape),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.surfaceHigh),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStatePropertyAll(BorderSide(color: p.line)),
          shape: WidgetStatePropertyAll(shape),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _button(
          p,
          shape,
          text,
          foreground: scheme.onPrimary,
          background: p.accent,
          disabledBackground: p.surfaceHigh,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _button(
          p,
          shape,
          text,
          foreground: p.text,
          border: BorderSide(color: p.line),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _button(p, shape, text, foreground: p.accent),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          splashFactory: NoSplash.splashFactory,
          shape: WidgetStatePropertyAll(shape),
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed)
                ? p.text.withValues(alpha: .10)
                : states.contains(WidgetState.hovered)
                ? p.text.withValues(alpha: .06)
                : null,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? BorderSide(color: p.accent, width: 2)
                : null,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbIcon: const WidgetStatePropertyAll(null),
        splashRadius: 0,
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? p.accent : p.surfaceHigh,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? p.accent : p.line,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : p.muted,
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
        iconColor: p.muted,
        textColor: p.text,
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodySmall!.copyWith(color: p.muted),
        horizontalTitleGap: 14,
      ),
      // Overlay scrollbars: present on hover, never a grey Material gutter.
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(8),
        interactive: true,
        crossAxisMargin: 2,
        mainAxisMargin: 6,
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
        trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.dragged)
              ? p.muted.withValues(alpha: .75)
              : p.line,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.surfaceHigh,
        contentTextStyle: text.bodyMedium!.copyWith(color: p.text),
        actionTextColor: p.accent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: p.line),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.text,
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        textStyle: text.bodySmall!.copyWith(color: p.background),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.background,
        isDense: true,
        labelStyle: text.bodySmall!.copyWith(color: p.muted),
        hintStyle: text.bodyMedium!.copyWith(color: p.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: p.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: p.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: p.accent),
        ),
      ),
    );
  }
}
