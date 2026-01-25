import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dshare_api.dart';
import 'gesture_recognizer.dart';

const String kBaseUrl = String.fromEnvironment(
  'DSHARE_BASE_URL',
  defaultValue: 'https://dshare.me',
);

const int kChunkSize = 1024 * 1024;
final FlutterLocalNotificationsPlugin kNotifications =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const darwinSettings = DarwinInitializationSettings();
  const initSettings =
      InitializationSettings(android: androidSettings, iOS: darwinSettings);
  await kNotifications.initialize(initSettings);
  if (Platform.isAndroid) {
    await kNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }
  if (Platform.isIOS) {
    await kNotifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: false, sound: true);
  }
  runApp(const DshareApp());
}

class DshareApp extends StatelessWidget {
  const DshareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DShare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          surface: Colors.black,
          onSurface: Colors.white,
        ),
      ),
      home: const HomePage(),
    );
  }
}

enum DshareAction {
  register,
  login,
  logout,
  paste,
  copy,
  status,
  me,
  passkey,
  help,
  upload,
  download,
  clear,
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FocusNode _focusNode = FocusNode();
  final OneDollarRecognizer _recognizer = buildDefaultRecognizer();
  final List<Offset> _stroke = [];
  static const double _gestureScoreThreshold = 0.72;
  Timer? _toastTimer;
  String _toastMessage = '';
  bool _toastVisible = false;
  bool _isPublic = true;
  bool _ready = false;
  String _buffer = '';
  double? _uploadProgress;
  bool _uploadPaused = false;

  DshareApi? _api;
  StreamSubscription<List<SharedMediaFile>>? _mediaShareSub;

  @override
  void initState() {
    super.initState();
    _initApi();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _mediaShareSub?.cancel();
    _toastTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _initApi() async {
    final api = await DshareApi.create(kBaseUrl);
    if (!mounted) {
      return;
    }
    setState(() {
      _api = api;
      _ready = true;
    });
    await _refreshMode();
    _initShareIntents();
  }

  void _initShareIntents() {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    try {
      _mediaShareSub =
          ReceiveSharingIntent.instance.getMediaStream().listen((files) {
        if (files.isNotEmpty) {
          _handleSharedFiles(files);
        }
      });
      ReceiveSharingIntent.instance.getInitialMedia().then((files) {
        if (files.isNotEmpty) {
          _handleSharedFiles(files);
          ReceiveSharingIntent.instance.reset();
        }
      });
    } catch (_) {}
  }

  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    if (_api == null || files.isEmpty) {
      return;
    }
    if (_uploadProgress != null) {
      _showToast('busy');
      return;
    }
    final first = files.first;
    if (first.type == SharedMediaType.text || first.type == SharedMediaType.url) {
      final text = first.message?.trim().isNotEmpty == true
          ? first.message!.trim()
          : first.path.trim();
      if (text.isEmpty) {
        _showToast('fail');
        return;
      }
      _showToast('uploading');
      try {
        final res = await _api!.uploadText(text);
        _showToast(_isOk(res) ? 'ok' : 'fail');
      } catch (_) {
        _showToast('fail');
      }
      return;
    }
    final filePath = first.path;
    if (filePath.isEmpty) {
      _showToast('fail');
      return;
    }
    await _uploadFilePath(filePath, showUploadingToast: true);
  }

  void _showToast(String message, {int ms = 1800}) {
    _toastTimer?.cancel();
    setState(() {
      _toastMessage = message;
      _toastVisible = true;
    });
    _toastTimer = Timer(Duration(milliseconds: ms), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _toastVisible = false;
      });
    });
  }

  Future<void> _refreshMode() async {
    if (_api == null) {
      return;
    }
    try {
      final res = await _api!.getJson('/api/auth/me/');
      final data = _jsonMap(res.data);
      final authenticated = data != null && data['authenticated'] == true;
      if (!mounted) {
        return;
      }
      setState(() {
        _isPublic = !authenticated;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPublic = true;
      });
    }
  }

  Map<String, dynamic>? _jsonMap(dynamic data) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data is String) {
      try {
        final parsed = jsonDecode(data);
        if (parsed is Map) {
          return Map<String, dynamic>.from(parsed);
        }
      } catch (_) {}
    }
    return null;
  }

  bool _isOk(Response<dynamic> res) {
    if ((res.statusCode ?? 500) >= 400) {
      return false;
    }
    final data = _jsonMap(res.data);
    if (data == null || !data.containsKey('status')) {
      return true;
    }
    return data['status'] == 'ok';
  }

  void _handleKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) {
      return;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _runAction(DshareAction.upload);
      return;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _runAction(DshareAction.download);
      return;
    }
    final ch = event.character;
    if (ch == null || ch.isEmpty) {
      return;
    }
    if (ch.length == 1) {
      _buffer += ch.toLowerCase();
      if (_buffer.length > 64) {
        _buffer = _buffer.substring(_buffer.length - 64);
      }
      _checkCommands();
    }
  }

  void _checkCommands() {
    if (_buffer.contains('divya')) {
      _buffer = '';
      _runAction(DshareAction.upload);
      return;
    }
    if (_buffer.contains('moti')) {
      _buffer = '';
      _runAction(DshareAction.download);
      return;
    }
    for (final prefix in ['/', '\\']) {
      final idx = _buffer.lastIndexOf(prefix);
      if (idx == -1) {
        continue;
      }
      final maybe = _buffer.substring(idx + 1);
      final cmd = _commandFor(maybe);
      if (cmd != null) {
        _buffer = '';
        _runAction(cmd);
        break;
      }
    }
  }

  DshareAction? _commandFor(String cmd) {
    switch (cmd) {
      case 'register':
        return DshareAction.register;
      case 'login':
        return DshareAction.login;
      case 'logout':
        return DshareAction.logout;
      case 'paste':
        return DshareAction.paste;
      case 'copy':
        return DshareAction.copy;
      case 'status':
        return DshareAction.status;
      case 'me':
        return DshareAction.me;
      case 'passkey':
        return DshareAction.passkey;
      case 'help':
      case '?':
        return DshareAction.help;
      case 'clear':
        return DshareAction.clear;
    }
    return null;
  }

  DshareAction? _verticalSwipeAction(List<Offset> stroke) {
    if (stroke.length < 2) {
      return null;
    }
    final size = MediaQuery.of(context).size;
    final minDy = math.max(50.0, size.height * 0.06);
    final maxDx = math.max(220.0, size.width * 0.65);
    double minX = stroke.first.dx;
    double maxX = stroke.first.dx;
    double minY = stroke.first.dy;
    double maxY = stroke.first.dy;
    double sumAbsDx = 0.0;
    double sumAbsDy = 0.0;
    int posDySegments = 0;
    int negDySegments = 0;
    for (int i = 1; i < stroke.length; i++) {
      final prev = stroke[i - 1];
      final curr = stroke[i];
      final dx = curr.dx - prev.dx;
      final dy = curr.dy - prev.dy;
      sumAbsDx += dx.abs();
      sumAbsDy += dy.abs();
      if (dy > 2.0) {
        posDySegments += 1;
      } else if (dy < -2.0) {
        negDySegments += 1;
      }
      if (curr.dx < minX) minX = curr.dx;
      if (curr.dx > maxX) maxX = curr.dx;
      if (curr.dy < minY) minY = curr.dy;
      if (curr.dy > maxY) maxY = curr.dy;
    }
    final dxRange = maxX - minX;
    final dyRange = maxY - minY;
    if (dyRange < minDy) {
      return null;
    }
    if (dxRange > maxDx) {
      return null;
    }
    if (sumAbsDy <= 0) {
      return null;
    }
    final dominance =
        sumAbsDx == 0 ? double.infinity : (sumAbsDy / sumAbsDx);
    if (dominance < 1.05) {
      return null;
    }
    final totalDy = posDySegments + negDySegments;
    if (totalDy > 0) {
      final dominant =
          math.max(posDySegments, negDySegments) / totalDy;
      if (dominant < 0.6) {
        return null;
      }
    }
    final netDy = stroke.last.dy - stroke.first.dy;
    if (netDy.abs() < dyRange * 0.35) {
      return null;
    }
    return netDy < 0 ? DshareAction.upload : DshareAction.download;
  }

  DshareAction? _verticalSwipeFallback(List<Offset> stroke) {
    if (stroke.length < 2) {
      return null;
    }
    final size = MediaQuery.of(context).size;
    final minDy = math.max(40.0, size.height * 0.05);
    final netDy = stroke.last.dy - stroke.first.dy;
    final netDx = stroke.last.dx - stroke.first.dx;
    if (netDy.abs() < minDy) {
      return null;
    }
    if (netDy.abs() < netDx.abs() * 1.1) {
      return null;
    }
    return netDy < 0 ? DshareAction.upload : DshareAction.download;
  }

  void _handleStrokeEnd() {
    if (_stroke.length < 2) {
      _stroke.clear();
      setState(() {});
      return;
    }
    final stroke = List<Offset>.from(_stroke);
    _stroke.clear();
    setState(() {});
    final verticalAction = _verticalSwipeAction(stroke);
    if (verticalAction != null) {
      _runAction(verticalAction);
      return;
    }
    final fallbackAction = _verticalSwipeFallback(stroke);
    if (fallbackAction != null) {
      _runAction(fallbackAction);
      return;
    }
    if (stroke.length < 10) {
      return;
    }
    final result = _recognizer.recognize(stroke);
    if (result == null || result.score < _gestureScoreThreshold) {
      _showToast('fail');
      return;
    }
    switch (result.name) {
      case 'R':
        _runAction(DshareAction.register);
        break;
      case 'L':
        _runAction(DshareAction.login);
        break;
      case 'P':
        _runAction(DshareAction.paste);
        break;
      case 'S':
        _runAction(DshareAction.status);
        break;
      case 'C':
        _runAction(DshareAction.copy);
        break;
      case 'M':
        _runAction(DshareAction.me);
        break;
      case 'K':
        _runAction(DshareAction.passkey);
        break;
      case 'H':
        _runAction(DshareAction.help);
        break;
      case 'UP':
      case 'ARROW_UP':
        _runAction(DshareAction.upload);
        break;
      case 'DOWN':
      case 'ARROW_DOWN':
        _runAction(DshareAction.download);
        break;
      default:
        _showToast('fail');
        break;
    }
  }

  Future<void> _runAction(DshareAction action) async {
    if (!_ready || _api == null) {
      _showToast('loading');
      return;
    }
    switch (action) {
      case DshareAction.register:
        await _actionRegister();
        break;
      case DshareAction.login:
        await _actionLogin();
        break;
      case DshareAction.logout:
        await _actionLogout();
        break;
      case DshareAction.paste:
        await _actionPaste();
        break;
      case DshareAction.copy:
        await _actionCopy();
        break;
      case DshareAction.status:
        await _actionStatus();
        break;
      case DshareAction.me:
        await _actionMe();
        break;
      case DshareAction.passkey:
        _showToast('passkey: use web');
        break;
      case DshareAction.help:
        _actionHelp();
        break;
      case DshareAction.upload:
        await _actionUpload();
        break;
      case DshareAction.download:
        await _actionDownload();
        break;
      case DshareAction.clear:
        await _actionClear();
        break;
    }
  }

  Future<String?> _prompt(
    String title, {
    bool obscure = false,
  }) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black,
          title: Text(title),
          content: TextField(
            controller: controller,
            focusNode: focus,
            autofocus: true,
            obscureText: obscure,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    focus.dispose();
    return result;
  }

  Future<void> _actionRegister() async {
    final email = await _prompt('Email');
    if (email == null || email.isEmpty) {
      _showToast('fail');
      return;
    }
    bool canLogin = false;
    try {
      final res = await _api!.postJson('/api/auth/email-status/', {
        'email': email,
      });
      final data = _jsonMap(res.data);
      canLogin = res.statusCode == 200 &&
          data != null &&
          data['status'] == 'ok' &&
          data['can_login'] == true;
    } catch (_) {}
    if (canLogin) {
      final secret = await _prompt('Password or pin', obscure: true);
      if (secret == null || secret.isEmpty) {
        _showToast('fail');
        return;
      }
      final res = await _api!.postJson('/api/auth/login/', {
        'email': email,
        'secret': secret,
      });
      if (_isOk(res)) {
        _showToast('ok');
        await _refreshMode();
      } else {
        _showToast('fail');
      }
      return;
    }
    final password = await _prompt('Create password', obscure: true);
    if (password == null || password.isEmpty) {
      _showToast('fail');
      return;
    }
    final pin = await _prompt('Create pin (optional)', obscure: true) ?? '';
    final res = await _api!.postJson('/api/auth/register/', {
      'email': email,
      'password': password,
      'pin': pin,
    });
    _showToast(_isOk(res) ? 'sent' : 'fail');
  }

  Future<void> _actionLogin() async {
    final email = await _prompt('Email');
    if (email == null || email.isEmpty) {
      _showToast('fail');
      return;
    }
    final secret = await _prompt('Password or pin', obscure: true);
    if (secret == null || secret.isEmpty) {
      _showToast('fail');
      return;
    }
    final res = await _api!.postJson('/api/auth/login/', {
      'email': email,
      'secret': secret,
    });
    if (_isOk(res)) {
      _showToast('ok');
      await _refreshMode();
    } else {
      _showToast('fail');
    }
  }

  Future<void> _actionLogout() async {
    final res = await _api!.postJson('/api/auth/logout/', {});
    _showToast(_isOk(res) ? 'ok' : 'fail');
    await _refreshMode();
  }

  Future<void> _actionPaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) {
      _showToast('empty');
      return;
    }
    final res = await _api!.uploadText(text);
    _showToast(_isOk(res) ? 'ok' : 'fail');
  }

  Future<void> _actionCopy() async {
    final res = await _api!.getJson('/api/share/text/');
    final data = _jsonMap(res.data);
    final text = data != null ? (data['text'] ?? '') as String : '';
    await Clipboard.setData(ClipboardData(text: text));
    _showToast('ok');
  }

  Future<void> _actionStatus() async {
    await _refreshMode();
    _showToast(_isPublic ? 'public' : 'private');
  }

  Future<void> _actionMe() async {
    final res = await _api!.getJson('/api/auth/me/');
    final data = _jsonMap(res.data);
    if (data == null) {
      _showToast('fail');
      return;
    }
    final authenticated = data['authenticated'] == true;
    final emailVerified = data['email_verified'] == true;
    final hasPasskey = data['has_passkey'] == true;
    final hasPassword = data['has_password'] == true;
    final hasPin = data['has_pin'] == true;
    final summary = authenticated
        ? 'me: verified=$emailVerified passkey=$hasPasskey pw=$hasPassword pin=$hasPin'
        : 'me: public';
    _showToast(summary, ms: 3000);
    await _refreshMode();
  }

  void _actionHelp() {
    _showToast('R/L/P/S/C/M/K/H, up/down, /register /login /logout /help', ms: 3500);
  }

  Future<void> _notify(String message) async {
    const androidDetails = AndroidNotificationDetails(
      'dshare_uploads',
      'Uploads',
      channelDescription: 'DShare upload notifications',
      importance: Importance.low,
      priority: Priority.low,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );
    try {
      await kNotifications.show(0, 'DShare', message, details);
    } catch (_) {}
  }

  Future<SharedPreferences> _prefs() {
    return SharedPreferences.getInstance();
  }

  String _uploadCacheKey(String path, int size, int modifiedMs) {
    final encodedPath = base64Url.encode(utf8.encode(path));
    return 'dshare-upload:$encodedPath:$size:$modifiedMs';
  }

  Future<Map<String, dynamic>?> _loadUploadCache(String key) async {
    final prefs = await _prefs();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map) {
        return Map<String, dynamic>.from(parsed);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveUploadCache(String key, Map<String, dynamic> data) async {
    final prefs = await _prefs();
    prefs.setString(key, jsonEncode(data));
  }

  Future<void> _clearUploadCache(String key) async {
    final prefs = await _prefs();
    prefs.remove(key);
  }

  int _chunkByteSize(int totalSize, int index, int chunkSize) {
    final start = index * chunkSize;
    if (start >= totalSize) {
      return 0;
    }
    final remaining = totalSize - start;
    return remaining < chunkSize ? remaining : chunkSize;
  }

  Future<void> _waitWhilePaused() async {
    while (_uploadPaused && mounted) {
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  Future<void> _uploadFilePath(
    String path, {
    bool showUploadingToast = false,
  }) async {
    if (_api == null) {
      _showToast('loading');
      return;
    }
    if (_uploadProgress != null) {
      _showToast('busy');
      return;
    }
    final file = File(path);
    final stat = await file.stat();
    if (stat.size <= 0) {
      _showToast('fail');
      return;
    }
    if (showUploadingToast) {
      _showToast('uploading', ms: 1200);
    }
    final key = _uploadCacheKey(path, stat.size, stat.modified.millisecondsSinceEpoch);
    final cached = await _loadUploadCache(key);
    final startRes = await _api!.startUploadSession(
      filename: p.basename(path),
      size: stat.size,
      chunkSize: kChunkSize,
      contentType: '',
      uploadId: cached != null ? cached['upload_id'] as String? : null,
    );
    final startData = _jsonMap(startRes.data);
    if (startData == null || startData['status'] != 'ok') {
      _showToast('fail');
      return;
    }
    final uploadId = startData['upload_id']?.toString();
    if (uploadId == null || uploadId.isEmpty) {
      _showToast('fail');
      return;
    }
    final chunkSize = (startData['chunk_size'] as int?) ?? kChunkSize;
    await _saveUploadCache(key, {"upload_id": uploadId, "chunk_size": chunkSize});
    final totalChunks = (startData['total_chunks'] as int?) ??
        ((stat.size + chunkSize - 1) ~/ chunkSize);
    final received = <int>{};
    final receivedRaw = startData['received_chunks'];
    if (receivedRaw is List) {
      for (final item in receivedRaw) {
        if (item is num) {
          received.add(item.toInt());
        }
      }
    }
    int uploadedBytes = 0;
    for (final idx in received) {
      uploadedBytes += _chunkByteSize(stat.size, idx, chunkSize);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _uploadProgress = uploadedBytes / stat.size;
      _uploadPaused = false;
    });
    final raf = await file.open();
    bool ok = false;
    try {
      for (int index = 0; index < totalChunks; index++) {
        if (received.contains(index)) {
          continue;
        }
        await _waitWhilePaused();
        final length = _chunkByteSize(stat.size, index, chunkSize);
        await raf.setPosition(index * chunkSize);
        final bytes = await raf.read(length);
        final res = await _api!.uploadChunk(
          uploadId: uploadId,
          index: index,
          bytes: bytes,
          filename: p.basename(path),
        );
        if (!_isOk(res)) {
          throw Exception('chunk failed');
        }
        uploadedBytes += bytes.length;
        if (!mounted) {
          return;
        }
        setState(() {
          _uploadProgress = uploadedBytes / stat.size;
        });
      }
      final completeRes = await _api!.completeUpload(uploadId);
      ok = _isOk(completeRes);
      _showToast(ok ? 'ok' : 'fail');
      if (ok) {
        await _clearUploadCache(key);
        await _notify('Upload complete.');
      }
    } catch (_) {
      _showToast('fail');
    } finally {
      await raf.close();
      if (!mounted) {
        return;
      }
      setState(() {
        _uploadProgress = null;
        _uploadPaused = false;
      });
    }
  }

  Future<void> _actionUpload() async {
    if (_uploadProgress != null) {
      _showToast('busy');
      return;
    }
    final picked = await FilePicker.platform.pickFiles(withData: false);
    if (picked == null || picked.files.isEmpty) {
      _showToast('fail');
      return;
    }
    final path = picked.files.first.path;
    if (path == null || path.isEmpty) {
      _showToast('fail');
      return;
    }
    await _uploadFilePath(path);
  }

  Future<void> _actionDownload() async {
    final res = await _api!.download();
    final status = res.statusCode ?? 500;
    if (status >= 400) {
      _showToast('fail');
      return;
    }
    final contentType =
        res.headers.value(Headers.contentTypeHeader) ?? '';
    final bytes = res.data as List<int>;
    if (contentType.contains('application/json')) {
      final text = utf8.decode(bytes);
      final data = _jsonMap(text);
      if (data != null && data['status'] == 'empty') {
        _showToast('empty');
        return;
      }
      _showToast('ok');
      return;
    }
    if (contentType.contains('text/plain')) {
      final text = utf8.decode(bytes);
      await Clipboard.setData(ClipboardData(text: text));
      _showToast('copied');
      return;
    }
    final fileName =
        _fileNameFromHeaders(res.headers.map) ?? 'download.bin';
    final dir = await _downloadDir();
    final outPath = p.join(dir.path, fileName);
    final file = File(outPath);
    await file.writeAsBytes(bytes, flush: true);
    _showToast('saved $fileName', ms: 2500);
  }

  Future<void> _actionClear() async {
    final res = await _api!.postJson('/api/share/clear/', {});
    _showToast(_isOk(res) ? 'ok' : 'fail');
  }

  String? _fileNameFromHeaders(Map<String, List<String>> headers) {
    final dispo = headers['content-disposition']?.join(',') ?? '';
    final match = RegExp(r'filename="([^"]+)"').firstMatch(dispo);
    if (match != null) {
      return match.group(1);
    }
    return null;
  }

  Future<Directory> _downloadDir() async {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      return downloads;
    }
    return getApplicationDocumentsDirectory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RawKeyboardListener(
        focusNode: _focusNode,
        onKey: _handleKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTap: () {
            _focusNode.requestFocus();
            _actionHelp();
          },
          onPanStart: (details) {
            _focusNode.requestFocus();
            _stroke
              ..clear()
              ..add(details.localPosition);
            setState(() {});
          },
          onPanUpdate: (details) {
            _stroke.add(details.localPosition);
            setState(() {});
          },
          onPanEnd: (_) => _handleStrokeEnd(),
          onPanCancel: () {
            _stroke.clear();
            setState(() {});
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Opacity(
                      opacity: 0.12,
                      child: Image.asset(
                        'assets/dshare_logo_text.png',
                        width: 260,
                        height: 140,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: StrokePainter(List<Offset>.of(_stroke)),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isPublic ? 'public' : 'private',
                        style: const TextStyle(
                          fontSize: 12,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        kBaseUrl,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_uploadProgress != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 48,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(_uploadProgress! * 100).round()}%',
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 1.2,
                            color: Colors.white.withOpacity(0.75),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 160,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: (_uploadProgress ?? 0)
                                  .clamp(0.0, 1.0)
                                  .toDouble(),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _uploadPaused = !_uploadPaused;
                            });
                            _showToast(_uploadPaused ? 'paused' : 'resumed', ms: 900);
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            foregroundColor: Colors.white.withOpacity(0.8),
                            textStyle: const TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.4,
                            ),
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.35),
                            ),
                          ),
                          child: Text(_uploadPaused ? 'RESUME' : 'PAUSE'),
                        ),
                      ],
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'draw or type /help',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.45),
                    ),
                  ),
                ),
              ),
              Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _toastVisible ? 1 : 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _toastMessage,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              if (!_ready)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: SafeArea(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'loading',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class StrokePainter extends CustomPainter {
  StrokePainter(this.points);

  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      return;
    }
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], paint);
    }
  }

  @override
  bool shouldRepaint(covariant StrokePainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
