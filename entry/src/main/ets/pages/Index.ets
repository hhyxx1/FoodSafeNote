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
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { AdaptiveColorHelper } from '../common/AdaptiveColorHelper';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @State refreshKey: number = 0;
  @State watchListOpen: boolean = false;
  @State watchTouchStartX: number = 0;
  @State watchTouchStartY: number = 0;
  @StorageLink('appColorMode') appColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  private tabsController: TabsController = new TabsController();
  private currentDeviceType: string = deviceInfo.deviceType;
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

  aboutToAppear(): void {
    const ctx: Context = getContext(this) as Context;
    this.loadAdaptiveTabBackgrounds(ctx);

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
    if (DatabaseHelper.getInstance().getStore() !== null) {
      this.refreshKey = this.refreshKey + 1;
    }
  }

  private exitWatchApp(): void {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      ctx.terminateSelf();
    } catch (e) {
      // ignore
    }
  }

  build() {
    if (this.currentDeviceType === 'wearable') {
      this.buildWatchLayout()
    } else if (this.currentDeviceType === 'tv') {
      this.buildTvLayout()
    } else {
      // phone / tablet / 2in1 均使用全功能布局
      this.buildPhoneLayout()
    }
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
        WatchInventoryView({ refreshKey: this.refreshKey, listOpen: this.watchListOpen })
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

      // 指示点 - 仅总览时显示，列表展开时隐藏
      if (!this.watchListOpen) {
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
    .backgroundColor($r('app.color.page_background'))
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.watchTouchStartX = event.touches[0].x;
        this.watchTouchStartY = event.touches[0].y;
        return;
      }
      if (event.type === TouchType.Up) {
        const dx: number = event.changedTouches[0].x - this.watchTouchStartX;
        const dy: number = event.changedTouches[0].y - this.watchTouchStartY;
        // 手表首页右滑退出应用（仅在库存总览页生效）
        if (dx > 70 && Math.abs(dx) > Math.abs(dy) && this.currentIndex === 0 && !this.watchListOpen) {
          this.exitWatchApp();
        }
      }
    })
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
