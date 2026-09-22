import difflib
import os
import re
import subprocess
import sys
import tempfile
from typing import Any, Callable, Optional

import pymupdf


def _sanitize_for_filename(name: str) -> str:
    clean = name.strip()
    # Remove quotes
    for ch in '«»""\'`':
        clean = clean.replace(ch, '')
    # Replace invalid OS filename characters with underscore
    for ch in r'\/:*?<>|':
        clean = clean.replace(ch, '_')
    # Collapse consecutive spaces/underscores
    clean = re.sub(r'_+', '_', clean)
    clean = re.sub(r'\s+', ' ', clean).strip(' _')
    return clean


def _ocr_image_macos(image_path: str) -> list[str]:
    try:
        import Vision
        from Foundation import NSURL
        from Quartz import CIImage

        url = NSURL.fileURLWithPath_(image_path)
        ci_img = CIImage.imageWithContentsOfURL_(url)
        if ci_img is None:
            return []

        handler = Vision.VNImageRequestHandler.alloc().initWithCIImage_options_(ci_img, {})
        lines: list[str] = []

        def callback(request: Any, error: Any) -> None:
            if error:
                return
            for obs in request.results() or []:
                cands = obs.topCandidates_(1)
                if cands and len(cands) > 0:
                    lines.append(str(cands[0].string()))

        req = Vision.VNRecognizeTextRequest.alloc().initWithCompletionHandler_(callback)
        req.setRecognitionLanguages_(['ru-RU', 'en-US'])
        req.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
        req.setUsesLanguageCorrection_(True)
        handler.performRequests_error_([req], None)
        return lines
    except Exception as e:
        print(f"[OCR macOS Vision] Error: {e}", file=sys.stderr)
        return []


def _ocr_image_windows(image_path: str) -> list[str]:
    ps_script = f"""
    $ErrorActionPreference = 'Stop'
    try {{
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        [Windows.Media.Ocr.OcrEngine, Windows.Foundation.Diagnostics, ContentType = WindowsRuntime] | Out-Null
        [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation.Diagnostics, ContentType = WindowsRuntime] | Out-Null
        [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null

        $absPath = [System.IO.Path]::GetFullPath('{image_path}')
        $fileTask = [Windows.Storage.StorageFile]::GetFileFromPathAsync($absPath)
        $asTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {{ $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' }}
        $storageFile = $fileTask.GetAwaiter().GetResult()
        
        $stream = $storageFile.OpenAsync([Windows.Storage.FileAccessMode]::Read).GetAwaiter().GetResult()
        $decoder = [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream).GetAwaiter().GetResult()
        $bitmap = $decoder.GetSoftwareBitmapAsync().GetAwaiter().GetResult()

        $lang = [Windows.Globalization.Language]::new('ru-RU')
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang)
        if (-not $engine) {{
            $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
        }}
        $result = $engine.RecognizeAsync($bitmap).GetAwaiter().GetResult()
        foreach ($line in $result.Lines) {{
            [Console]::WriteLine($line.Text)
        }}
    }} catch {{
        # Fallback or error
    }}
    """
    try:
        proc = subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", ps_script],
            capture_output=True,
            text=True,
            check=False,
            timeout=15,
        )
        if proc.stdout:
            return [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    except Exception as e:
        print(f"[OCR Windows Media] Error: {e}", file=sys.stderr)
    return []


def _ocr_image_tesseract(image_path: str) -> list[str]:
    try:
        proc = subprocess.run(
            ["tesseract", image_path, "stdout", "-l", "rus+eng", "--psm", "6"],
            capture_output=True,
            text=True,
            check=False,
            timeout=15,
        )
        if proc.stdout:
            return [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    except Exception:
        pass
    return []


def ocr_image(image_path: str) -> list[str]:
    if sys.platform == "darwin":
        lines = _ocr_image_macos(image_path)
        if lines:
            return lines
    elif sys.platform == "win32":
        lines = _ocr_image_windows(image_path)
        if lines:
            return lines

    # Cross-platform fallback if tesseract exists
    return _ocr_image_tesseract(image_path)


def extract_lines_from_pdf(pdf_path: str) -> list[str]:
    doc = pymupdf.open(pdf_path)
    if len(doc) == 0:
        return []

    first_page = doc[0]
    raw_text = first_page.get_text().strip()
    
    # Check if PDF already contains searchable text
    if raw_text:
        lines = [line.strip() for line in raw_text.splitlines() if line.strip()]
        combined = " ".join(lines)
        if any(kw in combined for kw in ["Между", "ИНН", "Предприятие", "Уведомление", "штраф", "ООО", "ИП"]):
            doc.close()
            return lines

    # Raster PDF scan: render top 65% of the page where headers & company names are
    rect = first_page.rect
    clip_rect = pymupdf.Rect(0, 0, rect.width, rect.height * 0.65)
    pix = first_page.get_pixmap(dpi=200, clip=clip_rect)
    doc.close()

    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp_path = tmp.name
    try:
        pix.save(tmp_path)
        lines = ocr_image(tmp_path)
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

    return lines


def parse_company_info(lines: list[str]) -> dict[str, Any]:
    full_text = " ".join(lines)
    result: dict[str, Any] = {
        "company_name": "",
        "inn": "",
        "ogrn": "",
        "method": "none",
        "confidence": 0.0,
    }

    # Extract INN if present
    m_inn = re.search(r"ИНН\D{0,4}(\d{10}|\d{12})", full_text, re.IGNORECASE)
    if m_inn:
        result["inn"] = m_inn.group(1)

    # Extract OGRN if present
    m_ogrn = re.search(r"ОГРН(?:ИП)?\D{0,4}(\d{13}|\d{15})", full_text, re.IGNORECASE)
    if m_ogrn:
        result["ogrn"] = m_ogrn.group(1)

    # Anchor 1: In notification body: "Между <КОМПАНИЯ> (далее – «Предприятие»)..."
    body_pattern = r"Между\s+([^\n\r\(]+?)\s*\(далее\s*[–—\-]?\s*[«\"']?Предприяти"
    m_body = re.search(body_pattern, full_text, re.IGNORECASE)
    if m_body:
        cand = m_body.group(1).strip()
        cand = re.sub(r'[\s\.\,]+$', '', cand)
        if len(cand) >= 3 and any(cand.startswith(prefix) for prefix in ("ООО", "ИП", "АО", "ПАО", "ЗАО", "Общество")):
            result["company_name"] = cand
            result["method"] = "body"
            result["confidence"] = 0.95
            return result
        elif len(cand) >= 3:
            result["company_name"] = cand
            result["method"] = "body"
            result["confidence"] = 0.85
            return result

    # Anchor 2: Search specific lines starting with legal forms
    for line in lines:
        cleaned = line.strip()
        m_legal = re.match(r"^(?:(?:ООО|ИП|АО|ПАО|ЗАО)\s+[«\"']?[А-ЯЁа-яёA-Za-z0-9\s\.\-–—]+[»\"']?)", cleaned)
        if m_legal:
            cand = m_legal.group(0).strip()
            if "КЛАУДПЭЙМЕНТС" not in cand.upper() and "CLOUDPAYMENTS" not in cand.upper():
                result["company_name"] = cand
                result["method"] = "header"
                result["confidence"] = 0.80
                return result

    # Anchor 3: Check lines right before OGRN / INN in the header
    for i, line in enumerate(lines):
        if re.search(r"ОГРН|ИНН", line, re.IGNORECASE) and i > 0:
            prev_line = lines[i - 1].strip()
            if any(prev_line.startswith(p) for p in ("ООО", "ИП", "АО", "ПАО", "ЗАО")):
                result["company_name"] = prev_line
                result["method"] = "header_pre_inn"
                result["confidence"] = 0.75
                return result

    return result


def _normalize_name_for_match(name: str) -> str:
    s = name.lower()
    for ch in '«»""\'`.,_-()':
        s = s.replace(ch, " ")
    return re.sub(r"\s+", " ", s).strip()


def match_with_candidates(
    extracted_name: str,
    extracted_inn: str,
    candidates: list[str],
) -> Optional[str]:
    if not candidates:
        return None

    norm_extracted = _normalize_name_for_match(extracted_name)

    best_match: Optional[str] = None
    best_score = 0.0

    for cand in candidates:
        norm_cand = _normalize_name_for_match(cand)

        # Exact normalized match
        if norm_extracted and norm_cand == norm_extracted:
            return cand

        # Substring match
        if norm_extracted and len(norm_extracted) >= 5:
            if norm_extracted in norm_cand or norm_cand in norm_extracted:
                score = len(norm_extracted) / max(len(norm_cand), 1)
                if score > best_score:
                    best_score = score
                    best_match = cand

        # Fuzzy string similarity
        if norm_extracted and norm_cand:
            similarity = difflib.SequenceMatcher(None, norm_extracted, norm_cand).ratio()
            if similarity > best_score:
                best_score = similarity
                best_match = cand

    if best_score >= 0.75:
        return best_match

    return None


def get_candidate_names(folder_path: str) -> list[str]:
    candidates: set[str] = set()

    folders_to_check = [folder_path]
    parent = os.path.dirname(os.path.abspath(folder_path))
    if parent and parent != folder_path and os.path.isdir(parent):
        folders_to_check.append(parent)

    for fld in folders_to_check:
        try:
            for item in os.listdir(fld):
                if item.lower().endswith(".docx") and not item.startswith("~$"):
                    stem = os.path.splitext(item)[0]
                    if "шаблон" not in stem.lower() and "реестр" not in stem.lower():
                        candidates.add(stem)
        except Exception:
            continue

    return sorted(list(candidates))


def analyze_scan_folder(
    folder_path: str,
    progress_callback: Optional[Callable[[int, int, str], None]] = None,
) -> list[dict[str, Any]]:
    if not os.path.isdir(folder_path):
        raise FileNotFoundError(f"Папка не найдена: {folder_path}")

    pdf_files = [
        f for f in os.listdir(folder_path)
        if f.lower().endswith(".pdf") and not f.startswith("._") and not f.startswith("~$")
    ]
    pdf_files.sort()

    if not pdf_files:
        return []

    candidates = get_candidate_names(folder_path)
    results: list[dict[str, Any]] = []
    total = len(pdf_files)
    used_proposed: set[str] = set()

    for idx, filename in enumerate(pdf_files):
        pdf_path = os.path.join(folder_path, filename)
        if progress_callback:
            progress_callback(idx + 1, total, filename)

        try:
            lines = extract_lines_from_pdf(pdf_path)
            info = parse_company_info(lines)

            company = info["company_name"]
            inn = info["inn"]

            matched_candidate = match_with_candidates(company, inn, candidates)
            final_company = matched_candidate if matched_candidate else company

            if final_company:
                clean_name = _sanitize_for_filename(final_company)
                proposed_name = f"{clean_name}.pdf"
                status = "matched"
            else:
                proposed_name = filename
                status = "unrecognized"

            if status == "matched":
                base_stem = os.path.splitext(proposed_name)[0]
                dedup_name = proposed_name
                counter = 2
                while dedup_name.lower() in used_proposed:
                    dedup_name = f"{base_stem}_{counter}.pdf"
                    counter += 1
                proposed_name = dedup_name
                used_proposed.add(proposed_name.lower())

            results.append({
                "original_name": filename,
                "original_path": pdf_path,
                "proposed_name": proposed_name,
                "company_name": final_company or "—",
                "inn": inn or "—",
                "method": info["method"],
                "confidence": info["confidence"],
                "status": status,
            })
        except Exception as e:
            results.append({
                "original_name": filename,
                "original_path": pdf_path,
                "proposed_name": filename,
                "company_name": "—",
                "inn": "—",
                "method": "error",
                "confidence": 0.0,
                "status": "error",
                "error": str(e),
            })

    return results


def rename_scans(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rename_results: list[dict[str, Any]] = []

    for item in items:
        orig_path = item.get("original_path", "")
        proposed_name = item.get("proposed_name", "").strip()

        if not orig_path or not os.path.exists(orig_path):
            rename_results.append({
                "original_name": item.get("original_name", ""),
                "new_name": proposed_name,
                "success": False,
                "error": "Файл не найден",
            })
            continue

        folder = os.path.dirname(orig_path)
        new_path = os.path.join(folder, proposed_name)

        if orig_path == new_path:
            rename_results.append({
                "original_name": item.get("original_name", ""),
                "new_name": proposed_name,
                "success": True,
                "skipped": True,
            })
            continue

        try:
            os.rename(orig_path, new_path)
            rename_results.append({
                "original_name": item.get("original_name", ""),
                "new_name": proposed_name,
                "success": True,
            })
        except Exception as e:
            rename_results.append({
                "original_name": item.get("original_name", ""),
                "new_name": proposed_name,
                "success": False,
                "error": str(e),
            })

    return rename_results
