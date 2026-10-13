# FAB Menu - M3 Expressive Component
 
## Overview
 
The FAB Menu is an expressive pattern where a Floating Action Button (FAB) expands to reveal multiple related actions. It uses springy animations and shape morphing to create a seamless transition from a single button to a list of actions.
 
## Design Principles
 
- **Primary Action Focus**: The main FAB should represent the most common action.
- **Organic Expansion**: Use spatial springs for the expansion animation so it feels like it's growing.
- **Clear Secondary Actions**: Actions revealed should be clearly labeled or have distinct icons.
- **Dismissability**: Users should be able to easily collapse the menu by tapping the main button again or tapping outside.
 
## Implementation in Flutter
 
### Basic FAB Menu
 
```dart
class ExpressiveFabMenu extends StatefulWidget {
  const ExpressiveFabMenu({super.key});
 
  @override
  State<ExpressiveFabMenu> createState() => _ExpressiveFabMenuState();
}
 
class _ExpressiveFabMenuState extends State<ExpressiveFabMenu>
    with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  late AnimationController _controller;
  late Animation<double> _expandAnimation;
 
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      value: _isOpen ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      curve: Curves.fastOutSlowIn,
      reverseCurve: Curves.easeOutQuad,
      parent: _controller,
    );
  }
 
  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }
 
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildStep(0, Icons.camera, 'Camera'),
        _buildStep(1, Icons.photo, 'Gallery'),
        _buildStep(2, Icons.videocam, 'Video'),
        const SizedBox(height: 16),
        FloatingActionButton.large(
          onPressed: _toggle,
          child: AnimatedIcon(
            icon: AnimatedIcons.menu_close,
            progress: _expandAnimation,
          ),
        ),
      ],
    );
  }
 
  Widget _buildStep(int index, IconData icon, String label) {
    return SizeTransition(
      sizeFactor: _expandAnimation,
      child: FadeTransition(
        opacity: _expandAnimation,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(label),
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton.small(
                onPressed: () {},
                heroTag: 'fab_$index',
                child: Icon(icon),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```
 
### Advanced Morphing FAB (tofu_expressive style)
 
For a more expressive feel, the main FAB can morph into a larger container.
 
```dart
// Placeholder for morphing logic
// Use AnimatedContainer + Stack to transition FAB into a menu surface
```
 
## Best Practices
 
1. **Limit Actions**: Don't exceed 5 secondary actions to avoid clutter.
2. **Animation Speed**: Expansion should be fast (200-300ms) to feel responsive.
3. **Accessibility**: Use `Semantics` to label the menu state (e.g., "Expand actions menu" vs "Collapse actions menu").
4. **Scrim**: Consider adding a subtle scrim (darkened background) when the menu is open to focus attention.
 
## Accessibility
 
```dart
Semantics(
  label: _isOpen ? 'Close menu' : 'Open action menu',
  button: true,
  child: FloatingActionButton(...),
)
```
 
## Android Compose Reference
 
```kotlin
@Composable
fun ExpressiveFabMenu() {
    // Jetpack Compose implementation using AnimatedVisibility and FAB
}
```
 
## Related Components
 
- [Split Buttons](split-buttons.md)
- [Button Groups](button-groups.md)
- [Toolbars](toolbars.md)
