import { HdsNavDestination } from '@kit.UIDesignKit';
import { AppNavigation } from '../common/AppNavigation';
import { FoodButtonStyle, FOOD_PRESS_EFFECT, FoodMenuRow, FOOD_TITLE_BAR_STYLE } from '../common/FoodInterface';

@Component
struct EntrySelectionPage {
  private scroller: Scroller = new Scroller();

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column({ space: 18 }) {
          Row({ space: 14 }) {
            SymbolGlyph($r('sys.symbol.barcode_viewfinder'))
              .fontSize(32).fontColor([$r('app.color.journal_hero_text')])
            Column({ space: 5 }) {
              Text($r('app.string.ui_scan_a_barcode'))
                .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.journal_hero_text'))
              Text($r('app.string.add_scan_hint'))
                .fontSize(14).fontColor($r('app.color.journal_hero_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            SymbolGlyph($r('sys.symbol.chevron_forward'))
              .fontSize(17).fontColor([$r('app.color.journal_hero_text')])
          }
          .width('100%').constraintSize({ minHeight: 88 }).padding(18)
          .borderRadius(22).backgroundColor($r('app.color.journal_hero_bg'))
          .focusable(true)
          .clickEffect(FOOD_PRESS_EFFECT)
          .onClick(() => { AppNavigation.push('BarcodeScanPage'); })

          Column({ space: 8 }) {
            Text($r('app.string.entry_other_methods'))
              .fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
              .width('100%')
            Column() {
              FoodMenuRow({
                symbol: $r('sys.symbol.square_and_pencil'),
                title: $r('app.string.add_manual_title'),
                subtitle: $r('app.string.add_manual_hint'),
                onOpen: () => { AppNavigation.push('AddFoodPage'); }
              })
              Divider().color($r('app.color.divider')).margin({ left: 66, right: 14 })
              FoodMenuRow({
                symbol: $r('sys.symbol.camera'),
                title: $r('app.string.ui_add_from_a_photo'),
                subtitle: $r('app.string.add_photo_hint'),
                onOpen: () => { AppNavigation.push('PhotoEntryPage'); }
              })
              Divider().color($r('app.color.divider')).margin({ left: 66, right: 14 })
              FoodMenuRow({
                symbol: $r('sys.symbol.rectangle_stack'),
                title: $r('app.string.ui_add_in_bulk_2'),
                subtitle: $r('app.string.add_batch_hint'),
                onOpen: () => { AppNavigation.push('BatchAddPage'); }
              })
              Divider().color($r('app.color.divider')).margin({ left: 66, right: 14 })
              FoodMenuRow({
                symbol: $r('sys.symbol.list_bullet'),
                title: $r('app.string.ui_import_from_clipboard_2'),
                subtitle: $r('app.string.add_clipboard_hint'),
                onOpen: () => { AppNavigation.push('ClipboardParsePage'); }
              })
            }
            .width('100%').backgroundColor($r('app.color.card_background')).borderRadius(20)
          }
          .width('100%').alignItems(HorizontalAlign.Start)

          Button($r('app.string.ui_product_dictionary'))
            .attributeModifier(FoodButtonStyle.text)
            .onClick(() => { AppNavigation.push('ProductDictPage'); })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 66, bottom: 24 })
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off)
    }
    .titleBar({
      content: {
        title: { mainTitle: $r('app.string.ui_choose_how_to_add_food') }
      },
      style: FOOD_TITLE_BAR_STYLE
    })
    .bindToScrollable([this.scroller])
    .backgroundColor($r('app.color.page_background'))
  }
}

@Builder
export function EntrySelectionPageBuilder() {
  EntrySelectionPage()
}
