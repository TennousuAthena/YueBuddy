/*
 * Copyright (c) 2025 Hunan OpenValley Digital Industry Development Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
 
import media from '@ohos.multimedia.media';
import audio from '@ohos.multimedia.audio';
import { Log } from '@ohos/flutter_ohos';

export default class AudioContextOhos {
  rendererFlags: number = 0;
  usageType: number = 1;
  isSpeakerphoneOn: boolean = true;
  audioScene: number = 0;
  stayAwake: boolean = false;
  audioFocus: number = 0;

  copy(): AudioContextOhos {
    let context = new AudioContextOhos()
    context.rendererFlags = this.rendererFlags;
    context.usageType = this.usageType;
    context.isSpeakerphoneOn = this.isSpeakerphoneOn;
    context.audioScene = this.audioScene;
    context.stayAwake = this.stayAwake;
    context.audioFocus = this.audioFocus;
    return context;
  }

  setAttributesOnPlayer(mediaPlayer: media.AVPlayer) {
    mediaPlayer.audioRendererInfo = {
      content: 2,
      usage: this.usageType, rendererFlags: this.rendererFlags,
    }
  }

  buildAttributes(): audio.AudioRendererInfo {
    return {
      content: 2,
      usage: this.usageType,
      rendererFlags: this.rendererFlags,
    }
  }

  equals(context: AudioContextOhos) {
    return context.rendererFlags == this.rendererFlags && context.usageType == this.usageType &&
      context.isSpeakerphoneOn == this.isSpeakerphoneOn && context.audioScene == this.audioScene &&
      context.stayAwake == this.stayAwake && context.audioFocus == this.audioFocus;
  }

  toString(){
    return "AudioContextOhos{isSpeakerphoneOn=" + this.isSpeakerphoneOn +
      ", rendererFlags=" + this.rendererFlags +
      ", usageType=" + this.usageType +
      ", audioScene=" + this.audioScene +
      ", stayAwake=" + this.stayAwake +
      ", audioFocus=" + this.audioFocus +
      "}";
  }
}