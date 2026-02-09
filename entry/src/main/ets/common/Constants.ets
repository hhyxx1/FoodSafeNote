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
export const WASTE_REASONS: string[] = ['过期', '变质', '吃不完', '其他'];

// 获取存储类型中文名
export function getStorageTypeName(type: string): string {
  if (type === StorageType.FRIDGE) return '冷藏';
  if (type === StorageType.FREEZER) return '冷冻';
  if (type === StorageType.ROOM) return '常温';
  return '未知';
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

// 时间戳格式化为 YYYY-MM-DD
export function formatTimestamp(timestamp: number): string {
  const date = new Date(timestamp);
  const year: number = date.getFullYear();
  const month: number = date.getMonth() + 1;
  const day: number = date.getDate();
  return year + '-' + padZero(month) + '-' + padZero(day);
}

// 数据来源标识
export class DataSource {
  static readonly MANUAL: string = 'manual';
  static readonly OCR: string = 'ocr';
  static readonly EDITED: string = 'edited';
  static readonly BUILTIN: string = 'builtin';
}

// 获取数据来源中文名
export function getSourceName(source: string): string {
  if (source === DataSource.MANUAL) return '手动录入';
  if (source === DataSource.OCR) return 'OCR识别';
  if (source === DataSource.EDITED) return '修改确认';
  if (source === DataSource.BUILTIN) return '内置库';
  return '未知';
}

// 时间戳格式化为 YYYY-MM-DD HH:mm
export function formatTimestampFull(timestamp: number): string {
  const date = new Date(timestamp);
  const year: number = date.getFullYear();
  const month: number = date.getMonth() + 1;
  const day: number = date.getDate();
  const hour: number = date.getHours();
  const minute: number = date.getMinutes();
  return year + '-' + padZero(month) + '-' + padZero(day) + ' ' + padZero(hour) + ':' + padZero(minute);
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
