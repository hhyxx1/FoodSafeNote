// 全局导航中枢：替代 router 页面跳转，配合 Index.ets 的 HdsNavigation（Navigation 架构）使用
// 手机/平板分支的页面跳转统一走这里；手表/智慧屏分支仍使用 router
// NavPathStack 为 ArkUI 全局类型，无需导入
export class AppNavigation {
  private static stack: NavPathStack | null = null;
  private static readonly dataChangeTickKey: string = 'dataChangeTick';

  public static setStack(stack: NavPathStack): void {
    AppNavigation.stack = stack;
  }

  public static push(name: string, param?: Object): void {
    if (AppNavigation.stack !== null) {
      const paths: string[] = AppNavigation.stack.getAllPathName();
      if (paths[paths.length - 1] !== name) {
        AppNavigation.stack.pushPathByName(name, param !== undefined ? param : null);
      }
    }
  }

  // 替换当前页面（等价于原 replaceUrl）
  public static replace(name: string, param?: Object): void {
    if (AppNavigation.stack !== null) {
      AppNavigation.stack.replacePath({ name: name, param: param !== undefined ? param : null });
    }
  }

  public static pop(): void {
    if (AppNavigation.stack !== null) {
      AppNavigation.stack.pop();
    }
  }

  // 页面在 aboutToAppear 中获取路由参数（push/replace 时同步写入，时序安全）
  public static getParamByName(name: string): Object | undefined {
    if (AppNavigation.stack === null) {
      return undefined;
    }
    // SDK 声明返回 Array<unknown>，此处做单一断言收敛为 Object
    const params: Array<Object> = AppNavigation.stack.getParamByName(name) as Array<Object>;
    if (params.length === 0) {
      return undefined;
    }
    return params[params.length - 1];
  }

  // 页面返回（含系统侧滑）后通知主页刷新数据，等价于原 Index.onPageShow 的 refreshKey++
  public static notifyDataChanged(): void {
    const tick: number = AppStorage.get<number>(AppNavigation.dataChangeTickKey) ?? 0;
    AppStorage.setOrCreate<number>(AppNavigation.dataChangeTickKey, tick + 1);
  }
}
