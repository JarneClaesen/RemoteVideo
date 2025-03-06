import 'package:flutter/material.dart';

class AppTheme {
  static final lightColorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF7E1D1D),
    brightness: Brightness.light,
  );

  static final darkColorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF7E1D1D),
    brightness: Brightness.dark,
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: lightColorScheme,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: lightColorScheme.primary,
          foregroundColor: lightColorScheme.onPrimary,
          minimumSize: const Size(64, 44), // Sets minimum size
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        // Normal borders
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(12), // Adjust radius as needed
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(12),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(12),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(12),
        ),
        // Add disabled border styling
        disabledBorder: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(12),
        ),
        // Add background fill
        filled: true,
        fillColor: lightColorScheme.surfaceContainerLowest,
        // Add specific disabled styling
        hoverColor: lightColorScheme.surfaceContainerHigh,
        // Adjust padding
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        // Customize hint text style
        hintStyle: TextStyle(
          color: lightColorScheme.onSurfaceVariant,
          fontSize: 16,
        ),
        // Style for disabled state
        floatingLabelStyle: MaterialStateTextStyle.resolveWith(
              (states) => states.contains(MaterialState.disabled)
              ? TextStyle(color: lightColorScheme.onSurfaceVariant.withOpacity(0.6))
              : TextStyle(color: lightColorScheme.onSurfaceVariant),
        ),
        labelStyle: MaterialStateTextStyle.resolveWith(
              (states) => states.contains(MaterialState.disabled)
              ? TextStyle(color: lightColorScheme.onSurfaceVariant.withOpacity(0.6))
              : TextStyle(color: lightColorScheme.onSurfaceVariant),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: lightColorScheme.primary,
        selectionColor: lightColorScheme.primary.withOpacity(0.2),
        selectionHandleColor: lightColorScheme.primary,
      ),
      // Add disabled text field styling
      textTheme: Typography.material2021().black.copyWith(
        bodyLarge: Typography.material2021().black.bodyLarge?.copyWith(
          color: lightColorScheme.onSurface,
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: darkColorScheme,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: darkColorScheme.primary,
          foregroundColor: darkColorScheme.onPrimary,
          minimumSize: const Size(64, 44), // Sets minimum size
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        // Normal borders
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(12),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(12),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(12),
        ),
        // Add disabled border styling
        disabledBorder: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(12),
        ),
        // Add background fill
        filled: true,
        fillColor: darkColorScheme.surfaceContainer,
        // Add specific styling for disabled state
        hoverColor: darkColorScheme.surfaceContainerHigh,
        // Adjust padding
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        // Customize hint text style
        hintStyle: TextStyle(
          color: darkColorScheme.onSurfaceVariant,
          fontSize: 16,
        ),
        // Style for disabled state
        floatingLabelStyle: MaterialStateTextStyle.resolveWith(
              (states) => states.contains(MaterialState.disabled)
              ? TextStyle(color: darkColorScheme.onSurfaceVariant.withOpacity(0.6))
              : TextStyle(color: darkColorScheme.onSurfaceVariant),
        ),
        labelStyle: MaterialStateTextStyle.resolveWith(
              (states) => states.contains(MaterialState.disabled)
              ? TextStyle(color: darkColorScheme.onSurfaceVariant.withOpacity(0.6))
              : TextStyle(color: darkColorScheme.onSurfaceVariant),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: darkColorScheme.primary,
        selectionColor: darkColorScheme.primary.withOpacity(0.2),
        selectionHandleColor: darkColorScheme.primary,
      ),
      // Add disabled text field styling
      textTheme: Typography.material2021().white.copyWith(
        bodyLarge: Typography.material2021().white.bodyLarge?.copyWith(
          color: darkColorScheme.onSurface,
        ),
      ),
    );
  }

  // Additional extension method to apply consistent disabled text styling
  static InputDecoration getDisabledTextFieldDecoration(BuildContext context, String label, {String? hint, Widget? prefixIcon, Widget? suffixIcon}) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: colorScheme.brightness == Brightness.light
          ? colorScheme.surfaceContainerLowest
          : colorScheme.surfaceContainer,
      disabledBorder: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.circular(12),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }
}