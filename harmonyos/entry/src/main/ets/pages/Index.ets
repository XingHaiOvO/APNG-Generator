import { FrameItem } from '../models/FrameItem';
import { FrameStore, MAX_TOTAL_FRAME_BYTES } from '../state/FrameStore';
import { loadImageFromUri, releaseLoadedImage } from '../services/image_loader';
import { writeApngToSandbox, createAlbumImageAsset, writeBytesToAlbumAsset } from '../services/export_service';
import { encodeApng, FrameData } from '../core/apng_encoder';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { showToast } from '../services/toast';
import { apng, ApngController } from '@ohos/apng';
import { AppStorageV2 } from '@kit.ArkUI';
import { SafeAreaStore } from '../state/SafeAreaStore';

/** APNG 的 delay_num 是 16 位字段，超过 65535 会在编码时被截断 */
const MAX_DELAY_NUM: number = 65535;
/** acTL 的 num_plays 是 32 位无符号字段 */
const MAX_LOOP_COUNT: number = 4294967295;

/** 超过这个体积就不再缓存编码结果：长期驻留一份大缓冲的代价高于重新编码 */
const CACHE_MAX_BYTES: number = 16 * 1024 * 1024;

/**
 * 应用内 apng 动画预览的体积上限。
 * apng 组件会在 UI 线程把每一帧转成 base64 字符串再播放，文件大时会长时间卡住界面，
 * 因此超过上限就只保留逐帧步进预览。
 */
const APNG_PREVIEW_MAX_BYTES: number = 20 * 1024 * 1024;

function formatMb(bytes: number): string {
  return `${Math.round(bytes / (1024 * 1024))}MB`;
}

@Entry
@ComponentV2
struct Index {
  private store: FrameStore = new FrameStore();
  @Local isEncoding: boolean = false;
  @Local previewIndex: number = 0;

  @Local previewW: number = 240;
  @Local previewH: number = 240;

  private previewTimer: number = -1;
  @Local isPreviewing: boolean = false;

  @Local apngPreviewPath: string = '';
  /** apng 动画预览是否正在播放（决定底部按钮的图标与文案） */
  @Local isApngPlaying: boolean = false;
  private apngController: ApngController = new ApngController();

  @Local safeArea: SafeAreaStore = AppStorageV2.connect(
  SafeAreaStore,
  'safeAreaStore',
  () => new SafeAreaStore()
  )!;

  @Local batchDelay: number = 10;   // 批量延迟输入值
  @Local encodeProgress: string = '';   // 编码进度，例如 "3/10"

  // 编码结果缓存：帧内容不变时重复保存不必重新编码
  private cachedBytes: Uint8Array | null = null;
  private cacheSignature: string = '';

  aboutToDisappear() {
    this.stopPreview();
    this.apngController.stop();
  }

  // ------------------ 选择图片 ------------------
  async pickImages() {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 100;
    const picker = new photoAccessHelper.PhotoViewPicker();

    let result: photoAccessHelper.PhotoSelectResult;
    try {
      result = await picker.select(options);
    } catch (e) {
      console.error(`选择图片失败: ${e.message}`);
      return;
    }
    if (!result || result.photoUris.length === 0) return;

    const expectedWidth = this.store.frames.length > 0 ? this.store.frames[0].width : -1;
    const expectedHeight = this.store.frames.length > 0 ? this.store.frames[0].height : -1;

    let skippedFormat = 0;
    let skippedSize = 0;
    let skippedMemory = 0;

    for (const uri of result.photoUris) {
      try {
        const loaded = await loadImageFromUri(uri);

        if (expectedWidth !== -1 &&
          (loaded.width !== expectedWidth || loaded.height !== expectedHeight)) {
          releaseLoadedImage(loaded);   // 跳过的图片必须释放，否则白白占着显存
          skippedSize++;
          continue;
        }

        // 像素总量预算：宁可少加几帧，也不要因为 OOM 被系统杀掉
        if (!this.store.hasRoomFor(loaded.rgba.byteLength)) {
          releaseLoadedImage(loaded);
          skippedMemory++;
          continue;
        }

        const frame = new FrameItem(
          `${Date.now()}_${Math.random()}`,
          loaded.pixelMap, loaded.rgba, loaded.width, loaded.height
        );
        this.store.addFrame(frame);
      } catch (e) {
        const msg = (e as Error).message ?? '';
        if (msg.includes('不支持')) skippedFormat++;
        console.error(`加载失败: ${uri}, ${msg}`);
      }
    }

    this.onFramesChanged();

    if (skippedFormat > 0) {
      this.getUIContext().showAlertDialog({
        title: '部分图片已跳过',
        message: `${skippedFormat} 张图片格式不受支持（WebP / HEIC 已被禁用，或像素格式无法转换为 RGBA）。\n支持格式：PNG、JPEG、BMP、GIF、TIFF。`,
        confirm: { value: '知道了', action: () => {} }
      });
    }
    if (skippedSize > 0) {
      showToast(this.getUIContext(), `${skippedSize} 张因尺寸不一致已跳过`, 2500);
    }
    if (skippedMemory > 0) {
      showToast(this.getUIContext(),
        `已达内存上限（${formatMb(MAX_TOTAL_FRAME_BYTES)}），${skippedMemory} 张未添加`, 3000);
    }
  }

  /**
   * 帧内容变化后的统一收尾：
   * 1) 丢弃编码缓存；
   * 2) 关掉动画预览——它已经和当前帧对不上了，退回逐帧步进预览。
   * 任何会改变输出结果的编辑都要走这里，否则画面上播的还是上一次保存的旧动画。
   */
  private onFramesChanged(): void {
    this.cachedBytes = null;
    this.cacheSignature = '';
    this.closeApngPreview();
  }

  /**
   * 帧集合 / 延迟 / 循环数任一变化都会让签名变化，
   * 用签名判断缓存是否还能复用，比手工在每个修改点置脏更不容易漏。
   */
  private computeSignature(): string {
    let signature = `${this.store.loopCount}|${this.store.frames.length}`;
    for (const f of this.store.frames) {
      signature += `|${f.id}:${f.delayNum}:${f.delayDen}`;
    }
    return signature;
  }

  // ------------------ 编码 ------------------
  async buildApngBytes(): Promise<Uint8Array> {
    const signature = this.computeSignature();
    if (this.cachedBytes !== null && this.cacheSignature === signature) {
      return this.cachedBytes;
    }

    // 先断开旧结果的引用，否则编码期间新旧两份等量数据会同时驻留
    this.cachedBytes = null;
    this.cacheSignature = '';

    const frameData: FrameData[] = this.store.frames.map(f =>
    new FrameData(f.width, f.height, f.rgba, f.delayNum, f.delayDen)
    );
    this.encodeProgress = `0/${frameData.length}`;
    const bytes = await encodeApng(frameData, this.store.loopCount,
      (done: number, total: number): void => {
        this.encodeProgress = `${done}/${total}`;
      });

    // 大文件不缓存：驻留一份几十上百 MB 的结果，风险高于重新编码一次
    if (bytes.byteLength <= CACHE_MAX_BYTES) {
      this.cachedBytes = bytes;
      this.cacheSignature = signature;
    }
    return bytes;
  }

  // ------------------ 保存 ------------------
  async onSaveClick(result: SaveButtonOnClickResult) {
    if (result !== SaveButtonOnClickResult.SUCCESS) return;
    if (this.store.frames.length === 0) {
      showToast(this.getUIContext(), '请先添加帧');
      return;
    }
    if (this.isEncoding) return;

    this.isEncoding = true;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;

    try {
      // 1. 先取相册 uri：安全控件的临时授权自点击起只有 1 分钟
      //    （API 19 及以前仅 10 秒），必须赶在耗时编码之前调用 createAsset。
      const uri = await createAlbumImageAsset(context);

      // 2. 编码：拿到 uri 之后写入不再受授权时限约束，可以慢慢算
      const bytes = await this.buildApngBytes();

      // 3. 写入相册
      await writeBytesToAlbumAsset(uri, bytes);
      showToast(this.getUIContext(), '已保存到相册');

      // 4. 顺带刷新应用内预览，失败不影响保存结果
      try {
        if (bytes.byteLength > APNG_PREVIEW_MAX_BYTES) {
          // apng 组件加载时会在 UI 线程逐帧转 base64，大文件会把界面卡住，
          // 这里直接跳过动画预览，保留逐帧步进预览（点"播放预览"）
          this.closeApngPreview();
          showToast(this.getUIContext(),
            `文件 ${formatMb(bytes.byteLength)}，已跳过动画预览（保存已完成）`, 3000);
        } else {
          const previewPath = await writeApngToSandbox(context, bytes, 'preview.png');
          // 逐帧预览的定时器没必要再跑，画面已经切给 apng 组件了
          this.stopPreview();
          this.apngPreviewPath = previewPath;
          this.apngController.stop();   // 先回到第一帧，再从头播放
          this.apngController.play();
          this.isApngPlaying = true;
        }
      } catch (previewErr) {
        console.error(`生成预览失败: ${(previewErr as Error).message}`);
      }
    } catch (e) {
      showToast(this.getUIContext(), `生成失败：${(e as Error).message}`, 3000);
    } finally {
      this.isEncoding = false;
      this.encodeProgress = '';
    }
  }

  // ------------------ 手动按帧预览 ------------------
  startPreview() {
    if (this.store.frames.length === 0) return;
    if (this.isPreviewing) return;

    this.isPreviewing = true;
    this.previewIndex = 0;
    this.tickPreview();
  }

  stopPreview() {
    if (this.previewTimer !== -1) {
      clearTimeout(this.previewTimer);
      this.previewTimer = -1;
    }
    this.isPreviewing = false;
  }

  togglePreview() {
    if (this.isApngPreviewShown()) {
      if (this.isApngPlaying) {
        this.apngController.pause();   // 停在当前帧，保留播放进度
        this.isApngPlaying = false;
      } else {
        this.apngController.play();
        this.isApngPlaying = true;
      }
      return;
    }

    if (this.isPreviewing) {
      this.stopPreview();
    } else {
      this.startPreview();
    }
  }

  /** 关闭 apng 动画预览，回到逐帧步进预览 */
  private closeApngPreview(): void {
    this.apngPreviewPath = '';
    this.isApngPlaying = false;
    this.apngController.pause();
  }

  /** 预览区当前显示的是 apng 动画（而不是逐帧步进） */
  private isApngPreviewShown(): boolean {
    return this.apngPreviewPath !== '';
  }

  /** 当前预览是否正在播放 */
  private isPreviewPlaying(): boolean {
    return this.isApngPreviewShown() ? this.isApngPlaying : this.isPreviewing;
  }

  /** apng 预览用的是暂停/继续，逐帧预览用的是停止/播放 */
  private previewButtonLabel(): string {
    if (this.isApngPreviewShown()) {
      return this.isApngPlaying ? '暂停预览' : '继续预览';
    }
    return this.isPreviewing ? '停止预览' : '播放预览';
  }

  private tickPreview() {
    if (!this.isPreviewing) return;
    if (this.store.frames.length === 0) {
      this.stopPreview();
      return;
    }
    const frame = this.store.frames[this.previewIndex];
    if (!frame) {
      // 下标兜底：删除帧后若下标一时没跟上，退回第一帧而不是解引用 undefined
      this.previewIndex = 0;
      return;
    }
    const delay = frame.delayDen > 0 ? (frame.delayNum * 1000 / frame.delayDen) : 100;
    this.previewTimer = setTimeout(() => {
      if (!this.isPreviewing) return;
      if (this.store.frames.length === 0) {
        this.stopPreview();
        return;
      }
      this.previewIndex = (this.previewIndex + 1) % this.store.frames.length;
      this.tickPreview();
    }, delay);
  }

  // ------------------ 清空所有帧 ------------------
  private confirmClear() {
    if (this.store.frames.length === 0) return;
    this.getUIContext().showAlertDialog({
      title: '清空所有帧',
      message: `确定删除全部 ${this.store.frames.length} 张图片吗？此操作不可撤销。`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '清空',
        fontColor: $r('sys.color.warning'),
        action: () => {
          this.stopPreview();
          this.store.clear();
          this.onFramesChanged();   // 已包含关闭动画预览
          this.previewIndex = 0;
        }
      }
    });
  }

  /** 删除单帧并修正预览下标 */
  private removeFrame(item: FrameItem) {
    this.store.removeFrame(item.id);
    this.onFramesChanged();   // 已包含关闭动画预览
    if (this.store.frames.length === 0) {
      this.stopPreview();
      this.previewIndex = 0;
    } else if (this.previewIndex >= this.store.frames.length) {
      this.previewIndex = 0;
    }
  }

  // ------------------ 批量应用延迟 ------------------
  private applyBatchDelay() {
    if (this.store.frames.length === 0) return;
    if (this.batchDelay < 1) {
      showToast(this.getUIContext(), '延迟必须大于 0');
      return;
    }
    this.store.applyDelayToAll(this.batchDelay);
    this.onFramesChanged();
    showToast(this.getUIContext(),
      `已将全部 ${this.store.frames.length} 帧延迟设为 ${this.batchDelay}/100s`);

    // 用新延迟重播正在进行的预览
    if (this.isPreviewing) {
      this.stopPreview();
      this.startPreview();
    }
  }

  // ============================================================
  //                            UI
  // ============================================================
  build() {
    Column() {
      // ---------- 1. 标题区 ----------
      Column({ space: 4 }) {
        Text('APNG Generator')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
        Text('拖拽排序 · 逐帧延迟 · 一键生成')
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 8, bottom: 12 })

      // ---------- 2. 大预览区 ----------
      Stack() {
        if (this.apngPreviewPath !== '') {
          apng({
            src: this.apngPreviewPath,
            speedRate: 1,
            apngWidth: this.previewW,
            apngHeight: this.previewH,
            controller: this.apngController
          })
        } else if (this.store.frames.length > 0) {
          Image(this.store.frames[this.previewIndex].pixelMap)
            .width('100%').height('100%')
            .objectFit(ImageFit.Contain)
        } else {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.picture'))
              .fontSize(56)
              .fontColor([$r('sys.color.font_secondary')])
              .opacity(0.4)
            Text('暂无预览')
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
            Text('添加图片后点击保存')
              .fontSize(12)
              .fontColor($r('sys.color.font_tertiary'))
          }
        }
      }
      .width('100%')
      .height(240)
      .padding(16)
      .borderRadius(16)
      .backgroundColor($r('sys.color.background_secondary')).onAreaChange((oldVal: Area, newVal: Area): void => {
        // 动态更新 apng 渲染尺寸，减去 padding 32
        const w = newVal.width as number - 32;
        const h = newVal.height as number - 32;
        if (w > 0 && h > 0) {
          this.previewW = w;
          this.previewH = h;
        }
      })

      // ---------- 3. 参数栏 ----------
      Column({ space: 8 }) {
        // 第一行：循环次数 + 添加图片
        Row({ space: 8 }) {
          Text('循环')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))

          TextInput({ text: `${this.store.loopCount}` })
            .type(InputType.Number)
            .maxLength(10)
            .width(64).height(36)
            .backgroundColor($r('sys.color.background_primary'))
            .onChange((v: string): void => {
              // 输入过程中允许空串，解析不出数字就不回写，避免清空时被强行填回
              const n = parseInt(v, 10);
              if (isNaN(n)) return;
              const next = Math.min(MAX_LOOP_COUNT, Math.max(0, n));
              if (next === this.store.loopCount) return;   // 值没变就别打断预览
              this.store.loopCount = next;
              this.onFramesChanged();
            })

          Text('0 = 无限')
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))

          Blank()

          Button('添加图片')
            .height(36)
            .fontSize(13)
            .backgroundColor($r('sys.color.background_primary'))
            .fontColor($r('sys.color.font_emphasize'))
            .onClick((): void => { this.pickImages(); })
        }
        .width('100%')

        // 第二行：批量延迟 + 应用到全部帧（有帧时显示）
        if (this.store.frames.length > 0) {
          Row({ space: 8 }) {
            Text('批量延迟')
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))

            TextInput({ text: `${this.batchDelay}` })
              .type(InputType.Number)
              .maxLength(5)
              .width(64).height(36)
              .backgroundColor($r('sys.color.background_primary'))
              .onChange((v: string): void => {
                const n = parseInt(v, 10);
                if (isNaN(n)) return;
                this.batchDelay = Math.min(MAX_DELAY_NUM, Math.max(1, n));
              })
              .onSubmit((): void => {
                if (this.batchDelay < 1) this.batchDelay = 1;
              })

            Text('/100s')
              .fontSize(12)
              .fontColor($r('sys.color.font_tertiary'))

            Blank()

            Button('应用到全部帧')
              .height(36)
              .fontSize(13)
              .backgroundColor($r('sys.color.background_primary'))
              .fontColor($r('sys.color.font_emphasize'))
              .onClick((): void => this.applyBatchDelay())
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding({ top: 12, bottom: 8 })

      // ---------- 4. 帧列表标题 + 清空 ----------
      Row({ space: 8 }) {
        Text('帧列表')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
        Text(`(${this.store.frames.length})`)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))

        // 像素占用超过预算一半时提示，让"加不进去"这件事有解释
        if (this.store.usedBytes * 2 > MAX_TOTAL_FRAME_BYTES) {
          Text(`像素占用 ${formatMb(this.store.usedBytes)} / ${formatMb(MAX_TOTAL_FRAME_BYTES)}`)
            .fontSize(11)
            .fontColor($r('sys.color.warning'))
        }

        Blank()

        if (this.store.frames.length > 0) {
          if (this.isEncoding) {
            Text(`生成中 ${this.encodeProgress}`)
              .fontSize(11)
              .fontColor($r('sys.color.font_emphasize'))
          } else {
            Text('长按拖动排序')
              .fontSize(11)
              .fontColor($r('sys.color.font_tertiary'))
          }

          Button('清空')
            .fontSize(12).height(28)
            .backgroundColor($r('sys.color.background_primary'))
            .fontColor($r('sys.color.warning'))
            .onClick((): void => this.confirmClear())
        }
      }
      .width('100%')
      .padding({ top: 8, bottom: 6, left: 4, right: 4 })

      // ---------- 5. 帧列表 ----------
      if (this.store.frames.length === 0) {
        // 空状态
        Column({ space: 6 }) {
          Text('还没有添加任何图片')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
          Text('点击上方“添加图片”按钮开始')
            .fontSize(12)
            .fontColor($r('sys.color.font_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(
            this.store.frames,
            (item: FrameItem, index: number) => {
              ListItem() {
                Row({ space: 10 }) {
                  // 序号
                  Text(`${index + 1}`)
                    .fontSize(12)
                    .fontColor($r('sys.color.font_tertiary'))
                    .width(20)
                    .textAlign(TextAlign.Center)

                  // 缩略图
                  Image(item.pixelMap)
                    .width(48).height(48)
                    .objectFit(ImageFit.Contain)
                    .borderRadius(8)
                    .backgroundColor($r('sys.color.background_secondary'))

                  // 延迟编辑
                  Column({ space: 2 }) {
                    Text('延迟')
                      .fontSize(11)
                      .fontColor($r('sys.color.font_tertiary'))
                    Row({ space: 4 }) {
                      TextInput({ text: `${item.delayNum}` })
                        .type(InputType.Number)
                        .maxLength(5)
                        .width(56).height(30)
                        .fontSize(13)
                        .backgroundColor($r('sys.color.background_secondary'))
                        .onChange((v: string): void => {
                          const n = parseInt(v, 10);
                          if (isNaN(n)) return;
                          const next = Math.min(MAX_DELAY_NUM, Math.max(1, n));
                          if (next === item.delayNum) return;   // 值没变就别打断预览
                          item.delayNum = next;
                          this.onFramesChanged();
                        })
                        .onSubmit((): void => {
                          if (item.delayNum < 1) item.delayNum = 1;
                        })
                      Text('/100s')
                        .fontSize(11)
                        .fontColor($r('sys.color.font_tertiary'))
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  // 单帧删除
                  Button({ type: ButtonType.Circle, stateEffect: true }) {
                    SymbolGlyph($r('sys.symbol.xmark'))
                      .fontSize(16)
                      .fontColor([$r('sys.color.font_secondary')])
                  }
                  .width(32).height(32)
                  .backgroundColor(Color.Transparent)
                  .onClick((): void => this.removeFrame(item))
                }
                .width('95%')
                .padding({ left: 12, right: 8, top: 10, bottom: 10 })
                .backgroundColor($r('sys.color.background_primary'))
                .borderRadius(12)
                .margin({ left: '2.5%', right: '2.5%' })
              }
            },
            (item: FrameItem): string => item.id
          )
            .onMove((from: number, to: number): void => {
              this.store.moveFrame(from, to);
              this.onFramesChanged();
            })
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .clip(true)
      }

      // ---------- 6. 底部操作栏 ----------
      Row({ space: 12 }) {
        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r(this.isPreviewPlaying() ? 'sys.symbol.pause' : 'sys.symbol.play_fill'))
              .fontSize(16)
              .fontColor([$r('sys.color.font_emphasize')])
            Text(this.previewButtonLabel())
              .fontSize(14)
              .fontColor($r('sys.color.font_emphasize'))
          }
          .justifyContent(FlexAlign.Center)
        }
        .layoutWeight(1)
        .height(44)
        .backgroundColor($r('sys.color.background_primary'))
        .enabled(this.store.frames.length > 0)
        .onClick((): void => this.togglePreview())

        SaveButton({ text: SaveDescription.SAVE_IMAGE })
          .width('48%')
          .height(44)
          .fontSize(14)
          .onClick(async (event: ClickEvent, result: SaveButtonOnClickResult): Promise<void> => {
            await this.onSaveClick(result);
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 8 })
    }
    .padding({
      left: 16,
      right: 16,
      top: 8 + this.safeArea.topSafeHeight,
      bottom: 8 + this.safeArea.bottomSafeHeight
    })
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_tertiary'))
  }
}
