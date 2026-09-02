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
you can cut Vita off mid-sentence — is an **acoustic echo cancellation** problem, not an
architectural one: iOS solves it natively via `AVAudioSession` in voice-chat mode with AEC enabled.

It does not require LiveKit, WebRTC, or a server. It is a contained piece of platform work, and it
is the single change that would most make the current mode feel like the ones being compared to.

## 7. Recommendation

1. **Now — make what exists good.** Native AEC for true barge-in, and `sherpa-onnx` for streaming
   ASR + a Kokoro voice. No server, no audio egress, no ADR reversal, no new per-minute cost.
   Measure on a real iPhone 13 before adopting: cold start, per-sentence latency, battery, size.
2. **Then — realtime as a metered feature, not the default.** Gemini Live over ephemeral tokens,
   paid tier, direct from the client. It needs its own ADR covering audio egress, the biometric
   category, and a hard per-user minute cap enforced the way `ai_usage` already caps everything
   else. Plausible shapes: BYOK, a paid tier, or a small free allowance (a few minutes a day).
3. **Do not adopt LiveKit / Pipecat / TEN / Bolna** unless we decide to self-host the whole
   pipeline. Ephemeral tokens make the server they provide unnecessary, and TEN's licence is
   unresolved regardless.

## Sources

- Gemini API pricing (Live API native audio, 25 tokens/second) — https://ai.google.dev/gemini-api/docs/pricing
- Gemini ephemeral tokens — https://ai.google.dev/gemini-api/docs/ephemeral-tokens
- Gemini API terms, paid vs unpaid data use — https://ai.google.dev/gemini-api/terms
- OpenAI Realtime pricing — https://www.cloudzero.com/blog/openai-pricing/ · https://tokenmix.ai/blog/openai-realtime-voice-api-2026-cost-latency
- sherpa-onnx — https://github.com/k2-fsa/sherpa-onnx · https://pub.dev/packages/sherpa_onnx
- Licences verified via the GitHub API: sherpa-onnx Apache-2.0, whisper.cpp MIT, LiveKit Apache-2.0,
  Pipecat BSD-2-Clause, TEN NOASSERTION; Kokoro-82M Apache-2.0 and fish-speech CC-BY-NC-SA-4.0
  (non-commercial — unusable here) via the Hugging Face API.
