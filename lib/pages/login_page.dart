import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/seat_model.dart';
import '../utils/translations.dart';
import 'floor_map_page.dart';
import 'admin_page.dart';

const bool kUseMockLogin = false;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.onLocaleChange});

  final ValueChanged<Locale>? onLocaleChange;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _pwdController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _isRegisterMode = false; // 是否处于注册模式

  static const String _baseUrl = ApiConfig.baseUrl;

  late final Dio _dio;

  @override
  void initState() {
    super.initState();
    BaseOptions options = BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    );
    _dio = Dio(options);
  }

  Future<void> _login() async {
    if (_loading) return;

    final id = _idController.text.trim();
    final pwd = _pwdController.text.trim();

    if (id.isEmpty || pwd.isEmpty) {
      _showError('Please enter ID and password');
      return;
    }

    // Allow alphanumeric usernames (letters and numbers)
    if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(id)) {
      _showError('ID must contain only letters and numbers');
      return;
    }

    if (pwd.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }

    setState(() => _loading = true);

    try {
      if (kUseMockLogin) {
        await _mockLogin(id: id);
        return;
      }

      // OAuth2PasswordRequestForm expects form-urlencoded data, not JSON
      final formData = 'username=${Uri.encodeComponent(id)}&password=${Uri.encodeComponent(pwd)}';
      final res = await _dio.post(
        '/auth/login',
        data: formData,
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
      );
      final token = res.data['access_token'];
      final role = res.data['role'] as String?;
      final username = res.data['username'] as String?;
      final userId = res.data['user_id'] as int?;

      if (token == null || role == null || username == null) {
        throw Exception('Invalid response from server');
      }

      await _persistSession(token: token, username: username, role: role, userId: userId);

      if (mounted) {
        _navigateToRole(role);
      }
    } on DioException catch (e) {
      String msg = 'Login failed';
      if (e.response?.statusCode == 401) {
        msg = 'Invalid ID or password';
      } else if (e.type == DioExceptionType.connectionError) {
        msg = 'Cannot connect to server. Check IP and CORS.';
      } else if (e.type == DioExceptionType.badResponse) {
        msg = 'Server error: ${e.response?.statusCode}';
      }
      _showError(msg);
    } catch (_) {
      _showError('Unexpected error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    if (_loading) return;

    final id = _idController.text.trim();
    final pwd = _pwdController.text.trim();

    if (id.isEmpty || pwd.isEmpty) {
      _showError('Please enter ID and password');
      return;
    }

    // Allow alphanumeric usernames (letters and numbers)
    if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(id)) {
      _showError('ID must contain only letters and numbers');
      return;
    }

    if (pwd.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }

    setState(() => _loading = true);

    try {
      // 注册API使用JSON格式
      final res = await _dio.post(
        '/auth/register',
        data: {
          'username': id,
          'password': pwd,
        },
        options: Options(
          contentType: 'application/json',
        ),
      );
      final token = res.data['access_token'];
      final role = res.data['role'] as String?;
      final username = res.data['username'] as String?;
      final userId = res.data['user_id'] as int?;

      if (token == null || role == null || username == null) {
        throw Exception('Invalid response from server');
      }

      await _persistSession(token: token, username: username, role: role, userId: userId);

      if (mounted) {
        _showError('Registration successful!');
        _navigateToRole(role);
      }
    } on DioException catch (e) {
      String msg = 'Registration failed';
      if (e.response?.statusCode == 400) {
        final detail = e.response?.data?['detail'] as String?;
        msg = detail ?? 'Registration failed. Username may already exist.';
      } else if (e.type == DioExceptionType.connectionError) {
        msg = 'Cannot connect to server. Check IP and CORS.';
      } else if (e.type == DioExceptionType.badResponse) {
        msg = 'Server error: ${e.response?.statusCode}';
      }
      _showError(msg);
    } catch (_) {
      _showError('Unexpected error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _mockLogin({required String id}) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final role = id == 'admin' ? 'admin' : 'user';
    await _persistSession(token: 'mock-token-$role', username: id.isEmpty ? 'tester' : id, role: role, userId: 1);
    if (mounted) {
      _navigateToRole(role);
    }
  }

  Future<void> _persistSession({required String token, required String username, required String role, int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('username', username);
    await prefs.setString('role', role);
    if (userId != null) {
      await prefs.setInt('user_id', userId);
    }
  }

  void _navigateToRole(String role) {
    // Admin navigates to AdminPage, others navigate to FloorMapPage
    final Widget target = role == 'admin'
        ? AdminPage(onLocaleChange: widget.onLocaleChange ?? (_) {})
        : FloorMapPage(onLocaleChange: widget.onLocaleChange ?? (_) {});
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => target),
    );
  }

  String t(String key) {
    final locale = Localizations.localeOf(context);
    String languageCode = locale.languageCode;
    if (languageCode == 'zh') {
      languageCode = locale.countryCode == 'TW' ? 'zh_TW' : 'zh';
    }
    return AppTranslations.get(key, languageCode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.pageBackground, // 使用与管理员界面一致的背景色
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                // Logo/标题区域
                Column(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.green.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.library_books,
                        size: 50,
                        color: AppColors.green,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      t('library_seat_management') ?? 'Library Seat Management',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRegisterMode 
                          ? (t('register_prompt') ?? 'Create a new account')
                          : (t('login_prompt') ?? 'Sign in to continue'),
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                const SizedBox(height: 48),
                // 输入框区域
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AdminColors.listItemBackground, // 使用与管理员界面一致的列表背景色
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _idController,
                        decoration: InputDecoration(
                          labelText: t('user_id') ?? 'User ID',
                          hintText: t('user_id') ?? 'User ID',
                          prefixIcon: const Icon(Icons.person_outline, color: Colors.grey),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.green, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _pwdController,
                        decoration: InputDecoration(
                          labelText: t('password') ?? 'Password',
                          hintText: t('password') ?? 'Password',
                          prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure ? Icons.visibility_off : Icons.visibility,
                              color: Colors.grey[600],
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.green, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _isRegisterMode ? _register() : _login(),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // 登录/注册按钮
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _loading ? null : (_isRegisterMode ? _register : _login),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: AppColors.green.withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            _isRegisterMode 
                                ? (t('register') ?? 'Register')
                                : (t('login') ?? 'Login'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                // 切换登录/注册模式
                TextButton(
                  onPressed: _loading ? null : () {
                    setState(() {
                      _isRegisterMode = !_isRegisterMode;
                      _idController.clear();
                      _pwdController.clear();
                    });
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  ),
                  child: Text(
                    _isRegisterMode 
                        ? (t('login_prompt') ?? 'Already have an account? Login')
                        : (t('register_prompt') ?? 'Don\'t have an account? Register'),
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // 语言选择
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.language, size: 18, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: Text(
                        _getCurrentLanguageLabel(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (value) {
                        if (widget.onLocaleChange != null) {
                          Locale locale;
                          switch (value) {
                            case 'en':
                              locale = const Locale('en');
                              break;
                            case 'zh_CN':
                              locale = const Locale('zh', 'CN');
                              break;
                            case 'zh_TW':
                              locale = const Locale('zh', 'TW');
                              break;
                            default:
                              locale = const Locale('en');
                          }
                          widget.onLocaleChange!(locale);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'en',
                          child: Text('English'),
                        ),
                        const PopupMenuItem(
                          value: 'zh_CN',
                          child: Text('简体中文'),
                        ),
                        const PopupMenuItem(
                          value: 'zh_TW',
                          child: Text('繁體中文'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getCurrentLanguageLabel() {
    final locale = Localizations.localeOf(context);
    if (locale.languageCode == 'zh') {
      return locale.countryCode == 'TW' ? '繁體中文' : '简体中文';
    }
    return 'English';
  }
}


