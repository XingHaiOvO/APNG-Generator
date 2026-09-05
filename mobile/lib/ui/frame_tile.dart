/// 帧列表条目：缩略图、序号、延迟、删除、拖拽手柄。
library;

import 'package:flutter/material.dart';

import '../models/frame.dart';

class FrameTile extends StatelessWidget {
  final int index;
  final Frame frame;
  final VoidCallback onDelete;
  final VoidCallback onEditDelay;

  const FrameTile({
    super.key,
    required this.index,
    required this.frame,
    required this.onDelete,
    required this.onEditDelay,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          // 缩略图 + 序号徽标
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: RawImage(image: frame.image, fit: BoxFit.contain),
                  ),
                ),
              ),
              Positioned(
                left: -4,
                top: -4,
                child: Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: scheme.surfaceContainerLowest, width: 2),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '帧 ${index + 1}',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '延迟 ${frame.delayNum}/$frameDelayDen s',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '编辑延迟',
            icon: const Icon(Icons.timer_outlined),
            onPressed: onEditDelay,
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.close),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
