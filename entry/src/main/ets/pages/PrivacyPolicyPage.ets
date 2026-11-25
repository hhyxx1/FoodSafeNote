import { FoodButtonStyle, FOOD_TITLE_BAR_STYLE } from '../common/FoodInterface';
import { webview } from '@kit.ArkWeb';
import { deviceInfo } from '@kit.BasicServicesKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppNavigation } from '../common/AppNavigation';

interface PrivacyPolicyParams {
  policyUrl?: string;
}

@Component
struct PrivacyPolicyPage {
  private webController: webview.WebviewController = new webview.WebviewController();
  private currentDeviceType: string = deviceInfo.deviceType;
  @State policyLoadFailed: boolean = false;
  @State policyUrl: string = 'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1881994806624794944';

  // 状态栏高度（vp），由 Index 写入 AppStorage；用于标题栏沉浸避让
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  aboutToAppear(): void {
    const params: PrivacyPolicyParams | undefined = AppNavigation.getParamByName('PrivacyPolicyPage') as PrivacyPolicyParams | undefined;
    if (params !== null && params !== undefined && typeof params.policyUrl === 'string' && params.policyUrl.length > 0) {
      this.policyUrl = params.policyUrl;
    }
  }

  build() {
    HdsNavDestination() {
    Column() {
      Stack() {
        Web({ src: this.policyUrl, controller: this.webController })
          .overScrollMode(OverScrollMode.ALWAYS)
          .width('100%')
          .height('100%')
          .borderRadius(this.currentDeviceType === 'wearable' ? 12 : 0)
          .onErrorReceive((event: OnErrorReceiveEvent) => {
            if (event.request.isMainFrame()) this.policyLoadFailed = true;
          })

        if (this.policyLoadFailed) {
          Column({ space: 12 }) {
            Text($r('app.string.ui_privacy_policy_load_failed'))
              .fontColor($r('app.color.text_primary'))
              .textAlign(TextAlign.Center)
            Button($r('app.string.ui_retry_action'))
              .attributeModifier(FoodButtonStyle.primary)
              .onClick(() => {
                this.policyLoadFailed = false;
                this.webController.refresh();
              })
          }
          .width('100%').height('100%')
          .padding(16)
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.page_background'))
        }
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    // 标题栏沉浸避让：状态栏高度 + 标题栏高度(56vp)
    .padding(this.currentDeviceType === 'wearable'
      ? { left: 16, right: 16, top: 56 + this.statusBarHeight, bottom: 16 }
      : { left: 0, right: 0, top: 56 + this.statusBarHeight, bottom: 0 })
    .backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      content: {
        title: { mainTitle: $r('app.string.privacy_policy_page_title') }
      },
      style: FOOD_TITLE_BAR_STYLE
    })
    .onHidden(() => {
      AppNavigation.notifyDataChanged();
    })
    .backgroundColor($r('app.color.page_background'))
  }
}

// Navigation 系统路由表入口（router_map.json 中注册为 PrivacyPolicyPage）
@Builder
export function PrivacyPolicyPageBuilder() {
  PrivacyPolicyPage()
}
