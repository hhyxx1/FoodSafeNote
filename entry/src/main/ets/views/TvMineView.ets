import { DatabaseHelper } from '../common/DatabaseHelper';
import { ProductDict } from '../model/DataModels';
import { getSourceName } from '../common/Constants';

@Component
export struct TvMineView {
  @Prop @Watch('onRefresh') refreshKey: number = 0;
  @State dictList: ProductDict[] = [];
  @State totalCount: number = 0;
  @State focusedId: number = -1;

  aboutToAppear(): void {
    if (DatabaseHelper.getInstance().getStore() !== null) {
      this.loadData();
    }
  }

  onRefresh(): void {
    this.loadData();
  }

  private loadData(): void {
    DatabaseHelper.getInstance().getAllProductDict().then((list: ProductDict[]) => {
      this.dictList = list;
      this.totalCount = list.length;
    });
  }

  build() {
    Column() {
      // 标题
      Row() {
        Text('产品字典')
          .fontSize(27)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.totalCount + ' 条记录')
          .fontSize(21)
          .fontColor($r('app.color.text_hint'))
      }
      .width('100%')
      .padding({ left: 40, right: 40, top: 24, bottom: 16 })

      Text('数据仅本地存储，离线可用')
        .fontSize(18)
        .fontColor($r('app.color.text_hint'))
        .width('100%')
        .padding({ left: 40, right: 40, bottom: 16 })

      // 只读列表（可聚焦行）
      if (this.dictList.length === 0) {
        Column() {
          Text('暂无产品字典数据')
            .fontSize(24)
            .fontColor($r('app.color.text_hint'))
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List({ space: 12 }) {
          ForEach(this.dictList, (item: ProductDict) => {
            ListItem() {
              Row() {
                Column({ space: 6 }) {
                  Text(item.name)
                    .fontSize(24)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  Row({ space: 20 }) {
                    if (item.barcode.length > 0) {
                      Text('条码: ' + item.barcode)
                        .fontSize(18)
                        .fontColor($r('app.color.text_hint'))
                    }
                    if (item.category.length > 0) {
                      Text(item.category)
                        .fontSize(18)
                        .fontColor($r('app.color.text_hint'))
                    }
                    if (item.spec.length > 0) {
                      Text(item.spec)
                        .fontSize(18)
                        .fontColor($r('app.color.text_hint'))
                    }
                    Text(getSourceName(item.source))
                      .fontSize(18)
                      .fontColor('#007DFF')
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Text(item.calories > 0 ? item.calories.toFixed(0) + ' kcal' : '未记录')
                  .fontSize(24)
                  .fontColor(item.calories > 0 ? '#FF6B00' : $r('app.color.text_disabled'))
              }
              .width('100%')
              .padding(24)
              .backgroundColor(this.focusedId === item.id ? '#E0EFFF' : $r('app.color.card_background'))
              .borderRadius(12)
              .border({
                width: this.focusedId === item.id ? 3 : 0,
                color: '#007DFF'
              })
            }
            .focusable(true)
            .onFocus(() => {
              this.focusedId = item.id;
            })
            .onBlur(() => {
              if (this.focusedId === item.id) {
                this.focusedId = -1;
              }
            })
          }, (item: ProductDict) => item.id.toString())
        }
        .layoutWeight(1)
        .padding({ left: 40, right: 40, bottom: 30 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
