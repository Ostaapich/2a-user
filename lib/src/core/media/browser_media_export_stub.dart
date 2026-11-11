import 'browser_media_export_types.dart';

Future<BrowserMediaExportResult> beginBrowserMediaExport(
  BrowserMediaExportRequest request,
) => throw UnsupportedError('Browser export only');
Future<BrowserMediaExportResult> sharePreparedBrowserMedia(String id) =>
    throw UnsupportedError('Browser export only');
void clearPreparedBrowserMedia(String id) {}
void cancelActiveBrowserMediaExports() {}

void cancelBrowserMediaExport(String id) {}
