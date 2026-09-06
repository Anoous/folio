# Weibo Subtitle Extraction Validation

Source title: 刘强东谈如何管理自己。全是干货，以后估计都不可能听到刘强东这样演讲了。
Video id: 5291219005475796
Video duration: 1234.466s

## OCR hard-subtitle extraction
- Frame sampling: 4 fps
- Frames expected from duration: 4938
- Frames OCR processed: 4938
- Frame index coverage: 0..4937
- Missing frame indices: 0
- Frames with bottom caption text: 4401
- Final OCR subtitle segments: 644
- OCR subtitle time coverage: 1100.50s
- First OCR caption: 0.00s - 而且是严格遵守这个方方面去用的
- Last OCR caption: 1229.75s - 谢谢大家

## ASR cross-check
- Whisper model: small, language=Chinese
- ASR segments: 797
- First ASR segment: 0.00s - 硬了这个一二十年以来 回过头我觉得呢
- Last ASR segment: 1229.62s - 谢谢大家

## Long no-subtitle gaps in OCR
- Before OCR segment 19: 37.25s to 40.25s (3.00s)
- Before OCR segment 191: 353.50s to 356.25s (2.75s)
- Before OCR segment 200: 371.50s to 374.00s (2.50s)
- Before OCR segment 302: 583.25s to 586.75s (3.50s)
- Before OCR segment 372: 712.50s to 716.50s (4.00s)
- Before OCR segment 398: 765.00s to 767.50s (2.50s)
- Before OCR segment 557: 1060.50s to 1062.75s (2.25s)
- Before OCR segment 596: 1142.25s to 1145.25s (3.00s)

## Notes
- The Weibo video has no embedded subtitle stream; the final subtitle files are extracted from burned-in yellow hard subtitles by OCR.
- ASR output is retained only as a reference check because it does not exactly match the on-screen subtitle wording.
- Raw per-frame OCR JSONL is retained so individual subtitle lines can be audited against frame images if needed.
