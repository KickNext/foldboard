import 'package:flutter/material.dart';

import '../../../../app_info.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../domain/models/app_settings.dart';
import '../../../../l10n/l10n.dart';
import '../../../../webmcp/webmcp_bridge.dart';
import '../../../core/app_theme.dart';
import '../../../core/page_feedback.dart';
import '../../../core/segmented_picker.dart';
import '../../../core/shortcuts_dialog.dart';
import '../../../core/write_access_scope.dart';
import '../view_models/settings_view_model.dart';

class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = SettingsScope.maybeOf(context);
    if (vm == null) return const SizedBox.shrink();
    return IconButton(
      key: const Key('open-settings'),
      tooltip: context.l10n.settings,
      icon: const Icon(Icons.settings_outlined, size: 20),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SettingsPage(viewModel: vm)),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.viewModel, this.status});
  final SettingsViewModel viewModel;

  /// Injected in tests; the real bridge is only present on the web build.
  final McpStatus? status;

  Future<void> _reset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.resetSettings),
        content: Text(context.l10n.resetSettingsHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.reset),
          ),
        ],
      ),
    );
    if (confirmed == true) viewModel.reset();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final writable = WriteAccessScope.canWriteOf(context);
      final editable = viewModel.canEdit && writable;
      final warning = switch (viewModel.failure) {
        SettingsFailure.read => context.l10n.settingsReadFailed,
        SettingsFailure.write => context.l10n.settingsWriteFailed,
        null => WriteAccessScope.warningOf(context),
      };
      final mcp = status ?? WebMcpBridge.status;
      return Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.settings),
          actions: [
            PageInfoButton(
              key: const Key('settings-info'),
              message: warning ?? context.l10n.settingsLocalHint,
              warning: warning != null,
            ),
          ],
        ),
        body: PageFeedback(
          message: warning,
          ticket: viewModel.feedbackVersion,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
                children: [
                  _Section(
                    title: context.l10n.appearance,
                    children: [
                      _Field(
                        label: context.l10n.theme,
                        child: SegmentedPicker<Appearance>(
                          key: const Key('appearance-picker'),
                          value: viewModel.value.appearance,
                          options: [
                            (Appearance.dark, context.l10n.darkTheme),
                            (Appearance.light, context.l10n.lightTheme),
                            (Appearance.system, context.l10n.systemTheme),
                          ],
                          onChanged: editable ? viewModel.setAppearance : null,
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    title: context.l10n.rootLevel,
                    children: [
                      SwitchListTile(
                        key: const Key('show-grid'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.l10n.showGrid),
                        subtitle: Text(context.l10n.showGridHint),
                        value: viewModel.showGrid,
                        onChanged: editable ? viewModel.setShowGrid : null,
                      ),
                    ],
                  ),
                  _Section(
                    title: context.l10n.agents,
                    children: [
                      _Field(
                        label: context.l10n.agentReadOnly,
                        child: SegmentedButton<bool>(
                          key: const Key('agent-access'),
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: true,
                              icon: const Icon(Icons.visibility_outlined),
                              label: Text(context.l10n.agentViewOnly),
                            ),
                            ButtonSegment(
                              value: false,
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(context.l10n.agentViewAndEdit),
                            ),
                          ],
                          selected: {viewModel.value.agentReadOnly},
                          onSelectionChanged: editable
                              ? (values) =>
                                    viewModel.setAgentReadOnly(values.single)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            viewModel.value.agentReadOnly
                                ? Icons.lock_outline
                                : Icons.edit_note_outlined,
                            size: 17,
                            color: viewModel.value.agentReadOnly
                                ? context.colors.muted
                                : context.colors.accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              viewModel.value.agentReadOnly
                                  ? context.l10n.agentReadOnlyHint
                                  : context.l10n.agentCanEditHint,
                              style: context.type.bodySmall!.copyWith(
                                color: context.colors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  _Section(
                    title: context.l10n.about,
                    children: [
                      _AboutRow(
                        label: context.l10n.version,
                        value: AppInfo.appVersion,
                      ),
                      _AboutRow(
                        label: context.l10n.agentConnection,
                        value: mcp.available
                            ? context.l10n.webMcpConnected(mcp.registered)
                            : context.l10n.agentConnectionUnavailable,
                      ),
                      ExpansionTile(
                        key: const Key('technical-details'),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        shape: const Border(),
                        collapsedShape: const Border(),
                        title: Text(
                          context.l10n.technicalDetails,
                          style: context.type.bodySmall,
                        ),
                        children: [
                          _AboutRow(
                            key: const Key('about-webmcp'),
                            label: context.l10n.webMcp,
                            value: mcp.available
                                ? context.l10n.webMcpConnected(mcp.registered)
                                : context.l10n.webMcpUnavailable,
                          ),
                        ],
                      ),
                      _AboutRow(
                        label: context.l10n.storageLabel,
                        value: context.l10n.storageAboutHint,
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          key: const Key('open-shortcuts'),
                          onPressed: () =>
                              KeyboardShortcutsDialog.show(context),
                          icon: const Icon(Icons.keyboard_outlined, size: 18),
                          label: Text(context.l10n.keyboardShortcuts),
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    title: context.l10n.dangerZone,
                    children: [
                      Text(
                        context.l10n.resetSettingsHint,
                        style: context.type.bodySmall!.copyWith(
                          color: context.colors.muted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          key: const Key('reset-settings'),
                          onPressed: writable ? () => _reset(context) : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.colors.danger,
                            side: BorderSide(
                              color: context.colors.danger.withValues(
                                alpha: .6,
                              ),
                            ),
                          ),
                          child: Text(context.l10n.resetSettings),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 36),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.type.titleLarge),
        const SizedBox(height: 4),
        Divider(color: context.colors.line, height: 17),
        ...children,
      ],
    ),
  );
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: context.type.labelMedium!.copyWith(
              color: context.colors.muted,
            ),
          ),
        ),
        Expanded(child: Text(value, style: context.type.bodySmall)),
      ],
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: context.type.labelMedium!.copyWith(color: context.colors.muted),
      ),
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerLeft, child: child),
    ],
  );
}
