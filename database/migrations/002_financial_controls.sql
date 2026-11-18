-- ميزان: ضوابط مالية وكيانات تشغيلية إضافية
-- ينفذ بعد 001_initial.sql على PostgreSQL 16+

CREATE TABLE IF NOT EXISTS idempotency_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id uuid NOT NULL REFERENCES users(id),
  idempotency_key varchar(180) NOT NULL,
  request_hash char(64) NOT NULL,
  response_status integer,
  response_body jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz,
  UNIQUE(actor_user_id, idempotency_key)
);

CREATE TABLE IF NOT EXISTS expense_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), expense_id uuid NOT NULL REFERENCES expenses(id),
  revision_no integer NOT NULL, changed_by uuid NOT NULL REFERENCES users(id),
  reason text NOT NULL, before_data jsonb NOT NULL, after_data jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(expense_id, revision_no)
);
CREATE TABLE IF NOT EXISTS recurring_expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), group_id uuid NOT NULL REFERENCES groups(id),
  created_by_profile_id uuid NOT NULL REFERENCES profiles(id), description varchar(500) NOT NULL,
  category_id uuid REFERENCES categories(id), merchant_name varchar(180), amount_sar numeric(19,4) NOT NULL CHECK(amount_sar >= 0),
  frequency varchar(20) NOT NULL CHECK(frequency IN ('weekly','monthly','quarterly','yearly')),
  starts_on date NOT NULL, ends_on date, next_run_on date NOT NULL,
  is_active boolean NOT NULL DEFAULT true, template_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(), CHECK(ends_on IS NULL OR ends_on >= starts_on)
);
CREATE TABLE IF NOT EXISTS account_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), account_id uuid NOT NULL REFERENCES accounts(id),
  transaction_type varchar(30) NOT NULL CHECK(transaction_type IN ('deposit','withdrawal','transfer_in','transfer_out','adjustment')),
  amount_original numeric(19,4) NOT NULL CHECK(amount_original > 0), currency_code char(3) NOT NULL,
  amount_sar numeric(19,4) NOT NULL CHECK(amount_sar > 0), transaction_at timestamptz NOT NULL,
  source_type varchar(40) NOT NULL, source_id uuid, status payment_status NOT NULL DEFAULT 'pending',
  created_by uuid NOT NULL REFERENCES users(id), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS account_transactions_account_date_idx ON account_transactions(account_id, transaction_at DESC);
CREATE TABLE IF NOT EXISTS group_leave_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), group_id uuid NOT NULL REFERENCES groups(id),
  profile_id uuid NOT NULL REFERENCES profiles(id), requested_at timestamptz NOT NULL DEFAULT now(),
  decision varchar(20) NOT NULL DEFAULT 'pending' CHECK(decision IN ('pending','approved','rejected')),
  decided_by uuid REFERENCES profiles(id), decided_at timestamptz, note text
);
CREATE TABLE IF NOT EXISTS stocktake_approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), stocktake_id uuid NOT NULL REFERENCES stocktakes(id),
  approved_by uuid NOT NULL REFERENCES profiles(id), decision varchar(20) NOT NULL CHECK(decision IN ('approved','rejected')),
  note text, decided_at timestamptz NOT NULL DEFAULT now(), UNIQUE(stocktake_id, approved_by)
);
CREATE TABLE IF NOT EXISTS reconciliation_adjustments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), stocktake_line_id uuid NOT NULL REFERENCES stocktake_lines(id),
  reason text NOT NULL, attachment_id uuid REFERENCES attachments(id), requested_by uuid NOT NULL REFERENCES profiles(id),
  approved_by uuid REFERENCES profiles(id), status varchar(20) NOT NULL DEFAULT 'pending'
    CHECK(status IN ('pending','approved','rejected','posted')),
  journal_entry_id uuid REFERENCES journal_entries(id), created_at timestamptz NOT NULL DEFAULT now(), approved_at timestamptz
);
CREATE TABLE IF NOT EXISTS bank_statement_imports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), account_id uuid NOT NULL REFERENCES accounts(id),
  uploaded_by uuid NOT NULL REFERENCES users(id), file_attachment_id uuid REFERENCES attachments(id),
  period_start date, period_end date, status varchar(20) NOT NULL DEFAULT 'uploaded', created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS bank_statement_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), import_id uuid NOT NULL REFERENCES bank_statement_imports(id),
  transaction_date timestamptz NOT NULL, description text, amount numeric(19,4) NOT NULL,
  currency_code char(3) NOT NULL, external_reference varchar(180), raw_data jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE TABLE IF NOT EXISTS bank_transaction_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), statement_line_id uuid NOT NULL REFERENCES bank_statement_lines(id),
  account_transaction_id uuid REFERENCES account_transactions(id), expense_payment_id uuid REFERENCES expense_payments(id),
  matched_by uuid NOT NULL REFERENCES users(id), matched_at timestamptz NOT NULL DEFAULT now(),
  CHECK(num_nonnulls(account_transaction_id, expense_payment_id) = 1), UNIQUE(statement_line_id)
);
CREATE TABLE IF NOT EXISTS ocr_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), attachment_id uuid NOT NULL REFERENCES attachments(id),
  requested_by uuid NOT NULL REFERENCES users(id), status varchar(20) NOT NULL DEFAULT 'queued',
  provider varchar(80), error_message text, created_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz
);
CREATE TABLE IF NOT EXISTS ocr_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), ocr_job_id uuid NOT NULL REFERENCES ocr_jobs(id),
  extracted_data jsonb NOT NULL, confidence numeric(5,4), reviewed_by uuid REFERENCES users(id),
  reviewed_at timestamptz, accepted boolean, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS import_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), requested_by uuid NOT NULL REFERENCES users(id),
  entity_type varchar(40) NOT NULL, attachment_id uuid REFERENCES attachments(id),
  status varchar(20) NOT NULL DEFAULT 'queued', total_rows integer NOT NULL DEFAULT 0,
  success_rows integer NOT NULL DEFAULT 0, error_rows integer NOT NULL DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS import_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), import_job_id uuid NOT NULL REFERENCES import_jobs(id),
  row_number integer NOT NULL, raw_data jsonb NOT NULL, normalized_data jsonb,
  status varchar(20) NOT NULL DEFAULT 'pending', error_detail jsonb, possible_duplicate_of uuid,
  UNIQUE(import_job_id, row_number)
);
CREATE TABLE IF NOT EXISTS export_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), requested_by uuid NOT NULL REFERENCES users(id),
  export_type varchar(40) NOT NULL, format varchar(10) NOT NULL CHECK(format IN ('xlsx','pdf','csv')),
  filters jsonb NOT NULL DEFAULT '{}'::jsonb, storage_key text, status varchar(20) NOT NULL DEFAULT 'queued',
  created_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz
);
CREATE TABLE IF NOT EXISTS backup_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), backup_type varchar(20) NOT NULL CHECK(backup_type IN ('daily','manual','pre_restore')),
  storage_key text, status varchar(20) NOT NULL DEFAULT 'queued', started_at timestamptz,
  completed_at timestamptz, checksum_sha256 char(64), error_message text, initiated_by uuid REFERENCES users(id)
);
CREATE TABLE IF NOT EXISTS restore_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), backup_job_id uuid NOT NULL REFERENCES backup_jobs(id),
  requested_by uuid NOT NULL REFERENCES users(id), status varchar(20) NOT NULL DEFAULT 'requested',
  approved_by uuid REFERENCES users(id), started_at timestamptz, completed_at timestamptz, notes text
);
CREATE TABLE IF NOT EXISTS permanent_deletions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), recycle_bin_id uuid NOT NULL REFERENCES recycle_bin(id),
  deleted_by uuid NOT NULL REFERENCES users(id), reason text NOT NULL, snapshot_hash char(64) NOT NULL,
  deleted_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS settlement_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), settlement_id uuid NOT NULL REFERENCES settlements(id),
  attachment_id uuid NOT NULL REFERENCES attachments(id), uploaded_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(settlement_id, attachment_id)
);
CREATE TABLE IF NOT EXISTS ledger_periods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), group_id uuid REFERENCES groups(id),
  period_start date NOT NULL, period_end date NOT NULL, status varchar(20) NOT NULL DEFAULT 'open'
    CHECK(status IN ('open','closed')), closed_by uuid REFERENCES users(id), closed_at timestamptz,
  CHECK(period_end >= period_start)
);
CREATE TABLE IF NOT EXISTS financial_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), group_id uuid REFERENCES groups(id),
  event_type varchar(50) NOT NULL, source_type varchar(50) NOT NULL, source_id uuid NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb, created_by uuid REFERENCES users(id), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS sync_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id),
  device_label varchar(120) NOT NULL, last_seen_at timestamptz, revoked_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS sync_operations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), device_id uuid NOT NULL REFERENCES sync_devices(id),
  client_operation_id varchar(180) NOT NULL, entity_type varchar(50) NOT NULL, payload jsonb NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(), UNIQUE(device_id, client_operation_id)
);
CREATE TABLE IF NOT EXISTS user_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id),
  token_hash char(64) NOT NULL UNIQUE, expires_at timestamptz NOT NULL, revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- حماية قيد افتتاحي فريد لكل حساب دفتر أستاذ شخصي (group_id IS NULL).
CREATE UNIQUE INDEX IF NOT EXISTS ledger_accounts_profile_code_uq
  ON ledger_accounts(profile_id, code) WHERE group_id IS NULL AND profile_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS journal_entries_source_uq
  ON journal_entries(source_type, source_id) WHERE source_id IS NOT NULL AND status = 'posted';
CREATE INDEX IF NOT EXISTS audit_logs_entity_idx ON audit_logs(entity_type, entity_id, created_at DESC);
CREATE INDEX IF NOT EXISTS recycle_bin_deleted_idx ON recycle_bin(deleted_at DESC) WHERE restored_at IS NULL;

-- تقسيم متساوٍ على المستفيدين النشطين وقت إنشاء المصروف.
-- SAR يعامل بدقة الهللة (منزلتان)، والباقي يوزع بترتيب UUID ثابت.
CREATE OR REPLACE FUNCTION create_equal_expense_shares(p_expense_id uuid)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_total numeric(19,2); v_count integer; v_base numeric(19,2); v_remainder integer;
BEGIN
  SELECT round(total_sar, 2) INTO v_total FROM expenses WHERE id = p_expense_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'expense_not_found'; END IF;
  IF EXISTS (SELECT 1 FROM expense_shares WHERE expense_id = p_expense_id AND share_version = 1) THEN
    RAISE EXCEPTION 'shares_already_created';
  END IF;
  SELECT count(*) INTO v_count FROM group_members gm JOIN expenses e ON e.group_id = gm.group_id
    WHERE e.id = p_expense_id AND gm.status = 'active';
  IF v_count = 0 THEN RAISE EXCEPTION 'no_active_members'; END IF;
  v_base := floor((v_total * 100) / v_count) / 100;
  v_remainder := ((v_total * 100)::integer - (v_base * 100 * v_count)::integer);
  INSERT INTO expense_shares(expense_id, profile_id, share_amount_sar, share_version)
  SELECT p_expense_id, ranked.profile_id,
    v_base + CASE WHEN ranked.rn <= v_remainder THEN 0.01 ELSE 0 END, 1
  FROM (
    SELECT gm.profile_id, row_number() OVER (ORDER BY gm.profile_id) AS rn
    FROM group_members gm JOIN expenses e ON e.group_id = gm.group_id
    WHERE e.id = p_expense_id AND gm.status = 'active'
  ) ranked;
  RETURN v_count;
END $$;

-- ترحيل الرصيد الافتتاحي كأصل مقابل حقوق/أرصدة افتتاحية؛ ليس إيراداً.
CREATE OR REPLACE FUNCTION post_account_opening_balance(p_opening_balance_id uuid, p_created_by uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_ob account_opening_balances%ROWTYPE; v_account accounts%ROWTYPE;
        v_asset_id uuid; v_equity_id uuid; v_entry_id uuid;
BEGIN
  SELECT * INTO v_ob FROM account_opening_balances WHERE id = p_opening_balance_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'opening_balance_not_found'; END IF;
  SELECT * INTO v_account FROM accounts WHERE id = v_ob.account_id;
  IF v_ob.amount_sar = 0 THEN RETURN NULL; END IF;
  SELECT id INTO v_asset_id FROM ledger_accounts WHERE group_id IS NULL AND profile_id = v_account.profile_id AND code = 'ASSET:' || v_account.id::text;
  IF v_asset_id IS NULL THEN
    INSERT INTO ledger_accounts(group_id,profile_id,code,name,account_class)
    VALUES(NULL,v_account.profile_id,'ASSET:' || v_account.id::text,'رصيد حساب: ' || v_account.name,'asset') RETURNING id INTO v_asset_id;
  END IF;
  SELECT id INTO v_equity_id FROM ledger_accounts WHERE group_id IS NULL AND profile_id = v_account.profile_id AND code = 'OPENING_BALANCE';
  IF v_equity_id IS NULL THEN
    INSERT INTO ledger_accounts(group_id,profile_id,code,name,account_class)
    VALUES(NULL,v_account.profile_id,'OPENING_BALANCE','الأرصدة الافتتاحية','equity') RETURNING id INTO v_equity_id;
  END IF;
  INSERT INTO journal_entries(group_id,entry_date,description,source_type,source_id,status,created_by)
  VALUES(NULL,v_ob.opening_date,'إثبات الرصيد الافتتاحي للحساب ' || v_account.name,'account_opening_balance',v_ob.id,'draft',p_created_by)
  RETURNING id INTO v_entry_id;
  INSERT INTO journal_lines(journal_entry_id,ledger_account_id,debit_sar,credit_sar)
  VALUES(v_entry_id,v_asset_id,v_ob.amount_sar,0),(v_entry_id,v_equity_id,0,v_ob.amount_sar);
  IF (SELECT sum(debit_sar) FROM journal_lines WHERE journal_entry_id=v_entry_id)
     <> (SELECT sum(credit_sar) FROM journal_lines WHERE journal_entry_id=v_entry_id) THEN
    RAISE EXCEPTION 'unbalanced_opening_entry';
  END IF;
  UPDATE journal_entries SET status='posted', posted_at=now() WHERE id=v_entry_id;
  RETURN v_entry_id;
END $$;

-- نقطة اعتماد عامة: لا يسمح بترحيل قيد غير متوازن.
CREATE OR REPLACE FUNCTION post_journal_entry(p_entry_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_debit numeric(19,4); v_credit numeric(19,4); v_status ledger_status;
BEGIN
  SELECT status INTO v_status FROM journal_entries WHERE id=p_entry_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'journal_entry_not_found'; END IF;
  IF v_status <> 'draft' THEN RAISE EXCEPTION 'journal_entry_not_draft'; END IF;
  SELECT COALESCE(sum(debit_sar),0), COALESCE(sum(credit_sar),0)
    INTO v_debit,v_credit FROM journal_lines WHERE journal_entry_id=p_entry_id;
  IF v_debit <= 0 OR v_debit <> v_credit THEN RAISE EXCEPTION 'journal_entry_unbalanced'; END IF;
  UPDATE journal_entries SET status='posted', posted_at=now() WHERE id=p_entry_id;
END $$;

COMMENT ON TABLE account_opening_balances IS 'الرصيد الفعلي عند إضافة الحساب؛ لا يصنف كإيراد أو مصروف.';
COMMENT ON TABLE expense_shares IS 'لقطة ثابتة لحصص المستفيدين عند تسجيل المصروف؛ لا يعاد احتسابها عند تغير العضوية.';
COMMENT ON FUNCTION create_equal_expense_shares(uuid) IS 'ينشئ حصصاً متساوية بالهللة مع توزيع الباقي بترتيب UUID ثابت.';
