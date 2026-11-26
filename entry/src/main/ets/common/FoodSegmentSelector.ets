import { FoodButtonStyle, FoodMotion } from './FoodInterface';

export interface FoodSegmentOption {
  id: string;
  label: Resource;
}

@Component
export struct FoodSegmentSelector {
  @Prop options: FoodSegmentOption[] = [];
  @Prop @Watch('syncIndicator') selectedId: string = '';
  @Prop counts: number[] = [];
  @State indicatorIndex: number = 0;
  @State hasSelection: boolean = false;
  @State segmentWidth: number = 0;
  onSelect: (id: string) => void = () => {};

  aboutToAppear(): void {
    this.syncIndicator();
  }

  private syncIndicator(): void {
    const target = this.options.findIndex((option: FoodSegmentOption): boolean => option.id === this.selectedId);
    if (target >= 0) this.indicatorIndex = target;
    this.hasSelection = target >= 0;
  }

  @Builder
  label(option: FoodSegmentOption, index: number, active: boolean) {
    Column({ space: 1 }) {
      Text(option.label)
        .fontSize(13).fontWeight(FontWeight.Medium)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .fontColor(active ? $r('app.color.button_primary_text') : $r('app.color.text_primary'))
      if (this.counts.length > index) {
        Text(this.counts[index].toString())
          .fontSize(16).fontWeight(FontWeight.Bold)
          .textAlign(TextAlign.Center)
          .fontColor(active ? $r('app.color.button_primary_text') : $r('app.color.text_primary'))
      }
    }
    .width('100%').padding({ left: 3, right: 3 })
  }

  build() {
    Row() {
      ForEach(this.options, (option: FoodSegmentOption, index: number) => {
        Button() {
          Stack({ alignContent: Alignment.Center }) {
            this.label(option, index, false)

            // Each cell clips its share of the same moving capsule. Counter-translation keeps the label still.
            Stack({ alignContent: Alignment.Center }) {
              Row() {
                this.label(option, index, true)
              }
              .width('100%')
              .translate({ x: (index - this.indicatorIndex) * this.segmentWidth })
              .animation(FoodMotion.selection)
            }
            .width('100%').height('100%')
            .backgroundColor($r('app.color.button_primary_bg'))
            .borderRadius(this.counts.length > 0 ? 29 : 23).clip(true)
            .translate({ x: (this.indicatorIndex - index) * this.segmentWidth })
            .opacity(this.hasSelection && this.segmentWidth > 0 ? 1 : 0)
            .animation(FoodMotion.selection)
            .hitTestBehavior(HitTestMode.None)
            .accessibilityLevel('no-hide-descendants')
          }
          .width('100%').height('100%').clip(true)
        }
        .attributeModifier(FoodButtonStyle.segment)
        .layoutWeight(1).height(this.counts.length > 0 ? 58 : 46).padding(0)
        .accessibilityText(option.label)
        .accessibilityDescription(this.counts.length > index ? this.counts[index].toString() : '')
        .accessibilitySelected(this.selectedId === option.id)
        .onClick(() => { this.onSelect(option.id); })
      }, (option: FoodSegmentOption): string => option.id)
    }
    .width('100%')
    .padding(4)
    .backgroundColor($r('app.color.button_neutral_bg'))
    .borderRadius(this.counts.length > 0 ? 33 : 27)
    .onSizeChange((_oldSize: SizeOptions, next: SizeOptions) => {
      const availableWidth = Number(next.width) - 8;
      if (availableWidth > 0 && this.options.length > 0) {
        this.segmentWidth = availableWidth / this.options.length;
      }
    })
  }
}
