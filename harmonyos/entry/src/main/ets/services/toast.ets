import { UIContext } from '@kit.ArkUI';

/**
 * 全局 promptAction.showToast 自 API 18 起已废弃，
 * 统一改走 UIContext，也避免多窗口场景下弹错窗口。
 */
export function showToast(uiContext: UIContext, message: string, duration: number = 2000): void {
  try {
    uiContext.getPromptAction().showToast({ message, duration });
  } catch (err) {
    console.error(`showToast failed: ${JSON.stringify(err)}`);
  }
}
