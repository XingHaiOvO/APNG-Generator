import struct
import zlib
from io import BytesIO
from typing import List, Tuple

from PIL import Image

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _write_chunk(out: BytesIO, chunk_type: bytes, data: bytes) -> None:
    out.write(struct.pack(">I", len(data)))
    out.write(chunk_type)
    out.write(data)
    crc = zlib.crc32(chunk_type + data) & 0xFFFFFFFF
    out.write(struct.pack(">I", crc))


def _parse_png(png_data: bytes):
    """解析 PNG，返回 (IHDR 数据, 拼接后的 IDAT 数据)。"""
    if len(png_data) < 8 or png_data[:8] != PNG_SIGNATURE:
        return None

    pos = 8
    ihdr = None
    idat = bytearray()

    while pos + 8 <= len(png_data):
        length = struct.unpack(">I", png_data[pos:pos + 4])[0]
        pos += 4
        chunk_type = png_data[pos:pos + 4]
        pos += 4
        if pos + length + 4 > len(png_data):
            return None
        data = png_data[pos:pos + length]
        pos += length + 4  # skip CRC

        if chunk_type == b"IHDR":
            ihdr = data
        elif chunk_type == b"IDAT":
            idat.extend(data)
        elif chunk_type == b"IEND":
            break

    if ihdr is None or not idat:
        return None
    return ihdr, bytes(idat)


def generate_apng(
    images: List[Image.Image],
    delays: List[Tuple[int, int]],
    loop_count: int = 0,
) -> bytes:
    """
    生成 APNG 文件字节流。

    :param images: PIL Image 列表，尺寸必须一致
    :param delays: 每帧延迟 (delay_num, delay_den)，单位为秒
    :param loop_count: 循环次数，0 表示无限
    :return: APNG 文件字节流
    """
    if not images:
        raise ValueError("至少需要一帧")

    w, h = images[0].size
    for img in images:
        if img.size != (w, h):
            raise ValueError("所有帧的尺寸必须相同")
    if len(delays) != len(images):
        raise ValueError("delays 长度必须与帧数一致")

    # 统一转为 RGBA 并编码为 PNG
    png_frames = []
    for img in images:
        if img.mode != "RGBA":
            img = img.convert("RGBA")
        buf = BytesIO()
        img.save(buf, format="PNG")
        png_frames.append(buf.getvalue())

    parsed_first = _parse_png(png_frames[0])
    if parsed_first is None:
        raise ValueError("第一帧 PNG 解析失败")
    ihdr, first_idat = parsed_first

    out = BytesIO()
    out.write(PNG_SIGNATURE)

    # IHDR
    _write_chunk(out, b"IHDR", ihdr)

    # acTL: 帧数 + 循环次数
    _write_chunk(out, b"acTL", struct.pack(">II", len(images), loop_count))

    seq = 0  # fcTL 和 fdAT 共享 sequence_number

    # 第一帧：fcTL + IDAT
    delay_num, delay_den = delays[0]
    fctl = struct.pack(
        ">IIIIIHHBB",
        seq, w, h, 0, 0,
        delay_num, delay_den,
        0,  # dispose_op = none
        0,  # blend_op = source
    )
    _write_chunk(out, b"fcTL", fctl)
    seq += 1
    _write_chunk(out, b"IDAT", first_idat)

    # 后续帧：fcTL + fdAT
    for i in range(1, len(images)):
        parsed = _parse_png(png_frames[i])
        if parsed is None:
            raise ValueError(f"第 {i + 1} 帧 PNG 解析失败")
        _, idat = parsed

        delay_num, delay_den = delays[i]
        fctl = struct.pack(
            ">IIIIIHHBB",
            seq, w, h, 0, 0,
            delay_num, delay_den,
            0, 0,
        )
        _write_chunk(out, b"fcTL", fctl)
        seq += 1

        fdat = struct.pack(">I", seq) + idat
        _write_chunk(out, b"fdAT", fdat)
        seq += 1

    _write_chunk(out, b"IEND", b"")
    return out.getvalue()