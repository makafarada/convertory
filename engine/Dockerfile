# Build from the repo root:  docker build -f engine/Dockerfile -t convertory-engine .
FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      libreoffice-writer libreoffice-calc libreoffice-impress \
      tesseract-ocr tesseract-ocr-eng fonts-liberation fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY engine/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY conversion-engine.py engine/server.py ./
RUN useradd -m engine && chown -R engine /app
USER engine
ENV PORT=8080
EXPOSE 8080
CMD ["python", "server.py"]
