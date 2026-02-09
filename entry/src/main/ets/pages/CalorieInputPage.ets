import { router, promptAction } from '@kit.ArkUI';
import { BarcodeService } from '../common/BarcodeService';
import { OcrRecord } from '../model/DataModels';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { textRecognition } from '@kit.CoreVisionKit';
import { cameraPicker, camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { kjToKcal } from '../common/Constants';

// 路由参数接口
interface CaloriePageParams {
  barcode: string;
  name: string;
  category: string;
  spec: string;
}

// 跳转AddFoodPage参数接口
interface AddFoodParams {
  barcode: string;
  name: string;
  category: string;
  spec: string;
  calories: number;
  fromBarcodeScan: boolean;
}

@Entry
@Component
struct CalorieInputPage {
  @State barcode: string = '';
  @State foodName: string = '';
  @State category: string = '';
  @State spec: string = '';
  @State caloriesText: string = '';
  @State autoFillCalories: number = 0;
  @State calorieSource: string = '';
  @State calorieUnit: string = 'kJ';
  @State isLoading: boolean = true;

  aboutToAppear(): void {
    const params: CaloriePageParams = router.getParams() as CaloriePageParams;
    if (params !== null && params !== undefined) {
      this.barcode = params.barcode;
      this.foodName = params.name;
      this.category = params.category;
      this.spec = params.spec;
      this.fetchCalories();
    } else {
      this.isLoading = false;
    }
  }

  private fetchCalories(): void {
    BarcodeService.getInstance().fetchCalories(this.barcode, this.category, this.foodName)
      .then((calories: number) => {
        if (calories > 0) {
          this.autoFillCalories = calories;
          this.caloriesText = calories.toString();
          this.calorieSource = '来自本地记忆';
        }
        this.isLoading = false;
      });
  }

  private async startOcrRecognition(): Promise<void> {
    try {
      const pickerProfile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
      };
      const pickerResult: cameraPicker.PickerResult =
        await cameraPicker.pick(getContext(this), [cameraPicker.PickerMediaType.PHOTO], pickerProfile);
      const imageUri: string = pickerResult.resultUri;
      if (imageUri.length === 0) {
        return;
      }
      // 从URI创建PixelMap
      const imageSource: image.ImageSource = image.createImageSource(imageUri);
      const pixelMap: image.PixelMap = await imageSource.createPixelMap();
      const visionInfo: textRecognition.VisionInfo = {
        pixelMap: pixelMap
      };
      const textResult: textRecognition.TextRecognitionResult =
        await textRecognition.recognizeText(visionInfo);
      const recognizedText: string = textResult.value;
      pixelMap.release();
      imageSource.release();
      // 尝试从识别文本中提取热量值
      const calorieValue: number = this.parseCalorieFromText(recognizedText);
      if (calorieValue > 0) {
        this.caloriesText = calorieValue.toString();
        this.autoFillCalories = calorieValue;
        this.calorieSource = '来自OCR识别';
        promptAction.showToast({ message: '已识别热量值: ' + calorieValue.toString() + ' kcal', duration: 2000 });
      } else {
        promptAction.showToast({ message: '未能从图片中识别出热量值，请手动输入', duration: 2000 });
      }
    } catch (e) {
      promptAction.showToast({ message: 'OCR功能需要设备支持', duration: 2000 });
    }
  }

  private parseCalorieFromText(text: string): number {
    // 匹配常见营养表中的能量/热量值
    // 尝试匹配 "能量" 或 "热量" 后面的数字
    const lines: string[] = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      if (line.indexOf('能量') >= 0 || line.indexOf('热量') >= 0 || line.indexOf('Energy') >= 0) {
        // 提取该行中的数字
        const num: number = this.extractNumber(line);
        if (num > 0) {
          // 如果是kJ，转换为kcal (1kcal ≈ 4.184kJ)
          if (line.indexOf('kJ') >= 0 || line.indexOf('千焦') >= 0) {
            return Math.round(num / 4.184);
          }
          return num;
        }
      }
    }
    return 0;
  }

  private extractNumber(text: string): number {
    let numStr: string = '';
    let foundDot: boolean = false;
    for (let i = 0; i < text.length; i++) {
      const ch: string = text.charAt(i);
      if (ch >= '0' && ch <= '9') {
        numStr = numStr + ch;
      } else if (ch === '.' && !foundDot && numStr.length > 0) {
        numStr = numStr + ch;
        foundDot = true;
      } else if (numStr.length > 0) {
        break;
      }
    }
    if (numStr.length > 0) {
      return Number(numStr);
    }
    return 0;
  }

  private confirmAndProceed(): void {
    const rawValue: number = Number(this.caloriesText) || 0;
    const finalCalories: number = this.calorieUnit === 'kJ' ? kjToKcal(rawValue) : rawValue;

    // 如果热量>0，存入ProductDict
    if (finalCalories > 0) {
      BarcodeService.getInstance().saveToProductDict(
        this.barcode, this.foodName, this.category,
        this.spec, finalCalories, this.autoFillCalories > 0 ? 'edited' : 'manual'
      );
    }

    // 记录OCR记录（即使没有用OCR，也记录手动输入）
    if (finalCalories > 0 || this.autoFillCalories > 0) {
      const ocrRec = new OcrRecord();
      ocrRec.foodName = this.foodName;
      ocrRec.barcode = this.barcode;
      ocrRec.ocrValue = this.autoFillCalories;
      ocrRec.finalValue = finalCalories;
      DatabaseHelper.getInstance().insertOcrRecord(ocrRec);
    }

    // 跳转到AddFoodPage完成入库
    const params: AddFoodParams = {
      barcode: this.barcode,
      name: this.foodName,
      category: this.category,
      spec: this.spec,
      calories: finalCalories,
      fromBarcodeScan: true
    };
    router.replaceUrl({ url: 'pages/AddFoodPage', params: params });
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
        Text('热量获取')
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

      Scroll() {
        Column({ space: 16 }) {
          // 食品信息摘要
          Column({ space: 8 }) {
            Text('食品信息')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            this.buildInfoLine('名称', this.foodName)
            if (this.category.length > 0) {
              this.buildInfoLine('分类', this.category)
            }
            if (this.spec.length > 0) {
              this.buildInfoLine('规格', this.spec)
            }
            if (this.barcode.length > 0) {
              this.buildInfoLine('条码', this.barcode)
            }
          }
          .width('100%')
          .padding(16)
          .margin({ left: 16, right: 16, top: 16 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)

          // 热量输入区
          Column({ space: 12 }) {
            Text('能量/热量（每100g）')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')

            if (this.autoFillCalories > 0) {
              Row({ space: 6 }) {
                Text('✅').fontSize(14)
                Text(this.calorieSource).fontSize(13).fontColor('#34C759')
              }
            }

            // kJ/kcal 单位切换
            Row({ space: 0 }) {
              Text('千焦 kJ（营养表常用）')
                .fontSize(13)
                .fontColor(this.calorieUnit === 'kJ' ? Color.White : $r('app.color.text_secondary'))
                .textAlign(TextAlign.Center).layoutWeight(1).height(34)
                .backgroundColor(this.calorieUnit === 'kJ' ? '#007DFF' : $r('app.color.chip_background'))
                .borderRadius(8)
                .onClick(() => { this.calorieUnit = 'kJ'; })
              Text('千卡 kcal')
                .fontSize(13)
                .fontColor(this.calorieUnit === 'kcal' ? Color.White : $r('app.color.text_secondary'))
                .textAlign(TextAlign.Center).layoutWeight(1).height(34)
                .backgroundColor(this.calorieUnit === 'kcal' ? '#007DFF' : $r('app.color.chip_background'))
                .borderRadius(8)
                .onClick(() => { this.calorieUnit = 'kcal'; })
            }
            .width('100%').borderRadius(8).clip(true)

            Row({ space: 8 }) {
              TextInput({ text: this.caloriesText, placeholder: '输入营养表上的数值' })
                .layoutWeight(1).height(48).fontSize(18).borderRadius(8)
                .backgroundColor($r('app.color.input_background'))
                .type(InputType.Number)
                .onChange((value: string) => { this.caloriesText = value; })
              Text(this.calorieUnit).fontSize(16).fontColor($r('app.color.text_secondary'))
            }
            .width('100%')

            if (this.calorieUnit === 'kJ' && this.caloriesText.length > 0) {
              Text('≈ ' + kjToKcal(Number(this.caloriesText) || 0) + ' kcal（自动换算，存储为千卡）')
                .fontSize(12).fontColor('#007DFF')
            }

            Button('拍营养表 (OCR识别)')
              .width('100%').height(40).fontSize(14)
              .fontColor('#007DFF').backgroundColor('#E8F0FE').borderRadius(8)
              .onClick(() => { this.startOcrRecognition(); })

            if (this.caloriesText.length === 0 || this.caloriesText === '0') {
              Row({ space: 6 }) {
                Text('⚠️')
                  .fontSize(14)
                Text('未录入热量值，建议补录用于健康统计')
                  .fontSize(13)
                  .fontColor('#FF9500')
              }
              .width('100%')
              .padding({ top: 4, bottom: 4, left: 8, right: 8 })
              .backgroundColor('#FFF3E0')
              .borderRadius(8)
            }
          }
          .width('100%')
          .padding(16)
          .margin({ left: 16, right: 16 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)

          // 提示信息
          Column({ space: 8 }) {
            Text('💡 热量获取方式')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text('• 查看食品包装上的营养成分表')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Text('• 热量值确认后将自动存入本地记忆库')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Text('• 下次添加同类食品时将自动填充')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .padding(16)
          .margin({ left: 16, right: 16 })
          .backgroundColor('#E8F5E9')
          .borderRadius(16)
          .alignItems(HorizontalAlign.Start)

          // 确认按钮
          Button('下一步：设置保质期')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor('#007DFF')
            .borderRadius(12)
            .margin({ left: 16, right: 16, top: 8, bottom: 32 })
            .onClick(() => {
              this.confirmAndProceed();
            })
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  buildInfoLine(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_hint'))
        .width(50)
      Text(value)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 2, bottom: 2 })
  }
}
