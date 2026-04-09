import { router, promptAction } from '@kit.ArkUI';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BarcodeService } from '../common/BarcodeService';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { FoodItem, BarcodeMatchResult } from '../model/DataModels';
import { StorageType, FOOD_CATEGORIES, isPackagedFood, calculateExpiryTimestamp, padZero, kjToKcal } from '../common/Constants';

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

@Entry
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

  // 步骤1：扫码收集
  private startScan(): void {
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: true,
      enableAlbum: true
    };
    try {
      scanBarcode.startScanForResult(getContext(this), options)
        .then((result: scanBarcode.ScanResult) => {
          const code: string = result.originalValue;
          if (code.length > 0) {
            this.matchAndAdd(code);
          }
        })
        .catch((error: BusinessError) => {
          promptAction.showToast({ message: '扫码取消', duration: 1500 });
        });
    } catch (error) {
      promptAction.showToast({ message: '扫码功能不可用', duration: 1500 });
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
        promptAction.showToast({ message: '已匹配: ' + result.name, duration: 1500 });
      } else {
        promptAction.showToast({ message: '未匹配，需手动填写名称', duration: 1500 });
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
    this.editName = item.name;
    this.editCategory = item.category;
    this.editSpec = item.spec;
    this.editCalories = item.calories > 0 ? item.calories.toString() : '';
    this.editStorage = item.storageType;
    this.currentStep = 'edit';
  }

  // 保存编辑
  private saveEdit(): void {
    if (this.editName.trim().length === 0) {
      promptAction.showToast({ message: '请输入食品名称', duration: 1500 });
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
    // 检查是否所有条目都有名称
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].name.trim().length === 0) {
        promptAction.showToast({ message: '第 ' + (i + 1) + ' 项缺少名称，请点击编辑', duration: 2000 });
        return;
      }
    }
    if (this.items.length === 0) {
      promptAction.showToast({ message: '请先添加食品', duration: 1500 });
      return;
    }
    this.isSaving = true;
    const db: DatabaseHelper = DatabaseHelper.getInstance();
    let count: number = 0;
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
      await db.insertFoodItem(food);
      // 存入产品字典
      if (item.barcode.length > 0) {
        await BarcodeService.getInstance().saveToProductDict(
          item.barcode, item.name, item.category, item.spec, item.calories, 'manual'
        );
      }
      count++;
    }
    this.isSaving = false;
    promptAction.showToast({ message: '成功入库 ' + count + ' 件食品', duration: 2000 });
    router.back();
  }

  private getConfirmedCount(): number {
    let count: number = 0;
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].confirmed && this.items[i].name.length > 0) count++;
    }
    return count;
  }

  build() {
    Column() {
      // 导航栏
      Row() {
        Button('返回')
          .height(40).fontSize(14).fontColor($r('app.color.accent_link'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            if (this.currentStep === 'edit') {
              this.currentStep = 'collect';
            } else {
              router.back();
            }
          })
        Text(this.currentStep === 'edit' ? '编辑食品信息' : '批量添加')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          .layoutWeight(1).textAlign(TextAlign.Center)
        if (this.currentStep === 'collect' && this.items.length > 0) {
          Button('全部入库')
            .height(40).fontSize(14).fontColor($r('app.color.button_primary_text'))
            .backgroundColor($r('app.color.button_primary_bg')).borderRadius(8)
            .enabled(!this.isSaving)
            .onClick(() => { this.batchSave(); })
        } else {
          Text('').width(70)
        }
      }
      .width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))

      if (this.currentStep === 'collect') {
        this.buildCollectView()
      } else {
        this.buildEditView()
      }
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }

  // 收集阶段
  @Builder
  buildCollectView() {
    Column() {
      // 操作按钮
      Row({ space: 12 }) {
        Button('扫码添加')
          .layoutWeight(1).height(44).fontSize(14)
          .fontColor($r('app.color.button_primary_text')).backgroundColor($r('app.color.button_primary_bg')).borderRadius(8)
          .onClick(() => { this.startScan(); })
        Button('手动添加')
          .layoutWeight(1).height(44).fontSize(14)
          .fontColor($r('app.color.button_secondary_text')).backgroundColor($r('app.color.button_secondary_bg')).borderRadius(8)
          .onClick(() => { this.addManualItem(); })
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Text('已添加 ' + this.items.length + ' 项，' + this.getConfirmedCount() + ' 项已确认信息')
        .fontSize(12).fontColor($r('app.color.text_hint'))
        .width('100%').padding({ left: 16, right: 16, bottom: 8 })

      // 条目列表
      if (this.items.length === 0) {
        Column({ space: 8 }) {
          Text('📋').fontSize(48)
          Text('点击上方按钮添加食品').fontSize(14).fontColor($r('app.color.text_hint'))
          Text('可连续扫描多个条码').fontSize(12).fontColor($r('app.color.text_disabled'))
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.items, (item: BatchItem, index: number) => {
            ListItem() {
              Row() {
                // 状态指示
                Circle().width(10).height(10)
                  .fill(item.confirmed ? $r('app.color.status_success') : $r('app.color.status_warning'))
                  .margin({ right: 8 })

                Column({ space: 2 }) {
                  Text(item.name.length > 0 ? item.name : '(未命名，点击编辑)')
                    .fontSize(15)
                    .fontColor(item.name.length > 0 ? $r('app.color.text_primary') : $r('app.color.status_warning'))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row({ space: 8 }) {
                    if (item.barcode.length > 0) {
                      Text(item.barcode).fontSize(11).fontColor($r('app.color.text_hint'))
                    }
                    if (item.category.length > 0) {
                      Text(item.category).fontSize(11).fontColor($r('app.color.text_hint'))
                    }
                    if (item.calories > 0) {
                      Text(item.calories.toString() + 'kcal').fontSize(11).fontColor($r('app.color.status_warning'))
                    }
                  }
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)

                Button('编辑')
                  .height(40).fontSize(11).fontColor($r('app.color.button_secondary_text'))
                  .backgroundColor($r('app.color.button_secondary_bg')).borderRadius(6)
                  .margin({ right: 6 })
                  .onClick(() => { this.openEdit(index); })
                Button('删除')
                  .height(40).fontSize(11).fontColor($r('app.color.button_danger_text'))
                  .backgroundColor($r('app.color.button_danger_bg')).borderRadius(6)
                  .onClick(() => { this.removeItem(index); })
              }
              .width('100%').padding(12)
              .backgroundColor($r('app.color.card_background')).borderRadius(12)
            }
          }, (item: BatchItem, index: number) => index.toString() + '_' + item.name)
        }
        .width('100%').layoutWeight(1).padding({ left: 16, right: 16, bottom: 16 })
      }
    }
    .width('100%').layoutWeight(1)
  }

  // 编辑阶段（逐个编辑食品详情）
  @Builder
  buildEditView() {
    Scroll() {
      Column({ space: 16 }) {
        // 名称
        Column({ space: 6 }) {
          Row() {
            Text('食品名称').fontSize(14).fontColor($r('app.color.text_primary'))
            Text(' *').fontSize(14).fontColor($r('app.color.status_danger'))
          }
          TextInput({ text: this.editName, placeholder: '如：纯牛奶、苹果' })
            .width('100%').height(44).fontSize(15).borderRadius(8)
            .backgroundColor($r('app.color.input_background'))
            .onChange((value: string) => { this.editName = value; })
        }
        .width('100%').padding({ left: 16, right: 16, top: 16 })

        // 分类
        Column({ space: 6 }) {
          Text('食品分类').fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(FOOD_CATEGORIES, (cat: string) => {
              Text(cat)
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
          Text('规格（选填）').fontSize(14).fontColor($r('app.color.text_primary'))
          TextInput({ text: this.editSpec, placeholder: '如：250ml、500g' })
            .width('100%').height(44).fontSize(15).borderRadius(8)
            .backgroundColor($r('app.color.input_background'))
            .onChange((value: string) => { this.editSpec = value; })
        }
        .width('100%').padding({ left: 16, right: 16 })

        // 热量（支持kJ/kcal切换）
        Column({ space: 6 }) {
          Text('能量/热量（每100g，选填）').fontSize(14).fontColor($r('app.color.text_primary'))
          Row({ space: 0 }) {
            Text('千焦 kJ')
              .fontSize(13)
              .fontColor(this.editCalorieUnit === 'kJ' ? Color.White : $r('app.color.text_secondary'))
              .textAlign(TextAlign.Center).layoutWeight(1).height(40)
              .backgroundColor(this.editCalorieUnit === 'kJ' ? $r('app.color.button_primary_bg') : $r('app.color.chip_background'))
              .borderRadius(8)
              .onClick(() => { this.editCalorieUnit = 'kJ'; })
            Text('千卡 kcal')
              .fontSize(13)
              .fontColor(this.editCalorieUnit === 'kcal' ? Color.White : $r('app.color.text_secondary'))
              .textAlign(TextAlign.Center).layoutWeight(1).height(40)
              .backgroundColor(this.editCalorieUnit === 'kcal' ? $r('app.color.button_primary_bg') : $r('app.color.chip_background'))
              .borderRadius(8)
              .onClick(() => { this.editCalorieUnit = 'kcal'; })
          }
          .width('100%').borderRadius(8).clip(true)
          Row({ space: 8 }) {
            TextInput({ text: this.editCalories, placeholder: '营养表上的数值' })
              .layoutWeight(1).height(44).fontSize(15).borderRadius(8)
              .backgroundColor($r('app.color.input_background'))
              .type(InputType.Number)
              .onChange((value: string) => { this.editCalories = value; })
            Text(this.editCalorieUnit).fontSize(14).fontColor($r('app.color.text_hint'))
          }
          if (this.editCalorieUnit === 'kJ' && this.editCalories.length > 0) {
            Text('≈ ' + kjToKcal(Number(this.editCalories) || 0) + ' kcal（自动换算）')
              .fontSize(12).fontColor($r('app.color.accent_link'))
          }
        }
        .width('100%').padding({ left: 16, right: 16 })

        // 存储方式
        Column({ space: 6 }) {
          Text('存储方式').fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
          Row({ space: 0 }) {
            Text('冷藏').fontSize(14).textAlign(TextAlign.Center).layoutWeight(1).height(40)
              .fontColor(this.editStorage === StorageType.FRIDGE ? Color.White : $r('app.color.text_secondary'))
              .backgroundColor(this.editStorage === StorageType.FRIDGE ? $r('app.color.button_primary_bg') : $r('app.color.chip_background'))
              .onClick(() => { this.editStorage = StorageType.FRIDGE; })
            Text('冷冻').fontSize(14).textAlign(TextAlign.Center).layoutWeight(1).height(40)
              .fontColor(this.editStorage === StorageType.FREEZER ? Color.White : $r('app.color.text_secondary'))
              .backgroundColor(this.editStorage === StorageType.FREEZER ? $r('app.color.button_primary_bg') : $r('app.color.chip_background'))
              .onClick(() => { this.editStorage = StorageType.FREEZER; })
            Text('常温').fontSize(14).textAlign(TextAlign.Center).layoutWeight(1).height(40)
              .fontColor(this.editStorage === StorageType.ROOM ? Color.White : $r('app.color.text_secondary'))
              .backgroundColor(this.editStorage === StorageType.ROOM ? $r('app.color.button_primary_bg') : $r('app.color.chip_background'))
              .onClick(() => { this.editStorage = StorageType.ROOM; })
          }
          .width('100%').borderRadius(8).clip(true)
        }
        .width('100%').padding({ left: 16, right: 16 })

        // 确认按钮
        Button('确认信息')
          .width('100%').height(48).fontSize(16)
          .fontColor($r('app.color.button_primary_text')).backgroundColor($r('app.color.button_primary_bg')).borderRadius(12)
          .margin({ left: 16, right: 16, top: 8, bottom: 32 })
          .onClick(() => { this.saveEdit(); })
      }
    }
    .layoutWeight(1).scrollBar(BarState.Off)
  }
}
