class ApiConfig {
  // 后端 API 地址配置
  // 
  // 使用说明：
  // - Chrome浏览器（Mac本地）: 使用 localhost:8000
  // - 真机测试: 使用 Mac 的局域网 IP（当前: 10.244.100.167）
  // 
  // 切换方法：
  // 1. Chrome浏览器运行：取消注释下面一行，注释掉 IP 地址那一行
  // 2. 真机测试：注释掉下面一行，取消注释 IP 地址那一行
  
  // Chrome浏览器（Mac本地开发）- 使用 localhost 避免 CORS 问题
  // static const String baseUrl = 'http://localhost:8000';
  
  // 使用 127.0.0.1 作为替代方案（如果 localhost 有问题）
  // static const String baseUrl = 'http://127.0.0.1:8000';
  
  // 真机测试（使用 Mac 的局域网 IP）
  // 当前 Mac IP: 192.168.1.106
  // 如果 IP 变化，请运行: ifconfig | grep "inet " | grep -v 127.0.0.1
  static const String baseUrl = 'http://192.168.1.106:8000';
  
  // 获取当前配置的 baseURL（用于调试）
  static String get currentBaseUrl => baseUrl;
}
