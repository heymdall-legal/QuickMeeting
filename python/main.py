import argparse
import json
import math
import multiprocessing
import os
import sys
import soundfile as sf
import torch
import numpy as np
import torchaudio
import warnings
from importlib import import_module
from pathlib import Path

# from matplotlib_cache import configure_matplotlib_cache_environment


# if getattr(sys, "frozen", False):
#     configure_matplotlib_cache_environment()


TRANSCRIPTION_MODEL = "mlx-community/whisper-turbo"
DIARIZATION_MODEL = "pyannote/speaker-diarization-community-1"
MATCH_THRESHOLD = 0.8
CANDIDATE_THRESHOLD = 0.7


def parse_args(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-file", required=True, type=Path)
    parser.add_argument("--hf-token", required=True)
    parser.add_argument("--hf-home", type=Path)
    parser.add_argument("--language")
    parser.add_argument("--initial-prompt")
    parser.add_argument("--known-speakers-file", type=Path)
    return parser.parse_args(argv)


def emit_event(payload):
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def validate_args(args):
    if not args.input_file.exists():
        raise ValueError(f"input file does not exist: {args.input_file}")
    if not args.input_file.is_file():
        raise ValueError(f"input file is not a file: {args.input_file}")
    if args.known_speakers_file is not None:
        if not args.known_speakers_file.exists():
            raise ValueError(
                f"known speakers file does not exist: {args.known_speakers_file}"
            )
        if not args.known_speakers_file.is_file():
            raise ValueError(
                f"known speakers file is not a file: {args.known_speakers_file}"
            )


def configure_environment(args):
    os.environ["HF_TOKEN"] = str(args.hf_token)
    if args.hf_home is not None:
        os.environ["HF_HOME"] = str(args.hf_home)


def suppress_warnings_and_logs():
    warnings.filterwarnings("ignore")


class DiarizationProgressHook:
    def __init__(self, emitter):
        self._emitter = emitter
        self._milestones = {}

    def __call__(
        self,
        step_name,
        step_artifact,
        file=None,
        total=None,
        completed=None,
    ):
        if total in (None, 0) or completed is None:
            return

        percent = max(0, min(100, int(completed * 100 / total)))
        milestone = percent
        last_reported = self._milestones.get(step_name, 0)
        while milestone >= last_reported + 1:
            last_reported += 1
            self._emitter(
                {"status": "diarization", "step": step_name, "percent": last_reported}
            )
        self._milestones[step_name] = last_reported


def build_download_event(progress, percent):
    payload = {"status": "downloading", "percent": percent}
    description = getattr(progress, "desc", None)
    if description:
        payload["file"] = str(description)

    completed = getattr(progress, "n", None)
    if isinstance(completed, (int, float)):
        payload["bytes_downloaded"] = int(completed)

    total = getattr(progress, "total", None)
    if isinstance(total, (int, float)):
        payload["bytes_total"] = int(total)

    return payload


class DownloadProgressProxy:
    def __init__(self, progress, emitter, description=None, total=None, initial=0):
        self._progress = progress
        self._emitter = emitter
        self._description = description
        self._total = total if total is not None else getattr(progress, "total", None)
        self._completed = initial if initial is not None else getattr(progress, "n", 0)
        self._last_reported = 0

        if hasattr(progress, "n"):
            try:
                self._completed = progress.n
            except Exception:
                pass

    def update(self, n=1):
        result = self._progress.update(n)
        if n is not None:
            self._completed += n
        if self._total:
            percent = max(0, min(100, int(self._completed * 100 / self._total)))
            while percent >= self._last_reported + 1:
                self._last_reported += 1
                payload = {
                    "status": "downloading",
                    "percent": self._last_reported,
                    "bytes_downloaded": int(self._completed),
                    "bytes_total": int(self._total),
                }
                file_name = self._description or getattr(self._progress, "desc", None)
                if file_name:
                    payload["file"] = str(file_name)
                self._emitter(payload)
        return result

    def __getattr__(self, name):
        return getattr(self._progress, name)


def wrap_hf_download_function(function, tqdm_class):
    def wrapped(*args, **kwargs):
        kwargs.setdefault("tqdm_class", tqdm_class)
        return function(*args, **kwargs)

    return wrapped


def patch_loaded_module_download_function(module_name, attribute_name, tqdm_class):
    module = sys.modules.get(module_name)
    if module is None:
        return

    if hasattr(module, attribute_name):
        setattr(
            module,
            attribute_name,
            wrap_hf_download_function(getattr(module, attribute_name), tqdm_class),
        )


def wrap_progress_bar_factory(function, tqdm_class):
    def wrapped(*args, **kwargs):
        kwargs["cls"] = tqdm_class
        return function(*args, **kwargs)

    return wrapped


def wrap_progress_bar_context(function, tqdm_class, emitter):
    def wrapped(*args, **kwargs):
        kwargs["tqdm_class"] = tqdm_class
        context_manager = function(*args, **kwargs)

        class WrappedContextManager:
            def __enter__(self_inner):
                progress = context_manager.__enter__()
                return DownloadProgressProxy(
                    progress,
                    emitter,
                    description=kwargs.get("desc"),
                    total=kwargs.get("total"),
                    initial=kwargs.get("initial", 0),
                )

            def __exit__(self_inner, exc_type, exc_value, traceback):
                return context_manager.__exit__(exc_type, exc_value, traceback)

        return WrappedContextManager()

    return wrapped


def install_progress_hook(emitter=emit_event):
    transcribe_module = import_module("mlx_whisper.transcribe")
    original_tqdm = transcribe_module.tqdm.tqdm

    class ProgressTqdm(original_tqdm):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self._last_reported = 0

        def update(self, n=1):
            result = super().update(n)
            if not self.disable and self.total:
                percent = int(self.n * 100 / self.total)
                milestone = percent
                while milestone >= self._last_reported + 1:
                    self._last_reported += 1
                    emitter({"status": "transcribing", "percent": self._last_reported})
            return result

        def display(self, *args, **kwargs):
            return

        def refresh(self, *args, **kwargs):
            return

    transcribe_module.tqdm.tqdm = ProgressTqdm


def install_download_progress_hook(emitter=emit_event):
    try:
        utils_tqdm_module = import_module("huggingface_hub.utils.tqdm")
    except (ImportError, ModuleNotFoundError):
        return

    try:
        utils_module = import_module("huggingface_hub.utils")
    except (ImportError, ModuleNotFoundError):
        utils_module = None

    original_tqdm = utils_tqdm_module.tqdm

    class DownloadProgressTqdm(original_tqdm):
        @classmethod
        def get_lock(cls):
            getter = getattr(original_tqdm, "get_lock", None)
            if getter is None:
                return None
            return getter()

        @classmethod
        def set_lock(cls, lock):
            setter = getattr(original_tqdm, "set_lock", None)
            if setter is None:
                return None
            return setter(lock)

        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self._last_reported = 0

        def update(self, n=1):
            result = super().update(n)
            if self.total:
                percent = max(0, min(100, int(self.n * 100 / self.total)))
                milestone = percent
                while milestone >= self._last_reported + 1:
                    self._last_reported += 1
                    emitter(build_download_event(self, self._last_reported))
            return result

        def display(self, *args, **kwargs):
            return

        def refresh(self, *args, **kwargs):
            return

    utils_tqdm_module.tqdm = DownloadProgressTqdm

    if utils_module is not None and hasattr(utils_module, "disable_progress_bars"):
        utils_module.disable_progress_bars()

    for module_name in ("tqdm.auto", "tqdm.std"):
        try:
            tqdm_module = import_module(module_name)
        except (ImportError, ModuleNotFoundError):
            continue
        if hasattr(tqdm_module, "tqdm"):
            tqdm_module.tqdm = DownloadProgressTqdm

    huggingface_hub_module = sys.modules.get("huggingface_hub")

    snapshot_download = (
        None
        if huggingface_hub_module is None
        else huggingface_hub_module.__dict__.get("snapshot_download")
    )
    if snapshot_download is not None:
        huggingface_hub_module.snapshot_download = wrap_hf_download_function(
            snapshot_download,
            DownloadProgressTqdm,
        )
    hf_hub_download = (
        None
        if huggingface_hub_module is None
        else huggingface_hub_module.__dict__.get("hf_hub_download")
    )
    if hf_hub_download is not None:
        huggingface_hub_module.hf_hub_download = wrap_hf_download_function(
            hf_hub_download,
            DownloadProgressTqdm,
        )

    try:
        snapshot_download_module = import_module("huggingface_hub._snapshot_download")
    except (ImportError, ModuleNotFoundError):
        snapshot_download_module = None
    if snapshot_download_module is not None and hasattr(
        snapshot_download_module, "snapshot_download"
    ):
        snapshot_download_module.snapshot_download = wrap_hf_download_function(
            snapshot_download_module.snapshot_download,
            DownloadProgressTqdm,
        )
        if hasattr(snapshot_download_module, "hf_tqdm"):
            snapshot_download_module.hf_tqdm = DownloadProgressTqdm
        if hasattr(snapshot_download_module, "_create_progress_bar"):
            snapshot_download_module._create_progress_bar = wrap_progress_bar_factory(
                snapshot_download_module._create_progress_bar,
                DownloadProgressTqdm,
            )

    try:
        file_download_module = import_module("huggingface_hub.file_download")
    except (ImportError, ModuleNotFoundError):
        file_download_module = None
    if file_download_module is not None:
        file_download_module.tqdm = DownloadProgressTqdm
        if hasattr(file_download_module, "hf_hub_download"):
            file_download_module.hf_hub_download = wrap_hf_download_function(
                file_download_module.hf_hub_download,
                DownloadProgressTqdm,
            )
        if hasattr(file_download_module, "_get_progress_bar_context"):
            file_download_module._get_progress_bar_context = wrap_progress_bar_context(
                file_download_module._get_progress_bar_context,
                DownloadProgressTqdm,
                emitter,
            )

    patch_loaded_module_download_function(
        "mlx_whisper.load_models",
        "snapshot_download",
        DownloadProgressTqdm,
    )
    patch_loaded_module_download_function(
        "pyannote.audio.utils.hf_hub",
        "hf_hub_download",
        DownloadProgressTqdm,
    )

def load_audio(audio_path):
    data, sr = sf.read(str(audio_path), dtype="float32")
    if data.ndim > 1:
        data = data.mean(axis=1)                            # downmix to mono
    audio = data.astype(np.float32)                         # -> transcribe()

    waveform = torch.from_numpy(audio).unsqueeze(0)

    return audio, waveform, sr

def transcribe_audio(audio_path, language=None, initial_prompt=None):
    mlx_whisper = import_module("mlx_whisper")
    transcribe_module = import_module("mlx_whisper.transcribe")
    kwargs = {
        "path_or_hf_repo": TRANSCRIPTION_MODEL,
        "word_timestamps": True,
        "verbose": False,
        "condition_on_previous_text": False,
        "no_speech_threshold": 0.5,
    }
    if language is not None:
        kwargs["language"] = language
    if initial_prompt is not None:
        kwargs["initial_prompt"] = initial_prompt
    original_print = getattr(transcribe_module, "print", print)
    transcribe_module.print = lambda *args, **kwargs: None
    try:
        audio, waveform, sr = load_audio(audio_path)
        return mlx_whisper.transcribe(audio, **kwargs)
    finally:
        transcribe_module.print = original_print


def configure_diarization_device(pipeline):
    try:
        torch = import_module("torch")
    except ModuleNotFoundError:
        return pipeline

    if torch.backends.mps.is_available():
        return pipeline.to(torch.device("mps"))
    return pipeline


def diarize_audio(audio_path, hf_token, emitter=emit_event):
    pyannote_audio = import_module("pyannote.audio")
    pipeline = pyannote_audio.Pipeline.from_pretrained(
        DIARIZATION_MODEL,
        token=hf_token,
    )
    pipeline = configure_diarization_device(pipeline)
    audio, waveform, sr = load_audio(audio_path)
    return pipeline({"waveform": waveform, "sample_rate": sr}, hook=DiarizationProgressHook(emitter))


def extract_words(transcription_result):
    words = []
    for segment in transcription_result.get("segments", []):
        for word in segment.get("words", []):
            words.append(word)
    return words


def extract_speaker_turns(diarization_result):
    diarization = getattr(
        diarization_result,
        "exclusive_speaker_diarization",
        getattr(diarization_result, "speaker_diarization", diarization_result),
    )
    turns = []

    if hasattr(diarization, "itertracks"):
        for turn, _, speaker in diarization.itertracks(yield_label=True):
            turns.append(
                {"speaker": speaker, "start": float(turn.start), "end": float(turn.end)}
            )
        return turns

    for item in diarization:
        if len(item) == 2:
            turn, speaker = item
        else:
            turn, _, speaker = item
        turns.append(
            {"speaker": speaker, "start": float(turn.start), "end": float(turn.end)}
        )
    return turns


def _vector_to_list(vector):
    if vector is None:
        return None
    if hasattr(vector, "tolist"):
        vector = vector.tolist()
    return [float(value) for value in vector]


def extract_meeting_speakers(diarization_result):
    annotation = getattr(diarization_result, "speaker_diarization", None)
    labels = list(annotation.labels()) if annotation and hasattr(annotation, "labels") else []
    embeddings = getattr(diarization_result, "speaker_embeddings", None)
    if embeddings is None:
        embeddings = []
    speakers = []

    for index, speaker_id in enumerate(labels):
        centroid = _vector_to_list(embeddings[index]) if index < len(embeddings) else None
        speakers.append(
            {
                "speaker_id": speaker_id,
                "centroid": centroid,
                "match": {"status": "unknown"},
            }
        )

    return speakers


def average_centroids(centroids):
    if centroids is None or len(centroids) == 0:
        return None
    size = len(centroids[0])
    return [
        sum(vector[index] for vector in centroids) / len(centroids)
        for index in range(size)
    ]


def cosine_similarity(left, right):
    if left is None or right is None:
        return None
    if len(left) == 0 or len(right) == 0:
        return None

    numerator = sum(a * b for a, b in zip(left, right))
    left_norm = math.sqrt(sum(a * a for a in left))
    right_norm = math.sqrt(sum(b * b for b in right))
    if left_norm == 0 or right_norm == 0:
        return None
    return numerator / (left_norm * right_norm)


def match_meeting_speakers(meeting_speakers, registry):
    matched = []
    known_speakers = registry.get("speakers", [])

    for meeting_speaker in meeting_speakers:
        speaker = {**meeting_speaker, "match": {"status": "unknown"}}
        best_profile = None
        best_similarity = None

        for profile in known_speakers:
            profile_centroids = profile.get("centroids") or []
            if not profile_centroids:
                single = profile.get("centroid")
                if single:
                    profile_centroids = [single]
            best_for_profile = None
            for known_centroid in profile_centroids:
                similarity = cosine_similarity(speaker.get("centroid"), known_centroid)
                if similarity is not None and (best_for_profile is None or similarity > best_for_profile):
                    best_for_profile = similarity
            if best_for_profile is None:
                continue
            if best_similarity is None or best_for_profile > best_similarity:
                best_similarity = best_for_profile
                best_profile = profile

        if best_profile is not None and best_similarity is not None:
            if best_similarity >= MATCH_THRESHOLD:
                speaker["match"] = {
                    "status": "matched",
                    "speaker_id": best_profile["id"],
                    "similarity": round(best_similarity, 3),
                }
            elif best_similarity >= CANDIDATE_THRESHOLD:
                speaker["match"] = {
                    "status": "candidate",
                    "speaker_id": best_profile["id"],
                    "similarity": round(best_similarity, 3),
                }

        matched.append(speaker)

    return matched


def normalize_known_speakers(payload):
    if isinstance(payload, dict):
        payload = payload.get("speakers", [])
    if not isinstance(payload, list):
        raise ValueError("known speakers file must contain an array of speakers")

    normalized = []
    for item in payload:
        if not isinstance(item, dict):
            raise ValueError("known speaker entries must be objects")
        speaker_id = item.get("id")
        if not isinstance(speaker_id, str) or not speaker_id:
            raise ValueError("known speaker id must be a non-empty string")

        centroid = item.get("centroid")
        centroids = item.get("centroids")

        if centroid is not None:
            if not isinstance(centroid, list) or not centroid:
                raise ValueError("known speaker centroid must be a non-empty array")
            all_centroids = [[float(v) for v in centroid]]
        elif centroids is not None:
            if not isinstance(centroids, list) or not centroids:
                raise ValueError("known speaker centroids must be a non-empty array")
            all_centroids = []
            for c in centroids:
                if not isinstance(c, list) or not c:
                    raise ValueError("each centroid must be a non-empty array")
                all_centroids.append([float(v) for v in c])
        else:
            raise ValueError("known speaker must have either 'centroid' or 'centroids'")

        normalized.append({"id": speaker_id, "centroids": all_centroids})
    return normalized


def load_known_speakers_file(path):
    with path.open() as handle:
        return normalize_known_speakers(json.load(handle))


def find_speaker_for_word(word, speaker_turns):
    if not speaker_turns:
        return "UNKNOWN"

    best_turn = None
    best_overlap = -1.0
    for turn in speaker_turns:
        overlap = max(
            0.0,
            min(word["end"], turn["end"]) - max(word["start"], turn["start"]),
            )
        if overlap > best_overlap:
            best_overlap = overlap
            best_turn = turn

    if best_overlap > 0:
        return best_turn["speaker"]

    midpoint = (word["start"] + word["end"]) / 2
    return min(
        speaker_turns,
        key=lambda turn: 0.0
        if turn["start"] <= midpoint <= turn["end"]
        else min(abs(midpoint - turn["start"]), abs(midpoint - turn["end"])),
    )["speaker"]


def build_transcript_blocks(words, speaker_turns):
    blocks = []
    for word in words:
        speaker_id = find_speaker_for_word(word, speaker_turns)
        if blocks and blocks[-1]["speaker_id"] == speaker_id:
            blocks[-1]["parts"].append(word["word"])
            blocks[-1]["end"] = word["end"]
        else:
            blocks.append(
                {
                    "speaker_id": speaker_id,
                    "start": word["start"],
                    "end": word["end"],
                    "parts": [word["word"]],
                }
            )
    return blocks


def build_transcript_segments(blocks, label_map=None):
    segments = []
    for block in blocks:
        segments.append(
            {
                "speaker_id": block["speaker_id"],
                "label": (label_map or {}).get(block["speaker_id"], block["speaker_id"]),
                "start": round(block["start"], 3),
                "end": round(block["end"], 3),
                "text": "".join(block["parts"]).strip(),
            }
        )
    return segments


def build_output_speakers(meeting_speakers):
    output = []
    for speaker in meeting_speakers:
        match = speaker.get("match", {})
        output.append(
            {
                "id": speaker["speaker_id"],
                "matched_id": match.get("speaker_id")
                if match.get("status") in {"matched", "candidate", "confirmed"}
                else None,
                "probability": match.get("similarity")
                if match.get("status") in {"matched", "candidate"}
                else None,
                "centroid": speaker.get("centroid"),
            }
        )
    return output


def build_output_segments(transcript_segments):
    return [
        {
            "speaker": segment["speaker_id"],
            "start": segment["start"],
            "end": segment["end"],
            "text": segment["text"],
        }
        for segment in transcript_segments
    ]


def build_completed_payload(meeting_speakers, transcript_segments):
    return {
        "status": "completed",
        "speakers": build_output_speakers(meeting_speakers),
        "segments": build_output_segments(transcript_segments),
    }


def run_pipeline(args):
    transcription_result = transcribe_audio(
        args.input_file,
        language=args.language,
        initial_prompt=args.initial_prompt,
    )
    diarization_result = diarize_audio(args.input_file, hf_token=args.hf_token)
    words = extract_words(transcription_result)
    speaker_turns = extract_speaker_turns(diarization_result)
    meeting_speakers = extract_meeting_speakers(diarization_result)
    known_speakers = (
        load_known_speakers_file(args.known_speakers_file)
        if args.known_speakers_file is not None
        else []
    )
    registry = {"speakers": known_speakers}
    meeting_speakers = match_meeting_speakers(meeting_speakers, registry)
    blocks = build_transcript_blocks(words, speaker_turns)
    transcript_segments = build_transcript_segments(
        blocks,
        {speaker["speaker_id"]: speaker["speaker_id"] for speaker in meeting_speakers},
    )
    return build_completed_payload(meeting_speakers, transcript_segments)


def main(argv=None):
    try:
        args = parse_args(argv)
        validate_args(args)
        configure_environment(args)
        suppress_warnings_and_logs()
        install_download_progress_hook()
        install_progress_hook()
        emit_event({"status": "running"})
        emit_event(run_pipeline(args))
        return 0
    except SystemExit as error:
        emit_event({"status": "error", "reason": str(error) or "invalid arguments"})
        return 1
    except Exception as error:
        emit_event({"status": "error", "reason": str(error)})
        return 1


def run_cli(argv=None):
    multiprocessing.freeze_support()
    return main(argv)


if __name__ == "__main__":
    raise SystemExit(run_cli())
