# Wearable Social Assistive System
XIAO ESP32-S3 Sense（OV3660）的語音事件與多臉關聯專案。每段 VAD 語音建立獨立 Event ID，將 16 kHz mono PCM16 RAW 音訊與 pre-roll 寫成 SD WAV，同時於開始及每 30 秒拍攝並處理多張人臉。PC 以 BLE 接收 JPEG、執行 InsightFace 辨識並保存 SQLite 關聯；iOS 套件提供 VAD 控制、Wi-Fi SD 匯出及明確刪檔功能。

## 目錄

- `firmware/`：單一 ESP-IDF 專案，包含 `main/`、`components/`、預設設定、分割表與依賴鎖定。
- `pc_client/`：Python BLE／InsightFace CLI 與 EventStore。
- `clients/ios/`：iOS 16+ Swift 套件與整合範例。
- `protocol/`：BLE 協定與合成 SD 資料範例。
- `tools/`：SD 檢查、序列日誌解析與開發檢查工具。
- `tests/`：自動化 host 測試與必要 stub。

## 硬體

使用 8 MB flash／octal PSRAM 的 XIAO ESP32-S3 Sense 與 OV3660。PDM DATA=GPIO41、CLK=GPIO42；microSD SCLK=7、MISO=8、MOSI=9，**預設 CS=GPIO21**（`CONFIG_BOARD_SD_PROFILE_LEGACY=y`），狀態 LED 因共用 GPIO21 而停用。若實際擴充板使用不同接腳，先於 menuconfig 選擇 SD profile。可選診斷按鈕接 D1/GPIO2 與 GND；GPIO0 保留給 BOOT。

## 安裝 ESP-IDF

安裝 **ESP-IDF v6.0** 與 ESP32-S3 工具鏈，請依 [官方 Windows／Linux／macOS 安裝指引](https://docs.espressif.com/projects/esp-idf/en/v6.0/esp32s3/get-started/index.html)。不依賴特定磁碟或安裝路徑。

- Windows：開啟安裝程式提供的 ESP-IDF PowerShell／Command Prompt；或依安裝方式執行該 ESP-IDF 的環境啟用指令。
- Linux／macOS：使用 EIM 的啟用環境；若從 Git 安裝，安裝後在 ESP-IDF 目錄執行 `. ./export.sh`。
- 執行 `idf.py --version` 確認為 v6.0，再回到本專案根目錄。

## 建置與燒錄

以下命令在已啟用 ESP-IDF 的終端機執行，各平台相同：

```sh
idf.py -C firmware build
idf.py -C firmware menuconfig
idf.py -C firmware -p COM8 flash monitor
```

將 `COM8` 換成實際裝置埠；Linux 常見 `/dev/ttyACM0`，macOS 常見 `/dev/cu.usbmodem...`。`Ctrl+]` 離開 monitor。第一次建置由 component manager 取得鎖定元件；無須複製其他專案或已生成的 sdkconfig。

分割表提供 6 MiB app、位於 `0x610000` 的 1 MiB VAD 模型。使用完整 `flash` 命令，僅燒錄 app binary 會漏掉模型。一般燒錄保留 NVS 與 SD；不要為更新韌體執行整片清除。NVS 保存 Event boot counter，清除後會重設該身分歷史。

## PC client

使用 Python 3.11～3.13。以下指令不需要啟用 venv：

```sh
python -m venv pc_client/.venv
```

Windows 使用 `pc_client/.venv/Scripts/python.exe`；Linux／macOS 使用 `pc_client/.venv/bin/python`。以該執行檔執行：

```sh
python -m pip install -r pc_client/requirements.lock
python -m pip install --no-build-isolation -e pc_client
python -m pc_client scan
python -m pc_client --event-database event_store.db run --wait-only
python -m pc_client vad off
python -m pc_client vad on
```

此區命令中的 `python` 請替換成上述 venv 執行檔。`register --person-id P001 --name Alice --image alice.jpg` 建立身分；`list`、`remove --person-id P001` 管理資料庫；`recognize-file --image image.jpg` 辨識本機圖片。預設不保存收到的 JPEG 或註冊原圖。InsightFace 模型首次使用時另行下載，其模型授權見 [隱私與安全](docs/PRIVACY.md)。

關閉 VAD 會在 RAW frame 邊界結束目前 Event，SD writer 非同步收尾；PDM 繼續取樣。BLE 斷線與匯出恢復保留開關選擇，重啟回到開啟。

## iOS 與操作文件

以 local Swift Package 加入 `clients/ios`，產品為 `EventPipeSDExport`，需要 iOS 16+。套件包含 `setVAD(enabled:)`、匯出進度、斷點續傳與明確刪檔 API；掃描、配對及人臉模型由 host App 整合。

- [Event 架構與操作](docs/EVENT1.md)、[狀態圖](docs/EVENT_STATE_DIAGRAM.md)、[模組架構](ARCHITECTURE.md)
- [BLE／HTTP 契約](docs/BLE_PROTOCOL.md)、[SD 資料模型](docs/EVENT_DATA_MODEL.md)
- [iOS 整合](docs/IOS_SD_EXPORT.md)、[依賴版本](DEPENDENCIES.md)、[疑難排解](docs/TROUBLESHOOTING.md)

以 `python tools/inspect_event_sd.py <SD-copy> --output events.json` 重建 Event。實際錄音、影像與資料庫請放於本機資料目錄，勿加入版本控制。
