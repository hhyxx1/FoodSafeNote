import { FoodButtonStyle, FOOD_PRESS_EFFECT, FoodMotion, FOOD_TITLE_BAR_STYLE } from '../common/FoodInterface';
import { localizedFoodLabel } from '../common/Constants';
import { promptAction } from '@kit.ArkUI';
import { HdsNavDestination, HdsNavigationBadgeIconOptions, TextStyleMode } from '@kit.UIDesignKit';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { AppNavigation } from '../common/AppNavigation';
import { FoodItem, FamilyMember } from '../model/DataModels';
import { EXPIRED_WASTE_REASON, formatTimestamp, getStorageTypeName, WASTE_REASONS } from '../common/Constants';

interface FoodDetailParams {
  foodId: number;
}

interface EditFoodParams {
  editMode: boolean;
  foodId: number;
}

@Component
struct FoodDetailPage {
  @StorageLink('foodDetailRefreshVersion') @Watch('onFoodDetailRefreshVersionChanged') foodDetailRefreshVersion: number = 0;
  @StorageProp('dataChangeTick') @Watch('onDataChangeTick') dataChangeTick: number = 0;
  @State foodItem: FoodItem | null = null;
  @State isLoading: boolean = true;
  @State isChangingFood: boolean = false;
  @State showEatPanel: boolean = false;
  @State showWastePanel: boolean = false;
  @State members: FamilyMember[] = [];
  private foodId: number = 0;
  private scroller: Scroller = new Scroller();
  // 状态栏高度（vp），由 Index 写入 AppStorage；用于标题栏沉浸避让
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  aboutToAppear(): void {
    const params: FoodDetailParams | undefined = AppNavigation.getParamByName('FoodDetailPage') as FoodDetailParams | undefined;
    if (params !== null && params !== undefined) {
      this.foodId = params.foodId;
      this.loadData();
    } else {
      this.isLoading = false;
    }
  }

  // 从编辑页返回（含系统侧滑）后刷新数据，等价于原 onPageShow
  private onDataChangeTick(): void {
    if (this.foodId > 0) {
      this.loadData();
    }
  }

  private onFoodDetailRefreshVersionChanged(): void {
    const refreshedFoodId: number | undefined = AppStorage.get<number>('foodDetailRefreshFoodId');
    if (this.foodId > 0 && refreshedFoodId !== undefined && refreshedFoodId === this.foodId) {
      this.loadData();
    }
  }

  private loadData(): void {
    DatabaseHelper.getInstance().getFoodItemById(this.foodId).then((item: FoodItem | null) => {
      this.foodItem = item;
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

  private getExpiryText(): ResourceStr {
    if (this.foodItem === null) return '';
    if (this.foodItem.expiryDate <= 0) return $r('app.string.ui_expiry_date_not_set');
    const days: number = this.foodItem.getRemainingDays();
    if (days < 0) return $r('app.string.ui_expired_d_days_ago', Math.abs(days));
    if (days === 0) return $r('app.string.watch_expire_today');
    return $r('app.string.ui_expires_in_d_days', days);
  }

  private handleEat(memberName: string): void {
    if (this.foodItem === null || this.isChangingFood) return;
    this.isChangingFood = true;
    DatabaseHelper.getInstance().consumeFood(this.foodItem.id, memberName, this.foodItem.calories, this.foodItem.name).then(() => {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_recorded_as_eaten_by_s', memberName), duration: 1500 });
      AppNavigation.pop();
    }).catch(() => {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.ui_could_not_save_the_record_refresh_your_inventory_and_try_again'),
        duration: 2000
      });
    }).finally(() => {
      this.isChangingFood = false;
    });
  }

  private handleWaste(reason: string): void {
    if (this.foodItem === null || this.isChangingFood) return;
    this.isChangingFood = true;
    DatabaseHelper.getInstance().wasteFood(this.foodItem.id, reason, this.foodItem.calories, this.foodItem.name).then(() => {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_discard_recorded'), duration: 1500 });
      AppNavigation.pop();
    }).catch(() => {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.ui_could_not_save_the_record_refresh_your_inventory_and_try_again'),
        duration: 2000
      });
    }).finally(() => {
      this.isChangingFood = false;
    });
  }

  private isWasteReasonDisabled(reason: string): boolean {
    if (this.foodItem === null) {
      return false;
    }
    if (!this.foodItem.isExpired()) {
      return false;
    }
    return reason !== EXPIRED_WASTE_REASON;
  }

  private async handleDelete(): Promise<void> {
    if (this.isChangingFood || this.foodItem === null) return;
    this.isChangingFood = true;
    try {
      const result: promptAction.ShowDialogSuccessResponse = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.ui_confirm_deletion'),
        message: $r('app.string.ui_delete_s_this_cannot_be_undone', this.foodItem.name),
        buttons: [
          { text: $r('app.string.ui_cancel'), color: '#6B7280' },
          { text: $r('app.string.ui_delete'), color: '#B42318' }
        ]
      });
      if (result.index !== 1) return;
      if (!await DatabaseHelper.getInstance().deleteFoodItem(this.foodId)) {
        throw new Error('Food item was not deleted');
      }
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_deleted'), duration: 1500 });
      AppNavigation.pop();
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.ui_could_not_save_try_again') });
    } finally {
      this.isChangingFood = false;
    }
  }

  private handleEdit(): void {
    if (this.isChangingFood) return;
    const params: EditFoodParams = { editMode: true, foodId: this.foodId };
    AppNavigation.push('AddFoodPage', params);
  }

  // 标题栏右侧菜单：仅未入库消耗的食品显示"编辑"
  private getMenuItems(): Array<HdsNavigationBadgeIconOptions> {
    if (this.foodItem === null || this.foodItem.status !== 0) {
      return [];
    }
    const item: HdsNavigationBadgeIconOptions = {
      content: { type: TextStyleMode.NORMAL, componentId: 'edit-food', isEnabled: !this.isChangingFood, label: $r('app.string.ui_edit'), action: () => { this.handleEdit(); } }
    };
    return [item];
  }

  build() {
    HdsNavDestination() {
      Column() {
        if (this.foodItem !== null) {
        Scroll(this.scroller) {
          Column({ space: 16 }) {
            this.buildFoodSummary()

            // 操作区
            if (this.foodItem !== null && this.foodItem.status === 0) {
              this.buildActionButtons()
            }

            // 吃掉面板
            if (this.showEatPanel) {
              this.buildEatPanel()
            }

            // 扔掉面板
            if (this.showWastePanel) {
              this.buildWastePanel()
            }

            this.buildInfoCard()

            Button($r('app.string.ui_delete_this_item'))
              .attributeModifier(FoodButtonStyle.dangerText)
              .width('100%')
              .margin({ left: 16, right: 16, top: 16, bottom: 32 })
              .onClick(() => { this.handleDelete(); })
          }
          // 标题栏沉浸避让：状态栏高度 + 标题栏高度(56vp)
          .padding({ top: 56 + this.statusBarHeight })
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .layoutWeight(1).scrollBar(BarState.Off)
      } else if (this.isLoading) {
        Column() {
          LoadingProgress().width(40).height(40)
          Text($r('app.string.ui_loading')).fontSize(14).fontColor($r('app.color.text_hint')).margin({ top: 12 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Text($r('app.string.ui_food_item_not_found')).fontSize(16).fontColor($r('app.color.text_hint'))
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      content: {
        title: { mainTitle: $r('app.string.ui_food_details') },
        menu: { value: this.getMenuItems() }
      },
      style: FOOD_TITLE_BAR_STYLE
    })
    .bindToScrollable([this.scroller])
    .onBackPressed(() => this.isChangingFood)
    .onHidden(() => {
      // 返回主页后通知刷新，等价于原 Index.onPageShow 的 refreshKey++
      AppNavigation.notifyDataChanged();
    })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  buildFoodSummary() {
    if (this.foodItem !== null) {
      Column({ space: 12 }) {
        Row({ space: 12 }) {
          Text(this.foodItem.name)
            .fontSize(28).lineHeight(34).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.journal_hero_text')).layoutWeight(1)
          Text(this.foodItem.getStatusText())
            .fontSize(13).fontWeight(FontWeight.Medium)
            .fontColor(this.foodItem.getStatusColor())
            .padding({ left: 9, right: 9, top: 5, bottom: 5 })
            .borderRadius(10).backgroundColor(this.foodItem.getStatusBgColor())
        }.width('100%')
        Text(this.getExpiryText())
          .fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.journal_hero_secondary'))
        Text(getStorageTypeName(this.foodItem.storageType))
          .fontSize(14).fontColor($r('app.color.journal_hero_secondary'))
      }
      .width('100%').alignItems(HorizontalAlign.Start)
      .padding(18).margin({ left: 16, right: 16, top: 8 })
      .backgroundColor($r('app.color.journal_hero_bg')).borderRadius(22)
    }
  }

  @Builder
  buildInfoCard() {
    if (this.foodItem !== null) {
      Column({ space: 8 }) {
        Text($r('app.string.ui_food_information'))
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
          .padding({ bottom: 4 })

        if (this.foodItem.category.length > 0) {
          this.buildInfoRow($r('app.string.ui_food_category'), localizedFoodLabel(this.foodItem.category))
        }
        if (this.foodItem.spec.length > 0) {
          this.buildInfoRow($r('app.string.ui_package_details_optional'), this.foodItem.spec)
        }
        if (this.foodItem.barcode.length > 0) {
          this.buildInfoRow($r('app.string.ui_barcode'), this.foodItem.barcode)
        }
        this.buildInfoRow($r('app.string.ui_expiry_date'),
          this.foodItem.expiryDate > 0 ? formatTimestamp(this.foodItem.expiryDate) : $r('app.string.watch_not_set'))
        this.buildInfoRow($r('app.string.ui_calories_for_this_item'),
          this.foodItem.calories > 0 ? this.foodItem.calories.toFixed(0) + ' kcal' : $r('app.string.ui_not_recorded'))
        this.buildInfoRow($r('app.string.ui_added_on'),
          this.foodItem.createTime > 0 ? formatTimestamp(this.foodItem.createTime) : $r('app.string.ui_unknown'))

        if (this.foodItem.status === 1) {
          Divider().color($r('app.color.divider'))
          this.buildInfoRow($r('app.string.ui_eaten_by'), this.foodItem.consumedBy)
          this.buildInfoRow($r('app.string.ui_eaten_on'), formatTimestamp(this.foodItem.consumeTime))
        }
        if (this.foodItem.status === 2) {
          Divider().color($r('app.color.divider'))
          this.buildInfoRow($r('app.string.ui_reason_for_discarding'), localizedFoodLabel(this.foodItem.wasteReason))
          this.buildInfoRow($r('app.string.ui_discarded_on'), formatTimestamp(this.foodItem.consumeTime))
        }
      }
      .width('100%').padding(16).margin({ left: 16, right: 16 })
      .backgroundColor($r('app.color.card_background')).borderRadius(16)
    }
  }

  @Builder
  buildInfoRow(label: ResourceStr, value: ResourceStr) {
    Row() {
      Text(label).fontSize(14).fontColor($r('app.color.text_secondary')).width(80)
      Text(value).fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1).textAlign(TextAlign.End)
    }
    .width('100%').padding({ top: 6, bottom: 6 })
  }

  private toggleFoodAction(eat: boolean): void {
    if (this.isChangingFood) return;
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.showEatPanel = eat && !this.showEatPanel;
      this.showWastePanel = !eat && !this.showWastePanel;
    });
  }

  @Builder
  buildActionButtons() {
    Row({ space: 10 }) {
      if (this.foodItem !== null && !this.foodItem.isExpired()) {
        Button($r('app.string.ui_mark_as_eaten'))
          .attributeModifier(FoodButtonStyle.primary)
          .layoutWeight(1)
          .enabled(!this.isChangingFood)
          .onClick(() => { this.toggleFoodAction(true); })
      } else {
        Text($r('app.string.ui_expired_do_not_eat'))
          .layoutWeight(1).fontSize(14).fontColor($r('app.color.status_danger'))
      }
      Button($r('app.string.ui_discard'))
        .attributeModifier(FoodButtonStyle.danger)
        .layoutWeight(1)
        .enabled(!this.isChangingFood)
        .onClick(() => { this.toggleFoodAction(false); })
    }
    .width('100%').padding({ left: 16, right: 16 })
  }

  @Builder
  buildEatPanel() {
    Column({ space: 12 }) {
      Text($r('app.string.ui_who_ate_this')).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      if (this.members.length === 0) {
        Text($r('app.string.ui_add_a_family_member_in_profile_first')).fontSize(13).fontColor($r('app.color.text_hint'))
          .width('100%').textAlign(TextAlign.Center).padding({ top: 12, bottom: 12 })
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.members, (member: FamilyMember) => {
            Column({ space: 4 }) {
              Text(member.name.substring(0, 1))
                .fontSize(18).fontWeight(FontWeight.Bold).fontColor(Color.White)
                .textAlign(TextAlign.Center).width(48).height(48).borderRadius(24)
                .backgroundColor($r('app.color.button_primary_bg'))
              Text(member.name).fontSize(12).fontColor($r('app.color.text_primary'))
            }
            .alignItems(HorizontalAlign.Center)
            .padding(8).margin({ right: 8, bottom: 8 })
            .borderRadius(12).backgroundColor($r('app.color.input_background'))
            .clickEffect(FOOD_PRESS_EFFECT)
            .onClick(() => { this.handleEat(member.name); })
          }, (member: FamilyMember) => member.id.toString())
        }
        .width('100%')
      }
    }
    .width('100%').padding(16).margin({ left: 16, right: 16 })
    .backgroundColor($r('app.color.card_background')).borderRadius(16)
    .transition(FoodMotion.reveal())
  }

  @Builder
  buildWastePanel() {
    Column({ space: 12 }) {
      Text($r('app.string.ui_choose_a_reason')).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(WASTE_REASONS, (reason: string) => {
          Text(localizedFoodLabel(reason))
            .fontSize(14)
            .fontColor(this.isWasteReasonDisabled(reason) ? $r('app.color.text_disabled') : $r('app.color.chip_warning_text'))
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .margin({ right: 8, bottom: 8 })
            .borderRadius(8)
            .backgroundColor(this.isWasteReasonDisabled(reason) ? $r('app.color.chip_background') : $r('app.color.chip_warning_bg'))
            .enabled(!this.isWasteReasonDisabled(reason) && !this.isChangingFood)
            .clickEffect(FOOD_PRESS_EFFECT)
            .onClick(() => {
              if (!this.isWasteReasonDisabled(reason)) {
                this.handleWaste(reason);
              }
            })
        }, (reason: string) => reason)
      }
      .width('100%')
    }
    .width('100%').padding(16).margin({ left: 16, right: 16 })
    .backgroundColor($r('app.color.card_background')).borderRadius(16)
    .transition(FoodMotion.reveal())
  }
}

// Navigation 系统路由表入口（router_map.json 中注册为 FoodDetailPage）
@Builder
export function FoodDetailPageBuilder() {
  FoodDetailPage()
}