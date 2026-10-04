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

export default class BytesSource implements Source {
  private bytes: ArrayBuffer

  constructor(bytes: ArrayBuffer) {
    this.bytes = bytes;
  }

  setForMediaPlayer(mediaPlayer: media.AVPlayer): void {
    let src: media.AVDataSrcDescriptor = {
      fileSize: this.bytes.byteLength,
      callback: (buf: ArrayBuffer, length: number, pos: number | undefined) => {
        if (buf == undefined || length == undefined || pos == undefined) {
          return -1;
        }
        if (pos >= src.fileSize) {
          return -1
        }
        let remainingSize = this.computeRemainingSize(length, pos);
        if (remainingSize < 0) {
          return -1;
        }
        const view = new Uint8Array(buf);
        const dataToCopy = this.bytes.slice(pos, pos + remainingSize);
        const dataView = new Uint8Array(dataToCopy);
        // 复制数据到ArrayBuffer
        view.set(dataView);

        if (remainingSize > 0 && (src.fileSize >= pos)) {
          return remainingSize;
        }
        return -1;
      }
    }
    mediaPlayer.dataSrc = src
  }

  setForSoundPool(soundPoolPlayer: SoundPoolPlayer): void {
    throw new Error("Bytes sources are not supported on LOW_LATENCY mode yet.")
  }

  private computeRemainingSize(length: number, position: number): number {
    let remainingSize = length
    if (position + remainingSize > this.bytes.byteLength) {
      remainingSize -= position + remainingSize - this.bytes.byteLength
    }
    return remainingSize
  }
}