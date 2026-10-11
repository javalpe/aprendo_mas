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
