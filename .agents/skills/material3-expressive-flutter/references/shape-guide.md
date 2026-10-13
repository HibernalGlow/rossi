# Shape System - M3 Expressive
 
## Overview
 
Material 3 Expressive introduces a dynamic shape system that moves beyond simple rounded rectangles. Shapes are used as containers, buttons, and state indicators, focusing on fluidity and hierarchy.
 
## Design Principles
 
- **Expressive Shapes**: Use non-standard shapes (pixel triangles, teardrops, squircles) to convey brand personality.
- **Shape Hierarchy**: Larger, more complex shapes denote higher importance.
- **Fluid Morphing**: Shapes should seamlessly transition between states (e.g., FAB to Extended FAB).
- **Containment**: Use shapes to group related content clearly.
 
## Corner Token System
 
M3 uses a tokenized corner radius system:
 
| Token | Radius | Example Usage |
|-------|--------|---------------|
| `none` | 0dp | Full-width elements, square buttons |
| `extra-small` | 4dp | Tooltips, selection controls |
| `small` | 8dp | Chips, snackbars |
| `medium` | 12dp | Cards, small dialogs |
| `large` | 16dp | Extended FABs, menus |
| `extra-large` | 28dp | FABs, navigation rails/bars |
| `full` | 100% | Circular buttons, pill-shaped tags |
 
## Implementation in Flutter
 
### 1. Rounded Rectangle (Standard M3)
 
```dart
ElevatedButton(
  style: ElevatedButton.styleFrom(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16), // Large token
    ),
  ),
  onPressed: () {},
  child: const Text('Standard M3'),
)
```
 
### 2. Squircle / Continuous Corners
 
For a more premium feel, use "continuous" corners (similar to iOS) instead of standard circular arcs.
 
```dart
// Use a package or custom clipper for true squircles
Container(
  decoration: ShapeDecoration(
    shape: SmoothRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      smoothness: 1, // Full squircle
    ),
    color: Colors.blue,
  ),
  child: const Padding(
    padding: EdgeInsets.all(16),
    child: Text('Squircle Container'),
  ),
)
```
 
### 3. Teardrop Shape (Expressive)
 
Commonly used for active indicators or expressive buttons.
 
```dart
class TeardropShape extends ShapeBorder {
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;
 
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect);
 
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..moveTo(rect.left + rect.width / 2, rect.top)
      ..arcToPoint(
        Offset(rect.right, rect.top + rect.height / 2),
        radius: Radius.circular(rect.width / 2),
      )
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.left + rect.width / 2, rect.bottom)
      ..arcToPoint(
        Offset(rect.left, rect.top + rect.height / 2),
        radius: Radius.circular(rect.width / 2),
      )
      ..close();
  }
 
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
 
  @override
  ShapeBorder scale(double t) => this;
}
```
 
### 4. Shape Morphing Animation
 
```dart
class MorphingShapeButton extends StatefulWidget {
  const MorphingShapeButton({super.key});
 
  @override
  State<MorphingShapeButton> createState() => _MorphingShapeButtonState();
}
 
class _MorphingShapeButtonState extends State<MorphingShapeButton> {
  bool _isRound = true;
 
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _isRound = !_isRound),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.elasticOut,
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: Colors.deepPurple,
          borderRadius: BorderRadius.circular(_isRound ? 50 : 8),
        ),
        child: const Center(
          child: Icon(Icons.refresh, color: Colors.white),
        ),
      ),
    );
  }
}
```
 
## Best Practices
 
1. **Consistency**: Stick to a "shape family" across your app. If you use squircles, use them everywhere.
2. **Accessible Targets**: Ensure that even with expressive shapes, the touch target remains at least 48x48dp.
3. **Contrast**: Shapes should be distinguishible from their background; use subtle shadows or outlines.
4. **Performance**: Complex custom paths in `CustomPainter` should be optimized. Use `const` paths where possible.
 
## Resources
 
- [Material 3 Shapes Guidelines](https://m3.material.io/styles/shape/overview)
- [Smooth Rectangle Border Package](https://pub.dev/packages/figma_squircle)
 
## Related
 
- [Motion Guide](motion-guide.md) for shape transitions
- [Color Schemes](color-schemes.md) for container colors
