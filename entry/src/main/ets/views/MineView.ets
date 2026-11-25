import { FoodButtonStyle, FoodMenuRow, FoodMotion } from '../common/FoodInterface';
import { FoodSyncStatus } from '../common/FoodDeviceSync';
import { bundleManager } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { BarcodeService } from '../common/BarcodeService';
import { AppNavigation } from '../common/AppNavigation';
import { FamilyMember, FoodStats } from '../model/DataModels';

@Component
export struct MineView {
  @Prop @Watch('onRefreshKeyChange') refreshKey: number = 0;
  @Prop tabBarInset: number = 0;
  @StorageProp('foodDeviceSyncStatus') syncStatus: number = FoodSyncStatus.NeedsPermission;
  @State members: FamilyMember[] = [];
  @State appVersion: string = '';
  @State isAddingMember: boolean = false;
  @State newMemberName: string = '';
  @State stats: FoodStats = new FoodStats();
  @State builtinCount: number = 0;
  @State dictCount: number = 0;

  aboutToAppear(): void {
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      .then((info: bundleManager.BundleInfo) => {
        this.appVersion = 'v' + info.versionName;
      })
      .catch(() => {});
    if (DatabaseHelper.getInstance().getStore() !== null) {
      this.loadData();
    }
  }

  onRefreshKeyChange(): void {
    this.loadData();
  }

  private loadData(): void {
    DatabaseHelper.getInstance().getAllMembers().then((members: FamilyMember[]) => {
      this.members = members;
    });
    DatabaseHelper.getInstance().getFoodStats().then((stats: FoodStats) => {
      this.stats = stats;
    });
    DatabaseHelper.getInstance().getBuiltinBarcodeCount().then((count: number) => {
      this.builtinCount = count;
    });
    DatabaseHelper.getInstance().getProductDictCount().then((count: number) => {
      this.dictCount = count;
    });
  }

  private async addMember(): Promise<void> {
    if (this.isAddingMember) return;
    const name: string = this.newMemberName.trim();
    if (name.length === 0) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_enter_a_family_member_name'), duration: 1500 });
      } catch (e) {
        // 提示失败，忽略
      }
      return;
    }
    this.isAddingMember = true;
    try {
      if (await DatabaseHelper.getInstance().insertMember(name) <= 0) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_could_not_save_try_again') });
        return;
      }
      this.newMemberName = '';
      this.loadData();
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_added'), duration: 1500 });
    } finally {
      this.isAddingMember = false;
    }
  }

  private deleteMember(member: FamilyMember): void {
    DatabaseHelper.getInstance().getMemberCount().then((count: number) => {
      if (count <= 1) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_keep_at_least_one_family_member'), duration: 1500 });
        return;
      }
      this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.ui_confirm_deletion'),
        message: $r('app.string.ui_remove_s_from_your_family', member.name),
        buttons: [
          { text: $r('app.string.ui_cancel'), color: '#999999' },
          { text: $r('app.string.ui_delete'), color: '#FF3B30' }
        ]
      }).then((result: promptAction.ShowDialogSuccessResponse) => {
        if (result.index === 1) {
          DatabaseHelper.getInstance().deleteMember(member.id).then((success: boolean) => {
            if (success) {
              this.loadData();
              this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_deleted'), duration: 1500 });
            } else {
              this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_keep_at_least_one_family_member'), duration: 1500 });
            }
          });
        }
      });
    });
  }

  private getSyncStatusText(): Resource {
    switch (this.syncStatus) {
      case FoodSyncStatus.WaitingForDevice: return $r('app.string.food_sync_waiting');
      case FoodSyncStatus.Syncing: return $r('app.string.food_sync_syncing');
      case FoodSyncStatus.Synced: return $r('app.string.food_sync_synced');
      case FoodSyncStatus.Failed: return $r('app.string.food_sync_failed');
      case FoodSyncStatus.Unavailable: return $r('app.string.food_sync_unavailable');
      default: return $r('app.string.food_sync_permission');
    }
  }

  build() {
    Column() {
      Text($r('app.string.ui_profile'))
        .fontSize(29).lineHeight(36).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        .width('100%').padding({ left: 20, right: 20, top: 14, bottom: 14 })

      Scroll() {
        Column({ space: 22 }) {
          Column({ space: 9 }) {
            this.sectionHeading($r('app.string.profile_records_and_tools'))
            Column() {
              FoodMenuRow({
                symbol: $r('sys.symbol.doc_text'),
                title: $r('app.string.ui_product_dictionary_2'),
                subtitle: $r('app.string.ui_saved_entries_d', this.dictCount),
                onOpen: () => { AppNavigation.push('ProductDictPage'); }
              })
              this.menuDivider()
              FoodMenuRow({
                symbol: $r('sys.symbol.heart'),
                title: $r('app.string.ui_health_report_2'),
                subtitle: $r('app.string.ui_view_calorie_and_food_waste_reports'),
                onOpen: () => { AppNavigation.push('HealthReportPage'); }
              })
              this.menuDivider()
              FoodMenuRow({
                symbol: $r('sys.symbol.archivebox'),
                title: $r('app.string.ui_backup'),
                subtitle: $r('app.string.ui_export_import_or_restore_data'),
                onOpen: () => { AppNavigation.push('DataBackupPage'); }
              })
              if (this.syncStatus !== FoodSyncStatus.Unavailable) {
                this.menuDivider()
                FoodMenuRow({
                  symbol: $r('sys.symbol.arrow_clockwise'),
                  title: $r('app.string.food_sync_title'),
                  subtitle: this.getSyncStatusText(),
                  onOpen: () => { void DatabaseHelper.getInstance().deviceSync.requestAccess(true); }
                })
              }
              this.menuDivider()
              FoodMenuRow({
                symbol: $r('sys.symbol.magnifyingglass'),
                title: $r('app.string.ui_ocr_history_2'),
                subtitle: $r('app.string.ui_view_nutrition_label_scan_history'),
                onOpen: () => { AppNavigation.push('OcrRecordPage'); }
              })
            }
            .width('100%').backgroundColor($r('app.color.card_background')).borderRadius(20)
          }.width('100%')

          Column({ space: 9 }) {
            this.sectionHeading($r('app.string.ui_family_members'))
            Column({ space: 10 }) {
              ForEach(this.members, (member: FamilyMember) => {
                Row({ space: 10 }) {
                  Text(member.name.substring(0, 1))
                    .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.button_secondary_text'))
                    .textAlign(TextAlign.Center).width(36).height(36).borderRadius(12)
                    .backgroundColor($r('app.color.button_secondary_bg'))
                  Text(member.name)
                    .fontSize(16).fontColor($r('app.color.text_primary')).layoutWeight(1)
                  Button($r('app.string.ui_delete'))
                    .attributeModifier(FoodButtonStyle.compactDanger)
                    .onClick(() => { this.deleteMember(member); })
                }
                .width('100%')
                .transition(FoodMotion.reveal())
              }, (member: FamilyMember) => member.id.toString())

              if (this.members.length === 0) {
                Text($r('app.string.ui_add_a_family_member_to_get_started'))
                  .fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
              }

              Row({ space: 8 }) {
                TextInput({ text: this.newMemberName, placeholder: $r('app.string.ui_enter_a_name_e_g_dad') })
                  .layoutWeight(1).height(46).fontSize(15).borderRadius(13)
                  .fontColor($r('app.color.text_primary')).placeholderColor($r('app.color.text_hint'))
                  .backgroundColor($r('app.color.input_background'))
                  .enabled(!this.isAddingMember)
                  .enterKeyType(EnterKeyType.Done)
                  .onChange((value: string) => { this.newMemberName = value; })
                  .onSubmit(() => { this.addMember(); })
                Button($r('app.string.ui_add'))
                  .attributeModifier(FoodButtonStyle.compactPrimary)
                  .enabled(this.newMemberName.trim().length > 0 && !this.isAddingMember)
                  .onClick(() => { this.addMember(); })
              }
              .width('100%')
            }
            .width('100%').padding(14).backgroundColor($r('app.color.card_background')).borderRadius(20)
          }.width('100%')

          Column({ space: 9 }) {
            this.sectionHeading($r('app.string.ui_statistics'))
            Column({ space: 12 }) {
              Row() {
                this.statValue($r('app.string.ui_total_added'), this.stats.total)
                this.statValue($r('app.string.ui_in_stock'), this.stats.active)
                this.statValue($r('app.string.ui_consumed'), this.stats.consumed)
                this.statValue($r('app.string.ui_discarded'), this.stats.wasted)
              }
              .width('100%')
              Divider().color($r('app.color.divider'))
              Row({ space: 8 }) {
                Text($r('app.string.ui_built_in_barcode_database'))
                  .fontSize(13).fontColor($r('app.color.text_secondary')).layoutWeight(1)
                Text(this.builtinCount > 0 ? $r('app.string.ui_loaded_d', this.builtinCount) : $r('app.string.ui_loading'))
                  .fontSize(13).fontColor($r('app.color.accent_link'))
              }.width('100%')
            }
            .width('100%').padding(14).backgroundColor($r('app.color.card_background')).borderRadius(20)
          }.width('100%')

          Column({ space: 10 }) {
            this.sectionHeading($r('app.string.ui_about'))
            this.buildAboutRow($r('app.string.about_app_name'), $r('app.string.about_app_name_value'))
            if (this.appVersion.length > 0) {
              this.buildAboutRow($r('app.string.about_version'), this.appVersion)
            }
            this.buildAboutRow($r('app.string.about_storage'), $r('app.string.about_storage_value'))
            this.buildAboutRow($r('app.string.about_design'), $r('app.string.about_design_value'))
          }
          .width('100%')
          .padding({ bottom: 10 })
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: this.tabBarInset })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }

  @Builder
  sectionHeading(title: ResourceStr) {
    Text(title).width('100%')
      .fontSize(17).fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
  }

  @Builder
  menuDivider() {
    Divider().color($r('app.color.divider')).margin({ left: 66, right: 14 })
  }

  @Builder
  statValue(label: ResourceStr, count: number) {
    Column({ space: 5 }) {
      Text(count.toString()).fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.accent_link'))
      Text(label).fontSize(13).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
  }

  @Builder
  buildAboutRow(label: ResourceStr, detail: ResourceStr) {
    Row({ space: 12 }) {
      Text(label).fontSize(14).fontColor($r('app.color.text_secondary')).layoutWeight(1)
      Text(detail).fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(2)
        .textAlign(TextAlign.End)
    }
    .width('100%').padding({ top: 4, bottom: 4 })
  }
}
