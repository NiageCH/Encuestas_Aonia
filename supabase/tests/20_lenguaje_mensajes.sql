-- Revisión de lenguaje (docs/GLOSARIO.md): ninguna función del servidor conserva un mensaje con los términos descartados
-- (migración 20261027000028 y, en fase2, 20261028000036).
begin;
select plan(4);

-- Mensajes como «Sin acceso a este profesor»: entre comillas, empiezan por una palabra con mayúscula y llevan un término
-- descartado. No cuenta «profesor/a» ni los códigos en minúscula ('alumnos', 'administrador'), que no son mensajes.
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('public', 'privado', 'permisos')
             and p.prosrc ~ '''(\(|[[:upper:]])[^'']* [^'']*\m(alumnos|Alumnos|profesores|profesor(?!/a)|administrador|administradores|usuario|Usuario|jefe|colegio)\M[^'']*'''),
          0, 'ningún mensaje del servidor usa un término descartado');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('public', 'privado', 'permisos') and p.prosrc like '%''Sin acceso a este profesor''%'),
          0, 'ya no queda «Sin acceso a este profesor» sin la barra');
select ok(exists (select 1 from pg_proc p where p.prosrc like '%''Sin acceso a este profesor/a''%'), 'el acceso a un informe dice «profesor/a»');
select ok(exists (select 1 from pg_proc p where p.prosrc like '%''Doble factor obligatorio para las cuentas de administración''%'),
          'el doble factor habla de cuentas de administración');

select * from finish();
rollback;
