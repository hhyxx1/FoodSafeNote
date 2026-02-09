import { router, promptAction } from '@kit.ArkUI';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { BusinessError } from '@kit.BasicServicesKit';
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
}

@Entry
@Component
struct BarcodeScanPage {
  @State barcodeInput: string = '';
  @State isMatching: boolean = false;
  @State showVerifyDialog: boolean = false;
  @State matchedName: string = '';
  @State matchedCategory: string = '';
  @State matchedSpec: string = '';
  @State currentBarcode: string = '';
  @State matchSource: string = '';

  // 调用系统扫码
  private startScan(): void {
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: false,
      enableAlbum: true
    };
    try {
      scanBarcode.startScanForResult(getContext(this), options)
        .then((result: scanBarcode.ScanResult) => {
          const code: string = result.originalValue;
          if (code.length > 0) {
            this.barcodeInput = code;
            this.handleBarcodeMatch(code);
          }
        })
        .catch((error: BusinessError) => {
          promptAction.showToast({ message: '扫码取消或失败', duration: 1500 });
        });
    } catch (error) {
      promptAction.showToast({ message: '扫码功能不可用，请手动输入条码', duration: 2000 });
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
    const source: string = this.matchSource === 'product_dict' ? 'edited' : 'manual';
    BarcodeService.getInstance().saveToProductDict(
      this.currentBarcode, this.matchedName.trim(),
      this.matchedCategory, this.matchedSpec, 0, source
    );
    this.showVerifyDialog = false;
    // 跳转到热量获取页
    const params: CaloriePageParams = {
      barcode: this.currentBarcode,
      name: this.matchedName.trim(),
      category: this.matchedCategory,
      spec: this.matchedSpec
    };
    router.pushUrl({ url: 'pages/CalorieInputPage', params: params });
  }

  build() {
    Stack() {
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
              .onClick(() => {
                this.startScan();
              })
            Text('对准商品条码即可识别')
              .fontSize(13)
              .fontColor($r('app.color.text_hint'))
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
        .padding(20)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .position({ x: '7.5%', y: '20%' })
      }
    }
    .width('100%')
    .height('100%')
  }
}
