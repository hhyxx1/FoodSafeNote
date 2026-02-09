import { router } from '@kit.ArkUI';
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
  @State backFocused: boolean = false;
  private foodId: number = 0;

  aboutToAppear(): void {
    const params: TvFoodParams = router.getParams() as TvFoodParams;
    if (params !== null && params !== undefined) {
      this.foodId = params.foodId;
      this.loadData();
    }
  }

  private loadData(): void {
    DatabaseHelper.getInstance().getFoodItemById(this.foodId).then((item: FoodItem | null) => {
      this.foodItem = item;
    });
  }

  private getExpiryText(): string {
    if (this.foodItem === null) return '';
    if (this.foodItem.expiryDate <= 0) return '未设置保质期';
    const days: number = this.foodItem.getRemainingDays();
    if (days < 0) return '已过期 ' + Math.abs(days) + ' 天';
    if (days === 0) return '今天到期';
    return '剩余 ' + days + ' 天';
  }

  build() {
    Column() {
      // 顶部导航
      Row() {
        Button('返回')
          .height(60)
          .fontSize(21)
          .fontColor(this.backFocused ? Color.White : '#007DFF')
          .backgroundColor(this.backFocused ? '#007DFF' : Color.Transparent)
          .borderRadius(12)
          .focusable(true)
          .defaultFocus(true)
          .onFocus(() => { this.backFocused = true; })
          .onBlur(() => { this.backFocused = false; })
          .onClick(() => { router.back(); })
          .onKeyEvent((event: KeyEvent) => {
            if (event.type === KeyType.Up && event.keyCode === 2054) {
              router.back();
            }
          })
        Text('食品详情')
          .fontSize(27)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('').width(80)
      }
      .width('100%')
      .padding({ left: 30, right: 30, top: 20, bottom: 16 })
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
                  Text(this.foodItem.category)
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
              this.buildRow('条码', this.foodItem.barcode)
            }
            this.buildRow('存储方式', getStorageTypeName(this.foodItem.storageType))
            this.buildRow('到期日期',
              this.foodItem.expiryDate > 0 ? formatTimestamp(this.foodItem.expiryDate) : '未设置')
            this.buildRow('保质期状态', this.getExpiryText())
            this.buildRow('热量',
              this.foodItem.calories > 0 ? this.foodItem.calories.toFixed(0) + ' kcal/100g' : '未记录')
            this.buildRow('入库时间',
              this.foodItem.createTime > 0 ? formatTimestamp(this.foodItem.createTime) : '未知')
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
          Text('加载中...')
            .fontSize(24)
            .fontColor($r('app.color.text_hint'))
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  buildRow(label: string, value: string) {
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
