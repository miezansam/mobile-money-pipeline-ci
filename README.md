# Pipeline ETL Mobile Money — Côte d'Ivoire 🇨🇮

![Python](https://img.shields.io/badge/Python-3.10-blue)
![Pandas](https://img.shields.io/badge/Pandas-2.0-green)
![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL-darkgreen)
![Airflow](https://img.shields.io/badge/Apache_Airflow-2.9-red)
![Docker](https://img.shields.io/badge/Docker-✓-blue)

## Contexte
Pipeline de données complet pour l'analyse des transactions Mobile Money
en Côte d'Ivoire. 100 000 transactions sur 6 mois (Jan–Juin 2024)
couvrant les 4 opérateurs : MTN CI, Orange Money, Moov Africa et Wave.

## Architecture
CSV brut → Pandas (ETL) → Supabase PostgreSQL → Schéma en étoile → Dashboard
↓
Apache Airflow (orchestration)
↓
Docker (conteneurisation)

## Résultats clés
- 📊 99 800 transactions analysées sur 6 mois
- 💰 Volume total : 14,8 milliards FCFA
- 🏆 Opérateur dominant : Wave (25.2%)
- ⚠️ Taux de succès moyen : 80%
- 🌍 Zone dominante : Korhogo

## Technologies
| Outil | Usage |
|---|---|
| Python / Pandas | Nettoyage et transformation ETL |
| Supabase (PostgreSQL) | Stockage cloud |
| Apache Airflow | Orchestration quotidienne (23h) |
| Docker | Conteneurisation |
| Matplotlib | Tableau de bord analytique |
| GitHub Actions | CI/CD |

## Structure du projet
mobile-money-pipeline-ci/
├── notebooks/
│   └── pipeline_etl.ipynb    ← Pipeline complet
├── dags/
│   └── dag_mobile_money.py   ← DAG Airflow
├── data/
│   └── output/
│       └── dashboard_mobile_money.png
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
└── .env.example

## Installation
```bash
# Cloner le repo
git clone https://github.com/[VOTRE-NOM-UTILISATEUR]/mobile-money-pipeline-ci.git
cd mobile-money-pipeline-ci

# Configurer les variables d'environnement
cp .env.example .env
# Éditer .env avec vos credentials Supabase

# Lancer avec Docker
docker-compose up -d
```

## Auteurs
Miézan Sam & Ariel Gnapié
