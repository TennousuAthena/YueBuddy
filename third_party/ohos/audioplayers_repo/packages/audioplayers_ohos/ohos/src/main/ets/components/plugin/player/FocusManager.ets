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

import WrappedPlayer from './WrappedPlayer';
import audio from '@ohos.multimedia.audio';
import AudioContextOhos from '../AudioContextOhos';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { HashMap } from '@kit.ArkTS';
import { Log } from '@ohos/flutter_ohos';


const TAG = "FocusManager";

const API_6_0 = 20;

/**
 * 焦点管理是应用级别，各个player的焦点策略，都会被应用到全局
 */
export default class FocusManager {
  private static instance: FocusManager = new FocusManager();

  public static getInstance() {
    return FocusManager.instance;
  }

  //订阅焦点的播放器，第二个值，代表是否因为焦点事件中断，为true时，重新获取焦点后，会继续播放
  private subscribedPlayerSet: HashMap<WrappedPlayer, boolean> = new HashMap();
  private audioSessionManager: audio.AudioSessionManager;
  private context?: AudioContextOhos;
  private audioSessionDeactivatedCallback?: (audioSessionDeactivatedEvent: audio.AudioSessionDeactivatedEvent) => void;
  private audioSessionStateChangedCallback?: (audioSessionStateChangedEvent: audio.AudioSessionStateChangedEvent) => void;

  constructor() {
    let audioManager = audio.getAudioManager();
    this.audioSessionManager = audioManager.getSessionManager();
    this.subscribeFocusCallback();
  }

  subscribePlayer(player: WrappedPlayer) {
    if (!this.subscribedPlayerSet.hasKey(player)) {
      this.subscribedPlayerSet.set(player, false);
    }
  }

  unsubscribePlayer(player: WrappedPlayer) {
    if (this.subscribedPlayerSet.hasKey(player)) {
      this.subscribedPlayerSet.remove(player);
    }
  }

  //停用音频焦点
  handleStop(player: WrappedPlayer) {
    if (this.hasOtherPlayerPlaying(player)) {
      return;
    }
    if (this.hasAudioFocus()) {
      this.deactivateAudioSession();
    }
  }

  /**
   * 每次的策略，都根据最新请求焦点的播放器决定。 如果已有音频焦点，不更新策略。
   * @param player
   */
  maybeRequestAudioFocus(player: WrappedPlayer) {
    this.subscribePlayer(player);
    this.context = player.context;
    //如果已有焦点，直接播放
    if (this.hasAudioFocus()) {
      player.actuallyPlay();
      return;
    }
    let strategy: audio.AudioSessionStrategy = {
      concurrencyMode: this.getFocusStrategy()
    };
    if (deviceInfo.sdkApiVersion >= API_6_0) {
      this.audioSessionManager.setAudioSessionScene(audio.AudioSessionScene.AUDIO_SESSION_SCENE_MEDIA);
    }
    //请求焦点之后，开始播放
    this.audioSessionManager.activateAudioSession(strategy).then(() => {
      Log.d(TAG, 'Succeeded in doing activateAudioSession.');
      player.actuallyPlay();
    }).catch((err: BusinessError) => {
      Log.e(TAG, `Failed to activateAudioSession. Code: ${err.code}, message: ${err.message}`);
    });
  }

  dispose(): void {
    if (this.hasAudioFocus()) {
      this.deactivateAudioSession();
    }
    this.audioSessionManager.off('audioSessionDeactivated', this.audioSessionDeactivatedCallback);
    if (deviceInfo.sdkApiVersion >= API_6_0) {
      this.audioSessionManager.off('audioSessionStateChanged', this.audioSessionStateChangedCallback);
    }
  }


  private onGranted() {
    this.subscribedPlayerSet.forEach((isSuspend, player) => {
      if (isSuspend) {
        player?.actuallyPlay();
      }
    })
  }

  private onLoss(isTransient: boolean) {
    this.subscribedPlayerSet.forEach((isSuspend, player) => {
      //失去焦点后，暂停所有播放器
      if (player?.isPlaying()) {
        //如果是暂时中断，标记，代表下次可能重新获取焦点
        if (isTransient) {
          this.subscribedPlayerSet.set(player, true);
        }
        player?.pause();
      }
    })
  }


  private hasOtherPlayerPlaying(currentPlayer: WrappedPlayer): boolean {
    let hasOtherPlaying: boolean = false;
    this.subscribedPlayerSet.forEach((isSuspend, player) => {
      if (currentPlayer != player && player?.isPlaying()) {
        hasOtherPlaying = true;
      }
    })
    return hasOtherPlaying;
  }


  private deactivateAudioSession() {
    this.audioSessionManager.deactivateAudioSession().then(() => {
      Log.d(TAG, 'Succeeded in doing deactivateAudioSession.');
    }).catch((err: BusinessError) => {
      Log.e(TAG, `Failed to deactivateAudioSession. Code: ${err.code}, message: ${err.message}`);
    });
  }


  private subscribeFocusCallback() {
    this.audioSessionDeactivatedCallback = (audioSessionDeactivatedEvent: audio.AudioSessionDeactivatedEvent) => {
      Log.d(TAG, `audioSessionDeactivatedCallback: ${audioSessionDeactivatedEvent.reason.toString()} `);
      this.onLoss(false);
    }
    this.audioSessionManager.on("audioSessionDeactivated", this.audioSessionDeactivatedCallback);
    if (deviceInfo.sdkApiVersion >= API_6_0) {
      this.audioSessionStateChangedCallback = (audioSessionStateChangedEvent: audio.AudioSessionStateChangedEvent) => {
        Log.d(TAG, `hint of audioSessionStateChanged: ${audioSessionStateChangedEvent.stateChangeHint} `);
        switch (audioSessionStateChangedEvent.stateChangeHint) {
          case audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_PAUSE:
            // 此分支表示系统已将音频流暂停，应用需切换至音频暂停状态。
            // 临时失去焦点：其他音频流释放音频焦点后，本音频流会收到resume事件，可继续播放。
            this.onLoss(true);
            break;
          case audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_RESUME:
            // 此分支表示系统解除AudioSession焦点的暂停操作。
            this.onGranted();
            break;
          case audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_STOP:
            // 此分支表示系统已将音频流停止（永久失去焦点），为保持状态一致，应用需切换至音频暂停状态。
            // 永久失去焦点：后续不会再收到音频焦点事件，恢复播放需用户主动触发。
            this.onLoss(false);
            break;
          case audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_TIME_OUT_STOP:
            // 此分支表示由于长时间无音频流播放，系统已将AudioSession停止（永久失去焦点），应用需切换至音频暂停状态。
            // 永久失去焦点：后续不会再收到音频焦点事件，恢复播放需用户主动触发。
            this.onLoss(false);
            break;
          case audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_DUCK:
            // 此分支表示系统已将音频音量降低（默认降到正常音量的20%）。
            break;
          case audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_UNDUCK:
            // 此分支表示系统已将音频音量恢复正常。
            break;
          default:
            break;
        }
      };
      this.audioSessionManager.on('audioSessionStateChanged', this.audioSessionStateChangedCallback);
    }
  }


  private hasAudioFocus(): boolean {
    return this.audioSessionManager.isAudioSessionActivated();
  }

  private getFocusStrategy(): audio.AudioConcurrencyMode {
    switch (this.context?.audioFocus) {
      case 1: //对应dart侧AudioContextConfigFocus.duckOthers
        return audio.AudioConcurrencyMode.CONCURRENCY_DUCK_OTHERS;
      case 2: //对应dart侧AudioContextConfigFocus.mixWithOthers
        return audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS;
      case 0: //对应dart侧AudioContextConfigFocus.gain
      default:
        return audio.AudioConcurrencyMode.CONCURRENCY_DEFAULT;
    }
  }
}