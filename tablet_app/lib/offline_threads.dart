import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import 'forum_identity.dart';
import 'models.dart';
import 'parsers.dart';
import 'session.dart';
import 'site.dart';

class OfflineThread {
  OfflineThread({
    required this.id,
    required this.folder,
    required this.root,
    required this.title,
    required this.created,
  });
  final String id, folder;
  final Uri root;
  String title;
  final DateTime created;
  int totalPages = 0;
  final Map<int, String> pages = {};
  // Every asset retains the page that supplied its referer.
  final Map<String, String> sources = {};
  final Map<String, String> assets = {};
  String status = 'Queued';
  String? error;
  bool pending = true;
  bool get complete => status == 'Completed';
  double? get progress => totalPages == 0
      ? null
      : (pages.length + assets.length) / (totalPages + sources.length);
  Map<String, Object?> toJson() => {
    'id': id,
    'folder': folder,
    'root': '$root',
    'title': title,
    'created': created.toIso8601String(),
    'totalPages': totalPages,
    'pages': pages.map((k, v) => MapEntry('$k', v)),
    'sources': sources,
    'assets': assets,
    'status': status,
    'error': error,
    'pending': pending,
  };
  factory OfflineThread.fromJson(Map<String, dynamic> value) {
    final job = OfflineThread(
      id: value['id'] as String,
      folder: value['folder'] as String,
      root: Uri.parse(value['root'] as String),
      title: value['title'] as String,
      created: DateTime.parse(value['created'] as String),
    );
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(job.id) ||
        !RegExp(r'^[a-f0-9]{64}-[0-9]+$').hasMatch(job.folder)) {
      throw const FormatException('Invalid snapshot identity');
    }
    job.totalPages = value['totalPages'] as int;
    if (job.totalPages < 0 || job.totalPages > 10000) {
      throw const FormatException('Invalid page count');
    }
    job.pages.addAll(
      (value['pages'] as Map).map(
        (k, v) => MapEntry(int.parse(k as String), v as String),
      ),
    );
    job.sources.addAll(Map<String, String>.from(value['sources'] as Map));
    job.assets.addAll(Map<String, String>.from(value['assets'] as Map));
    if (job.pages.keys.any((p) => p < 1 || p > job.totalPages) ||
        job.pages.values.any(
          (p) => !RegExp(r'^page-[0-9]+\.json$').hasMatch(p),
        ) ||
        job.assets.values.any(
          (p) => !RegExp(r'^[a-f0-9]{64}\.image$').hasMatch(p),
        )) {
      throw const FormatException('Invalid snapshot paths');
    }
    job.status = value['status'] as String;
    job.error = value['error'] as String?;
    job.pending = value['pending'] as bool;
    return job;
  }
}

typedef OfflineImageLoader = Future<Uint8List> Function(Uri url, Uri referer);

/// A durable, serial snapshot queue. Closing its sheet does not own its lifetime.
class OfflineThreads extends ChangeNotifier {
  OfflineThreads(
    this.session, {
    Directory? directory,
    Future<PageCapture> Function(Uri)? loadPage,
    OfflineImageLoader? loadImage,
  }) : _directoryOverride = directory,
       _loadPage = loadPage ?? session.fetch,
       _loadImage =
           loadImage ??
           ((url, referer) => _downloadImage(session.site, url, referer));
  final ForumSession session;
  final Directory? _directoryOverride;
  final Future<PageCapture> Function(Uri) _loadPage;
  final OfflineImageLoader _loadImage;
  final Map<String, OfflineThread> _jobs = {};
  Directory? _directory;
  Future<void>? _initialization, _worker;
  Future<void> _writes = Future.value();
  bool readOnly = false, _disposed = false;
  List<OfflineThread> get jobs =>
      _jobs.values.toList()..sort((a, b) => b.created.compareTo(a.created));
  bool get working => _worker != null;
  String _id(Uri root) =>
      sha256.convert(utf8.encode(session.site.threadKey(root)!)).toString();
  OfflineThread? forUrl(Uri url) {
    final root = session.site.threadRoot(url);
    return root == null ? null : _jobs[_id(root)];
  }

  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    try {
      _directory =
          _directoryOverride ??
          Directory(
            '${(await getApplicationSupportDirectory()).path}/offline-threads',
          );
      await _directory!.create(recursive: true);
      final file = File('${_directory!.path}/index.json');
      if (await file.exists()) {
        final value = jsonDecode(await file.readAsString()) as Map;
        if (value['version'] != 1) {
          throw const FormatException('Unsupported index');
        }
        final restored = <String, OfflineThread>{};
        for (final data in value['jobs'] as List) {
          final job = OfflineThread.fromJson(
            Map<String, dynamic>.from(data as Map),
          );
          if (session.site.module != Module.south ||
              session.site.threadRoot(job.root) != job.root ||
              _id(job.root) != job.id) {
            throw const FormatException('Invalid snapshot root');
          }
          restored[job.id] = job;
        }
        _jobs.addAll(restored);
      }
    } catch (_) {
      // Never replace a corrupt or unsupported manifest with an empty index.
      readOnly = true;
    }
    _notify();
  }

  Future<void> resume() async {
    await initialize();
    if (!readOnly) _start();
  }

  Future<OfflineThread> enqueue(Uri url, String title) async {
    await initialize();
    final root = session.site.threadRoot(url);
    if (readOnly || root == null || session.site.module != Module.south) {
      throw StateError('Snapshot unavailable');
    }
    final id = _id(root);
    final existing = _jobs[id];
    if (existing != null) {
      if (!existing.complete) await retry(existing);
      return existing;
    }
    final job = OfflineThread(
      id: id,
      folder: '$id-${DateTime.now().microsecondsSinceEpoch}',
      root: root,
      title: title,
      created: DateTime.now(),
    );
    _jobs[id] = job;
    await _persist();
    _start();
    return job;
  }

  Future<void> retry(OfflineThread job) async {
    if (readOnly || _jobs[job.id] != job || _disposed) return;
    job.pending = true;
    job.status = 'Queued';
    job.error = null;
    await _persist();
    _start();
  }

  Future<void> pause(OfflineThread job) async {
    job.pending = false;
    job.status = 'Paused';
    await _persist();
  }

  Future<void> remove(OfflineThread job) async {
    if (readOnly || _jobs[job.id] != job) return;
    job.pending = false;
    _jobs.remove(job.id);
    await _persist();
    // The worker checks identity after every await, so no late response can
    // recreate this directory or resurrect an explicitly removed snapshot.
    final folder = Directory('${_directory!.path}/${job.folder}');
    if (await folder.exists()) await folder.delete(recursive: true);
  }

  bool _active(OfflineThread job) =>
      !_disposed && !readOnly && job.pending && _jobs[job.id] == job;
  void _start() {
    if (_worker != null || _disposed || readOnly) return;
    _worker = _drain().whenComplete(() {
      _worker = null;
      if (!_disposed && !readOnly && _jobs.values.any((j) => j.pending)) {
        _start();
      }
    });
  }

  Future<void> get idle async {
    while (_worker != null) {
      await _worker;
    }
  }

  Future<void> _drain() async {
    while (!_disposed && !readOnly) {
      final job = _jobs.values.where((j) => j.pending).firstOrNull;
      if (job == null) return;
      try {
        await _cache(job);
      } catch (error) {
        if (!_active(job)) continue;
        job.pending = false;
        job.status = 'Incomplete';
        job.error =
            error is ReaderFailure && error.kind == FailureKind.verification
            ? 'Login or verify in browser'
            : error is ReaderFailure && error.kind == FailureKind.login
            ? 'Sign in required'
            : 'Page unavailable';
        await _persist();
      }
    }
  }

  String _path(OfflineThread job, String leaf) =>
      '${_directory!.path}/${job.folder}/$leaf';
  Future<void> _cache(OfflineThread job) async {
    job.status = 'Downloading';
    job.error = null;
    await _persist();
    var missingImages = false;
    // Recover missing files, keeping valid downloaded pages and assets.
    for (final key in job.pages.keys.toList()) {
      if (!await File(_path(job, job.pages[key]!)).exists()) {
        job.pages.remove(key);
      }
    }
    for (final key in job.assets.keys.toList()) {
      if (!await File(_path(job, job.assets[key]!)).exists()) {
        job.assets.remove(key);
      }
    }
    for (
      var number = 1;
      number <= (job.totalPages == 0 ? 1 : job.totalPages);
      number++
    ) {
      if (!_active(job)) return;
      if (job.pages.containsKey(number)) continue;
      final capture = await _loadPage(session.site.pageUrl(job.root, number));
      if (!_active(job)) return;
      final page = PageParser(session.site).parse(capture.html, capture.url);
      if (capture.cached ||
          page.kind != PageKind.posts ||
          !session.site.sameThread(page.url, job.root) ||
          session.site.filtered(page.url) ||
          page.pageNumber != number ||
          session.site.pageNumber(page.url) != number) {
        throw const ReaderFailure(FailureKind.unsupported);
      }
      if (job.totalPages == 0) {
        if (!page.pageCountConfirmed ||
            page.totalPages < 1 ||
            page.totalPages > 10000) {
          throw const ReaderFailure(FailureKind.unsupported);
        }
        job.totalPages = page.totalPages;
        job.title = page.title;
      }
      final leaf = 'page-$number.json';
      await Directory(_path(job, '')).create(recursive: true);
      if (!_active(job)) return;
      await _atomic(
        File(_path(job, leaf)),
        jsonEncode({'url': '${page.url}', 'html': capture.html}),
      );
      if (!_active(job)) return;
      job.pages[number] = leaf;
      for (final url in _images(page)) {
        job.sources.putIfAbsent('$url', () => '${page.url}');
      }
      await _persist();
    }
    for (final source in job.sources.entries.toList()) {
      if (!_active(job)) return;
      if (job.assets.containsKey(source.key)) continue;
      try {
        final bytes = await _loadImage(
          Uri.parse(source.key),
          Uri.parse(source.value),
        );
        if (!_active(job)) return;
        final leaf = '${sha256.convert(utf8.encode(source.key))}.image';
        final file = File(_path(job, leaf));
        await file.writeAsBytes(bytes, flush: true);
        if (!_active(job)) return;
        job.assets[source.key] = leaf;
        await _persist();
      } catch (_) {
        missingImages = true;
      }
    }
    if (!_active(job)) return;
    job.pending = false;
    job.status = missingImages || job.assets.length != job.sources.length
        ? 'Incomplete'
        : 'Completed';
    job.error = job.complete ? null : 'Some images unavailable';
    await _persist();
  }

  Future<PageCapture> capture(OfflineThread job, Uri url) async {
    await initialize();
    if (_jobs[job.id] != job ||
        !session.site.sameThread(job.root, url) ||
        session.site.filtered(url)) {
      throw const ReaderFailure(FailureKind.unsupported);
    }
    final number = session.site.pageNumber(url);
    final leaf = job.pages[number];
    if (leaf == null) throw const ReaderFailure(FailureKind.network);
    final value =
        jsonDecode(await File(_path(job, leaf)).readAsString()) as Map;
    final capture = PageCapture(
      Uri.parse(value['url'] as String),
      value['html'] as String,
      cached: true,
    );
    if (!session.site.sameThread(capture.url, job.root) ||
        session.site.pageNumber(capture.url) != number) {
      throw const ReaderFailure(FailureKind.unsupported);
    }
    return capture;
  }

  Map<String, String> localAssets(OfflineThread job) =>
      job.assets.map((k, v) => MapEntry(k, _path(job, v)));
  Future<void> _persist() {
    if (readOnly || _directory == null) return Future.value();
    final data = jsonEncode({
      'version': 1,
      'jobs': _jobs.values.map((j) => j.toJson()).toList(),
    });
    final write = _writes.then(
      (_) => _atomic(File('${_directory!.path}/index.json'), data),
    );
    _writes = write.catchError((Object _) {
      readOnly = true;
      _notify();
    });
    _notify();
    return write;
  }

  static Future<void> _atomic(File file, String text) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(text, flush: true);
    await temporary.rename(file.path);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

Iterable<Uri> _images(ForumPage page) sync* {
  Iterable<Uri> collect(List<BodyBlock> blocks) sync* {
    for (final block in blocks) {
      if (block.kind == BlockKind.image && block.url != null) yield block.url!;
      if (block.originalUrl != null) yield block.originalUrl!;
      if (block.posterUrl != null) yield block.posterUrl!;
      yield* collect(block.children);
    }
  }

  for (final post in page.posts) {
    if (post.avatar != null) yield post.avatar!;
    yield* collect(post.blocks);
  }
}

Future<Uint8List> _downloadImage(ForumSite site, Uri url, Uri referer) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    var target = url;
    for (var hop = 0; hop < 6; hop++) {
      if (!const ['https', 'http'].contains(target.scheme) ||
          target.userInfo.isNotEmpty) {
        throw const FormatException('Unsupported image URL');
      }
      final request = await client.getUrl(target);
      request.followRedirects = false;
      request.headers.set('User-Agent', ForumSession.desktopAgent);
      request.headers.set('Referer', '$referer');
      if (site.sameOrigin(target)) {
        final cookies = await CookieManager.instance().getCookies(
          url: WebUri('$target'),
        );
        if (cookies.isNotEmpty) {
          request.headers.set(
            'Cookie',
            cookies.map((c) => '${c.name}=${c.value}').join('; '),
          );
        }
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.isRedirect) {
        final location = response.headers.value('location');
        if (location == null) throw const HttpException('Missing redirect');
        target = target.resolve(location);
        await response.drain<void>();
        continue;
      }
      if (response.statusCode != 200 ||
          response.contentLength > 32 * 1024 * 1024) {
        throw const HttpException('Invalid image response');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        bytes.add(chunk);
        if (bytes.length > 32 * 1024 * 1024) {
          throw const HttpException('Image too large');
        }
      }
      final data = bytes.takeBytes();
      // A successful HTTP status can still contain an anti-hotlink HTML page.
      final codec = await ui.instantiateImageCodec(data, targetWidth: 1);
      codec.dispose();
      return data;
    }
    throw const HttpException('Too many redirects');
  } finally {
    client.close(force: true);
  }
}
