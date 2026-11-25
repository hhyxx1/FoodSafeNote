import { FoodButtonStyle, FOOD_TITLE_BAR_STYLE } from '../common/FoodInterface';
import { calculateExpiryTimestamp, FOOD_CATEGORIES, getStorageTypeName, localizedFoodLabel, StorageType } from '../common/Constants';
import { IntakeDraft, IntakeImportParams, IntakeNutritionParams, IntakeParams, IntakeSeed } from '../common/FoodIntake';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { BarcodeService } from '../common/BarcodeService';
import { FoodItem } from '../model/DataModels';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore, customScan } from '@kit.ScanKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppNavigation } from '../common/AppNavigation';

@Component
struct IntakeCard {
  @ObjectLink draft: IntakeDraft;
  @Prop compact: boolean = false;
  @State expanded: boolean = false;
  @State showDate: boolean = false;
  @State chosenDate: Date = new Date();
  @State showDetails: boolean = false;
  onDelete: () => void = () => {};
  onNutrition: () => void = () => {};
  onSplit: () => void = () => {};

  @Builder
  storageChip(storage: string) {
    Button(getStorageTypeName(storage))
      .attributeModifier(this.draft.storage === storage ? FoodButtonStyle.compactSecondary : FoodButtonStyle.compactNeutral)
      .layoutWeight(1)
      .accessibilitySelected(this.draft.storage === storage)
      .onClick(() => {
        this.draft.storage = storage;
        if (this.draft.estimated) this.estimateDate();
      })
  }

  private estimateDate(): void {
    this.draft.expiry = calculateExpiryTimestamp(this.draft.category || '其他', this.draft.storage);
    this.draft.estimated = true;
    this.showDate = false;
  }

  @Builder
  summary() {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(this.draft.name.trim() || $r('app.string.intake_name_needed'))
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text($r('app.string.intake_quantity_value', this.draft.quantity))
          .fontSize(13).fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.compact) {
        Button(this.expanded ? $r('app.string.intake_done') : $r('app.string.ui_edit'))
          .attributeModifier(FoodButtonStyle.compactSecondary)
          .onClick(() => { this.expanded = !this.expanded; })
      }
    }
    .width('100%')
  }

  @Builder
  fields() {
    if (this.draft.photoUri.length > 0) {
      Image(this.draft.photoUri).width('100%').height(100).objectFit(ImageFit.Contain).borderRadius(14)
    }
    TextInput({ text: this.draft.name, placeholder: $r('app.string.intake_name') })
      .fontSize(17).height(48)
      .backgroundColor($r('app.color.input_background'))
      .borderRadius(14)
      .accessibilityText($r('app.string.intake_name'))
      .onChange((value: string) => { this.draft.name = value; })

    Row({ space: 10 }) {
      Text($r('app.string.intake_quantity')).layoutWeight(1).fontColor($r('app.color.text_primary')).fontSize(14)
      Button('−').attributeModifier(FoodButtonStyle.compactNeutral)
        .enabled(this.draft.quantity > 1)
        .onClick(() => { this.draft.quantity--; })
      Text(this.draft.quantity.toString()).width(30).textAlign(TextAlign.Center).fontColor($r('app.color.text_primary'))
      Button('+').attributeModifier(FoodButtonStyle.compactSecondary)
        .enabled(this.draft.quantity < 99)
        .onClick(() => { this.draft.quantity++; })
    }
    .width('100%')

    Row({ space: 6 }) {
      this.storageChip(StorageType.FRIDGE)
      this.storageChip(StorageType.FREEZER)
      this.storageChip(StorageType.ROOM)
    }

    Row({ space: 8 }) {
      Column({ space: 3 }) {
        Text($r('app.string.intake_expiry')).fontSize(14).fontColor($r('app.color.text_primary'))
        Text(this.draft.expiry === 0 ? $r('app.string.intake_pending_date') :
          new Date(this.draft.expiry).toLocaleDateString())
          .fontSize(14).fontColor($r('app.color.text_secondary'))
        if (this.draft.estimated) {
          Text($r('app.string.intake_estimated')).fontSize(12).fontColor($r('app.color.status_warning'))
        }
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button($r('app.string.intake_date_select')).attributeModifier(FoodButtonStyle.compactSecondary)
        .onClick(() => {
          if (!this.showDate) this.chosenDate = this.draft.expiry > 0 ? new Date(this.draft.expiry) : new Date();
          this.showDate = !this.showDate;
        })
    }
    .width('100%')

    if (this.showDate) {
      DatePicker({ start: new Date(2000, 0, 1), end: new Date(2100, 11, 31),
        selected: this.chosenDate })
        .height(140).width('100%')
        .onDateChange((value: Date) => { this.chosenDate = value; })
      Row({ space: 6 }) {
        Button($r('app.string.intake_later')).attributeModifier(FoodButtonStyle.compactNeutral)
          .layoutWeight(1).onClick(() => {
            this.draft.expiry = 0;
            this.draft.estimated = false;
            this.showDate = false;
          })
        if (this.draft.category.trim().length > 0) {
          Button($r('app.string.intake_use_estimate')).attributeModifier(FoodButtonStyle.compactSecondary)
            .layoutWeight(1).onClick(() => { this.estimateDate(); })
        }
        Button($r('app.string.ui_confirm')).attributeModifier(FoodButtonStyle.compactPrimary)
          .layoutWeight(1).onClick(() => {
            const date = new Date(this.chosenDate.getTime());
            date.setHours(23, 59, 59, 999);
            this.draft.expiry = date.getTime();
            this.draft.estimated = false;
            this.showDate = false;
          })
      }
      .width('100%')
    }

    Button($r('app.string.intake_more')).attributeModifier(FoodButtonStyle.text)
      .onClick(() => { this.showDetails = !this.showDetails; })
    if (this.showDetails) {
      Select(FOOD_CATEGORIES.map((category: string): SelectOption => ({ value: localizedFoodLabel(category) })))
        .value(this.draft.category.length > 0 ? localizedFoodLabel(this.draft.category) : $r('app.string.intake_category'))
        .width('100%')
        .onSelect((index: number) => {
          this.draft.category = FOOD_CATEGORIES[index];
          if (this.draft.estimated) this.estimateDate();
        })
      if (this.draft.photoUri.length > 0) {
        Image(this.draft.photoUri).width('100%').height(110).borderRadius(12).objectFit(ImageFit.Cover)
      }
      TextInput({ text: this.draft.spec, placeholder: $r('app.string.intake_spec') })
        .height(44).backgroundColor($r('app.color.input_background')).borderRadius(12)
        .onChange((value: string) => { this.draft.spec = value; })
      TextInput({ text: this.draft.calorieText, placeholder: $r('app.string.intake_calories_per_unit') })
        .type(InputType.NUMBER_DECIMAL).height(44).backgroundColor($r('app.color.input_background')).borderRadius(12)
        .onChange((value: string) => { this.draft.calorieText = value; })
      Button($r('app.string.intake_read_nutrition')).attributeModifier(FoodButtonStyle.compactSecondary)
        .onClick(() => { this.onNutrition(); })
    }
    if (this.compact) {
      Row({ space: 8 }) {
        if (this.draft.quantity > 1) {
          Button($r('app.string.intake_split')).attributeModifier(FoodButtonStyle.compactSecondary)
            .onClick(() => { this.onSplit(); })
        }
        Button($r('app.string.ui_delete')).attributeModifier(FoodButtonStyle.compactDanger)
          .onClick(() => { this.onDelete(); })
      }
    }
  }

  build() {
    Column({ space: 10 }) {
      if (this.compact) {
        this.summary()
      }
      if (!this.compact || this.expanded) {
        this.fields()
      } else {
        Row({ space: 8 }) {
          Text(getStorageTypeName(this.draft.storage)).fontSize(13).fontColor($r('app.color.text_secondary'))
          Text(this.draft.expiry === 0 ? $r('app.string.intake_pending_date') : new Date(this.draft.expiry).toLocaleDateString())
            .fontSize(13).fontColor($r('app.color.text_secondary'))
          if (this.draft.estimated) {
            Text($r('app.string.intake_estimated')).fontSize(12).fontColor($r('app.color.status_warning'))
          }
        }
        .width('100%')
      }
    }
    .width('100%').padding(16).alignItems(HorizontalAlign.Start)
    .borderRadius(20).backgroundColor($r('app.color.card_background'))
  }
}

@Component
struct BatchAddPage {
  @State drafts: IntakeDraft[] = [];
  @State recent: FoodItem[] = [];
  @State mode: string = 'batch';
  @State busy: boolean = false;
  @State undoIds: number[] = [];
  @State showBatchScanner: boolean = false;
  @State scanReady: boolean = false;
  @State scanCount: number = 0;
  @State showStorageOptions: boolean = false;
  private nextKey: number = 1;
  private autoScan: boolean = false;
  private shown = false;
  private scanController: XComponentController = new XComponentController();
  private scanSession: number = 0;
  private scanInitialized: boolean = false;
  private scroller: Scroller = new Scroller();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  aboutToAppear(): void {
    const params = AppNavigation.getParamByName('BatchAddPage') as IntakeParams | undefined;
    this.mode = params?.mode ?? 'batch';
    this.autoScan = this.mode === 'scan';
    if (params?.seeds) this.addImported(params.seeds);
    if (this.mode !== 'batch' && this.drafts.length === 0) this.drafts = [this.makeDraft()];
    this.loadRecent();
  }

  private loadRecent(): void {
    DatabaseHelper.getInstance().getRecentFoods().then((foods: FoodItem[]) => {
      if (this.shown) this.recent = foods;
    }).catch(() => {});
  }

  private makeDraft(seed?: IntakeSeed): IntakeDraft {
    return new IntakeDraft(this.nextKey++, seed);
  }

  private addImported(seeds: IntakeSeed[]): void {
    const drafts = this.drafts.slice();
    for (const seed of seeds) {
      const same = seed.name.trim().length > 0 && !seed.photoUri && !seed.barcode && !seed.category
        ? drafts.find((draft: IntakeDraft): boolean => draft.quantity < 99 && draft.expiry === 0 &&
          draft.name.trim().toLowerCase() === seed.name.trim().toLowerCase() && draft.barcode.length === 0 &&
          draft.category.length === 0 && draft.photoUri.length === 0 && draft.calorieText.length === 0 &&
          draft.spec.length === 0 && draft.storage === StorageType.FRIDGE) : undefined;
      if (same) {
        same.quantity++;
      } else {
        drafts.push(this.makeDraft(seed));
      }
    }
    this.drafts = drafts;
  }

  private openImport(page: string): void {
    const params: IntakeImportParams = { onImported: (items: IntakeSeed[]) => { this.addImported(items); } };
    AppNavigation.push(page, params);
  }

  private useRecent(food: FoodItem): void {
    const seed: IntakeSeed = {
      name: food.name, barcode: food.barcode, category: food.category, spec: food.spec,
      calories: food.nutritionKnown ? food.calories : undefined, storage: food.storageType
    };
    const draft = this.makeDraft(seed);
    this.drafts = this.mode === 'batch' ? this.drafts.concat([draft]) : [draft];
  }

  private async scan(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (this.busy || context === undefined) return;
    this.busy = true;
    try {
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.ALL], enableMultiMode: false, enableAlbum: true
      };
      const result = await scanBarcode.startScanForResult(context, options);
      await this.addBarcode(result.originalValue.trim());
    } catch (error) {
      if ((error as BusinessError).code !== scanCore.ScanErrorCode.SCAN_SERVICE_CANCELED && this.shown) {
        this.toast($r('app.string.ui_no_scan_result_received'));
      }
    } finally {
      this.busy = false;
    }
  }

  private async addBarcode(code: string): Promise<void> {
    if (code.length === 0) return;
    if (this.mode === 'batch') {
      const same = this.drafts.find((draft: IntakeDraft): boolean =>
        draft.barcode === code && draft.expiry === 0 && draft.quantity < 99);
      if (same !== undefined) {
        same.quantity++;
        this.drafts = this.drafts.slice();
        return;
      }
    }
    const matched = await BarcodeService.getInstance().matchBarcodeInfo(code).catch(() => undefined);
    const previous = this.recent.find((item: FoodItem): boolean => item.barcode === code);
    const draft = this.makeDraft({
      name: matched?.name ?? previous?.name ?? '', barcode: code,
      category: matched?.category || previous?.category, spec: matched?.spec || previous?.spec,
      storage: previous?.storageType, calories: previous?.nutritionKnown ? previous.calories : undefined
    });
    this.drafts = this.mode === 'batch' ? this.drafts.concat([draft]) : [draft];
  }

  private async openBatchScanner(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (!context || this.busy) return;
    if (!canIUse('SystemCapability.Multimedia.Scan.ScanBarcode')) {
      await this.scan();
      return;
    }
    this.busy = true;
    let granted = false;
    try {
      const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, ['ohos.permission.CAMERA']);
      granted = permission.authResults[0] === 0;
    } catch (error) {
      console.warn('Could not request scanner permission: ' + error);
    } finally {
      this.busy = false;
    }
    if (!granted) {
      this.toast($r('app.string.intake_camera_unavailable'));
      return;
    }
    this.scanCount = 0;
    this.scanReady = false;
    this.showBatchScanner = true;
  }

  private startBatchCamera(): void {
    const session = ++this.scanSession;
    try {
      customScan.init({ scanTypes: [scanCore.ScanType.ALL], enableMultiMode: false });
      this.scanInitialized = true;
      customScan.start({ surfaceId: this.scanController.getXComponentSurfaceId(), width: 288, height: 204 },
        (error: BusinessError, results: scanBarcode.ScanResult[]) => {
          if (session !== this.scanSession) return;
          if (error) {
            this.toast($r('app.string.intake_camera_unavailable'));
            void this.closeBatchScanner();
            return;
          }
          const code = results[0]?.originalValue.trim() ?? '';
          if (!code || this.busy || this.scanReady) return;
          this.busy = true;
          void this.addBarcode(code).then(() => {
            if (session !== this.scanSession) return;
            this.scanCount++;
            this.scanReady = true;
          }).finally(() => { this.busy = false; });
        });
    } catch (error) {
      this.toast($r('app.string.intake_camera_unavailable'));
      void this.closeBatchScanner();
    }
  }

  private nextScan(): void {
    if (!this.scanReady) return;
    this.scanReady = false;
    try {
      customScan.rescan();
    } catch (error) {
      this.toast($r('app.string.intake_camera_unavailable'));
      void this.closeBatchScanner();
    }
  }

  private async closeBatchScanner(): Promise<void> {
    ++this.scanSession;
    if (!this.scanInitialized) {
      this.showBatchScanner = false;
      return;
    }
    this.scanInitialized = false;
    this.busy = true;
    try {
      await customScan.stop();
    } catch (error) {
      console.warn('Could not stop batch scanner: ' + error);
    }
    try {
      await customScan.release();
    } catch (error) {
      console.warn('Could not release batch scanner: ' + error);
    } finally {
      this.busy = false;
      this.showBatchScanner = false;
    }
  }

  private openNutrition(draft: IntakeDraft): void {
    const params: IntakeNutritionParams = {
      barcode: draft.barcode, name: draft.name, category: draft.category, spec: draft.spec,
      onApplied: (calories: number) => { draft.calorieText = calories.toString(); }
    };
    AppNavigation.push('CalorieInputPage', params);
  }

  private splitDraft(draft: IntakeDraft): void {
    if (draft.quantity < 2) return;
    const newDraft = this.makeDraft({
      name: draft.name, barcode: draft.barcode, category: draft.category, spec: draft.spec,
      calories: draft.calorieText.trim().length > 0 ? Number(draft.calorieText) : undefined,
      storage: draft.storage, photoUri: draft.photoUri
    });
    draft.quantity--;
    this.drafts = this.drafts.concat([newDraft]);
  }

  private applyStorage(storage: string): void {
    for (const draft of this.drafts) {
      draft.storage = storage;
      if (draft.estimated) draft.expiry = calculateExpiryTimestamp(draft.category || '其他', storage);
    }
    this.drafts = this.drafts.slice();
    this.showStorageOptions = false;
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
  }

  private async rememberProduct(item: FoodItem): Promise<void> {
    if (item.barcode.length === 0) return;
    const database = DatabaseHelper.getInstance();
    if (await database.queryProductDictByBarcode(item.barcode) === null) {
      // The database stores normalized label energy. An intake amount belongs to this entry.
      await BarcodeService.getInstance().saveToProductDict(item.barcode, item.name, item.category, item.spec, 0, 'manual');
    }
  }

  private async save(): Promise<void> {
    if (this.busy || this.drafts.length === 0) return;
    const items: FoodItem[] = [];
    const products: Map<string, FoodItem> = new Map<string, FoodItem>();
    for (const draft of this.drafts) {
      if (!draft.name.trim()) {
        this.toast($r('app.string.intake_name_needed'));
        return;
      }
      const text = draft.calorieText.trim();
      const kcal = text.length > 0 ? Number(text) : 0;
      if (!Number.isFinite(kcal) || kcal < 0) {
        this.toast($r('app.string.ui_enter_a_valid_energy_value'));
        return;
      }
      const item = new FoodItem();
      item.name = draft.name.trim();
      item.category = draft.category;
      item.spec = draft.spec.trim();
      item.barcode = draft.barcode;
      item.storageType = draft.storage;
      item.expiryDate = draft.expiry;
      item.expiryEstimated = draft.estimated;
      item.calories = kcal;
      item.nutritionKnown = text.length > 0;
      for (let unit = 0; unit < draft.quantity; unit++) items.push(item);
      if (item.barcode.length > 0) products.set(item.barcode, item);
    }
    this.busy = true;
    try {
      this.undoIds = await DatabaseHelper.getInstance().insertIntake(items);
      this.drafts = [];
      AppNavigation.notifyDataChanged();
      for (const item of products.values()) {
        try {
          await this.rememberProduct(item);
        } catch (error) {
          console.warn('Could not remember intake product: ' + error);
        }
      }
      this.loadRecent();
    } catch (error) {
      this.toast($r('app.string.ui_could_not_save_try_again'));
    } finally {
      this.busy = false;
    }
  }

  private async undo(): Promise<void> {
    if (this.busy || this.undoIds.length === 0) return;
    this.busy = true;
    try {
      await DatabaseHelper.getInstance().undoIntake(this.undoIds);
      this.undoIds = [];
      AppNavigation.notifyDataChanged();
      this.loadRecent();
      this.continueAdding();
    } catch (error) {
      this.toast($r('app.string.intake_undo_failed'));
    } finally {
      this.busy = false;
    }
  }

  private continueAdding(): void {
    this.undoIds = [];
    this.drafts = this.mode === 'batch' ? [] : [this.makeDraft()];
  }

  @Builder
  batchTools() {
    Row({ space: 8 }) {
      Button($r('app.string.ui_scan_to_add')).attributeModifier(FoodButtonStyle.compactPrimary)
        .layoutWeight(1).onClick(() => { void this.openBatchScanner(); })
      Button($r('app.string.ui_add_manually')).attributeModifier(FoodButtonStyle.compactSecondary)
        .layoutWeight(1).onClick(() => { this.drafts = this.drafts.concat([this.makeDraft()]); })
    }
    Row({ space: 8 }) {
      Button($r('app.string.ui_add_from_a_photo')).attributeModifier(FoodButtonStyle.text)
        .layoutWeight(1).onClick(() => { this.openImport('PhotoEntryPage'); })
      Button($r('app.string.ui_import_from_clipboard_2')).attributeModifier(FoodButtonStyle.text)
        .layoutWeight(1).onClick(() => { this.openImport('ClipboardParsePage'); })
    }
    if (this.drafts.length > 0) {
      Button($r('app.string.intake_batch_location')).attributeModifier(FoodButtonStyle.secondary)
        .width('100%').onClick(() => { this.showStorageOptions = !this.showStorageOptions; })
    }
    if (this.showStorageOptions) {
      Row({ space: 6 }) {
        ForEach([StorageType.FRIDGE, StorageType.FREEZER, StorageType.ROOM], (storage: StorageType) => {
          Button(getStorageTypeName(storage)).attributeModifier(FoodButtonStyle.compactNeutral)
            .layoutWeight(1).onClick(() => { this.applyStorage(storage); })
        })
      }
    }
  }

  @Builder
  batchScannerPanel() {
    Column({ space: 14 }) {
      XComponent({ id: 'intake-batch-camera', type: XComponentType.SURFACE, controller: this.scanController })
        .width(288).height(204).borderRadius(16)
        .onLoad(() => { this.startBatchCamera(); })
      Text(this.scanReady ? $r('app.string.intake_scan_count', this.scanCount) :
        $r('app.string.intake_scan_aim'))
        .fontSize(16).fontColor($r('app.color.text_primary'))
      Button($r('app.string.intake_scan_next')).attributeModifier(FoodButtonStyle.primary)
        .enabled(this.scanReady).onClick(() => { this.nextScan(); })
      Button($r('app.string.intake_done')).attributeModifier(FoodButtonStyle.secondary)
        .onClick(() => { void this.closeBatchScanner(); })
    }
    .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding(16)
  }

  build() {
    HdsNavDestination() {
      Column({ space: 8 }) {
        if (this.showBatchScanner) {
          this.batchScannerPanel()
        } else if (this.undoIds.length > 0) {
          Column({ space: 14 }) {
            Text($r('app.string.ui_added_d_items', this.undoIds.length)).fontSize(21).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Button($r('app.string.intake_continue')).attributeModifier(FoodButtonStyle.primary)
              .width('100%').onClick(() => { this.continueAdding(); })
            Button($r('app.string.intake_undo')).attributeModifier(FoodButtonStyle.neutral)
              .width('100%').onClick(() => { void this.undo(); })
            Button($r('app.string.intake_done')).attributeModifier(FoodButtonStyle.text)
              .onClick(() => { AppNavigation.pop(); })
          }
          .width('100%').padding(24).layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll(this.scroller) {
            Column({ space: 12 }) {
              if (this.mode === 'batch') {
                this.batchTools()
              } else if (this.mode === 'scan' && !this.drafts[0]?.barcode) {
                Button($r('app.string.ui_scan_to_add')).attributeModifier(FoodButtonStyle.compactSecondary)
                  .width('100%').onClick(() => { void this.scan(); })
              }
              ForEach(this.drafts, (draft: IntakeDraft) => {
                IntakeCard({
                  draft: draft, compact: this.mode === 'batch',
                  onDelete: () => {
                    this.drafts = this.drafts.filter((other: IntakeDraft): boolean => other.key !== draft.key);
                  },
                  onNutrition: () => { this.openNutrition(draft); },
                  onSplit: () => { this.splitDraft(draft); }
                })
              }, (draft: IntakeDraft): string => draft.key.toString())
              if (this.recent.length > 0) {
                Text($r('app.string.intake_recent')).fontSize(16).fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.recent, (item: FoodItem) => {
                    Button(item.name).attributeModifier(FoodButtonStyle.compactSecondary)
                      .margin({ right: 6, bottom: 6 }).onClick(() => { this.useRecent(item); })
                  }, (item: FoodItem): string => item.id.toString())
                }
              }
            }
            .width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, top: 8, bottom: 12 })
          }
          .layoutWeight(1).align(Alignment.Top)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).scrollBar(BarState.Off)
          Row() {
            Button(this.mode === 'batch' ? $r('app.string.ui_add_all_items') : $r('app.string.ui_add_to_inventory'))
              .attributeModifier(FoodButtonStyle.primary)
              .width('100%').enabled(!this.busy && this.drafts.length > 0)
              .onClick(() => { void this.save(); })
          }
          .width('100%').padding({ left: 16, right: 16, bottom: 16 })
        }
      }
      .enabled(!this.busy).width('100%').height('100%')
      .padding({ top: 12 + this.statusBarHeight })
      .backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      content: { title: { mainTitle: this.mode === 'batch' ? $r('app.string.ui_add_in_bulk_2') :
        $r('app.string.intake_quick_add') } },
      style: FOOD_TITLE_BAR_STYLE
    })
    .onShown(() => {
      this.shown = true;
      this.loadRecent();
      if (this.autoScan) {
        this.autoScan = false;
        void this.scan();
      }
    })
    .onHidden(() => {
      this.shown = false;
      if (this.showBatchScanner) void this.closeBatchScanner();
    })
    .onBackPressed((): boolean => {
      if (this.busy) return true;
      if (!this.showBatchScanner) return false;
      void this.closeBatchScanner();
      return true;
    })
  }
}

@Builder
export function BatchAddPageBuilder() {
  BatchAddPage()
}
