import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../services/api_service.dart';
import '../utils/translations.dart';
import '../models/seat_model.dart';
import '../config/api_config.dart';
import 'login_page.dart';
import 'floor_map_page.dart';

// 管理员界面颜色常量
class AdminColors {
  // 页面背景：#f3f1f8
  static const pageBackground = Color(0xFFF3F1F8);
  // 列表信息背景颜色：#fdfdfe
  static const listItemBackground = Color(0xFFFDFDFE);
  // setting 齿轮外层圈颜色：#98989d
  static const settingCircle = Color(0xFF98989D);
  // setting 齿轮颜色：#464646
  static const settingIcon = Color(0xFF464646);
  // 勾选提示信息后，左侧圆圈内的颜色：#7fdbca
  static const checkActive = Color(0xFF7FDBCA);
  // 删除按钮填充颜色：#ef949e
  static const deleteButton = Color(0xFFEF949E);
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.onLocaleChange});

  final ValueChanged<Locale> onLocaleChange;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final Dio _dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
  List<AnomalyResponse> _anomalies = [];
  List<AnomalyResponse> _filteredAnomalies = [];
  Set<String> _selectedSeats = {};
  bool _loading = false;
  Locale _currentLocale = const Locale('en');

  @override
  void initState() {
    super.initState();
    _initDio();
    _loadAnomalies();
  }

  void _initDio() {
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAnomalies() async {
    setState(() => _loading = true);
    try {
      final anomalies = await _apiService.getAnomalies();
      // 按楼层排序（F1, F2, F3, F4）
      anomalies.sort((a, b) => a.floorId.compareTo(b.floorId));
      setState(() {
        _anomalies = anomalies;
        _filteredAnomalies = anomalies;
        _selectedSeats = anomalies
            .where((a) => a.isMalicious)
            .map((a) => a.seatId)
            .toSet()
            .cast<String>();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load anomalies: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  void _filterAnomalies(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredAnomalies = _anomalies;
      } else {
        _filteredAnomalies = _anomalies.where((anomaly) {
          final seatId = anomaly.seatId.toLowerCase();
          final floorId = anomaly.floorId.toLowerCase();
          final searchLower = query.toLowerCase();
          return seatId.contains(searchLower) || floorId.contains(searchLower);
        }).toList();
      }
    });
  }

  Future<void> _toggleAnomaly(AnomalyResponse anomaly) async {
    if (anomaly.lastReportId == null) return;

    setState(() => _loading = true);
    try {
      final updated = await _apiService.confirmAnomaly(anomaly.lastReportId!);
      // 确认异常后自动上锁5分钟
      await _apiService.lockSeat(anomaly.seatId, minutes: 5);
      // 更新列表中的异常
      setState(() {
        final index = _anomalies.indexWhere((a) => a.seatId == anomaly.seatId);
        if (index != -1) {
          _anomalies[index] = updated;
        }
        _filterAnomalies(_searchController.text);
        _selectedSeats = _anomalies
            .where((a) => a.isMalicious)
            .map((a) => a.seatId)
            .toSet()
            .cast<String>();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Anomaly confirmed and seat locked for 5 minutes')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update anomaly: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteAnomaly(AnomalyResponse anomaly) async {
    setState(() => _loading = true);
    try {
      await _apiService.clearAnomaly(anomaly.seatId);
      // 从列表中移除
      setState(() {
        _anomalies.removeWhere((a) => a.seatId == anomaly.seatId);
        _filterAnomalies(_searchController.text);
        _selectedSeats.remove(anomaly.seatId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Anomaly cleared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete anomaly: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _lockSeat(AnomalyResponse anomaly) async {
    String t(String key) => AppTranslations.get(key, _currentLocale.languageCode);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(t('lock_seat')),
        content: Text(t('lock_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('cancel'), style: const TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.confirmButton,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('confirm')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      await _apiService.lockSeat(anomaly.seatId, minutes: 5);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seat locked for 5 minutes')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to lock seat: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _showReportDetails(AnomalyResponse anomaly) async {
    if (anomaly.lastReportId == null) {
      // 如果没有报告，只显示基本信息
      if (!mounted) return;
      _showAnomalyInfoDialog(anomaly);
      return;
    }

    setState(() => _loading = true);
    try {
      final report = await _apiService.getReport(anomaly.lastReportId!);
      if (!mounted) return;
      _showReportDetailDialog(anomaly, report);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load report details: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showAnomalyInfoDialog(AnomalyResponse anomaly) {
    String t(String key) => AppTranslations.get(key, _currentLocale.languageCode);
    final floorName = _getFloorName(anomaly.floorId);
    final seatNumber = anomaly.seatId.split('-').last;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(t('report_details')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(t('floor'), floorName),
            _buildInfoRow(t('seat_number'), seatNumber),
            _buildInfoRow(t('status'), anomaly.isMalicious ? t('status_suspicious') : t('status_occupied')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('confirm')),
          ),
        ],
      ),
    );
  }

  void _showReportDetailDialog(AnomalyResponse anomaly, ReportResponse report) {
    String t(String key) => AppTranslations.get(key, _currentLocale.languageCode);
    final floorName = _getFloorName(anomaly.floorId);
    final seatNumber = anomaly.seatId.split('-').last;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(t('report_details')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow(t('floor'), floorName),
              _buildInfoRow(t('seat_number'), seatNumber),
              if (report.text != null && report.text!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(t('report_text'), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(report.text!, style: const TextStyle(fontSize: 14)),
              ],
              if (report.images.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(t('report_images'), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: report.images.length,
                    itemBuilder: (context, index) {
                      final imagePath = report.images[index];
                      final imageUrl = '${ApiConfig.baseUrl}/$imagePath';
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Image.network(
                          imageUrl,
                          width: 200,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 200,
                              color: Colors.grey[300],
                              child: const Icon(Icons.broken_image),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text(t('no_images'), style: TextStyle(color: Colors.grey[600])),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // 跳转到楼层地图
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FloorMapPage(onLocaleChange: widget.onLocaleChange),
                ),
              );
            },
            child: Text(t('go_to_floor_map')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('confirm')),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  String _getFloorName(String floorId) {
    String t(String key) => AppTranslations.get(key, _currentLocale.languageCode);
    switch (floorId) {
      case 'F1':
        return t('first_floor');
      case 'F2':
        return t('second_floor');
      case 'F3':
        return t('third_floor');
      case 'F4':
        return t('fourth_floor');
      default:
        return floorId;
    }
  }

  String _getAnomalyDescription(AnomalyResponse anomaly) {
    String t(String key) => AppTranslations.get(key, _currentLocale.languageCode);
    final floorName = _getFloorName(anomaly.floorId);
    final seatNumber = anomaly.seatId.split('-').last;
    if (anomaly.isReported) {
      return 'Report: Seat $seatNumber, $floorName, ${t('seat_occupation')}';
    } else {
      return 'Seat $seatNumber, $floorName, ${t('suspected_seat_occupation')}';
    }
  }

  // 删除确认对话框
  Future<bool?> _showDeleteConfirmationDialog(AnomalyResponse anomaly) async {
    String t(String key) => AppTranslations.get(key, _currentLocale.languageCode);
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.dialogBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.help_outline,
                color: Color(0xFFFF9800),
                size: 48.0,
              ),
              const SizedBox(height: 16),
              Text(
                'Are you sure you want to clear this anomaly?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade600,
                      minimumSize: const Size(120, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(t('cancel')),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.deleteButton,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(120, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(t('confirm')),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppTranslations.get('language', _currentLocale.languageCode)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLangOption('English', const Locale('en')),
            const Divider(),
            _buildLangOption('简体中文', const Locale('zh', 'CN')),
            const Divider(),
            _buildLangOption('繁體中文', const Locale('zh', 'TW')),
          ],
        ),
      ),
    );
  }

  Widget _buildLangOption(String label, Locale locale) {
    return ListTile(
      title: Text(label),
      onTap: () {
        setState(() => _currentLocale = locale);
        widget.onLocaleChange(locale);
        Navigator.pop(context);
      },
    );
  }

  void _showLogoutDialog() {
    String t(String key) => AppTranslations.get(key, _currentLocale.languageCode);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(t('logout')),
        content: Text(t('logout_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('cancel'), style: const TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.confirmButton,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(context);
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('token');
              await prefs.remove('username');
              await prefs.remove('role');
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => LoginPage(onLocaleChange: widget.onLocaleChange),
                ),
                (route) => false,
              );
            },
            child: Text(t('confirm')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppTranslations.get(key, _currentLocale.languageCode);
    return Scaffold(
      backgroundColor: AdminColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AdminColors.pageBackground,
        surfaceTintColor: AdminColors.pageBackground,
        elevation: 0,
        centerTitle: false,
        title: Text(
          t('admin'),
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: AdminColors.settingCircle.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: PopupMenuButton<String>(
              icon: Icon(
                Icons.settings,
                color: AdminColors.settingIcon,
                size: 24,
              ),
              offset: const Offset(0, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: Colors.white,
              constraints: const BoxConstraints(minWidth: 180),
              onSelected: (value) {
                if (value == 'refresh') {
                  _loadAnomalies();
                } else if (value == 'language') {
                  _showLanguageDialog();
                } else if (value == 'floor_map') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FloorMapPage(onLocaleChange: widget.onLocaleChange),
                    ),
                  );
                } else if (value == 'logout') {
                  _showLogoutDialog();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'refresh',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.refresh, color: Colors.black54, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        t('refresh'),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'language',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.language, color: Colors.black54, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        t('language'),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'floor_map',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.map, color: Colors.black54, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        t('floor_map'),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.logout, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        t('logout'),
                        style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              onChanged: _filterAnomalies,
              decoration: InputDecoration(
                hintText: t('search'),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: AdminColors.listItemBackground,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // 异常列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredAnomalies.isEmpty
                    ? Center(
                        child: Text(
                          t('no_anomalies'),
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 8.0),
                        itemCount: _filteredAnomalies.length,
                        itemBuilder: (context, index) {
                          final anomaly = _filteredAnomalies[index];
                          final isSelected = _selectedSeats.contains(anomaly.seatId);
                          // 使用 Dismissible 实现左滑删除
                          return Dismissible(
                            key: ValueKey(anomaly.seatId),
                            direction: DismissDirection.endToStart,
                            // 背景：显示删除按钮
                            background: Container(
                              color: Colors.transparent,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AdminColors.deleteButton,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.delete_forever, color: Colors.white, size: 24),
                                    const SizedBox(width: 8),
                                    Text(
                                      t('delete'),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            confirmDismiss: (direction) async {
                              if (direction == DismissDirection.endToStart) {
                                final confirmed = await _showDeleteConfirmationDialog(anomaly);
                                return confirmed ?? false;
                              }
                              return false;
                            },
                            onDismissed: (direction) {
                              if (direction == DismissDirection.endToStart) {
                                _deleteAnomaly(anomaly);
                              }
                            },
                            // 列表项内容
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                              child: Material(
                                elevation: 2,
                                shadowColor: Colors.black12,
                                borderRadius: BorderRadius.circular(15),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  tileColor: AdminColors.listItemBackground,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  // 左侧的勾选框
                                  leading: GestureDetector(
                                    onTap: () => _toggleAnomaly(anomaly),
                                    child: Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelected
                                            ? AdminColors.checkActive
                                            : Colors.grey.shade300,
                                        border: Border.all(
                                          color: isSelected
                                              ? AdminColors.checkActive
                                              : Colors.grey.shade500,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: isSelected
                                          ? const Icon(
                                              Icons.check,
                                              color: Colors.white,
                                              size: 20,
                                            )
                                          : null,
                                    ),
                                  ),
                                  // 主要信息
                                  title: Text(
                                    _getAnomalyDescription(anomaly),
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  // 右侧上锁按钮
                                  trailing: IconButton(
                                    icon: const Icon(Icons.lock, size: 20),
                                    color: Colors.grey.shade600,
                                    onPressed: () => _lockSeat(anomaly),
                                    tooltip: t('lock_seat'),
                                  ),
                                  // 点击列表项显示详情
                                  onTap: () => _showReportDetails(anomaly),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
