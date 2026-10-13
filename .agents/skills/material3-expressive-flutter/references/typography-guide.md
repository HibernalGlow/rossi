# Typography - M3 Expressive
 
## Overview
 
Typography in Material 3 Expressive is about more than just readability; it's about establishing hierarchy and conveying emotion. M3E introduces emphasized styles and a stronger focus on the "editorial" look.
 
## Design Principles
 
- **Hierarchy through Size**: Use large scale differences to separate headings from body text.
- **Weight as Emphasis**: Utilize variable fonts or bold weights for primary actions and key data points.
- **Readable on Any Surface**: Ensure high contrast regardless of the container color.
- **Editorial Feel**: Treat UI text layout like a high-end magazine or editorial design.
 
## Type Scale
 
M3 uses a standard type scale with 15 styles:
 
| Class | Style | Size | Weight | Use Case |
|-------|-------|------|--------|----------|
| **Display** | Large | 57pt | Regular | Hero headings |
| | Medium | 45pt | Regular | Large page titles |
| | Small | 36pt | Regular | Featured content |
| **Headline** | Large | 32pt | Regular | Page headers |
| | Medium | 28pt | Regular | Section headers |
| | Small | 24pt | Regular | Sub-sections |
| **Title** | Large | 22pt | Regular | App bar titles |
| | Medium | 16pt | Medium | Card titles |
| | Small | 14pt | Medium | List item titles |
| **Label** | Large | 14pt | Medium | Button text, chips |
| | Medium | 12pt | Medium | Tabs, small buttons |
| | Small | 11pt | Medium | Captions, badges |
| **Body** | Large | 16pt | Regular | Primary body text |
| | Medium | 14pt | Regular | Secondary text |
| | Small | 12pt | Regular | Tertiary text |
 
## Expressive Enhancements
 
### 1. Emphasized Text Styles
 
For the most important actions, use "Emphasized" variants which often include bold weights and slightly larger sizes.
 
```dart
Text(
  'URGENT ACTION',
  style: Theme.of(context).textTheme.labelLarge?.copyWith(
    fontWeight: FontWeight.w900,
    letterSpacing: 1.2,
    color: Theme.of(context).colorScheme.error,
  ),
)
```
 
### 2. Variable Fonts
 
If available, use variable fonts to transition weight during interaction (e.g., bolding a button label when pressed).
 
```dart
AnimatedDefaultTextStyle(
  style: TextStyle(
    fontVariations: [FontVariation('wght', _isPressed ? 700 : 400)],
  ),
  duration: const Duration(milliseconds: 200),
  child: const Text('Responsive Label'),
)
```
 
## Implementation in Flutter
 
### Accessing Typography
 
```dart
final textTheme = Theme.of(context).textTheme;
 
Text('Title', style: textTheme.titleLarge);
Text('Body', style: textTheme.bodyMedium);
```
 
### Customizing the Type Scale
 
```dart
ThemeData(
  useMaterial3: true,
  textTheme: const TextTheme(
    displayLarge: TextStyle(fontSize: 64, fontWeight: FontWeight.bold),
    // ... other overrides
  ),
)
```
 
## Best Practices
 
1. **Limit Font Families**: Use 1-2 font families max. Use weight and size for variety.
2. **Line Height**: Ensure comfortable leading (1.2x to 1.5x font size) for long-form text.
3. **Tracking (Letter Spacing)**: Use tighter tracking for large displays and looser for small labels.
4. **Accessibility**: Never go below 12pt for body content. Ensure 4.5:1 contrast ratio.
 
## Resources
 
- [Material 3 Typography Guidelines](https://m3.material.io/styles/typography/overview)
- [Google Fonts for Flutter](https://pub.dev/packages/google_fonts)
 
## Related
 
- [Color Schemes](color-schemes.md) for text coloring
- [Component Template](../scripts/component_template.dart) for text implementation examples
