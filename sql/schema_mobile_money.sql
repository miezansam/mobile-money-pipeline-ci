-- ============================================================
-- FICHIER : schema_mobile_money.sql
-- PROJET  : Pipeline ETL Mobile Money — Côte d'Ivoire
-- AUTEUR  : Miézan Sam & Ariel Gnapié
-- DATE    : 12 06 2026 
-- DESC    : Création complète du schéma en étoile et des
--           tables d'agrégation pour l'analyse Mobile Money
-- ============================================================


-- ============================================================
-- PARTIE 1 : TABLE BRUTE DES TRANSACTIONS
-- Contient toutes les transactions telles que chargées
-- depuis le CSV — avant modélisation en étoile
-- ============================================================

CREATE TABLE IF NOT EXISTS transactions_raw (
    id_transaction    TEXT PRIMARY KEY,        -- identifiant unique de la transaction
    date_heure        TIMESTAMP,               -- date et heure exacte de la transaction
    operateur         TEXT,                    -- MTN CI, Orange Money, Moov Africa, Wave
    type_operation    TEXT,                    -- Dépôt, Retrait, Transfert, Paiement, Recharge
    expediteur        TEXT,                    -- numéro ou identifiant de l'expéditeur
    beneficiaire      TEXT,                    -- numéro ou identifiant du bénéficiaire
    montant_fcfa      BIGINT,                  -- montant de la transaction en FCFA
    frais_fcfa        INTEGER DEFAULT 0,       -- frais prélevés par l'opérateur
    zone_expediteur   TEXT,                    -- zone géographique de l'expéditeur
    zone_beneficiaire TEXT,                    -- zone géographique du bénéficiaire
    id_agent          TEXT,                    -- agent Mobile Money ayant traité l'opération
    statut            TEXT,                    -- Succès, Échec, En attente
    -- Colonnes enrichies (calculées lors du nettoyage ETL)
    montant_net_fcfa  BIGINT,                  -- montant_fcfa - frais_fcfa
    heure             INTEGER,                 -- heure extraite de date_heure (0 à 23)
    mois              INTEGER,                 -- mois extrait de date_heure (1 à 12)
    annee             INTEGER,                 -- année extraite de date_heure
    jour_semaine      TEXT,                    -- nom du jour (Monday, Tuesday...)
    est_succes        INTEGER DEFAULT 0,       -- 1 si statut = Succès, 0 sinon
    inter_ville       INTEGER DEFAULT 0,       -- 1 si zones expéditeur ≠ bénéficiaire
    tranche_montant   TEXT                     -- < 5k / 5k-20k / 20k-100k / > 100k
);


-- ============================================================
-- PARTIE 2 : TABLES DE DIMENSIONS
-- Les dimensions décrivent QUI, QUOI, OÙ, QUAND
-- Elles entourent la table de faits dans le schéma en étoile
-- ============================================================

-- ------------------------------------------------------------
-- DIMENSION 1 : Opérateur
-- Décrit les 4 opérateurs Mobile Money actifs en Côte d'Ivoire
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dim_operateur (
    id_operateur   SERIAL PRIMARY KEY,         -- identifiant auto-incrémenté (1, 2, 3, 4)
    nom_operateur  TEXT NOT NULL UNIQUE,       -- MTN CI, Orange Money, Moov Africa, Wave
    type_operateur TEXT,                       -- Telecoms ou Fintech
    actif          BOOLEAN DEFAULT TRUE        -- TRUE si l'opérateur est encore en activité
);

-- ------------------------------------------------------------
-- DIMENSION 2 : Zone géographique
-- Décrit les zones d'Abidjan et les villes de l'intérieur CI
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dim_zone (
    id_zone    SERIAL PRIMARY KEY,             -- identifiant auto-incrémenté
    nom_zone   TEXT NOT NULL UNIQUE,           -- ex : Abidjan-Cocody, Bouaké, Korhogo
    region     TEXT,                           -- ex : Abidjan, Centre, Nord, Ouest
    type_zone  TEXT,                           -- Quartier Abidjan ou Ville intérieur
    population INTEGER                         -- population estimée de la zone
);

-- ------------------------------------------------------------
-- DIMENSION 3 : Type d'opération
-- Décrit les 5 types d'opérations Mobile Money disponibles
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dim_type_operation (
    id_type        SERIAL PRIMARY KEY,         -- identifiant auto-incrémenté
    nom_type       TEXT NOT NULL UNIQUE,       -- Transfert, Dépôt, Retrait, Paiement, Recharge
    categorie      TEXT,                       -- Envoi de fonds, Entrée fonds, Sortie fonds...
    taux_frais_max NUMERIC(4,2)               -- taux de frais maximum appliqué (en %)
);

-- ------------------------------------------------------------
-- DIMENSION 4 : Calendrier
-- Permet d'analyser les tendances temporelles (mois, trimestre)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dim_date (
    id_date       SERIAL PRIMARY KEY,          -- identifiant auto-incrémenté
    date_complete DATE NOT NULL UNIQUE,        -- ex : 2024-01-15
    annee         INTEGER,                     -- ex : 2024
    mois          INTEGER,                     -- 1 à 12
    nom_mois      TEXT,                        -- Janvier, Février...
    trimestre     INTEGER,                     -- 1 à 4
    semaine       INTEGER,                     -- 1 à 52
    jour          INTEGER,                     -- 1 à 31
    nom_jour      TEXT,                        -- Lundi, Mardi...
    est_weekend   BOOLEAN                      -- TRUE si samedi ou dimanche
);


-- ============================================================
-- PARTIE 3 : TABLE DE FAITS
-- Centre du schéma en étoile — contient les mesures
-- et les clés étrangères vers toutes les dimensions
-- ============================================================

CREATE TABLE IF NOT EXISTS faits_transactions (
    id_transaction    TEXT PRIMARY KEY,        -- identifiant unique de la transaction

    -- Clés étrangères vers les dimensions (le cœur du schéma en étoile)
    id_operateur      INTEGER REFERENCES dim_operateur(id_operateur),
    id_zone_exp       INTEGER REFERENCES dim_zone(id_zone),       -- zone expéditeur
    id_zone_ben       INTEGER REFERENCES dim_zone(id_zone),       -- zone bénéficiaire
    id_type           INTEGER REFERENCES dim_type_operation(id_type),
    id_date           INTEGER REFERENCES dim_date(id_date),

    -- Mesures (les chiffres à analyser)
    montant_fcfa      BIGINT NOT NULL,         -- montant brut de la transaction
    frais_fcfa        INTEGER DEFAULT 0,       -- frais prélevés par l'opérateur
    montant_net_fcfa  BIGINT,                  -- montant net reçu par le bénéficiaire
    taux_frais_pct    NUMERIC(5,2),            -- pourcentage de frais sur le montant
    heure             INTEGER,                 -- heure de la transaction (0 à 23)
    statut            TEXT,                    -- Succès, Échec, En attente
    inter_ville       INTEGER DEFAULT 0,       -- 1 = transaction entre deux villes différentes
    id_agent          TEXT                     -- agent ayant traité la transaction
);


-- ============================================================
-- PARTIE 4 : TABLES D'AGRÉGATION
-- Résumés précalculés pour accélérer les analyses
-- et alimenter directement le tableau de bord
-- ============================================================

-- ------------------------------------------------------------
-- AGRÉGATION 1 : Performance par opérateur
-- Résume le volume, les frais et le taux de succès par opérateur
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS agg_operateur (
    operateur         TEXT PRIMARY KEY,        -- nom de l'opérateur
    nb_transactions   INTEGER,                 -- nombre total de transactions
    volume_total      BIGINT,                  -- volume total en FCFA
    frais_total       BIGINT,                  -- frais totaux collectés en FCFA
    montant_moyen     NUMERIC(12,2),           -- montant moyen par transaction
    taux_succes_pct   NUMERIC(5,2)            -- pourcentage de transactions réussies
);

-- ------------------------------------------------------------
-- AGRÉGATION 2 : Performance par type d'opération
-- Résume les transactions par type (Dépôt, Retrait, etc.)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS agg_type_operation (
    type_operation    TEXT PRIMARY KEY,        -- nom du type d'opération
    nb_transactions   INTEGER,                 -- nombre de transactions de ce type
    volume_total      BIGINT,                  -- volume total en FCFA
    frais_total       BIGINT,                  -- frais totaux collectés
    montant_moyen     NUMERIC(12,2)            -- montant moyen par transaction
);

-- ------------------------------------------------------------
-- AGRÉGATION 3 : Performance par zone géographique
-- Résume les transactions par zone expéditeur
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS agg_zone (
    zone              TEXT PRIMARY KEY,        -- nom de la zone géographique
    nb_transactions   INTEGER,                 -- nombre de transactions émises
    volume_total      BIGINT,                  -- volume total émis en FCFA
    frais_total       BIGINT,                  -- frais totaux collectés
    montant_moyen     NUMERIC(12,2)            -- montant moyen par transaction
);


-- ============================================================
-- VÉRIFICATION FINALE
-- Lister toutes les tables créées dans le schéma public
-- ============================================================
SELECT
    table_name,
    pg_size_pretty(pg_total_relation_size(quote_ident(table_name))) AS taille
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;