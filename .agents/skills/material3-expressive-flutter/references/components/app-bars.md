# App Bars - M3 Expressive Component
 
## Overview
 
App bars in M3 Expressive focus on clarity and accessibility. They often feature larger touch targets, more expressive typography, and can morph into search bars or other functional elements.
 
## Design Principles
 
- **Hierarchical Titles**: Use `titleLarge` for primary views and `titleMedium` for sub-sections.
- **Expressive Search**: Search-integrated app bars are a core pattern.
- **Surface Elevation**: Use color and subtle shadows to separate the app bar from content.
- **Responsive Heights**: Heights can vary based on scroll state (e.g., shrinking on scroll).
 
## Implementation in Flutter
 
### Expressive Search App Bar
 
```dart
class SearchAppBar extends StatelessWidget implements PreferredSizeWidget {
  final TextEditingController controller;
 
  const SearchAppBar({super.key, required this.controller});
 
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
 
    return AppBar(
      title: SearchBar(
        controller: controller,
        hintText: 'Search...',
        leading: const Icon(Icons.search),
        elevation: WidgetStateProperty.all(0),
        backgroundColor: WidgetStateProperty.all(colorScheme.surfaceContainerHigh),
        shape: WidgetStateProperty.all(const StadiumBorder()),
      ),
      centerTitle: true,
    );
  }
 
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 16);
}
```
 
### Large/Medium App Bars
 
Use Flutter's built-in `SliverAppBar.large` or `SliverAppBar.medium` for expressive titles.
 
```dart
SliverAppBar.large(
  title: const Text('Expressive Page'),
  actions: [
    IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
  ],
)
```
 
## Best Practices
 
1. **Scrolling behavior**: Use `pinned: true` or `floating: true` appropriately in `CustomScrollView`.
2. **Action limits**: Keep actions to 3 max. Use an overflow menu for more.
3. **Contrast**: Ensure text/icons have at least 4.5:1 contrast against the app bar surface.
 
## Related Components
 
- [Toolbars](toolbars.md)
- [Typography](../typography-guide.md)
- [Navigation Bar](navigation-bar.md)
