import { router } from '@kit.ArkUI';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { FoodItem } from '../model/DataModels';
import { getStorageTypeName } from '../common/Constants';

interface TvFoodParams {
  foodId: number;
}

@Component
export struct TvInventoryView {
  @Prop @Watch('onRefresh') refreshKey: number = 0;
  @State foodItems: FoodItem[] = [];
  @State filteredItems: FoodItem[] = [];
  @State filterType: string = 'all';
  @State focusedCardId: number = -1;

  aboutToAppear(): void {
    if (DatabaseHelper.getInstance().getStore() !== null) {
      this.loadData();
    }
  }

  onRefresh(): void {
    this.loadData();
  }

  private loadData(): void {
    DatabaseHelper.getInstance().getActiveFoodItems().then((items: FoodItem[]) => {
      this.foodItems = items;
      this.applyFilter();
    });
  }

  private applyFilter(): void {
    if (this.filterType === 'all') {
      this.filteredItems = this.foodItems;
    } else if (this.filterType === 'normal') {
      const result: FoodItem[] = [];
      for (let i = 0; i < this.foodItems.length; i++) {
        if (!this.foodItems[i].isExpired() && !this.foodItems[i].isNearExpiry()) result.push(this.foodItems[i]);
      }
      this.filteredItems = result;
    } else if (this.filterType === 'nearExpiry') {
      const result: FoodItem[] = [];
      for (let i = 0; i < this.foodItems.length; i++) {
        if (this.foodItems[i].isNearExpiry() && !this.foodItems[i].isExpired()) result.push(this.foodItems[i]);
      }
      this.filteredItems = result;
    } else if (this.filterType === 'expired') {
      const result: FoodItem[] = [];
      for (let i = 0; i < this.foodItems.length; i++) {
        if (this.foodItems[i].isExpired()) result.push(this.foodItems[i]);
      }
      this.filteredItems = result;
    }
  }

  private getExpiryText(item: FoodItem): string {
    if (item.expiryDate <= 0) return '未设置保质期';
    const days: number = item.getRemainingDays();
    if (days < 0) return '已过期 ' + Math.abs(days) + ' 天';
    if (days === 0) return '今天到期';
    return '剩余 ' + days + ' 天';
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('食品库存')
          .fontSize(27)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.foodItems.length + ' 件')
          .fontSize(21)
          .fontColor($r('app.color.text_hint'))
      }
      .width('100%')
      .padding({ left: 40, right: 40, top: 24, bottom: 16 })

      // 筛选栏 - 可聚焦按钮，遥控器左右切换
      Row({ space: 20 }) {
        this.buildTvFilter('全部', 'all', 0)
        this.buildTvFilter('正常', 'normal', 1)
        this.buildTvFilter('临期', 'nearExpiry', 2)
        this.buildTvFilter('过期', 'expired', 3)
      }
      .width('100%')
      .padding({ left: 40, right: 40, bottom: 20 })

      // 3列网格 - 可聚焦卡片
      if (this.filteredItems.length === 0) {
        Column() {
          Text('暂无食品').fontSize(24).fontColor($r('app.color.text_hint'))
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.filteredItems, (item: FoodItem) => {
            GridItem() {
              Column({ space: 8 }) {
                Row() {
                  Circle().width(12).height(12).fill(item.getStatusColor())
                  Text(item.getStatusText())
                    .fontSize(18)
                    .fontColor(item.getStatusColor())
                    .padding({ left: 8 })
                }

                Text(item.name)
                  .fontSize(24)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(item.isExpired() ? $r('app.color.text_hint') : $r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')

                Row({ space: 16 }) {
                  if (item.category.length > 0) {
                    Text(item.category).fontSize(18).fontColor($r('app.color.text_secondary'))
                  }
                  Text(getStorageTypeName(item.storageType)).fontSize(18).fontColor($r('app.color.text_secondary'))
                }

                Text(this.getExpiryText(item))
                  .fontSize(18)
                  .fontColor(item.getStatusColor())

                if (item.calories > 0) {
                  Text(item.calories.toFixed(0) + ' kcal')
                    .fontSize(18)
                    .fontColor('#FF6B00')
                }
              }
              .width('100%')
              .padding(20)
              .backgroundColor(this.focusedCardId === item.id ? '#E0EFFF' : (item.isExpired() ? '#FAFAFA' : $r('app.color.card_background')))
              .borderRadius(16)
              .border({
                width: this.focusedCardId === item.id ? 3 : 0,
                color: '#007DFF'
              })
              .opacity(item.isExpired() ? 0.7 : 1.0)
              .alignItems(HorizontalAlign.Start)
            }
            .focusable(true)
            .onFocus(() => {
              this.focusedCardId = item.id;
            })
            .onBlur(() => {
              if (this.focusedCardId === item.id) {
                this.focusedCardId = -1;
              }
            })
            .onClick(() => {
              const params: TvFoodParams = { foodId: item.id };
              router.pushUrl({ url: 'pages/TvFoodDetailPage', params: params });
            })
            .onKeyEvent((event: KeyEvent) => {
              if (event.type === KeyType.Up && event.keyCode === 2054) {
                // 确认键(Enter/OK)
                const params: TvFoodParams = { foodId: item.id };
                router.pushUrl({ url: 'pages/TvFoodDetailPage', params: params });
              }
            })
          }, (item: FoodItem) => item.id.toString())
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(20)
        .rowsGap(20)
        .layoutWeight(1)
        .padding({ left: 40, right: 40, bottom: 30 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  buildTvFilter(label: string, type: string, tabIdx: number) {
    Text(label)
      .fontSize(21)
      .fontColor(this.filterType === type ? Color.White : $r('app.color.text_secondary'))
      .textAlign(TextAlign.Center)
      .height(60)
      .padding({ left: 30, right: 30 })
      .backgroundColor(this.filterType === type ? '#007DFF' : $r('app.color.chip_background'))
      .borderRadius(12)
      .focusable(true)
      .tabIndex(tabIdx)
      .border({
        width: 0,
        color: Color.Transparent
      })
      .onFocus(() => {
        this.filterType = type;
        this.applyFilter();
      })
      .onClick(() => {
        this.filterType = type;
        this.applyFilter();
      })
  }
}
