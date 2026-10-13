# Navigation Bar - M3 Expressive Component
 
## Overview
 
The Navigation Bar (Bottom Navigation) in M3 Expressive features larger active indicators, expressive shapes (like pills), and improved label hierarchy.
 
## Design Principles
 
- **Clear Active State**: The selected item should be strikingly different (e.g., inside a pill container).
- **Smooth Transitions**: Animate the active indicator and label property changes.
- **Expressive Motion**: Use scale and fade for switching views.
- **Hierarchy**: Use labels for all items if space allows, otherwise only for the active item (less expressive).
 
## Implementation in Flutter
 
### 1. Standard M3 Navigation Bar
 
```dart
NavigationBar(
  selectedIndex: _currentIndex,
  onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
  destinations: const [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.search),
      label: 'Search',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: 'Profile',
    ),
  ],
)
```
 
### 2. Expressive Active Indicator Customize
 
```dart
ThemeData(
  navigationBarTheme: NavigationBarThemeData(
    indicatorColor: colorScheme.secondaryContainer,
    indicatorShape: const StadiumBorder(),
  ),
)
```
 
## Best Practices
 
1. **Item Count**: Use 3-5 destinations. For more, use a Navigation Rail or Drawer.
2. **Icons vs Labels**: Use icons that are meaningful. If labels are hidden, icons must be unmistakable.
3. **Badge integration**: Use `Badge` widgets to show updates or notifications on nav items.
 
## Related Components
 
- [Navigation Rail](navigation-rail.md)
- [Toolbars](toolbars.md)
- [App Bars](app-bars.md)
