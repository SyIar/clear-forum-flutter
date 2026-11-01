import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../platform/baidu_login_page.dart';
import 'local_store.dart';
import 'session_store.dart';
import 'settings_store.dart';
import 'tieba_api.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.sessions,
    required this.settings,
    required this.local,
    this.onAccountChanged,
  }) {
    api = TiebaApi(
      sessionProvider: () => session,
      deviceId: '${sessions.installId.toUpperCase()}|0',
    );
    sessions.addListener(_relay);
    settings.addListener(_relay);
    local.addListener(_relay);
  }

  final SessionStore sessions;
  final SettingsStore settings;
  final LocalStore local;
  final VoidCallback? onAccountChanged;
  late final TiebaApi api;
  Future<void> _accountQueue = Future<void>.value();
  bool _changingAccount = false;
  bool _loginInProgress = false;
  bool _disposed = false;

  TiebaSession? get session => sessions.currentAccount?.session;
  UserProfile? get profile => sessions.currentAccount?.profile;
  List<StoredAccount> get accounts => sessions.accounts;
  bool get isLoggedIn => session?.isAuthenticated == true;
  bool get changingAccount => _changingAccount;
  bool get defersIncomingLinks => _changingAccount || _loginInProgress;

  void _relay() {
    if (!_changingAccount && !_disposed) notifyListeners();
  }

  Future<void> login(BuildContext context) async {
    if (_loginInProgress || _disposed) return;
    final labels = AppLocalizations.of(context);
    final previous = sessions.currentAccount;
    _loginInProgress = true;
    var authenticated = false;
    try {
      authenticated =
          await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => BaiduLoginPage(
                title: labels.loginTitle,
                cancelLabel: labels.cancel,
                finishLabel: labels.done,
                privacyLabel: labels.loginPrivacy,
                errorLabel: labels.operationFailed,
                notReadyLabel: labels.accountCookiesMissing,
                unsupportedLabel: labels.nativeLoginOnly,
                retryLabel: labels.retry,
                onCookies: (cookies) async {
                  final validated = await api.login(
                    bduss: cookies.bduss,
                    stoken: cookies.stoken,
                    cookie: cookies.cookie,
                  );
                  await _changeAccount(
                    () => sessions.saveSession(validated),
                    resetNavigation: false,
                  );
                },
              ),
            ),
          ) ==
          true;
    } finally {
      if (!_disposed &&
          (authenticated || !identical(previous, sessions.currentAccount))) {
        onAccountChanged?.call();
      }
      _loginInProgress = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> switchAccount(String? userId) =>
      _changeAccount(() => sessions.activate(userId));
  Future<void> removeAccount(String userId) =>
      _changeAccount(() => sessions.remove(userId));

  Future<void> _changeAccount(
    Future<void> Function() mutation, {
    bool resetNavigation = true,
  }) {
    final result = _accountQueue.then((_) async {
      _changingAccount = true;
      if (!_disposed) notifyListeners();
      try {
        await mutation();
        try {
          await local.activateAccount(sessions.currentAccount?.id);
        } catch (error, stack) {
          // Do not expose a new session alongside an unreadable local namespace.
          await sessions.activate(null);
          try {
            await local.activateAccount(null);
          } catch (_) {
            /* The store remains empty and read-only. */
          }
          Error.throwWithStackTrace(error, stack);
        }
      } finally {
        if (resetNavigation && !_disposed) onAccountChanged?.call();
        _changingAccount = false;
        if (!_disposed) notifyListeners();
      }
    });
    _accountQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    sessions.removeListener(_relay);
    settings.removeListener(_relay);
    local.removeListener(_relay);
    api.close();
    sessions.dispose();
    settings.dispose();
    local.dispose();
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController? controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
