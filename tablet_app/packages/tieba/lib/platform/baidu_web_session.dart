import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Serializes access to the shared native WebKit cookie store.
class BaiduWebSessionCoordinator {
  BaiduWebSessionCoordinator({required this.clearStore});

  static final instance = BaiduWebSessionCoordinator(
    clearStore: () async {
      await CookieManager.instance().deleteAllCookies();
      final storage = WebStorageManager.instance();
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
          // deleteAllData is Android-only in the plugin's platform contract.
          await storage.removeDataModifiedSince(
            dataTypes: WebsiteDataType.values,
            date: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          );
        case TargetPlatform.android:
          await storage.deleteAllData();
        default:
          throw UnsupportedError('Baidu web sessions require a native WebView');
      }
    },
  );

  final Future<void> Function() clearStore;
  Future<void> _pending = Future<void>.value();
  BaiduWebSessionLease? _owner;

  Future<BaiduWebSessionLease> acquire({Future<void> Function()? configure}) {
    if (_owner != null) {
      return Future.error(StateError('A Baidu web session is already active'));
    }
    final lease = BaiduWebSessionLease._(this);
    _owner = lease;
    return _enqueue(() async {
      try {
        await clearStore();
        await configure?.call();
        return lease;
      } catch (_) {
        lease._closed = true;
        if (identical(_owner, lease)) _owner = null;
        try {
          await clearStore();
        } catch (_) {
          // The next acquisition must clear successfully before it can load.
        }
        rethrow;
      }
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _release(BaiduWebSessionLease lease) {
    if (lease._closed || !identical(_owner, lease)) return Future.value();
    lease._closed = true;
    _owner = null;
    return _enqueue(clearStore);
  }
}

class BaiduWebSessionLease {
  BaiduWebSessionLease._(this._coordinator);
  final BaiduWebSessionCoordinator _coordinator;
  bool _closed = false;
  bool get active => !_closed;
  Future<void> close() => _coordinator._release(this);
}
