# Material 3 Expressive Flutter Skill

This skill allows the agent to build premium Flutter UIs following the Material 3 Expressive (M3E) specification.

## Core Directives

- **Motion**: Always prefer `Curves.elasticOut` or `Cubic(0.34, 1.56, 0.64, 1)` for movement. Avoid linear easing.
- **Shapes**: High-importance components should use `StadiumBorder()` (Pill shape).
- **Haptics**: Always call `HapticFeedback.lightImpact()` on primary action taps.
- **Typography**: Use `Theme.of(context).textTheme.displayLarge` for emphasized headers.

## Directory Structure

- `rules/`: Modular design guidelines (Motion, Shapes, Color, Typography).
- `scripts/`: Implementation templates like `component_template.dart`.
- `references/`: Detailed documentation and component guides.

## Component Implementation

When asked to implement a component:
1. Reference the specific guide in `references/components/`.
2. Apply the relevant rules from `rules/`.
3. Use `scripts/component_template.dart` as the code foundation.

## Trigger Phrases

- "Implement a [component] with M3 Expressive style"
- "Audit this Flutter code for M3 Expressive principles"
- "Add physics-based motion to this button"
- "Create a wavy loading indicator"
