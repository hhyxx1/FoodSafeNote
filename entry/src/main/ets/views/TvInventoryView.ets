import { localizedFoodLabel } from '../common/Constants';
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

  private getExpiryText(item: FoodItem): ResourceStr {
    if (item.expiryDate <= 0) return $r('app.string.ui_expiry_date_not_set');
    const days: number = item.getRemainingDays();
    if (days < 0) return $r('app.string.ui_expired_d_days_ago', Math.abs(days));
    if (days === 0) return $r('app.string.watch_expire_today');
    return $r('app.string.ui_expires_in_d_days', days);
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text($r('app.string.ui_food_inventory'))
          .fontSize(27)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text($r('app.string.inventory_count', this.foodItems.length))
          .fontSize(21)
          .fontColor($r('app.color.text_hint'))
      }
      .width('100%')
      .padding({ left: 56, right: 56, top: 22, bottom: 22 })

      // 筛选栏 - 可聚焦按钮，遥控器左右切换
      Row({ space: 20 }) {
        this.buildTvFilter($r('app.string.ui_all'), 'all', 0)
        this.buildTvFilter($r('app.string.status_normal'), 'normal', 1)
        this.buildTvFilter($r('app.string.status_near_expiry'), 'nearExpiry', 2)
        this.buildTvFilter($r('app.string.watch_expired_prefix'), 'expired', 3)
      }
      .width('100%')
      .padding({ left: 56, right: 56, bottom: 22 })

      // 3列网格 - 可聚焦卡片
      if (this.filteredItems.length === 0) {
        Column() {
          Text($r('app.string.ui_no_food_items')).fontSize(24).fontColor($r('app.color.text_hint'))
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.filteredItems, (item: FoodItem) => {
            GridItem() {
              Column({ space: 8 }) {
                Row() {
                  Row().width(12).height(12).borderRadius(6).backgroundColor(item.getStatusColor())
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
                    Text(localizedFoodLabel(item.category)).fontSize(18).fontColor($r('app.color.text_secondary'))
                  }
                  Text(getStorageTypeName(item.storageType)).fontSize(18).fontColor($r('app.color.text_secondary'))
                }

                Text(this.getExpiryText(item))
                  .fontSize(18)
                  .fontColor(item.getStatusColor())

                if (item.calories > 0) {
                  Text($r('app.string.ui_this_item_s_kcal', item.calories.toFixed(0)))
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
              this.getUIContext().getRouter().pushUrl({ url: 'pages/TvFoodDetailPage', params: params });
            })
            .onKeyEvent((event: KeyEvent) => {
              if (event.type === KeyType.Up && event.keyCode === 2054) {
                // 确认键(Enter/OK)
                const params: TvFoodParams = { foodId: item.id };
                this.getUIContext().getRouter().pushUrl({ url: 'pages/TvFoodDetailPage', params: params });
              }
            })
          }, (item: FoodItem) => item.id.toString())
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(20)
        .rowsGap(20)
        .layoutWeight(1)
        .padding({ left: 56, right: 56, bottom: 22 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .animation({ duration: 260, curve: Curve.EaseInOut })
  }

  @Builder
  buildTvFilter(label: ResourceStr, type: string, tabIdx: number) {
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
