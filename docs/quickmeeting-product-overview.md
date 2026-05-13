# QuickMeeting Product Overview

## What QuickMeeting is

QuickMeeting is a macOS desktop app for capturing meeting audio, turning that audio into a transcript on the same machine, and keeping each meeting's recording and transcript organized in a local library. It is designed for people who want a lightweight meeting recorder and transcription tool without depending on a cloud transcription service for the core workflow.

From a product point of view, QuickMeeting sits somewhere between a personal note-taking utility and a meeting archive tool. It helps a user start a recording quickly, keep a history of meetings, transcribe recordings later, review the transcript, rename speakers, and export transcript text when needed.

## What it can do

- Record meeting audio from the Mac app interface or the menu bar.
- Create one meeting record per recording session and keep a browsable meeting history.
- Store the canonical meeting audio file on disk.
- Run on-device transcription using downloadable Whisper models.
- Show transcription and diarization progress inside the app.
- Display transcripts in a readable meeting detail view.
- Support basic speaker-name cleanup after transcription.
- Rename meetings after capture.
- Play back recorded meeting audio inside the app.
- Copy a transcript export in Markdown format for use in other tools.
- Read selected macOS calendars to show the next event for today and use a nearby event title as the default meeting name.

## Technical shape

QuickMeeting is a native macOS app built with SwiftUI. It uses SwiftData for persisted meeting metadata and stores larger artifacts, such as audio files, in app-managed folders on disk instead of embedding them in the database.

The app is structured around a few core services:

- a recording service for capture lifecycle
- a transcription service for running Whisper-based transcription
- a meeting store for persistence and state updates
- a model manager for installing and selecting local transcription models
- a calendar integration layer built on macOS EventKit

Transcription is local-first. The app downloads transcription models to the Mac, selects one of those installed models as the default, and runs transcription through a WhisperKit-based backend. In the current codebase, transcription is configured with Russian (`ru`) decoding by default.

## Data and outputs

For each meeting, QuickMeeting maintains a structured record that includes:

- title
- start and end time
- status such as recording, recorded, transcribing, completed, or failed
- local audio file path
- transcript preview text
- structured transcript segments and speakers
- optional calendar event reference
- attendee names derived from a matching calendar event

In practical terms, the app produces two useful outputs:

- a local audio recording, currently treated as the canonical source artifact
- a transcript that can be viewed in-app and copied out as Markdown

## Main limitations

- macOS only. This is not a web app, mobile app, or cross-platform service.
- The current integration model is mostly local and user-driven. There is no exposed API, webhook system, or built-in sync layer for other apps.
- Only one recording session can be active at a time.
- Only one transcription job can be active at a time.
- Transcription depends on a locally installed default model. If no model is installed, transcription cannot run.
- Calendar support is read-oriented. The app reads selected calendars and event metadata, but it is not acting as a calendar writer or meeting scheduler.
- Transcript export is currently lightweight: the app copies Markdown to the clipboard rather than managing a full outbound document pipeline.
- The app keeps its own local storage model, so external systems would need to integrate through files, copied transcript content, or a future custom bridge.

## Current implementation caveats

These are especially important if you are thinking about automation or interoperability:

- The recording pipeline is designed to capture both system audio and microphone audio, but the implementation should be validated carefully in real usage before treating mixed multi-source capture as a guaranteed contract.
- The app chooses and manages its own canonical artifact locations internally rather than exposing a shared workspace model.
- Calendar matching is intentionally narrow: it looks at selected calendars, ignores all-day events, and uses nearby timed events to infer context.
- Speaker labeling is post-processing, not a live participant identity system.
- There is no concept of team accounts, shared libraries, permissions roles, or centralized admin control in the current product.

## Integration implications

QuickMeeting is easiest to integrate with other apps in these ways:

- as a local transcript source, where a user manually copies Markdown into another app
- as a local audio-and-transcript archive that another tool reads from disk
- as a desktop-side capture utility that feeds a later workflow, such as summarization, CRM logging, or document generation
- as a contextual companion to calendar-driven workflows on the same Mac

It is harder to integrate in these ways without additional product work:

- fully automated server-side ingestion
- real-time transcription streaming into another app
- multi-user collaboration
- organization-wide deployment with centralized data management
- direct bidirectional sync with task managers, CRMs, note systems, or messaging tools

## Bottom line

QuickMeeting is best understood as a local-first macOS meeting recorder and transcription workspace. It already covers the core loop of capture, transcribe, review, and export, with some useful calendar context. Its current strength is simplicity and on-device ownership of meeting artifacts. Its current weakness, from an integration perspective, is that it behaves more like a standalone desktop tool than an extensible platform.
