import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:protobuf/protobuf.dart';

import 'models.dart';

class TiebaApiException implements Exception {
  const TiebaApiException(
    this.message, {
    this.code = '',
    this.requiresLogin = false,
    this.verificationUrl,
  });
  final String message, code;
  final bool requiresLogin;
  final Uri? verificationUrl;
  @override
  String toString() => message;
}

class TiebaTransport {
  TiebaTransport({required this.sessionProvider, Dio? dio, String? deviceId})
    : deviceId = deviceId ?? _randomDeviceId(),
      dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 45),
              sendTimeout: const Duration(seconds: 45),
              followRedirects: false,
            ),
          );
  final SessionProvider sessionProvider;
  final Dio dio;
  final String deviceId;
  static const apiOrigin = 'https://tiebac.baidu.com';
  static const webOrigin = 'https://tieba.baidu.com';
  static String _randomDeviceId() =>
      '${List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join().toUpperCase()}|0';
  TiebaSession requireSession() {
    final session = sessionProvider();
    if (session == null || !session.isAuthenticated) {
      throw const TiebaApiException(
        'Sign in to continue.',
        code: 'login_required',
        requiresLogin: true,
      );
    }
    return session;
  }

  Map<String, String> headers({
    String version = '12.52.1.0',
    TiebaSession? session,
    bool web = false,
  }) {
    session ??= sessionProvider();
    return {
      'User-Agent': web
          ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 tieba/$version'
          : 'bdtb for Android $version',
      'Accept': '*/*',
      'cuid': deviceId,
      'cuid_galaxy2': deviceId,
      'cuid_gid': '',
      if (session?.userId.isNotEmpty == true)
        'client_user_token': session!.userId,
      'Cookie': web && session != null
          ? _webCookie(session)
          : 'ka=open;CUID=$deviceId;',
    };
  }

  String _webCookie(TiebaSession session) => session.rawCookie.isNotEmpty
      ? session.rawCookie.replaceAll(RegExp(r'[\r\n]'), '')
      : 'BDUSS=${session.bduss};STOKEN=${session.stoken};';

  Map<String, String> commonForm({
    String version = '11.10.8.6',
    TiebaSession? session,
  }) {
    session ??= sessionProvider();
    return {
      '_client_type': '2',
      '_client_version': version,
      '_client_id': 'wappc_${deviceId.split('|').first}',
      '_os_version': '33',
      'model': 'iPhone',
      'net_type': '1',
      'timestamp': '${DateTime.now().millisecondsSinceEpoch}',
      'cuid': deviceId,
      'cuid_galaxy2': deviceId,
      'cuid_gid': '',
      'from': 'tieba',
      if (session?.bduss.isNotEmpty == true) 'BDUSS': session!.bduss,
      if (session?.stoken.isNotEmpty == true) 'stoken': session!.stoken,
    };
  }

  static String sign(Map<String, String> params) {
    final values =
        params.entries
            .where((e) => e.key != 'sign')
            .map((e) => '${e.key}=${e.value}')
            .toList()
          ..sort();
    return md5
        .convert(utf8.encode('${values.join()}tiebaclient!!!'))
        .toString()
        .toUpperCase();
  }

  Future<JsonMap> form(
    String path,
    Map<String, dynamic> fields, {
    bool authenticated = false,
    String version = '11.10.8.6',
    TiebaSession? session,
    Set<String> omit = const {},
  }) async {
    if (authenticated) requireSession();
    session ??= sessionProvider();
    final params = commonForm(version: version, session: session);
    for (final entry in fields.entries) {
      if (entry.value != null) params[entry.key] = stringValue(entry.value);
    }
    for (final key in omit) {
      params.remove(key);
    }
    params['sign'] = sign(params);
    final response = await _request(
      () => dio.post<String>(
        '$apiOrigin$path',
        data: params,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: false,
          headers: headers(version: version, session: session),
        ),
      ),
    );
    return _decodeJson(response.data, session: session);
  }

  Future<JsonMap> web(
    String path,
    Map<String, dynamic> query, {
    bool authenticated = false,
  }) async {
    if (authenticated) requireSession();
    final session = sessionProvider();
    final response = await _request(
      () => dio.get<String>(
        '$webOrigin$path',
        queryParameters: query,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          headers: {
            ...headers(web: true, session: session),
            'Referer': '$webOrigin/mo/q/hybrid/search',
          },
        ),
      ),
    );
    return _decodeJson(response.data, session: session);
  }

  Future<JsonMap> protobuf(
    String path,
    GeneratedMessage request,
    GeneratedMessage Function(List<int>) decode, {
    bool authenticated = false,
    bool outerToken = true,
    bool posting = false,
    bool legacy = false,
  }) async {
    if (authenticated) requireSession();
    final session = sessionProvider();
    final fields = <String, String>{
      if (outerToken && session != null) 'stoken': session.stoken,
    };
    if (posting || legacy) {
      fields.addAll(
        commonForm(
          version: posting ? '12.35.1.0' : '11.10.8.6',
          session: session,
        ),
      );
      fields['sign'] = sign(fields);
    }
    final body = FormData();
    body.fields.addAll(fields.entries);
    body.files.add(
      MapEntry(
        'data',
        MultipartFile.fromBytes(request.writeToBuffer(), filename: 'file'),
      ),
    );
    final response = await _request(
      () => dio.post<List<int>>(
        '$apiOrigin$path',
        data: body,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: false,
          headers: {
            ...headers(
              version: posting
                  ? '12.35.1.0'
                  : legacy
                  ? '11.10.8.6'
                  : '12.52.1.0',
              session: session,
            ),
            'x_bd_data_type': 'protobuf',
          },
        ),
      ),
    );
    final bytes = response.data ?? <int>[];
    if (bytes.isEmpty) {
      throw const TiebaApiException(
        'The server returned an empty response.',
        code: 'empty_response',
      );
    }
    if (bytes.first == 123 || bytes.first == 91 || bytes.first == 60) {
      _decodeJson(utf8.decode(bytes, allowMalformed: true), session: session);
      throw const TiebaApiException(
        'The server returned an unexpected response format.',
        code: 'invalid_response',
      );
    }
    try {
      final json = normalizeJson(decode(bytes).toProto3Json());
      checkError(json, secrets: _secrets(session));
      return objectValue(json['data']);
    } on TiebaApiException {
      rethrow;
    } catch (_) {
      throw const TiebaApiException(
        'This response is incompatible with the current protocol schema.',
        code: 'protocol_error',
      );
    }
  }

  Future<JsonMap> upload(
    String path,
    Map<String, String> fields,
    Uint8List bytes, {
    String fieldName = 'chunk',
    String version = '12.25.1.0',
  }) async {
    final session = requireSession();
    final params = {
      ...commonForm(version: version, session: session),
      ...fields,
    };
    params['sign'] = sign(params);
    final body = FormData()..fields.addAll(params.entries);
    body.files.add(
      MapEntry(fieldName, MultipartFile.fromBytes(bytes, filename: 'file')),
    );
    final response = await _request(
      () => dio.post<String>(
        '$apiOrigin$path',
        data: body,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          headers: headers(version: version, session: session),
        ),
      ),
    );
    return _decodeJson(response.data, session: session);
  }

  Future<String> fetchZid() async {
    const appKey = '200033';
    const protocolKey = 'ea737e4f435b53786043369d2e5ace4f';
    final cuid =
        '${md5.convert(utf8.encode(deviceId)).toString().toUpperCase()}|0';
    final cuidHash = md5.convert(utf8.encode(cuid)).toString();
    final timestamp = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final pathHash = md5
        .convert(utf8.encode('$appKey$timestamp$protocolKey'))
        .toString();
    final compressed = GZipEncoder().encodeBytes(
      utf8.encode(
        jsonEncode({
          'module_section': [
            {'zid': cuid},
          ],
        }),
      ),
    );
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    final key = Uint8List.fromList(
      utf8.encode(
        List.generate(
          16,
          (_) => alphabet[random.nextInt(alphabet.length)],
        ).join(),
      ),
    );
    final encrypted = sofireAes(compressed, key, encrypt: true);
    final payload = Uint8List.fromList([
      ...encrypted,
      ...md5.convert(compressed).bytes,
    ]);
    final skey = base64Encode(
      rc442(key, Uint8List.fromList(utf8.encode(cuidHash))),
    );
    try {
      final response = await _request(
        () => dio.post<String>(
          'https://sofire.baidu.com/c/11/z/100/$appKey/$timestamp/$pathHash',
          queryParameters: {'skey': skey},
          data: payload,
          options: Options(
            responseType: ResponseType.plain,
            contentType: Headers.formUrlEncodedContentType,
            followRedirects: false,
            headers: {
              'Pragma': 'no-cache',
              'Accept': '*/*',
              'Accept-Language': 'en',
              'x-device-id': cuidHash,
              'x-client-src': 'src',
              'User-Agent': 'x6/$appKey/12.35.1.0/4.4.1.3',
              'x-sdk-ver': 'sofire/3.5.9.6',
              'x-plu-ver': 'x6/4.4.1.3',
              'x-app-ver': 'com.baidu.tieba/12.35.1.0',
              'x-api-ver': '33',
            },
          ),
        ),
      );
      final result = objectValue(jsonDecode(response.data ?? ''));
      final responseKey = rc442(
        base64Decode(stringValue(result['skey']).replaceAll(RegExp(r'\s'), '')),
        Uint8List.fromList(utf8.encode(cuidHash)),
      );
      final encoded = base64Decode(
        stringValue(result['data']).replaceAll(RegExp(r'\s'), ''),
      );
      if (responseKey.length != 16 || encoded.length <= 16) {
        throw const FormatException();
      }
      final decoded = sofireAes(
        Uint8List.sublistView(encoded, 0, encoded.length - 16),
        responseKey,
        encrypt: false,
      );
      final token = stringValue(
        objectValue(jsonDecode(utf8.decode(decoded)))['token'],
      );
      if (token.isEmpty) throw const FormatException();
      return token;
    } on TiebaApiException {
      rethrow;
    } catch (_) {
      throw const TiebaApiException(
        'The device verification service returned an incompatible response.',
        code: 'device_verification',
      );
    }
  }

  Future<Response<T>> _request<T>(Future<Response<T>> Function() action) async {
    try {
      return await action();
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      throw TiebaApiException(
        status == null
            ? 'Could not connect. Check your network and try again.'
            : 'The server rejected the request (HTTP $status).',
        code: status?.toString() ?? 'network_error',
      );
    }
  }

  JsonMap _decodeJson(String? value, {TiebaSession? session}) {
    try {
      final json = normalizeJson(jsonDecode(value ?? ''));
      checkError(
        json,
        secrets: [
          ..._secrets(),
          if (session != null) ...[
            session.bduss,
            session.stoken,
            session.rawCookie,
            session.zid,
          ],
        ],
      );
      return json;
    } on TiebaApiException {
      rethrow;
    } catch (_) {
      throw const TiebaApiException(
        'The server returned a non-JSON response. A browser verification may be required.',
        code: 'invalid_response',
      );
    }
  }

  List<String> _secrets([TiebaSession? snapshot]) {
    final session = snapshot ?? sessionProvider();
    return [
      if (session != null) ...[
        session.bduss,
        session.stoken,
        session.rawCookie,
        session.zid,
      ],
    ];
  }

  static void checkError(JsonMap json, {List<String> secrets = const []}) {
    final error = objectValue(json['error']);
    final rawCode = stringValue(
      json['error_code'] ??
          json['no'] ??
          json['errno'] ??
          error['error_code'] ??
          error['errorno'] ??
          error['errno'] ??
          error['code'],
    );
    final code =
        rawCode.length < 40 && RegExp(r'^[a-zA-Z0-9_-]*$').hasMatch(rawCode)
        ? rawCode
        : 'server_error';
    if (code.isNotEmpty && code != '0') {
      var message = stringValue(
        json['error_msg'] ??
            json['errmsg'] ??
            error['error_msg'] ??
            error['user_msg'] ??
            error['errmsg'] ??
            error['usermsg'] ??
            (json['error'] is String ? json['error'] : null),
      );
      for (final secret in secrets.where((value) => value.isNotEmpty)) {
        message = message.replaceAll(secret, '[redacted]');
      }
      message = message.replaceAll(
        RegExp(
          r'(BDUSS|STOKEN|cookie)\s*[:=]\s*[^\s;,]+',
          caseSensitive: false,
        ),
        '[redacted]',
      );
      if (message.length > 300) {
        message = 'Tieba rejected this request (code $code).';
      }
      final rawUrl = stringValue(json['vcode_url'] ?? error['vcode_url']);
      final uri = Uri.tryParse(rawUrl);
      final safeUrl =
          uri != null &&
              uri.scheme == 'https' &&
              (uri.host == 'baidu.com' || uri.host.endsWith('.baidu.com'))
          ? uri
          : null;
      throw TiebaApiException(
        message.isEmpty ? 'Tieba rejected this request (code $code).' : message,
        code: code,
        requiresLogin: const {'4', '5', '110001', '110002'}.contains(code),
        verificationUrl: safeUrl,
      );
    }
  }

  void close() => dio.close();
}

Uint8List sofireAes(Uint8List data, Uint8List key, {required bool encrypt}) {
  final cipher = pc.PaddedBlockCipherImpl(
    pc.PKCS7Padding(),
    pc.CBCBlockCipher(pc.AESEngine()),
  );
  cipher.init(
    encrypt,
    pc.PaddedBlockCipherParameters<pc.ParametersWithIV<pc.KeyParameter>, Null>(
      pc.ParametersWithIV(pc.KeyParameter(key), Uint8List(16)),
      null,
    ),
  );
  return cipher.process(data);
}

Uint8List rc442(Uint8List source, Uint8List key) {
  if (key.isEmpty) throw ArgumentError.value(key, 'key', 'must not be empty');
  final state = List<int>.generate(256, (index) => index);
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j + state[i] + key[i % key.length]) & 255;
    final value = state[i];
    state[i] = state[j];
    state[j] = value;
  }
  var x = 0;
  var y = 0;
  final output = Uint8List(source.length);
  for (var i = 0; i < source.length; i++) {
    x = (x + 1) & 255;
    final a = state[x];
    y = (y + a) & 255;
    final b = state[y];
    state[x] = b;
    state[y] = a;
    output[i] = source[i] ^ state[(a + b) & 255] ^ 42;
  }
  return output;
}

JsonMap normalizeJson(dynamic value) {
  if (value is! Map) return <String, dynamic>{};
  dynamic normalize(dynamic item) {
    if (item is Map) return normalizeJson(item);
    if (item is List) return item.map(normalize).toList();
    return item;
  }

  final output = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key.toString();
    final normalized = normalize(entry.value);
    output[key] = normalized;
    output[key
            .replaceAllMapped(
              RegExp(r'([a-z0-9])([A-Z])'),
              (match) => '${match[1]}_${match[2]}',
            )
            .toLowerCase()] =
        normalized;
  }
  return output;
}
