import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** 预览图最长边（px）。编码始终使用原始分辨率像素，这里只影响界面显示 */
const PREVIEW_MAX_EDGE: number = 720;

export interface LoadedImage {
  /** 缩放后的预览图，仅用于界面显示 */
  pixelMap: PixelMap;
  /** 原始分辨率的 RGBA 像素（直通 alpha），用于 APNG 编码 */
  rgba: Uint8Array;
  width: number;
  height: number;
}

/** 取像素时统一后的结果 */
interface StraightRgba {
  rgba: Uint8Array;
  width: number;
  height: number;
}

/** 明确排除的 MIME 类型 */
const EXCLUDED_MIME_TYPES: string[] = [
  'image/webp',
  'image/heic',
  'image/heif'
];

/** 明确排除的扩展名（作为兜底） */
const EXCLUDED_EXTENSIONS: string[] = [
  '.webp', '.heic', '.heif'
];

/** EXIF Orientation 的 8 种取值，下标 + 1 即为方向编号 */
const ORIENTATION_NAMES: string[] = [
  'Top-left', 'Top-right', 'Bottom-right', 'Bottom-left',
  'Left-top', 'Right-top', 'Right-bottom', 'Left-bottom'
];

function hasExcludedExtension(uri: string): boolean {
  const lower = uri.toLowerCase();
  return EXCLUDED_EXTENSIONS.some(ext =>
  lower.endsWith(ext) || lower.includes(ext + '?')
  );
}

/**
 * 把 EXIF 方向统一成 1~8。
 * 不同 SDK 版本 / 不同机型上 getImageProperty 可能返回 'Top-left' 这类名称，
 * 也可能返回 '1' 这类数字字符串，两种形式都要能识别。
 */
function normalizeOrientation(raw: string | undefined): number {
  if (!raw) return 1;
  const trimmed = raw.trim();
  const asNumber = parseInt(trimmed, 10);
  if (!isNaN(asNumber) && asNumber >= 1 && asNumber <= 8 && `${asNumber}` === trimmed) {
    return asNumber;
  }
  const index = ORIENTATION_NAMES.indexOf(trimmed);
  return index >= 0 ? index + 1 : 1;
}

/** 按 EXIF 方向对 PixelMap 做原地校正 */
function applyOrientation(pixelMap: PixelMap, orientation: number): void {
  try {
    switch (orientation) {
      case 2:                // 水平镜像
        pixelMap.flipSync(true, false);
        break;
      case 3:                // 旋转 180°
        pixelMap.rotateSync(180);
        break;
      case 4:                // 垂直镜像
        pixelMap.flipSync(false, true);
        break;
      case 5:                // 水平镜像 + 顺时针 270°
        pixelMap.flipSync(true, false);
        pixelMap.rotateSync(270);
        break;
      case 6:                // 顺时针 90°
        pixelMap.rotateSync(90);
        break;
      case 7:                // 水平镜像 + 顺时针 90°
        pixelMap.flipSync(true, false);
        pixelMap.rotateSync(90);
        break;
      case 8:                // 顺时针 270°
        pixelMap.rotateSync(270);
        break;
      default:               // 1 = Top-left，无需变换
        break;
    }
  } catch (err) {
    const error = err as BusinessError;
    console.error(`EXIF orientation correction failed: ${error.code} ${error.message}`);
  }
}

/** 读取方向信息，读取失败按正常方向处理 */
async function readOrientation(source: image.ImageSource): Promise<string | undefined> {
  try {
    return await source.getImageProperty(image.PropertyKey.ORIENTATION);
  } catch (e) {
    return undefined;
  }
}

/** 读取 MIME 类型，读取失败返回空串（此时依赖扩展名过滤） */
async function readMimeType(source: image.ImageSource): Promise<string> {
  try {
    const info = await source.getImageInfo();
    return (info.mimeType ?? '').toLowerCase();
  } catch (e) {
    return '';
  }
}

/** 单平面 8 位及以下的每像素字节数；返回 0 表示不能按单一平面直接解读 */
function bytesPerPixelOf(format: image.PixelMapFormat): number {
  switch (format) {
    case image.PixelMapFormat.ALPHA_8:
      return 1;
    case image.PixelMapFormat.RGB_565:
      return 2;
    case image.PixelMapFormat.RGB_888:
      return 3;
    case image.PixelMapFormat.RGBA_8888:
      return 4;
    case image.PixelMapFormat.BGRA_8888:
      return 4;
    default:
      // NV12 / NV21（YUV 多平面）、RGBA_F16、RGBA_1010102、YCBCR_P010，
      // 以及 API 18 才可引用的 ARGB_8888 等
      return 0;
  }
}

/** 按行读出像素，行间按 stride 对齐 */
async function readRows(
  pixelMap: PixelMap, width: number, height: number, stride: number
): Promise<ArrayBuffer> {
  const area: image.PositionArea = {
    pixels: new ArrayBuffer(stride * height),
    offset: 0,
    stride: stride,
    region: { size: { width, height }, x: 0, y: 0 }
  };
  await pixelMap.readPixels(area);
  return area.pixels;
}

/** 去掉行间对齐填充，得到紧密排列的像素 */
function packRows(
  raw: ArrayBuffer, stride: number, width: number, height: number, bpp: number
): Uint8Array {
  const rowBytes = width * bpp;
  if (stride === rowBytes) {
    return new Uint8Array(raw);
  }
  const src = new Uint8Array(raw);
  const out = new Uint8Array(rowBytes * height);
  for (let y = 0; y < height; y++) {
    out.set(src.subarray(y * stride, y * stride + rowBytes), y * rowBytes);
  }
  return out;
}

/**
 * PNG 存储的是直通（非预乘）alpha，而解码结果可能是预乘的，
 * 直接写进去会让半透明像素整体偏暗，这里按 alpha 还原一次。
 */
function unpremultiplyInPlace(rgba: Uint8Array): void {
  for (let i = 0; i < rgba.length; i += 4) {
    const a = rgba[i + 3];
    if (a === 255) continue;
    if (a === 0) {
      rgba[i] = 0;
      rgba[i + 1] = 0;
      rgba[i + 2] = 0;
      continue;
    }
    rgba[i] = Math.min(255, Math.round(rgba[i] * 255 / a));
    rgba[i + 1] = Math.min(255, Math.round(rgba[i + 1] * 255 / a));
    rgba[i + 2] = Math.min(255, Math.round(rgba[i + 2] * 255 / a));
  }
}

/**
 * 解出紧密排列、直通 alpha 的 RGBA 像素。
 *
 * 关键点：readPixels 写回的是「PixelMap 自身的像素格式」，createPixelMap 的
 * desiredPixelFormat 只是请求、不保证被采纳。若照搬 4 字节/像素去解读 BGRA、
 * RGB_565、10bit 或 HDR 的解码结果，通道顺序/位宽就错了，存出来的图颜色是歪的
 * （应用内预览直接渲染 PixelMap，所以看起来还是对的）。
 * 因此这里一律以 getImageInfo 报告的实际格式为准，不对就先让原生接口转成
 * RGBA_8888 + 非预乘再读。
 */
async function readStraightRgba(pixelMap: PixelMap): Promise<StraightRgba> {
  const info = await pixelMap.getImageInfo();
  const width = info.size.width;
  const height = info.size.height;
  const format = info.pixelFormat;

  console.info(`apng decode: ${width}x${height} format=${format} alphaType=${info.alphaType}`
    + ` stride=${info.stride} isHdr=${info.isHdr} mime=${info.mimeType}`);

  const tightStride = width * 4;
  const needConvert = format !== image.PixelMapFormat.RGBA_8888
    || info.alphaType === image.AlphaType.PREMUL
    || (info.stride > 0 && info.stride !== tightStride);

  if (!needConvert) {
    const raw = await readRows(pixelMap, width, height, tightStride);
    return { rgba: new Uint8Array(raw), width, height };
  }

  const bpp = bytesPerPixelOf(format);
  if (bpp === 0) {
    throw new Error(`不支持的图片格式：像素格式 ${format}`
      + `${info.isHdr ? '（HDR）' : ''}，无法转换为 RGBA`);
  }

  // 先按原格式读出来，再交给原生做格式/alpha 转换
  const srcStride = info.stride > 0 ? info.stride : width * bpp;
  const rawBuffer = await readRows(pixelMap, width, height, srcStride);
  const packed = packRows(rawBuffer, srcStride, width, height, bpp);

  const converted = await image.createPixelMap(packed.buffer as ArrayBuffer, {
    size: { width: width, height: height },
    srcPixelFormat: format,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    alphaType: image.AlphaType.UNPREMUL
  });

  try {
    const convertedInfo = await converted.getImageInfo();
    if (convertedInfo.pixelFormat !== image.PixelMapFormat.RGBA_8888) {
      throw new Error(`不支持的图片格式：像素格式转换后仍为 ${convertedInfo.pixelFormat}`);
    }
    const out = new Uint8Array(await readRows(converted, width, height, width * 4));
    if (convertedInfo.alphaType === image.AlphaType.PREMUL) {
      // 转换没给出直通 alpha，只能自己还原
      unpremultiplyInPlace(out);
    }
    return { rgba: out, width, height };
  } finally {
    await converted.release();
  }
}

/**
 * 释放加载结果占用的原生内存。
 * 被跳过的图片必须调用，否则会一直占用原始分辨率的显存。
 */
export function releaseLoadedImage(loaded: LoadedImage): void {
  loaded.pixelMap.release().catch((e: Error) => {
    console.error(`release preview pixelMap failed: ${e.message}`);
  });
}

/**
 * 从相册 URI 加载图片，解码为 RGBA 像素数组，并附带一张降采样的预览图。
 * 若图片格式为 WebP / HEIC，会抛出异常。
 */
export async function loadImageFromUri(uri: string): Promise<LoadedImage> {
  // 第一层：按扩展名快速过滤
  if (hasExcludedExtension(uri)) {
    throw new Error('不支持的图片格式（WebP / HEIC）');
  }

  let file: fileIo.File | null = null;
  let source: image.ImageSource | null = null;
  let pixelMap: PixelMap | null = null;

  try {
    // 打开文件获取文件描述符
    file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);

    // 使用 fd 创建 ImageSource
    source = image.createImageSource(file.fd);

    // 第二层：按真实 MIME 类型过滤
    const mime = await readMimeType(source);
    if (mime !== '' && EXCLUDED_MIME_TYPES.includes(mime)) {
      throw new Error(`不支持的图片格式：${mime}`);
    }

    const orientation = normalizeOrientation(await readOrientation(source));

    // 以原始分辨率解码，保证编码像素不损失
    pixelMap = await source.createPixelMap({
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    });
    applyOrientation(pixelMap, orientation);

    // 取出直通 RGBA（含实际格式 / 预乘 / 行对齐的处理）
    const pixels = await readStraightRgba(pixelMap);
    const width = pixels.width;
    const height = pixels.height;
    const rgba = pixels.rgba;

    // 像素已经拷出，把 PixelMap 原地缩小到预览所需尺寸，
    // 否则一张 1200 万像素照片会一直占着约 48MB 原生内存
    const longEdge = Math.max(width, height);
    if (longEdge > PREVIEW_MAX_EDGE) {
      const factor = PREVIEW_MAX_EDGE / longEdge;
      try {
        await pixelMap.scale(factor, factor);
      } catch (scaleErr) {
        const error = scaleErr as BusinessError;
        console.error(`scale preview failed: ${error.code} ${error.message}`);
      }
    }

    const result: LoadedImage = { pixelMap, rgba, width, height };
    pixelMap = null;   // 所有权交给调用方
    return result;
  } catch (err) {
    // 失败路径必须自己释放，否则原生内存只增不减
    if (pixelMap) {
      try {
        await pixelMap.release();
      } catch (releaseErr) {
        console.error(`release pixelMap failed: ${JSON.stringify(releaseErr)}`);
      }
    }
    const error = err as BusinessError;
    const msg = error.message ?? '未知错误';
    console.error(`Failed to load image from URI. Code: ${error.code}, message: ${msg}`);

    if (msg.includes('不支持的图片格式')) {
      throw new Error(msg);
    }
    throw new Error(`图片加载失败: ${msg}`);
  } finally {
    // ImageSource 持有解码资源，必须先于文件句柄释放
    if (source) {
      try {
        await source.release();
      } catch (releaseErr) {
        console.error(`release image source failed: ${JSON.stringify(releaseErr)}`);
      }
    }
    if (file) {
      try {
        fileIo.closeSync(file);
      } catch (closeErr) {
        const err = closeErr as BusinessError;
        console.error(`Failed to close file. Code: ${err.code}, message: ${err.message}`);
      }
    }
  }
}
