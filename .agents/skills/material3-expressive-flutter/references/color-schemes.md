# Color Schemes - M3 Expressive

## Overview

Material 3 Expressive uses color purposefully to guide attention and create emotional impact beyond aesthetics. The key difference is bolder use of on-container colors.

## Core Principles

1. **Color with Purpose**: Guide user attention, not just decoration
2. **Vibrant Containers**: Bolder on-container colors than standard M3
3. **Dynamic Color**: Support Material You on Android 12+
4. **Accessibility**: Maintain WCAG contrast ratios

## Generating Color Schemes

### Basic Seed Color Approach

```dart
// Generate from single seed color
final lightScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF6200EE), // Purple
  brightness: Brightness.light,
);

final darkScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF6200EE),
  brightness: Brightness.dark,
);
```

### Dynamic Color (Material You)

```dart
import 'package:dynamic_color/dynamic_color.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // Use system colors if available, fallback to custom
        ColorScheme lightScheme = lightDynamic ?? ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        );

        ColorScheme darkScheme = darkDynamic ?? ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        );

        return MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: lightScheme,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: darkScheme,
          ),
        );
      },
    );
  }
}
```

### Custom Expressive Scheme

```dart
// Create a vibrant, expressive color scheme
ColorScheme createExpressiveScheme({
  required Color seedColor,
  required Brightness brightness,
}) {
  // Generate base scheme
  final baseScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  );

  // Enhance for expressiveness
  if (brightness == Brightness.light) {
    return baseScheme.copyWith(
      // Make primary container more vibrant
      primaryContainer: seedColor.withOpacity(0.3),
      onPrimaryContainer: seedColor.withOpacity(0.9),
      
      // Boost secondary container
      secondaryContainer: baseScheme.secondary.withOpacity(0.25),
      onSecondaryContainer: baseScheme.secondary,
      
      // Enhance tertiary for variety
      tertiaryContainer: baseScheme.tertiary.withOpacity(0.25),
      onTertiaryContainer: baseScheme.tertiary,
    );
  } else {
    return baseScheme.copyWith(
      // Dark mode expressive adjustments
      primaryContainer: seedColor.withOpacity(0.25),
      onPrimaryContainer: seedColor.withOpacity(0.7),
      
      secondaryContainer: baseScheme.secondary.withOpacity(0.2),
      onSecondaryContainer: baseScheme.secondary.withOpacity(0.8),
      
      tertiaryContainer: baseScheme.tertiary.withOpacity(0.2),
      onTertiaryContainer: baseScheme.tertiary.withOpacity(0.8),
    );
  }
}

// Usage:
ThemeData(
  useMaterial3: true,
  colorScheme: createExpressiveScheme(
    seedColor: Colors.indigo,
    brightness: Brightness.light,
  ),
)
```

## M3 Expressive Color Roles

### Container Colors (Key for Expressiveness)

```dart
// Primary containers - main interactive elements
Container(
  color: colorScheme.primaryContainer,
  child: Text(
    'Primary Action',
    style: TextStyle(color: colorScheme.onPrimaryContainer),
  ),
)

// Secondary containers - supportive elements
Container(
  color: colorScheme.secondaryContainer,
  child: Text(
    'Secondary',
    style: TextStyle(color: colorScheme.onSecondaryContainer),
  ),
)

// Tertiary containers - accent elements
Container(
  color: colorScheme.tertiaryContainer,
  child: Text(
    'Tertiary',
    style: TextStyle(color: colorScheme.onTertiaryContainer),
  ),
)
```

### Surface Colors (Backgrounds & Cards)

```dart
// Surface hierarchy (from lowest to highest elevation)
colorScheme.surface
colorScheme.surfaceContainerLowest
colorScheme.surfaceContainerLow
colorScheme.surfaceContainer
colorScheme.surfaceContainerHigh
colorScheme.surfaceContainerHighest
```

## Using flex_color_scheme

```dart
import 'package:flex_color_scheme/flex_color_scheme.dart';

// Expressive scheme with FlexColorScheme
ThemeData(
  useMaterial3: true,
  colorScheme: FlexColorScheme.light(
    scheme: FlexScheme.indigo,
    surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
    blendLevel: 20, // More color blending for expressiveness
  ).toScheme,
)

// Or create fully custom:
ThemeData(
  useMaterial3: true,
  colorScheme: FlexColorScheme.light(
    primary: const Color(0xFF6200EE),
    secondary: const Color(0xFF03DAC6),
    tertiary: const Color(0xFFFF6E40),
    surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
    blendLevel: 25,
  ).toScheme,
)
```

## Color Application Strategies

### Strategy 1: Vibrant & Bold

```dart
// For energetic, playful apps
final expressiveVibrant = ColorScheme.fromSeed(
  seedColor: Colors.deepOrange,
  brightness: Brightness.light,
).copyWith(
  primaryContainer: Colors.deepOrange.shade100,
  onPrimaryContainer: Colors.deepOrange.shade900,
  secondaryContainer: Colors.amber.shade100,
  onSecondaryContainer: Colors.amber.shade900,
);
```

### Strategy 2: Calm & Professional

```dart
// For professional, trustworthy apps
final expressiveCalm = ColorScheme.fromSeed(
  seedColor: Colors.blue,
  brightness: Brightness.light,
).copyWith(
  primaryContainer: Colors.blue.shade50,
  onPrimaryContainer: Colors.blue.shade900,
  secondaryContainer: Colors.blueGrey.shade50,
  onSecondaryContainer: Colors.blueGrey.shade900,
);
```

### Strategy 3: Warm & Friendly

```dart
// For welcoming, approachable apps
final expressiveWarm = ColorScheme.fromSeed(
  seedColor: Colors.pink,
  brightness: Brightness.light,
).copyWith(
  primaryContainer: Colors.pink.shade50,
  onPrimaryContainer: Colors.pink.shade900,
  secondaryContainer: Colors.orange.shade50,
  onSecondaryContainer: Colors.orange.shade900,
);
```

## Accessibility Considerations

### Contrast Checking

```dart
import 'package:flutter/material.dart';

double calculateContrast(Color foreground, Color background) {
  final fgLuminance = foreground.computeLuminance();
  final bgLuminance = background.computeLuminance();
  
  final lighter = fgLuminance > bgLuminance ? fgLuminance : bgLuminance;
  final darker = fgLuminance > bgLuminance ? bgLuminance : fgLuminance;
  
  return (lighter + 0.05) / (darker + 0.05);
}

// WCAG AA requires 4.5:1 for normal text, 3:1 for large text
bool hasGoodContrast(Color foreground, Color background) {
  return calculateContrast(foreground, background) >= 4.5;
}
```

### Ensuring Accessible Expressive Colors

```dart
ColorScheme ensureAccessibleScheme(ColorScheme scheme) {
  // Check and adjust if needed
  if (!hasGoodContrast(scheme.onPrimaryContainer, scheme.primaryContainer)) {
    // Darken onPrimaryContainer or lighten primaryContainer
    return scheme.copyWith(
      onPrimaryContainer: scheme.onPrimaryContainer.withOpacity(0.95),
    );
  }
  return scheme;
}
```

## Theme Switcher

```dart
class ThemeController extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Color _seedColor = Colors.deepPurple;

  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  void setSeedColor(Color color) {
    _seedColor = color;
    notifyListeners();
  }

  ColorScheme getLightScheme() {
    return ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    );
  }

  ColorScheme getDarkScheme() {
    return ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );
  }
}

// In app:
ChangeNotifierProvider(
  create: (_) => ThemeController(),
  child: Consumer<ThemeController>(
    builder: (context, themeController, _) {
      return MaterialApp(
        themeMode: themeController.themeMode,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: themeController.getLightScheme(),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: themeController.getDarkScheme(),
        ),
      );
    },
  ),
)
```

## Color Picker for Runtime Changes

```dart
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class ColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;

  const ColorPickerDialog({
    super.key,
    required this.initialColor,
    required this.onColorChanged,
  });

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late Color _currentColor;

  @override
  void initState() {
    super.initState();
    _currentColor = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pick a seed color'),
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: _currentColor,
          onColorChanged: (color) => setState(() => _currentColor = color),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.onColorChanged(_currentColor);
            Navigator.pop(context);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
```

## Debugging Colors

```dart
class ColorDebugger extends StatelessWidget {
  final ColorScheme colorScheme;

  const ColorDebugger({super.key, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _buildColorTile('Primary', colorScheme.primary, colorScheme.onPrimary),
        _buildColorTile('Primary Container', colorScheme.primaryContainer, 
            colorScheme.onPrimaryContainer),
        _buildColorTile('Secondary', colorScheme.secondary, 
            colorScheme.onSecondary),
        _buildColorTile('Secondary Container', colorScheme.secondaryContainer,
            colorScheme.onSecondaryContainer),
        // ... add all color roles
      ],
    );
  }

  Widget _buildColorTile(String label, Color background, Color foreground) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: foreground, fontWeight: FontWeight.bold)),
          Text('BG: ${background.value.toRadixString(16)}', 
              style: TextStyle(color: foreground, fontSize: 12)),
          Text('FG: ${foreground.value.toRadixString(16)}',
              style: TextStyle(color: foreground, fontSize: 12)),
          Text('Contrast: ${calculateContrast(foreground, background).toStringAsFixed(2)}:1',
              style: TextStyle(color: foreground, fontSize: 12)),
        ],
      ),
    );
  }
}
```

## Best Practices

1. **Start with Seed**: Use ColorScheme.fromSeed() as foundation
2. **Test Both Modes**: Always check light AND dark themes
3. **Verify Contrast**: Use accessibility checker tools
4. **Respect System**: Support dynamic color when available
5. **Be Purposeful**: Each color should guide user attention
6. **Stay Consistent**: Use color roles, not hardcoded values

## Resources

- Material Theme Builder: https://m3.material.io/theme-builder
- WCAG Contrast Checker: https://webaim.org/resources/contrastchecker/
- flex_color_scheme docs: https://pub.dev/packages/flex_color_scheme
