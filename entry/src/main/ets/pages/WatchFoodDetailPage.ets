import { router } from '@kit.ArkUI';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { FoodItem } from '../model/DataModels';

interface WatchFoodParams {
  foodId: number;
}

@Entry
@Component
struct WatchFoodDetailPage {
  @State foodItem: FoodItem | null = null;
  private foodId: number = 0;

  aboutToAppear(): void {
    const params: WatchFoodParams = router.getParams() as WatchFoodParams;
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
    if (this.foodItem.expiryDate <= 0) return '未设置';
    const days: number = this.foodItem.getRemainingDays();
    if (days < 0) return '过期' + Math.abs(days) + '天';
    if (days === 0) return '今天到期';
    return '剩余' + days + '天';
  }

  build() {
    Column({ space: 4 }) {
      Text('< 返回')
        .fontSize(10)
        .fontColor('#007DFF')
        .onClick(() => { router.back(); })

      if (this.foodItem !== null) {
        Circle()
          .width(14)
          .height(14)
          .fill(this.foodItem.getStatusColor())

        Text(this.foodItem.name)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)

        Text(this.foodItem.getStatusText())
          .fontSize(13)
          .fontColor(this.foodItem.getStatusColor())

        Text(this.getExpiryText())
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.foodItem.getStatusColor())

        if (this.foodItem.calories > 0) {
          Text(this.foodItem.calories.toFixed(0) + ' kcal')
            .fontSize(12)
            .fontColor('#FF6B00')
        }
      } else {
        Text('加载中...')
          .fontSize(11)
          .fontColor($r('app.color.text_hint'))
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 30, right: 30, top: 16, bottom: 24 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.page_background'))
  }
}
