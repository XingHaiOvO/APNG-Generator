#include "ApngGenerator.h"

#include <QBuffer>
#include <QByteArray>
#include <QDataStream>
#include <QFile>
#include <QImage>
#include <QDebug>

// ---------- PNG / APNG 块处理辅助函数 ----------

// 计算 CRC32（与 zlib 兼容）
static quint32 crc32(const QByteArray &data)
{
    // 使用查表法
    static quint32 table[256];
    static bool initialized = false;
    if (!initialized) {
        for (quint32 i = 0; i < 256; ++i) {
            quint32 c = i;
            for (int k = 0; k < 8; ++k) {
                if (c & 1)
                    c = 0xEDB88320U ^ (c >> 1);
                else
                    c = c >> 1;
            }
            table[i] = c;
        }
        initialized = true;
    }

    quint32 crc = 0xFFFFFFFFU;
    for (char byte : data) {
        crc = table[(crc ^ static_cast<quint8>(byte)) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFFU;
}

// 写入一个 PNG 块：长度(4) + 类型(4) + 数据 + CRC(4)
static void writeChunk(QByteArray &out, const QByteArray &type, const QByteArray &data)
{
    quint32 len = data.size();
    QByteArray lenBytes;
    QDataStream lenStream(&lenBytes, QIODevice::WriteOnly);
    lenStream.setByteOrder(QDataStream::BigEndian);
    lenStream << len;

    QByteArray crcData = type + data;
    quint32 crc = crc32(crcData);
    QByteArray crcBytes;
    QDataStream crcStream(&crcBytes, QIODevice::WriteOnly);
    crcStream.setByteOrder(QDataStream::BigEndian);
    crcStream << crc;

    out += lenBytes;
    out += type;
    out += data;
    out += crcBytes;
}

// 从内存中的 PNG 文件提取 IHDR 数据和 IDAT 数据（连接所有 IDAT 块）
static bool parsePng(const QByteArray &pngData, QByteArray *ihdrData, QByteArray *idatData)
{
    const int pngSignatureSize = 8;
    if (pngData.size() < pngSignatureSize)
        return false;

    // 检查 PNG 签名
    static const QByteArray pngSignature = QByteArray::fromHex("89504e470d0a1a0a");
    if (pngData.left(pngSignatureSize) != pngSignature)
        return false;

    int pos = pngSignatureSize;
    bool ihdrFound = false;
    idatData->clear();

    while (pos + 8 <= pngData.size()) {
        // 读取长度（大端）
        quint32 length;
        QDataStream lengthStream(pngData.mid(pos, 4));
        lengthStream.setByteOrder(QDataStream::BigEndian);
        lengthStream >> length;
        pos += 4;

        if (pos + 4 + length + 4 > pngData.size())
            return false; // 数据不完整

        QByteArray type = pngData.mid(pos, 4);
        pos += 4;

        QByteArray data = pngData.mid(pos, length);
        pos += length;

        // 跳过 CRC（4 字节）
        pos += 4;

        if (type == "IHDR") {
            if (length != 13)
                return false;
            *ihdrData = data;
            ihdrFound = true;
        }
        else if (type == "IDAT") {
            idatData->append(data);
        }
        else if (type == "IEND") {
            break;
        }
    }

    return ihdrFound && !idatData->isEmpty();
}

// 将 4 字节整数（大端）转换为 QByteArray
static QByteArray toBigEndian4(quint32 value)
{
    QByteArray bytes;
    QDataStream stream(&bytes, QIODevice::WriteOnly);
    stream.setByteOrder(QDataStream::BigEndian);
    stream << value;
    return bytes;
}

// 将 2 字节整数（大端）转换为 QByteArray
static QByteArray toBigEndian2(quint16 value)
{
    QByteArray bytes;
    QDataStream stream(&bytes, QIODevice::WriteOnly);
    stream.setByteOrder(QDataStream::BigEndian);
    stream << value;
    return bytes;
}

// ---------- 主生成函数 ----------

bool ApngGenerator::generate(const QString &outputPath,
                             const QVector<FrameItem> &frames,
                             int loopCount,
                             QString *errorString)
{
    if (frames.isEmpty()) {
        if (errorString) *errorString = "No frames to generate.";
        return false;
    }

    // 检查所有帧尺寸是否一致
    QSize canvasSize = frames.first().image.size();
    for (int i = 1; i < frames.size(); ++i) {
        if (frames[i].image.size() != canvasSize) {
            if (errorString) *errorString = "All frames must have the same dimensions.";
            return false;
        }
    }

    // 1. 将每个帧编码为 PNG 字节流（内存中）
    QVector<QByteArray> pngFrames;
    for (int i = 0; i < frames.size(); ++i) {
        QByteArray pngData;
        QBuffer buffer(&pngData);
        buffer.open(QIODevice::WriteOnly);
        if (!frames[i].image.save(&buffer, "PNG")) {
            if (errorString) *errorString = QString("Failed to encode frame %1 as PNG.").arg(i);
            return false;
        }
        buffer.close();
        pngFrames.append(pngData);
    }

    // 2. 解析第一个帧，获取 IHDR
    QByteArray ihdrData;
    QByteArray firstIdatData;
    if (!parsePng(pngFrames.first(), &ihdrData, &firstIdatData)) {
        if (errorString) *errorString = "Failed to parse first frame PNG data.";
        return false;
    }

    // 3. 构建 APNG 文件
    QByteArray apng;

    // PNG 签名
    apng.append(QByteArray::fromHex("89504e470d0a1a0a"));

    // IHDR 块（直接使用第一帧的 IHDR）
    writeChunk(apng, "IHDR", ihdrData);

    // acTL 块：帧数 + 循环次数
    QByteArray actlData;
    actlData += toBigEndian4(static_cast<quint32>(frames.size()));
    actlData += toBigEndian4(static_cast<quint32>(loopCount));
    writeChunk(apng, "acTL", actlData);

    // 第一帧：fcTL + IDAT
    {
        // fcTL 数据：seq(4) + width(4) + height(4) + x(4) + y(4) + delay_num(2) + delay_den(2) + dispose_op(1) + blend_op(1)
        QByteArray fctlData;
        fctlData += toBigEndian4(0); // sequence_number 0
        fctlData += toBigEndian4(static_cast<quint32>(canvasSize.width()));
        fctlData += toBigEndian4(static_cast<quint32>(canvasSize.height()));
        fctlData += toBigEndian4(static_cast<quint32>(frames[0].xOffset));
        fctlData += toBigEndian4(static_cast<quint32>(frames[0].yOffset));
        fctlData += toBigEndian2(static_cast<quint16>(frames[0].delayNum));
        fctlData += toBigEndian2(static_cast<quint16>(frames[0].delayDen));
        fctlData.append(static_cast<char>(frames[0].disposeOp));
        fctlData.append(static_cast<char>(frames[0].blendOp));
        writeChunk(apng, "fcTL", fctlData);

        // IDAT 块（直接使用第一帧的 IDAT 数据，可能包含多个 IDAT 块，但我们已合并，所以写入一个）
        writeChunk(apng, "IDAT", firstIdatData);
    }

    // 后续帧：fcTL + fdAT
    for (int i = 1; i < frames.size(); ++i) {
        // 解析当前帧的 PNG，获取其 IDAT 数据
        QByteArray dummyIhdr;
        QByteArray idatData;
        if (!parsePng(pngFrames[i], &dummyIhdr, &idatData)) {
            if (errorString) *errorString = QString("Failed to parse frame %1 PNG data.").arg(i);
            return false;
        }

        // fcTL
        QByteArray fctlData;
        fctlData += toBigEndian4(static_cast<quint32>(i)); // sequence_number
        fctlData += toBigEndian4(static_cast<quint32>(canvasSize.width()));
        fctlData += toBigEndian4(static_cast<quint32>(canvasSize.height()));
        fctlData += toBigEndian4(static_cast<quint32>(frames[i].xOffset));
        fctlData += toBigEndian4(static_cast<quint32>(frames[i].yOffset));
        fctlData += toBigEndian2(static_cast<quint16>(frames[i].delayNum));
        fctlData += toBigEndian2(static_cast<quint16>(frames[i].delayDen));
        fctlData.append(static_cast<char>(frames[i].disposeOp));
        fctlData.append(static_cast<char>(frames[i].blendOp));
        writeChunk(apng, "fcTL", fctlData);

        // fdAT：序列号 + IDAT 数据
        QByteArray fdatData;
        fdatData += toBigEndian4(static_cast<quint32>(i)); // sequence_number
        fdatData += idatData;
        writeChunk(apng, "fdAT", fdatData);
    }

    // IEND 块
    writeChunk(apng, "IEND", QByteArray());

    // 写入文件
    QFile file(outputPath);
    if (!file.open(QIODevice::WriteOnly)) {
        if (errorString) *errorString = "Cannot open output file for writing.";
        return false;
    }
    if (file.write(apng) != apng.size()) {
        file.close();
        if (errorString) *errorString = "Failed to write APNG file.";
        return false;
    }
    file.close();

    return true;
}