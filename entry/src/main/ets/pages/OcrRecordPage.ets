import { router, promptAction } from '@kit.ArkUI';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { OcrRecord } from '../model/DataModels';
import { formatTimestampFull } from '../common/Constants';

@Entry
@Component
struct OcrRecordPage {
  @State records: OcrRecord[] = [];
  @State filterDays: number = 30;
  @State searchName: string = '';
  @State isLoading: boolean = true;
  @State showEditDialog: boolean = false;
  @State editRecordId: number = 0;
  @State editFinalValue: string = '';

  aboutToAppear(): void {
    this.loadData();
  }

  private loadData(): void {
    this.isLoading = true;
    DatabaseHelper.getInstance().searchOcrRecords(this.filterDays, this.searchName).then((records: OcrRecord[]) => {
      this.records = records;
      this.isLoading = false;
    });
  }

  private openEditDialog(record: OcrRecord): void {
    this.editRecordId = record.id;
    this.editFinalValue = record.finalValue.toString();
    this.showEditDialog = true;
  }

  private saveEdit(): void {
    const newValue: number = Number(this.editFinalValue) || 0;
    DatabaseHelper.getInstance().updateOcrRecord(this.editRecordId, newValue).then(() => {
      promptAction.showToast({ message: '已更新', duration: 1500 });
      this.showEditDialog = false;
      this.loadData();
    });
  }

  build() {
    Stack() {
      Column() {
        // 导航栏
        Row() {
          Button('返回')
            .height(36).fontSize(14).fontColor('#007DFF')
            .backgroundColor(Color.Transparent)
            .onClick(() => { router.back(); })
          Text('OCR记录')
            .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            .layoutWeight(1).textAlign(TextAlign.Center)
          Text(this.records.length + '条')
            .fontSize(13).fontColor($r('app.color.text_hint')).width(56).textAlign(TextAlign.Center)
        }
        .width('100%')        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        // 时间筛选
        Row({ space: 0 }) {
          this.buildDayTab('7天', 7)
          this.buildDayTab('15天', 15)
          this.buildDayTab('30天', 30)
        }
        .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        // 名称搜索
        Row({ space: 8 }) {
          TextInput({ text: this.searchName, placeholder: '搜索食品名称' })
            .layoutWeight(1).height(40).fontSize(14).borderRadius(20)
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
          Text('💡 记录热量识别和校验历史，可回溯修改')
            .fontSize(12).fontColor($r('app.color.text_hint'))
        }
        .width('100%').padding({ left: 16, right: 16, top: 4, bottom: 4 })

        // 记录列表
        if (this.records.length === 0 && !this.isLoading) {
          Column({ space: 8 }) {
            Text('🔍').fontSize(48)
            Text('暂无OCR记录').fontSize(14).fontColor($r('app.color.text_hint'))
            Text('通过扫码入库并设置热量后，记录将显示在这里')
              .fontSize(12).fontColor($r('app.color.text_disabled')).textAlign(TextAlign.Center)
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
          .padding({ left: 32, right: 32 })
        } else {
          List({ space: 8 }) {
            ForEach(this.records, (record: OcrRecord) => {
              ListItem() {
                this.buildRecordCard(record)
              }
            }, (record: OcrRecord) => record.id.toString())
          }
          .width('100%').layoutWeight(1)
          .padding({ left: 16, right: 16, top: 8, bottom: 16 })
        }
      }
      .width('100%').height('100%').backgroundColor($r('app.color.page_background'))

      // 修改弹窗
      if (this.showEditDialog) {
        Column() {
          Column()
            .width('100%').height('100%').backgroundColor('#80000000')
            .onClick(() => { this.showEditDialog = false; })
        }
        .width('100%').height('100%').position({ x: 0, y: 0 })

        Column({ space: 16 }) {
          Text('修改热量值')
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
          Column({ space: 4 }) {
            Text('最终确认热量 (kcal)')
              .fontSize(13).fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.editFinalValue, placeholder: '输入热量值' })
              .width('100%').height(44).fontSize(15).borderRadius(8)
              .backgroundColor($r('app.color.input_background')).type(InputType.Number)
              .onChange((value: string) => { this.editFinalValue = value; })
          }
          Row({ space: 12 }) {
            Button('取消').layoutWeight(1).height(40).fontSize(14)
              .fontColor($r('app.color.text_secondary')).backgroundColor($r('app.color.chip_background')).borderRadius(8)
              .onClick(() => { this.showEditDialog = false; })
            Button('保存').layoutWeight(1).height(40).fontSize(14)
              .fontColor(Color.White).backgroundColor('#007DFF').borderRadius(8)
              .onClick(() => { this.saveEdit(); })
          }.width('100%')
        }
        .width('85%').padding(20).backgroundColor($r('app.color.card_background')).borderRadius(16)
        .position({ x: '7.5%', y: '30%' })
      }
    }
    .width('100%').height('100%')
  }

  @Builder
  buildDayTab(label: string, days: number) {
    Text(label)
      .fontSize(14)
      .fontColor(this.filterDays === days ? Color.White : '#666666')
      .textAlign(TextAlign.Center)
      .layoutWeight(1).height(36)
      .backgroundColor(this.filterDays === days ? '#007DFF' : '#F0F0F0')
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
          .fontSize(11).fontColor($r('app.color.text_hint'))
      }.width('100%')

      if (record.barcode.length > 0) {
        Text('条码: ' + record.barcode)
          .fontSize(12).fontColor($r('app.color.text_hint'))
      }

      Row({ space: 16 }) {
        Column({ space: 2 }) {
          Text('AI识别值').fontSize(11).fontColor($r('app.color.text_hint'))
          Text(record.ocrValue > 0 ? record.ocrValue.toFixed(0) + ' kcal' : '无')
            .fontSize(14).fontColor(record.ocrValue > 0 ? '#007DFF' : '#CCCCCC')
        }
        Column({ space: 2 }) {
          Text('最终确认值').fontSize(11).fontColor($r('app.color.text_hint'))
          Text(record.finalValue > 0 ? record.finalValue.toFixed(0) + ' kcal' : '0')
            .fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(record.finalValue > 0 ? '#FF6B00' : '#CCCCCC')
        }
        .layoutWeight(1)

        Button('修改')
          .height(28).fontSize(11).fontColor('#007DFF')
          .backgroundColor('#E8F0FE').borderRadius(6)
          .onClick(() => { this.openEditDialog(record); })
      }.width('100%')
    }
    .width('100%').padding(12).backgroundColor($r('app.color.card_background')).borderRadius(12)
  }
}
