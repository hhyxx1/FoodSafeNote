import { router } from '@kit.ArkUI';

@Entry
@Component
struct EntrySelectionPage {
  build() {
    Column() {
      // 导航栏
      Row() {
        Button('返回')
          .height(36).fontSize(14).fontColor('#007DFF')
          .backgroundColor(Color.Transparent)
          .onClick(() => { router.back(); })
        Text('选择入库方式')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          .layoutWeight(1).textAlign(TextAlign.Center)
        Text('').width(56)
      }
      .width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))

      Scroll() {
        Column({ space: 12 }) {
          Blank()
            .height(6)

          // 扫码入库
          this.buildEntryCard('📷', '扫码入库', '扫描商品条码，自动匹配商品信息', () => {
            router.pushUrl({ url: 'pages/BarcodeScanPage' });
          })

          // 拍照入库
          this.buildEntryCard('📸', '拍照入库', '拍摄食品照片，适合生鲜果蔬', () => {
            router.pushUrl({ url: 'pages/PhotoEntryPage' });
          })

          // 手动入库
          this.buildEntryCard('✏️', '手动入库', '手动填写食品信息，适合无条码商品', () => {
            router.pushUrl({ url: 'pages/AddFoodPage' });
          })

          // 批量添加
          this.buildEntryCard('📋', '批量添加', '连续扫码/拍照多件食品，统一补充信息后批量入库', () => {
            router.pushUrl({ url: 'pages/BatchAddPage' });
          })

          // 剪贴板解析
          this.buildEntryCard('📎', '剪贴板解析', '手动读取剪贴板中的购物清单并生成待入库卡片', () => {
            router.pushUrl({ url: 'pages/ClipboardParsePage' });
          })

          // 底部快捷入口
          Row({ space: 16 }) {
            Button('产品字典')
              .height(40).fontSize(14).fontColor('#007DFF')
              .backgroundColor('#E8F0FE').borderRadius(8).layoutWeight(1)
              .onClick(() => { router.pushUrl({ url: 'pages/ProductDictPage' }); })
          }
          .width('100%').padding({ left: 16, right: 16, bottom: 16 })
        }
      }
      .layoutWeight(1).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }

  @Builder
  buildEntryCard(icon: string, title: string, subtitle: string, action: () => void) {
    Column({ space: 6 }) {
      Text(icon).fontSize(30)
      Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text(subtitle).fontSize(12).fontColor($r('app.color.text_hint')).textAlign(TextAlign.Center)
    }
    .width('100%').padding({ left: 14, right: 14, top: 14, bottom: 14 }).margin({ left: 16, right: 16 })
    .backgroundColor($r('app.color.card_background')).borderRadius(12)
    .alignItems(HorizontalAlign.Center)
    .shadow({ radius: 3, color: '#0D000000', offsetX: 0, offsetY: 1 })
    .onClick(action)
  }
}
