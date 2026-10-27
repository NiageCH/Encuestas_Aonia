-- Registro de descargas (decisión del 27/10/2026): cada PDF, CSV o ZIP que sale de la plataforma queda en el registro de
-- actividad con un código único, que va impreso en el pie de cada página del PDF y en la cabecera del CSV. Así, un
-- documento que aparezca fuera del Colegio se puede atribuir a una descarga concreta: quién, cuándo, de qué y con qué
-- filtros.
--
-- 1. registrar_descarga: la web la llama justo antes de crear el archivo, cuando ya tiene los datos (que salen de las
--    RPC de siempre, con sus permisos). El servidor pone el código, el nombre de quien descarga y la hora, y devuelve las
--    tres cosas para imprimirlas. En un ZIP, un código por informe y otro para el ZIP.
-- 2. Las descargas son entradas del registro de actividad con la acción «descarga». No se pueden cambiar ni borrar:
--    authenticated no tiene permisos de escritura sobre la tabla y un trigger lo impide también a cualquier otro rol.
--    Lo único que se permite es lo que ya hacía eliminar una cuenta: guardar su nombre y correo y dejar el usuario a nulo.
-- 3. admin_descargas: la pestaña «Descargas» de Accesos, con filtros y búsqueda por código. Solo administración.
-- 4. admin_registro (la actividad) deja fuera las descargas, que tienen su propia pestaña.

create unique index registro_descarga_codigo on public.registro_actividad ((detalle ->> 'codigo')) where accion = 'descarga';

/** Código de descarga: 8 caracteres sin los que se confunden (0/O, 1/I/L), en dos grupos: «7KQ2-M9XD». */
create function privado.codigo_descarga() returns text
language plpgsql volatile set search_path = '' as $$
declare
  a constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  b bytea := extensions.gen_random_bytes(8);
  r text := '';
begin
  for i in 0 .. 7 loop
    r := r || substr(a, 1 + get_byte(b, i) % length(a), 1);
    if i = 3 then r := r || '-'; end if;
  end loop;
  return r;
end $$;

/** Un código que no esté ya en el registro (y que no se repita dentro de la misma petición). */
create function privado.codigo_descarga_libre(p_usados text[] default '{}') returns text
language plpgsql volatile security definer set search_path = '' as $$
declare v text;
begin
  loop
    v := privado.codigo_descarga();
    exit when not v = any(p_usados) and not exists (
      select 1 from public.registro_actividad r
      where r.accion = 'descarga' and (r.detalle ->> 'codigo' = v or r.detalle -> 'informes' @> jsonb_build_array(jsonb_build_object('codigo', v))));
  end loop;
  return v;
end $$;

create function public.registrar_descarga(p_tipo text, p_datos jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_perfil public.usuario_perfil := permisos.exigir();
  v_datos jsonb := coalesce(p_datos, '{}');
  v_codigo text;
  v_usados text[] := '{}';
  v_informes jsonb := '[]';
  v_fecha timestamptz := now();
  x jsonb;
begin
  if p_tipo is null or p_tipo not in ('informe_profesor', 'informe_jefatura', 'informe_equipo', 'informe_direccion', 'vista_pdf', 'csv', 'zip') then
    raise exception 'Tipo de descarga no válido' using errcode = '22023';
  end if;
  if jsonb_typeof(v_datos) <> 'object' or length(v_datos::text) > 60000
     or (v_datos ? 'filtros' and jsonb_typeof(v_datos -> 'filtros') <> 'object')
     or coalesce(btrim(v_datos ->> 'objeto'), '') = '' or length(v_datos ->> 'objeto') > 300 then
    raise exception 'Datos de la descarga no válidos' using errcode = '22023';
  end if;
  -- Lo que cada rol puede descargar (los datos ya los ha filtrado la RPC de cada informe o vista).
  if v_perfil.rol = 'coordinacion' and p_tipo in ('informe_jefatura', 'informe_equipo', 'informe_direccion') then
    raise exception 'Sin acceso a los informes de responsables' using errcode = '42501';
  end if;
  if p_tipo in ('vista_pdf', 'csv') then
    if coalesce(v_datos ->> 'vista', '') not in ('inicio', 'alumnos', 'familias', 'personal', 'descargas') then
      raise exception 'Vista de exportación no válida' using errcode = '22023';
    end if;
    if v_datos ->> 'vista' = 'personal' and v_perfil.rol = 'coordinacion' then
      raise exception 'Sin acceso a los resultados de personal' using errcode = '42501';
    end if;
    if v_datos ->> 'vista' = 'descargas' and v_perfil.rol <> 'administrador' then
      raise exception 'Solo para administración' using errcode = '42501';
    end if;
  end if;
  if p_tipo = 'zip' then
    if coalesce(jsonb_typeof(v_datos -> 'informes'), '') <> 'array' or jsonb_array_length(v_datos -> 'informes') = 0
       or jsonb_array_length(v_datos -> 'informes') > 500 then
      raise exception 'Un ZIP necesita la lista de sus informes' using errcode = '22023';
    end if;
    for x in select * from jsonb_array_elements(v_datos -> 'informes') loop
      if jsonb_typeof(x) <> 'object' or coalesce(btrim(x ->> 'objeto'), '') = '' then
        raise exception 'Datos de la descarga no válidos' using errcode = '22023';
      end if;
      v_codigo := privado.codigo_descarga_libre(v_usados);
      v_usados := v_usados || v_codigo;
      v_informes := v_informes || jsonb_build_object('objeto', x ->> 'objeto', 'docente', x -> 'docente', 'codigo', v_codigo);
    end loop;
  end if;
  v_codigo := privado.codigo_descarga_libre(v_usados);

  perform privado.registrar('descarga', jsonb_strip_nulls(jsonb_build_object(
    'codigo', v_codigo, 'tipo', p_tipo, 'curso', v_datos ->> 'curso', 'objeto', btrim(v_datos ->> 'objeto'),
    'docente', v_datos -> 'docente', 'persona', v_datos -> 'persona', 'tramos', v_datos -> 'tramos', 'vista', v_datos ->> 'vista',
    'filtros', nullif(coalesce(v_datos -> 'filtros', '{}'), '{}'), 'archivo', v_datos ->> 'archivo',
    'informes', case when p_tipo = 'zip' then v_informes end,
    'nombre', v_perfil.nombre)));
  return jsonb_build_object('codigo', v_codigo, 'nombre', v_perfil.nombre, 'fecha', v_fecha, 'informes', v_informes);
end $$;

-- Las descargas no se cambian ni se borran ------------------------------------------------------------------------------
create function privado.descarga_inalterable() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    if old.accion = 'descarga' then
      raise exception 'El registro de descargas no se puede borrar' using errcode = '42501';
    end if;
    return old;
  end if;
  if (old.accion = 'descarga' or new.accion = 'descarga')
     and (new.accion, new.detalle, new.fecha) is distinct from (old.accion, old.detalle, old.fecha) then
    raise exception 'El registro de descargas no se puede cambiar' using errcode = '42501';
  end if;
  return new;
end $$;

create trigger descarga_inalterable before update or delete on public.registro_actividad
  for each row execute function privado.descarga_inalterable();
-- Y nadie de la API puede escribir en la tabla (ya era así; se deja explícito).
revoke insert, update, delete, truncate on public.registro_actividad from anon, authenticated;

-- Pestaña «Descargas» ---------------------------------------------------------------------------------------------------
/** Texto para buscar sin mayúsculas ni acentos. */
create function privado.plano(p text) returns text
language sql immutable set search_path = '' as $$
  select translate(lower(coalesce(p, '')), 'áéíóúüàèìòùâêîôûäëïöñç', 'aeiouuaeiouaeiouaeionc')
$$;

/** Descargas, de la más reciente a la más antigua, con filtros: persona (id de la cuenta), tipo, desde y hasta (fechas,
 *  hora de Madrid), objeto (de quién o de qué vista, también dentro de un ZIP) y código (también el de cada informe de
 *  un ZIP). Hasta 1000 filas; total dice cuántas hay con esos filtros. */
create function public.admin_descargas(p_filtros jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  f jsonb := coalesce(p_filtros, '{}');
  v_codigo text := upper(btrim(coalesce(f ->> 'codigo', '')));
  v_objeto text := privado.plano(btrim(coalesce(f ->> 'objeto', '')));
  v jsonb;
begin
  perform privado.exigir_admin();
  with d as (
    select r.*, coalesce(p.nombre, r.usuario_nombre, r.detalle ->> 'nombre') as persona, coalesce(u.email, r.usuario_correo) as correo
    from public.registro_actividad r
    left join public.usuario_perfil p on p.id = r.usuario_id left join auth.users u on u.id = r.usuario_id
    where r.accion = 'descarga'
      and (f ->> 'persona' is null or r.usuario_id = (f ->> 'persona')::uuid)
      and (f ->> 'tipo' is null or r.detalle ->> 'tipo' = f ->> 'tipo')
      and (f ->> 'desde' is null or r.fecha >= ((f ->> 'desde')::date)::timestamp at time zone 'Europe/Madrid')
      and (f ->> 'hasta' is null or r.fecha < ((f ->> 'hasta')::date + 1)::timestamp at time zone 'Europe/Madrid')
      and (v_codigo = '' or r.detalle ->> 'codigo' = v_codigo
           or r.detalle -> 'informes' @> jsonb_build_array(jsonb_build_object('codigo', v_codigo)))
      and (v_objeto = '' or privado.plano(r.detalle ->> 'objeto') like '%' || v_objeto || '%'
           or exists (select 1 from jsonb_array_elements(coalesce(r.detalle -> 'informes', '[]')) i
                      where privado.plano(i ->> 'objeto') like '%' || v_objeto || '%')))
  select jsonb_build_object(
    'total', (select count(*) from d),
    'filas', coalesce((select jsonb_agg(x.fila order by x.fecha desc) from (
       select d.fecha, jsonb_build_object('fecha', d.fecha, 'usuario_id', d.usuario_id, 'persona', d.persona, 'correo', d.correo)
                       || (d.detalle - 'nombre') as fila
       from d order by d.fecha desc limit 1000) x), '[]')) into v;
  -- Para el filtro de persona: quien ha descargado algo alguna vez.
  return v || jsonb_build_object('personas', coalesce((select jsonb_agg(jsonb_build_object('id', q.usuario_id, 'nombre', q.nombre) order by q.nombre) from (
      select distinct on (r.usuario_id) r.usuario_id, coalesce(p.nombre, r.usuario_nombre, r.detalle ->> 'nombre') as nombre
      from public.registro_actividad r left join public.usuario_perfil p on p.id = r.usuario_id
      where r.accion = 'descarga' and r.usuario_id is not null order by r.usuario_id, r.fecha desc) q), '[]'));
end $$;

-- La actividad deja fuera las descargas, que tienen su pestaña.
create or replace function public.admin_registro(p_limite integer default 200)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_admin();
  return coalesce((
    select jsonb_agg(x order by x.fecha desc)
    from (
      select r.fecha, r.accion, r.detalle,
             coalesce(p.nombre, r.usuario_nombre, u.email, '(acceso eliminado)') as usuario,
             r.usuario_id is null as usuario_eliminado
      from public.registro_actividad r
      left join public.usuario_perfil p on p.id = r.usuario_id
      left join auth.users u on u.id = r.usuario_id
      where r.accion <> 'descarga'
      order by r.fecha desc
      limit least(greatest(p_limite, 1), 1000)
    ) x
  ), '[]');
end $$;

revoke execute on function privado.codigo_descarga(), privado.codigo_descarga_libre(text[]), privado.plano(text) from public, anon, authenticated;
revoke execute on function public.registrar_descarga(text, jsonb), public.admin_descargas(jsonb) from public, anon;
grant execute on function public.registrar_descarga(text, jsonb), public.admin_descargas(jsonb) to authenticated;
