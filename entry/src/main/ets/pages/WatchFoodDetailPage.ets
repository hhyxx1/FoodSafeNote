import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
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

  private getString(resId: number, fallback: string): string {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      return ctx.resourceManager.getStringSync(resId);
    } catch (e) {
      return fallback;
    }
  }

  private getStatusText(): string {
    if (this.foodItem === null) {
      return '';
    }
    if (this.foodItem.status === 1) {
      return this.getString($r('app.string.status_consumed').id, 'Consumed');
    }
    if (this.foodItem.status === 2) {
      return this.getString($r('app.string.status_wasted').id, 'Discarded');
    }
    if (this.foodItem.isExpired()) {
      return this.getString($r('app.string.status_expired').id, 'Expired');
    }
    if (this.foodItem.isNearExpiry()) {
      return this.getString($r('app.string.status_near_expiry').id, 'Near expiry');
    }
    return this.getString($r('app.string.status_normal').id, 'Normal');
  }

  private getExpiryText(): string {
    if (this.foodItem === null) return '';
    if (this.foodItem.expiryDate <= 0) return this.getString($r('app.string.watch_not_set').id, 'Not set');
    const days: number = this.foodItem.getRemainingDays();
    if (days < 0) {
      return this.getString($r('app.string.watch_expired_prefix').id, 'Expired ') + Math.abs(days).toString() +
        this.getString($r('app.string.watch_days_suffix').id, ' days');
    }
    if (days === 0) return this.getString($r('app.string.watch_expire_today').id, 'Expires today');
    return this.getString($r('app.string.watch_remaining_prefix').id, 'Remaining ') + days.toString() +
      this.getString($r('app.string.watch_days_suffix').id, ' days');
  }

  build() {
    Column({ space: 4 }) {
      Text($r('app.string.watch_back'))
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

        Text(this.getStatusText())
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
        Text($r('app.string.watch_loading'))
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
