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
