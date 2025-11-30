import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'pages/floor_map_page.dart';
import 'pages/login_page.dart';

void main() {
  runApp(const LibrarySeatApp());
}

class LibrarySeatApp extends StatefulWidget {
  const LibrarySeatApp({super.key});

  @override
  State<LibrarySeatApp> createState() => _LibrarySeatAppState();
}

class _LibrarySeatAppState extends State<LibrarySeatApp> {
  Locale _locale = const Locale('en');

  void _handleLocaleChange(Locale value) {
    setState(() {
      _locale = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '图书馆座位管理',
      theme: ThemeData(
        // 主题配色使用绿色系，符合图书馆应用概念
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: const Color(0xFFEAF4E8), // 淡绿色背景
        useMaterial3: true,
      ),
      locale: _locale,
      supportedLocales: const [
        Locale('en', ''),
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: LoginPage(onLocaleChange: _handleLocaleChange),
    );
  }
}