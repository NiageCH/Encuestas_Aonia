-- Respuestas abiertas (especificación §7.9, criterio confirmado por Mark): se cargan tal cual y solo las ven Dirección y
-- administración, nunca la coordinación ni los informes del profesorado.
--
-- Cada respuesta abierta va suelta, sin enlace con la respuesta cerrada de la misma persona (no hay respuesta_id): solo
-- su pregunta y lo que hace falta para los filtros del colectivo (grupo en alumnado, etapas en familias, docente o no y
-- antigüedad en personal). Identificador aleatorio y carga en orden aleatorio (etl/cargar_abiertas_2526.py).
-- Cada consulta queda en el registro de actividad; cada exportación, en el registro de descargas, con su código.

create table public.pregunta_abierta (
  id               serial primary key,
  cuestionario_id  integer not null references public.cuestionario (id) on delete cascade,
  orden            smallint not null,
  -- La misma pregunta en varios cuestionarios: echa_en_falta, comentario, igualdad_necesidades...
  codigo           text not null check (codigo ~ '^[a-z_]+$'),
  texto            text not null,
  nota             text,
  unique (cuestionario_id, orden)
);

alter table public.pregunta_abierta enable row level security;
-- Sin políticas: solo se lee a través de las RPC de abajo.
revoke all on public.pregunta_abierta from anon, authenticated;

create table privado.respuesta_abierta (
  id           bigint primary key default privado.id_aleatorio(),
  pregunta_id  integer not null references public.pregunta_abierta (id) on delete cascade,
  grupo_id     integer references public.grupo (id),
  etapas       text[] not null default '{}',
  docente      boolean,
  antiguedad   text check (antiguedad in ('primer_ano', 'mas_de_un_ano')),
  texto        text not null check (btrim(texto) <> '')
);

create index on privado.respuesta_abierta (pregunta_id);

-- Solo Dirección y administración.
create or replace function privado.exigir_abiertas() returns public.usuario_perfil
language plpgsql stable security definer set search_path = '' as $$
declare
  v_perfil public.usuario_perfil := permisos.exigir();
begin
  if v_perfil.rol not in ('direccion', 'administrador') then
    raise exception 'Las respuestas abiertas solo las ven Dirección y administración' using errcode = '42501';
  end if;
  return v_perfil;
end $$;

revoke execute on function privado.exigir_abiertas() from public, anon, authenticated;

-- Preguntas abiertas del curso con su número de respuestas, para elegir en la pantalla. No enseña ningún texto de
-- respuesta, así que no se anota.
create or replace function public.abiertas_preguntas(p_curso text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_abiertas();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', pa.id, 'colectivo', c.colectivo, 'cuestionario', c.codigo, 'cuestionario_titulo', c.titulo, 'etapa', c.etapa,
             'codigo', pa.codigo, 'texto', pa.texto, 'nota', pa.nota,
             'n', (select count(*) from privado.respuesta_abierta ra where ra.pregunta_id = pa.id))
           order by c.colectivo, c.id, pa.orden)
    from public.pregunta_abierta pa
    join public.cuestionario c on c.id = pa.cuestionario_id
    join public.curso cu on cu.id = c.curso_id
    where cu.nombre = p_curso), '[]');
end $$;

revoke execute on function public.abiertas_preguntas(text) from public, anon;
grant execute on function public.abiertas_preguntas(text) to authenticated;

-- Respuestas de una pregunta (por su código, en todos los cuestionarios del colectivo que la tienen), con los filtros
-- del colectivo:
--   alumnos:  etapa, cuestionario, grupo
--   familias: etapa (una familia cuenta en cada etapa que marcó)
--   personal: docente (true o false) o antigüedad, de uno en uno, como en la vista de personal
-- Devuelve los textos tal cual, en orden aleatorio, sin nada que los enlace con otras respuestas. Queda en el registro.
create or replace function public.abiertas(p_filtro jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_perfil  public.usuario_perfil := privado.exigir_abiertas();
  v_f       jsonb := coalesce(p_filtro, '{}');
  v_col     text := v_f ->> 'colectivo';
  v_curso   smallint := (select id from public.curso where nombre = v_f ->> 'curso');
  v_validos text[];
  v_resp    jsonb;
  v_preg    jsonb;
  v_n       integer;
  k         text;
begin
  if v_curso is null then
    raise exception 'Curso no encontrado' using errcode = 'P0002';
  end if;
  if v_col is null or v_col not in ('alumnos', 'familias', 'personal') then
    raise exception 'Colectivo no válido' using errcode = '22023';
  end if;
  if coalesce(v_f ->> 'pregunta', '') !~ '^[a-z_]+$' then
    raise exception 'Pregunta no válida' using errcode = '22023';
  end if;
  v_validos := case v_col
    when 'alumnos' then array['curso', 'colectivo', 'pregunta', 'etapa', 'cuestionario', 'grupo']
    when 'familias' then array['curso', 'colectivo', 'pregunta', 'etapa']
    else array['curso', 'colectivo', 'pregunta', 'docente', 'antiguedad'] end;
  for k in select jsonb_object_keys(v_f) loop
    if not k = any(v_validos) then
      raise exception 'Filtro no válido para %: %', v_col, k using errcode = '22023';
    end if;
  end loop;
  if v_f ? 'docente' and v_f ? 'antiguedad' then
    raise exception 'Los filtros de personal no se combinan: usa uno a la vez' using errcode = '22023';
  end if;
  if v_f ? 'docente' and jsonb_typeof(v_f -> 'docente') <> 'boolean' then
    raise exception 'Filtro docente no válido' using errcode = '22023';
  end if;

  select jsonb_agg(jsonb_build_object('cuestionario', c.codigo, 'cuestionario_titulo', c.titulo, 'texto', pa.texto, 'nota', pa.nota)
                   order by c.id)
    into v_preg
  from public.pregunta_abierta pa
  join public.cuestionario c on c.id = pa.cuestionario_id
  where c.curso_id = v_curso and c.colectivo = v_col and pa.codigo = v_f ->> 'pregunta'
    and (not v_f ? 'etapa' or v_col <> 'alumnos' or c.etapa = v_f ->> 'etapa')
    and (not v_f ? 'cuestionario' or c.codigo = v_f ->> 'cuestionario');
  if v_preg is null then
    raise exception 'No hay respuestas abiertas para este filtro' using errcode = 'P0002';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('texto', ra.texto, 'cuestionario', c.codigo) order by ra.id), '[]'), count(*)
    into v_resp, v_n
  from privado.respuesta_abierta ra
  join public.pregunta_abierta pa on pa.id = ra.pregunta_id
  join public.cuestionario c on c.id = pa.cuestionario_id
  left join public.grupo g on g.id = ra.grupo_id
  where c.curso_id = v_curso and c.colectivo = v_col and pa.codigo = v_f ->> 'pregunta'
    and (not v_f ? 'cuestionario' or c.codigo = v_f ->> 'cuestionario')
    and (not v_f ? 'etapa' or (case when v_col = 'alumnos' then c.etapa = v_f ->> 'etapa' else v_f ->> 'etapa' = any(ra.etapas) end))
    and (not v_f ? 'grupo' or g.nombre = v_f ->> 'grupo')
    and (not v_f ? 'docente' or ra.docente = (v_f ->> 'docente')::boolean)
    and (not v_f ? 'antiguedad' or ra.antiguedad = v_f ->> 'antiguedad');

  perform privado.registrar('abiertas_consulta', jsonb_build_object('filtro', v_f - 'curso', 'curso', v_f ->> 'curso', 'n', v_n));
  return jsonb_build_object('preguntas', v_preg, 'n', v_n, 'respuestas', v_resp);
end $$;

revoke execute on function public.abiertas(jsonb) from public, anon;
grant execute on function public.abiertas(jsonb) to authenticated;

-- Grupos con respuestas abiertas de un cuestionario (para el filtro de grupo), sin cifras.
create or replace function public.abiertas_grupos(p_curso text, p_cuestionario text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_abiertas();
  return coalesce((
    select jsonb_agg(distinct g.nombre order by g.nombre)
    from privado.respuesta_abierta ra
    join public.pregunta_abierta pa on pa.id = ra.pregunta_id
    join public.cuestionario c on c.id = pa.cuestionario_id
    join public.curso cu on cu.id = c.curso_id
    join public.grupo g on g.id = ra.grupo_id
    where cu.nombre = p_curso and c.codigo = p_cuestionario), '[]');
end $$;

revoke execute on function public.abiertas_grupos(text, text) from public, anon;
grant execute on function public.abiertas_grupos(text, text) to authenticated;

-- Registro de descargas: la exportación de respuestas abiertas (CSV o PDF), solo Dirección y administración, y la
-- versión del informe del profesor/a (completa o docente, §5.0).
create or replace function public.registrar_descarga(p_tipo text, p_datos jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
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
    if coalesce(v_datos ->> 'vista', '') not in ('inicio', 'alumnos', 'familias', 'personal', 'descargas', 'abiertas') then
      raise exception 'Vista de exportación no válida' using errcode = '22023';
    end if;
    if v_datos ->> 'vista' = 'personal' and v_perfil.rol = 'coordinacion' then
      raise exception 'Sin acceso a los resultados de personal' using errcode = '42501';
    end if;
    if v_datos ->> 'vista' = 'abiertas' and v_perfil.rol not in ('direccion', 'administrador') then
      raise exception 'Las respuestas abiertas solo las ven Dirección y administración' using errcode = '42501';
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
    'version', case when v_datos ->> 'version' in ('completa', 'docente') then v_datos ->> 'version' end,
    'informes', case when p_tipo = 'zip' then v_informes end,
    'nombre', v_perfil.nombre)));
  return jsonb_build_object('codigo', v_codigo, 'nombre', v_perfil.nombre, 'fecha', v_fecha, 'informes', v_informes);
end $$;


