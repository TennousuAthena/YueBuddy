/**
 * Copyright (c) 2024 Hunan OpenValley Digital Industry Development Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
 
import SoundPoolPlayer from '../player/SoundPoolPlayer';
import Source from './Source';
import media from '@ohos.multimedia.media';
import fs from '@ohos.file.fs';
import request from '@ohos.request';

export default class UrlSource implements Source {
  url: string
  private isLocal: boolean

  constructor(url: string, isLocal: boolean) {
    this.url = url;
    this.isLocal = isLocal;
  }

  setForMediaPlayer(mediaPlayer: media.AVPlayer): void {
    if (this.isLocal) {
      let fdPath = 'fd://';
      // 打开相应的资源文件地址获取fd，并为url赋值触发initialized状态机上报
      let file = fs.openSync(this.url);
      fdPath = fdPath + '' + file.fd;
      mediaPlayer.url = fdPath;
    } else {
      mediaPlayer.url = this.url;
    }
  }

  setForSoundPool(soundPoolPlayer: SoundPoolPlayer): void {
    soundPoolPlayer.setUrlSource(this);
  }

  getAudioPathForSoundPool(context: Context): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      if (this.isLocal) {
        // 打开相应的资源文件地址获取fd，并为url赋值触发initialized状态机上报
        let file = fs.openSync(this.url);
        resolve('fd://' + file.fd)
      } else {
        let tempFile = context.tempDir + "/sound.data"
        if (fs.accessSync(tempFile)) {
          fs.rmdirSync(tempFile)
        }
        request.downloadFile(context, {
          url: this.url,
          filePath: tempFile
        }).then((downloadTask: request.DownloadTask) => {
          downloadTask.on('complete', () => {
            let file = fs.openSync(tempFile);
            resolve('fd://' + file.fd)
          })
          downloadTask.on('fail', (err: number) => {
            resolve(tempFile)
          })
        })
      }
    })
  }
}