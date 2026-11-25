import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { preferences, relationalStore } from '@kit.ArkData';
import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import { AppNavigation } from './AppNavigation';

const SYNC_PERMISSION: Permissions = 'ohos.permission.DISTRIBUTED_DATASYNC';
const PERMISSION_PROMPTED = 'distributed_permission_requested';
const SYNC_STATUS_KEY = 'foodDeviceSyncStatus';

export enum FoodSyncStatus {
  NeedsPermission,
  WaitingForDevice,
  Syncing,
  Synced,
  Failed,
  Unavailable
}

export class FoodDeviceSync {
  private store: relationalStore.RdbStore | null = null;
  private context: common.Context | null = null;
  private readonly tables: string[];
  private manager: distributedDeviceManager.DeviceManager | null = null;
  private ready = false;
  private active = true;
  private timer = -1;
  private running = false;
  private rerunRequested = false;
  private needsPull = false;
  private pauseCount = 0;
  private askingPermission = false;
  private pending: Set<string> = new Set<string>();

  constructor(tables: string[]) {
    this.tables = tables;
  }

  async initialize(store: relationalStore.RdbStore, context: common.Context): Promise<void> {
    this.store = store;
    this.context = context;
    if (!canIUse('SystemCapability.DistributedHardware.DeviceManager')) {
      this.setStatus(FoodSyncStatus.Unavailable);
      return;
    }
    await this.requestAccess(false);
  }

  async requestAccess(fromSettings: boolean): Promise<void> {
    const context = this.context;
    if (context === null || this.askingPermission ||
      !canIUse('SystemCapability.DistributedHardware.DeviceManager')) return;
    this.askingPermission = true;
    try {
      const manager = abilityAccessCtrl.createAtManager();
      if (!this.hasPermission()) {
        const settings = await preferences.getPreferences(context, 'food_device_sync');
        const asked = await settings.get(PERMISSION_PROMPTED, false);
        if (!asked) {
          await manager.requestPermissionsFromUser(context, [SYNC_PERMISSION]);
          await settings.put(PERMISSION_PROMPTED, true);
          await settings.flush();
        } else if (fromSettings) {
          await manager.requestPermissionOnSetting(context, [SYNC_PERMISSION]);
        }
      }
    } catch (error) {
      console.warn('Could not request distributed data permission: ' + error);
    } finally {
      this.askingPermission = false;
      this.refresh();
    }
  }

  onForeground(active: boolean): void {
    this.active = active;
    if (active) this.refresh();
  }

  refresh(): void {
    for (const table of this.tables) this.pending.add(table);
    this.needsPull = true;
    this.schedule();
  }

  markChanged(table: string): void {
    this.pending.add(table);
    this.schedule();
  }

  pause(): void {
    this.pauseCount++;
  }

  resume(): void {
    this.pauseCount = Math.max(0, this.pauseCount - 1);
    this.schedule();
  }

  private hasPermission(): boolean {
    if (this.context === null) return false;
    const manager = abilityAccessCtrl.createAtManager();
    return manager.checkAccessTokenSync(this.context.applicationInfo.accessTokenId, SYNC_PERMISSION) ===
      abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  private setStatus(status: FoodSyncStatus): void {
    AppStorage.setOrCreate<number>(SYNC_STATUS_KEY, status);
  }

  private schedule(): void {
    if (this.running) {
      this.rerunRequested = true;
      return;
    }
    if (this.store === null || !this.active || this.timer >= 0 ||
      this.pauseCount > 0 || !canIUse('SystemCapability.DistributedHardware.DeviceManager')) return;
    this.timer = setTimeout(() => {
      this.timer = -1;
      void this.syncPending();
    }, 350);
  }

  private async prepareStore(store: relationalStore.RdbStore, context: common.Context): Promise<void> {
    if (!this.ready) {
      const config: relationalStore.DistributedConfig = {
        autoSync: false,
        asyncDownloadAsset: false,
        enableCloud: false,
        tableType: relationalStore.DistributedTableType.SINGLE_VERSION
      };
      await store.setDistributedTables(this.tables, relationalStore.DistributedType.DISTRIBUTED_DEVICE, config);
      store.on('dataChange', relationalStore.SubscribeType.SUBSCRIBE_TYPE_REMOTE, () => {
        AppNavigation.notifyDataChanged();
      });
      this.ready = true;
    }
    if (this.manager === null) {
      const manager = distributedDeviceManager.createDeviceManager(context.applicationInfo.name);
      try {
        manager.on('deviceStateChange', () => { this.refresh(); });
      } catch (error) {
        distributedDeviceManager.releaseDeviceManager(manager);
        throw new Error('Could not subscribe to device changes');
      }
      this.manager = manager;
    }
  }

  private async syncPending(): Promise<void> {
    const store = this.store;
    const context = this.context;
    if (store === null || context === null || !this.active || this.pauseCount > 0) return;
    this.running = true;
    let completed = false;
    try {
      if (!this.hasPermission()) {
        this.setStatus(FoodSyncStatus.NeedsPermission);
        return;
      }
      await this.prepareStore(store, context);
      if (!this.active || this.pauseCount > 0) return;
      const devices = this.manager?.getAvailableDeviceListSync() ?? [];
      const deviceIds = devices.map((device: distributedDeviceManager.DeviceBasicInfo): string => device.networkId ?? '')
        .filter((networkId: string): boolean => networkId.length > 0);
      if (deviceIds.length === 0) {
        this.setStatus(FoodSyncStatus.WaitingForDevice);
        return;
      }
      this.setStatus(FoodSyncStatus.Syncing);
      const changed = this.pending;
      const pull = this.needsPull;
      this.pending = new Set<string>();
      this.needsPull = false;
      let failed = false;
      for (const table of this.tables) {
        if (!changed.has(table) && !pull) continue;
        if (changed.has(table) &&
          !await this.syncTable(store, table, deviceIds, relationalStore.SyncMode.SYNC_MODE_PUSH)) {
          failed = true;
          this.pending.add(table);
        }
        if (pull && !await this.syncTable(store, table, deviceIds, relationalStore.SyncMode.SYNC_MODE_PULL)) {
          failed = true;
          this.needsPull = true;
        }
      }
      this.setStatus(failed ? FoodSyncStatus.Failed : FoodSyncStatus.Synced);
      completed = !failed;
      if (pull) AppNavigation.notifyDataChanged();
    } catch (error) {
      this.setStatus(FoodSyncStatus.Failed);
      console.warn('Cross-device sync unavailable: ' + error);
    } finally {
      this.running = false;
      const anotherRequest = this.rerunRequested;
      this.rerunRequested = false;
      if ((completed || anotherRequest) && (this.pending.size > 0 || this.needsPull)) this.schedule();
    }
  }

  private async syncTable(store: relationalStore.RdbStore, table: string, devices: string[],
    mode: relationalStore.SyncMode): Promise<boolean> {
    if (!this.active || this.pauseCount > 0) return false;
    try {
      const predicates = new relationalStore.RdbPredicates(table).inDevices(devices);
      const results = await store.sync(mode, predicates);
      return results.length >= devices.length &&
        results.every((result: [string, number]): boolean => result[1] === 0);
    } catch (error) {
      console.warn('Cross-device sync request failed for ' + table + ': ' + error);
      return false;
    }
  }
}
