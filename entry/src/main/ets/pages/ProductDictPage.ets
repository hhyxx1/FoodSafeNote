import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { DataExportService } from '../common/DataExportService';
import { ProductDict } from '../model/DataModels';
import { getSourceName, formatTimestampFull } from '../common/Constants';

@Entry
@Component
struct ProductDictPage {
  @State dictList: ProductDict[] = [];
  @State searchKeyword: string = '';
  @State isLoading: boolean = true;
  @State totalCount: number = 0;
  @State showEditDialog: boolean = false;
  @State editItem: ProductDict | null = null;
  @State editName: string = '';
  @State editCategory: string = '';
  @State editSpec: string = '';
  @State editCalories: string = '';
  @State isDictExporting: boolean = false;
  @State isDictImporting: boolean = false;

  aboutToAppear(): void {
    this.loadData();
  }

  onPageShow(): void {
    this.loadData();
  }

  private loadData(): void {
    this.isLoading = true;
    DatabaseHelper.getInstance().searchProductDict(this.searchKeyword).then((list: ProductDict[]) => {
      this.dictList = list;
      this.isLoading = false;
    });
    DatabaseHelper.getInstance().getProductDictCount().then((count: number) => {
      this.totalCount = count;
    });
  }

  private deleteItem(item: ProductDict): void {
    promptAction.showDialog({
      title: '确认删除',
      message: '确定要删除 "' + item.name + '" 的记忆数据吗？',
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '删除', color: '#FF3B30' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        DatabaseHelper.getInstance().deleteProductDict(item.id).then(() => {
          promptAction.showToast({ message: '已删除', duration: 1500 });
          this.loadData();
        });
      }
    });
  }

  private openEditDialog(item: ProductDict): void {
    this.editItem = item;
    this.editName = item.name;
    this.editCategory = item.category;
    this.editSpec = item.spec;
    this.editCalories = item.calories > 0 ? item.calories.toString() : '';
    this.showEditDialog = true;
  }

  private async exportDict(): Promise<void> {
    this.isDictExporting = true;
    try {
      const json: string = await DataExportService.exportProductDict();
      const fileName: string = 'dict_' + Date.now() + '.json';
      await DataExportService.saveToFile(getContext(this), json, fileName);
      promptAction.showToast({ message: '字典导出成功', duration: 2000 });
    } catch (e) {
      promptAction.showToast({ message: '导出失败', duration: 1500 });
    }
    this.isDictExporting = false;
  }

  private async importDict(): Promise<void> {
    this.isDictImporting = true;
    try {
      const ctx: common.Context = getContext(this) as common.Context;
      const dir: string = ctx.filesDir;
      const filePath: string = dir + '/import_dict.json';
      const jsonStr: string = await DataExportService.readFromFile(filePath);
      const parsed: Record<string, Object> = JSON.parse(jsonStr) as Record<string, Object>;
      const dictArray: ProductDict[] = parsed['productDict'] as ProductDict[];
      if (dictArray === undefined || dictArray === null) {
        promptAction.showToast({ message: '文件格式错误：缺少productDict字段', duration: 2000 });
        this.isDictImporting = false;
        return;
      }
      const db: DatabaseHelper = DatabaseHelper.getInstance();
      for (let i = 0; i < dictArray.length; i++) {
        const dict: ProductDict = dictArray[i];
        const pd = new ProductDict();
        pd.dictKey = dict.dictKey;
        pd.barcode = dict.barcode;
        pd.name = dict.name;
        pd.category = dict.category;
        pd.spec = dict.spec;
        pd.calories = dict.calories;
        pd.source = dict.source;
        await db.insertOrUpdateProductDict(pd);
      }
      promptAction.showToast({ message: '字典导入成功', duration: 2000 });
      this.loadData();
    } catch (e) {
      promptAction.showToast({ message: '导入失败：文件不存在或格式错误', duration: 2000 });
    }
    this.isDictImporting = false;
  }

  private saveEdit(): void {
    if (this.editItem === null || this.editName.trim().length === 0) {
      promptAction.showToast({ message: '商品名称不能为空', duration: 1500 });
      return;
    }
    const dict = new ProductDict();
    dict.dictKey = this.editItem.dictKey;
    dict.barcode = this.editItem.barcode;
    dict.name = this.editName.trim();
    dict.category = this.editCategory.trim();
    dict.spec = this.editSpec.trim();
    dict.calories = Number(this.editCalories) || 0;
    dict.source = 'edited';
    DatabaseHelper.getInstance().insertOrUpdateProductDict(dict).then(() => {
      promptAction.showToast({ message: '已更新', duration: 1500 });
      this.showEditDialog = false;
      this.loadData();
    });
  }

  build() {
    Stack() {
      Column() {
        // 导航栏
        Row() {
          Button('返回')
            .height(36).fontSize(14).fontColor('#007DFF')
            .backgroundColor(Color.Transparent)
            .onClick(() => { router.back(); })
          Text('产品字典')
            .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            .layoutWeight(1).textAlign(TextAlign.Center)
          Text(this.totalCount + '条')
            .fontSize(13).fontColor($r('app.color.text_hint')).width(56).textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        // 搜索栏
        Row({ space: 8 }) {
          TextInput({ text: this.searchKeyword, placeholder: '搜索商品名称或条码' })
            .layoutWeight(1).height(40).fontSize(14).borderRadius(20)
            .backgroundColor($r('app.color.input_background'))
            .onChange((value: string) => {
              this.searchKeyword = value;
              this.loadData();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor($r('app.color.card_background'))

        // 提示
        Row() {
          Text('💡 数据仅本地存储，离线可用')
            .fontSize(12).fontColor($r('app.color.text_hint'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 4 })

        // 列表
        if (this.dictList.length === 0 && !this.isLoading) {
          Column({ space: 8 }) {
            Text('📖').fontSize(48)
            Text('暂无产品字典数据').fontSize(14).fontColor($r('app.color.text_hint'))
            Text('通过扫码入库会自动记录商品信息').fontSize(12).fontColor($r('app.color.text_disabled'))
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.dictList, (item: ProductDict) => {
              ListItem() {
                this.buildDictCard(item)
              }
            }, (item: ProductDict) => item.id.toString())
          }
          .width('100%').layoutWeight(1)
          .padding({ left: 16, right: 16, top: 8, bottom: 16 })
        }

        // 导入导出按钮
        Row({ space: 12 }) {
          Button('导出字典')
            .layoutWeight(1).height(40).fontSize(13)
            .fontColor(Color.White).backgroundColor('#007DFF').borderRadius(8)
            .enabled(!this.isDictExporting)
            .onClick(() => { this.exportDict(); })
          Button('导入字典')
            .layoutWeight(1).height(40).fontSize(13)
            .fontColor(Color.White).backgroundColor('#34C759').borderRadius(8)
            .enabled(!this.isDictImporting)
            .onClick(() => { this.importDict(); })
        }
        .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('100%').height('100%').backgroundColor($r('app.color.page_background'))

      // 编辑弹窗
      if (this.showEditDialog) {
        Column() {
          Column()
            .width('100%').height('100%').backgroundColor('#80000000')
            .onClick(() => { this.showEditDialog = false; })
        }
        .width('100%').height('100%').position({ x: 0, y: 0 })

        Column({ space: 12 }) {
          Text('编辑产品信息')
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')

          if (this.editItem !== null && this.editItem.barcode.length > 0) {
            Row() {
              Text('条码: ').fontSize(13).fontColor($r('app.color.text_secondary'))
              Text(this.editItem.barcode).fontSize(13).fontColor($r('app.color.text_hint'))
            }.width('100%')
          }

          Column({ space: 4 }) {
            Text('商品名称 *').fontSize(13).fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.editName, placeholder: '商品名称' })
              .width('100%').height(40).fontSize(14).borderRadius(8).backgroundColor($r('app.color.input_background'))
              .onChange((value: string) => { this.editName = value; })
          }
          Column({ space: 4 }) {
            Text('品类').fontSize(13).fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.editCategory, placeholder: '品类（选填）' })
              .width('100%').height(40).fontSize(14).borderRadius(8).backgroundColor($r('app.color.input_background'))
              .onChange((value: string) => { this.editCategory = value; })
          }
          Column({ space: 4 }) {
            Text('规格').fontSize(13).fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.editSpec, placeholder: '规格（选填）' })
              .width('100%').height(40).fontSize(14).borderRadius(8).backgroundColor($r('app.color.input_background'))
              .onChange((value: string) => { this.editSpec = value; })
          }
          Column({ space: 4 }) {
            Text('热量 (kcal)').fontSize(13).fontColor($r('app.color.text_secondary'))
            TextInput({ text: this.editCalories, placeholder: '0' })
              .width('100%').height(40).fontSize(14).borderRadius(8).backgroundColor($r('app.color.input_background'))
              .type(InputType.Number)
              .onChange((value: string) => { this.editCalories = value; })
          }
          Row({ space: 12 }) {
            Button('取消').layoutWeight(1).height(40).fontSize(14)
              .fontColor($r('app.color.text_secondary')).backgroundColor($r('app.color.chip_background')).borderRadius(8)
              .onClick(() => { this.showEditDialog = false; })
            Button('保存').layoutWeight(1).height(40).fontSize(14)
              .fontColor(Color.White).backgroundColor('#007DFF').borderRadius(8)
              .onClick(() => { this.saveEdit(); })
          }.width('100%')
        }
        .width('85%').padding(20).backgroundColor($r('app.color.card_background')).borderRadius(16)
        .position({ x: '7.5%', y: '15%' })
      }
    }
    .width('100%').height('100%')
  }

  @Builder
  buildDictCard(item: ProductDict) {
    Column({ space: 6 }) {
      Row() {
        Text(item.name)
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(getSourceName(item.source))
          .fontSize(11).fontColor('#007DFF')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8).backgroundColor('#E8F0FE')
      }.width('100%')

      Row({ space: 12 }) {
        if (item.barcode.length > 0) {
          Text('条码: ' + item.barcode).fontSize(12).fontColor($r('app.color.text_hint'))
        }
        if (item.category.length > 0) {
          Text(item.category).fontSize(12).fontColor($r('app.color.text_hint'))
        }
        if (item.spec.length > 0) {
          Text(item.spec).fontSize(12).fontColor($r('app.color.text_hint'))
        }
      }

      Row() {
        Text(item.calories > 0 ? item.calories.toFixed(0) + ' kcal' : '未记录热量')
          .fontSize(12).fontColor(item.calories > 0 ? '#FF6B00' : '#CCCCCC')
          .layoutWeight(1)
        Button('编辑')
          .height(28).fontSize(11).fontColor('#007DFF').backgroundColor('#E8F0FE')
          .borderRadius(6).margin({ right: 8 })
          .onClick(() => { this.openEditDialog(item); })
        Button('删除')
          .height(28).fontSize(11).fontColor('#FF3B30').backgroundColor('#FFEDE9')
          .borderRadius(6)
          .onClick(() => { this.deleteItem(item); })
      }.width('100%')
    }
    .width('100%').padding(12).backgroundColor($r('app.color.card_background')).borderRadius(12)
  }
}
