import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/glass_accessibility.dart';
import 'native_glass.dart';
export 'native_glass.dart';

/// A bounded glass layer for controls; long reading surfaces stay unfiltered.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 28,
    this.tint,
    this.blur = true,
    this.elevated = true,
    this.pressed = false,
  });
  final Widget child;
  final double radius;
  final Color? tint;
  final bool blur, elevated, pressed;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return Material(
        color: tint ?? Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accessibility = GlassAccessibilityScope.of(context);
    final opaque =
        MediaQuery.highContrastOf(context) ||
        accessibility?.reduceTransparency == true;
    final still =
        MediaQuery.disableAnimationsOf(context) ||
        accessibility?.reduceMotion == true;
    final base =
        tint ?? (dark ? const Color(0xFF242424) : const Color(0xFFF9F9F9));
    final border = BorderRadius.circular(radius);
    final nested =
        context.dependOnInheritedWidgetOfExactType<_GlassLayer>() != null;
    final layer = AnimatedContainer(
      duration: still ? Duration.zero : const Duration(milliseconds: 140),
      decoration: BoxDecoration(
        borderRadius: border,
        color: opaque ? base.withValues(alpha: 1) : null,
        gradient: opaque
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    Colors.white.withValues(alpha: dark ? .08 : .3),
                    base,
                  ).withValues(alpha: pressed ? .96 : .88),
                  base.withValues(alpha: pressed ? .96 : .76),
                ],
              ),
        border: Border.all(
          color: opaque
              ? theme.colorScheme.outline
              : (dark ? Colors.white : Colors.black).withValues(
                  alpha: dark ? .14 : .09,
                ),
          width: .7,
        ),
      ),
      child: _GlassLayer(child: child),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: border,
        boxShadow: elevated && !opaque
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? .16 : .035),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: border,
        child: blur && !opaque && !nested
            ? BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: layer,
              )
            : layer,
      ),
    );
  }
}

class _GlassLayer extends InheritedWidget {
  const _GlassLayer({required super.child});
  @override
  bool updateShouldNotify(_GlassLayer oldWidget) => false;
}

Widget glassButtonBackground(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) {
  if (context.dependOnInheritedWidgetOfExactType<_GlassLayer>() != null) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: states.contains(WidgetState.pressed)
            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: .08)
            : Colors.transparent,
      ),
      child: child,
    );
  }
  return GlassSurface(
    pressed: states.contains(WidgetState.pressed),
    elevated: !states.contains(WidgetState.disabled),
    child: child ?? const SizedBox.shrink(),
  );
}

/// Floating controls reserve their height, including the iPhone home indicator.
class GlassBottomBar extends StatelessWidget {
  const GlassBottomBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(6),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(12, 6, 12, 8),
    child: GlassSurface(
      radius: 30,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.titleSpacing,
    this.backgroundColor,
    this.foregroundColor,
    this.automaticallyImplyLeading = true,
  });
  final Widget? title, leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final double? titleSpacing;
  final Color? backgroundColor, foregroundColor;
  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize =>
      Size.fromHeight(60 + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final darkMedia = backgroundColor == Colors.black;
    final theme = Theme.of(context);
    final barTheme = darkMedia
        ? theme.copyWith(
            brightness: Brightness.dark,
            colorScheme: const ColorScheme.dark(),
            iconButtonTheme: IconButtonThemeData(
              style: theme.iconButtonTheme.style?.copyWith(
                foregroundColor: const WidgetStatePropertyAll(Colors.white),
              ),
            ),
          )
        : theme;
    return Theme(
      data: barTheme,
      child: AppBar(
        title: title,
        toolbarHeight: 60,
        titleSpacing: titleSpacing ?? 14,
        leadingWidth: 60,
        automaticallyImplyLeading: automaticallyImplyLeading,
        leading: leading == null
            ? (usesNativeGlass &&
                      automaticallyImplyLeading &&
                      Navigator.canPop(context)
                  ? Center(
                      child: nativeGlassButton(
                        context,
                        IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .backButtonTooltip,
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.maybePop(context),
                        ),
                      ),
                    )
                  : null)
            : Center(child: nativeGlassButton(context, leading!)),
        actions: actions == null
            ? null
            : [
                for (final action in actions!)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Center(child: nativeGlassButton(context, action)),
                  ),
                const SizedBox(width: 9),
              ],
        bottom: bottom,
        backgroundColor:
            backgroundColor ??
            (usesNativeGlass
                ? Colors.transparent
                : theme.appBarTheme.backgroundColor),
        foregroundColor: foregroundColor,
        systemOverlayStyle: darkMedia ? SystemUiOverlayStyle.light : null,
      ),
    );
  }
}

class GlassFloatingButton extends StatelessWidget {
  const GlassFloatingButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.tooltip,
    this.small = false,
  });
  const GlassFloatingButton.small({
    super.key,
    required this.onPressed,
    required this.child,
    this.tooltip,
  }) : small = true;
  final VoidCallback? onPressed;
  final Widget child;
  final String? tooltip;
  final bool small;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: small ? 48 : 56,
    child: nativeGlassButton(
      context,
      IconButton(onPressed: onPressed, tooltip: tooltip, icon: child),
    ),
  );
}

/// Convert navigation actions, not repeated content-row controls.
Widget nativeGlassButton(BuildContext context, Widget source) {
  if (!usesNativeGlass) return source;
  NativeGlassAction? action;
  if (source is IconButton && source.icon is Icon) {
    final symbol = _symbol((source.icon as Icon).icon);
    if (symbol == null) return source;
    action = NativeGlassAction(
      id: 'press',
      label: source.tooltip ?? symbol,
      symbol: symbol,
      selected: source.isSelected ?? false,
      onPressed: source.onPressed,
    );
  } else if (source is PopupMenuButton<String>) {
    final entries = source.itemBuilder(context);
    if (!source.enabled ||
        source.onOpened != null ||
        source.onCanceled != null ||
        entries.any(
          (entry) =>
              entry is! PopupMenuItem<String> ||
              entry.child is! Text ||
              entry.value == null,
        )) {
      return source;
    }
    action = NativeGlassAction(
      id: 'menu',
      label:
          source.tooltip ?? MaterialLocalizations.of(context).showMenuTooltip,
      symbol: 'ellipsis',
      menu: [
        for (final entry in entries.cast<PopupMenuItem<String>>())
          NativeGlassAction(
            id: entry.value!,
            label: (entry.child as Text).data ?? '',
            symbol: '',
            destructive: entry.value == 'delete',
            selected: entry is CheckedPopupMenuItem<String> && entry.checked,
            onPressed: !source.enabled || !entry.enabled
                ? null
                : () {
                    entry.onTap?.call();
                    source.onSelected?.call(entry.value!);
                  },
          ),
      ],
    );
  }
  if (action == null) return source;
  return SizedBox(
    width: 46,
    height: 46,
    child: NativeGlassControl(
      kind: 'button',
      actions: [action],
      height: 46,
      fallback: source,
    ),
  );
}

String? _symbol(IconData? icon) {
  const symbols = <String, List<IconData>>{
    'chevron.backward': [
      Icons.arrow_back,
      Icons.arrow_back_ios,
      Icons.chevron_left,
    ],
    'magnifyingglass': [Icons.search, Icons.search_rounded],
    'plus': [Icons.add, Icons.add_rounded],
    'link': [Icons.link, Icons.link_rounded],
    'arrow.clockwise': [Icons.refresh, Icons.refresh_rounded],
    'xmark': [Icons.close, Icons.close_rounded],
    'checkmark': [
      Icons.check,
      Icons.check_rounded,
      Icons.done,
      Icons.done_rounded,
    ],
    'square.and.arrow.up': [Icons.share, Icons.share_rounded, Icons.ios_share],
    'square.and.pencil': [Icons.edit, Icons.edit_rounded, Icons.edit_outlined],
    'person.crop.circle': [Icons.manage_accounts_outlined],
    'bubble.left.and.bubble.right': [Icons.forum_outlined],
    'arrow.up': [Icons.arrow_upward, Icons.arrow_upward_rounded],
    'bookmark': [Icons.bookmark_border_rounded, Icons.bookmark_border],
    'bookmark.fill': [Icons.bookmark_rounded, Icons.bookmark],
    'gearshape': [
      Icons.settings,
      Icons.settings_rounded,
      Icons.settings_outlined,
    ],
  };
  for (final entry in symbols.entries) {
    if (entry.value.contains(icon)) return entry.key;
  }
  return null;
}

class GlassActionBar extends StatelessWidget {
  const GlassActionBar({super.key, required this.actions});
  final List<NativeGlassAction> actions;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(12, 6, 12, 8),
    child: NativeGlassControl(
      kind: 'toolbar',
      actions: actions,
      height: ui.lerpDouble(
        56,
        88,
        ((MediaQuery.textScalerOf(context).scale(16) / 16 - 1) / 2).clamp(0, 1),
      )!,
      fallback: GlassSurface(
        child: Row(
          children: [
            for (final action in actions)
              if (action.showLabel)
                Expanded(
                  child: TextButton.icon(
                    onPressed: action.onPressed,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(action.label),
                  ),
                )
              else
                IconButton(
                  tooltip: action.label,
                  onPressed: action.onPressed,
                  icon: Icon(
                    action.symbol.startsWith('hand.thumbsup')
                        ? (action.selected
                              ? Icons.thumb_up_rounded
                              : Icons.thumb_up_outlined)
                        : (action.selected
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded),
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}

Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showDialog<T>(
  context: context,
  builder: (context) {
    final opaque =
        MediaQuery.highContrastOf(context) ||
        GlassAccessibilityScope.of(context)?.reduceTransparency == true;
    final child = builder(context);
    return opaque
        ? child
        : BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: child,
          );
  },
);

Future<T?> showGlassBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  backgroundColor: Colors.transparent,
  elevation: 0,
  builder: (context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
    child: GlassSurface(radius: 28, child: builder(context)),
  ),
);
