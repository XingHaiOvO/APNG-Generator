#ifndef FRAMEITEM_H
#define FRAMEITEM_H

#include <QImage>

struct FrameItem {
    QImage image;               // 帧图像（应保持格式一致）
    int delayNum = 10;          // 延迟分子
    int delayDen = 100;         // 延迟分母，固定为 100
    int xOffset = 0;
    int yOffset = 0;
    int disposeOp = 0;          // 0: none, 1: background, 2: previous
    int blendOp = 0;            // 0: source, 1: over
};

#endif // FRAMEITEM_H