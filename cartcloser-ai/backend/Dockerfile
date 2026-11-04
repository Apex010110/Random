FROM python:3.13-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 SEED_DIR=/app/seed
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/ .
COPY seed/ /app/seed/
EXPOSE 8000
# Apply migrations, seed the fictional demo tenant if empty, then serve.
CMD ["sh", "-c", "python -m app.cli migrate && python -m app.cli seed && uvicorn app.main:app --host 0.0.0.0 --port 8000"]
