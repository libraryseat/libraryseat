import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isRegisterMode ? 'Register' : 'Login'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _idController,
              decoration: InputDecoration(
                labelText: 'User ID',
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pwdController,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _isRegisterMode ? _register() : _login(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : (_isRegisterMode ? _register : _login),
                style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(_isRegisterMode ? 'Register' : 'Login', style: const TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _isRegisterMode = !_isRegisterMode;
                  _idController.clear();
                  _pwdController.clear();
                });
              },
              child: Text(
                _isRegisterMode ? 'Already have an account? Login' : 'Don\'t have an account? Register',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


