import 'gofile.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;

class DownloadItem {
  DownloadItem(Map data)
    : id = data['id'] as String,
      name = data['name'] as String,
      state = data['state'] as String,
      received = (data['received'] as num?)?.toInt() ?? 0,
      total = (data['total'] as num?)?.toInt() ?? -1,
      path = data['path'] as String? ?? '',
      error = data['error'] as String? ?? '',
      sourcePage = Uri.tryParse('${data['sourcePage'] ?? ''}'),
      remoteID = data['remoteID'] as String? ?? '',
      refreshes = data['refreshes'] is num
          ? (data['refreshes'] as num).toInt()
          : 0;
  final String id, name, state, path, error, remoteID;
  final Uri? sourcePage;
  final int refreshes;
  final int received, total;
}

class FileRequest {
  const FileRequest(
    this.url,
    this.name, {
    this.referer,
    this.cookie,
    this.folder = '',
    this.sourcePage,
    this.remoteID = '',
  });
  final Uri url;
  final String name, folder;
  final String? referer, cookie;
  final Uri? sourcePage;
  final String remoteID;
}

FileRequest refreshedFile(DownloadItem item, List<FileRequest> files) {
  final matches = files.where(
    (file) =>
        file.remoteID.isNotEmpty &&
        file.remoteID == item.remoteID &&
        file.sourcePage == item.sourcePage,
  );
  if (matches.length != 1) throw const FormatException('File identity changed');
  return matches.single;
}

class DownloadManager extends ChangeNotifier {
  static final instance = DownloadManager._();
  DownloadManager._();
  static const channel = MethodChannel('dev.sylar.tablet/downloads');
  Timer? _timer;
  List<DownloadItem> tasks = [];
  String? directory;
  bool resolving = false;
  final Set<String> refreshingLinks = {};
  Map<String, dynamic> fileJob = {};
  bool _refreshing = false;
  bool get fileJobRunning => fileJob['state'] == 'running';
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<void> init() async {
    if (!supported) return;
    directory = await channel.invokeMethod<String>('directory');
    await refresh();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(refresh()),
    );
  }

  Future<void> refresh() async {
    if (!supported || _refreshing) return;
    _refreshing = true;
    try {
      final data = await channel.invokeListMethod<dynamic>('tasks') ?? [];
      tasks = data.map((e) => DownloadItem(e as Map)).toList();
      fileJob = Map<String, dynamic>.from(
        await channel.invokeMapMethod('fileJobStatus') ?? {},
      );
      notifyListeners();
      final expired = tasks
          .where(
            (item) =>
                item.state == 'expired' &&
                item.refreshes < 2 &&
                item.remoteID.isNotEmpty,
          )
          .firstOrNull;
      if (expired != null && refreshingLinks.isEmpty) {
        unawaited(_refreshLink(expired));
      }
    } on PlatformException {
      // Keep the last known queue during a transient service failure.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> enqueue(FileRequest file) async {
    if (!supported) throw UnsupportedError('Android download service required');
    if (!validDownloadUrl(file.url)) {
      throw const FormatException('Invalid download URL');
    }
    await channel.invokeMethod<void>('enqueue', {
      'url': '${file.url}',
      'name': file.name,
      'referer': file.referer,
      'cookie': file.cookie,
      'folder': file.folder,
      'sourcePage': file.sourcePage?.toString(),
      'remoteID': file.remoteID,
    });
    await refresh();
  }

  Future<void> resolve(Uri url) async {
    resolving = true;
    notifyListeners();
    try {
      final files = await HostResolver().resolve(url);
      for (final file in files) {
        await enqueue(file);
      }
    } finally {
      resolving = false;
      notifyListeners();
    }
  }

  Future<void> action(String action, String id) async {
    final item = tasks.where((t) => t.id == id).firstOrNull;
    if (action == 'resume' &&
        item != null &&
        item.remoteID.isNotEmpty &&
        item.sourcePage != null) {
      await _refreshLink(item);
      return;
    }
    await channel.invokeMethod<void>(action, {'id': id});
    await refresh();
  }

  Future<void> _refreshLink(DownloadItem item) async {
    if (!refreshingLinks.add(item.id)) return;
    notifyListeners();
    try {
      final file = refreshedFile(
        item,
        await HostResolver().resolve(item.sourcePage!),
      );
      await channel.invokeMethod<void>('refreshLink', {
        'id': item.id,
        'url': '${file.url}',
        'referer': file.referer,
        'cookie': file.cookie,
        'remoteID': file.remoteID,
      });
    } catch (_) {
      await channel.invokeMethod<void>('resolutionFailed', {'id': item.id});
    } finally {
      refreshingLinks.remove(item.id);
      notifyListeners();
      await refresh();
    }
  }

  Future<void> startFileJob(
    String operation,
    String path, {
    String? password,
  }) async {
    fileJob = Map<String, dynamic>.from(
      await channel.invokeMapMethod('startFileJob', {
            'operation': operation,
            'path': path,
            'password': password,
          }) ??
          {},
    );
    notifyListeners();
  }

  Future<String> resolvedPath(String path) async =>
      await channel.invokeMethod<String>('resolvePath', {'path': path}) ?? path;

  Future<void> openExternal(String path) =>
      channel.invokeMethod<void>('openFile', {'path': path});
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

bool validDownloadUrl(Uri url) =>
    const ['https', 'http'].contains(url.scheme) &&
    url.host.isNotEmpty &&
    url.userInfo.isEmpty;

class HostResolver {
  final Dio client = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      maxRedirects: 4,
    ),
  );
  Future<dynamic> _get(Uri url) async => (await client.get<dynamic>(
    '$url',
    options: Options(headers: {'User-Agent': 'Mozilla/5.0 Chrome/140.0.0.0'}),
  )).data;
  bool _host(Uri url, String name) =>
      url.host == name || url.host.endsWith('.$name');
  Future<List<FileRequest>> resolve(Uri url, {int depth = 0}) async {
    if (!validDownloadUrl(url) || depth > 3) {
      throw const FormatException('Invalid file link');
    }
    try {
      if ([
        'filester.me',
        'filester.si',
        'filester.to',
      ].any((h) => _host(url, h))) {
        return await _filester(url, depth);
      }
      if (_host(url, 'pixeldrain.com')) return await _pixeldrain(url);
      if (_host(url, 'gofile.io')) return await _gofile(url);
      if (RegExp(r'^(?:www\.)?bunkr\.[a-z]+$').hasMatch(url.host)) {
        return await _bunkr(url, depth);
      }
      return [FileRequest(url, url.pathSegments.lastOrNull ?? 'download')];
    } finally {
      if (depth == 0) client.close();
    }
  }

  Future<List<FileRequest>> _filester(Uri url, int depth) async {
    final source = await _get(url);
    final doc = html.parse('$source');
    if (url.path.startsWith('/f/')) {
      final pages =
          int.tryParse(
            doc.querySelector('#loadAllPagesBtn')?.attributes['data-total'] ??
                '',
          ) ??
          1;
      if (pages > 200) throw const FormatException('Album limit exceeded');
      final targets = <Uri>{};
      for (var page = 1; page <= pages; page++) {
        final pageDoc = page == 1
            ? doc
            : html.parse(
                '${await _get(url.replace(queryParameters: {'page': '$page'}))}',
              );
        for (final card in pageDoc.querySelectorAll(
          '#filesGrid .file-item,#subfoldersGrid .subfolder-item',
        )) {
          final href =
              card.attributes['href'] ??
              card.querySelector('a[href]')?.attributes['href'] ??
              RegExp(
                r'''window\.location\.href\s*=\s*['"](/[df]/[A-Za-z0-9_-]+)['"]''',
              ).firstMatch(card.attributes['onclick'] ?? '')?[1];
          if (href != null) targets.add(url.resolve(href));
        }
      }
      final result = <FileRequest>[];
      for (final target in targets) {
        if (target.host == url.host) {
          result.addAll(await resolve(target, depth: depth + 1));
        }
      }
      if (result.isEmpty) throw const FormatException('Empty album');
      return result;
    }
    final title = doc.querySelector('#fileTitle')?.text.trim();
    if (title == null || title.isEmpty) {
      throw const FormatException('Missing file metadata');
    }
    final response = await client.post<dynamic>(
      '${url.resolve('/v2/api/public/download')}',
      data: {'file_slug': url.pathSegments.last},
      options: Options(headers: {'Referer': '$url', 'Origin': url.origin}),
    );
    final data = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    final base = Uri.parse('${data['server'] ?? 'https://cn1.filester.me'}');
    if (base.scheme != 'https' ||
        !(RegExp(r'^fsc[1-9][0-9]*\.cdn\.cr$').hasMatch(base.host) ||
            [
              'filester.me',
              'filester.si',
              'filester.to',
            ].any((h) => _host(base, h)))) {
      throw const FormatException('Unrecognized file server');
    }
    final name = '${data['name'] ?? title}',
        file = '${data['file'] ?? ''}',
        token = '${data['token'] ?? ''}';
    if (file.isEmpty ||
        file.contains('..') ||
        token.isEmpty ||
        data['success'] == false) {
      throw const FormatException('Missing download token');
    }
    return [
      FileRequest(
        base
            .resolve('/v2/$file')
            .replace(
              queryParameters: {'token': token, 'download': 'true', 'n': name},
            ),
        name,
        referer: '$url',
        sourcePage: url.removeFragment().replace(query: ''),
        remoteID: 'filester:${url.pathSegments.last}',
      ),
    ];
  }

  Future<List<FileRequest>> _pixeldrain(Uri url) async {
    final id = url.pathSegments.last;
    final folder = url.path.startsWith('/l/');
    final data = await _get(
      url.resolve('/api/${folder ? 'list/$id' : 'file/$id/info'}'),
    ) as Map;
    final files = folder ? data['files'] as List : [data];
    return files
        .whereType<Map>()
        .map(
          (f) => FileRequest(
            url.resolve('/api/file/${f['id'] ?? id}?download'),
            '${f['name']}',
            folder: folder ? '${data['title'] ?? id}' : '',
            sourcePage: url.resolve('/u/${f['id'] ?? id}'),
            remoteID: 'pixeldrain:${f['id'] ?? id}',
          ),
        )
        .toList();
  }

  Future<List<FileRequest>> _gofile(Uri url) async {
    final page = gofilePage(url);
    final entries = await collectGofile(
      page,
      (url, page) => captureGofile(url, page: page),
    );
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri('https://gofile.io/'),
    );
    final token = cookies
        .where((c) => c.name == 'accountToken')
        .firstOrNull
        ?.value;
    return [
      for (final child in entries)
        FileRequest(
          Uri.parse('${child['link']}'),
          '${child['name']}',
          cookie: token == null ? null : 'accountToken=$token',
          referer: 'https://gofile.io/',
          folder: '${child['folder']}',
          sourcePage: Uri.parse('${child['sourcePage']}'),
          remoteID: 'gofile:${child['id']}',
        ),
    ];
  }

  Future<List<FileRequest>> _bunkr(Uri url, int depth) async {
    final source = '${await _get(url)}';
    final doc = html.parse(source);
    if (url.path.startsWith('/a/')) {
      final targets = doc
          .querySelectorAll('a[href*="/f/"]')
          .map((a) => url.resolve(a.attributes['href']!))
          .toSet();
      final result = <FileRequest>[];
      for (final target in targets.take(10000)) {
        if (target.host == url.host) {
          result.addAll(await resolve(target, depth: depth + 1));
        }
      }
      if (result.isEmpty) throw const FormatException('Empty album');
      return result;
    }
    final id = RegExp(r'''(?:id\s*:\s*|data-id=["'])(\d+)''')
        .firstMatch(source)?[1];
    if (id == null) throw const FormatException('Missing file id');
    final response = await client.post<dynamic>(
      'https://apidl.bunkr.ru/api/_001_v2',
      data: {'id': id},
      options: Options(headers: {'Referer': 'https://get.bunkrr.su/file/$id'}),
    );
    final data = response.data as Map;
    var target = '${data['url']}';
    if (data['encrypted'] == true) {
      final bytes = base64Decode(target),
          key = utf8.encode(
            'SECRET_KEY_${(data['timestamp'] as num).toInt() ~/ 3600}',
          );
      target = utf8.decode([
        for (var i = 0; i < bytes.length; i++) bytes[i] ^ key[i % key.length],
      ]);
    }
    final file = Uri.parse(target);
    if (!validDownloadUrl(file)) {
      throw const FormatException('Invalid resolved URL');
    }
    return [
      FileRequest(
        file,
        doc.querySelector('h1')?.text.trim() ?? file.pathSegments.last,
        referer: '$url',
        sourcePage: url.removeFragment().replace(query: ''),
        remoteID: 'bunkr:$id',
      ),
    ];
  }
}

String formatBytes(int value) {
  if (value < 0) return '--';
  if (value < 1024) return '$value B';
  final units = ['KB', 'MB', 'GB', 'TB'];
  var size = value / 1024;
  var index = 0;
  while (size >= 1024 && index < units.length - 1) {
    size /= 1024;
    index++;
  }
  return '${size.toStringAsFixed(1)} ${units[index]}';
}

Future<List<FileSystemEntity>> localFiles(String path) async {
  final directory = Directory(path);
  if (!await directory.exists()) return [];
  final entries = await directory
      .list(followLinks: false)
      .where(
        (e) =>
            !e.path.endsWith('.part') &&
            !e.path.split(Platform.pathSeparator).last.startsWith('.') &&
            e is! Link,
      )
      .toList();
  final dates = <String, DateTime>{};
  for (final e in entries) {
    dates[e.path] = (await e.stat()).modified;
  }
  entries.sort((a, b) => dates[b.path]!.compareTo(dates[a.path]!));
  return entries;
}
