import { router, promptAction } from '@kit.ArkUI';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';

interface AddFoodParams {
  barcode: string;
  name: string;
  category: string;
  spec: string;
  calories: number;
  fromBarcodeScan: boolean;
}

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
  @State isGenerating: boolean = false;
  @State pasteAuthorized: boolean = false;

  aboutToAppear(): void {
    // 剪贴板读取改为用户点击安全控件触发
  }

  private handlePasteButtonResult(result: PasteButtonOnClickResult): void {
    if (result !== PasteButtonOnClickResult.SUCCESS) {
      promptAction.showToast({ message: '未完成授权，无法读取剪贴板', duration: 1500 });
      return;
    }
    this.pasteAuthorized = true;
    this.readClipboard();
  }

  private readClipboard(): void {
    try {
      const sysBoard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      sysBoard.getData((err: BusinessError, data: pasteboard.PasteData) => {
        if (err) {
          promptAction.showToast({ message: '读取剪贴板失败', duration: 1500 });
          return;
        }
        if (!data || typeof data.getPrimaryText !== 'function') {
          promptAction.showToast({ message: '剪贴板为空或不可读', duration: 1500 });
          return;
        }
        let text: string = '';
        try {
          const maybe = data.getPrimaryText();
          text = (typeof maybe === 'string' ? maybe : (maybe ? String(maybe) : '')) || '';
        } catch (e) {
          text = '';
        }
        if (!text || text.length === 0) {
          promptAction.showToast({ message: '剪贴板为空', duration: 1500 });
          return;
        }
        this.clipboardText = text;
        this.generateCards(text, true);
      });
    } catch (e) {
      promptAction.showToast({ message: '读取剪贴板失败', duration: 1500 });
    }
  }

  private parseEntries(text: string): ParsedFoodEntry[] {
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
    return items;
  }

  private calculateParseConfidence(text: string, items: ParsedFoodEntry[]): number {
    let score: number = 0.3;
    if (text.indexOf('购买完成') >= 0 || text.indexOf('已买') >= 0 || text.indexOf('入库') >= 0 || text.indexOf('采购') >= 0) {
      score = score + 0.35;
    }
    if (text.indexOf('清单') >= 0 || text.indexOf('买菜') >= 0 || text.indexOf('食材') >= 0) {
      score = score + 0.15;
    }
    if (items.length >= 2) {
      score = score + 0.15;
    }
    if (text.indexOf('、') >= 0 || text.indexOf('，') >= 0 || text.indexOf('\n') >= 0) {
      score = score + 0.1;
    }
    if (score > 1) {
      return 1;
    }
    return score;
  }

  private generateCards(text: string, skipConfidenceCheck: boolean = false): void {
    if (this.isGenerating) return;
    this.isGenerating = true;
    const items: ParsedFoodEntry[] = this.parseEntries(text);
    const confidence: number = this.calculateParseConfidence(text, items);
    if (items.length === 0) {
      this.isGenerating = false;
      promptAction.showToast({ message: '未识别到可用的食品名称', duration: 1800 });
      return;
    }

    if (!skipConfidenceCheck && confidence < 0.8) {
      promptAction.showDialog({
        title: '解析置信度较低',
        message: '当前文本不太像购物清单，是否仍生成待入库卡片？',
        buttons: [
          { text: '取消', color: '#999999' },
          { text: '继续生成', color: '#007DFF' }
        ]
      }).then((result: promptAction.ShowDialogSuccessResponse) => {
        if (result.index === 1) {
          this.parsedItems = items;
        }
        this.isGenerating = false;
      }).catch(() => {
        this.isGenerating = false;
      });
      return;
    }

    this.parsedItems = items;
    this.isGenerating = false;
  }

  private addManualItems(): void {
    const text: string = this.manualInput.trim();
    if (text.length === 0) return;
    this.generateCards(text, true);
    this.manualInput = '';
  }

  private continueEntry(): void {
    let selectedIndex: number = -1;
    for (let i = 0; i < this.parsedItems.length; i++) {
      if (this.parsedItems[i].selected) {
        selectedIndex = i;
        break;
      }
    }
    if (selectedIndex < 0) {
      promptAction.showToast({ message: '请至少选择一项', duration: 1500 });
      return;
    }

    this.startEntryForItem(selectedIndex);
  }

  private startEntryForItem(index: number): void {
    if (index < 0 || index >= this.parsedItems.length) return;
    const item: ParsedFoodEntry = this.parsedItems[index];
    if (!item.selected) {
      promptAction.showToast({ message: '该卡片未选中', duration: 1200 });
      return;
    }

    const newList: ParsedFoodEntry[] = [];
    for (let i = 0; i < this.parsedItems.length; i++) {
      const current: ParsedFoodEntry = this.parsedItems[i];
      if (i === index) {
        newList.push({ name: current.name, selected: false, confidence: current.confidence });
      } else {
        newList.push(current);
      }
    }
    this.parsedItems = newList;

    const params: AddFoodParams = {
      barcode: '',
      name: item.name,
      category: '',
      spec: '',
      calories: 0,
      fromBarcodeScan: false
    };
    router.pushUrl({ url: 'pages/AddFoodPage', params: params });
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
          .height(40).fontSize(14).fontColor($r('app.color.accent_link'))
          .backgroundColor(Color.Transparent)
          .onClick(() => { router.back(); })
        Text('剪贴板解析')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          .layoutWeight(1).textAlign(TextAlign.Center)
        Button('继续录入 (' + this.getSelectedCount() + ')')
          .height(40).fontSize(14).fontColor($r('app.color.button_primary_text'))
          .backgroundColor($r('app.color.button_primary_bg')).borderRadius(8)
          .enabled(!this.isGenerating && this.getSelectedCount() > 0)
          .onClick(() => { this.continueEntry(); })
      }
      .width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))

      Scroll() {
        Column({ space: 16 }) {
          // 安全粘贴控件
          Column({ space: 8 }) {
            Text('从系统剪贴板读取（需点击授权）')
              .fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
            Row() {
              PasteButton()
                .padding({ top: 10, bottom: 10, left: 20, right: 20 })
                .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
                  this.handlePasteButtonResult(result);
                })
              if (this.pasteAuthorized) {
                Text('已授权').fontSize(12).fontColor($r('app.color.status_success')).padding({ left: 8 })
              }
            }
            .width('100%')
          }
          .width('100%').padding(16).margin({ left: 16, right: 16, top: 16 })
          .backgroundColor($r('app.color.card_background')).borderRadius(16)

          // 手动输入区
          Column({ space: 8 }) {
            Text('输入购物清单（用逗号、顿号或换行分隔）')
              .fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
            Row({ space: 8 }) {
              TextInput({ text: this.manualInput, placeholder: '如：牛奶、面包、苹果、鸡蛋' })
                .layoutWeight(1).height(40).fontSize(14).borderRadius(8)
                .onChange((value: string) => { this.manualInput = value; })
              Button('解析')
                .height(40).fontSize(14).fontColor($r('app.color.button_primary_text'))
                .backgroundColor($r('app.color.button_primary_bg')).borderRadius(8)
                .onClick(() => { this.addManualItems(); })
            }
          }
          .width('100%').padding(16).margin({ left: 16, right: 16 })
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
            Text('待入库卡片 (' + this.parsedItems.length + ')')
              .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')

            if (this.parsedItems.length === 0) {
              Column({ space: 8 }) {
                Text('📋').fontSize(40)
                Text('手动触发后生成待入库卡片').fontSize(13).fontColor($r('app.color.text_hint'))
              }
              .width('100%').padding({ top: 24, bottom: 24 }).alignItems(HorizontalAlign.Center)
            } else {
              ForEach(this.parsedItems, (item: ParsedFoodEntry, index: number) => {
                Column({ space: 8 }) {
                  Row() {
                    Checkbox()
                      .select(item.selected)
                      .selectedColor($r('app.color.button_primary_bg'))
                      .onChange((value: boolean) => {
                        this.toggleItem(index);
                      })
                    Text(item.name)
                      .fontSize(15).fontColor($r('app.color.text_primary'))
                      .layoutWeight(1).padding({ left: 8 })
                    if (item.confidence < 0.8) {
                      Text('仅供参考')
                        .fontSize(10).fontColor($r('app.color.chip_warning_text'))
                        .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                        .borderRadius(4).backgroundColor($r('app.color.chip_warning_bg'))
                    }
                  }
                  .width('100%')

                  Row() {
                    Text('需继续补充热量、保质期等信息')
                      .fontSize(12).fontColor($r('app.color.text_hint')).layoutWeight(1)
                    Button('加入入库')
                      .height(40).fontSize(12).fontColor($r('app.color.button_secondary_text'))
                      .backgroundColor($r('app.color.button_secondary_bg')).borderRadius(6)
                      .enabled(item.selected)
                      .onClick(() => {
                        this.startEntryForItem(index);
                      })
                  }
                  .width('100%')
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
