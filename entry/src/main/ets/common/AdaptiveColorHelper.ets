import { image } from '@kit.ImageKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';

interface RgbColor {
  red: number;
  green: number;
  blue: number;
}

interface HsvColor {
  hue: number;
  saturation: number;
  value: number;
}

export class AdaptiveColorHelper {
  private static cardCache: Map<string, string> = new Map<string, string>();
  private static accentCache: Map<string, string> = new Map<string, string>();
  private static currentColorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;

  public static setCurrentColorMode(mode: number): void {
    AdaptiveColorHelper.currentColorMode = mode;
  }

  private static getCurrentColorMode(): number {
    return AdaptiveColorHelper.currentColorMode;
  }

  public static isDarkModeEnabled(): boolean {
    return AdaptiveColorHelper.getCurrentColorMode() === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private static clamp(value: number, min: number, max: number): number {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  private static toHex2(value: number): string {
    const normalized: number = AdaptiveColorHelper.clamp(Math.round(value), 0, 255);
    const hex: string = normalized.toString(16);
    return hex.length === 1 ? '0' + hex : hex;
  }

  private static hsvToRgb(hue: number, saturation: number, value: number): RgbColor {
    const h: number = ((hue % 360) + 360) % 360;
    const s: number = AdaptiveColorHelper.clamp(saturation, 0, 1);
    const v: number = AdaptiveColorHelper.clamp(value, 0, 1);

    const c: number = v * s;
    const x: number = c * (1 - Math.abs((h / 60) % 2 - 1));
    const m: number = v - c;

    let r1: number = 0;
    let g1: number = 0;
    let b1: number = 0;

    if (h < 60) {
      r1 = c;
      g1 = x;
      b1 = 0;
    } else if (h < 120) {
      r1 = x;
      g1 = c;
      b1 = 0;
    } else if (h < 180) {
      r1 = 0;
      g1 = c;
      b1 = x;
    } else if (h < 240) {
      r1 = 0;
      g1 = x;
      b1 = c;
    } else if (h < 300) {
      r1 = x;
      g1 = 0;
      b1 = c;
    } else {
      r1 = c;
      g1 = 0;
      b1 = x;
    }

    return {
      red: (r1 + m) * 255,
      green: (g1 + m) * 255,
      blue: (b1 + m) * 255
    };
  }

  private static rgbToHsv(color: RgbColor): HsvColor {
    const r: number = color.red / 255;
    const g: number = color.green / 255;
    const b: number = color.blue / 255;
    const max: number = Math.max(r, g, b);
    const min: number = Math.min(r, g, b);
    const delta: number = max - min;

    let hue: number = 0;
    if (delta > 0) {
      if (max === r) {
        hue = 60 * (((g - b) / delta) % 6);
      } else if (max === g) {
        hue = 60 * (((b - r) / delta) + 2);
      } else {
        hue = 60 * (((r - g) / delta) + 4);
      }
      if (hue < 0) {
        hue += 360;
      }
    }

    const saturation: number = max <= 0 ? 0 : delta / max;
    return { hue: hue, saturation: saturation, value: max };
  }

  private static rgbToHex(color: RgbColor): string {
    return '#' +
      AdaptiveColorHelper.toHex2(color.red) +
      AdaptiveColorHelper.toHex2(color.green) +
      AdaptiveColorHelper.toHex2(color.blue);
  }

  private static hexToRgb(hex: string): RgbColor {
    let normalized: string = hex.trim();
    if (normalized.startsWith('#')) {
      normalized = normalized.substring(1);
    }
    if (normalized.length === 3) {
      const r: string = normalized.substring(0, 1);
      const g: string = normalized.substring(1, 2);
      const b: string = normalized.substring(2, 3);
      normalized = r + r + g + g + b + b;
    }
    if (normalized.length !== 6) {
      return { red: 0, green: 0, blue: 0 };
    }
    const red: number = parseInt(normalized.substring(0, 2), 16);
    const green: number = parseInt(normalized.substring(2, 4), 16);
    const blue: number = parseInt(normalized.substring(4, 6), 16);
    return {
      red: Number.isNaN(red) ? 0 : red,
      green: Number.isNaN(green) ? 0 : green,
      blue: Number.isNaN(blue) ? 0 : blue
    };
  }

  private static srgbToLinear(channel: number): number {
    const c: number = AdaptiveColorHelper.clamp(channel / 255, 0, 1);
    if (c <= 0.03928) {
      return c / 12.92;
    }
    return Math.pow((c + 0.055) / 1.055, 2.4);
  }

  private static relativeLuminance(color: RgbColor): number {
    const r: number = AdaptiveColorHelper.srgbToLinear(color.red);
    const g: number = AdaptiveColorHelper.srgbToLinear(color.green);
    const b: number = AdaptiveColorHelper.srgbToLinear(color.blue);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  public static contrastRatio(foregroundHex: string, backgroundHex: string): number {
    const fg: RgbColor = AdaptiveColorHelper.hexToRgb(foregroundHex);
    const bg: RgbColor = AdaptiveColorHelper.hexToRgb(backgroundHex);
    const l1: number = AdaptiveColorHelper.relativeLuminance(fg);
    const l2: number = AdaptiveColorHelper.relativeLuminance(bg);
    const lighter: number = Math.max(l1, l2);
    const darker: number = Math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  public static pickTextColor(backgroundHex: string, preferredHex: string, minRatio: number): string {
    const preferredRatio: number = AdaptiveColorHelper.contrastRatio(preferredHex, backgroundHex);
    if (preferredRatio >= minRatio) {
      return preferredHex;
    }
    const dark: string = '#1A1A1A';
    const light: string = '#FFFFFF';
    const darkRatio: number = AdaptiveColorHelper.contrastRatio(dark, backgroundHex);
    const lightRatio: number = AdaptiveColorHelper.contrastRatio(light, backgroundHex);
    if (darkRatio >= minRatio && darkRatio >= lightRatio) {
      return dark;
    }
    if (lightRatio >= minRatio) {
      return light;
    }
    return darkRatio >= lightRatio ? dark : light;
  }

  private static async extractDominantColor(ctx: Context, iconRawfileName: string): Promise<RgbColor> {
    const rawDescriptor: resourceManager.RawFileDescriptor = ctx.resourceManager.getRawFdSync(iconRawfileName);
    const imgSource: image.ImageSource = image.createImageSource(rawDescriptor);
    try {
      const pixelMap: image.PixelMap = await imgSource.createPixelMap({
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.BGRA_8888,
        desiredSize: { width: 40, height: 40 }
      });
      try {
        const buffer: ArrayBuffer = new ArrayBuffer(40 * 40 * 4);
        await pixelMap.readPixelsToBuffer(buffer);
        const bytes: Uint8Array = new Uint8Array(buffer);
        const colorCounter: Map<number, number> = new Map<number, number>();

        for (let i = 0; i < bytes.length; i += 4) {
          const blue: number = bytes[i];
          const green: number = bytes[i + 1];
          const red: number = bytes[i + 2];
          const alpha: number = bytes[i + 3];
          if (alpha < 32) {
            continue;
          }
          const key: number = (red << 16) | (green << 8) | blue;
          const existing: number | undefined = colorCounter.get(key);
          colorCounter.set(key, existing !== undefined ? existing + 1 : 1);
        }

        let bestColor: number = 0x7DA8D6;
        let bestCount: number = -1;
        // Map.forEach 回调签名是 (value, key) —— 此处 color 为 key、count 为 value
        colorCounter.forEach((count: number, color: number) => {
          if (count > bestCount) {
            bestCount = count;
            bestColor = color;
          }
        });

        return {
          red: (bestColor >> 16) & 0xFF,
          green: (bestColor >> 8) & 0xFF,
          blue: bestColor & 0xFF
        };
      } finally {
        pixelMap.release();
      }
    } finally {
      imgSource.release();
      // 关闭 getRawFdSync 打开的 raw fd，避免 fd 泄漏
      ctx.resourceManager.closeRawFdSync(iconRawfileName);
    }
  }

  private static buildModeCacheKey(iconRawfileName: string, darkMode: boolean): string {
    return iconRawfileName + (darkMode ? ':dark' : ':light');
  }

  public static async cardBgFromIconWithMode(ctx: Context, iconRawfileName: string, darkMode: boolean): Promise<string> {
    const cacheKey: string = AdaptiveColorHelper.buildModeCacheKey(iconRawfileName, darkMode);
    if (AdaptiveColorHelper.cardCache.has(cacheKey)) {
      return AdaptiveColorHelper.cardCache.get(cacheKey) as string;
    }
    try {
      const dominant: RgbColor = await AdaptiveColorHelper.extractDominantColor(ctx, iconRawfileName);
      const hsv: HsvColor = AdaptiveColorHelper.rgbToHsv(dominant);
      const softened: RgbColor = darkMode
        ? AdaptiveColorHelper.hsvToRgb(hsv.hue, 0.30, 0.34)
        : AdaptiveColorHelper.hsvToRgb(hsv.hue, 0.16, 0.98);
      const hex: string = AdaptiveColorHelper.rgbToHex(softened);
      AdaptiveColorHelper.cardCache.set(cacheKey, hex);
      return hex;
    } catch (e) {
      return darkMode ? '#2A3340' : '#EDF3FB';
    }
  }

  public static async cardBgFromIcon(ctx: Context, iconRawfileName: string): Promise<string> {
    return AdaptiveColorHelper.cardBgFromIconWithMode(
      ctx,
      iconRawfileName,
      AdaptiveColorHelper.isDarkModeEnabled()
    );
  }

  public static async accentBgFromIconWithMode(ctx: Context, iconRawfileName: string, darkMode: boolean): Promise<string> {
    const cacheKey: string = AdaptiveColorHelper.buildModeCacheKey(iconRawfileName, darkMode);
    if (AdaptiveColorHelper.accentCache.has(cacheKey)) {
      return AdaptiveColorHelper.accentCache.get(cacheKey) as string;
    }
    try {
      const dominant: RgbColor = await AdaptiveColorHelper.extractDominantColor(ctx, iconRawfileName);
      const hsv: HsvColor = AdaptiveColorHelper.rgbToHsv(dominant);
      const accent: RgbColor = darkMode
        ? AdaptiveColorHelper.hsvToRgb(hsv.hue, 0.34, 0.46)
        : AdaptiveColorHelper.hsvToRgb(hsv.hue, 0.28, 0.95);
      const hex: string = AdaptiveColorHelper.rgbToHex(accent);
      AdaptiveColorHelper.accentCache.set(cacheKey, hex);
      return hex;
    } catch (e) {
      return darkMode ? '#2F4560' : '#E8F0FE';
    }
  }

  public static async accentBgFromIcon(ctx: Context, iconRawfileName: string): Promise<string> {
    return AdaptiveColorHelper.accentBgFromIconWithMode(
      ctx,
      iconRawfileName,
      AdaptiveColorHelper.isDarkModeEnabled()
    );
  }

  // 清空全部缓存（Ability 销毁时调用，避免长生命周期下缓存膨胀）
  public static clearCache(): void {
    AdaptiveColorHelper.cardCache.clear();
    AdaptiveColorHelper.accentCache.clear();
  }
}
