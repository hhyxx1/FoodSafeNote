import { FoodButtonStyle, FOOD_TITLE_BAR_STYLE } from '../common/FoodInterface';
import { common } from '@kit.AbilityKit';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppNavigation } from '../common/AppNavigation';
import { DataExportService } from '../common/DataExportService';
import { formatTimestampFull } from '../common/Constants';

@Component
struct DataBackupPage {
  @State backupFiles: string[] = [];
  @State isExporting: boolean = false;
  @State isImporting: boolean = false;
  private scroller: Scroller = new Scroller();
  // 状态栏高度（vp），由 Index 写入 AppStorage；用于标题栏沉浸避让
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  aboutToAppear(): void {
    this.loadBackupFiles();
  }

  private loadBackupFiles(): void {
    this.backupFiles = DataExportService.getBackupFiles(this.getUIContext().getHostContext() as common.Context);
  }

  private async exportAll(): Promise<void> {
    if (this.isExporting || this.isImporting) return;
    this.isExporting = true;
    try {
      const json: string = await DataExportService.exportAllData();
      const fileName: string = 'backup_' + Date.now() + '.json';
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (await DataExportService.saveToFile(ctx, json, fileName)) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_full_backup_exported'), duration: 2000 });
      }
    } catch (e) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_export_failed'), duration: 1500 });
      } catch (e) {
        // 提示失败，忽略
      }
    } finally {
      this.isExporting = false;
    }
  }

  private async importAll(backupFile: string = ''): Promise<void> {
    if (this.isExporting || this.isImporting) return;
    this.isImporting = true;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const files: string[] = backupFile.length > 0 ? [ctx.filesDir + '/' + backupFile] :
        await DataExportService.pickImportFile(ctx);
      if (files.length === 0) return;
      const jsonStr: string = await DataExportService.readFromFile(files[0]);
      const choice = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.ui_import_full_backup_file'),
        message: $r('app.string.ui_import_backup_adds_records'),
        buttons: [
          { text: $r('app.string.ui_cancel'), color: '#6B7280' },
          { text: $r('app.string.ui_confirm'), color: '#007DFF' }
        ]
      }).catch(() => null);
      if (choice === null || choice.index !== 1) return;
      const result = await DataExportService.importAllData(jsonStr);
      if (result.success) {
        AppNavigation.notifyDataChanged();
        this.getUIContext().getPromptAction().showToast({ message: result.message, duration: 2000 });
      } else {
        this.getUIContext().getPromptAction().showToast({ message: result.message, duration: 2000 });
      }
    } catch (e) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_import_failed_the_file_is_missing_or_has_an_invalid_format'), duration: 2000 });
      } catch (e) {
        // 提示失败，忽略
      }
    } finally {
      this.isImporting = false;
    }
  }

  private async exportDict(): Promise<void> {
    if (this.isExporting || this.isImporting) return;
    this.isExporting = true;
    try {
      const json: string = await DataExportService.exportProductDict();
      const fileName: string = 'dict_' + Date.now() + '.json';
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (await DataExportService.saveToFile(ctx, json, fileName)) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_product_dictionary_exported'), duration: 2000 });
      }
    } catch (e) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_export_failed'), duration: 1500 });
      } catch (e) {
        // 提示失败，忽略
      }
    } finally {
      this.isExporting = false;
    }
  }

  build() {
    HdsNavDestination() {
    Column() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          Column({ space: 12 }) {
            Text($r('app.string.ui_export_data'))
              .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
            Text($r('app.string.ui_choose_where_to_save_backup'))
              .fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')

            Button($r('app.string.ui_export_foods_members_and_dictionary'))
              .attributeModifier(FoodButtonStyle.primary)
              .width('100%')
              .enabled(!this.isImporting && !this.isExporting)
              .onClick(() => { this.exportAll(); })

            Button($r('app.string.ui_export_product_dictionary_only'))
              .attributeModifier(FoodButtonStyle.text)
              .width('100%')
              .enabled(!this.isImporting && !this.isExporting)
              .onClick(() => { this.exportDict(); })
          }
          .width('100%').padding(16).margin({ left: 16, right: 16, top: 10 })
          .backgroundColor($r('app.color.card_background')).borderRadius(20)

          Column({ space: 10 }) {
            Text($r('app.string.backup_restore_heading'))
              .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
            Text($r('app.string.backup_restore_description'))
              .fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
            Button($r('app.string.ui_import_full_backup_file'))
              .attributeModifier(FoodButtonStyle.secondary)
              .width('100%')
              .enabled(!this.isImporting && !this.isExporting)
              .onClick(() => { this.importAll(); })
          }
          .width('100%').padding(16).margin({ left: 16, right: 16 })
          .backgroundColor($r('app.color.card_background')).borderRadius(20)

          Text($r('app.string.ui_uninstalling_the_app_deletes_its_local_data'))
            .fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
            .padding({ left: 18, right: 18 })

          // 备份文件列表
          Column({ space: 12 }) {
            Text($r('app.string.ui_backup_files'))
              .fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
            if (this.backupFiles.length === 0) {
              Text($r('app.string.ui_no_backup_files'))
                .fontSize(13).fontColor($r('app.color.text_hint')).width('100%')
                .textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
            } else {
              ForEach(this.backupFiles, (file: string) => {
                Row() {
                  Image($r('app.media.icon_file')).width(16).height(16).draggable(false).margin({ right: 12 })
                  Text(file).fontSize(13).fontColor($r('app.color.text_primary')).layoutWeight(1)
                }
                .width('100%').padding({ top: 6, bottom: 6 })
                .enabled(!this.isImporting && !this.isExporting && !file.startsWith('dict_') && file !== 'import_dict.json')
                .onClick(() => { this.importAll(file); })
              }, (file: string) => file)
            }
          }
          .width('100%').padding(16).margin({ left: 16, right: 16, bottom: 32 })
          .backgroundColor($r('app.color.card_background')).borderRadius(16)
        }
        // 标题栏沉浸避让：状态栏高度 + 标题栏高度(56vp)
        .padding({ top: 56 + this.statusBarHeight })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      content: {
        title: { mainTitle: $r('app.string.ui_backup_and_restore') }
      },
      style: FOOD_TITLE_BAR_STYLE
    })
    .bindToScrollable([this.scroller])
    .onBackPressed(() => this.isImporting || this.isExporting)
    .onHidden(() => {
      AppNavigation.notifyDataChanged();
    })
    .backgroundColor($r('app.color.page_background'))
  }
}

// Navigation 系统路由表入口（router_map.json 中注册为 DataBackupPage）
@Builder
export function DataBackupPageBuilder() {
  DataBackupPage()
}