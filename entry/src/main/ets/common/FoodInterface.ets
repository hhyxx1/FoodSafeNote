import { BlurStrategy, HdsNavigationTitleBarStyle, TitleBarStyleOptions } from '@kit.UIDesignKit';

const FOOD_BAR_SURFACE: HdsNavigationTitleBarStyle = {
  backgroundStyle: { backgroundColor: $r('app.color.page_background') },
  contentStyle: {
    titleStyle: {
      mainTitleColor: $r('app.color.text_primary'),
      subTitleColor: $r('app.color.text_secondary')
    },
    backIconStyle: {
      backgroundColor: $r('app.color.button_secondary_bg'),
      iconColor: $r('app.color.accent_link')
    },
    menuStyle: {
      backgroundColor: $r('app.color.button_secondary_bg'),
      iconColor: $r('app.color.accent_link'),
      textColor: $r('app.color.button_secondary_text')
    }
  }
};

export const FOOD_TITLE_BAR_STYLE: TitleBarStyleOptions = {
  originalStyle: FOOD_BAR_SURFACE,
  scrollEffectStyle: FOOD_BAR_SURFACE,
  scrollEffectOpts: { enableScrollEffect: false },
  blurStrategy: BlurStrategy.DISABLE
};

export const FOOD_PRESS_EFFECT: ClickEffect = { level: ClickEffectLevel.LIGHT, scale: 0.97 };

export class FoodButtonStyle implements AttributeModifier<ButtonAttribute> {
  static readonly primary = new FoodButtonStyle($r('app.color.button_primary_bg'),
    $r('app.color.button_primary_text'));
  static readonly secondary = new FoodButtonStyle($r('app.color.button_secondary_bg'),
    $r('app.color.button_secondary_text'));
  static readonly neutral = new FoodButtonStyle($r('app.color.button_neutral_bg'),
    $r('app.color.button_neutral_text'));
  static readonly text = new FoodButtonStyle(Color.Transparent, $r('app.color.accent_link'));
  static readonly danger = new FoodButtonStyle($r('app.color.button_danger_bg'), $r('app.color.button_danger_text'));
  static readonly compactPrimary = new FoodButtonStyle($r('app.color.button_primary_bg'),
    $r('app.color.button_primary_text'), true);
  static readonly compactSecondary = new FoodButtonStyle($r('app.color.button_secondary_bg'),
    $r('app.color.button_secondary_text'), true);
  static readonly compactNeutral = new FoodButtonStyle($r('app.color.button_neutral_bg'),
    $r('app.color.button_neutral_text'), true);
  static readonly compactDanger = new FoodButtonStyle($r('app.color.button_danger_bg'),
    $r('app.color.button_danger_text'), true);
  static readonly dangerText = new FoodButtonStyle(Color.Transparent, $r('app.color.button_danger_text'));

  private readonly surfaceColor: ResourceColor;
  private readonly labelColor: ResourceColor;
  private readonly compact: boolean;

  private constructor(surfaceColor: ResourceColor, labelColor: ResourceColor, compact: boolean = false) {
    this.surfaceColor = surfaceColor;
    this.labelColor = labelColor;
    this.compact = compact;
  }

  applyNormalAttribute(button: ButtonAttribute): void {
    button.type(ButtonType.Capsule);
    button.constraintSize({ minWidth: 44, minHeight: this.compact ? 44 : 48 });
    button.padding({ left: this.compact ? 10 : 16, right: this.compact ? 10 : 16, top: 8, bottom: 8 });
    button.labelStyle({ maxLines: 2, overflow: TextOverflow.Ellipsis });
    button.fontSize(this.compact ? 14 : 15);
    button.fontWeight(FontWeight.Medium);
    button.fontColor(this.labelColor);
    button.backgroundColor(this.surfaceColor);
    button.clickEffect(FOOD_PRESS_EFFECT);
  }
}

export class FoodMotion {
  static reveal(): TransitionEffect {
    return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
      .animation({ duration: 180, curve: Curve.EaseOut });
  }

  static panel(): TransitionEffect {
    return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 24 }))
      .animation({ duration: 220, curve: Curve.EaseOut });
  }
}

@Component
export struct FoodMenuRow {
  @Prop title: ResourceStr = '';
  @Prop subtitle: ResourceStr = '';
  @Prop symbol: Resource = $r('sys.symbol.doc_text');
  onOpen: () => void = () => {};

  build() {
    Row({ space: 12 }) {
      Row() {
        SymbolGlyph(this.symbol)
          .fontSize(19)
          .fontColor([$r('app.color.accent_link')])
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.button_secondary_bg'))
      .borderRadius(12)

      Column({ space: 4 }) {
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_forward'))
        .fontSize(15)
        .fontColor([$r('app.color.text_hint')])
    }
    .width('100%')
    .constraintSize({ minHeight: 66 })
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .focusable(true)
    .hoverEffect(HoverEffect.Highlight)
    .clickEffect(FOOD_PRESS_EFFECT)
    .onClick(() => { this.onOpen(); })
  }
}

@Component
export struct FoodJournalMetric {
  @Prop label: ResourceStr = '';
  @Prop amount: string = '';

  build() {
    Column({ space: 5 }) {
      Text(this.label)
        .fontSize(13).fontColor($r('app.color.journal_hero_secondary'))
      Text(this.amount)
        .fontSize(29).lineHeight(36).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.journal_hero_text'))
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }
}
