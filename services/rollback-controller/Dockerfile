# syntax=docker/dockerfile:1

FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim
RUN groupadd -r -g 10001 appuser && useradd -r -u 10001 -g appuser appuser
WORKDIR /app
COPY --from=builder /install /usr/local
COPY app ./app
USER 10001
EXPOSE 8080
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
