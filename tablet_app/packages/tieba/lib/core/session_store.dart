import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

class StoredAccount {
  const StoredAccount({required this.profile, required this.session});

  final UserProfile profile;
  final TiebaSession session;
  String get id => profile.id.isNotEmpty ? profile.id : session.userId;
}

/// Account credentials are serialized exclusively into platform secure storage.
class SessionStore extends ChangeNotifier {
  SessionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked),
          );

  static const _storageKey = 'tieba_lite.accounts.v1';
  final FlutterSecureStorage _storage;
  List<StoredAccount> _accounts = [];
  String? _activeId;
  String _installId = '';
  bool _initialized = false;
  Future<void> _pending = Future<void>.value();

  List<StoredAccount> get accounts => List.unmodifiable(_accounts);
  String get installId => _installId;
  StoredAccount? get currentAccount {
    for (final account in _accounts) {
      if (account.id == _activeId) return account;
    }
    return null;
  }

  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) {
      _installId = _newInstallId();
      _initialized = true;
      notifyListeners();
      return;
    }
    final raw = await _storage.read(key: _storageKey);
    if (raw != null) {
      final document = jsonDecode(raw);
      if (document is! Map || document['version'] != 1) {
        throw const FormatException('Unsupported secure account data');
      }
      final data = objectValue(document);
      if (data['accounts'] is! List ||
          data['installId'] is! String ||
          (data['activeId'] != null && data['activeId'] is! String)) {
        throw const FormatException('Invalid secure account metadata');
      }
      final loadedAccounts = listValue(data['accounts']).map((value) {
        if (value is! Map ||
            value['profile'] is! Map ||
            value['session'] is! Map) {
          throw const FormatException('Invalid saved account');
        }
        final item = objectValue(value);
        final account = StoredAccount(
          profile: UserProfile.fromJson(objectValue(item['profile'])),
          session: TiebaSession.fromJson(objectValue(item['session'])),
        );
        if (!_isValidAccount(account)) {
          throw const FormatException('Invalid saved account identity');
        }
        return account;
      }).toList();
      final activeId = data['activeId'] as String?;
      if (loadedAccounts.map((account) => account.id).toSet().length !=
              loadedAccounts.length ||
          (activeId != null &&
              !loadedAccounts.any((account) => account.id == activeId))) {
        throw const FormatException('Inconsistent saved account selection');
      }
      _accounts = loadedAccounts;
      _activeId = activeId;
      _installId = stringValue(data['installId']);
    }
    if (_installId.isEmpty) {
      _installId = _newInstallId();
      await _write(_accounts, _activeId);
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> save(
    StoredAccount account, {
    bool activate = true,
  }) => _enqueue(() async {
    if (kIsWeb) {
      throw UnsupportedError('Web preview does not store account credentials');
    }
    if (!_isValidAccount(account)) {
      throw ArgumentError('A validated account is required');
    }
    final next = [..._accounts.where((item) => item.id != account.id), account];
    final active = activate ? account.id : _activeId;
    await _write(next, active);
    _accounts = next;
    _activeId = active;
    notifyListeners();
  });

  Future<void> saveSession(TiebaSession session, {bool activate = true}) =>
      save(
        StoredAccount(profile: session.user, session: session),
        activate: activate,
      );

  /// Passing null enters guest mode without removing saved accounts.
  Future<void> activate(String? id) => _enqueue(() async {
    if (id != null && !_accounts.any((account) => account.id == id)) {
      throw ArgumentError('Unknown account');
    }
    await _write(_accounts, id);
    _activeId = id;
    notifyListeners();
  });

  Future<void> remove(String id) => _enqueue(() async {
    final next = _accounts.where((account) => account.id != id).toList();
    final active = _activeId == id ? null : _activeId;
    await _write(next, active);
    _accounts = next;
    _activeId = active;
    notifyListeners();
  });

  Future<void> clear() => _enqueue(() async {
    await _write([], null);
    _accounts = [];
    _activeId = null;
    notifyListeners();
  });

  Future<void> _write(List<StoredAccount> accounts, String? activeId) {
    if (kIsWeb) {
      if (accounts.isNotEmpty) {
        throw UnsupportedError(
          'Web preview does not store account credentials',
        );
      }
      return Future<void>.value();
    }
    return _storage.write(
      key: _storageKey,
      value: jsonEncode({
        'version': 1,
        'installId': _installId,
        'activeId': activeId,
        'accounts': accounts
            .map(
              (account) => {
                'profile': account.profile.toJson(),
                'session': account.session.toJson(),
              },
            )
            .toList(),
      }),
    );
  }

  static String _newInstallId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool _isValidAccount(StoredAccount account) =>
      account.id.isNotEmpty &&
      account.session.isAuthenticated &&
      (account.profile.id.isEmpty ||
          account.session.userId.isEmpty ||
          account.profile.id == account.session.userId);

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _pending.then((_) async {
      if (!_initialized) throw StateError('SessionStore is not initialized');
      await action();
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
