import { router, promptAction } from '@kit.ArkUI';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { FoodItem } from '../model/DataModels';
import {
  FOOD_CATEGORIES,
  StorageType,
  isPackagedFood,
  calculateExpiryTimestamp,
  getBaseDays,
  padZero
} from '../common/Constants';

// 路由参数接口（来自扫码流程或编辑模式）
interface AddFoodParams {
  barcode: string;
  name: string;
  category: string;
  spec: string;
  calories: number;
  fromBarcodeScan: boolean;
  fromPhotoCapture?: boolean;
  photoUri?: string;
  storageType?: string;
  freshnessLevel?: string;
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
  @State hasExactProductionInfo: boolean = false;
  @State productionDate: Date = new Date();
  @State showProductionDatePicker: boolean = false;
  @State shelfLifeDaysText: string = '';
  @State shelfLifeUnit: string = 'day'; // day | month | year
  @State nameError: boolean = false;
  @State isSaving: boolean = false;
  @State isOpened: boolean = false;
  @State isEditMode: boolean = false;
  @State editFoodId: number = 0;
  @State pageTitle: string = '添加食品';
  @State fromBarcodeScan: boolean = false;
  @State fromPhotoCapture: boolean = false;
  @State photoUri: string = '';
  @State freshnessLevel: string = 'fresh';

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
      if (params.fromPhotoCapture !== undefined && params.fromPhotoCapture) {
        this.fromPhotoCapture = true;
        this.pageTitle = '拍照入库确认';
      }
      if (params.photoUri !== undefined && params.photoUri.length > 0) {
        this.photoUri = params.photoUri;
      }
      if (params.storageType !== undefined && params.storageType.length > 0) {
        this.storageType = params.storageType;
      }
      if (params.freshnessLevel !== undefined && params.freshnessLevel.length > 0) {
        this.freshnessLevel = params.freshnessLevel;
      }
      // 编辑模式
      if (params.editMode !== undefined && params.editMode) {
        this.isEditMode = true;
        this.editFoodId = params.foodId;
        this.pageTitle = '编辑食品';
        this.loadFoodForEdit(params.foodId);
      }
      // 自动计算保质期（默认简洁模式）
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
          // 编辑模式下提供一个可参考的推断值（不强制）
          const diffDays: number = Math.ceil((item.expiryDate - Date.now()) / (24 * 60 * 60 * 1000));
          if (diffDays > 0) {
            this.shelfLifeDaysText = diffDays.toString();
          }
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
    if (this.hasExactProductionInfo) {
      this.calculateExpiryFromProduction();
      return;
    }
    if (this.selectedCategory.length > 0 && !isPackagedFood(this.selectedCategory)) {
      if (this.fromPhotoCapture) {
        const baseDays: number = getBaseDays(this.selectedCategory);
        let factor: number = 1;
        if (this.storageType === StorageType.FREEZER) {
          factor = 10;
        } else if (this.storageType === StorageType.ROOM) {
          factor = 0.5;
        }
        if (this.isOpened) {
          factor = factor / 3;
        }
        let freshnessFactor: number = 1;
        if (this.freshnessLevel === 'normal') {
          freshnessFactor = 0.7;
        } else if (this.freshnessLevel === 'stale') {
          freshnessFactor = 0.4;
        }
        const expiryDays: number = Math.max(1, Math.round(baseDays * factor * freshnessFactor));
        this.expiryDate = new Date(Date.now() + expiryDays * 24 * 60 * 60 * 1000);
        return;
      }
      const timestamp: number = calculateExpiryTimestamp(this.selectedCategory, this.storageType, this.isOpened);
      this.expiryDate = new Date(timestamp);
    }
  }

  private calculateExpiryFromProduction(): void {
    const amount: number = Number(this.shelfLifeDaysText) || 0;
    if (amount <= 0) {
      return;
    }
    const base: Date = new Date(this.productionDate.getTime());
    base.setHours(0, 0, 0, 0);
    this.expiryDate = this.calculateByShelfLifeUnit(base, amount, this.shelfLifeUnit);
  }

  private getDaysInMonth(year: number, monthZeroBased: number): number {
    return new Date(year, monthZeroBased + 1, 0).getDate();
  }

  private calculateByShelfLifeUnit(baseDate: Date, amount: number, unit: string): Date {
    const y: number = baseDate.getFullYear();
    const m: number = baseDate.getMonth();
    const d: number = baseDate.getDate();

    if (unit === 'month') {
      const totalMonths: number = m + amount;
      const targetYear: number = y + Math.floor(totalMonths / 12);
      const targetMonth: number = totalMonths % 12;
      const maxDay: number = this.getDaysInMonth(targetYear, targetMonth);
      const targetDay: number = d > maxDay ? maxDay : d;
      const result: Date = new Date(targetYear, targetMonth, targetDay);
      result.setHours(23, 59, 59, 0);
      return result;
    }

    if (unit === 'year') {
      const targetYear: number = y + amount;
      const maxDay: number = this.getDaysInMonth(targetYear, m);
      const targetDay: number = d > maxDay ? maxDay : d;
      const result: Date = new Date(targetYear, m, targetDay);
      result.setHours(23, 59, 59, 0);
      return result;
    }

    const result: Date = new Date(baseDate.getTime());
    result.setDate(result.getDate() + amount);
    result.setHours(23, 59, 59, 0);
    return result;
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
    food.calories = Number(this.caloriesText) || 0;
    food.storageType = this.storageType;
    food.isOpened = this.isOpened;
    if (this.hasExactProductionInfo) {
      const shelfLifeAmount: number = Number(this.shelfLifeDaysText) || 0;
      if (shelfLifeAmount <= 0) {
        promptAction.showToast({ message: '请填写有效保质期', duration: 1500 });
        this.isSaving = false;
        return;
      }
      this.calculateExpiryFromProduction();
    }
    food.expiryDate = this.expiryDate.getTime();
    food.status = 0;

    try {
      if (this.isEditMode) {
        food.id = this.editFoodId;
        await DatabaseHelper.getInstance().updateFoodItem(food);
        AppStorage.setOrCreate<number>('foodDetailRefreshFoodId', this.editFoodId);
        AppStorage.setOrCreate<number>('foodDetailRefreshVersion', Date.now());
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
          .height(40)
          .fontSize(14)
          .fontColor($r('app.color.accent_link'))
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
          .height(40)
          .fontSize(14)
          .fontColor($r('app.color.button_primary_text'))
          .backgroundColor($r('app.color.button_primary_bg'))
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

          if (this.fromPhotoCapture) {
            Row() {
              Text(this.photoUri.length > 0 ? '已完成食品拍照，可继续补充信息并入库' : '拍照入库模式：可先填写信息，稍后补拍')
                .fontSize(12)
                .fontColor(this.photoUri.length > 0 ? $r('app.color.status_success') : $r('app.color.status_warning'))
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
          }

          // 食品名称
          Column({ space: 6 }) {
            Row() {
              Text('食品名称')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Text(' *')
                .fontSize(14)
                .fontColor($r('app.color.status_danger'))
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
                .fontColor($r('app.color.status_danger'))
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
                .backgroundColor(this.fromBarcodeScan ? $r('app.color.chip_background') : $r('app.color.input_background'))
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
                  .fontColor(this.selectedCategory === category ? $r('app.color.button_primary_text') : $r('app.color.button_neutral_text'))
                  .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                  .margin({ right: 8, bottom: 8 })
                  .borderRadius(16)
                  .backgroundColor(this.selectedCategory === category ? $r('app.color.button_primary_bg') : $r('app.color.button_neutral_bg'))
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

          if (this.fromPhotoCapture) {
            Column({ space: 6 }) {
              Text('新鲜程度（拍照建议，可调整）')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Row({ space: 8 }) {
                this.buildFreshnessButton('新鲜', 'fresh')
                this.buildFreshnessButton('一般', 'normal')
                this.buildFreshnessButton('偏差', 'stale')
              }
              .width('100%')
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
          }

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

          // 生产信息开关（展开/折叠）
          Row() {
            Column({ space: 2 }) {
              Text('有确切生产日期和保质期')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Text('开启后填写生产日期 + 保质期（天/月/年），系统自动计算到期日期')
                .fontSize(12)
                .fontColor($r('app.color.text_hint'))
            }
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.hasExactProductionInfo })
              .selectedColor($r('app.color.button_primary_bg'))
              .onChange((isOn: boolean) => {
                this.hasExactProductionInfo = isOn;
                if (!isOn) {
                  this.showProductionDatePicker = false;
                  this.updateExpiryDate();
                } else {
                  this.calculateExpiryFromProduction();
                }
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          // 日期与保质期信息
          Column({ space: 6 }) {
            if (this.hasExactProductionInfo) {
              Column({ space: 8 }) {
                Row() {
                  Text('生产日期')
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                  Blank()
                  Text(this.showProductionDatePicker ? '收起' : '选择日期')
                    .fontSize(13)
                    .fontColor($r('app.color.accent_link'))
                }
                .width('100%')

                Row() {
                  Text(this.formatDate(this.productionDate))
                    .fontSize(16)
                    .fontColor($r('app.color.text_primary'))
                }
                .width('100%')
                .height(44)
                .padding({ left: 12, right: 12 })
                .backgroundColor($r('app.color.input_background'))
                .borderRadius(8)
                .onClick(() => {
                  this.showProductionDatePicker = !this.showProductionDatePicker;
                })

                if (this.showProductionDatePicker) {
                  DatePicker({
                    start: new Date('2020-01-01'),
                    end: new Date(),
                    selected: this.productionDate
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
                      d.setHours(0, 0, 0, 0);
                      this.productionDate = d;
                      this.calculateExpiryFromProduction();
                    })
                }

                Column({ space: 4 }) {
                  Text('保质期')
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                  Row({ space: 8 }) {
                    TextInput({ text: this.shelfLifeDaysText, placeholder: '如：7 / 6 / 1' })
                      .layoutWeight(1)
                      .height(44)
                      .fontSize(15)
                      .borderRadius(8)
                      .backgroundColor($r('app.color.input_background'))
                      .type(InputType.Number)
                      .onChange((value: string) => {
                        this.shelfLifeDaysText = value;
                        this.calculateExpiryFromProduction();
                      })
                    Row({ space: 0 }) {
                      Text('天')
                        .fontSize(13)
                        .fontColor(this.shelfLifeUnit === 'day' ? $r('app.color.button_primary_text') : $r('app.color.button_neutral_text'))
                        .textAlign(TextAlign.Center).width(44).height(40)
                        .backgroundColor(this.shelfLifeUnit === 'day' ? $r('app.color.button_primary_bg') : $r('app.color.button_neutral_bg'))
                        .borderRadius(8)
                        .onClick(() => {
                          this.shelfLifeUnit = 'day';
                          this.calculateExpiryFromProduction();
                        })
                      Text('月')
                        .fontSize(13)
                        .fontColor(this.shelfLifeUnit === 'month' ? $r('app.color.button_primary_text') : $r('app.color.button_neutral_text'))
                        .textAlign(TextAlign.Center).width(44).height(40)
                        .backgroundColor(this.shelfLifeUnit === 'month' ? $r('app.color.button_primary_bg') : $r('app.color.button_neutral_bg'))
                        .borderRadius(8)
                        .onClick(() => {
                          this.shelfLifeUnit = 'month';
                          this.calculateExpiryFromProduction();
                        })
                      Text('年')
                        .fontSize(13)
                        .fontColor(this.shelfLifeUnit === 'year' ? $r('app.color.button_primary_text') : $r('app.color.button_neutral_text'))
                        .textAlign(TextAlign.Center).width(44).height(40)
                        .backgroundColor(this.shelfLifeUnit === 'year' ? $r('app.color.button_primary_bg') : $r('app.color.button_neutral_bg'))
                        .borderRadius(8)
                        .onClick(() => {
                          this.shelfLifeUnit = 'year';
                          this.calculateExpiryFromProduction();
                        })
                    }
                    .borderRadius(8)
                    .clip(true)
                  }
                }
                .width('100%')
              }
            }

            Row() {
              Text('到期日期（自动计算）')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text(this.hasExactProductionInfo ? '来自生产信息' : '来自品类与存储环境')
                .fontSize(12)
                .fontColor($r('app.color.accent_link'))
            }
            .width('100%')

            Row() {
              Text(this.formatDate(this.expiryDate))
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')
            .height(44)
            .padding({ left: 12, right: 12 })
            .backgroundColor($r('app.color.input_background'))
            .borderRadius(8)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          // 营养信息
          this.buildSectionTitle('营养信息')

          Column({ space: 6 }) {
            Text('本次总热量（kcal，选填）')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))

            Row({ space: 8 }) {
              TextInput({ text: this.caloriesText, placeholder: '输入本次入库总热量（kcal）' })
                .layoutWeight(1).height(44).fontSize(15).borderRadius(8)
                .backgroundColor($r('app.color.input_background'))
                .type(InputType.Number)
                .onChange((value: string) => { this.caloriesText = value; })
              Text('kcal')
                .fontSize(14).fontColor($r('app.color.text_hint'))
            }
            if (this.caloriesText.length === 0) {
              Text('💡 建议先在“热量获取”页录入营养标注与数量，再回到此页确认总热量')
                .fontSize(12).fontColor($r('app.color.status_warning'))
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          // 确认按钮
          Button(this.isEditMode ? '保存修改' : '确认入库')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontColor($r('app.color.button_primary_text'))
            .backgroundColor($r('app.color.button_primary_bg'))
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
      .fontColor(this.storageType === type ? $r('app.color.button_primary_text') : $r('app.color.button_neutral_text'))
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(40)
      .backgroundColor(this.storageType === type ? $r('app.color.button_primary_bg') : $r('app.color.button_neutral_bg'))
      .onClick(() => {
        this.storageType = type;
        this.updateExpiryDate();
      })
  }

  @Builder
  buildFreshnessButton(label: string, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.freshnessLevel === value ? $r('app.color.button_primary_text') : $r('app.color.button_neutral_text'))
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(40)
      .borderRadius(8)
      .backgroundColor(this.freshnessLevel === value ? $r('app.color.button_primary_bg') : $r('app.color.button_neutral_bg'))
      .onClick(() => {
        this.freshnessLevel = value;
        this.updateExpiryDate();
      })
  }
}
