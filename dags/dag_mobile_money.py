from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta
import pandas as pd
import numpy as np

# ── Arguments par défaut ──────────────────────────────
default_args = {
    "owner":            "mobile_money_ci",
    "depends_on_past":  False,
    "start_date":       datetime(2024, 1, 1),
    "email":            ["miezamsam@gmail.com"],
    "email_on_failure": True,
    "email_on_retry":   False,
    "retries":          2,
    "retry_delay":      timedelta(minutes=5),
}

# ── Tâche 1 : Extraction ──────────────────────────────
def extraire():
    df = pd.read_csv("/data/transactions_mobile_money_100k.csv",
                     encoding="utf-8", low_memory=False)
    df.to_parquet("/data/raw/transactions_raw.parquet", index=False)
    print(f"EXTRACT : {len(df):,} lignes extraites")

# ── Tâche 2 : Nettoyage ───────────────────────────────
def nettoyer():
    df = pd.read_parquet("/data/raw/transactions_raw.parquet")
    df = df.replace("", np.nan)
    df["frais_fcfa"]        = df["frais_fcfa"].fillna(0).astype(int)
    df["zone_beneficiaire"] = df["zone_beneficiaire"].fillna("Zone inconnue")
    df["id_agent"]          = df["id_agent"].fillna("AGT-INCONNU")
    df = df[df["montant_fcfa"] > 0].copy()
    df["date_heure"]        = pd.to_datetime(df["date_heure"])
    df["montant_net_fcfa"]  = df["montant_fcfa"] - df["frais_fcfa"]
    df["heure"]             = df["date_heure"].dt.hour
    df["mois"]              = df["date_heure"].dt.month
    df["est_succes"]        = (df["statut"] == "Succès").astype(int)
    df["inter_ville"]       = (df["zone_expediteur"] != df["zone_beneficiaire"]).astype(int)
    df.to_parquet("/data/clean/transactions_clean.parquet", index=False)
    print(f"CLEAN : {len(df):,} lignes propres")

# ── Tâche 3 : Chargement Supabase ─────────────────────
def charger():
    import sqlalchemy, os
    SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
    if not SUPABASE_URL:
        raise ValueError("SUPABASE_URL non définie !")
    engine = sqlalchemy.create_engine(SUPABASE_URL)
    df = pd.read_parquet("/data/clean/transactions_clean.parquet")
    with engine.connect() as conn:
        df.to_sql("transactions_raw", conn,
                  if_exists="replace", index=False, chunksize=5000)
        conn.commit()
    engine.dispose()
    print(f"LOAD : {len(df):,} lignes chargées")

# ── Tâche 4 : Rapport JSON ────────────────────────────
def rapport():
    import json
    from datetime import datetime as dt
    df = pd.read_parquet("/data/clean/transactions_clean.parquet")
    df_s = df[df["statut"] == "Succès"]
    kpi = {
        "date_generation":    dt.now().strftime("%Y-%m-%d %H:%M"),
        "nb_total":           int(len(df)),
        "nb_succes":          int(len(df_s)),
        "taux_succes_pct":    round(len(df_s)/len(df)*100, 1),
        "volume_total_fcfa":  int(df_s["montant_fcfa"].sum()),
        "montant_moyen_fcfa": int(df_s["montant_fcfa"].mean()),
    }
    with open("/data/output/rapport_nuit.json", "w") as f:
        json.dump(kpi, f, ensure_ascii=False, indent=2)
    print("RAPPORT : rapport_nuit.json généré")

# ── Définition du DAG ─────────────────────────────────
with DAG(
    dag_id="pipeline_mobile_money_ci",
    default_args=default_args,
    description="Pipeline ETL Mobile Money CI — quotidien 23h",
    schedule="0 23 * * *",   # chaque jour à 23h
    catchup=False,
    max_active_runs=1,
    tags=["etl", "mobile_money", "cote_ivoire"],
) as dag:

    t1 = PythonOperator(task_id="extraire",  python_callable=extraire)
    t2 = PythonOperator(task_id="nettoyer",  python_callable=nettoyer)
    t3 = PythonOperator(task_id="charger",   python_callable=charger)
    t4 = PythonOperator(task_id="rapport",   python_callable=rapport)

    # Ordre d'exécution : t1 → t2 → t3 → t4
    t1 >> t2 >> t3 >> t4