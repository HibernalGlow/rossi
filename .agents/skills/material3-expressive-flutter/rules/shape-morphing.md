# Shape Morphing Rule

Identify and implement shapes that communicate state and personality.

## Shape Tokens
- **Stadium**: Full rounding (`StadiumBorder`). Use for buttons and primary high-importance containers.
- **Teardrop**: Asymmetric rounding. Use for emphasized items or specific brand moments.
- **Squircel**: High-curvature rounding. Use for cards and containment areas.

## Strategy: Shape Contrast
- Use contrasting shapes to separate hierarchy.
- A **Stadium** button inside a **Rounded Rectangle** card creates clear containment.
- Use **Sharp Corners** sparingly to create tension or focus.

## Implementation Standard
1. **Interpolation**: When animating between states, ensure shapes interpolate smoothly. Use `ShapeDecoration` with `lerp`.
2. **Pill Indicators**: Active states in navigation should always use a pill/stadium shape.
3. **Organic Feel**: Avoid "perfect" mathematical circles where a squircle or organic curve feels more expressive.
