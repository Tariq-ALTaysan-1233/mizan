-- ميزان: تأسيس المخطط المالي الأولي لـ PostgreSQL
-- جميع المبالغ محفوظة بدقة عشرية. العملة الأساسية SAR.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE record_status AS ENUM ('active','inactive','deleted');
CREATE TYPE account_type AS ENUM ('bank','cash','wallet','prepaid_card');
CREATE TYPE expense_status AS ENUM ('draft','approved','partially_paid','paid','voided');
CREATE TYPE payment_status AS ENUM ('pending','posted','reversed');
CREATE TYPE ledger_status AS ENUM ('draft','posted','reversed');
CREATE TYPE membership_status AS ENUM ('pending','active','leave_requested','left','removed');

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name varchar(160) NOT NULL,
  email varchar(320) UNIQUE NOT NULL,
  password_hash text NOT NULL,
  status record_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id),
  display_name varchar(120) NOT NULL,
  avatar_key text,
  status record_status NOT NULL DEFAULT 'active',
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX profiles_user_idx ON profiles(user_id);
CREATE TABLE groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name varchar(160) NOT NULL,
  owner_profile_id uuid NOT NULL REFERENCES profiles(id),
  base_currency char(3) NOT NULL DEFAULT 'SAR' CHECK (base_currency='SAR'),
  status record_status NOT NULL DEFAULT 'active', created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE group_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), group_id uuid NOT NULL REFERENCES groups(id),
  profile_id uuid NOT NULL REFERENCES profiles(id), role varchar(40) NOT NULL DEFAULT 'member',
  status membership_status NOT NULL DEFAULT 'pending', joined_at timestamptz, left_at timestamptz,
  UNIQUE(group_id, profile_id)
);
CREATE TABLE profile_shares (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), owner_profile_id uuid NOT NULL REFERENCES profiles(id),
  target_profile_id uuid NOT NULL REFERENCES profiles(id), can_view boolean NOT NULL DEFAULT true,
  can_use_shared_accounts boolean NOT NULL DEFAULT false, status record_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(), CHECK(owner_profile_id <> target_profile_id),
  UNIQUE(owner_profile_id,target_profile_id)
);
CREATE TABLE categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), group_id uuid REFERENCES groups(id),
  parent_id uuid REFERENCES categories(id), name varchar(100) NOT NULL,
  color varchar(20), icon varchar(60), status record_status NOT NULL DEFAULT 'active'
);
CREATE TABLE accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), profile_id uuid NOT NULL REFERENCES profiles(id),
  name varchar(120) NOT NULL, type account_type NOT NULL, currency_code char(3) NOT NULL DEFAULT 'SAR',
  status record_status NOT NULL DEFAULT 'active', created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE account_opening_balances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), account_id uuid NOT NULL UNIQUE REFERENCES accounts(id),
  amount_original numeric(19,4) NOT NULL CHECK(amount_original >= 0), currency_code char(3) NOT NULL,
  exchange_rate_to_sar numeric(19,8) NOT NULL CHECK(exchange_rate_to_sar > 0),
  amount_sar numeric(19,4) NOT NULL CHECK(amount_sar >= 0), opening_date date NOT NULL,
  source_note text, created_by uuid NOT NULL REFERENCES users(id), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE account_access_grants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), account_id uuid NOT NULL REFERENCES accounts(id),
  profile_id uuid NOT NULL REFERENCES profiles(id), can_view boolean NOT NULL DEFAULT true,
  can_use_for_payment boolean NOT NULL DEFAULT false, granted_by uuid NOT NULL REFERENCES profiles(id),
  status record_status NOT NULL DEFAULT 'active', UNIQUE(account_id,profile_id)
);
CREATE TABLE payment_methods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), account_id uuid NOT NULL REFERENCES accounts(id),
  name varchar(100) NOT NULL, method_type varchar(40) NOT NULL, last_four_digits char(4),
  status record_status NOT NULL DEFAULT 'active'
);
CREATE TABLE exchange_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), currency_code char(3) NOT NULL,
  rate_to_sar numeric(19,8) NOT NULL CHECK(rate_to_sar > 0), rate_date date NOT NULL,
  source varchar(100) NOT NULL, is_manual boolean NOT NULL DEFAULT false,
  created_by uuid REFERENCES users(id), UNIQUE(currency_code,rate_date,source)
);
CREATE TABLE expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), group_id uuid NOT NULL REFERENCES groups(id),
  created_by_profile_id uuid NOT NULL REFERENCES profiles(id), description varchar(500) NOT NULL,
  category_id uuid REFERENCES categories(id), merchant_name varchar(180), purchase_date date NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(), total_original numeric(19,4) NOT NULL CHECK(total_original >= 0),
  currency_code char(3) NOT NULL DEFAULT 'SAR', exchange_rate_to_sar numeric(19,8) NOT NULL DEFAULT 1,
  total_sar numeric(19,4) NOT NULL CHECK(total_sar >= 0), status expense_status NOT NULL DEFAULT 'draft',
  source_type varchar(30) NOT NULL DEFAULT 'manual', deleted_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX expenses_group_date_idx ON expenses(group_id,purchase_date DESC);
CREATE TABLE expense_shares (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), expense_id uuid NOT NULL REFERENCES expenses(id),
  profile_id uuid NOT NULL REFERENCES profiles(id), share_amount_sar numeric(19,4) NOT NULL CHECK(share_amount_sar >= 0),
  share_amount_original numeric(19,4), share_version integer NOT NULL DEFAULT 1,
  UNIQUE(expense_id,profile_id,share_version)
);
CREATE TABLE expense_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), expense_id uuid NOT NULL REFERENCES expenses(id),
  payer_profile_id uuid NOT NULL REFERENCES profiles(id), account_id uuid NOT NULL REFERENCES accounts(id),
  payment_method_id uuid REFERENCES payment_methods(id), amount_original numeric(19,4) NOT NULL CHECK(amount_original > 0),
  currency_code char(3) NOT NULL, amount_sar numeric(19,4) NOT NULL CHECK(amount_sar > 0),
  payment_date timestamptz NOT NULL, status payment_status NOT NULL DEFAULT 'pending', created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE payment_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), payment_id uuid NOT NULL REFERENCES expense_payments(id),
  expense_id uuid NOT NULL REFERENCES expenses(id), allocated_amount_sar numeric(19,4) NOT NULL CHECK(allocated_amount_sar > 0)
);
CREATE TABLE journal_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), group_id uuid REFERENCES groups(id),
  entry_date date NOT NULL, description varchar(500) NOT NULL, source_type varchar(50) NOT NULL,
  source_id uuid, status ledger_status NOT NULL DEFAULT 'draft', reverses_entry_id uuid REFERENCES journal_entries(id),
  created_by uuid NOT NULL REFERENCES users(id), posted_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE ledger_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), group_id uuid REFERENCES groups(id),
  profile_id uuid REFERENCES profiles(id), code varchar(40) NOT NULL, name varchar(160) NOT NULL,
  account_class varchar(30) NOT NULL, UNIQUE(group_id,profile_id,code)
);
CREATE TABLE journal_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), journal_entry_id uuid NOT NULL REFERENCES journal_entries(id),
  ledger_account_id uuid NOT NULL REFERENCES ledger_accounts(id), debit_sar numeric(19,4) NOT NULL DEFAULT 0 CHECK(debit_sar >= 0),
  credit_sar numeric(19,4) NOT NULL DEFAULT 0 CHECK(credit_sar >= 0),
  CHECK ((debit_sar = 0) <> (credit_sar = 0))
);
CREATE TABLE settlements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), group_id uuid NOT NULL REFERENCES groups(id),
  from_profile_id uuid NOT NULL REFERENCES profiles(id), to_profile_id uuid NOT NULL REFERENCES profiles(id),
  amount_sar numeric(19,4) NOT NULL CHECK(amount_sar > 0), status varchar(30) NOT NULL DEFAULT 'proposed',
  created_at timestamptz NOT NULL DEFAULT now(), CHECK(from_profile_id <> to_profile_id)
);
CREATE TABLE settlement_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), settlement_id uuid NOT NULL REFERENCES settlements(id),
  payer_profile_id uuid NOT NULL REFERENCES profiles(id), receiver_profile_id uuid NOT NULL REFERENCES profiles(id),
  amount_sar numeric(19,4) NOT NULL CHECK(amount_sar > 0), paid_at timestamptz,
  status payment_status NOT NULL DEFAULT 'pending'
);
CREATE TABLE stocktakes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), profile_id uuid NOT NULL REFERENCES profiles(id),
  group_id uuid REFERENCES groups(id), stocktake_type varchar(20) NOT NULL CHECK(stocktake_type IN ('daily','monthly','manual')),
  stocktake_date date NOT NULL, status varchar(30) NOT NULL DEFAULT 'draft', created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE stocktake_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), stocktake_id uuid NOT NULL REFERENCES stocktakes(id),
  account_id uuid NOT NULL REFERENCES accounts(id), system_balance_sar numeric(19,4) NOT NULL,
  actual_balance_sar numeric(19,4) NOT NULL, difference_sar numeric(19,4) NOT NULL
);
CREATE TABLE attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), storage_key text NOT NULL UNIQUE, file_name text NOT NULL,
  mime_type varchar(120) NOT NULL, size_bytes bigint NOT NULL CHECK(size_bytes >= 0),
  uploaded_by uuid NOT NULL REFERENCES users(id), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE attachment_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), attachment_id uuid NOT NULL REFERENCES attachments(id),
  entity_type varchar(50) NOT NULL, entity_id uuid NOT NULL
);
CREATE TABLE audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid REFERENCES users(id), profile_id uuid REFERENCES profiles(id),
  action varchar(80) NOT NULL, entity_type varchar(60) NOT NULL, entity_id uuid,
  before_data jsonb, after_data jsonb, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE recycle_bin (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), entity_type varchar(60) NOT NULL, entity_id uuid NOT NULL,
  deleted_by uuid NOT NULL REFERENCES users(id), deleted_at timestamptz NOT NULL DEFAULT now(), snapshot jsonb NOT NULL,
  restored_at timestamptz, restored_by uuid REFERENCES users(id)
);
CREATE TABLE sync_conflicts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), entity_type varchar(60) NOT NULL, entity_id uuid NOT NULL,
  version_a jsonb NOT NULL, version_b jsonb NOT NULL, resolution_status varchar(30) NOT NULL DEFAULT 'pending',
  resolved_by uuid REFERENCES users(id), resolved_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE backup_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), backup_type varchar(30) NOT NULL,
  storage_key text, status varchar(30) NOT NULL, started_at timestamptz NOT NULL,
  completed_at timestamptz, error_message text
);

-- ملاحظة: يجب ترحيل القيود من خلال خدمة مالية داخل معاملة قاعدة بيانات،
-- والتحقق من تساوي مجموع المدين والدائن قبل تحويل القيد إلى posted.
