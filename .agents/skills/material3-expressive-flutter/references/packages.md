# Recommended Packages - Material 3 Expressive Flutter

## Essential Packages

### Theming & Colors

#### tofu_expressive
```yaml
dependencies:
  tofu_expressive: ^latest_version
```

**Purpose**: M3 Expressive theme with dynamic color support  
**Features**:
- Pre-configured M3E themes
- Dynamic color (Material You on Android 12+)
- Dark/light mode
- Built on flex_color_scheme

**Usage**:
```dart
import 'package:tofu_expressive/tofu_expressive.dart';

MaterialApp(
  theme: TofuTheme.light(seedColor: Colors.purple),
  darkTheme: TofuTheme.dark(seedColor: Colors.purple),
)
```

#### flex_color_scheme
```yaml
dependencies:
  flex_color_scheme: ^7.3.0
```

**Purpose**: Advanced Material theming  
**Features**:
- 52+ built-in schemes
- Custom color scheme generation
- Excellent M3 support
- Theme playground app

**Usage**:
```dart
import 'package:flex_color_scheme/flex_color_scheme.dart';

MaterialApp(
  theme: FlexThemeData.light(
    scheme: FlexScheme.indigo,
    useMaterial3: true,
  ),
)
```

#### dynamic_color
```yaml
dependencies:
  dynamic_color: ^1.7.0
```

**Purpose**: Material You dynamic color support  
**Features**:
- Extract system colors (Android 12+)
- Fallback handling
- Cross-platform

**Usage**:
```dart
import 'package:dynamic_color/dynamic_color.dart';

DynamicColorBuilder(
  builder: (lightDynamic, darkDynamic) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: lightDynamic ?? ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
      ),
    );
  },
)
```

### Animations & Motion

#### spring
```yaml
dependencies:
  spring: ^2.0.2
```

**Purpose**: Spring physics animations  
**Features**:
- Natural spring motion
- Configurable stiffness/damping
- Easy integration

**Usage**:
```dart
import 'package:spring/spring.dart';

Spring.of(context).animate(
  child: widget,
  curve: SpringCurve.criticallyDamped,
)
```

#### flutter_animate
```yaml
dependencies:
  flutter_animate: ^4.5.0
```

**Purpose**: Declarative animations  
**Features**:
- Simple API
- Chainable effects
- Custom curves

**Usage**:
```dart
import 'package:flutter_animate/flutter_animate.dart';

Text('Hello')
  .animate()
  .fadeIn(curve: Curves.elasticOut)
  .scale(delay: 100.ms)
```

### Loading & Progress

#### loading_animation_widget
```yaml
dependencies:
  loading_animation_widget: ^1.2.1
```

**Purpose**: Pre-built loading animations  
**Features**:
- 20+ animation styles
- Customizable colors
- Lightweight

**Usage**:
```dart
import 'package:loading_animation_widget/loading_animation_widget.dart';

LoadingAnimationWidget.waveDots(
  color: Colors.blue,
  size: 50,
)
```

#### shimmer
```yaml
dependencies:
  shimmer: ^3.0.0
```

**Purpose**: Shimmer loading effects  
**Features**:
- Skeleton screens
- Customizable gradient
- Simple API

**Usage**:
```dart
import 'package:shimmer/shimmer.dart';

Shimmer.fromColors(
  baseColor: Colors.grey[300]!,
  highlightColor: Colors.grey[100]!,
  child: Container(/* ... */),
)
```

### Icons & Graphics

#### flutter_svg
```yaml
dependencies:
  flutter_svg: ^2.0.0
```

**Purpose**: SVG rendering (for custom M3E shapes)  
**Usage**: Custom expressive shapes and icons

#### custom_clippers
```yaml
dependencies:
  custom_clippers: ^2.1.0
```

**Purpose**: Pre-built shape clippers  
**Usage**: Wave shapes, triangles, etc.

### State Management (for Complex Components)

#### provider
```yaml
dependencies:
  provider: ^6.1.0
```

**Purpose**: Simple state management  
**Usage**: Theme switching, button states

#### riverpod
```yaml
dependencies:
  flutter_riverpod: ^2.5.0
```

**Purpose**: Advanced state management  
**Usage**: Complex component state

## Development Tools

### flutter_lints
```yaml
dev_dependencies:
  flutter_lints: ^4.0.0
```

**Purpose**: Recommended lints  
**Usage**: Code quality

### very_good_analysis
```yaml
dev_dependencies:
  very_good_analysis: ^6.0.0
```

**Purpose**: Strict linting  
**Usage**: Production apps

## Component-Specific Packages

### For Navigation

#### go_router
```yaml
dependencies:
  go_router: ^14.0.0
```

**Purpose**: Declarative routing  
**Integration**: Works well with M3 navigation components

### For Dialogs & Sheets

#### modal_bottom_sheet
```yaml
dependencies:
  modal_bottom_sheet: ^3.0.0
```

**Purpose**: Custom bottom sheets  
**Integration**: M3E style sheets

## Platform-Specific

### Android

#### flutter_native_splash
```yaml
dependencies:
  flutter_native_splash: ^2.4.0
```

**Purpose**: Native splash screens  
**Integration**: M3E branded loading

### Cross-Platform

#### universal_platform
```yaml
dependencies:
  universal_platform: ^1.1.0
```

**Purpose**: Platform detection  
**Usage**: Conditional M3E features

## Complete pubspec.yaml Example

```yaml
name: my_m3_expressive_app
description: Material 3 Expressive Flutter app

environment:
  sdk: '>=3.8.0 <4.0.0'
  flutter: ">=3.32.0"

dependencies:
  flutter:
    sdk: flutter
  
  # Theming
  tofu_expressive: ^1.0.0
  flex_color_scheme: ^7.3.0
  dynamic_color: ^1.7.0
  
  # Animations
  spring: ^2.0.2
  flutter_animate: ^4.5.0
  
  # Loading
  loading_animation_widget: ^1.2.1
  shimmer: ^3.0.0
  
  # Icons & Graphics
  flutter_svg: ^2.0.0
  
  # State Management
  provider: ^6.1.0
  
  # Navigation
  go_router: ^14.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  very_good_analysis: ^6.0.0

flutter:
  uses-material-design: true
  
  assets:
    - assets/images/
    - assets/fonts/
  
  fonts:
    - family: Roboto
      fonts:
        - asset: fonts/Roboto-Regular.ttf
        - asset: fonts/Roboto-Bold.ttf
          weight: 700
```

## Package Selection Guidelines

### When to Use Packages
✅ Well-maintained (updated within 6 months)  
✅ Good documentation  
✅ Null-safe  
✅ High pub.dev score (>100)  
✅ Active community

### When to Build Custom
❌ Package abandoned (>1 year no updates)  
❌ Overkill for your needs  
❌ Poor performance  
❌ Conflicts with other dependencies  
❌ Simple implementation (<100 lines)

## Keeping Packages Updated

```bash
# Check outdated packages
flutter pub outdated

# Update to latest compatible
flutter pub upgrade

# Update to latest (may break)
flutter pub upgrade --major-versions
```

## Alternative Approaches

If packages don't fit your needs:

1. **Custom Implementation**: Build component from scratch using SKILL.md references
2. **Fork & Modify**: Fork package and customize
3. **Compose Existing**: Combine Flutter widgets creatively
4. **Request Feature**: File issue on package repo

## Community Packages to Watch

Check pub.dev regularly for new M3 Expressive packages:

```
Search terms:
- "material 3 expressive"
- "m3 expressive"
- "material you"
- "material design 3"
```

## Getting Help with Packages

1. **Package Documentation**: README and example/
2. **pub.dev Example Tab**: Working code samples
3. **GitHub Issues**: Known problems and solutions
4. **Stack Overflow**: [flutter] + [package-name]
