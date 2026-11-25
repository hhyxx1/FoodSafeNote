import { fileIo, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { DatabaseHelper } from './DatabaseHelper';
import { FoodItem, FamilyMember, ProductDict, ConsumptionRecord, OcrRecord } from '../model/DataModels';

// 导出数据结构接口
interface ExportData {
  version: string;
  exportTime: number;
  foodItems: FoodItem[];
  members: FamilyMember[];
  productDict: ProductDict[];
  consumptionRecords: ConsumptionRecord[];
  ocrRecords: OcrRecord[];
}

interface ImportResult {
  success: boolean;
  message: ResourceStr;
  imported?: number;
  skipped?: number;
}

interface ProductDictImportPayload {
  productDict: ProductDict[];
}

export class DataExportService {
  private static async yieldToUi(index: number, step: number = 40): Promise<void> {
    if (index > 0 && index % step === 0) {
      await Promise.resolve();
    }
  }

  private static normalizeProductDict(raw: ProductDict): ProductDict | null {
    const barcode: string = (raw.barcode || '').trim();
    const name: string = (raw.name || '').trim();
    const category: string = (raw.category || '').trim();
    const spec: string = (raw.spec || '').trim();
    if (name.length === 0) {
      return null;
    }

    const pd = new ProductDict();
    pd.barcode = barcode;
    pd.name = name;
    pd.category = category;
    pd.spec = spec;
    pd.dictKey = barcode.length > 0 ? barcode : (category + '_' + name);
    pd.calories = Number(raw.calories) || 0;
    pd.rawEnergy = Number(raw.rawEnergy) || 0;
    pd.energyUnit = (raw.energyUnit === 'kcal' ? 'kcal' : 'kJ');
    pd.basisType = (raw.basisType === 'per100ml' || raw.basisType === 'perServing') ? raw.basisType : 'per100g';
    pd.servingSize = Number(raw.servingSize) || 0;
    pd.servingUnit = (raw.servingUnit === 'ml' ? 'ml' : 'g');
    pd.isReliable = raw.isReliable !== false;
    pd.source = (raw.source || 'manual');
    return pd;
  }

  static async importProductDictJson(jsonStr: string): Promise<ImportResult> {
    const result: ImportResult = { success: false, message: '', imported: 0, skipped: 0 };
    try {
      const parsed: Record<string, Object> = JSON.parse(jsonStr) as Record<string, Object>;
      const dictArray: ProductDict[] = parsed['productDict'] as ProductDict[];
      if (dictArray === undefined || dictArray === null) {
        result.message = $r('app.string.ui_invalid_file_missing_product_dictionary');
        return result;
      }

      const db: DatabaseHelper = DatabaseHelper.getInstance();
      const seenKeys: Set<string> = new Set<string>();
      for (let i = 0; i < dictArray.length; i++) {
        const normalized: ProductDict | null = DataExportService.normalizeProductDict(dictArray[i]);
        if (normalized === null || normalized.dictKey.length === 0) {
          result.skipped = (result.skipped || 0) + 1;
          continue;
        }
        if (seenKeys.has(normalized.dictKey)) {
          result.skipped = (result.skipped || 0) + 1;
          continue;
        }
        seenKeys.add(normalized.dictKey);
        if (await db.insertOrUpdateProductDict(normalized) > 0) {
          result.imported = (result.imported || 0) + 1;
        } else {
          result.skipped = (result.skipped || 0) + 1;
        }
        await DataExportService.yieldToUi(i);
      }
      result.success = true;
      result.message = $r('app.string.ui_product_dictionary_imported');
      return result;
    } catch (e) {
      result.message = $r('app.string.ui_import_failed_invalid_data_format');
      return result;
    }
  }

  // 全量导出为JSON字符串
  static async exportAllData(): Promise<string> {
    const db: DatabaseHelper = DatabaseHelper.getInstance();
    const foods: FoodItem[] = await db.getAllFoodItems();
    const members: FamilyMember[] = await db.getAllMembers();
    const dicts: ProductDict[] = await db.getAllProductDict();
    const consumptions: ConsumptionRecord[] = await db.getConsumptionsByRange(0, Date.now());
    const ocrs: OcrRecord[] = await db.getOcrRecords(9999);

    const data: ExportData = {
      version: '1.0.0',
      exportTime: Date.now(),
      foodItems: foods,
      members: members,
      productDict: dicts,
      consumptionRecords: consumptions,
      ocrRecords: ocrs
    };
    return JSON.stringify(data);
  }

  // 产品字典单独导出
  static async exportProductDict(): Promise<string> {
    const db: DatabaseHelper = DatabaseHelper.getInstance();
    const dicts: ProductDict[] = await db.getAllProductDict();
    const data: Record<string, Object> = {
      'version': '1.0.0',
      'exportTime': Date.now(),
      'productDict': dicts
    };
    return JSON.stringify(data);
  }

  static async saveToFile(context: common.UIAbilityContext, content: string, fileName: string): Promise<boolean> {
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    const uris: string[] = await new picker.DocumentViewPicker(context).save(options);
    if (uris.length === 0) return false;

    const file = await fileIo.open(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, content);
    } finally {
      await fileIo.close(file);
    }
    return true;
  }

  static async pickImportFile(context: common.UIAbilityContext): Promise<string[]> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['.json'];
    return await new picker.DocumentViewPicker(context).select(options);
  }

  static async readFromFile(filePath: string): Promise<string> {
    const file = await fileIo.open(filePath, fileIo.OpenMode.READ_ONLY);
    try {
      const stat: fileIo.Stat = await fileIo.stat(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      const length: number = await fileIo.read(file.fd, buffer);
      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(new Uint8Array(buffer, 0, length));
    } finally {
      await fileIo.close(file);
    }
  }

  // 全量导入
  static async importAllData(jsonStr: string): Promise<ImportResult> {
    const result: ImportResult = { success: false, message: '', imported: 0, skipped: 0 };
    const db = DatabaseHelper.getInstance();
    db.deviceSync.pause();
    try {
      const data: ExportData = JSON.parse(jsonStr) as ExportData;
      if (data.foodItems === undefined && data.members === undefined) {
        result.message = $r('app.string.ui_invalid_file_format');
        return result;
      }
      const restoredFoodIds: Map<number, number> = new Map<number, number>();

      // 导入食品
      if (data.foodItems !== undefined) {
        for (let i = 0; i < data.foodItems.length; i++) {
          const item: FoodItem = data.foodItems[i];
          if ((item.name || '').trim().length === 0) {
            result.skipped = (result.skipped || 0) + 1;
            continue;
          }
          const food = new FoodItem();
          food.name = item.name;
          food.category = item.category;
          food.spec = item.spec;
          food.barcode = item.barcode;
          food.calories = item.calories;
          food.storageType = item.storageType;
          food.expiryDate = item.expiryDate;
          food.status = item.status;
          food.isOpened = item.isOpened === true;
          food.createTime = item.createTime || 0;
          food.consumedBy = item.consumedBy || '';
          food.wasteReason = item.wasteReason || '';
          food.consumeTime = item.consumeTime || 0;
          const restoredId: number = await db.insertFoodItem(food);
          if (restoredId > 0) {
            if (item.id > 0) restoredFoodIds.set(item.id, restoredId);
            result.imported = (result.imported || 0) + 1;
          } else {
            result.skipped = (result.skipped || 0) + 1;
          }
          await DataExportService.yieldToUi(i);
        }
      }

      // 导入成员
      if (data.members !== undefined) {
        const memberSet: Set<string> = new Set<string>();
        for (let i = 0; i < data.members.length; i++) {
          const name: string = (data.members[i].name || '').trim();
          if (name.length === 0 || memberSet.has(name)) {
            result.skipped = (result.skipped || 0) + 1;
            continue;
          }
          memberSet.add(name);
          if (await db.insertMember(name) > 0) {
            result.imported = (result.imported || 0) + 1;
          } else {
            result.skipped = (result.skipped || 0) + 1;
          }
          await DataExportService.yieldToUi(i);
        }
      }

      // 导入产品字典
      if (data.productDict !== undefined) {
        const dictPayload: ProductDictImportPayload = { productDict: data.productDict };
        const dictResult: ImportResult = await DataExportService.importProductDictJson(JSON.stringify(dictPayload));
        result.imported = (result.imported || 0) + (dictResult.imported || 0);
        result.skipped = (result.skipped || 0) + (dictResult.skipped || 0);
      }

      // 导入消耗记录
      if (data.consumptionRecords !== undefined) {
        for (let i = 0; i < data.consumptionRecords.length; i++) {
          const rec: ConsumptionRecord = data.consumptionRecords[i];
          if ((rec.foodName || '').trim().length === 0) {
            result.skipped = (result.skipped || 0) + 1;
            continue;
          }
          rec.foodItemId = restoredFoodIds.get(rec.foodItemId) ?? 0;
          if (await db.insertConsumptionRecord(rec) > 0) {
            result.imported = (result.imported || 0) + 1;
          } else {
            result.skipped = (result.skipped || 0) + 1;
          }
          await DataExportService.yieldToUi(i);
        }
      }

      // 导入OCR记录
      if (data.ocrRecords !== undefined) {
        for (let i = 0; i < data.ocrRecords.length; i++) {
          const ocr: OcrRecord = data.ocrRecords[i];
          if ((ocr.foodName || '').trim().length === 0 && (ocr.barcode || '').trim().length === 0) {
            result.skipped = (result.skipped || 0) + 1;
            continue;
          }
          const ocrRec = new OcrRecord();
          ocrRec.foodName = ocr.foodName;
          ocrRec.barcode = ocr.barcode;
          ocrRec.ocrValue = ocr.ocrValue;
          ocrRec.finalValue = ocr.finalValue;
          ocrRec.createTime = ocr.createTime || 0;
          if (await db.insertOcrRecord(ocrRec) > 0) {
            result.imported = (result.imported || 0) + 1;
          } else {
            result.skipped = (result.skipped || 0) + 1;
          }
          await DataExportService.yieldToUi(i);
        }
      }

      result.success = true;
      result.message = $r('app.string.ui_import_complete_d_added_d_skipped', result.imported || 0, result.skipped || 0);
    } catch (e) {
      result.message = $r('app.string.ui_import_failed_invalid_data_format');
    } finally {
      db.deviceSync.resume();
    }
    return result;
  }

  // 获取备份文件列表
  static getBackupFiles(context: common.Context): string[] {
    const dir: string = context.filesDir;
    const files: string[] = [];
    try {
      const dirEntries: string[] = fileIo.listFileSync(dir);
      for (let i = 0; i < dirEntries.length; i++) {
        if (dirEntries[i].endsWith('.json')) {
          files.push(dirEntries[i]);
        }
      }
    } catch (e) {
      // 目录读取失败
    }
    return files;
  }
}
