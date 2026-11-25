import { FoodButtonStyle, FOOD_PRESS_EFFECT, FoodJournalMetric, FoodMotion } from '../common/FoodInterface';
import { resolveLocalizedText } from '../common/Constants';
import { localizedFoodLabel, localizedFoodLabelText } from '../common/Constants';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { AppNavigation } from '../common/AppNavigation';
import { ConsumptionRecord, DailyCalorie, WasteStat } from '../model/DataModels';
import { padZero } from '../common/Constants';

@Component
export struct HealthView {
  @Prop @Watch('onRefreshKeyChange') refreshKey: number = 0;
  @Prop tabBarInset: number = 0;
  @State dailyCalories: DailyCalorie[] = [];
  @State missingCalories: number = 0;
  @State todayRecords: ConsumptionRecord[] = [];
  @State wasteStats: WasteStat[] = [];
  @State isLoading: boolean = true;
  private loadRequest: number = 0;
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
      // 赋新 Date 对象触发 @State 重绘（直接 setHours 改内部字段不触发刷新）
      const start = new Date(this.customStart.getTime());
      start.setHours(0, 0, 0, 0);
      const end = new Date(this.customEnd.getTime());
      end.setHours(23, 59, 59, 999);
      this.customStart = start;
      this.customEnd = end;
      startTime = this.customStart.getTime();
      return [startTime, this.customEnd.getTime()];
    }
    return [startTime, endTime];
  }

  private async loadData(): Promise<void> {
    const request: number = ++this.loadRequest;
    this.isLoading = true;
    const range: number[] = this.getTimeRange();
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

      this.dailyCalories = calories;
      this.todayRecords = records;
      this.missingCalories = records.filter((record: ConsumptionRecord): boolean =>
        record.type === 0 && !record.nutritionKnown).length;
      this.wasteStats = waste;
    } finally {
      if (request === this.loadRequest) this.isLoading = false;
    }
  }

  private getTodayString(): string {
    const now = new Date();
    return now.toLocaleDateString();
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
    return d.toLocaleDateString();
  }

  private getViewModeLabel(): string {
    if (this.viewMode === 'today') return resolveLocalizedText(this.getUIContext().getHostContext(), $r('app.string.watch_today').id);
    if (this.viewMode === 'week') return resolveLocalizedText(this.getUIContext().getHostContext(), $r('app.string.ui_last_7_days').id);
    if (this.viewMode === 'month') return resolveLocalizedText(this.getUIContext().getHostContext(), $r('app.string.ui_last_30_days').id);
    if (this.viewMode === 'custom') return this.formatDate(this.customStart) + ' ~ ' + this.formatDate(this.customEnd);
    return '';
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text($r('app.string.ui_health_dashboard'))
          .fontSize(29).lineHeight(36).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary')).layoutWeight(1)
        Button($r('app.string.ui_detailed_report'))
          .attributeModifier(FoodButtonStyle.compactSecondary)
          .onClick(() => { AppNavigation.push('HealthReportPage'); })
      }
      .width('100%').padding({ left: 20, right: 20, top: 14, bottom: 4 })

      Column() {
        Row({ space: 3 }) {
          this.buildTimeBtn($r('app.string.watch_today'), 'today')
          this.buildTimeBtn($r('app.string.ui_last_7_days'), 'week')
          this.buildTimeBtn($r('app.string.ui_last_30_days'), 'month')
          this.buildTimeBtn($r('app.string.ui_custom'), 'custom')
        }
        .padding(4).backgroundColor($r('app.color.chip_background')).borderRadius(26)
        .width('100%')
      }
      .width('100%').padding({ left: 20, right: 20 })

      // 自定义日期选择区
      if (this.viewMode === 'custom' && this.showDatePicker) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Button($r('app.string.ui_start_s', this.formatDate(this.customStart)))
              .attributeModifier(this.pickingStart ? FoodButtonStyle.compactSecondary : FoodButtonStyle.compactNeutral)
              .layoutWeight(1)
              .accessibilitySelected(this.pickingStart)
              .onClick(() => { this.pickingStart = true; })
            Button($r('app.string.ui_end_s', this.formatDate(this.customEnd)))
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
            .onClick(() => {
              this.showDatePicker = false;
              this.loadData();
            })
        }
        .width('100%').padding(12)
        .margin({ left: 20, right: 20 })
        .backgroundColor($r('app.color.card_background')).borderRadius(16)
        .transition(FoodMotion.reveal())
      }

      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 13 }) {
            Text($r('app.string.ui_s_records_d', this.getViewModeLabel(), this.todayRecords.length))
              .fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.journal_hero_secondary')).width('100%')
            if (this.missingCalories > 0) {
              Text($r('app.string.intake_missing_calories', this.missingCalories))
                .fontColor($r('app.color.journal_hero_secondary')).fontSize(13).width('100%')
            }
            Row({ space: 18 }) {
              FoodJournalMetric({
                label: $r('app.string.ui_intake_kcal'), amount: this.getTotalCalories().toFixed(0)
              })
              Column().width(1).height(44).backgroundColor($r('app.color.journal_hero_divider'))
              FoodJournalMetric({
                label: $r('app.string.ui_discarded_items'), amount: this.getTotalWasteCount().toString()
              })
            }
            .width('100%')
          }
          .width('100%').padding(20)
          .backgroundColor($r('app.color.journal_hero_bg')).borderRadius(22)

          // 成员摄入
          if (this.dailyCalories.length > 0) {
            Column({ space: 12 }) {
              Text($r('app.string.ui_intake_by_family_member'))
                .fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
              ForEach(this.dailyCalories, (item: DailyCalorie) => {
                Row() {
                  Text(item.memberName.substring(0, 1))
                    .fontSize(16).fontWeight(FontWeight.Bold).fontColor(Color.White)
                    .textAlign(TextAlign.Center).width(40).height(40).borderRadius(20)
                    .backgroundColor($r('app.color.button_primary_bg'))
                  Column({ space: 4 }) {
                    Text(item.memberName).fontSize(15).fontColor($r('app.color.text_primary'))
                    Text($r('app.string.ui_times_eaten_d', item.recordCount)).fontSize(12).fontColor($r('app.color.text_hint'))
                  }
                  .layoutWeight(1).alignItems(HorizontalAlign.Start).padding({ left: 12 })
                  Text(item.totalCalories.toFixed(0) + ' kcal')
                    .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.status_warning'))
                }
                .width('100%').padding({ top: 8, bottom: 8 })
              }, (item: DailyCalorie) => item.memberName)
            }
            .width('100%').padding(16)
            .backgroundColor($r('app.color.card_background')).borderRadius(16)
          }

          // 浪费统计
          if (this.wasteStats.length > 0) {
            Column({ space: 8 }) {
              Text($r('app.string.ui_waste_statistics')).fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
              ForEach(this.wasteStats, (stat: WasteStat) => {
                Row() {
                  Image($r('app.media.icon_trash')).width(14).height(14).draggable(false).margin({ right: 10 })
                  Text(localizedFoodLabel(stat.category)).fontSize(13).fontColor($r('app.color.text_primary')).layoutWeight(1)
                  Text($r('app.string.inventory_count', stat.count)).fontSize(13).fontColor($r('app.color.status_warning'))
                }
                .width('100%').padding({ top: 4, bottom: 4 })
              }, (stat: WasteStat) => stat.category)
            }
            .width('100%').padding(16)
            .backgroundColor($r('app.color.card_background')).borderRadius(16)
          }

          // 记录列表
          Column({ space: 12 }) {
            Text($r('app.string.ui_consumption_history'))
              .fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
            if (this.todayRecords.length === 0) {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.clock'))
                  .fontSize(23).fontColor([$r('app.color.accent_link')])
                Text($r('app.string.ui_no_records_for_this_date_range'))
                  .fontSize(14).fontColor($r('app.color.text_secondary')).layoutWeight(1)
              }
              .width('100%').padding({ top: 9, bottom: 8 })
            } else {
              ForEach(this.todayRecords, (record: ConsumptionRecord) => {
                Row() {
                  Image(record.type === 0 ? $r('app.media.icon_eat') : $r('app.media.icon_trash'))
                    .width(20).height(20).margin({ right: 12 }).draggable(false)
                  Column({ space: 2 }) {
                    Text(record.foodName).fontSize(14).fontColor($r('app.color.text_primary'))
                    if (record.type === 0) {
                      Text($r('app.string.ui_eaten_by_s', record.memberName)).fontSize(12).fontColor($r('app.color.text_secondary'))
                    } else {
                      Text($r('app.string.ui_discarded_s', localizedFoodLabelText(this.getUIContext().getHostContext(), record.wasteReason))).fontSize(12).fontColor($r('app.color.status_danger'))
                    }
                  }
                  .layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Column({ space: 2 }) {
                    if (record.nutritionKnown) {
                      Text(record.calories.toFixed(0) + ' kcal')
                        .fontSize(13).fontColor(record.type === 0 ? $r('app.color.status_warning') : $r('app.color.text_disabled'))
                    } else if (record.type === 0) {
                      Text($r('app.string.intake_missing_calorie_record'))
                        .fontSize(12).fontColor($r('app.color.text_secondary'))
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
          .width('100%').padding(16).margin({ bottom: 8 })
          .backgroundColor($r('app.color.card_background')).borderRadius(16)
        }
        .padding({ left: 20, right: 20, top: 4, bottom: this.tabBarInset })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }

  @Builder
  buildTimeBtn(label: ResourceStr, mode: string) {
    Button(label)
      .type(ButtonType.Capsule)
      .fontSize(13).fontWeight(FontWeight.Medium)
      .fontColor(this.viewMode === mode ? $r('app.color.accent_link') : $r('app.color.text_secondary'))
      .layoutWeight(1).height(44)
      .padding({ left: 3, right: 3 })
      .backgroundColor(this.viewMode === mode ? $r('app.color.card_background') : Color.Transparent)
      .accessibilitySelected(this.viewMode === mode)
      .clickEffect(FOOD_PRESS_EFFECT)
      .onClick(() => {
        this.getUIContext().animateTo({ duration: 170, curve: Curve.EaseOut }, () => {
          this.viewMode = mode;
          this.showDatePicker = mode === 'custom';
        });
        this.loadData();
      })
  }
}
