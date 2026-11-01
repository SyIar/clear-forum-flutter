import 'package:flutter/material.dart';

/// Uses window width, including split-screen windows, rather than orientation.
class TabletLayout {
  static bool split(double width) => width >= 600;
  static bool rail(double width) => width >= 840;
  static double masterWidth(double width) => (width * .34).clamp(208, 340);
}

class ReaderSplit extends StatelessWidget {
  const ReaderSplit({super.key, required this.master, required this.detail});
  final Widget master, detail;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      if (!TabletLayout.split(size.maxWidth)) return master;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: TabletLayout.masterWidth(size.maxWidth),
            child: master,
          ),
          const VerticalDivider(width: 1),
          Expanded(child: detail),
        ],
      );
    },
  );
}

Future<T?> tabletSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: child,
      ),
    );
