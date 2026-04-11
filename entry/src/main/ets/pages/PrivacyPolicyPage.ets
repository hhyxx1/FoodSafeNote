import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { deviceInfo } from '@kit.BasicServicesKit';

interface PrivacyPolicyParams {
  policyUrl?: string;
}

@Entry
@Component
struct PrivacyPolicyPage {
  private webController: webview.WebviewController = new webview.WebviewController();
  private currentDeviceType: string = deviceInfo.deviceType;
  @State policyUrl: string = 'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1881994806624794944';

  aboutToAppear(): void {
    const params: PrivacyPolicyParams = router.getParams() as PrivacyPolicyParams;
    if (params && typeof params.policyUrl === 'string' && params.policyUrl.length > 0) {
      this.policyUrl = params.policyUrl;
    }
  }

  build() {
    Column() {
      Row() {
        Button('返回')
          .height(this.currentDeviceType === 'wearable' ? 34 : 40)
          .fontSize(this.currentDeviceType === 'wearable' ? 12 : 14)
          .fontColor($r('app.color.accent_link'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            router.back();
          })
        Text($r('app.string.privacy_policy_page_title'))
          .fontSize(this.currentDeviceType === 'wearable' ? 15 : 18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('').width(this.currentDeviceType === 'wearable' ? 48 : 56)
      }
      .width('100%')
      .padding(this.currentDeviceType === 'wearable'
        ? { left: 6, right: 6, top: 6, bottom: 6 }
        : { left: 8, right: 8, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))

      Web({ src: this.policyUrl, controller: this.webController })
        .width('100%')
        .borderRadius(this.currentDeviceType === 'wearable' ? 12 : 0)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding(this.currentDeviceType === 'wearable'
      ? { left: 16, right: 16, top: 16, bottom: 16 }
      : { left: 0, right: 0, top: 0, bottom: 0 })
    .backgroundColor($r('app.color.page_background'))
  }
}
