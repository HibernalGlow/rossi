# Loading Indicators - M3 Expressive Component

## Overview

Loading indicators in M3 Expressive feature wavy, organic shapes instead of simple circles. They communicate progress for tasks under 5 seconds.

## Design Principles

- **Expressive Shape**: Wavy, undulating perimeter instead of perfect circle
- **Under 5 Seconds**: For longer operations, use progress indicators
- **Contained**: Often appears within a container or card
- **Smooth Animation**: Natural, flowing motion

## Implementation in Flutter

### Wavy Circular Loading Indicator (Custom Paint)

```dart
class WavyLoadingIndicator extends StatefulWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const WavyLoadingIndicator({
    super.key,
    this.size = 40,
    this.color,
    this.strokeWidth = 4,
  });

  @override
  State<WavyLoadingIndicator> createState() => _WavyLoadingIndicatorState();
}

class _WavyLoadingIndicatorState extends State<WavyLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ??
        Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _WavyCirclePainter(
            progress: _controller.value,
            color: color,
            strokeWidth: widget.strokeWidth,
          ),
        );
      },
    );
  }
}

class _WavyCirclePainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _WavyCirclePainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - strokeWidth;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final path = Path();
    const waveCount = 6; // Number of waves around the circle
    const waveAmplitude = 2.0; // How pronounced the waves are

    for (var i = 0; i <= 360; i++) {
      final angle = i * math.pi / 180;
      final wave = math.sin((i + progress * 360) * waveCount * math.pi / 180) 
          * waveAmplitude;
      final r = radius + wave;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavyCirclePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
```

### Simpler Rotating Wave Indicator

```dart
class RotatingWaveIndicator extends StatefulWidget {
  final double size;
  final Color? color;

  const RotatingWaveIndicator({
    super.key,
    this.size = 40,
    this.color,
  });

  @override
  State<RotatingWaveIndicator> createState() => _RotatingWaveIndicatorState();
}

class _RotatingWaveIndicatorState extends State<RotatingWaveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;

    return RotationTransition(
      turns: _controller,
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _WaveShapePainter(color: color),
      ),
    );
  }
}

class _WaveShapePainter extends CustomPainter {
  final Color color;

  _WaveShapePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final path = Path();

    // Create a wavy arc shape
    path.addArc(
      Rect.fromCircle(center: center, radius: size.width / 2 - 4),
      0,
      math.pi * 1.5,
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WaveShapePainter oldDelegate) => false;
}
```

### Shimmer-Style Loading (Alternative)

```dart
class ShimmerLoadingIndicator extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const ShimmerLoadingIndicator({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  State<ShimmerLoadingIndicator> createState() =>
      _ShimmerLoadingIndicatorState();
}

class _ShimmerLoadingIndicatorState extends State<ShimmerLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                colorScheme.surfaceContainerHighest,
                colorScheme.surfaceContainerHigh,
                colorScheme.surfaceContainerHighest,
              ],
              stops: [
                math.max(0, _animation.value - 1),
                _animation.value,
                math.min(1, _animation.value + 1),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

### Usage Examples

```dart
class LoadingIndicatorDemo extends StatelessWidget {
  const LoadingIndicatorDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loading Indicators')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Wavy circular indicator
            const WavyLoadingIndicator(size: 48),
            
            const SizedBox(height: 32),
            
            // Rotating wave
            const RotatingWaveIndicator(size: 48),
            
            const SizedBox(height: 32),
            
            // Shimmer loading placeholder
            ShimmerLoadingIndicator(
              width: 200,
              height: 100,
              borderRadius: BorderRadius.circular(12),
            ),
            
            const SizedBox(height: 32),
            
            // Inside a card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const WavyLoadingIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Loading...',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### With Backdrop Blur (M3E Style)

```dart
import 'dart:ui';

class BlurredLoadingOverlay extends StatelessWidget {
  final Widget child;
  final bool isLoading;

  const BlurredLoadingOverlay({
    super.key,
    required this.child,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
            child: Container(
              color: Colors.black.withOpacity(0.1),
              child: const Center(
                child: WavyLoadingIndicator(size: 64),
              ),
            ),
          ),
      ],
    );
  }
}
```

## Best Practices

1. **Duration Appropriate**: Use loading indicators for < 5 seconds; progress indicators for longer
2. **Provide Context**: Show "Loading..." text when possible
3. **Centered Placement**: Usually center in available space
4. **Size Matters**: 40-48dp for inline, 56-64dp for full-screen
5. **Respect Reduced Motion**: Check `MediaQuery.disableAnimations`

## Accessibility

```dart
class AccessibleLoadingIndicator extends StatelessWidget {
  const AccessibleLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      liveRegion: true,
      child: const WavyLoadingIndicator(),
    );
  }
}
```

## Using Third-Party Packages

```yaml
# pubspec.yaml
dependencies:
  loading_animation_widget: ^1.2.0  # Various animated loaders
  shimmer: ^3.0.0                   # Shimmer effects
```

```dart
import 'package:loading_animation_widget/loading_animation_widget.dart';

LoadingAnimationWidget.waveDots(
  color: Theme.of(context).colorScheme.primary,
  size: 50,
)
```

## Android Compose Reference

```kotlin
@Composable
fun ExpressiveLoadingIndicator() {
    LoadingIndicator(
        modifier = Modifier.size(48.dp),
        color = MaterialTheme.colorScheme.primary
    )
}
```

## When to Use

- ✅ Loading content from network (< 5 seconds)
- ✅ Processing user input
- ✅ Opening a document
- ✅ Rendering complex UI
- ❌ Long-running tasks (use LinearProgressIndicator instead)
- ❌ Background sync (use notification or subtle badge)

## Related Components

- Progress Indicators: For determinate/longer progress
- Skeletons/Shimmer: For content loading placeholders
- Refresh Indicators: For pull-to-refresh patterns
