import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'dshare_api.dart';
import 'gesture_recognizer.dart';

const String kBaseUrl = String.fromEnvironment(
  'DSHARE_BASE_URL',
  defaultValue: 'https://dshare.me',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  Timer? _toastTimer;
  String _toastMessage = '';
  bool _toastVisible = false;
  bool _isPublic = true;
  bool _ready = false;
  String _buffer = '';

  DshareApi? _api;
  // StreamSubscription<List<SharedMediaFile>>? _mediaShareSub;

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
    // _mediaShareSub?.cancel();
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
    // _initShareIntents();
  }

  void _initShareIntents() {
    /*
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
    */
  }

  /*
  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    if (_api == null || files.isEmpty) {
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
    _showToast('uploading');
    try {
      final res = await _api!.uploadFile(filePath);
      _showToast(_isOk(res) ? 'ok' : 'fail');
    } catch (_) {
      _showToast('fail');
    }
  }
  */

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

  void _handleStrokeEnd() {
    if (_stroke.length < 10) {
      _stroke.clear();
      setState(() {});
      return;
    }
    final result = _recognizer.recognize(List.of(_stroke));
    _stroke.clear();
    setState(() {});
    if (result == null || result.score < 0.65) {
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
        _runAction(DshareAction.upload);
        break;
      case 'DOWN':
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

  Future<void> _actionUpload() async {
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
    final res = await _api!.uploadFile(path);
    _showToast(_isOk(res) ? 'ok' : 'fail');
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
          onTap: () => _focusNode.requestFocus(),
          onPanStart: (details) {
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
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: StrokePainter(_stroke),
                ),
              ),
              if (_isPublic)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Text(
                        'PUBLIC',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.06),
                          fontSize: 72,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 6,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Text(
                      'DShare',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.12),
                        fontSize: 24,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
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
