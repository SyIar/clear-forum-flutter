import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'diagnostics.dart';
import 'session.dart';
import 'strings.dart';

class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({super.key, required this.session});
  final ForumSession session;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('Diagnostics')),
      automaticallyImplyLeading: false,
    ),
    body: ValueListenableBuilder<List<PageDiagnostic>>(
      valueListenable: session.diagnostics,
      builder: (context, entries, _) => ListView(
        children: [
          ListTile(subtitle: Text(tr('Diagnostics hint'))),
          for (final entry in entries)
            ExpansionTile(
              title: Text('${entry.url}', maxLines: 2),
              subtitle: Text('${entry.captured.toLocal()} · ${entry.state}'),
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.copy),
                  label: Text(tr('Copy diagnostics')),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: entry.text)),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    entry.source.length > 12000
                        ? '${entry.source.substring(0, 12000)}\n...'
                        : entry.source,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}
