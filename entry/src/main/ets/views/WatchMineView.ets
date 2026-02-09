import { DatabaseHelper } from '../common/DatabaseHelper';
import { ProductDict } from '../model/DataModels';

@Component
export struct WatchMineView {
  @Prop @Watch('onRefresh') refreshKey: number = 0;
  @State dictList: ProductDict[] = [];

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
    });
  }

  build() {
    Column() {
      Text('产品字典')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 4, bottom: 2 })

      if (this.dictList.length === 0) {
        Text('暂无数据')
          .fontSize(11)
          .fontColor($r('app.color.text_hint'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
      } else {
        List({ space: 0 }) {
          ForEach(this.dictList, (item: ProductDict) => {
            ListItem() {
              Row() {
                Text(item.name)
                  .fontSize(11)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.calories > 0 ? item.calories.toFixed(0) : '-')
                  .fontSize(11)
                  .fontColor(item.calories > 0 ? '#FF6B00' : $r('app.color.text_disabled'))
              }
              .width('100%')
              .padding({ left: 24, right: 24, top: 4, bottom: 4 })
            }
          }, (item: ProductDict) => item.id.toString())
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: 2, bottom: 12 })
  }
}
