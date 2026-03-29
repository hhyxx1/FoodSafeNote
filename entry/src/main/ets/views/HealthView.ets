import { router } from '@kit.ArkUI';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { ConsumptionRecord, DailyCalorie, WasteStat } from '../model/DataModels';
import { padZero } from '../common/Constants';

@Component
export struct HealthView {
  @Prop @Watch('onRefreshKeyChange') refreshKey: number = 0;
  @State dailyCalories: DailyCalorie[] = [];
  @State todayRecords: ConsumptionRecord[] = [];
  @State wasteStats: WasteStat[] = [];
  @State isLoading: boolean = true;
  @State viewMode: string = 'today';
  @State showDatePicker: boolean = false;
  @State customStart: Date = new Date();
  @State customEnd: Date = new Date();
  @State pickingStart: boolean = true;

  aboutToAppear(): void {
    if (DatabaseHelper.getInstance().getStore() !== null) {
      this.loadData();
    }
  }

  onRefreshKeyChange(): void {
    this.loadData();
  }

  private getTimeRange(): number[] {
    const now = new Date();
    let startTime: number = 0;
    const endTime: number = now.getTime();
    if (this.viewMode === 'today') {
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      startTime = today.getTime();
    } else if (this.viewMode === 'week') {
      startTime = endTime - 7 * 24 * 60 * 60 * 1000;
    } else if (this.viewMode === 'month') {
      startTime = endTime - 30 * 24 * 60 * 60 * 1000;
    } else if (this.viewMode === 'custom') {
      this.customStart.setHours(0, 0, 0, 0);
      this.customEnd.setHours(23, 59, 59, 999);
      startTime = this.customStart.getTime();
      return [startTime, this.customEnd.getTime()];
    }
    return [startTime, endTime];
  }

  private loadData(): void {
    this.isLoading = true;
    const range: number[] = this.getTimeRange();
    const startTime: number = range[0];
    const endTime: number = range[1];

    DatabaseHelper.getInstance().getCaloriesByMemberForRange(startTime, endTime)
      .then((calories: DailyCalorie[]) => {
        this.dailyCalories = calories;
      });
    DatabaseHelper.getInstance().getConsumptionsByRange(startTime, endTime)
      .then((records: ConsumptionRecord[]) => {
        this.todayRecords = records;
        this.isLoading = false;
      });
    DatabaseHelper.getInstance().getWasteStatsByCategory()
      .then((stats: WasteStat[]) => {
        this.wasteStats = stats;
      });
  }

  private getTodayString(): string {
    const now = new Date();
    const weekDays: string[] = ['日', '一', '二', '三', '四', '五', '六'];
    return now.getFullYear() + '年' + (now.getMonth() + 1) + '月' + now.getDate() + '日 星期' + weekDays[now.getDay()];
  }

  private formatRecordTime(timestamp: number): string {
    const date = new Date(timestamp);
    return padZero(date.getMonth() + 1) + '-' + padZero(date.getDate()) + ' ' +
      padZero(date.getHours()) + ':' + padZero(date.getMinutes());
  }

  private getTotalCalories(): number {
    let total: number = 0;
    for (let i = 0; i < this.dailyCalories.length; i++) {
      total = total + this.dailyCalories[i].totalCalories;
    }
    return total;
  }

  private getTotalWasteCount(): number {
    let total: number = 0;
    for (let i = 0; i < this.wasteStats.length; i++) {
      total = total + this.wasteStats[i].count;
    }
    return total;
  }

  private formatDate(d: Date): string {
    return d.getFullYear() + '-' + padZero(d.getMonth() + 1) + '-' + padZero(d.getDate());
  }

  private getViewModeLabel(): string {
    if (this.viewMode === 'today') return '今日';
    if (this.viewMode === 'week') return '近7天';
    if (this.viewMode === 'month') return '近30天';
    if (this.viewMode === 'custom') return this.formatDate(this.customStart) + ' ~ ' + this.formatDate(this.customEnd);
    return '';
  }

  build() {
    Column() {
      Row() {
        Text('健康看板')
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Blank()
        Button('详细报表')
          .height(40).fontSize(12).fontColor('#007DFF')
          .backgroundColor('#E8F0FE').borderRadius(16)
            .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            router.pushUrl({ url: 'pages/HealthReportPage' });
          })
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 时间选择栏
      Row({ space: 0 }) {
        this.buildTimeBtn('今日', 'today')
        this.buildTimeBtn('近7天', 'week')
        this.buildTimeBtn('近30天', 'month')
        this.buildTimeBtn('自定义', 'custom')
      }
      .width('100%').padding({ left: 16, right: 16, bottom: 4 })

      // 自定义日期选择区
      if (this.viewMode === 'custom') {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text('开始: ' + this.formatDate(this.customStart))
              .fontSize(13).fontColor(this.pickingStart ? '#007DFF' : '#666666')
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(6)
              .backgroundColor(this.pickingStart ? '#E8F0FE' : '#F0F0F0')
              .onClick(() => { this.pickingStart = true; })
            Text('结束: ' + this.formatDate(this.customEnd))
              .fontSize(13).fontColor(!this.pickingStart ? '#007DFF' : '#666666')
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(6)
              .backgroundColor(!this.pickingStart ? '#E8F0FE' : '#F0F0F0')
              .onClick(() => { this.pickingStart = false; })
            Button('查询')
              .height(40).fontSize(12).fontColor(Color.White)
              .backgroundColor('#007DFF').borderRadius(6)
              .onClick(() => {
                this.showDatePicker = false;
                this.loadData();
              })
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
      Text(this.getViewModeLabel() + ' · ' + this.todayRecords.length + '条记录')
        .fontSize(12).fontColor($r('app.color.text_hint'))
        .width('100%').padding({ left: 16, right: 16, bottom: 4 })

      Scroll() {
        Column({ space: 16 }) {
          // 总览
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text(this.getTotalCalories().toFixed(0))
                .fontSize(28).fontWeight(FontWeight.Bold).fontColor('#007DFF')
              Text('摄入 (kcal)').fontSize(12).fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1).padding(16).backgroundColor($r('app.color.card_background')).borderRadius(12)
            .alignItems(HorizontalAlign.Center)
            Column({ space: 4 }) {
              Text(this.getTotalWasteCount().toString())
                .fontSize(28).fontWeight(FontWeight.Bold).fontColor('#FF6B00')
              Text('浪费 (件)').fontSize(12).fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1).padding(16).backgroundColor($r('app.color.card_background')).borderRadius(12)
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%').padding({ left: 16, right: 16 })

          // 成员摄入
          if (this.dailyCalories.length > 0) {
            Column({ space: 12 }) {
              Text('成员摄入详情')
                .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
              ForEach(this.dailyCalories, (item: DailyCalorie) => {
                Row() {
                  Text(item.memberName.substring(0, 1))
                    .fontSize(16).fontWeight(FontWeight.Bold).fontColor(Color.White)
                    .textAlign(TextAlign.Center).width(40).height(40).borderRadius(20)
                    .backgroundColor('#007DFF')
                  Column({ space: 4 }) {
                    Text(item.memberName).fontSize(15).fontColor($r('app.color.text_primary'))
                    Text(item.recordCount + ' 次进食').fontSize(12).fontColor($r('app.color.text_hint'))
                  }
                  .layoutWeight(1).alignItems(HorizontalAlign.Start).padding({ left: 12 })
                  Text(item.totalCalories.toFixed(0) + ' kcal')
                    .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#FF6B00')
                }
                .width('100%').padding({ top: 8, bottom: 8 })
              }, (item: DailyCalorie) => item.memberName)
            }
            .width('100%').padding(16).margin({ left: 16, right: 16 })
            .backgroundColor($r('app.color.card_background')).borderRadius(16)
          }

          // 浪费统计
          if (this.wasteStats.length > 0) {
            Column({ space: 8 }) {
              Text('浪费统计').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
              ForEach(this.wasteStats, (stat: WasteStat) => {
                Row() {
                  Text('🗑️').fontSize(14).width(24)
                  Text(stat.category).fontSize(13).fontColor($r('app.color.text_primary')).layoutWeight(1)
                  Text(stat.count + ' 件').fontSize(13).fontColor('#FF6B00')
                }
                .width('100%').padding({ top: 4, bottom: 4 })
              }, (stat: WasteStat) => stat.category)
            }
            .width('100%').padding(16).margin({ left: 16, right: 16 })
            .backgroundColor($r('app.color.card_background')).borderRadius(16)
          }

          // 记录列表
          Column({ space: 12 }) {
            Text('消耗记录')
              .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
            if (this.todayRecords.length === 0) {
              Column({ space: 8 }) {
                Text('📊').fontSize(40)
                Text('暂无记录').fontSize(14).fontColor($r('app.color.text_hint'))
              }
              .width('100%').padding({ top: 24, bottom: 24 })
              .alignItems(HorizontalAlign.Center)
            } else {
              ForEach(this.todayRecords, (record: ConsumptionRecord) => {
                Row() {
                  Text(record.type === 0 ? '🍽️' : '🗑️').fontSize(20).width(32)
                  Column({ space: 2 }) {
                    Text(record.foodName).fontSize(14).fontColor($r('app.color.text_primary'))
                    if (record.type === 0) {
                      Text(record.memberName + ' 食用').fontSize(12).fontColor($r('app.color.text_secondary'))
                    } else {
                      Text('丢弃: ' + record.wasteReason).fontSize(12).fontColor('#FF3B30')
                    }
                  }
                  .layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Column({ space: 2 }) {
                    if (record.calories > 0) {
                      Text(record.calories.toFixed(0) + ' kcal')
                        .fontSize(13).fontColor(record.type === 0 ? '#FF6B00' : '#999999')
                    }
                    Text(this.formatRecordTime(record.createTime))
                      .fontSize(11).fontColor($r('app.color.text_disabled'))
                  }
                  .alignItems(HorizontalAlign.End)
                }
                .width('100%').padding({ top: 8, bottom: 8 })
              }, (record: ConsumptionRecord) => record.id.toString())
            }
          }
          .width('100%').padding(16).margin({ left: 16, right: 16, bottom: 16 })
          .backgroundColor($r('app.color.card_background')).borderRadius(16)
        }
      }
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
      .animation({ duration: 260, curve: Curve.EaseInOut })
  }

  @Builder
  buildTimeBtn(label: string, mode: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.viewMode === mode ? Color.White : '#666666')
      .textAlign(TextAlign.Center)
      .layoutWeight(1).height(40)
      .backgroundColor(this.viewMode === mode ? '#007DFF' : '#F0F0F0')
      .borderRadius(8)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.viewMode = mode;
        if (mode !== 'custom') {
          this.loadData();
        }
      })
  }
}
