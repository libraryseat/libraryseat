import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/seat_model.dart';
import '../utils/translations.dart';
import '../services/api_service.dart';
import 'login_page.dart';
import 'admin_page.dart';

class FloorMapPage extends StatefulWidget {
  const FloorMapPage({super.key, required this.onLocaleChange});

  final ValueChanged<Locale> onLocaleChange;

  @override
  State<FloorMapPage> createState() => _FloorMapPageState();
}

class _FloorMapPageState extends State<FloorMapPage> {
  int _selectedFloorIndex = 3;
  final ApiService _apiService = ApiService();
  bool _isAdmin = false;
  bool _loading = false;
  bool _useApiData = true; // 是否使用 API 数据，如果 API 失败则回退到硬编码数据

  // 从 API 获取的数据
  Map<String, List<SeatResponse>> _apiSeats = {};
  List<FloorResponse> _floors = [];

  // 硬编码的座位位置（因为后端不提供位置信息）
  static final Map<String, Map<String, Offset>> _seatPositions = {
    'F4': {
      'F4-01': const Offset(80, 100),
      'F4-02': const Offset(180, 100),
      'F4-03': const Offset(80, 200),
      'F4-04': const Offset(180, 200),
      'F4-05': const Offset(80, 350),
      'F4-06': const Offset(180, 350),
      'F4-07': const Offset(110, 500),
      'F4-08': const Offset(160, 500),
    },
    'F3': {
      'F3-01': const Offset(50, 120),
      'F3-02': const Offset(130, 120),
      'F3-03': const Offset(210, 120),
      'F3-04': const Offset(50, 250),
      'F3-05': const Offset(130, 250),
      'F3-06': const Offset(210, 250),
      'F3-07': const Offset(130, 400),
    },
    'F2': {
      // F2: 两排布局，每排2个座位，中间有圆桌
      'F2-01': const Offset(80, 450),   // 下排左（无电源）
      'F2-02': const Offset(320, 450),  // 下排右（有电源）
      'F2-03': const Offset(80, 250),  // 上排左（无电源）
      'F2-04': const Offset(320, 250),  // 上排右（无电源）
    },
    'F1': {
      'F1-01': const Offset(110, 100),
      'F1-02': const Offset(160, 100),
      'F1-03': const Offset(110, 200),
      'F1-04': const Offset(160, 200),
      'F1-05': const Offset(110, 250),
      'F1-06': const Offset(160, 250),
      'F1-07': const Offset(110, 350),
      'F1-08': const Offset(160, 350),
      'F1-09': const Offset(110, 500),
      'F1-10': const Offset(180, 550),
    },
  };

  // 硬编码的座位布局（作为后备数据）
  static final List<List<Seat>> _seatLayouts = const [
    [
      Seat(id: 'F4-01', status: 'empty', top: 100, left: 80),
      Seat(id: 'F4-02', status: 'empty', top: 100, left: 180),
      Seat(id: 'F4-03', status: 'occupied', top: 200, left: 80),
      Seat(id: 'F4-04', status: 'occupied', top: 200, left: 180),
      Seat(id: 'F4-05', status: 'empty', top: 350, left: 80),
      Seat(id: 'F4-06', status: 'has_power', top: 350, left: 180),
      Seat(id: 'F4-07', status: 'empty', top: 500, left: 110),
      Seat(id: 'F4-08', status: 'empty', top: 500, left: 160),
    ],
    [
      Seat(id: 'F3-01', status: 'has_power', top: 120, left: 50),
      Seat(id: 'F3-02', status: 'occupied', top: 120, left: 130),
      Seat(id: 'F3-03', status: 'has_power', top: 120, left: 210),
      Seat(id: 'F3-04', status: 'suspicious', top: 250, left: 50),
      Seat(id: 'F3-05', status: 'has_power', top: 250, left: 130),
      Seat(id: 'F3-06', status: 'occupied', top: 250, left: 210),
      Seat(id: 'F3-07', status: 'empty', top: 400, left: 130),
    ],
    [
      // F2: 两排布局，每排2个座位
      Seat(id: 'F2-01', status: 'empty', top: 450, left: 80),   // 下排左（无电源）
      Seat(id: 'F2-02', status: 'empty', top: 450, left: 320),  // 下排右（有电源）
      Seat(id: 'F2-03', status: 'empty', top: 250, left: 80),  // 上排左（无电源）
      Seat(id: 'F2-04', status: 'empty', top: 250, left: 320), // 上排右（无电源）
    ],
    [
      Seat(id: 'F1-01', status: 'occupied', top: 100, left: 110),
      Seat(id: 'F1-02', status: 'empty', top: 100, left: 160),
      Seat(id: 'F1-03', status: 'has_power', top: 200, left: 110),
      Seat(id: 'F1-04', status: 'empty', top: 200, left: 160),
      Seat(id: 'F1-05', status: 'suspicious', top: 250, left: 110),
      Seat(id: 'F1-06', status: 'suspicious', top: 250, left: 160),
      Seat(id: 'F1-07', status: 'occupied', top: 350, left: 110),
      Seat(id: 'F1-08', status: 'occupied', top: 350, left: 160),
      Seat(id: 'F1-09', status: 'empty', top: 500, left: 110),
      Seat(id: 'F1-10', status: 'occupied', top: 550, left: 180),
    ],
  ];

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _loadData();
  }

  Future<void> _checkUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role');
    setState(() {
      _isAdmin = role == 'admin';
    });
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // 获取楼层列表
      final floors = await _apiService.getFloors();

      // 获取所有楼层的座位
      final Map<String, List<SeatResponse>> seatsMap = {};
      for (var floor in floors) {
        try {
          final seats = await _apiService.getSeats(floor: floor.floorId);
          seatsMap[floor.floorId] = seats;
        } catch (e) {
          // 如果某个楼层获取失败，继续处理其他楼层
          print('Failed to load seats for ${floor.floorId}: $e');
        }
      }

      setState(() {
        _floors = floors;
        _apiSeats = seatsMap;
        _useApiData = true;
        _loading = false;
      });
    } catch (e) {
      // API 失败时回退到硬编码数据
      print('Failed to load data from API: $e');
      setState(() {
        _useApiData = false;
        _loading = false;
      });
    }
  }

  Future<void> _refreshCurrentFloor() async {
    final floorId = _getCurrentFloorId();
    setState(() => _loading = true);
    try {
      final seats = await _apiService.refreshFloor(floorId);
      setState(() {
        _apiSeats[floorId] = seats;
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('refresh_success') ?? '刷新成功')),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t('refresh_failed') ?? '刷新失败'}: $e')),
        );
      }
    }
  }

  String _getCurrentFloorId() {
    const floorIds = ['F4', 'F3', 'F2', 'F1'];
    return floorIds[_selectedFloorIndex];
  }

  String _getFloorLabel(String floorId) {
    const labels = {'F4': 'IV', 'F3': 'III', 'F2': 'II', 'F1': 'I'};
    return labels[floorId] ?? floorId;
  }

  List<FloorInfo> _buildFloorData() {
    if (_useApiData && _floors.isNotEmpty) {
      // 使用 API 数据
      return _floors.map((floor) {
        return FloorInfo(
          label: _getFloorLabel(floor.floorId),
          availableCount: floor.emptyCount,
          totalSeats: floor.totalCount,
        );
      }).toList();
    } else {
      // 使用硬编码数据
      const labels = ['IV', 'III', 'II', 'I'];
      return List.generate(_seatLayouts.length, (index) {
        final seats = _seatLayouts[index];
        final availableCount = seats.where(
          (seat) => seat.status == 'empty' || seat.status == 'has_power',
        ).length;
        return FloorInfo(
          label: labels[index],
          availableCount: availableCount,
          totalSeats: seats.length,
        );
      });
    }
  }

  List<Widget> _getTablesForCurrentFloor() {
    switch (_selectedFloorIndex) {
      case 0:
        return [
          Positioned(top: 140, left: 90, child: _buildTableRect(width: 120, height: 60)),
          Positioned(top: 240, left: 90, child: _buildTableRect(width: 120, height: 60)),
          Positioned(top: 390, left: 90, child: _buildTableRect(width: 120, height: 60)),
        ];
      case 1: // F2: 两排布局，每排2个座位，中间有圆桌
        return [
          // 上排长桌：位于上排两个座位前方（座位在top: 250，桌子在top: 200）
          Positioned(top: 200, left: 50, child: _buildTableRect(width: 120, height: 40)),
          Positioned(top: 200, left: 290, child: _buildTableRect(width: 120, height: 40)),
          // 下排长桌：位于下排两个座位前方（座位在top: 450，桌子在top: 400）
          Positioned(top: 400, left: 50, child: _buildTableRect(width: 120, height: 40)),
          Positioned(top: 400, left: 290, child: _buildTableRect(width: 120, height: 40)),
          // 中间圆桌：位于上下排之间，避免与长桌重叠
          Positioned(top: 320, left: 200, child: _buildTableCircle(size: 100)),
        ];
      case 2:
        return [
          Positioned(top: 240, left: 110, child: _buildTableCircle(size: 140)),
          Positioned(top: 480, left: 130, child: _buildTableCircle(size: 100)),
        ];
      case 3:
      default:
        return [
          Positioned(top: 140, left: 90, child: _buildTableRect(width: 120, height: 60)),
          Positioned(top: 400, left: 90, child: _buildTableRect(width: 120, height: 60)),
          Positioned(top: 550, left: 90, child: _buildTableCircle(size: 80)),
        ];
    }
  }

  String t(String key) {
    final locale = Localizations.localeOf(context);
    String languageCode = locale.languageCode;

    if (languageCode == 'zh') {
      languageCode = locale.countryCode == 'TW' ? 'zh_TW' : 'zh';
    }

    return AppTranslations.get(key, languageCode);
  }

  List<Seat> _getSeatsForCurrentFloor() {
    if (_useApiData) {
      // 使用 API 数据
      final floorId = _getCurrentFloorId();
      final apiSeats = _apiSeats[floorId] ?? [];
      final positions = _seatPositions[floorId] ?? {};

      return apiSeats.map((apiSeat) {
        final pos = positions[apiSeat.seatId] ?? const Offset(0, 0);
        return Seat.fromApiResponse(
          apiSeat,
          top: pos.dy,
          left: pos.dx,
          isAdmin: _isAdmin,
        );
      }).where((seat) {
        // 如果不是管理员，过滤掉 suspicious 状态的座位（黄色异常座位）
        if (!_isAdmin && seat.status == 'suspicious') {
          return false;
        }
        return true;
      }).toList();
    } else {
      // 使用硬编码数据
      final seats = _seatLayouts[_selectedFloorIndex];
      // 如果不是管理员，过滤掉 suspicious 状态的座位（黄色异常座位）
      if (!_isAdmin) {
        return seats.where((seat) => seat.status != 'suspicious').toList();
      }
      return seats;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSeats = _getSeatsForCurrentFloor();
    final currentTables = _getTablesForCurrentFloor();

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _buildSidebar(),
            Expanded(
              child: Stack(
                children: [
                  InteractiveViewer(
                    boundaryMargin: const EdgeInsets.all(20),
                    minScale: 0.5,
                    maxScale: 3.0,
                    child: Container(
                      color: Colors.transparent,
                      width: 600,
                      height: 800,
                      child: Stack(
                        children: [
                          ...currentTables,
                          ...currentSeats.map(
                            (seat) => Positioned(
                              key: ValueKey(seat.id),
                              top: seat.top,
                              left: seat.left,
                              child: _buildSeatIcon(seat),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 20,
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.settings, color: Colors.grey, size: 30),
                      offset: const Offset(0, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      color: Colors.white,
                      constraints: const BoxConstraints(minWidth: 180),
                      onSelected: (value) {
                        if (value == 'refresh') {
                          _refreshCurrentFloor();
                        } else if (value == 'language') {
                          _showLanguageDialog();
                        } else if (value == 'admin') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdminPage(onLocaleChange: widget.onLocaleChange),
                            ),
                          );
                        } else if (value == 'logout') {
                          _showLogoutDialog();
                        }
                      },
                      itemBuilder: (context) => [
                        if (_useApiData)
                          PopupMenuItem(
                            value: 'refresh',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.refresh, color: Colors.black54, size: 20),
                                const SizedBox(width: 12),
                                Text(
                                  t('refresh') ?? '刷新',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        if (_useApiData) const PopupMenuDivider(),
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
                        if (_isAdmin) const PopupMenuDivider(),
                        if (_isAdmin)
                          PopupMenuItem(
                            value: 'admin',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.admin_panel_settings, color: Colors.black54, size: 20),
                                const SizedBox(width: 12),
                                Text(
                                  t('admin'),
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
                  if (_loading)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.3),
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(t('language'), textAlign: TextAlign.center),
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
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      onTap: () {
        widget.onLocaleChange(locale);
        Navigator.pop(context);
      },
    );
  }

  void _showLogoutDialog() {
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
              // Clear login session
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('token');
              await prefs.remove('username');
              await prefs.remove('role');
              // Navigate back to login page
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => LoginPage(onLocaleChange: widget.onLocaleChange),
                  ),
                  (route) => false,
                );
              }
            },
            child: Text(t('confirm')),
          ),
        ],
      ),
    );
  }

  // 显示座位详情对话框
  // 注意：所有用户（包括管理员）都可以举报座位
  void _showSeatDetailDialog(Seat seat) {
    final statusKey = 'status_${seat.status}';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(t('seat_info'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close, color: Colors.black54), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 15),
            _buildInfoRow("ID:", seat.id),
            _buildInfoRow("${t('floor')}:", _buildFloorData()[_selectedFloorIndex].label),
            _buildInfoRow("${t('status')}:", t(statusKey), color: seat.color),
            const SizedBox(height: 25),
            // 举报按钮：所有用户（包括管理员）都可以使用
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.reportButton,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.report_problem_outlined),
                label: Text(t('report_issue'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.pop(context);
                  _showReportDialog(seat);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportDialog(Seat seat) {
    final controller = TextEditingController();
    bool _submitting = false;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.dialogBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t('report_title'), style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close, color: Colors.black54), onPressed: () => Navigator.pop(context)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("ID: ${seat.id}", style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 15),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.5),
                    labelText: t('desc_label'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    hintText: t('desc_hint'),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 15),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white54),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.camera_alt, color: Colors.black45, size: 30),
                      const SizedBox(height: 5),
                      Text(t('upload_photo'), style: const TextStyle(color: Colors.black45)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.confirmButton,
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _submitting ? null : () async {
                  setDialogState(() => _submitting = true);
                  try {
                    final prefs = await SharedPreferences.getInstance();
                    final userId = prefs.getInt('user_id');
                    if (userId == null) {
                      throw Exception('User ID not found');
                    }
                    await _apiService.submitReport(
                      seatId: seat.id,
                      reporterId: userId,
                      text: controller.text.trim().isEmpty ? null : controller.text.trim(),
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(t('success_msg')),
                          backgroundColor: AppColors.green,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                      // 刷新当前楼层数据
                      _loadData();
                    }
                  } catch (e) {
                    setDialogState(() => _submitting = false);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to submit report: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
                      )
                    : Text(t('submit'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
          const SizedBox(width: 10),
          Text(value, style: TextStyle(color: color ?? Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 80,
      color: Colors.transparent,
      child: Column(
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.arrow_drop_down, size: 40, color: Colors.grey),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: _buildFloorData().length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final floorData = _buildFloorData();
                final isSelected = index == _selectedFloorIndex;
                return GestureDetector(
                  onTap: () => setState(() => _selectedFloorIndex = index),
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: floorData[index].color,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            if (isSelected)
                              const BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 4)),
                            const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                floorData[index].label,
                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                "${floorData[index].availableCount}",
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (isSelected) const CircleAvatar(backgroundColor: Colors.black54, radius: 3),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeatIcon(Seat seat) {
    return GestureDetector(
      onTap: () => _showSeatDetailDialog(seat),
      child: Icon(
        Icons.chair,
        color: seat.color,
        size: 36,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 3,
            offset: const Offset(1, 1),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRect({double width = 120, double height = 60}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.5), width: 2),
      ),
    );
  }

  Widget _buildTableCircle({double size = 80}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.3),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.withValues(alpha: 0.5), width: 2),
      ),
    );
  }
}

