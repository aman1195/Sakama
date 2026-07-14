# 0004. Sakama is closed-source and commercial

**Status:** Accepted · **Date:** 2026-07

## Context
The question arose because the best open-source nutrition app (OpenNutriTracker) is GPL-3.0. Adopting it
would force Sakama's entire source — including the AI coach, PhotoSnap, and plan engine — to be published
under GPL, letting any competitor clone the product wholesale. The product is free to users, so an
open-source stance was genuinely arguable.

The product owner decided: **closed-source.**

## Decision
Sakama's source is **closed and proprietary**. The *product* remains free to users (free forever, no ads,
no data selling), but the code is not published.

## Consequences
- **All GPL/AGPL code is disqualified**, regardless of quality: OpenNutriTracker, wger, FoodYou, Waistline.
  They may be read for domain understanding, **never copied** (derivative-work risk).
- Only **MIT / Apache-2.0 / BSD / CC0** dependencies are permitted. A licence checker belongs in CI.
- We retain full freedom to license, dual-license, or open-source later **because we own the copyright** —
  a freedom forking GPL code would have permanently destroyed.

## Note on an earlier error
An earlier claim that "GPL is incompatible with the Apple App Store" was **overstated**. OpenNutriTracker
itself ships on the App Store. The FSF objection is real and Apple has removed GPL apps before, but it is a
contested grey area, **not** the decisive factor. The decisive factor is copyleft.
