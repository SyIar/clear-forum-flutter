import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/local_store.dart';
import '../widgets/common.dart';
import 'theme_background_page.dart';
import 'native_preferences.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final settings = app.settings;
    return Scaffold(
      appBar: GlassAppBar(title: Text(context.l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 36),
        children: [
          SectionTitle(context.l10n.appearance),
          SurfaceCard(
            child: ListTile(
              leading: const Icon(Icons.apps_rounded),
              title: Text(context.l10n.appIcon),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const AppIconPage()),
              ),
            ),
          ),
          SurfaceCard(
            child: ListTile(
              leading: const Icon(Icons.wallpaper_rounded),
              title: Text(context.l10n.backgroundTheme),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const ThemeBackgroundPage(),
                ),
              ),
            ),
          ),
          SurfaceCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: Text(context.l10n.theme),
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: settings.themeMode,
                      onChanged: (value) {
                        if (value != null) {
                          settings.setString('themeMode', value);
                        }
                      },
                      items: [
                        DropdownMenuItem(
                          value: 'system',
                          child: Text(context.l10n.systemTheme),
                        ),
                        DropdownMenuItem(
                          value: 'light',
                          child: Text(context.l10n.lightTheme),
                        ),
                        DropdownMenuItem(
                          value: 'dark',
                          child: Text(context.l10n.darkTheme),
                        ),
                      ],
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: Text(context.l10n.darkPalette),
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: settings.getString(
                        'darkPalette',
                        fallback: 'amoled_dark',
                      ),
                      onChanged: (value) {
                        if (value != null) {
                          settings.setString('darkPalette', value);
                        }
                      },
                      items: [
                        DropdownMenuItem(
                          value: 'grey_dark',
                          child: Text(context.l10n.darkGrey),
                        ),
                        DropdownMenuItem(
                          value: 'blue_dark',
                          child: Text(context.l10n.darkBlue),
                        ),
                        DropdownMenuItem(
                          value: 'amoled_dark',
                          child: Text(context.l10n.darkBlack),
                        ),
                      ],
                    ),
                  ),
                ),
                _toggle(
                  context,
                  'listItemsBackgroundIntermixed',
                  context.l10n.alternatingCards,
                  Icons.table_rows_outlined,
                  fallback: true,
                ),
                ListTile(
                  leading: const Icon(Icons.font_download_outlined),
                  title: Text(context.l10n.fontFamily),
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: settings.fontFamily,
                      onChanged: (value) {
                        if (value != null) {
                          settings.setString('fontFamily', value);
                        }
                      },
                      items: [
                        DropdownMenuItem(
                          value: 'system',
                          child: Text(context.l10n.systemFont),
                        ),
                        DropdownMenuItem(
                          value: 'notoSans',
                          child: Text(context.l10n.notoSans),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: Text(
                    context.l10n.fontPreview,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.text_fields_rounded),
                  title: Text(context.l10n.fontSize),
                  trailing: Text('${(settings.fontScale * 100).round()}%'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Slider(
                    value: settings.fontScale.clamp(.8, 1.6),
                    min: .8,
                    max: 1.6,
                    divisions: 8,
                    label: '${(settings.fontScale * 100).round()}%',
                    onChanged: (value) =>
                        settings.setDouble('fontScale', value),
                  ),
                ),
                _toggle(
                  context,
                  'compactCards',
                  context.l10n.compactCards,
                  Icons.view_agenda_outlined,
                ),
                _toggle(
                  context,
                  'hideExplore',
                  context.l10n.hideExplore,
                  Icons.explore_outlined,
                ),
                ListTile(
                  leading: const Icon(Icons.color_lens_outlined),
                  title: Text(context.l10n.accentColor),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children:
                        [
                              0xFF007AFF,
                              0xFF4167A8,
                              0xFF6D529B,
                              0xFFAA4B66,
                              0xFF966329,
                              0xFF477D4D,
                              0xFF546472,
                            ]
                            .map(
                              (color) => Semantics(
                                button: true,
                                selected:
                                    settings.getInt(
                                      'customPrimaryColor',
                                      fallback: 0xFF007AFF,
                                    ) ==
                                    color,
                                child: InkWell(
                                  onTap: () => settings.setInt(
                                    'customPrimaryColor',
                                    color,
                                  ),
                                  customBorder: const CircleBorder(),
                                  child: CircleAvatar(
                                    backgroundColor: Color(color),
                                    radius: 20,
                                    child:
                                        settings.getInt(
                                              'customPrimaryColor',
                                              fallback: 0xFF167D8D,
                                            ) ==
                                            color
                                        ? const Icon(
                                            Icons.check_rounded,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
                _toggle(
                  context,
                  'toolbarPrimaryColor',
                  context.l10n.coloredToolbar,
                  Icons.format_color_fill_rounded,
                ),
                ListTile(
                  leading: const Icon(Icons.rounded_corner_rounded),
                  title: Text(context.l10n.cornerRadius),
                  trailing: Text(
                    '${settings.getDouble('radius', fallback: 20).round()}',
                  ),
                ),
                Slider(
                  value: settings
                      .getDouble('radius', fallback: 20)
                      .clamp(0, 32),
                  min: 0,
                  max: 32,
                  divisions: 8,
                  onChanged: (value) => settings.setDouble('radius', value),
                ),
                _toggle(
                  context,
                  'homePageScroll',
                  context.l10n.swipeTabs,
                  Icons.swipe_rounded,
                ),
              ],
            ),
          ),
          SectionTitle(context.l10n.reading),
          SurfaceCard(
            child: Column(
              children: [
                _toggle(
                  context,
                  'showShortcutInThread',
                  context.l10n.threadShortcuts,
                  Icons.tune_rounded,
                  fallback: true,
                ),
                ListTile(
                  leading: const Icon(Icons.radio_button_checked_rounded),
                  title: Text(context.l10n.forumFab),
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: settings.getString(
                        'forumFabFunction',
                        fallback: 'refresh',
                      ),
                      onChanged: (value) {
                        if (value != null) {
                          settings.setString('forumFabFunction', value);
                        }
                      },
                      items: [
                        DropdownMenuItem(
                          value: 'refresh',
                          child: Text(context.l10n.refresh),
                        ),
                        DropdownMenuItem(
                          value: 'back_to_top',
                          child: Text(context.l10n.backToTop),
                        ),
                        DropdownMenuItem(
                          value: 'hide',
                          child: Text(context.l10n.hide),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SurfaceCard(
            child: _toggle(
              context,
              'showBothUsernameAndNickname',
              context.l10n.bothUserNames,
              Icons.badge_outlined,
            ),
          ),
          SurfaceCard(
            child: _toggle(
              context,
              'loadPictureWhenScroll',
              context.l10n.loadWhileScrolling,
              Icons.swipe_vertical_rounded,
              fallback: true,
            ),
          ),
          SurfaceCard(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.image_outlined),
                  title: Text(context.l10n.showImages),
                  value: !settings.hideMedia,
                  onChanged: (value) => settings.setBool('hideMedia', !value),
                ),
                ListTile(
                  leading: const Icon(Icons.network_wifi_rounded),
                  title: Text(context.l10n.imageLoadPolicy),
                  subtitle: Text(switch (settings.getString('imageLoadType')) {
                    '0' => context.l10n.imageSmartOriginal,
                    '1' => context.l10n.imageSmartLoad,
                    '3' => context.l10n.imageNever,
                    _ => context.l10n.imageAllOriginal,
                  }),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    final mode = await showGlassBottomSheet<String>(
                      context: context,
                      builder: (context) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children:
                              [
                                    ('0', context.l10n.imageSmartOriginal),
                                    ('1', context.l10n.imageSmartLoad),
                                    ('2', context.l10n.imageAllOriginal),
                                    ('3', context.l10n.imageNever),
                                  ]
                                  .map(
                                    (option) => ListTile(
                                      title: Text(option.$2),
                                      trailing:
                                          settings.getString('imageLoadType') ==
                                              option.$1
                                          ? const Icon(Icons.check_rounded)
                                          : null,
                                      onTap: () =>
                                          Navigator.pop(context, option.$1),
                                    ),
                                  )
                                  .toList(),
                        ),
                      ),
                    );
                    if (mode != null) {
                      await settings.setString('imageLoadType', mode);
                    }
                  },
                ),
                _toggle(
                  context,
                  'readerMode',
                  context.l10n.readerMode,
                  Icons.chrome_reader_mode_outlined,
                ),
                _toggle(
                  context,
                  'restoreReading',
                  context.l10n.restoreReading,
                  Icons.bookmark_added_outlined,
                  fallback: true,
                ),
                _toggle(
                  context,
                  'homePageShowHistoryForum',
                  context.l10n.showRecentForums,
                  Icons.history_rounded,
                ),
                _toggle(
                  context,
                  'showTopForumInNormalList',
                  context.l10n.repeatPinnedForums,
                  Icons.push_pin_outlined,
                  fallback: true,
                ),
                _toggle(
                  context,
                  'hideForumIntroAndStat',
                  context.l10n.hideForumHeader,
                  Icons.view_compact_outlined,
                ),
                _toggle(
                  context,
                  'imageDarkenWhenNightMode',
                  context.l10n.imageDarken,
                  Icons.brightness_4_outlined,
                  fallback: true,
                ),
                _toggle(
                  context,
                  'collectThreadSeeLz',
                  context.l10n.savedAuthorOnly,
                  Icons.person_outline_rounded,
                  fallback: true,
                ),
                _toggle(
                  context,
                  'collectThreadDescSort',
                  context.l10n.savedNewestFirst,
                  Icons.vertical_align_top_rounded,
                ),
                ListTile(
                  leading: const Icon(Icons.sort_rounded),
                  title: Text(context.l10n.defaultSort),
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: settings.getString(
                        'defaultSortType',
                        fallback: 'reply',
                      ),
                      onChanged: (value) {
                        if (value != null) {
                          settings.setString('defaultSortType', value);
                        }
                      },
                      items: [
                        DropdownMenuItem(
                          value: 'reply',
                          child: Text(context.l10n.latestReply),
                        ),
                        DropdownMenuItem(
                          value: 'post',
                          child: Text(context.l10n.latestPost),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SectionTitle(context.l10n.privacyAndFilters),
          SurfaceCard(
            child: _toggle(
              context,
              'useWebView',
              context.l10n.linksInApp,
              Icons.open_in_browser_rounded,
            ),
          ),
          SurfaceCard(
            child: Column(
              children: [
                _toggle(
                  context,
                  'blockVideo',
                  context.l10n.hideVideo,
                  Icons.videocam_off_outlined,
                ),
                _toggle(
                  context,
                  'hideReply',
                  context.l10n.hideReply,
                  Icons.speaker_notes_off_outlined,
                ),
                _toggle(
                  context,
                  'hideBlockedContent',
                  context.l10n.hideBlocked,
                  Icons.visibility_off_outlined,
                ),
                _toggle(
                  context,
                  'showBlockTip',
                  context.l10n.showBlockTip,
                  Icons.info_outline_rounded,
                  fallback: true,
                ),
                ListTile(
                  leading: const Icon(Icons.filter_alt_outlined),
                  title: Text(context.l10n.privacyAndFilters),
                  subtitle: Text('${app.local.blockRules.length}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const BlockListPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SectionTitle(context.l10n.reply),
          SurfaceCard(
            child: ListTile(
              leading: const Icon(Icons.branding_watermark_outlined),
              title: Text(context.l10n.watermark),
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: settings.getString('picWatermarkType', fallback: '2'),
                  onChanged: (value) {
                    if (value != null) {
                      settings.setString('picWatermarkType', value);
                    }
                  },
                  items:
                      [
                            ('0', context.l10n.watermarkNone),
                            ('1', context.l10n.watermarkUsername),
                            ('2', context.l10n.watermarkForum),
                          ]
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.$1,
                              child: Text(item.$2),
                            ),
                          )
                          .toList(),
                ),
              ),
            ),
          ),
          SurfaceCard(
            child: Column(
              children: [
                _toggle(
                  context,
                  'postOrReplyWarning',
                  context.l10n.replyWarningTitle,
                  Icons.info_outline_rounded,
                ),
                _toggle(
                  context,
                  'originalImages',
                  context.l10n.originalImage,
                  Icons.photo_size_select_large_rounded,
                ),
                ListTile(
                  leading: const Icon(Icons.format_quote_rounded),
                  title: Text(context.l10n.signature),
                  subtitle: settings.getString('littleTail').isEmpty
                      ? null
                      : Text(settings.getString('littleTail'), maxLines: 2),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () async {
                    final value = await textPrompt(
                      context,
                      title: context.l10n.signature,
                      value: settings.getString('littleTail'),
                    );
                    if (value != null) {
                      await settings.setString('littleTail', value);
                    }
                  },
                ),
              ],
            ),
          ),
          SectionTitle(context.l10n.localData),
          const SurfaceCard(child: ImageCacheTile()),
          SurfaceCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.manage_search_rounded),
                  title: Text(context.l10n.clearSearchHistory),
                  onTap: () async {
                    if (await confirmAction(
                      context,
                      context.l10n.clearSearchHistory,
                      context.l10n.clearConfirm,
                    )) {
                      await app.local.clearSearchHistory();
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: Text(context.l10n.clearReadingHistory),
                  onTap: () async {
                    if (await confirmAction(
                      context,
                      context.l10n.clearReadingHistory,
                      context.l10n.clearConfirm,
                    )) {
                      await app.local.clearHistory();
                    }
                  },
                ),
              ],
            ),
          ),
          SurfaceCard(
            child: ListTile(
              leading: const Icon(Icons.task_alt_rounded),
              title: Text(context.l10n.autoCheckIn),
              subtitle: Text(context.l10n.autoCheckInBody),
            ),
          ),
          SurfaceCard(
            child: _toggle(
              context,
              'signSlowMode',
              context.l10n.slowCheckIn,
              Icons.timer_outlined,
              fallback: true,
            ),
          ),
          SurfaceCard(
            child: _toggle(
              context,
              'oksignUseOfficialOksign',
              context.l10n.officialBatchCheckIn,
              Icons.done_all_rounded,
              fallback: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle(
    BuildContext context,
    String key,
    String title,
    IconData icon, {
    bool fallback = false,
  }) {
    final store = AppScope.of(context).settings;
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      value: store.getBool(key, fallback: fallback),
      onChanged: (value) => store.setBool(key, value),
    );
  }
}

class BlockListPage extends StatefulWidget {
  const BlockListPage({super.key});
  @override
  State<BlockListPage> createState() => _BlockListPageState();
}

class _BlockListPageState extends State<BlockListPage> {
  bool _allow = false;
  @override
  Widget build(BuildContext context) {
    final local = AppScope.of(context).local;
    final rules = local.blockRules
        .where((rule) => rule.allow == _allow)
        .toList();
    return Scaffold(
      appBar: GlassAppBar(title: Text(context.l10n.privacyAndFilters)),
      floatingActionButton: GlassFloatingButton(
        onPressed: () async {
          final allow = _allow;
          final kind = await showGlassBottomSheet<BlockKind>(
            context: context,
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.text_fields_rounded),
                    title: Text(context.l10n.keyword),
                    onTap: () => Navigator.pop(context, BlockKind.keyword),
                  ),
                  ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: Text(context.l10n.forumName),
                    onTap: () => Navigator.pop(context, BlockKind.forum),
                  ),
                  ListTile(
                    leading: const Icon(Icons.person_outline_rounded),
                    title: Text(context.l10n.userIdOrName),
                    onTap: () => Navigator.pop(context, BlockKind.user),
                  ),
                  ListTile(
                    leading: const Icon(Icons.article_outlined),
                    title: Text(context.l10n.threadId),
                    onTap: () => Navigator.pop(context, BlockKind.thread),
                  ),
                ],
              ),
            ),
          );
          if (!context.mounted || kind == null) return;
          final title = switch (kind) {
            BlockKind.keyword => context.l10n.keywordGroup,
            BlockKind.forum => context.l10n.forumName,
            BlockKind.user => context.l10n.userIdOrName,
            BlockKind.thread => context.l10n.threadId,
          };
          final value = await textPrompt(
            context,
            title: title,
            hint: kind == BlockKind.keyword
                ? context.l10n.keywordGroupHint
                : null,
            maxLines: kind == BlockKind.keyword ? 4 : 1,
            keyboardType: kind == BlockKind.keyword
                ? TextInputType.multiline
                : TextInputType.text,
          );
          if (value != null && value.isNotEmpty) {
            final keywords = kind == BlockKind.keyword
                ? value
                      .split('\n')
                      .map((word) => word.trim())
                      .where((word) => word.isNotEmpty)
                      .toSet()
                      .toList()
                : <String>[];
            if (kind == BlockKind.keyword && keywords.isEmpty) return;
            await local.addBlock(
              BlockRule(
                kind: kind,
                value: keywords.isEmpty ? value : keywords.join('\n'),
                label: keywords.isEmpty ? value : keywords.join(' + '),
                allow: allow,
                keywords: keywords,
              ),
            );
          }
        },
        child: const Icon(Icons.add_rounded),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(context.l10n.blockRules),
                  icon: const Icon(Icons.block_rounded),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(context.l10n.allowRules),
                  icon: const Icon(Icons.check_circle_outline_rounded),
                ),
              ],
              selected: {_allow},
              onSelectionChanged: (value) =>
                  setState(() => _allow = value.first),
            ),
          ),
          Expanded(
            child: rules.isEmpty
                ? const EmptyPanel(icon: Icons.filter_alt_outlined)
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: rules.length,
                    itemBuilder: (context, index) {
                      final rule = rules[index];
                      return SurfaceCard(
                        child: ListTile(
                          leading: Icon(switch (rule.kind) {
                            BlockKind.user => Icons.person_outline_rounded,
                            BlockKind.forum => Icons.forum_outlined,
                            BlockKind.thread => Icons.article_outlined,
                            BlockKind.keyword => Icons.text_fields_rounded,
                          }),
                          title: Text(
                            rule.label.isEmpty ? rule.value : rule.label,
                          ),
                          subtitle:
                              rule.label != rule.value && rule.label.isNotEmpty
                              ? Text(rule.value)
                              : null,
                          trailing: IconButton(
                            onPressed: () => local.removeBlock(
                              rule.kind,
                              rule.value,
                              allow: rule.allow,
                            ),
                            icon: const Icon(Icons.close_rounded),
                            tooltip: context.l10n.unblockUser,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: GlassAppBar(title: Text(context.l10n.about)),
    body: ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 40, 30, 32),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: context.colors.primaryContainer,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Icon(
                  Icons.forum_rounded,
                  size: 52,
                  color: context.colors.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.l10n.appTitle,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text('0.1.0', style: TextStyle(color: context.colors.outline)),
              const SizedBox(height: 20),
              Text(
                context.l10n.aboutBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                  height: 1.7,
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SurfaceCard(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.code_rounded),
                title: Text(context.l10n.upstreamProject),
                subtitle: const Text('HuanCheng65 / TiebaLite'),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () => openExternal(
                  context,
                  'https://github.com/HuanCheng65/TiebaLite',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(context.l10n.licenses),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: context.l10n.appTitle,
                  applicationVersion: '0.1.0',
                  applicationLegalese: 'GNU GPL v3 · Tieba Lite contributors',
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
