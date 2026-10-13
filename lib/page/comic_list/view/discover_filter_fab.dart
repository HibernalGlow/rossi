import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zephyr/i18n/strings.g.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/widgets/spring_lens/elastic_press.dart';

class DiscoverFilterFab extends StatelessWidget {
  const DiscoverFilterFab({
    super.key,
    required this.onPressed,
    this.hasFilters = false,
  });
  final VoidCallback onPressed;
  final bool hasFilters;
  @override
  Widget build(BuildContext context) => ElasticButton(
    enabled: !MediaQuery.disableAnimationsOf(context),
    child: FloatingActionButton.extended(
      heroTag: null,
      tooltip: t.comicList.filter,
      shape: const StadiumBorder(),
      onPressed: () {
        HapticFeedback.lightImpact();
        onPressed();
      },
      icon: Badge(
        isLabelVisible: hasFilters,
        child: const GlyphIcon(AppGlyphs.sliders),
      ),
      label: Text(t.comicList.filter),
    ),
  );
}
