import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../l10n/app_localizations.dart';
import 'glass.dart';

export 'glass.dart';

extension LocalizedContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
}

void notifyUser(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> requireAccount(BuildContext context) async {
  final app = AppScope.read(context);
  if (app.isLoggedIn) return true;
  await app.login(context);
  return app.isLoggedIn;
}

Future<bool> performAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
  bool requiresLogin = true,
}) async {
  if (requiresLogin && !await requireAccount(context)) return false;
  if (!context.mounted) return false;
  try {
    await action();
    if (context.mounted && success != null) notifyUser(context, success);
    return true;
  } catch (error) {
    if (context.mounted) {
      notifyUser(context, '${context.l10n.operationFailed}\n$error');
    }
    return false;
  }
}

Future<void> openExternal(BuildContext context, String value) async {
  final uri = Uri.tryParse(value);
  if (uri == null || !['https', 'http'].contains(uri.scheme)) return;
  try {
    final embedded = AppScope.read(context).settings.getBool('useWebView');
    if (!await launchUrl(
          uri,
          mode: embedded
              ? LaunchMode.inAppBrowserView
              : LaunchMode.externalApplication,
        ) &&
        context.mounted) {
      notifyUser(context, context.l10n.operationFailed);
    }
  } catch (error) {
    if (context.mounted) notifyUser(context, error.toString());
  }
}

Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) notifyUser(context, context.l10n.copied);
}

String compactCount(int count) => NumberFormat.compact().format(count);
String displayUserName(BuildContext context, UserProfile user) {
  final display = user.name.isEmpty ? context.l10n.unknownUser : user.name;
  if (AppScope.of(context).settings.getBool('showBothUsernameAndNickname') &&
      user.username.isNotEmpty &&
      user.username != user.name) {
    return '$display (@${user.username})';
  }
  return display;
}

String shortDate(BuildContext context, DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  final now = DateTime.now();
  return DateFormat(
    now.year == local.year ? 'MM-dd HH:mm' : 'yyyy-MM-dd',
    Localizations.localeOf(context).languageCode,
  ).format(local);
}

Future<String?> textPrompt(
  BuildContext context, {
  required String title,
  String? hint,
  String value = '',
  TextInputType keyboardType = TextInputType.text,
  int maxLines = 1,
}) async {
  final controller = TextEditingController(text: value);
  final result = await showGlassDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: maxLines == 1
            ? (value) => Navigator.pop(context, value.trim())
            : null,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(context.l10n.done),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message,
) async =>
    await showGlassDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.confirm),
          ),
        ],
      ),
    ) ??
    false;

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.url,
    this.name = '',
    this.radius = 21,
  });
  final String url, name;
  final double radius;
  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox.square(
      dimension: radius * 2,
      child: url.isEmpty
          ? _fallback(context)
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => _fallback(context),
              placeholder: (_, _) => _fallback(context),
            ),
    ),
  );
  Widget _fallback(BuildContext context) => ColoredBox(
    color: context.colors.primaryContainer,
    child: Center(
      child: name.isEmpty
          ? Icon(
              Icons.person_outline_rounded,
              color: context.colors.onPrimaryContainer,
            )
          : Text(
              name.characters.first,
              style: TextStyle(
                color: context.colors.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
    ),
  );
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });
  final String? title, message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 58),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerHighest.withValues(
              alpha: .55,
            ),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 34, color: context.colors.primary),
        ),
        const SizedBox(height: 22),
        Text(
          title ?? context.l10n.emptyTitle,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 9),
        Text(
          message ?? context.l10n.emptyBody,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.colors.onSurfaceVariant,
            height: 1.55,
          ),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => EmptyPanel(
    title: context.l10n.networkError,
    message: error.toString(),
    icon: Icons.cloud_off_rounded,
    action: FilledButton.tonalIcon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded),
      label: Text(context.l10n.retry),
    ),
  );
}

class LoginPanel extends StatelessWidget {
  const LoginPanel({super.key});
  @override
  Widget build(BuildContext context) => EmptyPanel(
    title: context.l10n.loginNeeded,
    message: context.l10n.loginBody,
    icon: Icons.person_outline_rounded,
    action: FilledButton.icon(
      onPressed: () => AppScope.read(context).login(context),
      icon: const Icon(Icons.login_rounded),
      label: Text(context.l10n.signIn),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 12, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: .4,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
  });
  final Widget child;
  final EdgeInsets margin;
  @override
  Widget build(BuildContext context) => Card(
    margin: margin,
    elevation: 0,
    color: context.colors.surfaceContainerLow,
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}
