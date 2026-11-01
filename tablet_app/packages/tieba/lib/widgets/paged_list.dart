import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import 'common.dart';

class PagedList<T> extends StatefulWidget {
  const PagedList({
    super.key,
    required this.load,
    required this.itemBuilder,
    this.headerBuilder,
    this.emptyMessage,
    this.initialPage = 1,
    this.onLoaded,
    this.padding = const EdgeInsets.only(bottom: 32),
    this.filter,
    this.itemKey,
    this.onVisibleItemChanged,
  });
  final Future<PageResult<T>> Function(int page) load;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget Function(BuildContext context, PageResult<T>? result)?
  headerBuilder;
  final String? emptyMessage;
  final int initialPage;
  final ValueChanged<PageResult<T>>? onLoaded;
  final EdgeInsets padding;
  final bool Function(T item)? filter;
  final Object Function(T item)? itemKey;
  final ValueChanged<T>? onVisibleItemChanged;
  @override
  State<PagedList<T>> createState() => PagedListState<T>();
}

class PagedListState<T> extends State<PagedList<T>> {
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _itemKeys = <Object, GlobalKey>{};
  final _renderedItems = <Object, T>{};
  Timer? _visibilityTimer;
  Object? _lastVisible;
  List<T> _items = [];
  PageResult<T>? _result;
  Object? _error;
  bool _loading = true, _loadingMore = false, _retryReload = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    reload();
  }

  @override
  void dispose() {
    _generation++;
    _visibilityTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    _queueVisibility();
    if (_scroll.position.extentAfter < 600 &&
        !_loading &&
        !_loadingMore &&
        _error == null &&
        (_result?.hasMore ?? false)) {
      loadMore();
    }
  }

  void _queueVisibility() {
    if (!mounted || widget.onVisibleItemChanged == null) return;
    _visibilityTimer?.cancel();
    _visibilityTimer = Timer(const Duration(milliseconds: 160), _reportVisible);
  }

  void _reportVisible() {
    if (!mounted || _loading) return;
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached) return;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewport.size.height;
    Object? visible;
    double firstTop = double.infinity;
    for (final entry in _itemKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox ||
          !box.attached ||
          !box.hasSize ||
          box.size.height <= 0) {
        continue;
      }
      final top = box.localToGlobal(Offset.zero).dy;
      if (top + box.size.height > viewportTop + 8 &&
          top < viewportBottom &&
          top < firstTop) {
        firstTop = top;
        visible = entry.key;
      }
    }
    if (visible != null &&
        visible != _lastVisible &&
        _renderedItems.containsKey(visible)) {
      _lastVisible = visible;
      widget.onVisibleItemChanged?.call(_renderedItems[visible] as T);
    }
  }

  Future<void> scrollToTop() async {
    if (!_scroll.hasClients) return;
    await _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> reload() async {
    final generation = ++_generation;
    _lastVisible = null;
    setState(() {
      _loading = true;
      _retryReload = true;
      _loadingMore = false;
      _error = null;
    });
    try {
      final result = await widget.load(widget.initialPage);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = result.items;
        _result = result;
        _loading = false;
      });
      widget.onLoaded?.call(result);
      WidgetsBinding.instance.addPostFrameCallback((_) => _queueVisibility());
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || _loading || !(_result?.hasMore ?? false)) return;
    final generation = _generation;
    setState(() {
      _loadingMore = true;
      _retryReload = false;
      _error = null;
    });
    try {
      final result = await widget.load(_result!.page + 1);
      if (!mounted || generation != _generation) return;
      setState(() {
        final identity = widget.itemKey;
        _items = identity == null
            ? [..._items, ...result.items]
            : {
                for (final item in [..._items, ...result.items])
                  identity(item): item,
              }.values.toList();
        _result = result;
        _loadingMore = false;
      });
      widget.onLoaded?.call(result);
      WidgetsBinding.instance.addPostFrameCallback((_) => _queueVisibility());
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.filter == null
        ? _items
        : _items.where(widget.filter!).toList();
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView.builder(
        key: _viewport,
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding:
            widget.padding +
            EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top,
              bottom: MediaQuery.paddingOf(context).bottom,
            ),
        itemCount: visible.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return widget.headerBuilder?.call(context, _result) ??
                const SizedBox.shrink();
          }
          if (index <= visible.length) {
            final item = visible[index - 1];
            final alternate =
                index.isEven &&
                AppScope.of(context).settings
                    .getBool('listItemsBackgroundIntermixed', fallback: true);
            final theme = Theme.of(context);
            Widget child = !alternate
                ? widget.itemBuilder(context, item, index - 1)
                : Theme(
                    data: theme.copyWith(
                      colorScheme: theme.colorScheme.copyWith(
                        surfaceContainerLow: theme.colorScheme.surfaceContainer,
                      ),
                    ),
                    child: Builder(
                      builder: (context) =>
                          widget.itemBuilder(context, item, index - 1),
                    ),
                  );
            if (widget.onVisibleItemChanged != null) {
              final identity = widget.itemKey?.call(item) ?? index;
              _renderedItems[identity] = item;
              child = KeyedSubtree(
                key: _itemKeys.putIfAbsent(identity, GlobalKey.new),
                child: child,
              );
            }
            return child;
          }
          if (_loading) {
            return const Padding(
              padding: EdgeInsets.all(60),
              child: Center(child: CircularProgressIndicator.adaptive()),
            );
          }
          if (_error != null) {
            return ErrorPanel(
              error: _error!,
              onRetry: _retryReload ? reload : loadMore,
            );
          }
          if (visible.isEmpty && !(_result?.hasMore ?? false)) {
            return EmptyPanel(message: widget.emptyMessage);
          }
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator.adaptive()),
            );
          }
          if (_result?.hasMore ?? false) {
            return Padding(
              padding: const EdgeInsets.all(18),
              child: Center(
                child: TextButton.icon(
                  onPressed: loadMore,
                  icon: const Icon(Icons.expand_more),
                  label: Text(context.l10n.loadMore),
                ),
              ),
            );
          }
          return const SizedBox(height: 24);
        },
      ),
    );
  }
}
