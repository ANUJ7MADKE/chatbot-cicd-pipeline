# Multi-stage build for minimal image attack surface
FROM python:3.10.0-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.10.0-slim

# AWS Lambda Web Adapter: lets this same image run unchanged on AWS Lambda.
# Outside Lambda the extension is inactive and uvicorn runs as usual.
COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.9.1 /lambda-adapter /opt/extensions/lambda-adapter
ENV AWS_LWA_PORT=8000

WORKDIR /app
COPY --from=builder /install /usr/local
COPY ./app ./app

# Run as non-root user for security best practices
RUN useradd -m botuser && chown -R botuser /app
USER botuser

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
