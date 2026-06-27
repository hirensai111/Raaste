create extension if not exists pgcrypto;

create table if not exists public.restaurants (
  id uuid primary key default gen_random_uuid(),
  destination_id uuid,
  destination_name text not null default '',
  name text not null,
  type text,
  cuisine text,
  speciality text,
  description text,
  known_for_since text,
  is_veg_only boolean default false,
  jain_available boolean default false,
  halal_certified boolean default false,
  vegan_options boolean default false,
  non_veg_available boolean default true,
  price_range text,
  price_for_two text,
  area text,
  landmark text,
  address text,
  distance_from_center text,
  google_maps_query text,
  lat decimal(10, 8),
  lng decimal(11, 8),
  cash_only boolean default false,
  upi_accepted boolean default true,
  reservation_required boolean default false,
  reservation_note text,
  parking text,
  seating text,
  ac_available boolean default false,
  best_time_to_visit text,
  avoid_when text,
  wait_time_reality text,
  local_tip text,
  zomato_rating decimal(2, 1),
  google_rating decimal(2, 1),
  is_tourist_trap boolean default false,
  tourist_trap_detail text,
  best_for jsonb default '[]'::jsonb,
  signature_dishes jsonb default '[]'::jsonb,
  is_active boolean default true,
  is_verified boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index if not exists idx_restaurants_destination
on public.restaurants(destination_id);

create index if not exists idx_restaurants_destination_name
on public.restaurants(destination_name);

create index if not exists idx_restaurants_dietary
on public.restaurants(is_veg_only, jain_available, halal_certified, vegan_options);

create index if not exists idx_restaurants_active
on public.restaurants(is_active);

create table if not exists public.user_restaurant_saves (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  trip_id uuid references public.saved_trips(id) on delete cascade,
  saved_at timestamptz default now(),
  unique(user_id, restaurant_id, trip_id)
);

alter table public.restaurants enable row level security;
alter table public.user_restaurant_saves enable row level security;

create policy "Anyone can read active restaurants"
on public.restaurants
for select
using (is_active = true);

create policy "Users can read their restaurant saves"
on public.user_restaurant_saves
for select
using (auth.uid() = user_id);

create policy "Users can create their restaurant saves"
on public.user_restaurant_saves
for insert
with check (auth.uid() = user_id);

create policy "Users can delete their restaurant saves"
on public.user_restaurant_saves
for delete
using (auth.uid() = user_id);

create or replace function public.set_restaurants_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_restaurants_updated_at on public.restaurants;

create trigger set_restaurants_updated_at
before update on public.restaurants
for each row
execute function public.set_restaurants_updated_at();