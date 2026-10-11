-- Caso práctico Aprendo+ | Motor: SQLite 3 (compatible con DuckDB)
-- Requiere las vistas de sql/00_vistas.sql

-- 1.4 CONTROL DE CALIDAD: una fila por chequeo (problema, filas afectadas, % sobre el universo)
WITH q AS (
  SELECT 1 AS n, 'Tipo de interacción con variantes (Foto, FOTO, imagen, Audio, Video, Reaccion)' AS chequeo,
         (SELECT COUNT(*) FROM interacciones WHERE tipo NOT IN ('foto','audio','video','texto','reaccion','reenvio')) AS afectadas,
         (SELECT COUNT(*) FROM interacciones) AS universo
  UNION ALL SELECT 2, 'Interacciones de participante_id que no existe en participantes (huérfanas)',
         (SELECT COUNT(*) FROM interacciones WHERE participante_id NOT IN (SELECT participante_id FROM participantes)),
         (SELECT COUNT(*) FROM interacciones)
  UNION ALL SELECT 3, 'Teléfonos (personas) registrados con 2 participante_id',
         (SELECT COUNT(*) FROM (SELECT telefono_hash FROM participantes WHERE rol='familia' GROUP BY 1 HAVING COUNT(*)>1)),
         (SELECT COUNT(DISTINCT telefono_hash) FROM participantes WHERE rol='familia')
  UNION ALL SELECT 4, 'Filas exactamente duplicadas (mismo participante, actividad, hora y tipo; filas sobrantes)',
         (SELECT COUNT(*) - COUNT(DISTINCT participante_id||actividad_id||fecha_hora_utc||LOWER(tipo)) FROM interacciones),
         (SELECT COUNT(*) FROM interacciones)
  UNION ALL SELECT 5, 'Interacciones con hora anterior al envío de su actividad (imposible)',
         (SELECT COUNT(*) FROM interacciones i JOIN actividades a USING(actividad_id) WHERE i.fecha_hora_utc < a.fecha_envio_utc),
         (SELECT COUNT(*) FROM interacciones)
  UNION ALL SELECT 6, '...de ellas, con evidencia (foto/audio/video) de familias',
         (SELECT COUNT(*) FROM interacciones i JOIN actividades a USING(actividad_id) JOIN participantes p USING(participante_id)
           WHERE i.fecha_hora_utc < a.fecha_envio_utc AND p.rol='familia' AND LOWER(i.tipo) IN ('foto','audio','video','imagen')),
         (SELECT COUNT(*) FROM interacciones i JOIN participantes p USING(participante_id) WHERE p.rol='familia' AND LOWER(i.tipo) IN ('foto','audio','video','imagen'))
  UNION ALL SELECT 7, 'Actividades x UGEL sin ningún registro (hueco de datos)',
         (SELECT COUNT(*) FROM (SELECT a.actividad_id, u.ugel FROM actividades a CROSS JOIN (SELECT DISTINCT ugel FROM instituciones) u
            WHERE NOT EXISTS (SELECT 1 FROM interacciones i JOIN participantes p USING(participante_id)
              JOIN grupos g ON g.grupo_id=p.grupo_id JOIN instituciones x ON x.institucion_id=g.institucion_id
              WHERE i.actividad_id=a.actividad_id AND x.ugel=u.ugel))),
         (SELECT COUNT(*) FROM actividades)*3
  UNION ALL SELECT 8, 'Interacciones de docentes (no son evidencia familiar; deben excluirse)',
         (SELECT COUNT(*) FROM interacciones i JOIN participantes p USING(participante_id) WHERE p.rol='docente'),
         (SELECT COUNT(*) FROM interacciones)
  UNION ALL SELECT 9, 'Interacciones anteriores a la fecha_alta del participante',
         (SELECT COUNT(*) FROM interacciones i JOIN participantes p USING(participante_id) WHERE SUBSTR(i.fecha_hora_utc,1,10) < p.fecha_alta),
         (SELECT COUNT(*) FROM interacciones)
  UNION ALL SELECT 10, 'Integridad: grupos sin institución / participantes sin grupo / interacciones sin actividad',
         (SELECT COUNT(*) FROM grupos WHERE institucion_id NOT IN (SELECT institucion_id FROM instituciones))
        +(SELECT COUNT(*) FROM participantes WHERE grupo_id NOT IN (SELECT grupo_id FROM grupos))
        +(SELECT COUNT(*) FROM interacciones WHERE actividad_id NOT IN (SELECT actividad_id FROM actividades)),
         (SELECT COUNT(*) FROM participantes)
  UNION ALL SELECT 11, 'Duplicados de teléfono repartidos en grupos distintos',
         (SELECT COUNT(*) FROM (SELECT telefono_hash FROM participantes GROUP BY 1 HAVING COUNT(DISTINCT grupo_id)>1)),
         (SELECT COUNT(DISTINCT telefono_hash) FROM participantes)
)
SELECT n, chequeo, afectadas, universo, ROUND(100.0*afectadas/universo,1) AS pct FROM q ORDER BY n;

-- 1.4 (detalle a) Qué actividades/UGEL no tienen registros
SELECT a.actividad_id, a.fecha_envio_utc, u.ugel, 0 AS interacciones
FROM actividades a CROSS JOIN (SELECT DISTINCT ugel FROM instituciones) u
WHERE NOT EXISTS (SELECT 1 FROM interacciones i JOIN participantes p USING(participante_id)
   JOIN grupos g ON g.grupo_id=p.grupo_id JOIN instituciones x ON x.institucion_id=g.institucion_id
   WHERE i.actividad_id=a.actividad_id AND x.ugel=u.ugel);

-- 1.4 (detalle b) Variantes de 'tipo' halladas
SELECT tipo, COUNT(*) AS filas FROM interacciones
WHERE tipo NOT IN ('foto','audio','video','texto','reaccion','reenvio') GROUP BY tipo ORDER BY filas DESC;
