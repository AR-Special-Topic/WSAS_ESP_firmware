# Dependencies

## Firmware

Use ESP-IDF **v6.0.0** with the ESP32-S3 toolchain. `firmware/dependencies.lock` records the resolved component versions and hashes; direct component manifests pin their versions.

| Component | Version |
|---|---|
| esp-sr | 2.5.3 |
| esp-dl | 3.3.11 |
| human_face_detect | 0.5.0 |
| esp32-camera | 2.1.7 |
| esp-dsp | 1.8.0 |
| dl_fft | 0.8.0 |
| esp_new_jpeg | 1.0.2 |
| esp_jpeg | 1.3.1 |
| cjson | 1.7.19~2 |

The detector is ESPDet Pico 224x224; the SR partition contains VADNet1 medium. Defaults target 8 MB flash and octal 80 MHz PSRAM. BLE Event association requires ATT MTU at least 67.

## PC and iOS

Python supports 3.11 through 3.13. `pc_client/pyproject.toml` declares runtime and development dependencies; `pc_client/requirements.lock` pins the installation set. InsightFace may require a native C++ build toolchain. Its pretrained model downloads separately and has its own usage terms.

The Swift package requires Swift tools 5.9 and iOS 16 or later. Build it using Xcode on macOS with an iOS destination; it uses iOS platform APIs.
