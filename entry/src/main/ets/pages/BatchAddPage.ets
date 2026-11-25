import { FoodButtonStyle, FoodMotion, FOOD_TITLE_BAR_STYLE } from '../common/FoodInterface';
import { localizedFoodLabel } from '../common/Constants';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BarcodeService } from '../common/BarcodeService';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { FoodItem, BarcodeMatchResult } from '../model/DataModels';
import { StorageType, FOOD_CATEGORIES, isPackagedFood, calculateExpiryTimestamp, padZero, kjToKcal } from '../common/Constants';
import { HdsNavDestination, HdsNavigationBadgeIconOptions, TextStyleMode } from '@kit.UIDesignKit';
import { AppNavigation } from '../common/AppNavigation';

// 批量条目
interface BatchItem {
  name: string;
  barcode: string;
  category: string;
  spec: string;
  calories: number;
  storageType: string;
  expiryDays: number;
  confirmed: boolean;
}

@Component
struct BatchAddPage {
  @State items: BatchItem[] = [];
  @State currentStep: string = 'collect';
  @State editIndex: number = -1;
  @State isSaving: boolean = false;
  // 编辑用临时状态
  @State editName: string = '';
  @State editCategory: string = '';
  @State editSpec: string = '';
  @State editCalories: string = '';
  @State editCalorieUnit: string = 'kJ';
  @State editStorage: string = StorageType.FRIDGE;
  // 状态栏高度（vp），由 Index 写入 AppStorage；用于标题栏沉浸避让
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  // 收集态 List 与编辑态 Scroll 两个互斥滚动区的控制器
  private scroller: Scroller = new Scroller();
  private scroller2: Scroller = new Scroller();

  // 步骤1：扫码收集
  private startScan(): void {
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: true,
      enableAlbum: true
    };
    try {
      scanBarcode.startScanForResult(this.getUIContext().getHostContext(), options)
        .then((result: scanBarcode.ScanResult) => {
          const code: string = result.originalValue;
          if (code.length > 0) {
            this.matchAndAdd(code);
          }
        })
        .catch((error: BusinessError) => {
          this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_scan_canceled'), duration: 1500 });
        });
    } catch (error) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_barcode_scanning_is_unavailable'), duration: 1500 });
      } catch (e) {
        // Toast 展示失败时忽略
      }
    }
  }

  private matchAndAdd(barcode: string): void {
    BarcodeService.getInstance().matchBarcodeInfo(barcode).then((result: BarcodeMatchResult) => {
      const item: BatchItem = {
        name: result.matched ? result.name : '',
        barcode: barcode,
        category: result.category,
        spec: result.spec,
        calories: result.calories,
        storageType: StorageType.FRIDGE,
        expiryDays: 7,
        confirmed: false
      };
      const newList: BatchItem[] = [];
      for (let i = 0; i < this.items.length; i++) {
        newList.push(this.items[i]);
      }
      newList.push(item);
      this.items = newList;
      if (result.matched) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_match_found_s', result.name), duration: 1500 });
      } else {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_no_match_found_enter_a_name_manually'), duration: 1500 });
      }
    });
  }

  // 手动添加空条目
  private addManualItem(): void {
    const item: BatchItem = {
      name: '',
      barcode: '',
      category: '',
      spec: '',
      calories: 0,
      storageType: StorageType.FRIDGE,
      expiryDays: 7,
      confirmed: false
    };
    const newList: BatchItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      newList.push(this.items[i]);
    }
    newList.push(item);
    this.items = newList;
  }

  private removeItem(index: number): void {
    const newList: BatchItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (i !== index) {
        newList.push(this.items[i]);
      }
    }
    this.items = newList;
  }

  // 打开编辑
  private openEdit(index: number): void {
    const item: BatchItem = this.items[index];
    this.editIndex = index;
    this.editCalorieUnit = 'kcal';
    this.editName = item.name;
    this.editCategory = item.category;
    this.editSpec = item.spec;
    this.editCalories = item.calories > 0 ? item.calories.toString() : '';
    this.editStorage = item.storageType;
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.currentStep = 'edit';
    });
  }

  // 保存编辑
  private saveEdit(): void {
    if (this.editName.trim().length === 0) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_enter_a_food_name_2'), duration: 1500 });
      } catch (e) {
        // Toast 展示失败时忽略
      }
      return;
    }
    const newList: BatchItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (i === this.editIndex) {
        const rawCal: number = Number(this.editCalories) || 0;
        const finalCal: number = this.editCalorieUnit === 'kJ' ? kjToKcal(rawCal) : rawCal;
        const updated: BatchItem = {
          name: this.editName.trim(),
          barcode: this.items[i].barcode,
          category: this.editCategory,
          spec: this.editSpec,
          calories: finalCal,
          storageType: this.editStorage,
          expiryDays: this.items[i].expiryDays,
          confirmed: true
        };
        newList.push(updated);
      } else {
        newList.push(this.items[i]);
      }
    }
    this.items = newList;
    this.currentStep = 'collect';
  }

  // 批量入库
  private async batchSave(): Promise<void> {
    if (this.isSaving) return;
    // 检查是否所有条目都有名称
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].name.trim().length === 0) {
        try {
          this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_item_d_needs_a_name_tap_edit', i + 1), duration: 2000 });
        } catch (e) {
          // Toast 展示失败时忽略
        }
        return;
      }
    }
    if (this.items.length === 0) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_add_a_food_item_first'), duration: 1500 });
      } catch (e) {
        // Toast 展示失败时忽略
      }
      return;
    }
    this.isSaving = true;
    const db: DatabaseHelper = DatabaseHelper.getInstance();
    let count: number = 0;
    try {
      for (let i = 0; i < this.items.length; i++) {
        const item: BatchItem = this.items[i];
        const food = new FoodItem();
        food.name = item.name;
        food.barcode = item.barcode;
        food.category = item.category;
        food.spec = item.spec;
        food.calories = item.calories;
        food.storageType = item.storageType;
        if (isPackagedFood(item.category)) {
          food.expiryDate = Date.now() + item.expiryDays * 24 * 60 * 60 * 1000;
        } else {
          food.expiryDate = calculateExpiryTimestamp(item.category, item.storageType);
        }
        food.status = 0;
        if (await db.insertFoodItem(food) <= 0) {
          throw new Error('Food item was not inserted');
        }
        count++;
        // 存入产品字典
        if (item.barcode.length > 0) {
          await BarcodeService.getInstance().saveToProductDict(
            item.barcode, item.name, item.category, item.spec, item.calories, 'manual'
          );
        }
      }
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_added_d_items', count), duration: 2000 });
      AppNavigation.pop();
    } catch (e) {
      // 已写入的条目从待保存队列移除，重试只处理剩余条目。
      this.items = this.items.slice(count);
      if (count > 0) AppNavigation.notifyDataChanged();
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_could_not_save_try_again'), duration: 2000 });
    } finally {
      this.isSaving = false;
    }
  }

  private getConfirmedCount(): number {
    let count: number = 0;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].confirmed && this.items[i].name.length > 0) count++;
    }
    return count;
  }

  // 标题栏右侧菜单：收集阶段且已有条目时显示"全部入库"（等价于原标题栏按钮；保存中隐藏以模拟禁用态）
  private getMenuItems(): Array<HdsNavigationBadgeIconOptions> {
    if (this.currentStep !== 'collect' || this.items.length === 0 || this.isSaving) {
      return [];
    }
    const item: HdsNavigationBadgeIconOptions = {
      content: { type: TextStyleMode.NORMAL, componentId: 'save-batch', isEnabled: !this.isSaving, label: $r('app.string.ui_add_all_items'), action: () => { this.batchSave(); } }
    };
    return [item];
  }

  build() {
    HdsNavDestination() {
    Column() {
      if (this.currentStep === 'collect') {
        this.buildCollectView()
      } else {
        this.buildEditView()
      }
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      content: {
        title: { mainTitle: this.currentStep === 'edit' ? $r('app.string.ui_edit_food_details') : $r('app.string.ui_add_in_bulk_2') },
        menu: { value: this.getMenuItems() }
      },
      style: FOOD_TITLE_BAR_STYLE
    })
    .bindToScrollable([this.scroller, this.scroller2])
    .onBackPressed(() => {
      if (this.isSaving) return true;
      if (this.currentStep === 'edit') {
        this.currentStep = 'collect';
        return true;
      }
      return false;
    })
    .onHidden(() => {
      AppNavigation.notifyDataChanged();
    })
    .backgroundColor($r('app.color.page_background'))
  }

  // 收集阶段
  @Builder
  buildCollectView() {
    Column() {
      // 操作按钮
      Row({ space: 12 }) {
        Button($r('app.string.ui_scan_to_add'))
          .attributeModifier(FoodButtonStyle.primary)
          .layoutWeight(1)
          .onClick(() => { this.startScan(); })
        Button($r('app.string.ui_add_manually'))
          .attributeModifier(FoodButtonStyle.secondary)
          .layoutWeight(1)
          .onClick(() => { this.addManualItem(); })
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Text($r('app.string.ui_d_added_d_reviewed', this.items.length, this.getConfirmedCount()))
        .fontSize(13).fontColor($r('app.color.text_hint'))
        .width('100%').padding({ left: 16, right: 16, bottom: 8 })

      // 条目列表
      if (this.items.length === 0) {
        Scroll() {
          Column({ space: 8 }) {
            Image($r('app.media.icon_clipboard')).width(48).height(48).draggable(false)
            Text($r('app.string.ui_tap_the_button_above_to_add_food')).fontSize(14).fontColor($r('app.color.text_hint'))
            Text($r('app.string.ui_scan_multiple_barcodes_in_a_row')).fontSize(13).fontColor($r('app.color.text_disabled'))
          }
          .width('100%').alignItems(HorizontalAlign.Center)
        }
        .width('100%').layoutWeight(1).align(Alignment.Center)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      } else {
        List({ space: 8, scroller: this.scroller }) {
          ForEach(this.items, (item: BatchItem, index: number) => {
            ListItem() {
              Row() {
                // 状态指示
                Row().width(10).height(10).borderRadius(5)
                  .backgroundColor(item.confirmed ? $r('app.color.status_success') : $r('app.color.status_warning'))
                  .margin({ right: 8 })

                Column({ space: 2 }) {
                  Text(item.name.length > 0 ? item.name : $r('app.string.ui_untitled_tap_to_edit'))
                    .fontSize(15)
                    .fontColor(item.name.length > 0 ? $r('app.color.text_primary') : $r('app.color.status_warning'))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row({ space: 8 }) {
                    if (item.barcode.length > 0) {
                      Text(item.barcode).fontSize(13).fontColor($r('app.color.text_hint'))
                    }
                    if (item.category.length > 0) {
                      Text(localizedFoodLabel(item.category)).fontSize(13).fontColor($r('app.color.text_hint'))
                    }
                    if (item.calories > 0) {
                      Text(item.calories.toString() + 'kcal').fontSize(11).fontColor($r('app.color.status_warning'))
                    }
                  }
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)

                Button($r('app.string.ui_edit'))
                  .attributeModifier(FoodButtonStyle.compactSecondary)
                  .margin({ right: 6 })
                  .onClick(() => { this.openEdit(index); })
                Button($r('app.string.ui_delete'))
                  .attributeModifier(FoodButtonStyle.compactDanger)
                  .onClick(() => { this.removeItem(index); })
              }
              .width('100%').padding(12)
              .backgroundColor($r('app.color.card_background')).borderRadius(12)
            }
          }, (item: BatchItem, index: number) => index.toString() + '_' + item.name)
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%').layoutWeight(1).padding({ left: 16, right: 16, bottom: 16 })
      }
    }
    // 标题栏沉浸避让：状态栏高度 + 标题栏高度(56vp)
    .padding({ top: 56 + this.statusBarHeight })
    .width('100%').layoutWeight(1).enabled(!this.isSaving)
    .transition(FoodMotion.reveal())
  }

  // 编辑阶段（逐个编辑食品详情）
  @Builder
  buildEditView() {
    Scroll(this.scroller2) {
      Column({ space: 16 }) {
        // 原自定义标题栏"返回"按钮在编辑态的逻辑（返回收集列表）保留在内容区顶部；titleBar 的返回按钮固定为退出页面
        Row() {
          Button($r('app.string.ui_back_to_list'))
            .attributeModifier(FoodButtonStyle.text)
            .onClick(() => { this.currentStep = 'collect'; })
        }
        .width('100%').padding({ left: 16, right: 16, top: 8 })

        // 名称
        Column({ space: 6 }) {
          Row() {
            Text($r('app.string.ui_food_name')).fontSize(14).fontColor($r('app.color.text_primary'))
            Text(' *').fontSize(14).fontColor($r('app.color.status_danger'))
          }
          TextInput({ text: this.editName, placeholder: $r('app.string.ui_e_g_milk_apples') })
            .width('100%').height(44).fontSize(15).borderRadius(8)
            .backgroundColor($r('app.color.input_background'))
            .onChange((value: string) => { this.editName = value; })
        }
        .width('100%').padding({ left: 16, right: 16, top: 16 })

        // 分类
        Column({ space: 6 }) {
          Text($r('app.string.ui_food_category')).fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(FOOD_CATEGORIES, (cat: string) => {
              Text(localizedFoodLabel(cat))
                .fontSize(13)
                .fontColor(this.editCategory === cat ? Color.White : $r('app.color.text_secondary'))
                .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                .margin({ right: 8, bottom: 8 }).borderRadius(16)
                .backgroundColor(this.editCategory === cat ? $r('app.color.button_primary_bg') : $r('app.color.chip_background'))
                .onClick(() => { this.editCategory = cat; })
            }, (cat: string) => cat)
          }
        }
        .width('100%').padding({ left: 16, right: 16 })

        // 规格
        Column({ space: 6 }) {
          Text($r('app.string.ui_package_size_optional_2')).fontSize(14).fontColor($r('app.color.text_primary'))
          TextInput({ text: this.editSpec, placeholder: $r('app.string.ui_e_g_250_ml_500_g') })
            .width('100%').height(44).fontSize(15).borderRadius(8)
            .backgroundColor($r('app.color.input_background'))
            .onChange((value: string) => { this.editSpec = value; })
        }
        .width('100%').padding({ left: 16, right: 16 })

        // 热量（支持kJ/kcal切换）
        Column({ space: 6 }) {
          Text($r('app.string.ui_energy_per_100_g_optional')).fontSize(14).fontColor($r('app.color.text_primary'))
          Row({ space: 0 }) {
            Text($r('app.string.ui_kilojoules_kj'))
              .fontSize(13)
              .fontColor(this.editCalorieUnit === 'kJ' ? Color.White : $r('app.color.text_secondary'))
              .textAlign(TextAlign.Center).layoutWeight(1).height(40)
              .backgroundColor(this.editCalorieUnit === 'kJ' ? $r('app.color.button_primary_bg') : $r('app.color.chip_background'))
              .borderRadius(8)
              .onClick(() => { this.editCalorieUnit = 'kJ'; })
            Text($r('app.string.ui_kilocalories_kcal'))
              .fontSize(13)
              .fontColor(this.editCalorieUnit === 'kcal' ? Color.White : $r('app.color.text_secondary'))
              .textAlign(TextAlign.Center).layoutWeight(1).height(40)
              .backgroundColor(this.editCalorieUnit === 'kcal' ? $r('app.color.button_primary_bg') : $r('app.color.chip_background'))
              .borderRadius(8)
              .onClick(() => { this.editCalorieUnit = 'kcal'; })
          }
          .width('100%').borderRadius(8).clip(true)
          Row({ space: 8 }) {
            TextInput({ text: this.editCalories, placeholder: $r('app.string.ui_value_from_the_nutrition_label') })
              .layoutWeight(1).height(44).fontSize(15).borderRadius(8)
              .backgroundColor($r('app.color.input_background'))
              .type(InputType.Number)
              .onChange((value: string) => { this.editCalories = value; })
            Text(this.editCalorieUnit).fontSize(14).fontColor($r('app.color.text_hint'))
          }
          if (this.editCalorieUnit === 'kJ' && this.editCalories.length > 0) {
            Text($r('app.string.ui_about_d_kcal_converted', kjToKcal(Number(this.editCalories) || 0)))
              .fontSize(12).fontColor($r('app.color.accent_link'))
          }
        }
        .width('100%').padding({ left: 16, right: 16 })

        // 存储方式
        Column({ space: 6 }) {
          Text($r('app.string.ui_storage_method')).fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
          Row({ space: 0 }) {
            Text($r('app.string.ui_refrigerated')).fontSize(14).textAlign(TextAlign.Center).layoutWeight(1).height(40)
              .fontColor(this.editStorage === StorageType.FRIDGE ? Color.White : $r('app.color.text_secondary'))
              .backgroundColor(this.editStorage === StorageType.FRIDGE ? $r('app.color.button_primary_bg') : $r('app.color.chip_background'))
              .onClick(() => { this.editStorage = StorageType.FRIDGE; })
            Text($r('app.string.ui_frozen')).fontSize(14).textAlign(TextAlign.Center).layoutWeight(1).height(40)
              .fontColor(this.editStorage === StorageType.FREEZER ? Color.White : $r('app.color.text_secondary'))
              .backgroundColor(this.editStorage === StorageType.FREEZER ? $r('app.color.button_primary_bg') : $r('app.color.chip_background'))
              .onClick(() => { this.editStorage = StorageType.FREEZER; })
            Text($r('app.string.ui_room_temperature')).fontSize(14).textAlign(TextAlign.Center).layoutWeight(1).height(40)
              .fontColor(this.editStorage === StorageType.ROOM ? Color.White : $r('app.color.text_secondary'))
              .backgroundColor(this.editStorage === StorageType.ROOM ? $r('app.color.button_primary_bg') : $r('app.color.chip_background'))
              .onClick(() => { this.editStorage = StorageType.ROOM; })
          }
          .width('100%').borderRadius(8).clip(true)
        }
        .width('100%').padding({ left: 16, right: 16 })

        // 确认按钮
        Button($r('app.string.ui_review_details'))
          .attributeModifier(FoodButtonStyle.primary)
          .width('100%')
          .margin({ left: 16, right: 16, top: 8, bottom: 32 })
          .onClick(() => { this.saveEdit(); })
      }
      // 标题栏沉浸避让：状态栏高度 + 标题栏高度(56vp)
      .padding({ top: 56 + this.statusBarHeight })
    }
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .layoutWeight(1).scrollBar(BarState.Off)
  }
}

// Navigation 系统路由表入口（router_map.json 中注册为 BatchAddPage）
@Builder
export function BatchAddPageBuilder() {
  BatchAddPage()
}
