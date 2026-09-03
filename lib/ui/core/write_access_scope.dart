import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// Access state is inherited, never inserted as a layout-changing banner.
class WriteAccessScope extends InheritedWidget {
  const WriteAccessScope({
    super.key,
    required this.canWrite,
    required super.child,
  });
  final bool canWrite;
  static bool canWriteOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WriteAccessScope>()
          ?.canWrite ??
      true;
  static String? warningOf(BuildContext context) =>
      context
              .dependOnInheritedWidgetOfExactType<WriteAccessScope>()
              ?.canWrite ==
          false
      ? context.l10n.readOnlyHint
      : null;
  @override
  bool updateShouldNotify(WriteAccessScope oldWidget) =>
      canWrite != oldWidget.canWrite;
}
