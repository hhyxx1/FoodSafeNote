import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const MIGRATION_TABLE = 'local_schema_migrations';
const LEGACY_DATABASE = 'FoodSafeNote.db';
const LEGACY_ALIAS = 'legacy_food';

async function hasCompletedMigration(store: relationalStore.RdbStore): Promise<boolean> {
  await store.executeSql('CREATE TABLE IF NOT EXISTS ' + MIGRATION_TABLE + ' (version INTEGER PRIMARY KEY)');
  const rows = await store.querySql('SELECT version FROM ' + MIGRATION_TABLE + ' WHERE version = 1');
  try {
    return rows.goToFirstRow();
  } finally {
    rows.close();
  }
}

async function copyLegacyTable(store: relationalStore.RdbStore, table: string,
  extraColumns: string = '', extraValues: string = '', join: string = ''): Promise<void> {
  const available = await tableColumns(store, LEGACY_ALIAS, table);
  if (available.size === 0) return;
  const columns = Array.from(await tableColumns(store, 'main', table))
    .filter((name: string): boolean => available.has(name));
  if (!columns.includes('id')) throw new Error('Legacy table has no identifier: ' + table);

  const source = columns.map((column: string): string => 'old.' + column).join(', ');
  await store.executeSql('INSERT INTO ' + table + ' (' + columns.join(', ') + extraColumns +
    ') SELECT ' + source + extraValues + ' FROM ' + LEGACY_ALIAS + '.' + table + ' old' + join);
}

async function tableColumns(store: relationalStore.RdbStore, database: string, table: string): Promise<Set<string>> {
  const rows = await store.querySql('SELECT name FROM pragma_table_info(?, ?)', [table, database]);
  const columns = new Set<string>();
  try {
    const nameIndex = rows.getColumnIndex('name');
    while (rows.goToNextRow()) columns.add(rows.getString(nameIndex));
    return columns;
  } finally {
    rows.close();
  }
}

export async function migrateLegacyFoodDatabase(store: relationalStore.RdbStore, context: common.Context): Promise<void> {
  if (await hasCompletedMigration(store)) return;

  const previousConfig: relationalStore.StoreConfig = {
    name: LEGACY_DATABASE,
    securityLevel: relationalStore.SecurityLevel.S1
  };
  // Opening the old name also handles a fresh install, where the source contains no tables.
  const legacyStore = await relationalStore.getRdbStore(context, previousConfig);
  await legacyStore.close();
  await store.attach(context, previousConfig, LEGACY_ALIAS);
  try {
    store.beginTransaction();
    try {
      await copyLegacyTable(store, 'food_items', ', sync_key', ', lower(hex(randomblob(16)))');
      await copyLegacyTable(store, 'family_members', ', sync_key',
        ", CASE WHEN old.name = '我' AND old.id = (SELECT min(id) FROM legacy_food.family_members WHERE name = '我')" +
        " THEN 'self' ELSE lower(hex(randomblob(16))) END");
      await copyLegacyTable(store, 'consumption_records', ', sync_key, food_sync_key',
        ", lower(hex(randomblob(16))), coalesce(food.sync_key, '')",
        ' LEFT JOIN main.food_items food ON food.id = old.food_item_id');
      await copyLegacyTable(store, 'product_dict');
      await copyLegacyTable(store, 'builtin_barcodes');
      await copyLegacyTable(store, 'ocr_records');
      await store.executeSql('INSERT INTO ' + MIGRATION_TABLE + ' VALUES (1)');
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('Legacy database migration failed: ' + error);
    }
  } finally {
    await store.detach(LEGACY_ALIAS);
  }
}
