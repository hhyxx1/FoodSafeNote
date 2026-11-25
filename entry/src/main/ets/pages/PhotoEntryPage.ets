import { cacheRemoteFoodPhoto, canReceiveRemoteFoodPhoto } from '../common/RemoteFoodPhoto';
import { FoodButtonStyle, FoodMotion, FOOD_TITLE_BAR_STYLE } from '../common/FoodInterface';
import { resolveLocalizedText } from '../common/Constants';
import { localizedFoodLabel } from '../common/Constants';
import { cameraPicker, camera } from '@kit.CameraKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { FOOD_CATEGORIES, StorageType, getBaseDays, padZero } from '../common/Constants';
import {
  createCollaborationServiceMenuItems,
  CollaborationServiceStateDialog,
  CollaborationServiceFilter,
  CollaborationDeviceFilterType
} from '@kit.ServiceCollaborationKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppNavigation } from '../common/AppNavigation';

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
}

interface FoodKeywordItem {
  keyword: string;
  name: string;
  category: string;
}

@Component
struct PhotoEntryPage {
  @State photoUri: string = '';
  @State recognizedName: string = '';
  @State recognizedCategory: string = '其他';
  @State freshnessLevel: string = 'fresh';
  @State storageType: string = StorageType.FRIDGE;
  @State recognitionHint: ResourceStr = $r('app.string.ui_take_a_photo_to_start');
  @State estimatedExpiryText: string = '';
  @State showCollaborationButton: boolean = false;

  // 状态栏高度（vp），由 Index 写入 AppStorage；用于标题栏沉浸避让
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  @State isCapturingPhoto: boolean = false;
  private isPageActive: boolean = true;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.showCollaborationButton = canReceiveRemoteFoodPhoto();
  }

  @Builder
  collaborationMenu() {
    Menu() {
      createCollaborationServiceMenuItems([CollaborationServiceFilter.TAKE_PHOTO,
        CollaborationServiceFilter.IMAGE_PICKER], 1, [CollaborationDeviceFilterType.PHONE,
        CollaborationDeviceFilterType.TABLET, CollaborationDeviceFilterType.PC_2IN1]);
    }
  }

  private async takeFoodPhoto(): Promise<void> {
    if (!canIUse('SystemCapability.Multimedia.Camera.Core')) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_no_camera_is_available_add_the_item_manually'), duration: 2000 });
      } catch (e) {
        // Toast 展示失败时忽略
      }
      return;
    }

    if (this.isCapturingPhoto) return;
    this.isCapturingPhoto = true;
    try {
      const ctx: Context = this.getUIContext().getHostContext() as Context;
      const captureUri: string = ctx.cacheDir + '/photo_entry_' + Date.now().toString() + '.jpg';
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
        saveUri: captureUri,
        videoDuration: 0
      };
      const result: cameraPicker.PickerResult =
        await cameraPicker.pick(ctx, [cameraPicker.PickerMediaType.PHOTO], profile);

      if (result.resultUri !== undefined && result.resultUri.length > 0) {
        this.photoUri = result.resultUri;
        await this.analyzePhotoAndSuggest();
      }
    } catch (error) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_could_not_take_a_photo_try_again'), duration: 1500 });
      } catch (e) {
        // Toast 展示失败时忽略
      }
    } finally {
      this.isCapturingPhoto = false;
    }
  }

  private async analyzePhotoAndSuggest(): Promise<void> {
    this.recognitionHint = $r('app.string.ui_scanning_the_photo');

    if (!canIUse('SystemCapability.AI.OCR.TextRecognition')) {
      this.recognitionHint = $r('app.string.ui_automatic_recognition_is_unavailable_enter_the_details_manually');
      this.updateEstimatedExpiry();
      return;
    }

    const pixelMap: image.PixelMap | null = await this.getPixelMapFromUri(this.photoUri);
    if (pixelMap === null) {
      this.recognitionHint = $r('app.string.ui_could_not_read_the_image_enter_the_details_manually');
      this.updateEstimatedExpiry();
      return;
    }

    let recognizedText: string = '';
    try {
      recognizedText = await this.recognizeTextFromPixelMap(pixelMap);
    } finally {
      pixelMap.release();
    }

    if (!this.isPageActive) return;
    this.applySuggestionsFromText(recognizedText);
    this.updateEstimatedExpiry();
  }

  private async recognizeTextFromPixelMap(pixelMap: image.PixelMap): Promise<string> {
    try {
      const visionInfo: textRecognition.VisionInfo = {
        pixelMap: pixelMap
      };
      const result: textRecognition.TextRecognitionResult = await textRecognition.recognizeText(visionInfo);
      return result.value !== undefined ? result.value : '';
    } catch (error) {
      return '';
    }
  }

  private async onCollaborationState(stateCode: number, bufferType: string, buffer: ArrayBuffer): Promise<void> {
    if (!this.isPageActive || stateCode !== 0 || bufferType !== 'general.image' || !buffer || buffer.byteLength === 0 ||
      this.isCapturingPhoto) {
      return;
    }

    this.isCapturingPhoto = true;
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) return;
      this.photoUri = cacheRemoteFoodPhoto(context, buffer);
      await this.analyzePhotoAndSuggest();
    } catch (error) {
      if (this.isPageActive) {
        this.recognitionHint = $r('app.string.food_could_not_process_remote_photo');
      }
    } finally {
      this.isCapturingPhoto = false;
    }
  }

  private applySuggestionsFromText(text: string): void {
    const raw: string = text.trim();
    if (raw.length === 0) {
      this.recognitionHint = $r('app.string.ui_no_usable_text_found_review_the_food_details_manually');
      this.recognizedName = this.recognizedName.length > 0 ? this.recognizedName : '';
      this.recognizedCategory = this.recognizedCategory.length > 0 ? this.recognizedCategory : '其他';
      this.freshnessLevel = 'fresh';
      return;
    }

    const lower: string = raw.toLowerCase();
    const foodKeywords: FoodKeywordItem[] = [
      { keyword: '苹果', name: '苹果', category: '水果' },
      { keyword: '香蕉', name: '香蕉', category: '水果' },
      { keyword: '橙', name: '橙子', category: '水果' },
      { keyword: '番茄', name: '番茄', category: '蔬菜' },
      { keyword: '西红柿', name: '番茄', category: '蔬菜' },
      { keyword: '黄瓜', name: '黄瓜', category: '蔬菜' },
      { keyword: '生菜', name: '生菜', category: '蔬菜' },
      { keyword: '菠菜', name: '菠菜', category: '蔬菜' },
      { keyword: '白菜', name: '白菜', category: '蔬菜' },
      { keyword: '牛肉', name: '牛肉', category: '肉类' },
      { keyword: '猪肉', name: '猪肉', category: '肉类' },
      { keyword: '鸡肉', name: '鸡肉', category: '肉类' },
      { keyword: '鱼', name: '鲜鱼', category: '海鲜' },
      { keyword: '虾', name: '鲜虾', category: '海鲜' },
      { keyword: '牛奶', name: '牛奶', category: '乳制品' },
      { keyword: '酸奶', name: '酸奶', category: '乳制品' }
    ];

    for (let i = 0; i < foodKeywords.length; i++) {
      const item = foodKeywords[i];
      if (lower.indexOf(item.keyword) >= 0) {
        this.recognizedName = item.name;
        this.recognizedCategory = item.category;
        this.freshnessLevel = this.inferFreshness(raw);
        this.recognitionHint = $r('app.string.ui_detected_s_editable', item.name);
        return;
      }
    }

    const firstLine: string = raw.split('\n')[0].trim();
    this.recognizedName = firstLine.length > 12 ? firstLine.substring(0, 12) : firstLine;
    this.recognizedCategory = '其他';
    this.freshnessLevel = this.inferFreshness(raw);
    this.recognitionHint = $r('app.string.ui_text_detected_and_suggestions_generated_you_can_edit_them');
  }

  private inferFreshness(text: string): string {
    const lower: string = text.toLowerCase();
    if (
      lower.indexOf('变质') >= 0 ||
      lower.indexOf('腐') >= 0 ||
      lower.indexOf('坏') >= 0 ||
      lower.indexOf('酸败') >= 0
    ) {
      return 'stale';
    }
    if (
      lower.indexOf('即食') >= 0 ||
      lower.indexOf('熟透') >= 0 ||
      lower.indexOf('切片') >= 0 ||
      lower.indexOf('开封') >= 0
    ) {
      return 'normal';
    }
    return 'fresh';
  }

  private getFreshnessFactor(): number {
    if (this.freshnessLevel === 'stale') {
      return 0.4;
    }
    if (this.freshnessLevel === 'normal') {
      return 0.7;
    }
    return 1;
  }

  private getStorageFactor(): number {
    if (this.storageType === StorageType.FREEZER) {
      return 10;
    }
    if (this.storageType === StorageType.ROOM) {
      return 0.5;
    }
    return 1;
  }

  private updateEstimatedExpiry(): void {
    const category: string = this.recognizedCategory.length > 0 ? this.recognizedCategory : '其他';
    let baseDays: number = getBaseDays(category);
    if (baseDays <= 0) {
      baseDays = 7;
    }
    const days: number = Math.max(1, Math.round(baseDays * this.getStorageFactor() * this.getFreshnessFactor()));
    const expiry: Date = new Date(Date.now() + days * 24 * 60 * 60 * 1000);
    this.estimatedExpiryText = resolveLocalizedText(this.getUIContext().getHostContext(), $r('app.string.ui_s_about_d_days_left').id, this.formatDate(expiry), days);
  }

  private formatDate(date: Date): string {
    return date.toLocaleDateString();
  }

  private async getPixelMapFromUri(uri: string): Promise<image.PixelMap | null> {
    const uriCandidates: string[] = this.buildUriCandidates(uri);
    for (let i = 0; i < uriCandidates.length; i++) {
      const candidate: string = uriCandidates[i];
      try {
        const fileSource = await fs.open(candidate, fs.OpenMode.READ_ONLY);
        try {
          const imgSource: image.ImageSource = image.createImageSource(fileSource.fd);
          try {
            const pixelMap: image.PixelMap = await imgSource.createPixelMap();
            return pixelMap;
          } finally {
            imgSource.release();
          }
        } finally {
          fs.close(fileSource);
        }
      } catch (e) {
      }
    }
    return null;
  }

  private buildUriCandidates(uri: string): string[] {
    const list: string[] = [];
    const raw: string = uri.trim();
    if (raw.length === 0) {
      return list;
    }
    list.push(raw);
    if (raw.startsWith('file://')) {
      list.push(raw.substring(7));
    }
    if (!raw.startsWith('/')) {
      list.push('/' + raw);
    }
    return list;
  }

  private goToAddFood(): void {
    const params: AddFoodParams = {
      barcode: '',
      name: this.recognizedName,
      category: this.recognizedCategory,
      spec: '',
      calories: 0,
      fromBarcodeScan: false,
      fromPhotoCapture: true,
      photoUri: this.photoUri,
      storageType: this.storageType,
      freshnessLevel: this.freshnessLevel
    };
    try {
      AppNavigation.push('AddFoodPage', params);
    } catch (e) {
      // 路由跳转失败时忽略
    }
  }

  build() {
    HdsNavDestination() {
    Column() {
      if (this.showCollaborationButton) {
        CollaborationServiceStateDialog({
          onState: (stateCode: number, bufferType: string, buffer: ArrayBuffer): void => {
            this.onCollaborationState(stateCode, bufferType, buffer);
          }
        })
      }

      Scroll(this.scroller) {
        Column({ space: 12 }) {
          Column({ space: 10 }) {
            if (this.photoUri.length > 0) {
              Image(this.photoUri)
                .width('100%').height(150).borderRadius(14).draggable(false).objectFit(ImageFit.Cover)
                .transition(FoodMotion.reveal())
            } else {
              SymbolGlyph($r('sys.symbol.camera'))
                .fontSize(30).fontColor([$r('app.color.journal_hero_text')])
            }
            Text($r('app.string.ui_take_a_photo_to_get_suggestions_for_category_freshness_and_shelf_life'))
              .fontSize(14).fontColor($r('app.color.journal_hero_secondary')).width('100%')
            Button(this.photoUri.length > 0 ? $r('app.string.ui_retake_photo') : $r('app.string.ui_take_a_food_photo'))
              .attributeModifier(this.photoUri.length > 0 ? FoodButtonStyle.secondary : FoodButtonStyle.primary)
              .width('100%')
              .enabled(!this.isCapturingPhoto)
              .onClick(() => { this.takeFoodPhoto(); })
          }
          .width('100%').alignItems(HorizontalAlign.Start).padding(16)
          .backgroundColor($r('app.color.journal_hero_bg')).borderRadius(22)

          if (this.showCollaborationButton) {
            Button($r('app.string.food_pick_remote_photo'))
              .attributeModifier(FoodButtonStyle.secondary)
              .width('100%')
              .enabled(!this.isCapturingPhoto)
              .bindMenu(this.collaborationMenu)
          }

          Column({ space: 8 }) {
            Text($r('app.string.ui_scan_result'))
              .fontSize(18).fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text(this.recognitionHint)
              .fontSize(14)
              .fontColor($r('app.color.text_hint'))

            TextInput({ text: this.recognizedName, placeholder: $r('app.string.ui_detected_food_name_editable') })
              .width('100%')
              .height(44)
              .fontSize(15)
              .borderRadius(8)
              .backgroundColor($r('app.color.input_background'))
              .onChange((value: string) => {
                this.recognizedName = value;
              })

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(FOOD_CATEGORIES, (category: string) => {
                Text(localizedFoodLabel(category))
                  .fontSize(12)
                  .fontColor(this.recognizedCategory === category ? $r('app.color.button_primary_text') : $r('app.color.button_neutral_text'))
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .margin({ right: 8, bottom: 8 })
                  .borderRadius(14)
                  .backgroundColor(this.recognizedCategory === category ? $r('app.color.button_primary_bg') : $r('app.color.button_neutral_bg'))
                  .onClick(() => {
                    this.recognizedCategory = category;
                    this.updateEstimatedExpiry();
                  })
              }, (category: string) => category)
            }
            .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(18)

          Column({ space: 8 }) {
            Text($r('app.string.ui_freshness'))
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Row({ space: 8 }) {
              this.buildTag($r('app.string.ui_fresh'), 'fresh')
              this.buildTag($r('app.string.ui_fair'), 'normal')
              this.buildTag($r('app.string.ui_poor'), 'stale')
            }

            Text($r('app.string.ui_storage_conditions'))
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Row({ space: 8 }) {
              this.buildStorageTag($r('app.string.ui_refrigerated'), StorageType.FRIDGE)
              this.buildStorageTag($r('app.string.ui_frozen'), StorageType.FREEZER)
              this.buildStorageTag($r('app.string.ui_room_temperature'), StorageType.ROOM)
            }

            Text($r('app.string.ui_estimated_expiry_s', this.estimatedExpiryText.length > 0 ? this.estimatedExpiryText : '—'))
              .fontSize(13)
              .fontColor($r('app.color.accent_link'))
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(18)

          Button($r('app.string.ui_next_review_and_add'))
            .attributeModifier(FoodButtonStyle.primary)
            .width('100%')
            .enabled(!this.isCapturingPhoto && this.recognizedName.trim().length > 0)
            .onClick(() => {
              this.goToAddFood();
            })

          Button($r('app.string.ui_skip_photo_and_add_manually'))
            .attributeModifier(FoodButtonStyle.text)
            .width('100%')
            .onClick(() => {
              AppNavigation.push('AddFoodPage');
            })
        }
        // 标题栏沉浸避让：状态栏高度 + 标题栏高度(56vp)
        .padding({ left: 20, right: 20, top: 56 + this.statusBarHeight, bottom: 24 })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      content: {
        title: { mainTitle: $r('app.string.ui_add_from_a_photo') }
      },
      style: FOOD_TITLE_BAR_STYLE
    })
    .bindToScrollable([this.scroller])
    .onShown(() => { this.isPageActive = true; })
    .onHidden(() => {
      this.isPageActive = false;
      AppNavigation.notifyDataChanged();
    })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  buildTag(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.freshnessLevel === value ? $r('app.color.button_primary_text') : $r('app.color.button_neutral_text'))
      .textAlign(TextAlign.Center)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .height(40)
      .constraintSize({ minWidth: 56 })
      .borderRadius(16)
      .backgroundColor(this.freshnessLevel === value ? $r('app.color.button_primary_bg') : $r('app.color.button_neutral_bg'))
      .onClick(() => {
        this.freshnessLevel = value;
        this.updateEstimatedExpiry();
      })
  }

  @Builder
  buildStorageTag(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.storageType === value ? $r('app.color.button_primary_text') : $r('app.color.button_neutral_text'))
      .textAlign(TextAlign.Center)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .height(40)
      .constraintSize({ minWidth: 56 })
      .borderRadius(16)
      .backgroundColor(this.storageType === value ? $r('app.color.button_primary_bg') : $r('app.color.button_neutral_bg'))
      .onClick(() => {
        this.storageType = value;
        this.updateEstimatedExpiry();
      })
  }
}

// Navigation 系统路由表入口（router_map.json 中注册为 PhotoEntryPage）
@Builder
export function PhotoEntryPageBuilder() {
  PhotoEntryPage()
}
