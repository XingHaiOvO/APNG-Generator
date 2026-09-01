#ifndef APNGGENERATOR_H
#define APNGGENERATOR_H

#include <QVector>
#include <QString>
#include <QSize>
#include "FrameItem.h"

class ApngGenerator
{
public:
    static bool generate(const QString &outputPath,
                         const QVector<FrameItem> &frames,
                         int loopCount = 0,
                         QString *errorString = nullptr);
};

#endif // APNGGENERATOR_H