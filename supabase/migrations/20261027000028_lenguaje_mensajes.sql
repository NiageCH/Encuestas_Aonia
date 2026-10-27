-- Revisión de lenguaje de Aonia (docs/GLOSARIO.md): mensajes de error y avisos del servidor con los términos aprobados
-- (alumnado, profesorado, profesor/a, administración, accesos, jefatura, Colegio con mayúscula).
--
-- Solo cambia el texto de los mensajes, nunca la lógica: sustituye cada mensaje completo, con sus comillas, en las
-- funciones de public, privado y permisos que lo contienen, y vuelve a crear esas funciones con el mismo cuerpo. Con las
-- comillas la sustitución no puede tocar códigos como 'alumnos' (colectivo) ni repetirse si se aplica dos veces.
-- La misma lista se aplica en fase2 (migración 20261028000036) a las funciones que la Fase 2 vuelve a crear.

do $$
declare
  cambios constant text[][] := array[
    ['''Sin acceso a este profesor''', '''Sin acceso a este profesor/a'''],
    ['''Profesor o curso no encontrado''', '''Profesor/a o curso no encontrado'''],
    ['''La referencia del colegio es solo el total de familias, sin filtros ni repartos''', '''La referencia del Colegio es solo el total de familias, sin filtros ni repartos'''],
    ['''Alumnos: el grupo «%s» no existe en el curso''', '''Alumnado: el grupo «%s» no existe en el curso'''],
    ['''Alumnos de %s: «%s» no es un número válido''', '''Alumnado de %s: «%s» no es un número válido'''],
    ['''Usuario no encontrado''', '''Acceso no encontrado'''],
    ['''Una encuesta de alumnos necesita su etapa''', '''Una encuesta del alumnado necesita su etapa'''],
    ['''Los segmentos de personal no aplican a alumnos''', '''Los segmentos de personal no se aplican al alumnado'''],
    ['''Jefe de departamento no encontrado''', '''Jefatura de departamento no encontrada'''],
    ['''El número de alumnos debe ser un número de 0 a 999''', '''El alumnado del grupo debe ser un número de 0 a 999'''],
    ['''El grupo «%s» no existe en el curso y no es de ningún nivel con encuesta de alumnos''', '''El grupo «%s» no existe en el curso y no es de ningún nivel con encuesta del alumnado'''],
    ['''Doble factor obligatorio para administradores''', '''Doble factor obligatorio para las cuentas de administración'''],
    ['''Una respuesta de alumnos necesita grupo''', '''Una respuesta del alumnado necesita grupo'''],
    ['''Tiene que quedar al menos un administrador activo''', '''Tiene que quedar al menos una cuenta de administración activa'''],
    ['''Solo para administradores''', '''Solo para administración'''],
    ['''No se puede eliminar al último administrador activo''', '''No se puede eliminar la última cuenta de administración activa'''],
    ['''No puedes quitarte el rol de administrador ni desactivarte a ti mismo''', '''No puedes quitarte el rol de administración ni desactivar tu propio acceso'''],
    ['''Las preguntas por asignatura solo existen en alumnos''', '''Las preguntas por asignatura solo existen en las encuestas del alumnado'''],
    ['''La atribución a un docente solo existe en alumnos''', '''La atribución a un docente solo existe en las encuestas del alumnado'''],
    ['''El nivel % no es de ninguna etapa con encuestas de alumnos''', '''El nivel % no es de ninguna etapa con encuestas del alumnado'''],
    ['''El departamento «%» tiene profesores en el curso: cámbialos de departamento con la asignación docente antes de retirarlo''', '''El departamento «%» tiene docentes en el curso: cámbialos de departamento con la asignación docente antes de retirarlo'''],
    ['''El departamento «%» tiene jefe en el curso: quítalo antes en Responsables del curso''', '''El departamento «%» tiene jefatura en el curso: quítala antes en Responsables del curso'''],
    ['''El correo escrito no coincide con el del usuario: no se ha eliminado''', '''El correo escrito no coincide con el de la cuenta: no se ha eliminado'''],
    ['''(usuario eliminado)''', '''(acceso eliminado)''']
  ];
  f record;
  def text;
  nuevo text;
  i int;
  quedan text;
begin
  for f in
    select p.oid, n.nspname, p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'privado', 'permisos') and p.prokind = 'f'
  loop
    def := pg_get_functiondef(f.oid);
    nuevo := def;
    for i in 1 .. array_length(cambios, 1) loop
      nuevo := replace(nuevo, cambios[i][1], cambios[i][2]);
    end loop;
    if nuevo <> def then
      execute nuevo;
      raise notice 'Mensajes revisados en %.%', f.nspname, f.proname;
    end if;
  end loop;

  -- Comprobación: ningún mensaje antiguo queda en ninguna función.
  select string_agg(distinct n.nspname || '.' || p.proname, ', ') into quedan
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  cross join generate_subscripts(cambios, 1) as g(i)
  where n.nspname in ('public', 'privado', 'permisos') and p.prosrc like '%' || cambios[g.i][1] || '%';
  if quedan is not null then
    raise exception 'Quedan mensajes sin revisar en: %', quedan;
  end if;
end
$$;
