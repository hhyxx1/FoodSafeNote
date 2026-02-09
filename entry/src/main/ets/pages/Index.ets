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
import { pasteboard } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { promptAction, router } from '@kit.ArkUI';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @State refreshKey: number = 0;
  @State watchListOpen: boolean = false;
  private tabsController: TabsController = new TabsController();
  private currentDeviceType: string = deviceInfo.deviceType;

  aboutToAppear(): void {
    const ctx = getContext(this);
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
      // 剪贴板自动检测（仅手机/平板/2in1，且开关开启时）
      if (this.currentDeviceType !== 'wearable' && this.currentDeviceType !== 'tv') {
        this.checkClipboard();
      }
    }
  }

  private checkClipboard(): void {
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(getContext(this), { name: 'settings' });
      const enabled: boolean = store.getSync('clipboard_auto', false) as boolean;
      if (!enabled) return;
      const sysBoard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      sysBoard.getData().then((data: pasteboard.PasteData) => {
        if (data.getRecordCount() > 0) {
          const record: pasteboard.PasteDataRecord = data.getRecord(0);
          const text: string = record.plainText !== undefined ? record.plainText : '';
          if (text.length > 2 && text.length < 500) {
            // 检查是否包含食品相关关键词
            const hasKeyword: boolean = text.indexOf('买') >= 0 || text.indexOf('购') >= 0 ||
              text.indexOf('入库') >= 0 || text.indexOf('采购') >= 0 ||
              text.indexOf('清单') >= 0 || text.indexOf('食') >= 0;
            if (hasKeyword) {
              promptAction.showDialog({
                title: '检测到食品清单',
                message: '剪贴板内容可能包含食品信息，是否批量添加？',
                buttons: [
                  { text: '忽略', color: '#999999' },
                  { text: '去添加', color: '#007DFF' }
                ]
              }).then((result: promptAction.ShowDialogSuccessResponse) => {
                if (result.index === 1) {
                  router.pushUrl({ url: 'pages/ClipboardParsePage' });
                }
              });
            }
          }
        }
      });
    } catch (e) {
      // 剪贴板检测失败不影响使用
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
      .tabBar(this.phoneTabBuilder('库存', 0, '📦'))

      TabContent() {
        HealthView({ refreshKey: this.refreshKey })
      }
      .tabBar(this.phoneTabBuilder('健康', 1, '❤️'))

      TabContent() {
        MineView({ refreshKey: this.refreshKey })
      }
      .tabBar(this.phoneTabBuilder('我的', 2, '👤'))
    }
    .scrollable(false)
    .barHeight(60)
    .barBackgroundColor($r('app.color.tab_bar_background'))
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
            .fill(this.currentIndex === 0 ? '#007DFF' : '#CCCCCC')
          Circle().width(5).height(5)
            .fill(this.currentIndex === 1 ? '#007DFF' : '#CCCCCC')
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  // 智慧屏布局 - 大Tab
  @Builder
  buildTvLayout() {
    Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
      TabContent() {
        TvInventoryView({ refreshKey: this.refreshKey })
      }
      .tabBar(this.tvTabBuilder('库存', 0, '📦'))

      TabContent() {
        TvHealthView({ refreshKey: this.refreshKey })
      }
      .tabBar(this.tvTabBuilder('健康', 1, '❤️'))

      TabContent() {
        TvMineView({ refreshKey: this.refreshKey })
      }
      .tabBar(this.tvTabBuilder('字典', 2, '📖'))
    }
    .scrollable(false)
    .barHeight(80)
    .barBackgroundColor($r('app.color.tab_bar_background'))
    .onChange((index: number) => {
      this.currentIndex = index;
    })
  }

  @Builder
  phoneTabBuilder(title: string, targetIndex: number, icon: string) {
    Column({ space: 4 }) {
      Text(icon).fontSize(22)
      Text(title)
        .fontSize(11)
        .fontWeight(this.currentIndex === targetIndex ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentIndex === targetIndex ? '#007DFF' : $r('app.color.tab_inactive'))
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
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
      .fontColor(this.currentIndex === targetIndex ? '#007DFF' : $r('app.color.tab_inactive'))
      .textAlign(TextAlign.Center)
      .width('100%').height('100%')
      .onClick(() => {
        this.currentIndex = targetIndex;
        this.tabsController.changeIndex(targetIndex);
      })
  }

  @Builder
  tvTabBuilder(title: string, targetIndex: number, icon: string) {
    Column({ space: 6 }) {
      Text(icon).fontSize(30)
      Text(title)
        .fontSize(18)
        .fontWeight(this.currentIndex === targetIndex ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentIndex === targetIndex ? '#007DFF' : $r('app.color.tab_inactive'))
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentIndex = targetIndex;
      this.tabsController.changeIndex(targetIndex);
    })
  }
}
