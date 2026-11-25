import { StorageType } from './Constants';

export interface IntakeSeed {
  name: string;
  barcode?: string;
  category?: string;
  spec?: string;
  calories?: number;
  storage?: string;
  photoUri?: string;
}

export interface IntakeParams {
  mode: string;
  seeds?: IntakeSeed[];
}

export interface IntakeImportParams {
  onImported: (seeds: IntakeSeed[]) => void;
}

export interface IntakeNutritionParams {
  barcode: string;
  name: string;
  category: string;
  spec: string;
  amount?: number;
  amountUnit?: string;
  onApplied?: (calories: number) => void;
}

@Observed
export class IntakeDraft {
  key: number = 0;
  name: string = '';
  barcode: string = '';
  category: string = '';
  spec: string = '';
  calorieText: string = '';
  storage: string = StorageType.FRIDGE;
  expiry: number = 0;
  estimated: boolean = false;
  quantity: number = 1;
  photoUri: string = '';

  constructor(key: number, seed?: IntakeSeed) {
    this.key = key;
    this.name = seed?.name ?? '';
    this.barcode = seed?.barcode ?? '';
    this.category = seed?.category ?? '';
    this.spec = seed?.spec ?? '';
    this.calorieText = seed?.calories === undefined ? '' : seed.calories.toString();
    this.storage = seed?.storage || StorageType.FRIDGE;
    this.photoUri = seed?.photoUri ?? '';
  }
}
