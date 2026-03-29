import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DataExportService } from '../common/DataExportService';
import { formatTimestampFull } from '../common/Constants';

@Entry
@Component
struct DataBackupPage {
  @State backupFiles: string[] = [];
  @State isExporting: boolean = false;
  @State isImporting: boolean = false;
  @State lastExportPath: string = '';

  aboutToAppear(): void {
    this.loadBackupFiles();
  }

  private loadBackupFiles(): void {
    this.backupFiles = DataExportService.getBackupFiles(getContext(this));
  }

  private async exportAll(): Promise<void> {
    this.isExporting = true;
    try {
      const json: string = await DataExportService.exportAllData();
      const fileName: string = 'backup_' + Date.now() + '.json';
      const path: string = await DataExportService.saveToFile(getContext(this), json, fileName);
      this.lastExportPath = path;
      promptAction.showToast({ message: '全量备份成功', duration: 2000 });
      this.loadBackupFiles();
    } catch (e) {
      promptAction.showToast({ message: '导出失败', duration: 1500 });
    }
    this.isExporting = false;
  }

  private async importAll(): Promise<void> {
    this.isImporting = true;
    try {
      const ctx: common.Context = getContext(this) as common.Context;
      const dir: string = ctx.filesDir;
      const filePath: string = dir + '/import_data.json';
      const jsonStr: string = await DataExportService.readFromFile(filePath);
      const result = await DataExportService.importAllData(jsonStr);
      if (result.success) {
        promptAction.showToast({ message: '全量导入成功', duration: 2000 });
      } else {
        promptAction.showToast({ message: result.message, duration: 2000 });
      }
    } catch (e) {
      promptAction.showToast({ message: '导入失败：文件不存在或格式错误', duration: 2000 });
    }
    this.isImporting = false;
  }

  private async exportDict(): Promise<void> {
    this.isExporting = true;
    try {
      const json: string = await DataExportService.exportProductDict();
      const fileName: string = 'dict_' + Date.now() + '.json';
      const path: string = await DataExportService.saveToFile(getContext(this), json, fileName);
      this.lastExportPath = path;
      promptAction.showToast({ message: '产品字典导出成功', duration: 2000 });
      this.loadBackupFiles();
    } catch (e) {
      promptAction.showToast({ message: '导出失败', duration: 1500 });
    }
    this.isExporting = false;
  }

  build() {
    Column() {
      // 导航栏
      Row() {
        Button('返回')
          .height(40).fontSize(14).fontColor('#007DFF')
          .backgroundColor(Color.Transparent)
          .onClick(() => { router.back(); })
        Text('数据备份与恢复')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          .layoutWeight(1).textAlign(TextAlign.Center)
        Text('').width(56)
      }
      .width('100%')      .padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))

      Scroll() {
        Column({ space: 16 }) {
          // 导出操作
          Column({ space: 12 }) {
            Text('数据导出')
              .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
            Text('导出数据为JSON文件，保存在应用沙箱目录')
              .fontSize(13).fontColor($r('app.color.text_hint')).width('100%')

            Button('全量导出（食品+成员+字典）')
              .width('100%').height(44).fontSize(14)
              .fontColor(Color.White).backgroundColor('#007DFF').borderRadius(8)
              .enabled(!this.isExporting)
              .onClick(() => { this.exportAll(); })

            Button('产品字典单独导出')
              .width('100%').height(44).fontSize(14)
              .fontColor('#007DFF').backgroundColor('#E8F0FE').borderRadius(8)
              .enabled(!this.isExporting)
              .onClick(() => { this.exportDict(); })

            Button('全量导入（从沙箱目录）')
              .width('100%').height(44).fontSize(14)
              .fontColor(Color.White).backgroundColor('#34C759').borderRadius(8)
              .enabled(!this.isImporting)
              .onClick(() => { this.importAll(); })

            Text('导入说明：将备份JSON文件重命名为 import_data.json 放入应用沙箱目录')
              .fontSize(11).fontColor($r('app.color.text_hint')).width('100%')

            if (this.lastExportPath.length > 0) {
              Text('最近导出: ' + this.lastExportPath)
                .fontSize(11).fontColor('#34C759').width('100%')
            }
          }
          .width('100%').padding(16).margin({ left: 16, right: 16, top: 16 })
          .backgroundColor($r('app.color.card_background')).borderRadius(16)

          // 安全提示
          Column({ space: 8 }) {
            Text('💡 数据安全说明')
              .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Text('• 所有数据仅存储在本地设备')
              .fontSize(13).fontColor($r('app.color.text_secondary'))
            Text('• 导出文件保存在应用沙箱目录')
              .fontSize(13).fontColor($r('app.color.text_secondary'))
            Text('• 卸载应用将清除所有本地数据')
              .fontSize(13).fontColor($r('app.color.text_secondary'))
            Text('• 建议定期导出备份重要数据')
              .fontSize(13).fontColor($r('app.color.text_secondary'))
          }
          .width('100%').padding(16).margin({ left: 16, right: 16 })
          .backgroundColor('#E8F5E9').borderRadius(16)
          .alignItems(HorizontalAlign.Start)

          // 备份文件列表
          Column({ space: 12 }) {
            Text('备份文件')
              .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
            if (this.backupFiles.length === 0) {
              Text('暂无备份文件')
                .fontSize(13).fontColor($r('app.color.text_hint')).width('100%')
                .textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 })
            } else {
              ForEach(this.backupFiles, (file: string) => {
                Row() {
                  Text('📄').fontSize(16).width(28)
                  Text(file).fontSize(13).fontColor($r('app.color.text_primary')).layoutWeight(1)
                }
                .width('100%').padding({ top: 6, bottom: 6 })
              }, (file: string) => file)
            }
          }
          .width('100%').padding(16).margin({ left: 16, right: 16, bottom: 32 })
          .backgroundColor($r('app.color.card_background')).borderRadius(16)
        }
      }
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }
}
