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
        Text('添加食品')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          .layoutWeight(1).textAlign(TextAlign.Center)
        Text('').width(56)
      }
      .width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))

      Scroll() {
        Column({ space: 16 }) {
          // 标题
          Column({ space: 8 }) {
            Text('选择入库方式')
              .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            Text('扫码入库可自动匹配17万+商品信息')
              .fontSize(14).fontColor($r('app.color.text_hint'))
          }
          .width('100%').alignItems(HorizontalAlign.Center).padding({ top: 24 })

          // 扫码入库
          this.buildEntryCard('📷', '扫码入库', '扫描商品条码，自动匹配商品信息', () => {
            router.pushUrl({ url: 'pages/BarcodeScanPage' });
          })

          // 拍照入库
          this.buildEntryCard('📸', '拍照入库', '拍摄食品照片，适合生鲜果蔬', () => {
            router.pushUrl({ url: 'pages/AddFoodPage' });
          })

          // 手动入库
          this.buildEntryCard('✏️', '手动入库', '手动填写食品信息，适合无条码商品', () => {
            router.pushUrl({ url: 'pages/AddFoodPage' });
          })

          // 批量添加
          this.buildEntryCard('📋', '批量添加', '连续扫码/拍照多件食品，统一补充信息后批量入库', () => {
            router.pushUrl({ url: 'pages/BatchAddPage' });
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
    Column({ space: 8 }) {
      Text(icon).fontSize(36)
      Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text(subtitle).fontSize(13).fontColor($r('app.color.text_hint')).textAlign(TextAlign.Center)
    }
    .width('100%').padding(20).margin({ left: 16, right: 16 })
    .backgroundColor($r('app.color.card_background')).borderRadius(16)
    .alignItems(HorizontalAlign.Center)
    .shadow({ radius: 4, color: '#0D000000', offsetX: 0, offsetY: 2 })
    .onClick(action)
  }
}
