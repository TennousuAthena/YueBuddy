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
import AudioplayersPlugin, { EventHandler } from '../AudioplayersPlugin';
import { ReleaseMode } from '../ReleaseMode';
import { PlayerMode } from '../PlayerMode';
import Source from '../source/Source';
import Player from './Player';
import { Context } from '@kit.AbilityKit';
import audio from '@ohos.multimedia.audio';
import SoundPoolPlayer, { SoundPoolManager } from './SoundPoolPlayer';
import MediaPlayerPlayer from './MediaPlayerPlayer';
import { Log } from '@ohos/flutter_ohos';
import FocusManager from './FocusManager';

const TAG = 'WrappedPlayer';

export default class WrappedPlayer {
  private ref: AudioplayersPlugin;
  eventHandler: EventHandler;
  context: AudioContextOhos;
  private soundPoolManager: SoundPoolManager;
  private player: Player | null = null;
  private source: Source | null = null;
  private released: boolean = true;
  private prepared: boolean = false;
  private playing: boolean = false;
  private volume: number = 1.0;
  private balance: number = 0.0;
  private rate: number = 1.0;
  private releaseMode: ReleaseMode = ReleaseMode.RELEASE;
  private isLooping: boolean = this.releaseMode == ReleaseMode.LOOP;
  private playerMode: PlayerMode = PlayerMode.MEDIA_PLAYER;
  private shouldSeekTo: number = -1

  constructor(plugin: AudioplayersPlugin, eventHandler: EventHandler, context: AudioContextOhos,
    soundPoolManager: SoundPoolManager) {
    this.ref = plugin;
    this.eventHandler = eventHandler;
    this.context = context;
    this.soundPoolManager = soundPoolManager;
  }

  async setSource(value: Source | null) {
    if (this.source != value) {
      this.source = value;
      if (value != null) {
        let player = await this.getOrCreatePlayer()
        player.setSource(value)
        await this.configAndPrepare()
      } else {
        this.released = true
        this.setPrepared(false)
        this.playing = false
        await this.player?.release()
      }
    } else {
      this.ref.handlePrepared(this, true)
    }
  }

  getSource(): Source | null {
    return this.source;
  }

  isPlaying(): boolean {
    return this.playing
  }

  setVolume(value: number) {
    if (this.volume != value) {
      this.volume = value
      if (!this.released) {
        this.setVolumeAndBalance(value, this.balance)
      }
    }
  }

  setBalance(value: number) {
    if (this.balance != value) {
      this.balance = value
      if (!this.released) {
        this.setVolumeAndBalance(this.volume, value)
      }
    }
  }

  setRate(value: number) {
    if (this.rate != value) {
      this.rate = value
      this.player && this.player?.setRate(value)
    }
  }

  setReleaseMode(value: ReleaseMode) {
    if (this.releaseMode != value) {
      this.releaseMode = value
      this.isLooping = this.releaseMode == ReleaseMode.LOOP;
      if (!this.released) {
        this.player?.setLooping(this.isLooping)
      }
    }
  }

  getLooping() {
    return this.releaseMode == ReleaseMode.LOOP;
  }

  async setPlayerMode(value: PlayerMode) {
    if (this.playerMode != value) {
      this.playerMode = value
      if (this.player) {
        this.shouldSeekTo = this.maybeGetCurrentPosition()
        this.setPrepared(false)
        await this.player.release()
      }
      await this.initPlayer()
    }
  }

  setPrepared(value: boolean) {
    if (this.prepared != value) {
      this.prepared = value
      this.ref.handlePrepared(this, value)
    }
  }

  getPrepared(): boolean {
    return this.prepared
  }

  getVolume() {
    return this.volume;
  }

  getRate() {
    return this.rate;
  }

  private maybeGetCurrentPosition(): number {
    if (this.player) {
      let position = this.player.getCurrentPosition();
      return position != null ? position : -1;
    }
    return -1;
  }

  private async getOrCreatePlayer() {
    let currentPlayer = this.player;
    if (this.released || currentPlayer == null) {
      this.player = await this.createPlayer();
      this.released = false
      return this.player!
    } else if (this.prepared) {
      await currentPlayer?.reset()
      this.setPrepared(false);
    }
    return currentPlayer!
  }

  async updateAudioContext(audioContext: AudioContextOhos) {
    if (this.context == audioContext) {
      return
    }
    Log.d(TAG, 'updateAudioContext,value=' + audioContext.toString());
    this.context = audioContext.copy()

    // AudioManager values are set globally
    //audioManager.mode = context.audioMode  // OHOS没有类似接口？
    //audioManager.isSpeakerphoneOn = context.isSpeakerphoneOn

    if (this.player) {
      await this.player.stop()
      await this.player.reset()
      this.setPrepared(false)
      this.player.updateContext(this.context)
      if (this.source) {
        this.player.setSource(this.source)
        await this.configAndPrepare()
      }
    }
  }

  getDuration(): number | null {
    return (this.prepared && this.player) ? this.player!.getDuration() : null;
  }

  getCurrentPosition(): number | null {
    return (this.prepared && this.player) ? this.player!.getCurrentPosition() : null;
  }

  isActuallyPlaying(): boolean {
    return this.playing && this.prepared && this.player != null && this.player!.isActuallyPlaying() == true
  }

  getApplicationContext(): Context {
    return this.ref.getApplicationContext()
  }

  getAudioManager(): audio.AudioManager {
    return this.ref.getAudioManager()
  }

  play() {
    Log.d('WrappedPlayer', 'Starting play request...');
    FocusManager.getInstance().maybeRequestAudioFocus(this);
  }

  async actuallyPlay() {
    if (!this.playing && !this.released) {
      Log.d('WrappedPlayer', 'Actually starting playback...');
      let currentPlayer = this.player;
      this.playing = true
      if (currentPlayer == null) {
        await this.initPlayer()
      } else if (this.prepared) {
        await currentPlayer.start()
        this.ref.handleIsPlaying()
      }
      Log.d('WrappedPlayer', `Playback state updated: playing=${this.playing}`);
    } else {
      Log.d('WrappedPlayer', `Skipping play - already playing: ${this.playing}, released: ${this.released}`);
    }
  }

  async stop() {
    FocusManager.getInstance().handleStop(this);
    if (this.released) {
      return
    }
    if (this.releaseMode != ReleaseMode.RELEASE) {
      await this.pause()
      if (this.prepared) {
        if (this.player?.isLiveStream() == true) {
          await this.player?.stop()
          this.setPrepared(false)
          await this.player?.prepare()
        } else {
          // MediaPlayer does not allow to call player.seekTo after calling player.stop
          this.seek(0)
        }
      }
    } else {
      await this.release()
    }
  }

  async release() {
    FocusManager.getInstance().handleStop(this);
    if (this.released) {
      return
    }
    if (this.playing) {
      await this.player?.stop()
    }

    // Setting source to null will reset released, prepared and playing
    // and also calls player.release()
    this.setSource(null)
    this.player = null
  }

  async pause() {
    if (this.playing) {
      this.playing = false
      if (this.prepared) {
        await this.player?.pause()
      }
    }
  }

  // seek operations cannot be called until after
  // the player is ready.
  seek(position: number) {
    if (this.prepared && this.player?.isLiveStream() != true) {
      this.player?.seekTo(position)
      this.shouldSeekTo = -1
    } else {
      this.shouldSeekTo = position
    }
  }

  /**
   * Player callbacks
   */
  async onPrepared() {
    this.setPrepared(true)
    this.ref.handleDuration(this)
    if (this.playing) {
      await this.player?.start()
      this.ref.handleIsPlaying()
    }
    if (this.shouldSeekTo >= 0 && this.player?.isLiveStream() != true) {
      this.player?.seekTo(this.shouldSeekTo)
    }
  }

  async onCompletion() {
    if (this.releaseMode != ReleaseMode.LOOP) {
      await this.stop()
    }
    this.ref.handleComplete(this)
  }

  onBuffering(percent: number) {
    // TODO(luan): expose this as a stream
  }

  onSeekComplete() {
    this.ref.handleSeekComplete(this)
  }

  handleLog(message: string) {
    this.ref.handleLog(this, message)
  }

  handleError(errorCode?: string, errorMessage?: string, errorDetails?: ESObject) {
    this.ref.handleError(this, errorCode, errorMessage, errorDetails)
  }

  onError(what: number, extra: string): Boolean {
    // TODO 添加OHOS的player错误
    // When an error occurs, reset player to not [prepared].
    // Then no functions will be called, which end up in an illegal player state.
    this.setPrepared(false)
    this.handleError(what.toString(), extra, null)
    return false
  }

  /**
   * Create new player
   */
  private async createPlayer(): Promise<Player> {
    if (this.playerMode == PlayerMode.LOW_LATENCY) {
      let player = new SoundPoolPlayer(this, this.soundPoolManager);
      await player.init();
      return player;
    } else {
      let player = new MediaPlayerPlayer(this, this.context);
      await player.initMediaPlayer()
      return player
    }
  }

  /**
   * Create new player, assign and configure source
   */
  private async initPlayer() {
    let player = await this.createPlayer()
    // Need to set player before calling prepare, as onPrepared may is called before player is assigned
    this.player = player
    if (this.source) {
      await this.player.setSource(this.source)
      await this.configAndPrepare()
    }
  }

  private async configAndPrepare() {
    this.player?.setRate(this.rate)
    this.setVolumeAndBalance(this.volume, this.balance)
    this.player?.setLooping(this.isLooping)
    await this.player?.prepare()
  }

  private setVolumeAndBalance(volume: number, balance: number) {
    let leftVolume = Math.min(1, 1 - balance) * volume
    let rightVolume = Math.min(1, 1 + balance) * volume
    this.player?.setVolume(leftVolume, rightVolume)
  }

  async dispose() {
    await this.release();
    FocusManager.getInstance().unsubscribePlayer(this);
    this.eventHandler.dispose();
  }

  startContinuousTask() {
    this.ref.startContinuousTask()
  }

  stopContinuousTask() {
    this.ref.stopContinuousTask()
  }
}