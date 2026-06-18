import datetime
import os
import subprocess
import sys
import threading
from tkinter import filedialog

import customtkinter

import generator

# Premium Dark Theme Color Palette
BG_COLOR = "#0B0F19"       # Deep dark space background
CARD_BG = "#151D30"        # Sleek dark blue card background
INPUT_BG = "#0D1321"       # Deep dark inputs
BORDER_COLOR = "#232D42"   # Border for cards and inputs
BORDER_FOCUS = "#5D5CDE"   # Neon violet focus color
ACCENT = "#5D5CDE"         # Electric Indigo primary
ACCENT_HOVER = "#4B4AC4"   # Darker indigo hover
SUCCESS_COLOR = "#10B981"  # Emerald green
WARNING_COLOR = "#F59E0B"  # Amber orange
ERROR_COLOR = "#EF4444"    # Rose red
TEXT_COLOR = "#F8FAFC"     # Primary text color
MUTED_COLOR = "#94A3B8"    # Secondary text color


class RulesWindow(customtkinter.CTkToplevel):
    def __init__(self, parent, font_family):
        super().__init__(parent)
        self.title("Правила работы и логика генератора")
        self.geometry("540x500")
        self.resizable(False, False)
        self.configure(fg_color=BG_COLOR)
        
        # Keep modal and in front of parent
        self.transient(parent)
        self.grab_set()

        # Center relative to parent
        parent.update_idletasks()
        x = parent.winfo_x() + (parent.winfo_width() - 540) // 2
        y = parent.winfo_y() + (parent.winfo_height() - 500) // 2
        self.geometry(f"540x500+{x}+{y}")

        # Ensure window is lifted and focused
        self.lift()
        self.focus_set()

        # Fonts
        font_header = customtkinter.CTkFont(family=font_family, size=15, weight="bold")
        font_text_bold = customtkinter.CTkFont(family=font_family, size=13, weight="bold")
        font_small = customtkinter.CTkFont(family=font_family, size=12)

        # Title
        lbl_title = customtkinter.CTkLabel(
            self, text="⚙️ Правила работы и логика генератора",
            font=customtkinter.CTkFont(family=font_family, size=16, weight="bold"),
            text_color=ACCENT,
            fg_color=BG_COLOR
        )
        lbl_title.pack(anchor="w", padx=20, pady=(20, 10))

        # Scrollable frame for rules content
        scroll = customtkinter.CTkScrollableFrame(
            self, fg_color=INPUT_BG, border_width=1, border_color=BORDER_COLOR, corner_radius=8
        )
        scroll.pack(fill="both", expand=True, padx=20, pady=(0, 15))
        scroll.grid_columnconfigure(0, weight=1)

        rules = [
            ("📋 Отбор контрагентов", 
             "Программа обрабатывает только те строки из листа «Для соп-я», у которых в колонке «Решение» написано «да» (в любом регистре). Все остальные строки пропускаются."),
            
            ("⚙️ Дополнительные столбцы (ОГРН, Почта, Директор)", 
             "Эти столбцы являются необязательными. Если они есть в Excel, данные переносятся в документ. Если их нет, программа пропустит их без ошибок, вставив в Word-файл редактируемые заглушки."),
            
            ("👤 Склонение имени директора", 
             "Для ИП ФИО автоматически извлекается из названия компании (например, «ИП Иванов Иван Иванович»). Если есть колонка «Директор», имя берется из нее (подходит для ООО и ИП). В обоих случаях ФИО склоняется в дательный падеж (кому: Иванову Ивану Ивановичу)."),
            
            ("✏️ Свободное редактирование", 
             "Все созданные файлы Word автоматически очищаются от парольной защиты. Вы можете свободно открывать их и редактировать любые данные, ОГРН, почту или подписи."),
            
            ("✍️ Подпись представителя", 
             "Внизу каждого документа подставляется подпись указанного в программе уполномоченного представителя (по умолчанию — Жаворонкина А.М.).")
        ]

        for i, (rule_title, rule_body) in enumerate(rules):
            card = customtkinter.CTkFrame(
                scroll, fg_color=CARD_BG, border_width=1, border_color=BORDER_COLOR, corner_radius=8
            )
            card.grid(row=i, column=0, sticky="ew", padx=5, pady=6)
            
            # Using solid fg_color on labels to activate ClearType and prevent shadowing/ghosting on scroll
            lbl_r_title = customtkinter.CTkLabel(
                card, text=rule_title, font=font_text_bold, text_color=ACCENT, fg_color=CARD_BG
            )
            lbl_r_title.pack(anchor="w", padx=12, pady=(10, 4))
            
            lbl_r_body = customtkinter.CTkLabel(
                card, text=rule_body, font=font_small, text_color=TEXT_COLOR, fg_color=CARD_BG,
                justify="left", wraplength=380
            )
            lbl_r_body.pack(anchor="w", padx=12, pady=(0, 10))

        # Close button
        close_btn = customtkinter.CTkButton(
            self, text="Понятно", font=font_text_bold, height=38,
            fg_color=ACCENT, hover_color=ACCENT_HOVER, text_color="#FFFFFF",
            corner_radius=8, command=self.destroy
        )
        close_btn.pack(fill="x", padx=20, pady=(0, 20))


class App(customtkinter.CTk):
    def __init__(self):
        super().__init__()

        customtkinter.set_appearance_mode("dark")
        self.configure(fg_color=BG_COLOR)

        self.title("Штрафинатор 2000")
        self.geometry("800x600")
        self.resizable(False, False)

        # 1. Download and load Google Font (Montserrat) dynamically
        self.font_family = "Arial"  # default fallback
        self._load_fonts()

        # 2. Configure font styles (slightly increased for crispness and readability)
        self.font_title = customtkinter.CTkFont(family=self.font_family, size=24, weight="bold")
        self.font_subtitle = customtkinter.CTkFont(family=self.font_family, size=13)
        self.font_header = customtkinter.CTkFont(family=self.font_family, size=14, weight="bold")
        self.font_text = customtkinter.CTkFont(family=self.font_family, size=13)
        self.font_text_bold = customtkinter.CTkFont(family=self.font_family, size=13, weight="bold")
        self.font_small = customtkinter.CTkFont(family=self.font_family, size=12)
        self.font_small_bold = customtkinter.CTkFont(family=self.font_family, size=12, weight="bold")

        self._output_dir: str = ""
        self._building = False

        self._build_ui()

    def _load_fonts(self):
        font_dir = os.path.join(os.getcwd(), "fonts")
        os.makedirs(font_dir, exist_ok=True)

        reg_path = os.path.join(font_dir, "Montserrat-Regular.ttf")
        bold_path = os.path.join(font_dir, "Montserrat-Bold.ttf")

        try:
            if not os.path.exists(reg_path) or not os.path.exists(bold_path):
                import fonts_data
                if not os.path.exists(reg_path):
                    with open(reg_path, "wb") as f:
                        f.write(fonts_data.get_regular_bytes())
                if not os.path.exists(bold_path):
                    with open(bold_path, "wb") as f:
                        f.write(fonts_data.get_bold_bytes())
                
            if sys.platform == "win32":
                import ctypes
                FR_PRIVATE = 0x10
                gdi32 = ctypes.WinDLL('gdi32')
                r1 = gdi32.AddFontResourceExW(reg_path, FR_PRIVATE, 0)
                r2 = gdi32.AddFontResourceExW(bold_path, FR_PRIVATE, 0)
                if r1 and r2:
                    self.font_family = "Montserrat"
                else:
                    self.font_family = "Arial"
            else:
                self.font_family = "Arial"
        except Exception:
            self.font_family = "Arial"

    def _build_ui(self):
        # Configure layout weights
        self.grid_columnconfigure(0, weight=1, minsize=370)
        self.grid_columnconfigure(1, weight=1, minsize=390)
        self.grid_rowconfigure(1, weight=1)

        # --- HEADER (Row 0, spans columns 0 and 1) ---
        header_frame = customtkinter.CTkFrame(self, fg_color="transparent")
        header_frame.grid(row=0, column=0, columnspan=2, sticky="ew", padx=25, pady=(20, 15))
        
        # Solid background on title to enable ClearType subpixel rendering
        title_label = customtkinter.CTkLabel(
            header_frame, text="ШТРАФИНАТОР 2000",
            font=self.font_title,
            text_color=ACCENT,
            fg_color=BG_COLOR
        )
        title_label.pack(anchor="w")

        subtitle_label = customtkinter.CTkLabel(
            header_frame, text="Автоматическая генерация уведомлений об удержании штрафов",
            font=self.font_subtitle,
            text_color=MUTED_COLOR,
            fg_color=BG_COLOR
        )
        subtitle_label.pack(anchor="w", pady=(2, 0))

        # Underline accent bar
        underline = customtkinter.CTkFrame(header_frame, height=2, fg_color=BORDER_COLOR)
        underline.pack(fill="x", pady=(10, 0))

        # --- LEFT PANEL: Parameters & Inputs (Column 0, Row 1) ---
        left_card = customtkinter.CTkFrame(
            self, fg_color=CARD_BG, border_width=1, border_color=BORDER_COLOR, corner_radius=12
        )
        left_card.grid(row=1, column=0, sticky="nsew", padx=(25, 10), pady=(0, 25))

        # 1. Excel input section
        excel_label = customtkinter.CTkLabel(
            left_card, text="Excel-реестр штрафов (.xlsx)",
            font=self.font_header,
            text_color=TEXT_COLOR,
            fg_color=CARD_BG
        )
        excel_label.pack(anchor="w", padx=18, pady=(18, 5))

        excel_sub_frame = customtkinter.CTkFrame(left_card, fg_color="transparent")
        excel_sub_frame.pack(fill="x", padx=18, pady=(0, 15))

        self.excel_entry = customtkinter.CTkEntry(
            excel_sub_frame, placeholder_text="Выберите файл реестра...",
            fg_color=INPUT_BG, border_color=BORDER_COLOR, text_color=TEXT_COLOR,
            placeholder_text_color=MUTED_COLOR, height=36, corner_radius=8,
            state="readonly", font=self.font_text
        )
        self.excel_entry.pack(side="left", fill="x", expand=True, padx=(0, 8))

        excel_btn = customtkinter.CTkButton(
            excel_sub_frame, text="Обзор", width=75, height=36,
            fg_color=ACCENT, hover_color=ACCENT_HOVER, text_color="#FFFFFF",
            font=self.font_text_bold, corner_radius=8,
            command=self._pick_excel
        )
        excel_btn.pack(side="right")

        # 2. Output folder section
        out_label = customtkinter.CTkLabel(
            left_card, text="Папка для сохранения документов",
            font=self.font_header,
            text_color=TEXT_COLOR,
            fg_color=CARD_BG
        )
        out_label.pack(anchor="w", padx=18, pady=(5, 5))

        out_sub_frame = customtkinter.CTkFrame(left_card, fg_color="transparent")
        out_sub_frame.pack(fill="x", padx=18, pady=(0, 15))

        self.out_entry = customtkinter.CTkEntry(
            out_sub_frame, placeholder_text="Выберите папку...",
            fg_color=INPUT_BG, border_color=BORDER_COLOR, text_color=TEXT_COLOR,
            placeholder_text_color=MUTED_COLOR, height=36, corner_radius=8,
            state="readonly", font=self.font_text
        )
        self.out_entry.pack(side="left", fill="x", expand=True, padx=(0, 8))

        out_btn = customtkinter.CTkButton(
            out_sub_frame, text="Обзор", width=75, height=36,
            fg_color=ACCENT, hover_color=ACCENT_HOVER, text_color="#FFFFFF",
            font=self.font_text_bold, corner_radius=8,
            command=self._pick_output
        )
        out_btn.pack(side="right")

        # 3. Date picker section
        date_label = customtkinter.CTkLabel(
            left_card, text="Дата уведомления",
            font=self.font_header,
            text_color=TEXT_COLOR,
            fg_color=CARD_BG
        )
        date_label.pack(anchor="w", padx=18, pady=(5, 5))

        date_sub_frame = customtkinter.CTkFrame(left_card, fg_color="transparent")
        date_sub_frame.pack(fill="x", padx=18, pady=(0, 20))

        today = datetime.date.today()
        self.day_var = customtkinter.StringVar(value=str(today.day).zfill(2))
        self.month_var = customtkinter.StringVar(value=str(today.month).zfill(2))
        self.year_var = customtkinter.StringVar(value=str(today.year))

        day_vals = [str(d).zfill(2) for d in range(1, 32)]
        month_vals = [str(m).zfill(2) for m in range(1, 13)]
        year_vals = [str(y) for y in range(2020, 2031)]

        self.day_menu = customtkinter.CTkOptionMenu(
            date_sub_frame, values=day_vals, variable=self.day_var,
            width=70, height=36, fg_color=INPUT_BG, button_color=ACCENT,
            button_hover_color=ACCENT_HOVER, dropdown_fg_color=CARD_BG,
            dropdown_text_color=TEXT_COLOR, dropdown_hover_color=ACCENT_HOVER,
            corner_radius=8, font=self.font_text
        )
        self.day_menu.pack(side="left", padx=(0, 4))

        sep1 = customtkinter.CTkLabel(
            date_sub_frame, text=".",
            font=customtkinter.CTkFont(family=self.font_family, size=16, weight="bold"),
            text_color=MUTED_COLOR,
            fg_color=CARD_BG
        )
        sep1.pack(side="left", padx=2)

        self.month_menu = customtkinter.CTkOptionMenu(
            date_sub_frame, values=month_vals, variable=self.month_var,
            width=70, height=36, fg_color=INPUT_BG, button_color=ACCENT,
            button_hover_color=ACCENT_HOVER, dropdown_fg_color=CARD_BG,
            dropdown_text_color=TEXT_COLOR, dropdown_hover_color=ACCENT_HOVER,
            corner_radius=8, font=self.font_text
        )
        self.month_menu.pack(side="left", padx=(4, 4))

        sep2 = customtkinter.CTkLabel(
            date_sub_frame, text=".",
            font=customtkinter.CTkFont(family=self.font_family, size=16, weight="bold"),
            text_color=MUTED_COLOR,
            fg_color=CARD_BG
        )
        sep2.pack(side="left", padx=2)

        self.year_menu = customtkinter.CTkOptionMenu(
            date_sub_frame, values=year_vals, variable=self.year_var,
            width=90, height=36, fg_color=INPUT_BG, button_color=ACCENT,
            button_hover_color=ACCENT_HOVER, dropdown_fg_color=CARD_BG,
            dropdown_text_color=TEXT_COLOR, dropdown_hover_color=ACCENT_HOVER,
            corner_radius=8, font=self.font_text
        )
        self.year_menu.pack(side="left", padx=(4, 0))

        # 4. Signatory section
        signatory_label = customtkinter.CTkLabel(
            left_card, text="Подписант (ФИО)",
            font=self.font_header,
            text_color=TEXT_COLOR,
            fg_color=CARD_BG
        )
        signatory_label.pack(anchor="w", padx=18, pady=(5, 5))

        self.signatory_entry = customtkinter.CTkEntry(
            left_card, placeholder_text="ФИО подписанта...",
            fg_color=INPUT_BG, border_color=BORDER_COLOR, text_color=TEXT_COLOR,
            placeholder_text_color=MUTED_COLOR, height=36, corner_radius=8,
            font=self.font_text
        )
        self.signatory_entry.pack(fill="x", padx=18, pady=(0, 15))
        self.signatory_entry.insert(0, "Жаворонкина А.М.")

        # Interactive Rules Button packed right below the signatory input
        rules_btn = customtkinter.CTkButton(
            left_card, text="⚙️  Правила работы и логика",
            font=self.font_text_bold, height=40,
            fg_color=INPUT_BG, border_color=BORDER_COLOR, border_width=1,
            hover_color=CARD_BG, text_color=TEXT_COLOR,
            corner_radius=10,
            command=self._open_rules_modal
        )
        rules_btn.pack(fill="x", padx=18, pady=(25, 20))

        # --- RIGHT PANEL: Action & Results (Column 1, Row 1) ---
        right_panel_frame = customtkinter.CTkFrame(self, fg_color="transparent")
        right_panel_frame.grid(row=1, column=1, sticky="nsew", padx=(10, 25), pady=(0, 25))
        right_panel_frame.grid_columnconfigure(0, weight=1)
        right_panel_frame.grid_rowconfigure(1, weight=1)

        # Top Card: Launch & Progress
        launch_card = customtkinter.CTkFrame(
            right_panel_frame, fg_color=CARD_BG, border_width=1, border_color=BORDER_COLOR, corner_radius=12
        )
        launch_card.grid(row=0, column=0, sticky="ew", pady=(0, 15))

        self.gen_btn = customtkinter.CTkButton(
            launch_card, text="Сгенерировать уведомления",
            font=customtkinter.CTkFont(family=self.font_family, size=14, weight="bold"),
            height=44, fg_color=ACCENT, hover_color=ACCENT_HOVER, text_color="#FFFFFF",
            corner_radius=8,
            command=self._on_generate,
        )
        self.gen_btn.pack(fill="x", padx=18, pady=(18, 12))

        self.progress = customtkinter.CTkProgressBar(
            launch_card, height=8, progress_color=ACCENT, fg_color=INPUT_BG, corner_radius=4
        )
        self.progress.pack(fill="x", padx=18, pady=(0, 8))
        self.progress.set(0)

        self.status_label = customtkinter.CTkLabel(
            launch_card, text="Готов к работе",
            font=self.font_text_bold,
            text_color=MUTED_COLOR,
            fg_color=CARD_BG
        )
        self.status_label.pack(anchor="w", padx=18, pady=(0, 14))

        # Bottom Card: Scrollable Results
        results_card = customtkinter.CTkFrame(
            right_panel_frame, fg_color=CARD_BG, border_width=1, border_color=BORDER_COLOR, corner_radius=12
        )
        results_card.grid(row=1, column=0, sticky="nsew")
        results_card.grid_columnconfigure(0, weight=1)
        results_card.grid_rowconfigure(1, weight=1)

        results_header = customtkinter.CTkFrame(results_card, fg_color="transparent")
        results_header.grid(row=0, column=0, sticky="ew", padx=18, pady=(14, 8))

        results_title = customtkinter.CTkLabel(
            results_header, text="Результаты обработки",
            font=self.font_header,
            text_color=TEXT_COLOR,
            fg_color=CARD_BG
        )
        results_title.pack(side="left")

        self.open_folder_btn = customtkinter.CTkButton(
            results_header, text="📁 Открыть папку", width=120, height=28,
            fg_color=ACCENT, hover_color=ACCENT_HOVER, text_color="#FFFFFF",
            font=self.font_small_bold, corner_radius=6,
            command=self._open_output_folder,
        )
        self.open_folder_btn.pack(side="right")
        self.open_folder_btn.pack_forget()

        self.results_frame = customtkinter.CTkScrollableFrame(
            results_card, fg_color=INPUT_BG, border_width=1, border_color=BORDER_COLOR, corner_radius=8
        )
        self.results_frame.grid(row=1, column=0, sticky="nsew", padx=18, pady=(0, 18))
        self.results_frame.grid_columnconfigure(0, weight=1)

    def _open_rules_modal(self):
        RulesWindow(self, self.font_family)

    def _pick_excel(self):
        path = filedialog.askopenfilename(
            title="Выберите Excel-файл",
            filetypes=[("Excel", "*.xlsx"), ("Все файлы", "*.*")],
        )
        if path:
            self.excel_entry.configure(state="normal")
            self.excel_entry.delete(0, "end")
            self.excel_entry.insert(0, path)
            self.excel_entry.configure(state="readonly")

    def _pick_output(self):
        path = filedialog.askdirectory(title="Выберите папку для сохранения")
        if path:
            self._output_dir = path
            self.out_entry.configure(state="normal")
            self.out_entry.delete(0, "end")
            self.out_entry.insert(0, path)
            self.out_entry.configure(state="readonly")

    def _get_date(self) -> datetime.datetime:
        d = int(self.day_var.get())
        m = int(self.month_var.get())
        y = int(self.year_var.get())
        return datetime.datetime(y, m, d)

    def _clear_results(self):
        for w in self.results_frame.winfo_children():
            w.destroy()
        self.open_folder_btn.pack_forget()
        self.status_label.configure(text="")
        self.progress.set(0)

    def _on_generate(self):
        if self._building:
            return

        excel_path = self.excel_entry.get()
        output_dir = self._output_dir

        if not excel_path:
            self.status_label.configure(text="⚠ Выберите Excel-файл", text_color=WARNING_COLOR)
            return
        if not output_dir:
            self.status_label.configure(text="⚠ Выберите папку для сохранения", text_color=WARNING_COLOR)
            return

        try:
            self._get_date()
        except ValueError:
            self.status_label.configure(text="⚠ Некорректная дата", text_color=WARNING_COLOR)
            return

        self._building = True
        self._clear_results()
        self.gen_btn.configure(state="disabled")
        self.status_label.configure(text="Генерация файлов...", text_color=MUTED_COLOR)

        thread = threading.Thread(target=self._worker, daemon=True)
        thread.start()

    def _worker(self):
        try:
            excel_path = self.excel_entry.get()
            letter_date = self._get_date()
            signatory = self.signatory_entry.get().strip() or "Жаворонкина А.М."

            results = generator.generate_all(
                excel_path,
                self._output_dir,
                letter_date,
                signatory=signatory,
                progress_callback=self._on_progress,
            )
            self.after(0, lambda: self._on_complete(results))
        except Exception as e:
            self.after(0, lambda: self._on_error(str(e)))

    def _on_progress(self, current: int, total: int):
        self.after(0, lambda: self.progress.set(current / total))

    def _on_complete(self, results: list[generator.GenerationResult]):
        self._building = False
        self.gen_btn.configure(state="normal")
        self.progress.set(1.0)

        success_count = sum(1 for r in results if r.success)
        warn_count = sum(1 for r in results if r.success and r.warnings)
        error_count = sum(1 for r in results if not r.success)

        for r in results:
            if r.success:
                line1 = customtkinter.CTkLabel(
                    self.results_frame,
                    text=f"✅  {r.filename}",
                    font=self.font_text_bold,
                    text_color="#E2E8F0",
                    anchor="w",
                    fg_color=INPUT_BG
                )
                line1.grid(sticky="w", padx=8, pady=(6, 0))

                if r.warnings:
                    warn_text = " · ".join(r.warnings)
                    line2 = customtkinter.CTkLabel(
                        self.results_frame,
                        text=f"      ⚠ {warn_text}",
                        font=self.font_small,
                        text_color=WARNING_COLOR,
                        anchor="w",
                        fg_color=INPUT_BG,
                        justify="left",
                        wraplength=340
                    )
                    line2.grid(sticky="w", padx=8, pady=(0, 4))
            else:
                line1 = customtkinter.CTkLabel(
                    self.results_frame,
                    text=f"❌  {r.filename}",
                    font=self.font_text_bold,
                    text_color=ERROR_COLOR,
                    anchor="w",
                    fg_color=INPUT_BG
                )
                line1.grid(sticky="w", padx=8, pady=(6, 0))
                
                line2 = customtkinter.CTkLabel(
                    self.results_frame,
                    text=f"      Ошибка: {r.error}",
                    font=self.font_small,
                    text_color=ERROR_COLOR,
                    anchor="w",
                    fg_color=INPUT_BG,
                    justify="left",
                    wraplength=340
                )
                line2.grid(sticky="w", padx=8, pady=(0, 4))

        self.status_label.configure(
            text=f"Обработано: {len(results)}  •  С ошибками: {error_count}",
            text_color=SUCCESS_COLOR if error_count == 0 else WARNING_COLOR,
        )
        self.open_folder_btn.pack(side="right")

        # Config layout again
        right_panel_frame = self.grid_slaves(row=1, column=1)[0]
        results_card = right_panel_frame.grid_slaves(row=1, column=0)[0]
        results_card.grid(row=1, column=0, sticky="nsew")

    def _on_error(self, msg: str):
        self._building = False
        self.gen_btn.configure(state="normal")
        self.progress.set(0)
        self.status_label.configure(text=f"❌ {msg}", text_color=ERROR_COLOR)

    def _open_output_folder(self):
        if not self._output_dir:
            return
        if sys.platform == "win32":
            os.startfile(self._output_dir)
        elif sys.platform == "darwin":
            subprocess.Popen(["open", self._output_dir])
        else:
            subprocess.Popen(["xdg-open", self._output_dir])
