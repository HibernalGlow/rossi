# Button Groups - M3 Expressive Component

## Overview

Button groups are NEW in Material 3 Expressive. They allow users to select one or more options from a related set of choices with consistent styling.

## Design Principles

- **Related Actions**: Group buttons that perform similar or related functions
- **Clear Selection States**: Active/inactive states must be immediately obvious
- **Consistent Spacing**: Buttons should be visually connected but distinguishable

## Implementation in Flutter

### Basic Button Group (Custom Implementation)

```dart
class ButtonGroup extends StatefulWidget {
  final List<String> options;
  final List<bool> initialSelection;
  final ValueChanged<List<bool>> onSelectionChanged;
  final bool multiSelect;

  const ButtonGroup({
    super.key,
    required this.options,
    required this.initialSelection,
    required this.onSelectionChanged,
    this.multiSelect = false,
  });

  @override
  State<ButtonGroup> createState() => _ButtonGroupState();
}

class _ButtonGroupState extends State<ButtonGroup> {
  late List<bool> _selection;

  @override
  void initState() {
    super.initState();
    _selection = List.from(widget.initialSelection);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(widget.options.length, (index) {
        final isFirst = index == 0;
        final isLast = index == widget.options.length - 1;
        final isSelected = _selection[index];

        return Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: colorScheme.outline,
              width: 1,
            ),
            borderRadius: BorderRadius.horizontal(
              left: isFirst ? const Radius.circular(100) : Radius.zero,
              right: isLast ? const Radius.circular(100) : Radius.zero,
            ),
            color: isSelected
                ? colorScheme.secondaryContainer
                : colorScheme.surface,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  if (widget.multiSelect) {
                    _selection[index] = !_selection[index];
                  } else {
                    _selection = List.generate(
                      widget.options.length,
                      (i) => i == index,
                    );
                  }
                });
                widget.onSelectionChanged(_selection);
              },
              borderRadius: BorderRadius.horizontal(
                left: isFirst ? const Radius.circular(100) : Radius.zero,
                right: isLast ? const Radius.circular(100) : Radius.zero,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
                child: Text(
                  widget.options[index],
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: isSelected
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
```

### Usage Example

```dart
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<bool> _selection = [true, false, false];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Button Groups')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Single select
            ButtonGroup(
              options: const ['Option 1', 'Option 2', 'Option 3'],
              initialSelection: _selection,
              onSelectionChanged: (selection) {
                setState(() => _selection = selection);
              },
            ),
            const SizedBox(height: 24),
            // Multi select
            ButtonGroup(
              options: const ['Coffee', 'Tea', 'Juice'],
              initialSelection: [false, false, false],
              multiSelect: true,
              onSelectionChanged: (selection) {
                print('Multi-select: $selection');
              },
            ),
          ],
        ),
      ),
    );
  }
}
```

### With Icons

```dart
class IconButtonGroup extends StatelessWidget {
  final List<IconData> icons;
  final List<String> labels;
  final List<bool> selection;
  final ValueChanged<int> onPressed;

  const IconButtonGroup({
    super.key,
    required this.icons,
    required this.labels,
    required this.selection,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(icons.length, (index) {
        return _buildIconButton(context, index);
      }),
    );
  }

  Widget _buildIconButton(BuildContext context, int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = selection[index];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        selected: isSelected,
        label: Row(
          children: [
            Icon(
              icons[index],
              size: 18,
              color: isSelected
                  ? colorScheme.onSecondaryContainer
                  : colorScheme.onSurface,
            ),
            const SizedBox(width: 8),
            Text(labels[index]),
          ],
        ),
        onSelected: (_) => onPressed(index),
      ),
    );
  }
}
```

## Best Practices

1. **Limit Options**: Keep button groups to 2-5 options for clarity
2. **Equal Importance**: Only use when options have roughly equal importance
3. **Short Labels**: Keep text concise (1-2 words ideal)
4. **Accessible Touch Targets**: Minimum 48x48 dp hit areas
5. **Visual Feedback**: Show hover/press states for better UX

## Accessibility

```dart
// Add semantics for screen readers
Semantics(
  button: true,
  label: 'Select ${widget.options[index]}',
  selected: isSelected,
  child: // ... button widget
)
```

## Android Compose Reference

For comparison, here's how it looks in Jetpack Compose (M3E is implemented):

```kotlin
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun ExpressiveButtonGroup() {
    val checked = remember { mutableStateListOf(false, false, false) }
    
    ButtonGroup(
        modifier = Modifier.padding(8.dp),
        overflowIndicator = {}
    ) {
        options.forEachIndexed { index, label ->
            toggleableItem(
                checked = checked[index],
                onCheckedChange = { checked[index] = it },
                label = label,
                icon = { Icon(icons[index], null) }
            )
        }
    }
}
```

## Related Components

- Split Buttons: For primary + secondary action pairs
- Segmented Buttons: Flutter's `SegmentedButton` widget (similar but not M3E)
- Toggle Buttons: Use `ToggleButtons` for simpler cases
