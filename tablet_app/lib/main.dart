import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tieba_lite/app.dart';
import 'package:tieba_lite/tablet_bridge.dart';

import 'download_ui.dart';
import 'downloads.dart';
import 'forum_app.dart';
import 'library.dart';
import 'site.dart';
import 'strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStrings.load();
  await DownloadManager.instance.init();
  final site = ForumSite.current;
  TabletBridge.downloads = (_) => const DownloadsPage();
  TabletBridge.downloadsLabel = tr('Downloads');
  TabletBridge.download = (url) =>
      DownloadManager.instance.resolve(Uri.parse(url));
  runApp(
    site.module == Module.tieba
        ? const TiebaLiteApp()
        : ForumTabletApp(
            site: site,
            library: LibraryStore(
              await SharedPreferences.getInstance(),
              site: site,
            ),
          ),
  );
}
