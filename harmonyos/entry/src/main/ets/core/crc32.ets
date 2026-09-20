let table: Uint32Array | null = null;

function initTable(): Uint32Array {
  if (table) return table;
  const t = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let k = 0; k < 8; k++) {
      c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    t[i] = c >>> 0;
  }
  table = t;
  return t;
}

/** 增量计算的起始值，配合 crc32Update/crc32Final 使用 */
export function crc32Init(): number {
  return 0xFFFFFFFF;
}

/** 追加一段数据继续计算（返回中间值，仍是未取反的原始 CRC） */
export function crc32Update(crc: number, data: Uint8Array): number {
  const t = initTable();
  let c = crc;
  for (let i = 0; i < data.length; i++) {
    c = (t[(c ^ data[i]) & 0xFF] ^ (c >>> 8)) >>> 0;
  }
  return c;
}

/** 取反得到最终 CRC32 值 */
export function crc32Final(crc: number): number {
  return (crc ^ 0xFFFFFFFF) >>> 0;
}
