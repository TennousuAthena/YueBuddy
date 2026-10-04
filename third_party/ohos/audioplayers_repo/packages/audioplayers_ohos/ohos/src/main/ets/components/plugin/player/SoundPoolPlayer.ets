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
 
import audio from '@ohos.multimedia.audio';
import media from '@ohos.multimedia.media';
import AudioContextOhos from '../AudioContextOhos';
import AudioplayersPlugin from '../AudioplayersPlugin';
import Source from '../source/Source';
import UrlSource from '../source/UrlSource';
import Player from './Player';
import WrappedPlayer from './WrappedPlayer';
import { HashMap } from '@kit.ArkTS';

const MAX_STREAMS = 32;

export default class SoundPoolPlayer implements Player {
  wrappedPlayer: WrappedPlayer;
  private soundPoolManager: SoundPoolManager;
  soundId: number | null = null;
  private streamId: number | null = null;
  private audioContext: AudioContextOhos;
  private soundPoolWrapper: SoundPoolWrapper | null = null;
  private soundPool: media.SoundPool | null = null;

  constructor(wrappedPlayer: WrappedPlayer, soundPoolManager: SoundPoolManager) {
    this.wrappedPlayer = wrappedPlayer;
    this.soundPoolManager = soundPoolManager;
    this.audioContext = wrappedPlayer.context;
  }

  async init() {
    await this.soundPoolManager.createSoundPoolWrapper(MAX_STREAMS, this.audioContext);
    this.soundPoolWrapper = this.soundPoolManager.getSoundPoolWrapper(this.audioContext);
    this.soundPool = this.soundPoolWrapper!.soundPool;
  }

  async setAudioContext(audioContext: AudioContextOhos) {
    if (!audioContext.equals(audioContext)) {
      this.audioContext = audioContext;
      await this.release();
      await this.init()
    }
  }

  getDuration(): number | null {
    return null;
  }

  getCurrentPosition(): number | null {
    return null;
  }

  isActuallyPlaying(): boolean {
    return false;
  }

  isLiveStream(): boolean {
    return false;
  }

  async start() {
    let streamId = this.streamId
    let soundId = this.soundId
    if (soundId != null) {
      let playParameters: media.PlayParameters = {
        loop: this.wrappedPlayer.getLooping() ? -1 : 0,
        rate: this.convertRate(this.wrappedPlayer.getRate()), // 正常倍速
        leftVolume: this.wrappedPlayer.getVolume(), // range = 0.0-1.0
        rightVolume: this.wrappedPlayer.getVolume(), // range = 0.0-1.0
        priority: 0, // 最低优先级
      }
      this.streamId = await this.soundPool!.play(this.soundId, playParameters)!
    }
  }

  pause() {
    if (this.streamId != null) {
      this.soundPool!.stop(this.streamId)
      this.streamId = null;
    }
  }

  stop() {
    if (this.streamId != null) {
      this.soundPool!.stop(this.streamId)
      this.streamId = null;
    }
  }

  seekTo(position: number) {
    //TODO
    //this.unsupportedOperation("seek")
  }

  async release() {
    await this.stop()
    if (this.soundId == null) {
      return
    }
    if (this.getUrlSource() == null) {
      return;
    }
    if (!this.soundPoolWrapper!.urlToPlayers.hasKey(this.getUrlSource())) {
      return;
    }
    let playersForSoundId = this.soundPoolWrapper!.urlToPlayers.get(this.getUrlSource());
    if (playersForSoundId.length == 1 && playersForSoundId[0] == this) {
      this.soundPoolWrapper!.urlToPlayers.remove(this.getUrlSource())
      await this.soundPool!.unload(this.soundId)
      this.soundPoolWrapper!.soundIdToPlayer.remove(this.soundId)
      this.wrappedPlayer.handleLog("unloaded soundId $soundId")
    } else {
      // This is not the last player using the soundId, just remove it from the list.
      let index = playersForSoundId.indexOf(this);
      if (index > -1) {
        playersForSoundId.splice(index, 1)
      }
    }
    this.soundId = null
  }

  async setVolume(leftVolume: number, rightVolume: number) {
    if (this.streamId != null) {
      await this.soundPool!.setVolume(this.streamId, leftVolume, rightVolume)
    }
  }

  async setRate(rate: number) {
    if (this.streamId != null) {
      await this.soundPool!.setRate(this.streamId, this.convertRate(rate))
    }
  }

  async setLooping(looping: boolean) {
    if (this.streamId != null) {
      await this.soundPool!.setLoop(this.streamId, looping ? -1 : 0);
    }
  }

  updateContext(context: AudioContextOhos) {
    this.audioContext = context
  }

  setSource(source: Source) {
    source.setForSoundPool(this)
  }

  prepare() {
    // sound pool automatically prepares when source URL is set
  }

  reset() {
    // TODO(luan): what do I do here?
  }

  private unsupportedOperation(message: string) {
    throw new Error(`LOW_LATENCY mode does not support: ${message}`)
  }

  private convertRate(rate: number): audio.AudioRendererRate {
    let ohrate = audio.AudioRendererRate.RENDER_RATE_NORMAL;
    if (this.wrappedPlayer.getRate() < 1) {
      ohrate = audio.AudioRendererRate.RENDER_RATE_HALF;
    } else if (this.wrappedPlayer.getRate() > 1) {
      ohrate = audio.AudioRendererRate.RENDER_RATE_DOUBLE;
    }
    return ohrate;
  }

  async setUrlSource(urlSource: UrlSource) {
    if (this.soundId != null) {
      await this.release()
    }
    if (!this.soundPoolWrapper!.urlToPlayers.hasKey(urlSource)) {
      this.soundPoolWrapper!.urlToPlayers.set(urlSource, Array<SoundPoolPlayer>())
    }
    let urlPlayers = this.soundPoolWrapper!.urlToPlayers.get(urlSource);
    let originalPlayer = urlPlayers.length > 0 ? urlPlayers[0] : null;
    if (originalPlayer != null) {
      // Sound has already been loaded - reuse the soundId.
      let prepared = originalPlayer.wrappedPlayer.getPrepared();
      this.wrappedPlayer.setPrepared(prepared);
      this.soundId = originalPlayer.soundId
      this.wrappedPlayer.handleLog(`Reusing soundId ${this.soundId} for ${urlSource.url} is prepared=${prepared}`)
    } else {
      // First one for this URL - load it.
      let start = new Date().getTime();
      this.wrappedPlayer.setPrepared(false);
      this.wrappedPlayer.handleLog(`Fetching actual URL for ${urlSource.url}}`)
      let actualUrl = await urlSource.getAudioPathForSoundPool(this.wrappedPlayer.getApplicationContext());
      this.wrappedPlayer.handleLog(`Now loading ${actualUrl}`)
      let intSoundId = await this.soundPool!.load(actualUrl)
      this.soundPoolWrapper!.soundIdToPlayer.set(intSoundId, this)
      this.soundId = intSoundId
      this.wrappedPlayer.handleLog(`time to call load() for ${urlSource.url}: ${new Date().getTime() - start} player=${this}}`,)
    }
    urlPlayers.push(this);
  }

  getUrlSource(): UrlSource | null {
    let source = this.wrappedPlayer.getSource();
    return source ? this.wrappedPlayer.getSource() as UrlSource : null
  }
}

export class SoundPoolManager {
  private ref: AudioplayersPlugin;
  private legacySoundPoolWrapper: SoundPoolWrapper | null = null
  private soundPoolWrappers = new HashMap<string, SoundPoolWrapper>()

  constructor(plugin: AudioplayersPlugin) {
    this.ref = plugin;
  }

  async createSoundPoolWrapper(maxStreams: number, audioContext: AudioContextOhos) {
    let attrs = audioContext.buildAttributes();
    let key = attrs.usage + "" + attrs.rendererFlags;
    if (!this.soundPoolWrappers.hasKey(key)) {
      let soundPool = await media.createSoundPool(maxStreams, attrs);
      this.ref.handleGlobalLog("Create SoundPool with " + key);
      let soundPoolWrapper = new SoundPoolWrapper(soundPool);
      soundPoolWrapper.soundPool.on('loadComplete', (soundId: number) => {
        this.ref.handleGlobalLog(`Loaded ${soundId}`)
        let loadingPlayer = soundPoolWrapper.soundIdToPlayer.get(soundId)
        let urlSource = loadingPlayer.getUrlSource()
        if (urlSource) {
          soundPoolWrapper.soundIdToPlayer.remove(loadingPlayer.soundId);
          let urlPlayers = soundPoolWrapper.urlToPlayers.get(urlSource)
          for (let player of urlPlayers) {
            player.wrappedPlayer.handleLog(`Marking ${player.soundId} as loaded`);
            player.wrappedPlayer.setPrepared(true);
            if (player.wrappedPlayer.isPlaying()) {
              player.wrappedPlayer.handleLog(`Delayed start of ${player.soundId}`);
              player.start();
            }
          }
        }
      });
      this.soundPoolWrappers.set(key, soundPoolWrapper);
    }
  }

  /**
   * Get the [SoundPoolWrapper] with the given [audioContext].
   */
  getSoundPoolWrapper(audioContext: AudioContextOhos): SoundPoolWrapper | null {
    let attrs = audioContext.buildAttributes();
    let key = attrs.usage + "" + attrs.rendererFlags;
    return this.soundPoolWrappers.hasKey(key) ? this.soundPoolWrappers.get(key) : null;
  }

  dispose() {
    this.soundPoolWrappers.forEach((value: SoundPoolWrapper, key: string) => value.dispose())
    this.soundPoolWrappers.clear()
  }
}

class SoundPoolWrapper {
  soundPool: media.SoundPool;
  soundIdToPlayer = new HashMap<number, SoundPoolPlayer>()
  urlToPlayers = new  HashMap<UrlSource, Array<SoundPoolPlayer>>()

  constructor(soundPool: media.SoundPool) {
    this.soundPool = soundPool;
  }

  /** For the onLoadComplete listener, track which sound id is associated with which player. An entry only exists until
   * it has been loaded.
   */

  /** This is to keep track of the players which share the same sound id, referenced by url. When a player release()s, it
   * is removed from the associated player list. The last player to be removed actually unloads() the sound id and then
   * the url is removed from this map.
   */
  dispose() {
    this.soundPool.off('loadComplete');
    this.soundPool.release();
    this.soundIdToPlayer.clear();
    this.urlToPlayers.clear();
  }
}