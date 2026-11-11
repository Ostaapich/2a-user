import 'package:dio/dio.dart';

class BrowserMediaExportRequest {
  const BrowserMediaExportRequest({
    required this.operationId,
    required this.url,
    required this.name,
    required this.apiBase,
    required this.identity,
    required this.getIdentity,
    this.token,
    this.share = false,
    this.onProgress,
  });
  final String operationId, url, name, apiBase, identity;
  final String? token;
  final bool share;
  final Future<String> Function() getIdentity;
  final ProgressCallback? onProgress;
}

enum BrowserMediaExportKind { downloaded, shareReady, shared, cancelled }

class BrowserMediaExportResult {
  const BrowserMediaExportResult(this.kind, {this.preparedId});
  final BrowserMediaExportKind kind;
  final String? preparedId;
}

class BrowserMediaExportException implements Exception {
  const BrowserMediaExportException(this.code);
  final String code;
  @override
  String toString() => 'BrowserMediaExportException: $code';
}
