/**
 * MIT License
 *
 * Copyright (C) 2026 Huawei Device Co., Ltd.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { BusinessError, deviceInfo, ErrorCallback } from '@kit.BasicServicesKit';
import { ArkTSUtils } from '@kit.ArkTS';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { fileIo } from '@kit.CoreFileKit';
import { LOGGER } from './Logger';

const FLUTTER_TTS_TAG = "FlutterTtsPlugin";

/** FlutterTtsPlugin **/
export default class FlutterTtsPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: Context | null = null;
  private ttsEngine: textToSpeech.TextToSpeechEngine | null = null;
  private engineLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();
  // 语速 支持范围[0.5-2]
  private speed: number = 1.0;
  // 音量 支持范围[0-2]
  private volume: number = 1.0;
  // 音调 支持范围[0.5-2]
  private pitch: number = 1.0;
  private person: number = 0;
  // 语言
  private language: string = "zh-CN";
  // 0：排队模式播报。1：抢占模式播报。
  private queueMode: number = 0;
  // 播报通道 3: 默认媒体通道, 13: 导航通道
  private soundChannel: number = 3;
  // 开始播放前静默时间（毫秒）
  private silence: number = 0;
  // 延时器 id 列表
  private timeoutIds: number[] = [];

  // ---------- awaitSpeakCompletion 相关 ----------
  private awaitSpeakCompletion: boolean = false;
  private speakResult: MethodResult | null = null;

  // ---------- awaitSynthCompletion / synthesizeToFile 相关 ----------
  private awaitSynthCompletion: boolean = false;
  private synthResult: MethodResult | null = null;
  private synthMode: boolean = false;
  private synthAudioBuffers: ArrayBuffer[] = [];
  private synthFilePath: string = '';

  // ---------- 暂停/继续 相关 ----------
  /** pause() 时设为 true，引擎停止后 onStop 检测此标记发 speak.onPause */
  private isPaused: boolean = false;

  // ---------- 语音监听器 相关 ----------
  private speakListener: textToSpeech.SpeakListener | null = null;

  // ---------- 下载任务追踪 相关 ----------
  private activeDownloadResponses: textToSpeech.DownloadResponse[] = [];

  // ---------- setEngine 异步任务追踪 相关 ----------
  private pendingSetEngineResult: MethodResult | null = null;
  // 标记插件是否已分离，防止异步 createEngine 在 detach 后创建无法释放的引擎
  private detached: boolean = false;

  /**
   * 构造函数，初始化 FlutterTtsPlugin 实例
   */
  constructor() {
  }

  /**
   * 获取插件唯一类名
   * @returns 类名字符串
   */
  getUniqueClassName(): string {
    return "FlutterTtsPlugin";
  }

  /**
   * 插件附加到 Flutter 引擎时的回调
   * @param binding - Flutter 插件绑定对象，提供 BinaryMessenger 和 ApplicationContext
   */
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.detached = false;
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "flutter_tts");
    this.channel.setMethodCallHandler(this);
    this.context = binding.getApplicationContext();
    this.createEngine().catch((e: Error) => {
      LOGGER.error(FLUTTER_TTS_TAG, 'createEngine failed in onAttachedToEngine: ' + e);
      // 通知 Flutter 层初始化失败
      this.invokeMethodCall("speak.onError", `TTS engine initialization failed: ${e}`);
    });
  }

  /**
   * Ability 附加到插件时的回调
   * @param binding - Flutter 插件绑定对象
   */
  onAttachedToAbility(binding: FlutterPluginBinding): void {
    this.detached = false;
    LOGGER.info(FLUTTER_TTS_TAG, 'onAttachedToAbility called');
    if (!this.ttsEngine) {
      this.createEngine().catch((e: Error) => {
        LOGGER.error(FLUTTER_TTS_TAG, 'createEngine failed in onAttachedToAbility: ' + e);
        this.invokeMethodCall("speak.onError", `TTS engine initialization failed: ${e}`);
      });
    }
  }

  /**
   * Ability 从插件分离时的回调
   * @param binding - Flutter 插件绑定对象
   */
  onDetachedFromAbility(binding: FlutterPluginBinding): void {
    this.detached = true;
    LOGGER.info(FLUTTER_TTS_TAG, 'onDetachedFromAbility called');
    this.clearAllPendingTimeouts();
    // 清理 pending result，避免 Dart Future 泄漏
    if (this.speakResult !== null) {
      this.speakResult.success(0);
      this.speakResult = null;
    }
    if (this.synthResult !== null) {
      this.synthResult.success(0);
      this.synthResult = null;
    }
    if (this.pendingSetEngineResult !== null) {
      this.pendingSetEngineResult.success(0);
      this.pendingSetEngineResult = null;
    }
    // 重置合成状态
    this.synthMode = false;
    this.synthAudioBuffers = [];
    this.synthFilePath = '';
    this.stop();
    try {
      this.ttsEngine?.setListener(null);
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, 'setListener(null) failed in onDetachedFromAbility: ' + e);
    }
    this.speakListener = null;
    // 取消所有活跃的下载任务
    this.cancelAllActiveDownloads();
    this.shutdown();
    this.context = null;
    if (this.channel !== null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
  }

  /**
   * 取消所有活跃的下载任务
   */
  private cancelAllActiveDownloads(): void {
    for (const response of this.activeDownloadResponses) {
      try {
        response.off('start');
        response.off('progress');
        response.off('complete');
        response.off('cancel');
        response.off('error');
      } catch (e) {
        LOGGER.error(FLUTTER_TTS_TAG, 'cancelActiveDownload failed: ' + e);
      }
    }
    this.activeDownloadResponses = [];
  }

  /**
   * 从活跃下载列表中移除指定响应
   * @param response 要移除的下载响应
   */
  private removeActiveDownloadResponse(response: textToSpeech.DownloadResponse): void {
    const index = this.activeDownloadResponses.indexOf(response);
    if (index > -1) {
      this.activeDownloadResponses.splice(index, 1);
    }
  }

  /**
   * 注销下载任务的所有回调
   * @param downloadResponse 下载响应对象
   * @param startCb 开始回调
   * @param progressCb 进度回调
   * @param completeCb 完成回调
   * @param cancelCb 取消回调
   * @param errorCb 错误回调
   */
  private unregisterDownloadCallbacks(
    downloadResponse: textToSpeech.DownloadResponse,
    startCb: Callback<string>,
    progressCb: Callback<string>,
    completeCb: Callback<textToSpeech.VoiceInfo>,
    cancelCb: Callback<string>,
    errorCb: ErrorCallback<BusinessError>): void {
    try { downloadResponse.off('start', startCb); } catch (_) {}
    try { downloadResponse.off('progress', progressCb); } catch (_) {}
    try { downloadResponse.off('complete', completeCb); } catch (_) {}
    try { downloadResponse.off('cancel', cancelCb); } catch (_) {}
    try { downloadResponse.off('error', errorCb); } catch (_) {}
  }

  /**
   * 插件从 Flutter 引擎分离时的回调
   * @param binding - Flutter 插件绑定对象
   */
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.detached = true;
    this.clearAllPendingTimeouts();
    // 清理 pending result，避免 Dart 端 Future 泄漏
    if (this.speakResult !== null) {
      this.speakResult.success(0);
      this.speakResult = null;
    }
    if (this.synthResult !== null) {
      this.synthResult.success(0);
      this.synthResult = null;
    }
    if (this.pendingSetEngineResult !== null) {
      this.pendingSetEngineResult.success(0);
      this.pendingSetEngineResult = null;
    }
    this.synthMode = false;
    this.synthAudioBuffers = [];
    this.synthFilePath = '';
    this.stop();
    // 显式断开 speakListener 闭包引用链
    try {
      this.ttsEngine?.setListener(null);
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, 'setListener(null) failed: ' + e);
    }
    this.speakListener = null;
    // 取消所有活跃的下载任务
    this.cancelAllActiveDownloads();
    this.shutdown();
    this.context = null;
    if (this.channel !== null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
  }

  /**
   * 处理来自 Flutter Dart 端的方法调用
   * @param call - 方法调用对象，包含方法名和参数
   * @param result - 方法调用结果回调
   */
  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
      case "speak": { this.handleSpeak(call, result); break; }
      case "awaitSpeakCompletion": { this.handleAwaitSpeakCompletion(call, result); break; }
      case "awaitSynthCompletion": { this.handleAwaitSynthCompletion(call, result); break; }
      case "getMaxSpeechInputLength": { this.handleGetMaxSpeechInputLength(result); break; }
      case "synthesizeToFile": { this.handleSynthesizeToFile(call, result); break; }
      case "pause": {
        // OHOS TextToSpeech 引擎无原生 pause API，通过 stop() 模拟暂停
        this.pause(result); break;
      }
      case "stop": { this.handleStop(result); break; }
      case "setEngine": { this.handleSetEngine(result); break; }
      case "setSpeechRate": { this.handleSetSpeechRate(call, result); break; }
      case "setVolume": { this.handleSetVolume(call, result); break; }
      case "setPitch": { this.handleSetPitch(call, result); break; }
      case "setLanguage": { this.handleSetLanguage(call, result); break; }
      case "getLanguages": { this.handleGetLanguages(result); break; }
      case "getVoices": { this.getVoices(result); break; }
      case "getSpeechRateValidRange": { this.handleGetSpeechRateValidRange(result); break; }
      case "getEngines": { this.handleGetEngines(result); break; }
      case "getDefaultEngine": { this.handleGetDefaultEngine(result); break; }
      case "getDefaultVoice": { this.getDefaultVoice(result); break; }
      case "setVoice": { this.handleSetVoiceCommand(call, result); break; }
      case "clearVoice": { this.clearVoice(result); break; }
      case "isLanguageAvailable": { this.handleIsLanguageAvailable(call, result); break; }
      case "setSilence": { this.handleSetSilence(call, result); break; }
      case "setSharedInstance": { this.handleSetSharedInstance(result); break; }
      case "isLanguageInstalled": {
        const lang = call.args as string;
        if (typeof lang !== 'string') {
          result.error('INVALID_ARGUMENT', 'isLanguageInstalled expects a string argument', '');
          break;
        }
        this.isLanguageInstalledInternal(lang, result); break;
      }
      case "areLanguagesInstalled": {
        const languages = call.args as string[];
        if (!Array.isArray(languages)) {
          result.error('INVALID_ARGUMENT', 'areLanguagesInstalled expects a string array argument', '');
          break;
        }
        this.areLanguagesInstalledInternal(languages, result); break;
      }
      case "setQueueMode": { this.handleSetQueueMode(call, result); break; }
      case "setAudioAttributesForNavigation": { this.handleSetAudioAttributesForNavigation(result); break; }
      case "downloadVoice": {
        const downloadParams = call.args as Map<string, string>;
        if (!(downloadParams instanceof Map)) {
          result.error('INVALID_ARGUMENT', 'downloadVoice expects a Map argument', '');
          break;
        }
        this.downloadVoice(result, downloadParams); break;
      }
      case "autoStopSharedSession": { this.handleAutoStopSharedSession(result); break; }
      default: { result.notImplemented(); break; }
      }
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, `onMethodCall unhandled exception: ${call.method} - ${e}`);
      result.error('UNHANDLED_EXCEPTION', `Method ${call.method} failed: ${e}`, null);
    }
  }

  /**
   * 处理 speak 方法调用
   * @param call - 方法调用对象
   * @param result - 方法调用结果回调
   */
  private handleSpeak(call: MethodCall, result: MethodResult): void {
    let text: string = '';
    let focus: boolean = false;
    if (typeof call.args === 'object' && call.args !== null) {
      // Map 格式：直接取值（与 Android 一致）
      const args = call.args as Record<string, Object>;
      text = (args['text'] as string) || '';
      focus = (args['focus'] as boolean) || false;
    } else if (typeof call.args === 'string') {
      const argStr = call.args as string;
      // 字符串格式：可能为 "text:xxx,focus:xxx"，用位置截取避免逗号截断
      if (argStr.startsWith('text:')) {
        const focusIdx: number = argStr.lastIndexOf(',focus:');
        if (focusIdx > 0) {
          text = argStr.substring(5, focusIdx);
          const focusVal: string = argStr.substring(focusIdx + 7); // 7 = ",focus:".length
          focus = focusVal === 'true';
        } else {
          text = argStr.substring(5);
        }
      } else {
        text = argStr;
      }
    }
    if (!text) {
      result.error('INVALID_ARGUMENT', 'Text is empty', '');
      return;
    }
    // 合成进行中，拒绝常规 speak 调用
    if (this.synthMode) {
      result.error('BUSY', 'Synthesize in progress, speak rejected', '');
      return;
    }
    // OHOS 无音频焦点机制，focus 参数不影响 queueMode
    const effectiveQueueMode = this.queueMode;
    // 仅抢占模式（queueMode=1）下已有 speak 未完成时拒绝新调用，排队模式允许追加
    if (this.awaitSpeakCompletion && this.queueMode === 1 && this.speakResult !== null) {
      result.error('BUSY', 'Another speak is pending, please wait', '');
      return;
    }
    this.speak(text, effectiveQueueMode);
    // 仅抢占模式时才占用 speakResult 等待完成回调，排队模式直接返回
    if (this.awaitSpeakCompletion && this.queueMode === 1) {
      this.speakResult = result;
    } else {
      result.success(1);
    }
  }

  /**
   * 处理 awaitSpeakCompletion 方法调用
   * @param call - 方法调用对象
   * @param result - 方法调用结果回调
   */
  private handleAwaitSpeakCompletion(call: MethodCall, result: MethodResult): void {
    const awaitCompletion: Object = call.args;
    if (typeof awaitCompletion !== 'boolean') {
      result.error('INVALID_ARGUMENT', 'awaitSpeakCompletion expects a boolean argument', '');
      return;
    }
    this.awaitSpeakCompletion = awaitCompletion as boolean;
    result.success(1);
  }

  /**
   * 处理 awaitSynthCompletion 方法调用
   * @param call - 方法调用对象
   * @param result - 方法调用结果回调
   */
  private handleAwaitSynthCompletion(call: MethodCall, result: MethodResult): void {
    const awaitSynth: boolean = call.args as boolean;
    if (typeof awaitSynth !== 'boolean') {
      result.error('INVALID_ARGUMENT', 'awaitSynthCompletion expects a boolean argument', '');
      return;
    }
    this.awaitSynthCompletion = awaitSynth;
    result.success(1);
  }

  /**
   * 处理 synthesizeToFile 方法调用
   * @param call - 方法调用对象
   * @param result - 方法调用结果回调
   */
  private handleSynthesizeToFile(call: MethodCall, result: MethodResult): void {
    const args = call.args as Map<string, Object>;
    if (!(args instanceof Map)) {
      result.error('INVALID_ARGUMENT', 'synthesizeToFile expects a Map argument', '');
      return;
    }
    const text = (args.get('text') as string) || '';
    const fileName = (args.get('fileName') as string) || '';
    const isFullPathVal = args.get('isFullPath');
    if (isFullPathVal !== undefined && typeof isFullPathVal !== 'boolean') {
      result.error('INVALID_ARGUMENT', 'isFullPath must be a boolean', '');
      return;
    }
    const isFullPath = (isFullPathVal as boolean) || false;
    this.synthesizeToFile(text, fileName, isFullPath, result);
  }

  /**
   * 处理 stop 方法调用
   * @param result - 方法调用结果回调
   */
  private handleStop(result: MethodResult): void {
    this.isPaused = false;
    this.stop();
    result.success(1);
    if (this.speakResult !== null) {
      this.speakResult.success(0);
      this.speakResult = null;
    }
    if (this.synthResult !== null) {
      this.synthResult.success(0);
      this.synthResult = null;
    }
  }

  /**
   * 处理 setSpeechRate 方法调用
   * @param call - 方法调用对象
   * @param result - 方法调用结果回调
   */
  private handleSetSpeechRate(call: MethodCall, result: MethodResult): void {
    const rate: number = call.args as number;
    if (typeof rate !== 'number') {
      result.error('INVALID_ARGUMENT', 'setSpeechRate expects a number argument', '');
      return;
    }
    // Dart端传入0.0~1.0，OHOS CoreSpeechKit支持0.5~2.0，使用线性映射: rate*1.5+0.5
    // 注意与Android差异：Android映射 rate*2.0(0~2范围)，同一Dart值在不同平台感知语速不同
    const speed = rate * 1.5 + 0.5;
    this.speed = speed < 0.5 ? 0.5 : (speed > 2 ? 2 : speed);
    result.success(1);
  }

  /**
   * 处理 setVolume 方法调用
   * @param call - 方法调用对象
   * @param result - 方法调用结果回调
   */
  private handleSetVolume(call: MethodCall, result: MethodResult): void {
    const volume: number = call.args as number;
    if (typeof volume !== 'number') {
      result.error('INVALID_ARGUMENT', 'setVolume expects a number argument', '');
      return;
    }
    // Dart端传入0.0~1.0，OHOS CoreSpeechKit支持0~2，使用线性映射: volume*2
    const vol = volume * 2;
    this.volume = vol < 0 ? 0 : (vol > 2 ? 2 : vol);
    result.success(1);
  }

  /**
   * 处理 setPitch 方法调用
   * @param call - 方法调用对象
   * @param result - 方法调用结果回调
   */
  private handleSetPitch(call: MethodCall, result: MethodResult): void {
    const pitch: number = call.args as number;
    if (typeof pitch !== 'number') {
      result.error('INVALID_ARGUMENT', 'setPitch expects a number argument', '');
      return;
    }
    this.pitch = pitch < 0.5 ? 0.5 : (pitch > 2 ? 2 : pitch);
    result.success(1);
  }

  /**
   * 处理 setLanguage 方法调用
   * @param call - 方法调用对象
   * @param result - 方法调用结果回调
   */
  private handleSetLanguage(call: MethodCall, result: MethodResult): void {
    let lang: string = call.args as string;
    const cantonese = this.isCantoneseLanguage(lang);
    // Cantonese tags stay themselves. Collapsing every zh* string to zh-CN
    // would speak Mandarin for a Hong Kong request.
    if (cantonese) {
      lang = lang.replace(/_/g, '-');
    } else if (lang === 'zh' || lang === 'zh-Hans' || lang === 'zh-Hans-CN' || lang.startsWith('zh')) {
      lang = 'zh-CN';
    } else if (lang === 'en' || lang === 'en-GB' || lang.startsWith('en')) {
      lang = 'en-US';
    }
    if (!cantonese && lang !== 'zh-CN' && lang !== 'en-US') {
      result.success(0);
      return;
    }
    this.language = lang;
    this.person = lang === 'en-US' ? 8 : 0;
    this.pendingSetEngineResult = result;
    this.setEngine().then(() => {
      if (this.pendingSetEngineResult !== null) {
        this.pendingSetEngineResult.success(1);
        this.pendingSetEngineResult = null;
      }
    }).catch((e: Error) => {
      LOGGER.error(FLUTTER_TTS_TAG, 'setLanguage setEngine failed: ' + e);
      if (this.pendingSetEngineResult !== null) {
        if (cantonese) {
          this.language = 'zh-CN';
          this.person = 0;
          this.pendingSetEngineResult.success(0);
        } else {
          this.pendingSetEngineResult.error('ENGINE_ERROR', `Failed to rebuild engine: ${e}`, '');
        }
        this.pendingSetEngineResult = null;
      }
    });
  }

  /**
   * 处理 getSpeechRateValidRange 方法调用
   * @param result - 方法调用结果回调
   */
  private handleGetSpeechRateValidRange(result: MethodResult): void {
    const data: Record<string, string> = {
      "min": "0.0",
      "normal": "0.5",
      "high": "0.7",
      "max": "1.0",
      "platform": "ohos"
    };
    result.success(data);
  }

  /**
   * 处理 setVoice 方法调用
   * @param call - 方法调用对象
   * @param result - 方法调用结果回调
   */
  private handleSetVoiceCommand(call: MethodCall, result: MethodResult): void {
    const voice: Map<string, string> = call.args as Map<string, string>;
    if (!voice.has('person')) {
      result.error('INVALID_VOICE', 'Voice map must contain "person" key', '');
      return;
    }
    this.setVoice(result, voice);
  }

  /**
   * 处理 setSilence 方法调用
   * @param call - 方法调用对象
   * @param result - 方法调用结果回调
   */
  private handleSetSilence(call: MethodCall, result: MethodResult): void {
    const timems: number = call.args as number;
    if (typeof timems !== 'number') {
      result.error('INVALID_ARGUMENT', 'setSilence expects a number argument', '');
      return;
    }
    this.silence = timems;
    result.success(1);
  }

  /**
   * 处理 setQueueMode 方法调用
   * @param call - 方法调用对象
   * @param result - 方法调用结果回调
   */
  private handleSetQueueMode(call: MethodCall, result: MethodResult): void {
    const queueMode: number = call.args as number;
    if (typeof queueMode !== 'number') {
      result.error('INVALID_ARGUMENT', 'setQueueMode expects a number argument', '');
      return;
    }
    // Dart 端 0=QUEUE_FLUSH, 1=QUEUE_ADD；OHOS 端 0=排队, 1=抢占，语义反转
    this.queueMode = queueMode === 0 ? 1 : 0;
    result.success(1);
  }

  /**
   * 处理 getMaxSpeechInputLength 方法调用
   * @param result - 方法调用结果回调
   */
  private handleGetMaxSpeechInputLength(result: MethodResult): void {
    // OHOS CoreSpeechKit 不提供查询最大输入长度的API，固定返回10000字符
    result.success(10000);
  }

  /**
   * 处理 setEngine 方法调用
   * @param result - 方法调用结果回调
   */
  private handleSetEngine(result: MethodResult): void {
    result.error("NOT_SUPPORTED", "OHOS platform does not support engine switching", "");
    LOGGER.error(FLUTTER_TTS_TAG, 'setEngine ohos not support.');
  }

  /**
   * 处理 getLanguages 方法调用
   * @param result - 方法调用结果回调
   */
  private async handleGetLanguages(result: MethodResult): Promise<void> {
    const found: string[] = [];
    const candidates = ['zh-HK', 'yue-HK', 'zh-Hant-HK', 'zh-CN', 'en-US'];
    try {
      if (!this.ttsEngine) {
        await this.createEngine();
      }
      for (const lang of candidates) {
        if (await this.languageHasVoices(lang)) {
          found.push(lang);
        }
      }
    } catch (e) {
      LOGGER.warn(FLUTTER_TTS_TAG, 'getLanguages probe failed: ' + e);
    }
    if (!found.includes('zh-CN')) {
      found.push('zh-CN');
    }
    if (!found.includes('en-US')) {
      found.push('en-US');
    }
    result.success(found);
  }

  private isCantoneseLanguage(lang: string): boolean {
    const value = lang.replace(/_/g, '-').toLowerCase();
    return value === 'zh-hk' ||
      value === 'yue-hk' ||
      value === 'yue' ||
      value === 'zh-hant-hk' ||
      value === 'zh-yue' ||
      value === 'zh-yue-hk' ||
      value.includes('yue') ||
      value.endsWith('-hk');
  }

  private async languageHasVoices(lang: string): Promise<boolean> {
    if (!this.ttsEngine) {
      return false;
    }
    const voiceQuery: textToSpeech.VoiceQuery = {
      requestId: `id_${Date.now()}_${lang}`,
      online: 1,
      extraParams: { "language": lang }
    };
    try {
      const voices = await this.ttsEngine.listVoices(voiceQuery);
      if (!voices || voices.length === 0) {
        return false;
      }
      const wanted = lang.replace(/_/g, '-').toLowerCase();
      for (const voice of voices) {
        const reported = `${voice.language ?? ''}`.replace(/_/g, '-').toLowerCase();
        if (reported === wanted || reported.startsWith(`${wanted}-`)) {
          return true;
        }
      }
      return false;
    } catch (e) {
      LOGGER.warn(FLUTTER_TTS_TAG, `listVoices(${lang}) failed: ` + e);
      return false;
    }
  }

  /**
   * 处理 getEngines 方法调用
   * @param result - 方法调用结果回调
   */
  private handleGetEngines(result: MethodResult): void {
    LOGGER.error(FLUTTER_TTS_TAG, 'getEngines ohos not support.');
    result.success([]);
  }

  /**
   * 处理 getDefaultEngine 方法调用
   * @param result - 方法调用结果回调
   */
  private handleGetDefaultEngine(result: MethodResult): void {
    LOGGER.error(FLUTTER_TTS_TAG, 'getDefaultEngine ohos not support.');
    result.success("");
  }

  /**
   * 处理 setSharedInstance 方法调用
   * @param result - 方法调用结果回调
   */
  private handleSetSharedInstance(result: MethodResult): void {
    // iOS专属功能，Android和OHOS均为no-op
    result.success(1);
  }

  /**
   * 处理 isLanguageAvailable 方法调用
   * @param call - 方法调用对象
   * @param result - 方法调用结果回调
   */
  private handleIsLanguageAvailable(call: MethodCall, result: MethodResult): void {
    const lang = call.args as string;
    if (typeof lang !== 'string') {
      result.error('INVALID_ARGUMENT', 'isLanguageAvailable expects a string argument', '');
      return;
    }
    if (lang === 'zh-CN' || lang === 'en-US' || this.isCantoneseLanguage(lang)) {
      this.languageHasVoices(lang).then((available: boolean) => {
        result.success(available || lang === 'zh-CN' || lang === 'en-US');
      }).catch(() => {
        result.success(lang === 'zh-CN' || lang === 'en-US');
      });
      return;
    }
    result.success(false);
  }

  /**
   * 处理 setAudioAttributesForNavigation 方法调用
   * @param result - 方法调用结果回调
   */
  private handleSetAudioAttributesForNavigation(result: MethodResult): void {
    this.soundChannel = 13;
    result.success(1);
  }

  /**
   * 处理 autoStopSharedSession 方法调用
   * @param result - 方法调用结果回调
   */
  private handleAutoStopSharedSession(result: MethodResult): void {
    // iOS专属功能，OHOS无音频会话概念，此处为no-op
    result.success(1);
    LOGGER.info(FLUTTER_TTS_TAG, 'autoStopSharedSession: iOS-only feature, no-op on OHOS.');
  }

  /**
   * 创建引擎
   */
  private async createEngine(): Promise<void> {
    return this.engineLock.lockAsync<void>(async () => {
      if (this.ttsEngine) {
        return;
      }
      // 防止 detach 后异步创建无法释放的引擎
      if (this.detached) {
        LOGGER.warn(FLUTTER_TTS_TAG, 'createEngine skipped: plugin already detached');
        return;
      }
      const extraParam: Record<string, Object> = {
        "locate": 'CN',
        "name": `EngineName_${Date.now()}`,
        "isBackStage": true
      };
      const initParamsInfo: textToSpeech.CreateEngineParams = {
        language: this.language,
        person: this.person,
        online: 1,
        extraParams: extraParam
      };
      try {
        this.ttsEngine = await textToSpeech.createEngine(initParamsInfo);
      } catch (e) {
        LOGGER.error(FLUTTER_TTS_TAG, 'textToSpeech.createEngine failed: ' + e);
        throw new Error('Failed to create TTS engine: ' + e);
      }

      // await 后重新检查，防止 detach 在异步期间销毁了上下文
      if (this.detached) {
        LOGGER.warn(FLUTTER_TTS_TAG, 'createEngine: plugin detached during async creation, shutting down');
        try { this.ttsEngine?.shutdown(); } catch (_) {}
        this.ttsEngine = null;
        return;
      }

      this.speakListener = this.createSpeakListener();

      try {
        this.ttsEngine?.setListener(this.speakListener);
      } catch (e) {
        LOGGER.error(FLUTTER_TTS_TAG, 'ttsEngine.setListener failed: ' + e);
      }
    });
  }

  /**
   * 创建 SpeakListener 回调对象
   * @returns SpeakListener 包含引擎状态变化的回调处理
   */
  private createSpeakListener(): textToSpeech.SpeakListener {
    return {
      onStart: (requestId: string, response: textToSpeech.StartResponse): void => {
        this.handleSpeakStart(requestId);
      },
      onComplete: (requestId: string, response: textToSpeech.CompleteResponse): void => {
        this.handleSpeakComplete(requestId, response);
      },
      onStop: (requestId: string, response: textToSpeech.StopResponse): void => {
        this.handleSpeakStop(requestId);
      },
      onData: (requestId: string, audio: ArrayBuffer, response: textToSpeech.SynthesisResponse): void => {
        this.handleSpeakData(requestId, audio);
      },
      onError: (requestId: string, errorCode: number, errorMessage: string): void => {
        this.handleSpeakError(requestId, errorCode, errorMessage);
      }
    };
  }

  /**
   * 处理 TTS 引擎 onStart 回调
   * @param requestId - 播报请求ID
   */
  private handleSpeakStart(requestId: string): void {
    try {
      LOGGER.info(FLUTTER_TTS_TAG, `onStart, requestId: ${requestId}`);
      // 区分合成和播报事件，与 Android/iOS 行为一致
      if (this.synthMode) {
        this.invokeMethodCall("synth.onStart", true);
      } else if (this.isPaused) {
        this.isPaused = false;
        this.invokeMethodCall("speak.onContinue", true);
      } else {
        this.invokeMethodCall("speak.onStart", true);
      }
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, `onStart callback error: ${e}`);
    }
  }

  /**
   * 处理 TTS 引擎 onComplete 回调
   * @param requestId - 播报请求ID
   * @param response - 完成响应
   */
  private handleSpeakComplete(requestId: string, response: textToSpeech.CompleteResponse): void {
    try {
      LOGGER.info(FLUTTER_TTS_TAG, `onComplete, requestId: ${requestId} type: ${response.type}`);
      if (this.synthMode) {
        this.synthMode = false;
        this.onSynthComplete();
      } else {
        if (this.awaitSpeakCompletion && this.speakResult !== null) {
          this.speakResult.success(1);
          this.speakResult = null;
        }
        this.invokeMethodCall("speak.onComplete", true);
      }
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, `onComplete callback error: ${e}`);
    }
  }

  /**
   * 处理 TTS 引擎 onStop 回调
   * @param requestId - 播报请求ID
   */
  private handleSpeakStop(requestId: string): void {
    try {
      LOGGER.info(FLUTTER_TTS_TAG, `onStop, requestId: ${requestId}`);
      if (this.synthMode) {
        this.synthMode = false;
        // 加锁保护 synthAudioBuffers 清理，与 onData 回调中的 push 互斥
        this.engineLock.lockAsync<void>(() => {
          this.synthAudioBuffers = [];
          this.synthFilePath = '';
        }).catch((e: Error) => {
          LOGGER.error(FLUTTER_TTS_TAG, `handleSpeakStop lock error: ${e}`);
        });
        if (this.awaitSynthCompletion && this.synthResult !== null) {
          this.synthResult.success(0);
          this.synthResult = null;
        }
        return;
      }
      if (this.isPaused) {
        this.invokeMethodCall("speak.onPause", true);
      } else {
        if (this.awaitSpeakCompletion && this.speakResult !== null) {
          this.speakResult.success(0);
          this.speakResult = null;
        }
        this.invokeMethodCall("speak.onCancel", true);
      }
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, `onStop callback error: ${e}`);
    }
  }

  /**
   * 处理 TTS 引擎 onData 回调
   * @param requestId - 播报请求ID
   * @param audio - PCM音频数据
   */
  private handleSpeakData(requestId: string, audio: ArrayBuffer): void {
    try {
      LOGGER.info(FLUTTER_TTS_TAG, `onData, requestId: ${requestId} size: ${audio.byteLength}`);
      if (this.synthMode) {
        this.engineLock.lockAsync<void>(() => {
          this.synthAudioBuffers.push(audio);
        }).catch((e: Error) => {
          LOGGER.error(FLUTTER_TTS_TAG, `onData lock error: ${e}`);
          this.invokeMethodCall("synth.onError", `Audio data lost: ${e}`);
        });
      }
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, `onData callback error: ${e}`);
    }
  }

  /**
   * 处理 TTS 引擎 onError 回调
   * @param requestId - 播报请求ID
   * @param errorCode - 错误码
   * @param errorMessage - 错误消息
   */
  private handleSpeakError(requestId: string, errorCode: number, errorMessage: string): void {
    try {
      LOGGER.error(FLUTTER_TTS_TAG, `onError, requestId: ${requestId} code: ${errorCode} msg: ${errorMessage}`);
      if (this.synthMode) {
        this.synthMode = false;
        this.synthAudioBuffers = [];
        this.synthFilePath = '';
        if (this.awaitSynthCompletion && this.synthResult !== null) {
          this.synthResult.success(0);
          this.synthResult = null;
        }
        this.invokeMethodCall("synth.onError", `synth error: ${errorCode} ${errorMessage}`);
      } else {
        if (this.awaitSpeakCompletion && this.speakResult !== null) {
          this.speakResult.success(0);
          this.speakResult = null;
        }
        this.invokeMethodCall("speak.onError", `speak error: ${errorCode} ${errorMessage}`);
      }
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, `onError callback error: ${e}`);
    }
  }

  /**
   * 向Flutter Dart端发送方法调用
   * @param method - 方法名
   * @param args - 方法参数，可为null
   */
  private invokeMethodCall(method: string, args: Object | null): void {
    try {
      this.channel?.invokeMethod(method, args);
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, `invokeMethod ${method} failed: ` + e);
    }
  }

  // ===================== 核心功能方法 =====================

  /**
   * 播放语音
   * @param text 文本
   */
  private async speak(text: string, queueModeOverride?: number): Promise<void> {
    try {
      // 确保引擎已初始化
      await this.createEngine();
      if (!this.ttsEngine) {
        LOGGER.error(FLUTTER_TTS_TAG, 'speak failed: ttsEngine is not initialized');
        if (this.speakResult !== null) {
          this.speakResult.error('ENGINE_NOT_READY', 'TTS engine not initialized', '');
          this.speakResult = null;
        }
        return;
      }
      const effectiveQueue = queueModeOverride !== undefined ? queueModeOverride : this.queueMode;
      const requestId: string = `id_${Date.now()}`;
      const extraParam: Record<string, Object> = {
        "queueMode": effectiveQueue,
        "speed": this.speed,
        "volume": this.volume,
        "pitch": this.pitch,
        "languageContext": this.language,
        "audioType": "pcm",
        "soundChannel": this.soundChannel,
        "playType": this.synthMode ? 0 : 1
      };
      const speakParams: textToSpeech.SpeakParams = {
        requestId: requestId,
        extraParams: extraParam
      };

      if (this.silence > 0) {
        if (this.queueMode === 1) {
          this.stop();
        }
        const timeoutId = setTimeout(() => {
          this.doSpeak(text, speakParams);
          const index = this.timeoutIds.indexOf(timeoutId);
          if (index > -1) {
            this.timeoutIds.splice(index, 1);
          }
        }, this.silence);
        this.timeoutIds.push(timeoutId);
      } else {
        this.doSpeak(text, speakParams);
      }
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, 'speak failed: ' + e);
      // 释放 speakResult 避免 Dart Future 挂起
      if (this.speakResult !== null) {
        this.speakResult.error('SPEAK_ERROR', `speak failed: ${e}`, '');
        this.speakResult = null;
      }
    }
  }

  /**
   * 执行语音播报，统一处理错误和 pending result 释放
   * @param text 文本内容
   * @param speakParams 播报参数
   */
  private doSpeak(text: string, speakParams: textToSpeech.SpeakParams): void {
    try {
      this.ttsEngine?.speak(text, speakParams);
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, 'doSpeak failed: ' + e);
      if (this.speakResult !== null) {
        this.speakResult.error('SPEAK_ERROR', `speak failed: ${e}`, '');
        this.speakResult = null;
      }
      this.invokeMethodCall("speak.onError", `speak error: ${e}`);
    }
  }

  /**
   * 暂停语音播放
   * 标记 isPaused=true 后停掉引擎，onStop 回调会发 speak.onPause 到 Flutter 端
   * @param result - 方法调用结果回调
   */
  private pause(result: MethodResult): void {
    try {
      this.isPaused = true;
      this.stop();  // 停掉当前播放 → onStop 检测 isPaused → 发 speak.onPause
      // 处理 pending result，避免 Future 泄漏
      if (this.speakResult !== null) {
        this.speakResult.success(0);
        this.speakResult = null;
      }
      if (this.synthResult !== null) {
        this.synthResult.success(0);
        this.synthResult = null;
      }
      result.success(1);
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, 'pause failed: ' + e);
      result.error('PAUSE_ERROR', `Pause failed: ${e}`, '');
    }
  }

  /**
   * 合成语音到文件
   * @param text 文本
   * @param fileName 文件名
   * @param isFullPath 是否为完整路径
   * @param result 回调
   */
  private async synthesizeToFile(text: string, fileName: string, isFullPath: boolean,
    result: MethodResult): Promise<void> {
    if (!text || !fileName) {
      result.success(0);
      return;
    }
    try {
      let filePath = fileName;
      if (!isFullPath) {
        const filesDir = this.context?.filesDir;
        if (!filesDir) {
          LOGGER.error(FLUTTER_TTS_TAG, 'synthesizeToFile: context.filesDir is null');
          result.error('INVALID_ARGUMENT', 'context.filesDir is null', '');
          return;
        }
        filePath = `${filesDir}/${fileName}`;
      }
      await this.createEngine();
      if (!this.ttsEngine) {
        LOGGER.error(FLUTTER_TTS_TAG, 'synthesizeToFile: ttsEngine is not initialized');
        result.error('ENGINE_NOT_READY', 'TTS engine not initialized', '');
        return;
      }
      this.synthMode = true;
      this.synthFilePath = filePath;
      this.synthAudioBuffers = [];

      await this.speak(text);

      if (this.awaitSynthCompletion) {
        this.synthResult = result;
      } else {
        result.success(1);
      }
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, 'synthesizeToFile failed: ' + e);
      this.synthMode = false;
      result.error('SYNTH_ERROR', `Synthesize to file failed: ${e}`, '');
    }
  }

  /**
   * 将收集的音频数据写入文件（异步，不阻塞 TTS 回调线程）
   */
  private async writeSynthAudioToFileAsync(): Promise<void> {
    // 加锁保护：提取并清空 buffers，与 onData 回调中的 push 互斥
    let buffers: ArrayBuffer[] = [];
    let filePath: string = '';
    await this.engineLock.lockAsync<void>(() => {
      buffers = this.synthAudioBuffers;
      filePath = this.synthFilePath;
      this.synthAudioBuffers = [];
      this.synthFilePath = '';
    });
    if (buffers.length === 0) {
      LOGGER.error(FLUTTER_TTS_TAG, 'writeSynthAudioToFileAsync: no audio data');
      throw new Error('writeSynthAudioToFileAsync: no audio data');
    }
    try {
      let totalLen = 0;
      for (const buf of buffers) {
        totalLen += buf.byteLength;
      }
      const merged = new ArrayBuffer(totalLen);
      const mergedView = new Uint8Array(merged);
      let offset = 0;
      for (const buf of buffers) {
        const src = new Uint8Array(buf);
        mergedView.set(src, offset);
        offset += src.length;
      }
      // 先删除旧文件避免残留
      try {
        fileIo.unlink(filePath);
      } catch (e) {
        // 文件不存在忽略
      }
      const file = await fileIo.open(filePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      try {
        await fileIo.write(file.fd, merged);
      } catch (writeErr) {
        LOGGER.error(FLUTTER_TTS_TAG, 'fileIo.write failed: ' + writeErr);
        await fileIo.close(file);
        // 写入失败时清理已创建的空文件
        try {
          fileIo.unlink(filePath);
        } catch (_) {
          // 忽略删除失败
        }
        throw new Error('fileIo.write failed');
      }
      await fileIo.close(file);
      LOGGER.info(FLUTTER_TTS_TAG, `writeSynthAudioToFileAsync success: ${filePath} (${totalLen} bytes)`);
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, 'writeSynthAudioToFileAsync failed: ' + e);
      throw new Error('writeSynthAudioToFileAsync failed');
    }
  }

  /**
   * 合成完成回调：异步写入文件，完成后通知 Dart 端
   */
  private async onSynthComplete(): Promise<void> {
    try {
      await this.writeSynthAudioToFileAsync();
      if (this.awaitSynthCompletion && this.synthResult !== null) {
        this.synthResult.success(1);
        this.synthResult = null;
      }
      this.invokeMethodCall("synth.onComplete", true);
    } catch (e) {
      const errorMsg = e instanceof Error ? e.message : String(e);
      LOGGER.error(FLUTTER_TTS_TAG, 'onSynthComplete failed: ' + errorMsg);
      if (this.awaitSynthCompletion && this.synthResult !== null) {
        this.synthResult.error('SYNTH_COMPLETE_ERROR', `Synth complete failed: ${errorMsg}`, '');
        this.synthResult = null;
      }
      this.invokeMethodCall('synth.onError', `synth file write failed: ${errorMsg}`);
    }
  }

  /**
   * 重置语音为默认
   * @param result - 方法调用结果回调
   */
  private async clearVoice(result: MethodResult): Promise<void> {
    try {
      if (this.person !== 0) {
        this.person = 0;
        this.pendingSetEngineResult = result;
        await this.setEngine();
        if (this.pendingSetEngineResult !== null) {
          this.pendingSetEngineResult.success(1);
          this.pendingSetEngineResult = null;
        }
      } else {
        result.success(1);
      }
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, 'clearVoice failed: ' + e);
      if (this.pendingSetEngineResult !== null) {
        this.pendingSetEngineResult.error('CLEAR_VOICE_ERROR', `Clear voice failed: ${e}`, '');
        this.pendingSetEngineResult = null;
      } else {
        result.error('CLEAR_VOICE_ERROR', `Clear voice failed: ${e}`, '');
      }
    }
  }

  /**
   * 清空所有延时任务
   */
  private clearAllPendingTimeouts(): void {
    const hadTimeouts = this.timeoutIds.length > 0;
    for (const id of this.timeoutIds) {
      clearTimeout(id);
    }
    this.timeoutIds = [];
    // 仅在有实际 timeout 被清除时才解析 pending result，避免提前释放
    if (hadTimeouts && this.pendingSetEngineResult !== null) {
      this.pendingSetEngineResult.success(0);
      this.pendingSetEngineResult = null;
    }
  }

  /**
   * 停止播放
   * 注意：不修改 isPaused 状态，由外部调用者（pause/stop 命令）管理
   */
  private stop(): void {
    this.clearAllPendingTimeouts();
    try {
      this.ttsEngine?.stop();
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, 'stop failed: ' + e);
    }
  }

  /**
   * 关闭引擎，释放引擎资源。
   */
  private shutdown(): void {
    try {
      this.ttsEngine?.shutdown();
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, 'shutdown failed: ' + e);
    } finally {
      this.ttsEngine = null;
    }
  }

  /**
   * 重启引擎（重置 person 后调用）
   */
  private async setEngine(): Promise<void> {
    this.stop();
    // 清理 pending result，避免 shutdown 后 onStop 不再触发导致 Future 挂起
    if (this.speakResult !== null) {
      this.speakResult.success(0);
      this.speakResult = null;
    }
    if (this.synthResult !== null) {
      this.synthResult.success(0);
      this.synthResult = null;
    }
    // 先断开 listener 再 shutdown，避免引擎回调访问已销毁实例
    try {
      this.ttsEngine?.setListener(null);
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, 'setListener(null) in setEngine failed: ' + e);
    }
    this.speakListener = null;
    this.shutdown();
    return new Promise<void>((resolve: () => void, reject: (e: Error) => void) => {
      const timeoutId = setTimeout(() => {
        const index = this.timeoutIds.indexOf(timeoutId);
        if (index > -1) {
          this.timeoutIds.splice(index, 1);
        }
        this.createEngine().then(() => resolve()).catch((e: Error) => {
          LOGGER.error(FLUTTER_TTS_TAG, 'setEngine createEngine failed: ' + e);
          reject(e);
        });
      }, 600);
      this.timeoutIds.push(timeoutId);
    });
  }

  /**
   * 设置音色
   * @param result 回调
   * @param voice 音色参数
   */
  private async setVoice(result: MethodResult, voice: Map<string, string> | undefined): Promise<void> {
    if (this.ttsEngine?.isBusy()) {
      this.stop();
    }
    try {
      const personNew = Number.parseInt(voice?.get("person") ?? '0');
      if (this.person !== personNew) {
        this.person = personNew;
        this.pendingSetEngineResult = result;
        await this.setEngine();
        if (this.pendingSetEngineResult !== null) {
          this.pendingSetEngineResult.success(1);
          this.pendingSetEngineResult = null;
        }
      } else {
        result.success(1);
      }
    } catch (e) {
      const err = e as BusinessError;
      LOGGER.error(FLUTTER_TTS_TAG, 'setVoice failed: ' + e);
      if (this.pendingSetEngineResult !== null) {
        this.pendingSetEngineResult.error(`${err.code}`, `${err.message}`, "");
        this.pendingSetEngineResult = null;
      } else {
        result.error(`${err.code}`, `${err.message}`, "");
      }
    }
  }

  /**
   * 下载音色
   * @param result - 方法调用结果回调
   * @param voice - 音色参数（language, person, style）
   */
  private async downloadVoice(result: MethodResult, voice: Map<string, string> | undefined): Promise<void> {
    try {
      const language: string = voice?.get("language") ?? "";
      const personStr: string = voice?.get("person") ?? "0";
      const style: string = voice?.get("style") ?? "";

      if (!language) {
        result.error('INVALID_ARGUMENT', 'language is required', '');
        return;
      }
      const person: number = Number.parseInt(personStr);
      if (isNaN(person)) {
        result.error('INVALID_ARGUMENT', 'person must be a valid number', '');
        return;
      }

      const downloadId: string = `download_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
      const voicesDownload: textToSpeech.VoiceDownload = {
        requestId: downloadId,
        language: language,
        person: person,
        style: style
      };

      this.setupDownloadCallbacks(voicesDownload, downloadId);

      result.success({ "downloadId": downloadId });
    } catch (e) {
      const err = e as BusinessError;
      LOGGER.error(FLUTTER_TTS_TAG, 'downloadVoice failed: ' + e);
      result.error(`${err.code}`, `${err.message}`, "");
    }
  }

  /**
   * 设置下载回调并注册到下载响应
   * @param voicesDownload - 下载请求参数
   * @param downloadId - 下载任务标识
   */
  private setupDownloadCallbacks(voicesDownload: textToSpeech.VoiceDownload, downloadId: string): void {
    textToSpeech.downloadVoice(voicesDownload,
      (error: BusinessError, downloadResponse: textToSpeech.DownloadResponse) => {
        if (error) {
          LOGGER.error(FLUTTER_TTS_TAG, `Failed to download voice. code: ${error.code}, message: ${error.message}`);
          const errorMap1: Record<string, Object> = {
            "downloadId": downloadId,
            "errorCode": error.code,
            "errorMessage": error.message
          };
          this.invokeMethodCall("downloadVoice.onError", errorMap1);
          return;
        }
        if (!downloadResponse) {
          LOGGER.error(FLUTTER_TTS_TAG, `Failed to download voice. downloadResponse is null`);
          const errorMap2: Record<string, Object> = {
            "downloadId": downloadId,
            "errorCode": -1,
            "errorMessage": "Download response is null"
          };
          this.invokeMethodCall("downloadVoice.onError", errorMap2);
          return;
        }
        let requestId: string = downloadResponse.requestId;

        let startCallback: Callback<string> = (info: string) => {
          LOGGER.info(FLUTTER_TTS_TAG, `download voice start, requestId: ${requestId}, info:${info}`);
          const startMap: Record<string, Object> = {
            "downloadId": downloadId,
            "info": info
          };
          this.invokeMethodCall("downloadVoice.onStart", startMap);
        };

        let progressCallback: Callback<string> = (schedule: string) => {
          LOGGER.info(FLUTTER_TTS_TAG, `download voice schedule, requestId: ${requestId} scheduleInfo: ${schedule}`);
          const progressMap: Record<string, Object> = {
            "downloadId": downloadId,
            "schedule": schedule
          };
          this.invokeMethodCall("downloadVoice.onProgress", progressMap);
        };

        let completeCallback: Callback<textToSpeech.VoiceInfo> = (voiceInfo: textToSpeech.VoiceInfo) => {
          try {
            const voiceInfoStr = JSON.stringify(voiceInfo);
            LOGGER.info(FLUTTER_TTS_TAG, `download voice complete, requestId: ${requestId} voiceInfo: ${voiceInfoStr}`);
            this.unregisterDownloadCallbacks(
              downloadResponse, startCallback, progressCallback,
              completeCallback, cancelCallback, errorCallback);
            this.removeActiveDownloadResponse(downloadResponse);

            const completeMap: Record<string, Object> = {
              "downloadId": downloadId,
              "voiceInfo": voiceInfo
            };
            this.invokeMethodCall("downloadVoice.onComplete", completeMap);
          } catch (e) {
            LOGGER.error(FLUTTER_TTS_TAG, `completeCallback error: ${e}`);
          }
        };

        let cancelCallback: Callback<string> = (cancelInfo: string) => {
          try {
            LOGGER.info(FLUTTER_TTS_TAG, `download voice cancel, requestId: ${requestId} cancelInfo: ${cancelInfo}`);
            this.unregisterDownloadCallbacks(
              downloadResponse, startCallback, progressCallback,
              completeCallback, cancelCallback, errorCallback);
            this.removeActiveDownloadResponse(downloadResponse);
            const cancelMap: Record<string, Object> = {
              "downloadId": downloadId,
              "cancelInfo": cancelInfo
            };
            this.invokeMethodCall("downloadVoice.onCancel", cancelMap);
          } catch (e) {
            LOGGER.error(FLUTTER_TTS_TAG, `cancelCallback error: ${e}`);
          }
        };

        let errorCallback: ErrorCallback<BusinessError> = (err: BusinessError) => {
          try {
            const errMsg = `errorCode: ${err.code} errorMessage: ${err.message}`;
            LOGGER.error(FLUTTER_TTS_TAG, `download voice error, requestId: ${requestId} ${errMsg}`);
            this.unregisterDownloadCallbacks(
              downloadResponse, startCallback, progressCallback,
              completeCallback, cancelCallback, errorCallback);
            this.removeActiveDownloadResponse(downloadResponse);
            const errorMap3: Record<string, Object> = {
              "downloadId": downloadId,
              "errorCode": err.code,
              "errorMessage": err.message
            };
            this.invokeMethodCall("downloadVoice.onError", errorMap3);
          } catch (e) {
            LOGGER.error(FLUTTER_TTS_TAG, `errorCallback error: ${e}`);
          }
        };

        downloadResponse.on('start', startCallback);
        downloadResponse.on('progress', progressCallback);
        downloadResponse.on('complete', completeCallback);
        downloadResponse.on('cancel', cancelCallback);
        downloadResponse.on('error', errorCallback);
        // 追踪活跃的下载任务，防止累积过多（上限100）
        if (this.activeDownloadResponses.length < 100) {
          this.activeDownloadResponses.push(downloadResponse);
        } else {
          LOGGER.warn(FLUTTER_TTS_TAG, 'activeDownloadResponses limit reached, discarding oldest');
          const oldest = this.activeDownloadResponses.shift();
          if (oldest) {
            try { oldest.off('start'); oldest.off('progress'); oldest.off('complete'); oldest.off('cancel'); oldest.off('error'); } catch (_) {}
          }
          this.activeDownloadResponses.push(downloadResponse);
        }
      });
  }

  /**
   * 获取所有语音
   * @param result - 方法调用结果回调，返回voices数组
   */
  private async getVoices(result: MethodResult): Promise<void> {
    if (deviceInfo.sdkApiVersion < 19) {
      LOGGER.error(FLUTTER_TTS_TAG, 'Only supports OHOS API 19+ ');
      result.error(`0`, "Only supports OHOS API 19+", "");
      return;
    }
    // 等待引擎重建完成（如果正在重建中）
    await this.engineLock.lockAsync<void>(async () => {
      // 锁内检查引擎状态
    }).catch((e: Error) => {
      LOGGER.error(FLUTTER_TTS_TAG, 'getVoices lock wait failed: ' + e);
    });
    // 确保引擎可用：如果当前 language+person 组合无法创建引擎（如英文音色未下载），
    // 回退用 zh-CN+person=0 创建，保证 listVoices 能正常执行
    if (!this.ttsEngine) {
      try {
        await this.createEngine();
      } catch (e) {
        LOGGER.warn(FLUTTER_TTS_TAG, 'getVoices: createEngine with current language failed, fallback to zh-CN');
        const savedLanguage = this.language;
        const savedPerson = this.person;
        this.language = 'zh-CN';
        this.person = 0;
        try {
          await this.createEngine();
        } catch (fallbackErr) {
          LOGGER.error(FLUTTER_TTS_TAG, 'getVoices: fallback createEngine also failed: ' + fallbackErr);
          result.error('ENGINE_ERROR', 'Failed to create TTS engine', '');
          this.language = savedLanguage;
          this.person = savedPerson;
          return;
        }
        this.language = savedLanguage;
        this.person = savedPerson;
      }
    }
    if (!this.ttsEngine) {
      LOGGER.error(FLUTTER_TTS_TAG, 'getVoices: ttsEngine is not initialized');
      result.error('ENGINE_NOT_READY', 'TTS engine not initialized', '');
      return;
    }

    // 用当前 language 过滤，返回对应语言的音色
    const voiceQuery: textToSpeech.VoiceQuery = {
      requestId: `id_${Date.now()}`,
      online: 1,
      extraParams: { "language": this.language }
    };

    try {
      const voices = await this.ttsEngine.listVoices(voiceQuery);
      // 确保 person 字段为整数，避免 Dart 端解析为 double
      if (voices) {
        for (const voice of voices) {
          if (voice.person !== undefined && voice.person !== null) {
            voice.person = Math.floor(Number(voice.person));
          }
        }
      }
      result.success(voices ?? []);
    } catch (e) {
      const err = e as BusinessError;
      LOGGER.error(FLUTTER_TTS_TAG, 'getVoices failed: ' + e);
      result.error(`${err.code}`, err.message, "");
    }
  }

  /**
   * 获取默认语音
   * @param result - 方法调用结果回调，返回第一个可用的voice对象
   */
  private async getDefaultVoice(result: MethodResult): Promise<void> {
    if (deviceInfo.sdkApiVersion < 19) {
      LOGGER.error(FLUTTER_TTS_TAG, 'Only supports OHOS API 19+ ');
      result.error(`0`, "Only supports OHOS API 19+", "");
      return;
    }
    try {
      await this.createEngine();
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, 'getDefaultVoice: createEngine failed: ' + e);
      result.error('ENGINE_ERROR', 'Failed to create TTS engine', '');
      return;
    }
    if (!this.ttsEngine) {
      LOGGER.error(FLUTTER_TTS_TAG, 'getDefaultVoice: ttsEngine is not initialized');
      result.error('ENGINE_NOT_READY', 'TTS engine not initialized', '');
      return;
    }
    const extraParam: Record<string, Object> = { "language": this.language };
    const voiceQuery: textToSpeech.VoiceQuery = {
      requestId: `id_${Date.now()}`,
      online: 1,
      extraParams: extraParam
    };

    try {
      const voices = await this.ttsEngine.listVoices(voiceQuery);
      if (voices && voices.length > 0) {
        const voice = voices[0];
        // 确保 person 字段为整数，避免 Dart 端解析为 double
        if (voice.person !== undefined && voice.person !== null) {
          voice.person = Math.floor(Number(voice.person));
        }
        result.success(voice);
      } else {
        result.error(`voiceError`, "no default voice.", "");
      }
    } catch (e) {
      const err = e as BusinessError;
      LOGGER.error(FLUTTER_TTS_TAG, 'getDefaultVoice failed: ' + e);
      result.error(`${err.code}`, err.message, "");
    }
  }

  /**
   * 检查指定语言的语音包是否已安装
   * 通过 listVoices API 查询语音状态，检查 status 字段是否为'INSTALLED'
   * 与Android实现差异：Android通过 tts.voices 检查 isNetworkConnectionRequired 和
   * KEY_FEATURE_NOT_INSTALLED，两者查询方式不同但功能等价
   * @param lang - 待检查的语言代码（如 'zh-CN', 'en-US'）
   * @param result - 方法调用结果回调
   */
  private async isLanguageInstalledInternal(lang: string, result: MethodResult): Promise<void> {
    try {
      await this.createEngine();
      if (!this.ttsEngine) {
        result.success(false);
        return;
      }
      const extraParam: Record<string, Object> = { "language": lang };
      const voiceQuery: textToSpeech.VoiceQuery = {
        requestId: `id_${Date.now()}`,
        online: 1,
        extraParams: extraParam
      };
      const voices = await this.ttsEngine?.listVoices(voiceQuery);
      if (voices && voices.length > 0) {
        // 检查是否有 INSTALLED 状态的语音
        for (const voice of voices) {
          if (voice.status === 'INSTALLED') {
            result.success(true);
            return;
          }
        }
      }
      result.success(false);
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, 'isLanguageInstalled failed: ' + e);
      result.error('QUERY_ERROR', `Language install check failed: ${e}`, '');
    }
  }

  /**
   * 批量检查多个语言包的安装状态
   * @param languages - 待检查的语言代码数组
   * @param result - 方法调用结果回调，返回 Record<string, boolean> 格式的安装状态
   */
  private async areLanguagesInstalledInternal(languages: string[], result: MethodResult): Promise<void> {
    try {
      const map: Record<string, boolean> = {};
      for (const lang of languages) {
        // 对每个语言进行安装检查，但不阻塞整体结果
        const installed = await this.isLanguageInstalledPromise(lang);
        map[lang] = installed;
      }
      result.success(map);
    } catch (e) {
      LOGGER.error(FLUTTER_TTS_TAG, 'areLanguagesInstalled failed: ' + e);
      result.error('QUERY_ERROR', `Languages install check failed: ${e}`, '');
    }
  }

  /**
   * 检查语言包安装状态（Promise 形式，供批量调用）
   * @param lang - 待检查的语言代码
   */
  private async isLanguageInstalledPromise(lang: string): Promise<boolean> {
    try {
      await this.createEngine();
      if (!this.ttsEngine) {
        return false;
      }
      const extraParam: Record<string, Object> = { "language": lang };
      const voiceQuery: textToSpeech.VoiceQuery = {
        requestId: `id_${Date.now()}`,
        online: 1,
        extraParams: extraParam
      };
      const voices = await this.ttsEngine?.listVoices(voiceQuery);
      if (voices && voices.length > 0) {
        for (const voice of voices) {
          if (voice.status === 'INSTALLED') {
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      const errorMsg = e instanceof Error ? e.message : String(e);
      LOGGER.error(FLUTTER_TTS_TAG, `isLanguageInstalledPromise failed for lang ${lang}: ${errorMsg}`);
      return false;
    }
  }
}