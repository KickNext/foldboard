// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get history => 'History';

  @override
  String get storageConflict =>
      'Another tab owns editing access, or saved data has changed. Export any unsaved work, close the other Foldboard tabs, then reload this tab. Nothing was overwritten.';

  @override
  String get importJson => 'Import JSON';

  @override
  String get importTitle => 'Replace this board?';

  @override
  String get importHint =>
      'The selected file replaces this board. Other projects are unchanged. You can undo the import.';

  @override
  String get importInvalid =>
      'Could not import this file. Choose a valid Foldboard JSON file up to 10 MB. Your board is unchanged.';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get disconnectHint =>
      'Remove connections between this external card and this level. The original card and connections in other levels will remain.';

  @override
  String get openOriginal => 'Go to original';

  @override
  String get referenceHint =>
      'External card. Its name and description belong to the original. Double-click to go there.';

  @override
  String get connectionExists =>
      'This arrow already exists. Select another target or cancel.';

  @override
  String get agentReadOnly => 'Agent access';

  @override
  String get agentViewOnly => 'View only';

  @override
  String get agentViewAndEdit => 'View and edit';

  @override
  String get askAgent => 'Ask agent';

  @override
  String get boardTools => 'Board tools';

  @override
  String get zoomControls => 'Zoom controls';

  @override
  String get canvasControls => 'Canvas controls';

  @override
  String get agentRequests => 'Agent requests';

  @override
  String get agentRequestsHint =>
      'Saved with board context. An agent must read these requests via WebMCP; saving does not start an agent.';

  @override
  String requestAbout(String title) {
    return 'About: $title';
  }

  @override
  String get requestQuestion => 'Question or task';

  @override
  String get requestQuestionHint => 'What should the agent look at or change?';

  @override
  String get saveRequest => 'Save request';

  @override
  String get requestSaveFailed =>
      'Could not save the request. Your draft is still here. Check storage access and try again.';

  @override
  String get requestLoadFailed =>
      'Saved requests could not be loaded. They have not been overwritten.';

  @override
  String pendingRequests(int count) {
    return 'Pending ($count)';
  }

  @override
  String get handledRequests => 'Handled';

  @override
  String get noRequests => 'No requests here yet.';

  @override
  String get agentResponse => 'Agent response';

  @override
  String requestTargetRemoved(String title) {
    return '$title · removed';
  }

  @override
  String get removeRequest => 'Remove request';

  @override
  String get removeRequestHint =>
      'The request and its response will be removed. Board cards will not change.';

  @override
  String get reopenRequest => 'Reopen request';

  @override
  String get discardRequest => 'Discard this draft?';

  @override
  String get discard => 'Discard';

  @override
  String get agentReadOnlyHint =>
      'Agents can view, search and export. They cannot change projects or cards.';

  @override
  String get agentCanEditHint =>
      'Agents can change projects and cards saved in this browser.';

  @override
  String agentChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Agent changed $count items',
      one: 'Agent changed 1 item',
    );
    return '$_temp0';
  }

  @override
  String get addBlock => 'Add block';

  @override
  String get addFold => 'Add fold';

  @override
  String get agentAnswered => 'Agent answered a request';

  @override
  String get viewRequests => 'View';

  @override
  String get pendingCommentMarker => 'Pending agent request';

  @override
  String get ancestorConnection =>
      'A card cannot connect to the fold that contains it, or any fold above that. Choose a different connection.';

  @override
  String get removeProject => 'Remove project';

  @override
  String get removeProjectHint =>
      'Remove this project from the list? Its saved board is kept for recovery. You can restore it immediately.';

  @override
  String get projectRemoved => 'Project removed';

  @override
  String get restoreProject => 'Restore';

  @override
  String get moreActions => 'More actions';

  @override
  String get keyboardHint =>
      'Tab to focus cards. Enter opens details or follows a fold. Arrow keys move cards; Shift moves faster.';

  @override
  String get backToProjects => 'Back to projects';

  @override
  String get search => 'Search';

  @override
  String get searchBoardHint => 'Search this project';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get noSearchResults => 'No matches. Try another name or description.';

  @override
  String get emptySearchBoard =>
      'Nothing to find yet. Add a block or fold to this project.';

  @override
  String get searchStartHint =>
      'Type a name or description to search every level.';

  @override
  String get searchAllLevels => 'Searches all levels';

  @override
  String searchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
      zero: 'No results',
    );
    return '$_temp0 · All levels';
  }

  @override
  String get projects => 'Projects';

  @override
  String get newProject => 'New project';

  @override
  String get myProject => 'My project';

  @override
  String get openProject => 'Open project';

  @override
  String get renameProject => 'Rename project';

  @override
  String get createProject => 'Create project';

  @override
  String get save => 'Save';

  @override
  String get projectsLocalHint =>
      'Boards save in this browser. Export JSON for backup; clearing site data deletes them.';

  @override
  String get gettingStarted => 'Start with one flow';

  @override
  String get gettingStartedHint =>
      'Blocks are steps. Folds contain levels. Arrows connect the flow.';

  @override
  String get openYourBoard => 'Open your board';

  @override
  String get exploreExample => 'Explore example';

  @override
  String get exampleProjectHint =>
      'See a person and agent work across bounded levels.';

  @override
  String get projectsReadFailed =>
      'Could not read saved projects. Original data has not been overwritten. Reload to try again.';

  @override
  String get projectsWriteFailed =>
      'Could not save in this browser. If a board is open, export JSON before leaving. Then try again.';

  @override
  String get block => 'Block';

  @override
  String get fold => 'Fold';

  @override
  String get arrow => 'Arrow';

  @override
  String get newBlock => 'New block';

  @override
  String get newFold => 'New fold';

  @override
  String get findOnBoard => 'Find on board';

  @override
  String get saving => 'Saving…';

  @override
  String get savedInBrowser => 'Saved in this browser';

  @override
  String get add => 'Add';

  @override
  String get exportProject => 'Export project';

  @override
  String get exportMarkdown => 'Markdown';

  @override
  String get exportJsonFormat => 'JSON';

  @override
  String get exportDiagramHint =>
      'JSON is the backup. Markdown and Mermaid describe the plan. PNG captures this level.';

  @override
  String get exportJsonHint => 'The exact board, for import and backup.';

  @override
  String get exportMarkdownHint =>
      'The plan as a document, for people and AI agents.';

  @override
  String get exportMermaidHint => 'A Mermaid flowchart, for docs and wikis.';

  @override
  String get exportPngHint => 'An image of this level as it is laid out.';

  @override
  String get exportNote => 'Agent requests and replies are not included.';

  @override
  String get chooseSecondBlock => 'Choose the second block';

  @override
  String connectFromPrompt(String title) {
    return 'Arrow from “$title” — click the target card';
  }

  @override
  String get cancelArrow => 'Cancel connection';

  @override
  String get open => 'Open';

  @override
  String get delete => 'Delete';

  @override
  String get clearSelection => 'Clear selection';

  @override
  String get searchHint => 'Name or description';

  @override
  String get closeDetails => 'Close details';

  @override
  String get name => 'Name';

  @override
  String get description => 'Description';

  @override
  String get onBoard => 'On the board';

  @override
  String get drawArrow => 'Draw arrow';

  @override
  String deleteTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get deleteFoldMessage =>
      'Contents will move up one level. Connections to this fold card will be deleted.';

  @override
  String get deleteBlockMessage => 'Connected arrows will also be deleted.';

  @override
  String get deleteArrowMessage => 'Only this arrow will be deleted.';

  @override
  String get cancel => 'Cancel';

  @override
  String get focusArea => 'Focus this area';

  @override
  String get selectAndMove => 'Select and move';

  @override
  String get panAnywhere => 'Pan anywhere';

  @override
  String get arrange => 'Tidy';

  @override
  String get rebuildLayout => 'Rebuild layout';

  @override
  String get fitContent => 'Fit content';

  @override
  String get zoomIn => 'Zoom in';

  @override
  String get zoomOut => 'Zoom out';

  @override
  String zoomPercent(int value) {
    return '$value%';
  }

  @override
  String get close => 'Close';

  @override
  String get storageReadFailed =>
      'Could not open the saved board. The original data has not been overwritten.';

  @override
  String get storageWriteFailed =>
      'Could not save the board. Export JSON before closing.';

  @override
  String get changeFailed =>
      'Could not apply this change. Check the selected objects and connections.';

  @override
  String get openFold => 'Open fold';

  @override
  String get outside => 'Outside · Open original';

  @override
  String get referenceInput => 'Input · Outside';

  @override
  String get referenceOutput => 'Output · Outside';

  @override
  String get referenceBoth => 'Input / Output · Outside';

  @override
  String get thisFold => 'This fold · Go up';

  @override
  String get upOneLevel => 'Up one level';

  @override
  String get rootLevel => 'Board';

  @override
  String get moveTo => 'Move to level';

  @override
  String get details => 'Details';

  @override
  String connectionCount(int count) {
    return '$count connections';
  }

  @override
  String deleteConnections(int count) {
    return 'Delete all $count connections represented by this arrow?';
  }

  @override
  String get settings => 'Settings';

  @override
  String get settingsLocalHint =>
      'Saved automatically in this browser. Applies to all projects.';

  @override
  String get appearance => 'Appearance';

  @override
  String get theme => 'Theme';

  @override
  String get darkTheme => 'Dark';

  @override
  String get lightTheme => 'Light';

  @override
  String get systemTheme => 'System';

  @override
  String get showGrid => 'Show grid';

  @override
  String get showGridHint => 'Display dots on the board background.';

  @override
  String get resetSettings => 'Reset settings';

  @override
  String get resetSettingsHint =>
      'Restore the dark theme and show the grid. Your projects and boards will not change.';

  @override
  String get reset => 'Reset';

  @override
  String get settingsReadFailed =>
      'Could not read saved settings. Defaults are shown; use Reset settings to recover.';

  @override
  String get readOnly => 'Read only';

  @override
  String get readOnlyHint =>
      'Read only — another tab is editing. You can browse, search and export. Close the editing tab and reload to edit here.';

  @override
  String get projectsActionFailed =>
      'Could not complete this action. Your projects have not been changed. Try again.';

  @override
  String get settingsWriteFailed =>
      'Could not save settings in this browser. Your previous settings are still active. Try again.';

  @override
  String get agents => 'Agents';

  @override
  String get about => 'About';

  @override
  String get version => 'Version';

  @override
  String get storageLabel => 'Storage';

  @override
  String get storageAboutHint =>
      'Boards live in this browser, under this exact address. There is no server copy — export a board to move or back it up.';

  @override
  String get webMcp => 'WebMCP';

  @override
  String webMcpConnected(int count) {
    return 'Connected · $count tools registered';
  }

  @override
  String get webMcpUnavailable =>
      'No WebMCP client detected. Foldboard works without one.';

  @override
  String get agentConnection => 'Agent connection';

  @override
  String get agentConnectionReady => 'Ready';

  @override
  String get agentConnectionUnavailable => 'Not connected';

  @override
  String get technicalDetails => 'Technical details';

  @override
  String get dangerZone => 'Danger zone';

  @override
  String get keyboardShortcuts => 'Keyboard shortcuts';

  @override
  String get keyboardShortcutsHint => 'These work while the board has focus.';

  @override
  String get shortcutsBoard => 'Board';

  @override
  String get shortcutsEditing => 'Editing';

  @override
  String get shortcutsNavigation => 'Navigation';

  @override
  String get shortcutSearch => 'Search every level';

  @override
  String get shortcutPan => 'Pan the board';

  @override
  String get shortcutZoom => 'Zoom toward the pointer';

  @override
  String get shortcutHelp => 'Show this list';

  @override
  String get shortcutDelete => 'Delete the selection';

  @override
  String get shortcutEscape => 'Cancel a connection, then clear the selection';

  @override
  String get shortcutMarquee => 'Select several with a rectangle';

  @override
  String get shortcutFocusCard => 'Focus the next visible card';

  @override
  String get shortcutOpen =>
      'Open details, enter a fold, or go to the original';

  @override
  String get shortcutMove => 'Move the selected card';

  @override
  String get shortcutMoveFar => 'Move it four times further';

  @override
  String get shortcutDuplicate => 'Duplicate the selection';

  @override
  String get shortcutCopy => 'Copy the selection';

  @override
  String get shortcutPaste => 'Paste into this level';

  @override
  String get keyWheel => 'Wheel';

  @override
  String get keyMiddleMouse => 'Middle mouse';

  @override
  String get keyArrows => 'Arrows';

  @override
  String get keyDrag => 'drag';

  @override
  String get emptyBoardTitle => 'This level is empty';

  @override
  String get emptyBoardBody =>
      'Add a block for one part of the plan, or a fold for anything that has its own inner level.';

  @override
  String get emptyBoardAgentHint => 'An agent can fill it in too, over WebMCP.';

  @override
  String blockCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count blocks',
      one: '1 block',
      zero: 'No blocks',
    );
    return '$_temp0';
  }

  @override
  String foldCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count folds',
      one: '1 fold',
      zero: 'no folds',
    );
    return '$_temp0';
  }

  @override
  String arrowCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count arrows',
      one: '1 arrow',
      zero: 'no arrows',
    );
    return '$_temp0';
  }

  @override
  String get projectUnreadable => 'Saved board could not be read';

  @override
  String get noProjectsTitle => 'No projects yet';

  @override
  String get noProjectsBody =>
      'A project is one independent board with its own levels, history and agent requests.';

  @override
  String get duplicateProject => 'Duplicate project';

  @override
  String projectCopyName(String name) {
    return '$name copy';
  }

  @override
  String get exportPng => 'PNG';

  @override
  String get exportMermaid => 'Mermaid';

  @override
  String get exportImageFailed => 'Could not create the image. Try again.';

  @override
  String get duplicate => 'Duplicate';

  @override
  String get copy => 'Copy';

  @override
  String get paste => 'Paste';

  @override
  String copiedCard(String name) {
    return 'Copied “$name”';
  }

  @override
  String get clipboardEmpty => 'Nothing has been copied yet.';

  @override
  String selectedCards(int count) {
    return '$count cards selected';
  }

  @override
  String get trace => 'Trace';

  @override
  String get traceFromHere => 'Trace from here';

  @override
  String get traceBetween => 'Trace between';

  @override
  String get traceThrough => 'Trace through';

  @override
  String get traceStraighten => 'Straighten';

  @override
  String get traceNoConnection =>
      'These cards are not connected, so there is no thread to straighten.';

  @override
  String get traceNothingToFollow =>
      'No arrows to follow yet. Connect two cards, then trace.';

  @override
  String traceStepCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count steps',
      one: '1 step',
    );
    return '$_temp0';
  }

  @override
  String traceFoldedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count folds folded',
      one: '1 fold folded',
      zero: 'straightened',
    );
    return '$_temp0';
  }

  @override
  String traceCollapseFold(String title) {
    return 'Fold $title back into one card';
  }

  @override
  String traceStepsInside(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count steps inside',
      one: '1 step inside',
    );
    return '$_temp0';
  }

  @override
  String get traceExpandAll => 'Expand all';

  @override
  String get traceOpenHere => 'Open where it lives';

  @override
  String get traceClose => 'Close trace';

  @override
  String traceBranchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count branches',
      one: '1 branch',
    );
    return '$_temp0';
  }

  @override
  String traceLoopsBack(String title) {
    return 'Loops back to $title';
  }

  @override
  String traceInto(String title) {
    return 'Into $title';
  }

  @override
  String traceOutOf(String title) {
    return 'Out of $title';
  }

  @override
  String get traceNoLoop =>
      'This card has no way back to itself, so there is no loop to trace.';

  @override
  String get traceStartAt => 'Start the thread at another card';

  @override
  String get traceEndAt => 'End the thread at another card';

  @override
  String get traceRunOnStart => 'Let the thread run back to its own start';

  @override
  String get traceRunOnEnd => 'Let the thread run on to its own end';

  @override
  String traceEnds(String from, String to) {
    return '$from to $to';
  }

  @override
  String get traceDensityCards => 'Cards';

  @override
  String get traceDensityRead => 'Text';

  @override
  String get traceCopyMarkdown => 'Copy as Markdown';

  @override
  String get traceCopied => 'The trace is on the clipboard as Markdown.';

  @override
  String get traceCopyFailed =>
      'The clipboard is not available here. Select the text and copy it instead.';

  @override
  String get traceAnchor => 'Traced from here';

  @override
  String get traceProfile => 'Depth of the thread, step by step';

  @override
  String get shortcutTrace => 'Trace from the selection';

  @override
  String get shortcutTraceStep => 'Step along the trace';

  @override
  String get shortcutTraceBranch => 'Take another branch';

  @override
  String get shortcutTraceOpen => 'Open the step where it lives';

  @override
  String get shortcutTraceDensity => 'Cards or Text';

  @override
  String get shortcutsTrace => 'Trace';

  @override
  String get deleteSelectedCardsMessage =>
      'The selected cards and their connected arrows will be deleted.';

  @override
  String get overview => 'Overview';

  @override
  String get overviewTooltip => 'See the scale of the whole board';

  @override
  String get overviewReadOnly => 'View only';

  @override
  String get overviewHint => 'Scroll to zoom. Drag to move.';

  @override
  String get overviewEmptyTitle => 'Nothing to map yet';

  @override
  String get overviewEmptyHint =>
      'Add blocks to see the scale of the board here.';

  @override
  String overviewOpenFold(String title) {
    return 'Open $title';
  }

  @override
  String overviewStats(int blocks, int connections) {
    return '$blocks blocks · $connections connections';
  }
}

/// The translations for English, as used in the United States (`en_US`).
class AppLocalizationsEnUs extends AppLocalizationsEn {
  AppLocalizationsEnUs() : super('en_US');

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get history => 'Undo / Redo';

  @override
  String get storageConflict =>
      'Another tab owns editing access, or saved data has changed. Export any unsaved work, close the other Foldboard tabs, then reload this tab. Nothing was overwritten.';

  @override
  String get importJson => 'Import JSON';

  @override
  String get importTitle => 'Replace this board?';

  @override
  String get importHint =>
      'The selected file replaces this board. Other projects are unchanged. You can undo the import.';

  @override
  String get importInvalid =>
      'Could not import this file. Choose a valid Foldboard JSON file up to 10 MB. Your board is unchanged.';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get disconnectHint =>
      'Remove connections between this external card and this level. The original card and connections in other levels will remain.';

  @override
  String get openOriginal => 'Go to original';

  @override
  String get referenceHint =>
      'External card. Its name and description belong to the original. Double-click to go there.';

  @override
  String get connectionExists =>
      'This arrow already exists. Select another target or cancel.';

  @override
  String get removeProject => 'Remove project';

  @override
  String get removeProjectHint =>
      'Remove this project from the list? Its saved board is kept for recovery. You can restore it immediately.';

  @override
  String get projectRemoved => 'Project removed';

  @override
  String get restoreProject => 'Restore';

  @override
  String get moreActions => 'More actions';

  @override
  String get keyboardHint =>
      'Tab to focus cards. Enter opens details or follows a fold. Arrow keys move cards; Shift moves faster.';
}
