import { router, promptAction } from '@kit.ArkUI';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { BarcodeService } from '../common/BarcodeService';
import { FamilyMember, FoodStats } from '../model/DataModels';

@Component
export struct MineView {
  @Prop @Watch('onRefreshKeyChange') refreshKey: number = 0;
  @State members: FamilyMember[] = [];
  @State newMemberName: string = '';
  @State stats: FoodStats = new FoodStats();
  @State builtinCount: number = 0;
  @State dictCount: number = 0;

  aboutToAppear(): void {
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

  private addMember(): void {
    const name: string = this.newMemberName.trim();
    if (name.length === 0) {
      promptAction.showToast({ message: '请输入成员名称', duration: 1500 });
      return;
    }
    DatabaseHelper.getInstance().insertMember(name).then(() => {
      this.newMemberName = '';
      this.loadData();
      promptAction.showToast({ message: '添加成功', duration: 1500 });
    });
  }

  private deleteMember(member: FamilyMember): void {
    DatabaseHelper.getInstance().getMemberCount().then((count: number) => {
      if (count <= 1) {
        promptAction.showToast({ message: '至少保留一个家庭成员', duration: 1500 });
        return;
      }
      promptAction.showDialog({
        title: '确认删除',
        message: '确定要删除家庭成员 "' + member.name + '" 吗？',
        buttons: [
          { text: '取消', color: '#999999' },
          { text: '删除', color: '#FF3B30' }
        ]
      }).then((result: promptAction.ShowDialogSuccessResponse) => {
        if (result.index === 1) {
          DatabaseHelper.getInstance().deleteMember(member.id).then((success: boolean) => {
            if (success) {
              this.loadData();
              promptAction.showToast({ message: '已删除', duration: 1500 });
            } else {
              promptAction.showToast({ message: '至少保留一个家庭成员', duration: 1500 });
            }
          });
        }
      });
    });
  }

  build() {
    Column() {
      Row() {
        Text('我的')
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: 16 }) {
          // 家庭成员管理
          Column({ space: 12 }) {
            Text('家庭成员')
              .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
            Row({ space: 8 }) {
              TextInput({ text: this.newMemberName, placeholder: '输入成员名称，如：爸爸' })
                .layoutWeight(1).height(40).fontSize(14).borderRadius(8)
                .onChange((value: string) => { this.newMemberName = value; })
              Button('添加')
                .height(40).fontSize(14).fontColor(Color.White)
                .backgroundColor('#007DFF').borderRadius(8)
                .hoverEffect(HoverEffect.Highlight)
                .onClick(() => { this.addMember(); })
            }.width('100%')

            if (this.members.length === 0) {
              Text('暂无家庭成员，请添加')
                .fontSize(13).fontColor($r('app.color.text_hint')).width('100%')
                .textAlign(TextAlign.Center).padding({ top: 12, bottom: 12 })
            } else {
              ForEach(this.members, (member: FamilyMember) => {
                Row() {
                  Text(member.name.substring(0, 1))
                    .fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.White)
                    .textAlign(TextAlign.Center).width(36).height(36).borderRadius(18)
                    .backgroundColor('#007DFF')
                  Text(member.name)
                    .fontSize(15).fontColor($r('app.color.text_primary')).layoutWeight(1).padding({ left: 12 })
                  Button('删除')
                    .height(40).fontSize(12).fontColor('#FF3B30')
                    .backgroundColor('#FFEDE9').borderRadius(6)
                    .hoverEffect(HoverEffect.Highlight)
                    .onClick(() => { this.deleteMember(member); })
                }
                .width('100%').padding({ top: 8, bottom: 8 })
              }, (member: FamilyMember) => member.id.toString())
            }
          }
          .width('100%').padding(16).margin({ left: 16, right: 16 })
          .backgroundColor($r('app.color.card_background')).borderRadius(16)

          // 功能入口 - 直接内联，不通过builder传参，确保@State绑定
          Column({ space: 0 }) {
            Text('功能')
              .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
              .width('100%').padding({ bottom: 8 })

            // 产品字典 - 直接引用this.dictCount
            Row() {
              Column({ space: 2 }) {
                Text('📖 产品字典').fontSize(15).fontColor($r('app.color.text_primary'))
                Text(this.dictCount + ' 条记忆数据').fontSize(12).fontColor($r('app.color.text_hint'))
              }
              .layoutWeight(1).alignItems(HorizontalAlign.Start)
              Text('>').fontSize(16).fontColor($r('app.color.text_disabled'))
            }
            .width('100%').padding({ top: 12, bottom: 12 })
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => { router.pushUrl({ url: 'pages/ProductDictPage' }); })

            Divider().color($r('app.color.divider'))

            // 健康报表
            Row() {
              Column({ space: 2 }) {
                Text('📊 健康报表').fontSize(15).fontColor($r('app.color.text_primary'))
                Text('查看详细热量与浪费分析').fontSize(12).fontColor($r('app.color.text_hint'))
              }
              .layoutWeight(1).alignItems(HorizontalAlign.Start)
              Text('>').fontSize(16).fontColor($r('app.color.text_disabled'))
            }
            .width('100%').padding({ top: 12, bottom: 12 })
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => { router.pushUrl({ url: 'pages/HealthReportPage' }); })

            Divider().color($r('app.color.divider'))

            // 数据备份
            Row() {
              Column({ space: 2 }) {
                Text('💾 数据备份').fontSize(15).fontColor($r('app.color.text_primary'))
                Text('导出/导入/恢复数据').fontSize(12).fontColor($r('app.color.text_hint'))
              }
              .layoutWeight(1).alignItems(HorizontalAlign.Start)
              Text('>').fontSize(16).fontColor($r('app.color.text_disabled'))
            }
            .width('100%').padding({ top: 12, bottom: 12 })
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => { router.pushUrl({ url: 'pages/DataBackupPage' }); })

            Divider().color($r('app.color.divider'))

            // OCR记录
            Row() {
              Column({ space: 2 }) {
                Text('🔍 OCR记录').fontSize(15).fontColor($r('app.color.text_primary'))
                Text('查看热量识别历史').fontSize(12).fontColor($r('app.color.text_hint'))
              }
              .layoutWeight(1).alignItems(HorizontalAlign.Start)
              Text('>').fontSize(16).fontColor($r('app.color.text_disabled'))
            }
            .width('100%').padding({ top: 12, bottom: 12 })
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => { router.pushUrl({ url: 'pages/OcrRecordPage' }); })

            Divider().color($r('app.color.divider'))

            // 剪贴板解析入口已移至入库选择页（首页“+”），此处不再展示
          }
          .width('100%').padding(16).margin({ left: 16, right: 16 })
          .backgroundColor($r('app.color.card_background')).borderRadius(16)

          // 数据统计
          Column({ space: 12 }) {
            Text('数据统计')
              .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
            Row() {
              Column({ space: 4 }) {
                Text(this.stats.total.toString())
                  .fontSize(24).fontWeight(FontWeight.Bold).fontColor('#007DFF')
                Text('总入库').fontSize(12).fontColor($r('app.color.text_secondary'))
              }.alignItems(HorizontalAlign.Center).layoutWeight(1)
              Column({ space: 4 }) {
                Text(this.stats.active.toString())
                  .fontSize(24).fontWeight(FontWeight.Bold).fontColor('#34C759')
                Text('在库').fontSize(12).fontColor($r('app.color.text_secondary'))
              }.alignItems(HorizontalAlign.Center).layoutWeight(1)
              Column({ space: 4 }) {
                Text(this.stats.consumed.toString())
                  .fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FF9500')
                Text('已食用').fontSize(12).fontColor($r('app.color.text_secondary'))
              }.alignItems(HorizontalAlign.Center).layoutWeight(1)
              Column({ space: 4 }) {
                Text(this.stats.wasted.toString())
                  .fontSize(24).fontWeight(FontWeight.Bold).fontColor('#FF3B30')
                Text('已丢弃').fontSize(12).fontColor($r('app.color.text_secondary'))
              }.alignItems(HorizontalAlign.Center).layoutWeight(1)
            }
            .width('100%')

            Divider().color($r('app.color.divider'))

            Row() {
              Text('内置条码库')
                .fontSize(13).fontColor($r('app.color.text_secondary'))
              Blank()
              Text(this.builtinCount > 0 ? this.builtinCount + ' 条已加载' : '加载中...')
                .fontSize(13).fontColor(this.builtinCount > 0 ? '#34C759' : $r('app.color.text_hint'))
            }
            .width('100%')
          }
          .width('100%').padding(16).margin({ left: 16, right: 16 })
          .backgroundColor($r('app.color.card_background')).borderRadius(16)

          // 关于
          Column({ space: 12 }) {
            Text('关于')
              .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
            this.buildAboutRow('应用名称', '食安记 (Food Safe Note)')
            this.buildAboutRow('版本', 'v1.0.0')
            this.buildAboutRow('数据存储', '仅本地存储，离线可用')
            this.buildAboutRow('设计理念', '智能优先 · 全员平权 · 隐私安全')
          }
          .width('100%').padding(16).margin({ left: 16, right: 16, bottom: 16 })
          .backgroundColor($r('app.color.card_background')).borderRadius(16)
        }
      }
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
    .animation({ duration: 260, curve: Curve.EaseInOut })
  }

  @Builder
  buildAboutRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor($r('app.color.text_secondary')).width(80)
      Text(value).fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
    }
    .width('100%').padding({ top: 4, bottom: 4 })
  }
}
