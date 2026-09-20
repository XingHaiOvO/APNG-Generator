import { crc32Init, crc32Update, crc32Final } from './crc32';

export const PNG_SIGNATURE = new Uint8Array([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
]);

export function writeUint32BEAt(buf: Uint8Array, offset: number, value: number): void {
  buf[offset] = (value >>> 24) & 0xFF;
  buf[offset + 1] = (value >>> 16) & 0xFF;
  buf[offset + 2] = (value >>> 8) & 0xFF;
  buf[offset + 3] = value & 0xFF;
}

function writeUint16BEAt(buf: Uint8Array, offset: number, value: number): void {
  buf[offset] = (value >>> 8) & 0xFF;
  buf[offset + 1] = value & 0xFF;
}

/**
 * 组装一个 PNG 数据块，返回可直接顺序拼接的若干段：
 * [length(4) + type(4)] [data 各段原样引用] [CRC(4)]
 * 数据段不做拷贝，避免为大块 IDAT/fdAT 额外分配一份内存。
 */
export function buildChunk(type: string, dataParts: Uint8Array[]): Uint8Array[] {
  const typeBytes = new Uint8Array(4);
  for (let i = 0; i < 4; i++) typeBytes[i] = type.charCodeAt(i);

  let length = 0;
  let crc = crc32Init();
  crc = crc32Update(crc, typeBytes);
  for (let i = 0; i < dataParts.length; i++) {
    const part = dataParts[i];
    length += part.length;
    crc = crc32Update(crc, part);
  }

  const head = new Uint8Array(8);
  writeUint32BEAt(head, 0, length);
  head.set(typeBytes, 4);

  const tail = new Uint8Array(4);
  writeUint32BEAt(tail, 0, crc32Final(crc));

  const out: Uint8Array[] = [head];
  for (let i = 0; i < dataParts.length; i++) out.push(dataParts[i]);
  out.push(tail);
  return out;
}

/** 把所有分块合并成最终文件字节流 */
export function concatChunks(chunks: Uint8Array[]): Uint8Array {
  let total = 0;
  for (let i = 0; i < chunks.length; i++) total += chunks[i].length;

  const out = new Uint8Array(total);
  let offset = 0;
  for (let i = 0; i < chunks.length; i++) {
    const chunk = chunks[i];
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
}

export function buildSignature(): Uint8Array {
  return PNG_SIGNATURE;
}

export function buildIhdr(width: number, height: number): Uint8Array {
  const data = new Uint8Array(13);
  writeUint32BEAt(data, 0, width);
  writeUint32BEAt(data, 4, height);
  data[8] = 8;   // bit depth
  data[9] = 6;   // color type: RGBA
  data[10] = 0;  // compression
  data[11] = 0;  // filter
  data[12] = 0;  // interlace
  return data;
}

export function buildActl(frameCount: number, loopCount: number): Uint8Array {
  const data = new Uint8Array(8);
  writeUint32BEAt(data, 0, frameCount);
  writeUint32BEAt(data, 4, loopCount);
  return data;
}

export function buildFctl(
  sequence: number, width: number, height: number,
  delayNum: number, delayDen: number
): Uint8Array {
  const data = new Uint8Array(26);
  writeUint32BEAt(data, 0, sequence);
  writeUint32BEAt(data, 4, width);
  writeUint32BEAt(data, 8, height);
  writeUint32BEAt(data, 12, 0);  // x_offset
  writeUint32BEAt(data, 16, 0);  // y_offset
  writeUint16BEAt(data, 20, delayNum);
  writeUint16BEAt(data, 22, delayDen);
  data[24] = 0;  // dispose_op = none
  data[25] = 0;  // blend_op = source
  return data;
}
