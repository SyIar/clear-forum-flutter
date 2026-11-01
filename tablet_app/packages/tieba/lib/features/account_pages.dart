import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../platform/baidu_action_page.dart';
import '../widgets/common.dart';
import '../widgets/content_cards.dart';
import '../widgets/paged_list.dart';
import 'main_shell.dart';
import 'history_page.dart';
import 'reply_page.dart';
import 'profile_editor.dart';
import 'settings_page.dart';
import 'thread_page.dart';

export 'history_page.dart' show HistoryPage;

class MePage extends StatelessWidget {
  const MePage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final user = app.profile;
    return Scaffold(
      appBar: GlassAppBar(
        title: Text(context.l10n.me),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const AccountsPage()),
            ),
            icon: const Icon(Icons.manage_accounts_outlined),
            tooltip: context.l10n.accounts,
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: 32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () =>
                  user == null ? app.login(context) : openUser(context, user),
              child: Row(
                children: [
                  UserAvatar(
                    url: user?.avatar ?? '',
                    name: user?.name ?? '',
                    radius: 37,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name.isNotEmpty == true
                              ? user!.name
                              : context.l10n.signIn,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          user == null
                              ? context.l10n.loginBody
                              : user.intro.isNotEmpty
                              ? user.intro
                              : context.l10n.viewProfile,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colors.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
          if (user != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _stat(context, context.l10n.following, user.followingCount),
                  _stat(context, context.l10n.followers, user.followerCount),
                  _stat(context, context.l10n.posts, user.threadCount),
                ],
              ),
            ),
          const SizedBox(height: 20),
          SurfaceCard(
            child: Column(
              children: [
                _item(
                  context,
                  Icons.bookmark_border_rounded,
                  context.l10n.favorites,
                  const FavoritesPage(),
                ),
                _item(
                  context,
                  Icons.history_rounded,
                  context.l10n.history,
                  const HistoryPage(),
                ),
                _item(
                  context,
                  Icons.edit_note_rounded,
                  context.l10n.drafts,
                  const DraftsPage(),
                ),
                if (user != null)
                  _item(
                    context,
                    Icons.forum_outlined,
                    context.l10n.myForums,
                    UserForumsPage(userId: user.id),
                  ),
              ],
            ),
          ),
          SurfaceCard(
            child: Column(
              children: [
                _item(
                  context,
                  Icons.tune_rounded,
                  context.l10n.settings,
                  const SettingsPage(),
                ),
                _item(
                  context,
                  Icons.manage_accounts_outlined,
                  context.l10n.accounts,
                  const AccountsPage(),
                ),
                ListTile(
                  leading: const Icon(Icons.support_agent_rounded),
                  title: Text(context.l10n.serviceCenter),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    if (!await requireAccount(context) || !context.mounted) {
                      return;
                    }
                    final session = AppScope.read(context).session;
                    if (session == null) return;
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BaiduActionPage(
                          url: Uri.parse(
                            'https://tieba.baidu.com/mo/q/hybrid-main-service/uegServiceCenter',
                          ),
                          session: session,
                          title: context.l10n.serviceCenter,
                          errorLabel: context.l10n.operationFailed,
                          retryLabel: context.l10n.retry,
                          unsupportedLabel: context.l10n.nativeLoginOnly,
                        ),
                      ),
                    );
                  },
                ),
                _item(
                  context,
                  Icons.info_outline_rounded,
                  context.l10n.about,
                  const AboutPage(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              context.l10n.footerHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.outline, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, int count) => Expanded(
    child: Column(
      children: [
        Text(
          compactCount(count),
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: context.colors.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
  Widget _item(
    BuildContext context,
    IconData icon,
    String title,
    Widget page,
  ) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () =>
        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page)),
  );
}

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: GlassAppBar(title: Text(context.l10n.accounts)),
      body: ListView(
        children: [
          for (final account in app.accounts)
            SurfaceCard(
              child: ListTile(
                leading: UserAvatar(
                  url: account.profile.avatar,
                  name: account.profile.name,
                ),
                title: Text(account.profile.name),
                subtitle: Text(
                  account.id == app.session?.userId
                      ? context.l10n.activeAccount
                      : account.id,
                ),
                onTap: app.changingAccount
                    ? null
                    : () => performAction(
                        context,
                        () => app.switchAccount(account.id),
                        requiresLogin: false,
                      ),
                trailing: PopupMenuButton<String>(
                  onSelected: (_) async {
                    if (await confirmAction(
                          context,
                          context.l10n.removeAccount,
                          context.l10n.removeAccountBody,
                        ) &&
                        context.mounted) {
                      await performAction(
                        context,
                        () => app.removeAccount(account.id),
                        requiresLogin: false,
                        success: context.l10n.accountRemoved,
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(context.l10n.removeAccount),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: FilledButton.tonalIcon(
              onPressed: app.changingAccount ? null : () => app.login(context),
              icon: const Icon(Icons.person_add_alt_rounded),
              label: Text(context.l10n.addAccount),
            ),
          ),
          if (app.isLoggedIn)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: OutlinedButton(
                onPressed: app.changingAccount
                    ? null
                    : () => performAction(
                        context,
                        () => app.switchAccount(null),
                        requiresLogin: false,
                        success: context.l10n.signedOut,
                      ),
                child: Text(context.l10n.signOut),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.l10n.loginPrivacy,
              style: TextStyle(
                color: context.colors.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: GlassAppBar(title: Text(context.l10n.favorites)),
      body: !app.isLoggedIn
          ? const LoginPanel()
          : PagedList<ThreadSummary>(
              key: ValueKey(app.session?.userId),
              load: (page) => app.api.favorites(page: page),
              emptyMessage: context.l10n.emptyFavorites,
              itemBuilder: (context, thread, _) => ThreadCard(
                thread: thread,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ThreadPage(
                      threadId: thread.id,
                      initialThread: thread,
                      anchorPostId: thread.lastPostId.isEmpty
                          ? null
                          : thread.lastPostId,
                    ),
                  ),
                ),
                onAuthorTap: () => openUser(context, thread.author),
                onForumTap: () => openForum(context, thread.forum.name),
              ),
            ),
    );
  }
}

class DraftsPage extends StatelessWidget {
  const DraftsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: GlassAppBar(title: Text(context.l10n.drafts)),
      body: app.local.drafts.isEmpty
          ? EmptyPanel(
              message: context.l10n.emptyDrafts,
              icon: Icons.edit_note_rounded,
            )
          : ListView.builder(
              itemCount: app.local.drafts.length,
              itemBuilder: (context, index) {
                final draft = app.local.drafts[index];
                return SurfaceCard(
                  child: ListTile(
                    title: Text(
                      draft.content.isEmpty
                          ? context.l10n.replyDraft
                          : draft.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${draft.forumName} · ${shortDate(context, draft.updatedAt)}',
                    ),
                    trailing: IconButton(
                      onPressed: () async {
                        if (await confirmAction(
                          context,
                          context.l10n.discard,
                          context.l10n.leaveDraftBody,
                        )) {
                          await app.local.removeDraft(draft.key);
                        }
                      },
                      icon: const Icon(Icons.close_rounded),
                      tooltip: context.l10n.discard,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<bool>(
                        builder: (_) => ReplyPage(
                          threadId: draft.threadId,
                          forum: Forum(name: draft.forumName),
                          draft: draft,
                          parentPostId: draft.parentPostId.isEmpty
                              ? null
                              : draft.parentPostId,
                          subPostId: draft.targetSubPostId.isEmpty
                              ? null
                              : draft.targetSubPostId,
                          replyUserId: draft.replyUserId.isEmpty
                              ? null
                              : draft.replyUserId,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key, required this.userId, this.initialUser});
  final String userId;
  final UserProfile? initialUser;
  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  Future<UserProfile>? _profile;
  bool _busy = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _profile ??= AppScope.read(context).api.userProfile(widget.userId);
  }

  void _refresh() => setState(
    () => _profile = AppScope.read(context).api.userProfile(widget.userId),
  );
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: GlassAppBar(
          title: Text(context.l10n.profile),
          actions: [
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => UserForumsPage(userId: widget.userId),
                ),
              ),
              icon: const Icon(Icons.forum_outlined),
              tooltip: context.l10n.myForums,
            ),
          ],
        ),
        body: Column(
          children: [
            FutureBuilder<UserProfile>(
              future: _profile,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SizedBox(
                    height: 260,
                    child: SingleChildScrollView(
                      child: ErrorPanel(
                        error: snapshot.error!,
                        onRetry: _refresh,
                      ),
                    ),
                  );
                }
                final user =
                    snapshot.data ?? widget.initialUser ?? const UserProfile();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          UserAvatar(
                            url: user.avatar,
                            name: user.name,
                            radius: 31,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.name.isEmpty
                                      ? context.l10n.unknownUser
                                      : user.name,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                if (user.intro.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      user.intro,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: context.colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${context.l10n.following} ${compactCount(user.followingCount)}  ·  ${context.l10n.followers} ${compactCount(user.followerCount)}',
                              style: TextStyle(
                                color: context.colors.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (app.session?.userId == widget.userId)
                            OutlinedButton(
                              onPressed: snapshot.hasData
                                  ? () async {
                                      final changed =
                                          await Navigator.push<bool>(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  EditProfilePage(user: user),
                                            ),
                                          );
                                      if (changed == true && mounted) {
                                        _refresh();
                                      }
                                    }
                                  : null,
                              child: Text(context.l10n.editProfile),
                            )
                          else
                            FilledButton.tonal(
                              onPressed: _busy || !snapshot.hasData
                                  ? null
                                  : () async {
                                      setState(() => _busy = true);
                                      final ok = await performAction(
                                        context,
                                        () => app.api.followUser(
                                          user,
                                          follow: !user.isFollowing,
                                        ),
                                      );
                                      if (mounted) {
                                        setState(() => _busy = false);
                                        if (ok) _refresh();
                                      }
                                    },
                              child: Text(
                                user.isFollowing
                                    ? context.l10n.unfollow
                                    : context.l10n.follow,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            TabBar(
              tabs: [
                Tab(text: context.l10n.userPosts),
                Tab(text: context.l10n.userReplies),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [false, true]
                    .map(
                      (replies) => PagedList<ThreadSummary>(
                        key: ValueKey('${widget.userId}:$replies'),
                        load: (page) => app.api.userPosts(
                          widget.userId,
                          page: page,
                          replies: replies,
                        ),
                        itemBuilder: (context, thread, _) => ThreadCard(
                          thread: thread,
                          onTap: () => openThread(context, thread),
                          onForumTap: () =>
                              openForum(context, thread.forum.name),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UserForumsPage extends StatelessWidget {
  const UserForumsPage({super.key, required this.userId});
  final String userId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: GlassAppBar(title: Text(context.l10n.followedForums)),
    body: PagedList<Forum>(
      load: (page) => AppScope.read(context).api.userForums(userId, page: page),
      itemBuilder: (context, forum, _) => SurfaceCard(
        child: ForumTile(
          forum: forum,
          onTap: () => openForum(context, forum.name),
        ),
      ),
    ),
  );
}
