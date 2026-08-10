import { common } from '@kit.AbilityKit';
import { DatabaseHelper } from './DatabaseHelper';
import { ProductDict, BarcodeMatchResult, BuiltinBarcode } from '../model/DataModels';
import { util } from '@kit.ArkTS';

export interface NutritionMeta {
  rawEnergy: number;
  energyUnit: string;
  basisType: string;
  servingSize: number;
  servingUnit: string;
  isReliable: boolean;
}

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
    const missingCategoryCount: number = await db.getBuiltinBarcodeMissingCategoryCount();
    if (count > 0 && missingCategoryCount === 0) {
      this.initialized = true;
      return;
    }
    if (count > 0 && missingCategoryCount > 0) {
      await db.clearBuiltinBarcodes();
    }
    // 从rawfile读取CSV并批量导入
    try {
      const rawData: Uint8Array = await context.resourceManager.getRawFileContent('food_barcodes.csv');
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      const csvText: string = decoder.decodeToString(rawData);
      const lines: string[] = csvText.split('\n');
      const barcodes: string[] = [];
      const names: string[] = [];
      const categories: string[] = [];
      const specs: string[] = [];
      // 跳过header行
      for (let i = 1; i < lines.length; i++) {
        const line: string = lines[i].trim();
        if (line.length === 0) continue;
        const firstComma: number = line.indexOf(',');
        if (firstComma <= 0) continue;
        const barcode: string = line.substring(0, firstComma).trim();
        const rest: string = line.substring(firstComma + 1);
        const secondComma: number = rest.indexOf(',');
        let name: string = '';
        let spec: string = '';
        if (secondComma >= 0) {
          name = rest.substring(0, secondComma).trim();
          spec = rest.substring(secondComma + 1).trim();
        } else {
          name = rest.trim();
          spec = '';
        }
        if (barcode.length > 0 && name.length > 0) {
          barcodes.push(barcode);
          names.push(name);
          categories.push(this.inferBuiltinCategory(name));
          specs.push(spec);
        }
      }
      if (barcodes.length > 0) {
        await db.batchInsertBuiltinBarcodes(barcodes, names, categories, specs);
      }
      this.initialized = true;
    } catch (e) {
      // CSV导入失败：不标记 initialized，允许下次启动重试；不影响应用其他功能
    }
  }

  private inferBuiltinCategory(name: string): string {
    if (name.indexOf('牛奶') >= 0 || name.indexOf('酸奶') >= 0 || name.indexOf('奶') >= 0) {
      return '乳制品';
    }
    if (name.indexOf('饼干') >= 0 || name.indexOf('薯片') >= 0 || name.indexOf('巧克力') >= 0 ||
      name.indexOf('零食') >= 0 || name.indexOf('芝麻糊') >= 0) {
      return '零食';
    }
    if (name.indexOf('酱油') >= 0 || name.indexOf('味精') >= 0 || name.indexOf('调味') >= 0 ||
      name.indexOf('鸡精') >= 0 || name.indexOf('火锅底料') >= 0) {
      return '调味品';
    }
    if (name.indexOf('罐头') >= 0) {
      return '罐头';
    }
    if (name.indexOf('饮料') >= 0 || name.indexOf('果汁') >= 0 || name.indexOf('可乐') >= 0 || name.indexOf('茶') >= 0) {
      return '饮料';
    }
    if (name.indexOf('面') >= 0 || name.indexOf('米') >= 0) {
      return '主食';
    }
    return '其他';
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
    const builtinInfo: BuiltinBarcode | null = await db.queryBuiltinBarcode(barcode);
    if (builtinInfo !== null && builtinInfo.name.length > 0) {
      result.name = builtinInfo.name;
      result.category = builtinInfo.category;
      result.spec = builtinInfo.spec;
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

  // 获取完整营养预设（单位/基准等）
  async fetchNutritionPreset(barcode: string, category: string, name: string): Promise<ProductDict | null> {
    const db: DatabaseHelper = DatabaseHelper.getInstance();
    if (barcode.length > 0) {
      const byBarcode: ProductDict | null = await db.queryProductDictByBarcode(barcode);
      if (byBarcode !== null) {
        return byBarcode;
      }
    }
    if (category.length > 0 && name.length > 0) {
      const key: string = category + '_' + name;
      return await db.queryProductDictByKey(key);
    }
    return null;
  }

  // 确认后存入本地记忆库
  async saveToProductDict(barcode: string, name: string, category: string,
    spec: string, calories: number, source: string, meta?: NutritionMeta): Promise<void> {
    const db: DatabaseHelper = DatabaseHelper.getInstance();
    const dict = new ProductDict();
    dict.dictKey = barcode.length > 0 ? barcode : (category + '_' + name);
    // dict_key 列为 UNIQUE NOT NULL，键为空时直接放弃写入，避免违反约束
    if (dict.dictKey.length === 0) {
      return;
    }
    dict.barcode = barcode;
    dict.name = name;
    dict.category = category;
    dict.spec = spec;
    dict.calories = calories;
    dict.rawEnergy = meta !== undefined ? meta.rawEnergy : calories;
    dict.energyUnit = meta !== undefined ? meta.energyUnit : 'kcal';
    dict.basisType = meta !== undefined ? meta.basisType : 'per100g';
    dict.servingSize = meta !== undefined ? meta.servingSize : 0;
    dict.servingUnit = meta !== undefined ? meta.servingUnit : 'g';
    dict.isReliable = meta !== undefined ? meta.isReliable : true;

    // 严格模式保护：按份但缺少每份重量时，不用0覆盖已有标准化值
    if (meta !== undefined && !meta.isReliable && calories <= 0) {
      const existing: ProductDict | null = await db.queryProductDictByKey(dict.dictKey);
      if (existing !== null && existing.calories > 0) {
        dict.calories = existing.calories;
      }
    }
    dict.source = source;
    await db.insertOrUpdateProductDict(dict);
  }

  isInitialized(): boolean {
    return this.initialized;
  }
}
