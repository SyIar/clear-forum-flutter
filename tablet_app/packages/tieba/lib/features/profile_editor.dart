import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_controller.dart';
import '../core/tieba_api.dart';
import '../platform/avatar_crop.dart';
import '../widgets/common.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key, required this.user});
  final UserProfile user;
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController _name, _intro;
  late UserProfile _saved;
  late int _sex;
  Uint8List? _avatarPreview;
  bool _avatarPending = false;
  bool _busy = false;
  bool _changed = false;
  bool _mustRefresh = false;
  bool _partial = false;

  bool get _fieldsChanged =>
      _name.text.trim() != _saved.name ||
      _intro.text != _saved.intro ||
      _sex != _saved.sex;
  bool get _unsaved => _fieldsChanged || _avatarPending;

  @override
  void initState() {
    super.initState();
    _saved = widget.user;
    _sex = _saved.sex;
    _name = TextEditingController(text: _saved.name)..addListener(_edited);
    _intro = TextEditingController(text: _saved.intro)..addListener(_edited);
  }

  void _edited() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name.dispose();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 3000,
        maxHeight: 3000,
        imageQuality: 95,
        requestFullMetadata: false,
      );
      if (image == null || !mounted) return;
      final prepared = await prepareAvatarImage(await image.readAsBytes());
      if (!mounted) return;
      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => _AvatarCropPage(image: prepared)),
      );
      if (cropped != null && mounted) {
        setState(() {
          _avatarPreview = cropped;
          _avatarPending = true;
        });
      }
    } catch (_) {
      if (mounted) notifyUser(context, context.l10n.imageUnsupported);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final app = AppScope.read(context);
      if (app.session?.userId != widget.user.id) {
        throw StateError('Account changed');
      }
      final current = await app.api.userProfile(widget.user.id);
      if (!mounted) return;
      if (current.name != _saved.name ||
          current.intro != _saved.intro ||
          current.sex != _saved.sex) {
        _changed = true;
      }
      if (_avatarPending &&
          (current.portrait != _saved.portrait ||
              current.avatar != _saved.avatar)) {
        _avatarPending = false;
        _changed = true;
      }
      setState(() {
        _saved = current;
        _mustRefresh = false;
      });
      await _cacheProfile(app, current);
    } catch (_) {
      if (mounted) notifyUser(context, context.l10n.operationFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _mustRefresh || _name.text.trim().isEmpty) return;
    if (!_unsaved) {
      Navigator.pop(context, _changed);
      return;
    }
    final app = AppScope.read(context);
    if (app.session?.userId != widget.user.id) {
      notifyUser(context, context.l10n.operationFailed);
      return;
    }
    setState(() {
      _busy = true;
      _partial = false;
    });
    var committed = false;
    try {
      if (_avatarPending && _avatarPreview != null) {
        await app.api.uploadPortrait(_avatarPreview!);
        _avatarPending = false;
        _changed = true;
        committed = true;
        if (mounted) notifyUser(context, context.l10n.avatarSaved);
      }
      if (_fieldsChanged) {
        if (!mounted || app.session?.userId != widget.user.id) return;
        await app.api.updateProfile(
          nickname: _name.text.trim(),
          intro: _intro.text,
          sex: _sex == 0 && _saved.sex == 0 ? null : _sex,
        );
        _changed = true;
        committed = true;
      }
      if (!mounted) return;
      try {
        final current = await app.api.userProfile(widget.user.id);
        await _cacheProfile(app, current);
      } catch (_) {
        // Confirmed remote writes must not be retried after a refresh failure.
      }
      if (!mounted) return;
      notifyUser(context, context.l10n.profileUpdated);
      Navigator.pop(context, _changed);
    } catch (error) {
      if (mounted) {
        final uncertain =
            error is! TiebaApiException ||
            {
              'network_error',
              'invalid_response',
              'unexpected_response',
            }.contains(error.code);
        setState(() {
          _mustRefresh = uncertain;
          _partial = committed;
        });
        notifyUser(
          context,
          uncertain
              ? context.l10n.profileSaveUncertain
              : committed
              ? context.l10n.profilePartialSave
              : context.l10n.operationFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cacheProfile(AppController app, UserProfile profile) async {
    final session = app.session;
    if (session == null || session.userId != profile.id) return;
    try {
      await app.sessions.saveSession(
        session.copyWith(user: profile),
        activate: false,
      );
    } catch (_) {
      // A local cache failure does not undo a server-confirmed profile update.
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (_unsaved &&
        !await confirmAction(
          context,
          context.l10n.editProfile,
          context.l10n.discardProfileChanges,
        )) {
      return;
    }
    if (mounted) Navigator.pop(context, _changed);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !_unsaved,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_busy) _leave();
    },
    child: Scaffold(
      appBar: GlassAppBar(
        leading: IconButton(
          onPressed: _busy ? null : _leave,
          icon: const Icon(Icons.close_rounded),
          tooltip: context.l10n.cancel,
        ),
        title: Text(context.l10n.editProfile),
        actions: [
          TextButton(
            onPressed: _busy || _mustRefresh || _name.text.trim().isEmpty
                ? null
                : _save,
            child: Text(context.l10n.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_mustRefresh || _partial)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _mustRefresh
                          ? context.l10n.profileSaveUncertain
                          : context.l10n.profilePartialSave,
                    ),
                    if (_mustRefresh)
                      TextButton.icon(
                        onPressed: _busy ? null : _refresh,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(context.l10n.refresh),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 18),
          Center(
            child: _avatarPreview == null
                ? UserAvatar(url: _saved.avatar, name: _saved.name, radius: 48)
                : ClipOval(
                    child: Image.memory(
                      _avatarPreview!,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          Center(
            child: OutlinedButton.icon(
              onPressed: _busy || _mustRefresh ? null : _pickAvatar,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(context.l10n.changeAvatar),
            ),
          ),
          if (_avatarPending)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                context.l10n.avatarPending,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            enabled: !_busy,
            decoration: InputDecoration(labelText: context.l10n.nickname),
            maxLines: 1,
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<int>(
            initialValue: _sex,
            decoration: InputDecoration(labelText: context.l10n.profileSex),
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null) setState(() => _sex = value);
                  },
            items: [
              if (_saved.sex == 0)
                DropdownMenuItem(
                  value: 0,
                  enabled: false,
                  child: Text(context.l10n.profileSexUnset),
                ),
              DropdownMenuItem(
                value: 1,
                child: Text(context.l10n.profileSexMale),
              ),
              DropdownMenuItem(
                value: 2,
                child: Text(context.l10n.profileSexFemale),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _intro,
            enabled: !_busy,
            minLines: 4,
            maxLines: 8,
            maxLength: 500,
            decoration: InputDecoration(labelText: context.l10n.intro),
          ),
        ],
      ),
    ),
  );
}

class _AvatarCropPage extends StatefulWidget {
  const _AvatarCropPage({required this.image});
  final PreparedAvatar image;
  @override
  State<_AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<_AvatarCropPage> {
  double _viewport = 0, _zoom = 1, _gestureZoom = 1;
  Offset _offset = Offset.zero, _gesturePoint = Offset.zero;
  bool _busy = false;

  double get _baseScale =>
      math.max(_viewport / widget.image.width, _viewport / widget.image.height);
  Size get _displaySize => Size(
    widget.image.width * _baseScale * _zoom,
    widget.image.height * _baseScale * _zoom,
  );

  void _layout(double viewport) {
    if (_viewport == viewport) return;
    _viewport = viewport;
    _zoom = 1;
    final size = _displaySize;
    _offset = Offset(
      (_viewport - size.width) / 2,
      (_viewport - size.height) / 2,
    );
  }

  Future<void> _crop() async {
    if (_busy || _viewport <= 0) return;
    setState(() => _busy = true);
    try {
      final region = AvatarCropRegion.fromViewport(
        imageWidth: widget.image.width,
        imageHeight: widget.image.height,
        viewport: _viewport,
        zoom: _zoom,
        offsetX: _offset.dx,
        offsetY: _offset.dy,
      );
      final bytes = await cropAvatarJpeg(widget.image, region);
      if (mounted) Navigator.pop(context, bytes);
    } catch (_) {
      if (mounted) notifyUser(context, context.l10n.imageUnsupported);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: GlassAppBar(
      title: Text(context.l10n.cropAvatar),
      actions: [
        TextButton(
          onPressed: _busy ? null : _crop,
          child: Text(context.l10n.done),
        ),
      ],
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = math.max(
            80.0,
            math.min(
              math.min(constraints.maxWidth - 40, constraints.maxHeight - 110),
              420.0,
            ),
          );
          _layout(side);
          final size = _displaySize;
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_busy) const LinearProgressIndicator(),
              Center(
                child: SizedBox(
                  width: side,
                  height: side,
                  child: GestureDetector(
                    onScaleStart: _busy
                        ? null
                        : (details) {
                            _gestureZoom = _zoom;
                            _gesturePoint =
                                (details.localFocalPoint - _offset) / _zoom;
                          },
                    onScaleUpdate: _busy
                        ? null
                        : (details) => setState(() {
                            _zoom = (_gestureZoom * details.scale).clamp(1, 5);
                            final desired =
                                details.localFocalPoint - _gesturePoint * _zoom;
                            final display = _displaySize;
                            _offset = Offset(
                              desired.dx.clamp(side - display.width, 0),
                              desired.dy.clamp(side - display.height, 0),
                            );
                          }),
                    child: ClipRect(
                      child: Stack(
                        children: [
                          Positioned(
                            left: _offset.dx,
                            top: _offset.dy,
                            width: size.width,
                            height: size.height,
                            child: Image.memory(
                              widget.image.bytes,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(context.l10n.cropHint, textAlign: TextAlign.center),
              ),
            ],
          );
        },
      ),
    ),
  );
}
