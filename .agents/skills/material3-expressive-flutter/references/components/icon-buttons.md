# Icon Buttons - M3 Expressive Component
 
## Overview
 
Icon buttons in M3 Expressive prioritize touch target size and visual clarity. They come in several variants: standard, filled, tonal, and outlined.
 
## Variants
 
- **Standard**: No container, low visual emphasis.
- **Filled**: High emphasis, solid color background.
- **Tonal**: Lightly colored background, balanced emphasis.
- **Outlined**: Explicit border, medium emphasis.
 
## Implementation in Flutter
 
### 1. Filled Icon Button (Expressive)
 
```dart
IconButton.filled(
  iconSize: 24,
  style: IconButton.styleFrom(
    backgroundColor: Theme.of(context).colorScheme.primary,
    foregroundColor: Theme.of(context).colorScheme.onPrimary,
    minimumSize: const Size(48, 48), // Ensure touch target
  ),
  onPressed: () {},
  icon: const Icon(Icons.add),
)
```
 
### 2. Tonal Icon Button
 
```dart
IconButton.filledTonal(
  onPressed: () {},
  icon: const Icon(Icons.favorite),
)
```
 
### 3. Outlined Icon Button
 
```dart
IconButton.outlined(
  onPressed: () {},
  icon: const Icon(Icons.share),
)
```
 
## Best Practices
 
1. **Minimum Hit Area**: Always maintain at least a 48x48dp hit area, even if the icon is smaller.
2. **Visual Consistency**: Use filled variants for primary actions and standard/outlined for secondary ones.
3. **Accessibility Labels**: Every icon button MUST have a `tooltip` or `Semantics` label.
 
## Related Components
 
- [Common Buttons](buttons.md)
- [Toolbars](toolbars.md)
- [FAB Menu](fab-menu.md)
