part of '../video_page_surface.dart';

extension _VideoPageControlsPart on _VideoPageSurfaceState {
  void _togglePin() {
    setState(() => _pinned = !_pinned);
    // 取消固定、关弹层、恢复播放都必须重新计时，不能依赖下一次鼠标移动。
    _revealControls();
    unawaited(_persistPinned(_pinned));
  }

  Future<void> _persistPinned(bool value) async {
    final store = VideoSettingsStore.instance;
    await store.save((await store.load()).copyWith(controlsPinned: value));
  }

  Future<void> _persistSubtitleStyle(VideoSubtitleStyle style) async {
    final store = VideoSettingsStore.instance;
    await store.save((await store.load()).copyWith(subtitleStyle: style));
  }

  void _publishBottomControls(bool visible) {
    final scope = _bottomControlsScope;
    final controller = _controller;
    if (scope == null || controller == null) return;
    if (!widget.active) {
      scope.slot.release(this);
      return;
    }
    scope.slot.publish(
      ReaderVideoControls(
        owner: this,
        isCurrent: () =>
            mounted &&
            widget.active &&
            identical(_controller, controller) &&
            identical(_bottomControlsScope?.slot, scope.slot),
        pinned: _pinned,
        visible: visible,
        panelsOpen: _panelsOpen,
        builder: (embedded, visible) => ListenableBuilder(
          listenable: _controlsState,
          builder: (context, _) =>
              mounted && widget.active && identical(_controller, controller)
              ? _buildVideoControls(embedded: embedded, visible: visible)
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _buildVideoControls({required bool embedded, required bool visible}) {
    final controller = _controller!;
    final transport = _transport!;
    final snapshot = controller.snapshot;
    return VideoControlOverlay(
      snapshot: snapshot,
      progressUpdates: visible,
      embedded: embedded,
      onScrubChanged: (scrubbing) =>
          _panelsOpen.setOpen(_scrubPanel, scrubbing),
      controlUpdates: _controlsState,
      controller: controller,
      labels: widget.labels,
      pinned: _pinned,
      panelsOpen: _panelsOpen,
      framePreview: _preview,
      filter: _filter,
      subtitleStyle: _subtitleStyle,
      onFilterChanged: (next) {
        setState(() => _filter = next);
        transport.setFilter(next);
      },
      onSubtitleStyleChanged: (next) {
        setState(() => _subtitleStyle = next);
        transport.setSubtitleStyle(next);
        // 字号/颜色/位置是「读下一本也想保持」的偏好，上游同样持久化。
        unawaited(_persistSubtitleStyle(next));
      },
      onTogglePin: _togglePin,
      onScreenshot: _screenshot,
      onFullscreen: widget.onFullscreen,
      onTogglePip: () => setState(() => _pip = !_pip),
      onOpenInfo: _showInfo,
      extraSubtitleTracks: _subtitleOptions,
      onSubtitleSelected: _chooseSubtitle,
      waveform: _waveform,
    );
  }

  Widget _buildVideoPage(BuildContext context) {
    final controller = _controller;
    final transport = _transport;
    if (_error != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (controller == null || transport == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Listener(
      onPointerDown: (_) => _revealControls(),
      child: ColoredBox(
        color: Colors.black,
        child: MouseRegion(
          onHover: (_) => _revealControls(),
          child: ListenableBuilder(
            listenable: _controlsState,
            // 位置更新不重建画面、按钮与菜单，只刷新控制条里的进度和时间。
            child: _videoBody(transport),
            builder: (context, videoBody) {
              final snapshot = controller.snapshot;
              final showControls =
                  _controlsVisible ||
                  !snapshot.playing ||
                  _pinned ||
                  _panelsOpen.value;
              _publishBottomControls(showControls);
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (!_pip) videoBody!,
                  if (snapshot.phase == VideoEnginePhase.prerolling &&
                      snapshot.duration <= Duration.zero)
                    const Center(child: CircularProgressIndicator()),
                  if (snapshot.phase == VideoEnginePhase.failed)
                    ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: Text(
                          snapshot.failureReason ?? t.video.cannotPlay,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  if (_bottomControlsScope == null)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: IgnorePointer(
                        ignoring: !showControls,
                        child: ExcludeFocus(
                          excluding: !showControls,
                          child: AnimatedOpacity(
                            key: const ValueKey('video-controls-visibility'),
                            opacity: showControls ? 1 : 0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1080,
                                ),
                                child: _buildVideoControls(
                                  embedded: false,
                                  visible: showControls,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  if (_pip) videoBody!,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
