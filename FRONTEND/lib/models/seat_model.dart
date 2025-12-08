import 'package:flutter/material.dart';
import '../services/api_service.dart';

// 1. 定义颜色常量，用于座位状态和UI元素
class AppColors {
  // 座位状态颜色
  static const green = Color(0xFF60D937); // 空闲 (Available)
  static const blue = Color(0xFF00A1FF);  // 空闲 (有插座)
  static const grey = Color(0xFF929292);  // 占用 (Occupied)
  static const yellow = Color(0xFFFEAE03); // 可疑占座/警告 (Suspicious/Warning)
  static const red = Color(0xFFFF5252);   // 满座/错误 (Full/Error)
  
  // UI 颜色
  static const reportButton = Color(0xFFEF949E);   // 报告按钮 (Report)
  static const confirmButton = Color(0xFFC9E5B3);  // 确认按钮 (Confirm)
  static const dialogBackground = Color(0xFFABB8C8); // 对话框背景 (Dialog Background)
}

// 座位数据模型
class Seat {
  final String id; // 座位编号
  final String status; // 状态: 'occupied', 'suspicious', 'has_power', 'empty'
  final double top; // 地图上的 Y 坐标
  final double left; // 地图上的 X 坐标
  final String? apiColor; // 从 API 获取的颜色（十六进制字符串）
  final String? previousStatus; // 举报前的状态（用于非管理员用户显示）

  // 确保 Seat 构造函数也是 const，以便用于静态数据
  const Seat({
    required this.id,
    required this.status,
    required this.top,
    required this.left,
    this.apiColor,
    this.previousStatus,
  });

  // 从 API 响应创建 Seat（需要提供位置信息）
  factory Seat.fromApiResponse(SeatResponse apiSeat, {required double top, required double left, required bool isAdmin}) {
    // 先确定原始状态（举报前的状态）
    String originalStatus;
    if (!apiSeat.isEmpty) {
      originalStatus = 'occupied';
    } else if (apiSeat.hasPower) {
      originalStatus = 'has_power';
    } else {
      originalStatus = 'empty';
    }
    
    String status = originalStatus;
    String? previousStatus;
    String? apiColor;
    
    // 如果是管理员且 (is_malicious 或 is_reported)，显示为 suspicious
    if (isAdmin) {
      if (apiSeat.isMalicious) {
        status = 'malicious'; // 确认为恶意占用 -> 红色
        previousStatus = originalStatus;
      } else if (apiSeat.isReported) {
        status = 'suspicious'; // 被举报 -> 黄色
        previousStatus = originalStatus;
      }
      // 管理员使用 adminColor
      apiColor = apiSeat.adminColor;
    } else {
      // 非管理员用户：如果座位被举报，保存原始状态但不显示为suspicious
      if (apiSeat.isMalicious || apiSeat.isReported) {
        previousStatus = originalStatus;
        status = originalStatus; // 非管理员显示原始状态
        // 非管理员用户：被举报的座位应该显示举报前的颜色，而不是黄色
        // 根据 originalStatus 计算颜色，而不是使用后端返回的 seatColor（可能是黄色）
        switch (originalStatus) {
          case 'occupied':
            apiColor = '#929292'; // 灰色
            break;
          case 'has_power':
            apiColor = '#00A1FF'; // 蓝色
            break;
          case 'empty':
          default:
            apiColor = '#60D937'; // 绿色
            break;
        }
      } else {
        // 没有被举报，正常使用后端返回的颜色
        apiColor = apiSeat.seatColor;
      }
    }

    return Seat(
      id: apiSeat.seatId,
      status: status,
      top: top,
      left: left,
      apiColor: apiColor,
      previousStatus: previousStatus,
    );
  }

  Color get color {
    // 如果 API 提供了颜色，优先使用
    if (apiColor != null) {
      try {
        // 将十六进制颜色字符串转换为 Color
        final hexColor = apiColor!.replaceFirst('#', '');
        return Color(int.parse('FF$hexColor', radix: 16));
      } catch (e) {
        // 如果解析失败，使用默认逻辑
      }
    }
    
    // 否则使用默认逻辑
    switch (status) {
      case 'occupied': return AppColors.grey;
      case 'suspicious': return AppColors.yellow;
      case 'has_power': return AppColors.blue;
      case 'empty':
      default: return AppColors.green;
    }
  }
  
  // 获取显示状态（对于非管理员用户，如果座位被举报则显示previousStatus）
  String getDisplayStatus(bool isAdmin) {
    // 非管理员用户：如果座位状态是suspicious（被举报），显示举报前的状态
    if (!isAdmin) {
      // 如果状态是suspicious，说明座位被举报了
      if (status == 'suspicious' || status == 'malicious') {
        // 如果有previousStatus，使用previousStatus
        if (previousStatus != null) {
          return previousStatus!;
        }
        // 如果没有previousStatus，假设举报前是occupied
        return 'occupied';
      }
    }
    // 管理员用户或非suspicious状态，使用正常状态
    return status;
  }
  
  // 获取显示颜色（对于非管理员用户，如果座位被举报则显示举报前的颜色）
  Color getDisplayColor(bool isAdmin) {
    // 非管理员用户：如果座位状态是suspicious（被举报），显示举报前的颜色
    if (!isAdmin) {
      // 如果状态是suspicious，说明座位被举报了
      if (status == 'suspicious' || status == 'malicious') {
        // 如果有previousStatus，使用previousStatus对应的颜色
        if (previousStatus != null) {
          switch (previousStatus!) {
            case 'occupied': return AppColors.grey;
            case 'has_power': return AppColors.blue;
            case 'empty':
            default: return AppColors.green;
          }
        }
        // 如果没有previousStatus，假设举报前是occupied（灰色）
        return AppColors.grey;
      }
    }
    // 管理员用户或非suspicious状态，使用正常颜色
    return color;
  }
}

// 楼层信息模型
class FloorInfo {
  final String label; // 楼层标签 (如: 'I', 'II', 'III', 'IV')
  final int availableCount; // 可用座位数
  final int totalSeats; // 总座位数

  // 关键修复: 将构造函数改为 const
  const FloorInfo({
    required this.label, 
    required this.availableCount, 
    required this.totalSeats 
  });
  
  // 楼层选择器颜色逻辑
  Color get color {
    if (availableCount == 0) return AppColors.red;
    double ratio = availableCount / totalSeats;
    if (ratio > 0.5) return AppColors.green;
    return AppColors.yellow;
  }
}