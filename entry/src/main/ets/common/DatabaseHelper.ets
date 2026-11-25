import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { FoodDeviceSync } from './FoodDeviceSync';
import { migrateLegacyFoodDatabase } from './FoodDatabaseMigration';
import { FoodItem, FamilyMember, ConsumptionRecord, DailyCalorie, FoodStats,
  ProductDict, OcrRecord, WasteStat, BuiltinBarcode } from '../model/DataModels';

const DB_NAME: string = 'FoodSafeNoteShared.db';
const FOOD_TABLE: string = 'food_items';
const MEMBER_TABLE: string = 'family_members';
const CONSUMPTION_TABLE: string = 'consumption_records';
const PRODUCT_DICT_TABLE: string = 'product_dict';
const BUILTIN_BARCODE_TABLE: string = 'builtin_barcodes';
const OCR_RECORD_TABLE: string = 'ocr_records';

const SQL_CREATE_FOOD: string =
  'CREATE TABLE IF NOT EXISTS food_items (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
  'sync_key TEXT NOT NULL UNIQUE,' +
  'name TEXT NOT NULL,' +
  'category TEXT DEFAULT "",' +
  'spec TEXT DEFAULT "",' +
  'barcode TEXT DEFAULT "",' +
  'calories REAL DEFAULT 0,' +
  'storage_type TEXT DEFAULT "FRIDGE",' +
  'expiry_date INTEGER DEFAULT 0,' +
  'status INTEGER DEFAULT 0,' +
  'create_time INTEGER DEFAULT 0,' +
  'consumed_by TEXT DEFAULT "",' +
  'waste_reason TEXT DEFAULT "",' +
  'consume_time INTEGER DEFAULT 0,' +
  'is_opened INTEGER DEFAULT 0)';

const SQL_CREATE_MEMBER: string =
  'CREATE TABLE IF NOT EXISTS family_members (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
  'sync_key TEXT NOT NULL UNIQUE,' +
  'name TEXT NOT NULL,' +
  'create_time INTEGER DEFAULT 0)';

const SQL_CREATE_CONSUMPTION: string =
  'CREATE TABLE IF NOT EXISTS consumption_records (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
  'sync_key TEXT NOT NULL UNIQUE,' +
  'food_sync_key TEXT NOT NULL DEFAULT "",' +
  'food_name TEXT DEFAULT "",' +
  'member_name TEXT DEFAULT "",' +
  'type INTEGER DEFAULT 0,' +
  'calories REAL DEFAULT 0,' +
  'waste_reason TEXT DEFAULT "",' +
  'create_time INTEGER DEFAULT 0)';

const SQL_CREATE_PRODUCT_DICT: string =
  'CREATE TABLE IF NOT EXISTS product_dict (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
  'dict_key TEXT UNIQUE NOT NULL,' +
  'barcode TEXT DEFAULT "",' +
  'name TEXT NOT NULL,' +
  'category TEXT DEFAULT "",' +
  'spec TEXT DEFAULT "",' +
  'calories REAL DEFAULT 0,' +
  'raw_energy REAL DEFAULT 0,' +
  'energy_unit TEXT DEFAULT "kJ",' +
  'basis_type TEXT DEFAULT "per100g",' +
  'serving_size REAL DEFAULT 0,' +
  'serving_unit TEXT DEFAULT "g",' +
  'is_reliable INTEGER DEFAULT 1,' +
  'source TEXT DEFAULT "manual",' +
  'update_time INTEGER DEFAULT 0)';

const SQL_CREATE_BUILTIN_BARCODE: string =
  'CREATE TABLE IF NOT EXISTS builtin_barcodes (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
  'barcode TEXT NOT NULL,' +
  'name TEXT NOT NULL,' +
  'category TEXT DEFAULT "",' +
  'spec TEXT DEFAULT "")';

const SQL_CREATE_BUILTIN_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_builtin_barcode ON builtin_barcodes(barcode)';

const SQL_CREATE_OCR_RECORD: string =
  'CREATE TABLE IF NOT EXISTS ocr_records (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
  'food_name TEXT DEFAULT "",' +
  'barcode TEXT DEFAULT "",' +
  'ocr_value REAL DEFAULT 0,' +
  'final_value REAL DEFAULT 0,' +
  'create_time INTEGER DEFAULT 0)';

// 需要分布式同步的表名列表
const DISTRIBUTED_TABLES: string[] = [FOOD_TABLE, MEMBER_TABLE, CONSUMPTION_TABLE, PRODUCT_DICT_TABLE];

export class DatabaseHelper {
  private static instance: DatabaseHelper | null = null;
  private rdbStore: relationalStore.RdbStore | null = null;
  private initialization: Promise<void> | null = null;
  readonly deviceSync: FoodDeviceSync = new FoodDeviceSync(DISTRIBUTED_TABLES);

  static getInstance(): DatabaseHelper {
    if (DatabaseHelper.instance === null) {
      DatabaseHelper.instance = new DatabaseHelper();
    }
    return DatabaseHelper.instance;
  }

  getStore(): relationalStore.RdbStore | null {
    return this.initialization === null ? this.rdbStore : null;
  }

  async initDB(context: common.Context): Promise<void> {
    if (this.initialization !== null) {
      await this.initialization;
      return;
    }
    if (this.rdbStore !== null) {
      return;
    }
    this.initialization = this.initializeStore(context);
    try {
      await this.initialization;
    } finally {
      this.initialization = null;
    }
  }

  private async initializeStore(context: common.Context): Promise<void> {
    try {
      const storeConfig: relationalStore.StoreConfig = {
        name: DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      };
      this.rdbStore = await relationalStore.getRdbStore(context, storeConfig);
      await this.rdbStore.executeSql(SQL_CREATE_FOOD);
      await this.rdbStore.executeSql(SQL_CREATE_MEMBER);
      await this.rdbStore.executeSql(SQL_CREATE_CONSUMPTION);
      await this.rdbStore.executeSql(SQL_CREATE_PRODUCT_DICT);
      await this.rdbStore.executeSql(SQL_CREATE_BUILTIN_BARCODE);
      await this.rdbStore.executeSql(SQL_CREATE_BUILTIN_INDEX);
      await this.rdbStore.executeSql(SQL_CREATE_OCR_RECORD);
      await migrateLegacyFoodDatabase(this.rdbStore, context);
      await this.ensureDefaultMember();
    } catch (error) {
      const failedStore = this.rdbStore;
      this.rdbStore = null;
      if (failedStore !== null) {
        try {
          await failedStore.close();
        } catch (closeError) {
          console.error('Could not close failed database initialization: ' + closeError);
        }
      }
      throw error instanceof Error ? error : new Error('Database init failed');
    }
  }

  private async ensureDefaultMember(): Promise<void> {
    if (this.rdbStore === null) return;
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      const predicates = new relationalStore.RdbPredicates(MEMBER_TABLE);
      resultSet = await this.rdbStore.query(predicates);
      const count: number = resultSet.rowCount;
      if (count === 0) {
        const valueBucket: relationalStore.ValuesBucket = {
          'sync_key': 'self',
          'name': '我',
          'create_time': Date.now()
        };
        await this.rdbStore.insert(MEMBER_TABLE, valueBucket);
      }
    } catch (e) {
      console.error('ensureDefaultMember 初始化默认成员失败: ' + e);
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
  }

  // ============ 食品项 CRUD ============

  async insertFoodItem(item: FoodItem): Promise<number> {
    if (this.rdbStore === null) return -1;
    const valueBucket: relationalStore.ValuesBucket = {
      'sync_key': util.generateRandomUUID(),
      'name': item.name,
      'category': item.category,
      'spec': item.spec,
      'barcode': item.barcode,
      'calories': item.calories,
      'storage_type': item.storageType,
      'expiry_date': item.expiryDate,
      'status': item.status,
      'create_time': item.createTime > 0 ? item.createTime : Date.now(),
      'consumed_by': item.consumedBy,
      'waste_reason': item.wasteReason,
      'consume_time': item.consumeTime,
      'is_opened': item.isOpened ? 1 : 0
    };
    try {
      const rowId: number = await this.rdbStore.insert(FOOD_TABLE, valueBucket);
      this.deviceSync.markChanged(FOOD_TABLE);
      return rowId;
    } catch (e) {
      console.error('insertFoodItem 插入食品数据失败: ' + e);
      return -1;
    }
  }

  async updateFoodItem(item: FoodItem): Promise<boolean> {
    if (this.rdbStore === null) return false;
    const valueBucket: relationalStore.ValuesBucket = {
      'name': item.name,
      'category': item.category,
      'spec': item.spec,
      'barcode': item.barcode,
      'calories': item.calories,
      'storage_type': item.storageType,
      'expiry_date': item.expiryDate,
      'is_opened': item.isOpened ? 1 : 0
    };
    const predicates = new relationalStore.RdbPredicates(FOOD_TABLE);
    predicates.equalTo('id', item.id);
    try {
      if (await this.rdbStore.update(valueBucket, predicates) !== 1) return false;
      this.deviceSync.markChanged(FOOD_TABLE);
      return true;
    } catch (e) {
      console.error('updateFoodItem 更新食品数据失败: ' + e);
      return false;
    }
  }

  async getActiveFoodItems(): Promise<FoodItem[]> {
    if (this.rdbStore === null) return [];
    const predicates = new relationalStore.RdbPredicates(FOOD_TABLE);
    predicates.equalTo('status', 0);
    predicates.orderByDesc('create_time');
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      const items: FoodItem[] = this.parseFoodItems(resultSet);
      return items;
    } catch (e) {
      console.error('getActiveFoodItems 查询在库食品失败: ' + e);
      return [];
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
  }

  async getAllFoodItems(): Promise<FoodItem[]> {
    if (this.rdbStore === null) return [];
    const predicates = new relationalStore.RdbPredicates(FOOD_TABLE);
    predicates.orderByDesc('create_time');
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      const items: FoodItem[] = this.parseFoodItems(resultSet);
      return items;
    } catch (e) {
      console.error('getAllFoodItems 查询全部食品失败: ' + e);
      return [];
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
  }

  async getFoodItemById(id: number): Promise<FoodItem | null> {
    if (this.rdbStore === null) return null;
    const predicates = new relationalStore.RdbPredicates(FOOD_TABLE);
    predicates.equalTo('id', id);
    let item: FoodItem | null = null;
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      if (resultSet.goToNextRow()) {
        item = this.parseSingleFoodItem(resultSet);
      }
    } catch (e) {
      console.error('getFoodItemById 查询食品详情失败: ' + e);
      return null;
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
    return item;
  }

  async consumeFood(id: number, memberName: string, calories: number, foodName: string): Promise<void> {
    await this.recordFoodDisposition(id, foodName, calories, 1, memberName, '');
  }

  async wasteFood(id: number, reason: string, calories: number, foodName: string): Promise<void> {
    await this.recordFoodDisposition(id, foodName, calories, 2, '', reason);
  }

  private async recordFoodDisposition(id: number, foodName: string, calories: number,
    status: number, memberName: string, reason: string): Promise<void> {
    const store = this.getStore();
    if (store === null) {
      throw new Error('数据库尚未就绪');
    }

    const foodKey = await this.findFoodSyncKey(store, id);
    if (foodKey.length === 0) throw new Error('食品不存在');
    const timestamp = Date.now();
    const values: relationalStore.ValuesBucket = {
      'status': status,
      'consumed_by': memberName,
      'waste_reason': reason,
      'consume_time': timestamp
    };
    const record: relationalStore.ValuesBucket = {
      'sync_key': foodKey,
      'food_sync_key': foodKey,
      'food_name': foodName,
      'member_name': memberName,
      'type': status === 1 ? 0 : 1,
      'calories': calories,
      'waste_reason': reason,
      'create_time': timestamp
    };
    const predicates = new relationalStore.RdbPredicates(FOOD_TABLE);
    predicates.equalTo('id', id).equalTo('status', 0);

    let transaction: relationalStore.Transaction | null = null;
    try {
      transaction = await store.createTransaction();
      if (await transaction.update(values, predicates) !== 1) {
        throw new Error('食品已处理或不存在');
      }
      if (await transaction.insert(CONSUMPTION_TABLE, record) <= 0) {
        throw new Error('记录写入失败');
      }
      await transaction.commit();
    } catch (error) {
      try {
        if (transaction !== null) {
          await transaction.rollback();
        }
      } catch (rollbackError) {
        console.error('食品处理事务回滚失败');
      }
      throw error instanceof Error ? error : new Error('食品处理事务失败');
    }

    this.deviceSync.markChanged(FOOD_TABLE);
    this.deviceSync.markChanged(CONSUMPTION_TABLE);
  }

  async deleteFoodItem(id: number): Promise<boolean> {
    if (this.rdbStore === null) return false;
    const predicates = new relationalStore.RdbPredicates(FOOD_TABLE);
    predicates.equalTo('id', id);
    try {
      if (await this.rdbStore.delete(predicates) !== 1) return false;
      this.deviceSync.markChanged(FOOD_TABLE);
      return true;
    } catch (e) {
      console.error('deleteFoodItem 删除食品失败: ' + e);
      return false;
    }
  }

  async getFoodStats(): Promise<FoodStats> {
    const stats = new FoodStats();
    if (this.rdbStore === null) return stats;
    const predicates = new relationalStore.RdbPredicates(FOOD_TABLE);
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      while (resultSet.goToNextRow()) {
        stats.total++;
        const status: number = resultSet.getLong(resultSet.getColumnIndex('status'));
        if (status === 0) {
          stats.active++;
          const expiryDate: number = resultSet.getLong(resultSet.getColumnIndex('expiry_date'));
          if (expiryDate > 0 && Date.now() > expiryDate) {
            stats.expired++;
          }
        } else if (status === 1) {
          stats.consumed++;
        } else if (status === 2) {
          stats.wasted++;
        }
      }
    } catch (e) {
      console.error('getFoodStats 统计食品数据失败: ' + e);
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
    return stats;
  }

  private parseFoodItems(resultSet: relationalStore.ResultSet): FoodItem[] {
    const items: FoodItem[] = [];
    try {
      while (resultSet.goToNextRow()) {
        const item: FoodItem = this.parseSingleFoodItem(resultSet);
        items.push(item);
      }
    } catch (e) {
      console.error('parseFoodItems 解析食品列表失败: ' + e);
    }
    return items;
  }

  private parseSingleFoodItem(resultSet: relationalStore.ResultSet): FoodItem {
    const item = new FoodItem();
    try {
      item.id = resultSet.getLong(resultSet.getColumnIndex('id'));
      item.name = resultSet.getString(resultSet.getColumnIndex('name'));
      item.category = resultSet.getString(resultSet.getColumnIndex('category'));
      item.spec = resultSet.getString(resultSet.getColumnIndex('spec'));
      item.barcode = resultSet.getString(resultSet.getColumnIndex('barcode'));
      item.calories = resultSet.getDouble(resultSet.getColumnIndex('calories'));
      item.storageType = resultSet.getString(resultSet.getColumnIndex('storage_type'));
      item.expiryDate = resultSet.getLong(resultSet.getColumnIndex('expiry_date'));
      item.status = resultSet.getLong(resultSet.getColumnIndex('status'));
      item.createTime = resultSet.getLong(resultSet.getColumnIndex('create_time'));
      item.consumedBy = resultSet.getString(resultSet.getColumnIndex('consumed_by'));
      item.wasteReason = resultSet.getString(resultSet.getColumnIndex('waste_reason'));
      item.consumeTime = resultSet.getLong(resultSet.getColumnIndex('consume_time'));
      item.isOpened = resultSet.getLong(resultSet.getColumnIndex('is_opened')) === 1;
    } catch (e) {
      console.error('parseSingleFoodItem 解析单条食品数据失败: ' + e);
    }
    return item;
  }

  // ============ 家庭成员 CRUD ============

  async insertMember(name: string): Promise<number> {
    if (this.rdbStore === null) return -1;
    const valueBucket: relationalStore.ValuesBucket = {
      'sync_key': util.generateRandomUUID(),
      'name': name,
      'create_time': Date.now()
    };
    try {
      const rowId: number = await this.rdbStore.insert(MEMBER_TABLE, valueBucket);
      this.deviceSync.markChanged(MEMBER_TABLE);
      return rowId;
    } catch (e) {
      console.error('insertMember 插入家庭成员失败: ' + e);
      return -1;
    }
  }

  async getAllMembers(): Promise<FamilyMember[]> {
    if (this.rdbStore === null) return [];
    const predicates = new relationalStore.RdbPredicates(MEMBER_TABLE);
    predicates.orderByAsc('create_time');
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      const members: FamilyMember[] = [];
      while (resultSet.goToNextRow()) {
        const member = new FamilyMember();
        member.id = resultSet.getLong(resultSet.getColumnIndex('id'));
        member.name = resultSet.getString(resultSet.getColumnIndex('name'));
        member.createTime = resultSet.getLong(resultSet.getColumnIndex('create_time'));
        members.push(member);
      }
      return members;
    } catch (e) {
      console.error('getAllMembers 查询家庭成员失败: ' + e);
      return [];
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
  }

  async getMemberCount(): Promise<number> {
    if (this.rdbStore === null) return 0;
    const predicates = new relationalStore.RdbPredicates(MEMBER_TABLE);
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      const count: number = resultSet.rowCount;
      return count;
    } catch (e) {
      console.error('getMemberCount 查询成员数量失败: ' + e);
      return 0;
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
  }

  async deleteMember(id: number): Promise<boolean> {
    if (this.rdbStore === null) return false;
    // 至少保留一个成员
    const count: number = await this.getMemberCount();
    if (count <= 1) return false;
    const predicates = new relationalStore.RdbPredicates(MEMBER_TABLE);
    predicates.equalTo('id', id);
    try {
      await this.rdbStore.delete(predicates);
      this.deviceSync.markChanged(MEMBER_TABLE);
      return true;
    } catch (e) {
      console.error('deleteMember 删除家庭成员失败: ' + e);
      return false;
    }
  }

  // ============ 消耗记录查询 ============

  async getTodayConsumptions(): Promise<ConsumptionRecord[]> {
    if (this.rdbStore === null) return [];
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const startTime: number = today.getTime();
    const endTime: number = startTime + 24 * 60 * 60 * 1000;
    return await this.getConsumptionsByRange(startTime, endTime);
  }

  async getConsumptionsByRange(startTime: number, endTime: number): Promise<ConsumptionRecord[]> {
    if (this.rdbStore === null) return [];
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.querySql(
        'SELECT c.*, coalesce(f.id, 0) AS linked_food_id FROM consumption_records c ' +
        'LEFT JOIN food_items f ON f.sync_key = c.food_sync_key ' +
        'WHERE c.create_time >= ? AND c.create_time < ? ORDER BY c.create_time DESC', [startTime, endTime]);
      const records: ConsumptionRecord[] = this.parseConsumptionRecords(resultSet);
      return records;
    } catch (e) {
      console.error('getConsumptionsByRange 查询消耗记录失败: ' + e);
      return [];
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
  }

  async getCaloriesByMemberForRange(startTime: number, endTime: number): Promise<DailyCalorie[]> {
    const records: ConsumptionRecord[] = await this.getConsumptionsByRange(startTime, endTime);
    const calorieMap: Map<string, DailyCalorie> = new Map();
    for (let i = 0; i < records.length; i++) {
      const record: ConsumptionRecord = records[i];
      if (record.type !== 0) continue;
      const memberName: string = record.memberName;
      if (calorieMap.has(memberName)) {
        const existing: DailyCalorie | undefined = calorieMap.get(memberName);
        if (existing !== undefined) {
          existing.totalCalories = existing.totalCalories + record.calories;
          existing.recordCount = existing.recordCount + 1;
        }
      } else {
        const daily = new DailyCalorie();
        daily.memberName = memberName;
        daily.totalCalories = record.calories;
        daily.recordCount = 1;
        calorieMap.set(memberName, daily);
      }
    }
    const result: DailyCalorie[] = [];
    calorieMap.forEach((value: DailyCalorie) => {
      result.push(value);
    });
    return result;
  }

  async getTodayCaloriesByMember(): Promise<DailyCalorie[]> {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const startTime: number = today.getTime();
    const endTime: number = startTime + 24 * 60 * 60 * 1000;
    return await this.getCaloriesByMemberForRange(startTime, endTime);
  }

  async getWasteStatsByCategory(startTime?: number, endTime?: number): Promise<WasteStat[]> {
    if (this.rdbStore === null) return [];
    const predicates = new relationalStore.RdbPredicates(FOOD_TABLE);
    predicates.equalTo('status', 2);
    if (startTime !== undefined && endTime !== undefined) {
      predicates.greaterThanOrEqualTo('consume_time', startTime);
      predicates.lessThan('consume_time', endTime);
    }
    const statsMap: Map<string, WasteStat> = new Map();
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      while (resultSet.goToNextRow()) {
        const category: string = resultSet.getString(resultSet.getColumnIndex('category'));
        const foodName: string = resultSet.getString(resultSet.getColumnIndex('name'));
        const calories: number = resultSet.getDouble(resultSet.getColumnIndex('calories'));
        const catName: string = category.length > 0 ? category : foodName;
        if (statsMap.has(catName)) {
          const existing: WasteStat | undefined = statsMap.get(catName);
          if (existing !== undefined) {
            existing.count = existing.count + 1;
            existing.totalCalories = existing.totalCalories + calories;
          }
        } else {
          const stat = new WasteStat();
          stat.category = catName;
          stat.count = 1;
          stat.totalCalories = calories;
          statsMap.set(catName, stat);
        }
      }
    } catch (e) {
      console.error('getWasteStatsByCategory 统计浪费数据失败: ' + e);
      return [];
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
    const result: WasteStat[] = [];
    statsMap.forEach((value: WasteStat) => {
      result.push(value);
    });
    return result;
  }

  private async findFoodSyncKey(store: relationalStore.RdbStore, id: number): Promise<string> {
    if (id <= 0) return '';
    const rows = await store.query(new relationalStore.RdbPredicates(FOOD_TABLE).equalTo('id', id), ['sync_key']);
    try {
      return rows.goToFirstRow() ? rows.getString(0) : '';
    } finally {
      rows.close();
    }
  }

  async insertConsumptionRecord(record: ConsumptionRecord): Promise<number> {
    const store = this.rdbStore;
    if (store === null) return -1;
    try {
      const foodKey = await this.findFoodSyncKey(store, record.foodItemId);
      const valueBucket: relationalStore.ValuesBucket = {
        'sync_key': util.generateRandomUUID(),
        'food_sync_key': foodKey,
        'food_name': record.foodName,
        'member_name': record.memberName,
        'type': record.type,
        'calories': record.calories,
        'waste_reason': record.wasteReason,
        'create_time': record.createTime > 0 ? record.createTime : Date.now()
      };
      const rowId: number = await store.insert(CONSUMPTION_TABLE, valueBucket);
      this.deviceSync.markChanged(CONSUMPTION_TABLE);
      return rowId;
    } catch (error) {
      console.error('insertConsumptionRecord 插入消耗记录失败: ' + error);
      return -1;
    }
  }

  private parseConsumptionRecords(resultSet: relationalStore.ResultSet): ConsumptionRecord[] {
    const records: ConsumptionRecord[] = [];
    try {
      while (resultSet.goToNextRow()) {
        const record = new ConsumptionRecord();
        record.id = resultSet.getLong(resultSet.getColumnIndex('id'));
        record.foodItemId = resultSet.getLong(resultSet.getColumnIndex('linked_food_id'));
        record.foodName = resultSet.getString(resultSet.getColumnIndex('food_name'));
        record.memberName = resultSet.getString(resultSet.getColumnIndex('member_name'));
        record.type = resultSet.getLong(resultSet.getColumnIndex('type'));
        record.calories = resultSet.getDouble(resultSet.getColumnIndex('calories'));
        record.wasteReason = resultSet.getString(resultSet.getColumnIndex('waste_reason'));
        record.createTime = resultSet.getLong(resultSet.getColumnIndex('create_time'));
        records.push(record);
      }
    } catch (e) {
      console.error('parseConsumptionRecords 解析消耗记录失败: ' + e);
    }
    return records;
  }

  // ============ 产品字典 CRUD ============

  async insertOrUpdateProductDict(dict: ProductDict): Promise<number> {
    if (this.rdbStore === null) return -1;
    const valueBucket: relationalStore.ValuesBucket = {
      'dict_key': dict.dictKey,
      'barcode': dict.barcode,
      'name': dict.name,
      'category': dict.category,
      'spec': dict.spec,
      'calories': dict.calories,
      'raw_energy': dict.rawEnergy,
      'energy_unit': dict.energyUnit,
      'basis_type': dict.basisType,
      'serving_size': dict.servingSize,
      'serving_unit': dict.servingUnit,
      'is_reliable': dict.isReliable ? 1 : 0,
      'source': dict.source,
      'update_time': Date.now()
    };
    // 先尝试查询是否存在
    const existing: ProductDict | null = await this.queryProductDictByKey(dict.dictKey);
    try {
      if (existing !== null) {
        const predicates = new relationalStore.RdbPredicates(PRODUCT_DICT_TABLE);
        predicates.equalTo('dict_key', dict.dictKey);
        await this.rdbStore.update(valueBucket, predicates);
        this.deviceSync.markChanged(PRODUCT_DICT_TABLE);
        return existing.id;
      }
      const rowId: number = await this.rdbStore.insert(PRODUCT_DICT_TABLE, valueBucket);
      this.deviceSync.markChanged(PRODUCT_DICT_TABLE);
      return rowId;
    } catch (e) {
      console.error('insertOrUpdateProductDict 保存产品字典失败: ' + e);
      return -1;
    }
  }

  async queryProductDictByBarcode(barcode: string): Promise<ProductDict | null> {
    if (this.rdbStore === null || barcode.length === 0) return null;
    const predicates = new relationalStore.RdbPredicates(PRODUCT_DICT_TABLE);
    predicates.equalTo('barcode', barcode);
    let dict: ProductDict | null = null;
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      if (resultSet.goToNextRow()) {
        dict = this.parseSingleProductDict(resultSet);
      }
    } catch (e) {
      console.error('queryProductDictByBarcode 按条码查询产品字典失败: ' + e);
      return null;
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
    return dict;
  }

  async queryProductDictByKey(key: string): Promise<ProductDict | null> {
    if (this.rdbStore === null || key.length === 0) return null;
    const predicates = new relationalStore.RdbPredicates(PRODUCT_DICT_TABLE);
    predicates.equalTo('dict_key', key);
    let dict: ProductDict | null = null;
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      if (resultSet.goToNextRow()) {
        dict = this.parseSingleProductDict(resultSet);
      }
    } catch (e) {
      console.error('queryProductDictByKey 按键查询产品字典失败: ' + e);
      return null;
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
    return dict;
  }

  async searchProductDict(keyword: string): Promise<ProductDict[]> {
    if (this.rdbStore === null) return [];
    const predicates = new relationalStore.RdbPredicates(PRODUCT_DICT_TABLE);
    if (keyword.length > 0) {
      let isBarcode: boolean = true;
      for (let i = 0; i < keyword.length; i++) {
        const ch: string = keyword.charAt(i);
        if (ch < '0' || ch > '9') {
          isBarcode = false;
          break;
        }
      }
      if (isBarcode) {
        predicates.like('barcode', '%' + keyword + '%');
      } else {
        predicates.like('name', '%' + keyword + '%');
      }
    }
    predicates.orderByDesc('update_time');
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      const dicts: ProductDict[] = [];
      while (resultSet.goToNextRow()) {
        dicts.push(this.parseSingleProductDict(resultSet));
      }
      return dicts;
    } catch (e) {
      console.error('searchProductDict 搜索产品字典失败: ' + e);
      return [];
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
  }

  async getAllProductDict(): Promise<ProductDict[]> {
    return await this.searchProductDict('');
  }

  async deleteProductDict(id: number): Promise<void> {
    if (this.rdbStore === null) return;
    const predicates = new relationalStore.RdbPredicates(PRODUCT_DICT_TABLE);
    predicates.equalTo('id', id);
    try {
      await this.rdbStore.delete(predicates);
      this.deviceSync.markChanged(PRODUCT_DICT_TABLE);
    } catch (e) {
      console.error('deleteProductDict 删除产品字典失败: ' + e);
    }
  }

  async updateProductDict(id: number, dict: ProductDict): Promise<number> {
    const store = this.rdbStore;
    if (store === null) return -1;
    const valueBucket: relationalStore.ValuesBucket = {
      'dict_key': dict.dictKey,
      'barcode': dict.barcode,
      'name': dict.name,
      'category': dict.category,
      'spec': dict.spec,
      'calories': dict.calories,
      'raw_energy': dict.rawEnergy,
      'energy_unit': dict.energyUnit,
      'basis_type': dict.basisType,
      'serving_size': dict.servingSize,
      'serving_unit': dict.servingUnit,
      'is_reliable': dict.isReliable ? 1 : 0,
      'source': dict.source,
      'update_time': Date.now()
    };
    let transaction: relationalStore.Transaction | null = null;
    try {
      transaction = await store.createTransaction();
      const current = new relationalStore.RdbPredicates(PRODUCT_DICT_TABLE).equalTo('id', id);
      const target = new relationalStore.RdbPredicates(PRODUCT_DICT_TABLE).equalTo('dict_key', dict.dictKey);
      const match = await transaction.query(target, ['id']);
      let targetId = 0;
      try {
        if (match.goToFirstRow()) targetId = match.getLong(0);
      } finally {
        match.close();
      }
      if (targetId === id) {
        if (await transaction.update(valueBucket, current) !== 1) throw new Error('Dictionary entry changed');
      } else {
        // A changed sync key must delete the old row so peers also remove its old key.
        if (await transaction.delete(current) !== 1) throw new Error('Dictionary entry changed');
        if (targetId > 0) {
          if (await transaction.update(valueBucket, target) !== 1) throw new Error('Dictionary entry changed');
        } else {
          valueBucket['id'] = id;
          if (await transaction.insert(PRODUCT_DICT_TABLE, valueBucket) <= 0) {
            throw new Error('Could not save renamed dictionary entry');
          }
          targetId = id;
        }
      }
      await transaction.commit();
      this.deviceSync.markChanged(PRODUCT_DICT_TABLE);
      return targetId;
    } catch (e) {
      if (transaction !== null) {
        try {
          await transaction.rollback();
        } catch (rollbackError) {
          console.error('Could not roll back dictionary update: ' + rollbackError);
        }
      }
      console.error('updateProductDict 更新产品字典失败: ' + e);
      return -1;
    }
  }

  async getProductDictCount(): Promise<number> {
    if (this.rdbStore === null) return 0;
    const predicates = new relationalStore.RdbPredicates(PRODUCT_DICT_TABLE);
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      const count: number = resultSet.rowCount;
      return count;
    } catch (e) {
      console.error('getProductDictCount 查询产品字典数量失败: ' + e);
      return 0;
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
  }

  private parseSingleProductDict(resultSet: relationalStore.ResultSet): ProductDict {
    const dict = new ProductDict();
    try {
      dict.id = resultSet.getLong(resultSet.getColumnIndex('id'));
      dict.dictKey = resultSet.getString(resultSet.getColumnIndex('dict_key'));
      dict.barcode = resultSet.getString(resultSet.getColumnIndex('barcode'));
      dict.name = resultSet.getString(resultSet.getColumnIndex('name'));
      dict.category = resultSet.getString(resultSet.getColumnIndex('category'));
      dict.spec = resultSet.getString(resultSet.getColumnIndex('spec'));
      dict.calories = resultSet.getDouble(resultSet.getColumnIndex('calories'));
      dict.rawEnergy = resultSet.getDouble(resultSet.getColumnIndex('raw_energy'));
      dict.energyUnit = resultSet.getString(resultSet.getColumnIndex('energy_unit'));
      dict.basisType = resultSet.getString(resultSet.getColumnIndex('basis_type'));
      dict.servingSize = resultSet.getDouble(resultSet.getColumnIndex('serving_size'));
      dict.servingUnit = resultSet.getString(resultSet.getColumnIndex('serving_unit'));
      dict.isReliable = resultSet.getLong(resultSet.getColumnIndex('is_reliable')) === 1;
      dict.source = resultSet.getString(resultSet.getColumnIndex('source'));
      dict.updateTime = resultSet.getLong(resultSet.getColumnIndex('update_time'));
    } catch (e) {
      console.error('parseSingleProductDict 解析单条产品字典失败: ' + e);
    }
    return dict;
  }

  // ============ 内置条码库 ============

  async getBuiltinBarcodeCount(): Promise<number> {
    if (this.rdbStore === null) return 0;
    const predicates = new relationalStore.RdbPredicates(BUILTIN_BARCODE_TABLE);
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      const count: number = resultSet.rowCount;
      return count;
    } catch (e) {
      console.error('getBuiltinBarcodeCount 查询内置条码数量失败: ' + e);
      return 0;
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
  }

  async queryBuiltinBarcode(barcode: string): Promise<BuiltinBarcode | null> {
    if (this.rdbStore === null || barcode.length === 0) return null;
    const predicates = new relationalStore.RdbPredicates(BUILTIN_BARCODE_TABLE);
    predicates.equalTo('barcode', barcode);
    let builtin: BuiltinBarcode | null = null;
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      if (resultSet.goToNextRow()) {
        builtin = new BuiltinBarcode();
        builtin.id = resultSet.getLong(resultSet.getColumnIndex('id'));
        builtin.barcode = resultSet.getString(resultSet.getColumnIndex('barcode'));
        builtin.name = resultSet.getString(resultSet.getColumnIndex('name'));
        builtin.category = resultSet.getString(resultSet.getColumnIndex('category'));
        builtin.spec = resultSet.getString(resultSet.getColumnIndex('spec'));
      }
    } catch (e) {
      console.error('queryBuiltinBarcode 查询内置条码失败: ' + e);
      return null;
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
    return builtin;
  }

  async batchInsertBuiltinBarcodes(barcodes: string[], names: string[], categories: string[], specs: string[]): Promise<void> {
    if (this.rdbStore === null) return;
    const BATCH_SIZE: number = 500;
    const total: number = barcodes.length;
    const escapeSqlValue = (raw: string): string => {
      // 转义反斜杠和单引号，防止 SQL 注入和字符串截断
      let escaped: string = '';
      for (let i = 0; i < raw.length; i++) {
        const ch: string = raw.charAt(i);
        if (ch === '\\') {
          escaped = escaped + '\\\\';
        } else if (ch === '\'') {
          escaped = escaped + "''";
        } else {
          escaped = escaped + ch;
        }
      }
      return escaped;
    };
    try {
      for (let start = 0; start < total; start += BATCH_SIZE) {
        const end: number = Math.min(start + BATCH_SIZE, total);
        let sql: string = 'INSERT INTO builtin_barcodes (barcode, name, category, spec) VALUES ';
        const parts: string[] = [];
        for (let i = start; i < end; i++) {
          const escapedName: string = escapeSqlValue(names[i]);
          const escapedCategory: string = escapeSqlValue(categories[i]);
          const escapedSpec: string = escapeSqlValue(specs[i]);
          parts.push("('" + escapeSqlValue(barcodes[i]) + "','" + escapedName + "','" + escapedCategory + "','" + escapedSpec + "')");
        }
        sql = sql + parts.join(',');
        await this.rdbStore.executeSql(sql);
      }
    } catch (e) {
      console.error('batchInsertBuiltinBarcodes 批量插入内置条码失败: ' + e);
    }
  }

  async clearBuiltinBarcodes(): Promise<void> {
    if (this.rdbStore === null) return;
    const predicates = new relationalStore.RdbPredicates(BUILTIN_BARCODE_TABLE);
    try {
      await this.rdbStore.delete(predicates);
    } catch (e) {
      console.error('clearBuiltinBarcodes 清空内置条码失败: ' + e);
    }
  }

  async getBuiltinBarcodeMissingCategoryCount(): Promise<number> {
    if (this.rdbStore === null) return 0;
    const predicates = new relationalStore.RdbPredicates(BUILTIN_BARCODE_TABLE);
    predicates.equalTo('category', '');
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      const count: number = resultSet.rowCount;
      return count;
    } catch (e) {
      console.error('getBuiltinBarcodeMissingCategoryCount 查询缺失分类条码数量失败: ' + e);
      return 0;
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
  }

  // ============ OCR记录 CRUD ============

  async insertOcrRecord(record: OcrRecord): Promise<number> {
    if (this.rdbStore === null) return -1;
    const valueBucket: relationalStore.ValuesBucket = {
      'food_name': record.foodName,
      'barcode': record.barcode,
      'ocr_value': record.ocrValue,
      'final_value': record.finalValue,
      'create_time': record.createTime > 0 ? record.createTime : Date.now()
    };
    try {
      return await this.rdbStore.insert(OCR_RECORD_TABLE, valueBucket);
    } catch (e) {
      console.error('insertOcrRecord 插入OCR记录失败: ' + e);
      return -1;
    }
  }

  async getOcrRecords(days: number): Promise<OcrRecord[]> {
    if (this.rdbStore === null) return [];
    const cutoff: number = Date.now() - days * 24 * 60 * 60 * 1000;
    const predicates = new relationalStore.RdbPredicates(OCR_RECORD_TABLE);
    predicates.greaterThanOrEqualTo('create_time', cutoff);
    predicates.orderByDesc('create_time');
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      const records: OcrRecord[] = [];
      while (resultSet.goToNextRow()) {
        const rec = new OcrRecord();
        rec.id = resultSet.getLong(resultSet.getColumnIndex('id'));
        rec.foodName = resultSet.getString(resultSet.getColumnIndex('food_name'));
        rec.barcode = resultSet.getString(resultSet.getColumnIndex('barcode'));
        rec.ocrValue = resultSet.getDouble(resultSet.getColumnIndex('ocr_value'));
        rec.finalValue = resultSet.getDouble(resultSet.getColumnIndex('final_value'));
        rec.createTime = resultSet.getLong(resultSet.getColumnIndex('create_time'));
        records.push(rec);
      }
      return records;
    } catch (e) {
      console.error('getOcrRecords 查询OCR记录失败: ' + e);
      return [];
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
  }

  async searchOcrRecords(days: number, keyword: string): Promise<OcrRecord[]> {
    if (this.rdbStore === null) return [];
    const cutoff: number = Date.now() - days * 24 * 60 * 60 * 1000;
    const predicates = new relationalStore.RdbPredicates(OCR_RECORD_TABLE);
    predicates.greaterThanOrEqualTo('create_time', cutoff);
    if (keyword.length > 0) {
      predicates.like('food_name', '%' + keyword + '%');
    }
    predicates.orderByDesc('create_time');
    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      const records: OcrRecord[] = [];
      while (resultSet.goToNextRow()) {
        const rec = new OcrRecord();
        rec.id = resultSet.getLong(resultSet.getColumnIndex('id'));
        rec.foodName = resultSet.getString(resultSet.getColumnIndex('food_name'));
        rec.barcode = resultSet.getString(resultSet.getColumnIndex('barcode'));
        rec.ocrValue = resultSet.getDouble(resultSet.getColumnIndex('ocr_value'));
        rec.finalValue = resultSet.getDouble(resultSet.getColumnIndex('final_value'));
        rec.createTime = resultSet.getLong(resultSet.getColumnIndex('create_time'));
        records.push(rec);
      }
      return records;
    } catch (e) {
      console.error('searchOcrRecords 搜索OCR记录失败: ' + e);
      return [];
    } finally {
      if (resultSet !== null) {
        try {
          resultSet.close();
        } catch (e) {
          // 关闭结果集失败，忽略
        }
      }
    }
  }

  async updateOcrRecord(id: number, finalValue: number): Promise<boolean> {
    if (this.rdbStore === null) return false;
    const valueBucket: relationalStore.ValuesBucket = {
      'final_value': finalValue
    };
    const predicates = new relationalStore.RdbPredicates(OCR_RECORD_TABLE);
    predicates.equalTo('id', id);
    try {
      if (await this.rdbStore.update(valueBucket, predicates) !== 1) return false;
      return true;
    } catch (e) {
      console.error('updateOcrRecord 更新OCR记录失败: ' + e);
      return false;
    }
  }
}
