import { FoodButtonStyle, FOOD_PRESS_EFFECT, FoodMotion, FOOD_TITLE_BAR_STYLE } from '../common/FoodInterface';
import { localizedFoodLabel } from '../common/Constants';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { AppNavigation } from '../common/AppNavigation';
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
  fromClipboardParse?: boolean;
  clipboardSourceIndex?: number;
  editMode: boolean;
  foodId: number;
}

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
  @State showOptionalDetails: boolean = false;
  @State isOpened: boolean = false;
  @State isEditMode: boolean = false;
  @State editFoodId: number = 0;
  @State pageTitle: ResourceStr = $r('app.string.ui_add_food');
  @State fromBarcodeScan: boolean = false;
  @State fromPhotoCapture: boolean = false;
  @State photoUri: string = '';
  @State freshnessLevel: string = 'fresh';
  @State fromClipboardParse: boolean = false;
  @State clipboardSourceIndex: number = -1;

  @StorageProp('naviIndicatorHeight') naviIndicatorHeight: number = 0;

  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    const params: AddFoodParams | undefined = AppNavigation.getParamByName('AddFoodPage') as AddFoodParams | undefined;
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
        this.pageTitle = $r('app.string.ui_add_to_inventory');
      }
      if (params.fromPhotoCapture !== undefined && params.fromPhotoCapture) {
        this.fromPhotoCapture = true;
        this.pageTitle = $r('app.string.ui_review_photo_entry');
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
      if (params.fromClipboardParse !== undefined && params.fromClipboardParse) {
        this.fromClipboardParse = true;
      }
      if (params.clipboardSourceIndex !== undefined && params.clipboardSourceIndex >= 0) {
        this.clipboardSourceIndex = params.clipboardSourceIndex;
      }
      // 编辑模式
      if (params.editMode !== undefined && params.editMode) {
        this.isEditMode = true;
        this.editFoodId = params.foodId;
        this.pageTitle = $r('app.string.ui_edit_food');
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
    return date.getFullYear() + '-' + padZero(date.getMonth() + 1) + '-' + padZero(date.getDate());
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
    try {
      if (this.foodName.trim().length === 0) {
        this.nameError = true;
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_enter_a_food_name_2'), duration: 1500 });
        return;
      }
      if (this.isSaving) return;
      this.isSaving = true;

      const food = new FoodItem();
      food.name = this.foodName.trim();
      food.category = this.selectedCategory;
      food.spec = this.spec.trim();
      food.barcode = this.barcode;
      food.calories = this.caloriesText.trim().length === 0 ? 0 : Number(this.caloriesText);
      if (!Number.isFinite(food.calories) || food.calories < 0) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_enter_a_valid_energy_value') });
        this.isSaving = false;
        return;
      }
      food.storageType = this.storageType;
      food.isOpened = this.isOpened;
      if (this.hasExactProductionInfo) {
        const shelfLifeAmount: number = Number(this.shelfLifeDaysText) || 0;
        if (!Number.isFinite(shelfLifeAmount) || shelfLifeAmount <= 0) {
          this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_enter_a_valid_shelf_life'), duration: 1500 });
          this.isSaving = false;
          return;
        }
        this.calculateExpiryFromProduction();
      }
      food.expiryDate = this.expiryDate.getTime();
      food.status = 0;

      if (this.isEditMode) {
        food.id = this.editFoodId;
        if (!await DatabaseHelper.getInstance().updateFoodItem(food)) {
          throw new Error('Food item was not updated');
        }
        AppStorage.setOrCreate<number>('foodDetailRefreshFoodId', this.editFoodId);
        AppStorage.setOrCreate<number>('foodDetailRefreshVersion', Date.now());
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_changes_saved'), duration: 1500 });
      } else {
        if (await DatabaseHelper.getInstance().insertFoodItem(food) <= 0) {
          throw new Error('Food item was not inserted');
        }
        if (this.fromClipboardParse && this.clipboardSourceIndex >= 0) {
          AppStorage.setOrCreate<number>('clipboardEntryCompletedIndex', this.clipboardSourceIndex);
        }
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_added_to_inventory'), duration: 1500 });
      }
      AppNavigation.pop();
    } catch (e) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_could_not_save_try_again'), duration: 1500 });
      } catch (e) {
        // 提示失败，忽略
      }
      this.isSaving = false;
    }
  }

  private getCategoryOptions(): SelectOption[] {
    return FOOD_CATEGORIES.map((category: string): SelectOption => {
      return { value: localizedFoodLabel(category) };
    });
  }

  build() {
    HdsNavDestination() {
    Column() {
      // 表单
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          Column({ space: 14 }) {
            // 基本信息
            this.buildSectionTitle($r('app.string.ui_basic_information'))

            if (this.fromPhotoCapture) {
              Row() {
                Text(this.photoUri.length > 0 ? $r('app.string.ui_photo_taken_add_any_missing_details_to_save_the_item') : $r('app.string.ui_you_can_enter_details_now_and_take_a_photo_later'))
                  .fontSize(12)
                  .fontColor(this.photoUri.length > 0 ? $r('app.color.status_success') : $r('app.color.status_warning'))
              }
              .width('100%')

            }

            // 食品名称
            Column({ space: 6 }) {
              Row() {
                Text($r('app.string.ui_food_name'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                Text(' *')
                  .fontSize(14)
                  .fontColor($r('app.color.status_danger'))
              }
              .width('100%')
              TextInput({ text: this.foodName, placeholder: $r('app.string.ui_e_g_milk_lettuce_apples') })
                .width('100%')
                .height(44)
                .fontSize(15)
                .borderRadius(8)
                .backgroundColor($r('app.color.input_background'))
                .placeholderColor($r('app.color.text_hint'))
                .fontColor($r('app.color.text_primary'))
                .onChange((value: string) => {
                  this.foodName = value;
                  this.nameError = false;
                })
              if (this.nameError) {
                Text($r('app.string.ui_enter_a_food_name'))
                  .fontSize(12)
                  .fontColor($r('app.color.status_danger'))
              }
            }
            .width('100%')


            Column({ space: 7 }) {
              Text($r('app.string.ui_food_category'))
                .fontSize(14).fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Select(this.getCategoryOptions())
                .width('100%').height(48)
                .selected(FOOD_CATEGORIES.indexOf(this.selectedCategory))
                .value(this.selectedCategory.length > 0 ? localizedFoodLabel(this.selectedCategory) :
                  $r('app.string.food_form_select_category'))
                .font({ size: 15 })
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.input_background'))
                .selectedOptionBgColor($r('app.color.button_secondary_bg'))
                .selectedOptionFontColor($r('app.color.accent_link'))
                .onSelect((index: number) => {
                  if (index < 0 || index >= FOOD_CATEGORIES.length) return;
                  this.selectedCategory = FOOD_CATEGORIES[index];
                  this.updateExpiryDate();
                })
            }
            .width('100%').alignItems(HorizontalAlign.Start)
          }
          .width('100%').padding(16)
          .backgroundColor($r('app.color.card_background')).borderRadius(20)

          Column({ space: 14 }) {
            // 存储信息
            this.buildSectionTitle($r('app.string.ui_storage_details'))

            // 存储方式
            Column({ space: 6 }) {
              Text($r('app.string.ui_storage_method'))
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Row({ space: 3 }) {
                this.buildStorageButton($r('app.string.ui_refrigerated'), StorageType.FRIDGE)
                this.buildStorageButton($r('app.string.ui_frozen'), StorageType.FREEZER)
                this.buildStorageButton($r('app.string.ui_room_temperature'), StorageType.ROOM)
              }
              .width('100%')
              .borderRadius(13)
              .padding(3)
              .backgroundColor($r('app.color.input_background'))
            }
            .width('100%')


            if (this.fromPhotoCapture) {
              Column({ space: 6 }) {
                Text($r('app.string.ui_suggested_freshness_editable'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                Row({ space: 8 }) {
                  this.buildFreshnessButton($r('app.string.ui_fresh'), 'fresh')
                  this.buildFreshnessButton($r('app.string.ui_fair'), 'normal')
                  this.buildFreshnessButton($r('app.string.ui_poor'), 'stale')
                }
                .width('100%')
              }
              .width('100%')

            }

            // 已开封
            Row() {
              Text($r('app.string.ui_opened'))
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.isOpened })
                .selectedColor($r('app.color.button_primary_bg'))
                .onChange((isOn: boolean) => {
                  this.isOpened = isOn;
                  this.updateExpiryDate();
                })
            }
            .width('100%')
            .height(48)


            // 生产信息开关（展开/折叠）
            Row() {
              Column({ space: 2 }) {
                Text($r('app.string.ui_production_date_and_shelf_life_are_known'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                Text($r('app.string.ui_enter_the_production_date_and_shelf_life_to_calculate_the_expiry_date'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_hint'))
              }
              .layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.hasExactProductionInfo })
                .selectedColor($r('app.color.button_primary_bg'))
                .onChange((isOn: boolean) => {
                  this.getUIContext().animateTo({ duration: 190, curve: Curve.EaseOut }, () => {
                    this.hasExactProductionInfo = isOn;
                    if (!isOn) {
                      this.showProductionDatePicker = false;
                      this.updateExpiryDate();
                    } else {
                      this.calculateExpiryFromProduction();
                    }
                  });
                })
            }
            .width('100%')


            // 日期与保质期信息
            Column({ space: 6 }) {
              if (this.hasExactProductionInfo) {
                Column({ space: 8 }) {
                  Row() {
                    Text($r('app.string.ui_production_date'))
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                    Blank()
                    Text(this.showProductionDatePicker ? $r('app.string.ui_collapse') : $r('app.string.ui_select_date'))
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
                  .clickEffect(FOOD_PRESS_EFFECT)
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
                      .transition(FoodMotion.reveal())
                      .onDateChange((value: Date) => {
                        const d = new Date();
                        d.setFullYear(value.getFullYear());
                        d.setMonth(value.getMonth());
                        d.setDate(value.getDate());
                        d.setHours(0, 0, 0, 0);
                        this.productionDate = d;
                        this.calculateExpiryFromProduction();
                      })
                  }

                  Column({ space: 4 }) {
                    Text($r('app.string.ui_shelf_life'))
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                    Row({ space: 8 }) {
                      TextInput({ text: this.shelfLifeDaysText, placeholder: $r('app.string.ui_e_g_7_6_1') })
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
                        Text($r('app.string.watch_days_suffix'))
                          .fontSize(13)
                          .fontColor(this.shelfLifeUnit === 'day' ? $r('app.color.button_primary_text') : $r('app.color.button_neutral_text'))
                          .textAlign(TextAlign.Center).width(44).height(40)
                          .backgroundColor(this.shelfLifeUnit === 'day' ? $r('app.color.button_primary_bg') : $r('app.color.button_neutral_bg'))
                          .borderRadius(8)
                          .onClick(() => {
                            this.shelfLifeUnit = 'day';
                            this.calculateExpiryFromProduction();
                          })
                        Text($r('app.string.ui_months'))
                          .fontSize(13)
                          .fontColor(this.shelfLifeUnit === 'month' ? $r('app.color.button_primary_text') : $r('app.color.button_neutral_text'))
                          .textAlign(TextAlign.Center).width(44).height(40)
                          .backgroundColor(this.shelfLifeUnit === 'month' ? $r('app.color.button_primary_bg') : $r('app.color.button_neutral_bg'))
                          .borderRadius(8)
                          .onClick(() => {
                            this.shelfLifeUnit = 'month';
                            this.calculateExpiryFromProduction();
                          })
                        Text($r('app.string.ui_years'))
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
                .transition(FoodMotion.reveal())
              }

              Column({ space: 5 }) {
                Text($r('app.string.ui_expiry_date_calculated_automatically'))
                  .fontSize(13).fontColor($r('app.color.button_secondary_text'))
                Text(this.formatDate(this.expiryDate))
                  .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
                Text(this.hasExactProductionInfo ? $r('app.string.ui_based_on_production_date') :
                  $r('app.string.ui_based_on_category_and_storage'))
                  .fontSize(13).fontColor($r('app.color.text_secondary'))
              }
              .width('100%').padding(12).alignItems(HorizontalAlign.Start)
              .borderRadius(13).backgroundColor($r('app.color.button_secondary_bg'))
            }
            .width('100%')
          }
          .width('100%').padding(16)
          .backgroundColor($r('app.color.card_background')).borderRadius(20)

          Column({ space: 8 }) {
            Row({ space: 10 }) {
              Column({ space: 4 }) {
                Text($r('app.string.food_form_more_details'))
                  .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                Text($r('app.string.food_form_more_details_hint'))
                  .fontSize(13).fontColor($r('app.color.text_secondary'))
              }
              .layoutWeight(1).alignItems(HorizontalAlign.Start)
              SymbolGlyph($r('sys.symbol.chevron_forward'))
                .fontSize(15).fontColor([$r('app.color.accent_link')])
                .rotate({ angle: this.showOptionalDetails ? 90 : 0 })
                .animation({ duration: 190, curve: Curve.EaseOut })
            }
            .width('100%').constraintSize({ minHeight: 56 })
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .backgroundColor($r('app.color.card_background')).borderRadius(16)
            .focusable(true).clickEffect(FOOD_PRESS_EFFECT)
            .onClick(() => {
              this.getUIContext().animateTo({ duration: 190, curve: Curve.EaseOut }, () => {
                this.showOptionalDetails = !this.showOptionalDetails;
              });
            })

            if (this.showOptionalDetails) {
            Column({ space: 14 }) {
              // 条码（如有）
              if (this.barcode.length > 0 || !this.fromBarcodeScan) {
                Column({ space: 6 }) {
                  Text($r('app.string.ui_barcode_optional'))
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                  TextInput({ text: this.barcode, placeholder: $r('app.string.ui_e_g_6901234567890') })
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

              }

              // 规格说明
              Column({ space: 6 }) {
                Text($r('app.string.ui_package_details_optional'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                TextInput({ text: this.spec, placeholder: $r('app.string.ui_e_g_250_ml_500_g_1_bag') })
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


              Column({ space: 6 }) {
                Text($r('app.string.ui_total_calories_kcal_optional'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))

                Row({ space: 8 }) {
                  TextInput({ text: this.caloriesText, placeholder: $r('app.string.ui_enter_total_calories_kcal') })
                    .layoutWeight(1).height(44).fontSize(15).borderRadius(8)
                    .backgroundColor($r('app.color.input_background'))
                    .type(InputType.Number)
                    .onChange((value: string) => { this.caloriesText = value; })
                  Text('kcal')
                    .fontSize(14).fontColor($r('app.color.text_hint'))
                }

              }
              .width('100%')
            }
            .width('100%').padding(16)
            .backgroundColor($r('app.color.card_background')).borderRadius(20)
              .transition(FoodMotion.reveal())
            }
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 66, bottom: 16 })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)

      Column() {
        Button(this.isEditMode ? $r('app.string.ui_save_changes') : $r('app.string.ui_add_to_inventory'))
          .attributeModifier(FoodButtonStyle.primary)
          .width('100%')
          .enabled(!this.isSaving)
          .onClick(() => { this.saveFoodItem(); })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 8, bottom: Math.max(12, this.naviIndicatorHeight) })
      .backgroundColor($r('app.color.page_background'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      content: {
        title: { mainTitle: this.pageTitle }
      },
      style: FOOD_TITLE_BAR_STYLE
    })
    .bindToScrollable([this.scroller])
    .onBackPressed(() => this.isSaving)
    .onHidden(() => {
      AppNavigation.notifyDataChanged();
    })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  buildSectionTitle(title: ResourceStr) {
    Text(title)
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
  }

  @Builder
  buildStorageButton(label: ResourceStr, type: string) {
    Text(label)
      .fontSize(14)
      .fontColor(this.storageType === type ? $r('app.color.button_primary_text') : $r('app.color.button_neutral_text'))
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(44).borderRadius(10)
      .backgroundColor(this.storageType === type ? $r('app.color.button_primary_bg') : Color.Transparent)
      .clickEffect(FOOD_PRESS_EFFECT)
      .onClick(() => {
        this.storageType = type;
        this.updateExpiryDate();
      })
  }

  @Builder
  buildFreshnessButton(label: ResourceStr, value: string) {
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

// Navigation 系统路由表入口（router_map.json 中注册为 AddFoodPage）
@Builder
export function AddFoodPageBuilder() {
  AddFoodPage()
}