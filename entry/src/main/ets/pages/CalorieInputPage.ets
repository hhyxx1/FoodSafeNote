import { router, promptAction } from '@kit.ArkUI';
import { BarcodeService, NutritionMeta } from '../common/BarcodeService';
import { OcrRecord } from '../model/DataModels';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { textRecognition } from '@kit.CoreVisionKit';
import { cameraPicker, camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { kjToKcal } from '../common/Constants';
import {
  createCollaborationServiceMenuItems,
  CollaborationServiceStateDialog,
  CollaborationServiceFilter
} from '@kit.ServiceCollaborationKit';
import { deviceInfo } from '@kit.BasicServicesKit';

// 路由参数接口
interface CaloriePageParams {
  barcode: string;
  name: string;
  category: string;
  spec: string;
  amount?: number;
  amountUnit?: string;
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

interface NutritionParseResult {
  value: number;
  unit: string;
  basisType: string;
  per100Unit: string;
  servingSize: number;
  servingUnit: string;
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
  @State calorieBasis: string = 'per100'; // per100 | perServing
  @State per100Unit: string = 'g'; // g | ml
  @State amountText: string = '';
  @State servingsText: string = '1';
  @State servingSizeText: string = '';
  @State servingUnit: string = 'g'; // g | ml
  @State isLoading: boolean = true;
  @State showOcrCheckDialog: boolean = false;
  @State ocrDialogValue: string = '';
  @State ocrDialogUnit: string = 'kJ';
  @State ocrDialogBasis: string = 'per100';
  @State ocrDialogPer100Unit: string = 'g';
  @State ocrDialogServingSize: string = '';
  @State ocrDialogServingUnit: string = 'g';
  @State showCollaborationButton: boolean = true;

  @Builder
  collaborationMenu() {
    Menu() {
      createCollaborationServiceMenuItems([CollaborationServiceFilter.ALL]);
    }
  }

  aboutToAppear(): void {
    this.showCollaborationButton = deviceInfo.deviceType !== 'phone';
    const params: CaloriePageParams = router.getParams() as CaloriePageParams;
    if (params !== null && params !== undefined) {
      this.barcode = params.barcode;
      this.foodName = params.name;
      this.category = params.category;
      this.spec = params.spec;
      this.prefillAmountFromParamsOrSpec(params);
      this.fetchCalories();
    } else {
      this.isLoading = false;
    }
  }

  private prefillAmountFromParamsOrSpec(params: CaloriePageParams): void {
    if (params.amount !== undefined && params.amount > 0) {
      this.amountText = params.amount.toString();
      if (params.amountUnit !== undefined && (params.amountUnit === 'g' || params.amountUnit === 'ml')) {
        this.per100Unit = params.amountUnit;
      }
      return;
    }

    const specText: string = params.spec !== undefined ? params.spec : '';
    const m: RegExpMatchArray | null = specText.match(/(\d+(?:\.\d+)?)\s*(g|G|克|ml|mL|ML|毫升)/);
    if (m !== null && m.length >= 3) {
      this.amountText = (Number(m[1]) || 0).toString();
      const unitToken: string = m[2];
      this.per100Unit = (unitToken.indexOf('ml') >= 0 || unitToken.indexOf('mL') >= 0 || unitToken.indexOf('毫升') >= 0) ? 'ml' : 'g';
    }
  }

  private fetchCalories(): void {
    BarcodeService.getInstance().fetchNutritionPreset(this.barcode, this.category, this.foodName)
      .then((dict) => {
        if (dict !== null) {
          if (dict.rawEnergy > 0) {
            this.caloriesText = dict.rawEnergy.toString();
            this.calorieUnit = dict.energyUnit.length > 0 ? dict.energyUnit : 'kJ';
            this.calorieBasis = dict.basisType === 'perServing' ? 'perServing' : 'per100';
            this.per100Unit = dict.basisType === 'per100ml' ? 'ml' : 'g';
            this.servingSizeText = dict.servingSize > 0 ? dict.servingSize.toString() : '';
            this.servingUnit = dict.servingUnit.length > 0 ? dict.servingUnit : 'g';
          } else if (dict.calories > 0) {
            this.caloriesText = dict.calories.toString();
            this.calorieUnit = 'kcal';
            this.calorieBasis = dict.basisType === 'perServing' ? 'perServing' : 'per100';
            this.per100Unit = dict.basisType === 'per100ml' ? 'ml' : 'g';
          }
          if (this.calorieBasis === 'perServing') {
            this.servingsText = '1';
          }
          this.calorieSource = dict.isReliable ? '来自本地记忆（已标准化）' : '来自本地记忆（待补全）';
        }
        this.isLoading = false;
      });
  }

  private async startOcrRecognition(): Promise<void> {
    try {
      if (!canIUse('SystemCapability.AI.OCR.TextRecognition')) {
        promptAction.showToast({ message: '当前设备不支持OCR识别', duration: 2000 });
        return;
      }

      const ctx: Context = getContext(this) as Context;
      const captureUri: string = ctx.cacheDir + '/ocr_capture_' + Date.now().toString() + '.jpg';
      const pickerProfile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
        saveUri: captureUri
      };
      const pickerResult: cameraPicker.PickerResult =
        await cameraPicker.pick(ctx, [cameraPicker.PickerMediaType.PHOTO], pickerProfile);
      const imageUri: string = pickerResult.resultUri;
      if (imageUri.length === 0) {
        return;
      }

      // 参照官方示例：构建VisionInfo + TextRecognitionConfiguration后进行OCR
      const pixelMap: image.PixelMap | null = await this.getPixelMapFromUri(imageUri);
      if (pixelMap === null) {
        promptAction.showToast({ message: '图片读取失败，请重试', duration: 2000 });
        return;
      }
      let recognizedText: string = '';
      try {
        const visionInfo: textRecognition.VisionInfo = {
          pixelMap: pixelMap
        };
        const textConfig: textRecognition.TextRecognitionConfiguration = {
          isDirectionDetectionSupported: true
        };
        const textResult: textRecognition.TextRecognitionResult =
          await textRecognition.recognizeText(visionInfo, textConfig);
        recognizedText = (textResult && typeof textResult.value === 'string') ? textResult.value : '';
      } finally {
        pixelMap.release();
      }
      this.applyOcrResultFromText(recognizedText, 'OCR识别');
    } catch (e) {
      promptAction.showToast({ message: 'OCR识别失败，请重试', duration: 2000 });
    }
  }

  private applyOcrResultFromText(recognizedText: string, sourceLabel: string): void {
    if (recognizedText.trim().length === 0) {
      promptAction.showToast({ message: '未识别到文本，请重试', duration: 2000 });
      return;
    }
    const parsed: NutritionParseResult | null = this.parseNutritionFromText(recognizedText);
    if (parsed !== null && parsed.value > 0) {
      this.ocrDialogValue = parsed.value.toString();
      this.ocrDialogUnit = parsed.unit;
      this.ocrDialogBasis = parsed.basisType;
      this.ocrDialogPer100Unit = parsed.per100Unit;
      this.ocrDialogServingSize = parsed.servingSize > 0 ? parsed.servingSize.toString() : '';
      this.ocrDialogServingUnit = parsed.servingUnit;
      this.showOcrCheckDialog = true;
      promptAction.showToast({ message: '已接收' + sourceLabel + '结果，请校验', duration: 1800 });
      return;
    }
    promptAction.showToast({ message: '未能识别到完整能量信息，请手动补录单位和基准', duration: 2200 });
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
    image.createImageSource(buffer).createPixelMap().then(async (pixelMap: image.PixelMap) => {
      let recognizedText: string = '';
      try {
        const visionInfo: textRecognition.VisionInfo = { pixelMap: pixelMap };
        const textConfig: textRecognition.TextRecognitionConfiguration = { isDirectionDetectionSupported: true };
        const textResult: textRecognition.TextRecognitionResult =
          await textRecognition.recognizeText(visionInfo, textConfig);
        recognizedText = (textResult && typeof textResult.value === 'string') ? textResult.value : '';
      } catch (e) {
        recognizedText = '';
      } finally {
        pixelMap.release();
      }
      this.applyOcrResultFromText(recognizedText, '协同图片');
    }).catch(() => {
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
      this.applyOcrResultFromText(payload, '协同文本');
    }
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
        // 尝试下一个候选URI
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

  private confirmOcrValue(): void {
    const finalValue: number = Number(this.ocrDialogValue) || 0;
    if (finalValue <= 0) {
      promptAction.showToast({ message: '请填写有效能量值', duration: 1500 });
      return;
    }
    this.caloriesText = finalValue.toString();
    this.calorieUnit = this.ocrDialogUnit;
    this.calorieBasis = this.ocrDialogBasis;
    this.per100Unit = this.ocrDialogPer100Unit;
    this.servingSizeText = this.ocrDialogServingSize;
    this.servingUnit = this.ocrDialogServingUnit;
    if (this.calorieBasis === 'perServing' && this.servingsText.length === 0) {
      this.servingsText = '1';
    }
    this.autoFillCalories = this.getReferenceKcal();
    this.calorieSource = '来自OCR识别（已校验）';
    this.showOcrCheckDialog = false;
    promptAction.showToast({ message: '已应用OCR结果，请继续补充本次入库量', duration: 1800 });
  }

  private parseNutritionFromText(text: string): NutritionParseResult | null {
    const normalizedText: string = this.normalizeOcrText(text);
    const lines: string[] = normalizedText.split('\n');
    let targetLine: string = '';
    let energyLineIndex: number = -1;
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      if (line.length === 0) continue;
      if (line.match(/能.{0,2}量|热.{0,2}量|energy/i) !== null) {
        targetLine = line;
        energyLineIndex = i;
        break;
      }
    }
    if (targetLine.length === 0) {
      targetLine = normalizedText;
    }

    const hasEnergyKeyword: boolean = targetLine.match(/能.{0,2}量|热.{0,2}量|energy/i) !== null;
    let value: number = 0;
    let unit: string = 'kJ';

    // 回退1：优先从“数值+单位”组合中提取
    if (value <= 0) {
      const withUnit: RegExpMatchArray | null = targetLine.match(/(\d+(?:[\.,]\d+)?)\s*(kJ|KJ|千焦|kcal|KCAL|千卡|大卡)/);
      if (withUnit !== null && withUnit.length >= 3) {
        value = Number(withUnit[1].replace(',', '')) || 0;
        const unitToken: string = withUnit[2];
        unit = (unitToken.indexOf('kcal') >= 0 || unitToken.indexOf('KCAL') >= 0 || unitToken.indexOf('千卡') >= 0 || unitToken.indexOf('大卡') >= 0)
          ? 'kcal' : 'kJ';
      }
    }

    // 回退1.5：关键词行中优先取“紧邻单位(kJ/kcal)”的数字，避免取到“每100”
    if (value <= 0 && hasEnergyKeyword) {
      const lineWithUnit: RegExpMatchArray | null = targetLine.match(/(\d+(?:[\.,]\d+)?)\s*(kJ|KJ|千焦|kcal|KCAL|千卡|大卡)/);
      if (lineWithUnit !== null && lineWithUnit.length >= 3) {
        value = Number(lineWithUnit[1].replace(',', '')) || 0;
        const unitToken: string = lineWithUnit[2];
        unit = (unitToken.indexOf('kcal') >= 0 || unitToken.indexOf('KCAL') >= 0 || unitToken.indexOf('千卡') >= 0 || unitToken.indexOf('大卡') >= 0)
          ? 'kcal' : 'kJ';
      }
    }

    // 回退1.6：在“能量/热量”关键词后再取数字，避免拿到“每100ml”的100
    if (value <= 0 && hasEnergyKeyword) {
      const afterKeyword: RegExpMatchArray | null = targetLine.match(/(?:能.{0,2}量|热.{0,2}量|energy)[^0-9]{0,12}(\d+(?:[\.,]\d+)?)/i);
      if (afterKeyword !== null && afterKeyword.length >= 2) {
        value = Number(afterKeyword[1].replace(',', '')) || 0;
      }
    }

    // 回退1.7：最后才在全文找“数值+单位”，尽量避免条码/批号等噪声
    if (value <= 0) {
      const withUnitGlobal: RegExpMatchArray | null = normalizedText.match(/(\d+(?:[\.,]\d+)?)\s*(kJ|KJ|千焦|kcal|KCAL|千卡|大卡)/);
      if (withUnitGlobal !== null && withUnitGlobal.length >= 3) {
        value = Number(withUnitGlobal[1].replace(',', '')) || 0;
        const unitToken: string = withUnitGlobal[2];
        unit = (unitToken.indexOf('kcal') >= 0 || unitToken.indexOf('KCAL') >= 0 || unitToken.indexOf('千卡') >= 0 || unitToken.indexOf('大卡') >= 0)
          ? 'kcal' : 'kJ';
      }
    }

    // 回退2：从全文数字中按“能量相关性”打分，避免把年份/地址/条码数字当成能量
    if (value <= 0) {
      const reg: RegExp = /(\d+(?:[\.,]\d+)?)/g;
      let best: number = 0;
      let bestScore: number = -999;
      let energyWindow: string = '';
      if (energyLineIndex >= 0) {
        const startLine: number = energyLineIndex > 0 ? energyLineIndex - 1 : 0;
        const endLine: number = energyLineIndex + 1 < lines.length ? energyLineIndex + 1 : lines.length - 1;
        energyWindow = lines.slice(startLine, endLine + 1).join(' ');
      }
      let m: RegExpExecArray | null = reg.exec(normalizedText);
      while (m !== null) {
        const n: number = Number(m[1].replace(',', '')) || 0;
        if (n > 0) {
          const token: string = m[1];
          const idx: number = m.index;
          const start: number = idx > 8 ? idx - 8 : 0;
          const end: number = idx + token.length + 10 < normalizedText.length ? idx + token.length + 10 : normalizedText.length;
          const around: string = normalizedText.substring(start, end);
          // 过滤“每100g/每100ml/100克/100毫升”这类基准数字
          const isBasisNumber: boolean = around.match(/每\s*100|\/\s*100|100\s*(g|克|ml|毫升)/i) !== null && Math.round(n) === 100;
          // 过滤NRV百分比等非能量值
          const isPercent: boolean = around.indexOf('%') >= 0 || around.indexOf('NRV') >= 0 || around.indexOf('nrv') >= 0;
          const isBarcodeLike: boolean = token.length >= 8;
          const isYearLike: boolean = Math.round(n) >= 1900 && Math.round(n) <= 2099;
          const hasDateOrAddrHint: boolean = around.match(/年|月|日|号|室|栋|幢|单元|省|市|区|县|路|街|巷|地址|电话|SC|GB|生产|标准|保质期/i) !== null;
          if (isBasisNumber || isPercent || isBarcodeLike) {
            m = reg.exec(normalizedText);
            continue;
          }
          if (isYearLike && hasDateOrAddrHint) {
            m = reg.exec(normalizedText);
            continue;
          }

          let score: number = 0;
          if (around.match(/kJ|KJ|千焦|kcal|KCAL|千卡|大卡/) !== null) score += 6;
          if (around.match(/能.{0,2}量|热.{0,2}量|energy/i) !== null) score += 4;
          if (energyWindow.length > 0 && energyWindow.indexOf(token) >= 0) score += 3;
          if (n >= 20 && n <= 800) score += 3;
          else if (n > 800 && n <= 2500) score += 1;
          if (isYearLike) score -= 4;
          if (hasDateOrAddrHint) score -= 4;

          if (score > bestScore || (score === bestScore && (best <= 0 || n < best))) {
            bestScore = score;
            best = n;
          }
        }
        m = reg.exec(normalizedText);
      }
      // 仅接受合理范围，避免异常大值误判
      if (best < 10 || best > 5000) {
        best = 0;
      }
      value = best;
    }

    if (value <= 0) {
      return null;
    }

    if (targetLine.match(/kcal|KCAL|千卡|大卡/) !== null || normalizedText.match(/kcal|KCAL|千卡|大卡/) !== null) {
      unit = 'kcal';
    }

    let basisType: string = 'per100';
    let per100Unit: string = 'g';
    if (normalizedText.match(/每\s*份|每份|per\s*serving/i) !== null) {
      basisType = 'perServing';
    } else if (normalizedText.match(/每\s*100\s*(ml|毫升)|\/\s*100\s*(ml|毫升)|100\s*(ml|毫升)/i) !== null) {
      basisType = 'per100';
      per100Unit = 'ml';
    } else if (normalizedText.match(/每\s*100\s*(g|克)|\/\s*100\s*(g|克)|100\s*(g|克)/i) !== null) {
      basisType = 'per100';
      per100Unit = 'g';
    }

    let servingSize: number = 0;
    let servingUnit: string = 'g';
    const servingMatch: RegExpMatchArray | null = normalizedText.match(/每\s*份[^0-9]{0,10}(\d+(?:[\.,]\d+)?)\s*(g|克|ml|毫升)/i);
    if (servingMatch !== null && servingMatch.length >= 3) {
      servingSize = Number(servingMatch[1].replace(',', '')) || 0;
      const unitStr: string = servingMatch[2];
      servingUnit = (unitStr.indexOf('ml') >= 0 || unitStr.indexOf('毫升') >= 0) ? 'ml' : 'g';
    }

    const parsed: NutritionParseResult = {
      value: value,
      unit: unit,
      basisType: basisType,
      per100Unit: per100Unit,
      servingSize: servingSize,
      servingUnit: servingUnit
    };
    return parsed;
  }

  private normalizeOcrText(text: string): string {
    const arr: string[] = [];
    for (let i = 0; i < text.length; i++) {
      const ch: string = text.charAt(i);
      if (ch === '\r') {
        continue;
      }
      if (ch === '\n') {
        arr.push('\n');
        continue;
      }
      const code: number = ch.charCodeAt(0);
      if (code >= 0xFF10 && code <= 0xFF19) {
        arr.push(String.fromCharCode(code - 0xFEE0));
      } else if (ch === '．' || ch === '。') {
        arr.push('.');
      } else if (ch === '，') {
        arr.push(',');
      } else if (ch === '／') {
        arr.push('/');
      } else {
        arr.push(ch);
      }
    }
    const joined: string = arr.join('').replace(/\u00A0/g, ' ');
    const lines: string[] = joined.split('\n');
    const normalizedLines: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].replace(/[ \t\f\v]+/g, ' ').trim();
      if (line.length > 0) {
        normalizedLines.push(line);
      }
    }
    return normalizedLines.join('\n');
  }

  private extractNumber(text: string): number {
    const normalized: string = this.normalizeOcrText(text);
    const m: RegExpMatchArray | null = normalized.match(/(\d+(?:[\.,]\d+)?)/);
    if (m !== null && m.length > 1) {
      return Number(m[1].replace(',', '')) || 0;
    }
    return 0;
  }

  private getReferenceKcal(): number {
    const raw: number = Number(this.caloriesText) || 0;
    if (raw <= 0) return 0;
    return this.calorieUnit === 'kJ' ? kjToKcal(raw) : raw;
  }

  private getBasisLabel(): string {
    if (this.calorieBasis === 'per100') return '每100' + this.per100Unit;
    if (this.calorieBasis === 'perServing') return '每份';
    return '每100g';
  }

  private getActualCalories(): number {
    const kcalRef: number = this.getReferenceKcal();
    if (kcalRef <= 0) return 0;
    if (this.calorieBasis === 'per100') {
      const amount: number = Number(this.amountText) || 0;
      if (amount <= 0) return -1;
      return Math.round(kcalRef * amount / 100);
    }
    const servings: number = Number(this.servingsText) || 0;
    if (servings <= 0) return -1;
    return Math.round(kcalRef * servings);
  }

  private buildNutritionMetaForDict(): NutritionMeta {
    const meta: NutritionMeta = {
      rawEnergy: Number(this.caloriesText) || 0,
      energyUnit: this.calorieUnit,
      basisType: this.calorieBasis === 'perServing' ? 'perServing' : (this.per100Unit === 'ml' ? 'per100ml' : 'per100g'),
      servingSize: Number(this.servingSizeText) || 0,
      servingUnit: this.servingUnit,
      isReliable: true
    };
    if (this.calorieBasis === 'perServing' && meta.servingSize <= 0) {
      meta.isReliable = false;
    }
    return meta;
  }

  private getNormalizedCaloriesForDict(meta: NutritionMeta): number {
    const refKcal: number = this.getReferenceKcal();
    if (refKcal <= 0) return 0;
    if (meta.basisType === 'per100g' || meta.basisType === 'per100ml') {
      return refKcal;
    }
    if (meta.basisType === 'perServing' && meta.servingSize > 0) {
      return Math.round(refKcal * 100 / meta.servingSize);
    }
    return 0;
  }

  private confirmAndProceed(): void {
    const rawValue: number = Number(this.caloriesText) || 0;
    if (rawValue <= 0) {
      promptAction.showToast({ message: '请先填写营养标注值', duration: 1600 });
      return;
    }

    if (this.calorieBasis === 'per100' && (Number(this.amountText) || 0) <= 0) {
      promptAction.showToast({ message: '请填写本次入库量（用于计算本份热量）', duration: 1800 });
      return;
    }
    if (this.calorieBasis === 'perServing' && (Number(this.servingsText) || 0) <= 0) {
      promptAction.showToast({ message: '请填写份数（用于计算本份热量）', duration: 1800 });
      return;
    }

    const finalCalories: number = this.getActualCalories();
    if (finalCalories < 0) {
      promptAction.showToast({ message: '请补全数量信息', duration: 1500 });
      return;
    }

    // 存入ProductDict（严格模式：按份但未填写每份重量时，仅存原始标注，不沉淀标准化值）
    if (rawValue > 0) {
      let source: string = 'manual';
      if (this.calorieSource.indexOf('OCR') >= 0) {
        source = 'ocr';
      } else if (this.calorieSource.indexOf('本地记忆') >= 0) {
        source = 'edited';
      }
      const meta: NutritionMeta = this.buildNutritionMetaForDict();
      const normalizedCalories: number = this.getNormalizedCaloriesForDict(meta);
      BarcodeService.getInstance().saveToProductDict(
        this.barcode, this.foodName, this.category,
        this.spec, normalizedCalories, source, meta
      );
      if (meta.basisType === 'perServing' && !meta.isReliable) {
        promptAction.showToast({ message: '已按严格模式保存原始标注，待补全每份重量后再沉淀标准化值', duration: 2200 });
      }
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
      CollaborationServiceStateDialog({
        onState: (stateCode: number, bufferType: string, buffer: ArrayBuffer): void => {
          this.onCollaborationState(stateCode, bufferType, buffer);
        }
      })

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

          // 能量输入区（原始营养标注 + 本次入库量）
          Column({ space: 12 }) {
            Text('营养标注值（来自包装）')
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

            // 能量单位切换（不再固定为kcal）
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

            // 基准切换（简化为每100单位 or 每份）
            Row({ space: 0 }) {
              Text('每100单位')
                .fontSize(13)
                .fontColor(this.calorieBasis === 'per100' ? Color.White : $r('app.color.text_secondary'))
                .textAlign(TextAlign.Center).layoutWeight(1).height(34)
                .backgroundColor(this.calorieBasis === 'per100' ? '#007DFF' : $r('app.color.chip_background'))
                .borderRadius(8)
                .onClick(() => { this.calorieBasis = 'per100'; })
              Text('每份')
                .fontSize(13)
                .fontColor(this.calorieBasis === 'perServing' ? Color.White : $r('app.color.text_secondary'))
                .textAlign(TextAlign.Center).layoutWeight(1).height(34)
                .backgroundColor(this.calorieBasis === 'perServing' ? '#007DFF' : $r('app.color.chip_background'))
                .borderRadius(8)
                .onClick(() => { this.calorieBasis = 'perServing'; })
            }
            .width('100%').borderRadius(8).clip(true)

            Row({ space: 8 }) {
              TextInput({ text: this.caloriesText, placeholder: '输入' + this.getBasisLabel() + '的能量值' })
                .layoutWeight(1).height(48).fontSize(18).borderRadius(8)
                .backgroundColor($r('app.color.input_background'))
                .type(InputType.Number)
                .onChange((value: string) => { this.caloriesText = value; })
              Text(this.calorieUnit).fontSize(16).fontColor($r('app.color.text_secondary'))
            }
            .width('100%')

            if (this.calorieUnit === 'kJ' && this.caloriesText.length > 0) {
              Text('≈ ' + this.getReferenceKcal() + ' kcal（仅换算一次）')
                .fontSize(12).fontColor('#007DFF')
            }

            if (this.calorieBasis === 'per100') {
              Column({ space: 6 }) {
                Text('本次入库量 *')
                  .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
                Row({ space: 8 }) {
                  TextInput({
                    text: this.amountText,
                    placeholder: this.per100Unit === 'ml' ? '输入本次体积（ml）' : '输入本次重量（g）'
                  })
                    .layoutWeight(1).height(44).fontSize(15).borderRadius(8)
                    .backgroundColor($r('app.color.input_background')).type(InputType.Number)
                    .onChange((value: string) => { this.amountText = value; })
                  Row({ space: 0 }) {
                    Text('g')
                      .fontSize(13)
                      .fontColor(this.per100Unit === 'g' ? Color.White : $r('app.color.text_secondary'))
                      .textAlign(TextAlign.Center).width(44).height(32)
                      .backgroundColor(this.per100Unit === 'g' ? '#007DFF' : $r('app.color.chip_background'))
                      .borderRadius(8)
                      .onClick(() => { this.per100Unit = 'g'; })
                    Text('ml')
                      .fontSize(13)
                      .fontColor(this.per100Unit === 'ml' ? Color.White : $r('app.color.text_secondary'))
                      .textAlign(TextAlign.Center).width(44).height(32)
                      .backgroundColor(this.per100Unit === 'ml' ? '#007DFF' : $r('app.color.chip_background'))
                      .borderRadius(8)
                      .onClick(() => { this.per100Unit = 'ml'; })
                  }
                }
              }
            } else {
              Column({ space: 8 }) {
                Text('按份信息')
                  .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')

                Row({ space: 8 }) {
                  TextInput({ text: this.servingsText, placeholder: '本次份数（如 1）' })
                    .layoutWeight(1).height(44).fontSize(15).borderRadius(8)
                    .backgroundColor($r('app.color.input_background')).type(InputType.Number)
                    .onChange((value: string) => { this.servingsText = value; })
                  Text('份')
                    .fontSize(14).fontColor($r('app.color.text_secondary'))
                }

                Row({ space: 8 }) {
                  TextInput({ text: this.servingSizeText, placeholder: '每份重量/体积（严格模式建议填写）' })
                    .layoutWeight(1).height(44).fontSize(15).borderRadius(8)
                    .backgroundColor($r('app.color.input_background')).type(InputType.Number)
                    .onChange((value: string) => { this.servingSizeText = value; })
                  Row({ space: 0 }) {
                    Text('g')
                      .fontSize(13)
                      .fontColor(this.servingUnit === 'g' ? Color.White : $r('app.color.text_secondary'))
                      .textAlign(TextAlign.Center).width(44).height(32)
                      .backgroundColor(this.servingUnit === 'g' ? '#007DFF' : $r('app.color.chip_background'))
                      .borderRadius(8)
                      .onClick(() => { this.servingUnit = 'g'; })
                    Text('ml')
                      .fontSize(13)
                      .fontColor(this.servingUnit === 'ml' ? Color.White : $r('app.color.text_secondary'))
                      .textAlign(TextAlign.Center).width(44).height(32)
                      .backgroundColor(this.servingUnit === 'ml' ? '#007DFF' : $r('app.color.chip_background'))
                      .borderRadius(8)
                      .onClick(() => { this.servingUnit = 'ml'; })
                  }
                }
              }
            }

            if (this.getActualCalories() > 0) {
              Text('本次入库热量 ≈ ' + this.getActualCalories() + ' kcal')
                .fontSize(13).fontColor('#34C759')
            }

            Button('实时拍照识别 (OCR)')
              .width('100%').height(40).fontSize(14)
              .fontColor('#007DFF').backgroundColor('#E8F0FE').borderRadius(8)
              .onClick(() => { this.startOcrRecognition(); })

            if (this.showCollaborationButton) {
              Button('手机协同传图识别')
                .width('100%').height(40).fontSize(14)
                .fontColor('#007DFF').backgroundColor('#E8F0FE').borderRadius(8)
                .bindMenu(this.collaborationMenu)
            }

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

            if (this.calorieBasis === 'perServing' && (Number(this.servingSizeText) || 0) <= 0) {
              Row({ space: 6 }) {
                Text('⚠️').fontSize(14)
                Text('严格模式：未填写“每份重量/体积”时，不会沉淀标准化值（仅保存原始标注）')
                  .fontSize(12).fontColor('#FF9500')
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
            Text('• 统一记录：原始标注值 + 单位 + 基准；避免重复换算')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Text('• 严格模式：按份但未填每份重量时，不沉淀标准化值')
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

      if (this.showOcrCheckDialog) {
        Column() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#80000000')
            .onClick(() => {
              this.showOcrCheckDialog = false;
            })
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })

        Column({ space: 12 }) {
          Text('OCR营养信息校验')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          Text('请检查识别值、单位和基准（100g/100ml/每份）')
            .fontSize(13)
            .fontColor($r('app.color.text_hint'))
            .width('100%')

          Column({ space: 4 }) {
            Text('能量值')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.ocrDialogValue, placeholder: '输入OCR识别结果' })
              .width('100%')
              .height(44)
              .fontSize(15)
              .borderRadius(8)
              .backgroundColor($r('app.color.input_background'))
              .type(InputType.Number)
              .onChange((value: string) => {
                this.ocrDialogValue = value;
              })
          }

          Row({ space: 0 }) {
            Text('kJ')
              .fontSize(13)
              .fontColor(this.ocrDialogUnit === 'kJ' ? Color.White : $r('app.color.text_secondary'))
              .textAlign(TextAlign.Center).layoutWeight(1).height(34)
              .backgroundColor(this.ocrDialogUnit === 'kJ' ? '#007DFF' : $r('app.color.chip_background'))
              .borderRadius(8)
              .onClick(() => { this.ocrDialogUnit = 'kJ'; })
            Text('kcal')
              .fontSize(13)
              .fontColor(this.ocrDialogUnit === 'kcal' ? Color.White : $r('app.color.text_secondary'))
              .textAlign(TextAlign.Center).layoutWeight(1).height(34)
              .backgroundColor(this.ocrDialogUnit === 'kcal' ? '#007DFF' : $r('app.color.chip_background'))
              .borderRadius(8)
              .onClick(() => { this.ocrDialogUnit = 'kcal'; })
          }
          .width('100%').borderRadius(8).clip(true)

          Row({ space: 0 }) {
            Text('每100单位')
              .fontSize(13)
              .fontColor(this.ocrDialogBasis === 'per100' ? Color.White : $r('app.color.text_secondary'))
              .textAlign(TextAlign.Center).layoutWeight(1).height(34)
              .backgroundColor(this.ocrDialogBasis === 'per100' ? '#007DFF' : $r('app.color.chip_background'))
              .borderRadius(8)
              .onClick(() => { this.ocrDialogBasis = 'per100'; })
            Text('每份')
              .fontSize(13)
              .fontColor(this.ocrDialogBasis === 'perServing' ? Color.White : $r('app.color.text_secondary'))
              .textAlign(TextAlign.Center).layoutWeight(1).height(34)
              .backgroundColor(this.ocrDialogBasis === 'perServing' ? '#007DFF' : $r('app.color.chip_background'))
              .borderRadius(8)
              .onClick(() => { this.ocrDialogBasis = 'perServing'; })
          }
          .width('100%').borderRadius(8).clip(true)

          if (this.ocrDialogBasis === 'per100') {
            Row({ space: 8 }) {
              Text('每100单位类型').fontSize(12).fontColor($r('app.color.text_hint')).layoutWeight(1)
              Row({ space: 0 }) {
                Text('g')
                  .fontSize(13)
                  .fontColor(this.ocrDialogPer100Unit === 'g' ? Color.White : $r('app.color.text_secondary'))
                  .textAlign(TextAlign.Center).width(42).height(32)
                  .backgroundColor(this.ocrDialogPer100Unit === 'g' ? '#007DFF' : $r('app.color.chip_background'))
                  .borderRadius(8)
                  .onClick(() => { this.ocrDialogPer100Unit = 'g'; })
                Text('ml')
                  .fontSize(13)
                  .fontColor(this.ocrDialogPer100Unit === 'ml' ? Color.White : $r('app.color.text_secondary'))
                  .textAlign(TextAlign.Center).width(42).height(32)
                  .backgroundColor(this.ocrDialogPer100Unit === 'ml' ? '#007DFF' : $r('app.color.chip_background'))
                  .borderRadius(8)
                  .onClick(() => { this.ocrDialogPer100Unit = 'ml'; })
              }
            }
            .width('100%')
          }

          if (this.ocrDialogBasis === 'perServing') {
            Row({ space: 8 }) {
              TextInput({ text: this.ocrDialogServingSize, placeholder: '每份重量/体积（可识别后手改）' })
                .layoutWeight(1).height(40).fontSize(14).borderRadius(8)
                .backgroundColor($r('app.color.input_background')).type(InputType.Number)
                .onChange((value: string) => { this.ocrDialogServingSize = value; })
              Row({ space: 0 }) {
                Text('g')
                  .fontSize(13)
                  .fontColor(this.ocrDialogServingUnit === 'g' ? Color.White : $r('app.color.text_secondary'))
                  .textAlign(TextAlign.Center).width(42).height(32)
                  .backgroundColor(this.ocrDialogServingUnit === 'g' ? '#007DFF' : $r('app.color.chip_background'))
                  .borderRadius(8)
                  .onClick(() => { this.ocrDialogServingUnit = 'g'; })
                Text('ml')
                  .fontSize(13)
                  .fontColor(this.ocrDialogServingUnit === 'ml' ? Color.White : $r('app.color.text_secondary'))
                  .textAlign(TextAlign.Center).width(42).height(32)
                  .backgroundColor(this.ocrDialogServingUnit === 'ml' ? '#007DFF' : $r('app.color.chip_background'))
                  .borderRadius(8)
                  .onClick(() => { this.ocrDialogServingUnit = 'ml'; })
              }
            }
            .width('100%')
          }

          Row({ space: 12 }) {
            Button('取消')
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .backgroundColor($r('app.color.chip_background'))
              .borderRadius(8)
              .onClick(() => {
                this.showOcrCheckDialog = false;
              })
            Button('确认')
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontColor(Color.White)
              .backgroundColor('#007DFF')
              .borderRadius(8)
              .onClick(() => {
                this.confirmOcrValue();
              })
          }
          .width('100%')
        }
        .width('85%')
        .padding(20)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .position({ x: '7.5%', y: '28%' })
      }
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
