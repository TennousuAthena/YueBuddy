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
 
export enum ReleaseMode {
  RELEASE = 1,
  LOOP = 2,
  STOP = 3
}

export const parseReleaseMode = (mode: string) => {
  if (mode == "ReleaseMode.stop") {
    return ReleaseMode.STOP
  } else if (mode == "ReleaseMode.loop") {
    return ReleaseMode.LOOP
  }
  return ReleaseMode.RELEASE;
}