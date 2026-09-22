import os
import tempfile
import pymupdf
import pytest

import scanner


def test_sanitize_for_filename():
    assert scanner._sanitize_for_filename('ООО "Ромашка"') == "ООО Ромашка"
    assert scanner._sanitize_for_filename('ИП «Иванов И.И.»') == "ИП Иванов И.И."
    assert scanner._sanitize_for_filename('ООО/Финанс:2026*') == "ООО_Финанс_2026"
    assert scanner._sanitize_for_filename('  ООО   Вектор   ') == "ООО Вектор"


def test_parse_company_info_body_anchor():
    lines = [
        "Исх. № 100 от 01.09.2026г.",
        "Уведомление об удержании штрафа",
        "Между ООО «Ромашка Финанс» (далее – «Предприятие») и ООО «КЛАУДПЭЙМЕНТС» (далее – «Агрегатор»)",
        "заключены Условия осуществления расчетов...",
    ]
    info = scanner.parse_company_info(lines)
    assert info["company_name"] == "ООО «Ромашка Финанс»"
    assert info["method"] == "body"
    assert info["confidence"] >= 0.85


def test_parse_company_info_header_anchor():
    lines = [
        "Исх. № 100",
        "Генеральному директору",
        "ООО «Северный Альянс»",
        "ОГРН 1157746123456",
        "ИНН 7701234567",
        "Уведомление об удержании штрафа",
    ]
    info = scanner.parse_company_info(lines)
    assert info["company_name"] == "ООО «Северный Альянс»"
    assert info["inn"] == "7701234567"
    assert info["ogrn"] == "1157746123456"
    assert info["method"] in ("header", "header_pre_inn")


def test_match_with_candidates():
    candidates = ["ООО «Ромашка Финанс»", "ИП Смирнов А. В.", "ООО Вектор"]
    
    # Exact / normalized match
    match = scanner.match_with_candidates("ООО Ромашка Финанс", "7701234567", candidates)
    assert match == "ООО «Ромашка Финанс»"

    # OCR typo corrected by fuzzy match
    match_typo = scanner.match_with_candidates("ООО Ромашкз Финанс", "", candidates)
    assert match_typo == "ООО «Ромашка Финанс»"

    # No match
    no_match = scanner.match_with_candidates("ЗАО Неизвестная Компания", "", candidates)
    assert no_match is None


def test_analyze_and_rename_scans():
    with tempfile.TemporaryDirectory() as tmpdir:
        # Create a parent folder with a docx to act as candidate
        docx_path = os.path.join(tmpdir, "ООО Альфа Трейд.docx")
        with open(docx_path, "wb") as f:
            f.write(b"dummy docx")

        # Create a subfolder "scans"
        scans_dir = os.path.join(tmpdir, "scans")
        os.makedirs(scans_dir)

        # Create a simulated searchable PDF in scans_dir
        pdf_path = os.path.join(scans_dir, "SKM_C25822092212000.pdf")
        doc = pymupdf.open()
        page = doc.new_page(width=595, height=842)
        font_path = "/System/Library/Fonts/Supplemental/Arial.ttf" if os.path.exists("/System/Library/Fonts/Supplemental/Arial.ttf") else None
        
        sample_text = (
            "Уведомление об удержании штрафа\n"
            "ИНН 7701999888\n"
            "Между ООО Альфа Трейд (далее – «Предприятие») и ООО «КЛАУДПЭЙМЕНТС»\n"
        )
        if font_path:
            page.insert_font(fontname="f0", fontfile=font_path)
            page.insert_textbox(pymupdf.Rect(50, 50, 500, 300), sample_text, fontname="f0", fontsize=12)
        else:
            page.insert_textbox(pymupdf.Rect(50, 50, 500, 300), sample_text, fontsize=12)
        doc.save(pdf_path)
        doc.close()

        # Run analyze_scan_folder
        results = scanner.analyze_scan_folder(scans_dir)
        assert len(results) == 1
        item = results[0]
        assert item["status"] == "matched"
        assert "Альфа Трейд" in item["company_name"]
        assert item["proposed_name"] == "ООО Альфа Трейд.pdf"

        # Apply rename
        rename_results = scanner.rename_scans([item])
        assert len(rename_results) == 1
        assert rename_results[0]["success"] is True

        # Verify old file is gone and new file exists
        assert not os.path.exists(pdf_path)
        assert os.path.exists(os.path.join(scans_dir, "ООО Альфа Трейд.pdf"))
