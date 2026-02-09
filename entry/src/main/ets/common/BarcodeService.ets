import { common } from '@kit.AbilityKit';
import { DatabaseHelper } from './DatabaseHelper';
import { ProductDict, BarcodeMatchResult } from '../model/DataModels';
import { util } from '@kit.ArkTS';

// 条码匹配服务：两层本地匹配 + CSV导入
export class BarcodeService {
  private static instance: BarcodeService | null = null;
  private initialized: boolean = false;

  static getInstance(): BarcodeService {
    if (BarcodeService.instance === null) {
      BarcodeService.instance = new BarcodeService();
    }
    return BarcodeService.instance;
  }

  // 首次启动时初始化内置条码库
  async initBuiltinLibrary(context: common.Context): Promise<void> {
    if (this.initialized) return;
    const db: DatabaseHelper = DatabaseHelper.getInstance();
    const count: number = await db.getBuiltinBarcodeCount();
    if (count > 0) {
      this.initialized = true;
      return;
    }
    // 从rawfile读取CSV并批量导入
    try {
      const rawData: Uint8Array = await context.resourceManager.getRawFileContent('food_barcodes.csv');
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      const csvText: string = decoder.decodeToString(rawData);
      const lines: string[] = csvText.split('\n');
      const barcodes: string[] = [];
      const names: string[] = [];
      // 跳过header行
      for (let i = 1; i < lines.length; i++) {
        const line: string = lines[i].trim();
        if (line.length === 0) continue;
        const commaIdx: number = line.indexOf(',');
        if (commaIdx <= 0) continue;
        const barcode: string = line.substring(0, commaIdx).trim();
        const name: string = line.substring(commaIdx + 1).trim();
        if (barcode.length > 0 && name.length > 0) {
          barcodes.push(barcode);
          names.push(name);
        }
      }
      if (barcodes.length > 0) {
        await db.batchInsertBuiltinBarcodes(barcodes, names);
      }
      this.initialized = true;
    } catch (e) {
      // CSV导入失败不影响应用使用
      this.initialized = true;
    }
  }

  // 两层条码匹配算法
  async matchBarcodeInfo(barcode: string): Promise<BarcodeMatchResult> {
    const result = new BarcodeMatchResult();
    if (barcode.length === 0) return result;
    const db: DatabaseHelper = DatabaseHelper.getInstance();

    // 第一层：匹配本地记忆库（ProductDict）- 优先级最高
    const dictInfo: ProductDict | null = await db.queryProductDictByBarcode(barcode);
    if (dictInfo !== null && dictInfo.name.length > 0) {
      result.name = dictInfo.name;
      result.category = dictInfo.category;
      result.spec = dictInfo.spec;
      result.calories = dictInfo.calories;
      result.source = 'product_dict';
      result.matched = true;
      return result;
    }

    // 第二层：匹配内置本地条码库
    const builtinName: string = await db.queryBuiltinBarcode(barcode);
    if (builtinName.length > 0) {
      result.name = builtinName;
      result.category = '';
      result.spec = '';
      result.calories = 0;
      result.source = 'builtin';
      result.matched = true;
      return result;
    }

    // 无匹配
    return result;
  }

  // 热量两层获取：先查ProductDict，返回热量值
  async fetchCalories(barcode: string, category: string, name: string): Promise<number> {
    const db: DatabaseHelper = DatabaseHelper.getInstance();
    // 有条码则以条码为键查询
    if (barcode.length > 0) {
      const dict: ProductDict | null = await db.queryProductDictByBarcode(barcode);
      if (dict !== null && dict.calories > 0) {
        return dict.calories;
      }
    }
    // 无条码则以品类+名称为键
    if (category.length > 0 && name.length > 0) {
      const key: string = category + '_' + name;
      const dict: ProductDict | null = await db.queryProductDictByKey(key);
      if (dict !== null && dict.calories > 0) {
        return dict.calories;
      }
    }
    return 0;
  }

  // 确认后存入本地记忆库
  async saveToProductDict(barcode: string, name: string, category: string,
    spec: string, calories: number, source: string): Promise<void> {
    const db: DatabaseHelper = DatabaseHelper.getInstance();
    const dict = new ProductDict();
    dict.dictKey = barcode.length > 0 ? barcode : (category + '_' + name);
    dict.barcode = barcode;
    dict.name = name;
    dict.category = category;
    dict.spec = spec;
    dict.calories = calories;
    dict.source = source;
    await db.insertOrUpdateProductDict(dict);
  }

  isInitialized(): boolean {
    return this.initialized;
  }
}
