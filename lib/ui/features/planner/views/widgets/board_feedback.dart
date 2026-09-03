import 'package:flutter/material.dart';
import 'package:foldboard/l10n/l10n.dart';

import '../../../../core/transient_feedback.dart';
import '../../../../core/write_access_scope.dart';
import '../../view_models/planner_view_model.dart';

class BoardFeedback extends StatefulWidget {
  const BoardFeedback({
    super.key,
    required this.viewModel,
    this.externalWarning,
    this.externalTicket,
    this.onOpenRequests,
  });
  final PlannerViewModel viewModel;
  final String? externalWarning;
  final Object? externalTicket;
  final VoidCallback? onOpenRequests;

  @override
  State<BoardFeedback> createState() => _BoardFeedbackState();
}

class _BoardFeedbackState extends State<BoardFeedback> {
  Object? _dismissedWarning;

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final rawWarning =
        vm.warning ??
        widget.externalWarning ??
        WriteAccessScope.warningOf(context);
    final ticket = (vm, vm.feedbackVersion, rawWarning, widget.externalTicket);
    final warning = _dismissedWarning == ticket ? null : rawWarning;
    void dismissWarning() => setState(() => _dismissedWarning = ticket);
    // A copy/paste confirmation outranks the agent lanes but never a
    // warning or the live connection prompt.
    final notice = warning == null && vm.connectFrom == null ? vm.notice : null;
    final agentNotice =
        warning == null &&
        vm.connectFrom == null &&
        notice == null &&
        vm.agentChangeRevision != null;
    // The change notice (with its Undo window) outranks the answer notice;
    // the answer surfaces once the change notice is dismissed or expires.
    final answered =
        warning == null &&
        vm.connectFrom == null &&
        notice == null &&
        !agentNotice &&
        vm.agentRespondedRequestId != null;
    void dismissAnswer() => vm.dismissAgentResponse();
    // Naming the source keeps the connection state unmistakable even when
    // the pill is the only sign of it.
    final connectSource = vm.connectFrom == null
        ? null
        : vm.nodes.where((n) => n.id == vm.connectFrom).firstOrNull?.title ??
              vm.groups.where((g) => g.id == vm.connectFrom).firstOrNull?.title;
    return TransientFeedback(
      message:
          warning ??
          (vm.connectFrom != null
              ? (connectSource == null || connectSource.isEmpty
                    ? context.l10n.chooseSecondBlock
                    : context.l10n.connectFromPrompt(connectSource))
              : notice ??
                    (agentNotice
                        ? context.l10n.agentChanged(vm.agentChangeCount)
                        : answered
                        ? context.l10n.agentAnswered
                        : null)),
      warning: warning != null,
      ticket: (
        ticket,
        vm.connectFrom,
        notice == null ? null : vm.noticeVersion,
        agentNotice ? vm.agentChangeVersion : null,
        answered ? vm.agentResponseVersion : null,
      ),
      duration: notice != null
          ? const Duration(seconds: 3)
          : agentNotice
          ? const Duration(seconds: 6)
          : answered
          ? const Duration(seconds: 8)
          : warning == null
          ? null
          : const Duration(seconds: 4),
      actionLabel: agentNotice
          ? context.l10n.undo
          : answered
          ? context.l10n.viewRequests
          : null,
      onAction: agentNotice && vm.canUndoAgentChange
          ? vm.undoAgentChange
          : answered && widget.onOpenRequests != null
          ? () {
              widget.onOpenRequests!();
              dismissAnswer();
            }
          : null,
      onExpired: notice != null
          ? vm.dismissNotice
          : agentNotice
          ? vm.dismissAgentChange
          : answered
          ? dismissAnswer
          : warning == null
          ? null
          : dismissWarning,
      onDismiss: notice != null
          ? vm.dismissNotice
          : agentNotice
          ? vm.dismissAgentChange
          : answered
          ? dismissAnswer
          : warning == null
          ? vm.cancelConnection
          : dismissWarning,
      dismissLabel:
          warning == null && notice == null && !agentNotice && !answered
          ? context.l10n.cancelArrow
          : context.l10n.close,
      surfaceKey: const Key('board-feedback'),
      dismissKey: const Key('dismiss-board-feedback'),
    );
  }
}
