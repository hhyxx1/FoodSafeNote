import { router, promptAction } from '@kit.ArkUI';
import { scanBarcode, scanCore, detectBarcode } from '@kit.ScanKit';
import {
  createCollaborationServiceMenuItems,
  CollaborationServiceStateDialog,
  CollaborationServiceFilter
} from '@kit.ServiceCollaborationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BarcodeService } from '../common/BarcodeService';
import { BarcodeMatchResult } from '../model/DataModels';

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

@Entry
@Component
struct BarcodeScanPage {
  @State barcodeInput: string = '';
  @State isMatching: boolean = false;
  @State batchScanMode: boolean = false;
  @State showVerifyDialog: boolean = false;
  @State matchedName: string = '';
  @State matchedCategory: string = '';
  @State matchedSpec: string = '';
  @State currentBarcode: string = '';
  @State matchSource: string = '';
  @State forceAlbumMode: boolean = false;

  aboutToAppear(): void {
    // 2in1 机型普遍无本地摄像头，默认使用相册/协同路径
    this.forceAlbumMode = deviceInfo.deviceType === '2in1' || !canIUse('SystemCapability.Multimedia.Camera.Core');
  }

  @Builder
  collaborationMenu() {
    Menu() {
      createCollaborationServiceMenuItems([CollaborationServiceFilter.ALL]);
    }
  }

  private decodeBufferToText(buffer: ArrayBuffer): string {
    const bytes: Uint8Array = new Uint8Array(buffer);
    let text: string = '';
    for (let i = 0; i < bytes.length; i++) {
      text = text + String.fromCharCode(bytes[i]);
    }
    return text;
  }

  private extractBarcodeFromPayload(payload: string): string {
    const txt: string = payload.trim();
    if (txt.length === 0) {
      return '';
    }

    // 优先尝试JSON载荷
    if (txt.startsWith('{') && txt.endsWith('}')) {
      try {
        const obj: Record<string, string> = JSON.parse(txt) as Record<string, string>;
        const direct: string = obj['barcode'] || obj['code'] || obj['originalValue'] || '';
        if (direct.length > 0) {
          return direct;
        }
      } catch (e) {
        // ignore
      }
    }

    // 兜底提取常见条码格式（8-18位数字）
    const m: RegExpMatchArray | null = txt.match(/\b\d{8,18}\b/);
    return m !== null && m.length > 0 ? m[0] : '';
  }

  private onCollaborationState(stateCode: number, bufferType: string, buffer: ArrayBuffer): void {
    if (stateCode !== 0) {
      return;
    }
    const payload: string = this.decodeBufferToText(buffer);
    const code: string = this.extractBarcodeFromPayload(payload);
    if (code.length > 0) {
      this.barcodeInput = code;
      this.handleBarcodeMatch(code);
      promptAction.showToast({ message: '已接收协同扫码结果', duration: 1500 });
      return;
    }
    if (bufferType.length > 0) {
      promptAction.showToast({ message: '协同返回内容中未识别到条码', duration: 1800 });
    }
  }

  private handleScanResult(result: scanBarcode.ScanResult | null | undefined): void {
    if (result === null || result === undefined) {
      promptAction.showToast({ message: '未获取到扫码结果', duration: 1500 });
      return;
    }
    const code: string = (typeof result.originalValue === 'string') ? result.originalValue : '';
    if (code.length > 0) {
      this.barcodeInput = code;
      this.handleBarcodeMatch(code);
      return;
    }
    promptAction.showToast({ message: '未识别到条码，请重试', duration: 1500 });
  }

  private async startScanFromAlbum(): Promise<void> {
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
      const inputImage: detectBarcode.InputImage = { uri: photoResult.photoUris[0] };
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.ALL],
        enableMultiMode: false,
        enableAlbum: true
      };
      const results: Array<scanBarcode.ScanResult> = await detectBarcode.decode(inputImage, options);
      if (results.length > 0) {
        this.handleScanResult(results[0]);
      } else {
        promptAction.showToast({ message: '图片中未识别到条码', duration: 1700 });
      }
    } catch (error) {
      promptAction.showToast({ message: '相册识别失败，请手动输入条码', duration: 2000 });
    }
  }

  private parseAmountFromSpec(spec: string): ParsedAmountResult {
    const text: string = spec.trim();
    if (text.length === 0) {
      return { amount: 0, unit: 'g' };
    }
    const matchWithUnit: RegExpMatchArray | null = text.match(/(\d+(?:\.\d+)?)\s*(g|G|克|kg|KG|千克|ml|mL|ML|毫升|l|L|升)/);
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
    const pureNumber: RegExpMatchArray | null = text.match(/(\d+(?:\.\d+)?)/);
    if (pureNumber !== null && pureNumber.length > 1) {
      return { amount: Number(pureNumber[1]) || 0, unit: 'g' };
    }
    return { amount: 0, unit: 'g' };
  }

  // 调用系统扫码
  private startScan(): void {
    // 2in1 等无摄像头设备：直接走相册识别兜底，避免调用相机扫码导致崩溃
    if (this.forceAlbumMode) {
      this.startScanFromAlbum();
      return;
    }

    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: this.batchScanMode,
      enableAlbum: true
    };
    try {
      scanBarcode.startScanForResult(getContext(this), options)
        .then((result: scanBarcode.ScanResult) => {
          this.handleScanResult(result);
        })
        .catch((error: BusinessError) => {
          if (error.code === scanCore.ScanErrorCode.SCAN_SERVICE_CANCELED) {
            return;
          }
          // 扫码服务异常时自动回退到相册解码
          this.startScanFromAlbum();
        });
    } catch (error) {
      // 某些设备会在启动扫码服务时直接抛错（如无摄像头），这里也回退到相册
      this.startScanFromAlbum();
    }
  }

  // 条码匹配
  private handleBarcodeMatch(barcode: string): void {
    this.isMatching = true;
    this.currentBarcode = barcode;
    BarcodeService.getInstance().matchBarcodeInfo(barcode).then((result: BarcodeMatchResult) => {
      this.isMatching = false;
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
    });
  }

  // 确认后跳转热量页
  private confirmAndProceed(): void {
    if (this.matchedName.trim().length === 0) {
      promptAction.showToast({ message: '请输入商品名称', duration: 1500 });
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
    );
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
    router.pushUrl({ url: 'pages/CalorieInputPage', params: params });
  }

  build() {
    Stack() {
      Column() {
        CollaborationServiceStateDialog({
          onState: (stateCode: number, bufferType: string, buffer: ArrayBuffer): void => {
            this.onCollaborationState(stateCode, bufferType, buffer);
          }
        })

        // 导航栏
        Row() {
          Button('返回')
            .height(40)
            .fontSize(14)
            .fontColor('#007DFF')
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              router.back();
            })
          Text('扫码入库')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Text('').width(56)
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        Column({ space: 24 }) {
          // 扫码按钮
          Column({ space: 12 }) {
            Text('📷')
              .fontSize(56)
            Button('点击扫码')
              .width(200)
              .height(48)
              .fontSize(16)
              .fontColor(Color.White)
              .backgroundColor('#007DFF')
              .borderRadius(24)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => {
                this.startScan();
              })
            Text('对准商品条码即可识别')
              .fontSize(13)
              .fontColor($r('app.color.text_hint'))

            if (this.forceAlbumMode) {
              Text('当前设备未检测到可用摄像头，已自动切换为相册/协同识别')
                .fontSize(12)
                .fontColor('#FF9500')
                .textAlign(TextAlign.Center)
            }

            Button('从相册识别条码')
              .width(200)
              .height(40)
              .fontSize(14)
              .fontColor('#007DFF')
              .backgroundColor('#E8F0FE')
              .borderRadius(20)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => {
                this.startScanFromAlbum();
              })

            Button('手机协同扫码')
              .width(200)
              .height(40)
              .fontSize(14)
              .fontColor('#007DFF')
              .backgroundColor('#E8F0FE')
              .borderRadius(20)
              .bindMenu(this.collaborationMenu)
          }
          .width('100%')
          .padding({ top: 40, bottom: 24 })
          .alignItems(HorizontalAlign.Center)

          // 分隔线
          Row() {
            Divider().layoutWeight(1).color('#E0E0E0')
            Text('  或手动输入条码  ')
              .fontSize(13)
              .fontColor($r('app.color.text_hint'))
            Divider().layoutWeight(1).color('#E0E0E0')
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          Row() {
            Column({ space: 2 }) {
              Text('批量扫码模式')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
              Text('开启后将优先启用多码识别，复杂场景可改用“批量添加”页')
                .fontSize(12)
                .fontColor($r('app.color.text_hint'))
            }
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.batchScanMode })
              .selectedColor('#007DFF')
              .onChange((isOn: boolean) => {
                this.batchScanMode = isOn;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          Button('前往批量添加页')
            .width('100%')
            .height(40)
            .margin({ left: 16, right: 16 })
            .fontSize(14)
            .fontColor('#007DFF')
            .backgroundColor('#E8F0FE')
            .borderRadius(8)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              router.pushUrl({ url: 'pages/BatchAddPage' });
            })

          // 手动输入
          Row({ space: 8 }) {
            TextInput({ text: this.barcodeInput, placeholder: '输入商品条码（如 6901234567890）' })
              .layoutWeight(1)
              .height(44)
              .fontSize(15)
              .borderRadius(8)
              .backgroundColor($r('app.color.input_background'))
              .type(InputType.Number)
              .onChange((value: string) => {
                this.barcodeInput = value;
              })
            Button('匹配')
              .height(44)
              .fontSize(14)
              .fontColor(Color.White)
              .backgroundColor('#007DFF')
              .borderRadius(8)
              .enabled(!this.isMatching && this.barcodeInput.trim().length > 0)
              .onClick(() => {
                this.handleBarcodeMatch(this.barcodeInput.trim());
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          if (this.isMatching) {
            Row({ space: 8 }) {
              LoadingProgress().width(20).height(20)
              Text('正在匹配条码...')
                .fontSize(14)
                .fontColor($r('app.color.text_hint'))
            }
          }
        }
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      // 条码信息校验弹窗
      if (this.showVerifyDialog) {
        Column() {
          // 遮罩
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#80000000')
            .onClick(() => {
              this.showVerifyDialog = false;
            })
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })

        Column({ space: 16 }) {
          // 标题
          Text(this.matchSource.length > 0 ? '条码信息校验（可修改）' : '条码无匹配，录入商品信息')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          // 条码（不可修改）
          Column({ space: 4 }) {
            Text('条码')
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
              Text('商品名称')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
              Text(' *')
                .fontSize(13)
                .fontColor('#FF3B30')
            }
            TextInput({ text: this.matchedName, placeholder: '如：纯牛奶、原味薯片' })
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
            Text('商品品类（选填）')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.matchedCategory, placeholder: '如：乳制品、零食' })
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
            Text('商品规格（选填）')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.matchedSpec, placeholder: '如：250ml、100g' })
              .width('100%')
              .height(40)
              .fontSize(14)
              .borderRadius(8)
              .backgroundColor($r('app.color.input_background'))
              .onChange((value: string) => {
                this.matchedSpec = value;
              })
          }

          Text('💡 商品规格会作为入库量来源并自动带入下一步')
            .fontSize(12)
            .fontColor($r('app.color.text_hint'))
            .width('100%')

          // 按钮
          Row({ space: 12 }) {
            Button('取消')
              .layoutWeight(1)
              .height(44)
              .fontSize(15)
              .fontColor($r('app.color.text_secondary'))
              .backgroundColor($r('app.color.chip_background'))
              .borderRadius(8)
              .onClick(() => {
                this.showVerifyDialog = false;
              })
            Button('确认')
              .layoutWeight(1)
              .height(44)
              .fontSize(15)
              .fontColor(Color.White)
              .backgroundColor('#007DFF')
              .borderRadius(8)
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
        .position({ x: '7.5%', y: '20%' })
      }
    }
    .width('100%')
    .height('100%')
    .animation({ duration: 260, curve: Curve.EaseInOut })
  }
}
