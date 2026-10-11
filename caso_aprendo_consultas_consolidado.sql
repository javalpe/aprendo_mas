-- =====================================================================
-- CASO PRÁCTICO APRENDO+  |  PARTE 1: SQL
-- Motor: SQLite 3 (≥3.25, usa funciones de ventana). Compatible con DuckDB.
-- Carga de datos (SQLite):  sqlite3 aprendo.sqlite
--   .mode csv
--   .import --csv instituciones.csv instituciones   (idem grupos, participantes,
--                                                    actividades, interacciones)
-- Supuestos de la métrica:
--   * Persona = telefono_hash (una misma persona puede tener 2 participante_id).
--   * Semana = lunes a domingo; "registradas hasta el fin de la semana" = fecha_alta <= domingo.
--   * La semana de una interacción es la de su actividad (actividades.semana), no la de su fecha UTC.
--   * Evidencia = foto, audio o video (tipo normalizado), solo de rol 'familia'.
-- =====================================================================

-- =====================================================================
-- CASO APRENDO+ | Motor: SQLite 3 (también compatible con DuckDB)
-- Vistas de limpieza: se usan en todas las consultas de la Parte 1
-- =====================================================================

-- Calendario de semanas: fin de semana = domingo (semana lunes-domingo)
DROP VIEW IF EXISTS semanas;
CREATE VIEW semanas AS
SELECT 1 AS semana, '2026-08-23' AS fin_semana UNION ALL
SELECT 2, '2026-08-30' UNION ALL SELECT 3, '2026-09-06' UNION ALL
SELECT 4, '2026-09-13' UNION ALL SELECT 5, '2026-09-20' UNION ALL
SELECT 6, '2026-09-27';

-- Familias = personas únicas. Una persona = un telefono_hash (la misma persona
-- puede tener 2 participante_id). Se conserva su alta más temprana.
DROP VIEW IF EXISTS familias;
CREATE VIEW familias AS
SELECT p.telefono_hash,
       MIN(p.grupo_id)   AS grupo_id,
       MIN(p.fecha_alta) AS fecha_alta
FROM participantes p
WHERE p.rol = 'familia'
GROUP BY p.telefono_hash;

-- Interacciones limpias: tipo normalizado, solo participantes existentes,
-- identificadas por persona (telefono_hash) y sin filas exactamente duplicadas.
DROP VIEW IF EXISTS int_limpia;
CREATE VIEW int_limpia AS
SELECT telefono_hash, actividad_id, semana, fecha_hora_utc, tipo_norm
FROM (
  SELECT p.telefono_hash, i.actividad_id, a.semana, i.fecha_hora_utc,
         CASE LOWER(TRIM(i.tipo)) WHEN 'imagen' THEN 'foto' ELSE LOWER(TRIM(i.tipo)) END AS tipo_norm,
         ROW_NUMBER() OVER (PARTITION BY p.telefono_hash, i.actividad_id, i.fecha_hora_utc,
                            CASE LOWER(TRIM(i.tipo)) WHEN 'imagen' THEN 'foto' ELSE LOWER(TRIM(i.tipo)) END
                            ORDER BY i.interaccion_id) AS rn
  FROM interacciones i
  JOIN participantes p ON p.participante_id = i.participante_id   -- descarta huérfanos
  JOIN actividades  a ON a.actividad_id     = i.actividad_id
  WHERE p.rol = 'familia'                                          -- docentes no cuentan
) WHERE rn = 1;

-- Familia-semana con evidencia (foto, audio o video). Cada persona una vez por semana.
DROP VIEW IF EXISTS evidencia_sem;
CREATE VIEW evidencia_sem AS
SELECT DISTINCT telefono_hash, semana
FROM int_limpia
WHERE tipo_norm IN ('foto','audio','video');

-- ---------------------------------------------------------------------
-- 1.1 Tasa de participación semanal por UGEL y total
-- Numerador: familias distintas con evidencia en la semana
-- Denominador: familias distintas registradas hasta el fin de esa semana
WITH base AS (                       -- familia x semana en que ya estaba registrada
  SELECT f.telefono_hash, g.institucion_id, s.semana
  FROM familias f
  JOIN grupos g  ON g.grupo_id = f.grupo_id
  JOIN semanas s ON f.fecha_alta <= s.fin_semana
),
por_ugel AS (
  SELECT i.ugel, b.semana,
         COUNT(*) AS registradas,
         SUM(CASE WHEN e.telefono_hash IS NOT NULL THEN 1 ELSE 0 END) AS con_evidencia
  FROM base b
  JOIN instituciones i ON i.institucion_id = b.institucion_id
  LEFT JOIN evidencia_sem e ON e.telefono_hash = b.telefono_hash AND e.semana = b.semana
  GROUP BY i.ugel, b.semana
),
total AS (
  SELECT 'TOTAL' AS ugel, semana, SUM(registradas) AS registradas, SUM(con_evidencia) AS con_evidencia
  FROM por_ugel GROUP BY semana
),
todo AS (SELECT * FROM por_ugel UNION ALL SELECT * FROM total)
SELECT ugel, semana, registradas, con_evidencia,
       ROUND(100.0 * con_evidencia / registradas, 1) AS tasa_pct
FROM todo
ORDER BY CASE ugel WHEN 'TOTAL' THEN 1 ELSE 0 END, ugel, semana;

-- ---------------------------------------------------------------------
-- 1.2 Top 5 grupos con mayor caída: promedio sem 1-4 vs promedio sem 5-6
-- Tasa de grupo-semana con la misma definición de la métrica (personas únicas)
WITH base AS (
  SELECT f.telefono_hash, f.grupo_id, s.semana
  FROM familias f JOIN semanas s ON f.fecha_alta <= s.fin_semana
),
tasa_gs AS (                          -- tasa por grupo y semana
  SELECT b.grupo_id, b.semana,
         COUNT(*) AS registradas,
         SUM(CASE WHEN e.telefono_hash IS NOT NULL THEN 1 ELSE 0 END) AS con_evid,
         100.0 * SUM(CASE WHEN e.telefono_hash IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS tasa
  FROM base b
  LEFT JOIN evidencia_sem e ON e.telefono_hash = b.telefono_hash AND e.semana = b.semana
  GROUP BY b.grupo_id, b.semana
),
prom AS (                             -- promedio simple de las tasas semanales
  SELECT grupo_id,
         AVG(CASE WHEN semana BETWEEN 1 AND 4 THEN tasa END) AS prom_s1_4,
         AVG(CASE WHEN semana IN (5,6)         THEN tasa END) AS prom_s5_6
  FROM tasa_gs GROUP BY grupo_id
)
SELECT p.grupo_id, i.ugel, i.zona, g.edad,
       (SELECT registradas FROM tasa_gs t WHERE t.grupo_id=p.grupo_id AND t.semana=6) AS familias,
       ROUND(prom_s1_4,1) AS prom_s1_4_pct,
       ROUND(prom_s5_6,1) AS prom_s5_6_pct,
       ROUND(prom_s1_4 - prom_s5_6,1) AS caida_pp
FROM prom p
JOIN grupos g ON g.grupo_id = p.grupo_id
JOIN instituciones i ON i.institucion_id = g.institucion_id
ORDER BY caida_pp DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- 1.3 Familias con evidencia en >=2 semanas distintas de 1-4 y SIN evidencia en 5 ni 6
WITH hist AS (
  SELECT telefono_hash,
         COUNT(DISTINCT CASE WHEN semana BETWEEN 1 AND 4 THEN semana END) AS sem_1_4,
         MAX(semana IN (5,6)) AS activa_5_6
  FROM evidencia_sem GROUP BY telefono_hash
),
fugadas AS (
  SELECT telefono_hash FROM hist WHERE sem_1_4 >= 2 AND activa_5_6 = 0
)
SELECT 'TOTAL' AS grupo_id, '' AS ugel, COUNT(*) AS familias_fugadas,
       (SELECT COUNT(*) FROM hist WHERE sem_1_4>=2) AS base_activas_1_4,
       ROUND(100.0*COUNT(*)/(SELECT COUNT(*) FROM hist WHERE sem_1_4>=2),1) AS pct_de_base
FROM fugadas;

-- 1.3 (detalle) Concentración por grupo
WITH hist AS (
  SELECT telefono_hash,
         COUNT(DISTINCT CASE WHEN semana BETWEEN 1 AND 4 THEN semana END) AS sem_1_4,
         MAX(semana IN (5,6)) AS activa_5_6
  FROM evidencia_sem GROUP BY telefono_hash
),
base AS (SELECT * FROM hist WHERE sem_1_4 >= 2)
SELECT f.grupo_id, i.ugel, i.zona,
       COUNT(*) AS base_activas_1_4,
       SUM(b.activa_5_6 = 0) AS fugadas,
       ROUND(100.0*SUM(b.activa_5_6 = 0)/COUNT(*),1) AS pct_fuga_grupo
FROM base b
JOIN familias f ON f.telefono_hash = b.telefono_hash
JOIN grupos g ON g.grupo_id = f.grupo_id
JOIN instituciones i ON i.institucion_id = g.institucion_id
GROUP BY f.grupo_id, i.ugel, i.zona
HAVING fugadas > 0
ORDER BY fugadas DESC, pct_fuga_grupo DESC
LIMIT 10;

-- ---------------------------------------------------------------------
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
