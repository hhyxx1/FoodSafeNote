import { InventoryView } from '../views/InventoryView';
import { HealthView } from '../views/HealthView';
import { MineView } from '../views/MineView';
import { WatchInventoryView } from '../views/WatchInventoryView';
import { WatchHealthView } from '../views/WatchHealthView';
// WatchMineView removed - watch only has inventory + health
import { TvInventoryView } from '../views/TvInventoryView';
import { TvHealthView } from '../views/TvHealthView';
import { TvMineView } from '../views/TvMineView';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { BarcodeService } from '../common/BarcodeService';
import { deviceInfo } from '@kit.BasicServicesKit';
import { common, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { AdaptiveColorHelper } from '../common/AdaptiveColorHelper';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @State refreshKey: number = 0;
  @State @Watch('onWatchListOpenChanged') watchListOpen: boolean = false;
  @State showPrivacyConsentDialog: boolean = false;
  private watchTouchStartX: number = 0;
  private watchTouchStartY: number = 0;
  @StorageLink('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  private tabsController: TabsController = new TabsController();
  private currentDeviceType: string = deviceInfo.deviceType;
  private lastWatchListClosedAt: number = 0;
  private prevWatchListOpen: boolean = false;
  private hasInitializedData: boolean = false;
  private readonly watchPrivacyConsentKey: string = 'watchPrivacyConsentVersion';
  private readonly privacyPolicyVersion: string = '2026-04-11';
  private readonly privacyPolicyUrl: string = 'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1881994806624794944';
  @State inventoryTabBgLight: string = '#E8F0FE';
  @State healthTabBgLight: string = '#FDECEC';
  @State dictTabBgLight: string = '#EEF2F5';
  @State inventoryTabBgDark: string = '#2F4560';
  @State healthTabBgDark: string = '#4A3535';
  @State dictTabBgDark: string = '#3A4148';

  private isDarkMode(): boolean {
    return this.appColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private getDefaultTabIconBg(iconRaw: string, darkMode: boolean): string {
    if (iconRaw === 'icon_inventory.svg') {
      return darkMode ? '#2F4560' : '#E8F0FE';
    }
    if (iconRaw === 'icon_health.svg') {
      return darkMode ? '#4A3535' : '#FDECEC';
    }
    if (iconRaw === 'icon_dict.svg') {
      return darkMode ? '#3A4148' : '#EEF2F5';
    }
    return darkMode ? '#2F4560' : '#E8F0FE';
  }

  private loadAdaptiveTabBackgrounds(ctx: Context): void {
    this.inventoryTabBgLight = this.getDefaultTabIconBg('icon_inventory.svg', false);
    this.healthTabBgLight = this.getDefaultTabIconBg('icon_health.svg', false);
    this.dictTabBgLight = this.getDefaultTabIconBg('icon_dict.svg', false);
    this.inventoryTabBgDark = this.getDefaultTabIconBg('icon_inventory.svg', true);
    this.healthTabBgDark = this.getDefaultTabIconBg('icon_health.svg', true);
    this.dictTabBgDark = this.getDefaultTabIconBg('icon_dict.svg', true);

    AdaptiveColorHelper.accentBgFromIconWithMode(ctx, 'icon_inventory.svg', false).then((color: string) => {
      this.inventoryTabBgLight = color;
    });
    AdaptiveColorHelper.accentBgFromIconWithMode(ctx, 'icon_health.svg', false).then((color: string) => {
      this.healthTabBgLight = color;
    });
    AdaptiveColorHelper.accentBgFromIconWithMode(ctx, 'icon_dict.svg', false).then((color: string) => {
      this.dictTabBgLight = color;
    });

    AdaptiveColorHelper.accentBgFromIconWithMode(ctx, 'icon_inventory.svg', true).then((color: string) => {
      this.inventoryTabBgDark = color;
    });
    AdaptiveColorHelper.accentBgFromIconWithMode(ctx, 'icon_health.svg', true).then((color: string) => {
      this.healthTabBgDark = color;
    });
    AdaptiveColorHelper.accentBgFromIconWithMode(ctx, 'icon_dict.svg', true).then((color: string) => {
      this.dictTabBgDark = color;
    });
  }

  private getTabIconBg(iconRaw: string): string {
    const darkMode: boolean = this.isDarkMode();
    if (iconRaw === 'icon_inventory.svg') return darkMode ? this.inventoryTabBgDark : this.inventoryTabBgLight;
    if (iconRaw === 'icon_health.svg') return darkMode ? this.healthTabBgDark : this.healthTabBgLight;
    if (iconRaw === 'icon_dict.svg') return darkMode ? this.dictTabBgDark : this.dictTabBgLight;
    return this.getDefaultTabIconBg(iconRaw, darkMode);
  }

  private isWearableDevice(): boolean {
    return this.currentDeviceType === 'wearable';
  }

  aboutToAppear(): void {
    const ctx: Context = getContext(this) as Context;
    this.loadAdaptiveTabBackgrounds(ctx);
    this.initPrivacyConsentState();
    this.tryInitDataAfterConsent(ctx);
  }

  private initPrivacyConsentState(): void {
    if (!this.isWearableDevice()) {
      this.showPrivacyConsentDialog = false;
      return;
    }
    PersistentStorage.persistProp(this.watchPrivacyConsentKey, '');
    const savedVersion: string | undefined = AppStorage.get<string>(this.watchPrivacyConsentKey);
    this.showPrivacyConsentDialog = savedVersion !== this.privacyPolicyVersion;
  }

  private hasPrivacyConsent(): boolean {
    if (!this.isWearableDevice()) {
      return true;
    }
    const savedVersion: string | undefined = AppStorage.get<string>(this.watchPrivacyConsentKey);
    return savedVersion === this.privacyPolicyVersion;
  }

  private agreePrivacyPolicy(): void {
    if (this.isWearableDevice()) {
      AppStorage.setOrCreate<string>(this.watchPrivacyConsentKey, this.privacyPolicyVersion);
    }
    this.showPrivacyConsentDialog = false;
    const ctx: Context = getContext(this) as Context;
    this.tryInitDataAfterConsent(ctx);
  }

  private rejectPrivacyPolicy(): void {
    this.terminateApp();
  }

  private openPrivacyPolicyPage(): void {
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: this.privacyPolicyUrl
    };
    ctx.startAbility(want).catch(() => {
      // 兜底：若系统浏览器拉起失败，仍可在应用内加载同一份在线隐私协议
      router.pushUrl({ url: 'pages/PrivacyPolicyPage', params: { policyUrl: this.privacyPolicyUrl } });
    });
  }

  private tryInitDataAfterConsent(ctx: Context): void {
    if (!this.hasPrivacyConsent() || this.hasInitializedData) {
      return;
    }
    this.hasInitializedData = true;
    DatabaseHelper.getInstance().initDB(ctx).then(() => {
      this.onDBReady(ctx);
    }).catch(() => {
      // initDB部分失败（如分布式表设置失败），但本地DB可能已就绪
      this.onDBReady(ctx);
    });
  }

  private onDBReady(ctx: Context): void {
    // DB就绪后通知所有视图加载数据
    this.refreshKey = this.refreshKey + 1;
    // 监听远端设备数据变更，自动刷新UI
    DatabaseHelper.getInstance().setOnRemoteChangeCallback(() => {
      this.refreshKey = this.refreshKey + 1;
    });
    // 异步初始化内置条码库（不阻塞UI）
    BarcodeService.getInstance().initBuiltinLibrary(ctx);
  }

  onPageShow(): void {
    if (!this.hasPrivacyConsent()) {
      return;
    }
    if (DatabaseHelper.getInstance().getStore() !== null) {
      this.refreshKey = this.refreshKey + 1;
    }
  }

  private onWatchListOpenChanged(): void {
    if (this.prevWatchListOpen && !this.watchListOpen) {
      this.lastWatchListClosedAt = Date.now();
    }
    this.prevWatchListOpen = this.watchListOpen;
  }

  onBackPress(): boolean {
    if (this.showPrivacyConsentDialog) {
      return true;
    }
    if (this.currentDeviceType === 'wearable' && this.currentIndex === 0) {
      if (this.watchListOpen) {
        this.watchListOpen = false;
        return true;
      }
      // 防止同一次侧滑手势导致“返回总览后又退出应用”的连触发
      if (Date.now() - this.lastWatchListClosedAt < 450) {
        return true;
      }
    }
    return false;
  }

  private terminateApp(): void {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      ctx.terminateSelf();
    } catch (e) {
      // ignore
    }
  }

  build() {
    Stack() {
      if (this.currentDeviceType === 'wearable') {
        this.buildWatchLayout()
      } else if (this.currentDeviceType === 'tv') {
        this.buildTvLayout()
      } else {
        // phone / tablet / 2in1 均使用全功能布局
        this.buildPhoneLayout()
      }

      if (this.showPrivacyConsentDialog) {
        this.buildPrivacyConsentDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  // 手机/平板布局
  @Builder
  buildPhoneLayout() {
    Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
      TabContent() {
        InventoryView({ refreshKey: this.refreshKey })
      }
      .tabBar(this.phoneTabBuilder('库存', 0, 'icon_inventory.svg'))

      TabContent() {
        HealthView({ refreshKey: this.refreshKey })
      }
      .tabBar(this.phoneTabBuilder('健康', 1, 'icon_health.svg'))

      TabContent() {
        MineView({ refreshKey: this.refreshKey })
      }
      .tabBar(this.phoneTabBuilder('我的', 2, 'icon_dict.svg'))
    }
    .scrollable(false)
    .barHeight(60)
    .barBackgroundColor($r('app.color.tab_bar_background'))
    .animation({ duration: 260, curve: Curve.EaseInOut })
    .onChange((index: number) => {
      this.currentIndex = index;
    })
  }

  // 手表布局 - 仅库存+健康两页，Swiper滑动切换
  @Builder
  buildWatchLayout() {
    Stack({ alignContent: Alignment.Top }) {
      Swiper() {
        WatchInventoryView({ refreshKey: this.refreshKey, listOpen: $watchListOpen })
        WatchHealthView({ refreshKey: this.refreshKey })
      }
      .indicator(false)
      .loop(false)
      .disableSwipe(this.watchListOpen)
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
        this.currentIndex = index;
      })

      // 指示点 - 仅总览时显示，列表展开或隐私弹窗时隐藏
      if (!this.watchListOpen && !this.showPrivacyConsentDialog) {
        Row({ space: 6 }) {
          Circle().width(5).height(5)
            .fill(this.currentIndex === 0 ? $r('app.color.accent_link') : $r('app.color.text_disabled'))
          Circle().width(5).height(5)
            .fill(this.currentIndex === 1 ? $r('app.color.accent_link') : $r('app.color.text_disabled'))
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor($r('app.color.page_background'))
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        const startTouch: TouchObject | undefined = event.touches[0];
        if (startTouch !== undefined) {
          this.watchTouchStartX = startTouch.x;
          this.watchTouchStartY = startTouch.y;
        }
        return;
      }
      if (event.type === TouchType.Up) {
        const changedTouch: TouchObject | undefined = event.changedTouches[0];
        if (changedTouch === undefined) {
          return;
        }
        const dx: number = changedTouch.x - this.watchTouchStartX;
        const dy: number = changedTouch.y - this.watchTouchStartY;
        const isExitSwipe: boolean = dx > 70 && Math.abs(dx) > Math.abs(dy);
        const justClosedList: boolean = Date.now() - this.lastWatchListClosedAt < 450;
        // 仅在库存总览页允许侧滑退出；列表刚收起时忽略同次手势，避免连退
        if (isExitSwipe && this.currentIndex === 0 && !this.watchListOpen && !justClosedList && !this.showPrivacyConsentDialog) {
          this.terminateApp();
        }
      }
    })
  }

  @Builder
  buildPrivacyConsentDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay_background'))

      if (this.currentDeviceType === 'wearable') {
        Column({ space: 6 }) {
          Text($r('app.string.privacy_dialog_title'))
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textAlign(TextAlign.Center)
            .width('100%')

          Scroll() {
            Column({ space: 5 }) {
              Text($r('app.string.privacy_dialog_content_watch'))
                .fontSize(10)
                .fontColor($r('app.color.text_secondary'))
                .lineHeight(14)
                .textAlign(TextAlign.Center)
                .width('100%')

              Text($r('app.string.privacy_dialog_view_full'))
                .fontSize(11)
                .fontColor($r('app.color.accent_link'))
                .textAlign(TextAlign.Center)
                .width('100%')
                .onClick(() => {
                  this.openPrivacyPolicyPage();
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)

          Row({ space: 8 }) {
            Button($r('app.string.privacy_dialog_reject_watch'))
              .layoutWeight(1)
              .height(34)
              .fontSize(10)
              .fontColor($r('app.color.button_danger_text'))
              .backgroundColor($r('app.color.button_danger_bg'))
              .borderRadius(18)
              .onClick(() => {
                this.rejectPrivacyPolicy();
              })

            Button($r('app.string.privacy_dialog_accept_watch'))
              .layoutWeight(1)
              .height(34)
              .fontSize(10)
              .fontColor($r('app.color.button_secondary_text'))
              .backgroundColor($r('app.color.button_secondary_bg'))
              .borderRadius(18)
              .onClick(() => {
                this.agreePrivacyPolicy();
              })
          }
          .width('100%')
        }
        .height('60%')
        .width('66%')
        .padding({ left: 10, right: 10, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column({ space: 12 }) {
          Text($r('app.string.privacy_dialog_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          Text($r('app.string.privacy_dialog_content'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(20)
            .width('100%')

          Text($r('app.string.privacy_dialog_view_full'))
            .fontSize(13)
            .fontColor($r('app.color.accent_link'))
            .width('100%')
            .onClick(() => {
              this.openPrivacyPolicyPage();
            })

          Text($r('app.string.privacy_dialog_agreement_tip'))
            .fontSize(12)
            .fontColor($r('app.color.text_hint'))
            .width('100%')

          Row({ space: 12 }) {
            Button($r('app.string.privacy_dialog_reject'))
              .layoutWeight(1)
              .height(44)
              .fontSize(14)
              .fontColor($r('app.color.button_danger_text'))
              .backgroundColor($r('app.color.button_danger_bg'))
              .borderRadius(10)
              .onClick(() => {
                this.rejectPrivacyPolicy();
              })

            Button($r('app.string.privacy_dialog_accept'))
              .layoutWeight(1)
              .height(44)
              .fontSize(14)
              .fontColor($r('app.color.button_primary_text'))
              .backgroundColor($r('app.color.button_primary_bg'))
              .borderRadius(10)
              .onClick(() => {
                this.agreePrivacyPolicy();
              })
          }
          .width('100%')
        }
        .width('90%')
        .constraintSize({ maxWidth: 560 })
        .padding(16)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .height('100%')
  }

  // 智慧屏布局 - 大Tab
  @Builder
  buildTvLayout() {
    Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
      TabContent() {
        TvInventoryView({ refreshKey: this.refreshKey })
      }
      .tabBar(this.tvTabBuilder('库存', 0, 'icon_inventory.svg'))

      TabContent() {
        TvHealthView({ refreshKey: this.refreshKey })
      }
      .tabBar(this.tvTabBuilder('健康', 1, 'icon_health.svg'))

      TabContent() {
        TvMineView({ refreshKey: this.refreshKey })
      }
      .tabBar(this.tvTabBuilder('字典', 2, 'icon_dict.svg'))
    }
    .scrollable(false)
    .barHeight(80)
    .barBackgroundColor($r('app.color.tab_bar_background'))
    .animation({ duration: 260, curve: Curve.EaseInOut })
    .onChange((index: number) => {
      this.currentIndex = index;
    })
  }

  @Builder
  phoneTabBuilder(title: string, targetIndex: number, iconRaw: string) {
    Column({ space: 4 }) {
      Image($rawfile(iconRaw))
        .width(20)
        .height(20)
        .padding(7)
        .width(34)
        .height(34)
        .backgroundColor(this.currentIndex === targetIndex ? this.getTabIconBg(iconRaw) : Color.Transparent)
        .borderRadius(17)
      Text(title)
        .fontSize(11)
        .fontWeight(this.currentIndex === targetIndex ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentIndex === targetIndex ? $r('app.color.accent_link') : $r('app.color.tab_inactive'))
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => {
      this.currentIndex = targetIndex;
      this.tabsController.changeIndex(targetIndex);
    })
  }

  @Builder
  watchTabBuilder(title: string, targetIndex: number) {
    Text(title)
      .fontSize(14)
      .fontWeight(this.currentIndex === targetIndex ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.currentIndex === targetIndex ? $r('app.color.accent_link') : $r('app.color.tab_inactive'))
      .textAlign(TextAlign.Center)
      .width('100%').height('100%')
      .onClick(() => {
        this.currentIndex = targetIndex;
        this.tabsController.changeIndex(targetIndex);
      })
  }

  @Builder
  tvTabBuilder(title: string, targetIndex: number, iconRaw: string) {
    Column({ space: 6 }) {
      Image($rawfile(iconRaw))
        .width(30)
        .height(30)
        .padding(8)
        .width(46)
        .height(46)
        .backgroundColor(this.currentIndex === targetIndex ? this.getTabIconBg(iconRaw) : Color.Transparent)
        .borderRadius(23)
      Text(title)
        .fontSize(18)
        .fontWeight(this.currentIndex === targetIndex ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentIndex === targetIndex ? $r('app.color.accent_link') : $r('app.color.tab_inactive'))
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => {
      this.currentIndex = targetIndex;
      this.tabsController.changeIndex(targetIndex);
    })
  }
}
