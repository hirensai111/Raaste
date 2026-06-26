create extension if not exists pgcrypto;

create table if not exists public.trip_checklists (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.saved_trips(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  checklist_type text not null check (
    checklist_type in ('pre_trip', 'in_trip_daily', 'post_trip')
  ),
  checklist_date date not null,
  day_number integer check (day_number is null or day_number > 0),
  destination_name text not null default '',
  trip_dates text not null default '',
  content jsonb not null,
  generated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (trip_id, checklist_type, checklist_date)
);

create index if not exists trip_checklists_user_generated_idx
on public.trip_checklists (user_id, generated_at desc);

create index if not exists trip_checklists_trip_type_date_idx
on public.trip_checklists (trip_id, checklist_type, checklist_date);

alter table public.trip_checklists enable row level security;

create policy "Users can read their trip checklists"
on public.trip_checklists
for select
using (auth.uid() = user_id);

create policy "Users can create their trip checklists"
on public.trip_checklists
for insert
with check (auth.uid() = user_id);

create policy "Users can update their trip checklists"
on public.trip_checklists
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "Users can delete their trip checklists"
on public.trip_checklists
for delete
using (auth.uid() = user_id);

create or replace function public.set_trip_checklists_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_trip_checklists_updated_at on public.trip_checklists;

create trigger set_trip_checklists_updated_at
before update on public.trip_checklists
for each row
execute function public.set_trip_checklists_updated_at();
