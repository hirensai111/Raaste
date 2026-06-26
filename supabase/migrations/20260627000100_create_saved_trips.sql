create extension if not exists pgcrypto;

create table if not exists public.saved_trips (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  guide_id text not null,
  destination_name text not null,
  destination_address text not null default '',
  dates text not null default '',
  people_count integer not null default 1 check (people_count > 0),
  image_url text not null default '',
  guide_json jsonb not null,
  status text not null default 'planned',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, guide_id)
);

alter table public.saved_trips enable row level security;

create policy "Users can read their saved trips"
on public.saved_trips
for select
using (auth.uid() = user_id);

create policy "Users can create their saved trips"
on public.saved_trips
for insert
with check (auth.uid() = user_id);

create policy "Users can update their saved trips"
on public.saved_trips
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "Users can delete their saved trips"
on public.saved_trips
for delete
using (auth.uid() = user_id);

create or replace function public.set_saved_trips_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_saved_trips_updated_at on public.saved_trips;

create trigger set_saved_trips_updated_at
before update on public.saved_trips
for each row
execute function public.set_saved_trips_updated_at();
