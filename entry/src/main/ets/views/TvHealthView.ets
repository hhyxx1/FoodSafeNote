import { DatabaseHelper } from '../common/DatabaseHelper';
import { DailyCalorie, WasteStat } from '../model/DataModels';

@Component
export struct TvHealthView {
  @Prop @Watch('onRefresh') refreshKey: number = 0;
  @State dailyCalories: DailyCalorie[] = [];
  @State wasteStats: WasteStat[] = [];
  @State totalCalories: number = 0;
  @State totalWaste: number = 0;
  @State focusedMember: string = '';

  aboutToAppear(): void {
    if (DatabaseHelper.getInstance().getStore() !== null) {
      this.loadData();
    }
  }

  onRefresh(): void {
    this.loadData();
  }

  private loadData(): void {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const startTime: number = today.getTime();
    const endTime: number = startTime + 24 * 60 * 60 * 1000;

    DatabaseHelper.getInstance().getCaloriesByMemberForRange(startTime, endTime)
      .then((calories: DailyCalorie[]) => {
        this.dailyCalories = calories;
        let total: number = 0;
        for (let i = 0; i < calories.length; i++) {
          total = total + calories[i].totalCalories;
        }
        this.totalCalories = total;
      });

    DatabaseHelper.getInstance().getWasteStatsByCategory()
      .then((stats: WasteStat[]) => {
        this.wasteStats = stats;
        let total: number = 0;
        for (let i = 0; i < stats.length; i++) {
          total = total + stats[i].count;
        }
        this.totalWaste = total;
      });
  }

  build() {
    Column() {
      Text('健康看板')
        .fontSize(27)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: 40, right: 40, top: 24, bottom: 20 })

      // 分栏布局
      Row({ space: 30 }) {
        // 左侧 - 成员摄入（可聚焦每个成员行）
        Column({ space: 16 }) {
          Text('今日成员摄入')
            .fontSize(24)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          if (this.dailyCalories.length === 0) {
            Text('今日暂无摄入记录')
              .fontSize(21)
              .fontColor($r('app.color.text_hint'))
              .margin({ top: 30 })
          } else {
            ForEach(this.dailyCalories, (item: DailyCalorie) => {
              Row() {
                Text(item.memberName.substring(0, 1))
                  .fontSize(24)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .textAlign(TextAlign.Center)
                  .width(56)
                  .height(56)
                  .borderRadius(28)
                  .backgroundColor('#007DFF')
                Column({ space: 4 }) {
                  Text(item.memberName)
                    .fontSize(24)
                    .fontColor($r('app.color.text_primary'))
                  Text(item.recordCount + ' 次进食')
                    .fontSize(18)
                    .fontColor($r('app.color.text_hint'))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 16 })
                Text(item.totalCalories.toFixed(0) + ' kcal')
                  .fontSize(24)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#FF6B00')
              }
              .width('100%')
              .padding(16)
              .borderRadius(12)
              .backgroundColor(this.focusedMember === item.memberName ? '#E0EFFF' : $r('app.color.card_background'))
              .border({
                width: this.focusedMember === item.memberName ? 3 : 0,
                color: '#007DFF'
              })
              .focusable(true)
              .onFocus(() => {
                this.focusedMember = item.memberName;
              })
              .onBlur(() => {
                if (this.focusedMember === item.memberName) {
                  this.focusedMember = '';
                }
              })
            }, (item: DailyCalorie) => item.memberName)
          }
        }
        .layoutWeight(2)
        .padding(30)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)

        // 右侧 - 总览+浪费
        Column({ space: 20 }) {
          // 总摄入
          Column({ space: 8 }) {
            Text('今日总摄入')
              .fontSize(21)
              .fontColor($r('app.color.text_secondary'))
            Text(this.totalCalories.toFixed(0))
              .fontSize(48)
              .fontWeight(FontWeight.Bold)
              .fontColor('#007DFF')
            Text('kcal')
              .fontSize(21)
              .fontColor($r('app.color.text_hint'))
          }
          .width('100%')
          .padding(24)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
          .alignItems(HorizontalAlign.Center)
          .focusable(true)

          // 浪费统计
          Column({ space: 8 }) {
            Text('浪费统计')
              .fontSize(21)
              .fontColor($r('app.color.text_secondary'))
            Text(this.totalWaste.toString() + ' 件')
              .fontSize(36)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FF6B00')
            if (this.wasteStats.length > 0) {
              ForEach(this.wasteStats, (stat: WasteStat) => {
                Row() {
                  Text(stat.category).fontSize(18).fontColor($r('app.color.text_primary')).layoutWeight(1)
                  Text(stat.count + ' 件').fontSize(18).fontColor('#FF6B00')
                }
                .width('100%')
                .padding({ top: 4, bottom: 4 })
              }, (stat: WasteStat) => stat.category)
            }
          }
          .width('100%')
          .padding(24)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
          .alignItems(HorizontalAlign.Center)
          .focusable(true)
        }
        .layoutWeight(1)
      }
      .layoutWeight(1)
      .padding({ left: 40, right: 40, bottom: 30 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
