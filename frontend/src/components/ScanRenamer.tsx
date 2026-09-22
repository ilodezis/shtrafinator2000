import { useState, useEffect } from 'react';
import {
  FolderOpen,
  Play,
  CheckCircle2,
  AlertTriangle,
  FileText,
  ExternalLink,
  RefreshCw,
  FolderSync,
  Edit3,
  Check,
  Sparkles,
  ArrowRight,
  ShieldCheck
} from 'lucide-react';
import type { ScanItemResult, ScanRenameResult } from '../types/pywebview';

interface ScanRenamerProps {
  outputDir: string;
}

export default function ScanRenamer({ outputDir }: ScanRenamerProps) {
  const [scansDir, setScansDir] = useState<string>('');
  const [isScanning, setIsScanning] = useState<boolean>(false);
  const [scanProgress, setScanProgress] = useState<{ current: number; total: number; filename: string }>({
    current: 0,
    total: 0,
    filename: '',
  });
  const [statusMessage, setStatusMessage] = useState<string>('Выберите папку со сканами');
  const [scanResults, setScanResults] = useState<ScanItemResult[]>([]);
  const [isRenaming, setIsRenaming] = useState<boolean>(false);
  const [renameSuccessCount, setRenameSuccessCount] = useState<number | null>(null);

  const getApi = () => {
    if (typeof window !== 'undefined' && window.pywebview && window.pywebview.api) {
      return window.pywebview.api;
    }
    return null;
  };

  useEffect(() => {
    const handleScanProgress = (event: any) => {
      const detail = event.detail || event;
      if (detail && typeof detail.current === 'number') {
        setScanProgress({
          current: detail.current,
          total: detail.total,
          filename: detail.filename || '',
        });
        setStatusMessage(`Распознавание скана ${detail.current} из ${detail.total}: ${detail.filename}...`);
      }
    };

    window.addEventListener('pywebview-scan-progress', handleScanProgress);
    return () => window.removeEventListener('pywebview-scan-progress', handleScanProgress);
  }, []);

  const handleSelectScansDir = async () => {
    const api = getApi();
    if (!api) return;
    try {
      const dir = await api.select_scans_dir();
      if (dir) {
        setScansDir(dir);
        setScanResults([]);
        setRenameSuccessCount(null);
        setStatusMessage(`Выбрана папка: ${dir}`);
      }
    } catch (e) {
      console.error(e);
    }
  };

  const handleUseGeneratorDir = () => {
    if (!outputDir) return;
    const sep = outputDir.includes('\\') ? '\\' : '/';
    const candidateSubdir = `${outputDir}${sep}сканы`;
    setScansDir(candidateSubdir);
    setScanResults([]);
    setRenameSuccessCount(null);
    setStatusMessage(`Выбрана папка: ${candidateSubdir}`);
  };

  const handleAnalyzeScans = async () => {
    if (!scansDir) {
      setStatusMessage('Ошибка: укажите папку со сканами');
      return;
    }
    const api = getApi();
    if (!api) return;

    setIsScanning(true);
    setStatusMessage('Поиск PDF-сканов и распознавание текста...');
    setScanProgress({ current: 0, total: 0, filename: '' });
    setRenameSuccessCount(null);

    try {
      const items = await api.analyze_scans(scansDir);
      setScanResults(items);
      const matched = items.filter(i => i.status === 'matched').length;
      if (items.length === 0) {
        setStatusMessage('В выбранной папке не найдено файлов .pdf');
      } else {
        setStatusMessage(`Анализ завершен: успешно распознано ${matched} из ${items.length} файлов`);
      }
    } catch (err: any) {
      setStatusMessage(`Ошибка: ${err?.message || String(err)}`);
    } finally {
      setIsScanning(false);
    }
  };

  const handleUpdateProposedName = (index: number, newName: string) => {
    setScanResults(prev => {
      const copy = [...prev];
      copy[index] = { ...copy[index], proposed_name: newName };
      return copy;
    });
  };

  const handleApplyRenames = async () => {
    if (scanResults.length === 0) return;
    const api = getApi();
    if (!api) return;

    setIsRenaming(true);
    setStatusMessage('Применение новых имен файлов...');

    try {
      const renameRes = await api.apply_scan_renames(scanResults);
      const successful = renameRes.filter((r: ScanRenameResult) => r.success && !r.skipped).length;
      setRenameSuccessCount(successful);
      setStatusMessage(`Успешно переименовано ${successful} файлов`);

      // Mark renamed items
      setScanResults(prev =>
        prev.map(item => {
          const res = renameRes.find((r: ScanRenameResult) => r.original_name === item.original_name);
          if (res && res.success) {
            return {
              ...item,
              original_name: item.proposed_name,
              status: 'matched',
            };
          }
          return item;
        })
      );
    } catch (err: any) {
      setStatusMessage(`Ошибка при переименовании: ${err?.message || String(err)}`);
    } finally {
      setIsRenaming(false);
    }
  };

  const handleOpenFolder = async () => {
    if (!scansDir) return;
    const api = getApi();
    if (api) {
      await api.open_path(scansDir);
    }
  };

  const matchedCount = scanResults.filter(i => i.status === 'matched').length;
  const unrecognizedCount = scanResults.filter(i => i.status !== 'matched').length;
  const progressPercent = scanProgress.total > 0
    ? Math.min(100, Math.round((scanProgress.current / scanProgress.total) * 100))
    : 0;

  return (
    <div className="flex flex-1 overflow-hidden">
      {/* LEFT PANE: Scan Folder Configuration & Controls */}
      <div className="w-[420px] flex-shrink-0 bg-white border-r border-slate-200 flex flex-col overflow-y-auto">
        <div className="p-5 space-y-5">
          {/* Step 1: Scans Folder Picker */}
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <label className="text-xs font-semibold uppercase tracking-wider text-slate-500 flex items-center gap-1.5">
                <FolderOpen className="w-4 h-4 text-cloud-500" />
                Папка со сканами (.pdf)
              </label>
              {outputDir && (
                <button
                  onClick={handleUseGeneratorDir}
                  className="text-xs text-cloud-600 hover:text-cloud-700 font-medium flex items-center gap-1"
                  title="Подставить подпапку 'сканы' из текущей папки выгрузки"
                >
                  <FolderSync className="w-3 h-3" />
                  Подпапка «сканы»
                </button>
              )}
            </div>

            <div className="flex gap-2">
              <div
                onClick={handleSelectScansDir}
                className="flex-1 px-3.5 py-2.5 rounded-lg bg-slate-50 border border-slate-200 hover:border-slate-300 hover:bg-slate-100/50 transition cursor-pointer text-xs flex items-center justify-between overflow-hidden"
              >
                <span className={`truncate font-mono text-[11px] ${scansDir ? 'text-slate-900 font-semibold' : 'text-slate-400'}`}>
                  {scansDir ? scansDir.split(/[/\\]/).pop() || scansDir : 'Выберите папку со сканами...'}
                </span>
                <span className="text-[10px] font-mono font-medium px-1.5 py-0.5 rounded bg-slate-200/80 text-slate-600">
                  PDF
                </span>
              </div>
              <button
                onClick={handleSelectScansDir}
                className="px-4 py-2.5 rounded-lg bg-cloud-500 hover:bg-cloud-600 text-white text-xs font-semibold transition shadow-xs"
              >
                Обзор
              </button>
            </div>

            {scansDir && (
              <p className="text-[11px] text-slate-400 font-mono truncate px-1">
                {scansDir}
              </p>
            )}
          </div>

          {/* How it works info card */}
          <div className="p-4 rounded-xl bg-slate-50 border border-slate-200/80 space-y-2.5">
            <div className="flex items-center gap-2 text-xs font-bold text-slate-800">
              <Sparkles className="w-4 h-4 text-cloud-500" />
              <span>Автораспознавание документов</span>
            </div>
            <p className="text-xs text-slate-600 leading-relaxed">
              Программа открывает каждый PDF от сканера, через OCR находит название компании в первом абзаце (<span className="font-semibold text-slate-800">«Между...»</span>) или в шапке, сверяет с файлами Word в папке и автоматически переименовывает файлы.
            </p>
            <div className="flex items-center gap-2 text-[11px] text-slate-500 pt-1 border-t border-slate-200">
              <ShieldCheck className="w-3.5 h-3.5 text-emerald-600" />
              <span>Обработка выполняется локально на вашем компьютере</span>
            </div>
          </div>

          {/* Action Button */}
          <button
            onClick={handleAnalyzeScans}
            disabled={!scansDir || isScanning}
            className={`w-full py-3 px-4 rounded-xl font-bold text-xs flex items-center justify-center gap-2 transition shadow-sm ${
              !scansDir || isScanning
                ? 'bg-slate-100 text-slate-400 cursor-not-allowed border border-slate-200'
                : 'bg-cloud-500 hover:bg-cloud-600 text-white shadow-cloud-500/20 active:scale-[0.99]'
            }`}
          >
            {isScanning ? (
              <>
                <RefreshCw className="w-4 h-4 animate-spin" />
                <span>Распознавание сканов...</span>
              </>
            ) : (
              <>
                <Play className="w-4 h-4 fill-current" />
                <span>Начать анализ сканов</span>
              </>
            )}
          </button>

          {/* Progress Bar */}
          {isScanning && (
            <div className="space-y-1.5 p-3 rounded-lg bg-blue-50/60 border border-blue-100">
              <div className="flex justify-between text-[11px] font-medium text-slate-600">
                <span>Прогресс OCR</span>
                <span className="font-mono text-cloud-600 font-bold">
                  {scanProgress.current} / {scanProgress.total} ({progressPercent}%)
                </span>
              </div>
              <div className="w-full bg-blue-200/50 rounded-full h-2 overflow-hidden">
                <div
                  className="bg-cloud-500 h-2 rounded-full transition-all duration-300"
                  style={{ width: `${progressPercent}%` }}
                />
              </div>
              {scanProgress.filename && (
                <p className="text-[10px] text-slate-500 font-mono truncate">
                  {scanProgress.filename}
                </p>
              )}
            </div>
          )}
        </div>

        {/* Bottom Status Box */}
        <div className="mt-auto p-4 bg-slate-50/80 border-t border-slate-200 text-xs flex items-center justify-between">
          <span className="text-slate-600 font-medium truncate">
            {statusMessage}
          </span>
          {scansDir && (
            <button
              onClick={handleOpenFolder}
              className="text-xs text-cloud-600 hover:text-cloud-700 font-semibold flex items-center gap-1 flex-shrink-0 ml-2"
            >
              <ExternalLink className="w-3.5 h-3.5" />
              Папка
            </button>
          )}
        </div>
      </div>

      {/* RIGHT PANE: Interactive Results & Rename Table */}
      <div className="flex-1 flex flex-col bg-slate-50/50 overflow-hidden">
        {/* Top summary bar */}
        <div className="flex items-center justify-between px-6 py-3.5 bg-white border-b border-slate-200 flex-shrink-0">
          <div className="flex items-center gap-3">
            <h2 className="text-sm font-bold text-slate-900 flex items-center gap-2">
              <FileText className="w-4 h-4 text-cloud-500" />
              Сканы для переименования
            </h2>
            {scanResults.length > 0 && (
              <span className="text-xs font-mono font-bold px-2 py-0.5 rounded-full bg-slate-100 text-slate-700 border border-slate-200">
                {scanResults.length}
              </span>
            )}
          </div>

          {scanResults.length > 0 && (
            <div className="flex items-center gap-2">
              <span className="text-xs font-medium px-2.5 py-1 rounded-md bg-emerald-50 text-emerald-700 border border-emerald-200 flex items-center gap-1.5">
                <CheckCircle2 className="w-3 h-3" />
                Распознано: {matchedCount}
              </span>
              {unrecognizedCount > 0 && (
                <span className="text-xs font-medium px-2.5 py-1 rounded-md bg-amber-50 text-amber-700 border border-amber-200 flex items-center gap-1.5">
                  <AlertTriangle className="w-3 h-3" />
                  Без имени: {unrecognizedCount}
                </span>
              )}
            </div>
          )}
        </div>

        {/* Content Area */}
        <div className="flex-1 overflow-y-auto p-6">
          {scanResults.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-center p-8 border-2 border-dashed border-slate-200 rounded-2xl bg-white/50">
              <div className="w-14 h-14 rounded-2xl bg-blue-50 text-cloud-500 flex items-center justify-center mb-4 border border-blue-100 shadow-xs">
                <FileText className="w-7 h-7" />
              </div>
              <h3 className="text-sm font-bold text-slate-800 mb-1">
                Список файлов пуст
              </h3>
              <p className="text-xs text-slate-500 max-w-sm leading-relaxed mb-4">
                Выберите папку, куда принтер или почта сохранили отсканированные уведомления (.pdf), и нажмите «Начать анализ сканов».
              </p>
              <button
                onClick={handleSelectScansDir}
                className="px-4 py-2 rounded-lg bg-slate-100 hover:bg-slate-200 text-slate-700 font-semibold text-xs transition"
              >
                Выбрать папку со сканами
              </button>
            </div>
          ) : (
            <div className="space-y-3">
              {renameSuccessCount !== null && (
                <div className="p-3.5 rounded-xl bg-emerald-50 border border-emerald-200 flex items-center justify-between text-xs text-emerald-800">
                  <div className="flex items-center gap-2 font-medium">
                    <CheckCircle2 className="w-4 h-4 text-emerald-600" />
                    <span>Файлы успешно переименованы ({renameSuccessCount} шт.)</span>
                  </div>
                  <button
                    onClick={handleOpenFolder}
                    className="font-bold underline hover:no-underline text-emerald-900"
                  >
                    Посмотреть в папке
                  </button>
                </div>
              )}

              <div className="bg-white border border-slate-200 rounded-xl overflow-hidden shadow-xs">
                <table className="w-full text-left border-collapse">
                  <thead>
                    <tr className="bg-slate-50 border-b border-slate-200 text-[11px] font-semibold text-slate-500 uppercase tracking-wider">
                      <th className="py-2.5 px-4">Исходный скан</th>
                      <th className="py-2.5 px-4">Распознанный контрагент</th>
                      <th className="py-2.5 px-4">Новое имя файла (.pdf)</th>
                      <th className="py-2.5 px-4 text-right">Статус</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100 text-xs">
                    {scanResults.map((item, idx) => (
                      <tr key={idx} className="hover:bg-slate-50/80 transition group">
                        <td className="py-3 px-4 font-mono text-slate-600 font-medium text-[11px] max-w-[180px] truncate">
                          {item.original_name}
                        </td>
                        <td className="py-3 px-4">
                          <div className="space-y-0.5">
                            <span className="font-semibold text-slate-900">
                              {item.company_name}
                            </span>
                            {item.inn && item.inn !== '—' && (
                              <span className="block text-[10px] font-mono text-slate-400">
                                ИНН: {item.inn}
                              </span>
                            )}
                          </div>
                        </td>
                        <td className="py-3 px-4">
                          <div className="flex items-center gap-1.5 max-w-[280px]">
                            <input
                              type="text"
                              value={item.proposed_name}
                              onChange={(e) => handleUpdateProposedName(idx, e.target.value)}
                              className="w-full px-2.5 py-1 text-xs font-mono rounded bg-slate-50 border border-slate-200 focus:bg-white focus:border-cloud-500 focus:outline-none transition"
                              title="Вы можете вручную изменить имя файла перед переименованием"
                            />
                            <Edit3 className="w-3 h-3 text-slate-300 group-hover:text-slate-500 flex-shrink-0" />
                          </div>
                        </td>
                        <td className="py-3 px-4 text-right">
                          {item.status === 'matched' ? (
                            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded font-mono text-[10px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
                              <Check className="w-3 h-3" />
                              Распознано
                            </span>
                          ) : (
                            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded font-mono text-[10px] font-bold bg-amber-50 text-amber-700 border border-amber-200">
                              <AlertTriangle className="w-3 h-3" />
                              Вручную
                            </span>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>

        {/* Bottom Action Bar */}
        {scanResults.length > 0 && (
          <div className="p-4 bg-white border-t border-slate-200 flex items-center justify-between flex-shrink-0">
            <div className="text-xs text-slate-500">
              Готово к переименованию: <span className="font-bold text-slate-800">{matchedCount}</span> из {scanResults.length}
            </div>

            <div className="flex items-center gap-3">
              <button
                onClick={handleOpenFolder}
                className="px-4 py-2 rounded-lg bg-slate-100 hover:bg-slate-200 border border-slate-200 text-slate-700 text-xs font-semibold transition flex items-center gap-1.5"
              >
                <ExternalLink className="w-3.5 h-3.5 text-slate-500" />
                Открыть папку
              </button>

              <button
                onClick={handleApplyRenames}
                disabled={isRenaming || matchedCount === 0}
                className={`px-5 py-2 rounded-lg font-bold text-xs flex items-center gap-2 transition shadow-xs ${
                  isRenaming || matchedCount === 0
                    ? 'bg-slate-100 text-slate-400 cursor-not-allowed border border-slate-200'
                    : 'bg-cloud-500 hover:bg-cloud-600 text-white shadow-cloud-500/20 active:scale-[0.99]'
                }`}
              >
                {isRenaming ? (
                  <>
                    <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                    <span>Переименование...</span>
                  </>
                ) : (
                  <>
                    <ArrowRight className="w-3.5 h-3.5" />
                    <span>Переименовать файлы ({matchedCount})</span>
                  </>
                )}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
