import datetime
import json
import os
import subprocess
import sys
from typing import Any, Optional

import webview

import generator

RULES = [
    {
        "title": "Отбор контрагентов",
        "body": "Программа обрабатывает только те строки из листа «Для соп-я», у которых в колонке «Решение» написано «да» (в любом регистре). Все остальные строки пропускаются.",
    },
    {
        "title": "Дополнительные столбцы (ОГРН, Почта, Директор)",
        "body": "Эти столбцы являются необязательными. Если они есть в Excel, данные переносятся. Если их нет, программа пропустит их без ошибок, вставив в Word-файл редактируемые заглушки.",
    },
    {
        "title": "Склонение имени директора",
        "body": "Для ИП ФИО автоматически извлекается из названия компании («ИП Иванов Иван Иванович»). Если есть колонка «Директор», имя берется из нее. ФИО склоняется в дательный падеж (кому: Иванову Ивану Ивановичу).",
    },
    {
        "title": "Свободное редактирование (Word)",
        "body": "Все созданные файлы Word автоматически очищаются от парольной защиты. Вы можете свободно открывать их и редактировать любые данные, ОГРН, почту или подписи.",
    },
    {
        "title": "Подпись представителя",
        "body": "Внизу каждого документа подставляется подпись указанного в программе уполномоченного представителя.",
    },
]


class AppApi:
    def __init__(self) -> None:
        self._window: Optional[webview.Window] = None

    def set_window(self, window: webview.Window) -> None:
        self._window = window

    def select_excel_file(self) -> Optional[str]:
        if not self._window:
            return None
        file_types = ("Excel Files (*.xlsx)", "All files (*.*)")
        result = self._window.create_file_dialog(
            webview.OPEN_DIALOG,
            allow_multiple=False,
            file_types=file_types,
        )
        if result and len(result) > 0:
            return str(result[0])
        return None

    def select_output_dir(self) -> Optional[str]:
        if not self._window:
            return None
        result = self._window.create_file_dialog(webview.FOLDER_DIALOG)
        if result and len(result) > 0:
            return str(result[0])
        return None

    def inspect_excel(self, path: str) -> dict[str, Any]:
        return generator.inspect_excel(path)

    def start_generation(
        self,
        excel_path: str,
        output_dir: str,
        letter_date_iso: str,
        signatory: str = "",
    ) -> list[dict[str, Any]]:
        # Parse ISO date (YYYY-MM-DD)
        if not letter_date_iso:
            letter_date = datetime.datetime.now()
        else:
            try:
                d = datetime.date.fromisoformat(letter_date_iso)
                letter_date = datetime.datetime(d.year, d.month, d.day)
            except Exception:
                letter_date = datetime.datetime.now()

        def progress_callback(current: int, total: int) -> None:
            if self._window:
                payload = json.dumps({"current": current, "total": total})
                self._window.evaluate_js(
                    f"window.dispatchEvent(new CustomEvent('pywebview-progress', {{ detail: {payload} }}))"
                )

        results = generator.generate_all(
            excel_path=excel_path,
            output_dir=output_dir,
            letter_date=letter_date,
            signatory=signatory.strip(),
            progress_callback=progress_callback,
        )

        return [
            {
                "filename": r.filename,
                "success": r.success,
                "warnings": r.warnings,
                "error": r.error,
            }
            for r in results
        ]

    def open_path(self, path: str) -> bool:
        if not path or not os.path.exists(path):
            return False
        try:
            if sys.platform == "win32":
                os.startfile(path)
            elif sys.platform == "darwin":
                subprocess.Popen(["open", path])
            else:
                subprocess.Popen(["xdg-open", path])
            return True
        except Exception:
            return False

    def get_rules(self) -> list[dict[str, str]]:
        return RULES


def get_html_path() -> str:
    # 1. If running as compiled PyInstaller bundle
    if getattr(sys, "_frozen", False):
        base_dir = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
        bundle_html = os.path.join(base_dir, "frontend", "dist", "index.html")
        if os.path.exists(bundle_html):
            return bundle_html

    # 2. Check local built frontend dist
    current_dir = os.path.dirname(os.path.abspath(__file__))
    dist_html = os.path.join(current_dir, "frontend", "dist", "index.html")
    if os.path.exists(dist_html):
        return dist_html

    # 3. Fallback dev server if running Vite in dev mode
    return "http://localhost:5173"


def main(debug: bool = False) -> None:
    api = AppApi()
    html_url = get_html_path()

    window = webview.create_window(
        title="Штрафинатор 2000",
        url=html_url,
        js_api=api,
        width=1080,
        height=720,
        min_size=(960, 640),
        text_select=False,
    )
    api.set_window(window)
    webview.start(debug=debug)


if __name__ == "__main__":
    main(debug="--debug" in sys.argv)
