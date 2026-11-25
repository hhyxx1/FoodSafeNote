import { cacheRemoteFoodPhoto, canReceiveRemoteFoodPhoto, removeRemoteFoodPhoto } from '../common/RemoteFoodPhoto';
import { FoodButtonStyle, FoodMotion, FOOD_TITLE_BAR_STYLE } from '../common/FoodInterface';
import { scanBarcode, scanCore, detectBarcode } from '@kit.ScanKit';
import {
  createCollaborationServiceMenuItems,
  CollaborationServiceStateDialog,
  CollaborationServiceFilter,
  CollaborationDeviceFilterType
} from '@kit.ServiceCollaborationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BarcodeService } from '../common/BarcodeService';
import { BarcodeMatchResult } from '../model/DataModels';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppNavigation } from '../common/AppNavigation';

// 条码校验弹窗参数接口
interface BarcodeVerifyResult {
  confirmed: boolean;
  name: string;
  category: string;
  spec: string;
}

// 路由参数接口
interface CaloriePageParams {
  barcode: string;
  name: string;
  category: string;
  spec: string;
  amount?: number;
  amountUnit?: string;
}

interface ParsedAmountResult {
  amount: number;
  unit: string;
}

@Component
struct BarcodeScanPage {
  @State barcodeInput: string = '';
  @State isMatching: boolean = false;
  @State batchScanMode: boolean = false;
  @State isScannerOpen: boolean = false;
  @State showVerifyDialog: boolean = false;
  @State matchedName: string = '';
  @State matchedCategory: string = '';
  @State matchedSpec: string = '';
  @State currentBarcode: string = '';
  @State matchSource: string = '';
  @State forceAlbumMode: boolean = false;
  @State showCollaborationButton: boolean = false;
  private isPageActive: boolean = true;

  // 状态栏高度（vp），由 Index 写入 AppStorage；用于标题栏沉浸避让
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  aboutToAppear(): void {
    // 2in1 机型普遍无本地摄像头，默认使用相册/协同路径
    this.forceAlbumMode = deviceInfo.deviceType === '2in1' || !canIUse('SystemCapability.Multimedia.Camera.Core');
    // 协同服务仅支持从更大设备发起到更便携设备，手机端不展示远端设备菜单
    this.showCollaborationButton = canReceiveRemoteFoodPhoto() &&
      canIUse('SystemCapability.Multimedia.Scan.ScanBarcode');
  }

  @Builder
  collaborationMenu() {
    Menu() {
      createCollaborationServiceMenuItems([CollaborationServiceFilter.TAKE_PHOTO,
        CollaborationServiceFilter.IMAGE_PICKER], 1, [CollaborationDeviceFilterType.PHONE,
        CollaborationDeviceFilterType.TABLET, CollaborationDeviceFilterType.PC_2IN1]);
    }
  }

  private async onCollaborationState(stateCode: number, bufferType: string, buffer: ArrayBuffer): Promise<void> {
    if (!this.isPageActive || stateCode !== 0 || bufferType !== 'general.image' || !buffer || buffer.byteLength === 0 ||
      this.isScannerOpen || this.isMatching) {
      return;
    }

    this.isScannerOpen = true;
    let uri = '';
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) return;
      uri = cacheRemoteFoodPhoto(context, buffer);
      await this.scanImage(uri);
    } catch (error) {
      if (this.isPageActive) {
        this.getUIContext().getPromptAction().showToast({
          message: $r('app.string.ui_could_not_scan_the_photo_enter_the_barcode_manually'), duration: 2000
        });
      }
    } finally {
      if (uri.length > 0) removeRemoteFoodPhoto(uri);
      this.isScannerOpen = false;
    }
  }

  private handleScanResult(result: scanBarcode.ScanResult | null | undefined): void {
    if (result === null || result === undefined) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_no_scan_result_received'), duration: 1500 });
      } catch (e) {
        // Toast 展示失败时忽略
      }
      return;
    }
    const code: string = (typeof result.originalValue === 'string') ? result.originalValue : '';
    if (code.length > 0) {
      this.barcodeInput = code;
      this.handleBarcodeMatch(code);
      return;
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_no_barcode_detected_try_again'), duration: 1500 });
    } catch (e) {
      // Toast 展示失败时忽略
    }
  }

  private async startScanFromAlbum(): Promise<void> {
    if (this.isScannerOpen) return;
    this.isScannerOpen = true;
    try {
      const photoOption = new photoAccessHelper.PhotoSelectOptions();
      photoOption.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoOption.maxSelectNumber = 1;
      photoOption.isEditSupported = false;
      const picker = new photoAccessHelper.PhotoViewPicker();
      const photoResult = await picker.select(photoOption);
      if (!photoResult || photoResult.photoUris.length === 0) {
        return;
      }
      await this.scanImage(photoResult.photoUris[0]);
    } catch (error) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_could_not_scan_the_photo_enter_the_barcode_manually'), duration: 2000 });
      } catch (e) {
        // Toast 展示失败时忽略
      }
    } finally {
      this.isScannerOpen = false;
    }
  }

  private parseAmountFromSpec(spec: string): ParsedAmountResult {
    const text: string = spec.trim();
    if (text.length === 0) {
      return { amount: 0, unit: 'g' };
    }
    const matchWithUnit: RegExpMatchArray | null = text.match(new RegExp('(\\d+(?:\\.\\d+)?)\\s*(g|G|克|kg|KG|千克|ml|mL|ML|毫升|l|L|升)'));
    if (matchWithUnit !== null && matchWithUnit.length >= 3) {
      const value: number = Number(matchWithUnit[1]) || 0;
      const unitToken: string = matchWithUnit[2];
      if (unitToken === 'kg' || unitToken === 'KG' || unitToken === '千克') {
        return { amount: Math.round(value * 1000), unit: 'g' };
      }
      if (unitToken === 'l' || unitToken === 'L' || unitToken === '升') {
        return { amount: Math.round(value * 1000), unit: 'ml' };
      }
      const unit: string = (unitToken.indexOf('ml') >= 0 || unitToken.indexOf('mL') >= 0 || unitToken.indexOf('毫升') >= 0)
        ? 'ml' : 'g';
      return { amount: value, unit: unit };
    }

    // 兜底：若规格仅数字，默认按g处理
    const pureNumber: RegExpMatchArray | null = text.match(new RegExp('(\\d+(?:\\.\\d+)?)'));
    if (pureNumber !== null && pureNumber.length > 1) {
      return { amount: Number(pureNumber[1]) || 0, unit: 'g' };
    }
    return { amount: 0, unit: 'g' };
  }

  private async scanImage(uri: string): Promise<void> {
    const inputImage: detectBarcode.InputImage = { uri: uri };
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: false,
      enableAlbum: true
    };
    const results: Array<scanBarcode.ScanResult> = await detectBarcode.decode(inputImage, options);
    if (!this.isPageActive) return;
    if (results.length > 0) {
      this.handleScanResult(results[0]);
    } else {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_no_barcode_found_in_the_image'), duration: 1700 });
    }
  }

  private async startScan(): Promise<void> {
    if (this.isScannerOpen || this.isMatching) return;
    if (this.forceAlbumMode) {
      await this.startScanFromAlbum();
      return;
    }
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: this.batchScanMode,
      enableAlbum: true
    };
    this.isScannerOpen = true;
    try {
      await scanBarcode.startScanForResult(this.getUIContext().getHostContext(), options)
        .then((result: scanBarcode.ScanResult) => {
          this.handleScanResult(result);
        });
      return;
    } catch (error) {
      if ((error as BusinessError).code === scanCore.ScanErrorCode.SCAN_SERVICE_CANCELED) return;
    } finally {
      this.isScannerOpen = false;
    }
    await this.startScanFromAlbum();
  }

  // 条码匹配
  private handleBarcodeMatch(barcode: string): void {
    if (this.isMatching) return;
    this.isMatching = true;
    this.currentBarcode = barcode;
    BarcodeService.getInstance().matchBarcodeInfo(barcode).then((result: BarcodeMatchResult) => {
      this.isMatching = false;
      if (!this.isPageActive) return;
      if (result.matched) {
        this.matchedName = result.name;
        this.matchedCategory = result.category;
        this.matchedSpec = result.spec;
        this.matchSource = result.source;
      } else {
        this.matchedName = '';
        this.matchedCategory = '';
        this.matchedSpec = '';
        this.matchSource = '';
      }
      this.showVerifyDialog = true;
    }).catch(() => {
      this.isMatching = false;
      if (!this.isPageActive) return;
      this.matchedName = '';
      this.matchedCategory = '';
      this.matchedSpec = '';
      this.matchSource = '';
      this.showVerifyDialog = true;
    });
  }

  // 确认后跳转热量页
  private confirmAndProceed(): void {
    if (this.matchedName.trim().length === 0) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_enter_a_product_name'), duration: 1500 });
      } catch (e) {
        // Toast 展示失败时忽略
      }
      return;
    }
    // 存入ProductDict
    let source: string = 'manual';
    if (this.matchSource === 'product_dict') {
      source = 'edited';
    } else if (this.matchSource === 'builtin') {
      source = 'builtin';
    }
    BarcodeService.getInstance().saveToProductDict(
      this.currentBarcode, this.matchedName.trim(),
      this.matchedCategory, this.matchedSpec, 0, source
    ).catch(() => {
      // 产品字典写入失败不阻断跳转
    });
    this.showVerifyDialog = false;
    const parsedAmount: ParsedAmountResult = this.parseAmountFromSpec(this.matchedSpec);
    // 跳转到热量获取页
    const params: CaloriePageParams = {
      barcode: this.currentBarcode,
      name: this.matchedName.trim(),
      category: this.matchedCategory,
      spec: this.matchedSpec,
      amount: parsedAmount.amount,
      amountUnit: parsedAmount.unit
    };
    try {
      AppNavigation.push('CalorieInputPage', params);
    } catch (e) {
      // 路由跳转失败时忽略
    }
  }

  build() {
    HdsNavDestination() {
    Stack() {
      Column() {
        if (this.showCollaborationButton) {
          CollaborationServiceStateDialog({
            onState: (stateCode: number, bufferType: string, buffer: ArrayBuffer): void => {
              this.onCollaborationState(stateCode, bufferType, buffer);
            }
          })
        }

        Scroll() {
          Column({ space: 14 }) {
            Column({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.barcode_viewfinder'))
                .fontSize(36).fontColor([$r('app.color.journal_hero_text')])
              Text(this.forceAlbumMode ? $r('app.string.ui_no_camera_found_scan_a_photo_or_use_a_connected_device') :
                $r('app.string.ui_point_the_camera_at_a_barcode'))
                .fontSize(14).fontColor($r('app.color.journal_hero_secondary')).width('100%')
              Button(this.forceAlbumMode ? $r('app.string.ui_scan_a_photo') : $r('app.string.ui_start_scanning'))
                .attributeModifier(FoodButtonStyle.primary)
                .width('100%')
                .enabled(!this.isScannerOpen && !this.isMatching)
                .onClick(() => { this.startScan(); })
            }
            .width('100%').padding(18).alignItems(HorizontalAlign.Start)
            .backgroundColor($r('app.color.journal_hero_bg')).borderRadius(22)

            if (!this.forceAlbumMode || this.showCollaborationButton) {
              Row({ space: 8 }) {
                if (!this.forceAlbumMode) {
                  Button($r('app.string.ui_scan_a_photo'))
                    .attributeModifier(FoodButtonStyle.text)
                    .layoutWeight(1)
                    .enabled(!this.isScannerOpen && !this.isMatching)
                    .onClick(() => { this.startScanFromAlbum(); })
                }
                if (this.showCollaborationButton) {
                  Button($r('app.string.food_scan_remote_photo'))
                    .attributeModifier(FoodButtonStyle.text)
                    .layoutWeight(1)
                    .enabled(!this.isScannerOpen && !this.isMatching)
                    .bindMenu(this.collaborationMenu)
                }
              }
              .width('100%')
            }

            Column({ space: 10 }) {
              Text($r('app.string.ui_or_enter_the_barcode_manually'))
                .fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
              Row({ space: 8 }) {
                TextInput({ text: this.barcodeInput, placeholder: $r('app.string.ui_enter_a_barcode_e_g_6901234567890') })
                  .layoutWeight(1).height(48).fontSize(15).borderRadius(12)
                  .fontColor($r('app.color.text_primary')).placeholderColor($r('app.color.text_hint'))
                  .backgroundColor($r('app.color.input_background')).type(InputType.Number)
                  .onChange((value: string) => { this.barcodeInput = value; })
                Button($r('app.string.ui_match'))
                  .attributeModifier(FoodButtonStyle.secondary)
                  .enabled(!this.isMatching && this.barcodeInput.trim().length > 0)
                  .onClick(() => { this.handleBarcodeMatch(this.barcodeInput.trim()); })
              }
              .width('100%')
              if (this.isMatching) {
                Row({ space: 8 }) {
                  LoadingProgress().width(20).height(20).color($r('app.color.accent_link'))
                  Text($r('app.string.ui_looking_up_barcode'))
                    .fontSize(14).fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .transition(FoodMotion.reveal())
              }
            }
            .width('100%').padding(16).backgroundColor($r('app.color.card_background')).borderRadius(20)

            Column({ space: 8 }) {
              Row({ space: 10 }) {
                Column({ space: 4 }) {
                  Text($r('app.string.ui_batch_scanning'))
                    .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  Text($r('app.string.ui_turn_on_to_scan_multiple_codes_use_add_in_bulk_for_more_control'))
                    .fontSize(13).fontColor($r('app.color.text_secondary'))
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.batchScanMode })
                  .selectedColor($r('app.color.button_primary_bg'))
                  .onChange((isOn: boolean) => { this.batchScanMode = isOn; })
              }.width('100%')
              Button($r('app.string.ui_add_in_bulk'))
                .attributeModifier(FoodButtonStyle.text)
                .onClick(() => { AppNavigation.push('BatchAddPage'); })
            }
            .width('100%').padding(16).backgroundColor($r('app.color.card_background')).borderRadius(20)
          }
          .width('100%').padding({ left: 18, right: 18, top: 12, bottom: 24 })
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
      // 标题栏沉浸避让：状态栏高度 + 标题栏高度(56vp)
      .padding({ top: 56 + this.statusBarHeight })

      // 条码信息校验弹窗
      if (this.showVerifyDialog) {
        Column() {
          // 遮罩
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor($r('app.color.overlay_background'))
            .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
            .onClick(() => {
              this.showVerifyDialog = false;
            })
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })

        Column({ space: 16 }) {
          // 标题
          Text(this.matchSource.length > 0 ? $r('app.string.ui_review_barcode_details_editable') : $r('app.string.ui_no_barcode_match_enter_product_details'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          // 条码（不可修改）
          Column({ space: 4 }) {
            Text($r('app.string.ui_barcode'))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Text(this.currentBarcode)
              .fontSize(15)
              .fontColor($r('app.color.text_hint'))
              .width('100%')
              .height(40)
              .padding({ left: 12 })
              .backgroundColor($r('app.color.chip_background'))
              .borderRadius(8)
          }

          // 商品名称（必填）
          Column({ space: 4 }) {
            Row() {
              Text($r('app.string.ui_product_name'))
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
              Text(' *')
                .fontSize(13)
                .fontColor($r('app.color.status_danger'))
            }
            TextInput({ text: this.matchedName, placeholder: $r('app.string.ui_e_g_milk_plain_potato_chips') })
              .width('100%')
              .height(40)
              .fontSize(14)
              .borderRadius(8)
              .backgroundColor($r('app.color.input_background'))
              .onChange((value: string) => {
                this.matchedName = value;
              })
          }

          // 品类
          Column({ space: 4 }) {
            Text($r('app.string.ui_category_optional'))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.matchedCategory, placeholder: $r('app.string.ui_e_g_dairy_snacks') })
              .width('100%')
              .height(40)
              .fontSize(14)
              .borderRadius(8)
              .backgroundColor($r('app.color.input_background'))
              .onChange((value: string) => {
                this.matchedCategory = value;
              })
          }

          // 规格
          Column({ space: 4 }) {
            Text($r('app.string.ui_package_size_optional'))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.matchedSpec, placeholder: $r('app.string.ui_e_g_250_ml_100_g') })
              .width('100%')
              .height(40)
              .fontSize(14)
              .borderRadius(8)
              .backgroundColor($r('app.color.input_background'))
              .onChange((value: string) => {
                this.matchedSpec = value;
              })
          }

          Row({ space: 6 }) {
            Image($r('app.media.icon_info')).width(14).height(14).draggable(false)
            Text($r('app.string.ui_package_size_is_used_to_suggest_the_amount_to_add'))
              .fontSize(12)
              .fontColor($r('app.color.text_hint'))
              .width('100%').layoutWeight(1)
          }
          .width('100%')

          // 按钮
          Row({ space: 12 }) {
            Button($r('app.string.ui_cancel'))
              .attributeModifier(FoodButtonStyle.neutral)
              .layoutWeight(1)
              .onClick(() => {
                this.showVerifyDialog = false;
              })
            Button($r('app.string.ui_confirm'))
              .attributeModifier(FoodButtonStyle.primary)
              .layoutWeight(1)
              .onClick(() => {
                this.confirmAndProceed();
              })
          }
          .width('100%')
        }
        .width('85%')
        .constraintSize({ minWidth: 320, maxWidth: 560 })
        .padding(20)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .transition(FoodMotion.panel())
        .position({ x: '7.5%', y: '20%' })
      }
    }
    .width('100%')
    .height('100%')
    .animation({ duration: 260, curve: Curve.EaseInOut })
    }
    .titleBar({
      content: {
        title: { mainTitle: $r('app.string.ui_scan_a_barcode') }
      },
      style: FOOD_TITLE_BAR_STYLE
    })
    .onShown(() => { this.isPageActive = true; })
    .onHidden(() => {
      this.isPageActive = false;
      AppNavigation.notifyDataChanged();
    })
    .backgroundColor($r('app.color.page_background'))
  }
}

// Navigation 系统路由表入口（router_map.json 中注册为 BarcodeScanPage）
@Builder
export function BarcodeScanPageBuilder() {
  BarcodeScanPage()
}
