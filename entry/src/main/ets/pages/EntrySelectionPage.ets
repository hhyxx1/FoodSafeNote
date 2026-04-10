import { router } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
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
  @StorageLink('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  @State scanCardBgLight: string = '#EDF3FB';
  @State photoCardBgLight: string = '#EDF3FB';
  @State manualCardBgLight: string = '#EDF3FB';
  @State batchCardBgLight: string = '#EDF3FB';
  @State clipCardBgLight: string = '#EDF3FB';
  @State scanCardBgDark: string = '#2A3340';
  @State photoCardBgDark: string = '#2A3340';
  @State manualCardBgDark: string = '#2A3340';
  @State batchCardBgDark: string = '#2A3340';
  @State clipCardBgDark: string = '#2A3340';

  private cardConfigs: EntryCardConfig[] = [
    { iconRaw: 'icon_scan.svg', title: '扫码入库', subtitle: '扫描商品条码，自动匹配商品信息', routeUrl: 'pages/BarcodeScanPage' },
    { iconRaw: 'icon_photo.svg', title: '拍照入库', subtitle: '拍摄食品照片，适合生鲜果蔬', routeUrl: 'pages/PhotoEntryPage' },
    { iconRaw: 'icon_edit.svg', title: '手动入库', subtitle: '手动填写食品信息，适合无条码商品', routeUrl: 'pages/AddFoodPage' },
    { iconRaw: 'icon_batch.svg', title: '批量添加', subtitle: '连续扫码/拍照多件食品，统一补充信息后批量入库', routeUrl: 'pages/BatchAddPage' },
    { iconRaw: 'icon_clipboard.svg', title: '剪贴板解析', subtitle: '手动读取剪贴板中的购物清单并生成待入库卡片', routeUrl: 'pages/ClipboardParsePage' }
  ];

  private isDarkMode(): boolean {
    return this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private getDefaultCardBg(darkMode: boolean): string {
    return darkMode ? '#2A3340' : '#EDF3FB';
  }

  private loadAdaptiveCardBackgrounds(ctx: Context): void {
    this.scanCardBgLight = this.getDefaultCardBg(false);
    this.photoCardBgLight = this.getDefaultCardBg(false);
    this.manualCardBgLight = this.getDefaultCardBg(false);
    this.batchCardBgLight = this.getDefaultCardBg(false);
    this.clipCardBgLight = this.getDefaultCardBg(false);

    this.scanCardBgDark = this.getDefaultCardBg(true);
    this.photoCardBgDark = this.getDefaultCardBg(true);
    this.manualCardBgDark = this.getDefaultCardBg(true);
    this.batchCardBgDark = this.getDefaultCardBg(true);
    this.clipCardBgDark = this.getDefaultCardBg(true);

    AdaptiveColorHelper.cardBgFromIconWithMode(ctx, 'icon_scan.svg', false).then((color: string) => { this.scanCardBgLight = color; });
    AdaptiveColorHelper.cardBgFromIconWithMode(ctx, 'icon_photo.svg', false).then((color: string) => { this.photoCardBgLight = color; });
    AdaptiveColorHelper.cardBgFromIconWithMode(ctx, 'icon_edit.svg', false).then((color: string) => { this.manualCardBgLight = color; });
    AdaptiveColorHelper.cardBgFromIconWithMode(ctx, 'icon_batch.svg', false).then((color: string) => { this.batchCardBgLight = color; });
    AdaptiveColorHelper.cardBgFromIconWithMode(ctx, 'icon_clipboard.svg', false).then((color: string) => { this.clipCardBgLight = color; });

    AdaptiveColorHelper.cardBgFromIconWithMode(ctx, 'icon_scan.svg', true).then((color: string) => { this.scanCardBgDark = color; });
    AdaptiveColorHelper.cardBgFromIconWithMode(ctx, 'icon_photo.svg', true).then((color: string) => { this.photoCardBgDark = color; });
    AdaptiveColorHelper.cardBgFromIconWithMode(ctx, 'icon_edit.svg', true).then((color: string) => { this.manualCardBgDark = color; });
    AdaptiveColorHelper.cardBgFromIconWithMode(ctx, 'icon_batch.svg', true).then((color: string) => { this.batchCardBgDark = color; });
    AdaptiveColorHelper.cardBgFromIconWithMode(ctx, 'icon_clipboard.svg', true).then((color: string) => { this.clipCardBgDark = color; });
  }

  aboutToAppear(): void {
    const ctx: Context = getContext(this) as Context;
    this.loadAdaptiveCardBackgrounds(ctx);
  }

  private getEntryCardBg(iconRaw: string): string {
    const darkMode: boolean = this.isDarkMode();
    if (iconRaw === 'icon_scan.svg') return darkMode ? this.scanCardBgDark : this.scanCardBgLight;
    if (iconRaw === 'icon_photo.svg') return darkMode ? this.photoCardBgDark : this.photoCardBgLight;
    if (iconRaw === 'icon_edit.svg') return darkMode ? this.manualCardBgDark : this.manualCardBgLight;
    if (iconRaw === 'icon_batch.svg') return darkMode ? this.batchCardBgDark : this.batchCardBgLight;
    if (iconRaw === 'icon_clipboard.svg') return darkMode ? this.clipCardBgDark : this.clipCardBgLight;
    return this.getDefaultCardBg(darkMode);
  }

  private getEntryCardTitleColor(iconRaw: string): string {
    const bgColor: string = this.getEntryCardBg(iconRaw);
    return AdaptiveColorHelper.pickTextColor(bgColor, '#182431', 3.0);
  }

  private getEntryCardSubtitleColor(iconRaw: string): string {
    const bgColor: string = this.getEntryCardBg(iconRaw);
    return AdaptiveColorHelper.pickTextColor(bgColor, '#4A5568', 4.5);
  }

  build() {
    Column() {
      // 导航栏
      Row() {
        Button('返回')
          .height(40).fontSize(14).fontColor($r('app.color.accent_link'))
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
              .height(40).fontSize(14).fontColor($r('app.color.button_secondary_text'))
              .backgroundColor($r('app.color.button_secondary_bg')).borderRadius(8).layoutWeight(1)
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
      Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.getEntryCardTitleColor(iconRaw))
      Text(subtitle).fontSize(12).fontColor(this.getEntryCardSubtitleColor(iconRaw)).textAlign(TextAlign.Center)
    }
    .width('100%').padding({ left: 14, right: 14, top: 14, bottom: 14 }).margin({ left: 16, right: 16 })
    .backgroundColor(this.getEntryCardBg(iconRaw)).borderRadius(12)
    .alignItems(HorizontalAlign.Center)
    .shadow({ radius: 3, color: '#0D000000', offsetX: 0, offsetY: 1 })
    .onClick(action)
  }
}
