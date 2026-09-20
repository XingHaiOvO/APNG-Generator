import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * 单次写入的字节数。
 * 同步写整个文件会把 UI 线程占住（几十 MB 就要好几秒，直接表现成"卡死"），
 * 这里改成异步分块写，每块之间 await 一次，让 UI 线程有机会响应。
 */
const WRITE_CHUNK_BYTES: number = 4 * 1024 * 1024;

/** 已经是完整缓冲区时直接复用，避免为了拿 ArrayBuffer 再整份拷贝一次 */
function exactBuffer(data: Uint8Array): ArrayBuffer {
  if (data.byteOffset === 0 && data.byteLength === data.buffer.byteLength) {
    return data.buffer;
  }
  return data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
}

/** 分块顺序写入（不传 offset，按文件当前位置依次追加） */
async function writeAll(file: fileIo.File, data: Uint8Array): Promise<void> {
  let offset = 0;
  try {
    while (offset < data.byteLength) {
      const end = Math.min(offset + WRITE_CHUNK_BYTES, data.byteLength);
      const part = data.subarray(offset, end);
      const written = await fileIo.write(file.fd, exactBuffer(part));
      if (written <= 0) {
        throw new Error(`写入返回 ${written}`);
      }
      // 按实际写入量推进：短写时下一轮会从断点续写，也保证循环一定会结束
      offset += written;
    }
  } catch (err) {
    const error = err as BusinessError;
    throw new Error(`写入第 ${offset} 字节起的数据失败: ${error.code} ${error.message}`);
  }
}

/**
 * 在 SaveButton 的 onClick 回调中【立即】调用，拿到相册文件 uri。
 *
 * 安全控件的临时授权有时限：API 20 及以后为 1 分钟（API 19 及以前仅 10 秒），
 * 从点击到调用 createAsset 的间隔超出授权时间就会失败。
 * 因此这里只做创建，编码、写文件等耗时操作一律放到拿到 uri 之后。
 */
export async function createAlbumImageAsset(context: common.UIAbilityContext): Promise<string> {
  try {
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    return await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'png');
  } catch (err) {
    const error = err as BusinessError;
    console.error(`createAlbumImageAsset failed. Code: ${error.code}, message: ${error.message}`);
    throw new Error(`创建相册文件失败: ${error.message}`);
  }
}

/**
 * 把 APNG 字节流写入已经创建好的相册 uri。
 * uri 一旦创建成功，写入过程不再受临时授权时限约束。
 */
export async function writeBytesToAlbumAsset(uri: string, apngBytes: Uint8Array): Promise<void> {
  let dstFile: fileIo.File | null = null;
  try {
    // 与官方保存到相册的示例一致带上 CREATE：媒体库的资源文件有可能是延迟落盘的
    dstFile = await fileIo.open(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    await writeAll(dstFile, apngBytes);
    await fileIo.close(dstFile);
    dstFile = null;
  } catch (err) {
    const error = err as BusinessError;
    console.error(`writeBytesToAlbumAsset failed. Code: ${error.code}, message: ${error.message}`);
    throw new Error(`写入相册失败: ${error.message}`);
  } finally {
    if (dstFile) {
      try {
        await fileIo.close(dstFile);
      } catch (e) {
        // 忽略关闭异常
      }
    }
  }
}

/**
 * 将 APNG 字节流写入沙箱，供预览组件读取。
 * 返回文件路径。
 */
export async function writeApngToSandbox(
  context: common.UIAbilityContext,
  apngBytes: Uint8Array,
  fileName: string = 'preview.png'
): Promise<string> {
  const filePath = `${context.filesDir}/${fileName}`;
  let file: fileIo.File | null = null;
  try {
    // 覆盖写入
    file = await fileIo.open(
      filePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    await writeAll(file, apngBytes);
    await fileIo.close(file);
    file = null;
    return filePath;
  } catch (err) {
    const error = err as BusinessError;
    throw new Error(`写入预览文件失败: ${error.message}`);
  } finally {
    if (file) {
      try {
        await fileIo.close(file);
      } catch (e) {
        // 忽略
      }
    }
  }
}
