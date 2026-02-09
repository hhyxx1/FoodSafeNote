// 食品项数据模型
export class FoodItem {
  id: number = 0;
  name: string = '';
  category: string = '';
  spec: string = '';
  barcode: string = '';
  calories: number = 0;
  storageType: string = 'FRIDGE';
  isOpened: boolean = false;
  expiryDate: number = 0;
  status: number = 0;
  createTime: number = 0;
  consumedBy: string = '';
  wasteReason: string = '';
  consumeTime: number = 0;

  getRemainingDays(): number {
    if (this.expiryDate <= 0) return 999;
    const now: number = Date.now();
    const diff: number = this.expiryDate - now;
    return Math.ceil(diff / (24 * 60 * 60 * 1000));
  }

  isExpired(): boolean {
    if (this.expiryDate <= 0) return false;
    return Date.now() > this.expiryDate;
  }

  isNearExpiry(): boolean {
    if (this.expiryDate <= 0) return false;
    const remainingDays: number = this.getRemainingDays();
    return remainingDays >= 0 && remainingDays <= 3;
  }

  getStatusText(): string {
    if (this.status === 1) return '已食用';
    if (this.status === 2) return '已丢弃';
    if (this.isExpired()) return '已过期';
    if (this.isNearExpiry()) return '临期';
    return '正常';
  }

  getStatusColor(): string {
    if (this.status === 1) return '#999999';
    if (this.status === 2) return '#999999';
    if (this.isExpired()) return '#FF3B30';
    if (this.isNearExpiry()) return '#FF9500';
    return '#34C759';
  }

  getStatusBgColor(): string {
    if (this.isExpired()) return '#FFEDE9';
    if (this.isNearExpiry()) return '#FFF3E0';
    return '#E8F5E9';
  }
}

// 家庭成员数据模型
export class FamilyMember {
  id: number = 0;
  name: string = '';
  createTime: number = 0;
}

// 消耗记录数据模型
export class ConsumptionRecord {
  id: number = 0;
  foodItemId: number = 0;
  foodName: string = '';
  memberName: string = '';
  type: number = 0;
  calories: number = 0;
  wasteReason: string = '';
  createTime: number = 0;
}

// 每日热量汇总
export class DailyCalorie {
  memberName: string = '';
  totalCalories: number = 0;
  recordCount: number = 0;
}

// 食品统计
export class FoodStats {
  total: number = 0;
  active: number = 0;
  consumed: number = 0;
  wasted: number = 0;
  expired: number = 0;
}

// 产品字典数据模型（本地记忆库）
export class ProductDict {
  id: number = 0;
  dictKey: string = '';
  barcode: string = '';
  name: string = '';
  category: string = '';
  spec: string = '';
  calories: number = 0;
  source: string = 'manual';
  updateTime: number = 0;
}

// 内置条码库条目
export class BuiltinBarcode {
  id: number = 0;
  barcode: string = '';
  name: string = '';
}

// 条码匹配结果
export class BarcodeMatchResult {
  name: string = '';
  category: string = '';
  spec: string = '';
  calories: number = 0;
  source: string = '';
  matched: boolean = false;
}

// OCR识别记录
export class OcrRecord {
  id: number = 0;
  foodName: string = '';
  barcode: string = '';
  ocrValue: number = 0;
  finalValue: number = 0;
  createTime: number = 0;
}

// 浪费统计项
export class WasteStat {
  category: string = '';
  count: number = 0;
  totalCalories: number = 0;
}
