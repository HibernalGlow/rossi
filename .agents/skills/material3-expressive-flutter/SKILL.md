---
name: material3-expressive-flutter
description: Expert guidance for building Material 3 Expressive (M3E) Flutter apps. Use when implementing expressive motion, dynamic shapes, and premium components like FAB menus and toolbars.
---

# Material 3 Expressive Flutter

This skill provides comprehensive patterns, scripts, and rules for implementing the **Material 3 Expressive** design system in Flutter. It focuses on physics-based motion, organic shapes, and engagement-driven components.

## How It Works

1.  **Requirement Analysis**: When you ask about M3E, the agent analyzes the context (component type, state, importance).
2.  **Rule Application**: It applies rules from `rules/` (Motion Physics, Shape Morphing) to ensure design compliance.
3.  **Code Generation**: It uses the `scripts/component_template.dart` as a base for premium, accessible, and high-performance components.
4.  **Verification**: It audits the output against M3E principles like "Spatial vs Effects Springs" and "Shape Contrast".

## When to Use

-   **New Feature Development**: When creating components requiring high user engagement (promos, onboarding, key actions).
-   **Design Modernization**: Updating standard M3 apps to the more fluid, expressive style.
-   **Expressive Motion**: Implementing spring-based animations for a natural feel.
-   **Custom Shapes**: Implementing morphing containers or non-standard rounded shapes.

## Usage

### 1. Scaffold a New Component
Use the template to create a robust, state-aware widget.
```bash
# Path to script
flutter run scripts/component_template.dart
```

### 2. Implementation Strategies
Trigger phrases:
- "Implement a [component] with M3 Expressive style"
- "Add expressive motion to this transition"
- "Modernize this standard M3 button"
- "Audit my UI against M3 Expressive principles"

## Examples

### Spatial Spring Motion (Example)
```dart
// Use for movement and position
Curves.elasticOut; // Strong, tactile response
Cubic(0.34, 1.56, 0.64, 1); // Expressive overshoot
```

### Shape Morphing Container
```dart
AnimatedContainer(
  duration: const Duration(milliseconds: 500),
  curve: Curves.elasticOut,
  decoration: ShapeDecoration(
    shape: M3ExpressiveShape.teardrop, // Custom token
    color: theme.colorScheme.primaryContainer,
  ),
);
```

## Reference Guides

-   [Motion Guide](references/motion-guide.md) - Spatial vs Effects Springs.
-   [Shape System](references/shape-guide.md) - Squircels, Teardrops, and Morphing.
-   [Typography Guide](references/typography-guide.md) - Editorial hierarchy.
-   [Component Library](references/components/) - Patterns for all M3E components.

## Rules & Standards

1.  **Physics Over Duration**: Use springs (Spatial/Effects) instead of fixed durations.
2.  **Full Rounding**: Use `StadiumBorder()` for buttons and primary indicators.
3.  **Meaningful Feedback**: Always include `HapticFeedback.lightImpact()` for expressive actions.
4.  **Accessibility**: Ensure minimum touch targets of 48x48dp and proper `Semantics`.

## Troubleshooting

-   **"Animation feels jittery"**: Ensure you aren't using `Curves.linear` or too short a duration (<200ms) with springs.
-   **"Shape doesn't morph correctly"**: Ensure you are using `ShapeDecoration` with a custom `ShapeBorder` that supports interpolation.
-   **"UI feels flat"**: Check color contrast and ensure you are using filled containers for primary actions.

## Present Results to User
When completing an M3E task, summarize the expressive features added:
- ✅ **Motion**: Applied [Spatial/Effects] springs for [Action].
- ✅ **Shape**: Used [Pill/Teardrop/Squircel] for [Component].
- ✅ **Haptics**: Integrated tactile feedback.
- ✅ **Color**: Dynamic M3 color tokens used.
- ✅ **Accessibility**: Verified touch targets and semantics.
