import { localizedFoodLabel } from '../common/Constants';
import { FoodButtonStyle, FOOD_PRESS_EFFECT, FoodMotion } from '../common/FoodInterface';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { AppNavigation } from '../common/AppNavigation';
import { FoodItem, FamilyMember } from '../model/DataModels';
import { EXPIRED_WASTE_REASON, getStorageTypeName, WASTE_REASONS } from '../common/Constants';

interface FoodRouterParams {
  foodId: number;
}

interface EditFoodParams {
  editMode: boolean;
  foodId: number;
}

@Component
export struct InventoryView {
  @Prop @Watch('onRefreshKeyChange') refreshKey: number = 0;
  @Prop tabBarInset: number = 0;
  @State foodItems: FoodItem[] = [];
  @State filteredItems: FoodItem[] = [];
  @State isLoading: boolean = true;
  @State filterType: string = 'all';
  @State showActionPanel: boolean = false;
  @State selectedItem: FoodItem | null = null;
  @State members: FamilyMember[] = [];
  // 用@State存储计数，直接在UI中引用，避免通过@Builder参数传递断开绑定
  @State normalCount: number = 0;
  @State nearExpiryCount: number = 0;
  @State expiredCount: number = 0;
  aboutToAppear(): void {
    if (DatabaseHelper.getInstance().getStore() !== null) {
      this.loadFoodItems();
    }
  }

  onRefreshKeyChange(): void {
    this.loadFoodItems();
  }

  private loadFoodItems(): void {
    DatabaseHelper.getInstance().getActiveFoodItems().then((items: FoodItem[]) => {
      this.foodItems = items;
      this.updateCounts();
      this.applyFilter();
      this.isLoading = false;
    }).catch(() => {
      this.isLoading = false;
    });
    DatabaseHelper.getInstance().getAllMembers().then((members: FamilyMember[]) => {
      this.members = members;
    }).catch(() => {
      this.members = [];
    });
  }

  private updateCounts(): void {
    let normal: number = 0;
    let near: number = 0;
    let expired: number = 0;
    for (let i = 0; i < this.foodItems.length; i++) {
      if (this.foodItems[i].isExpired()) {
        expired++;
      } else if (this.foodItems[i].isNearExpiry()) {
        near++;
      } else {
        normal++;
      }
    }
    this.normalCount = normal;
    this.nearExpiryCount = near;
    this.expiredCount = expired;
  }

  private applyFilter(): void {
    if (this.filterType === 'all') {
      const normal: FoodItem[] = [];
      const expired: FoodItem[] = [];
      for (let i = 0; i < this.foodItems.length; i++) {
        if (this.foodItems[i].isExpired()) {
          expired.push(this.foodItems[i]);
        } else {
          normal.push(this.foodItems[i]);
        }
      }
      const merged: FoodItem[] = [];
      for (let i = 0; i < normal.length; i++) { merged.push(normal[i]); }
      for (let i = 0; i < expired.length; i++) { merged.push(expired[i]); }
      this.filteredItems = merged;
    } else if (this.filterType === 'normal') {
      const result: FoodItem[] = [];
      for (let i = 0; i < this.foodItems.length; i++) {
        if (!this.foodItems[i].isExpired() && !this.foodItems[i].isNearExpiry()) result.push(this.foodItems[i]);
      }
      this.filteredItems = result;
    } else if (this.filterType === 'nearExpiry') {
      const result: FoodItem[] = [];
      for (let i = 0; i < this.foodItems.length; i++) {
        if (this.foodItems[i].isNearExpiry() && !this.foodItems[i].isExpired()) result.push(this.foodItems[i]);
      }
      this.filteredItems = result;
    } else if (this.filterType === 'expired') {
      const result: FoodItem[] = [];
      for (let i = 0; i < this.foodItems.length; i++) {
        if (this.foodItems[i].isExpired()) result.push(this.foodItems[i]);
      }
      this.filteredItems = result;
    }
  }

  private getExpiryText(item: FoodItem): ResourceStr {
    if (item.expiryDate <= 0) return $r('app.string.ui_expiry_date_not_set');
    const days: number = item.getRemainingDays();
    if (days < 0) return $r('app.string.ui_expired_d_days_ago', Math.abs(days));
    if (days === 0) return $r('app.string.watch_expire_today');
    return $r('app.string.ui_expires_in_d_days', days);
  }

  private handleEat(item: FoodItem, memberName: string): void {
    DatabaseHelper.getInstance().consumeFood(item.id, memberName, item.calories, item.name).then(() => {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_recorded_as_eaten_by_s', memberName), duration: 1500 });
      this.showActionPanel = false;
      this.loadFoodItems();
    }).catch(() => {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.ui_could_not_save_the_record_refresh_your_inventory_and_try_again'),
        duration: 2000
      });
    });
  }

  private handleWaste(item: FoodItem, reason: string): void {
    DatabaseHelper.getInstance().wasteFood(item.id, reason, item.calories, item.name).then(() => {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_discard_recorded'), duration: 1500 });
      this.showActionPanel = false;
      this.loadFoodItems();
    }).catch(() => {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.ui_could_not_save_the_record_refresh_your_inventory_and_try_again'),
        duration: 2000
      });
    });
  }

  private isWasteReasonDisabled(reason: string): boolean {
    if (this.selectedItem === null) {
      return false;
    }
    if (!this.selectedItem.isExpired()) {
      return false;
    }
    return reason !== EXPIRED_WASTE_REASON;
  }

  private selectInventoryFilter(filter: string): void {
    if (filter === this.filterType) return;
    this.getUIContext().animateTo({ duration: 170, curve: Curve.EaseOut }, () => {
      this.filterType = filter;
      this.applyFilter();
    });
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: 14 }) {
        Row({ space: 12 }) {
          Column({ space: 5 }) {
            Text($r('app.string.ui_food_inventory'))
              .fontSize(29).lineHeight(36).fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text($r('app.string.inventory_count', this.foodItems.length))
              .fontSize(14).fontColor($r('app.color.text_secondary'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(17).fontColor([$r('app.color.button_primary_text')])
              Text($r('app.string.ui_add_food'))
                .fontSize(14).fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.button_primary_text'))
            }
          }
          .attributeModifier(FoodButtonStyle.compactPrimary)
          .accessibilityText($r('app.string.ui_add_food'))
          .onClick(() => { AppNavigation.push('EntrySelectionPage'); })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 14 })

        Row({ space: 2 }) {
          this.inventoryFilter($r('app.string.ui_all'), this.foodItems.length, 'all')
          this.inventoryFilter($r('app.string.status_normal'), this.normalCount, 'normal')
          this.inventoryFilter($r('app.string.status_near_expiry'), this.nearExpiryCount, 'nearExpiry')
          this.inventoryFilter($r('app.string.status_expired'), this.expiredCount, 'expired')
        }
        .width('100%')
        .padding({ left: 20, right: 20 })

        if (this.isLoading) {
          LoadingProgress()
            .width(30).height(30).color($r('app.color.accent_link'))
            .margin({ top: 24 })
          Blank()
        } else {
          List() {
            if (this.filteredItems.length === 0) {
              ListItem() {
                this.buildEmptyState()
              }
            } else {
              ForEach(this.filteredItems, (item: FoodItem) => {
                ListItem() {
                  this.buildFoodCard(item)
                }
              }, (item: FoodItem) => item.id.toString())
            }
          }
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 20, right: 20 })
          .divider({ strokeWidth: 1, color: $r('app.color.divider') })
          .contentEndOffset(this.tabBarInset)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      // 长按操作面板遮罩
      if (this.showActionPanel && this.selectedItem !== null) {
        Column() {
          Column()
            .width('100%')
            .layoutWeight(1)
            .onClick(() => { this.showActionPanel = false; })
          Column({ space: 12 }) {
            Text(this.selectedItem !== null ? this.selectedItem.name : '')
              .fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')

            if (this.selectedItem !== null && !this.selectedItem.isExpired()) {
              Text($r('app.string.ui_who_ate_this')).fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.members, (member: FamilyMember) => {
                  Button(member.name)
                    .attributeModifier(FoodButtonStyle.compactSecondary)
                    .margin({ right: 8, bottom: 8 })
                    .onClick(() => {
                      if (this.selectedItem !== null) {
                        this.handleEat(this.selectedItem, member.name);
                      }
                    })
                }, (member: FamilyMember) => member.id.toString())
              }
              if (this.members.length === 0) {
                Text($r('app.string.ui_add_a_family_member_in_profile_first'))
                  .fontSize(12).fontColor($r('app.color.text_hint'))
              }
            }

            Divider().color($r('app.color.divider'))

            Text($r('app.string.ui_reason_for_discarding')).fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
            Row({ space: 8 }) {
              ForEach(WASTE_REASONS, (reason: string) => {
                Button(localizedFoodLabel(reason))
                  .attributeModifier(FoodButtonStyle.compactNeutral)
                  .enabled(!this.isWasteReasonDisabled(reason))
                  .onClick(() => {
                    if (!this.isWasteReasonDisabled(reason) && this.selectedItem !== null) {
                      this.handleWaste(this.selectedItem, reason);
                    }
                  })
              }, (reason: string) => reason)
            }

            Divider().color($r('app.color.divider'))

            Button($r('app.string.ui_edit'))
              .attributeModifier(FoodButtonStyle.secondary)
              .width('100%')
              .onClick(() => {
                this.showActionPanel = false;
                if (this.selectedItem !== null) {
                  const params: EditFoodParams = { editMode: true, foodId: this.selectedItem.id };
                  AppNavigation.push('AddFoodPage', params);
                }
              })
          }
          .width('100%').padding(16)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(20)
          .margin({ left: 12, right: 12, bottom: this.tabBarInset })
          .transition(FoodMotion.panel())
        }
        .width('100%').height('100%')
        .backgroundColor($r('app.color.overlay_background'))
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  inventoryFilter(label: ResourceStr, count: number, filter: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(13).fontWeight(FontWeight.Medium)
        .fontColor(this.filterType === filter ? $r('app.color.accent_link') : $r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
      Text(count.toString())
        .fontSize(17).fontWeight(FontWeight.Bold)
        .fontColor(this.filterType === filter ? $r('app.color.accent_link') : $r('app.color.text_primary'))
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: 56 })
    .padding({ top: 7, bottom: 7 })
    .borderRadius(12)
    .backgroundColor(this.filterType === filter ? $r('app.color.button_secondary_bg') : Color.Transparent)
    .accessibilitySelected(this.filterType === filter)
    .focusable(true)
    .clickEffect(FOOD_PRESS_EFFECT)
    .onClick(() => { this.selectInventoryFilter(filter); })
  }

  @Builder
  buildFoodCard(item: FoodItem) {
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Text(item.name)
          .fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })

        Flex({ wrap: FlexWrap.Wrap }) {
          if (item.category.length > 0) {
            Text(localizedFoodLabel(item.category)).fontSize(13).fontColor($r('app.color.text_secondary'))
              .margin({ right: 8 })
          }
          Text(getStorageTypeName(item.storageType)).fontSize(13).fontColor($r('app.color.text_secondary'))
            .margin({ right: 8 })
          if (item.spec.length > 0) {
            Text(item.spec).fontSize(13).fontColor($r('app.color.text_secondary'))
              .margin({ right: 8 })
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (item.calories > 0) {
            Text($r('app.string.ui_this_item_s_kcal', item.calories.toFixed(0)))
              .fontSize(13).fontColor($r('app.color.text_secondary'))
          }
        }
        .width('100%')

        Text(this.getExpiryText(item)).fontSize(13).fontColor(item.getStatusColor())
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(item.getStatusText())
        .fontSize(12).fontWeight(FontWeight.Medium)
        .fontColor(item.getStatusColor())
        .padding({ left: 9, right: 9, top: 5, bottom: 5 })
        .borderRadius(10)
        .backgroundColor(item.getStatusBgColor())

      SymbolGlyph($r('sys.symbol.chevron_forward'))
        .fontSize(14).fontColor([$r('app.color.text_hint')])
    }
    .width('100%')
    .padding({ top: 13, bottom: 13, left: 2, right: 2 })
    .constraintSize({ minHeight: 74 })
    .focusable(true)
    .hoverEffect(HoverEffect.Highlight)
    .clickEffect(FOOD_PRESS_EFFECT)
    .onClick(() => {
      const params: FoodRouterParams = { foodId: item.id };
      AppNavigation.push('FoodDetailPage', params);
    })
    .gesture(LongPressGesture({ repeat: false }).onAction(() => {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.selectedItem = item;
        this.showActionPanel = true;
      });
    }))
  }

  @Builder
  buildEmptyState() {
    Column({ space: 10 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.archivebox'))
          .fontSize(36).fontColor([$r('app.color.accent_link')])
      }
      .width(64).height(64).justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.button_secondary_bg')).borderRadius(18)

      Text(this.foodItems.length === 0 ? $r('app.string.ui_your_inventory_is_empty') :
        $r('app.string.inventory_filtered_empty'))
        .fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))

      if (this.foodItems.length === 0) {
        Text($r('app.string.inventory_empty_description'))
          .fontSize(14).fontColor($r('app.color.text_secondary'))
      } else {
        Button($r('app.string.ui_all'))
          .attributeModifier(FoodButtonStyle.compactSecondary)
          .onClick(() => { this.selectInventoryFilter('all'); })
      }
    }
    .width('100%')
    .padding(22)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(22)
    .transition(FoodMotion.reveal())
  }
}
