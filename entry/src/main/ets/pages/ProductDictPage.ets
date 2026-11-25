import { FoodButtonStyle, FoodMotion, FOOD_TITLE_BAR_STYLE } from '../common/FoodInterface';
import { resolveLocalizedText } from '../common/Constants';
import { localizedFoodLabel } from '../common/Constants';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { AppNavigation } from '../common/AppNavigation';
import { DataExportService } from '../common/DataExportService';
import { ProductDict } from '../model/DataModels';
import { getSourceName, formatTimestampFull } from '../common/Constants';

@Component
struct ProductDictPage {
  @StorageProp('dataChangeTick') @Watch('onDataChangeTick') dataChangeTick: number = 0;
  @State dictList: ProductDict[] = [];
  @State searchKeyword: string = '';
  @State isLoading: boolean = true;
  private loadRequest: number = 0;
  @State isSavingEdit: boolean = false;
  @State totalCount: number = 0;
  @State showEditDialog: boolean = false;
  @State editItem: ProductDict | null = null;
  @State editBarcode: string = '';
  @State editName: string = '';
  @State editCategory: string = '';
  @State editSpec: string = '';
  @State editCalories: string = '';
  @State isDictExporting: boolean = false;
  @State isDictImporting: boolean = false;
  private scroller: Scroller = new Scroller();
  // 状态栏高度（vp），由 Index 写入 AppStorage；用于标题栏沉浸避让
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  aboutToAppear(): void {
    this.loadData();
  }

  // 从其他页面返回（含系统侧滑）后刷新数据，等价于原 onPageShow
  private onDataChangeTick(): void {
    this.loadData();
  }

  private loadData(): void {
    const request: number = ++this.loadRequest;
    this.isLoading = true;
    DatabaseHelper.getInstance().searchProductDict(this.searchKeyword).then((list: ProductDict[]) => {
      if (request !== this.loadRequest) return;
      this.dictList = list;
      this.isLoading = false;
    }).catch(() => {
      if (request === this.loadRequest) this.isLoading = false;
    });
    DatabaseHelper.getInstance().getProductDictCount().then((count: number) => {
      if (request === this.loadRequest) this.totalCount = count;
    });
  }

  private deleteItem(item: ProductDict): void {
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.ui_confirm_deletion'),
        message: $r('app.string.ui_delete_the_saved_details_for_s', item.name),
        buttons: [
          { text: $r('app.string.ui_cancel'), color: '#999999' },
          { text: $r('app.string.ui_delete'), color: '#FF3B30' }
        ]
      }).then((result: promptAction.ShowDialogSuccessResponse) => {
        if (result.index === 1) {
          DatabaseHelper.getInstance().deleteProductDict(item.id).then(() => {
            this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_deleted'), duration: 1500 });
            this.loadData();
          });
        }
      });
    } catch (e) {
      // 弹窗展示失败时忽略
    }
  }

  private openEditDialog(item: ProductDict): void {
    this.editItem = item;
    this.editBarcode = item.barcode;
    this.editName = item.name;
    this.editCategory = item.category;
    this.editSpec = item.spec;
    this.editCalories = item.calories > 0 ? item.calories.toString() : '';
    this.showEditDialog = true;
  }

  private async exportDict(): Promise<void> {
    if (this.isDictExporting || this.isDictImporting) return;
    this.isDictExporting = true;
    try {
      const json: string = await DataExportService.exportProductDict();
      const fileName: string = 'dict_' + Date.now() + '.json';
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (await DataExportService.saveToFile(ctx, json, fileName)) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_dictionary_exported'), duration: 2000 });
      }
    } catch (e) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_export_failed'), duration: 1500 });
      } catch (e) {
        // Toast 展示失败时忽略
      }
    } finally {
      this.isDictExporting = false;
    }
  }

  private async importDict(): Promise<void> {
    if (this.isDictExporting || this.isDictImporting) return;
    this.isDictImporting = true;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const files: string[] = await DataExportService.pickImportFile(ctx);
      if (files.length === 0) return;
      const jsonStr: string = await DataExportService.readFromFile(files[0]);
      const result = await DataExportService.importProductDictJson(jsonStr);
      if (result.success) {
        this.getUIContext().getPromptAction().showToast({
          message: $r('app.string.ui_dictionary_imported_d_added_d_skipped', result.imported || 0, result.skipped || 0),
          duration: 2200
        });
        this.loadData();
      } else {
        this.getUIContext().getPromptAction().showToast({ message: result.message, duration: 2000 });
      }
    } catch (e) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_import_failed_the_file_is_missing_or_has_an_invalid_format'), duration: 2000 });
      } catch (e) {
        // Toast 展示失败时忽略
      }
    } finally {
      this.isDictImporting = false;
    }
  }

  private saveEdit(): void {
    if (this.isSavingEdit) return;
    if (this.editItem === null || this.editName.trim().length === 0) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_enter_a_product_name_2'), duration: 1500 });
      } catch (e) {
        // Toast 展示失败时忽略
      }
      return;
    }
    const finalBarcode: string = this.editBarcode.trim();
    const finalCategory: string = this.editCategory.trim();
    const finalName: string = this.editName.trim();
    const dict = new ProductDict();
    dict.dictKey = finalBarcode.length > 0 ? finalBarcode : (finalCategory + '_' + finalName);
    dict.barcode = finalBarcode;
    dict.name = finalName;
    dict.category = finalCategory;
    dict.spec = this.editSpec.trim();
    dict.calories = this.editCalories.trim().length === 0 ? 0 : Number(this.editCalories);
    if (!Number.isFinite(dict.calories) || dict.calories < 0) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_enter_a_valid_energy_value') });
      return;
    }
    if (this.editItem !== null) {
      dict.rawEnergy = this.editItem.rawEnergy;
      dict.energyUnit = this.editItem.energyUnit;
      dict.basisType = this.editItem.basisType;
      dict.servingSize = this.editItem.servingSize;
      dict.servingUnit = this.editItem.servingUnit;
      dict.isReliable = this.editItem.isReliable;
    }
    dict.source = 'edited';
    this.isSavingEdit = true;
    DatabaseHelper.getInstance().updateProductDict(this.editItem.id, dict).then((id: number) => {
      if (id <= 0) throw new Error('Product was not updated');
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
        Text($r('app.string.ui_records_d', this.totalCount))
          .fontSize(13).fontColor($r('app.color.text_hint'))
          .width('100%').textAlign(TextAlign.End)
          .padding({ left: 16, right: 16, top: 8 })

        // 搜索栏
        Row({ space: 8 }) {
          TextInput({ text: this.searchKeyword, placeholder: $r('app.string.ui_search_by_name_or_barcode') })
            .layoutWeight(1).height(46).fontSize(15).borderRadius(14)
            .placeholderColor($r('app.color.text_hint')).fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.input_background'))
            .onChange((value: string) => {
              this.searchKeyword = value;
              this.loadData();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        // 提示
        Row() {
          Row({ space: 6 }) {
            Image($r('app.media.icon_info')).width(14).height(14).draggable(false)
            Text($r('app.string.ui_works_offline_with_on_device_storage'))
              .fontSize(13).fontColor($r('app.color.text_hint')).layoutWeight(1)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 4 })

        // 列表
        if (this.dictList.length === 0 && !this.isLoading) {
          Scroll() {
            Column({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.doc_text')).fontSize(34).fontColor([$r('app.color.accent_link')])
              Text($r('app.string.ui_no_dictionary_entries')).fontSize(14).fontColor($r('app.color.text_hint'))
              Text($r('app.string.ui_scanning_a_barcode_when_adding_food_saves_the_product_information')).fontSize(13).fontColor($r('app.color.text_disabled'))
            }
            .width('100%')
          }
          .width('100%').layoutWeight(1).align(Alignment.Center)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        } else {
          List({ space: 8, scroller: this.scroller }) {
            ForEach(this.dictList, (item: ProductDict) => {
              ListItem() {
                this.buildDictCard(item)
              }
            }, (item: ProductDict) => item.id.toString())
          }
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .width('100%').layoutWeight(1)
          .padding({ left: 16, right: 16, top: 8, bottom: 16 })
        }

        // 导入导出按钮
        Row({ space: 12 }) {
          Button($r('app.string.ui_export_dictionary'))
            .attributeModifier(FoodButtonStyle.secondary)
            .layoutWeight(1)
            .enabled(!this.isDictImporting && !this.isDictExporting)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => { this.exportDict(); })
          Button($r('app.string.ui_import_dictionary'))
            .attributeModifier(FoodButtonStyle.secondary)
            .layoutWeight(1)
            .enabled(!this.isDictImporting && !this.isDictExporting)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => { this.importDict(); })
        }
        .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
      // 标题栏沉浸避让：状态栏高度 + 标题栏高度(56vp)
      .padding({ top: 56 + this.statusBarHeight })

      // 编辑弹窗
      if (this.showEditDialog) {
        Column() {
          Column()
            .width('100%').height('100%').backgroundColor($r('app.color.overlay_background'))
            .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
            .onClick(() => { this.showEditDialog = false; })
        }
        .width('100%').height('100%').position({ x: 0, y: 0 })

        Column({ space: 12 }) {
          Text($r('app.string.ui_edit_product_details'))
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')

          Column({ space: 4 }) {
            Text($r('app.string.ui_barcode_editable_or_removable')).fontSize(13).fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.editBarcode, placeholder: $r('app.string.ui_leave_blank_to_remove_barcode') })
              .width('100%').height(40).fontSize(14).borderRadius(8).backgroundColor($r('app.color.input_background'))
              .onChange((value: string) => { this.editBarcode = value; })
          }

          Column({ space: 4 }) {
            Text($r('app.string.ui_product_name_2')).fontSize(13).fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.editName, placeholder: $r('app.string.ui_product_name') })
              .width('100%').height(40).fontSize(14).borderRadius(8).backgroundColor($r('app.color.input_background'))
              .onChange((value: string) => { this.editName = value; })
          }
          Column({ space: 4 }) {
            Text($r('app.string.ui_category')).fontSize(13).fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.editCategory, placeholder: $r('app.string.ui_category_optional_2') })
              .width('100%').height(40).fontSize(14).borderRadius(8).backgroundColor($r('app.color.input_background'))
              .onChange((value: string) => { this.editCategory = value; })
          }
          Column({ space: 4 }) {
            Text($r('app.string.ui_package_size')).fontSize(13).fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.editSpec, placeholder: $r('app.string.ui_package_size_optional_2') })
              .width('100%').height(40).fontSize(14).borderRadius(8).backgroundColor($r('app.color.input_background'))
              .onChange((value: string) => { this.editSpec = value; })
          }
          Column({ space: 4 }) {
            Text($r('app.string.ui_standardized_calories_kcal_per_100_units')).fontSize(13).fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.editCalories, placeholder: '0' })
              .width('100%').height(40).fontSize(14).borderRadius(8).backgroundColor($r('app.color.input_background'))
              .type(InputType.Number)
              .onChange((value: string) => { this.editCalories = value; })
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
        .position({ x: '7.5%', y: '15%' })
      }
    }
    .width('100%').height('100%')
    .animation({ duration: 260, curve: Curve.EaseInOut })
    }
    .titleBar({
      content: {
        title: { mainTitle: $r('app.string.ui_product_dictionary') }
      },
      style: FOOD_TITLE_BAR_STYLE
    })
    .bindToScrollable([this.scroller])
    .onHidden(() => {
      AppNavigation.notifyDataChanged();
    })
    .backgroundColor($r('app.color.page_background'))
  }

  private getBasisLabel(basisType: string): string {
    if (basisType === 'per100ml') return resolveLocalizedText(this.getUIContext().getHostContext(), $r('app.string.ui_per_100_ml').id);
    if (basisType === 'perServing') return resolveLocalizedText(this.getUIContext().getHostContext(), $r('app.string.ui_per_serving').id);
    return resolveLocalizedText(this.getUIContext().getHostContext(), $r('app.string.ui_per_100_g').id);
  }

  private getNormalizedLabel(item: ProductDict): string {
    const basis: string = item.basisType === 'per100ml' ? '100ml' : '100g';
    if (item.calories <= 0) {
      return resolveLocalizedText(this.getUIContext().getHostContext(), $r('app.string.ui_no_standardized_calorie_value_yet').id);
    }
    return item.calories.toFixed(0) + ' kcal/' + basis;
  }

  @Builder
  buildDictCard(item: ProductDict) {
    Column({ space: 6 }) {
      Row() {
        Text(item.name)
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(getSourceName(item.source))
          .fontSize(11).fontColor($r('app.color.button_secondary_text'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8).backgroundColor($r('app.color.button_secondary_bg'))
      }.width('100%')

      Row({ space: 12 }) {
        if (item.barcode.length > 0) {
          Text($r('app.string.ui_barcode_s', item.barcode)).fontSize(13).fontColor($r('app.color.text_hint'))
        }
        if (item.category.length > 0) {
          Text(localizedFoodLabel(item.category)).fontSize(13).fontColor($r('app.color.text_hint'))
        }
        if (item.spec.length > 0) {
          Text(item.spec).fontSize(13).fontColor($r('app.color.text_hint'))
        }
      }

      Column({ space: 2 }) {
        Row({ space: 8 }) {
          if (item.rawEnergy > 0) {
            Text($r('app.string.ui_original_s_s_s', item.rawEnergy.toFixed(0), item.energyUnit, this.getBasisLabel(item.basisType)))
              .fontSize(13).fontColor($r('app.color.text_secondary')).layoutWeight(1)
          } else {
            Text($r('app.string.ui_no_original_nutrition_label_value_saved'))
              .fontSize(13).fontColor($r('app.color.text_secondary')).layoutWeight(1)
          }

          Text(item.isReliable ? $r('app.string.ui_standardized') : $r('app.string.ui_details_needed'))
            .fontSize(10)
            .fontColor(item.isReliable ? $r('app.color.chip_success_text') : $r('app.color.chip_warning_text'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(8)
            .backgroundColor(item.isReliable ? $r('app.color.chip_success_bg') : $r('app.color.chip_warning_bg'))
        }
        .width('100%')

        Text(this.getNormalizedLabel(item))
          .fontSize(12)
          .fontColor(item.calories > 0 ? $r('app.color.status_warning') : $r('app.color.text_disabled'))
      }
      .width('100%')

      Row() {
        Blank().layoutWeight(1)
        Button($r('app.string.ui_edit'))
          .attributeModifier(FoodButtonStyle.compactSecondary)
          .margin({ right: 8 })
          .onClick(() => { this.openEditDialog(item); })
        Button($r('app.string.ui_delete'))
          .attributeModifier(FoodButtonStyle.compactDanger)
          .onClick(() => { this.deleteItem(item); })
      }.width('100%')
    }
    .width('100%').padding(12).backgroundColor($r('app.color.card_background')).borderRadius(12)
  }
}

// Navigation 系统路由表入口（router_map.json 中注册为 ProductDictPage）
@Builder
export function ProductDictPageBuilder() {
  ProductDictPage()
}