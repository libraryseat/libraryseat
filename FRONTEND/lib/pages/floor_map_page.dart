import 'dart:async';
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
  int _selectedFloorIndex = 0; // 默认显示第一层（F1）
  final ApiService _apiService = ApiService();
  bool _isAdmin = false;
  bool _loading = false;
  bool _useApiData = true; // 是否使用 API 数据，如果 API 失败则回退到硬编码数据

  // 从 API 获取的数据
  Map<String, List<SeatResponse>> _apiSeats = {};
  List<FloorResponse> _floors = [];
  
  // 定时刷新器
  Timer? _refreshTimer;
  
  // 伪数据定时器（用于F3和F4的演示数据）
  Timer? _mockDataTimer;
  
  // F3和F4的伪数据状态
  List<Seat> _mockF3Seats = [];
  List<Seat> _mockF4Seats = [];

  // 硬编码的座位位置（因为后端不提供位置信息）
  // 注意：座位位置是椅子图标的中心点，桌子位置需要避开座位
  static final Map<String, Map<String, Offset>> _seatPositions = {
    'F1': {
      // F1: 2x2 网格布局，保持原设定
      'F1-01': const Offset(100, 400),  // 左下（无电源）
      'F1-02': const Offset(250, 400),  // 右下（有电源）
      'F1-03': const Offset(100, 200),  // 左上（无电源）
      'F1-04': const Offset(250, 200),  // 右上（有电源）
    },
    'F2': {
      // F2: 两排布局，每排2个座位，中间有圆桌
      'F2-01': const Offset(80, 450),   // 下排左（无电源）
      'F2-02': const Offset(320, 450), // 下排右（有电源）
      'F2-03': const Offset(80, 250),  // 上排左（无电源）
      'F2-04': const Offset(320, 250), // 上排右（无电源）
    },
    'F3': {
      // F3: 重新规划，6个座位，L型布局 + 中间区域
      'F3-01': const Offset(120, 150),   // 左上
      'F3-02': const Offset(420, 150),  // 右上
      'F3-03': const Offset(120, 300),   // 左中
      'F3-04': const Offset(420, 300),   // 右中
      'F3-05': const Offset(120, 500),   // 左下
      'F3-06': const Offset(420, 500),  // 右下
      'F3-07': const Offset(270, 350),  // 中间独立座位
    },
    'F4': {
      // F4: 重新规划，8个座位，对称布局
      'F4-01': const Offset(120, 120),   // 左上1
      'F4-02': const Offset(270, 120),  // 左上2
      'F4-03': const Offset(420, 120),  // 左上3
      'F4-04': const Offset(120, 280),   // 左中1
      'F4-05': const Offset(420, 280),  // 右中1
      'F4-06': const Offset(120, 480),   // 左下1
      'F4-07': const Offset(270, 480),  // 左下2
      'F4-08': const Offset(420, 480),  // 右下1
    },
  };

  // 硬编码的座位布局（作为后备数据）
  // 顺序：F1(一楼), F2(二楼), F3(三楼), F4(四楼)
  static final List<List<Seat>> _seatLayouts = const [
    [
      // F1: 左边（01, 03）无电源，右边（02, 04）有电源
      Seat(id: 'F1-01', status: 'empty', top: 400, left: 230),  // 左下（无电源）
      Seat(id: 'F1-02', status: 'empty', top: 400, left: 380),  // 右下（有电源）
      Seat(id: 'F1-03', status: 'empty', top: 200, left: 230),  // 左上（无电源）
      Seat(id: 'F1-04', status: 'empty', top: 200, left: 380),  // 右上（有电源）
    ],
    [
      // F2: 两排布局，每排2个座位
      Seat(id: 'F2-01', status: 'empty', top: 450, left: 210),   // 下排左（无电源）
      Seat(id: 'F2-02', status: 'empty', top: 450, left: 450),  // 下排右（有电源）
      Seat(id: 'F2-03', status: 'empty', top: 250, left: 210),  // 上排左（无电源）
      Seat(id: 'F2-04', status: 'empty', top: 250, left: 450), // 上排右（无电源）
    ],
    [
      // F3: 6个座位，L型布局 + 右侧独立座位，优化布局
      Seat(id: 'F3-01', status: 'has_power', top: 150, left: 120), // 左上
      Seat(id: 'F3-02', status: 'occupied', top: 150, left: 420),  // 右上
      Seat(id: 'F3-03', status: 'has_power', top: 300, left: 120), // 左中
      Seat(id: 'F3-04', status: 'suspicious', top: 300, left: 420, previousStatus: 'occupied'), // 右中
      Seat(id: 'F3-05', status: 'has_power', top: 500, left: 120), // 左下
      Seat(id: 'F3-06', status: 'occupied', top: 500, left: 420),  // 右下
      Seat(id: 'F3-07', status: 'empty', top: 350, left: 270),     // 独立座位居中，位置下移
    ],
    [
      // F4: 8个座位，对称布局，优化布局
      Seat(id: 'F4-01', status: 'empty', top: 120, left: 120),     // 左上
      Seat(id: 'F4-02', status: 'has_power', top: 120, left: 270), // 中上（居中）
      Seat(id: 'F4-03', status: 'occupied', top: 120, left: 420),  // 右上
      Seat(id: 'F4-04', status: 'has_power', top: 280, left: 120), // 左中
      Seat(id: 'F4-05', status: 'empty', top: 280, left: 420),     // 右中
      Seat(id: 'F4-06', status: 'occupied', top: 480, left: 120),  // 左下
      Seat(id: 'F4-07', status: 'has_power', top: 480, left: 270), // 中下（居中）
      // F4-08初始为suspicious，设置previousStatus为occupied（假设举报前是被占用的）
      Seat(id: 'F4-08', status: 'suspicious', top: 480, left: 420, previousStatus: 'occupied'), // 右下
    ],
  ];

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _loadData();
    // 启动定时刷新，每5秒刷新一次
    _startAutoRefresh();
    // 初始化并启动伪数据定时器（F3和F4）
    _initializeMockData();
    _startMockDataTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mockDataTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    // 前端每2秒刷新一次，确保能快速看到后端8秒更新的结果
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_useApiData && mounted) {
        _silentRefresh(); // 静默刷新，不显示loading
      }
    });
  }

  // 静默刷新：只刷新当前楼层的座位数据，不显示loading状态
  Future<void> _silentRefresh() async {
    if (!_useApiData || _floors.isEmpty) return;
    
    try {
      // 只刷新当前楼层的座位数据
      final floorId = _getCurrentFloorId();
      final seats = await _apiService.getSeats(floor: floorId);
      
      // 检查数据是否有变化
      final currentSeats = _apiSeats[floorId];
      bool hasChanges = currentSeats == null || _hasSeatChanges(currentSeats, seats);
      
      // 总是更新UI以确保状态同步（即使数据看起来没变化，也可能有细微差异）
      if (mounted) {
        setState(() {
          _apiSeats[floorId] = seats;
        });
      }
      
      // 同时更新楼层统计信息（静默）- 总是更新，因为统计可能变化
      final floors = await _apiService.getFloors();
      if (mounted) {
        setState(() {
          _floors = floors;
        });
      }
    } catch (e) {
      // 静默失败，不显示错误提示，避免打扰用户
      print('Silent refresh failed: $e');
    }
  }

  // 初始化F3和F4的伪数据
  void _initializeMockData() {
    // F3: 7个座位，全部占用（灰色，0个空座位）
    _mockF3Seats = [
      Seat(id: 'F3-01', status: 'occupied', top: 150, left: 120),
      Seat(id: 'F3-02', status: 'occupied', top: 150, left: 420),
      Seat(id: 'F3-03', status: 'occupied', top: 300, left: 120),
      Seat(id: 'F3-04', status: 'occupied', top: 300, left: 420),
      Seat(id: 'F3-05', status: 'occupied', top: 500, left: 120),
      Seat(id: 'F3-06', status: 'occupied', top: 500, left: 420),
      Seat(id: 'F3-07', status: 'occupied', top: 350, left: 270),
    ];
    
    // F4: 8个座位，初始状态
    _mockF4Seats = [
      Seat(id: 'F4-01', status: 'has_power', top: 120, left: 120),
      Seat(id: 'F4-02', status: 'occupied', top: 120, left: 270),
      Seat(id: 'F4-03', status: 'empty', top: 120, left: 420),
      Seat(id: 'F4-04', status: 'occupied', top: 280, left: 120),
      Seat(id: 'F4-05', status: 'has_power', top: 280, left: 420),
      Seat(id: 'F4-06', status: 'empty', top: 480, left: 120),
      Seat(id: 'F4-07', status: 'has_power', top: 480, left: 270),
      // F4-08初始为suspicious，设置previousStatus为occupied（假设举报前是被占用的）
      Seat(id: 'F4-08', status: 'suspicious', top: 480, left: 420, previousStatus: 'occupied'),
    ];
  }

  // 启动伪数据定时器，每10秒改变一次状态
  void _startMockDataTimer() {
    _mockDataTimer?.cancel();
    _mockDataTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _updateMockData();
      }
    });
  }

  // 更新伪数据：随机改变座位状态
  void _updateMockData() {
    final random = DateTime.now().millisecondsSinceEpoch;
    
    // 更新F3座位状态：F3始终保持全占用（灰色）
    _mockF3Seats = _mockF3Seats.map((seat) {
      // F3楼层所有座位始终保持为 occupied（全占用）
      return Seat(
        id: seat.id,
        status: 'occupied', // F3强制全占用
        top: seat.top,
        left: seat.left,
      );
    }).toList();
    
    // 更新F4座位状态（但跳过已经被管理员处理过的座位）
    _mockF4Seats = _mockF4Seats.map((seat) {
      // 如果座位已经被管理员确认或删除（不再是suspicious），保持当前状态
      if (seat.status != 'suspicious') {
        return seat; // 保持管理员操作后的状态
      }
      final newStatus = _getRandomStatus(seat.id, random);
      return Seat(
        id: seat.id,
        status: newStatus,
        top: seat.top,
        left: seat.left,
      );
    }).toList();
    
    // 如果当前显示的是F3或F4，更新UI
    final floorId = _getCurrentFloorId();
    if (floorId == 'F3' || floorId == 'F4') {
      if (mounted) {
        setState(() {
          // 触发UI更新
        });
      }
    }
  }

  // 更新伪数据中特定座位的状态（用于举报后更新状态）
  void _updateMockSeatStatus(String seatId, String newStatus) {
    if (seatId.startsWith('F3')) {
      // 更新F3的伪数据
      final index = _mockF3Seats.indexWhere((s) => s.id == seatId);
      if (index != -1) {
        final currentSeat = _mockF3Seats[index];
        setState(() {
          // 如果新状态是suspicious，保存之前的状态
          final previousStatus = (newStatus == 'suspicious' && currentSeat.status != 'suspicious') 
              ? currentSeat.status 
              : currentSeat.previousStatus;
          _mockF3Seats[index] = Seat(
            id: seatId,
            status: newStatus,
            top: currentSeat.top,
            left: currentSeat.left,
            previousStatus: previousStatus,
          );
        });
      }
    } else if (seatId.startsWith('F4')) {
      // 更新F4的伪数据
      final index = _mockF4Seats.indexWhere((s) => s.id == seatId);
      if (index != -1) {
        final currentSeat = _mockF4Seats[index];
        setState(() {
          // 如果新状态是suspicious，保存之前的状态
          final previousStatus = (newStatus == 'suspicious' && currentSeat.status != 'suspicious') 
              ? currentSeat.status 
              : currentSeat.previousStatus;
          _mockF4Seats[index] = Seat(
            id: seatId,
            status: newStatus,
            top: currentSeat.top,
            left: currentSeat.left,
            previousStatus: previousStatus,
          );
        });
      }
    }
  }

  // 根据座位ID和随机种子生成新的状态
  String _getRandomStatus(String seatId, int seed) {
    // F3楼层的所有座位始终保持为 occupied（全占用）
    if (seatId.startsWith('F3')) {
      return 'occupied';
    }
    
    // 使用座位ID和种子生成伪随机数，确保每次更新都有变化
    final hash = (seatId.hashCode + seed) % 100;
    
    // 状态概率分布：
    // - empty: 40%
    // - occupied: 30%
    // - has_power: 20%
    // - suspicious: 10% (只有F4-08固定为suspicious，其他偶尔出现)
    
    if (seatId == 'F4-08') {
      // F4-08 保持为 suspicious（演示异常座位）
      return 'suspicious';
    }
    
    if (hash < 40) {
      return 'empty';
    } else if (hash < 70) {
      return 'occupied';
    } else if (hash < 90) {
      return 'has_power';
    } else {
      return 'suspicious';
    }
  }

  // 检查座位数据是否有变化
  bool _hasSeatChanges(List<SeatResponse> oldSeats, List<SeatResponse> newSeats) {
    if (oldSeats.length != newSeats.length) return true;
    
    // 创建新座位的映射以便快速查找
    final newSeatsMap = {for (var s in newSeats) s.seatId: s};
    
    for (final old in oldSeats) {
      final newSeat = newSeatsMap[old.seatId];
      if (newSeat == null) {
        // 座位不存在了
        return true;
      }
      
      // 检查所有可能变化的状态字段
      if (old.isEmpty != newSeat.isEmpty ||
          old.hasPower != newSeat.hasPower ||
          old.isMalicious != newSeat.isMalicious ||
          old.isReported != newSeat.isReported ||
          old.lockUntilTs != newSeat.lockUntilTs ||
          old.seatColor != newSeat.seatColor ||
          old.adminColor != newSeat.adminColor) {
        return true;
      }
    }
    return false;
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
      // 先触发后端刷新
      await _apiService.refreshFloor(floorId);
      // 然后获取最新数据
      final seats = await _apiService.getSeats(floor: floorId);
      setState(() {
        _apiSeats[floorId] = seats;
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('refresh_success') ?? '刷新成功'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${t('refresh_failed') ?? '刷新失败'}: $e'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _getCurrentFloorId() {
    // 从下到上：F1(一楼), F2(二楼), F3(三楼), F4(四楼)
    const floorIds = ['F1', 'F2', 'F3', 'F4'];
    return floorIds[_selectedFloorIndex];
  }

  String _getFloorLabel(String floorId) {
    // 从下到上：F1(一楼/I), F2(二楼/II), F3(三楼/III), F4(四楼/IV)
    const labels = {'F1': 'I', 'F2': 'II', 'F3': 'III', 'F4': 'IV'};
    return labels[floorId] ?? floorId;
  }

  List<FloorInfo> _buildFloorData() {
    // 定义正确的楼层顺序：F1, F2, F3, F4（从下到上）
    const floorOrder = ['F1', 'F2', 'F3', 'F4'];
    
    return floorOrder.map((floorId) {
      // F3和F4使用伪数据统计
      if (floorId == 'F3' && _mockF3Seats.isNotEmpty) {
        // F3强制为0个空座位（全占用）
        return FloorInfo(
          label: _getFloorLabel(floorId),
          availableCount: 0, // F3强制为0
          totalSeats: _mockF3Seats.length,
        );
      } else if (floorId == 'F4' && _mockF4Seats.isNotEmpty) {
        final availableCount = _mockF4Seats.where(
          (seat) => seat.status == 'empty' || seat.status == 'has_power',
        ).length;
        return FloorInfo(
          label: _getFloorLabel(floorId),
          availableCount: availableCount,
          totalSeats: _mockF4Seats.length,
        );
      }
      
      // F1和F2使用API数据或硬编码数据
      if (_useApiData && _floors.isNotEmpty) {
        try {
          final floor = _floors.firstWhere((f) => f.floorId == floorId);
          return FloorInfo(
            label: _getFloorLabel(floor.floorId),
            availableCount: floor.emptyCount,
            totalSeats: floor.totalCount,
          );
        } catch (e) {
          // 如果找不到该楼层，继续使用硬编码数据
        }
      }
      
      // 使用硬编码数据（F1和F2）
      final index = floorOrder.indexOf(floorId);
      if (index >= 0 && index < _seatLayouts.length) {
        final seats = _seatLayouts[index];
        final availableCount = seats.where(
          (seat) => seat.status == 'empty' || seat.status == 'has_power',
        ).length;
        return FloorInfo(
          label: _getFloorLabel(floorId),
          availableCount: availableCount,
          totalSeats: seats.length,
        );
      }
      return FloorInfo(
        label: _getFloorLabel(floorId),
        availableCount: 0,
        totalSeats: 0,
      );
    }).toList();
  }

  List<Widget> _getTablesForCurrentFloor() {
    switch (_selectedFloorIndex) {
      case 0: // F1: 上下排座位 + 中间，桌子向外扩展
        return [
          // 上排长桌：位于左右座位之间，向外扩展
          Positioned(top: 200, left: 160, child: _buildTableRect(width: 220, height: 50)),
          // 下排长桌：位于左右座位之间，向外扩展
          Positioned(top: 400, left: 160, child: _buildTableRect(width: 220, height: 50)),
          // 中间装饰小桌（垂直）
          Positioned(top: 290, left: 120, child: _buildTableRect(width: 40, height: 70)),
          Positioned(top: 290, left: 380, child: _buildTableRect(width: 40, height: 70)),
        ];
      case 1: // F2: 两排座位 + 中间圆桌
        return [
          // 上排长桌：连接左右 (top:250)
          Positioned(top: 250, left: 180, child: _buildTableRect(width: 180, height: 50)),
          // 下排长桌：连接左右 (top:450)
          Positioned(top: 450, left: 180, child: _buildTableRect(width: 180, height: 50)),
          // 中间大圆桌
          Positioned(top: 320, left: 240, child: _buildTableCircle(size: 100)),
        ];
      case 2: // F3: 只保留圆桌，并调整位置
        return [
          // 右下圆桌：服务于独立座位，位置调整
          Positioned(top: 320, left: 290, child: _buildTableCircle(size: 80)),
        ];
      case 3: // F4: 仅保留圆桌并往右移动
      default:
        return [
          // 中间圆桌：往右移动
          Positioned(top: 280, left: 270, child: _buildTableCircle(size: 100)),
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
    final floorId = _getCurrentFloorId();
    
    // F3和F4始终使用伪数据（每10秒自动变化）
    if (floorId == 'F3' && _mockF3Seats.isNotEmpty) {
      // 不再过滤suspicious座位，非管理员用户会看到previousStatus
      return _mockF3Seats;
    } else if (floorId == 'F4' && _mockF4Seats.isNotEmpty) {
      // 不再过滤suspicious座位，非管理员用户会看到previousStatus
      return _mockF4Seats;
    }
    
    // F1和F2使用API数据或硬编码数据
    if (_useApiData) {
      // 使用 API 数据
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
      }).toList()..sort((a, b) => a.id.compareTo(b.id)); // 排序以确保一致性
    } else {
      // 使用硬编码数据（F1和F2）
      return _seatLayouts[_selectedFloorIndex];
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSeats = _getSeatsForCurrentFloor();
    final currentTables = _getTablesForCurrentFloor();
    
    // 获取屏幕尺寸，用于响应式布局
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;
    
    // 计算地图尺寸：手机使用屏幕宽度，桌面使用固定宽度
    final sidebarWidth = isMobile ? 50.0 : 80.0;
    final appBarHeight = kToolbarHeight; // AppBar高度
    final availableWidth = screenSize.width - sidebarWidth;
    final availableHeight = screenSize.height - appBarHeight - (isMobile ? 10 : 40); // 减少边距，让地图更大
    
    // 计算地图尺寸，保持宽高比（600:800 = 3:4）
    final aspectRatio = 600.0 / 800.0;
    double mapWidth, mapHeight;
    
    if (isMobile) {
      // 手机：优先填满宽度，减少右边空白
      // 使用几乎全部可用宽度，只留最小边距
      mapWidth = availableWidth - (isMobile ? 4 : 16); // 最小边距
      mapHeight = mapWidth / aspectRatio;
      // 如果高度超出，则按高度计算，但保持尽可能大的宽度
      if (mapHeight > availableHeight) {
        mapHeight = availableHeight - (isMobile ? 4 : 16);
        mapWidth = mapHeight * aspectRatio;
        // 如果按高度计算后宽度还有空间，可以稍微放宽宽高比限制
        if (mapWidth < availableWidth * 0.95) {
          // 允许稍微拉伸宽度，但不超过95%的可用宽度
          mapWidth = (availableWidth * 0.95).clamp(mapWidth, availableWidth - 4);
          mapHeight = mapWidth / aspectRatio;
        }
      }
    } else {
      // 桌面：使用固定尺寸，但不超过可用空间
      mapWidth = 600.0;
      mapHeight = 800.0;
      if (mapWidth > availableWidth) {
        mapWidth = availableWidth - 16;
        mapHeight = mapWidth / aspectRatio;
      }
      if (mapHeight > availableHeight) {
        mapHeight = availableHeight - 16;
        mapWidth = mapHeight * aspectRatio;
      }
    }
    
    // 计算缩放比例（基于600x800的原始设计）
    final scaleX = mapWidth / 600.0;
    final scaleY = mapHeight / 800.0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          Container(
            margin: EdgeInsets.only(right: isMobile ? 12 : 16),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: PopupMenuButton<String>(
              icon: Icon(
                Icons.settings,
                color: Colors.grey[700],
                size: isMobile ? 22 : 24,
              ),
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
        ],
      ),
      body: SafeArea(
        child: Row(
          children: [
            _buildSidebar(isMobile: isMobile),
            Expanded(
              child: Center(
                child: Stack(
                  children: [
                    // 静态地图，禁用拖动和缩放
                    Container(
                      color: Colors.transparent,
                      width: mapWidth,
                      height: mapHeight,
                      child: Stack(
                        children: [
                          // 缩放桌子位置
                          ...currentTables.map((table) {
                            if (table is Positioned) {
                              final top = (table.top ?? 0) * scaleY;
                              final left = (table.left ?? 0) * scaleX;
                              final child = table.child;
                              // 获取child的尺寸并缩放
                              return Positioned(
                                top: top,
                                left: left,
                                child: Transform.scale(
                                  scaleX: scaleX,
                                  scaleY: scaleY,
                                  alignment: Alignment.topLeft,
                                  child: child,
                                ),
                              );
                            }
                            return table;
                          }),
                          // 缩放座位位置
                          ...currentSeats.map(
                            (seat) => Positioned(
                              key: ValueKey('${seat.id}_${seat.getDisplayColor(_isAdmin)}'),
                              top: seat.top * scaleY,
                              left: seat.left * scaleX,
                              child: Transform.scale(
                                scaleX: scaleX,
                                scaleY: scaleY,
                                alignment: Alignment.center,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    );
                                  },
                                  child: _buildSeatIcon(seat),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
    // 使用getDisplayStatus获取显示状态（非管理员看到previousStatus）
    final displayStatus = seat.getDisplayStatus(_isAdmin);
    final statusKey = 'status_$displayStatus';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(20),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width - 40,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(t('seat_info'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black54),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              _buildInfoRow("ID:", seat.id),
              _buildInfoRow("${t('floor')}:", _buildFloorData()[_selectedFloorIndex].label),
              _buildInfoRow("${t('status')}:", t(statusKey), color: seat.getDisplayColor(_isAdmin)),
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
                  label: Text(t('report_issue'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  onPressed: () {
                    Navigator.pop(context);
                    _showReportDialog(seat);
                  },
                ),
              ),
            ],
          ),
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
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 40,
            ),
            child: SingleChildScrollView(
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
                      
                      // 如果是F3或F4的座位，更新伪数据状态为suspicious
                      _updateMockSeatStatus(seat.id, 'suspicious');
                      
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

  Widget _buildRefreshButton() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: _loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
              )
            : const Icon(Icons.refresh, color: Colors.black87),
        onPressed: _loading ? null : _refreshCurrentFloor,
        tooltip: t('refresh') ?? '刷新',
      ),
    );
  }

  Widget _buildSidebar({bool isMobile = false}) {
    final floorData = _buildFloorData();
    final sidebarWidth = isMobile ? 50.0 : 80.0;
    final buttonSize = isMobile ? 45.0 : 60.0;
    return Container(
      width: sidebarWidth,
      color: Colors.transparent,
      child: Center(
        // 使用 Center 让楼层按钮垂直居中
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // 垂直居中
          children: [
            // 从下到上显示：F1(I) 在最下面，F4(IV) 在最上面
            // 所以需要反转显示顺序
            for (int i = floorData.length - 1; i >= 0; i--) ...[
              GestureDetector(
                onTap: () => setState(() => _selectedFloorIndex = i),
                child: Column(
                  children: [
                    Container(
                      width: buttonSize,
                      height: buttonSize,
                      decoration: BoxDecoration(
                        color: floorData[i].color,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          if (i == _selectedFloorIndex)
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
                              floorData[i].label,
                              style: TextStyle(
                                color: Colors.white, 
                                fontSize: isMobile ? 14 : 20, 
                                fontWeight: FontWeight.bold
                              ),
                            ),
                          ),
                          SizedBox(height: isMobile ? 1 : 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              "${floorData[i].availableCount}",
                              style: TextStyle(
                                color: Colors.white, 
                                fontSize: isMobile ? 10 : 14
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: isMobile ? 4 : 8),
                    if (i == _selectedFloorIndex) 
                      CircleAvatar(
                        backgroundColor: Colors.black54, 
                        radius: isMobile ? 2.5 : 3
                      ),
                  ],
                ),
              ),
              if (i > 0) SizedBox(height: isMobile ? 6 : 10), // 楼层之间的间距，手机减少
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSeatIcon(Seat seat) {
    // 根据屏幕尺寸调整图标大小，增大图标让座位更明显
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600;
    final iconSize = isMobile ? 60.0 : 68.0; // 增大图标尺寸
    
    return GestureDetector(
      onTap: () => _showSeatDetailDialog(seat),
      child: Icon(
        Icons.chair,
        color: seat.getDisplayColor(_isAdmin), // 使用getDisplayColor，非管理员看到previousStatus的颜色
        size: iconSize,
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
    // 恢复正常尺寸，不再强制放大
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
    // 恢复正常尺寸，不再强制放大
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

