import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/emoticons.dart';
import '../core/models.dart';
import '../features/main_shell.dart';
import '../platform/deep_links.dart';
import 'common.dart';

class EmoticonImage extends StatelessWidget {
  const EmoticonImage({
    super.key,
    required this.id,
    this.name = '',
    this.url = '',
    this.size = 28,
  });
  final String id, name, url;
  final double size;
  @override
  Widget build(BuildContext context) {
    final asset = TiebaEmoticon.assetForId(id);
    Widget fallback() => SizedBox(
      width: size,
      height: size,
      child: FittedBox(child: Text(name.isEmpty ? '?' : '#($name)')),
    );
    if (asset != null) {
      return Image.asset(
        asset,
        width: size,
        height: size,
        errorBuilder: (_, _, _) => fallback(),
      );
    }
    final source = url.isNotEmpty
        ? url
        : RegExp(r'^image_emoticon[0-9]+$').hasMatch(id)
        ? TiebaEmoticon(id: id, name: name).url
        : '';
    if (source.isEmpty) return fallback();
    return CachedNetworkImage(
      imageUrl: source,
      width: size,
      height: size,
      errorWidget: (_, _, _) => fallback(),
    );
  }
}

class EmoticonPicker extends StatefulWidget {
  const EmoticonPicker({super.key, required this.onSelected});
  final ValueChanged<TiebaEmoticon> onSelected;
  @override
  State<EmoticonPicker> createState() => _EmoticonPickerState();
}

class _EmoticonPickerState extends State<EmoticonPicker> {
  late Future<List<TiebaEmoticon>> _items;
  @override
  void initState() {
    super.initState();
    _items = loadEmoticons();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: 400,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.emoticons,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<TiebaEmoticon>>(
              future: _items,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorPanel(
                    error: snapshot.error!,
                    onRetry: () => setState(() => _items = loadEmoticons()),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: snapshot.data!.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 64,
                    mainAxisExtent: 62,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 6,
                  ),
                  itemBuilder: (context, index) {
                    final item = snapshot.data![index];
                    return Tooltip(
                      message: item.name,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => widget.onSelected(item),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            EmoticonImage(
                              id: item.id,
                              name: item.name,
                              size: 32,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class InlinePostText extends StatefulWidget {
  const InlinePostText({super.key, required this.parts});
  final List<ContentPart> parts;
  @override
  State<InlinePostText> createState() => _InlinePostTextState();
}

class _InlinePostTextState extends State<InlinePostText> {
  final List<TapGestureRecognizer> _recognizers = [];
  late final Future<void> _catalog;
  @override
  void initState() {
    super.initState();
    _catalog = EmoticonCatalog.instance.load();
  }

  void _clearRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  InlineSpan _image(TiebaEmoticon item) => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: EmoticonImage(id: item.id, name: item.name, size: 25),
  );
  List<InlineSpan> _tokens(String text) {
    final result = <InlineSpan>[];
    var cursor = 0;
    for (final match in RegExp(r'#\(([^()]+)\)').allMatches(text)) {
      if (match.start > cursor) {
        result.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final item = EmoticonCatalog.instance.byName(match.group(1)!);
      result.add(item == null ? TextSpan(text: match.group(0)) : _image(item));
      cursor = match.end;
    }
    if (cursor < text.length) {
      result.add(TextSpan(text: text.substring(cursor)));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _catalog,
    builder: (context, _) {
      _clearRecognizers();
      final spans = <InlineSpan>[];
      for (final part in widget.parts) {
        switch (part.type) {
          case ContentType.emoji:
            if (part.sourceId.isNotEmpty && part.caption.isNotEmpty) {
              EmoticonCatalog.instance.register(part.sourceId, part.caption);
            }
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: EmoticonImage(
                  id: part.sourceId,
                  name: part.caption,
                  url: part.url,
                  size: 25,
                ),
              ),
            );
          case ContentType.link:
            final recognizer = TapGestureRecognizer()
              ..onTap = () {
                final uri = Uri.tryParse(part.url);
                final link = uri == null ? null : TiebaLink.parse(uri);
                if (link != null) {
                  openIncomingLink(context, link);
                } else {
                  openExternal(context, part.url);
                }
              };
            _recognizers.add(recognizer);
            spans.add(
              TextSpan(
                text: part.text.isEmpty ? part.url : part.text,
                recognizer: recognizer,
                style: TextStyle(color: context.colors.primary),
              ),
            );
          case ContentType.mention:
            final mentionTap = RegExp(r'^[1-9][0-9]*$').hasMatch(part.sourceId)
                ? (TapGestureRecognizer()
                    ..onTap = () => openUser(
                      context,
                      UserProfile(id: part.sourceId, name: part.text),
                    ))
                : null;
            if (mentionTap != null) _recognizers.add(mentionTap);
            spans.add(
              TextSpan(
                text: part.text,
                recognizer: mentionTap,
                style: TextStyle(
                  color: context.colors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          default:
            spans.addAll(_tokens(part.text));
        }
      }
      return SelectionArea(
        child: Text.rich(
          TextSpan(children: spans),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    },
  );
}
