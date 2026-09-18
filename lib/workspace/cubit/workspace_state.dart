import 'package:flutter/foundation.dart';
import 'package:zephyr/workspace/model/workspace_layout_config.dart';
import 'package:zephyr/workspace/model/workspace_mode.dart';

@immutable
class WorkspaceState {
  final WorkspaceMode mode;
  final WorkspaceLayoutConfig layout;
  final Map<String, bool> cardExpanded;

  const WorkspaceState({
    required this.mode,
    required this.layout,
    required this.cardExpanded,
  });

  factory WorkspaceState.initial() {
    return WorkspaceState(
      mode: WorkspaceMode.swimlane,
      layout: WorkspaceLayoutConfig.defaults(),
      cardExpanded: const {
        'favorite': true,
        'history': true,
        'download': true,
        'discover_plugins': true,
        'discover_tags': false,
        'local_tree': true,
        'system_status': true,
      },
    );
  }

  WorkspaceState copyWith({
    WorkspaceMode? mode,
    WorkspaceLayoutConfig? layout,
    Map<String, bool>? cardExpanded,
  }) {
    return WorkspaceState(
      mode: mode ?? this.mode,
      layout: layout ?? this.layout,
      cardExpanded: cardExpanded ?? this.cardExpanded,
    );
  }
}
