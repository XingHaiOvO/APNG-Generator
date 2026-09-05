/// 主界面：预览区 + 帧列表 + 底部操作（对应 MainWindow）。
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/frame.dart';
import '../services/apng_exporter.dart';
import '../services/image_loader.dart';
import '../state/frame_store.dart';
import 'delay_editor.dart';
import 'frame_tile.dart';
import 'preview_area.dart';

class HomeScreen extends StatefulWidget {
  /// 便于测试注入外部 [FrameStore]。
  final FrameStore? store;

  const HomeScreen({super.key, this.store});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final FrameStore _store = widget.store ?? FrameStore();
  final ImagePicker _picker = ImagePicker();
  bool _busy = false;

  static const int _maxLoopCount = 10000;

  @override
  void dispose() {
    if (widget.store == null) _store.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _describeCanvas() {
    final canvas = _store.canvasSize;
    return canvas == null ? '' : '${canvas.width}×${canvas.height}';
  }

  /// 添加图片（对应 addFramesFromFiles：尺寸不一致警告并跳过）。
  Future<void> _addImages() async {
    if (_busy) return;
    try {
      final files = await _picker.pickMultiImage();
      if (files.isEmpty || !mounted) return;
      setState(() => _busy = true);

      var added = 0;
      var sizeSkipped = 0;
      var failed = 0;
      for (final file in files) {
        try {
          final bytes = await file.readAsBytes();
          final decoded = await decodeImageBytes(bytes);
          final canvas = _store.canvasSize;
          if (canvas != null &&
              (decoded.width != canvas.width || decoded.height != canvas.height)) {
            sizeSkipped++;
            continue;
          }
          _store.addFrame(Frame(
            image: decoded.image,
            width: decoded.width,
            height: decoded.height,
            delayNum: _store.defaultDelayNum,
          ));
          added++;
        } catch (_) {
          failed++;
        }
      }
      if (!mounted) return;

      final parts = <String>[
        '已添加 $added 张',
        if (sizeSkipped > 0) '尺寸不一致跳过 $sizeSkipped 张',
        if (failed > 0) '读取失败 $failed 张',
      ];
      _showSnack(parts.join('，'));
    } catch (e) {
      _showSnack('选择图片失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 生成 APNG 后保存到相册或拉起分享（对应 generateApng）。
  Future<void> _generate({required bool share}) async {
    if (_store.isEmpty) {
      _showSnack('请先添加图片');
      return;
    }
    if (_busy) return;

    if (kIsWeb) {
      _showSnack('保存功能需在 Android / iOS 设备上使用');
      return;
    }

    final notifier = ValueNotifier(0);
    final total = _store.frameCount;
    var dialogOpen = true;

    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('正在生成 APNG'),
          content: ValueListenableBuilder<int>(
            valueListenable: notifier,
            builder: (context, done, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: total > 0 ? done / total : 0),
                const SizedBox(height: 12),
                Text('$done / $total 帧'),
              ],
            ),
          ),
        ),
      ),
    ));

    Future<void> closeDialog() async {
      if (mounted && dialogOpen) {
        Navigator.of(context).pop();
        dialogOpen = false;
      }
    }

    try {
      final file = await writeApngFile(
        frames: _store.frames,
        loopCount: _store.loopCount,
        onProgress: (done, _) => notifier.value = done,
      );
      await closeDialog();
      if (share) {
        await shareApngFile(file);
        _showSnack('APNG 已生成，请在分享面板中选择保存位置');
      } else {
        await saveApngToGallery(file);
        _showSnack('已保存到系统相册「$kGalleryAlbum」');
      }
    } catch (e) {
      await closeDialog();
      _showSnack('生成 APNG 失败: $e');
    } finally {
      notifier.dispose();
    }
  }

  Future<void> _removeAt(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除帧 ${index + 1}？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) _store.removeAt(index);
  }

  Future<void> _editDelay(int index) async {
    final frame = _store.frames[index];
    final result = await showDelayEditor(context, current: frame.delayNum);
    if (result == null) return;
    final (delayNum, applyToAll) = result;
    if (applyToAll) {
      _store.applyDelayToAll(delayNum);
    } else {
      _store.setDelay(index, delayNum);
    }
  }

  Future<void> _editDefaultDelay() async {
    final result = await showDelayEditor(
      context,
      current: _store.defaultDelayNum,
    );
    if (result == null) return;
    _store.defaultDelayNum = result.$1;
    _showSnack('新添加图片的默认延迟已设为 ${result.$1}/100 s');
  }

  Future<void> _editLoopCount() async {
    final controller = TextEditingController(text: '${_store.loopCount}');
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('循环次数'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: '循环次数',
            helperText: '0 表示无限循环，范围 0..$_maxLoopCount',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text)),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result < 0 || result > _maxLoopCount) {
      _showSnack('循环次数需在 0..$_maxLoopCount 之间');
      return;
    }
    _store.setLoopCount(result);
  }

  Future<void> _clearAll() async {
    if (_store.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空全部帧？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) _store.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('APNG 生成器'),
        actions: [
          ListenableBuilder(
            listenable: _store,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton(
                onPressed: _editLoopCount,
                child: Text(_store.loopCount == 0
                    ? '循环 ∞'
                    : '循环 ${_store.loopCount} 次'),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多设置',
            onSelected: (value) {
              switch (value) {
                case 'share':
                  _generate(share: true);
                case 'default_delay':
                  _editDefaultDelay();
                case 'clear':
                  _clearAll();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: Icon(Icons.ios_share),
                  title: Text('分享 APNG'),
                ),
              ),
              PopupMenuItem(
                value: 'default_delay',
                child: ListTile(
                  leading: Icon(Icons.timer_outlined),
                  title: Text('默认帧延迟'),
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete_sweep_outlined),
                  title: Text('清空全部'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) => Column(
          children: [
            SizedBox(
              height: 280,
              child: PreviewArea(frames: _store.frames),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  Text(
                    _store.isEmpty
                        ? '未添加图片'
                        : '${_store.frameCount} 帧 · 单轮 '
                            '${(_store.totalDurationMs / 1000).toStringAsFixed(1)}s',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    _describeCanvas(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _store.isEmpty
                  ? const _EmptyHint()
                  : Column(
                      children: [
                        // 拖拽排序友好提示（常驻，避免功能不可见）
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                          child: Row(
                            children: [
                              Icon(
                                Icons.drag_indicator,
                                size: 14,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '长按帧并上下拖动可调整顺序',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ReorderableListView.builder(
                            buildDefaultDragHandles: true,
                            onReorderItem: _store.reorder,
                            // 拖拽代理保持卡片外观：圆角 + 随拖入进度浮起的阴影
                            proxyDecorator: (child, index, animation) =>
                                AnimatedBuilder(
                              animation: animation,
                              builder: (context, _) {
                                final t = Curves.easeOut
                                    .transform(animation.value);
                                final scheme =
                                    Theme.of(context).colorScheme;
                                return Transform.scale(
                                  scale: 1.0 + 0.02 * t,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: scheme.primary
                                              .withValues(alpha: 0.22 * t),
                                          blurRadius: 18 * t,
                                          offset: Offset(0, 8 * t),
                                        ),
                                      ],
                                    ),
                                    child: child,
                                  ),
                                );
                              },
                              child: child,
                            ),
                            itemCount: _store.frameCount,
                            itemBuilder: (context, index) => FrameTile(
                              key: ObjectKey(_store.frames[index]),
                              index: index,
                              frame: _store.frames[index],
                              onDelete: () => _removeAt(index),
                              onEditDelay: () => _editDelay(index),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: ListenableBuilder(
          listenable: _store,
          builder: (context, _) {
            final scheme = Theme.of(context).colorScheme;
            return ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        scheme.surfaceContainerLowest.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _addImages,
                          icon:
                              const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('添加图片'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _store.isEmpty || _busy
                              ? null
                              : () => _generate(share: false),
                          icon: const Icon(Icons.save_alt),
                          label: const Text('保存到相册'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.movie_creation_outlined, size: 64, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            '还没有图片帧\n点击下方"添加图片"，选择多张同尺寸图片',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}
