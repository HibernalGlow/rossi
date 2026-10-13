# Common Buttons - M3 Expressive
 
## Overview
 
Common buttons (Elevated, Filled, Tonal, Outlined, Text) are updated in M3 Expressive with larger sizes, fuller rounding, and more tactile feedback.
 
## Button Types
 
| Type | Use Case | Expressive Enhancement |
|------|----------|------------------------|
| **Filled** | Highest importance actions | Full rounding (`StadiumBorder`), high contrast |
| **Filled Tonal** | Secondary importance | Softer color interaction, tonal balance |
| **Elevated** | High importance with depth | Subtle shadows, expressive elevation shifts |
| **Outlined** | Medium importance, less visual weight | Crisp outlines, clear states |
| **Text** | Lowest importance, inline actions | Emphasized text weights |
 
## Implementation in Flutter
 
### 1. High-Emphasis Expressive Button
 
```dart
FilledButton(
  style: FilledButton.styleFrom(
    minimumSize: const Size(0, 56), // Larger height
    shape: const StadiumBorder(),   // Full rounding
  ),
  onPressed: () {},
  child: const Text('Primary Action'),
)
```
 
### 2. Springy Tonal Button
 
```dart
class SpringyTonalButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
 
  const SpringyTonalButton({super.key, required this.label, required this.onPressed});
 
  @override
  State<SpringyTonalButton> createState() => _SpringyTonalButtonState();
}
 
class _SpringyTonalButtonState extends State<SpringyTonalButton> {
  bool _isPressed = false;
 
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: FilledButton.tonal(
          onPressed: null, // Managed by GestureDetector for animation
          style: FilledButton.styleFrom(
            disabledBackgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            disabledForegroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
            shape: const StadiumBorder(),
          ),
          child: Text(widget.label),
        ),
      ),
    );
  }
}
```
 
## Best Practices
 
1. **Size-Based Hierarchy**: Reserve large buttons for primary calls to action.
2. **Standard heights**: 40dp (Small), 48dp (Regular), 56dp (Large).
3. **Pill-shaped as Default**: Prefer `StadiumBorder` for most buttons in M3E.
4. **Micro-interactions**: Use `InkWell` or custom scale animations for tactile feedback.
 
## Related
 
- [Icon Buttons](icon-buttons.md)
- [Split Buttons](split-buttons.md)
- [Button Groups](button-groups.md)
- [Motion Guide](../motion-guide.md)
