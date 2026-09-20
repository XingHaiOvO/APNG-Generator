import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, AppStorageV2, UIContext } from '@kit.ArkUI';
import { SafeAreaStore } from '../state/SafeAreaStore';

const DOMAIN = 0x0000;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }

      try {
        const win = windowStage.getMainWindowSync();
        this.setupSafeArea(win);
      } catch (e) {
        const error = e as BusinessError;
        hilog.error(DOMAIN, TAG, 'setupSafeArea failed: %{public}s', error.message);
      }
    });
  }

  /**
   * 开启全屏布局并把状态栏 / 导航条高度同步到共享状态。
   * 全局 px2vp 已废弃，改用 Window 自带的 UIContext 做 px→vp 换算。
   */
  private setupSafeArea(win: window.Window): void {
    let uiContext: UIContext;
    try {
      uiContext = win.getUIContext();
    } catch (e) {
      const error = e as BusinessError;
      hilog.error(DOMAIN, TAG,
        'getUIContext failed: code=%{public}d, message=%{public}s', error.code, error.message);
      return;
    }

    win.setWindowLayoutFullScreen(true).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'setWindowLayoutFullScreen failed: %{public}s', e.message);
    });

    const safeArea = AppStorageV2.connect(
      SafeAreaStore,
      'safeAreaStore',
      () => new SafeAreaStore()
    );
    if (!safeArea) return;

    safeArea.topSafeHeight = this.readAvoidSize(uiContext, win, window.AvoidAreaType.TYPE_SYSTEM);
    hilog.info(DOMAIN, TAG, 'topSafeHeight = %{public}s', safeArea.topSafeHeight.toString());

    safeArea.bottomSafeHeight =
      this.readAvoidSize(uiContext, win, window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    hilog.info(DOMAIN, TAG, 'bottomSafeHeight = %{public}s', safeArea.bottomSafeHeight.toString());

    // 监听安全区变化（横竖屏、折叠屏等）
    win.on('avoidAreaChange', (data: window.AvoidAreaOptions) => {
      if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
        safeArea.topSafeHeight = uiContext.px2vp(data.area.topRect.height);
      } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
        safeArea.bottomSafeHeight = uiContext.px2vp(data.area.bottomRect.height);
      }
    });
  }

  /** 读取指定类型的避让区高度（vp），失败时返回 0 */
  private readAvoidSize(
    uiContext: UIContext, win: window.Window, type: window.AvoidAreaType
  ): number {
    try {
      const area = win.getWindowAvoidArea(type);
      const px = type === window.AvoidAreaType.TYPE_SYSTEM
        ? area.topRect.height
        : area.bottomRect.height;
      return uiContext.px2vp(px);
    } catch (e) {
      const error = e as BusinessError;
      hilog.error(DOMAIN, TAG,
        'getWindowAvoidArea failed: code=%{public}d, message=%{public}s', error.code, error.message);
      return 0;
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    // 兜底：某些场景下窗口属性会被重置，回到前台时重新开启全屏
    try {
      window.getLastWindow(this.context)
        .then((win: window.Window) => {
          try {
            win.setWindowLayoutFullScreen(true).catch(() => {
              // 忽略
            });
          } catch (e) {
            const error = e as BusinessError;
            hilog.error(DOMAIN, TAG,
              'setWindowLayoutFullScreen failed: code=%{public}d, message=%{public}s',
              error.code, error.message);
          }
        })
        .catch((e: BusinessError) => {
          hilog.error(DOMAIN, TAG,
            'getLastWindow failed: code=%{public}d, message=%{public}s',
            e.code, e.message);
        });
    } catch (e) {
      const error = e as BusinessError;
      hilog.error(DOMAIN, TAG,
        'onForeground exception: code=%{public}d, message=%{public}s',
        error.code, error.message);
    }
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
