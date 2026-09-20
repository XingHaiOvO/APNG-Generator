import { FrameItem } from '../models/FrameItem';

/**
 * 全部帧的 RGBA 像素总量上限。
 * 一张 1200 万像素的照片单帧就要约 48MB，不设上限时多选几十张必然 OOM。
 * 编码期间峰值还要再叠加压缩结果和最终输出，所以这里留足余量。
 * 超出后拒绝继续添加并提示用户，而不是等系统杀进程。
 */
export const MAX_TOTAL_FRAME_BYTES: number = 256 * 1024 * 1024;

@ObservedV2
export class FrameStore {
  @Trace frames: FrameItem[] = [];
  @Trace loopCount: number = 0;
  @Trace usedBytes: number = 0;

  /** 是否还能容纳 sizeBytes 的像素数据 */
  hasRoomFor(sizeBytes: number): boolean {
    return this.usedBytes + sizeBytes <= MAX_TOTAL_FRAME_BYTES;
  }

  addFrame(frame: FrameItem) {
    this.frames.push(frame);
    this.usedBytes += frame.byteSize;
  }

  removeFrame(id: string) {
    const target = this.frames.find(f => f.id === id);
    if (target !== undefined) {
      this.usedBytes -= target.byteSize;
      target.release();
    }
    this.frames = this.frames.filter(f => f.id !== id);
  }

  moveFrame(from: number, to: number) {
    const item = this.frames.splice(from, 1)[0];
    this.frames.splice(to, 0, item);
  }

  applyDelayToAll(delayNum: number) {
    // FrameItem 是 @ObservedV2 + @Trace delayNum，逐个赋值即可触发刷新
    for (const f of this.frames) f.delayNum = delayNum;
  }

  clear() {
    for (const f of this.frames) f.release();
    this.frames = [];
    this.usedBytes = 0;
  }
}
