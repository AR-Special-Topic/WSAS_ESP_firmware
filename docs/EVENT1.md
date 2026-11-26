# Event 1

See [Event 1 state diagrams](EVENT_STATE_DIAGRAM.md) for the complete Event lifecycle, asynchronous audio/face completion, WAV recording, camera admission/multi-face processing, failure paths, and PC persistence.

For app-side interpretation of SD artifacts, use the [Event data model](EVENT_DATA_MODEL.md). The integrated app can now export all SD files through a [BLE-started Wi-Fi session](BLE_PROTOCOL.md); [iOS integration](IOS_SD_EXPORT.md) supplies the Swift module workflow. WAV bytes travel over HTTP in this explicit export mode. Recording and manual captures pause only after existing owners finish and the writer acknowledges its final metadata barrier.

## Ownership and lifecycle

One VAD utterance is one Event. The VAD-start callback reserves an Event ID and bounded metadata synchronously, then immediately copies the application RAW pre-roll ring into the writer queue. It only wakes the EventManager task; camera and BLE operations occur in that separate task and the existing controller. The manager can track 16 simultaneous owners without any face vectors. Exhaustion is logged as `EVENT_REJECTED`; no owner is overwritten. Its metadata signals occupy reserved slots and wake a task notification, so terminal signals cannot disappear because a lifecycle queue is full.

The upper 32 bits of the Event ID are a boot counter committed once to NVS namespace `event1`, key `boot_session`; the lower 32 bits are a sequence beginning at 1. NVS initialization, commit and counter-overflow failures stop Event startup. No NVS error handler erases the counter. PC/SD IDs are 16 uppercase hexadecimal digits. Erasing/replacing NVS intentionally starts a new identity history and is outside the preserved-NVS reboot guarantee.

EventManager submits an initial `CaptureRequest` and another at each 30-second slot from VAD start while the Event remains active. Each accepted request has a fresh ID under the same Event/WAV. Face indices restart per request. Busy/unavailable later slots are skipped without backlog; only the initial rejected batch gets a request-0 terminal. No new Event batches start after VAD_END, the five-minute cap or export gating; an admitted request can finish afterward. GPIO and BLE submissions share the original queue-of-one arbitration and generate no audio Event. If camera is busy, the new utterance still records audio and its face branch terminates `BUSY`, with request ID 0 because no request was accepted. Missing/unready BLE terminates the face branch `DISCONNECTED` locally. Camera initialization/task allocation failures leave audio Events enabled with face `FAILED`.

The controller emits `EVENT_OPEN` before any Event-owned camera work, guaranteeing request mapping before the first image. EventManager also sends an idempotent OPEN for lifecycle publication, including mappingless Events. It never changes capture/detection/recapture/rotation/sorting/crop/JPEG sequencing. Each validated result emits a bounded face association; each pipeline exit emits a final batch result. Previously returned results survive PARTIAL, timeout and disconnect.

Audio terminal is emitted after the writer closes/finalizes the WAV and appends its metadata, or reports a concrete failure. READY and FAILED are both terminal. Face terminal includes COMPLETED, NO_FACE, PARTIAL, BUSY, TIMEOUT, DISCONNECTED and FAILED. Completion requires VAD to end, audio to be terminal and the last admitted batch to finish. A batch ending during audio does not complete the Event. Any prior batch/face failure keeps the final result COMPLETE_WITH_ERROR even if a later retry succeeds. COMPLETE_WITH_ERROR preserves both branches.

## Audio semantics and scheduling

The receiver must distinguish model NO_FACE from identity UNKNOWN. Python raises `NoFaceError` for zero detections and returns status 2; Swift exposes `RecognitionResult.noFace(requestID:imageID:processingTimeMs:)`. For Event requests, NO_FACE causes a new full-batch capture after the current batch completes, capped at three recaptures per scheduled round while the Event remains active. Earlier successes and failures are retained. A new periodic round resets that budget; manual captures use the same bound. Transport/decoding/model errors remain FAILED and do not request recapture.

The firmware keeps only the current request, next slot timestamp, batch/retry counters and an accumulated error flag in each bounded Event context. SD retains every request sentinel and face row. PC stores request history in `event_batches` and uses `(event_id, request_id, face_index)` for face sequence uniqueness. Its version-2 SQLite migration rebuilds only the old face-index constraint and backfills existing batches without deleting faces. `events.request_id` and face counters summarize the latest batch; `faces()` and `batches()` expose full history. Exact duplicates of old batches never reset newer state.

Event WAV is RAW PDM capture, 16 kHz / mono / PCM16. The 80 Hz DC blocker and configured DSP/AFE affect VAD processing, without changing saved event PCM. Application pre-roll defaults to 1000 ms with a 2000 ms ring. `audio_last_sample` is an exclusive boundary of actual saved capture, including the raw frames collected while VAD output lags. A cold-start utterance can have no available pre-roll and reports its actual first sample. ESP-SR uses VADNet `VAD_MODE_0` and a 1000 ms minimum noise/silence setting. No multi-utterance conversation aggregation is added.

Each Event's audio ends at natural VAD_END or at 300000 ms (five minutes) from the VAD trigger sample, whichever comes first. `AUDIO_EVENT_MAX_DURATION_MS` defines this limit. The RAW capture sample clock enforces it independently of further VAD output, and the final audio packet is trimmed at the deadline. Saved pre-roll is additional: with one second available, the WAV can contain 301 seconds. At the limit, `EVENT,audio_end,...,reason,max_duration` is logged; the end callback and existing recorder END/finalization run once, using the deadline as the stored `vad_end_sample`/timestamp. Reaching the limit alone is not an audio failure; existing capture/queue/SD errors remain failures. Overall Event completion still waits for both audio and face terminals. VAD is not reset: after a limit, no new Event is admitted until VAD reports non-speech and then a new speech transition. Continuous background speech after the cap is therefore not recorded as repeated Events.

Capture priority20/core0, AFE fetch16/core1, audio processing15/core1, EventManager9/core1, SD writer8/core1, camera7/core1. Capture queues without waiting. DMA overflow and queue gaps advance sample indices and increment dropped samples/overruns; ring history resets on a discontinuity. Affected WAVs report FAILED. SD data/metadata leave two queue control slots; BEGIN leaves one for END. Writer errors never cancel camera ownership. The writer performs all filesystem work, including append-only metadata. UART per-frame audio metrics default off; periodic summaries remain enabled.

## Storage and protocol

SD flat layout:

```text
/sd/event_<16HEX>.wav
/sd/audio_events.csv
/sd/face_associations.csv
/sd/event_lifecycle.csv
```

`audio_events.csv` has one terminal row per accepted utterance, with source/format, actual first/exclusive-last sample, VAD samples/timestamps and audio status. `face_associations.csv` has one row per validated returned result, including UNKNOWN/CLIENT_NO_FACE/FAILED, and one terminal sentinel per batch: `image_id=0`, `face_index=-1`, `face_count=expected_faces`, status=terminal. The sentinel preserves the request/count even if transfer failed before the first result. It is not a face. `event_lifecycle.csv` appends one OPEN/AUDIO_READY/COMPLETE and multiple FACE_BATCH_OPEN/FACE_BATCH_END records. FACE_BATCH_OPEN status is OK or CLIENT_NO_FACE_RETRY; the initial batch uses OPEN. Queue/SD metadata failures are explicitly counted and logged; an unavailable SD cannot promise local artifacts.

Protocol v2 keeps the 32-byte header and FACE_SEQUENCE reserved word. New messages are 15 OPEN (16-byte payload), 16 AUDIO_READY (32), 17 FACE_BATCH_END (32), 18 COMPLETE (16). FACE payload has nine trailing reserved bytes; no compiler struct is copied onto wire. All event messages have image/chunk/flags/reserved header fields zero. MTU 67 is required. Audio bytes are never sent. See `docs/BLE_PROTOCOL.md` for wire layouts and enums.

PC `EventStore` persists `events`, `event_batches` and `event_faces` independently of identity embeddings. Request/image ownership is unique within boot session, allowing original counters to restart after reboot. Each recognition is saved before BLE write, and sent state is tracked separately. Exact duplicate lifecycle messages are idempotent; conflicts/stale/crossed owners are rejected. Disconnect observations retain every face and leave audio pending until a real device terminal arrives. Notifications missed during disconnect are not invented; SD/structured logs remain authoritative evidence for such Events. No unbounded firmware replay or audio upload is added in Event 1.


## Build and inspect

From an activated ESP-IDF v6.0 environment at the repository root:

```sh
idf.py -C firmware build
idf.py -C firmware -p COM8 flash monitor
```

Replace COM8 with the actual serial port. Full flash includes the VAD model at 0x610000; flashing only the application omits it. NVS boot identity and SD contents are preserved by normal firmware flashing.

After installing the PC package:

```sh
python -m pc_client --event-database event_store.db run --wait-only
python tools/inspect_event_sd.py <copied-SD-directory> --output events.json
```

The inspector preserves available artifacts and marks missing/inconsistent lifecycle evidence INCOMPLETE; its CLI exits 2 for incomplete evidence.

## Runtime resources

The SD writer uses a 256-slot PSRAM-backed queue with two reserved control slots. Task stacks and I2S DMA remain internal. NimBLE host pools and eligible audio/network payloads use PSRAM. Wi-Fi buffers are bounded, Wi-Fi IRAM acceleration is disabled, and camera DMA staging is 16 KiB. These settings preserve internal-memory headroom while trading peak Wi-Fi throughput.

Startup reserves the audio processing stack and I2S resources before creating ESP-SR. Successful logs include `audio_capture: resources ready`, `SD mounted at /sd`, `esp_sr_afe: bridge ready`, and `Event 1 running`. The WakeNet warning is expected because only VADNet is enabled.

The default SD profile uses CS=GPIO21 with SCLK=7, MISO=8 and MOSI=9. A mount timeout requires checking the selected profile and physical connections before changing the filesystem. The profile name remains `legacy-gpio21`; the status LED sharing GPIO21 is disabled.
