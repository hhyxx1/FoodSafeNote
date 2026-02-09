import { router, promptAction } from '@kit.ArkUI';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { FoodItem } from '../model/DataModels';
import {
  FOOD_CATEGORIES,
  StorageType,
  isPackagedFood,
  calculateExpiryTimestamp,
  padZero,
  kjToKcal
} from '../common/Constants';

// 路由参数接口（来自扫码流程或编辑模式）
interface AddFoodParams {
  barcode: string;
  name: string;
  category: string;
  spec: string;
  calories: number;
  fromBarcodeScan: boolean;
  editMode: boolean;
  foodId: number;
}

@Entry
@Component
struct AddFoodPage {
  @State foodName: string = '';
  @State selectedCategory: string = '';
  @State spec: string = '';
  @State caloriesText: string = '';
  @State barcode: string = '';
  @State storageType: string = StorageType.FRIDGE;
  @State expiryDate: Date = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
  @State showDatePicker: boolean = false;
  @State nameError: boolean = false;
  @State isSaving: boolean = false;
  @State isOpened: boolean = false;
  @State calorieUnit: string = 'kcal';
  @State isEditMode: boolean = false;
  @State editFoodId: number = 0;
  @State pageTitle: string = '添加食品';
  @State fromBarcodeScan: boolean = false;

  aboutToAppear(): void {
    const params: AddFoodParams = router.getParams() as AddFoodParams;
    if (params !== null && params !== undefined) {
      // 从扫码流程传来的预填值
      if (params.barcode !== undefined && params.barcode.length > 0) {
        this.barcode = params.barcode;
      }
      if (params.name !== undefined && params.name.length > 0) {
        this.foodName = params.name;
      }
      if (params.category !== undefined && params.category.length > 0) {
        this.selectedCategory = params.category;
      }
      if (params.spec !== undefined && params.spec.length > 0) {
        this.spec = params.spec;
      }
      if (params.calories !== undefined && params.calories > 0) {
        this.caloriesText = params.calories.toString();
      }
      if (params.fromBarcodeScan !== undefined) {
        this.fromBarcodeScan = params.fromBarcodeScan;
        this.pageTitle = '确认入库';
      }
      // 编辑模式
      if (params.editMode !== undefined && params.editMode) {
        this.isEditMode = true;
        this.editFoodId = params.foodId;
        this.pageTitle = '编辑食品';
        this.loadFoodForEdit(params.foodId);
      }
      // 自动计算保质期
      if (this.selectedCategory.length > 0) {
        this.updateExpiryDate();
      }
    }
  }

  private loadFoodForEdit(id: number): void {
    DatabaseHelper.getInstance().getFoodItemById(id).then((item: FoodItem | null) => {
      if (item !== null) {
        this.foodName = item.name;
        this.selectedCategory = item.category;
        this.spec = item.spec;
        this.barcode = item.barcode;
        this.caloriesText = item.calories > 0 ? item.calories.toString() : '';
        this.storageType = item.storageType;
        this.isOpened = item.isOpened;
        if (item.expiryDate > 0) {
          this.expiryDate = new Date(item.expiryDate);
        }
      }
    });
  }

  private formatDate(date: Date): string {
    const year: number = date.getFullYear();
    const month: number = date.getMonth() + 1;
    const day: number = date.getDate();
    return year + '-' + padZero(month) + '-' + padZero(day);
  }

  private updateExpiryDate(): void {
    if (this.selectedCategory.length > 0 && !isPackagedFood(this.selectedCategory)) {
      const timestamp: number = calculateExpiryTimestamp(this.selectedCategory, this.storageType, this.isOpened);
      this.expiryDate = new Date(timestamp);
    }
  }

  private async saveFoodItem(): Promise<void> {
    if (this.foodName.trim().length === 0) {
      this.nameError = true;
      promptAction.showToast({ message: '请输入食品名称', duration: 1500 });
      return;
    }
    if (this.isSaving) return;
    this.isSaving = true;

    const food = new FoodItem();
    food.name = this.foodName.trim();
    food.category = this.selectedCategory;
    food.spec = this.spec.trim();
    food.barcode = this.barcode;
    const rawCalorie: number = Number(this.caloriesText) || 0;
    food.calories = this.calorieUnit === 'kJ' ? kjToKcal(rawCalorie) : rawCalorie;
    food.storageType = this.storageType;
    food.isOpened = this.isOpened;
    food.expiryDate = this.expiryDate.getTime();
    food.status = 0;

    try {
      if (this.isEditMode) {
        food.id = this.editFoodId;
        await DatabaseHelper.getInstance().updateFoodItem(food);
        promptAction.showToast({ message: '修改成功', duration: 1500 });
      } else {
        await DatabaseHelper.getInstance().insertFoodItem(food);
        promptAction.showToast({ message: '入库成功', duration: 1500 });
      }
      router.back();
    } catch (e) {
      promptAction.showToast({ message: '保存失败，请重试', duration: 1500 });
      this.isSaving = false;
    }
  }

  build() {
    Column() {
      // 导航栏
      Row() {
        Button('返回')
          .height(36)
          .fontSize(14)
          .fontColor('#007DFF')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            router.back();
          })
        Text(this.pageTitle)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Button('保存')
          .height(36)
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor('#007DFF')
          .borderRadius(8)
          .onClick(() => {
            this.saveFoodItem();
          })
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))

      // 表单
      Scroll() {
        Column({ space: 16 }) {
          // 基本信息
          this.buildSectionTitle('基本信息')

          // 食品名称
          Column({ space: 6 }) {
            Row() {
              Text('食品名称')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Text(' *')
                .fontSize(14)
                .fontColor('#FF3B30')
            }
            TextInput({ text: this.foodName, placeholder: '如：纯牛奶、生菜、苹果' })
              .width('100%')
              .height(44)
              .fontSize(15)
              .borderRadius(8)
              .backgroundColor($r('app.color.input_background'))
              .onChange((value: string) => {
                this.foodName = value;
                this.nameError = false;
              })
            if (this.nameError) {
              Text('食品名称不能为空')
                .fontSize(12)
                .fontColor('#FF3B30')
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          // 条码（如有）
          if (this.barcode.length > 0 || !this.fromBarcodeScan) {
            Column({ space: 6 }) {
              Text('商品条码（选填）')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              TextInput({ text: this.barcode, placeholder: '如：6901234567890' })
                .width('100%')
                .height(44)
                .fontSize(15)
                .borderRadius(8)
                .backgroundColor(this.fromBarcodeScan ? '#F0F0F0' : '#F5F5F5')
                .enabled(!this.fromBarcodeScan)
                .onChange((value: string) => {
                  this.barcode = value;
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
          }

          // 食品分类
          Column({ space: 6 }) {
            Text('食品分类')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(FOOD_CATEGORIES, (category: string) => {
                Text(category)
                  .fontSize(13)
                  .fontColor(this.selectedCategory === category ? Color.White : '#666666')
                  .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                  .margin({ right: 8, bottom: 8 })
                  .borderRadius(16)
                  .backgroundColor(this.selectedCategory === category ? '#007DFF' : '#F0F0F0')
                  .onClick(() => {
                    this.selectedCategory = category;
                    this.updateExpiryDate();
                  })
              }, (category: string) => category)
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          // 规格说明
          Column({ space: 6 }) {
            Text('规格说明（选填）')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            TextInput({ text: this.spec, placeholder: '如：250ml、500g、1袋' })
              .width('100%')
              .height(44)
              .fontSize(15)
              .borderRadius(8)
              .backgroundColor($r('app.color.input_background'))
              .onChange((value: string) => {
                this.spec = value;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          // 存储信息
          this.buildSectionTitle('存储信息')

          // 存储方式
          Column({ space: 6 }) {
            Text('存储方式')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            Row({ space: 0 }) {
              this.buildStorageButton('冷藏', StorageType.FRIDGE)
              this.buildStorageButton('冷冻', StorageType.FREEZER)
              this.buildStorageButton('常温', StorageType.ROOM)
            }
            .width('100%')
            .borderRadius(8)
            .clip(true)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          // 已开封
          Row() {
            Text('已开封')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.isOpened })
              .onChange((isOn: boolean) => {
                this.isOpened = isOn;
                this.updateExpiryDate();
              })
          }
          .width('100%')
          .height(48)
          .padding({ left: 16, right: 16 })

          // 到期日期
          Column({ space: 6 }) {
            Row() {
              Text('到期日期')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Blank()
              if (this.selectedCategory.length > 0 && !isPackagedFood(this.selectedCategory)) {
                Text('已自动计算')
                  .fontSize(12)
                  .fontColor('#007DFF')
              }
            }
            .width('100%')

            Row() {
              Text(this.formatDate(this.expiryDate))
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text(this.showDatePicker ? '收起' : '选择日期')
                .fontSize(13)
                .fontColor('#007DFF')
            }
            .width('100%')
            .height(44)
            .padding({ left: 12, right: 12 })
            .backgroundColor($r('app.color.input_background'))
            .borderRadius(8)
            .onClick(() => {
              this.showDatePicker = !this.showDatePicker;
            })

            if (this.showDatePicker) {
              DatePicker({
                start: new Date(),
                end: new Date('2030-12-31'),
                selected: this.expiryDate
              })
                .width('100%')
                .onChange((value: DatePickerResult) => {
                  const year: number = value.year !== undefined ? value.year : new Date().getFullYear();
                  const month: number = value.month !== undefined ? value.month : new Date().getMonth();
                  const day: number = value.day !== undefined ? value.day : new Date().getDate();
                  const d = new Date();
                  d.setFullYear(year);
                  d.setMonth(month);
                  d.setDate(day);
                  d.setHours(23, 59, 59, 0);
                  this.expiryDate = d;
                })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          // 营养信息
          this.buildSectionTitle('营养信息')

          Column({ space: 6 }) {
            Text('能量/热量（每100g，选填）')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            // kJ/kcal 单位切换
            Row({ space: 0 }) {
              Text('千焦 kJ')
                .fontSize(13)
                .fontColor(this.calorieUnit === 'kJ' ? Color.White : $r('app.color.text_secondary'))
                .textAlign(TextAlign.Center).layoutWeight(1).height(32)
                .backgroundColor(this.calorieUnit === 'kJ' ? '#007DFF' : $r('app.color.chip_background'))
                .borderRadius(8)
                .onClick(() => { this.calorieUnit = 'kJ'; })
              Text('千卡 kcal')
                .fontSize(13)
                .fontColor(this.calorieUnit === 'kcal' ? Color.White : $r('app.color.text_secondary'))
                .textAlign(TextAlign.Center).layoutWeight(1).height(32)
                .backgroundColor(this.calorieUnit === 'kcal' ? '#007DFF' : $r('app.color.chip_background'))
                .borderRadius(8)
                .onClick(() => { this.calorieUnit = 'kcal'; })
            }
            .width('100%').borderRadius(8).clip(true)

            Row({ space: 8 }) {
              TextInput({ text: this.caloriesText, placeholder: '如营养表上的数值' })
                .layoutWeight(1).height(44).fontSize(15).borderRadius(8)
                .backgroundColor($r('app.color.input_background'))
                .type(InputType.Number)
                .onChange((value: string) => { this.caloriesText = value; })
              Text(this.calorieUnit)
                .fontSize(14).fontColor($r('app.color.text_hint'))
            }
            if (this.calorieUnit === 'kJ' && this.caloriesText.length > 0) {
              Text('≈ ' + kjToKcal(Number(this.caloriesText) || 0) + ' kcal（自动换算）')
                .fontSize(12).fontColor('#007DFF')
            }
            if (this.caloriesText.length === 0) {
              Text('💡 查看包装营养成分表，能量一栏通常为千焦(kJ)')
                .fontSize(12).fontColor('#FF9500')
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          // 确认按钮
          Button(this.isEditMode ? '保存修改' : '确认入库')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor('#007DFF')
            .borderRadius(12)
            .margin({ left: 16, right: 16, top: 8, bottom: 32 })
            .onClick(() => {
              this.saveFoodItem();
            })
        }
        .padding({ top: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  buildSectionTitle(title: string) {
    Text(title)
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })
  }

  @Builder
  buildStorageButton(label: string, type: string) {
    Text(label)
      .fontSize(14)
      .fontColor(this.storageType === type ? Color.White : '#666666')
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(40)
      .backgroundColor(this.storageType === type ? '#007DFF' : '#F0F0F0')
      .onClick(() => {
        this.storageType = type;
        this.updateExpiryDate();
      })
  }
}
