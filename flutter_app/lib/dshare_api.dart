import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DshareApi {
  DshareApi._(this.baseUri, this._dio, this._cookieJar);

  final Uri baseUri;
  final Dio _dio;
  final PersistCookieJar _cookieJar;

  static Future<DshareApi> create(String baseUrl) async {
    var normalized = baseUrl.trim();
    if (normalized.endsWith("/")) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    final baseUri = Uri.parse(normalized);
    final supportDir = await getApplicationSupportDirectory();
    final cookieDir = Directory(p.join(supportDir.path, "cookies"));
    final cookieJar = PersistCookieJar(storage: FileStorage(cookieDir.path));
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUri.toString(),
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    dio.interceptors.add(CookieManager(cookieJar));
    return DshareApi._(baseUri, dio, cookieJar);
  }

  Future<void> ensureCsrf() async {
    final csrf = await _csrfToken();
    if (csrf.isNotEmpty) {
      return;
    }
    await _dio.get("/");
  }

  Future<String> _csrfToken() async {
    final cookies = await _cookieJar.loadForRequest(baseUri);
    for (final cookie in cookies) {
      if (cookie.name == "csrftoken") {
        return cookie.value;
      }
    }
    return "";
  }

  Map<String, String> _csrfHeaders(String csrf) {
    final referer = baseUri.toString().endsWith("/")
        ? baseUri.toString()
        : "${baseUri.toString()}/";
    return {
      "X-CSRFToken": csrf,
      "Referer": referer,
      "Origin": baseUri.origin,
    };
  }

  Future<Response<dynamic>> postJson(String path, Map<String, dynamic> data) async {
    await ensureCsrf();
    final csrf = await _csrfToken();
    return _dio.post(
      path,
      data: data,
      options: Options(
        headers: _csrfHeaders(csrf),
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
  }

  Future<Response<dynamic>> getJson(String path) async {
    return _dio.get(
      path,
      options: Options(
        responseType: ResponseType.json,
      ),
    );
  }

  Future<Response<dynamic>> uploadText(String text) async {
    await ensureCsrf();
    final csrf = await _csrfToken();
    final formData = FormData.fromMap({"text": text});
    return _dio.post(
      "/upload/",
      data: formData,
      options: Options(
        headers: _csrfHeaders(csrf),
        contentType: "multipart/form-data",
        responseType: ResponseType.json,
      ),
    );
  }

  Future<Response<dynamic>> uploadFile(String filePath) async {
    await ensureCsrf();
    final csrf = await _csrfToken();
    final fileName = p.basename(filePath);
    final formData = FormData.fromMap({
      "file": await MultipartFile.fromFile(filePath, filename: fileName),
    });
    return _dio.post(
      "/upload/",
      data: formData,
      options: Options(
        headers: _csrfHeaders(csrf),
        contentType: "multipart/form-data",
        responseType: ResponseType.json,
      ),
    );
  }

  Future<Response<dynamic>> download() async {
    return _dio.get(
      "/download/",
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
  }
}
