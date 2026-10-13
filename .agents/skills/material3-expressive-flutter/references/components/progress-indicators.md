# Progress Indicators - M3 Expressive Component
 
## Overview
 
Progress indicators in M3 Expressive provide visual feedback for determinate or long-running tasks (>5 seconds). The expressive variant often includes wavy paths or organic animations.
 
## Types
 
- **Determinate**: Shows specific progress (0-100%).
- **Indeterminate**: Shows continuous activity without a specific end.
- **Wavy Progress**: Expressive variant with organic wave motion.
 
## Implementation in Flutter
 
### 1. Standard Linear Progress
 
```dart
LinearProgressIndicator(
  value: _progressValue,
  backgroundColor: colorScheme.surfaceVariant,
  color: colorScheme.primary,
  minHeight: 8,
  borderRadius: BorderRadius.circular(4),
)
```
 
### 2. Wavy Linear Progress (Custom implementation)
 
```dart
// Placeholder for Wavy Linear Progress
// Similar to WavyLoadingIndicator but linear
```
 
## Best Practices
 
1. **Determinate over Indeterminate**: Whenever possible, show exact progress.
2. **Placement**: Usually placed at the top of a container or pinned to the bottom of an app bar.
3. **Smoothness**: Animate the `value` property using `TweenAnimationBuilder` to avoid jumps.
 
## Related Components
 
- [Loading Indicators](loading-indicators.md)
- [Shimmers](../packages.md)
