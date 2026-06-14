FROM python:3.10-slim

LABEL maintainer="miezamsam@gmail.com"
LABEL description="Pipeline ETL Mobile Money Côte d Ivoire"

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN mkdir -p /data/raw /data/clean /data/output

CMD ["python", "notebooks/pipeline_etl.py"]