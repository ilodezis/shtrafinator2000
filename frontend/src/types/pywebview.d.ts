export interface PreflightInspection {
  sheet_name: string;
  total_rows: number;
  valid_rows_count: number;
  total_fine_sum: number;
  columns_found: string[];
  has_optional_columns: {
    director: boolean;
    ogrn: boolean;
    email: boolean;
  };
  sample_records: Array<{
    yl: string;
    inn: string;
    fine: number;
    director: string;
  }>;
}

export interface GenerationItemResult {
  filename: string;
  success: boolean;
  warnings: string[];
  error?: string | null;
}

export interface RuleItem {
  title: string;
  body: string;
}

export interface ScanItemResult {
  original_name: string;
  original_path: string;
  proposed_name: string;
  company_name: string;
  inn: string;
  method: string;
  confidence: number;
  status: 'matched' | 'unrecognized' | 'error';
  error?: string;
}

export interface ScanRenameResult {
  original_name: string;
  new_name: string;
  success: boolean;
  skipped?: boolean;
  error?: string;
}

export interface PyWebViewApi {
  select_excel_file: () => Promise<string | null>;
  select_output_dir: () => Promise<string | null>;
  inspect_excel: (path: string) => Promise<PreflightInspection>;
  start_generation: (
    excel_path: string,
    output_dir: string,
    letter_date_iso: string,
    signatory: string
  ) => Promise<GenerationItemResult[]>;
  select_scans_dir: () => Promise<string | null>;
  analyze_scans: (folder_path: string) => Promise<ScanItemResult[]>;
  apply_scan_renames: (items: ScanItemResult[]) => Promise<ScanRenameResult[]>;
  open_path: (path: string) => Promise<boolean>;
  get_rules: () => Promise<RuleItem[]>;
}

declare global {
  interface Window {
    pywebview?: {
      api: PyWebViewApi;
    };
  }
}
