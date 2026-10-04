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

import AudioContextOhos from '../AudioContextOhos';
import Source from '../source/Source';
import Player from './Player';
import WrappedPlayer from './WrappedPlayer'
import media from '@ohos.multimedia.media';
import { BusinessError } from '@ohos.base';
import { Log } from '@ohos/flutter_ohos';
import { window } from '@kit.ArkUI'
import common from '@ohos.app.ability.common';

const TAG = "MediaPlayerPlayer"
// === 通用错误码 ===
const PARAM_ERROR: number = 401; 
const OPERATE_ERROR: number = 801; 
const PERMISSION_DENIED: number = 1000001; 

// === AVPlayer 相关错误码 ===
const AVPLAYER_STATE_ERROR: number = 5400102; 
const AVPLAYER_IO_ERROR: number = 5400103; 
const AVPLAYER_TIMEOUT_ERROR: number = 5400104; 
const AVPLAYER_UNSUPPORTED_OPERATION: number = 5400105; 
const AVPLAYER_FORMAT_ERROR: number = 5400106;
const AVPLAYER_NETWORK_ERROR: number = 5400107;

// === 音频相关错误码 ===
const AUDIO_STATE_ERROR: number = 6800101;
const AUDIO_IO_ERROR: number = 6800102; 
const AUDIO_PERMISSION_DENIED: number = 6800103; 
const AUDIO_UNSUPPORTED_FORMAT: number = 6800104; 
const AUDIO_SYSTEM_ERROR: number = 6800105; 

// === 媒体库相关错误码 ===
const MEDIALIB_PERMISSION_DENIED: number = 5411001; 
const MEDIALIB_IO_ERROR: number = 5411002; 
const MEDIALIB_FORMAT_ERROR: number = 5411003; 
const MEDIALIB_NETWORK_ERROR: number = 5411004; 
const MEDIALIB_TIMEOUT: number = 5411005; 
const MEDIALIB_REQUEST_DENIED: number = 5411006; 

// === 文件系统相关错误码 ===
const FILE_PERMISSION_DENIED: number = 13900001; 
const FILE_NOT_EXIST: number = 13900002;
const FILE_IO_ERROR: number = 13900003; 
const FILESYSTEM_ERROR: number = 13900004; 

// === 网络相关错误码 ===
const NETWORK_CONNECTION_ERROR: number = 2300001; 
const NETWORK_TIMEOUT: number = 2300002; 
const NETWORK_UNAVAILABLE: number = 2300003; 
const NETWORK_PROTOCOL_ERROR: number = 2300004; 
const NETWORK_DNS_ERROR: number = 2300005;
const NETWORK_SSL_ERROR: number = 2300006; 

export default class MediaPlayerPlayer implements Player {
  private wrappedPlayer: WrappedPlayer;
  private mediaPlayer?: media.AVPlayer | null = null;
  private isLooping: boolean = false;
  private volume: number = 1;
  private needPrepare: boolean = false;
  private stayAwake: boolean = false;
  private speed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X;

  constructor(wrappedPlayer: WrappedPlayer, context: AudioContextOhos) {
    this.wrappedPlayer = wrappedPlayer;
    this.stayAwake = context.stayAwake;
  }

  async initMediaPlayer() {
    this.mediaPlayer = await media.createAVPlayer();
    this.setAVPlayerCallback(this.mediaPlayer)
    Log.d(TAG, "initMediaPlayer");
  }

  setAVPlayerCallback(avPlayer: media.AVPlayer) {
    // seek操作结果回调函数
    avPlayer.on('seekDone', (seekDoneTime: number) => {
      Log.d(TAG, `AVPlayer seek succeeded, seek time is ${seekDoneTime}`);
      this.wrappedPlayer.onSeekComplete()
    })

    avPlayer.on('bufferingUpdate', (infoType: media.BufferingInfoType, value: number) => {
      Log.d(TAG, `AVPlayer bufferingUpdate value is ${value}`);
      this.wrappedPlayer.onBuffering(value)
    })
    avPlayer.on('speedDone', (speed: number) => {
      console.info('speedDone called,and speed value is:' + speed)
    })
    // error回调监听函数,当avPlayer在操作过程中出现错误时调用 reset接口触发重置流程
    avPlayer.on('error', (err: BusinessError) => {
      if (err.code == OPERATE_ERROR || err.code == AVPLAYER_STATE_ERROR || err.code == AVPLAYER_IO_ERROR || err.code == MEDIALIB_PERMISSION_DENIED) {
        Log.e(TAG, "AvPlayer Avoid Error Reporting: " + JSON.stringify(err));
        return;
      }
      if (err.code == AVPLAYER_FORMAT_ERROR||err.code == MEDIALIB_REQUEST_DENIED) {
        this.wrappedPlayer.onPrepared()
        Log.e(TAG, "AvPlayer Avoid Error Reporting: " + JSON.stringify(err));
        return;
      }
      Log.e(TAG, `Invoke avPlayer failed, code is ${err.code}, message is ${err.message}`);
      this.wrappedPlayer.onError(err.code, err.message)
    })
    // 状态机变化回调函数
    avPlayer.on('stateChange', async (state: string, reason: media.StateChangeReason) => {
      switch (state) {
        case 'idle': // 成功调用reset接口后触发该状态机上报
          Log.d(TAG, 'AVPlayer state idle called.');
          break;
        case 'initialized': // avplayer 设置播放源后触发该状态上报
          Log.d(TAG, 'AVPlayer state initialized called.');
          this.wrappedPlayer.context?.setAttributesOnPlayer(this.mediaPlayer!)
          this.needPrepare && this.prepare();
          break;
        case 'prepared': // prepare调用成功后上报该状态机
          Log.d(TAG, 'AVPlayer state prepared called.');
          this.setVolume(this.volume, this.volume)
          this.setLooping(this.isLooping)
          this.setRate(this.speed);
          this.wrappedPlayer.onPrepared();
          break;
        case 'playing': // play成功调用后触发该状态机上报
          Log.d(TAG, 'AVPlayer state playing called.');
          break;
        case 'paused': // pause成功调用后触发该状态机上报
          Log.d(TAG, 'AVPlayer state paused called.');
          break;
        case 'completed': // 播放结束后触发该状态机上报
          Log.d(TAG, 'AVPlayer state completed called.');
          this.wrappedPlayer.onCompletion()
          break;
        case 'stopped': // stop接口成功调用后触发该状态机上报
          Log.d(TAG, 'AVPlayer state stopped called.');
          this.needPrepare && this.prepare();
          break;
        case 'released':
          Log.d(TAG, 'AVPlayer state released called.');
          break;
        default:
          Log.d(TAG, 'AVPlayer state unknown called.');
          break;
      }
    })
  }

  getDuration(): number {
    // media player returns -1 if the duration is unknown
    return this.mediaPlayer ? this.mediaPlayer!.duration : -1
  }

  getCurrentPosition(): number {
    return this.mediaPlayer ? this.mediaPlayer!.currentTime : -1
  }

  isActuallyPlaying(): boolean {
    return this.mediaPlayer ? this.mediaPlayer!.state == 'playing' : false
  }

  isLiveStream(): boolean {
    let duration = this.getDuration();
    return duration == 0 || duration == -1
  }

  async start() {
    this.mediaPlayer && await this.mediaPlayer.play();
  }

  async pause() {
    this.mediaPlayer && this.mediaPlayer!.state == 'playing' && await this.mediaPlayer.pause();
  }

  async stop() {
    this.needPrepare = false;
    this.mediaPlayer && await this.mediaPlayer.stop();
  }

  seekTo(position: number) {
    this.mediaPlayer && this.mediaPlayer.seek(position);
  }

  async release() {
    if (this.mediaPlayer) {
      await this.mediaPlayer.reset()
      await this.mediaPlayer.release()
    }
  }

  setVolume(leftVolume: number, rightVolume: number) {
    this.volume = leftVolume;
    if (this.isReadyState()) {
      this.mediaPlayer!.setVolume(leftVolume);
    }
  }

  setRate(rate: number) {
    if (rate < 0) {
      throw new Error('Invalid rate input: ' + rate);
    }
    if(rate == 0){
      this.mediaPlayer?.pause();
      return;
    }
    this.speed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    if (rate <= 0.5) {
      this.speed = media.PlaybackSpeed.SPEED_FORWARD_0_50_X;
    } else if (rate <= 0.75) {
      this.speed = media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    } else if (rate <= 1.0) {
      this.speed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    } else if (rate <= 1.25) {
      this.speed = media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
    } else if (rate <= 1.5) {
      this.speed = media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
    } else if (rate <= 1.75) {
      this.speed = media.PlaybackSpeed.SPEED_FORWARD_1_75_X;
    } else {
      this.speed = media.PlaybackSpeed.SPEED_FORWARD_2_00_X
    }
    this.mediaPlayer && this.mediaPlayer.setSpeed(this.speed);
    if(this.mediaPlayer?.state == 'paused'){
      this.start();
    }
  }

  setLooping(looping: boolean) {
    this.isLooping = looping;
    if (this.isReadyState()) {
      this.mediaPlayer!.loop = looping;
    }
  }

  private isReadyState() {
    return this.mediaPlayer && (this.mediaPlayer!.state == 'prepared' || this.mediaPlayer!.state == 'playing'
      || this.mediaPlayer!.state == 'paused' || this.mediaPlayer!.state == 'completed')
  }

  async updateContext(context: AudioContextOhos) {
    this.mediaPlayer && this.mediaPlayer!.state == 'initialized' && context.setAttributesOnPlayer(this.mediaPlayer);
    if (context.stayAwake != this.stayAwake) {
      let uiContext = getContext(this) as common.UIAbilityContext
      let windowClass: window.Window = await window.getLastWindow(uiContext)
      windowClass.setWindowKeepScreenOn(context.stayAwake);
      this.stayAwake = context.stayAwake
    }
  }

  async setSource(source: Source) {
    await this.reset()
    this.mediaPlayer && source.setForMediaPlayer(this.mediaPlayer);
  }

  async prepare() {
    if (this.canPrepare()) {
      this.needPrepare = false;
      await this.mediaPlayer!.prepare()
    } else {
      this.needPrepare = true
    }
  }

  private canPrepare() {
    return this.mediaPlayer && (this.mediaPlayer!.state == 'stopped' || this.mediaPlayer!.state == 'initialized')
  }

  async reset() {
    this.mediaPlayer && await this.mediaPlayer.reset()
  }
}