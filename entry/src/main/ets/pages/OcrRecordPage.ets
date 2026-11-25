import { FoodButtonStyle, FoodMotion, FOOD_TITLE_BAR_STYLE } from '../common/FoodInterface';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { AppNavigation } from '../common/AppNavigation';
import { OcrRecord } from '../model/DataModels';
import { formatTimestampFull } from '../common/Constants';

@Component
struct OcrRecordPage {
  @State records: OcrRecord[] = [];
  @State filterDays: number = 30;
  @State searchName: string = '';
  @State isLoading: boolean = true;
  private loadRequest: number = 0;
  @State isSavingEdit: boolean = false;
  @State showEditDialog: boolean = false;
  @State editRecordId: number = 0;
  @State editFinalValue: string = '';
  private scroller: Scroller = new Scroller();
  // 状态栏高度（vp），由 Index 写入 AppStorage；用于标题栏沉浸避让
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  aboutToAppear(): void {
    this.loadData();
  }

  private loadData(): void {
    const request: number = ++this.loadRequest;
    this.isLoading = true;
    DatabaseHelper.getInstance().searchOcrRecords(this.filterDays, this.searchName).then((records: OcrRecord[]) => {
      if (request !== this.loadRequest) return;
      this.records = records;
      this.isLoading = false;
    }).catch(() => {
      if (request === this.loadRequest) this.isLoading = false;
    });
  }

  private openEditDialog(record: OcrRecord): void {
    this.editRecordId = record.id;
    this.editFinalValue = record.finalValue.toString();
    this.showEditDialog = true;
  }

  private saveEdit(): void {
    if (this.isSavingEdit) return;
    const input: string = this.editFinalValue.trim();
    const newValue: number = Number(input);
    if (input.length === 0 || !Number.isFinite(newValue) || newValue < 0) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_enter_a_valid_energy_value') });
      return;
    }
    this.isSavingEdit = true;
    DatabaseHelper.getInstance().updateOcrRecord(this.editRecordId, newValue).then((updated: boolean) => {
      if (!updated) throw new Error('OCR record was not updated');
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_updated'), duration: 1500 });
      this.showEditDialog = false;
      this.loadData();
    }).catch(() => {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_could_not_save_try_again') });
    }).finally(() => {
      this.isSavingEdit = false;
    });
  }

  build() {
    HdsNavDestination() {
    Stack() {
      Column() {
        // 原标题栏右侧的记录总数文本（Navigation 迁移后移入内容区展示）
        Text($r('app.string.ui_records_d', this.records.length))
          .fontSize(13).fontColor($r('app.color.text_hint'))
          .width('100%').textAlign(TextAlign.End)
          .padding({ left: 16, right: 16, top: 8 })

        // 时间筛选
        Row({ space: 0 }) {
          this.buildDayTab($r('app.string.ui_7_days'), 7)
          this.buildDayTab($r('app.string.ui_15_days'), 15)
          this.buildDayTab($r('app.string.ui_30_days'), 30)
        }
        .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        // 名称搜索
        Row({ space: 8 }) {
          TextInput({ text: this.searchName, placeholder: $r('app.string.ui_search_food_names') })
            .layoutWeight(1).height(46).fontSize(15).borderRadius(14)
            .placeholderColor($r('app.color.text_hint')).fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.input_background'))
            .onChange((value: string) => {
              this.searchName = value;
              this.loadData();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 4 })
        .backgroundColor($r('app.color.card_background'))

        // 说明
        Row() {
          Row({ space: 6 }) {
            Image($r('app.media.icon_info')).width(14).height(14).draggable(false)
            Text($r('app.string.ui_review_and_edit_previous_nutrition_label_scans'))
              .fontSize(13).fontColor($r('app.color.text_hint')).layoutWeight(1)
          }
          .width('100%')
        }
        .width('100%').padding({ left: 16, right: 16, top: 4, bottom: 4 })

        // 记录列表
        if (this.records.length === 0 && !this.isLoading) {
          Scroll() {
            Column({ space: 8 }) {
              Image($r('app.media.icon_search')).width(48).height(48).draggable(false)
              Text($r('app.string.ui_no_ocr_records')).fontSize(14).fontColor($r('app.color.text_hint'))
              Text($r('app.string.ui_records_appear_here_after_you_scan_food_and_enter_calories'))
                .fontSize(13).fontColor($r('app.color.text_disabled')).textAlign(TextAlign.Center)
            }
            .width('100%')
            .padding({ left: 32, right: 32 })
          }
          .width('100%').layoutWeight(1).align(Alignment.Center)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        } else {
          List({ space: 8, scroller: this.scroller }) {
            ForEach(this.records, (record: OcrRecord) => {
              ListItem() {
                this.buildRecordCard(record)
              }
            }, (record: OcrRecord) => record.id.toString())
          }
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .width('100%').layoutWeight(1)
          .padding({ left: 16, right: 16, top: 8, bottom: 16 })
        }
      }
      .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
      // 标题栏沉浸避让：状态栏高度 + 标题栏高度(56vp)
      .padding({ top: 56 + this.statusBarHeight })

      // 修改弹窗
      if (this.showEditDialog) {
        Column() {
          Column()
            .width('100%').height('100%').backgroundColor($r('app.color.overlay_background'))
            .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
            .onClick(() => { this.showEditDialog = false; })
        }
        .width('100%').height('100%').position({ x: 0, y: 0 })

        Column({ space: 16 }) {
          Text($r('app.string.ui_edit_calories'))
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
          Column({ space: 4 }) {
            Text($r('app.string.ui_confirmed_calories_kcal'))
              .fontSize(13).fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.editFinalValue, placeholder: $r('app.string.ui_enter_calories') })
              .width('100%').height(44).fontSize(15).borderRadius(8)
              .backgroundColor($r('app.color.input_background')).type(InputType.Number)
              .onChange((value: string) => { this.editFinalValue = value; })
          }
          Row({ space: 12 }) {
            Button($r('app.string.ui_cancel'))
              .attributeModifier(FoodButtonStyle.neutral)
              .layoutWeight(1)
              .onClick(() => { this.showEditDialog = false; })
            Button($r('app.string.ui_save'))
              .attributeModifier(FoodButtonStyle.primary)
              .layoutWeight(1)
              .onClick(() => { this.saveEdit(); })
          }.width('100%')
        }
        .width('85%').constraintSize({ minWidth: 320, maxWidth: 560 }).padding(20).backgroundColor($r('app.color.card_background')).borderRadius(16)
        .transition(FoodMotion.panel())
        .position({ x: '7.5%', y: '30%' })
      }
    }
    .width('100%').height('100%')
    .animation({ duration: 260, curve: Curve.EaseInOut })
    }
    .titleBar({
      content: {
        title: { mainTitle: $r('app.string.ui_ocr_history') }
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
  buildDayTab(label: ResourceStr, days: number) {
    Text(label)
      .fontSize(14)
      .fontColor(this.filterDays === days ? $r('app.color.button_primary_text') : $r('app.color.button_neutral_text'))
      .textAlign(TextAlign.Center)
      .layoutWeight(1).height(40)
      .backgroundColor(this.filterDays === days ? $r('app.color.button_primary_bg') : $r('app.color.button_neutral_bg'))
      .borderRadius(8)
      .onClick(() => {
        this.filterDays = days;
        this.loadData();
      })
  }

  @Builder
  buildRecordCard(record: OcrRecord) {
    Column({ space: 6 }) {
      Row() {
        Text(record.foodName)
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(formatTimestampFull(record.createTime))
          .fontSize(13).fontColor($r('app.color.text_hint'))
      }.width('100%')

      if (record.barcode.length > 0) {
        Text($r('app.string.ui_barcode_s', record.barcode))
          .fontSize(13).fontColor($r('app.color.text_hint'))
      }

      Row({ space: 16 }) {
        Column({ space: 2 }) {
          Text($r('app.string.ui_detected_value')).fontSize(13).fontColor($r('app.color.text_hint'))
          Text(record.ocrValue > 0 ? record.ocrValue.toFixed(0) + ' kcal' : $r('app.string.ui_none'))
            .fontSize(14).fontColor(record.ocrValue > 0 ? $r('app.color.status_info') : $r('app.color.text_disabled'))
        }
        Column({ space: 2 }) {
          Text($r('app.string.ui_confirmed_value')).fontSize(13).fontColor($r('app.color.text_hint'))
          Text(record.finalValue > 0 ? record.finalValue.toFixed(0) + ' kcal' : '0')
            .fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(record.finalValue > 0 ? $r('app.color.status_warning') : $r('app.color.text_disabled'))
        }
        .layoutWeight(1)

        Button($r('app.string.ui_change'))
          .attributeModifier(FoodButtonStyle.compactSecondary)
          .onClick(() => { this.openEditDialog(record); })
      }.width('100%')
    }
    .width('100%').padding(12).backgroundColor($r('app.color.card_background')).borderRadius(12)
  }
}

// Navigation 系统路由表入口（router_map.json 中注册为 OcrRecordPage）
@Builder
export function OcrRecordPageBuilder() {
  OcrRecordPage()
}