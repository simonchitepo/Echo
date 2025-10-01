import 'package:flutter/material.dart';
import 'pages/home_page.dart';

void main() {
  runApp(const EchoApp());
}

class EchoApp extends StatelessWidget {
  const EchoApp({super.key});

  // Minimal brand
  static const Color brandGreen = Color(0xFF0F9D58);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      brightness: Brightness.light,
      primaryColor: brandGreen,
      scaffoldBackgroundColor: Colors.white,

      // Older Flutter: use ColorScheme, but keep it simple
      colorScheme: ColorScheme.fromSwatch(
        primarySwatch: _toMaterialColor(brandGreen),
      ).copyWith(
        secondary: brandGreen,
        surface: Colors.white,
        background: Colors.white,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Colors.black),
        titleTextStyle: TextStyle(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),

      // ✅ FIX: CardThemeData (not CardTheme)
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),

      dividerColor: Colors.black12,

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF7F8F7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: brandGreen, width: 1.5),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brandGreen,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Echo',
      theme: theme,
      home: const HomePage(),
    );
  }
}

// Helper to create a MaterialColor from a single Color (for older ThemeData)
MaterialColor _toMaterialColor(Color color) {
  final r = color.red, g = color.green, b = color.blue;

  return MaterialColor(color.value, <int, Color>{
    50: Color.fromRGBO(r, g, b, .10),
    100: Color.fromRGBO(r, g, b, .20),
    200: Color.fromRGBO(r, g, b, .30),
    300: Color.fromRGBO(r, g, b, .40),
    400: Color.fromRGBO(r, g, b, .50),
    500: Color.fromRGBO(r, g, b, .60),
    600: Color.fromRGBO(r, g, b, .70),
    700: Color.fromRGBO(r, g, b, .80),
    800: Color.fromRGBO(r, g, b, .90),
    900: Color.fromRGBO(r, g, b, 1),
  });
}
