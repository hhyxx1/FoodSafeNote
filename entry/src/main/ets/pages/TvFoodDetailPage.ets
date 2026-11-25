import { localizedFoodLabel } from '../common/Constants';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { FoodItem } from '../model/DataModels';
import { formatTimestamp, getStorageTypeName } from '../common/Constants';

interface TvFoodParams {
  foodId: number;
}

@Entry
@Component
struct TvFoodDetailPage {
  @State foodItem: FoodItem | null = null;
  @State isLoading: boolean = true;
  @State backFocused: boolean = false;
  private foodId: number = 0;

  aboutToAppear(): void {
    const params: TvFoodParams = this.getUIContext().getRouter().getParams() as TvFoodParams;
    if (params !== null && params !== undefined) {
      this.foodId = params.foodId;
      this.loadData();
    } else {
      this.isLoading = false;
    }
  }

  private loadData(): void {
    DatabaseHelper.getInstance().getFoodItemById(this.foodId).then((item: FoodItem | null) => {
      this.foodItem = item;
    }).finally(() => {
      this.isLoading = false;
    });
  }

  private getExpiryText(): ResourceStr {
    if (this.foodItem === null) return '';
    if (this.foodItem.expiryDate <= 0) return $r('app.string.ui_expiry_date_not_set');
    const days: number = this.foodItem.getRemainingDays();
    if (days < 0) return $r('app.string.ui_expired_d_days_ago', Math.abs(days));
    if (days === 0) return $r('app.string.watch_expire_today');
    return $r('app.string.ui_expires_in_d_days', days);
  }

  build() {
    Column() {
      // 顶部导航
      Row() {
        Button($r('app.string.ui_back'))
          .height(60)
          .fontSize(21)
          .fontColor(this.backFocused ? Color.White : '#007DFF')
          .backgroundColor(this.backFocused ? '#007DFF' : Color.Transparent)
          .borderRadius(12)
          .focusable(true)
          .defaultFocus(true)
          .onFocus(() => { this.backFocused = true; })
          .onBlur(() => { this.backFocused = false; })
          .onClick(() => { this.getUIContext().getRouter().back(); })
          .onKeyEvent((event: KeyEvent) => {
            if (event.type === KeyType.Up && event.keyCode === 2054) {
              this.getUIContext().getRouter().back();
            }
          })
        Text($r('app.string.ui_food_details'))
          .fontSize(27)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('').width(80)
      }
      .width('100%')
      .padding({ left: 56, right: 56, top: 22, bottom: 22 })
      .backgroundColor($r('app.color.card_background'))

      if (this.foodItem !== null) {
        // 大屏详情卡片 - 居中
        Column() {
          Column({ space: 20 }) {
            Row() {
              Text(this.foodItem.name)
                .fontSize(36)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
              Text(this.foodItem.getStatusText())
                .fontSize(21)
                .fontColor(this.foodItem.getStatusColor())
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                .borderRadius(16)
                .backgroundColor(this.foodItem.getStatusBgColor())
            }
            .width('100%')

            if (this.foodItem.category.length > 0 || this.foodItem.spec.length > 0) {
              Row({ space: 16 }) {
                if (this.foodItem.category.length > 0) {
                  Text(localizedFoodLabel(this.foodItem.category))
                    .fontSize(21)
                    .fontColor($r('app.color.text_secondary'))
                    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                    .borderRadius(12)
                    .backgroundColor($r('app.color.chip_background'))
                }
                if (this.foodItem.spec.length > 0) {
                  Text(this.foodItem.spec)
                    .fontSize(21)
                    .fontColor($r('app.color.text_secondary'))
                    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                    .borderRadius(12)
                    .backgroundColor($r('app.color.chip_background'))
                }
              }
            }

            Divider().color($r('app.color.divider'))

            if (this.foodItem.barcode.length > 0) {
              this.buildRow($r('app.string.ui_barcode'), this.foodItem.barcode)
            }
            this.buildRow($r('app.string.ui_storage_method'), getStorageTypeName(this.foodItem.storageType))
            this.buildRow($r('app.string.ui_expiry_date'),
              this.foodItem.expiryDate > 0 ? formatTimestamp(this.foodItem.expiryDate) : $r('app.string.watch_not_set'))
            this.buildRow($r('app.string.ui_expiry_status'), this.getExpiryText())
            this.buildRow($r('app.string.ui_calories_for_this_item'),
              this.foodItem.calories > 0 ? this.foodItem.calories.toFixed(0) + ' kcal' : $r('app.string.ui_not_recorded'))
            this.buildRow($r('app.string.ui_added_on'),
              this.foodItem.createTime > 0 ? formatTimestamp(this.foodItem.createTime) : $r('app.string.ui_unknown'))
          }
          .width('70%')
          .padding(40)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(24)
          .focusable(true)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
          Text(this.isLoading ? $r('app.string.ui_loading') : $r('app.string.ui_food_item_not_found'))
            .fontSize(24)
            .fontColor($r('app.color.text_hint'))
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .animation({ duration: 260, curve: Curve.EaseInOut })
  }

  @Builder
  buildRow(label: ResourceStr, value: ResourceStr) {
    Row() {
      Text(label)
        .fontSize(21)
        .fontColor($r('app.color.text_secondary'))
        .width(150)
      Text(value)
        .fontSize(21)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }
}
