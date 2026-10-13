# Motion Guide - M3 Expressive

## Overview

Material 3 Expressive introduces physics-based motion that feels natural, fluid, and alive. Motion uses spring-physics to mirror real-world object behavior.

## Two Types of Springs

### 1. Spatial Springs
**Purpose**: Object movement and position changes  
**Characteristics**: Natural bounce, overshoot, settle  
**Use for**: Entering/exiting animations, drag interactions, page transitions

### 2. Effects Springs
**Purpose**: Visual property changes (color, opacity, scale)  
**Characteristics**: Smooth, seamless transitions  
**Use for**: Color shifts, fade in/out, scale changes

## Spring Physics in Flutter

### Using Curves.elasticOut (Approximates Spatial Spring)

```dart
AnimatedContainer(
  duration: const Duration(milliseconds: 600),
  curve: Curves.elasticOut, // Springy overshoot
  // ... properties
)
```

### Custom Spring Simulation

```dart
import 'package:flutter/physics.dart';

class SpringyAnimationController extends StatefulWidget {
  const SpringyAnimationController({super.key});

  @override
  State<SpringyAnimationController> createState() =>
      _SpringyAnimationControllerState();
}

class _SpringyAnimationControllerState extends State<SpringyAnimationController>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // Create spring simulation
    final spring = SpringDescription(
      mass: 1.0,        // Object mass
      stiffness: 100.0, // Spring stiffness (higher = stiffer)
      damping: 10.0,    // Damping ratio (higher = less bounce)
    );

    final simulation = SpringSimulation(spring, 0.0, 1.0, 0.0);

    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Cubic(0.34, 1.56, 0.64, 1), // Custom spring curve
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _trigger() {
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: FloatingActionButton(
        onPressed: _trigger,
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

### Expressive Button Press Animation

```dart
class SpringyButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget child;

  const SpringyButton({
    super.key,
    required this.onPressed,
    required this.child,
  });

  @override
  State<SpringyButton> createState() => _SpringyButtonState();
}

class _SpringyButtonState extends State<SpringyButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.elasticOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onPressed();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}
```

### Color Transition (Effects Spring)

```dart
class ColorTransitionButton extends StatefulWidget {
  const ColorTransitionButton({super.key});

  @override
  State<ColorTransitionButton> createState() => _ColorTransitionButtonState();
}

class _ColorTransitionButtonState extends State<ColorTransitionButton> {
  bool _isActive = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut, // Smooth for color (Effects Spring)
      decoration: BoxDecoration(
        color: _isActive
            ? colorScheme.primaryContainer
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: _isActive
              ? colorScheme.primary
              : colorScheme.outline,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _isActive = !_isActive),
          borderRadius: BorderRadius.circular(100),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 12,
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              style: TextStyle(
                color: _isActive
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurface,
                fontWeight: _isActive ? FontWeight.bold : FontWeight.normal,
              ),
              child: const Text('Toggle Me'),
            ),
          ),
        ),
      ),
    );
  }
}
```

### Page Transition with Spring

```dart
class SpringPageRoute extends PageRouteBuilder {
  final Widget page;

  SpringPageRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Spatial spring for page movement
            const curve = Curves.elasticOut;
            var curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: curve,
            );

            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeIn, // Effects spring for fade
                  ),
                ),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 600),
        );
}

// Usage:
Navigator.of(context).push(
  SpringPageRoute(page: const DetailsPage()),
);
```

## Common M3 Expressive Curves

```dart
// Spatial springs (movement)
Curves.elasticOut      // Strong bounce
Curves.elasticInOut    // Bounce both ways
Curves.bounceOut       // Pronounced bounce
Cubic(0.34, 1.56, 0.64, 1)  // Custom expressive curve

// Effects springs (properties)
Curves.easeOutCubic    // Smooth deceleration
Curves.easeInOut       // Smooth both ways
Curves.fastOutSlowIn   // Material standard
```

## Morphing Shapes

```dart
class MorphingButton extends StatefulWidget {
  const MorphingButton({super.key});

  @override
  State<MorphingButton> createState() => _MorphingButtonState();
}

class _MorphingButtonState extends State<MorphingButton> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.elasticOut,
      width: _isExpanded ? 200 : 56,
      height: 56,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(_isExpanded ? 28 : 28),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(28),
          child: Center(
            child: _isExpanded
                ? const Text(
                    'Extended FAB',
                    style: TextStyle(color: Colors.white),
                  )
                : const Icon(Icons.add, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
```

## Hero Animations with Spring

```dart
class SpringHero extends StatelessWidget {
  const SpringHero({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) {
              return const DetailPage();
            },
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
          ),
        );
      },
      child: Hero(
        tag: 'expressive-hero',
        createRectTween: (begin, end) {
          return MaterialRectCenterArcTween(begin: begin, end: end);
        },
        flightShuttleBuilder: (
          flightContext,
          animation,
          direction,
          fromContext,
          toContext,
        ) {
          return ScaleTransition(
            scale: Tween<double>(begin: 1.0, end: 1.1).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.elasticOut,
              ),
            ),
            child: toContext.widget,
          );
        },
        child: Container(
          width: 100,
          height: 100,
          color: Colors.blue,
        ),
      ),
    );
  }
}
```

## Best Practices

1. **Choose the Right Spring**:
   - Spatial springs for position/layout changes
   - Effects springs for visual properties

2. **Duration Guidelines**:
   - Quick interactions: 200-300ms
   - Standard transitions: 300-500ms
   - Page transitions: 500-700ms
   - Dramatic effects: 700-1000ms

3. **Overshoot Carefully**:
   - Use elastic curves sparingly
   - Avoid for subtle interactions
   - Great for celebratory moments

4. **Respect Reduced Motion**:
```dart
final reduceMotion = MediaQuery.of(context).disableAnimations;
final duration = reduceMotion
    ? Duration.zero
    : const Duration(milliseconds: 400);
```

5. **Performance**:
   - Use `RepaintBoundary` for complex animations
   - Prefer `Transform` over layout changes
   - Profile with DevTools Timeline

## Stagger Animations

```dart
class StaggeredListAnimation extends StatelessWidget {
  final List<Widget> children;

  const StaggeredListAnimation({
    super.key,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: children.asMap().entries.map((entry) {
        final index = entry.key;
        final child = entry.value;
        
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 300 + (index * 100)),
          curve: Curves.elasticOut,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 50 * (1 - value)),
              child: Opacity(
                opacity: value,
                child: child,
              ),
            );
          },
          child: child,
        );
      }).toList(),
    );
  }
}
```

## Resources

- [Flutter Animations Guide](https://docs.flutter.dev/ui/animations)
- [Material Motion System](https://m3.material.io/styles/motion/overview)
- [Spring Physics Package](https://pub.dev/packages/spring)

## Testing Animations

```dart
testWidgets('Button has springy animation', (tester) async {
  await tester.pumpWidget(const MyApp());
  
  // Find button
  final button = find.byType(SpringyButton);
  
  // Tap and pump frames
  await tester.tap(button);
  await tester.pump(); // Start
  await tester.pump(const Duration(milliseconds: 150)); // Mid
  await tester.pump(const Duration(milliseconds: 150)); // End
  
  // Verify animation occurred
});
```
