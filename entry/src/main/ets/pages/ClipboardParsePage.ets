import { FoodButtonStyle, FOOD_TITLE_BAR_STYLE } from '../common/FoodInterface';
import { promptAction } from '@kit.ArkUI';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { HdsNavDestination, HdsNavigationBadgeIconOptions, TextStyleMode } from '@kit.UIDesignKit';
import { AppNavigation } from '../common/AppNavigation';

interface AddFoodParams {
  barcode: string;
  name: string;
  category: string;
  spec: string;
  calories: number;
  fromBarcodeScan: boolean;
  fromClipboardParse?: boolean;
  clipboardSourceIndex?: number;
}

// 解析出的食品条目
interface ParsedFoodEntry {
  name: string;
  selected: boolean;
  confidence: number;
}

@Component
struct ClipboardParsePage {
  @StorageProp('dataChangeTick') @Watch('onDataChangeTick') dataChangeTick: number = 0;
  @State clipboardText: string = '';
  @State parsedItems: ParsedFoodEntry[] = [];
  @State manualInput: string = '';
  @State isGenerating: boolean = false;
  @State pasteAuthorized: boolean = false;

  // 状态栏高度（vp），由 Index 写入 AppStorage；用于标题栏沉浸避让
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    // 剪贴板读取改为用户点击安全控件触发
  }

  // 页面返回（含系统侧滑）后消费已完成卡片，等价于原 onPageShow
  private onDataChangeTick(): void {
    this.consumeCompletedClipboardCard();
  }

  private consumeCompletedClipboardCard(): void {
    const completedIndex: number | undefined = AppStorage.get<number>('clipboardEntryCompletedIndex');
    if (completedIndex === undefined || completedIndex < 0) {
      return;
    }

    if (completedIndex >= this.parsedItems.length) {
      AppStorage.setOrCreate<number>('clipboardEntryCompletedIndex', -1);
      return;
    }

    const newList: ParsedFoodEntry[] = [];
    for (let i = 0; i < this.parsedItems.length; i++) {
      if (i !== completedIndex) {
        newList.push(this.parsedItems[i]);
      }
    }
    this.parsedItems = newList;
    AppStorage.setOrCreate<number>('clipboardEntryCompletedIndex', -1);
  }

  private handlePasteButtonResult(result: PasteButtonOnClickResult): void {
    if (result !== PasteButtonOnClickResult.SUCCESS) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_clipboard_access_was_not_granted'), duration: 1500 });
      } catch (e) {
        // Toast 展示失败时忽略
      }
      return;
    }
    this.pasteAuthorized = true;
    this.readClipboard();
  }

  private readClipboard(): void {
    try {
      const sysBoard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      // 此方法仅在 PasteButton 授权成功后调用，使用系统提供的临时剪贴板读取权限。
      sysBoard.getData((err: BusinessError, data: pasteboard.PasteData) => {
        if (err) {
          this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_could_not_read_the_clipboard'), duration: 1500 });
          return;
        }
        if (!data || typeof data.getPrimaryText !== 'function') {
          this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_the_clipboard_is_empty_or_unreadable'), duration: 1500 });
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
          this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_the_clipboard_is_empty'), duration: 1500 });
          return;
        }
        this.clipboardText = text;
        this.generateCards(text, true);
      });
    } catch (e) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_could_not_read_the_clipboard'), duration: 1500 });
      } catch (e) {
        // Toast 展示失败时忽略
      }
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
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_no_food_name_could_be_identified'), duration: 1800 });
      } catch (e) {
        // Toast 展示失败时忽略
      }
      return;
    }

    if (!skipConfidenceCheck && confidence < 0.8) {
      this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.ui_check_the_shopping_list'),
        message: $r('app.string.ui_this_text_may_not_be_a_shopping_list_create_draft_entries_anyway'),
        buttons: [
          { text: $r('app.string.ui_cancel'), color: '#999999' },
          { text: $r('app.string.ui_create_drafts_anyway'), color: '#007DFF' }
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

    this.parsedItems = this.parsedItems.concat(items);
    if (skipConfidenceCheck) this.manualInput = '';
    this.isGenerating = false;
  }

  private addManualItems(): void {
    const text: string = this.manualInput.trim();
    if (text.length === 0) return;
    if (this.isGenerating) return;
    this.generateCards(text, true);
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
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_select_at_least_one_item'), duration: 1500 });
      } catch (e) {
        // Toast 展示失败时忽略
      }
      return;
    }

    this.startEntryForItem(selectedIndex);
  }

  private startEntryForItem(index: number): void {
    if (index < 0 || index >= this.parsedItems.length) return;
    const item: ParsedFoodEntry = this.parsedItems[index];
    if (!item.selected) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_this_entry_is_not_selected'), duration: 1200 });
      } catch (e) {
        // Toast 展示失败时忽略
      }
      return;
    }

    const params: AddFoodParams = {
      barcode: '',
      name: item.name,
      category: '',
      spec: '',
      calories: 0,
      fromBarcodeScan: false,
      fromClipboardParse: true,
      clipboardSourceIndex: index
    };
    try {
      AppNavigation.push('AddFoodPage', params);
    } catch (e) {
      // 路由跳转失败时忽略
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

  // 标题栏右侧菜单：继续录入（等价于原标题栏按钮；未选择项时由 continueEntry 内部提示兜底）
  private getMenuItems(): Array<HdsNavigationBadgeIconOptions> {
    const item: HdsNavigationBadgeIconOptions = {
      content: { type: TextStyleMode.NORMAL, componentId: 'continue-clipboard-entry', isEnabled: this.getSelectedCount() > 0, label: $r('app.string.ui_continue_d', this.getSelectedCount()), action: () => { this.continueEntry(); } }
    };
    return [item];
  }

  build() {
    HdsNavDestination() {
    Column() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          // 安全粘贴控件
          Column({ space: 8 }) {
            Text($r('app.string.ui_tap_to_allow_clipboard_access'))
              .fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
            Row() {
              PasteButton()
                .padding({ top: 10, bottom: 10, left: 20, right: 20 })
                .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
                  this.handlePasteButtonResult(result);
                })
              if (this.pasteAuthorized) {
                Text($r('app.string.ui_access_granted')).fontSize(12).fontColor($r('app.color.status_success')).padding({ left: 8 })
              }
            }
            .width('100%')
          }
          .width('100%').padding(16).margin({ left: 16, right: 16, top: 16 })
          .backgroundColor($r('app.color.card_background')).borderRadius(16)

          // 手动输入区
          Column({ space: 8 }) {
            Text($r('app.string.ui_enter_a_shopping_list_separated_by_commas_or_line_breaks'))
              .fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
            Row({ space: 8 }) {
              TextInput({ text: this.manualInput, placeholder: $r('app.string.ui_e_g_milk_bread_apples_eggs') })
                .layoutWeight(1).height(40).fontSize(14).borderRadius(8)
                .onChange((value: string) => { this.manualInput = value; })
              Button($r('app.string.ui_parse'))
                .attributeModifier(FoodButtonStyle.compactPrimary)
                .onClick(() => { this.addManualItems(); })
            }
          }
          .width('100%').padding(16).margin({ left: 16, right: 16 })
          .backgroundColor($r('app.color.card_background')).borderRadius(16)

          // 剪贴板内容（如有）
          if (this.clipboardText.length > 0) {
            Column({ space: 8 }) {
              Text($r('app.string.ui_import_from_clipboard'))
                .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
              Text(this.clipboardText)
                .fontSize(13).fontColor($r('app.color.text_hint'))
                .width('100%').maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%').padding(16).margin({ left: 16, right: 16 })
            .backgroundColor($r('app.color.card_background')).borderRadius(16)
          }

          // 解析结果列表
          Column({ space: 8 }) {
            Text($r('app.string.ui_draft_entries_d', this.parsedItems.length))
              .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')

            if (this.parsedItems.length === 0) {
              Column({ space: 8 }) {
                Image($r('app.media.icon_clipboard')).width(40).height(40).draggable(false)
                Text($r('app.string.ui_select_parse_to_create_draft_food_entries')).fontSize(13).fontColor($r('app.color.text_hint'))
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
                      Text($r('app.string.ui_for_reference_only'))
                        .fontSize(10).fontColor($r('app.color.chip_warning_text'))
                        .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                        .borderRadius(4).backgroundColor($r('app.color.chip_warning_bg'))
                    }
                  }
                  .width('100%')

                  Row() {
                    Text($r('app.string.ui_add_calories_shelf_life_and_any_missing_details'))
                      .fontSize(13).fontColor($r('app.color.text_hint')).layoutWeight(1)
                    Button($r('app.string.ui_add_to_inventory_2'))
                      .attributeModifier(FoodButtonStyle.compactSecondary)
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
        // 标题栏沉浸避让：状态栏高度 + 标题栏高度(56vp)
        .padding({ top: 56 + this.statusBarHeight })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      content: {
        title: { mainTitle: $r('app.string.ui_import_from_clipboard_2') },
        menu: { value: this.getMenuItems() }
      },
      style: FOOD_TITLE_BAR_STYLE
    })
    .bindToScrollable([this.scroller])
    .onHidden(() => {
      AppNavigation.notifyDataChanged();
    })
    .backgroundColor($r('app.color.page_background'))
  }
}

// Navigation 系统路由表入口（router_map.json 中注册为 ClipboardParsePage）
@Builder
export function ClipboardParsePageBuilder() {
  ClipboardParsePage()
}
