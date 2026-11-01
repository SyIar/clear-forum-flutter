import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_controller.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../platform/draft_attachments.dart';
import '../widgets/common.dart';
import '../widgets/emoticons.dart';

class ReplyPage extends StatefulWidget {
  const ReplyPage({
    super.key,
    required this.threadId,
    required this.forum,
    this.parentPostId,
    this.subPostId,
    this.replyUserId,
    this.replyUserName = '',
    this.draft,
  });
  final String threadId, replyUserName;
  final Forum forum;
  final String? parentPostId, subPostId, replyUserId;
  final ReplyDraft? draft;
  @override
  State<ReplyPage> createState() => _ReplyPageState();
}

class _ReplyPageState extends State<ReplyPage> {
  final _text = TextEditingController();
  final List<XFile> _images = [];
  bool _posted = false;
  bool _sending = false,
      _allowPop = false,
      _original = false,
      _restored = false;
  int _uploading = 0;
  String? _routeAccountId;
  late String _draftKey;
  @override
  void initState() {
    super.initState();
    _draftKey =
        widget.draft?.key ??
        '${widget.threadId}:${widget.parentPostId ?? ''}:${widget.subPostId ?? ''}';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored) return;
    _restored = true;
    final app = AppScope.read(context);
    _routeAccountId = app.session?.userId;
    _original = app.settings.getBool('originalImages');
    final draft = widget.draft ?? app.local.getDraft(_draftKey);
    if (draft != null) {
      _text.text = draft.content;
      _restoreImages(draft.imagePaths);
    }
  }

  Future<void> _restoreImages(List<String> paths) async {
    for (final path in paths) {
      try {
        final image = await DraftAttachments.restoreImage(path);
        if (mounted) setState(() => _images.add(image));
      } catch (error) {
        if (mounted) notifyUser(context, error.toString());
      }
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _saveDraft() async {
    final app = AppScope.read(context);
    if (app.changingAccount || app.session?.userId != _routeAccountId) return;
    final draft = ReplyDraft(
      key: _draftKey,
      threadId: widget.threadId,
      forumName: widget.forum.name,
      content: _text.text,
      imagePaths: _images.map((image) => image.path).toList(),
      parentPostId: widget.parentPostId ?? '',
      targetSubPostId: widget.subPostId ?? '',
      replyUserId: widget.replyUserId ?? '',
    );
    await app.local.saveDraft(draft);
  }

  Future<void> _leave() async {
    if (_sending) return;
    if (_text.text.trim().isEmpty && _images.isEmpty) {
      setState(() => _allowPop = true);
      if (mounted) Navigator.pop(context);
      return;
    }
    final action = await showGlassDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.leaveDraftTitle),
        content: Text(context.l10n.leaveDraftBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: Text(context.l10n.discard),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: Text(context.l10n.saveDraft),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    final app = AppScope.read(context);
    if (app.changingAccount || app.session?.userId != _routeAccountId) return;
    try {
      if (action == 'save') {
        await _saveDraft();
      } else {
        await app.local.removeDraft(_draftKey);
      }
      if (mounted &&
          !app.changingAccount &&
          app.session?.userId == _routeAccountId) {
        setState(() => _allowPop = true);
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) notifyUser(context, error.toString());
    }
  }

  Future<void> _pickImages() async {
    try {
      final selected = await ImagePicker().pickMultiImage(
        imageQuality: _original ? null : 85,
        maxWidth: _original ? null : 1920,
      );
      for (final image in selected.take(9 - _images.length)) {
        final path = await DraftAttachments.retainImage(image);
        final retained = await DraftAttachments.restoreImage(path);
        if (mounted) setState(() => _images.add(retained));
      }
      if (mounted && selected.isNotEmpty) await _saveDraft();
    } catch (error) {
      if (mounted) notifyUser(context, error.toString());
    }
  }

  Future<void> _send() async {
    if (_sending || _posted) return;
    if (_text.text.trim().isEmpty && _images.isEmpty) {
      notifyUser(context, context.l10n.textRequired);
      return;
    }
    if (!await requireAccount(context) || !mounted) return;
    final app = AppScope.read(context);
    if (app.changingAccount || app.session?.userId != _routeAccountId) return;
    final sendingAccountId = app.session?.userId;
    if (app.settings.getBool('postOrReplyWarning') &&
        !await confirmAction(
          context,
          context.l10n.send,
          context.l10n.replyWarning,
        )) {
      return;
    }
    if (!mounted ||
        app.changingAccount ||
        app.session?.userId != sendingAccountId) {
      return;
    }
    setState(() => _sending = true);
    try {
      await _saveDraft();
      var forum = widget.forum;
      if (forum.id.isEmpty) {
        final result = await app.api.threadPosts(widget.threadId);
        forum = result.forum ?? result.thread?.forum ?? forum;
      }
      if (forum.id.isEmpty || forum.name.isEmpty) {
        throw StateError('Could not resolve the forum for this reply');
      }
      final content = StringBuffer(_text.text.trim());
      for (var index = 0; index < _images.length; index++) {
        if (!mounted ||
            app.changingAccount ||
            app.session?.userId != sendingAccountId) {
          return;
        }
        if (mounted) setState(() => _uploading = index + 1);
        final image = _images[index];
        final bytes = await image.readAsBytes();
        if (!mounted ||
            app.changingAccount ||
            app.session?.userId != sendingAccountId) {
          return;
        }
        final uploaded = await app.api.uploadImage(
          bytes,
          filename: image.name,
          forumName: forum.name,
          watermarkType:
              int.tryParse(
                app.settings.getString('picWatermarkType', fallback: '2'),
              ) ??
              2,
          saveOriginal: _original,
        );
        content.write(
          '#(pic,${uploaded.pictureId},${uploaded.width},${uploaded.height})',
        );
      }
      final tail = app.settings.getString('littleTail');
      if (tail.isNotEmpty) content.write('\n$tail');
      if (!mounted ||
          app.changingAccount ||
          app.session?.userId != sendingAccountId) {
        return;
      }
      await app.api.reply(
        content: content.toString(),
        forum: forum,
        threadId: widget.threadId,
        parentPostId: widget.parentPostId,
        subPostId: widget.subPostId,
        replyUserId: widget.replyUserId,
      );
      _posted = true;
      Object? cleanupError;
      try {
        await app.local.markDraftSent(
          _draftKey,
          expectedAccountId: sendingAccountId,
        );
      } catch (error) {
        cleanupError = error;
      }
      if (mounted &&
          !app.changingAccount &&
          app.session?.userId == sendingAccountId) {
        setState(() => _allowPop = true);
        notifyUser(
          context,
          cleanupError == null
              ? context.l10n.replySent
              : context.l10n.replySentCleanupFailed,
        );
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) notifyUser(context, error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploading = 0;
        });
      }
    }
  }

  void _insertEmoji(String emoji) {
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : _text.text.length;
    final end = selection.isValid ? selection.end : _text.text.length;
    _text.value = TextEditingValue(
      text: _text.text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: GlassAppBar(
        leading: IconButton(
          onPressed: _sending ? null : _leave,
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(context.l10n.reply),
        actions: [
          TextButton(
            onPressed: _sending ? null : _send,
            child: Text(
              _sending ? context.l10n.sending : context.l10n.send,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_sending) const LinearProgressIndicator(),
            if (_uploading > 0)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  '${context.l10n.sendingImages} $_uploading / ${_images.length}',
                ),
              ),
            if (widget.replyUserName.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
                child: Text(
                  '${context.l10n.replyTo} ${widget.replyUserName}',
                  style: TextStyle(color: context.colors.primary),
                ),
              ),
            Expanded(
              child: TextField(
                controller: _text,
                enabled: !_sending,
                autofocus: true,
                minLines: null,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: context.l10n.replyHint,
                  contentPadding: const EdgeInsets.all(22),
                  border: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
            if (_images.isNotEmpty)
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  itemCount: _images.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) => SizedBox(
                    width: 90,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: FutureBuilder<Uint8List>(
                              future: _images[index].readAsBytes(),
                              builder: (_, snapshot) => snapshot.hasData
                                  ? Image.memory(
                                      snapshot.data!,
                                      fit: BoxFit.cover,
                                    )
                                  : const Icon(Icons.image_outlined),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton.filled(
                            onPressed: _sending
                                ? null
                                : () => setState(() => _images.removeAt(index)),
                            visualDensity: VisualDensity.compact,
                            iconSize: 15,
                            tooltip: context.l10n.removeImage,
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _sending || _images.length >= 9
                        ? null
                        : _pickImages,
                    icon: const Icon(Icons.image_outlined),
                    tooltip: context.l10n.attachImages,
                  ),
                  IconButton(
                    onPressed: _sending
                        ? null
                        : () => showGlassBottomSheet<void>(
                            context: context,
                            builder: (context) => EmoticonPicker(
                              onSelected: (item) => _insertEmoji(item.token),
                            ),
                          ),
                    icon: const Icon(Icons.emoji_emotions_outlined),
                    tooltip: context.l10n.emoticons,
                  ),
                  const Spacer(),
                  Text(
                    context.l10n.originalImage,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Switch(
                    value: _original,
                    onChanged: _sending
                        ? null
                        : (value) {
                            setState(() => _original = value);
                            AppScope.read(context).settings
                                .setBool('originalImages', value);
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
