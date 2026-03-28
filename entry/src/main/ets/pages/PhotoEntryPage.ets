import { router, promptAction } from '@kit.ArkUI';
import { cameraPicker, camera } from '@kit.CameraKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { FOOD_CATEGORIES, StorageType, getBaseDays, padZero } from '../common/Constants';
import {
  createCollaborationServiceMenuItems,
  CollaborationServiceStateDialog,
  CollaborationServiceFilter
} from '@kit.ServiceCollaborationKit';
import { deviceInfo } from '@kit.BasicServicesKit';

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

@Entry
@Component
struct PhotoEntryPage {
  @State photoUri: string = '';
  @State recognizedName: string = '';
  @State recognizedCategory: string = '其他';
  @State freshnessLevel: string = 'fresh';
  @State storageType: string = StorageType.FRIDGE;
  @State recognitionHint: string = '等待拍照识别';
  @State estimatedExpiryText: string = '';
  @State showCollaborationButton: boolean = true;

  aboutToAppear(): void {
    this.showCollaborationButton = deviceInfo.deviceType !== 'phone';
  }

  @Builder
  collaborationMenu() {
    Menu() {
      createCollaborationServiceMenuItems([CollaborationServiceFilter.ALL]);
    }
  }

  private async takeFoodPhoto(): Promise<void> {
    if (!canIUse('SystemCapability.Multimedia.Camera.Core')) {
      promptAction.showToast({ message: '当前设备无可用摄像头，请改用手动入库', duration: 2000 });
      return;
    }

    try {
      const ctx: Context = getContext(this) as Context;
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
        promptAction.showToast({ message: '拍照成功，已生成入库建议', duration: 1500 });
      }
    } catch (error) {
      promptAction.showToast({ message: '拍照失败，请重试', duration: 1500 });
    }
  }

  private async analyzePhotoAndSuggest(): Promise<void> {
    this.recognitionHint = '正在识别图片内容...';

    if (!canIUse('SystemCapability.AI.OCR.TextRecognition')) {
      this.recognitionHint = '当前设备不支持自动识别，可手动调整';
      this.updateEstimatedExpiry();
      return;
    }

    const pixelMap: image.PixelMap | null = await this.getPixelMapFromUri(this.photoUri);
    if (pixelMap === null) {
      this.recognitionHint = '图片读取失败，请手动填写';
      this.updateEstimatedExpiry();
      return;
    }

    let recognizedText: string = '';
    try {
      recognizedText = await this.recognizeTextFromPixelMap(pixelMap);
    } finally {
      pixelMap.release();
    }

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

  private decodeBufferToText(buffer: ArrayBuffer): string {
    const bytes: Uint8Array = new Uint8Array(buffer);
    let text: string = '';
    for (let i = 0; i < bytes.length; i++) {
      text = text + String.fromCharCode(bytes[i]);
    }
    return text;
  }

  private handleCollaborationImage(buffer: ArrayBuffer): void {
    this.recognitionHint = '正在处理协同图片...';
    image.createImageSource(buffer).createPixelMap().then(async (pixelMap: image.PixelMap) => {
      let recognizedText: string = '';
      try {
        recognizedText = await this.recognizeTextFromPixelMap(pixelMap);
      } finally {
        pixelMap.release();
      }
      this.applySuggestionsFromText(recognizedText);
      this.updateEstimatedExpiry();
      promptAction.showToast({ message: '已接收协同图片并生成建议', duration: 1800 });
    }).catch(() => {
      this.recognitionHint = '协同图片解析失败，请重试';
      promptAction.showToast({ message: '协同图片解析失败', duration: 1800 });
    });
  }

  private onCollaborationState(stateCode: number, bufferType: string, buffer: ArrayBuffer): void {
    if (stateCode !== 0) {
      return;
    }
    if (bufferType === 'general.image') {
      this.handleCollaborationImage(buffer);
      return;
    }
    const payload: string = this.decodeBufferToText(buffer);
    if (payload.trim().length > 0) {
      this.applySuggestionsFromText(payload);
      this.updateEstimatedExpiry();
      promptAction.showToast({ message: '已接收协同文本建议', duration: 1600 });
    }
  }

  private applySuggestionsFromText(text: string): void {
    const raw: string = text.trim();
    if (raw.length === 0) {
      this.recognitionHint = '未识别到有效文本，请手动确认食品信息';
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
        this.recognitionHint = '已自动识别：' + item.name + '（可手动修改）';
        return;
      }
    }

    const firstLine: string = raw.split('\n')[0].trim();
    this.recognizedName = firstLine.length > 12 ? firstLine.substring(0, 12) : firstLine;
    this.recognizedCategory = '其他';
    this.freshnessLevel = this.inferFreshness(raw);
    this.recognitionHint = '已提取图片文本并生成建议（可手动修改）';
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
    this.estimatedExpiryText = this.formatDate(expiry) + '（预计剩余 ' + days.toString() + ' 天）';
  }

  private formatDate(date: Date): string {
    const year: number = date.getFullYear();
    const month: number = date.getMonth() + 1;
    const day: number = date.getDate();
    return year.toString() + '-' + padZero(month) + '-' + padZero(day);
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
    router.pushUrl({ url: 'pages/AddFoodPage', params: params });
  }

  build() {
    Column() {
      CollaborationServiceStateDialog({
        onState: (stateCode: number, bufferType: string, buffer: ArrayBuffer): void => {
          this.onCollaborationState(stateCode, bufferType, buffer);
        }
      })

      Row() {
        Button('返回')
          .height(36)
          .fontSize(14)
          .fontColor('#007DFF')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            router.back();
          })
        Text('拍照入库')
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
        Column({ space: 12 }) {
          Text('拍照后自动识别食品类别与新鲜程度，并给出保质期建议')
            .fontSize(14)
            .fontColor($r('app.color.text_hint'))
            .textAlign(TextAlign.Center)

          Button(this.photoUri.length > 0 ? '重新拍照识别' : '拍摄食品照片')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor('#007DFF')
            .borderRadius(12)
            .onClick(() => {
              this.takeFoodPhoto();
            })

          if (this.showCollaborationButton) {
            Button('手机协同传图识别')
              .width('100%')
              .height(40)
              .fontSize(14)
              .fontColor('#007DFF')
              .backgroundColor('#E8F0FE')
              .borderRadius(12)
              .bindMenu(this.collaborationMenu)
          }

          Column({ space: 8 }) {
            Text('识别结果')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Text(this.recognitionHint)
              .fontSize(12)
              .fontColor($r('app.color.text_hint'))

            TextInput({ text: this.recognizedName, placeholder: '食品名称（自动识别，可修改）' })
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
                Text(category)
                  .fontSize(12)
                  .fontColor(this.recognizedCategory === category ? Color.White : '#666666')
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .margin({ right: 8, bottom: 8 })
                  .borderRadius(14)
                  .backgroundColor(this.recognizedCategory === category ? '#007DFF' : '#F0F0F0')
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
          .borderRadius(10)

          Column({ space: 8 }) {
            Text('新鲜程度')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Row({ space: 8 }) {
              this.buildTag('新鲜', 'fresh')
              this.buildTag('一般', 'normal')
              this.buildTag('偏差', 'stale')
            }

            Text('存储环境')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Row({ space: 8 }) {
              this.buildStorageTag('冷藏', StorageType.FRIDGE)
              this.buildStorageTag('冷冻', StorageType.FREEZER)
              this.buildStorageTag('常温', StorageType.ROOM)
            }

            Text('预计到期：' + (this.estimatedExpiryText.length > 0 ? this.estimatedExpiryText : '待识别后生成'))
              .fontSize(13)
              .fontColor('#007DFF')
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(10)

          Button('下一步：确认并入库')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontColor('#007DFF')
            .backgroundColor('#E8F0FE')
            .borderRadius(12)
            .onClick(() => {
              this.goToAddFood();
            })

          Button('不拍照，直接手动入库')
            .width('100%')
            .height(44)
            .fontSize(14)
            .fontColor($r('app.color.text_hint'))
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              router.pushUrl({ url: 'pages/AddFoodPage' });
            })
        }
        .padding({ left: 20, right: 20, top: 16, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  buildTag(label: string, value: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.freshnessLevel === value ? Color.White : '#666666')
      .textAlign(TextAlign.Center)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .borderRadius(16)
      .backgroundColor(this.freshnessLevel === value ? '#007DFF' : '#F0F0F0')
      .onClick(() => {
        this.freshnessLevel = value;
        this.updateEstimatedExpiry();
      })
  }

  @Builder
  buildStorageTag(label: string, value: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.storageType === value ? Color.White : '#666666')
      .textAlign(TextAlign.Center)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .borderRadius(16)
      .backgroundColor(this.storageType === value ? '#007DFF' : '#F0F0F0')
      .onClick(() => {
        this.storageType = value;
        this.updateEstimatedExpiry();
      })
  }
}
