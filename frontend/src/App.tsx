import { useState, useEffect } from 'react';
import {
  FileSpreadsheet,
  FolderOpen,
  Calendar,
  UserCheck,
  Play,
  CheckCircle2,
  AlertTriangle,
  XCircle,
  FileText,
  HelpCircle,
  ExternalLink,
  ShieldCheck,
  RefreshCw,
  ChevronDown,
  ChevronRight,
  X
} from 'lucide-react';

import type { PreflightInspection, GenerationItemResult, RuleItem } from './types/pywebview';

// Fallback Mock API when opened in browser directly
const mockApi = {
  select_excel_file: async () => "/Users/cloud/Documents/Реестр_Штрафов_2026.xlsx",
  select_output_dir: async () => "/Users/cloud/Documents/Готовые_Уведомления",
  inspect_excel: async (_path: string): Promise<PreflightInspection> => ({
    sheet_name: "Для соп-я",
    total_rows: 154,
    valid_rows_count: 42,
    total_fine_sum: 4120000,
    columns_found: ["period", "inn", "yl", "fraud_rub", "fine", "decision", "fraud_pct", "director", "ogrn", "email"],
    has_optional_columns: { director: true, ogrn: true, email: true },
    sample_records: [
      { yl: "ООО Ритейл Групп", inn: "7701234567", fine: 150000, director: "Иванов Иван Иванович" },
      { yl: "ИП Смирнов А. В.", inn: "502409876543", fine: 45000, director: "Смирнов Алексей Викторович" },
      { yl: "ООО Вектор Финанс", inn: "7812987654", fine: 210000, director: "—" },
    ]
  }),
  start_generation: async () => [
    { filename: "ООО Ритейл Групп.docx", success: true, warnings: [] },
    { filename: "ИП Смирнов А. В..docx", success: true, warnings: ["Email не указан — оставлена редактируемая заглушка"] },
    { filename: "ООО Вектор Финанс.docx", success: true, warnings: ["Руководитель не указан — оставлена заглушка"] },
  ],
  open_path: async () => true,
  get_rules: async (): Promise<RuleItem[]> => [
    { title: "Отбор контрагентов", body: "Программа обрабатывает только те строки из листа «Для соп-я», у которых в колонке «Решение» написано «да» (в любом регистре). Все остальные строки пропускаются." },
    { title: "Дополнительные столбцы (ОГРН, Почта, Директор)", body: "Эти столбцы являются необязательными. Если они есть в Excel, данные переносятся. Если их нет, программа пропустит их без ошибок, вставив в Word-файл редактируемые заглушки." },
    { title: "Склонение имени директора", body: "Для ИП ФИО автоматически извлекается из названия компании («ИП Иванов Иван Иванович»). Если есть колонка «Директор», имя берется из нее. ФИО склоняется в дательный падеж (кому: Иванову Ивану Ивановичу)." },
    { title: "Свободное редактирование (Word)", body: "Все созданные файлы Word автоматически очищаются от парольной защиты. Вы можете свободно открывать их и редактировать любые данные, ОГРН, почту или подписи." },
    { title: "Подпись представителя", body: "Внизу каждого документа подставляется подпись указанного в программе уполномоченного представителя." }
  ]
};

const getApi = () => {
  if (typeof window !== 'undefined' && window.pywebview && window.pywebview.api) {
    return window.pywebview.api;
  }
  return mockApi;
};

export default function App() {
  const [excelPath, setExcelPath] = useState<string>('');
  const [outputDir, setOutputDir] = useState<string>('');
  const [signatory, setSignatory] = useState<string>('');
  
  const todayStr = new Date().toISOString().split('T')[0];
  const [letterDate, setLetterDate] = useState<string>(todayStr);

  const [inspecting, setInspecting] = useState<boolean>(false);
  const [inspection, setInspection] = useState<PreflightInspection | null>(null);
  const [inspectError, setInspectError] = useState<string | null>(null);

  const [isGenerating, setIsGenerating] = useState<boolean>(false);
  const [progress, setProgress] = useState<{ current: number; total: number }>({ current: 0, total: 0 });
  const [statusMessage, setStatusMessage] = useState<string>('Готов к работе');
  const [results, setResults] = useState<GenerationItemResult[]>([]);
  const [filterTab, setFilterTab] = useState<'all' | 'success' | 'warn' | 'error'>('all');

  const [rulesOpen, setRulesOpen] = useState<boolean>(false);
  const [rulesList, setRulesList] = useState<RuleItem[]>([]);
  const [showSamples, setShowSamples] = useState<boolean>(false);

  useEffect(() => {
    const handleProgress = (event: any) => {
      const detail = event.detail || event;
      if (detail && typeof detail.current === 'number') {
        setProgress({ current: detail.current, total: detail.total });
        setStatusMessage(`Формирование документов: ${detail.current} из ${detail.total}...`);
      }
    };

    window.addEventListener('pywebview-progress', handleProgress);
    return () => window.removeEventListener('pywebview-progress', handleProgress);
  }, []);

  useEffect(() => {
    getApi().get_rules().then(rules => {
      if (rules && rules.length > 0) {
        setRulesList(rules);
      }
    }).catch(console.error);
  }, []);

  const runInspection = async (path: string) => {
    if (!path) {
      setInspection(null);
      setInspectError(null);
      return;
    }

    setInspecting(true);
    setInspectError(null);

    try {
      const data = await getApi().inspect_excel(path);
      setInspection(data);
      if (data.valid_rows_count > 0) {
        setProgress({ current: 0, total: data.valid_rows_count });
      }
    } catch (err: any) {
      setInspection(null);
      setInspectError(err?.message || String(err));
    } finally {
      setInspecting(false);
    }
  };

  const handleSelectExcel = async () => {
    try {
      const path = await getApi().select_excel_file();
      if (path) {
        setExcelPath(path);
        if (!outputDir) {
          const lastSlash = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
          if (lastSlash > 0) {
            setOutputDir(path.substring(0, lastSlash));
          }
        }
        await runInspection(path);
      }
    } catch (e) {
      console.error(e);
    }
  };

  const handleSelectOutputDir = async () => {
    try {
      const dir = await getApi().select_output_dir();
      if (dir) {
        setOutputDir(dir);
      }
    } catch (e) {
      console.error(e);
    }
  };

  const handleSetSameDir = () => {
    if (!excelPath) return;
    const lastSlash = Math.max(excelPath.lastIndexOf('/'), excelPath.lastIndexOf('\\'));
    if (lastSlash > 0) {
      setOutputDir(excelPath.substring(0, lastSlash));
    }
  };

  const handleQuickDatePreset = (preset: 'today' | 'end_month' | 'yesterday') => {
    const now = new Date();
    if (preset === 'today') {
      setLetterDate(now.toISOString().split('T')[0]);
    } else if (preset === 'yesterday') {
      const d = new Date(now);
      d.setDate(d.getDate() - 1);
      setLetterDate(d.toISOString().split('T')[0]);
    } else if (preset === 'end_month') {
      const d = new Date(now.getFullYear(), now.getMonth() + 1, 0);
      setLetterDate(d.toISOString().split('T')[0]);
    }
  };

  const handleGenerate = async () => {
    if (!excelPath) {
      setStatusMessage('Ошибка: укажите Excel-файл реестра');
      return;
    }
    if (!outputDir) {
      setStatusMessage('Ошибка: выберите папку для сохранения');
      return;
    }

    setIsGenerating(true);
    setResults([]);
    setStatusMessage('Инициализация процесса генерации...');
    setProgress({ current: 0, total: inspection?.valid_rows_count || 1 });

    try {
      const res = await getApi().start_generation(excelPath, outputDir, letterDate, signatory);
      setResults(res);
      const errors = res.filter(r => !r.success).length;
      if (errors === 0) {
        setStatusMessage(`Успешно сформировано ${res.length} уведомлений`);
      } else {
        setStatusMessage(`Завершено: ${res.length - errors} успешно, ${errors} с ошибками`);
      }
    } catch (err: any) {
      setStatusMessage(`Ошибка генерации: ${err?.message || String(err)}`);
    } finally {
      setIsGenerating(false);
    }
  };

  const handleOpenFolder = async () => {
    if (!outputDir) return;
    await getApi().open_path(outputDir);
  };

  const handleOpenFile = async (filename: string) => {
    if (!outputDir) return;
    const sep = outputDir.includes('\\') ? '\\' : '/';
    const fullPath = `${outputDir}${sep}${filename}`;
    await getApi().open_path(fullPath);
  };

  const filteredResults = results.filter(r => {
    if (filterTab === 'success') return r.success && r.warnings.length === 0;
    if (filterTab === 'warn') return r.success && r.warnings.length > 0;
    if (filterTab === 'error') return !r.success;
    return true;
  });

  const successCount = results.filter(r => r.success && r.warnings.length === 0).length;
  const warnCount = results.filter(r => r.success && r.warnings.length > 0).length;
  const errorCount = results.filter(r => !r.success).length;

  const progressPercent = progress.total > 0
    ? Math.min(100, Math.round((progress.current / progress.total) * 100))
    : 0;

  return (
    <div className="flex flex-col h-screen w-screen bg-slate-50 text-slate-800 font-sans antialiased overflow-hidden select-none">
      {/* Corporate Header with Official CloudPayments Logo */}
      <header className="flex items-center justify-between px-6 py-3 bg-white border-b border-slate-200/80 shadow-xs flex-shrink-0 z-10">
        <div className="flex items-center gap-3.5">
          <img
            src="./logo.png"
            alt="CloudPayments"
            className="w-8 h-8 rounded-lg shadow-xs object-contain"
          />
          <div>
            <div className="flex items-center gap-2">
              <span className="font-bold text-base tracking-tight text-slate-900 font-sans">
                Штрафинатор <span className="text-cloud-500 font-mono">2000</span>
              </span>
              <span className="text-[11px] font-medium px-2 py-0.5 rounded-full bg-blue-50 text-cloud-600 border border-blue-200/60">
                CloudPayments
              </span>
            </div>
            <p className="text-[11px] text-slate-500 font-normal">
              Генератор уведомлений об удержании штрафов
            </p>
          </div>
        </div>

        <div className="flex items-center gap-3">
          {/* Security badge */}
          <div className="flex items-center gap-1.5 px-3 py-1 rounded-full bg-slate-100/80 border border-slate-200 text-xs text-slate-600">
            <span className="w-2 h-2 rounded-full bg-emerald-500"></span>
            <span className="text-[11px] font-medium">Безопасно · On-Device</span>
          </div>

          {/* Rules modal button */}
          <button
            onClick={() => setRulesOpen(true)}
            className="flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg bg-white hover:bg-slate-50 border border-slate-200 text-xs font-medium text-slate-700 hover:text-slate-900 transition shadow-xs"
          >
            <HelpCircle className="w-3.5 h-3.5 text-cloud-500" />
            <span>Регламент и правила</span>
          </button>
        </div>
      </header>

      {/* Main Dual-Pane Workbench */}
      <div className="flex flex-1 overflow-hidden">
        {/* LEFT PANE: Clean Configuration Panel */}
        <div className="w-[430px] flex-shrink-0 bg-white border-r border-slate-200 flex flex-col overflow-y-auto">
          <div className="p-5 space-y-5">
            {/* Step 1: Excel Registry Input */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <label className="text-xs font-semibold uppercase tracking-wider text-slate-500 flex items-center gap-1.5">
                  <FileSpreadsheet className="w-4 h-4 text-cloud-500" />
                  1. Excel-реестр штрафов
                </label>
                {inspecting && (
                  <span className="text-xs text-cloud-500 flex items-center gap-1 font-medium">
                    <RefreshCw className="w-3 h-3 animate-spin" /> Чтение...
                  </span>
                )}
              </div>

              <div className="flex gap-2">
                <div
                  onClick={handleSelectExcel}
                  className="flex-1 px-3.5 py-2.5 rounded-lg bg-slate-50 border border-slate-200 hover:border-slate-300 hover:bg-slate-100/50 transition cursor-pointer text-xs flex items-center justify-between group overflow-hidden"
                >
                  <span className={`truncate font-mono text-[11px] ${excelPath ? 'text-slate-900 font-semibold' : 'text-slate-400'}`}>
                    {excelPath ? excelPath.split(/[/\\]/).pop() : 'Выберите .xlsx файл...'}
                  </span>
                  <span className="text-[10px] font-mono font-medium px-1.5 py-0.5 rounded bg-slate-200/80 text-slate-600">
                    XLSX
                  </span>
                </div>
                <button
                  onClick={handleSelectExcel}
                  className="px-4 py-2.5 rounded-lg bg-cloud-500 hover:bg-cloud-600 text-white text-xs font-semibold transition shadow-xs"
                >
                  Обзор
                </button>
              </div>

              {/* Preflight Inspection Card */}
              {inspectError && (
                <div className="p-3 rounded-lg bg-red-50 border border-red-200 text-xs text-red-700 flex items-start gap-2">
                  <XCircle className="w-4 h-4 text-red-500 flex-shrink-0 mt-0.5" />
                  <div>
                    <p className="font-semibold">Ошибка чтения файла</p>
                    <p className="text-[11px] text-red-600 mt-0.5">{inspectError}</p>
                  </div>
                </div>
              )}

              {inspection && !inspectError && (
                <div className="p-4 rounded-xl bg-slate-50 border border-slate-200/90 space-y-3 shadow-xs">
                  <div className="flex items-center justify-between pb-2.5 border-b border-slate-200">
                    <div className="flex items-center gap-1.5 text-xs">
                      <ShieldCheck className="w-4 h-4 text-emerald-600" />
                      <span className="font-bold text-slate-900">Реестр проверен</span>
                    </div>
                    <span className="text-[11px] font-medium text-slate-500">Лист: «{inspection.sheet_name}»</span>
                  </div>

                  {/* Key Metrics */}
                  <div className="grid grid-cols-2 gap-2.5">
                    <div className="p-3 rounded-lg bg-white border border-slate-200 shadow-2xs">
                      <span className="text-[10px] text-slate-500 uppercase font-medium tracking-wider block">К генерации</span>
                      <span className="text-xl font-bold font-mono text-emerald-600">
                        {inspection.valid_rows_count}
                      </span>
                      <span className="text-[11px] text-slate-400 ml-1">из {inspection.total_rows}</span>
                    </div>

                    <div className="p-3 rounded-lg bg-white border border-slate-200 shadow-2xs">
                      <span className="text-[10px] text-slate-500 uppercase font-medium tracking-wider block">Сумма удержаний</span>
                      <span className="text-sm font-bold font-mono text-slate-900 block truncate" title={`${inspection.total_fine_sum.toLocaleString('ru-RU')} ₽`}>
                        {inspection.total_fine_sum.toLocaleString('ru-RU')} ₽
                      </span>
                    </div>
                  </div>

                  {/* Columns status */}
                  <div className="space-y-1.5 pt-0.5">
                    <span className="text-[10px] text-slate-500 uppercase font-medium tracking-wider block">Поля документа</span>
                    <div className="flex flex-wrap gap-1.5 text-[10px]">
                      <span className="px-2 py-0.5 rounded-md bg-emerald-50 text-emerald-700 border border-emerald-200/80 font-medium">
                        ✓ Обязательные (ИНН, ЮЛ, Штраф, Период)
                      </span>
                      <span className={`px-2 py-0.5 rounded-md border font-medium ${inspection.has_optional_columns.director ? 'bg-blue-50 text-blue-700 border-blue-200' : 'bg-slate-100 text-slate-500 border-slate-200'}`}>
                        {inspection.has_optional_columns.director ? '✓ Директор' : '— Директор (заглушка)'}
                      </span>
                      <span className={`px-2 py-0.5 rounded-md border font-medium ${inspection.has_optional_columns.ogrn ? 'bg-blue-50 text-blue-700 border-blue-200' : 'bg-slate-100 text-slate-500 border-slate-200'}`}>
                        {inspection.has_optional_columns.ogrn ? '✓ ОГРН' : '— ОГРН (заглушка)'}
                      </span>
                      <span className={`px-2 py-0.5 rounded-md border font-medium ${inspection.has_optional_columns.email ? 'bg-blue-50 text-blue-700 border-blue-200' : 'bg-slate-100 text-slate-500 border-slate-200'}`}>
                        {inspection.has_optional_columns.email ? '✓ Email' : '— Email (заглушка)'}
                      </span>
                    </div>
                  </div>

                  {/* Preview toggle */}
                  {inspection.sample_records && inspection.sample_records.length > 0 && (
                    <div className="pt-1">
                      <button
                        onClick={() => setShowSamples(!showSamples)}
                        className="text-xs text-cloud-600 hover:text-cloud-700 font-medium flex items-center gap-1"
                      >
                        {showSamples ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronRight className="w-3.5 h-3.5" />}
                        {showSamples ? 'Скрыть примеры записей' : `Показать первые ${inspection.sample_records.length} контрагентов`}
                      </button>

                      {showSamples && (
                        <div className="mt-2 p-2.5 rounded-lg bg-white border border-slate-200 space-y-1.5 shadow-2xs">
                          {inspection.sample_records.map((r, i) => (
                            <div key={i} className="text-[11px] flex justify-between items-center py-1 border-b border-slate-100 last:border-0 font-mono">
                              <span className="truncate max-w-[200px] text-slate-800 font-medium">{r.yl}</span>
                              <span className="text-emerald-600 font-bold">{r.fine.toLocaleString('ru-RU')} ₽</span>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  )}
                </div>
              )}
            </div>

            {/* Step 2: Destination Folder */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <label className="text-xs font-semibold uppercase tracking-wider text-slate-500 flex items-center gap-1.5">
                  <FolderOpen className="w-4 h-4 text-cloud-500" />
                  2. Папка сохранения (.docx)
                </label>
                {excelPath && (
                  <button
                    onClick={handleSetSameDir}
                    className="text-xs text-cloud-600 hover:text-cloud-700 font-medium"
                  >
                    Рядом с Excel
                  </button>
                )}
              </div>

              <div className="flex gap-2">
                <div
                  onClick={handleSelectOutputDir}
                  className="flex-1 px-3.5 py-2.5 rounded-lg bg-slate-50 border border-slate-200 hover:border-slate-300 hover:bg-slate-100/50 transition cursor-pointer text-xs flex items-center justify-between overflow-hidden"
                >
                  <span className={`truncate font-mono text-[11px] ${outputDir ? 'text-slate-900 font-semibold' : 'text-slate-400'}`}>
                    {outputDir || 'Выберите папку для сохранения...'}
                  </span>
                </div>
                <button
                  onClick={handleSelectOutputDir}
                  className="px-4 py-2.5 rounded-lg bg-slate-100 hover:bg-slate-200/80 border border-slate-300 text-slate-700 text-xs font-semibold transition"
                >
                  Обзор
                </button>
              </div>
            </div>

            {/* Step 3: Date & Signatory */}
            <div className="space-y-3 pt-2 border-t border-slate-200">
              {/* Date */}
              <div className="space-y-1.5">
                <div className="flex items-center justify-between">
                  <label className="text-xs font-semibold uppercase tracking-wider text-slate-500 flex items-center gap-1.5">
                    <Calendar className="w-4 h-4 text-cloud-500" />
                    Дата уведомления
                  </label>
                  <div className="flex gap-1.5">
                    <button
                      onClick={() => handleQuickDatePreset('today')}
                      className="px-2.5 py-0.5 rounded text-[11px] font-medium bg-slate-100 hover:bg-slate-200 text-slate-600 hover:text-slate-900 transition"
                    >
                      Сегодня
                    </button>
                    <button
                      onClick={() => handleQuickDatePreset('end_month')}
                      className="px-2.5 py-0.5 rounded text-[11px] font-medium bg-slate-100 hover:bg-slate-200 text-slate-600 hover:text-slate-900 transition"
                    >
                      Конец мес.
                    </button>
                  </div>
                </div>
                <input
                  type="date"
                  value={letterDate}
                  onChange={(e) => setLetterDate(e.target.value)}
                  className="w-full px-3.5 py-2 rounded-lg bg-slate-50 border border-slate-200 text-slate-900 text-xs font-mono focus:bg-white focus:border-cloud-500 focus:outline-none transition shadow-2xs"
                />
              </div>

              {/* Signatory */}
              <div className="space-y-1.5">
                <label className="text-xs font-semibold uppercase tracking-wider text-slate-500 flex items-center gap-1.5">
                  <UserCheck className="w-4 h-4 text-cloud-500" />
                  Подписант (Уполномоченное лицо)
                </label>
                <input
                  type="text"
                  placeholder="Например: Иванов И. И. (или оставьте пустым)"
                  value={signatory}
                  onChange={(e) => setSignatory(e.target.value)}
                  className="w-full px-3.5 py-2 rounded-lg bg-slate-50 border border-slate-200 text-slate-900 text-xs placeholder:text-slate-400 focus:bg-white focus:border-cloud-500 focus:outline-none transition shadow-2xs"
                />
              </div>
            </div>
          </div>

          {/* Bottom Generation Action Button */}
          <div className="p-5 mt-auto bg-slate-50 border-t border-slate-200">
            <button
              onClick={handleGenerate}
              disabled={isGenerating || !excelPath || !outputDir || (inspection?.valid_rows_count === 0)}
              className={`w-full py-3 px-4 rounded-xl font-bold text-xs uppercase tracking-wider flex items-center justify-center gap-2 transition shadow-md ${
                isGenerating || !excelPath || !outputDir || (inspection?.valid_rows_count === 0)
                  ? 'bg-slate-200 text-slate-400 cursor-not-allowed border border-slate-300'
                  : 'bg-cloud-500 hover:bg-cloud-600 text-white shadow-blue-500/20 active:scale-[0.99]'
              }`}
            >
              {isGenerating ? (
                <>
                  <RefreshCw className="w-4 h-4 animate-spin" />
                  Генерация файлов...
                </>
              ) : (
                <>
                  <Play className="w-4 h-4 fill-current" />
                  Сгенерировать уведомления
                  {inspection?.valid_rows_count ? ` (${inspection.valid_rows_count})` : ''}
                </>
              )}
            </button>
          </div>
        </div>

        {/* RIGHT PANE: Results Feed & Output Monitor */}
        <div className="flex-1 bg-slate-50 flex flex-col overflow-hidden">
          {/* Header Status & Progress */}
          <div className="p-5 border-b border-slate-200 bg-white shadow-2xs">
            <div className="flex items-center justify-between mb-2.5">
              <span className="text-xs font-semibold text-slate-900 flex items-center gap-2">
                <span className={`w-2.5 h-2.5 rounded-full ${isGenerating ? 'bg-cloud-500 animate-ping' : results.length > 0 ? 'bg-emerald-500' : 'bg-slate-300'}`}></span>
                {statusMessage}
              </span>
              {progress.total > 0 && (
                <span className="text-xs font-mono font-bold text-slate-600">
                  {progress.current} / {progress.total} ({progressPercent}%)
                </span>
              )}
            </div>

            {/* Smooth Progress Track */}
            <div className="h-2.5 w-full bg-slate-100 rounded-full overflow-hidden border border-slate-200">
              <div
                className={`h-full transition-all duration-300 ease-out rounded-full ${
                  isGenerating ? 'bg-cloud-500' : 'bg-emerald-500'
                }`}
                style={{ width: `${progressPercent}%` }}
              />
            </div>

            {/* Results Filter Bar */}
            {results.length > 0 && (
              <div className="flex items-center justify-between mt-4 pt-3.5 border-t border-slate-100">
                <div className="flex gap-1.5">
                  <button
                    onClick={() => setFilterTab('all')}
                    className={`px-3 py-1 rounded-lg text-xs font-mono font-semibold transition ${
                      filterTab === 'all'
                        ? 'bg-slate-900 text-white shadow-2xs'
                        : 'text-slate-600 hover:text-slate-900 hover:bg-slate-100'
                    }`}
                  >
                    Все ({results.length})
                  </button>
                  <button
                    onClick={() => setFilterTab('success')}
                    className={`px-3 py-1 rounded-lg text-xs font-mono font-semibold transition ${
                      filterTab === 'success'
                        ? 'bg-emerald-50 text-emerald-700 border border-emerald-200 shadow-2xs'
                        : 'text-slate-600 hover:text-emerald-700 hover:bg-emerald-50/50'
                    }`}
                  >
                    Успешно ({successCount})
                  </button>
                  {warnCount > 0 && (
                    <button
                      onClick={() => setFilterTab('warn')}
                      className={`px-3 py-1 rounded-lg text-xs font-mono font-semibold transition ${
                        filterTab === 'warn'
                          ? 'bg-amber-50 text-amber-700 border border-amber-200 shadow-2xs'
                          : 'text-slate-600 hover:text-amber-700 hover:bg-amber-50/50'
                      }`}
                    >
                      С замечаниями ({warnCount})
                    </button>
                  )}
                  {errorCount > 0 && (
                    <button
                      onClick={() => setFilterTab('error')}
                      className={`px-3 py-1 rounded-lg text-xs font-mono font-semibold transition ${
                        filterTab === 'error'
                          ? 'bg-red-50 text-red-700 border border-red-200 shadow-2xs'
                          : 'text-slate-600 hover:text-red-700 hover:bg-red-50/50'
                      }`}
                    >
                      Ошибки ({errorCount})
                    </button>
                  )}
                </div>

                <button
                  onClick={handleOpenFolder}
                  className="flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg bg-cloud-50 hover:bg-cloud-100 border border-cloud-200 text-xs font-semibold text-cloud-700 transition"
                >
                  <FolderOpen className="w-3.5 h-3.5 text-cloud-500" />
                  Открыть папку с файлами
                </button>
              </div>
            )}
          </div>

          {/* Results List or Empty State */}
          <div className="flex-1 overflow-y-auto p-5 space-y-2">
            {results.length === 0 ? (
              <div className="h-full flex flex-col items-center justify-center text-center p-8">
                <div className="w-16 h-16 rounded-2xl bg-white border border-slate-200 shadow-sm flex items-center justify-center text-slate-400 mb-4">
                  <FileText className="w-8 h-8 text-cloud-500/40" />
                </div>
                <h3 className="text-sm font-bold text-slate-800">Список сгенерированных документов</h3>
                <p className="text-xs text-slate-500 max-w-sm mt-1">
                  Загрузите Excel-реестр и нажмите кнопку генерации. Готовые файлы Word появятся здесь с возможностью мгновенного открытия.
                </p>
              </div>
            ) : (
              filteredResults.map((item, idx) => (
                <div
                  key={idx}
                  className="p-3.5 rounded-xl bg-white border border-slate-200/90 hover:border-slate-300 shadow-2xs hover:shadow-xs transition flex items-start justify-between gap-3 group"
                >
                  <div className="flex items-start gap-3 min-w-0">
                    <div className="mt-0.5">
                      {item.success ? (
                        item.warnings.length > 0 ? (
                          <AlertTriangle className="w-4 h-4 text-amber-500 flex-shrink-0" />
                        ) : (
                          <CheckCircle2 className="w-4 h-4 text-emerald-500 flex-shrink-0" />
                        )
                      ) : (
                        <XCircle className="w-4 h-4 text-red-500 flex-shrink-0" />
                      )}
                    </div>

                    <div className="min-w-0 space-y-1">
                      <div className="flex items-center gap-2">
                        <span className="text-xs font-mono font-semibold text-slate-900 truncate">
                          {item.filename}
                        </span>
                        {item.success && item.warnings.length === 0 && (
                          <span className="text-[10px] font-mono font-bold px-2 py-0.5 rounded bg-emerald-50 text-emerald-700 border border-emerald-200">
                            Готов
                          </span>
                        )}
                      </div>

                      {item.warnings.length > 0 && (
                        <div className="space-y-0.5">
                          {item.warnings.map((w, wi) => (
                            <p key={wi} className="text-[11px] text-amber-700 flex items-center gap-1 font-medium">
                              <span>⚠</span> {w}
                            </p>
                          ))}
                        </div>
                      )}

                      {item.error && (
                        <p className="text-[11px] text-red-600 font-mono">
                          Ошибка: {item.error}
                        </p>
                      )}
                    </div>
                  </div>

                  {item.success && (
                    <div className="flex items-center gap-1.5 flex-shrink-0">
                      <button
                        onClick={() => handleOpenFile(item.filename)}
                        className="px-2.5 py-1 rounded-md bg-slate-100 hover:bg-slate-200 border border-slate-200 text-xs font-medium text-slate-700 transition flex items-center gap-1"
                        title="Открыть документ Word"
                      >
                        <ExternalLink className="w-3.5 h-3.5 text-cloud-500" />
                        Открыть
                      </button>
                    </div>
                  )}
                </div>
              ))
            )}
          </div>
        </div>
      </div>

      {/* Rules Modal */}
      {rulesOpen && (
        <div className="fixed inset-0 z-50 bg-slate-900/40 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="w-[620px] max-w-full max-h-[85vh] bg-white border border-slate-200 rounded-2xl shadow-xl flex flex-col overflow-hidden animate-in fade-in zoom-in-95 duration-150">
            <div className="flex items-center justify-between px-6 py-4 border-b border-slate-200">
              <div className="flex items-center gap-2.5">
                <img src="./logo.png" alt="CloudPayments" className="w-6 h-6 rounded object-contain" />
                <h3 className="font-bold text-sm text-slate-900">Регламент работы и логика генератора</h3>
              </div>
              <button
                onClick={() => setRulesOpen(false)}
                className="p-1.5 rounded-lg hover:bg-slate-100 text-slate-400 hover:text-slate-600 transition"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="p-6 overflow-y-auto space-y-3.5">
              {rulesList.map((rule, idx) => (
                <div key={idx} className="p-4 rounded-xl bg-slate-50 border border-slate-200 space-y-1">
                  <h4 className="text-xs font-bold text-slate-900 flex items-center gap-2">
                    <span className="w-5 h-5 rounded-full bg-cloud-500 text-white flex items-center justify-center text-[11px] font-mono font-bold">
                      {idx + 1}
                    </span>
                    {rule.title}
                  </h4>
                  <p className="text-xs text-slate-600 leading-relaxed pl-7">
                    {rule.body}
                  </p>
                </div>
              ))}
            </div>

            <div className="px-6 py-3.5 bg-slate-50 border-t border-slate-200 flex justify-end">
              <button
                onClick={() => setRulesOpen(false)}
                className="px-5 py-2 rounded-lg bg-cloud-500 hover:bg-cloud-600 text-white text-xs font-bold transition shadow-xs"
              >
                Понятно
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
