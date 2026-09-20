import { zlib, BusinessError } from '@kit.BasicServicesKit';
import {
  buildChunk, buildSignature, buildIhdr, buildActl, buildFctl, concatChunks, writeUint32BEAt
} from './png_writer';

export class FrameData {
  width: number;
  height: number;
  rgba: Uint8Array;     // 每像素 4 字节 RGBA
  delayNum: number;     // 延迟分子
  delayDen: number;     // 延迟分母

  constructor(width: number, height: number, rgba: Uint8Array,
    delayNum: number, delayDen: number) {
    this.width = width;
    this.height = height;
    this.rgba = rgba;
    this.delayNum = delayNum;
    this.delayDen = delayDen;
  }
}

/**
 * APNG 的 delay_num / delay_den 是 16 位字段，超出范围会被静默截断并产生错误延迟，
 * 因此写入前统一钳制到合法区间。
 */
function clampUint16(value: number, minValue: number, fallback: number): number {
  if (isNaN(value) || !isFinite(value)) return fallback;
  const n = Math.floor(value);
  if (n < minValue) return fallback;
  return n > 0xFFFF ? 0xFFFF : n;
}

/** acTL 的 num_plays 是 32 位无符号字段 */
function clampUint32(value: number): number {
  if (isNaN(value) || !isFinite(value) || value < 0) return 0;
  const n = Math.floor(value);
  return n > 0xFFFFFFFF ? 0xFFFFFFFF : n;
}

/**
 * 将 RGBA 像素转换为 PNG 扫描线格式（每行滤波字节 0 + RGBA 数据）
 */
function toScanlines(rgba: Uint8Array, width: number, height: number): Uint8Array {
  const rowBytes = width * 4;
  const out = new Uint8Array(height * (1 + rowBytes));
  for (let y = 0; y < height; y++) {
    const dst = y * (1 + rowBytes);
    out[dst] = 0;  // 滤波类型 None
    out.set(rgba.subarray(y * rowBytes, (y + 1) * rowBytes), dst + 1);
  }
  return out;
}

/**
 * 用 zlib 压缩数据，返回压缩后的 Uint8Array
 */
async function deflate(data: Uint8Array): Promise<Uint8Array> {
  let dest: ArrayBuffer;
  let outputInfo: zlib.ZipOutputInfo;

  try {
    const zip: zlib.Zip = zlib.createZipSync();

    // 1. 计算压缩后数据的上限，确保目标缓冲区足够大
    const bound: number = await zip.compressBound(data.byteLength);
    dest = new ArrayBuffer(bound);

    // 2. 显式声明返回类型为 ZipOutputInfo
    outputInfo = await zip.compress2(
      dest,
      data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength),
      zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION
    );
  } catch (err) {
    const error = err as BusinessError;
    throw new Error(`zlib 压缩异常: ${error.code} ${error.message}`);
  }

  // 3. 检查压缩状态
  if (outputInfo.status !== zlib.ReturnStatus.OK) {
    throw new Error(`压缩失败，状态码: ${outputInfo.status}`);
  }

  // 4. 按实际长度拷出有效数据。
  //    不能直接返回 dest 上的视图：compressBound 给的是最坏情况上限（约等于未压缩大小），
  //    视图会让这块超大缓冲一直被后续的分块列表引用着，等于每帧白白多占一份原始像素内存。
  const exact = new Uint8Array(outputInfo.destLen);
  exact.set(new Uint8Array(dest, 0, outputInfo.destLen));
  return exact;
}

function appendChunk(chunks: Uint8Array[], type: string, dataParts: Uint8Array[]): void {
  const parts = buildChunk(type, dataParts);
  for (let i = 0; i < parts.length; i++) chunks.push(parts[i]);
}

/** 让出一轮事件循环，给 UI 线程渲染和响应输入的机会 */
function yieldToUi(): Promise<void> {
  return new Promise<void>((resolve: (value: void) => void) => {
    setTimeout(() => resolve(), 0);
  });
}

/** 编码进度回调：done 为已完成帧数，total 为总帧数 */
export type EncodeProgress = (done: number, total: number) => void;

/**
 * 生成 APNG 文件的完整字节流
 */
export async function encodeApng(
  frames: FrameData[],
  loopCount: number = 0,
  onProgress?: EncodeProgress
): Promise<Uint8Array> {
  if (frames.length === 0) {
    throw new Error('至少需要一帧');
  }

  const width = frames[0].width;
  const height = frames[0].height;
  if (width <= 0 || height <= 0) {
    throw new Error('帧尺寸无效');
  }
  for (const f of frames) {
    if (f.width !== width || f.height !== height) {
      throw new Error('所有帧的尺寸必须相同');
    }
    if (f.rgba.length < f.width * f.height * 4) {
      throw new Error('帧像素数据不完整');
    }
  }

  // 分块累积，最后一次性合并：避免 number[] 在大文件下的内存放大与性能损失
  const chunks: Uint8Array[] = [];
  chunks.push(buildSignature());
  appendChunk(chunks, 'IHDR', [buildIhdr(width, height)]);
  appendChunk(chunks, 'acTL', [buildActl(frames.length, clampUint32(loopCount))]);

  let seq = 0;

  for (let i = 0; i < frames.length; i++) {
    const frame = frames[i];

    // 扫描线用一个内层作用域包住：出去即可回收，否则下一帧再分配一份时，
    // 两帧的原始像素缓冲会同时存在（大图就是上百 MB 的瞬时峰值）
    let compressed: Uint8Array;
    {
      const scanlines = toScanlines(frame.rgba, width, height);
      compressed = await deflate(scanlines);
    }

    // fcTL
    appendChunk(chunks, 'fcTL', [
      buildFctl(seq, width, height,
        clampUint16(frame.delayNum, 1, 1),
        clampUint16(frame.delayDen, 0, 100))
    ]);
    seq++;

    if (i === 0) {
      // 第一帧：IDAT
      appendChunk(chunks, 'IDAT', [compressed]);
    } else {
      // 后续帧：fdAT = sequence_number(4) + 压缩数据
      const seqBytes = new Uint8Array(4);
      writeUint32BEAt(seqBytes, 0, seq);
      appendChunk(chunks, 'fdAT', [seqBytes, compressed]);
      seq++;
    }

    // 每帧结束后回报进度并让出线程：整段编码都在 ArkTS 线程上跑，
    // 不让出的话帧数一多界面就会长时间无响应（表现为"卡死"）
    if (onProgress) {
      onProgress(i + 1, frames.length);
    }
    await yieldToUi();
  }

  appendChunk(chunks, 'IEND', []);
  return concatChunks(chunks);
}
