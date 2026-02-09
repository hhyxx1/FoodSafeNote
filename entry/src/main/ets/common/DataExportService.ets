import { fileIo } from '@kit.CoreFileKit';
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
  message: string;
}

export class DataExportService {
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

  // 保存JSON到文件
  static async saveToFile(context: common.Context, content: string, fileName: string): Promise<string> {
    const dir: string = context.filesDir;
    const filePath: string = dir + '/' + fileName;
    const file: fileIo.File = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    fileIo.writeSync(file.fd, content);
    fileIo.closeSync(file.fd);
    return filePath;
  }

  // 从文件读取JSON
  static async readFromFile(filePath: string): Promise<string> {
    const file: fileIo.File = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
    const stat: fileIo.Stat = fileIo.statSync(filePath);
    const buf = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, buf);
    fileIo.closeSync(file.fd);
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decode(new Uint8Array(buf));
  }

  // 全量导入
  static async importAllData(jsonStr: string): Promise<ImportResult> {
    const result: ImportResult = { success: false, message: '' };
    try {
      const data: ExportData = JSON.parse(jsonStr) as ExportData;
      if (data.foodItems === undefined && data.members === undefined) {
        result.message = '文件格式错误';
        return result;
      }
      const db: DatabaseHelper = DatabaseHelper.getInstance();

      // 导入食品
      if (data.foodItems !== undefined) {
        for (let i = 0; i < data.foodItems.length; i++) {
          const item: FoodItem = data.foodItems[i];
          const food = new FoodItem();
          food.name = item.name;
          food.category = item.category;
          food.spec = item.spec;
          food.barcode = item.barcode;
          food.calories = item.calories;
          food.storageType = item.storageType;
          food.expiryDate = item.expiryDate;
          food.status = item.status;
          await db.insertFoodItem(food);
        }
      }

      // 导入成员
      if (data.members !== undefined) {
        for (let i = 0; i < data.members.length; i++) {
          await db.insertMember(data.members[i].name);
        }
      }

      // 导入产品字典
      if (data.productDict !== undefined) {
        for (let i = 0; i < data.productDict.length; i++) {
          const dict: ProductDict = data.productDict[i];
          const pd = new ProductDict();
          pd.dictKey = dict.dictKey;
          pd.barcode = dict.barcode;
          pd.name = dict.name;
          pd.category = dict.category;
          pd.spec = dict.spec;
          pd.calories = dict.calories;
          pd.source = dict.source;
          await db.insertOrUpdateProductDict(pd);
        }
      }

      // 导入消耗记录
      if (data.consumptionRecords !== undefined) {
        for (let i = 0; i < data.consumptionRecords.length; i++) {
          const rec: ConsumptionRecord = data.consumptionRecords[i];
          await db.insertConsumptionRecord(rec);
        }
      }

      // 导入OCR记录
      if (data.ocrRecords !== undefined) {
        for (let i = 0; i < data.ocrRecords.length; i++) {
          const ocr: OcrRecord = data.ocrRecords[i];
          const ocrRec = new OcrRecord();
          ocrRec.foodName = ocr.foodName;
          ocrRec.barcode = ocr.barcode;
          ocrRec.ocrValue = ocr.ocrValue;
          ocrRec.finalValue = ocr.finalValue;
          await db.insertOcrRecord(ocrRec);
        }
      }

      result.success = true;
      result.message = '导入成功';
    } catch (e) {
      result.message = '导入失败: 数据格式错误';
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
