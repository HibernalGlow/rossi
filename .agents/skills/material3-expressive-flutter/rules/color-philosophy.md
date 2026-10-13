# Color Philosophy Rule

M3 Expressive uses color to drive engagement and emotional impact.

## Principles
1. **Dynamic Color**: Always support `ColorScheme.fromSeed` or `dynamic_color` package if on Android.
2. **Vibrancy**: Use high-saturation "On-Container" colors for primary expressive elements.
3. **Hierarchy**: Use `primaryContainer` for high-importance actions and `surfaceContainer` for secondary grouping.
4. **Contrast**: Ensure AA/AAA contrast levels even when using expressive color blending.

## Application
- **Buttons**: Use `FilledButton` (Primary Container) for expressive actions.
- **Indicators**: Use `secondaryContainer` for selection indicators to provide clear but non-overwhelming state.
- **Micro-interactions**: Use subtle color shifts (surface -> surface-variant) for hover states.
