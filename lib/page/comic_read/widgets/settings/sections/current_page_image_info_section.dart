import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:zephyr/page/comic_read/method/local_read_source_adapter.dart';
import 'package:zephyr/page/comic_read/model/current_page_image_info.dart';
import 'package:zephyr/page/comic_read/widgets/settings/reader_settings_primitives.dart';
import 'package:zephyr/reader/super_resolution_status.dart';
import 'package:zephyr/icons/icons.dart';
import 'package:zephyr/i18n/strings.g.dart';

({String? format, int? width, int? height}) inspectImageBytes(Uint8List bytes) {
  final decoder = image.findDecoderForData(bytes);
  if (decoder == null) return (format: null, width: null, height: null);
  final info = decoder.startDecode(bytes);
  return (
    format: decoder.format.name.toUpperCase(),
    width: info?.width,
    height: info?.height,
  );
}

class _PageImageFacts {
  const _PageImageFacts({
    this.name,
    this.format,
    this.width,
    this.height,
    this.bytes,
  });

  final String? name;
  final String? format;
  final int? width;
  final int? height;
  final BigInt? bytes;
}

class CurrentPageImageInfoSection extends StatefulWidget {
  const CurrentPageImageInfoSection({super.key});

  @override
  State<CurrentPageImageInfoSection> createState() =>
      _CurrentPageImageInfoSectionState();
}

class _CurrentPageImageInfoSectionState
    extends State<CurrentPageImageInfoSection> {
  _PageImageFacts? _facts;
  bool _loading = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    CurrentPageImageInfo.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    CurrentPageImageInfo.instance.removeListener(_load);
    _revision++;
    super.dispose();
  }

  Future<void> _load() async {
    final current = CurrentPageImageInfo.instance.current;
    final revision = ++_revision;
    if (current == null) {
      if (mounted) {
        setState(() {
          _facts = null;
          _loading = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _facts = null;
        _loading = true;
      });
    }
    _PageImageFacts? facts;
    try {
      final source = current.source;
      final index = current.index;
      if (source != null &&
          index != null &&
          index >= 0 &&
          index < source.pages.length) {
        final page = source.pages[index];
        final bytes = await source.getPageBytes(index);
        final decoded = bytes == null
            ? null
            : await compute(inspectImageBytes, bytes);
        facts = _PageImageFacts(
          name: page.name,
          format: decoded?.format,
          width: decoded?.width,
          height: decoded?.height,
          bytes: page.size,
        );
      } else if (current.filePath case final String path) {
        final file = File(path);
        final stat = await file.stat();
        if (stat.type == FileSystemEntityType.file) {
          final decoded = await compute(
            inspectImageBytes,
            await file.readAsBytes(),
          );
          facts = _PageImageFacts(
            name: p.basename(path),
            format: decoded.format,
            width: decoded.width,
            height: decoded.height,
            bytes: BigInt.from(stat.size),
          );
        }
      }
    } catch (_) {
      // Source may close while the reader moves to another chapter.
    }
    if (!mounted || revision != _revision) return;
    setState(() {
      _facts = facts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final facts = _facts;
    final currentSource = CurrentPageImageInfo.instance.current?.source;
    final presenter =
        currentSource != null &&
            identical(currentSource, LocalReadSession.instance.currentSource)
        ? LocalReadSession.instance.presenter
        : null;
    final rows = <Widget>[
      if (facts?.name != null)
        ListTile(title: Text(t.reader.fileLabel), subtitle: Text(facts!.name!)),
      if (facts?.format != null)
        ListTile(
          title: Text(t.reader.formatLabel),
          trailing: Text(facts!.format!),
        ),
      if (facts?.width != null && facts?.height != null)
        ListTile(
          title: const Text('尺寸'),
          trailing: Text('${facts!.width} × ${facts.height}'),
        ),
      if (facts?.bytes != null)
        ListTile(
          title: Text(t.reader.fileSize),
          trailing: Text('${facts!.bytes} B'),
        ),
    ];
    if (presenter != null) {
      rows.add(
        ListenableBuilder(
          listenable: presenter,
          builder: (context, _) {
            final status = presenter.currentPageUpscaleStatus;
            return ListTile(
              title: Text(t.reader.processingStatus),
              trailing: Text(imageEnhancementPhaseLabel(status)),
            );
          },
        ),
      );
    }
    return SettingsSection(
      title: t.reader.currentImage,
      icon: AppGlyphs.info,
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (rows.isNotEmpty) SettingsCardGroup(children: rows),
        if (!_loading && rows.isEmpty) Text(t.reader.noImageInfoAvailable),
      ],
    );
  }
}
