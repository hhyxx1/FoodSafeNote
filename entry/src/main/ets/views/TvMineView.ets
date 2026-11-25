import { localizedFoodLabel } from '../common/Constants';
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
        Text($r('app.string.ui_product_dictionary'))
          .fontSize(27)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text($r('app.string.ui_records_d', this.totalCount))
          .fontSize(21)
          .fontColor($r('app.color.text_hint'))
      }
      .width('100%')
      .padding({ left: 56, right: 56, top: 22, bottom: 22 })

      Text($r('app.string.ui_works_offline_with_on_device_storage_2'))
        .fontSize(18)
        .fontColor($r('app.color.text_hint'))
        .width('100%')
        .padding({ left: 56, right: 56, bottom: 22 })

      // 只读列表（可聚焦行）
      if (this.dictList.length === 0) {
        Column() {
          Text($r('app.string.ui_no_dictionary_entries'))
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
                      Text($r('app.string.ui_barcode_s', item.barcode))
                        .fontSize(18)
                        .fontColor($r('app.color.text_hint'))
                    }
                    if (item.category.length > 0) {
                      Text(localizedFoodLabel(item.category))
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

                Text(item.calories > 0 ? item.calories.toFixed(0) + ' kcal' : $r('app.string.ui_not_recorded'))
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
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .layoutWeight(1)
        .padding({ left: 56, right: 56, bottom: 22 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .animation({ duration: 260, curve: Curve.EaseInOut })
  }
}
