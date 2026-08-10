import { appTasks } from '@ohos/hvigor-ohos-plugin';
import * as fs from 'fs';
import * as path from 'path';

// 从本地签名配置文件加载签名信息（signing-config.local.json 已被 .gitignore 忽略，不入库）
// 若文件缺失（新环境/CI），返回 null，由 build-profile.json5 中的占位配置兜底
function loadLocalSigningConfig(): Object | null {
  const configPath: string = path.resolve(__dirname, 'signing-config.local.json');
  if (!fs.existsSync(configPath)) {
    return null;
  }
  try {
    const raw: string = fs.readFileSync(configPath, 'utf-8');
    return JSON.parse(raw) as Object;
  } catch (e) {
    return null;
  }
}

const localSigningConfig: Object | null = loadLocalSigningConfig();

export default {
    system: appTasks,
    plugins: [],
    config: {
        ohos: {
            overrides: localSigningConfig !== null ? {
                signingConfig: localSigningConfig
            } : {}
        }
    }
}
