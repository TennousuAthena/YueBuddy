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

import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodChannel, { MethodResult, } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { EventSink, StreamHandler } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { AbilityAware, AbilityPluginBinding, BinaryMessenger, EventChannel, Log } from '@ohos/flutter_ohos';
import { HashMap } from '@kit.ArkTS';
import AudioContextOhos from './AudioContextOhos';
import { SoundPoolManager } from './player/SoundPoolPlayer';
import WrappedPlayer from './player/WrappedPlayer';
import audio from '@ohos.multimedia.audio';
import UrlSource from './source/UrlSource';
import BytesSource from './source/BytesSource';
import { parseReleaseMode } from './ReleaseMode';
import { parsePlayerMode } from './PlayerMode';
import { WantAgent, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { avSession as AVSessionManager } from '@kit.AVSessionKit';

const TAG = "AudioplayersPlugin";

export default class AudioplayersPlugin implements FlutterPlugin, AbilityAware, IUpdateCallback {
  private methods?: MethodChannel = undefined;
  private globalMethods?: MethodChannel = undefined;
  private globalEvents?: EventHandler = undefined;
  private context?: Context = undefined;
  private binaryMessenger?: BinaryMessenger = undefined;
  private soundPoolManager?: SoundPoolManager = undefined;
  private players = new HashMap<string, WrappedPlayer>();
  private defaultAudioContext = new AudioContextOhos();
  private updateInterval: number | null = null;
  private abilityBinding?: AbilityPluginBinding = undefined;
  private session?: AVSessionManager.AVSession = undefined;
  private isStartContinuousTask = false;

  getUniqueClassName(): string {
    return "AudioplayersPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext()
    this.binaryMessenger = binding.getBinaryMessenger()
    this.soundPoolManager = new SoundPoolManager(this)
    this.methods = new MethodChannel(binding.getBinaryMessenger(), "xyz.luan/audioplayers")
    this.methods.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        this.methodCall(call, result)
      }
    })
    this.globalMethods = new MethodChannel(binding.getBinaryMessenger(), "xyz.luan/audioplayers.global")
    this.globalMethods.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        this.globalMethodCall(call, result)
      }
    })
    this.globalEvents = new EventHandler(new EventChannel(binding.getBinaryMessenger(), "xyz.luan/audioplayers.global/events"))
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.stopUpdates()
    this.players.forEach((value: WrappedPlayer, key: string) => value.dispose())
    this.players.clear()
    this.soundPoolManager?.dispose()
    this.globalEvents?.dispose()
    this.stopUpdates();
  }

  private globalMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case "init":
        this.players.forEach((value: WrappedPlayer, key: string) => value.dispose())
        this.players.clear()
        break;
      case "setAudioContext":
      // TODO 没有相关API
      //let audioManager = this.getAudioManager()
      //audioManager.mode = defaultAudioContext.audioMode
      //audioManager.isSpeakerphoneOn = defaultAudioContext.isSpeakerphoneOn
        this.defaultAudioContext = this.getAudioContext(call)
        break;
      case "emitLog":
        let message = this.getObjectValue(call, "message", "message is required") as string;
        this.handleGlobalLog(message);
        break;
      case "emitError":
        let code = this.getObjectValue(call, "code", "code is required") as string;
        message = this.getObjectValue(call, "message", "message is required") as string;
        this.handleGlobalError(code, message, null)
        break;
      default:
        result.notImplemented()
        break;
    }
  }

  private getMimeType(url: string): string {
      const extension = url.split('.').pop()?.toLowerCase();
      const mimeTypes: Record<string, string> = {
          'mp3': 'audio/mpeg',
          'wav': 'audio/wav',
          'ogg': 'audio/ogg',
          'mp4': 'video/mp4',
          'avi': 'video/x-msvideo',
          'txt': 'text/plain',  // txt 不是媒体文件
      };
      return mimeTypes[extension || ''] || 'application/octet-stream';
  }

  private async methodCall(call: MethodCall, response: MethodResult) {
    let playerId = call.argument("playerId") as string
    if (playerId == null || playerId == undefined) {
      response.success(1)
      return;
    }
    try {
      if (call.method == "create") {
        let eventHandler = new EventHandler(new EventChannel(this.binaryMessenger!, `xyz.luan/audioplayers/events/${playerId}`))
        this.players.set(playerId, new WrappedPlayer(this, eventHandler, this.defaultAudioContext.copy(), this.soundPoolManager!))
        response.success(1);
        return;
      }
      let player = this.getPlayer(playerId)
      if (player == null) {
        response.error("OhosAudioError", "not find player", Error("not find player"))
        return;
      }
      switch (call.method) {
        case "setSourceUrl":
          let url = this.getObjectValue(call, "url", "url is required") as string;
          let isLocal = call.hasArgument("isLocal") ? (call.argument("isLocal") as boolean) : false;
          const mimeType = this.getMimeType(url);
          console.log("Detected MIME type:", mimeType);
          if (mimeType.startsWith('text/')) {
              console.error("Text file cannot be played as media");
              player.handleError("AudioError", "Failed to set source. For troubleshooting, https://github.com/bluefireteam/audioplayers/blob/main/troubleshooting.md", null)
              return;
          }
          await player!.setSource(new UrlSource(url, isLocal));
          break;
        case "setSourceBytes":
          let bytes = this.getObjectValue(call, "bytes", "bytes are required") as ArrayBuffer
          player.setSource(new BytesSource(bytes))
          break;
        case "resume":
          await this.startContinuousTask();
          player.play();
          break;
        case "pause":
          player.pause();
          await this.stopContinuousTask();
          break;
        case "stop":
          await player.stop();
          break;
        case "release":
          await player.release();
          break;
        case "seek":
          let position = this.getObjectValue(call, "position", "position is required") as number;
          player.seek(position);
          break;
        case "setVolume":
          let volume = this.getObjectValue(call, "volume", "volume is required") as number;
          player.setVolume(volume);
          break;
        case "setBalance":
          let balance = this.getObjectValue(call, "balance", "balance is required") as number;
          player.setBalance(balance);
          break;
        case "setPlaybackRate":
          let rate = this.getObjectValue(call, "playbackRate", "playbackRate is required") as number;
          player.setRate(rate);
          break;
        case "getDuration":
          let duration = player.getDuration();
          response.success(duration ? duration : 0);
          return;
        case "getCurrentPosition":
          let postion = player.getCurrentPosition();
          response.success(postion ? postion : 0)
          return;
        case "setReleaseMode":
          let releaseMode = this.getObjectValue(call, "releaseMode", "releaseMode is required") as string
          player.setReleaseMode(parseReleaseMode(releaseMode));
          break;
        case "setPlayerMode":
          let playerMode = this.getObjectValue(call, "playerMode", "playerMode is required") as string
          player.setPlayerMode(parsePlayerMode(playerMode));
          break;
        case "setAudioContext":
          let audioContext = this.getAudioContext(call);
          player.updateAudioContext(audioContext)
          break;
        case "emitLog":
          let message = this.getObjectValue(call, "message", "message is required") as string
          player.handleLog(message)
          break;
        case "emitError":
          let code = this.getObjectValue(call, "code", "code is required") as string
          message = this.getObjectValue(call, "message", "message is required") as string
          player.handleError(code, message, null)
          break;
        case "dispose":
          player.dispose()
          this.players.remove(playerId)
          break;
        default:
          response.notImplemented()
          return;
      }
      response.success(1)
    } catch (e) {
      response.error("OhosAudioError", e.message, e)
    }
  }

  private getPlayer(playerId: string): WrappedPlayer | null {
    if (this.players.hasKey(playerId)) {
      return this.players.get(playerId)
    }
    this.error("Player has not yet been created or has already been disposed.")
    return null
  }

  getApplicationContext(): Context {
    return this.context!
  }

  getAudioManager(): audio.AudioManager {
    return audio.getAudioManager();
  }

  handleIsPlaying() {
    this.startUpdates()
  }

  handleDuration(player: WrappedPlayer) {
    let map = new Map<string, number>();
    let dutraion = player.getDuration();
    map.set("value", dutraion ? dutraion : 0);
    player.eventHandler.success("audio.onDuration", map);
  }

  handleComplete(player: WrappedPlayer) {
    player.eventHandler.success("audio.onComplete");
  }

  handlePrepared(player: WrappedPlayer, isPrepared: boolean) {
    let map = new Map<string, boolean>();
    map.set("value", isPrepared);
    player.eventHandler.success("audio.onPrepared", map);
  }

  handleLog(player: WrappedPlayer, message: string) {
    let map = new Map<string, string>();
    map.set("value", message);
    player.eventHandler.success("audio.onLog", map);
  }

  handleGlobalLog(message: string) {
    let map = new Map<string, string>();
    map.set("value", message);
    this.globalEvents!.success("audio.onLog", map);
  }

  handleError(player: WrappedPlayer, errorCode?: string, errorMessage?: string, errorDetails?: ESObject) {
    player.eventHandler.error(errorCode, errorMessage, errorDetails)
  }

  handleGlobalError(errorCode?: string, errorMessage?: string, errorDetails?: ESObject) {
    this.globalEvents!.error(errorCode, errorMessage, errorDetails)
  }

  handleSeekComplete(player: WrappedPlayer) {
    let map = new Map<string, number>();
    let position = player.getCurrentPosition();
    map.set("value", position ? position : 0);
    player.eventHandler.success("audio.onSeekComplete")
    player.eventHandler.success("audio.onCurrentPosition", map)
  }

  startUpdates() {
    this.stopUpdates();
    this.updateInterval = setInterval(() => {
      this.updateCallback();
    }, 200)
  }

  stopUpdates() {
    if (this.updateInterval) {
      clearInterval(this.updateInterval)
      this.updateInterval = null
    }
  }

  private updateCallback() {
    let mediaPlayers = this.players;
    let channel = this.methods;
    if (mediaPlayers == null || channel == null) {
      this.stopUpdates()
      return
    }
    let isAnyPlaying = false
    mediaPlayers.forEach((player: WrappedPlayer, key: string) => {
      if (player.isActuallyPlaying()) {
        isAnyPlaying = true
        let time = player.getCurrentPosition()

        let map = new Map<string, number>();
        map.set("value", time ? time : 0);
        player.eventHandler.success("audio.onCurrentPosition", map)
      }
    })
    if (!isAnyPlaying) {
      this.stopUpdates()
    }
  }

  private getAudioContext(call: MethodCall): AudioContextOhos {
    let contextOhos = new AudioContextOhos();
    contextOhos.isSpeakerphoneOn = this.getObjectValue(call, "isSpeakerphoneOn", "isSpeakerphoneOn is required") as boolean
    contextOhos.rendererFlags = this.getObjectValue(call, "rendererFlags", "rendererFlags is required") as number
    contextOhos.usageType = this.getObjectValue(call, "usageType", "usageType is required") as number
    contextOhos.audioScene = this.getObjectValue(call, "audioScene", "audioScene is required") as number
    contextOhos.stayAwake =  this.getObjectValue(call, "stayAwake", "stayAwake is required") as boolean
    contextOhos.audioFocus = this.getObjectValue(call, "audioFocus", "audioFocus is required") as number
    return contextOhos;
  }

  private getObjectValue(call: MethodCall, key: string, error: string): ESObject {
    if (call.hasArgument(key)) {
      return call.argument(key);
    }
    this.error(error)
  }

  private error(msg: string) {
    throw new Error(msg);
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityBinding = binding
  }

  onDetachedFromAbility(): void {
    this.pauseAllPlayers()
    this.abilityBinding = undefined
    this.stopContinuousTask()
  }

  pauseOtherPlayers(currentPlayer: WrappedPlayer): void {
    Log.d(TAG, `Pausing other players, current player: ${currentPlayer ? 'valid' : 'null'}`);
    let pausedCount = 0;
    this.players.forEach((player: WrappedPlayer, playerId: string) => {
      if (player !== currentPlayer && player.isPlaying()) {
        player.pause();
        pausedCount++;
        Log.d(TAG, `Paused player ${playerId} due to audio focus change`);
      }
    });
    Log.d(TAG, `Total ${pausedCount} players paused`);
  }

  pauseAllPlayers(): void {
    this.players.forEach((player: WrappedPlayer, playerId: string) => {
      if (player.isPlaying()) {
        player.pause()
      }
    })
  }

  async startContinuousTask() {
    Log.d(TAG, `startContinuousTask`);
    if(this.isStartContinuousTask){
      return;
    }
    this.isStartContinuousTask = true;

    let context = this.abilityBinding!.getAbility().context;
    let type: AVSessionManager.AVSessionType = 'audio';

    try {
      this.session = await AVSessionManager.createAVSession(context, 'audioplayers', type);
      // 激活接口要在元数据、控制命令注册完成之后再执行
      await this.session?.activate();
      Log.d(TAG, `session create done : sessionId : ${this.session?.sessionId}`);
    } catch (error) {
      Log.e(TAG,`session create failed. code is ${(error as BusinessError).code} message is ${(error as BusinessError).message}`);
    }

    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: context?.abilityInfo.bundleName,
          abilityName: context?.abilityInfo.name
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };

    try {
      let wantAgentObj: WantAgent = await wantAgent.getWantAgent(wantAgentInfo);
      await backgroundTaskManager.startBackgroundRunning(context, backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, wantAgentObj);
    } catch (error) {
      Log.e(TAG,`startBackgroundRunning failed. code is ${(error as BusinessError).code} message is ${(error as BusinessError).message}`);
    }
  }

  async stopContinuousTask() {
    Log.d(TAG, `stopContinuousTask`);
    if(!this.isStartContinuousTask){
      return;
    }
    this.isStartContinuousTask = false;

    try {
      await this.session?.deactivate();
      await this.session?.destroy();
    } catch (error) {
      Log.e(TAG,`session destroy failed. code is ${(error as BusinessError).code} message is ${(error as BusinessError).message}`);
    }

    try {
      await backgroundTaskManager.stopBackgroundRunning(this.abilityBinding?.getAbility().context);
    } catch (error) {
      Log.e(TAG,`stopBackgroundRunning failed. code is ${(error as BusinessError).code} message is ${(error as BusinessError).message}`);
    }
  }
}

export class EventHandler implements StreamHandler {
  private eventChannel?: EventChannel = undefined;
  private eventSink: EventSink | null = null

  constructor(eventChannel: EventChannel) {
    this.eventChannel = eventChannel;
    this.eventChannel.setStreamHandler(this)
  }

  onListen(args: ESObject, events: EventSink): void {
    this.eventSink = events
  }

  onCancel(args: ESObject): void {
    this.eventSink = null
  }

  success(method: string, args: Map<string, ESObject> = new Map<string, ESObject>()) {
    args.set("event", method)
    this.eventSink?.success(args)
  }

  error(errorCode?: string, errorMessage?: string, errorDetails?: ESObject) {
    this.eventSink?.error(errorCode, errorMessage, errorDetails)
  }

  dispose() {
    if (this.eventSink) {
      this.eventSink.endOfStream();
      this.onCancel(null);
    }
    this.eventChannel?.setStreamHandler(null)
  }
}

interface IUpdateCallback {
  stopUpdates(): void

  startUpdates(): void
}