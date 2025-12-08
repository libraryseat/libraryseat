import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http_parser/http_parser.dart';
import '../config/api_config.dart';

class ApiService {
  late final Dio _dio;

  ApiService() {
    _initDio();
  }

  void _initDio() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));

    // 添加 token 拦截器
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  // 获取座位列表
  Future<List<SeatResponse>> getSeats({String? floor}) async {
    final response = await _dio.get('/seats', queryParameters: {
      if (floor != null) 'floor': floor,
    });
    return (response.data as List)
        .map((json) => SeatResponse.fromJson(json))
        .toList();
  }

  // 获取楼层列表
  Future<List<FloorResponse>> getFloors() async {
    final response = await _dio.get('/floors');
    return (response.data as List)
        .map((json) => FloorResponse.fromJson(json))
        .toList();
  }

  // 刷新楼层
  Future<List<SeatResponse>> refreshFloor(String floor) async {
    // 刷新操作需要更长的超时时间（YOLO检测可能需要30秒以上）
    final response = await _dio.post(
      '/floors/$floor/refresh',
      options: Options(
        receiveTimeout: const Duration(seconds: 60), // 设置为60秒
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    return (response.data as List)
        .map((json) => SeatResponse.fromJson(json))
        .toList();
  }

  // 获取异常列表（管理员）
  Future<List<AnomalyResponse>> getAnomalies({String? floor}) async {
    final response = await _dio.get('/admin/anomalies', queryParameters: {
      if (floor != null) 'floor': floor,
    });
    return (response.data as List)
        .map((json) => AnomalyResponse.fromJson(json))
        .toList();
  }

  // 确认/切换异常状态（管理员）
  Future<AnomalyResponse> confirmAnomaly(int reportId) async {
    final response = await _dio.post('/admin/reports/$reportId/confirm');
    return AnomalyResponse.fromJson(response.data);
  }

  // 清除异常（管理员）
  Future<AnomalyResponse> clearAnomaly(String seatId) async {
    final response = await _dio.delete('/admin/anomalies/$seatId');
    return AnomalyResponse.fromJson(response.data);
  }

  // 获取报告详情（管理员）
  Future<ReportResponse> getReport(int reportId) async {
    final response = await _dio.get('/admin/reports/$reportId');
    return ReportResponse.fromJson(response.data);
  }

  // 锁定座位（管理员）
  Future<SeatResponse> lockSeat(String seatId, {int minutes = 5}) async {
    final response = await _dio.post('/admin/seats/$seatId/lock', queryParameters: {'minutes': minutes});
    return SeatResponse.fromJson(response.data);
  }

  // 用户登出
  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } catch (e) {
      // 即使登出接口失败，也继续清除本地 token
      debugPrint('Logout API call failed: $e');
    }
  }

  // 提交举报
  Future<ReportResponse> submitReport({
    required String seatId,
    required int reporterId,
    String? text,
    List<XFile>? images,
    ProgressCallback? onSendProgress,
  }) async {
    debugPrint('DEBUG submitReport: seatId=$seatId, reporterId=$reporterId');
    debugPrint('DEBUG submitReport: text=$text');
    debugPrint('DEBUG submitReport: images=${images?.length ?? 0}');
    
    final formData = FormData();
    formData.fields.addAll([
      MapEntry('seat_id', seatId),
      MapEntry('reporter_id', reporterId.toString()),
    ]);
    if (text != null && text.isNotEmpty) {
      formData.fields.add(MapEntry('text', text));
    }
    
    if (images != null && images.isNotEmpty) {
      debugPrint('DEBUG submitReport: Processing ${images.length} image(s)...');
      for (var idx = 0; idx < images.length; idx++) {
        final image = images[idx];
        debugPrint('DEBUG submitReport: Image[$idx] - name=${image.name}, path=${image.path}');
        
        try {
          final bytes = await image.readAsBytes();
          debugPrint('DEBUG submitReport: Image[$idx] - size=${bytes.length} bytes');
          
          // Determine mime type based on extension
          MediaType contentType = MediaType('image', 'jpeg'); // default
          final name = image.name.toLowerCase();
          if (name.endsWith('.png')) {
            contentType = MediaType('image', 'png');
          } else if (name.endsWith('.gif')) {
            contentType = MediaType('image', 'gif');
          } else if (name.endsWith('.webp')) {
            contentType = MediaType('image', 'webp');
          }
          
          debugPrint('DEBUG submitReport: Image[$idx] - contentType=${contentType.toString()}');

          formData.files.add(MapEntry(
            'images',
            MultipartFile.fromBytes(
              bytes, 
              filename: image.name,
              contentType: contentType,
            ),
          ));
          debugPrint('DEBUG submitReport: Image[$idx] added to formData');
        } catch (e) {
          debugPrint('ERROR submitReport: Failed to process image[$idx]: $e');
          rethrow;
        }
      }
      debugPrint('DEBUG submitReport: Total files in formData: ${formData.files.length}');
    } else {
      debugPrint('DEBUG submitReport: No images to upload');
    }
    
    try {
      debugPrint('DEBUG submitReport: Sending POST request to /reports');
      final response = await _dio.post(
        '/reports',
        data: formData,
        onSendProgress: onSendProgress,
      );
      debugPrint('DEBUG submitReport: Response status: ${response.statusCode}');
      debugPrint('DEBUG submitReport: Response data: ${response.data}');
      return ReportResponse.fromJson(response.data);
    } catch (e) {
      debugPrint('ERROR submitReport: Request failed: $e');
      rethrow;
    }
  }
}

// API 响应模型
class SeatResponse {
  final String seatId;
  final String floorId;
  final bool hasPower;
  final bool isEmpty;
  final bool isReported;
  final bool isMalicious;
  final int lockUntilTs;
  final String seatColor;
  final String adminColor;

  SeatResponse({
    required this.seatId,
    required this.floorId,
    required this.hasPower,
    required this.isEmpty,
    required this.isReported,
    required this.isMalicious,
    required this.lockUntilTs,
    required this.seatColor,
    required this.adminColor,
  });

  factory SeatResponse.fromJson(Map<String, dynamic> json) {
    return SeatResponse(
      seatId: json['seat_id'] as String,
      floorId: json['floor_id'] as String,
      hasPower: json['has_power'] as bool,
      isEmpty: json['is_empty'] as bool,
      isReported: json['is_reported'] as bool,
      isMalicious: json['is_malicious'] as bool,
      lockUntilTs: json['lock_until_ts'] as int,
      seatColor: json['seat_color'] as String,
      adminColor: json['admin_color'] as String,
    );
  }
}

class FloorResponse {
  final String floorId;
  final int emptyCount;
  final int totalCount;
  final String floorColor;

  FloorResponse({
    required this.floorId,
    required this.emptyCount,
    required this.totalCount,
    required this.floorColor,
  });

  factory FloorResponse.fromJson(Map<String, dynamic> json) {
    return FloorResponse(
      floorId: json['floor_id'] as String,
      emptyCount: json['empty_count'] as int,
      totalCount: json['total_count'] as int,
      floorColor: json['floor_color'] as String,
    );
  }
}

class AnomalyResponse {
  final String seatId;
  final String floorId;
  final bool hasPower;
  final bool isEmpty;
  final bool isReported;
  final bool isMalicious;
  final String seatColor;
  final String adminColor;
  final int? lastReportId;

  AnomalyResponse({
    required this.seatId,
    required this.floorId,
    required this.hasPower,
    required this.isEmpty,
    required this.isReported,
    required this.isMalicious,
    required this.seatColor,
    required this.adminColor,
    this.lastReportId,
  });

  factory AnomalyResponse.fromJson(Map<String, dynamic> json) {
    return AnomalyResponse(
      seatId: json['seat_id'] as String,
      floorId: json['floor_id'] as String,
      hasPower: json['has_power'] as bool,
      isEmpty: json['is_empty'] as bool,
      isReported: json['is_reported'] as bool,
      isMalicious: json['is_malicious'] as bool,
      seatColor: json['seat_color'] as String,
      adminColor: json['admin_color'] as String,
      lastReportId: json['last_report_id'] as int?,
    );
  }
}

class ReportResponse {
  final int id;
  final String seatId;
  final int reporterId;
  final String? text;
  final List<String> images;
  final String status;
  final int createdAt;

  ReportResponse({
    required this.id,
    required this.seatId,
    required this.reporterId,
    this.text,
    required this.images,
    required this.status,
    required this.createdAt,
  });

  factory ReportResponse.fromJson(Map<String, dynamic> json) {
    return ReportResponse(
      id: json['id'] as int,
      seatId: json['seat_id'] as String,
      reporterId: json['reporter_id'] as int,
      text: json['text'] as String?,
      images: (json['images'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      status: json['status'] as String,
      createdAt: json['created_at'] as int,
    );
  }
}
