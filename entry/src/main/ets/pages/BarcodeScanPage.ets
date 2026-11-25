import { IntakeParams, IntakeSeed } from '../common/FoodIntake';
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
@Component
struct BarcodeScanPage {
  @State barcodeInput: string = '';
  @State isMatching: boolean = false;
  @State batchScanMode: boolean = false;
  @State isScannerOpen: boolean = false;
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

  private handleBarcodeMatch(barcode: string): void {
    if (this.isMatching) return;
    this.isMatching = true;
    BarcodeService.getInstance().matchBarcodeInfo(barcode).then((result: BarcodeMatchResult) => {
      this.openIntake(barcode, result);
    }).catch(() => {
      this.openIntake(barcode);
    }).finally(() => {
      this.isMatching = false;
    });
  }

  private openIntake(barcode: string, result?: BarcodeMatchResult): void {
    if (!this.isPageActive) return;
    const seed: IntakeSeed = {
      barcode: barcode, name: result?.name ?? '', category: result?.category, spec: result?.spec
    };
    const params: IntakeParams = { mode: 'single', seeds: [seed] };
    AppNavigation.replace('BatchAddPage', params);
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
