/**
 * 释放预览图前的等待时间。
 * 删除帧的同一轮里，列表中的 Image 可能还在绘制这个 PixelMap，
 * 立刻释放会撞上"绘制已释放对象"；等界面完成一次重绘再放，用户无感。
 */
const RELEASE_DELAY_MS: number = 100;

@ObservedV2
export class FrameItem {
  @Trace id: string;
  @Trace pixelMap: PixelMap;     // 用于预览（已降采样）
  @Trace rgba: Uint8Array;       // 用于编码（原始分辨率）
  @Trace width: number;
  @Trace height: number;
  @Trace delayNum: number = 10;
  @Trace delayDen: number = 100;

  constructor(id: string, pixelMap: PixelMap, rgba: Uint8Array, w: number, h: number) {
    this.id = id;
    this.pixelMap = pixelMap;
    this.rgba = rgba;
    this.width = w;
    this.height = h;
  }

  /** RGBA 像素占用字节数，用于统计内存预算 */
  get byteSize(): number {
    return this.rgba.byteLength;
  }

  /** 释放预览图占用的原生内存 */
  release(): void {
    // 注意：这里只负责延时释放，调用方不必等待
    setTimeout(() => {
      this.pixelMap.release().catch((e: Error) => {
        console.error(`release frame pixelMap failed: ${e.message}`);
      });
    }, RELEASE_DELAY_MS);
  }
}
