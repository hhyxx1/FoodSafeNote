import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { FoodItem, FamilyMember, ConsumptionRecord, DailyCalorie, FoodStats,
  ProductDict, OcrRecord, WasteStat } from '../model/DataModels';

const DB_NAME: string = 'FoodSafeNote.db';
const FOOD_TABLE: string = 'food_items';
const MEMBER_TABLE: string = 'family_members';
const CONSUMPTION_TABLE: string = 'consumption_records';
const PRODUCT_DICT_TABLE: string = 'product_dict';
const BUILTIN_BARCODE_TABLE: string = 'builtin_barcodes';
const OCR_RECORD_TABLE: string = 'ocr_records';

const SQL_CREATE_FOOD: string =
  'CREATE TABLE IF NOT EXISTS food_items (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
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
  'name TEXT NOT NULL,' +
  'create_time INTEGER DEFAULT 0)';

const SQL_CREATE_CONSUMPTION: string =
  'CREATE TABLE IF NOT EXISTS consumption_records (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
  'food_item_id INTEGER DEFAULT 0,' +
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
  'source TEXT DEFAULT "manual",' +
  'update_time INTEGER DEFAULT 0)';

const SQL_CREATE_BUILTIN_BARCODE: string =
  'CREATE TABLE IF NOT EXISTS builtin_barcodes (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
  'barcode TEXT NOT NULL,' +
  'name TEXT NOT NULL)';

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
  private initializing: boolean = false;
  private onRemoteChangeCallback: (() => void) | null = null;

  static getInstance(): DatabaseHelper {
    if (DatabaseHelper.instance === null) {
      DatabaseHelper.instance = new DatabaseHelper();
    }
    return DatabaseHelper.instance;
  }

  getStore(): relationalStore.RdbStore | null {
    return this.rdbStore;
  }

  async initDB(context: common.Context): Promise<void> {
    if (this.rdbStore !== null || this.initializing) {
      return;
    }
    this.initializing = true;
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
    // 数据库迁移：为已有表添加新列（ALTER TABLE不会报错如果列已存在会忽略）
    await this.migrateDatabase();
    // 首次初始化时添加默认成员"我"
    await this.ensureDefaultMember();
    // 配置分布式表（同账号设备间自动同步，失败不影响本地功能）
    try {
      await this.setupDistributedTables();
    } catch (e) {
      // 分布式设置失败（虚拟机/单设备环境），不影响本地数据库使用
    }
  }

  // 设置分布式表，启用同账号设备间数据同步
  private async setupDistributedTables(): Promise<void> {
    if (this.rdbStore === null) return;
    try {
      // 将关键业务表设为分布式表
      await this.rdbStore.setDistributedTables(DISTRIBUTED_TABLES);
      // 监听远端设备数据变更
      this.rdbStore.on('dataChange', relationalStore.SubscribeType.SUBSCRIBE_TYPE_REMOTE, () => {
        // 远端数据变更，通知UI刷新
        if (this.onRemoteChangeCallback !== null) {
          this.onRemoteChangeCallback();
        }
      });
    } catch (e) {
      // 分布式表设置失败不影响本地功能（虚拟机/单设备环境）
    }
  }

  // 注册远端数据变更回调（Index页面调用）
  setOnRemoteChangeCallback(callback: () => void): void {
    this.onRemoteChangeCallback = callback;
  }

  // 推送同步指定表到其他设备
  private syncTable(tableName: string): void {
    if (this.rdbStore === null) return;
    try {
      const predicates = new relationalStore.RdbPredicates(tableName);
      this.rdbStore.sync(relationalStore.SyncMode.SYNC_MODE_PUSH, predicates);
    } catch (e) {
      // 同步失败不影响本地操作
    }
  }

  // 同步所有分布式表
  private syncAllTables(): void {
    for (let i = 0; i < DISTRIBUTED_TABLES.length; i++) {
      this.syncTable(DISTRIBUTED_TABLES[i]);
    }
  }

  // 数据库迁移：为旧版数据库添加新字段
  private async migrateDatabase(): Promise<void> {
    if (this.rdbStore === null) return;
    // 逐个尝试添加新列，已存在的列会抛异常，捕获后跳过
    const migrations: string[] = [
      'ALTER TABLE food_items ADD COLUMN is_opened INTEGER DEFAULT 0'
    ];
    for (let i = 0; i < migrations.length; i++) {
      try {
        await this.rdbStore.executeSql(migrations[i]);
      } catch (e) {
        // 列已存在，忽略错误
      }
    }
  }

  private async ensureDefaultMember(): Promise<void> {
    if (this.rdbStore === null) return;
    const predicates = new relationalStore.RdbPredicates(MEMBER_TABLE);
    const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
    const count: number = resultSet.rowCount;
    resultSet.close();
    if (count === 0) {
      const valueBucket: relationalStore.ValuesBucket = {
        'name': '我',
        'create_time': Date.now()
      };
      await this.rdbStore.insert(MEMBER_TABLE, valueBucket);
    }
  }

  // ============ 食品项 CRUD ============

  async insertFoodItem(item: FoodItem): Promise<number> {
    if (this.rdbStore === null) return -1;
    const valueBucket: relationalStore.ValuesBucket = {
      'name': item.name,
      'category': item.category,
      'spec': item.spec,
      'barcode': item.barcode,
      'calories': item.calories,
      'storage_type': item.storageType,
      'expiry_date': item.expiryDate,
      'status': item.status,
      'create_time': Date.now(),
      'consumed_by': '',
      'waste_reason': '',
      'consume_time': 0,
      'is_opened': item.isOpened ? 1 : 0
    };
    const rowId: number = await this.rdbStore.insert(FOOD_TABLE, valueBucket);
    this.syncTable(FOOD_TABLE);
    return rowId;
  }

  async updateFoodItem(item: FoodItem): Promise<void> {
    if (this.rdbStore === null) return;
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
    await this.rdbStore.update(valueBucket, predicates);
    this.syncTable(FOOD_TABLE);
  }

  async getActiveFoodItems(): Promise<FoodItem[]> {
    if (this.rdbStore === null) return [];
    const predicates = new relationalStore.RdbPredicates(FOOD_TABLE);
    predicates.equalTo('status', 0);
    predicates.orderByDesc('create_time');
    const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
    const items: FoodItem[] = this.parseFoodItems(resultSet);
    resultSet.close();
    return items;
  }

  async getAllFoodItems(): Promise<FoodItem[]> {
    if (this.rdbStore === null) return [];
    const predicates = new relationalStore.RdbPredicates(FOOD_TABLE);
    predicates.orderByDesc('create_time');
    const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
    const items: FoodItem[] = this.parseFoodItems(resultSet);
    resultSet.close();
    return items;
  }

  async getFoodItemById(id: number): Promise<FoodItem | null> {
    if (this.rdbStore === null) return null;
    const predicates = new relationalStore.RdbPredicates(FOOD_TABLE);
    predicates.equalTo('id', id);
    const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
    let item: FoodItem | null = null;
    if (resultSet.goToNextRow()) {
      item = this.parseSingleFoodItem(resultSet);
    }
    resultSet.close();
    return item;
  }

  async consumeFood(id: number, memberName: string, calories: number, foodName: string): Promise<void> {
    if (this.rdbStore === null) return;
    const valueBucket: relationalStore.ValuesBucket = {
      'status': 1,
      'consumed_by': memberName,
      'consume_time': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(FOOD_TABLE);
    predicates.equalTo('id', id);
    await this.rdbStore.update(valueBucket, predicates);
    const record: relationalStore.ValuesBucket = {
      'food_item_id': id,
      'food_name': foodName,
      'member_name': memberName,
      'type': 0,
      'calories': calories,
      'waste_reason': '',
      'create_time': Date.now()
    };
    await this.rdbStore.insert(CONSUMPTION_TABLE, record);
    this.syncTable(FOOD_TABLE);
    this.syncTable(CONSUMPTION_TABLE);
  }

  async wasteFood(id: number, reason: string, calories: number, foodName: string): Promise<void> {
    if (this.rdbStore === null) return;
    const valueBucket: relationalStore.ValuesBucket = {
      'status': 2,
      'waste_reason': reason,
      'consume_time': Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(FOOD_TABLE);
    predicates.equalTo('id', id);
    await this.rdbStore.update(valueBucket, predicates);
    const record: relationalStore.ValuesBucket = {
      'food_item_id': id,
      'food_name': foodName,
      'member_name': '',
      'type': 1,
      'calories': calories,
      'waste_reason': reason,
      'create_time': Date.now()
    };
    await this.rdbStore.insert(CONSUMPTION_TABLE, record);
    this.syncTable(FOOD_TABLE);
    this.syncTable(CONSUMPTION_TABLE);
  }

  async deleteFoodItem(id: number): Promise<void> {
    if (this.rdbStore === null) return;
    const predicates = new relationalStore.RdbPredicates(FOOD_TABLE);
    predicates.equalTo('id', id);
    await this.rdbStore.delete(predicates);
    this.syncTable(FOOD_TABLE);
  }

  async getFoodStats(): Promise<FoodStats> {
    const stats = new FoodStats();
    if (this.rdbStore === null) return stats;
    const predicates = new relationalStore.RdbPredicates(FOOD_TABLE);
    const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
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
    resultSet.close();
    return stats;
  }

  private parseFoodItems(resultSet: relationalStore.ResultSet): FoodItem[] {
    const items: FoodItem[] = [];
    while (resultSet.goToNextRow()) {
      const item: FoodItem = this.parseSingleFoodItem(resultSet);
      items.push(item);
    }
    return items;
  }

  private parseSingleFoodItem(resultSet: relationalStore.ResultSet): FoodItem {
    const item = new FoodItem();
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
    return item;
  }

  // ============ 家庭成员 CRUD ============

  async insertMember(name: string): Promise<number> {
    if (this.rdbStore === null) return -1;
    const valueBucket: relationalStore.ValuesBucket = {
      'name': name,
      'create_time': Date.now()
    };
    const rowId: number = await this.rdbStore.insert(MEMBER_TABLE, valueBucket);
    this.syncTable(MEMBER_TABLE);
    return rowId;
  }

  async getAllMembers(): Promise<FamilyMember[]> {
    if (this.rdbStore === null) return [];
    const predicates = new relationalStore.RdbPredicates(MEMBER_TABLE);
    predicates.orderByAsc('create_time');
    const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
    const members: FamilyMember[] = [];
    while (resultSet.goToNextRow()) {
      const member = new FamilyMember();
      member.id = resultSet.getLong(resultSet.getColumnIndex('id'));
      member.name = resultSet.getString(resultSet.getColumnIndex('name'));
      member.createTime = resultSet.getLong(resultSet.getColumnIndex('create_time'));
      members.push(member);
    }
    resultSet.close();
    return members;
  }

  async getMemberCount(): Promise<number> {
    if (this.rdbStore === null) return 0;
    const predicates = new relationalStore.RdbPredicates(MEMBER_TABLE);
    const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
    const count: number = resultSet.rowCount;
    resultSet.close();
    return count;
  }

  async deleteMember(id: number): Promise<boolean> {
    if (this.rdbStore === null) return false;
    // 至少保留一个成员
    const count: number = await this.getMemberCount();
    if (count <= 1) return false;
    const predicates = new relationalStore.RdbPredicates(MEMBER_TABLE);
    predicates.equalTo('id', id);
    await this.rdbStore.delete(predicates);
    this.syncTable(MEMBER_TABLE);
    return true;
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
    const predicates = new relationalStore.RdbPredicates(CONSUMPTION_TABLE);
    predicates.greaterThanOrEqualTo('create_time', startTime);
    predicates.lessThan('create_time', endTime);
    predicates.orderByDesc('create_time');
    const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
    const records: ConsumptionRecord[] = this.parseConsumptionRecords(resultSet);
    resultSet.close();
    return records;
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

  async getWasteStatsByCategory(): Promise<WasteStat[]> {
    if (this.rdbStore === null) return [];
    const predicates = new relationalStore.RdbPredicates(FOOD_TABLE);
    predicates.equalTo('status', 2);
    const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
    const statsMap: Map<string, WasteStat> = new Map();
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
    resultSet.close();
    const result: WasteStat[] = [];
    statsMap.forEach((value: WasteStat) => {
      result.push(value);
    });
    return result;
  }

  async insertConsumptionRecord(record: ConsumptionRecord): Promise<number> {
    if (this.rdbStore === null) return -1;
    const valueBucket: relationalStore.ValuesBucket = {
      'food_item_id': record.foodItemId,
      'food_name': record.foodName,
      'member_name': record.memberName,
      'type': record.type,
      'calories': record.calories,
      'waste_reason': record.wasteReason,
      'create_time': record.createTime > 0 ? record.createTime : Date.now()
    };
    const rowId: number = await this.rdbStore.insert(CONSUMPTION_TABLE, valueBucket);
    return rowId;
  }

  private parseConsumptionRecords(resultSet: relationalStore.ResultSet): ConsumptionRecord[] {
    const records: ConsumptionRecord[] = [];
    while (resultSet.goToNextRow()) {
      const record = new ConsumptionRecord();
      record.id = resultSet.getLong(resultSet.getColumnIndex('id'));
      record.foodItemId = resultSet.getLong(resultSet.getColumnIndex('food_item_id'));
      record.foodName = resultSet.getString(resultSet.getColumnIndex('food_name'));
      record.memberName = resultSet.getString(resultSet.getColumnIndex('member_name'));
      record.type = resultSet.getLong(resultSet.getColumnIndex('type'));
      record.calories = resultSet.getDouble(resultSet.getColumnIndex('calories'));
      record.wasteReason = resultSet.getString(resultSet.getColumnIndex('waste_reason'));
      record.createTime = resultSet.getLong(resultSet.getColumnIndex('create_time'));
      records.push(record);
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
      'source': dict.source,
      'update_time': Date.now()
    };
    // 先尝试查询是否存在
    const existing: ProductDict | null = await this.queryProductDictByKey(dict.dictKey);
    if (existing !== null) {
      const predicates = new relationalStore.RdbPredicates(PRODUCT_DICT_TABLE);
      predicates.equalTo('dict_key', dict.dictKey);
      await this.rdbStore.update(valueBucket, predicates);
      this.syncTable(PRODUCT_DICT_TABLE);
      return existing.id;
    }
    const rowId: number = await this.rdbStore.insert(PRODUCT_DICT_TABLE, valueBucket);
    this.syncTable(PRODUCT_DICT_TABLE);
    return rowId;
  }

  async queryProductDictByBarcode(barcode: string): Promise<ProductDict | null> {
    if (this.rdbStore === null || barcode.length === 0) return null;
    const predicates = new relationalStore.RdbPredicates(PRODUCT_DICT_TABLE);
    predicates.equalTo('barcode', barcode);
    const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
    let dict: ProductDict | null = null;
    if (resultSet.goToNextRow()) {
      dict = this.parseSingleProductDict(resultSet);
    }
    resultSet.close();
    return dict;
  }

  async queryProductDictByKey(key: string): Promise<ProductDict | null> {
    if (this.rdbStore === null || key.length === 0) return null;
    const predicates = new relationalStore.RdbPredicates(PRODUCT_DICT_TABLE);
    predicates.equalTo('dict_key', key);
    const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
    let dict: ProductDict | null = null;
    if (resultSet.goToNextRow()) {
      dict = this.parseSingleProductDict(resultSet);
    }
    resultSet.close();
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
    const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
    const dicts: ProductDict[] = [];
    while (resultSet.goToNextRow()) {
      dicts.push(this.parseSingleProductDict(resultSet));
    }
    resultSet.close();
    return dicts;
  }

  async getAllProductDict(): Promise<ProductDict[]> {
    return await this.searchProductDict('');
  }

  async deleteProductDict(id: number): Promise<void> {
    if (this.rdbStore === null) return;
    const predicates = new relationalStore.RdbPredicates(PRODUCT_DICT_TABLE);
    predicates.equalTo('id', id);
    await this.rdbStore.delete(predicates);
    this.syncTable(PRODUCT_DICT_TABLE);
  }

  async getProductDictCount(): Promise<number> {
    if (this.rdbStore === null) return 0;
    const predicates = new relationalStore.RdbPredicates(PRODUCT_DICT_TABLE);
    const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
    const count: number = resultSet.rowCount;
    resultSet.close();
    return count;
  }

  private parseSingleProductDict(resultSet: relationalStore.ResultSet): ProductDict {
    const dict = new ProductDict();
    dict.id = resultSet.getLong(resultSet.getColumnIndex('id'));
    dict.dictKey = resultSet.getString(resultSet.getColumnIndex('dict_key'));
    dict.barcode = resultSet.getString(resultSet.getColumnIndex('barcode'));
    dict.name = resultSet.getString(resultSet.getColumnIndex('name'));
    dict.category = resultSet.getString(resultSet.getColumnIndex('category'));
    dict.spec = resultSet.getString(resultSet.getColumnIndex('spec'));
    dict.calories = resultSet.getDouble(resultSet.getColumnIndex('calories'));
    dict.source = resultSet.getString(resultSet.getColumnIndex('source'));
    dict.updateTime = resultSet.getLong(resultSet.getColumnIndex('update_time'));
    return dict;
  }

  // ============ 内置条码库 ============

  async getBuiltinBarcodeCount(): Promise<number> {
    if (this.rdbStore === null) return 0;
    const predicates = new relationalStore.RdbPredicates(BUILTIN_BARCODE_TABLE);
    const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
    const count: number = resultSet.rowCount;
    resultSet.close();
    return count;
  }

  async queryBuiltinBarcode(barcode: string): Promise<string> {
    if (this.rdbStore === null || barcode.length === 0) return '';
    const predicates = new relationalStore.RdbPredicates(BUILTIN_BARCODE_TABLE);
    predicates.equalTo('barcode', barcode);
    const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
    let name: string = '';
    if (resultSet.goToNextRow()) {
      name = resultSet.getString(resultSet.getColumnIndex('name'));
    }
    resultSet.close();
    return name;
  }

  async batchInsertBuiltinBarcodes(barcodes: string[], names: string[]): Promise<void> {
    if (this.rdbStore === null) return;
    const BATCH_SIZE: number = 500;
    const total: number = barcodes.length;
    for (let start = 0; start < total; start += BATCH_SIZE) {
      const end: number = Math.min(start + BATCH_SIZE, total);
      let sql: string = 'INSERT INTO builtin_barcodes (barcode, name) VALUES ';
      const parts: string[] = [];
      for (let i = start; i < end; i++) {
        const escapedName: string = names[i].replace(/'/g, "''");
        parts.push("('" + barcodes[i] + "','" + escapedName + "')");
      }
      sql = sql + parts.join(',');
      await this.rdbStore.executeSql(sql);
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
      'create_time': Date.now()
    };
    return await this.rdbStore.insert(OCR_RECORD_TABLE, valueBucket);
  }

  async getOcrRecords(days: number): Promise<OcrRecord[]> {
    if (this.rdbStore === null) return [];
    const cutoff: number = Date.now() - days * 24 * 60 * 60 * 1000;
    const predicates = new relationalStore.RdbPredicates(OCR_RECORD_TABLE);
    predicates.greaterThanOrEqualTo('create_time', cutoff);
    predicates.orderByDesc('create_time');
    const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
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
    resultSet.close();
    return records;
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
    const resultSet: relationalStore.ResultSet = await this.rdbStore.query(predicates);
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
    resultSet.close();
    return records;
  }

  async updateOcrRecord(id: number, finalValue: number): Promise<void> {
    if (this.rdbStore === null) return;
    const valueBucket: relationalStore.ValuesBucket = {
      'final_value': finalValue
    };
    const predicates = new relationalStore.RdbPredicates(OCR_RECORD_TABLE);
    predicates.equalTo('id', id);
    await this.rdbStore.update(valueBucket, predicates);
  }
}
