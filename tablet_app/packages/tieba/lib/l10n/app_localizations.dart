import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
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
    Locale('zh'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Tieba Lite'**
  String get appTitle;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @explore.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get explore;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get notifications;

  /// No description provided for @me.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get me;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search forums, posts, or people'**
  String get searchHint;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @emptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get emptyTitle;

  /// No description provided for @emptyBody.
  ///
  /// In en, this message translates to:
  /// **'Pull down to refresh, or try again later.'**
  String get emptyBody;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Could not load this page'**
  String get networkError;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @loginNeeded.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue'**
  String get loginNeeded;

  /// No description provided for @loginBody.
  ///
  /// In en, this message translates to:
  /// **'Use your Baidu account to follow forums, save posts, and join conversations.'**
  String get loginBody;

  /// No description provided for @loginPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Your sign-in takes place on Baidu. Account cookies are kept in the device Keychain.'**
  String get loginPrivacy;

  /// No description provided for @accounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accounts;

  /// No description provided for @addAccount.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get addAccount;

  /// No description provided for @removeAccount.
  ///
  /// In en, this message translates to:
  /// **'Remove account'**
  String get removeAccount;

  /// No description provided for @removeAccountBody.
  ///
  /// In en, this message translates to:
  /// **'Remove this account from this device? Your Baidu account will not be deleted.'**
  String get removeAccountBody;

  /// No description provided for @activeAccount.
  ///
  /// In en, this message translates to:
  /// **'Current account'**
  String get activeAccount;

  /// No description provided for @followedForums.
  ///
  /// In en, this message translates to:
  /// **'Followed forums'**
  String get followedForums;

  /// No description provided for @pinnedForums.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinnedForums;

  /// No description provided for @recentForums.
  ///
  /// In en, this message translates to:
  /// **'Recently visited'**
  String get recentForums;

  /// No description provided for @openForum.
  ///
  /// In en, this message translates to:
  /// **'Open a forum'**
  String get openForum;

  /// No description provided for @forumName.
  ///
  /// In en, this message translates to:
  /// **'Forum name'**
  String get forumName;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @pin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pin;

  /// No description provided for @unpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// No description provided for @gridView.
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get gridView;

  /// No description provided for @listView.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get listView;

  /// No description provided for @signAll.
  ///
  /// In en, this message translates to:
  /// **'Check in to followed forums'**
  String get signAll;

  /// No description provided for @signAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'Check in to all followed forums with your current account?'**
  String get signAllConfirm;

  /// No description provided for @checkIn.
  ///
  /// In en, this message translates to:
  /// **'Check in'**
  String get checkIn;

  /// No description provided for @checkedIn.
  ///
  /// In en, this message translates to:
  /// **'Checked in'**
  String get checkedIn;

  /// No description provided for @notCheckedIn.
  ///
  /// In en, this message translates to:
  /// **'Not checked in'**
  String get notCheckedIn;

  /// No description provided for @follow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get follow;

  /// No description provided for @unfollow.
  ///
  /// In en, this message translates to:
  /// **'Unfollow'**
  String get unfollow;

  /// No description provided for @following.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get following;

  /// No description provided for @followers.
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get followers;

  /// No description provided for @posts.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get posts;

  /// No description provided for @threads.
  ///
  /// In en, this message translates to:
  /// **'Threads'**
  String get threads;

  /// No description provided for @replies.
  ///
  /// In en, this message translates to:
  /// **'Replies'**
  String get replies;

  /// No description provided for @members.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'All posts'**
  String get general;

  /// No description provided for @digest.
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get digest;

  /// No description provided for @latestReply.
  ///
  /// In en, this message translates to:
  /// **'Latest reply'**
  String get latestReply;

  /// No description provided for @latestPost.
  ///
  /// In en, this message translates to:
  /// **'Latest post'**
  String get latestPost;

  /// No description provided for @forumInfo.
  ///
  /// In en, this message translates to:
  /// **'About this forum'**
  String get forumInfo;

  /// No description provided for @forumRules.
  ///
  /// In en, this message translates to:
  /// **'Forum rules'**
  String get forumRules;

  /// No description provided for @searchInForum.
  ///
  /// In en, this message translates to:
  /// **'Search this forum'**
  String get searchInForum;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @link.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get link;

  /// No description provided for @newPostUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This upstream branch does not implement new-thread publishing.'**
  String get newPostUnavailable;

  /// No description provided for @recommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get recommended;

  /// No description provided for @concern.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get concern;

  /// No description provided for @hot.
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get hot;

  /// No description provided for @replyMe.
  ///
  /// In en, this message translates to:
  /// **'Replies to me'**
  String get replyMe;

  /// No description provided for @mentionMe.
  ///
  /// In en, this message translates to:
  /// **'Mentions'**
  String get mentionMe;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Saved posts'**
  String get favorites;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @drafts.
  ///
  /// In en, this message translates to:
  /// **'Drafts'**
  String get drafts;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @viewProfile.
  ///
  /// In en, this message translates to:
  /// **'View profile'**
  String get viewProfile;

  /// No description provided for @myPosts.
  ///
  /// In en, this message translates to:
  /// **'My posts'**
  String get myPosts;

  /// No description provided for @myForums.
  ///
  /// In en, this message translates to:
  /// **'My forums'**
  String get myForums;

  /// No description provided for @userPosts.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get userPosts;

  /// No description provided for @userReplies.
  ///
  /// In en, this message translates to:
  /// **'Replies'**
  String get userReplies;

  /// No description provided for @unknownUser.
  ///
  /// In en, this message translates to:
  /// **'Tieba user'**
  String get unknownUser;

  /// No description provided for @visitor.
  ///
  /// In en, this message translates to:
  /// **'Browse as a guest'**
  String get visitor;

  /// No description provided for @visitorBody.
  ///
  /// In en, this message translates to:
  /// **'Find a forum or explore what people are discussing.'**
  String get visitorBody;

  /// No description provided for @noTitle.
  ///
  /// In en, this message translates to:
  /// **'Untitled post'**
  String get noTitle;

  /// No description provided for @reply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get reply;

  /// No description provided for @replyHint.
  ///
  /// In en, this message translates to:
  /// **'Write a reply…'**
  String get replyHint;

  /// No description provided for @replyTo.
  ///
  /// In en, this message translates to:
  /// **'Reply to'**
  String get replyTo;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @sending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get sending;

  /// No description provided for @replySent.
  ///
  /// In en, this message translates to:
  /// **'Reply sent'**
  String get replySent;

  /// No description provided for @replyWarning.
  ///
  /// In en, this message translates to:
  /// **'Replies are sent to Baidu Tieba with your account. Baidu may require verification or reject a request.'**
  String get replyWarning;

  /// No description provided for @attachImages.
  ///
  /// In en, this message translates to:
  /// **'Attach images'**
  String get attachImages;

  /// No description provided for @originalImage.
  ///
  /// In en, this message translates to:
  /// **'Original image'**
  String get originalImage;

  /// No description provided for @emoticons.
  ///
  /// In en, this message translates to:
  /// **'Emoticons'**
  String get emoticons;

  /// No description provided for @draftSaved.
  ///
  /// In en, this message translates to:
  /// **'Draft saved'**
  String get draftSaved;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @saveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save draft'**
  String get saveDraft;

  /// No description provided for @leaveDraftTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep this draft?'**
  String get leaveDraftTitle;

  /// No description provided for @leaveDraftBody.
  ///
  /// In en, this message translates to:
  /// **'You have an unsent reply.'**
  String get leaveDraftBody;

  /// No description provided for @textRequired.
  ///
  /// In en, this message translates to:
  /// **'Write a reply or attach an image.'**
  String get textRequired;

  /// No description provided for @onlyAuthor.
  ///
  /// In en, this message translates to:
  /// **'Author only'**
  String get onlyAuthor;

  /// No description provided for @allReplies.
  ///
  /// In en, this message translates to:
  /// **'All replies'**
  String get allReplies;

  /// No description provided for @oldestFirst.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get oldestFirst;

  /// No description provided for @newestFirst.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get newestFirst;

  /// No description provided for @jumpPage.
  ///
  /// In en, this message translates to:
  /// **'Jump to page'**
  String get jumpPage;

  /// No description provided for @page.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get page;

  /// No description provided for @invalidPage.
  ///
  /// In en, this message translates to:
  /// **'Enter a page number greater than zero.'**
  String get invalidPage;

  /// No description provided for @readerMode.
  ///
  /// In en, this message translates to:
  /// **'Reading mode'**
  String get readerMode;

  /// No description provided for @savePost.
  ///
  /// In en, this message translates to:
  /// **'Save post'**
  String get savePost;

  /// No description provided for @unsavePost.
  ///
  /// In en, this message translates to:
  /// **'Remove from saved'**
  String get unsavePost;

  /// No description provided for @like.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get like;

  /// No description provided for @unlike.
  ///
  /// In en, this message translates to:
  /// **'Unlike'**
  String get unlike;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @floorReplies.
  ///
  /// In en, this message translates to:
  /// **'Replies in this floor'**
  String get floorReplies;

  /// No description provided for @noReplies.
  ///
  /// In en, this message translates to:
  /// **'No replies yet'**
  String get noReplies;

  /// No description provided for @report.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get report;

  /// No description provided for @blockUser.
  ///
  /// In en, this message translates to:
  /// **'Block user'**
  String get blockUser;

  /// No description provided for @unblockUser.
  ///
  /// In en, this message translates to:
  /// **'Unblock user'**
  String get unblockUser;

  /// No description provided for @blocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get blocked;

  /// No description provided for @deletePost.
  ///
  /// In en, this message translates to:
  /// **'Delete post'**
  String get deletePost;

  /// No description provided for @deleteThread.
  ///
  /// In en, this message translates to:
  /// **'Delete thread'**
  String get deleteThread;

  /// No description provided for @deleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'This action removes your content from Tieba. Continue?'**
  String get deleteConfirm;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @operationSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get operationSucceeded;

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'The request failed'**
  String get operationFailed;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @relevance.
  ///
  /// In en, this message translates to:
  /// **'Relevance'**
  String get relevance;

  /// No description provided for @searchForums.
  ///
  /// In en, this message translates to:
  /// **'Forums'**
  String get searchForums;

  /// No description provided for @searchThreads.
  ///
  /// In en, this message translates to:
  /// **'Posts'**
  String get searchThreads;

  /// No description provided for @searchUsers.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get searchUsers;

  /// No description provided for @searchHistory.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get searchHistory;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get clearHistory;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @clearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear this history from this device?'**
  String get clearConfirm;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfile;

  /// No description provided for @editOnBaidu.
  ///
  /// In en, this message translates to:
  /// **'Edit on Baidu'**
  String get editOnBaidu;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @reading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get reading;

  /// No description provided for @privacyAndFilters.
  ///
  /// In en, this message translates to:
  /// **'Content filters'**
  String get privacyAndFilters;

  /// No description provided for @systemTheme.
  ///
  /// In en, this message translates to:
  /// **'Use system appearance'**
  String get systemTheme;

  /// No description provided for @lightTheme.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get lightTheme;

  /// No description provided for @darkTheme.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get darkTheme;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get fontSize;

  /// No description provided for @compactCards.
  ///
  /// In en, this message translates to:
  /// **'Compact cards'**
  String get compactCards;

  /// No description provided for @showImages.
  ///
  /// In en, this message translates to:
  /// **'Show images'**
  String get showImages;

  /// No description provided for @hideVideo.
  ///
  /// In en, this message translates to:
  /// **'Hide video posts'**
  String get hideVideo;

  /// No description provided for @hideBlocked.
  ///
  /// In en, this message translates to:
  /// **'Hide blocked content'**
  String get hideBlocked;

  /// No description provided for @blockedUsers.
  ///
  /// In en, this message translates to:
  /// **'Blocked users'**
  String get blockedUsers;

  /// No description provided for @blockedKeywords.
  ///
  /// In en, this message translates to:
  /// **'Blocked keywords'**
  String get blockedKeywords;

  /// No description provided for @addKeyword.
  ///
  /// In en, this message translates to:
  /// **'Add keyword'**
  String get addKeyword;

  /// No description provided for @keyword.
  ///
  /// In en, this message translates to:
  /// **'Keyword'**
  String get keyword;

  /// No description provided for @hideExplore.
  ///
  /// In en, this message translates to:
  /// **'Hide Discover tab'**
  String get hideExplore;

  /// No description provided for @showRecentForums.
  ///
  /// In en, this message translates to:
  /// **'Show recently visited forums'**
  String get showRecentForums;

  /// No description provided for @restoreReading.
  ///
  /// In en, this message translates to:
  /// **'Resume reading position'**
  String get restoreReading;

  /// No description provided for @imageDarken.
  ///
  /// In en, this message translates to:
  /// **'Dim images in dark mode'**
  String get imageDarken;

  /// No description provided for @followSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get followSystem;

  /// No description provided for @defaultSort.
  ///
  /// In en, this message translates to:
  /// **'Default post order'**
  String get defaultSort;

  /// No description provided for @localData.
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get localData;

  /// No description provided for @clearSearchHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear search history'**
  String get clearSearchHistory;

  /// No description provided for @clearReadingHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear reading history'**
  String get clearReadingHistory;

  /// No description provided for @emptyDrafts.
  ///
  /// In en, this message translates to:
  /// **'Your unfinished replies will appear here.'**
  String get emptyDrafts;

  /// No description provided for @emptyFavorites.
  ///
  /// In en, this message translates to:
  /// **'Posts you save on Tieba will appear here.'**
  String get emptyFavorites;

  /// No description provided for @emptyForums.
  ///
  /// In en, this message translates to:
  /// **'Follow a forum to keep it close.'**
  String get emptyForums;

  /// No description provided for @emptyNotifications.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up.'**
  String get emptyNotifications;

  /// No description provided for @sourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get sourceCode;

  /// No description provided for @upstreamProject.
  ///
  /// In en, this message translates to:
  /// **'Upstream project'**
  String get upstreamProject;

  /// No description provided for @licenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get licenses;

  /// No description provided for @aboutBody.
  ///
  /// In en, this message translates to:
  /// **'An unofficial Flutter port inspired by Tieba Lite. This project is not affiliated with Baidu or the upstream author.'**
  String get aboutBody;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @media.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get media;

  /// No description provided for @saveImage.
  ///
  /// In en, this message translates to:
  /// **'Save image'**
  String get saveImage;

  /// No description provided for @imageSaved.
  ///
  /// In en, this message translates to:
  /// **'Image saved'**
  String get imageSaved;

  /// No description provided for @saveImageViaShare.
  ///
  /// In en, this message translates to:
  /// **'Choose Save Image in the share sheet.'**
  String get saveImageViaShare;

  /// No description provided for @openInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get openInBrowser;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @video.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get video;

  /// No description provided for @audio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audio;

  /// No description provided for @unsupportedContent.
  ///
  /// In en, this message translates to:
  /// **'Open this content in the browser'**
  String get unsupportedContent;

  /// No description provided for @contentHidden.
  ///
  /// In en, this message translates to:
  /// **'Content hidden by your filters'**
  String get contentHidden;

  /// No description provided for @showContent.
  ///
  /// In en, this message translates to:
  /// **'Show content'**
  String get showContent;

  /// No description provided for @signedOut.
  ///
  /// In en, this message translates to:
  /// **'Signed out'**
  String get signedOut;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @checkInComplete.
  ///
  /// In en, this message translates to:
  /// **'Check-in requests completed'**
  String get checkInComplete;

  /// No description provided for @tapToLoad.
  ///
  /// In en, this message translates to:
  /// **'Tap to load'**
  String get tapToLoad;

  /// No description provided for @upstreamScope.
  ///
  /// In en, this message translates to:
  /// **'Feature status'**
  String get upstreamScope;

  /// No description provided for @accountCookiesMissing.
  ///
  /// In en, this message translates to:
  /// **'Baidu did not return a complete login session. Please finish signing in and try again.'**
  String get accountCookiesMissing;

  /// No description provided for @selectAccount.
  ///
  /// In en, this message translates to:
  /// **'Switch account'**
  String get selectAccount;

  /// No description provided for @accountRemoved.
  ///
  /// In en, this message translates to:
  /// **'Account removed'**
  String get accountRemoved;

  /// No description provided for @forumNotFound.
  ///
  /// In en, this message translates to:
  /// **'No matching forum'**
  String get forumNotFound;

  /// No description provided for @forumShortcut.
  ///
  /// In en, this message translates to:
  /// **'Forum shortcut'**
  String get forumShortcut;

  /// No description provided for @openByLink.
  ///
  /// In en, this message translates to:
  /// **'Open a Tieba link'**
  String get openByLink;

  /// No description provided for @pasteLink.
  ///
  /// In en, this message translates to:
  /// **'Paste a thread URL or ID'**
  String get pasteLink;

  /// No description provided for @invalidLink.
  ///
  /// In en, this message translates to:
  /// **'Enter a Tieba thread URL or numeric thread ID.'**
  String get invalidLink;

  /// No description provided for @enterForum.
  ///
  /// In en, this message translates to:
  /// **'Enter the forum name without the suffix.'**
  String get enterForum;

  /// No description provided for @followed.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get followed;

  /// No description provided for @notFollowing.
  ///
  /// In en, this message translates to:
  /// **'Not followed'**
  String get notFollowing;

  /// No description provided for @viewReplies.
  ///
  /// In en, this message translates to:
  /// **'View replies'**
  String get viewReplies;

  /// No description provided for @browse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get browse;

  /// No description provided for @current.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get current;

  /// No description provided for @sort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @userId.
  ///
  /// In en, this message translates to:
  /// **'User ID'**
  String get userId;

  /// No description provided for @nickname.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nickname;

  /// No description provided for @intro.
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get intro;

  /// No description provided for @accountInfo.
  ///
  /// In en, this message translates to:
  /// **'Account details'**
  String get accountInfo;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @sendingImages.
  ///
  /// In en, this message translates to:
  /// **'Uploading images…'**
  String get sendingImages;

  /// No description provided for @removeImage.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get removeImage;

  /// No description provided for @copiedText.
  ///
  /// In en, this message translates to:
  /// **'Text copied'**
  String get copiedText;

  /// No description provided for @copyText.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get copyText;

  /// No description provided for @replyDraft.
  ///
  /// In en, this message translates to:
  /// **'Reply draft'**
  String get replyDraft;

  /// No description provided for @threadId.
  ///
  /// In en, this message translates to:
  /// **'Thread ID'**
  String get threadId;

  /// No description provided for @forumId.
  ///
  /// In en, this message translates to:
  /// **'Forum ID'**
  String get forumId;

  /// No description provided for @noSession.
  ///
  /// In en, this message translates to:
  /// **'No account signed in'**
  String get noSession;

  /// No description provided for @advanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advanced;

  /// No description provided for @openOriginal.
  ///
  /// In en, this message translates to:
  /// **'Open original page'**
  String get openOriginal;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @followsSystem.
  ///
  /// In en, this message translates to:
  /// **'Follows system'**
  String get followsSystem;

  /// No description provided for @autoCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Automatic check-in'**
  String get autoCheckIn;

  /// No description provided for @autoCheckInBody.
  ///
  /// In en, this message translates to:
  /// **'iOS does not guarantee scheduled background work. Check in manually from Home.'**
  String get autoCheckInBody;

  /// No description provided for @footerHint.
  ///
  /// In en, this message translates to:
  /// **'Built for a quieter reading experience.'**
  String get footerHint;

  /// No description provided for @initializationFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the data stored on this device. Try again.'**
  String get initializationFailed;

  /// No description provided for @nativeLoginOnly.
  ///
  /// In en, this message translates to:
  /// **'Sign-in is available in the iOS app. The web preview supports guest browsing.'**
  String get nativeLoginOnly;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Baidu sign-in'**
  String get loginTitle;

  /// No description provided for @apiVerificationRequired.
  ///
  /// In en, this message translates to:
  /// **'Baidu requires additional verification. Complete it on the official page and try again.'**
  String get apiVerificationRequired;

  /// No description provided for @hideReply.
  ///
  /// In en, this message translates to:
  /// **'Hide inline floor replies'**
  String get hideReply;

  /// No description provided for @signature.
  ///
  /// In en, this message translates to:
  /// **'Reply signature'**
  String get signature;

  /// No description provided for @replyWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm before sending'**
  String get replyWarningTitle;

  /// No description provided for @replySentCleanupFailed.
  ///
  /// In en, this message translates to:
  /// **'Reply sent. The local draft could not be removed; do not send it again.'**
  String get replySentCleanupFailed;

  /// No description provided for @swipeTabs.
  ///
  /// In en, this message translates to:
  /// **'Swipe between main tabs'**
  String get swipeTabs;

  /// No description provided for @repeatPinnedForums.
  ///
  /// In en, this message translates to:
  /// **'Keep pinned forums in the full list'**
  String get repeatPinnedForums;

  /// No description provided for @hideForumHeader.
  ///
  /// In en, this message translates to:
  /// **'Hide forum description and statistics'**
  String get hideForumHeader;

  /// No description provided for @savedAuthorOnly.
  ///
  /// In en, this message translates to:
  /// **'Open saved posts in author-only mode'**
  String get savedAuthorOnly;

  /// No description provided for @savedNewestFirst.
  ///
  /// In en, this message translates to:
  /// **'Open saved posts newest first'**
  String get savedNewestFirst;

  /// No description provided for @slowCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Pause between check-ins'**
  String get slowCheckIn;

  /// No description provided for @accentColor.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get accentColor;

  /// No description provided for @cornerRadius.
  ///
  /// In en, this message translates to:
  /// **'Corner radius'**
  String get cornerRadius;

  /// No description provided for @coloredToolbar.
  ///
  /// In en, this message translates to:
  /// **'Use accent-colored toolbar'**
  String get coloredToolbar;

  /// No description provided for @imageLoadPolicy.
  ///
  /// In en, this message translates to:
  /// **'Load images'**
  String get imageLoadPolicy;

  /// No description provided for @imageLoadAlways.
  ///
  /// In en, this message translates to:
  /// **'Automatically'**
  String get imageLoadAlways;

  /// No description provided for @imageLoadTap.
  ///
  /// In en, this message translates to:
  /// **'When tapped'**
  String get imageLoadTap;

  /// No description provided for @profileSex.
  ///
  /// In en, this message translates to:
  /// **'Sex'**
  String get profileSex;

  /// No description provided for @profileSexUnset.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get profileSexUnset;

  /// No description provided for @profileSexMale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get profileSexMale;

  /// No description provided for @profileSexFemale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get profileSexFemale;

  /// No description provided for @changeAvatar.
  ///
  /// In en, this message translates to:
  /// **'Change avatar'**
  String get changeAvatar;

  /// No description provided for @cropAvatar.
  ///
  /// In en, this message translates to:
  /// **'Crop avatar'**
  String get cropAvatar;

  /// No description provided for @cropHint.
  ///
  /// In en, this message translates to:
  /// **'Drag and zoom to frame your avatar'**
  String get cropHint;

  /// No description provided for @avatarSaved.
  ///
  /// In en, this message translates to:
  /// **'Avatar updated'**
  String get avatarSaved;

  /// No description provided for @avatarPending.
  ///
  /// In en, this message translates to:
  /// **'Avatar will upload when you save'**
  String get avatarPending;

  /// No description provided for @profilePartialSave.
  ///
  /// In en, this message translates to:
  /// **'Some changes were saved. Retry the remaining changes.'**
  String get profilePartialSave;

  /// No description provided for @profileSaveUncertain.
  ///
  /// In en, this message translates to:
  /// **'The connection was interrupted. Refresh your profile before deciding whether to retry.'**
  String get profileSaveUncertain;

  /// No description provided for @discardProfileChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard unsaved profile changes?'**
  String get discardProfileChanges;

  /// No description provided for @imageUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Unable to read this image. Choose JPEG or PNG.'**
  String get imageUnsupported;

  /// No description provided for @profileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get profileUpdated;

  /// No description provided for @imageSmartOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original on Wi-Fi, preview on mobile data'**
  String get imageSmartOriginal;

  /// No description provided for @imageSmartLoad.
  ///
  /// In en, this message translates to:
  /// **'Automatically on Wi-Fi only'**
  String get imageSmartLoad;

  /// No description provided for @imageAllOriginal.
  ///
  /// In en, this message translates to:
  /// **'Always load original images'**
  String get imageAllOriginal;

  /// No description provided for @imageNever.
  ///
  /// In en, this message translates to:
  /// **'Tap to load images'**
  String get imageNever;

  /// No description provided for @showBlockTip.
  ///
  /// In en, this message translates to:
  /// **'Show a notice for blocked content'**
  String get showBlockTip;

  /// No description provided for @bothUserNames.
  ///
  /// In en, this message translates to:
  /// **'Show username and nickname'**
  String get bothUserNames;

  /// No description provided for @hotTopics.
  ///
  /// In en, this message translates to:
  /// **'Trending topics'**
  String get hotTopics;

  /// No description provided for @topicDiscussion.
  ///
  /// In en, this message translates to:
  /// **'Discussion'**
  String get topicDiscussion;

  /// No description provided for @topicHeat.
  ///
  /// In en, this message translates to:
  /// **'Popularity'**
  String get topicHeat;

  /// No description provided for @backgroundTheme.
  ///
  /// In en, this message translates to:
  /// **'Background theme'**
  String get backgroundTheme;

  /// No description provided for @chooseBackground.
  ///
  /// In en, this message translates to:
  /// **'Choose background image'**
  String get chooseBackground;

  /// No description provided for @removeBackground.
  ///
  /// In en, this message translates to:
  /// **'Remove background image'**
  String get removeBackground;

  /// No description provided for @backgroundBlur.
  ///
  /// In en, this message translates to:
  /// **'Background blur'**
  String get backgroundBlur;

  /// No description provided for @surfaceOpacity.
  ///
  /// In en, this message translates to:
  /// **'Card opacity'**
  String get surfaceOpacity;

  /// No description provided for @backgroundShade.
  ///
  /// In en, this message translates to:
  /// **'Background shade'**
  String get backgroundShade;

  /// No description provided for @loadWhileScrolling.
  ///
  /// In en, this message translates to:
  /// **'Load images while scrolling'**
  String get loadWhileScrolling;

  /// No description provided for @watermark.
  ///
  /// In en, this message translates to:
  /// **'Uploaded image watermark'**
  String get watermark;

  /// No description provided for @watermarkNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get watermarkNone;

  /// No description provided for @watermarkUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get watermarkUsername;

  /// No description provided for @watermarkForum.
  ///
  /// In en, this message translates to:
  /// **'Forum name'**
  String get watermarkForum;

  /// No description provided for @officialBatchCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Use Tieba batch check-in when available'**
  String get officialBatchCheckIn;

  /// No description provided for @hide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hide;

  /// No description provided for @forumFab.
  ///
  /// In en, this message translates to:
  /// **'Forum floating button'**
  String get forumFab;

  /// No description provided for @backToTop.
  ///
  /// In en, this message translates to:
  /// **'Back to top'**
  String get backToTop;

  /// No description provided for @threadShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Thread shortcuts'**
  String get threadShortcuts;

  /// No description provided for @darkPalette.
  ///
  /// In en, this message translates to:
  /// **'Dark palette'**
  String get darkPalette;

  /// No description provided for @alternatingCards.
  ///
  /// In en, this message translates to:
  /// **'Alternating list backgrounds'**
  String get alternatingCards;

  /// No description provided for @allowRules.
  ///
  /// In en, this message translates to:
  /// **'Allow rules'**
  String get allowRules;

  /// No description provided for @darkBlack.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get darkBlack;

  /// No description provided for @blockRules.
  ///
  /// In en, this message translates to:
  /// **'Block rules'**
  String get blockRules;

  /// No description provided for @userIdOrName.
  ///
  /// In en, this message translates to:
  /// **'User ID or username'**
  String get userIdOrName;

  /// No description provided for @keywordGroup.
  ///
  /// In en, this message translates to:
  /// **'Keyword group'**
  String get keywordGroup;

  /// No description provided for @darkGrey.
  ///
  /// In en, this message translates to:
  /// **'Grey'**
  String get darkGrey;

  /// No description provided for @darkBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get darkBlue;

  /// No description provided for @keywordGroupHint.
  ///
  /// In en, this message translates to:
  /// **'One keyword per line. Every word must occur in the same title or text. Matching is case-sensitive.'**
  String get keywordGroupHint;

  /// No description provided for @linksInApp.
  ///
  /// In en, this message translates to:
  /// **'Open links inside the app'**
  String get linksInApp;

  /// No description provided for @localDataRecoveryNotice.
  ///
  /// In en, this message translates to:
  /// **'Some local records could not be opened. The original data has been preserved; you can continue in guest mode or switch accounts.'**
  String get localDataRecoveryNotice;

  /// No description provided for @iconBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get iconBlue;

  /// No description provided for @removeFromHistory.
  ///
  /// In en, this message translates to:
  /// **'Remove from history'**
  String get removeFromHistory;

  /// No description provided for @forums.
  ///
  /// In en, this message translates to:
  /// **'Forums'**
  String get forums;

  /// No description provided for @imageCache.
  ///
  /// In en, this message translates to:
  /// **'Image cache'**
  String get imageCache;

  /// No description provided for @clearImageCache.
  ///
  /// In en, this message translates to:
  /// **'Clear image cache'**
  String get clearImageCache;

  /// No description provided for @iconDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get iconDark;

  /// No description provided for @cacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Image cache cleared'**
  String get cacheCleared;

  /// No description provided for @appIcon.
  ///
  /// In en, this message translates to:
  /// **'App icon'**
  String get appIcon;

  /// No description provided for @iconUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Alternate icons are available in the installed iPhone app.'**
  String get iconUnavailable;

  /// No description provided for @iconDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get iconDefault;

  /// No description provided for @cacheSizeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Disk cache size is unavailable on this platform.'**
  String get cacheSizeUnknown;

  /// No description provided for @clearImageCacheConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear cached viewing images? Draft attachments and your theme background will be kept.'**
  String get clearImageCacheConfirm;

  /// No description provided for @serviceCenter.
  ///
  /// In en, this message translates to:
  /// **'Service center'**
  String get serviceCenter;

  /// No description provided for @fontFamily.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get fontFamily;

  /// No description provided for @systemFont.
  ///
  /// In en, this message translates to:
  /// **'System font'**
  String get systemFont;

  /// No description provided for @notoSans.
  ///
  /// In en, this message translates to:
  /// **'Noto Sans'**
  String get notoSans;

  /// No description provided for @fontPreview.
  ///
  /// In en, this message translates to:
  /// **'Read slowly, see clearly. Let each line feel natural.'**
  String get fontPreview;
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
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
