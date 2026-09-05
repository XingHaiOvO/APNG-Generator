/// 帧延迟编辑对话框（对应原版延迟 QSpinBox，范围 1..10000，单位 1/100 秒）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 打开延迟编辑器，返回 `(delayNum, applyToAll)`；取消返回 null。
Future<(int, bool)?> showDelayEditor(
  BuildContext context, {
  required int current,
}) {
  return showDialog<(int, bool)>(
    context: context,
    builder: (context) => _DelayEditorDialog(current: current),
  );
}

class _DelayEditorDialog extends StatefulWidget {
  final int current;
  const _DelayEditorDialog({required this.current});

  @override
  State<_DelayEditorDialog> createState() => _DelayEditorDialogState();
}

class _DelayEditorDialogState extends State<_DelayEditorDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.current.toString());
  bool _applyToAll = false;

  static const List<int> _presets = [5, 10, 20, 50, 100];

  int? get _value {
    final v = int.tryParse(_controller.text);
    if (v == null || v < 1 || v > 10000) return null;
    return v;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('帧延迟'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '延迟（1/100 秒）',
              helperText: '范围 1..10000，10 即 0.1 秒',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final p in _presets)
                ActionChip(
                  label: Text('$p'),
                  onPressed: () {
                    _controller.text = '$p';
                    setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('应用到全部帧'),
            value: _applyToAll,
            onChanged: (v) => setState(() => _applyToAll = v ?? false),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _value == null
              ? null
              : () => Navigator.of(context).pop((_value!, _applyToAll)),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
