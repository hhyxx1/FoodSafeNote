// 食品状态枚举
export enum FoodStatus {
  NORMAL = 0,
  CONSUMED = 1,
  WASTED = 2
}

// 存储类型枚举
export enum StorageType {
  FRIDGE = 'FRIDGE',
  FREEZER = 'FREEZER',
  ROOM = 'ROOM'
}

// 食品分类列表
export const FOOD_CATEGORIES: string[] = [
  '蔬菜', '水果', '肉类', '海鲜', '乳制品',
  '零食', '饮料', '调味品', '主食', '熟食', '其他'
];

// 浪费原因列表
export const EXPIRED_WASTE_REASON: string = '过期/变质';
export const WASTE_REASONS: string[] = [EXPIRED_WASTE_REASON, '吃不完', '其他'];

// 获取存储类型中文名
export function getStorageTypeName(type: string): ResourceStr {
  if (type === StorageType.FRIDGE) return $r('app.string.ui_refrigerated');
  if (type === StorageType.FREEZER) return $r('app.string.ui_frozen');
  if (type === StorageType.ROOM) return $r('app.string.ui_room_temperature');
  return $r('app.string.ui_unknown');
}

// 判断是否为包装食品
export function isPackagedFood(category: string): boolean {
  const packagedList: string[] = ['零食', '饮料', '调味品', '主食'];
  return packagedList.indexOf(category) >= 0;
}

// 获取生鲜食品基础保质期天数
export function getBaseDays(category: string): number {
  if (category === '蔬菜') return 5;
  if (category === '水果') return 7;
  if (category === '肉类') return 3;
  if (category === '海鲜') return 2;
  if (category === '乳制品') return 14;
  if (category === '熟食') return 2;
  return 7;
}

// 计算保质期到期时间戳
export function calculateExpiryTimestamp(category: string, storageType: string, isOpened: boolean = false): number {
  const baseDays: number = getBaseDays(category);
  let factor: number = 1;
  if (storageType === StorageType.FREEZER) {
    factor = 10;
  } else if (storageType === StorageType.ROOM) {
    factor = 0.5;
  }
  if (isOpened) {
    factor = factor / 3;
  }
  const expiryDays: number = Math.round(baseDays * factor);
  const now: number = Date.now();
  return now + expiryDays * 24 * 60 * 60 * 1000;
}

// 日期格式化辅助
export function padZero(num: number): string {
  if (num < 10) return '0' + num.toString();
  return num.toString();
}

// 按设备语言显示日期。
export function formatTimestamp(timestamp: number): string {
  return new Date(timestamp).toLocaleDateString();
}

// 数据来源标识
export class DataSource {
  static readonly MANUAL: string = 'manual';
  static readonly OCR: string = 'ocr';
  static readonly EDITED: string = 'edited';
  static readonly BUILTIN: string = 'builtin';
}

// 获取数据来源中文名
export function getSourceName(source: string): ResourceStr {
  if (source === DataSource.MANUAL) return $r('app.string.ui_manual_entry');
  if (source === DataSource.OCR) return $r('app.string.ui_nutrition_label_scan');
  if (source === DataSource.EDITED) return $r('app.string.ui_edited_and_confirmed');
  if (source === DataSource.BUILTIN) return $r('app.string.ui_built_in_database');
  return $r('app.string.ui_unknown');
}

// 按设备语言显示日期与时间。
export function formatTimestampFull(timestamp: number): string {
  return new Date(timestamp).toLocaleString();
}

// kJ转kcal (1 kcal = 4.184 kJ)
export function kjToKcal(kj: number): number {
  return Math.round(kj / 4.184);
}

// kcal转kJ
export function kcalToKj(kcal: number): number {
  return Math.round(kcal * 4.184);
}

// 颜色常量
export class AppColors {
  static readonly PRIMARY: string = '#007DFF';
  static readonly WARNING: string = '#FF6B00';
  static readonly DANGER: string = '#FF3B30';
  static readonly SUCCESS: string = '#34C759';
  static readonly NEAR_EXPIRY: string = '#FF9500';
  static readonly TEXT_PRIMARY: string = '#333333';
  static readonly TEXT_SECONDARY: string = '#666666';
  static readonly TEXT_HINT: string = '#999999';
  static readonly BACKGROUND: string = '#F5F5F5';
  static readonly CARD_BG: string = '#FFFFFF';
}

// Translate known display labels while retaining persisted values.
export function localizedFoodLabel(value: string): ResourceStr {
  switch (value) {
    case '蔬菜': return $r('app.string.ui_vegetables');
    case '水果': return $r('app.string.ui_fruit');
    case '肉类': return $r('app.string.ui_meat');
    case '海鲜': return $r('app.string.ui_seafood');
    case '乳制品': return $r('app.string.ui_dairy');
    case '零食': return $r('app.string.ui_snacks');
    case '饮料': return $r('app.string.ui_drinks');
    case '调味品': return $r('app.string.ui_seasonings');
    case '主食': return $r('app.string.ui_staples');
    case '熟食': return $r('app.string.ui_prepared_food');
    case '其他': return $r('app.string.ui_other');
    case '过期/变质': return $r('app.string.ui_expired_or_spoiled');
    case '吃不完': return $r('app.string.ui_leftovers');
    case '手动录入': return $r('app.string.ui_manual_entry');
    case 'OCR识别': return $r('app.string.ui_nutrition_label_scan');
    case '修改确认': return $r('app.string.ui_edited_and_confirmed');
    case '内置库': return $r('app.string.ui_built_in_database');
    default: return value;
  }
}

export function resolveLocalizedText(context: Context | undefined, resourceId: number,
  first?: string | number, second?: string | number): string {
  if (context === undefined) {
    return '';
  }
  try {
    if (first === undefined) {
      return context.resourceManager.getStringSync(resourceId);
    }
    if (second === undefined) {
      return context.resourceManager.getStringSync(resourceId, first);
    }
    return context.resourceManager.getStringSync(resourceId, first, second);
  } catch (error) {
    console.warn('Could not load a localized string');
    return '';
  }
}

export function localizedFoodLabelText(context: Context | undefined, value: string): string {
  const label = localizedFoodLabel(value);
  return typeof label === 'string' ? label : resolveLocalizedText(context, label.id) || value;
}
