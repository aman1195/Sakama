# Voice agent architecture — what a real voice mode costs, and what it needs

**Date:** 2026-09-02 · **Status:** research, feeds a future ADR · **Verified from source**, not from
vendor summaries. Prices and terms change; re-check before committing.

The ask: voice mode like Gemini Live, ChatGPT Advanced Voice, Grok voice. This is what that
actually requires, what it costs, and where it collides with rules this project already set.

---

## 1. The finding that matters most: the frameworks solve a problem we would be choosing

Pipecat (BSD-2), LiveKit (Apache-2.0), TEN (**NOASSERTION** on GitHub — unresolved licence, treat as
all-rights-reserved until someone reads the file) and Bolna are **server-side orchestrators**. They
exist to wire STT → LLM → TTS on infrastructure you operate, with WebRTC/SIP transport. The mobile
SDK in each is a thin client.

Adopting any of them means running a persistent audio server. That is a direct reversal of
[ADR 0011](../adr/0011-serverless-ai-gateway.md), which chose Supabase Edge Functions and explicitly
rejected a self-hosted proxy. It is an infrastructure, on-call and cost decision, not a dependency.

**We do not need them**, because of the next finding.

## 2. Ephemeral tokens remove the server from the realtime path

Google's Live API supports **server-minted ephemeral tokens** so a mobile client connects
**directly** to the Live API over WebSocket. Google's own words: it "improves latency and avoids
your backends needing to proxy the real time data."

- created server-side with the real API key — ours stays in the Edge Function, satisfying rule 3
- **1 minute** to start the session (`newSessionExpireTime`), **30 minutes** total (`expireTime`)
- **single use** by default (`uses: 1`)
- can be **locked to a model and response modality**, so a stolen token cannot be repurposed

That is the same shape ADR 0011 already uses: the Edge Function holds the secret and hands the
client a scoped, short-lived capability. No server to run, no LiveKit, no Pipecat.

**This is the architecture, if we go realtime.**

## 3. The cost, which is the real blocker

Audio bills at roughly **25 tokens per second** (Google's figure).

| Path | Audio in | Audio out | ≈ per minute of conversation |
|---|---|---|---|
| **Gemini 2.5 Flash native audio (Live)** | $3 / M | $12 / M | **~$0.013** |
| **OpenAI gpt-realtime-mini** | $10 / M | $20 / M | ~$0.03 |
| **OpenAI gpt-realtime-2.1** | $32 / M | $64 / M | **~$0.10** |
| Today's text turn (cheap model) | — | — | ~$0.0005 |

Per-minute assumes ~20s of user speech and ~40s of Vita speech; longer sessions cost more as
context grows.

Put against this product: **five minutes of voice a day is roughly $2 per user per month.** Sakama
is free, aimed at Indian users, with hard per-user budgets under
[rule 9](../../CLAUDE.md). At 10,000 daily active users that is ~$20,000/month for one feature.
Even Gemini Live — the cheapest credible option, and ~8× cheaper than OpenAI's full model — does
not survive contact with "free".

**A text turn costs about a thousandth of a voice minute.** That ratio, not the engineering, is what
decides this.

## 4. The free tier is not an escape hatch

Gemini's Live API *does* have a free tier. It is unusable here.

Google's API terms draw the line explicitly: on **unpaid** services Google uses submitted content
"to provide, improve, and develop Google products", and "human reviewers may read, annotate, and
process your API input and output". On **paid** services Google "doesn't use your prompts ... or
responses to improve our products", retaining data only to detect policy violations.

CLAUDE.md rule 3 already forbids free tiers for health data for exactly this reason. Voice makes it
worse, not better: audio is biometric, and a human reviewer listening to someone describe their
symptoms is a different category of exposure from a logged text string.

**So realtime voice must be paid tier, which is the expensive one.** There is no cheap-and-private
version.

## 5. What the fully-local path can and cannot do

`sherpa-onnx` (Apache-2.0, 14.5k stars) has a **real Flutter package** (`sherpa_onnx` 1.13,
`sherpa_onnx_ios`), runs offline on iOS and Android, and covers **both ends**:

- **Streaming ASR** — models around 60–80 MB, with a reported ~160 ms latency on mobile
- **TTS** — supports **Kokoro-82M (Apache-2.0)**, Piper (MIT) and VITS, including Hindi and English
- models are **downloaded at runtime**, so they do not inflate the store binary

That is a genuine upgrade over what ships today: streaming partial transcripts instead of waiting
for a final result, and far better voices than Apple's compact ones.

**The weak link is not STT or TTS — it is the LLM.** A 1–3B quantised model on the phone is a large
quality regression in precisely the thing that is supposed to be this product's wedge, plus a
multi-gigabyte download, battery drain and thermals on an iPhone 13. Local STT + local TTS +
**gateway LLM** is the sensible split, and it keeps audio on the device exactly as today.

## 6. Barge-in is a smaller problem than it looks

What ships is tap-to-interrupt, because holding the microphone open while the speaker plays makes
Vita hear itself.

**That is not theoretical — the first version of voice mode did it.** `flutter_tts` defaults
`awaitSpeakCompletion` to **false**, so `speak()` returns as soon as the utterance is handed to the
synthesizer, and the loop reopened the microphone over the loudspeaker. `speech_to_text` configures
the audio session with `.mixWithOthers` and mode `.default`, so there is no cancellation and the
recogniser hears the reply. The dangerous part is *what* it hears: Vita's confirmation prompt says
"shall I log that?", and "log that" is an affirmative — the app could confirm its own proposal and
write a food row with no user involved. Caught in review of #155; fixed by awaiting completion, a
settle delay, and a guard that treats our own words as silence.

Those three defences shut the microphone while Vita speaks. Keeping it OPEN — true barge-in, where
you cut Vita off mid-sentence — needs **acoustic echo cancellation**, and iOS provides it natively.

**Correction to the first version of this section.** It called AEC "a contained piece of platform
work". It is not, and the reason changes the plan. Checked against `speech_to_text` 7.4.0 source:

- it creates its **own `AVAudioEngine`** and installs a tap on the input node
  (`SpeechToTextPlugin.swift:359, :593`)
- it never calls `setVoiceProcessingEnabled(true)`, which is what actually turns on iOS's echo
  canceller — session mode alone does not
- it hardcodes `setCategory(.playAndRecord, options: [… .mixWithOthers])` and `setMode(.default)`
  on **every** listen (`:520-527`)
- `SpeechListenOptions` exposes no audio-session control at all — the entire surface is
  `cancelOnError`, `partialResults`, `onDevice`, `listenMode`, `sampleRate`, `autoPunctuation`,
  `enableHapticFeedback`, `pauseFor`, `listenFor`, `localeId`

So AEC is unreachable from Dart while `speech_to_text` owns audio capture. Setting the mode
afterwards loses the race on the next listen, and would not enable voice processing on an engine
that is already running.

**The consequence is a simplification, not a setback: barge-in and the sherpa-onnx move are the
same piece of work.** Owning audio capture is what makes streaming ASR possible AND what lets us
enable voice processing. They should be scoped as one project, not two — and neither needs LiveKit,
WebRTC or a server.

## 7. Recommendation

1. **Now — own the audio input, once.** `sherpa-onnx` streaming ASR + a Kokoro voice + voice
   processing enabled on our own capture. One project delivering both a better voice and real
   barge-in; §6 explains why they cannot be separated. No server, no audio egress, no ADR reversal,
   no per-minute cost. **Spike before adopting**, on a real iPhone 13, to the same evidence-first
   bar as PhotoSnap: model size and download UX, cold start, per-sentence latency, battery and
   thermals, and accuracy on Indian English.
2. **Then — realtime as a metered feature, not the default.** Gemini Live over ephemeral tokens,
   paid tier, direct from the client. It needs its own ADR covering audio egress, the biometric
   category, and a hard per-user minute cap enforced the way `ai_usage` already caps everything
   else. Plausible shapes: BYOK, a paid tier, or a small free allowance (a few minutes a day).
3. **Do not adopt LiveKit / Pipecat / TEN / Bolna** unless we decide to self-host the whole
   pipeline. Ephemeral tokens make the server they provide unnecessary, and TEN's licence is
   unresolved regardless.

## 8. Owner decision (2026-09-02): models are the user's choice, downloaded in-app

The direction, as set: **the user picks which models to use, the app names them (Supertonic, Qwen,
Gemma, …), and there is a download button inside the app.** Small on-device LLMs are in scope too.

That design answers three separate problems at once, which is why it is the right frame:

- **App size stops being a constraint.** Nothing is bundled; the store binary stays near today's
  25.6 MB. §5's "models are downloaded at runtime" becomes a product feature instead of a
  workaround.
- **Naming the models IS the attribution** these licences ask for, which removes the one real
  obligation OpenRAIL-M and the Gemma terms impose on a distributor.
- **The user opts in.** A gigabyte is a serious ask on Indian mobile data. It should be a choice
  with a number attached, not a surprise on first launch.

### What actually fits on the target device

Measured from the Hugging Face API on 2026-09-02, not estimated:

| Role | Candidate | Size | Licence |
|---|---|---|---|
| TTS | Kokoro-82M `uint8f16` | **114 MB** | Apache-2.0 |
| TTS | Kokoro-82M `q4f16` | 155 MB | Apache-2.0 |
| TTS | Supertonic 3 (published ONNX) | **401 MB** | OpenRAIL-M (code MIT) |
| STT | sherpa-onnx streaming ASR | 60–80 MB | Apache-2.0 |
| LLM | Gemma 3 1B `IQ4_XS` | **714 MB** | Gemma terms |
| LLM | Qwen3 1.7B `IQ4_XS` | **1010 MB** | Apache-2.0 |

A full local stack is therefore **roughly 0.9–1.2 GB**. The iPhone 13 has **4 GB of RAM**, so a 1B–2B
model at Q4 is workable and a 4B is not — iOS will jetsam the app long before the model finishes
loading. Size the picker to that, and do not offer what cannot run.

Supertonic has no quantised build published (the `onnx-community` mirror holds stubs), so at 401 MB
it is 3.5× Kokoro today. If a quantised release lands, its 31 languages and measured 0.3× RTF on an
e-reader CPU make it a serious contender — that is a spike question, not a desk one.

### The strongest case for an on-device LLM is NOT quality

§5 says a 1–3B model is a large quality regression for coaching, and that stands. But it is the
wrong yardstick, because the right job for a local model here is **rule 1**: offline-first. Vita is
the only part of this app that stops working without signal. A local model does not have to beat
the gateway — it has to beat *nothing at all* on a train, in a basement, on a dead prepaid balance.
Framed that way it is a fallback tier, not a replacement, and it is something no competitor ships.

### The safety question this opens, and it is real

ADR 0016's guardrails — propose-confirm, and the refusals around eating disorders — were written
assuming a capable model. A 1B model will follow them **less reliably**.

Propose-confirm protects us structurally: the model can only ever *propose*, and a human confirms,
so a weak model cannot write a wrong row on its own. The refusals have no such structural backstop.
**Any SLM that ships must be re-tested against the same safety prompts before it is offered**, and
if it fails them it does not go in the picker. That is a gate, not a preference.

### Device-tiered availability (owner direction, 2026-09-02)

The picker should **detect the device and unlock accordingly**: a flagship can download anything, a
mid-range phone sees a shorter list, and each entry carries plain-language descriptors — *fast*,
*slow to start*, *better voice*, *heavy on battery* — instead of RTF and megabytes.

This is right, and it prevents the worst failure this feature can produce: a user spends a gigabyte
of mobile data, the app is jetsammed on first use, and they blame the app rather than the model.
Four things decide whether it works.

**1. Gate on AVAILABLE memory, not on a device model.** iOS exposes
`os_proc_available_memory()` — Apple's recommended API for how much memory *this app* may still
use before jetsam — alongside `ProcessInfo.processInfo.physicalMemory` for total RAM. A lookup
table of device names would be wrong the week a new phone ships, and per
[MOBILE.md](../MOBILE.md) **we cannot hotfix**. Ask the device what it has; do not consult a list
of what devices usually have.

**2. The thresholds belong in remote config, not the binary.** The same reason. `app_config`
already carries `min_supported_build` and the kill switches, and it is read-only to the client and
off the PowerSync publication. Model entries and their RAM floors belong there, so a model that
turns out to thrash on 4 GB can be withdrawn without a store release.

**3. Show what a device cannot run, and say why.** Hiding entries produces "why does my friend have
this?". Showing *"Needs 6 GB — this phone has 4 GB"* is the same instinct as the sync-failure
receipts and the below-the-floor plan notice: this app tells people what happened rather than
quietly doing less. It also sets expectations before someone upgrades.

**4. Lead the descriptors with TIME TO FIRST AUDIO.** Every latency analysis of this pipeline puts
the bottleneck in TTS first-audio, not the LLM — the spread across candidate engines is 106 ms to
3,658 ms, an order of magnitude, while a 1B LLM's first token is 20–30 ms. So the label a user
reads should answer *"how long before it talks"* and *"how good does it sound"*, in that order.
The LLM tier additionally needs a **battery and heat** warning, because that is where the power
goes.

**The floor matters more than the ceiling.** A large share of this app's market has 3–4 GB devices
that can run streaming STT and a small TTS but **cannot** hold a 1B LLM alongside the app. That is
not an edge case to handle with an empty screen; it is the common case, and it should read as
*"your phone can do voice; offline coaching needs more memory"* — a complete answer, not a gap.

**Thresholds come from the spike, not from a table.** Nearly every mobile figure in the published
comparisons is marked *estimated*. The RAM floors and the descriptor wording should be set from
measurements on real hardware, starting with the iPhone 13 (A15, 4 GB) — which is both the test
device and a fair proxy for the mid tier.

### What this means to build

1. A **model registry** — id, role (STT/TTS/LLM), display name, provider, size, licence, minimum
   device RAM, download URL, checksum.
2. A **download manager** — resumable, pausable, cancellable, deletable, with the size shown before
   a byte moves, and Wi-Fi-only by default.
3. A **models screen** naming each model and its provider and licence, which is the attribution.
4. **Graceful fallback** — Apple's on-device voices and the gateway model remain the default, so the
   app is whole before anything is downloaded and stays whole if the user declines or deletes.
5. **A device probe** — available memory at download time, checked against a remote-config floor,
   with an honest reason shown when a model is out of reach.

Steps 1–4 are independent of which runtime wins the spike, so they can be built before it resolves.

## Sources

- Gemini API pricing (Live API native audio, 25 tokens/second) — https://ai.google.dev/gemini-api/docs/pricing
- Gemini ephemeral tokens — https://ai.google.dev/gemini-api/docs/ephemeral-tokens
- Gemini API terms, paid vs unpaid data use — https://ai.google.dev/gemini-api/terms
- OpenAI Realtime pricing — https://www.cloudzero.com/blog/openai-pricing/ · https://tokenmix.ai/blog/openai-realtime-voice-api-2026-cost-latency
- sherpa-onnx — https://github.com/k2-fsa/sherpa-onnx · https://pub.dev/packages/sherpa_onnx
- Licences verified via the GitHub API: sherpa-onnx Apache-2.0, whisper.cpp MIT, LiveKit Apache-2.0,
  Pipecat BSD-2-Clause, TEN NOASSERTION; Kokoro-82M Apache-2.0 and fish-speech CC-BY-NC-SA-4.0
  (non-commercial — unusable here) via the Hugging Face API.
