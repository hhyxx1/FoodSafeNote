import { util } from '@kit.ArkTS';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { deviceInfo } from '@kit.BasicServicesKit';

export function canReceiveRemoteFoodPhoto(): boolean {
  return (deviceInfo.deviceType === 'phone' || deviceInfo.deviceType === 'tablet' ||
    deviceInfo.deviceType === '2in1') && canIUse('SystemCapability.Collaboration.Service');
}

export function cacheRemoteFoodPhoto(context: Context, data: ArrayBuffer): string {
  const path = context.cacheDir + '/remote_food_' + util.generateRandomUUID() + '.jpg';
  try {
    const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
    try {
      if (fileIo.writeSync(file.fd, data) !== data.byteLength) {
        throw new Error('Incomplete remote image write');
      }
    } finally {
      fileIo.closeSync(file);
    }
    return fileUri.getUriFromPath(path);
  } catch (error) {
    removeRemoteFoodPhoto(path);
    throw new Error('Could not cache the remote image');
  }
}

export function removeRemoteFoodPhoto(uri: string): void {
  try {
    fileIo.unlinkSync(uri.startsWith('file://') ? new fileUri.FileUri(uri).path : uri);
  } catch (error) {
    // Temporary files may already have been removed by the system.
  }
}
