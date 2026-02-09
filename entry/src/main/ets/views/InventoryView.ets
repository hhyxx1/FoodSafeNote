import { router, promptAction } from '@kit.ArkUI';
import { DatabaseHelper } from '../common/DatabaseHelper';
import { FoodItem, FamilyMember } from '../model/DataModels';
import { getStorageTypeName, WASTE_REASONS } from '../common/Constants';

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
    });
    DatabaseHelper.getInstance().getAllMembers().then((members: FamilyMember[]) => {
      this.members = members;
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

  private getExpiryText(item: FoodItem): string {
    if (item.expiryDate <= 0) return '未设置保质期';
    const days: number = item.getRemainingDays();
    if (days < 0) return '已过期 ' + Math.abs(days) + ' 天';
    if (days === 0) return '今天到期';
    return '剩余 ' + days + ' 天';
  }

  private handleEat(item: FoodItem, memberName: string): void {
    DatabaseHelper.getInstance().consumeFood(item.id, memberName, item.calories, item.name).then(() => {
      promptAction.showToast({ message: '已记录 ' + memberName + ' 食用', duration: 1500 });
      this.showActionPanel = false;
      this.loadFoodItems();
    });
  }

  private handleWaste(item: FoodItem, reason: string): void {
    DatabaseHelper.getInstance().wasteFood(item.id, reason, item.calories, item.name).then(() => {
      promptAction.showToast({ message: '已记录丢弃', duration: 1500 });
      this.showActionPanel = false;
      this.loadFoodItems();
    });
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // 顶部标题栏
        Row() {
          Text('食品库存')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(this.foodItems.length + ' 件')
            .fontSize(14)
            .fontColor($r('app.color.text_hint'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        // 筛选chip栏 - 直接引用@State计数变量，不通过builder参数传递
        Row({ space: 8 }) {
          // 全部
          Row({ space: 4 }) {
            Circle().width(8).height(8)
              .fill(this.filterType === 'all' ? '#007DFF' : $r('app.color.text_disabled'))
            Text('全部 ' + this.foodItems.length)
              .fontSize(12).fontColor(this.filterType === 'all' ? '#007DFF' : $r('app.color.text_secondary'))
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor(this.filterType === 'all' ? $r('app.color.card_background') : $r('app.color.chip_background'))
          .onClick(() => { this.filterType = 'all'; this.applyFilter(); })

          // 正常
          Row({ space: 4 }) {
            Circle().width(8).height(8)
              .fill(this.filterType === 'normal' ? '#34C759' : $r('app.color.text_disabled'))
            Text('正常 ' + this.normalCount)
              .fontSize(12).fontColor(this.filterType === 'normal' ? '#34C759' : $r('app.color.text_secondary'))
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor(this.filterType === 'normal' ? $r('app.color.card_background') : $r('app.color.chip_background'))
          .onClick(() => { this.filterType = 'normal'; this.applyFilter(); })

          // 临期
          Row({ space: 4 }) {
            Circle().width(8).height(8)
              .fill(this.filterType === 'nearExpiry' ? '#FF9500' : $r('app.color.text_disabled'))
            Text('临期 ' + this.nearExpiryCount)
              .fontSize(12).fontColor(this.filterType === 'nearExpiry' ? '#FF9500' : $r('app.color.text_secondary'))
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor(this.filterType === 'nearExpiry' ? $r('app.color.card_background') : $r('app.color.chip_background'))
          .onClick(() => { this.filterType = 'nearExpiry'; this.applyFilter(); })

          // 过期
          Row({ space: 4 }) {
            Circle().width(8).height(8)
              .fill(this.filterType === 'expired' ? '#FF3B30' : $r('app.color.text_disabled'))
            Text('过期 ' + this.expiredCount)
              .fontSize(12).fontColor(this.filterType === 'expired' ? '#FF3B30' : $r('app.color.text_secondary'))
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor(this.filterType === 'expired' ? $r('app.color.card_background') : $r('app.color.chip_background'))
          .onClick(() => { this.filterType = 'expired'; this.applyFilter(); })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 12 })

        // 食品列表
        if (this.filteredItems.length === 0 && !this.isLoading) {
          this.buildEmptyState()
        } else {
          List({ space: 12 }) {
            ForEach(this.filteredItems, (item: FoodItem) => {
              ListItem() {
                this.buildFoodCard(item)
              }
            }, (item: FoodItem) => item.id.toString())
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, bottom: 16 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      // FAB
      Button('+')
        .width(56)
        .height(56)
        .fontSize(28)
        .fontColor(Color.White)
        .backgroundColor('#007DFF')
        .borderRadius(28)
        .shadow({ radius: 8, color: '#40007DFF', offsetX: 0, offsetY: 4 })
        .margin({ right: 20, bottom: 20 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/EntrySelectionPage' });
        })

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
              Text('选择食用者').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.members, (member: FamilyMember) => {
                  Button(member.name)
                    .height(36).fontSize(13).fontColor(Color.White)
                    .backgroundColor('#34C759').borderRadius(18)
                    .margin({ right: 8, bottom: 8 })
                    .onClick(() => {
                      if (this.selectedItem !== null) {
                        this.handleEat(this.selectedItem, member.name);
                      }
                    })
                }, (member: FamilyMember) => member.id.toString())
              }
              if (this.members.length === 0) {
                Text('请先在"我的"页面添加家庭成员')
                  .fontSize(12).fontColor($r('app.color.text_hint'))
              }
            }

            Divider().color($r('app.color.divider'))

            Text('丢弃原因').fontSize(14).fontColor($r('app.color.text_secondary')).width('100%')
            Row({ space: 8 }) {
              ForEach(WASTE_REASONS, (reason: string) => {
                Button(reason)
                  .height(36).fontSize(13).fontColor('#FF6B00')
                  .backgroundColor('#FFF3E0').borderRadius(18)
                  .onClick(() => {
                    if (this.selectedItem !== null) {
                      this.handleWaste(this.selectedItem, reason);
                    }
                  })
              }, (reason: string) => reason)
            }

            Divider().color($r('app.color.divider'))

            Button('编辑')
              .width('100%').height(40).fontSize(14)
              .fontColor('#007DFF').backgroundColor('#E8F0FE').borderRadius(8)
              .onClick(() => {
                this.showActionPanel = false;
                if (this.selectedItem !== null) {
                  const params: EditFoodParams = { editMode: true, foodId: this.selectedItem.id };
                  router.pushUrl({ url: 'pages/AddFoodPage', params: params });
                }
              })
          }
          .width('100%').padding(16)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius({ topLeft: 16, topRight: 16 })
        }
        .width('100%').height('100%')
        .backgroundColor($r('app.color.overlay_background'))
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildFoodCard(item: FoodItem) {
    Row() {
      Column()
        .width(4).height(72).borderRadius(2).backgroundColor(item.getStatusColor())
      Column({ space: 4 }) {
        Row() {
          Text(item.name)
            .fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor(item.isExpired() ? $r('app.color.text_hint') : $r('app.color.text_primary'))
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(item.getStatusText())
            .fontSize(11).fontColor(item.getStatusColor())
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(10).backgroundColor(item.getStatusBgColor())
        }
        .width('100%')

        Row({ space: 8 }) {
          if (item.category.length > 0) {
            Text(item.category).fontSize(13).fontColor($r('app.color.text_hint'))
          }
          if (item.spec.length > 0) {
            Text(item.spec).fontSize(13).fontColor($r('app.color.text_hint'))
          }
          Text(getStorageTypeName(item.storageType)).fontSize(13).fontColor($r('app.color.text_hint'))
        }

        Row() {
          Text(this.getExpiryText(item))
            .fontSize(13).fontColor(item.getStatusColor()).layoutWeight(1)
          if (item.calories > 0) {
            Text(item.calories.toFixed(0) + ' kcal').fontSize(13).fontColor($r('app.color.text_hint'))
          }
        }
        .width('100%')
      }
      .layoutWeight(1).padding({ left: 12, right: 12, top: 10, bottom: 10 })
    }
    .width('100%')
    .backgroundColor(item.isExpired() ? $r('app.color.chip_background') : $r('app.color.card_background'))
    .borderRadius(12)
    .shadow({ radius: 4, color: '#0D000000', offsetX: 0, offsetY: 2 })
    .opacity(item.isExpired() ? 0.7 : 1.0)
    .onClick(() => {
      const params: FoodRouterParams = { foodId: item.id };
      router.pushUrl({ url: 'pages/FoodDetailPage', params: params });
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.selectedItem = item;
          this.showActionPanel = true;
        })
    )
  }

  @Builder
  buildEmptyState() {
    Column({ space: 16 }) {
      Text('🍽️').fontSize(64)
      Text('暂无食品库存').fontSize(16).fontColor($r('app.color.text_hint'))
      Text('点击右下角 + 添加食品').fontSize(14).fontColor($r('app.color.text_disabled'))
    }
    .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
  }
}
