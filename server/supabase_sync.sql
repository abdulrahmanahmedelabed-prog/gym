-- خادم المزامنة السحابية لنادي جيم (Supabase / PostgreSQL)
-- التنفيذ: supabase.com ← مشروع جديد (مجاني) ← SQL Editor ← الصق هذا الملف كاملاً ← Run.
-- ثم ضع Project URL و anon public key (Settings › API) في lib/core/vendor.dart (syncUrl, syncKey).
--
-- الأمان: الجداول مغلقة تماماً أمام التطبيق (RLS بدون سياسات)، والوصول فقط عبر الدوال أدناه
-- التي تتحقق من كلمة سر النادي (مخزنة كـ SHA-256 فقط). لكل نادٍ بياناته المعزولة.
-- آمن لإعادة التنفيذ (لتحديث الدوال).

create extension if not exists pgcrypto;

create table if not exists public.nadi_gyms (
  id          text primary key,
  secret_hash text not null,
  max_devices int  not null default 10,
  created_at  timestamptz not null default now()
);

create table if not exists public.nadi_devices (
  gym       text not null references public.nadi_gyms(id) on delete cascade,
  device    text not null,
  slot      int  not null,
  last_seen timestamptz not null default now(),
  primary key (gym, device)
);

create sequence if not exists public.nadi_seq;

-- سجل واحد لكل عنصر (عضو، فاتورة، دفعة...). data = null يعني محذوف.
create table if not exists public.nadi_records (
  gym  text   not null references public.nadi_gyms(id) on delete cascade,
  coll text   not null,
  id   text   not null,
  data jsonb,
  ts   bigint not null,             -- وقت التعديل (ساعة منطقية من الجهاز)
  dev  text   not null,             -- الجهاز الذي عدّله
  seq  bigint not null default nextval('public.nadi_seq'),  -- ترتيب الوصول للخادم
  primary key (gym, coll, id)
);
create index if not exists nadi_records_gym_seq on public.nadi_records (gym, seq);

alter table public.nadi_gyms    enable row level security;
alter table public.nadi_devices enable row level security;
alter table public.nadi_records enable row level security;
revoke all on public.nadi_gyms, public.nadi_devices, public.nadi_records from anon, authenticated;

-- التحقق من النادي وتسجيل الجهاز. يعيد (عدد الأجهزة النشطة، رقم هذا الجهاز)
create or replace function public.nadi_auth(p_gym text, p_secret text, p_device text, out devices int, out slot int)
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_variable
declare
  h text;
  lim int;
begin
  select secret_hash, max_devices into h, lim from nadi_gyms where id = p_gym;
  if h is null or h <> encode(digest(p_secret, 'sha256'), 'hex') then
    raise exception 'nadi_auth' using errcode = '28000';
  end if;
  update nadi_devices set last_seen = now() where gym = p_gym and device = p_device returning nadi_devices.slot into slot;
  if slot is null then
    perform pg_advisory_xact_lock(hashtext('nadi_dev:' || p_gym));
    select count(*) into devices from nadi_devices where gym = p_gym and last_seen > now() - interval '90 days';
    if devices >= lim then
      raise exception 'nadi_device_limit' using errcode = 'P0001';
    end if;
    select coalesce(max(d.slot), 0) + 1 into slot from nadi_devices d where d.gym = p_gym;
    insert into nadi_devices (gym, device, slot) values (p_gym, p_device, slot);
  end if;
  select count(*) into devices from nadi_devices where gym = p_gym and last_seen > now() - interval '90 days';
end $$;

create or replace function public.nadi_sync_register(p_gym text, p_secret text, p_device text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare a record;
begin
  if length(p_gym) < 8 or length(p_secret) < 20 then
    raise exception 'nadi_auth' using errcode = '28000';
  end if;
  insert into nadi_gyms (id, secret_hash) values (p_gym, encode(digest(p_secret, 'sha256'), 'hex'))
    on conflict (id) do nothing;
  select * into a from nadi_auth(p_gym, p_secret, p_device);
  return json_build_object('devices', a.devices, 'slot', a.slot);
end $$;

-- رفع التعديلات: يُحتفظ بالأحدث لكل سجل
create or replace function public.nadi_sync_push(p_gym text, p_secret text, p_device text, p_records jsonb)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare a record;
begin
  select * into a from nadi_auth(p_gym, p_secret, p_device);
  if jsonb_array_length(p_records) > 1000 then
    raise exception 'nadi_too_many';
  end if;
  -- رفع واحد في كل مرة للنادي نفسه حتى تبقى أرقام الترتيب متسلسلة لمن يجلب
  perform pg_advisory_xact_lock(hashtext('nadi:' || p_gym));
  insert into nadi_records (gym, coll, id, data, ts, dev)
  select p_gym, r->>'c', r->>'i', nullif(r->'d', 'null'::jsonb), (r->>'t')::bigint, p_device
  from jsonb_array_elements(p_records) r
  on conflict (gym, coll, id) do update
    set data = excluded.data, ts = excluded.ts, dev = excluded.dev, seq = nextval('public.nadi_seq')
    where nadi_records.ts < excluded.ts
       or (nadi_records.ts = excluded.ts and nadi_records.dev < excluded.dev);
  return json_build_object('devices', a.devices);
end $$;

-- جلب ما تغيّر بعد المؤشر
create or replace function public.nadi_sync_pull(p_gym text, p_secret text, p_device text, p_since bigint, p_limit int)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  a record;
  recs json;
begin
  select * into a from nadi_auth(p_gym, p_secret, p_device);
  -- ينتظر انتهاء أي رفع جارٍ لهذا النادي فلا يفوته سجل
  perform pg_advisory_xact_lock_shared(hashtext('nadi:' || p_gym));
  select coalesce(json_agg(json_build_object('c', x.coll, 'i', x.id, 'd', x.data, 't', x.ts, 'v', x.dev, 's', x.seq) order by x.seq), '[]'::json)
    into recs
  from (
    select coll, id, data, ts, dev, seq from nadi_records
    where gym = p_gym and seq > p_since
    order by seq
    limit least(greatest(p_limit, 1), 1000)
  ) x;
  return json_build_object('devices', a.devices, 'records', recs);
end $$;

revoke all on function public.nadi_auth(text, text, text) from public, anon, authenticated;
grant execute on function public.nadi_sync_register(text, text, text) to anon;
grant execute on function public.nadi_sync_push(text, text, text, jsonb) to anon;
grant execute on function public.nadi_sync_pull(text, text, text, bigint, int) to anon;

-- اختياري: حذف نادٍ وكل بياناته من السحابة
-- delete from public.nadi_gyms where id = '...';
