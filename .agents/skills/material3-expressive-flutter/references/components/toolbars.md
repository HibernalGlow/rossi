# Toolbars - M3 Expressive Component
 
## Overview
 
M3 Expressive toolbars are flexible, often floating elements that replace traditional bottom app bars. They provide quick access to contextual actions and can adapt their shape and size based on the content or screen state.
 
## Design Principles
 
- **Floating and Docked**: Toolbars can float above content or dock to the edges.
- **Contextual**: Show only the actions relevant to the current view or selection.
- **Expressive Shapes**: Use pill shapes or unique container shapes to distinguish from other UI elements.
- **Dynamic Sizing**: Toolbars should shrink or expand as the user interacts with them.
 
## Implementation in Flutter
 
### Floating Pill Toolbar
 
```dart
class FloatingToolbar extends StatelessWidget {
  final List<ToolbarAction> actions;
 
  const FloatingToolbar({super.key, required this.actions});
 
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
 
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: ShapeDecoration(
        color: colorScheme.surfaceContainerHigh,
        shape: const StadiumBorder(),
        shadows: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: actions.map((action) => _ToolbarItem(action: action)).toList(),
      ),
    );
  }
}
 
class _ToolbarItem extends StatelessWidget {
  final ToolbarAction action;
 
  const _ToolbarItem({required this.action});
 
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(action.icon),
      onPressed: action.onPressed,
      tooltip: action.label,
    );
  }
}
 
class ToolbarAction {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
 
  ToolbarAction({required this.icon, required this.label, required this.onPressed});
}
```
 
### Contextual Docked Toolbar
 
For multi-selection or editing modes.
 
```dart
// Use AnimatedPositioned to slide in a toolbar from the bottom
```
 
## Best Practices
 
1. **Interactive feedback**: Use scale animations on buttons when tapped.
2. **Spacing**: Keep consistent 8-12dp spacing between items.
3. **Hierarchy**: Use primary colors for the most important action in the toolbar if necessary.
4. **Touch Targets**: Ensure icons are large enough (min 24x24dp) with 48x48dp hit areas.
 
## Accessibility
 
- Ensure each action has a clear `tooltip` and `Semantics` label.
- Use `ExcludeSemantics` on decorative separators.
 
## Related Components
 
- [App Bars](app-bars.md)
- [Navigation Bar](navigation-bar.md)
- [Icon Buttons](icon-buttons.md)
