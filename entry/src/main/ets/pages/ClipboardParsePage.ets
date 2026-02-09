import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { FoodItem } from '../model/DataModels';
import { StorageType, calculateExpiryTimestamp } from '../common/Constants';

// 解析出的食品条目
interface ParsedFoodEntry {
  name: string;
  selected: boolean;
  confidence: number;
}

@Entry
@Component
struct ClipboardParsePage {
  @State clipboardText: string = '';
  @State parsedItems: ParsedFoodEntry[] = [];
  @State manualInput: string = '';
  @State isSaving: boolean = false;

  aboutToAppear(): void {
    this.readClipboard();
  }

  private readClipboard(): void {
    try {
      const sysBoard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      sysBoard.getData().then((data: pasteboard.PasteData) => {
        if (data.getRecordCount() > 0) {
          const record: pasteboard.PasteDataRecord = data.getRecord(0);
          const text: string = record.plainText !== undefined ? record.plainText : '';
          if (text.length > 0) {
            this.clipboardText = text;
            this.parseText(text);
          }
        }
      });
    } catch (e) {
      // 剪贴板读取失败
    }
  }

  private parseText(text: string): void {
    // 按换行、逗号、顿号分割
    const lines: string[] = text.split('\n');
    const items: ParsedFoodEntry[] = [];
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      if (line.length === 0) continue;
      // 进一步按逗号和顿号分割
      const parts: string[] = [];
      let current: string = '';
      for (let j = 0; j < line.length; j++) {
        const ch: string = line[j];
        if (ch === ',' || ch === '，' || ch === '、' || ch === ';' || ch === '；') {
          if (current.trim().length > 0) {
            parts.push(current.trim());
          }
          current = '';
        } else {
          current = current + ch;
        }
      }
      if (current.trim().length > 0) {
        parts.push(current.trim());
      }
      for (let k = 0; k < parts.length; k++) {
        const name: string = parts[k];
        // 过滤纯数字和过短的
        if (name.length >= 1 && name.length <= 20) {
          const entry: ParsedFoodEntry = { name: name, selected: true, confidence: name.length >= 2 ? 0.9 : 0.5 };
          items.push(entry);
        }
      }
    }
    this.parsedItems = items;
  }

  private addManualItems(): void {
    const text: string = this.manualInput.trim();
    if (text.length === 0) return;
    this.parseText(text);
    this.manualInput = '';
  }

  private async batchSave(): Promise<void> {
    if (this.isSaving) return;
    this.isSaving = true;
    let savedCount: number = 0;
    const db: DatabaseHelper = DatabaseHelper.getInstance();
    for (let i = 0; i < this.parsedItems.length; i++) {
      if (this.parsedItems[i].selected) {
        const food = new FoodItem();
        food.name = this.parsedItems[i].name;
        food.storageType = StorageType.FRIDGE;
        food.expiryDate = calculateExpiryTimestamp('其他', StorageType.FRIDGE);
        food.status = 0;
        await db.insertFoodItem(food);
        savedCount++;
      }
    }
    this.isSaving = false;
    if (savedCount > 0) {
      promptAction.showToast({ message: '成功入库 ' + savedCount + ' 件食品', duration: 2000 });
      router.back();
    } else {
      promptAction.showToast({ message: '请至少选择一项', duration: 1500 });
    }
  }

  private getSelectedCount(): number {
    let count: number = 0;
    for (let i = 0; i < this.parsedItems.length; i++) {
      if (this.parsedItems[i].selected) count++;
    }
    return count;
  }

  private toggleItem(index: number): void {
    const newList: ParsedFoodEntry[] = [];
    for (let i = 0; i < this.parsedItems.length; i++) {
      const item: ParsedFoodEntry = this.parsedItems[i];
      if (i === index) {
        const toggled: ParsedFoodEntry = { name: item.name, selected: !item.selected, confidence: item.confidence };
        newList.push(toggled);
      } else {
        newList.push(item);
      }
    }
    this.parsedItems = newList;
  }

  build() {
    Column() {
      // 导航栏
      Row() {
        Button('返回')
          .height(36).fontSize(14).fontColor('#007DFF')
          .backgroundColor(Color.Transparent)
          .onClick(() => { router.back(); })
        Text('批量添加')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          .layoutWeight(1).textAlign(TextAlign.Center)
        Button('入库 (' + this.getSelectedCount() + ')')
          .height(36).fontSize(14).fontColor(Color.White)
          .backgroundColor('#007DFF').borderRadius(8)
          .enabled(!this.isSaving && this.getSelectedCount() > 0)
          .onClick(() => { this.batchSave(); })
      }
      .width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))

      Scroll() {
        Column({ space: 16 }) {
          // 手动输入区
          Column({ space: 8 }) {
            Text('输入食品名称（用逗号、顿号分隔）')
              .fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
            Row({ space: 8 }) {
              TextInput({ text: this.manualInput, placeholder: '如：牛奶、面包、苹果、鸡蛋' })
                .layoutWeight(1).height(40).fontSize(14).borderRadius(8)
                .onChange((value: string) => { this.manualInput = value; })
              Button('解析')
                .height(40).fontSize(14).fontColor(Color.White)
                .backgroundColor('#007DFF').borderRadius(8)
                .onClick(() => { this.addManualItems(); })
            }
          }
          .width('100%').padding(16).margin({ left: 16, right: 16, top: 16 })
          .backgroundColor($r('app.color.card_background')).borderRadius(16)

          // 剪贴板内容（如有）
          if (this.clipboardText.length > 0) {
            Column({ space: 8 }) {
              Text('从剪贴板识别')
                .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
              Text(this.clipboardText)
                .fontSize(12).fontColor($r('app.color.text_hint'))
                .width('100%').maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%').padding(16).margin({ left: 16, right: 16 })
            .backgroundColor($r('app.color.card_background')).borderRadius(16)
          }

          // 解析结果列表
          Column({ space: 8 }) {
            Text('待入库食品 (' + this.parsedItems.length + ')')
              .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')

            if (this.parsedItems.length === 0) {
              Column({ space: 8 }) {
                Text('📋').fontSize(40)
                Text('输入或粘贴食品列表后解析').fontSize(13).fontColor($r('app.color.text_hint'))
              }
              .width('100%').padding({ top: 24, bottom: 24 }).alignItems(HorizontalAlign.Center)
            } else {
              ForEach(this.parsedItems, (item: ParsedFoodEntry, index: number) => {
                Row() {
                  Checkbox()
                    .select(item.selected)
                    .selectedColor('#007DFF')
                    .onChange((value: boolean) => {
                      this.toggleItem(index);
                    })
                  Text(item.name)
                    .fontSize(15).fontColor($r('app.color.text_primary'))
                    .layoutWeight(1).padding({ left: 8 })
                  if (item.confidence < 0.8) {
                    Text('仅供参考')
                      .fontSize(10).fontColor('#FF9500')
                      .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                      .borderRadius(4).backgroundColor('#FFF3E0')
                  }
                }
                .width('100%').padding({ top: 8, bottom: 8 })
              }, (item: ParsedFoodEntry, index: number) => index.toString())
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
}
