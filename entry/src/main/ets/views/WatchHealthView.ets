import { DatabaseHelper } from '../common/DatabaseHelper';
import { DailyCalorie } from '../model/DataModels';

@Component
export struct WatchHealthView {
  @Prop @Watch('onRefresh') refreshKey: number = 0;
  @State dailyCalories: DailyCalorie[] = [];
  @State totalCalories: number = 0;
  @State viewMode: string = 'today';

  aboutToAppear(): void {
    if (DatabaseHelper.getInstance().getStore() !== null) {
      this.loadData();
    }
  }

  onRefresh(): void {
    this.loadData();
  }

  private loadData(): void {
    const now = new Date();
    let startTime: number = 0;
    const endTime: number = now.getTime();
    if (this.viewMode === 'today') {
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      startTime = today.getTime();
    } else {
      startTime = endTime - 7 * 24 * 60 * 60 * 1000;
    }
    DatabaseHelper.getInstance().getCaloriesByMemberForRange(startTime, endTime)
      .then((calories: DailyCalorie[]) => {
        this.dailyCalories = calories;
        let total: number = 0;
        for (let i = 0; i < calories.length; i++) {
          total = total + calories[i].totalCalories;
        }
        this.totalCalories = total;
      });
  }

  build() {
    Column({ space: 3 }) {
      // 切换按钮
      Row({ space: 0 }) {
        Text('今日')
          .fontSize(10)
          .fontColor(this.viewMode === 'today' ? Color.White : $r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .width(36).height(20)
          .backgroundColor(this.viewMode === 'today' ? '#007DFF' : $r('app.color.chip_background'))
          .borderRadius(10)
          .onClick(() => { this.viewMode = 'today'; this.loadData(); })
        Text('本周')
          .fontSize(10)
          .fontColor(this.viewMode === 'week' ? Color.White : $r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .width(36).height(20)
          .backgroundColor(this.viewMode === 'week' ? '#007DFF' : $r('app.color.chip_background'))
          .borderRadius(10)
          .onClick(() => { this.viewMode = 'week'; this.loadData(); })
      }

      // 总热量
      Text(this.totalCalories.toFixed(0))
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor('#007DFF')
      Text('kcal')
        .fontSize(10)
        .fontColor($r('app.color.text_hint'))

      // 成员摄入（最多3条）
      ForEach(this.dailyCalories.slice(0, 3), (item: DailyCalorie) => {
        Row() {
          Text(item.memberName)
            .fontSize(11)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text(item.totalCalories.toFixed(0) + ' kcal')
            .fontSize(11)
            .fontColor('#FF6B00')
        }
        .width('100%')
        .padding({ top: 1, bottom: 1 })
      }, (item: DailyCalorie) => item.memberName)

      if (this.dailyCalories.length === 0) {
        Text('暂无摄入记录')
          .fontSize(10)
          .fontColor($r('app.color.text_hint'))
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 30, right: 30, top: 12, bottom: 12 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
