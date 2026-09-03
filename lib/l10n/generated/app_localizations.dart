import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('en', 'US'),
  ];

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @storageConflict.
  ///
  /// In en, this message translates to:
  /// **'Another tab owns editing access, or saved data has changed. Export any unsaved work, close the other Foldboard tabs, then reload this tab. Nothing was overwritten.'**
  String get storageConflict;

  /// No description provided for @importJson.
  ///
  /// In en, this message translates to:
  /// **'Import JSON'**
  String get importJson;

  /// No description provided for @importTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace this board?'**
  String get importTitle;

  /// No description provided for @importHint.
  ///
  /// In en, this message translates to:
  /// **'The selected file replaces this board. Other projects are unchanged. You can undo the import.'**
  String get importHint;

  /// No description provided for @importInvalid.
  ///
  /// In en, this message translates to:
  /// **'Could not import this file. Choose a valid Foldboard JSON file up to 10 MB. Your board is unchanged.'**
  String get importInvalid;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @disconnectHint.
  ///
  /// In en, this message translates to:
  /// **'Remove connections between this external card and this level. The original card and connections in other levels will remain.'**
  String get disconnectHint;

  /// No description provided for @openOriginal.
  ///
  /// In en, this message translates to:
  /// **'Go to original'**
  String get openOriginal;

  /// No description provided for @referenceHint.
  ///
  /// In en, this message translates to:
  /// **'External card. Its name and description belong to the original. Double-click to go there.'**
  String get referenceHint;

  /// No description provided for @connectionExists.
  ///
  /// In en, this message translates to:
  /// **'This arrow already exists. Select another target or cancel.'**
  String get connectionExists;

  /// No description provided for @agentReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Agent access'**
  String get agentReadOnly;

  /// No description provided for @agentViewOnly.
  ///
  /// In en, this message translates to:
  /// **'View only'**
  String get agentViewOnly;

  /// No description provided for @agentViewAndEdit.
  ///
  /// In en, this message translates to:
  /// **'View and edit'**
  String get agentViewAndEdit;

  /// No description provided for @askAgent.
  ///
  /// In en, this message translates to:
  /// **'Ask agent'**
  String get askAgent;

  /// No description provided for @boardTools.
  ///
  /// In en, this message translates to:
  /// **'Board tools'**
  String get boardTools;

  /// No description provided for @zoomControls.
  ///
  /// In en, this message translates to:
  /// **'Zoom controls'**
  String get zoomControls;

  /// No description provided for @canvasControls.
  ///
  /// In en, this message translates to:
  /// **'Canvas controls'**
  String get canvasControls;

  /// No description provided for @agentRequests.
  ///
  /// In en, this message translates to:
  /// **'Agent requests'**
  String get agentRequests;

  /// No description provided for @agentRequestsHint.
  ///
  /// In en, this message translates to:
  /// **'Saved with board context. An agent must read these requests via WebMCP; saving does not start an agent.'**
  String get agentRequestsHint;

  /// No description provided for @requestAbout.
  ///
  /// In en, this message translates to:
  /// **'About: {title}'**
  String requestAbout(String title);

  /// No description provided for @requestQuestion.
  ///
  /// In en, this message translates to:
  /// **'Question or task'**
  String get requestQuestion;

  /// No description provided for @requestQuestionHint.
  ///
  /// In en, this message translates to:
  /// **'What should the agent look at or change?'**
  String get requestQuestionHint;

  /// No description provided for @saveRequest.
  ///
  /// In en, this message translates to:
  /// **'Save request'**
  String get saveRequest;

  /// No description provided for @requestSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the request. Your draft is still here. Check storage access and try again.'**
  String get requestSaveFailed;

  /// No description provided for @requestLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Saved requests could not be loaded. They have not been overwritten.'**
  String get requestLoadFailed;

  /// No description provided for @pendingRequests.
  ///
  /// In en, this message translates to:
  /// **'Pending ({count})'**
  String pendingRequests(int count);

  /// No description provided for @handledRequests.
  ///
  /// In en, this message translates to:
  /// **'Handled'**
  String get handledRequests;

  /// No description provided for @noRequests.
  ///
  /// In en, this message translates to:
  /// **'No requests here yet.'**
  String get noRequests;

  /// No description provided for @agentResponse.
  ///
  /// In en, this message translates to:
  /// **'Agent response'**
  String get agentResponse;

  /// No description provided for @requestTargetRemoved.
  ///
  /// In en, this message translates to:
  /// **'{title} · removed'**
  String requestTargetRemoved(String title);

  /// No description provided for @removeRequest.
  ///
  /// In en, this message translates to:
  /// **'Remove request'**
  String get removeRequest;

  /// No description provided for @removeRequestHint.
  ///
  /// In en, this message translates to:
  /// **'The request and its response will be removed. Board cards will not change.'**
  String get removeRequestHint;

  /// No description provided for @reopenRequest.
  ///
  /// In en, this message translates to:
  /// **'Reopen request'**
  String get reopenRequest;

  /// No description provided for @discardRequest.
  ///
  /// In en, this message translates to:
  /// **'Discard this draft?'**
  String get discardRequest;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @agentReadOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Agents can view, search and export. They cannot change projects or cards.'**
  String get agentReadOnlyHint;

  /// No description provided for @agentCanEditHint.
  ///
  /// In en, this message translates to:
  /// **'Agents can change projects and cards saved in this browser.'**
  String get agentCanEditHint;

  /// No description provided for @agentChanged.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Agent changed 1 item} other{Agent changed {count} items}}'**
  String agentChanged(int count);

  /// No description provided for @addBlock.
  ///
  /// In en, this message translates to:
  /// **'Add block'**
  String get addBlock;

  /// No description provided for @addFold.
  ///
  /// In en, this message translates to:
  /// **'Add fold'**
  String get addFold;

  /// No description provided for @agentAnswered.
  ///
  /// In en, this message translates to:
  /// **'Agent answered a request'**
  String get agentAnswered;

  /// No description provided for @viewRequests.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get viewRequests;

  /// No description provided for @pendingCommentMarker.
  ///
  /// In en, this message translates to:
  /// **'Pending agent request'**
  String get pendingCommentMarker;

  /// No description provided for @ancestorConnection.
  ///
  /// In en, this message translates to:
  /// **'A card cannot connect to the fold that contains it, or any fold above that. Choose a different connection.'**
  String get ancestorConnection;

  /// No description provided for @removeProject.
  ///
  /// In en, this message translates to:
  /// **'Remove project'**
  String get removeProject;

  /// No description provided for @removeProjectHint.
  ///
  /// In en, this message translates to:
  /// **'Remove this project from the list? Its saved board is kept for recovery. You can restore it immediately.'**
  String get removeProjectHint;

  /// No description provided for @projectRemoved.
  ///
  /// In en, this message translates to:
  /// **'Project removed'**
  String get projectRemoved;

  /// No description provided for @restoreProject.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreProject;

  /// No description provided for @moreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActions;

  /// No description provided for @keyboardHint.
  ///
  /// In en, this message translates to:
  /// **'Tab to focus cards. Enter opens details or follows a fold. Arrow keys move cards; Shift moves faster.'**
  String get keyboardHint;

  /// Go back from the root board to the top-level project list.
  ///
  /// In en, this message translates to:
  /// **'Back to projects'**
  String get backToProjects;

  /// Compact header action opening search in the current project.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// Search all levels of the currently open project.
  ///
  /// In en, this message translates to:
  /// **'Search this project'**
  String get searchBoardHint;

  /// Clear query without closing the search dialog.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// The board search found no matching objects.
  ///
  /// In en, this message translates to:
  /// **'No matches. Try another name or description.'**
  String get noSearchResults;

  /// Search in an empty board.
  ///
  /// In en, this message translates to:
  /// **'Nothing to find yet. Add a block or fold to this project.'**
  String get emptySearchBoard;

  /// Prompt shown before the person types a board search query.
  ///
  /// In en, this message translates to:
  /// **'Type a name or description to search every level.'**
  String get searchStartHint;

  /// Scope hint shown before the person types a board search query.
  ///
  /// In en, this message translates to:
  /// **'Searches all levels'**
  String get searchAllLevels;

  /// Count and scope of search results.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No results} =1{1 result} other{{count} results}} · All levels'**
  String searchResultCount(int count);

  /// Top-level independent project boards.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get projects;

  /// Create project action and dialog title.
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get newProject;

  /// Name assigned to the existing board when introducing projects.
  ///
  /// In en, this message translates to:
  /// **'My project'**
  String get myProject;

  /// Open this project's independent board.
  ///
  /// In en, this message translates to:
  /// **'Open project'**
  String get openProject;

  /// Edit a project name without changing its board.
  ///
  /// In en, this message translates to:
  /// **'Rename project'**
  String get renameProject;

  /// Confirm creation of a named empty project.
  ///
  /// In en, this message translates to:
  /// **'Create project'**
  String get createProject;

  /// Confirm a name change.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Explain local project persistence and its limits.
  ///
  /// In en, this message translates to:
  /// **'Boards save in this browser. Export JSON for backup; clearing site data deletes them.'**
  String get projectsLocalHint;

  /// Heading for the first-project guide.
  ///
  /// In en, this message translates to:
  /// **'Start with one flow'**
  String get gettingStarted;

  /// Short explanation of the core board concepts for a new user.
  ///
  /// In en, this message translates to:
  /// **'Blocks are steps. Folds contain levels. Arrows connect the flow.'**
  String get gettingStartedHint;

  /// Open the empty starter project from the first-project guide.
  ///
  /// In en, this message translates to:
  /// **'Open your board'**
  String get openYourBoard;

  /// Open the editable example project saved in this browser.
  ///
  /// In en, this message translates to:
  /// **'Explore example'**
  String get exploreExample;

  /// Short explanation beside the example project entry point.
  ///
  /// In en, this message translates to:
  /// **'See a person and agent work across bounded levels.'**
  String get exampleProjectHint;

  /// Projects catalog or board could not be read.
  ///
  /// In en, this message translates to:
  /// **'Could not read saved projects. Original data has not been overwritten. Reload to try again.'**
  String get projectsReadFailed;

  /// Failed catalog or board save; navigation does not discard unsaved edits.
  ///
  /// In en, this message translates to:
  /// **'Could not save in this browser. If a board is open, export JSON before leaving. Then try again.'**
  String get projectsWriteFailed;

  /// Foldboard UI: block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// Foldboard UI: folds.
  ///
  /// In en, this message translates to:
  /// **'Fold'**
  String get fold;

  /// Foldboard UI: arrow.
  ///
  /// In en, this message translates to:
  /// **'Arrow'**
  String get arrow;

  /// Foldboard UI: new block.
  ///
  /// In en, this message translates to:
  /// **'New block'**
  String get newBlock;

  /// Foldboard UI: new folds.
  ///
  /// In en, this message translates to:
  /// **'New fold'**
  String get newFold;

  /// Foldboard UI: find on board.
  ///
  /// In en, this message translates to:
  /// **'Find on board'**
  String get findOnBoard;

  /// Foldboard UI: saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// Foldboard UI: saved in browser.
  ///
  /// In en, this message translates to:
  /// **'Saved in this browser'**
  String get savedInBrowser;

  /// Foldboard UI: add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @exportProject.
  ///
  /// In en, this message translates to:
  /// **'Export project'**
  String get exportProject;

  /// No description provided for @exportMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Markdown'**
  String get exportMarkdown;

  /// No description provided for @exportJsonFormat.
  ///
  /// In en, this message translates to:
  /// **'JSON'**
  String get exportJsonFormat;

  /// No description provided for @exportDiagramHint.
  ///
  /// In en, this message translates to:
  /// **'JSON is the backup. Markdown and Mermaid describe the plan. PNG captures this level.'**
  String get exportDiagramHint;

  /// No description provided for @exportJsonHint.
  ///
  /// In en, this message translates to:
  /// **'The exact board, for import and backup.'**
  String get exportJsonHint;

  /// No description provided for @exportMarkdownHint.
  ///
  /// In en, this message translates to:
  /// **'The plan as a document, for people and AI agents.'**
  String get exportMarkdownHint;

  /// No description provided for @exportMermaidHint.
  ///
  /// In en, this message translates to:
  /// **'A Mermaid flowchart, for docs and wikis.'**
  String get exportMermaidHint;

  /// No description provided for @exportPngHint.
  ///
  /// In en, this message translates to:
  /// **'An image of this level as it is laid out.'**
  String get exportPngHint;

  /// No description provided for @exportNote.
  ///
  /// In en, this message translates to:
  /// **'Agent requests and replies are not included.'**
  String get exportNote;

  /// Foldboard UI: choose second block.
  ///
  /// In en, this message translates to:
  /// **'Choose the second block'**
  String get chooseSecondBlock;

  /// Live connection prompt, naming the card the arrow starts from.
  ///
  /// In en, this message translates to:
  /// **'Arrow from “{title}” — click the target card'**
  String connectFromPrompt(String title);

  /// Foldboard UI: cancel arrow.
  ///
  /// In en, this message translates to:
  /// **'Cancel connection'**
  String get cancelArrow;

  /// Foldboard UI: open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// Foldboard UI: delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Foldboard UI: clear selection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get clearSelection;

  /// Foldboard UI: search hint.
  ///
  /// In en, this message translates to:
  /// **'Name or description'**
  String get searchHint;

  /// Foldboard UI: close details.
  ///
  /// In en, this message translates to:
  /// **'Close details'**
  String get closeDetails;

  /// Foldboard UI: name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// Foldboard UI: description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// Foldboard UI: on board.
  ///
  /// In en, this message translates to:
  /// **'On the board'**
  String get onBoard;

  /// Foldboard UI: draw arrow.
  ///
  /// In en, this message translates to:
  /// **'Draw arrow'**
  String get drawArrow;

  /// Foldboard UI: delete title.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”?'**
  String deleteTitle(String name);

  /// Foldboard UI: delete folds message.
  ///
  /// In en, this message translates to:
  /// **'Contents will move up one level. Connections to this fold card will be deleted.'**
  String get deleteFoldMessage;

  /// Foldboard UI: delete block message.
  ///
  /// In en, this message translates to:
  /// **'Connected arrows will also be deleted.'**
  String get deleteBlockMessage;

  /// Foldboard UI: delete arrow message.
  ///
  /// In en, this message translates to:
  /// **'Only this arrow will be deleted.'**
  String get deleteArrowMessage;

  /// Foldboard UI: cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Foldboard UI: focus folds.
  ///
  /// In en, this message translates to:
  /// **'Focus this area'**
  String get focusArea;

  /// Foldboard UI: select and move.
  ///
  /// In en, this message translates to:
  /// **'Select and move'**
  String get selectAndMove;

  /// Foldboard UI: pan anywhere.
  ///
  /// In en, this message translates to:
  /// **'Pan anywhere'**
  String get panAnywhere;

  /// Foldboard UI: arrange.
  ///
  /// In en, this message translates to:
  /// **'Tidy'**
  String get arrange;

  /// Foldboard UI: rebuild layout.
  ///
  /// In en, this message translates to:
  /// **'Rebuild layout'**
  String get rebuildLayout;

  /// Foldboard UI: fit content.
  ///
  /// In en, this message translates to:
  /// **'Fit content'**
  String get fitContent;

  /// Foldboard UI: zoom in.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get zoomIn;

  /// Foldboard UI: zoom out.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get zoomOut;

  /// Foldboard UI: zoom percent.
  ///
  /// In en, this message translates to:
  /// **'{value}%'**
  String zoomPercent(int value);

  /// Foldboard UI: close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Foldboard UI: storage read failed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the saved board. The original data has not been overwritten.'**
  String get storageReadFailed;

  /// Foldboard UI: storage write failed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the board. Export JSON before closing.'**
  String get storageWriteFailed;

  /// Foldboard UI: change failed.
  ///
  /// In en, this message translates to:
  /// **'Could not apply this change. Check the selected objects and connections.'**
  String get changeFailed;

  /// Enter a fold from its card.
  ///
  /// In en, this message translates to:
  /// **'Open fold'**
  String get openFold;

  /// Level navigation: outside
  ///
  /// In en, this message translates to:
  /// **'Outside · Open original'**
  String get outside;

  /// No description provided for @referenceInput.
  ///
  /// In en, this message translates to:
  /// **'Input · Outside'**
  String get referenceInput;

  /// No description provided for @referenceOutput.
  ///
  /// In en, this message translates to:
  /// **'Output · Outside'**
  String get referenceOutput;

  /// No description provided for @referenceBoth.
  ///
  /// In en, this message translates to:
  /// **'Input / Output · Outside'**
  String get referenceBoth;

  /// The fold you are inside, shown from within.
  ///
  /// In en, this message translates to:
  /// **'This fold · Go up'**
  String get thisFold;

  /// Level navigation: upOneLevel
  ///
  /// In en, this message translates to:
  /// **'Up one level'**
  String get upOneLevel;

  /// Level navigation: rootLevel
  ///
  /// In en, this message translates to:
  /// **'Board'**
  String get rootLevel;

  /// Level navigation: moveTo
  ///
  /// In en, this message translates to:
  /// **'Move to level'**
  String get moveTo;

  /// Level navigation: details
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// Level navigation: connectionCount
  ///
  /// In en, this message translates to:
  /// **'{count} connections'**
  String connectionCount(int count);

  /// Level navigation: deleteConnections
  ///
  /// In en, this message translates to:
  /// **'Delete all {count} connections represented by this arrow?'**
  String deleteConnections(int count);

  /// Application settings: settings
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Application settings: settingsLocalHint
  ///
  /// In en, this message translates to:
  /// **'Saved automatically in this browser. Applies to all projects.'**
  String get settingsLocalHint;

  /// Application settings: appearance
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// Application settings: theme
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// Application settings: darkTheme
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get darkTheme;

  /// Application settings: lightTheme
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get lightTheme;

  /// Application settings: systemTheme
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get systemTheme;

  /// Application settings: showGrid
  ///
  /// In en, this message translates to:
  /// **'Show grid'**
  String get showGrid;

  /// Application settings: showGridHint
  ///
  /// In en, this message translates to:
  /// **'Display dots on the board background.'**
  String get showGridHint;

  /// Application settings: resetSettings
  ///
  /// In en, this message translates to:
  /// **'Reset settings'**
  String get resetSettings;

  /// Application settings: resetSettingsHint
  ///
  /// In en, this message translates to:
  /// **'Restore the dark theme and show the grid. Your projects and boards will not change.'**
  String get resetSettingsHint;

  /// Application settings: reset
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// Application settings: settingsReadFailed
  ///
  /// In en, this message translates to:
  /// **'Could not read saved settings. Defaults are shown; use Reset settings to recover.'**
  String get settingsReadFailed;

  /// No description provided for @readOnly.
  ///
  /// In en, this message translates to:
  /// **'Read only'**
  String get readOnly;

  /// No description provided for @readOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Read only — another tab is editing. You can browse, search and export. Close the editing tab and reload to edit here.'**
  String get readOnlyHint;

  /// No description provided for @projectsActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not complete this action. Your projects have not been changed. Try again.'**
  String get projectsActionFailed;

  /// Application settings: settingsWriteFailed
  ///
  /// In en, this message translates to:
  /// **'Could not save settings in this browser. Your previous settings are still active. Try again.'**
  String get settingsWriteFailed;

  /// Settings section covering WebMCP agent access.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get agents;

  /// Settings section with build and storage facts.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// About row: the running app version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// About row: where boards are kept.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storageLabel;

  /// About row: explains the local-only storage model.
  ///
  /// In en, this message translates to:
  /// **'Boards live in this browser, under this exact address. There is no server copy — export a board to move or back it up.'**
  String get storageAboutHint;

  /// About row: agent bridge status.
  ///
  /// In en, this message translates to:
  /// **'WebMCP'**
  String get webMcp;

  /// About row: a WebMCP client picked up the tools.
  ///
  /// In en, this message translates to:
  /// **'Connected · {count} tools registered'**
  String webMcpConnected(int count);

  /// About row: no agent bridge in this browser.
  ///
  /// In en, this message translates to:
  /// **'No WebMCP client detected. Foldboard works without one.'**
  String get webMcpUnavailable;

  /// Plain-language label for agent bridge availability.
  ///
  /// In en, this message translates to:
  /// **'Agent connection'**
  String get agentConnection;

  /// Plain-language status when the agent bridge is available.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get agentConnectionReady;

  /// Plain-language status when the agent bridge is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get agentConnectionUnavailable;

  /// Expandable settings row containing implementation details.
  ///
  /// In en, this message translates to:
  /// **'Technical details'**
  String get technicalDetails;

  /// Settings section for destructive actions.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get dangerZone;

  /// Dialog listing every board shortcut.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get keyboardShortcuts;

  /// Subtitle of the keyboard shortcuts dialog.
  ///
  /// In en, this message translates to:
  /// **'These work while the board has focus.'**
  String get keyboardShortcutsHint;

  /// Shortcut group: viewing the board.
  ///
  /// In en, this message translates to:
  /// **'Board'**
  String get shortcutsBoard;

  /// Shortcut group: changing the board.
  ///
  /// In en, this message translates to:
  /// **'Editing'**
  String get shortcutsEditing;

  /// Shortcut group: moving around with the keyboard.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get shortcutsNavigation;

  /// Shortcut: open board search.
  ///
  /// In en, this message translates to:
  /// **'Search every level'**
  String get shortcutSearch;

  /// Shortcut: drag the canvas.
  ///
  /// In en, this message translates to:
  /// **'Pan the board'**
  String get shortcutPan;

  /// Shortcut: wheel zoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom toward the pointer'**
  String get shortcutZoom;

  /// Shortcut: open the shortcuts dialog.
  ///
  /// In en, this message translates to:
  /// **'Show this list'**
  String get shortcutHelp;

  /// Shortcut: delete key.
  ///
  /// In en, this message translates to:
  /// **'Delete the selection'**
  String get shortcutDelete;

  /// Shortcut: escape key.
  ///
  /// In en, this message translates to:
  /// **'Cancel a connection, then clear the selection'**
  String get shortcutEscape;

  /// Shortcut: shift-drag marquee selection on empty canvas.
  ///
  /// In en, this message translates to:
  /// **'Select several with a rectangle'**
  String get shortcutMarquee;

  /// Shortcut: tab key.
  ///
  /// In en, this message translates to:
  /// **'Focus the next visible card'**
  String get shortcutFocusCard;

  /// Shortcut: enter key.
  ///
  /// In en, this message translates to:
  /// **'Open details, enter a fold, or go to the original'**
  String get shortcutOpen;

  /// Shortcut: arrow keys.
  ///
  /// In en, this message translates to:
  /// **'Move the selected card'**
  String get shortcutMove;

  /// Shortcut: shift with arrow keys.
  ///
  /// In en, this message translates to:
  /// **'Move it four times further'**
  String get shortcutMoveFar;

  /// Shortcut: duplicate a card in place.
  ///
  /// In en, this message translates to:
  /// **'Duplicate the selection'**
  String get shortcutDuplicate;

  /// Shortcut: copy a card.
  ///
  /// In en, this message translates to:
  /// **'Copy the selection'**
  String get shortcutCopy;

  /// Shortcut: paste a copied card.
  ///
  /// In en, this message translates to:
  /// **'Paste into this level'**
  String get shortcutPaste;

  /// Key legend: the mouse wheel.
  ///
  /// In en, this message translates to:
  /// **'Wheel'**
  String get keyWheel;

  /// Key legend: the middle mouse button.
  ///
  /// In en, this message translates to:
  /// **'Middle mouse'**
  String get keyMiddleMouse;

  /// Key legend: the four arrow keys.
  ///
  /// In en, this message translates to:
  /// **'Arrows'**
  String get keyArrows;

  /// Key legend suffix: hold and drag the pointer.
  ///
  /// In en, this message translates to:
  /// **'drag'**
  String get keyDrag;

  /// Heading of the empty board state.
  ///
  /// In en, this message translates to:
  /// **'This level is empty'**
  String get emptyBoardTitle;

  /// Body of the empty board state.
  ///
  /// In en, this message translates to:
  /// **'Add a block for one part of the plan, or a fold for anything that has its own inner level.'**
  String get emptyBoardBody;

  /// Footnote of the empty board state.
  ///
  /// In en, this message translates to:
  /// **'An agent can fill it in too, over WebMCP.'**
  String get emptyBoardAgentHint;

  /// Project card: number of blocks on the board.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No blocks} =1{1 block} other{{count} blocks}}'**
  String blockCount(int count);

  /// Project card: number of folds on the board.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no folds} =1{1 fold} other{{count} folds}}'**
  String foldCount(int count);

  /// Project card: number of arrows on the board.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no arrows} =1{1 arrow} other{{count} arrows}}'**
  String arrowCount(int count);

  /// Project card: its stored board is corrupt or unavailable.
  ///
  /// In en, this message translates to:
  /// **'Saved board could not be read'**
  String get projectUnreadable;

  /// Heading shown when the catalog is empty.
  ///
  /// In en, this message translates to:
  /// **'No projects yet'**
  String get noProjectsTitle;

  /// Body shown when the catalog is empty.
  ///
  /// In en, this message translates to:
  /// **'A project is one independent board with its own levels, history and agent requests.'**
  String get noProjectsBody;

  /// Project action: copy a project and its board.
  ///
  /// In en, this message translates to:
  /// **'Duplicate project'**
  String get duplicateProject;

  /// Default name for a duplicated project.
  ///
  /// In en, this message translates to:
  /// **'{name} copy'**
  String projectCopyName(String name);

  /// Export format: an image of the current level.
  ///
  /// In en, this message translates to:
  /// **'PNG'**
  String get exportPng;

  /// Export format: a Mermaid flowchart.
  ///
  /// In en, this message translates to:
  /// **'Mermaid'**
  String get exportMermaid;

  /// The PNG export could not be rendered.
  ///
  /// In en, this message translates to:
  /// **'Could not create the image. Try again.'**
  String get exportImageFailed;

  /// Selection action: copy a card in place.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicate;

  /// Selection action: put a card on the Foldboard clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// Board action: place the copied card on this level.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// Confirmation after copying a card.
  ///
  /// In en, this message translates to:
  /// **'Copied “{name}”'**
  String copiedCard(String name);

  /// Paste was requested with an empty clipboard.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been copied yet.'**
  String get clipboardEmpty;

  /// Summary shown when more than one board card is selected.
  ///
  /// In en, this message translates to:
  /// **'{count} cards selected'**
  String selectedCards(int count);

  /// The mode that straightens one thread through the board into a single line.
  ///
  /// In en, this message translates to:
  /// **'Trace'**
  String get trace;

  /// No description provided for @traceFromHere.
  ///
  /// In en, this message translates to:
  /// **'Trace from here'**
  String get traceFromHere;

  /// No description provided for @traceBetween.
  ///
  /// In en, this message translates to:
  /// **'Trace between'**
  String get traceBetween;

  /// No description provided for @traceThrough.
  ///
  /// In en, this message translates to:
  /// **'Trace through'**
  String get traceThrough;

  /// Trace entry offered on an external card, whose thread leaves this level.
  ///
  /// In en, this message translates to:
  /// **'Straighten'**
  String get traceStraighten;

  /// No description provided for @traceNoConnection.
  ///
  /// In en, this message translates to:
  /// **'These cards are not connected, so there is no thread to straighten.'**
  String get traceNoConnection;

  /// No description provided for @traceNothingToFollow.
  ///
  /// In en, this message translates to:
  /// **'No arrows to follow yet. Connect two cards, then trace.'**
  String get traceNothingToFollow;

  /// Length of the straightened thread.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 step} other{{count} steps}}'**
  String traceStepCount(int count);

  /// How much of the thread is folded back up.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{straightened} =1{1 fold folded} other{{count} folds folded}}'**
  String traceFoldedCount(int count);

  /// No description provided for @traceCollapseFold.
  ///
  /// In en, this message translates to:
  /// **'Fold {title} back into one card'**
  String traceCollapseFold(String title);

  /// Shown on a folded card; opening it puts those steps back on the line.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 step inside} other{{count} steps inside}}'**
  String traceStepsInside(int count);

  /// No description provided for @traceExpandAll.
  ///
  /// In en, this message translates to:
  /// **'Expand all'**
  String get traceExpandAll;

  /// No description provided for @traceOpenHere.
  ///
  /// In en, this message translates to:
  /// **'Open where it lives'**
  String get traceOpenHere;

  /// No description provided for @traceClose.
  ///
  /// In en, this message translates to:
  /// **'Close trace'**
  String get traceClose;

  /// Continuations this step has that the thread did not take.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 branch} other{{count} branches}}'**
  String traceBranchCount(int count);

  /// No description provided for @traceLoopsBack.
  ///
  /// In en, this message translates to:
  /// **'Loops back to {title}'**
  String traceLoopsBack(String title);

  /// Tooltip on an arrow that crosses down into a fold.
  ///
  /// In en, this message translates to:
  /// **'Into {title}'**
  String traceInto(String title);

  /// Tooltip on an arrow that crosses up out of a fold.
  ///
  /// In en, this message translates to:
  /// **'Out of {title}'**
  String traceOutOf(String title);

  /// No description provided for @traceNoLoop.
  ///
  /// In en, this message translates to:
  /// **'This card has no way back to itself, so there is no loop to trace.'**
  String get traceNoLoop;

  /// No description provided for @traceStartAt.
  ///
  /// In en, this message translates to:
  /// **'Start the thread at another card'**
  String get traceStartAt;

  /// No description provided for @traceEndAt.
  ///
  /// In en, this message translates to:
  /// **'End the thread at another card'**
  String get traceEndAt;

  /// No description provided for @traceRunOnStart.
  ///
  /// In en, this message translates to:
  /// **'Let the thread run back to its own start'**
  String get traceRunOnStart;

  /// No description provided for @traceRunOnEnd.
  ///
  /// In en, this message translates to:
  /// **'Let the thread run on to its own end'**
  String get traceRunOnEnd;

  /// Accessible name for the two ends of the thread in the trace bar.
  ///
  /// In en, this message translates to:
  /// **'{from} to {to}'**
  String traceEnds(String from, String to);

  /// No description provided for @traceDensityCards.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get traceDensityCards;

  /// No description provided for @traceDensityRead.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get traceDensityRead;

  /// No description provided for @traceCopyMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Copy as Markdown'**
  String get traceCopyMarkdown;

  /// No description provided for @traceCopied.
  ///
  /// In en, this message translates to:
  /// **'The trace is on the clipboard as Markdown.'**
  String get traceCopied;

  /// No description provided for @traceCopyFailed.
  ///
  /// In en, this message translates to:
  /// **'The clipboard is not available here. Select the text and copy it instead.'**
  String get traceCopyFailed;

  /// No description provided for @traceAnchor.
  ///
  /// In en, this message translates to:
  /// **'Traced from here'**
  String get traceAnchor;

  /// No description provided for @traceProfile.
  ///
  /// In en, this message translates to:
  /// **'Depth of the thread, step by step'**
  String get traceProfile;

  /// No description provided for @shortcutTrace.
  ///
  /// In en, this message translates to:
  /// **'Trace from the selection'**
  String get shortcutTrace;

  /// No description provided for @shortcutTraceStep.
  ///
  /// In en, this message translates to:
  /// **'Step along the trace'**
  String get shortcutTraceStep;

  /// No description provided for @shortcutTraceBranch.
  ///
  /// In en, this message translates to:
  /// **'Take another branch'**
  String get shortcutTraceBranch;

  /// No description provided for @shortcutTraceOpen.
  ///
  /// In en, this message translates to:
  /// **'Open the step where it lives'**
  String get shortcutTraceOpen;

  /// No description provided for @shortcutTraceDensity.
  ///
  /// In en, this message translates to:
  /// **'Cards or Text'**
  String get shortcutTraceDensity;

  /// No description provided for @shortcutsTrace.
  ///
  /// In en, this message translates to:
  /// **'Trace'**
  String get shortcutsTrace;

  /// Confirmation text for deleting multiple selected cards.
  ///
  /// In en, this message translates to:
  /// **'The selected cards and their connected arrows will be deleted.'**
  String get deleteSelectedCardsMessage;

  /// No description provided for @overview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overview;

  /// No description provided for @overviewTooltip.
  ///
  /// In en, this message translates to:
  /// **'See the scale of the whole board'**
  String get overviewTooltip;

  /// No description provided for @overviewReadOnly.
  ///
  /// In en, this message translates to:
  /// **'View only'**
  String get overviewReadOnly;

  /// No description provided for @overviewHint.
  ///
  /// In en, this message translates to:
  /// **'Scroll to zoom. Drag to move.'**
  String get overviewHint;

  /// No description provided for @overviewEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing to map yet'**
  String get overviewEmptyTitle;

  /// No description provided for @overviewEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Add blocks to see the scale of the board here.'**
  String get overviewEmptyHint;

  /// No description provided for @overviewOpenFold.
  ///
  /// In en, this message translates to:
  /// **'Open {title}'**
  String overviewOpenFold(String title);

  /// No description provided for @overviewStats.
  ///
  /// In en, this message translates to:
  /// **'{blocks} blocks · {connections} connections'**
  String overviewStats(int blocks, int connections);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'en':
      {
        switch (locale.countryCode) {
          case 'US':
            return AppLocalizationsEnUs();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
