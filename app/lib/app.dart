import 'package:flutter/material.dart';

import 'ui/home/home_shell.dart';

class LogiOptionsApp extends StatelessWidget {
  const LogiOptionsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LogiOptions',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00B8FC),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F5F7),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00B8FC),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF1A1B1E),
      ),
      themeMode: ThemeMode.system,
      home: const HomeShell(),
    );
  }
}
