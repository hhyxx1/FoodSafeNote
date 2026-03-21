import { router, promptAction } from '@kit.ArkUI';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { FoodItem, FamilyMember } from '../model/DataModels';
import { EXPIRED_WASTE_REASON, formatTimestamp, getStorageTypeName, WASTE_REASONS } from '../common/Constants';

interface FoodDetailParams {
  foodId: number;
}

interface EditFoodParams {
  editMode: boolean;
  foodId: number;
}

@Entry
@Component
struct FoodDetailPage {
  @State foodItem: FoodItem | null = null;
  @State isLoading: boolean = true;
  @State showEatPanel: boolean = false;
  @State showWastePanel: boolean = false;
  @State members: FamilyMember[] = [];
  private foodId: number = 0;

  aboutToAppear(): void {
    const params: FoodDetailParams = router.getParams() as FoodDetailParams;
    if (params !== null && params !== undefined) {
      this.foodId = params.foodId;
      this.loadData();
    }
  }

  onPageShow(): void {
    if (this.foodId > 0) {
      this.loadData();
    }
  }

  private loadData(): void {
    DatabaseHelper.getInstance().getFoodItemById(this.foodId).then((item: FoodItem | null) => {
      this.foodItem = item;
      this.isLoading = false;
    });
    DatabaseHelper.getInstance().getAllMembers().then((members: FamilyMember[]) => {
      this.members = members;
    });
  }

  private getExpiryText(): string {
    if (this.foodItem === null) return '';
    if (this.foodItem.expiryDate <= 0) return '未设置保质期';
    const days: number = this.foodItem.getRemainingDays();
    if (days < 0) return '已过期 ' + Math.abs(days) + ' 天';
    if (days === 0) return '今天到期';
    return '剩余 ' + days + ' 天';
  }

  private handleEat(memberName: string): void {
    if (this.foodItem === null) return;
    DatabaseHelper.getInstance().consumeFood(this.foodItem.id, memberName, this.foodItem.calories, this.foodItem.name).then(() => {
      promptAction.showToast({ message: '已记录 ' + memberName + ' 食用', duration: 1500 });
      router.back();
    });
  }

  private handleWaste(reason: string): void {
    if (this.foodItem === null) return;
    DatabaseHelper.getInstance().wasteFood(this.foodItem.id, reason, this.foodItem.calories, this.foodItem.name).then(() => {
      promptAction.showToast({ message: '已记录丢弃', duration: 1500 });
      router.back();
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

  private handleDelete(): void {
    promptAction.showDialog({
      title: '确认删除',
      message: '确定要删除 "' + (this.foodItem !== null ? this.foodItem.name : '') + '" 吗？此操作不可恢复。',
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '删除', color: '#FF3B30' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        DatabaseHelper.getInstance().deleteFoodItem(this.foodId).then(() => {
          promptAction.showToast({ message: '已删除', duration: 1500 });
          router.back();
        });
      }
    });
  }

  private handleEdit(): void {
    const params: EditFoodParams = { editMode: true, foodId: this.foodId };
    router.pushUrl({ url: 'pages/AddFoodPage', params: params });
  }

  build() {
    Column() {
      // 导航栏
      Row() {
        Button('返回')
          .height(36).fontSize(14).fontColor('#007DFF')
          .backgroundColor(Color.Transparent)
          .onClick(() => { router.back(); })
        Text('食品详情')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          .layoutWeight(1).textAlign(TextAlign.Center)
        if (this.foodItem !== null && this.foodItem.status === 0) {
          Button('编辑')
            .height(36).fontSize(14).fontColor('#007DFF')
            .backgroundColor(Color.Transparent)
            .onClick(() => { this.handleEdit(); })
        } else {
          Text('').width(56)
        }
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))

      if (this.foodItem !== null) {
        Scroll() {
          Column({ space: 16 }) {
            // 信息卡片
            this.buildInfoCard()

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

            // 删除
            Button('删除此食品')
              .width('100%').height(44).fontSize(14)
              .fontColor('#FF3B30').backgroundColor('#FFEDE9').borderRadius(12)
              .margin({ left: 16, right: 16, top: 16, bottom: 32 })
              .onClick(() => { this.handleDelete(); })
          }
          .padding({ top: 16 })
        }
        .layoutWeight(1).scrollBar(BarState.Off)
      } else if (this.isLoading) {
        Column() {
          LoadingProgress().width(40).height(40)
          Text('加载中...').fontSize(14).fontColor($r('app.color.text_hint')).margin({ top: 12 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Text('食品不存在').fontSize(16).fontColor($r('app.color.text_hint'))
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }

  @Builder
  buildInfoCard() {
    if (this.foodItem !== null) {
      Column({ space: 12 }) {
        Row() {
          Text(this.foodItem.name)
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).layoutWeight(1)
          Text(this.foodItem.getStatusText())
            .fontSize(12).fontColor(this.foodItem.getStatusColor())
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(12).backgroundColor(this.foodItem.getStatusBgColor())
        }
        .width('100%')

        if (this.foodItem.category.length > 0 || this.foodItem.spec.length > 0) {
          Row({ space: 12 }) {
            if (this.foodItem.category.length > 0) {
              this.buildInfoTag(this.foodItem.category)
            }
            if (this.foodItem.spec.length > 0) {
              this.buildInfoTag(this.foodItem.spec)
            }
          }
        }

        Divider().color('#F0F0F0')

        if (this.foodItem.barcode.length > 0) {
          this.buildInfoRow('条码', this.foodItem.barcode)
        }
        this.buildInfoRow('存储方式', getStorageTypeName(this.foodItem.storageType))
        this.buildInfoRow('到期日期',
          this.foodItem.expiryDate > 0 ? formatTimestamp(this.foodItem.expiryDate) : '未设置')
        this.buildInfoRow('保质期状态', this.getExpiryText())
        this.buildInfoRow('本次热量',
          this.foodItem.calories > 0 ? this.foodItem.calories.toFixed(0) + ' kcal' : '未记录')
        this.buildInfoRow('入库时间',
          this.foodItem.createTime > 0 ? formatTimestamp(this.foodItem.createTime) : '未知')

        if (this.foodItem.status === 1) {
          Divider().color('#F0F0F0')
          this.buildInfoRow('食用者', this.foodItem.consumedBy)
          this.buildInfoRow('食用时间', formatTimestamp(this.foodItem.consumeTime))
        }
        if (this.foodItem.status === 2) {
          Divider().color('#F0F0F0')
          this.buildInfoRow('丢弃原因', this.foodItem.wasteReason)
          this.buildInfoRow('丢弃时间', formatTimestamp(this.foodItem.consumeTime))
        }
      }
      .width('100%').padding(16).margin({ left: 16, right: 16 })
      .backgroundColor($r('app.color.card_background')).borderRadius(16)
    }
  }

  @Builder
  buildInfoTag(text: string) {
    Text(text).fontSize(12).fontColor($r('app.color.text_secondary'))
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .borderRadius(12).backgroundColor($r('app.color.input_background'))
  }

  @Builder
  buildInfoRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor($r('app.color.text_secondary')).width(80)
      Text(value).fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1).textAlign(TextAlign.End)
    }
    .width('100%').padding({ top: 6, bottom: 6 })
  }

  @Builder
  buildActionButtons() {
    Row({ space: 12 }) {
      if (this.foodItem !== null && !this.foodItem.isExpired()) {
        Button('🍽️ 吃掉')
          .layoutWeight(1).height(48).fontSize(15)
          .fontColor(Color.White).backgroundColor('#34C759').borderRadius(12)
          .onClick(() => {
            this.showEatPanel = !this.showEatPanel;
            this.showWastePanel = false;
          })
      } else {
        Button('已过期，不可食用')
          .layoutWeight(1).height(48).fontSize(14)
          .fontColor($r('app.color.text_hint')).backgroundColor($r('app.color.chip_background')).borderRadius(12).enabled(false)
      }
      Button('🗑️ 扔掉')
        .layoutWeight(1).height(48).fontSize(15)
        .fontColor(Color.White).backgroundColor('#FF6B00').borderRadius(12)
        .onClick(() => {
          this.showWastePanel = !this.showWastePanel;
          this.showEatPanel = false;
        })
    }
    .width('100%').padding({ left: 16, right: 16 })
  }

  @Builder
  buildEatPanel() {
    Column({ space: 12 }) {
      Text('选择食用者').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      if (this.members.length === 0) {
        Text('请先在"我的"页面添加家庭成员').fontSize(13).fontColor($r('app.color.text_hint'))
          .width('100%').textAlign(TextAlign.Center).padding({ top: 12, bottom: 12 })
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.members, (member: FamilyMember) => {
            Column({ space: 4 }) {
              Text(member.name.substring(0, 1))
                .fontSize(18).fontWeight(FontWeight.Bold).fontColor(Color.White)
                .textAlign(TextAlign.Center).width(48).height(48).borderRadius(24)
                .backgroundColor('#007DFF')
              Text(member.name).fontSize(12).fontColor($r('app.color.text_primary'))
            }
            .alignItems(HorizontalAlign.Center)
            .padding(8).margin({ right: 8, bottom: 8 })
            .borderRadius(12).backgroundColor($r('app.color.input_background'))
            .onClick(() => { this.handleEat(member.name); })
          }, (member: FamilyMember) => member.id.toString())
        }
        .width('100%')
      }
    }
    .width('100%').padding(16).margin({ left: 16, right: 16 })
    .backgroundColor($r('app.color.card_background')).borderRadius(16)
  }

  @Builder
  buildWastePanel() {
    Column({ space: 12 }) {
      Text('选择丢弃原因').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(WASTE_REASONS, (reason: string) => {
          Text(reason)
            .fontSize(14)
            .fontColor(this.isWasteReasonDisabled(reason) ? $r('app.color.text_disabled') : '#FF6B00')
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .margin({ right: 8, bottom: 8 })
            .borderRadius(8)
            .backgroundColor(this.isWasteReasonDisabled(reason) ? $r('app.color.chip_background') : '#FFF3E0')
            .opacity(this.isWasteReasonDisabled(reason) ? 0.65 : 1)
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
  }
}
