# Split Buttons - M3 Expressive Component

## Overview

Split buttons are NEW in Material 3 Expressive. They combine a primary action button with a dropdown menu for related secondary actions.

## Design Principles

- **Primary Action**: Left button performs the most common/important action
- **Related Options**: Right dropdown contains contextually related alternatives
- **Visual Unity**: Both parts appear as a single cohesive component
- **Contextual**: Use when user needs quick access to default action but flexibility for alternatives

## Anatomy

```
┌─────────────────┬─────┐
│  Primary Action │  ▼  │
└─────────────────┴─────┘
```

## Implementation in Flutter

### Basic Split Button

```dart
class SplitButton extends StatefulWidget {
  final String label;
  final VoidCallback onPrimaryAction;
  final List<String> menuItems;
  final ValueChanged<int> onMenuItemSelected;
  final IconData? leadingIcon;

  const SplitButton({
    super.key,
    required this.label,
    required this.onPrimaryAction,
    required this.menuItems,
    required this.onMenuItemSelected,
    this.leadingIcon,
  });

  @override
  State<SplitButton> createState() => _SplitButtonState();
}

class _SplitButtonState extends State<SplitButton> {
  bool _isMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Leading (primary action) button
        FilledButton(
          onPressed: widget.onPrimaryAction,
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(100),
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 10,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.leadingIcon != null) ...[
                Icon(widget.leadingIcon, size: 18),
                const SizedBox(width: 8),
              ],
              Text(widget.label),
            ],
          ),
        ),
        
        // Divider
        Container(
          width: 1,
          height: 40,
          color: colorScheme.onPrimary.withOpacity(0.3),
        ),
        
        // Trailing (dropdown) button
        PopupMenuButton<int>(
          icon: Icon(
            _isMenuOpen
                ? Icons.keyboard_arrow_up
                : Icons.keyboard_arrow_down,
            color: colorScheme.onPrimary,
          ),
          onOpened: () => setState(() => _isMenuOpen = true),
          onCanceled: () => setState(() => _isMenuOpen = false),
          onSelected: (index) {
            setState(() => _isMenuOpen = false);
            widget.onMenuItemSelected(index);
          },
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.all(colorScheme.primary),
            shape: WidgetStateProperty.all(
              const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(100),
                ),
              ),
            ),
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          itemBuilder: (context) => List.generate(
            widget.menuItems.length,
            (index) => PopupMenuItem<int>(
              value: index,
              child: Text(widget.menuItems[index]),
            ),
          ),
        ),
      ],
    );
  }
}
```

### Outlined Variant

```dart
class OutlinedSplitButton extends StatefulWidget {
  final String label;
  final VoidCallback onPrimaryAction;
  final List<String> menuItems;
  final ValueChanged<int> onMenuItemSelected;

  const OutlinedSplitButton({
    super.key,
    required this.label,
    required this.onPrimaryAction,
    required this.menuItems,
    required this.onMenuItemSelected,
  });

  @override
  State<OutlinedSplitButton> createState() => _OutlinedSplitButtonState();
}

class _OutlinedSplitButtonState extends State<OutlinedSplitButton> {
  bool _isMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Leading button
          TextButton(
            onPressed: widget.onPrimaryAction,
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.primary,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(100),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 10,
              ),
            ),
            child: Text(widget.label),
          ),
          
          // Divider
          Container(
            width: 1,
            height: 24,
            color: colorScheme.outline,
          ),
          
          // Trailing dropdown
          PopupMenuButton<int>(
            icon: Icon(
              _isMenuOpen
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
              color: colorScheme.primary,
            ),
            onOpened: () => setState(() => _isMenuOpen = true),
            onCanceled: () => setState(() => _isMenuOpen = false),
            onSelected: (index) {
              setState(() => _isMenuOpen = false);
              widget.onMenuItemSelected(index);
            },
            itemBuilder: (context) => List.generate(
              widget.menuItems.length,
              (index) => PopupMenuItem<int>(
                value: index,
                child: Text(widget.menuItems[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

### Usage Examples

```dart
class SplitButtonDemo extends StatelessWidget {
  const SplitButtonDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Split Buttons')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Filled split button
            SplitButton(
              label: 'Send',
              leadingIcon: Icons.send,
              onPrimaryAction: () {
                print('Primary: Send now');
              },
              menuItems: const ['Schedule send', 'Send later', 'Save draft'],
              onMenuItemSelected: (index) {
                print('Menu item $index selected');
              },
            ),
            
            const SizedBox(height: 24),
            
            // Outlined split button
            OutlinedSplitButton(
              label: 'Download',
              onPrimaryAction: () {
                print('Download as default format');
              },
              menuItems: const ['PDF', 'DOCX', 'TXT', 'HTML'],
              onMenuItemSelected: (index) {
                final formats = ['PDF', 'DOCX', 'TXT', 'HTML'];
                print('Download as ${formats[index]}');
              },
            ),
          ],
        ),
      ),
    );
  }
}
```

### Animated Icon Rotation

```dart
class AnimatedSplitButton extends StatefulWidget {
  // ... same parameters

  @override
  State<AnimatedSplitButton> createState() => _AnimatedSplitButtonState();
}

class _AnimatedSplitButtonState extends State<AnimatedSplitButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotation;
  bool _isMenuOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _rotation = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ... similar structure, but use RotationTransition for icon:
    
    // Inside PopupMenuButton:
    return PopupMenuButton<int>(
      icon: RotationTransition(
        turns: _rotation,
        child: const Icon(Icons.keyboard_arrow_down),
      ),
      onOpened: () {
        setState(() => _isMenuOpen = true);
        _controller.forward();
      },
      onCanceled: () {
        setState(() => _isMenuOpen = false);
        _controller.reverse();
      },
      // ... rest of implementation
    );
  }
}
```

## Size Variants

M3 Expressive defines 5 sizes for split buttons:

```dart
enum SplitButtonSize {
  small,    // Height: 32dp
  medium,   // Height: 40dp (default)
  large,    // Height: 48dp
  extraLarge, // Height: 56dp
  huge,     // Height: 64dp
}

class SizedSplitButton extends StatelessWidget {
  final SplitButtonSize size;
  // ... other parameters

  EdgeInsets _getPadding() {
    switch (size) {
      case SplitButtonSize.small:
        return const EdgeInsets.symmetric(horizontal: 16, vertical: 6);
      case SplitButtonSize.medium:
        return const EdgeInsets.symmetric(horizontal: 20, vertical: 10);
      case SplitButtonSize.large:
        return const EdgeInsets.symmetric(horizontal: 24, vertical: 12);
      case SplitButtonSize.extraLarge:
        return const EdgeInsets.symmetric(horizontal: 28, vertical: 16);
      case SplitButtonSize.huge:
        return const EdgeInsets.symmetric(horizontal: 32, vertical: 20);
    }
  }

  double _getIconSize() {
    switch (size) {
      case SplitButtonSize.small:
        return 16;
      case SplitButtonSize.medium:
        return 18;
      case SplitButtonSize.large:
        return 20;
      case SplitButtonSize.extraLarge:
        return 22;
      case SplitButtonSize.huge:
        return 24;
    }
  }
  
  // Use these in button configuration
}
```

## Color Styles

```dart
enum SplitButtonStyle {
  filled,    // Solid background
  elevated,  // Raised with shadow
  tonal,     // Tinted background
  outlined,  // Border only
}
```

## Best Practices

1. **Default Action**: Most common action should be the primary button
2. **Related Options**: Menu items should be contextually related to primary action
3. **Limited Choices**: Keep dropdown to 3-7 items max
4. **Clear Labels**: Primary button text should clearly indicate action
5. **Consistent Width**: Dropdown items should align visually

## Accessibility

```dart
Semantics(
  button: true,
  label: 'Send email. Double tap to open send options',
  child: SplitButton(/* ... */),
)
```

## Android Compose Reference

```kotlin
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun SplitButtonExample() {
    var checked by remember { mutableStateOf(false) }
    
    SplitButtonLayout(
        spacing = 8.dp,
        leadingButton = {
            SplitButtonDefaults.FilledLeadingButton(
                onClick = { /* primary action */ }
            ) {
                Icon(Icons.Filled.Send, null)
                Spacer(Modifier.size(ButtonDefaults.IconSpacing))
                Text("Send")
            }
        },
        trailingButton = {
            SplitButtonDefaults.FilledTrailingButton(
                checked = checked,
                onCheckedChange = { checked = it }
            ) {
                Icon(Icons.Filled.KeyboardArrowDown, null)
            }
        }
    )
}
```

## Related Components

- Button Groups: For multiple equal-weight options
- Dropdown Buttons: For single-purpose dropdowns
- Menu Anchor: For more complex menu positioning
