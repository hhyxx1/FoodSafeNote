import { FoodButtonStyle, FoodJournalMetric, FoodMotion, FOOD_TITLE_BAR_STYLE } from '../common/FoodInterface';
import { resolveLocalizedText } from '../common/Constants';
import { localizedFoodLabel, localizedFoodLabelText } from '../common/Constants';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { AppNavigation } from '../common/AppNavigation';
import { ConsumptionRecord, DailyCalorie, WasteStat } from '../model/DataModels';
import { padZero } from '../common/Constants';

@Component
struct HealthReportPage {
  @State timeRange: string = 'week';
  @State caloriesByMember: DailyCalorie[] = [];
  @State wasteStats: WasteStat[] = [];
  @State missingCalories: number = 0;
  @State records: ConsumptionRecord[] = [];
  @State totalCalories: number = 0;
  @State totalWaste: number = 0;
  @State totalEatCount: number = 0;
  @State isLoading: boolean = true;
  private loadRequest: number = 0;
  @State showDatePicker: boolean = false;
  @State customStart: Date = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  @State customEnd: Date = new Date();
  @State pickingStart: boolean = true;
  private scroller: Scroller = new Scroller();
  // 状态栏高度（vp），由 Index 写入 AppStorage；用于标题栏沉浸避让
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('dataChangeTick') @Watch('onDataChangeTick') dataChangeTick: number = 0;

  aboutToAppear(): void {
    this.loadData();
  }

  private onDataChangeTick(): void {
    void this.loadData();
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
      // 赋新 Date 对象触发 @State 重绘（直接 setHours 改内部字段不触发刷新）
      const start = new Date(this.customStart.getTime());
      start.setHours(0, 0, 0, 0);
      const end = new Date(this.customEnd.getTime());
      end.setHours(23, 59, 59, 999);
      this.customStart = start;
      this.customEnd = end;
      startTime = this.customStart.getTime();
      endTime = this.customEnd.getTime();
    }
    return [startTime, endTime];
  }

  private async loadData(): Promise<void> {
    const request: number = ++this.loadRequest;
    this.isLoading = true;
    const range: number[] = this.getTimeRangeMs();
    const db: DatabaseHelper = DatabaseHelper.getInstance();
    try {
      const data: [DailyCalorie[], ConsumptionRecord[], WasteStat[]] = await Promise.all([
        db.getCaloriesByMemberForRange(range[0], range[1]),
        db.getConsumptionsByRange(range[0], range[1]),
        db.getWasteStatsByCategory(range[0], range[1])
      ]);
      if (request !== this.loadRequest) return;
      const calories: DailyCalorie[] = data[0];
      const records: ConsumptionRecord[] = data[1];
      const waste: WasteStat[] = data[2];

      this.caloriesByMember = calories;
      this.records = records;
      this.missingCalories = records.filter((record: ConsumptionRecord): boolean =>
        record.type === 0 && !record.nutritionKnown).length;
      this.totalCalories = calories.reduce((total: number, row: DailyCalorie) => total + row.totalCalories, 0);
      this.totalEatCount = calories.reduce((total: number, row: DailyCalorie) => total + row.recordCount, 0);
      this.totalWaste = waste.reduce((total: number, row: WasteStat) => total + row.count, 0);
      this.wasteStats = waste;
    } finally {
      if (request === this.loadRequest) this.isLoading = false;
    }
  }

  private formatRecordTime(timestamp: number): string {
    const date = new Date(timestamp);
    return padZero(date.getMonth() + 1) + '-' + padZero(date.getDate()) + ' ' +
      padZero(date.getHours()) + ':' + padZero(date.getMinutes());
  }

  private formatDate(d: Date): string {
    return d.toLocaleDateString();
  }

  private getRangeLabel(): string {
    if (this.timeRange === 'today') return resolveLocalizedText(this.getUIContext().getHostContext(), $r('app.string.watch_today').id);
    if (this.timeRange === 'week') return resolveLocalizedText(this.getUIContext().getHostContext(), $r('app.string.ui_last_7_days').id);
    if (this.timeRange === 'month') return resolveLocalizedText(this.getUIContext().getHostContext(), $r('app.string.ui_last_30_days').id);
    if (this.timeRange === '90d') return resolveLocalizedText(this.getUIContext().getHostContext(), $r('app.string.ui_last_90_days').id);
    if (this.timeRange === 'halfyear') return resolveLocalizedText(this.getUIContext().getHostContext(), $r('app.string.ui_last_six_months').id);
    if (this.timeRange === 'year') return resolveLocalizedText(this.getUIContext().getHostContext(), $r('app.string.ui_last_year').id);
    if (this.timeRange === 'all') return resolveLocalizedText(this.getUIContext().getHostContext(), $r('app.string.ui_all_records').id);
    if (this.timeRange === 'custom') return this.formatDate(this.customStart) + ' ~ ' + this.formatDate(this.customEnd);
    return '';
  }

  build() {
    HdsNavDestination() {
    Column() {
      // 快捷时间选择 - 第一行
      Row({ space: 6 }) {
        this.buildTab($r('app.string.watch_today'), 'today')
        this.buildTab($r('app.string.ui_7_days'), 'week')
        this.buildTab($r('app.string.ui_30_days'), 'month')
        this.buildTab($r('app.string.ui_90_days'), '90d')
      }
      .width('100%').padding({ left: 16, right: 16, top: 8 })

      // 第二行
      Row({ space: 6 }) {
        this.buildTab($r('app.string.ui_six_months'), 'halfyear')
        this.buildTab($r('app.string.ui_one_year'), 'year')
        this.buildTab($r('app.string.ui_all'), 'all')
        this.buildTab($r('app.string.ui_custom'), 'custom')
      }
      .width('100%').padding({ left: 16, right: 16, top: 4, bottom: 4 })

      // 自定义日期选择器
      if (this.timeRange === 'custom') {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Button($r('app.string.ui_from_s', this.formatDate(this.customStart)))
              .attributeModifier(this.pickingStart ? FoodButtonStyle.compactSecondary : FoodButtonStyle.compactNeutral)
              .layoutWeight(1)
              .accessibilitySelected(this.pickingStart)
              .onClick(() => { this.pickingStart = true; })
            Button($r('app.string.ui_to_s', this.formatDate(this.customEnd)))
              .attributeModifier(this.pickingStart ? FoodButtonStyle.compactNeutral : FoodButtonStyle.compactSecondary)
              .layoutWeight(1)
              .accessibilitySelected(!this.pickingStart)
              .onClick(() => { this.pickingStart = false; })
          }
          .width('100%')

          DatePicker({
            start: new Date('2020-01-01'),
            end: new Date(),
            selected: this.pickingStart ? this.customStart : this.customEnd
          })
            .width('100%')
            .height(120)
            .onDateChange((value: Date) => {
              const selected = new Date(value.getFullYear(), value.getMonth(), value.getDate());
              if (this.pickingStart) {
                this.customStart = selected;
                if (selected.getTime() > this.customEnd.getTime()) this.customEnd = selected;
              } else {
                this.customEnd = selected;
                if (selected.getTime() < this.customStart.getTime()) this.customStart = selected;
              }
            })

          Button($r('app.string.ui_search'))
            .attributeModifier(FoodButtonStyle.compactPrimary)
            .width('100%')
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => { this.loadData(); })
        }
        .width('100%').padding({ left: 16, right: 16, bottom: 4 })
        .transition(FoodMotion.reveal())
      }

      Scroll(this.scroller) {
        Column({ space: 16 }) {
          Column({ space: 12 }) {
            Text($r('app.string.ui_s_records_d', this.getRangeLabel(), this.records.length))
              .fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.journal_hero_secondary')).width('100%')
            if (this.missingCalories > 0) {
              Text($r('app.string.intake_missing_calories', this.missingCalories))
                .fontColor($r('app.color.journal_hero_secondary')).fontSize(13).width('100%')
            }
            Row({ space: 10 }) {
              FoodJournalMetric({
                label: $r('app.string.ui_total_intake_kcal'), amount: this.totalCalories.toFixed(0)
              })
              FoodJournalMetric({
                label: $r('app.string.ui_times_eaten'), amount: this.totalEatCount.toString()
              })
              FoodJournalMetric({
                label: $r('app.string.ui_discarded_food'), amount: this.totalWaste.toString()
              })
            }.width('100%')
          }
          .width('100%').padding(18).margin({ left: 16, right: 16, top: 10 })
          .backgroundColor($r('app.color.journal_hero_bg')).borderRadius(20)

          // 成员摄入
          if (this.caloriesByMember.length > 0) {
            Column({ space: 12 }) {
              Text($r('app.string.ui_calorie_intake_by_member'))
                .fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
              ForEach(this.caloriesByMember, (item: DailyCalorie) => {
                Row() {
                  Text(item.memberName.substring(0, 1))
                    .fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.White)
                    .textAlign(TextAlign.Center).width(36).height(36).borderRadius(18)
                    .backgroundColor($r('app.color.button_primary_bg'))
                  Column({ space: 2 }) {
                    Text(item.memberName).fontSize(14).fontColor($r('app.color.text_primary'))
                    Text($r('app.string.ui_times_eaten_d', item.recordCount)).fontSize(13).fontColor($r('app.color.text_hint'))
                  }
                  .layoutWeight(1).padding({ left: 12 }).alignItems(HorizontalAlign.Start)
                  Text(item.totalCalories.toFixed(0) + ' kcal')
                    .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.status_warning'))
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
              Text($r('app.string.ui_food_waste_analysis'))
                .fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
              ForEach(this.wasteStats, (stat: WasteStat) => {
                Row() {
                  Text(localizedFoodLabel(stat.category))
                    .fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
                  Text($r('app.string.inventory_count', stat.count))
                    .fontSize(14).fontColor($r('app.color.status_warning'))
                }
                .width('100%').padding({ top: 6, bottom: 6 })
              }, (stat: WasteStat) => stat.category)
            }
            .width('100%').padding(16).margin({ left: 16, right: 16 })
            .backgroundColor($r('app.color.card_background')).borderRadius(16)
          }

          // 详细记录
          Column({ space: 12 }) {
            Text($r('app.string.ui_detailed_records_d', this.records.length))
              .fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
            if (this.records.length === 0) {
              Text($r('app.string.ui_no_records_for_this_date_range')).fontSize(13).fontColor($r('app.color.text_hint'))
                .width('100%').textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
            } else {
              ForEach(this.records, (record: ConsumptionRecord) => {
                Row() {
                  Image(record.type === 0 ? $r('app.media.icon_eat') : $r('app.media.icon_trash'))
                    .width(16).height(16).margin({ right: 12 }).draggable(false)
                  Column({ space: 2 }) {
                    Text(record.foodName).fontSize(13).fontColor($r('app.color.text_primary'))
                    Text(record.type === 0 ? $r('app.string.ui_eaten_by_s', record.memberName) : $r('app.string.ui_discarded_s', localizedFoodLabelText(this.getUIContext().getHostContext(), record.wasteReason)))
                      .fontSize(13).fontColor(record.type === 0 ? $r('app.color.button_neutral_text') : $r('app.color.status_danger'))
                  }
                  .layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Column({ space: 2 }) {
                    if (record.nutritionKnown) {
                      Text(record.calories.toFixed(0) + ' kcal').fontSize(12).fontColor($r('app.color.status_warning'))
                    } else if (record.type === 0) {
                      Text($r('app.string.intake_missing_calorie_record'))
                        .fontSize(12).fontColor($r('app.color.text_secondary'))
                    }
                    Text(this.formatRecordTime(record.createTime)).fontSize(13).fontColor($r('app.color.text_secondary'))
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
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
    // 标题栏沉浸避让：状态栏高度 + 标题栏高度(56vp)
    .padding({ top: 56 + this.statusBarHeight })
    }
    .titleBar({
      content: {
        title: { mainTitle: $r('app.string.ui_health_report') }
      },
      style: FOOD_TITLE_BAR_STYLE
    })
    .bindToScrollable([this.scroller])
    .onHidden(() => {
      AppNavigation.notifyDataChanged();
    })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  buildTab(label: ResourceStr, type: string) {
    Button(label)
      .attributeModifier(this.timeRange === type ? FoodButtonStyle.compactPrimary : FoodButtonStyle.compactNeutral)
      .layoutWeight(1)
      .accessibilitySelected(this.timeRange === type)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.timeRange = type;
        if (type !== 'custom') {
          this.loadData();
        }
      })
  }
}

// Navigation 系统路由表入口（router_map.json 中注册为 HealthReportPage）
@Builder
export function HealthReportPageBuilder() {
  HealthReportPage()
}
