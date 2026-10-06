import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../shared/models/pending_upload.dart';

String lookupDropMimeType(String fileName) {
  final ext = p.extension(fileName).toLowerCase();
  switch (ext) {
    case '.pdf':
      return 'application/pdf';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.png':
      return 'image/png';
    case '.webp':
      return 'image/webp';
    case '.xlsx':
    case '.xls':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case '.docx':
    case '.doc':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case '.pptx':
    case '.ppt':
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    case '.zip':
      return 'application/zip';
    case '.txt':
      return 'text/plain; charset=utf-8';
    default:
      return 'application/octet-stream';
  }
}

class SharedDropFile {
  const SharedDropFile({
    required this.id,
    required this.name,
    required this.filePath,
    required this.fileSize,
    required this.sharedAt,
    this.mimeType = 'application/octet-stream',
    this.isFromAppLibrary = false,
  });

  final String id;
  final String name;
  final String filePath;
  final int fileSize;
  final DateTime sharedAt;
  final String mimeType;
  final bool isFromAppLibrary;

  String get formattedSize => formatBytes(fileSize);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'size': fileSize,
    'formattedSize': formattedSize,
    'time': '${sharedAt.hour.toString().padLeft(2, '0')}:${sharedAt.minute.toString().padLeft(2, '0')}',
    'mimeType': mimeType,
    'isFromAppLibrary': isFromAppLibrary,
  };

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class WebDropClientEvent {
  const WebDropClientEvent({
    required this.type,
    required this.message,
    required this.timestamp,
  });

  final String type; // 'connect', 'download', 'upload', 'error'
  final String message;
  final DateTime timestamp;
}

enum DropTransferDirection {
  sendingToPc('إرسال إلى الكمبيوتر', 'Sending to PC'),
  receivingFromPc('استقبال من الكمبيوتر', 'Receiving from PC');

  const DropTransferDirection(this.arabicLabel, this.englishLabel);
  final String arabicLabel;
  final String englishLabel;
}

class DropTransferProgress {
  const DropTransferProgress({
    required this.id,
    required this.fileName,
    required this.direction,
    required this.transferredBytes,
    required this.totalBytes,
    required this.isCompleted,
    this.errorMessage,
  });

  final String id;
  final String fileName;
  final DropTransferDirection direction;
  final int transferredBytes;
  final int totalBytes;
  final bool isCompleted;
  final String? errorMessage;

  double get fraction {
    if (totalBytes <= 0) return 0.0;
    return (transferredBytes / totalBytes).clamp(0.0, 1.0);
  }

  int get percent => (fraction * 100).round();

  String get formattedTransferred => SharedDropFile.formatBytes(transferredBytes);
  String get formattedTotal =>
      totalBytes > 0 ? SharedDropFile.formatBytes(totalBytes) : '...';
  String get progressDetail =>
      '$formattedTransferred من $formattedTotal ($percent%)';
}

class LocalWebDropService {
  LocalWebDropService._();
  static final LocalWebDropService instance = LocalWebDropService._();

  HttpServer? _server;
  int _port = 8080;
  String? _localIp;
  bool _isRunning = false;

  final StreamController<List<WebDropClientEvent>> _eventsController =
      StreamController<List<WebDropClientEvent>>.broadcast();
  final List<WebDropClientEvent> _events = [];

  final List<SharedDropFile> _stagedFiles = [];
  final StreamController<List<SharedDropFile>> _stagedFilesController =
      StreamController<List<SharedDropFile>>.broadcast();

  DropTransferProgress? _activeTransfer;
  final StreamController<DropTransferProgress?> _transferProgressController =
      StreamController<DropTransferProgress?>.broadcast();

  bool get isRunning => _isRunning;
  int get port => _port;
  String? get localIp => _localIp;
  String get serverUrl => 'http://$_localIp:$_port';
  Stream<List<WebDropClientEvent>> get eventsStream => _eventsController.stream;
  List<WebDropClientEvent> get events => List.unmodifiable(_events);

  List<SharedDropFile> get stagedFiles => List.unmodifiable(_stagedFiles);
  Stream<List<SharedDropFile>> get stagedFilesStream => _stagedFilesController.stream;

  DropTransferProgress? get activeTransfer => _activeTransfer;
  Stream<DropTransferProgress?> get transferProgressStream =>
      _transferProgressController.stream;

  void _updateProgress(DropTransferProgress? progress) {
    _activeTransfer = progress;
    _transferProgressController.add(progress);
  }

  void _scheduleClearProgress(String transferId) {
    Timer(const Duration(seconds: 4), () {
      if (_activeTransfer?.id == transferId) {
        _updateProgress(null);
      }
    });
  }

  void addStagedFile(SharedDropFile file) {
    _stagedFiles.removeWhere((f) => f.filePath == file.filePath);
    _stagedFiles.insert(0, file);
    _stagedFilesController.add(List.unmodifiable(_stagedFiles));
    _logEvent('upload', 'تم تجهيز ملف من هاتفك للمشاركة: "${file.name}"');
  }

  void removeStagedFile(String id) {
    _stagedFiles.removeWhere((f) => f.id == id);
    _stagedFilesController.add(List.unmodifiable(_stagedFiles));
  }

  void clearStagedFiles() {
    _stagedFiles.clear();
    _stagedFilesController.add(List.unmodifiable(_stagedFiles));
  }

  void _logEvent(String type, String message) {
    final event = WebDropClientEvent(
      type: type,
      message: message,
      timestamp: DateTime.now(),
    );
    _events.insert(0, event);
    if (_events.length > 50) _events.removeLast();
    _eventsController.add(List.unmodifiable(_events));
  }

  /// Discovers the local Wi-Fi / Hotspot IPv4 address of the device
  Future<String?> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      // Prefer Wi-Fi / wlan / ap interfaces
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('wlan') ||
            name.contains('wi-fi') ||
            name.contains('wifi') ||
            name.contains('ap') ||
            name.contains('en') ||
            name.contains('eth')) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
              return addr.address;
            }
          }
        }
      }

      // Fallback: any non-loopback IPv4
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('[LocalWebDrop] Error finding IP: $e');
    }
    return null;
  }

  /// Starts the embedded HTTP Server
  Future<bool> startServer({
    required List<PendingUpload> Function() getDocuments,
    required Future<void> Function(String fileName, List<int> bytes) onFileUploaded,
    int initialPort = 8080,
  }) async {
    if (_isRunning) return true;

    _localIp = await getLocalIpAddress();
    _localIp ??= '127.0.0.1';

    _port = initialPort;
    for (int retry = 0; retry < 5; retry++) {
      try {
        _server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          _port,
          shared: true,
        );
        _isRunning = true;
        _listenRequests(getDocuments, onFileUploaded);
        _logEvent('connect', 'تم تشغيل سيرفر النقل بنجاح على $serverUrl');
        return true;
      } catch (e) {
        _port++;
      }
    }
    return false;
  }

  /// Stops the server
  Future<void> stopServer() async {
    if (!_isRunning) return;
    try {
      await _server?.close(force: true);
      _server = null;
      _isRunning = false;
      _logEvent('connect', 'تم إيقاف سيرفر النقل اللاسلكي.');
    } catch (e) {
      debugPrint('[LocalWebDrop] Stop error: $e');
    }
  }

  void _listenRequests(
    List<PendingUpload> Function() getDocuments,
    Future<void> Function(String fileName, List<int> bytes) onFileUploaded,
  ) {
    _server?.listen((HttpRequest request) async {
      try {
        final path = request.uri.path;
        final response = request.response;

        // CORS headers
        response.headers.add('Access-Control-Allow-Origin', '*');
        response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        response.headers.add('Access-Control-Allow-Headers', '*');

        if (request.method == 'OPTIONS') {
          response.statusCode = HttpStatus.ok;
          await response.close();
          return;
        }

        if (path == '/' || path == '/index.html') {
          // Serve modern Apple-styled Web Dashboard
          response.headers.contentType = ContentType.html;
          final html = _generateDashboardHtml(getDocuments());
          response.write(html);
          await response.close();
        } else if (path == '/api/documents') {
          // JSON list
          response.headers.contentType = ContentType.json;
          final docs = getDocuments().map((d) => {
            'id': d.id,
            'title': d.fileName,
            'pageCount': d.pageCount,
            'fileSize': d.fileSize,
            'createdAt': d.createdAt.toIso8601String(),
          }).toList();
          response.write(jsonEncode(docs));
          await response.close();
        } else if (path.startsWith('/download/')) {
          final docId = path.substring('/download/'.length);
          final doc = getDocuments().cast<PendingUpload?>().firstWhere(
            (d) => d?.id == docId,
            orElse: () => null,
          );

          if (doc != null && File(doc.filePath).existsSync()) {
            final file = File(doc.filePath);
            final length = await file.length();
            final fileName = Uri.encodeComponent(doc.fileName);

            response.headers.contentType = ContentType('application', 'pdf');
            response.headers.add(
              'Content-Disposition',
              'attachment; filename*=UTF-8\'\'$fileName',
            );
            response.headers.contentLength = length;

            _logEvent('download', 'تم تحميل المستند: "${doc.fileName}" على الكمبيوتر');
            await _streamFileWithProgress(
              file: file,
              fileName: doc.fileName,
              response: response,
              length: length,
              direction: DropTransferDirection.sendingToPc,
            );
          } else {
            response.statusCode = HttpStatus.notFound;
            response.write('Document not found');
            await response.close();
          }
        } else if (path.startsWith('/thumb/')) {
          final docId = path.substring('/thumb/'.length);
          final doc = getDocuments().cast<PendingUpload?>().firstWhere(
            (d) => d?.id == docId,
            orElse: () => null,
          );

          final thumbPath = doc?.thumbnailPath ?? (doc?.pages.isNotEmpty == true ? doc!.pages.first.imagePath : null);
          if (thumbPath != null && File(thumbPath).existsSync()) {
            final file = File(thumbPath);
            response.headers.contentType = ContentType('image', 'jpeg');
            response.headers.contentLength = await file.length();
            await file.openRead().pipe(response);
          } else {
            response.statusCode = HttpStatus.notFound;
            await response.close();
          }
        } else if (path == '/api/staged') {
          response.headers.contentType = ContentType.json;
          final list = _stagedFiles.map((f) => f.toJson()).toList();
          response.write(jsonEncode(list));
          await response.close();
        } else if (path.startsWith('/download_staged/')) {
          final fileId = path.substring('/download_staged/'.length);
          final item = _stagedFiles.cast<SharedDropFile?>().firstWhere(
            (f) => f?.id == fileId,
            orElse: () => null,
          );

          if (item != null && File(item.filePath).existsSync()) {
            final file = File(item.filePath);
            final length = await file.length();
            final fileName = Uri.encodeComponent(item.name);

            try {
              response.headers.contentType = ContentType.parse(item.mimeType);
            } catch (_) {
              response.headers.contentType = ContentType('application', 'octet-stream');
            }
            response.headers.add(
              'Content-Disposition',
              'attachment; filename*=UTF-8\'\'$fileName',
            );
            response.headers.contentLength = length;

            _logEvent('download', 'تم تحميل الملف المشارك من الهاتف: "${item.name}"');
            await _streamFileWithProgress(
              file: file,
              fileName: item.name,
              response: response,
              length: length,
              direction: DropTransferDirection.sendingToPc,
            );
          } else {
            response.statusCode = HttpStatus.notFound;
            response.write('File not found');
            await response.close();
          }
        } else if (path == '/upload' && request.method == 'POST') {
          // Upload file from PC to phone
          await _handleFileUpload(request, onFileUploaded);
        } else {
          response.statusCode = HttpStatus.notFound;
          response.write('Not Found');
          await response.close();
        }
      } catch (e) {
        debugPrint('[LocalWebDrop] Request error: $e');
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {}
      }
    });
  }

  Future<void> _handleFileUpload(
    HttpRequest request,
    Future<void> Function(String fileName, List<int> bytes) onFileUploaded,
  ) async {
    final response = request.response;
    try {
      final contentType = request.headers.contentType;
      final contentLength = request.headers.contentLength;
      final transferId = 'recv_${DateTime.now().millisecondsSinceEpoch}';

      if (contentType != null && contentType.primaryType == 'multipart') {
        final boundary = contentType.parameters['boundary'];
        if (boundary != null) {
          int receivedBytes = 0;
          _updateProgress(DropTransferProgress(
            id: transferId,
            fileName: 'ملف قيد الاستقبال من الكمبيوتر...',
            direction: DropTransferDirection.receivingFromPc,
            transferredBytes: 0,
            totalBytes: contentLength > 0 ? contentLength : 0,
            isCompleted: false,
          ));

          final progressStream = request.transform<List<int>>(
            StreamTransformer<Uint8List, List<int>>.fromHandlers(
              handleData: (chunk, sink) {
                receivedBytes += chunk.length;
                sink.add(chunk);
                _updateProgress(DropTransferProgress(
                  id: transferId,
                  fileName: 'ملف من الكمبيوتر',
                  direction: DropTransferDirection.receivingFromPc,
                  transferredBytes: receivedBytes,
                  totalBytes: contentLength > 0 ? contentLength : receivedBytes,
                  isCompleted: false,
                ));
              },
            ),
          );

          final transformer = MimeMultipartTransformer(boundary);
          final parts = await transformer.bind(progressStream).toList();

          int uploadedCount = 0;
          String lastFileName = '';
          for (final part in parts) {
            final contentDisposition = part.headers['content-disposition'];
            if (contentDisposition != null) {
              final filenameMatch =
                  RegExp(r'filename="([^"]+)"').firstMatch(contentDisposition);
              if (filenameMatch != null) {
                final filename = filenameMatch.group(1)!;
                lastFileName = filename;
                final bytes = await part.fold<List<int>>(
                    [], (prev, element) => prev..addAll(element));
                if (bytes.isNotEmpty) {
                  await onFileUploaded(filename, bytes);
                  uploadedCount++;
                  _logEvent('upload', 'تم استقبال ملف من الكمبيوتر: "$filename"');
                }
              }
            }
          }

          _updateProgress(DropTransferProgress(
            id: transferId,
            fileName: lastFileName.isNotEmpty ? lastFileName : 'تم استقبال الملفات بنجاح',
            direction: DropTransferDirection.receivingFromPc,
            transferredBytes: receivedBytes,
            totalBytes: receivedBytes,
            isCompleted: true,
          ));
          _scheduleClearProgress(transferId);

          response.statusCode = HttpStatus.ok;
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({'success': true, 'count': uploadedCount}));
          await response.close();
          return;
        }
      }
      response.statusCode = HttpStatus.badRequest;
      response.write('Invalid multipart request');
      await response.close();
    } catch (e) {
      _logEvent('error', 'خطأ أثناء رفع الملف من الكمبيوتر: $e');
      response.statusCode = HttpStatus.internalServerError;
      response.write('Upload error: $e');
      await response.close();
    }
  }

  Future<void> _streamFileWithProgress({
    required File file,
    required String fileName,
    required HttpResponse response,
    required int length,
    required DropTransferDirection direction,
  }) async {
    final transferId = 'send_${DateTime.now().millisecondsSinceEpoch}';
    int transferred = 0;

    _updateProgress(DropTransferProgress(
      id: transferId,
      fileName: fileName,
      direction: direction,
      transferredBytes: 0,
      totalBytes: length,
      isCompleted: false,
    ));

    final progressStream = file.openRead().transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          transferred += chunk.length;
          sink.add(chunk);
          _updateProgress(DropTransferProgress(
            id: transferId,
            fileName: fileName,
            direction: direction,
            transferredBytes: transferred,
            totalBytes: length,
            isCompleted: transferred >= length,
          ));
        },
        handleDone: (sink) {
          sink.close();
          _updateProgress(DropTransferProgress(
            id: transferId,
            fileName: fileName,
            direction: direction,
            transferredBytes: length,
            totalBytes: length,
            isCompleted: true,
          ));
          _scheduleClearProgress(transferId);
        },
        handleError: (err, st, sink) {
          sink.addError(err, st);
          _updateProgress(DropTransferProgress(
            id: transferId,
            fileName: fileName,
            direction: direction,
            transferredBytes: transferred,
            totalBytes: length,
            isCompleted: false,
            errorMessage: err.toString(),
          ));
          _scheduleClearProgress(transferId);
        },
      ),
    );

    await progressStream.pipe(response);
  }

  String _generateDashboardHtml(List<PendingUpload> documents) {
    final docsJson = jsonEncode(documents.map((d) => {
      'id': d.id,
      'title': d.fileName,
      'pageCount': d.pageCount,
      'fileSize': '${(d.fileSize / 1024).toStringAsFixed(1)} KB',
      'date': '${d.createdAt.year}/${d.createdAt.month.toString().padLeft(2, '0')}/${d.createdAt.day.toString().padLeft(2, '0')}',
      'hasThumb': d.thumbnailPath != null || d.pages.isNotEmpty,
    }).toList());

    return '''<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>لقطة • Laqta Web Drop</title>
  <style>
    :root {
      --bg: #F5F5F7;
      --card-bg: #FFFFFF;
      --accent: #007AFF;
      --accent-hover: #0056D2;
      --text: #1D1D1F;
      --text-sec: #86868B;
      --border: rgba(0,0,0,0.08);
      --radius: 18px;
      --shadow: 0 4px 20px rgba(0,0,0,0.06);
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #000000;
        --card-bg: #1C1C1E;
        --text: #F5F5F7;
        --text-sec: #A1A1A6;
        --border: rgba(255,255,255,0.12);
        --shadow: 0 4px 20px rgba(0,0,0,0.4);
      }
    }
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Cairo, sans-serif; }
    body { background: var(--bg); color: var(--text); padding: 24px; min-height: 100vh; }
    .header { max-width: 1080px; margin: 0 auto 28px; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 16px; }
    .logo-box { display: flex; align-items: center; gap: 14px; }
    .logo-icon { width: 44px; height: 44px; background: linear-gradient(135deg, #007AFF, #5856D6); border-radius: 12px; display: flex; align-items: center; justify-content: center; color: white; font-weight: 800; font-size: 20px; box-shadow: 0 4px 12px rgba(0,122,255,0.3); }
    .logo-text h1 { font-size: 20px; font-weight: 800; letter-spacing: -0.5px; }
    .logo-text p { font-size: 13px; color: var(--text-sec); }
    .status-badge { display: inline-flex; align-items: center; gap: 8px; padding: 8px 16px; background: rgba(52, 199, 89, 0.12); border: 1px solid rgba(52, 199, 89, 0.3); border-radius: 999px; color: #34C759; font-weight: 700; font-size: 13px; }
    .status-dot { width: 8px; height: 8px; background: #34C759; border-radius: 50%; box-shadow: 0 0 8px #34C759; }
    
    .container { max-width: 1080px; margin: 0 auto; }
    
    /* Upload Drop Zone */
    .drop-zone { background: var(--card-bg); border: 2px dashed var(--accent); border-radius: var(--radius); padding: 28px; text-align: center; margin-bottom: 28px; box-shadow: var(--shadow); cursor: pointer; transition: all 0.2s ease; }
    .drop-zone:hover { background: rgba(0,122,255,0.03); transform: translateY(-2px); }
    .drop-zone h3 { font-size: 16px; font-weight: 700; margin-bottom: 6px; }
    .drop-zone p { font-size: 13px; color: var(--text-sec); }
    
    /* Search Bar */
    .search-box { margin-bottom: 20px; position: relative; }
    .search-box input { width: 100%; padding: 14px 20px; font-size: 15px; border-radius: 14px; border: 1px solid var(--border); background: var(--card-bg); color: var(--text); outline: none; transition: border-color 0.2s; }
    .search-box input:focus { border-color: var(--accent); }
    
    /* Grid */
    .doc-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 18px; }
    .doc-card { background: var(--card-bg); border: 1px solid var(--border); border-radius: var(--radius); padding: 16px; box-shadow: var(--shadow); transition: transform 0.2s, box-shadow 0.2s; display: flex; flex-direction: column; justify-content: space-between; }
    .doc-card:hover { transform: translateY(-3px); box-shadow: 0 8px 26px rgba(0,0,0,0.09); }
    .doc-preview { width: 100%; height: 160px; background: rgba(0,0,0,0.04); border-radius: 12px; margin-bottom: 14px; overflow: hidden; display: flex; align-items: center; justify-content: center; position: relative; border: 1px solid var(--border); }
    .doc-preview img { width: 100%; height: 100%; object-fit: cover; }
    .doc-preview .pdf-badge { position: absolute; top: 10px; right: 10px; background: rgba(0,0,0,0.7); color: white; padding: 4px 8px; border-radius: 6px; font-size: 11px; font-weight: 700; backdrop-filter: blur(4px); }
    .doc-title { font-size: 15px; font-weight: 700; margin-bottom: 6px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .doc-meta { font-size: 12px; color: var(--text-sec); margin-bottom: 14px; }
    .doc-actions { display: flex; gap: 8px; }
    .btn { flex: 1; padding: 10px; border-radius: 12px; border: none; font-size: 13px; font-weight: 700; cursor: pointer; text-decoration: none; display: inline-flex; align-items: center; justify-content: center; gap: 6px; transition: background 0.2s; }
    .btn-primary { background: var(--accent); color: white; }
    .btn-primary:hover { background: var(--accent-hover); }
    .btn-secondary { background: rgba(0,0,0,0.05); color: var(--text); border: 1px solid var(--border); }
    @media (prefers-color-scheme: dark) {
      .btn-secondary { background: rgba(255,255,255,0.08); }
    }
    .empty-state { text-align: center; padding: 60px 20px; color: var(--text-sec); grid-column: 1 / -1; }
  </style>
</head>
<body>
  <div class="header">
    <div class="logo-box">
      <div class="logo-icon">📄</div>
      <div class="logo-text">
        <h1>لقطة • Laqta Web Drop</h1>
        <p>نقل مباشر للمستندات بين الهاتف والكمبيوتر عبر الواي فاي</p>
      </div>
    </div>
    <div class="status-badge">
      <span class="status-dot"></span>
      متصل محلياً ومؤمّن 100%
    </div>
  </div>

  <div class="container">
    <!-- Staged Files Directly Sent From Mobile Phone -->
    <div id="stagedSection" style="margin-bottom: 24px; display: none;">
      <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px;">
        <div style="display: flex; align-items: center; gap: 8px;">
          <span style="font-size: 20px;">⚡</span>
          <h2 style="font-size: 16.5px; font-weight: 800;">ملفات أرسلها الهاتف الآن (مشاركة مباشرة)</h2>
        </div>
        <span id="stagedCount" style="background: rgba(0,122,255,0.12); color: #007AFF; padding: 4px 10px; border-radius: 99px; font-size: 12px; font-weight: 700;">0 ملفات</span>
      </div>
      <div id="stagedGrid" style="display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 14px;"></div>
    </div>

    <!-- Live Upload Progress Box with Percentage and Bytes -->
    <div id="uploadProgressBox" style="display:none; background: var(--card-bg); border: 2px solid var(--accent); border-radius: var(--radius); padding: 20px; margin-bottom: 24px; box-shadow: var(--shadow);">
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
        <div style="display: flex; align-items: center; gap: 10px;">
          <span style="font-size: 24px;">🚀</span>
          <div>
            <h3 id="uploadProgressTitle" style="font-size: 15px; font-weight: 800;">جارٍ إرسال الملفات إلى هاتفك...</h3>
            <p id="uploadProgressSubtitle" style="font-size: 11.5px; color: var(--text-sec); margin-top: 2px;">يتم النقل مباشرة عبر الشبكة المحلية بأقصى سرعة</p>
          </div>
        </div>
        <div id="uploadProgressPercent" style="font-size: 18px; font-weight: 900; color: var(--accent); font-family: monospace;">0%</div>
      </div>
      <div style="width: 100%; height: 12px; background: rgba(0,0,0,0.06); border-radius: 99px; overflow: hidden; margin-bottom: 10px; position: relative;">
        <div id="uploadProgressBar" style="width: 0%; height: 100%; background: linear-gradient(90deg, #007AFF, #34C759); border-radius: 99px; transition: width 0.1s ease;"></div>
      </div>
      <div style="display: flex; justify-content: space-between; align-items: center; font-size: 12px; color: var(--text-sec);">
        <span id="uploadProgressStatus">⚡ جارٍ نقل البيانات...</span>
        <span id="uploadProgressBytes" style="font-weight: 700; font-family: monospace;">0 MB / 0 MB</span>
      </div>
    </div>

    <!-- Drag & Drop to Upload back to Phone -->
    <div class="drop-zone" id="dropZone" onclick="document.getElementById('fileInput').click()">
      <input type="file" id="fileInput" style="display:none" multiple onchange="handleFiles(this.files)">
      <h3>📤 إرسال ملفات من الكمبيوتر أو الهاتف الآخر إلى هاتفك</h3>
      <p>اسحب أي ملف PDF أو صور وأفلتها هنا، أو اضغط للتصفح</p>
    </div>

    <!-- Search -->
    <div class="search-box">
      <input type="text" id="searchInput" placeholder="🔍 بحث في المستندات..." oninput="filterDocs(this.value)">
    </div>

    <!-- Documents Grid -->
    <div class="doc-grid" id="docGrid"></div>
  </div>

  <script>
    const docs = $docsJson;

    function renderDocs(items) {
      const grid = document.getElementById('docGrid');
      if (items.length === 0) {
        grid.innerHTML = '<div class="empty-state"><h3>لا توجد مستندات مطابقة</h3></div>';
        return;
      }
      grid.innerHTML = items.map(d => `
        <div class="doc-card">
          <div>
            <div class="doc-preview">
              <span class="pdf-badge">\${d.pageCount} صفحات</span>
              <img src="/thumb/\${d.id}" onerror="this.style.display='none'" alt="">
            </div>
            <div class="doc-title" title="\${d.title}">\${d.title}</div>
            <div class="doc-meta">\${d.fileSize} • \${d.date}</div>
          </div>
          <div class="doc-actions">
            <a href="/download/\${d.id}" class="btn btn-primary" download>⬇️ تحميل PDF</a>
            <a href="/download/\${d.id}" class="btn btn-secondary" target="_blank">معاينة</a>
          </div>
        </div>
      `).join('');
    }

    function filterDocs(query) {
      const q = query.trim().toLowerCase();
      const filtered = docs.filter(d => d.title.toLowerCase().includes(q));
      renderDocs(filtered);
    }

    async function checkStagedFiles() {
      try {
        const res = await fetch('/api/staged');
        if (res.ok) {
          const items = await res.json();
          renderStaged(items);
        }
      } catch (e) {}
    }

    function renderStaged(items) {
      const section = document.getElementById('stagedSection');
      const grid = document.getElementById('stagedGrid');
      const countBadge = document.getElementById('stagedCount');
      if (!items || items.length === 0) {
        section.style.display = 'none';
        return;
      }
      section.style.display = 'block';
      countBadge.innerText = items.length + ' ملف';

      grid.innerHTML = items.map(f => `
        <div style="background: var(--card-bg); border: 2px solid #007AFF; border-radius: var(--radius); padding: 14px; box-shadow: 0 4px 16px rgba(0,122,255,0.12); display: flex; flex-direction: column; justify-content: space-between;">
          <div style="display: flex; align-items: center; gap: 12px; margin-bottom: 12px;">
            <div style="width: 42px; height: 42px; background: rgba(0,122,255,0.12); border-radius: 12px; display: flex; align-items: center; justify-content: center; font-size: 20px;">
              \${f.name.endsWith('.pdf') ? '📄' : (f.name.match(/\\.(jpg|jpeg|png|webp)\$/i) ? '🖼️' : (f.name.endsWith('.zip') ? '📦' : '📁'))}
            </div>
            <div style="overflow: hidden; flex: 1;">
              <div style="font-weight: 800; font-size: 13.5px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;" title="\${f.name}">\${f.name}</div>
              <div style="font-size: 11px; color: var(--text-sec); margin-top: 2px;">\${f.formattedSize} • أُرسل \${f.time}</div>
            </div>
          </div>
          <a href="/download_staged/\${f.id}" class="btn btn-primary" download style="background: #34C759; box-shadow: 0 2px 10px rgba(52,199,89,0.3);">
            ⬇️ تحميل الملف فوراً (\${f.formattedSize})
          </a>
        </div>
      `).join('');
    }

    setInterval(checkStagedFiles, 2500);
    checkStagedFiles();

    function handleFiles(files) {
      if (!files || files.length === 0) return;
      const progressBox = document.getElementById('uploadProgressBox');
      const progressBar = document.getElementById('uploadProgressBar');
      const progressPercent = document.getElementById('uploadProgressPercent');
      const progressTitle = document.getElementById('uploadProgressTitle');
      const progressSubtitle = document.getElementById('uploadProgressSubtitle');
      const progressBytes = document.getElementById('uploadProgressBytes');
      const progressStatus = document.getElementById('uploadProgressStatus');

      const formData = new FormData();
      let totalBytes = 0;
      for (let i = 0; i < files.length; i++) {
        formData.append('files', files[i]);
        totalBytes += files[i].size;
      }

      progressBox.style.display = 'block';
      progressBar.style.width = '0%';
      progressBar.style.background = 'linear-gradient(90deg, #007AFF, #34C759)';
      progressPercent.innerText = '0%';
      progressPercent.style.color = '#007AFF';
      progressTitle.innerText = 'جارٍ إرسال (' + files.length + ') ملف إلى هاتفك...';
      const totalMB = (totalBytes / (1024 * 1024)).toFixed(1);
      progressBytes.innerText = '0.0 MB / ' + totalMB + ' MB';
      progressStatus.innerText = '⚡ نقل مباشر عبر Wi-Fi...';

      const xhr = new XMLHttpRequest();
      xhr.open('POST', '/upload', true);

      xhr.upload.onprogress = function(e) {
        if (e.lengthComputable) {
          const pct = Math.round((e.loaded / e.total) * 100);
          progressBar.style.width = pct + '%';
          progressPercent.innerText = pct + '%';
          const loadedMB = (e.loaded / (1024 * 1024)).toFixed(1);
          progressBytes.innerText = loadedMB + ' MB / ' + totalMB + ' MB';
        }
      };

      xhr.onload = function() {
        if (xhr.status >= 200 && xhr.status < 300) {
          progressBar.style.width = '100%';
          progressPercent.innerText = '100%';
          progressPercent.style.color = '#34C759';
          progressTitle.innerText = '✅ تم إرسال الملفات بنجاح إلى هاتفك!';
          progressSubtitle.innerText = 'تم حفظها في مركز الملفات المنقولة في التطبيق';
          progressBytes.innerText = totalMB + ' MB / ' + totalMB + ' MB';
          progressStatus.innerText = '🎉 تم النقل بنجاح';
          setTimeout(() => {
            progressBox.style.display = 'none';
            checkStagedFiles();
          }, 3500);
        } else {
          progressTitle.innerText = '❌ حدث خطأ أثناء الإرسال (' + xhr.status + ')';
          progressBar.style.background = '#FF3B30';
          progressStatus.innerText = 'يرجى المحاولة مرة أخرى';
        }
      };

      xhr.onerror = function() {
        progressTitle.innerText = '❌ انقطع الاتصال بالهاتف';
        progressBar.style.background = '#FF3B30';
        progressStatus.innerText = 'تأكد من بقاء شاشة التطبيق مفتوحة';
      };

      xhr.send(formData);
    }

    // Drag & Drop handlers
    const dz = document.getElementById('dropZone');
    dz.addEventListener('dragover', (e) => { e.preventDefault(); dz.style.background = 'rgba(0,122,255,0.08)'; });
    dz.addEventListener('dragleave', () => { dz.style.background = 'var(--card-bg)'; });
    dz.addEventListener('drop', (e) => {
      e.preventDefault();
      dz.style.background = 'var(--card-bg)';
      handleFiles(e.dataTransfer.files);
    });

    renderDocs(docs);
  </script>
</body>
</html>''';
  }
}

/// Lightweight pure Dart MIME multipart transformer for processing file uploads from browser
class MimeMultipartTransformer extends StreamTransformerBase<List<int>, MimeMultipart> {
  MimeMultipartTransformer(this.boundary);
  final String boundary;

  @override
  Stream<MimeMultipart> bind(Stream<List<int>> stream) async* {
    final delimiter = utf8.encode('--$boundary');

    List<int> buffer = [];

    await for (final chunk in stream) {
      buffer.addAll(chunk);
    }

    int searchIndex = 0;
    while (true) {
      final startIndex = _indexOf(buffer, delimiter, searchIndex);
      if (startIndex == -1) break;

      final partStart = startIndex + delimiter.length;
      final nextDelim = _indexOf(buffer, delimiter, partStart);
      if (nextDelim == -1) break;

      final partBytes = buffer.sublist(partStart, nextDelim);
      final headerEnd = _indexOf(partBytes, utf8.encode('\r\n\r\n'), 0);
      if (headerEnd != -1) {
        final headerText = utf8.decode(partBytes.sublist(0, headerEnd));
        final bodyBytes = partBytes.sublist(headerEnd + 4);

        // Remove trailing \r\n if present
        List<int> cleanBody = bodyBytes;
        if (cleanBody.length >= 2 && cleanBody[cleanBody.length - 2] == 13 && cleanBody[cleanBody.length - 1] == 10) {
          cleanBody = cleanBody.sublist(0, cleanBody.length - 2);
        }

        final headers = <String, String>{};
        for (final line in headerText.split('\r\n')) {
          final col = line.indexOf(':');
          if (col != -1) {
            headers[line.substring(0, col).trim().toLowerCase()] = line.substring(col + 1).trim();
          }
        }
        yield MimeMultipart(headers, Stream.value(cleanBody));
      }
      searchIndex = nextDelim;
    }
  }

  int _indexOf(List<int> source, List<int> pattern, int start) {
    if (pattern.isEmpty || start >= source.length) return -1;
    for (int i = start; i <= source.length - pattern.length; i++) {
      bool match = true;
      for (int j = 0; j < pattern.length; j++) {
        if (source[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }
}

class MimeMultipart {
  MimeMultipart(this.headers, this._stream);
  final Map<String, String> headers;
  final Stream<List<int>> _stream;

  Future<T> fold<T>(T initialValue, T Function(T previous, List<int> element) combine) =>
      _stream.fold(initialValue, combine);
}
