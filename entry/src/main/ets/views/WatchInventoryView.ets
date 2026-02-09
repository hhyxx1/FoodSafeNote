import { router } from '@kit.ArkUI';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { FoodItem } from '../model/DataModels';

interface WatchFoodParams {
  foodId: number;
}

@Component
export struct WatchInventoryView {
  @Prop @Watch('onRefresh') refreshKey: number = 0;
  @Link listOpen: boolean;
  @State foodItems: FoodItem[] = [];
  @State normalCount: number = 0;
  @State nearExpiryCount: number = 0;
  @State expiredCount: number = 0;

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
      let normal: number = 0;
      let near: number = 0;
      let expired: number = 0;
      for (let i = 0; i < items.length; i++) {
        if (items[i].isExpired()) { expired++; }
        else if (items[i].isNearExpiry()) { near++; }
        else { normal++; }
      }
      this.normalCount = normal;
      this.nearExpiryCount = near;
      this.expiredCount = expired;
    });
  }

  build() {
    if (!this.listOpen) {
      // 总览页 - 可滑动翻页
      Column({ space: 4 }) {
        Text('库存')
          .fontSize(11)
          .fontColor($r('app.color.text_hint'))

        Text(this.foodItems.length.toString())
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor('#007DFF')

        Row({ space: 8 }) {
          Column({ space: 1 }) {
            Stack({ alignContent: Alignment.Center }) {
              Circle().width(24).height(24).fill('#34C759')
              Text(this.normalCount.toString())
                .fontSize(11).fontWeight(FontWeight.Bold).fontColor(Color.White)
            }
            Text('正常').fontSize(8).fontColor($r('app.color.text_secondary'))
          }.alignItems(HorizontalAlign.Center)

          Column({ space: 1 }) {
            Stack({ alignContent: Alignment.Center }) {
              Circle().width(24).height(24).fill('#FF9500')
              Text(this.nearExpiryCount.toString())
                .fontSize(11).fontWeight(FontWeight.Bold).fontColor(Color.White)
            }
            Text('临期').fontSize(8).fontColor($r('app.color.text_secondary'))
          }.alignItems(HorizontalAlign.Center)

          Column({ space: 1 }) {
            Stack({ alignContent: Alignment.Center }) {
              Circle().width(24).height(24).fill('#FF3B30')
              Text(this.expiredCount.toString())
                .fontSize(11).fontWeight(FontWeight.Bold).fontColor(Color.White)
            }
            Text('过期').fontSize(8).fontColor($r('app.color.text_secondary'))
          }.alignItems(HorizontalAlign.Center)
        }

        Text('点击查看列表 >')
          .fontSize(10)
          .fontColor('#007DFF')
          .margin({ top: 2 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 30, right: 30, top: 15, bottom: 15 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.listOpen = true;
      })
    } else {
      // 列表页 - 禁用Swiper滑动，指示点隐藏
      Column() {
        // 返回按钮 - 留出顶部安全区，不与指示点重叠
        Text('< 返回总览')
          .fontSize(11)
          .fontColor('#007DFF')
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 10, bottom: 4 })
          .onClick(() => { this.listOpen = false; })

        if (this.foodItems.length === 0) {
          // 空状态
          Column({ space: 4 }) {
            Text('暂无库存')
              .fontSize(13)
              .fontColor($r('app.color.text_hint'))
            Text('在手机端添加食品')
              .fontSize(10)
              .fontColor($r('app.color.text_disabled'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          List({ space: 1 }) {
            ForEach(this.foodItems, (item: FoodItem) => {
              ListItem() {
                Row() {
                  Circle().width(6).height(6).fill(item.getStatusColor())
                  Text(item.name)
                    .fontSize(12)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .padding({ left: 4 })
                  Text(item.getStatusText())
                    .fontSize(9)
                    .fontColor(item.getStatusColor())
                }
                .width('100%')
                .padding({ left: 24, right: 24, top: 4, bottom: 4 })
              }
              .onClick(() => {
                const params: WatchFoodParams = { foodId: item.id };
                router.pushUrl({ url: 'pages/WatchFoodDetailPage', params: params });
              })
            }, (item: FoodItem) => item.id.toString())
          }
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: 12 })
    }
  }
}
