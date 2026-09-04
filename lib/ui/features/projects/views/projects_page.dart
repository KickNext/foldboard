import 'package:flutter/material.dart';

import '../../../../data/repositories/projects_repository.dart';
import '../../../../domain/models/project.dart';
import '../../../../l10n/l10n.dart';
import '../../../../webmcp/foldboard_webmcp.dart';
import '../../../core/app_theme.dart';
import '../../../core/page_feedback.dart';
import '../../../core/write_access_scope.dart';
import '../../planner/views/planner_page.dart';
import '../view_models/projects_view_model.dart';
import '../../settings/views/settings_page.dart';

class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key, required this.viewModel});
  final ProjectsViewModel viewModel;

  Future<void> _removeProject(BuildContext context, Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.removeProject),
        content: Text(context.l10n.removeProjectHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.removeProject),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !context.mounted ||
        !viewModel.remove(project.id)) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.projectRemoved),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: context.l10n.restoreProject,
          onPressed: () => viewModel.restore(project),
        ),
      ),
    );
  }

  Future<void> _duplicateProject(BuildContext context, Project project) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _ProjectNameDialog(
        title: context.l10n.duplicateProject,
        confirmLabel: context.l10n.duplicateProject,
        initialName: context.l10n.projectCopyName(project.name),
      ),
    );
    if (name == null || !context.mounted) return;
    viewModel.duplicate(project.id, name);
  }

  Future<void> _nameProject(BuildContext context, [Project? project]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _ProjectNameDialog(
        title: project == null
            ? context.l10n.newProject
            : context.l10n.renameProject,
        confirmLabel: project == null
            ? context.l10n.createProject
            : context.l10n.save,
        initialName: project?.name ?? '',
      ),
    );
    if (name == null || !context.mounted) return;
    if (project == null) {
      viewModel.create(name);
    } else {
      viewModel.rename(project.id, name);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final planner = viewModel.planner;
      final canEdit =
          viewModel.repository.canEdit && WriteAccessScope.canWriteOf(context);
      final warning = viewModel.warning ?? WriteAccessScope.warningOf(context);
      final starterProject = viewModel.projects.length == 1
          ? viewModel.projects.first
          : null;
      final starterSummary = starterProject == null
          ? null
          : viewModel.summary(starterProject.id);
      final showGettingStarted =
          starterProject != null &&
          starterSummary != null &&
          starterSummary.blocks == 0 &&
          starterSummary.processes == 0 &&
          starterSummary.arrows == 0;
      final page = planner != null
          ? PlannerPage(
              key: ValueKey(viewModel.activeProject!.id),
              viewModel: planner,
              projectTitle: viewModel.activeProject!.name,
              onProjects: viewModel.showProjects,
              externalWarning: warning,
              externalTicket: viewModel.feedbackVersion,
            )
          : Scaffold(
              appBar: AppBar(
                actions: [
                  if (!canEdit) Text(context.l10n.readOnly),
                  PageInfoButton(
                    key: const Key('projects-info'),
                    message: warning ?? context.l10n.projectsLocalHint,
                    warning: warning != null,
                  ),
                  const SettingsButton(),
                ],
                title: const Text('Foldboard'),
                automaticallyImplyLeading: false,
              ),
              body: PageFeedback(
                message: warning,
                ticket: viewModel.feedbackVersion,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 24,
                          runSpacing: 16,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.projects,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  context.l10n.exampleProjectHint,
                                  style: context.type.bodySmall!.copyWith(
                                    color: context.colors.muted,
                                  ),
                                ),
                              ],
                            ),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                OutlinedButton.icon(
                                  key: const Key('explore-example'),
                                  onPressed: canEdit
                                      ? viewModel.openExample
                                      : null,
                                  icon: const Icon(
                                    Icons.auto_awesome_outlined,
                                    size: 18,
                                  ),
                                  label: Text(context.l10n.exploreExample),
                                ),
                                FilledButton.icon(
                                  key: const Key('new-project'),
                                  onPressed: canEdit
                                      ? () => _nameProject(context)
                                      : null,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: Text(context.l10n.newProject),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        if (showGettingStarted) ...[
                          _GettingStarted(
                            onOpen: () => viewModel.open(starterProject.id),
                          ),
                          const SizedBox(height: 24),
                        ] else
                          const SizedBox(height: 8),
                        if (viewModel.projects.isEmpty) const _NoProjects(),
                        for (final project in viewModel.projects)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                key: ValueKey('project-${project.id}'),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                leading: const Icon(Icons.folder_outlined),
                                title: Text(
                                  project.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: _ProjectSummaryLine(
                                  summary: viewModel.summary(project.id),
                                ),
                                onTap: () => viewModel.open(project.id),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      key: ValueKey(
                                        'rename-project-${project.id}',
                                      ),
                                      tooltip: context.l10n.renameProject,
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 19,
                                      ),
                                      onPressed: canEdit
                                          ? () => _nameProject(context, project)
                                          : null,
                                    ),
                                    PopupMenuButton<String>(
                                      enabled: canEdit,
                                      key: ValueKey(
                                        'project-actions-${project.id}',
                                      ),
                                      tooltip: context.l10n.moreActions,
                                      onSelected: (value) => value == 'remove'
                                          ? _removeProject(context, project)
                                          : _duplicateProject(context, project),
                                      itemBuilder: (_) => [
                                        PopupMenuItem(
                                          value: 'duplicate',
                                          child: Text(
                                            context.l10n.duplicateProject,
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'remove',
                                          child: Text(
                                            context.l10n.removeProject,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
      return FoldboardWebMcpScopes(
        catalog: viewModel.webMcp,
        boardEnabled: planner != null,
        requestsEnabled: planner != null && !planner.requests.loadFailed,
        child: page,
      );
    },
  );
}

class _ProjectNameDialog extends StatefulWidget {
  const _ProjectNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialName,
  });
  final String title;
  final String confirmLabel;
  final String initialName;
  @override
  State<_ProjectNameDialog> createState() => _ProjectNameDialogState();
}

class _ProjectNameDialogState extends State<_ProjectNameDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  void _submit() {
    if (_name.text.trim().isNotEmpty) Navigator.pop(context, _name.text.trim());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 360,
      child: TextField(
        key: const Key('project-name'),
        controller: _name,
        autofocus: true,
        maxLength: 100,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: context.l10n.name),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        key: const Key('save-project-name'),
        onPressed: _name.text.trim().isEmpty ? null : _submit,
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}

class _ProjectSummaryLine extends StatelessWidget {
  const _ProjectSummaryLine({required this.summary});
  final ProjectSummary? summary;

  @override
  Widget build(BuildContext context) {
    final value = summary;
    return Text(
      value == null
          ? context.l10n.projectUnreadable
          : [
              context.l10n.blockCount(value.blocks),
              context.l10n.foldCount(value.processes),
              context.l10n.arrowCount(value.arrows),
            ].join(' · '),
      style: context.type.bodySmall!.copyWith(
        color: value == null ? context.colors.danger : context.colors.muted,
      ),
    );
  }
}

class _NoProjects extends StatelessWidget {
  const _NoProjects();

  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('no-projects'),
    padding: const EdgeInsets.only(top: 24, bottom: 40),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.noProjectsTitle, style: context.type.titleLarge),
        const SizedBox(height: 8),
        Text(
          context.l10n.noProjectsBody,
          style: context.type.bodySmall!.copyWith(color: context.colors.muted),
        ),
      ],
    ),
  );
}

class _GettingStarted extends StatelessWidget {
  const _GettingStarted({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('getting-started'),
    color: context.colors.surfaceHigh,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 24,
        runSpacing: 16,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.gettingStarted,
                  style: context.type.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  context.l10n.gettingStartedHint,
                  style: context.type.bodySmall!.copyWith(
                    color: context.colors.muted,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            key: const Key('open-starter-board'),
            onPressed: onOpen,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: Text(context.l10n.openYourBoard),
          ),
        ],
      ),
    ),
  );
}
