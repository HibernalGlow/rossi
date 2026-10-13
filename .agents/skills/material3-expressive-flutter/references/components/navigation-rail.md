# Navigation Rail - M3 Expressive Component
 
## Overview
 
The Navigation Rail is a side-navigation component used for medium to large screens (tablets, desktops). In M3 Expressive, it features vertical layouts with expressive active indicators and optional trailing/leading widgets.
 
## Design Principles
 
- **Vertical Hierarchy**: Top-to-bottom flow of importance.
- **Expressive Indicators**: Use pills or teardrop shapes for the active state.
- **Adaptive Width**: Can be narrow (icons only) or extended (icons + labels).
- **Secondary Actions**: Use leading/trailing areas for FABs or profile icons.
 
## Implementation in Flutter
 
### 1. Simple Navigation Rail
 
```dart
NavigationRail(
  selectedIndex: _selectedIndex,
  onDestinationSelected: (int index) {
    setState(() {
      _selectedIndex = index;
    });
  },
  labelType: NavigationRailLabelType.selected,
  destinations: const [
    NavigationRailDestination(
      icon: Icon(Icons.favorite_border),
      selectedIcon: Icon(Icons.favorite),
      label: Text('First'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.bookmark_border),
      selectedIcon: Icon(Icons.book),
      label: Text('Second'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.star_border),
      selectedIcon: Icon(Icons.star),
      label: Text('Third'),
    ),
  ],
)
```
 
### 2. Rail with FAB (M3 Style)
 
```dart
NavigationRail(
  leading: FloatingActionButton(
    elevation: 0,
    onPressed: () {},
    child: const Icon(Icons.add),
  ),
  // ... destinations
)
```
 
## Best Practices
 
1. **Responsive Design**: Switch from `NavigationBar` to `NavigationRail` when screen width exceeds 600dp.
2. **Alignment**: Items are usually top-aligned.
3. **Labels**: Use `NavigationRailLabelType.all` for maximum expressiveness if space allows.
 
## Related Components
 
- [Navigation Bar](navigation-bar.md)
- [Toolbars](toolbars.md)
- [FAB Menu](fab-menu.md)
