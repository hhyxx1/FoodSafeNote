import { router } from '@kit.ArkUI';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { ConsumptionRecord, DailyCalorie, WasteStat } from '../model/DataModels';
import { padZero } from '../common/Constants';

@Entry
@Component
struct HealthReportPage {
  @State timeRange: string = 'week';
  @State caloriesByMember: DailyCalorie[] = [];
  @State wasteStats: WasteStat[] = [];
  @State records: ConsumptionRecord[] = [];
  @State totalCalories: number = 0;
  @State totalWaste: number = 0;
  @State totalEatCount: number = 0;
  @State isLoading: boolean = true;
  @State showDatePicker: boolean = false;
  @State customStart: Date = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  @State customEnd: Date = new Date();
  @State pickingStart: boolean = true;

  aboutToAppear(): void {
    this.loadData();
  }

  private getTimeRangeMs(): number[] {
    const now: number = Date.now();
    let startTime: number = 0;
    let endTime: number = now;
    if (this.timeRange === 'today') {
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      startTime = today.getTime();
    } else if (this.timeRange === 'week') {
      startTime = now - 7 * 24 * 60 * 60 * 1000;
    } else if (this.timeRange === 'month') {
      startTime = now - 30 * 24 * 60 * 60 * 1000;
    } else if (this.timeRange === '90d') {
      startTime = now - 90 * 24 * 60 * 60 * 1000;
    } else if (this.timeRange === 'halfyear') {
      startTime = now - 180 * 24 * 60 * 60 * 1000;
    } else if (this.timeRange === 'year') {
      startTime = now - 365 * 24 * 60 * 60 * 1000;
    } else if (this.timeRange === 'all') {
      startTime = 0;
    } else if (this.timeRange === 'custom') {
      this.customStart.setHours(0, 0, 0, 0);
      this.customEnd.setHours(23, 59, 59, 999);
      startTime = this.customStart.getTime();
      endTime = this.customEnd.getTime();
    }
    return [startTime, endTime];
  }

  private loadData(): void {
    this.isLoading = true;
    const range: number[] = this.getTimeRangeMs();
    const startTime: number = range[0];
    const endTime: number = range[1];

    DatabaseHelper.getInstance().getCaloriesByMemberForRange(startTime, endTime)
      .then((calories: DailyCalorie[]) => {
        this.caloriesByMember = calories;
        let total: number = 0;
        let eatCount: number = 0;
        for (let i = 0; i < calories.length; i++) {
          total = total + calories[i].totalCalories;
          eatCount = eatCount + calories[i].recordCount;
        }
        this.totalCalories = total;
        this.totalEatCount = eatCount;
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

    DatabaseHelper.getInstance().getConsumptionsByRange(startTime, endTime)
      .then((records: ConsumptionRecord[]) => {
        this.records = records;
        this.isLoading = false;
      });
  }

  private formatRecordTime(timestamp: number): string {
    const date = new Date(timestamp);
    return padZero(date.getMonth() + 1) + '-' + padZero(date.getDate()) + ' ' +
      padZero(date.getHours()) + ':' + padZero(date.getMinutes());
  }

  private formatDate(d: Date): string {
    return d.getFullYear() + '-' + padZero(d.getMonth() + 1) + '-' + padZero(d.getDate());
  }

  private getRangeLabel(): string {
    if (this.timeRange === 'today') return '今日';
    if (this.timeRange === 'week') return '近7天';
    if (this.timeRange === 'month') return '近30天';
    if (this.timeRange === '90d') return '近90天';
    if (this.timeRange === 'halfyear') return '近半年';
    if (this.timeRange === 'year') return '近一年';
    if (this.timeRange === 'all') return '全部数据';
    if (this.timeRange === 'custom') return this.formatDate(this.customStart) + ' ~ ' + this.formatDate(this.customEnd);
    return '';
  }

  build() {
    Column() {
      // 导航栏
      Row() {
        Button('返回')
          .height(36).fontSize(14).fontColor('#007DFF')
          .backgroundColor(Color.Transparent)
          .onClick(() => { router.back(); })
        Text('健康报表')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          .layoutWeight(1).textAlign(TextAlign.Center)
        Text('').width(56)
      }
      .width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))

      // 快捷时间选择 - 第一行
      Row({ space: 0 }) {
        this.buildTab('今日', 'today')
        this.buildTab('7天', 'week')
        this.buildTab('30天', 'month')
        this.buildTab('90天', '90d')
      }
      .width('100%').padding({ left: 16, right: 16, top: 8 })

      // 第二行
      Row({ space: 0 }) {
        this.buildTab('半年', 'halfyear')
        this.buildTab('一年', 'year')
        this.buildTab('全部', 'all')
        this.buildTab('自定义', 'custom')
      }
      .width('100%').padding({ left: 16, right: 16, top: 4, bottom: 4 })

      // 自定义日期选择器
      if (this.timeRange === 'custom') {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text('从: ' + this.formatDate(this.customStart))
              .fontSize(13).fontColor(this.pickingStart ? '#007DFF' : '#666666')
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(6)
              .backgroundColor(this.pickingStart ? '#E8F0FE' : '#F0F0F0')
              .onClick(() => { this.pickingStart = true; })
            Text('到: ' + this.formatDate(this.customEnd))
              .fontSize(13).fontColor(!this.pickingStart ? '#007DFF' : '#666666')
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(6)
              .backgroundColor(!this.pickingStart ? '#E8F0FE' : '#F0F0F0')
              .onClick(() => { this.pickingStart = false; })
            Button('查询')
              .height(28).fontSize(12).fontColor(Color.White)
              .backgroundColor('#007DFF').borderRadius(6)
              .onClick(() => { this.loadData(); })
          }
          .width('100%').justifyContent(FlexAlign.Center)

          DatePicker({
            start: new Date('2020-01-01'),
            end: new Date(),
            selected: this.pickingStart ? this.customStart : this.customEnd
          })
            .width('100%')
            .height(120)
            .onChange((value: DatePickerResult) => {
              const year: number = value.year !== undefined ? value.year : new Date().getFullYear();
              const month: number = value.month !== undefined ? value.month : new Date().getMonth();
              const day: number = value.day !== undefined ? value.day : new Date().getDate();
              const d = new Date();
              d.setFullYear(year);
              d.setMonth(month);
              d.setDate(day);
              if (this.pickingStart) {
                this.customStart = d;
              } else {
                this.customEnd = d;
              }
            })
        }
        .width('100%').padding({ left: 16, right: 16, bottom: 4 })
      }

      // 范围说明
      Text(this.getRangeLabel() + ' · 共 ' + this.records.length + ' 条记录')
        .fontSize(12).fontColor($r('app.color.text_hint'))
        .width('100%').padding({ left: 16, right: 16, bottom: 4 })

      Scroll() {
        Column({ space: 16 }) {
          // 总览卡片
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text(this.totalCalories.toFixed(0))
                .fontSize(28).fontWeight(FontWeight.Bold).fontColor('#007DFF')
              Text('总摄入 kcal').fontSize(12).fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1).padding(16).backgroundColor($r('app.color.card_background')).borderRadius(12)
            .alignItems(HorizontalAlign.Center)

            Column({ space: 4 }) {
              Text(this.totalEatCount.toString())
                .fontSize(28).fontWeight(FontWeight.Bold).fontColor('#34C759')
              Text('进食次数').fontSize(12).fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1).padding(16).backgroundColor($r('app.color.card_background')).borderRadius(12)
            .alignItems(HorizontalAlign.Center)

            Column({ space: 4 }) {
              Text(this.totalWaste.toString())
                .fontSize(28).fontWeight(FontWeight.Bold).fontColor('#FF6B00')
              Text('浪费食品').fontSize(12).fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1).padding(16).backgroundColor($r('app.color.card_background')).borderRadius(12)
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%').padding({ left: 16, right: 16, top: 8 })

          // 成员摄入
          if (this.caloriesByMember.length > 0) {
            Column({ space: 12 }) {
              Text('成员热量摄入')
                .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
              ForEach(this.caloriesByMember, (item: DailyCalorie) => {
                Row() {
                  Text(item.memberName.substring(0, 1))
                    .fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.White)
                    .textAlign(TextAlign.Center).width(36).height(36).borderRadius(18)
                    .backgroundColor('#007DFF')
                  Column({ space: 2 }) {
                    Text(item.memberName).fontSize(14).fontColor($r('app.color.text_primary'))
                    Text(item.recordCount + ' 次进食').fontSize(12).fontColor($r('app.color.text_hint'))
                  }
                  .layoutWeight(1).padding({ left: 12 }).alignItems(HorizontalAlign.Start)
                  Text(item.totalCalories.toFixed(0) + ' kcal')
                    .fontSize(15).fontWeight(FontWeight.Medium).fontColor('#FF6B00')
                }
                .width('100%').padding({ top: 6, bottom: 6 })
              }, (item: DailyCalorie) => item.memberName)
            }
            .width('100%').padding(16).margin({ left: 16, right: 16 })
            .backgroundColor($r('app.color.card_background')).borderRadius(16)
          }

          // 浪费分析
          if (this.wasteStats.length > 0) {
            Column({ space: 12 }) {
              Text('浪费分析')
                .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
              ForEach(this.wasteStats, (stat: WasteStat) => {
                Row() {
                  Text(stat.category)
                    .fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
                  Text(stat.count + ' 件')
                    .fontSize(14).fontColor('#FF6B00')
                }
                .width('100%').padding({ top: 6, bottom: 6 })
              }, (stat: WasteStat) => stat.category)
            }
            .width('100%').padding(16).margin({ left: 16, right: 16 })
            .backgroundColor($r('app.color.card_background')).borderRadius(16)
          }

          // 详细记录
          Column({ space: 12 }) {
            Text('详细记录 (' + this.records.length + ')')
              .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
            if (this.records.length === 0) {
              Text('该时间范围内暂无记录').fontSize(13).fontColor($r('app.color.text_hint'))
                .width('100%').textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
            } else {
              ForEach(this.records, (record: ConsumptionRecord) => {
                Row() {
                  Text(record.type === 0 ? '🍽️' : '🗑️').fontSize(16).width(28)
                  Column({ space: 2 }) {
                    Text(record.foodName).fontSize(13).fontColor($r('app.color.text_primary'))
                    Text(record.type === 0 ? record.memberName + ' 食用' : '丢弃: ' + record.wasteReason)
                      .fontSize(11).fontColor(record.type === 0 ? '#666666' : '#FF3B30')
                  }
                  .layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Column({ space: 2 }) {
                    if (record.calories > 0) {
                      Text(record.calories.toFixed(0) + ' kcal').fontSize(12).fontColor('#FF6B00')
                    }
                    Text(this.formatRecordTime(record.createTime)).fontSize(10).fontColor($r('app.color.text_disabled'))
                  }
                  .alignItems(HorizontalAlign.End)
                }
                .width('100%').padding({ top: 6, bottom: 6 })
              }, (record: ConsumptionRecord) => record.id.toString())
            }
          }
          .width('100%').padding(16).margin({ left: 16, right: 16, bottom: 32 })
          .backgroundColor($r('app.color.card_background')).borderRadius(16)
        }
      }
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }

  @Builder
  buildTab(label: string, type: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.timeRange === type ? Color.White : '#666666')
      .textAlign(TextAlign.Center)
      .layoutWeight(1).height(32)
      .backgroundColor(this.timeRange === type ? '#007DFF' : '#F0F0F0')
      .borderRadius(8)
      .onClick(() => {
        this.timeRange = type;
        if (type !== 'custom') {
          this.loadData();
        }
      })
  }
}
