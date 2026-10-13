// generate_theme.dart
// 
// Helper script to generate Material 3 Expressive theme configuration
// 
// Usage:
//   dart run scripts/generate_theme.dart --seed-color 0xFF6200EE --output lib/theme/
//

import 'dart:io';

void main(List<String> args) {
  // Parse arguments
  String seedColorHex = '0xFF6200EE'; // Default purple
  String outputPath = 'lib/theme/';
  
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--seed-color' && i + 1 < args.length) {
      seedColorHex = args[i + 1];
    } else if (args[i] == '--output' && i + 1 < args.length) {
      outputPath = args[i + 1];
    }
  }

  // Ensure output directory exists
  final outputDir = Directory(outputPath);
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  // Generate theme file
  final themeContent = generateThemeFile(seedColorHex);
  final themeFile = File('${outputPath}app_theme.dart');
  themeFile.writeAsStringSync(themeContent);

  print('✅ Theme generated at: ${themeFile.path}');
  print('🎨 Seed color: $seedColorHex');
  print('\nNext steps:');
  print('1. Import in main.dart: import \'theme/app_theme.dart\';');
  print('2. Use: MaterialApp(theme: AppTheme.light, darkTheme: AppTheme.dark)');
}

String generateThemeFile(String seedColorHex) {
  return '''
// app_theme.dart
// Generated Material 3 Expressive theme configuration

import 'package:flutter/material.dart';

class AppTheme {
  // Seed color for theme generation
  static const Color _seedColor = Color($seedColorHex);

  // Light theme
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.light,
        ),
        
        // Expressive button themes
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(100), // Fully rounded
            ),
            minimumSize: const Size(88, 48), // Larger touch targets
          ),
        ),
        
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(100),
            ),
            minimumSize: const Size(88, 48),
          ),
        ),
        
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(100),
            ),
            minimumSize: const Size(88, 48),
          ),
        ),
        
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(100),
            ),
            minimumSize: const Size(88, 48),
          ),
        ),
        
        // Expressive FAB theme
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28), // Large corner radius
          ),
          sizeConstraints: const BoxConstraints.tightFor(
            width: 56,
            height: 56,
          ),
        ),
        
        // Expressive card theme
        cardTheme: CardTheme(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), // More rounded
          ),
        ),
        
        // App bar theme
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
        
        // Navigation bar theme
        navigationBarTheme: NavigationBarThemeData(
          height: 80, // Larger for M3E
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        
        // Navigation rail theme  
        navigationRailTheme: NavigationRailThemeData(
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        
        // Input decoration theme
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
        ),
      );

  // Dark theme
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
        
        // Same expressive customizations as light theme
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(100),
            ),
            minimumSize: const Size(88, 48),
          ),
        ),
        
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(100),
            ),
            minimumSize: const Size(88, 48),
          ),
        ),
        
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(100),
            ),
            minimumSize: const Size(88, 48),
          ),
        ),
        
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(100),
            ),
            minimumSize: const Size(88, 48),
          ),
        ),
        
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          sizeConstraints: const BoxConstraints.tightFor(
            width: 56,
            height: 56,
          ),
        ),
        
        cardTheme: CardTheme(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
        
        navigationBarTheme: NavigationBarThemeData(
          height: 80,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        
        navigationRailTheme: NavigationRailThemeData(
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
        ),
      );

  // Helper to get current theme based on brightness
  static ThemeData getTheme(Brightness brightness) {
    return brightness == Brightness.light ? light : dark;
  }
}
''';
}
