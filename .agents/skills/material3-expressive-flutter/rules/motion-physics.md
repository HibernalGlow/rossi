# Motion Physics Rule

All M3 Expressive animations must use physics-based springs instead of fixed durations/easing where possible.

## Spatial Springs
Use for movement, position, and layout changes.
- **Goal**: Mirror real-world object physics.
- **Flutter Implementation**: `Curves.elasticOut`, `Curves.bounceOut`, or `SpringSimulation`.
- **Primary Curve**: `Cubic(0.34, 1.56, 0.64, 1)` (The Expressive Curve).

## Effects Springs
Use for non-spatial properties like color, opacity, and scale.
- **Goal**: Smooth, responsive transitions.
- **Flutter Implementation**: `Curves.easeInOutCubic` or `Curves.fastOutSlowIn`.

## Standards
1. **Interactive Feedback**: All touch interactions must trigger a scale or translation response using a Spatial spring.
2. **Speed**: Response must be immediate (<50ms start) even if the settling takes longer.
3. **Co-ordination**: Co-ordinate visual motion with `HapticFeedback.lightImpact()`.
