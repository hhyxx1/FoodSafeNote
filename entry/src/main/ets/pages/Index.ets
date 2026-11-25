import { FoodButtonStyle } from '../common/FoodInterface';
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
import { window } from '@kit.ArkUI';
import { HdsNavigation, HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { AdaptiveColorHelper } from '../common/AdaptiveColorHelper';
import { AppNavigation } from '../common/AppNavigation';

interface PrivacyPolicyParam {
  policyUrl: string;
}

interface PhoneEdgeTouch {
  id: number;
  x: number;
  y: number;
  tab: number;
}

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @State phoneHighlightIndex: number = 0;
  @State phoneTabWidths: number[] = [0, 0, 0];
  @State phoneEdgeOffset: number = 0;
  private phoneEdgeTouch: PhoneEdgeTouch | undefined = undefined;
  @State refreshKey: number = 0;
  @State @Watch('onWatchListOpenChanged') watchListOpen: boolean = false;
  @State showPrivacyConsentDialog: boolean = false;
  private watchTouchStartX: number = 0;
  private watchTouchStartY: number = 0;
  @StorageLink('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  private tvTabsController: TabsController = new TabsController();
  private pathStack: NavPathStack = new NavPathStack();
  @StorageProp('dataChangeTick') @Watch('onDataChangeTick') dataChangeTick: number = 0;
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
  private readonly phoneTabBarHeight: number = 60;
  private readonly phoneTabSlideDuration: number = 220;
  // 手势条（navigation indicator）高度，单位 vp；0 表示未知（胶囊退回默认间距）
  @State naviIndicatorHeight: number = 0;

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
    const ctx: Context = this.getUIContext().getHostContext() as Context;
    AppNavigation.setStack(this.pathStack);
    if (this.currentDeviceType === 'tv') {
      this.loadAdaptiveTabBackgrounds(ctx);
    }
    this.initNaviIndicatorHeight(ctx);
    this.initPrivacyConsentState();
    this.tryInitDataAfterConsent(ctx);
  }

  // 跟随官方示例：取手势条高度与状态栏高度，供胶囊间距与二级页面标题栏避让使用
  private initNaviIndicatorHeight(ctx: Context): void {
    try {
      window.getLastWindow(ctx).then((win: window.Window) => {
        const area: window.AvoidArea =
          win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        const h: number = this.getUIContext().px2vp(area.bottomRect.height);
        this.naviIndicatorHeight = h;
        AppStorage.setOrCreate('naviIndicatorHeight', h);
        const statusBarArea: window.AvoidArea =
          win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const sh: number = this.getUIContext().px2vp(statusBarArea.topRect.height);
        AppStorage.setOrCreate('statusBarHeight', sh);
      }).catch(() => {
        // 获取失败时保持 0，胶囊退回默认间距
      });
    } catch (err) {
      // 获取失败时保持 0，胶囊退回默认间距
    }
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
    const ctx: Context = this.getUIContext().getHostContext() as Context;
    this.tryInitDataAfterConsent(ctx);
  }

  private rejectPrivacyPolicy(): void {
    this.terminateApp();
  }

  private openPrivacyPolicyPage(): void {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: this.privacyPolicyUrl
    };
    ctx.startAbility(want).catch(() => {
      // 兜底：若系统浏览器拉起失败，仍可在应用内加载同一份在线隐私协议
      const navParam: PrivacyPolicyParam = { policyUrl: this.privacyPolicyUrl };
      AppNavigation.push('PrivacyPolicyPage', navParam);
    });
  }

  private tryInitDataAfterConsent(ctx: Context): void {
    if (!this.hasPrivacyConsent() || this.hasInitializedData) {
      return;
    }
    this.hasInitializedData = true;
    DatabaseHelper.getInstance().initDB(ctx).then(() => {
      this.onDBReady(ctx);
    }).catch((error: Error) => {
      this.hasInitializedData = false;
      console.error('Could not initialize food data: ' + error.message);
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.food_data_open_failed') });
    });
  }

  private onDBReady(ctx: Context): void {
    // DB就绪后通知所有视图加载数据
    this.refreshKey = this.refreshKey + 1;
    const database = DatabaseHelper.getInstance();
    const store = database.getStore();
    if (store !== null) void database.deviceSync.initialize(store, ctx);
    // 异步初始化内置条码库（不阻塞UI）
    BarcodeService.getInstance().initBuiltinLibrary(ctx);
  }

  // 二级页面返回（含系统侧滑）后刷新数据，等价于原 onPageShow 的刷新逻辑
  private onDataChangeTick(): void {
    this.refreshKey = this.refreshKey + 1;
  }

  onPageShow(): void {
    if (!this.hasPrivacyConsent()) {
      return;
    }
    if (DatabaseHelper.getInstance().getStore() !== null) {
      this.refreshKey = this.refreshKey + 1;
    } else {
      const context = this.getUIContext().getHostContext();
      if (context !== undefined) this.tryInitDataAfterConsent(context);
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
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
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
        // phone / tablet / 2in1 均使用全功能布局，HdsNavigation 承载二级页面路由
        HdsNavigation(this.pathStack) {
          this.buildPhoneLayout()
        }
        .hideTitleBar(true)
        .mode(NavigationMode.Stack)
        // 关闭 Navigation 底部自带的拖拽指示条（dragBar），避免遮挡内容
        .enableDragBar(false)
        // 跟随官方示例：内容延伸到底部手势条下方，消除手势条避让区露出的窗口底色（深色下为纯黑条）
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
        // 统一底部导航条避让区域背景，避免与内容区出现色差
        .backgroundColor($r('app.color.page_background'))
      }

      if (this.showPrivacyConsentDialog) {
        this.buildPrivacyConsentDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  private getPhoneBarBottomMargin(): number {
    return Math.max(this.naviIndicatorHeight, 16);
  }

  private getPhoneContentBottomInset(): number {
    return this.phoneTabBarHeight + this.getPhoneBarBottomMargin() + 12;
  }

  private finishPhoneEdgeGesture(): void {
    this.phoneEdgeTouch = undefined;
    if (this.phoneEdgeOffset === 0) return;
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.phoneEdgeOffset = 0;
    });
  }

  private followPhoneEdgeGesture(event: TouchEvent): void {
    const touch = event.touches[0];
    if (event.type === TouchType.Up || event.type === TouchType.Cancel || event.touches.length !== 1 ||
      touch === undefined) {
      this.finishPhoneEdgeGesture();
      return;
    }
    if (event.type === TouchType.Down) {
      this.phoneEdgeTouch = this.currentIndex === 0 || this.currentIndex === 2
        ? { id: touch.id, x: touch.windowX, y: touch.windowY, tab: this.currentIndex } : undefined;
      return;
    }
    const start = this.phoneEdgeTouch;
    if (event.type !== TouchType.Move || start === undefined || start.tab !== this.currentIndex ||
      start.id !== touch.id) return;

    const dx = touch.windowX - start.x;
    const dy = touch.windowY - start.y;
    const outward = start.tab === 0 ? dx : -dx;
    if (Math.max(Math.abs(dx), Math.abs(dy)) <= 8) return;
    if (outward <= 0 || Math.abs(dx) < Math.abs(dy) * 1.3) {
      this.finishPhoneEdgeGesture();
      return;
    }
    const distance = Math.max(0, outward - 8);
    const offset = 28 * distance / (distance + 45);
    this.phoneEdgeOffset = start.tab === 0 ? offset : -offset;
  }

  // 手机/平板布局 - HdsTabs 悬浮沉浸光感导航
  @Builder
  buildPhoneLayout() {
    HdsTabs({ barPosition: BarPosition.End }) {
      TabContent() {
        Column() {
          InventoryView({ refreshKey: this.refreshKey, tabBarInset: this.getPhoneContentBottomInset() })
        }
        .width('100%')
        .height('100%')
        .translate({ x: this.currentIndex === 0 ? this.phoneEdgeOffset : 0 })
      }
      .tabBar(this.phoneTabBuilder($r('app.string.ui_inventory'), 0,
        $r('sys.symbol.archivebox'), $r('sys.symbol.archivebox_fill')))

      TabContent() {
        Column() {
          HealthView({ refreshKey: this.refreshKey, tabBarInset: this.getPhoneContentBottomInset() })
        }
        .width('100%')
        .height('100%')
      }
      .tabBar(this.phoneTabBuilder($r('app.string.ui_health'), 1,
        $r('sys.symbol.heart'), $r('sys.symbol.heart_fill')))

      TabContent() {
        Column() {
          MineView({ refreshKey: this.refreshKey, tabBarInset: this.getPhoneContentBottomInset() })
        }
        .width('100%')
        .height('100%')
        .translate({ x: this.currentIndex === 2 ? this.phoneEdgeOffset : 0 })
      }
      .tabBar(this.phoneTabBuilder($r('app.string.ui_profile'), 2,
        $r('sys.symbol.person'), $r('sys.symbol.person_fill')))
    }
    .scrollable(true)
    .vertical(false)
    .barOverlap(true)
    .barHeight(this.phoneTabBarHeight)
    .animationDuration(this.phoneTabSlideDuration)
    .barFloatingStyle({
      // 手势条存在时胶囊上抬到手势条正上方（跟随官方示例），否则用系统默认间距
      barBottomMargin: this.getPhoneBarBottomMargin(),
      adaptToHandedness: true,
      // HdsTabs 默认底部渐变遮罩在深色下发黑；改为渐变到页面底色，与内容无缝衔接
      gradientMask: {
        maskColor: $r('app.color.page_background')
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    })
    .onAnimationStart((_index: number, targetIndex: number) => {
      this.finishPhoneEdgeGesture();
      this.phoneHighlightIndex = targetIndex;
    })
    .onChange((index: number) => {
      this.finishPhoneEdgeGesture();
      this.currentIndex = index;
      this.phoneHighlightIndex = index;
    })
    .onTouch((event: TouchEvent) => { this.followPhoneEdgeGesture(event); })
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
      .effectMode(EdgeEffect.Spring)
      .disableSwipe(this.watchListOpen)
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
        this.currentIndex = index;
      })

      // 指示点 - 仅总览时显示，列表展开或隐私弹窗时隐藏
      if (!this.watchListOpen && !this.showPrivacyConsentDialog) {
        Row({ space: 6 }) {
          Row().width(5).height(5).borderRadius(2.5)
            .backgroundColor(this.currentIndex === 0 ? $r('app.color.accent_link') : $r('app.color.text_disabled'))
          Row().width(5).height(5).borderRadius(2.5)
            .backgroundColor(this.currentIndex === 1 ? $r('app.color.accent_link') : $r('app.color.text_disabled'))
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
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)

          Row({ space: 8 }) {
            Button($r('app.string.privacy_dialog_reject_watch'))
              .layoutWeight(1)
              .height(34)
              .fontSize(10)
              .fontColor($r('app.color.button_danger_text'))
              .backgroundColor($r('app.color.button_danger_bg_glass'))
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .borderRadius(18)
              .onClick(() => {
                this.rejectPrivacyPolicy();
              })

            Button($r('app.string.privacy_dialog_accept_watch'))
              .layoutWeight(1)
              .height(34)
              .fontSize(10)
              .fontColor($r('app.color.button_secondary_text'))
              .backgroundColor($r('app.color.button_secondary_bg_glass'))
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
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
              .attributeModifier(FoodButtonStyle.neutral)
              .layoutWeight(1)
              .onClick(() => {
                this.rejectPrivacyPolicy();
              })

            Button($r('app.string.privacy_dialog_accept'))
              .attributeModifier(FoodButtonStyle.primary)
              .layoutWeight(1)
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
    Tabs({ barPosition: BarPosition.End, controller: this.tvTabsController }) {
      TabContent() {
        TvInventoryView({ refreshKey: this.refreshKey })
      }
      .tabBar(this.tvTabBuilder($r('app.string.ui_inventory'), 0, 'icon_inventory.svg'))

      TabContent() {
        TvHealthView({ refreshKey: this.refreshKey })
      }
      .tabBar(this.tvTabBuilder($r('app.string.ui_health'), 1, 'icon_health.svg'))

      TabContent() {
        TvMineView({ refreshKey: this.refreshKey })
      }
      .tabBar(this.tvTabBuilder($r('app.string.ui_dictionary'), 2, 'icon_dict.svg'))
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
  phoneTabBuilder(title: ResourceStr, targetIndex: number, outline: Resource, filled: Resource) {
    Column({ space: 2 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(outline)
          .fontSize(22)
          .fontColor([$r('app.color.tab_inactive')])

        // 绿色实心图标只在滑动胶囊内部可见，反向平移让图标固定在页签中心。
        Row() {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph(filled)
              .fontSize(22)
              .fontColor([$r('app.color.accent_link')])
              .translate({ x: (targetIndex - this.phoneHighlightIndex) * this.phoneTabWidths[targetIndex] })
              .animation({ duration: this.phoneTabSlideDuration, curve: Curve.EaseOut })
          }
          .width(44)
          .height(28)
          .backgroundColor($r('app.color.button_secondary_bg'))
          .borderRadius(14)
          .clip(true)
        }
        .width('100%')
        .height(28)
        .justifyContent(FlexAlign.Center)
        .translate({ x: ((this.phoneHighlightIndex - targetIndex) * 100).toString() + '%' })
        .animation({ duration: this.phoneTabSlideDuration, curve: Curve.EaseOut })
        .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height(28)
      .clip(true)
      .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions) => {
        this.phoneTabWidths[targetIndex] = Number(newSize.width);
      })

      Text(title)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.phoneHighlightIndex === targetIndex ? $r('app.color.accent_link') : $r('app.color.tab_inactive'))
        .animation({ duration: this.phoneTabSlideDuration, curve: Curve.EaseOut })
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .accessibilitySelected(this.currentIndex === targetIndex)
  }

  @Builder
  tvTabBuilder(title: ResourceStr, targetIndex: number, iconRaw: string) {
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
      this.tvTabsController.changeIndex(targetIndex);
    })
  }
}
