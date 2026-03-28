import { router } from '@kit.ArkUI';
import { AdaptiveColorHelper } from '../common/AdaptiveColorHelper';

interface EntryCardConfig {
  iconRaw: string;
  title: string;
  subtitle: string;
  routeUrl: string;
}

@Entry
@Component
struct EntrySelectionPage {
  @State scanCardBg: string = '#EDF3FB';
  @State photoCardBg: string = '#EDF3FB';
  @State manualCardBg: string = '#EDF3FB';
  @State batchCardBg: string = '#EDF3FB';
  @State clipCardBg: string = '#EDF3FB';

  private cardConfigs: EntryCardConfig[] = [
    { iconRaw: 'icon_scan.svg', title: '扫码入库', subtitle: '扫描商品条码，自动匹配商品信息', routeUrl: 'pages/BarcodeScanPage' },
    { iconRaw: 'icon_photo.svg', title: '拍照入库', subtitle: '拍摄食品照片，适合生鲜果蔬', routeUrl: 'pages/PhotoEntryPage' },
    { iconRaw: 'icon_edit.svg', title: '手动入库', subtitle: '手动填写食品信息，适合无条码商品', routeUrl: 'pages/AddFoodPage' },
    { iconRaw: 'icon_batch.svg', title: '批量添加', subtitle: '连续扫码/拍照多件食品，统一补充信息后批量入库', routeUrl: 'pages/BatchAddPage' },
    { iconRaw: 'icon_clipboard.svg', title: '剪贴板解析', subtitle: '手动读取剪贴板中的购物清单并生成待入库卡片', routeUrl: 'pages/ClipboardParsePage' }
  ];

  aboutToAppear(): void {
    const ctx: Context = getContext(this) as Context;
    AdaptiveColorHelper.cardBgFromIcon(ctx, 'icon_scan.svg').then((color: string) => { this.scanCardBg = color; });
    AdaptiveColorHelper.cardBgFromIcon(ctx, 'icon_photo.svg').then((color: string) => { this.photoCardBg = color; });
    AdaptiveColorHelper.cardBgFromIcon(ctx, 'icon_edit.svg').then((color: string) => { this.manualCardBg = color; });
    AdaptiveColorHelper.cardBgFromIcon(ctx, 'icon_batch.svg').then((color: string) => { this.batchCardBg = color; });
    AdaptiveColorHelper.cardBgFromIcon(ctx, 'icon_clipboard.svg').then((color: string) => { this.clipCardBg = color; });
  }

  private getEntryCardBg(iconRaw: string): string {
    if (iconRaw === 'icon_scan.svg') return this.scanCardBg;
    if (iconRaw === 'icon_photo.svg') return this.photoCardBg;
    if (iconRaw === 'icon_edit.svg') return this.manualCardBg;
    if (iconRaw === 'icon_batch.svg') return this.batchCardBg;
    if (iconRaw === 'icon_clipboard.svg') return this.clipCardBg;
    return '#EDF3FB';
  }

  build() {
    Column() {
      // 导航栏
      Row() {
        Button('返回')
          .height(36).fontSize(14).fontColor('#007DFF')
          .backgroundColor(Color.Transparent)
          .onClick(() => { router.back(); })
        Text('选择入库方式')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          .layoutWeight(1).textAlign(TextAlign.Center)
        Text('').width(56)
      }
      .width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))

      Scroll() {
        Column({ space: 12 }) {
          Blank()
            .height(6)

          ForEach(this.cardConfigs, (item: EntryCardConfig) => {
            this.buildEntryCard(item.iconRaw, item.title, item.subtitle, () => {
              router.pushUrl({ url: item.routeUrl });
            })
          }, (item: EntryCardConfig) => item.iconRaw)

          // 底部快捷入口
          Row({ space: 16 }) {
            Button('产品字典')
              .height(40).fontSize(14).fontColor('#007DFF')
              .backgroundColor('#E8F0FE').borderRadius(8).layoutWeight(1)
              .onClick(() => { router.pushUrl({ url: 'pages/ProductDictPage' }); })
          }
          .width('100%').padding({ left: 16, right: 16, bottom: 16 })
        }
      }
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }

  @Builder
  buildEntryCard(iconRaw: string, title: string, subtitle: string, action: () => void) {
    Column({ space: 6 }) {
      Image($rawfile(iconRaw)).width(30).height(30)
      Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text(subtitle).fontSize(12).fontColor($r('app.color.text_hint')).textAlign(TextAlign.Center)
    }
    .width('100%').padding({ left: 14, right: 14, top: 14, bottom: 14 }).margin({ left: 16, right: 16 })
    .backgroundColor(this.getEntryCardBg(iconRaw)).borderRadius(12)
    .alignItems(HorizontalAlign.Center)
    .shadow({ radius: 3, color: '#0D000000', offsetX: 0, offsetY: 1 })
    .onClick(action)
  }
}
