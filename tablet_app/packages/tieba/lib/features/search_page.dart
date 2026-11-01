import '../tablet_bridge.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import '../widgets/content_cards.dart';
import '../widgets/paged_list.dart';
import 'main_shell.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.forumName, this.initialQuery = ''});
  final String? forumName;
  final String initialQuery;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _input;
  String _query = '';
  String _editing = '';
  Timer? _debounce;
  List<String> _suggestions = [];
  int _suggestionGeneration = 0;
  int _sort = 0;
  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.initialQuery);
    _query = widget.initialQuery;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _search(String query) {
    final value = query.trim();
    if (value.isEmpty) return;
    FocusScope.of(context).unfocus();
    AppScope.read(context).local.rememberSearch(value);
    _input.text = value;
    _debounce?.cancel();
    _suggestionGeneration++;
    setState(() {
      _query = value;
      _editing = '';
      _suggestions = [];
    });
  }

  void _inputChanged(String value) {
    _debounce?.cancel();
    final generation = ++_suggestionGeneration;
    setState(() {
      _editing = value.trim();
      _suggestions = [];
    });
    if (_editing.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final query = value.trim();
      try {
        final items = await AppScope.read(context).api.searchSuggestions(query);
        if (mounted && generation == _suggestionGeneration) {
          setState(() => _suggestions = items);
        }
      } catch (_) {
        /* Suggestions are optional; submitted search retains its error state. */
      }
    });
  }

  @override
  Widget build(BuildContext context) => TabletThreadHost(builder: _buildMaster);

  Widget _buildMaster(BuildContext context) {
    final app = AppScope.of(context);
    final scoped = widget.forumName != null;
    return DefaultTabController(
      length: scoped ? 1 : 3,
      child: Scaffold(
        appBar: GlassAppBar(
          titleSpacing: 0,
          title: TextField(
            controller: _input,
            autofocus: _query.isEmpty,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            onChanged: _inputChanged,
            decoration: InputDecoration(
              hintText: scoped
                  ? '${context.l10n.searchInForum} · ${widget.forumName}'
                  : context.l10n.searchHint,
              border: InputBorder.none,
              filled: false,
            ),
          ),
          actions: [
            IconButton(
              onPressed: () => _search(_input.text),
              icon: const Icon(Icons.search_rounded),
            ),
          ],
          bottom: _query.isEmpty
              ? null
              : TabBar(
                  tabs: scoped
                      ? [Tab(text: context.l10n.searchThreads)]
                      : [
                          Tab(text: context.l10n.searchForums),
                          Tab(text: context.l10n.searchThreads),
                          Tab(text: context.l10n.searchUsers),
                        ],
                ),
        ),
        body: _editing.isNotEmpty && _suggestions.isNotEmpty
            ? ListView(
                children: _suggestions
                    .map(
                      (suggestion) => ListTile(
                        leading: const Icon(Icons.search_rounded),
                        title: Text(suggestion),
                        onTap: () => _search(suggestion),
                        trailing: const Icon(
                          Icons.north_west_rounded,
                          size: 18,
                        ),
                      ),
                    )
                    .toList(),
              )
            : _query.isEmpty
            ? ListView(
                children: [
                  SectionTitle(
                    context.l10n.searchHistory,
                    trailing: IconButton(
                      onPressed: app.local.searchQueries.isEmpty
                          ? null
                          : () async {
                              if (await confirmAction(
                                context,
                                context.l10n.clearHistory,
                                context.l10n.clearConfirm,
                              )) {
                                await app.local.clearSearchHistory();
                              }
                            },
                      icon: const Icon(Icons.history_rounded),
                      tooltip: context.l10n.clearHistory,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: app.local.searchQueries
                          .map(
                            (query) => ActionChip(
                              label: Text(query),
                              onPressed: () => _search(query),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  if (app.local.searchQueries.isEmpty)
                    EmptyPanel(
                      icon: Icons.manage_search_rounded,
                      title: context.l10n.search,
                      message: context.l10n.searchHint,
                    ),
                ],
              )
            : TabBarView(
                children: [
                  if (!scoped)
                    PagedList<Forum>(
                      key: ValueKey('forum:$_query'),
                      load: (_) async =>
                          PageResult(items: await app.api.searchForums(_query)),
                      itemBuilder: (context, forum, _) => SurfaceCard(
                        child: ForumTile(
                          forum: forum,
                          onTap: () => openForum(context, forum.name),
                        ),
                      ),
                    ),
                  PagedList<ThreadSummary>(
                    key: ValueKey('thread:$_query:$_sort'),
                    load: (page) => app.api.searchThreads(
                      _query,
                      page: page,
                      sort: _sort,
                      forumName: widget.forumName,
                    ),
                    filter: (thread) =>
                        (!app.local.blocksThread(thread) ||
                        !app.settings.getBool('hideBlockedContent')),
                    headerBuilder: (context, _) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      child: Wrap(
                        spacing: 8,
                        children:
                            [
                                  (0, context.l10n.relevance),
                                  (1, context.l10n.newestFirst),
                                  (2, context.l10n.oldestFirst),
                                ]
                                .map(
                                  (item) => ChoiceChip(
                                    label: Text(item.$2),
                                    selected: _sort == item.$1,
                                    onSelected: (_) =>
                                        setState(() => _sort = item.$1),
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                    itemBuilder: (context, thread, _) => ThreadCard(
                      thread: thread,
                      onTap: () => openThread(context, thread),
                      onForumTap: () => openForum(context, thread.forum.name),
                      onAuthorTap: () => openUser(context, thread.author),
                    ),
                  ),
                  if (!scoped)
                    PagedList<UserProfile>(
                      key: ValueKey('user:$_query'),
                      load: (_) async =>
                          PageResult(items: await app.api.searchUsers(_query)),
                      itemBuilder: (context, user, _) => SurfaceCard(
                        child: UserTile(
                          user: user,
                          onTap: () => openUser(context, user),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
